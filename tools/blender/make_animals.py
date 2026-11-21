"""Builds Logiheim's animals: sculpted, fur-textured, rigged and animated.

Run headless (Blender 4.x):
    blender -b --python tools/blender/make_animals.py -- assets/models/animals
Set ANIMALS=horse,sheep to rebuild only some of them.

For every species:
  1. Anatomy from real measurements (withers/croup height, body length, chest depth...)
     gives joint positions: spine, neck, head, ears, tail, and jointed legs
     (shoulder-elbow-knee-fetlock-hoof in front, hip-stifle-hock-fetlock-hoof behind).
  2. Flesh: metaballs along every bone plus ellipsoid muscle masses (ribcage, belly,
     shoulders, haunches, cranium, jaw), converted to a smoothed mesh.
  3. Coat: painted by body region, then baked with fine fur noise into an albedo texture
     and a fur normal map (Cycles bake, smart UVs).
  4. Rig: an armature on the same joints, skinned with automatic weights.
  5. Looping animations as NLA tracks: "idle", "graze", "walk" (whale: "swim"; seals:
     "idle", "graze" = resting, "walk" = galumphing).
Exported as .glb (skin + animations + embedded textures) plus animals.json with each
species' walking speed and behaviour.
"""
import json
import math
import os
import sys

import addon_utils
import bmesh
import bpy
from mathutils import Quaternion, Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models/animals"
TEX = 1024
FPS = 24
META = {}
Y = Vector((0, 1, 0))   # side axis: rotating about it pitches forward/back
Z = Vector((0, 0, 1))   # up axis: rotating about it yaws left/right
ELLIPSOID_K = 1.0 / 0.573   # metaball ellipsoid surface sits at 0.573 x radius x size
BALL_K = 0.85 / 0.575


# --------------------------------------------------------------------------- body description

class Body:
    """Rig bones, flesh pieces and paint labels for one animal."""

    def __init__(self):
        self.bones = []      # (name, head, tail, parent, deform)
        self.segments = []   # (a, b, ra, rb, label) flesh along a line
        self.masses = []     # (centre, half_extents (x,y,z), rotation quaternion, label)

    def bone(self, name, head, tail, parent=None, deform=True):
        self.bones.append((name, Vector(head), Vector(tail), parent, deform))

    def limb(self, a, b, ra, rb, label):
        self.segments.append((Vector(a), Vector(b), ra, rb, label))

    def mass(self, c, half, label, rot=None):
        self.masses.append((Vector(c), Vector(half), rot or Quaternion(), label))

    def label_at(self, p):
        best = ("body", 0.0, 1e9)
        for a, b, ra, rb, label in self.segments:
            ab = b - a
            s = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            r = ra + (rb - ra) * s
            d = (p - (a + ab * s)).length / max(r, 1e-4)
            if d < best[2]:
                best = (label, s, d)
        for c, half, rot, label in self.masses:
            q = rot.inverted() @ (p - c)
            d = Vector((q.x / half.x, q.y / half.y, q.z / half.z)).length
            if d < best[2]:
                best = (label, 0.5, d)
        return best


def build_flesh(name, body, resolution, faces):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    for a, b, ra, rb, _ in body.segments:
        n = max(2, math.ceil((b - a).length / max(min(ra, rb) * 0.6, 1e-3)))
        for i in range(n + 1):
            t = i / n
            e = mb.elements.new()
            e.co = a.lerp(b, t)
            e.radius = (ra + (rb - ra) * t) * BALL_K
            e.stiffness = 2.0
    for c, half, rot, _ in body.masses:
        e = mb.elements.new()
        e.type = "ELLIPSOID"
        e.co = c
        r = max(half.x, half.y, half.z)
        e.radius = r * ELLIPSOID_K * 0.92
        e.size_x, e.size_y, e.size_z = half.x / r, half.y / r, half.z / r
        e.rotation = rot
        e.stiffness = 2.0
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.view_layer.update()
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    sm = obj.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 5
    bpy.ops.object.modifier_apply(modifier="smooth")
    if len(obj.data.polygons) > faces:
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = faces / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier="dec")
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def add_eyes(obj, eyes):
    before = len(obj.data.vertices)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for co, r in eyes:
        geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        for v in geo["verts"]:
            v.co += Vector(co)
    bm.to_mesh(obj.data)
    bm.free()
    clean_mesh(obj)
    return set(range(before, len(obj.data.vertices)))


def clean_mesh(obj):
    """Removes degenerate geometry left by metaball conversion and decimation; an invalid
    mesh makes the glTF exporter drop it."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.validate(clean_customdata=False)
    obj.data.update()


# --------------------------------------------------------------------------- coat + bake

def paint_and_bake(obj, body, paint, eye_ids, fur_scale, fur_bump, name):
    mesh = obj.data
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for v in mesh.vertices:
        if v.index in eye_ids:
            c = (0.02, 0.018, 0.015)
        else:
            label, t, _ = body.label_at(v.co)
            c = paint(v.co, v.normal, label, t)
        col.data[v.index].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bake material: painted coat x fine fur noise x large patches; fur bump for normals.
    mat = bpy.data.materials.new(name + "_bake")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    attr = nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (fur_scale * 0.35, fur_scale, fur_scale)  # hair lies along the body
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    fur = nodes.new("ShaderNodeTexNoise")
    fur.inputs["Scale"].default_value = 1.0
    fur.inputs["Detail"].default_value = 6.0
    fur.inputs["Roughness"].default_value = 0.7
    links.new(mapping.outputs["Vector"], fur.inputs["Vector"])
    patch = nodes.new("ShaderNodeTexNoise")
    patch.inputs["Scale"].default_value = 3.0
    links.new(coord.outputs["Object"], patch.inputs["Vector"])
    r1 = nodes.new("ShaderNodeMapRange")
    r1.inputs["To Min"].default_value = 0.8
    r1.inputs["To Max"].default_value = 1.16
    links.new(fur.outputs["Fac"], r1.inputs["Value"])
    r2 = nodes.new("ShaderNodeMapRange")
    r2.inputs["To Min"].default_value = 0.9
    r2.inputs["To Max"].default_value = 1.1
    links.new(patch.outputs["Fac"], r2.inputs["Value"])
    m1 = nodes.new("ShaderNodeMixRGB")
    m1.blend_type = "MULTIPLY"
    m1.inputs["Fac"].default_value = 1.0
    links.new(attr.outputs["Color"], m1.inputs["Color1"])
    links.new(r1.outputs["Result"], m1.inputs["Color2"])
    m2 = nodes.new("ShaderNodeMixRGB")
    m2.blend_type = "MULTIPLY"
    m2.inputs["Fac"].default_value = 1.0
    links.new(m1.outputs["Color"], m2.inputs["Color1"])
    links.new(r2.outputs["Result"], m2.inputs["Color2"])
    links.new(m2.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = fur_bump
    bump.inputs["Distance"].default_value = 0.004
    links.new(fur.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    mesh.materials.clear()
    mesh.materials.append(mat)

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.cycles.device = "CPU"
    images = {}
    for kind in ("albedo", "normal"):
        img = bpy.data.images.new(f"{name}_{kind}", TEX, TEX)
        if kind == "normal":
            img.colorspace_settings.name = "Non-Color"
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        nodes.active = tex
        if kind == "albedo":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=6)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=6)
        images[kind] = img
        nodes.remove(tex)

    # Final material for export: the baked maps (embedded in the .glb).
    final = bpy.data.materials.new(name)
    final.use_nodes = True
    fn = final.node_tree
    fb = fn.nodes["Principled BSDF"]
    ta = fn.nodes.new("ShaderNodeTexImage")
    ta.image = images["albedo"]
    fn.links.new(ta.outputs["Color"], fb.inputs["Base Color"])
    tn = fn.nodes.new("ShaderNodeTexImage")
    tn.image = images["normal"]
    nm = fn.nodes.new("ShaderNodeNormalMap")
    fn.links.new(tn.outputs["Color"], nm.inputs["Color"])
    fn.links.new(nm.outputs["Normal"], fb.inputs["Normal"])
    fb.inputs["Roughness"].default_value = 0.85
    mesh.materials.clear()
    mesh.materials.append(final)
    try:
        mesh.color_attributes.remove(col)
    except RuntimeError:
        pass   # harmless: the exporter skips colours (export_colors=False)


# --------------------------------------------------------------------------- rig + animation

def build_rig(name, body, mesh_obj):
    arm_data = bpy.data.armatures.new(name + "_rig")
    arm = bpy.data.objects.new(name + "_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, tail, parent, deform in body.bones:
        eb = arm_data.edit_bones.new(bname)
        eb.head = head
        eb.tail = tail
        eb.use_deform = deform
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # Automatic weights can miss thin parts (antler tines, tusks): give every unweighted
    # vertex fully to its nearest deforming bone so the skin exports cleanly.
    deform = [(bn, h, t) for bn, h, t, _, d in body.bones if d]
    groups = {g.name: g for g in mesh_obj.vertex_groups}
    for v in mesh_obj.data.vertices:
        if any(g.weight > 0.001 for g in v.groups):
            continue
        best, best_d = None, 1e9
        for bn, h, t in deform:
            ab = t - h
            k = max(0.0, min(1.0, (v.co - h).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (v.co - (h + ab * k)).length
            if d < best_d:
                best, best_d = bn, d
        g = groups.get(best) or mesh_obj.vertex_groups.new(name=best)
        groups[best] = g
        g.add([v.index], 1.0, "REPLACE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def local_axis(arm, bname, world_axis):
    return (arm.data.bones[bname].matrix_local.to_3x3().inverted() @ world_axis).normalized()


class Anim:
    """Keyframes one looping action into its own NLA track."""

    def __init__(self, arm, name):
        self.arm, self.name = arm, name
        arm.animation_data_create()
        self.action = bpy.data.actions.new(name)
        arm.animation_data.action = self.action

    def key(self, frame, poses, root_z=0.0):
        """poses: {bone: [(world_axis, angle), ...]}; root_z lifts the whole body."""
        for pb in self.arm.pose.bones:
            q = Quaternion()
            for axis, ang in poses.get(pb.name, []):
                q = q @ Quaternion(local_axis(self.arm, pb.name, axis), ang)
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "root":
                pb.location = (0, root_z, 0)   # the root bone points up: its local Y is world Z
                pb.keyframe_insert("location", frame=frame)

    def done(self):
        track = self.arm.animation_data.nla_tracks.new()
        track.name = self.name
        track.strips.new(self.name, 1, self.action)
        self.arm.animation_data.action = None


def animate_quadruped(arm, sp):
    legs = [("L", "h", 0.0), ("L", "f", 0.25), ("R", "h", 0.5), ("R", "f", 0.75)]

    # Walk: four-beat lateral sequence, with body bob, nodding and a swinging tail.
    C = sp["walk_frames"]
    a = Anim(arm, "walk")
    for f in range(0, C + 1, 2):
        ph = f / C
        poses = {}
        for side, end, off in legs:
            w = 2 * math.pi * (ph + off)
            swing = math.sin(w)
            lift = max(0.0, math.cos(w))
            upper = sp["stride_angle"] * swing
            if end == "f":
                poses[f"scap.{side}"] = [(Y, -upper * 0.65)]
                poses[f"forearm.{side}"] = [(Y, -upper * 0.35)]
                poses[f"cannon_f.{side}"] = [(Y, 0.9 * lift)]
                poses[f"pastern_f.{side}"] = [(Y, 0.3 * lift)]
            else:
                poses[f"thigh.{side}"] = [(Y, -upper * 0.8)]
                poses[f"gaskin.{side}"] = [(Y, 0.35 * lift)]
                poses[f"cannon_h.{side}"] = [(Y, -0.3 * lift)]
                poses[f"pastern_h.{side}"] = [(Y, 0.3 * lift)]
        nod = math.sin(2 * math.pi * ph * 2)
        poses["neck1"] = [(Y, 0.05 * nod)]
        poses["head"] = [(Y, -0.03 * nod)]
        poses["tail1"] = [(Z, 0.12 * math.sin(2 * math.pi * ph))]
        poses["spine2"] = [(Z, 0.02 * math.sin(2 * math.pi * ph))]
        a.key(f + 1, poses, root_z=sp["height"] * 0.012 * math.sin(4 * math.pi * ph))
    a.done()

    # Graze: head down to the grass, chewing, tail swishing, ears turning.
    C = 96
    a = Anim(arm, "graze")
    g = sp["graze"]
    for f in range(0, C + 1, 3):
        ph = f / C
        chew = math.sin(2 * math.pi * ph * 6)
        poses = {"neck1": [(Y, g * 0.5)], "neck2": [(Y, g * 0.18), (Z, 0.08 * math.sin(2 * math.pi * ph))],
                 "head": [(Y, g * 0.12 + 0.04 * chew)],
                 "tail1": [(Z, 0.3 * math.sin(2 * math.pi * ph * 2))],
                 "tail2": [(Z, 0.3 * math.sin(2 * math.pi * ph * 2 - 0.6))],
                 "ear.L": [(Z, 0.25 * math.sin(2 * math.pi * ph))],
                 "ear.R": [(Z, -0.25 * math.sin(2 * math.pi * ph + 1.0))]}
        a.key(f + 1, poses)
    a.done()

    # Idle: head up, looking around, ears flicking, slow tail.
    C = 144
    a = Anim(arm, "idle")
    for f in range(0, C + 1, 3):
        ph = f / C
        look = math.sin(2 * math.pi * ph)
        poses = {"neck1": [(Y, -0.05 + 0.05 * math.sin(2 * math.pi * ph * 2))],
                 "neck2": [(Z, 0.35 * look)], "head": [(Z, 0.2 * look), (Y, 0.05 * math.sin(2 * math.pi * ph * 3))],
                 "tail1": [(Z, 0.15 * math.sin(2 * math.pi * ph * 2))],
                 "ear.L": [(Y, -0.6 * math.exp(-((ph - 0.6) * 25) ** 2))],
                 "ear.R": [(Y, -0.4 * math.exp(-((ph - 0.2) * 25) ** 2))]}
        a.key(f + 1, poses, root_z=sp["height"] * 0.004 * math.sin(2 * math.pi * ph * 4))
    a.done()


# --------------------------------------------------------------------------- quadrupeds

def quadruped(sp):
    """Anatomy from measurements (metres, Blender X forward, Z up)."""
    b = Body()
    H, Hc, L, D, W = sp["height"], sp["croup"], sp["length"], sp["chest"], sp["width"]
    xs, xb = L / 2, -L / 2
    withers = Vector((xs - 0.12 * L, 0, H))
    mid = Vector((0.0, 0, H - 0.04 * H))
    croup = Vector((xb + 0.2 * L, 0, Hc))
    tailhead = Vector((xb + 0.06 * L, 0, Hc - 0.1 * H))
    b.bone("root", (0, 0, 0), (0, 0, 0.15 * H), deform=False)
    b.bone("spine1", croup, mid, "root")
    b.bone("spine2", mid, withers, "spine1")
    na = math.radians(sp["neck_angle"])
    nbase = Vector((xs - 0.02 * L, 0, H - D * 0.35))
    ndir = Vector((math.cos(na), 0, math.sin(na)))
    nmid = nbase + ndir * sp["neck"] * 0.5
    poll = nbase + ndir * sp["neck"]
    ha = math.radians(-sp["head_angle"])
    hdir = Vector((math.cos(ha), 0, math.sin(ha)))
    muzzle = poll + hdir * sp["head"]
    b.bone("neck1", nbase, nmid, "spine2")
    b.bone("neck2", nmid, poll, "neck1")
    b.bone("head", poll, muzzle, "neck2")
    tl = sp["tail"]
    td = math.radians(sp["tail_droop"])
    tdir = Vector((-math.cos(td), 0, -math.sin(td)))
    t1, t2, t3 = tailhead + tdir * tl * 0.33, tailhead + tdir * tl * 0.66, tailhead + tdir * tl
    b.bone("tail1", tailhead, t1, "spine1")
    b.bone("tail2", t1, t2, "tail1")
    b.bone("tail3", t2, t3, "tail2")

    lr = sp["legs"]   # (upper, middle, lower) radii
    for side, sy in (("L", 1), ("R", -1)):
        y = sy * W * 0.72
        scap = Vector((xs - 0.17 * L, sy * W * 0.55, H - 0.06 * H))
        shoulder = Vector((xs - 0.01 * L, y, H - D * 0.62))
        elbow = Vector((xs - 0.1 * L, y, H - D * 1.02))
        knee = Vector((xs - 0.08 * L, y * 0.95, H * 0.3))
        fet_f = Vector((xs - 0.07 * L, y * 0.92, H * 0.09))
        hoof_f = Vector((xs - 0.03 * L, y * 0.92, sp["hoof"] * 0.6))
        b.bone(f"scap.{side}", scap, elbow, "spine2")
        b.bone(f"forearm.{side}", elbow, knee, f"scap.{side}")
        b.bone(f"cannon_f.{side}", knee, fet_f, f"forearm.{side}")
        b.bone(f"pastern_f.{side}", fet_f, hoof_f, f"cannon_f.{side}")
        hip = Vector((xb + 0.2 * L, sy * W * 0.6, Hc - 0.12 * H))
        stifle = Vector((xb + 0.3 * L, y, Hc - D * 1.02))
        hock = Vector((xb + 0.0 * L, y * 0.95, H * 0.3))
        fet_h = Vector((xb + 0.03 * L, y * 0.92, H * 0.08))
        hoof_h = Vector((xb + 0.06 * L, y * 0.92, sp["hoof"] * 0.6))
        b.bone(f"thigh.{side}", hip, stifle, "spine1")
        b.bone(f"gaskin.{side}", stifle, hock, f"thigh.{side}")
        b.bone(f"cannon_h.{side}", hock, fet_h, f"gaskin.{side}")
        b.bone(f"pastern_h.{side}", fet_h, hoof_h, f"cannon_h.{side}")
        b.limb(shoulder, elbow, lr[0] * 1.15, lr[0], "leg_upper")
        b.limb(elbow, knee, lr[0] * 0.95, lr[1], "leg_upper")
        b.limb(knee, fet_f, lr[1] * 0.85, lr[2], "leg_lower")
        b.limb(fet_f, hoof_f, lr[2] * 1.1, sp["hoof"], "hoof")
        b.limb(stifle, hock, lr[0] * 1.0, lr[1] * 0.9, "leg_upper")
        b.limb(Vector((xb + 0.04 * L, y * 0.9, Hc - D * 0.75)), hock + Vector((0.01 * L, 0, 0.04 * H)),
               lr[0] * 0.85, lr[1] * 0.75, "leg_upper")
        b.limb(hock, fet_h, lr[1] * 0.85, lr[2], "leg_lower")
        b.limb(fet_h, hoof_h, lr[2] * 1.1, sp["hoof"], "hoof")
        b.mass(shoulder.lerp(scap, 0.45) + Vector((0, -sy * W * 0.1, 0)), (L * 0.13, W * 0.42, D * 0.42), "body")
        b.mass(hip.lerp(stifle, 0.55) + Vector((-0.03 * L, -sy * W * 0.15, 0)), (L * 0.12, W * 0.38, D * 0.45), "body")
        b.mass(elbow.lerp(knee, 0.2), (lr[0] * 1.2, lr[0] * 1.0, (elbow - knee).length * 0.32), "leg_upper")

    # Trunk: ribcage, belly, hindquarters, withers, chest.
    b.mass((xs - 0.22 * L, 0, H - D * 0.52), (L * 0.3, W * 0.98, D * 0.5), "body")
    b.mass((-0.02 * L, 0, H - D * 0.55), (L * 0.28, W * 1.0, D * 0.47), "body")
    b.mass((xb + 0.22 * L, 0, Hc - D * 0.56), (L * 0.21, W * 0.92, D * 0.42), "body")
    b.mass((xb + 0.07 * L, 0, Hc - D * 0.62), (L * 0.08, W * 0.72, D * 0.36), "body")
    b.mass((xs - 0.14 * L, 0, H - D * 0.18), (L * 0.14, W * 0.45, D * 0.2), "body")
    b.mass((xs + 0.02 * L, 0, H - D * 0.62), (L * 0.08, W * 0.62, D * 0.3), "body")
    # (No flesh between croup and tail root: the hindquarter masses shape the rump.)
    nr0, nr1 = sp["neck_r"]
    b.limb(nbase - ndir * 0.05 * L, nmid, nr0, (nr0 + nr1) / 2, "neck")
    b.limb(nmid, poll, (nr0 + nr1) / 2, nr1, "neck")
    if sp.get("mane"):
        b.limb(nbase + Vector((0, 0, nr0 * 0.75)), poll + Vector((-0.03, 0, nr1 * 0.95)), nr0 * 0.42, nr1 * 0.4, "mane")
    cr, mr = sp["cranium"], sp["muzzle"]
    b.mass(poll + hdir * cr * 0.7, (cr * 1.25, cr * 0.95, cr * 1.0), "head", Quaternion(Y, -ha))
    b.limb(poll + hdir * cr * 1.2, muzzle, cr * 0.85, mr, "muzzle")
    # Jaw and cheek: the lower half of the head is deep in grazers.
    side = Vector((-math.sin(ha), 0, math.cos(ha)))   # "up" across the head
    b.mass(poll + hdir * sp["head"] * 0.38 - side * cr * 0.55, (sp["head"] * 0.32, cr * 0.75, cr * 0.6), "head", Quaternion(Y, -ha))
    b.mass(muzzle - hdir * mr * 0.6, (mr * 1.3, mr * 1.15, mr * 1.1), "muzzle", Quaternion(Y, -ha))
    for side, sy in (("L", 1), ("R", -1)):
        eb = poll + Vector((-cr * 0.25, sy * cr * 0.55, cr * 0.75))
        et = eb + Vector((-sp["ear"] * 0.3, sy * sp["ear"] * sp.get("ear_spread", 0.45), sp["ear"] * 0.85))
        b.bone(f"ear.{side}", eb, et, "head")
        b.limb(eb, et, sp["ear_r"], sp["ear_r"] * 0.3, "ear")
    tr = sp["tail_r"]
    tm = sp.get("tail_mid", 0.9)
    b.limb(tailhead, t1, tr * 0.7, tr * tm, "tail")
    b.limb(t1, t2, tr * tm, tr * tm, "tail")
    b.limb(t2, t3, tr * tm, tr * sp.get("tail_tip", 0.5), "tail")
    if sp.get("antler"):
        an = sp["antler"]
        for sy in (1, -1):
            base = poll + Vector((cr * 0.1, sy * cr * 0.4, cr * 0.85))
            prev = base
            for k in range(an["segments"]):
                f = (k + 1) / an["segments"]
                pt = base + Vector((-an["back"] * f, sy * an["spread"] * math.sin(f * 1.7), an["height"] * f))
                r0 = an["r"] * (1.0 - 0.55 * (k / an["segments"]))
                b.limb(prev, pt, r0, r0 * 0.85, "antler")
                if k < an["segments"] - 1:
                    tine = pt + Vector((an["tine"] * 0.75, sy * an["tine"] * 0.2, an["tine"] * 0.65))
                    b.limb(pt, tine, r0 * 0.6, r0 * 0.25, "antler")
                prev = pt
            if an.get("brow"):
                b.limb(base, base + Vector((an["brow"], sy * 0.04, an["brow"] * 0.35)), an["r"] * 0.7, an["r"] * 0.3, "antler")
    if sp.get("tusk"):
        for sy in (1, -1):
            tb = muzzle + Vector((-mr * 1.2, sy * mr * 0.9, -mr * 0.2))
            b.limb(tb, tb + Vector((sp["tusk"] * 0.15, sy * sp["tusk"] * 0.35, sp["tusk"])), 0.016, 0.006, "tusk")
    eye_c = poll + hdir * cr * 0.65
    eyes = [((eye_c + Vector((0, sy * cr * 0.82, cr * 0.32))), cr * 0.13) for sy in (1, -1)]
    return b, eyes


def make_quadruped(name, sp, paint, fur_scale=300.0, fur_bump=0.25, displace=None):
    body, eyes = quadruped(sp)
    obj = build_flesh(name, body, sp["height"] * 0.012, sp.get("faces", 9000))
    if displace:
        for v in obj.data.vertices:
            label, t, _ = body.label_at(v.co)
            v.co += v.normal * displace(v.co, label)
    eye_ids = add_eyes(obj, eyes)
    paint_and_bake(obj, body, lambda co, n, label, t: paint(co, n, label, t, sp), eye_ids, fur_scale, fur_bump, name)
    arm = build_rig(name, body, obj)
    animate_quadruped(arm, sp)
    META[name] = {"kind": "land", "walk_speed": round(sp["stride"] / (sp["walk_frames"] / FPS), 3),
                  "height": sp["height"], "length": sp["length"]}
    return obj, arm


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def shade(c, k):
    return tuple(min(1.0, x * k) for x in c)


# --------------------------------------------------------------------------- species

def horse():
    sp = dict(height=1.42, croup=1.40, length=1.45, chest=0.66, width=0.27, neck=0.78, neck_angle=46,
              neck_r=(0.24, 0.15), head=0.55, cranium=0.13, muzzle=0.09, head_angle=58, ear=0.14, ear_r=0.032,
              ear_spread=0.2, legs=(0.12, 0.07, 0.042), hoof=0.06, tail=0.75, tail_r=0.07, tail_droop=72,
              tail_mid=1.15, tail_tip=0.8, mane=True, walk_frames=26, stride=1.55, stride_angle=0.42, graze=1.3)
    coat = (0.62, 0.48, 0.3)   # Fjord dun; the game tints it to other colours
    dark = (0.1, 0.08, 0.07)

    def paint(co, n, label, t, sp):
        if label in ("mane", "tail"):
            return dark
        if label == "hoof":
            return (0.08, 0.07, 0.06)
        if label == "leg_lower":
            return mix(dark, coat, 0.15)
        if label == "muzzle":
            return mix(coat, (0.22, 0.17, 0.14), t)
        if label == "ear":
            return mix(coat, dark, t)
        belly = max(0.0, -n.z) * 0.3
        dorsal = max(0.0, 1.0 - abs(co.y) / 0.03) if label == "body" and n.z > 0.8 else 0.0
        return mix(mix(coat, (0.78, 0.68, 0.52), belly), dark, dorsal * 0.8)   # dun dorsal stripe
    return make_quadruped("horse", sp, paint, fur_scale=420.0, fur_bump=0.18)


def sheep():
    sp = dict(height=0.72, croup=0.72, length=0.88, chest=0.4, width=0.22, neck=0.3, neck_angle=35,
              neck_r=(0.12, 0.085), head=0.26, cranium=0.08, muzzle=0.05, head_angle=52, ear=0.1, ear_r=0.024,
              ear_spread=0.9, legs=(0.06, 0.038, 0.024), hoof=0.025, tail=0.22, tail_r=0.045, tail_droop=82,
              walk_frames=22, stride=0.62, stride_angle=0.38, graze=1.15)
    wool = (0.86, 0.83, 0.76)
    face = (0.17, 0.14, 0.12)

    def paint(co, n, label, t, sp):
        if label in ("head", "muzzle", "ear"):
            return face
        if label == "hoof":
            return (0.08, 0.07, 0.06)
        if label == "leg_lower" or (label == "leg_upper" and co.z < 0.3):
            return face
        return wool

    def displace(co, label):
        if label in ("body", "neck", "tail") or (label == "leg_upper" and co.z > 0.3):
            return 0.025 + 0.02 * noise.noise(co * 22.0)   # fleece
        return 0.0
    return make_quadruped("sheep", sp, paint, fur_scale=70.0, fur_bump=0.6, displace=displace)


def deer(name, reindeer):
    if reindeer:
        sp = dict(height=1.1, croup=1.08, length=1.28, chest=0.55, width=0.25, neck=0.52, neck_angle=40,
                  neck_r=(0.17, 0.1), head=0.42, cranium=0.1, muzzle=0.07, head_angle=45, ear=0.12, ear_r=0.03,
                  ear_spread=0.6, legs=(0.1, 0.055, 0.035), hoof=0.06, tail=0.12, tail_r=0.04, tail_droop=60,
                  walk_frames=26, stride=1.25, stride_angle=0.4, graze=1.2, faces=12000,
                  antler=dict(segments=5, back=0.5, spread=0.35, height=0.75, r=0.03, tine=0.16, brow=0.22))
        coat, pale = (0.42, 0.37, 0.31), (0.86, 0.84, 0.78)
    else:
        sp = dict(height=1.22, croup=1.26, length=1.38, chest=0.52, width=0.21, neck=0.6, neck_angle=55,
                  neck_r=(0.17, 0.1), head=0.42, cranium=0.1, muzzle=0.06, head_angle=55, ear=0.17, ear_r=0.032,
                  ear_spread=0.7, legs=(0.085, 0.048, 0.028), hoof=0.035, tail=0.14, tail_r=0.04, tail_droop=70,
                  walk_frames=26, stride=1.4, stride_angle=0.42, graze=1.25, faces=12000,
                  antler=dict(segments=4, back=0.4, spread=0.38, height=0.85, r=0.028, tine=0.2, brow=0.2))
        coat, pale = (0.5, 0.31, 0.17), (0.8, 0.7, 0.53)
    antler = (0.55, 0.47, 0.37)

    def paint(co, n, label, t, sp):
        if label == "antler":
            return antler
        if label == "hoof":
            return (0.06, 0.05, 0.04)
        if label == "leg_lower":
            return shade(coat, 0.7)
        if label == "tail" or (label == "body" and co.x < -sp["length"] * 0.42 and n.x < -0.3):
            return pale
        if reindeer and label == "neck":
            return mix(coat, pale, 0.75)
        if label == "muzzle":
            return mix(coat, shade(coat, 0.45), t)
        return mix(coat, pale, max(0.0, -n.z) * 0.6)
    return make_quadruped(name, sp, paint, fur_scale=380.0, fur_bump=0.2)


def boar():
    sp = dict(height=0.85, croup=0.8, length=1.05, chest=0.56, width=0.24, neck=0.2, neck_angle=12,
              neck_r=(0.24, 0.2), head=0.46, cranium=0.15, muzzle=0.075, head_angle=30, ear=0.12, ear_r=0.035,
              ear_spread=0.4, legs=(0.085, 0.048, 0.032), hoof=0.034, tail=0.25, tail_r=0.025, tail_droop=82,
              tusk=0.08, walk_frames=20, stride=0.7, stride_angle=0.38, graze=0.75)
    hair = (0.24, 0.18, 0.13)

    def paint(co, n, label, t, sp):
        if label == "tusk":
            return (0.92, 0.88, 0.78)
        if label == "hoof":
            return (0.05, 0.04, 0.04)
        if label == "muzzle":
            return (0.32, 0.24, 0.21) if t > 0.85 else shade(hair, 0.9)
        if label in ("leg_lower", "leg_upper"):
            return shade(hair, 0.6)
        if n.z > 0.6 and label in ("body", "neck"):
            return shade(hair, 0.65)
        return hair
    return make_quadruped("boar", sp, paint, fur_scale=160.0, fur_bump=0.5)


def fox():
    sp = dict(height=0.4, croup=0.4, length=0.6, chest=0.2, width=0.08, neck=0.16, neck_angle=38,
              neck_r=(0.058, 0.042), head=0.19, cranium=0.05, muzzle=0.02, head_angle=14, ear=0.085, ear_r=0.022,
              ear_spread=0.3, legs=(0.03, 0.018, 0.012), hoof=0.016, tail=0.42, tail_r=0.055, tail_droop=22,
              tail_mid=1.25, tail_tip=0.6, walk_frames=16, stride=0.48, stride_angle=0.45, graze=0.9)
    red, white, black = (0.74, 0.36, 0.12), (0.93, 0.9, 0.85), (0.08, 0.06, 0.05)

    def paint(co, n, label, t, sp):
        if label == "tail":
            return white if t > 0.82 and co.x < -0.6 else red
        if label in ("leg_lower", "hoof"):
            return black
        if label == "ear":
            return black if t > 0.55 else red
        if label == "muzzle" and n.z < 0.0:
            return white
        if label in ("neck", "body") and n.z < -0.25:
            return white
        return red
    return make_quadruped("fox", sp, paint, fur_scale=260.0, fur_bump=0.35)


# --------------------------------------------------------------------------- marine

def seal(name, walrus):
    s = 1.0 if not walrus else 1.85
    b = Body()
    r = 0.22 * s if not walrus else 0.27 * s
    pts = [Vector((-0.85 * s, 0, 0.1 * s)), Vector((-0.45 * s, 0, 0.16 * s)), Vector((0.0, 0, 0.2 * s)),
           Vector((0.4 * s, 0, 0.22 * s)), Vector((0.7 * s, 0, 0.3 * s)), Vector((0.95 * s, 0, 0.38 * s))]
    b.bone("root", (0, 0, 0), (0, 0, 0.1), deform=False)
    names = ["body1", "body2", "body3", "neck", "head"]
    for k in range(5):
        b.bone(names[k], pts[k], pts[k + 1], "root" if k == 0 else names[k - 1])
    radii = [0.08 * s, r * 0.85, r, r * 0.88, r * 0.6, r * 0.42]
    labels = ["body", "body", "body", "neck", "head"]
    for k in range(5):
        b.limb(pts[k], pts[k + 1], radii[k], radii[k + 1], labels[k])
    b.mass(pts[2], (0.55 * s, r * 1.05, r * 0.95), "body")
    b.limb(pts[5], pts[5] + Vector((0.14 * s, 0, -0.03 * s)), r * 0.42, r * 0.28, "muzzle")
    for side, sy in (("L", 1), ("R", -1)):
        fa = pts[3] + Vector((0, sy * r * 0.8, -0.1 * s))
        ft = fa + Vector((0.12 * s, sy * 0.25 * s, -0.08 * s))
        b.bone(f"flipper.{side}", fa, ft, "body3")
        b.limb(fa, ft, 0.05 * s, 0.03 * s, "flipper")
        ha = pts[0] + Vector((-0.05 * s, sy * 0.06 * s, 0))
        ht = ha + Vector((-0.25 * s, sy * 0.12 * s, 0))
        b.bone(f"hind.{side}", ha, ht, "body1")
        b.limb(ha, ht, 0.04 * s, 0.03 * s, "flipper")
        if walrus:
            tb = pts[5] + Vector((0.1 * s, sy * 0.05 * s, -0.06 * s))
            b.limb(tb, tb + Vector((0.03 * s, sy * 0.02 * s, -0.32 * s)), 0.022 * s, 0.008 * s, "tusk")
    obj = build_flesh(name, b, 0.02 * s, 7000)
    if walrus:
        for v in obj.data.vertices:
            label, t, _ = b.label_at(v.co)
            if label in ("body", "neck"):
                v.co += v.normal * 0.02 * s * noise.noise(v.co * 7.0)
    eye_ids = add_eyes(obj, [(pts[5] + Vector((0.05 * s, sy * r * 0.36, 0.06 * s)), 0.022 * s) for sy in (1, -1)])
    base = (0.42, 0.42, 0.4) if not walrus else (0.5, 0.36, 0.28)

    def paint(co, n, label, t):
        if label == "tusk":
            return (0.93, 0.9, 0.8)
        if label == "flipper":
            return shade(base, 0.6)
        if not walrus:
            spot = 0.72 if noise.noise(co * 13.0) > 0.35 else 1.0
            return mix(shade(base, spot), (0.66, 0.64, 0.6), max(0.0, -n.z) * 0.6)
        return base
    paint_and_bake(obj, b, paint, eye_ids, 120.0 if walrus else 300.0, 0.3, name)
    arm = build_rig(name, b, obj)
    a = Anim(arm, "idle")
    for f in range(0, 145, 4):
        ph = f / 144
        a.key(f + 1, {"neck": [(Y, -0.25), (Z, 0.3 * math.sin(2 * math.pi * ph))], "head": [(Z, 0.15 * math.sin(2 * math.pi * ph))],
                      "hind.L": [(Z, 0.2 * math.sin(2 * math.pi * ph * 2))], "hind.R": [(Z, -0.2 * math.sin(2 * math.pi * ph * 2))]})
    a.done()
    a = Anim(arm, "graze")
    for f in range(0, 145, 4):
        ph = f / 144
        a.key(f + 1, {"neck": [(Y, 0.25)], "head": [(Y, 0.15 + 0.03 * math.sin(2 * math.pi * ph * 2))],
                      "hind.L": [(Z, 0.1 * math.sin(2 * math.pi * ph))]})
    a.done()
    a = Anim(arm, "walk")
    for f in range(0, 31, 2):
        w = 2 * math.pi * f / 30
        a.key(f + 1, {"body1": [(Y, 0.15 * math.sin(w))], "body2": [(Y, 0.18 * math.sin(w - 0.8))],
                      "body3": [(Y, 0.15 * math.sin(w - 1.6))], "neck": [(Y, -0.15 * math.sin(w - 2.2))],
                      "flipper.L": [(Y, 0.5 * math.sin(w))], "flipper.R": [(Y, 0.5 * math.sin(w))]},
              root_z=0.04 * s * max(0.0, math.sin(w)))
    a.done()
    META[name] = {"kind": "shore", "walk_speed": round(0.5 * s, 3), "height": 0.5 * s, "length": 2.0 * s}
    return obj, arm


def whale():
    b = Body()
    pts = [Vector((5.6, 0, -0.9)), Vector((3.5, 0, -0.6)), Vector((1.0, 0, -0.55)), Vector((-2.0, 0, -0.65)),
           Vector((-4.5, 0, -0.75)), Vector((-6.2, 0, -0.8))]
    radii = [0.55, 1.25, 1.45, 1.2, 0.6, 0.28]
    b.bone("root", (0, 0, 0), (0, 0, 0.5), deform=False)
    b.bone("chest", pts[2], pts[1], "root")
    b.bone("head", pts[1], pts[0], "chest")
    b.bone("belly", pts[2], pts[3], "root")
    b.bone("tail1", pts[3], pts[4], "belly")
    b.bone("tail2", pts[4], pts[5], "tail1")
    for k in range(5):
        b.limb(pts[k], pts[k + 1], radii[k], radii[k + 1], "body")
    b.mass(pts[2], (3.2, 1.45, 1.25), "body")
    for side, sy in (("L", 1), ("R", -1)):
        fa = Vector((2.6, sy * 1.3, -1.3))
        ft = Vector((1.0, sy * 4.4, -2.5))
        b.bone(f"fin.{side}", fa, ft, "chest")
        b.limb(fa, fa.lerp(ft, 0.5), 0.22, 0.15, "fin")
        b.limb(fa.lerp(ft, 0.5), ft, 0.15, 0.06, "fin")
        fl = Vector((-6.6, sy * 1.1, -0.8))
        b.limb(pts[5], fl, 0.2, 0.12, "fluke")
        b.limb(fl, Vector((-7.0, sy * 2.0, -0.75)), 0.12, 0.05, "fluke")
    b.limb(Vector((-2.4, 0, 0.3)), Vector((-2.7, 0, 0.62)), 0.18, 0.06, "dorsal")
    obj = build_flesh("whale", b, 0.1, 7000)
    eye_ids = add_eyes(obj, [((4.3, sy * 1.42, -1.0), 0.1) for sy in (1, -1)])

    def paint(co, n, label, t):
        dark = (0.1, 0.11, 0.13)
        if label == "fin" and n.z < 0:
            return (0.82, 0.82, 0.8)
        belly = max(0.0, -n.z)
        if belly > 0.5 and co.x > 1.5 and math.sin(co.y * 22.0) > 0.4:
            return (0.6, 0.6, 0.58)
        return mix(dark, (0.72, 0.72, 0.7), belly * 0.9)
    paint_and_bake(obj, b, paint, eye_ids, 12.0, 0.15, "whale")
    arm = build_rig("whale", b, obj)
    a = Anim(arm, "swim")
    for f in range(0, 97, 3):
        w = 2 * math.pi * f / 96
        a.key(f + 1, {"tail1": [(Y, 0.08 * math.sin(w))], "tail2": [(Y, 0.18 * math.sin(w - 0.9))],
                      "head": [(Y, -0.03 * math.sin(w + 0.6))], "fin.L": [(Z, 0.1 * math.sin(w))], "fin.R": [(Z, -0.1 * math.sin(w))]},
              root_z=0.25 * math.sin(w + 1.2))
    a.done()
    META["whale"] = {"kind": "sea", "walk_speed": 1.6, "height": 2.0, "length": 12.5}
    return obj, arm


def export(name, obj, arm):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_texcoords=True, export_normals=True,
                              export_tangents=True, export_colors=False, export_image_format="AUTO")
    print("exported", path, len(obj.data.polygons), "faces")


BUILDERS = [
    ("horse", horse), ("sheep", sheep), ("deer", lambda: deer("deer", False)),
    ("reindeer", lambda: deer("reindeer", True)), ("boar", boar), ("fox", fox),
    ("seal", lambda: seal("seal", False)), ("walrus", lambda: seal("walrus", True)), ("whale", whale),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    only = os.environ.get("ANIMALS")
    for name, build in BUILDERS:
        if only and name not in only.split(","):
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        addon_utils.enable("cycles")
        obj, arm = build()
        export(name, obj, arm)
    path = os.path.join(OUT, "animals.json")
    data = {}
    if only and os.path.exists(path):
        data = json.load(open(path))
    data.update(META)
    with open(path, "w") as f:
        json.dump(data, f, indent=1)
    print("wrote animals.json")


main()
