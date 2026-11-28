"""Builds Logiheim's villagers: sculpted bodies in clothes, rigged and animated.

Run headless (Blender 4.x):
    blender -b --python tools/blender/make_people.py -- assets/models/people

Two figures, a man and a woman, ~1.75 m, standing facing -Z in Godot (+Y here):
  1. Flesh: metaballs - a torso family (hips, belly, ribcage, chest, shoulders, neck, a head
     with jaw, cheekbones, nose, brow and ears), and each arm (upper arm, forearm, a hand with
     a thumb) and each leg (thigh, calf, a foot) a family of its own so limbs never melt into
     the body; converted, smoothed and joined.
  2. Clothes as shells over it: the man's tunic flaring from the belt to the knee over
     trousers and leg wraps; the woman's long linen underdress and the apron dress over it,
     hung from straps; a belt; turnshoes. Eyes, brows and lips are small pieces of their own.
  3. Every vertex says what it is in its colour's red channel (REGIONS): skin, the outer
     garment, the underdress / shirt, trousers, leg wraps, shoes, belt, trim, hair, eye white,
     dark (pupils, brows), lips - so the game colours each person (shaders/people.gdshader).
  4. Hair and beards as separate pieces on the head (several styles each; the game shows one
     of each).
  5. Rig: a full skeleton (hips, spine, chest, neck, head; clavicles, upper arms, forearms,
     hands; thighs, shins, feet), skinned with automatic weights; the skirts are weighted to
     the hips and, lower down, partly to the thighs, so the cloth follows the legs.
  6. Looping animations as NLA tracks: idle, walk, walk_carry, chop, pick, hammer, dig, reap,
     net, stir, march, guard, brace - keyed every frame from curves with eased arcs,
     follow-through, weight shift and counter-rotation.
Exported as villager_m.glb and villager_f.glb (skin + animations + vertex colours).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Quaternion, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models/people"
FPS = 24
X = Vector((1, 0, 0))   # the figure's right
Y = Vector((0, 1, 0))   # forward
Z = Vector((0, 0, 1))   # up
ELLIPSOID_K = 1.0 / 0.573
BALL_K = 0.85 / 0.575

REGIONS = {"skin": 0, "outer": 1, "under": 2, "trousers": 3, "wraps": 4, "shoes": 5, "belt": 6, "trim": 7,
           "hair": 8, "eye": 9, "dark": 10, "lips": 11}


def region_color(name):
    return (REGIONS[name] / 15.0, 0.0, 0.0, 1.0)


# --------------------------------------------------------------------------- flesh

def metaball(name, balls, ellipsoids, resolution=0.022):
    """balls: (a, b, ra, rb) segments; ellipsoids: (centre, half extents, rotation)."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    for a, b, ra, rb in balls:
        a, b = Vector(a), Vector(b)
        n = max(2, math.ceil((b - a).length / max(min(ra, rb) * 0.5, 1e-3)))
        for i in range(n + 1):
            t = i / n
            e = mb.elements.new()
            e.co = a.lerp(b, t)
            e.radius = (ra + (rb - ra) * t) * BALL_K
            e.stiffness = 2.0
    for c, half, rot in ellipsoids:
        half = Vector(half)
        e = mb.elements.new()
        e.type = "ELLIPSOID"
        e.co = Vector(c)
        r = max(half.x, half.y, half.z)
        e.radius = r * ELLIPSOID_K * 0.92
        e.size_x, e.size_y, e.size_z = half.x / r, half.y / r, half.z / r
        e.rotation = rot or Quaternion()
        e.stiffness = 2.0
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.view_layer.update()
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    sm = obj.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 4
    bpy.ops.object.modifier_apply(modifier="smooth")
    return obj


def paint(obj, fn):
    """Sets each vertex's region (fn(co) -> region name) as the mesh's vertex colour."""
    me = obj.data
    if not me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    attr = me.color_attributes[0]
    for v in me.vertices:
        attr.data[v.index].color = region_color(fn(v.co))


def solid(obj, region):
    paint(obj, lambda co: region)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def finish(obj, faces=None):
    if faces and len(obj.data.polygons) > faces:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = faces / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier="dec")
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.data.validate(clean_customdata=False)
    obj.data.update()


# --------------------------------------------------------------------------- shells

def lathe(name, rings, sides=24, wave=0.0, wave_n=7, open_top=True):
    """A surface of revolution round Z: rings = [(z, rx, ry, y_off)], top to bottom. A cloth
    shell: the hem may wave."""
    bm = bmesh.new()
    rows = []
    for k, (z, rx, ry, yo) in enumerate(rings):
        row = []
        last = k == len(rings) - 1
        for i in range(sides):
            a = 2 * math.pi * i / sides
            w = 1.0 + (wave * math.sin(a * wave_n) if last else wave * 0.4 * math.sin(a * wave_n) * (k / max(len(rings) - 1, 1)))
            row.append(bm.verts.new((math.cos(a) * rx * w, math.sin(a) * ry * w + yo, z)))
        rows.append(row)
    for k in range(len(rows) - 1):
        for i in range(sides):
            a, b = rows[k][i], rows[k][(i + 1) % sides]
            c, d = rows[k + 1][(i + 1) % sides], rows[k + 1][i]
            bm.faces.new((a, b, c, d))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    # Cloth has thickness.
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    sol = obj.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.008
    sol.offset = 1.0
    bpy.ops.object.modifier_apply(modifier="sol")
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    bpy.ops.object.modifier_apply(modifier="sub")
    return obj


def ico(name, c, r, scale=(1, 1, 1), subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(c)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tube(name, pts, r, sides=8):
    """A tube along a polyline (braids, straps)."""
    bm = bmesh.new()
    rows = []
    for i, p in enumerate(pts):
        p = Vector(p)
        d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        u = d.cross(Y if abs(d.dot(Y)) < 0.9 else X).normalized()
        v = d.cross(u).normalized()
        rr = r[i] if isinstance(r, (list, tuple)) else r
        rows.append([bm.verts.new(p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * rr) for k in range(sides)])
    for i in range(len(rows) - 1):
        for k in range(sides):
            bm.faces.new((rows[i][k], rows[i][(k + 1) % sides], rows[i + 1][(k + 1) % sides], rows[i + 1][k]))
    bmesh.ops.contextual_create(bm, geom=rows[0])
    bmesh.ops.contextual_create(bm, geom=rows[-1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# --------------------------------------------------------------------------- the figure

class Figure:
    def __init__(self, female):
        self.female = female
        f = female
        self.hips_z = 0.95
        self.sh = 0.205 if f else 0.235        # shoulder joint, out from the middle
        self.sh_z = 1.45 if f else 1.47
        self.hip_x = 0.1 if f else 0.095
        self.head_c = Vector((0, 0.005, 1.675))
        # Arms hang a little out from the body (A-pose), elbows a touch forward.
        s = 1
        self.joints = {}
        for side, sx in (("R", 1), ("L", -1)):
            self.joints["shoulder." + side] = Vector((sx * self.sh, 0.0, self.sh_z))
            self.joints["elbow." + side] = Vector((sx * (self.sh + 0.07), 0.025, self.sh_z - 0.29))
            self.joints["wrist." + side] = Vector((sx * (self.sh + 0.1), 0.05, self.sh_z - 0.55))
            self.joints["fingers." + side] = Vector((sx * (self.sh + 0.11), 0.06, self.sh_z - 0.72))
            self.joints["hip." + side] = Vector((sx * self.hip_x, 0.0, self.hips_z))
            self.joints["knee." + side] = Vector((sx * (self.hip_x + 0.01), 0.015, 0.5))
            self.joints["ankle." + side] = Vector((sx * (self.hip_x + 0.015), -0.01, 0.075))
            self.joints["toe." + side] = Vector((sx * (self.hip_x + 0.02), 0.15, 0.02))
        s = s

    def bones(self):
        j = self.joints
        b = [("root", (0, 0, 0), (0, 0, 0.12), None, False),
             ("hips", (0, 0, self.hips_z), (0, 0, 1.08), "root", True),
             ("spine", (0, 0, 1.08), (0, 0.005, 1.25), "hips", True),
             ("chest", (0, 0.005, 1.25), (0, 0.0, 1.44), "spine", True),
             ("neck", (0, 0.0, 1.44), (0, 0.01, 1.57), "chest", True),
             ("head", (0, 0.01, 1.57), (0, 0.01, 1.8), "neck", True)]
        for side in ("R", "L"):
            sx = 1 if side == "R" else -1
            b += [("clavicle." + side, (sx * 0.03, 0.01, self.sh_z - 0.02), tuple(j["shoulder." + side]), "chest", True),
                  ("upper_arm." + side, tuple(j["shoulder." + side]), tuple(j["elbow." + side]), "clavicle." + side, True),
                  ("forearm." + side, tuple(j["elbow." + side]), tuple(j["wrist." + side]), "upper_arm." + side, True),
                  ("hand." + side, tuple(j["wrist." + side]), tuple(j["fingers." + side]), "forearm." + side, True),
                  ("thigh." + side, tuple(j["hip." + side]), tuple(j["knee." + side]), "hips", True),
                  ("shin." + side, tuple(j["knee." + side]), tuple(j["ankle." + side]), "thigh." + side, True),
                  ("foot." + side, tuple(j["ankle." + side]), tuple(j["toe." + side]), "shin." + side, True)]
        return b

    # The body itself.
    def flesh(self):
        f = self.female
        j = self.joints
        hc = self.head_c
        torso_balls = [((0, 0.0, 1.42), (0, 0.005, 1.6), 0.052, 0.048)]     # neck
        torso_ell = [
            ((0, 0.0, 0.97), (0.165 if f else 0.15, 0.11, 0.1), None),       # pelvis
            ((0, 0.01, 1.1), (0.135 if f else 0.14, 0.095, 0.1), None),      # waist / belly
            ((0, 0.0, 1.26), (0.15 if f else 0.165, 0.1, 0.12), None),       # ribcage
            ((0, -0.005, 1.38), (0.17 if f else 0.2, 0.095, 0.075), None),   # chest and shoulders
            (hc, (0.088, 0.105, 0.118), None),                                # cranium
            ((0, hc.y + 0.035, hc.z - 0.075), (0.062, 0.065, 0.05), None),   # jaw and chin
            ((0, hc.y + 0.085, hc.z - 0.005), (0.016, 0.022, 0.03), None),   # nose
            ((0, hc.y + 0.08, hc.z + 0.04), (0.065, 0.02, 0.016), None),     # brow
        ]
        for sx in (1, -1):
            torso_ell.append(((sx * 0.06, hc.y + 0.06, hc.z - 0.02), (0.03, 0.03, 0.025), None))  # cheekbones
            torso_ell.append(((sx * 0.093, hc.y - 0.005, hc.z - 0.005), (0.014, 0.024, 0.032), None))  # ears
            torso_ell.append(((sx * (self.sh - 0.035), 0.0, self.sh_z - 0.01), (0.06, 0.055, 0.055), None))  # deltoids
            if f:
                torso_ell.append(((sx * 0.065, 0.065, 1.3), (0.06, 0.05, 0.055), None))   # bust
            else:
                torso_ell.append(((sx * 0.075, 0.06, 1.33), (0.07, 0.04, 0.05), None))    # pectorals
            torso_ell.append(((sx * 0.08, -0.06, 0.92), (0.085, 0.07, 0.08), None))      # buttocks
        torso = metaball("torso", torso_balls, torso_ell, 0.016)
        parts = [torso]
        for side, sx in (("R", 1), ("L", -1)):
            sh, el, wr, fi = (j[k + "." + side] for k in ("shoulder", "elbow", "wrist", "fingers"))
            arm = metaball("arm" + side, [
                (sh, el, 0.052 if not f else 0.045, 0.042 if not f else 0.038),
                (el, wr, 0.042 if not f else 0.036, 0.03 if not f else 0.027),
            ], [
                ((sh + el) * 0.5 + Vector((0, -0.01, 0.02)), (0.05, 0.048, 0.08), None),   # upper arm
                ((el + wr) * 0.5 + Vector((0, 0.005, 0.04)), (0.04, 0.04, 0.07), None),    # forearm
                (wr + (fi - wr) * 0.45, (0.022, 0.046, 0.06), None),                        # hand
                (wr + Vector((-sx * 0.0, 0.04, -0.04)), (0.014, 0.014, 0.03), None),       # thumb
            ], 0.013)
            leg = metaball("leg" + side, [
                (j["hip." + side], j["knee." + side], 0.085 if not f else 0.09, 0.055),
                (j["knee." + side], j["ankle." + side], 0.052, 0.036),
            ], [
                ((j["hip." + side] + j["knee." + side]) * 0.5 + Vector((0, 0.01, 0.03)), (0.075, 0.08, 0.17), None),
                ((j["knee." + side] + j["ankle." + side]) * 0.5 + Vector((0, -0.025, 0.1)), (0.05, 0.055, 0.11), None),
                (j["ankle." + side] + Vector((0, 0.06, -0.035)), (0.045, 0.11, 0.04), None),   # foot
            ], 0.016)
            parts += [arm, leg]
        body = join(parts, "body")

        def region(co):
            # Hands and head are skin; feet in shoes; shins wrapped; the rest by garment.
            z = co.z
            if z > 1.55 or (abs(co.x) > self.sh + 0.06 and z < self.sh_z - 0.53):
                return "skin"
            if z < 0.12:
                return "shoes"
            if z < 0.47:
                return "wraps" if not f else "under"
            if z < self.hips_z - 0.02:
                return "trousers" if not f else "under"
            if abs(co.x) > self.sh - 0.02 and z < self.sh_z - 0.5:
                return "trim"  # cuff
            return "outer" if not f else "under"
        paint(body, region)
        finish(body)
        return body

    def clothes(self):
        """The garment shells: tunic or dresses, belt, trims."""
        f = self.female
        pieces = []
        if not f:
            tunic = lathe("tunic", [
                (self.hips_z + 0.02, 0.178, 0.135, 0.0),
                (self.hips_z - 0.08, 0.2, 0.15, 0.0),
                (self.hips_z - 0.22, 0.235, 0.18, 0.005),
                (0.57, 0.27, 0.215, 0.01),
            ], wave=0.04)
            solid(tunic, "outer")
            hem = lathe("hem", [(0.6, 0.27, 0.215, 0.01), (0.565, 0.275, 0.22, 0.01)], wave=0.04)
            solid(hem, "trim")
            pieces += [tunic, hem]
        else:
            under = lathe("underdress", [
                (self.hips_z + 0.03, 0.165, 0.125, 0.0),
                (self.hips_z - 0.15, 0.21, 0.16, 0.005),
                (0.5, 0.25, 0.2, 0.01),
                (0.09, 0.29, 0.24, 0.02),
            ], wave=0.035)
            solid(under, "under")
            apron = lathe("apron_dress", [
                (1.37, 0.16, 0.13, 0.008),
                (1.2, 0.152, 0.118, 0.008),
                (self.hips_z, 0.192, 0.147, 0.0),
                (self.hips_z - 0.25, 0.25, 0.195, 0.008),
                (0.3, 0.31, 0.255, 0.02),
            ], wave=0.0)
            solid(apron, "outer")
            # Shoulder straps.
            for sx in (1, -1):
                st = tube("strap", [(sx * 0.09, 0.09, 1.37), (sx * 0.12, 0.06, 1.46), (sx * 0.12, -0.04, 1.47), (sx * 0.1, -0.1, 1.37)], 0.012)
                solid(st, "outer")
                pieces.append(st)
            pieces += [under, apron]
        belt = lathe("belt", [(self.hips_z + 0.04, 0.18 if not f else 0.172, 0.138 if not f else 0.13, 0.0),
                              (self.hips_z - 0.005, 0.184 if not f else 0.176, 0.142 if not f else 0.134, 0.0)])
        solid(belt, "belt")
        pieces.append(belt)
        # Neckline trim.
        neck = lathe("neckline", [(1.45, 0.075, 0.07, 0.0), (1.42, 0.09, 0.085, 0.0)])
        solid(neck, "trim")
        pieces.append(neck)
        return pieces

    def face(self):
        hc = self.head_c
        out = []
        for sx in (1, -1):
            e = ico("eye", (sx * 0.034, hc.y + 0.087, hc.z + 0.012), 0.0125, (1, 0.6, 0.85))
            solid(e, "eye")
            p = ico("pupil", (sx * 0.034, hc.y + 0.096, hc.z + 0.012), 0.0062, (1, 0.4, 1))
            solid(p, "dark")
            br = tube("brow", [(sx * 0.016, hc.y + 0.094, hc.z + 0.034), (sx * 0.034, hc.y + 0.096, hc.z + 0.038), (sx * 0.052, hc.y + 0.09, hc.z + 0.034)], 0.0055, 6)
            solid(br, "dark")
            out += [e, p, br]
        lips = tube("lips", [(-0.022, hc.y + 0.092, hc.z - 0.048), (0, hc.y + 0.097, hc.z - 0.046), (0.022, hc.y + 0.092, hc.z - 0.048)], 0.0075, 6)
        solid(lips, "lips")
        out.append(lips)
        return out

    def hair_pieces(self):
        """Each a separate object named hair_* / beard_* (the game shows one hair, one beard)."""
        hc = self.head_c
        pieces = {}

        def cap(name, back_drop=0.0):
            o = ico(name, (hc.x, hc.y - 0.012, hc.z + 0.012), 0.118, (0.96, 1.06, 1.0), 3)
            # Off the face: drop the verts in front of the hairline.
            me = o.data
            bm = bmesh.new()
            bm.from_mesh(me)
            kill = [v for v in bm.verts if (v.co.y - hc.y > 0.035 and v.co.z < hc.z + 0.055) or (v.co.z < hc.z - 0.05 + back_drop * (v.co.y < hc.y - 0.02)) or (abs(v.co.x) > 0.06 and v.co.z < hc.z - 0.015 and v.co.y > hc.y - 0.03)]
            bmesh.ops.delete(bm, geom=kill, context="VERTS")
            bm.to_mesh(me)
            bm.free()
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            sol = o.modifiers.new("sol", "SOLIDIFY")
            sol.thickness = 0.012
            bpy.ops.object.select_all(action="DESELECT")
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            bpy.ops.object.modifier_apply(modifier="sol")
            return o

        pieces["hair_short"] = [cap("hair_short")]
        long_back = ico("long", (0, hc.y - 0.07, hc.z - 0.1), 0.1, (1.05, 0.45, 1.5), 2)
        pieces["hair_long"] = [cap("hair_long_cap"), long_back]
        pieces["hair_bun"] = [cap("hair_bun_cap"), ico("bun", (0, hc.y - 0.12, hc.z + 0.02), 0.05, (1, 0.9, 1), 2)]
        braids = [cap("hair_braid_cap")]
        for sx in (1, -1):
            pts = [(sx * 0.085, hc.y - 0.02, hc.z - 0.04), (sx * 0.1, hc.y + 0.02, hc.z - 0.16), (sx * 0.105, hc.y + 0.05, hc.z - 0.3), (sx * 0.1, hc.y + 0.06, hc.z - 0.38)]
            braids.append(tube("braid", pts, [0.02, 0.018, 0.016, 0.01], 8))
        pieces["hair_braids"] = braids
        pieces["hair_bald"] = [ico("fringe", (0, hc.y - 0.06, hc.z - 0.03), 0.1, (1.0, 0.6, 0.45), 2)]
        if not self.female:
            beard = ico("beard_full", (0, hc.y + 0.055, hc.z - 0.085), 0.07, (0.95, 0.75, 0.9), 3)
            mo = tube("moustache", [(-0.04, hc.y + 0.088, hc.z - 0.045), (-0.012, hc.y + 0.1, hc.z - 0.032), (0.012, hc.y + 0.1, hc.z - 0.032), (0.04, hc.y + 0.088, hc.z - 0.045)], 0.009, 6)
            pieces["beard_full"] = [beard, mo]
            long_b = ico("beard_long", (0, hc.y + 0.06, hc.z - 0.13), 0.065, (0.85, 0.65, 1.6), 3)
            mo2 = tube("moustache2", [(-0.04, hc.y + 0.088, hc.z - 0.045), (0, hc.y + 0.1, hc.z - 0.03), (0.04, hc.y + 0.088, hc.z - 0.045)], 0.009, 6)
            pieces["beard_long"] = [long_b, mo2]
            pieces["beard_moustache"] = [tube("moustache3", [(-0.045, hc.y + 0.085, hc.z - 0.06), (-0.015, hc.y + 0.1, hc.z - 0.033), (0.015, hc.y + 0.1, hc.z - 0.033), (0.045, hc.y + 0.085, hc.z - 0.06)], 0.009, 6)]
        out = {}
        for name, objs in pieces.items():
            for o in objs:
                solid(o, "hair")
            o = join(objs, name) if len(objs) > 1 else objs[0]
            o.name = name
            finish(o)
            out[name] = o
        return out


# --------------------------------------------------------------------------- rig and skin

def build_rig(fig, body, others):
    arm_data = bpy.data.armatures.new("villager_rig")
    arm = bpy.data.objects.new("villager_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, tail, parent, deform in fig.bones():
        eb = arm_data.edit_bones.new(bname)
        eb.head = head
        eb.tail = tail
        eb.use_deform = deform
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def weight_rigid(obj, arm, bone):
    """Everything on one bone (hair, beards)."""
    obj.vertex_groups.clear()
    g = obj.vertex_groups.new(name=bone)
    g.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    mod = obj.modifiers.new("arm", "ARMATURE")
    mod.object = arm
    obj.parent = arm


def weight_cloth(obj, arm, fig):
    """Skirts: on the hips at the belt, more and more on each thigh lower down (the side the
    cloth is on), so the hem follows the legs. Upper parts of the dresses ride the chest."""
    obj.vertex_groups.clear()
    groups = {n: obj.vertex_groups.new(name=n) for n in ("hips", "spine", "chest", "thigh.R", "thigh.L", "shin.R", "shin.L")}
    hz = fig.hips_z
    for v in obj.data.vertices:
        z = v.co.z
        if z > 1.15:
            groups["chest"].add([v.index], 1.0, "REPLACE")
            continue
        if z > hz + 0.05:
            t = (z - hz - 0.05) / 0.1
            groups["spine"].add([v.index], min(1.0, t), "REPLACE")
            groups["hips"].add([v.index], max(0.0, 1.0 - t), "REPLACE")
            continue
        down = max(0.0, min(1.0, (hz - z) / (hz - 0.45)))
        side = max(0.0, min(1.0, 0.5 + v.co.x / 0.16))
        legs = 0.75 * down
        groups["hips"].add([v.index], 1.0 - legs, "REPLACE")
        groups["thigh.R"].add([v.index], legs * side, "REPLACE")
        groups["thigh.L"].add([v.index], legs * (1.0 - side), "REPLACE")
        if z < 0.45:
            low = max(0.0, min(1.0, (0.45 - z) / 0.3)) * 0.35
            groups["shin.R"].add([v.index], low * side, "REPLACE")
            groups["shin.L"].add([v.index], low * (1.0 - side), "REPLACE")
    mod = obj.modifiers.new("arm", "ARMATURE")
    mod.object = arm
    obj.parent = arm


# --------------------------------------------------------------------------- animation

def local_axis(arm, bname, world_axis):
    return (arm.data.bones[bname].matrix_local.to_3x3().inverted() @ world_axis).normalized()


class Anim:
    def __init__(self, arm, name):
        self.arm, self.name = arm, name
        arm.animation_data_create()
        self.action = bpy.data.actions.new(name)
        arm.animation_data.action = self.action

    def key(self, frame, poses, lift=0.0, fwd=0.0):
        for pb in self.arm.pose.bones:
            q = Quaternion()
            for axis, ang in poses.get(pb.name, []):
                if abs(ang) > 1e-5:
                    q = q @ Quaternion(local_axis(self.arm, pb.name, axis), ang)
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "root":
                # The root points up: its local Y is world Z, local Z is -world Y.
                pb.location = (0, lift, -fwd)
                pb.keyframe_insert("location", frame=frame)

    def done(self):
        track = self.arm.animation_data.nla_tracks.new()
        track.name = self.name
        track.strips.new(self.name, 1, self.action)
        self.arm.animation_data.action = None


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def sn(t, k=1.0, ph=0.0):
    return math.sin(2 * math.pi * (t * k + ph))


def base_arms(p, f):
    """Arms hanging relaxed: brought in a little from the A-pose."""
    p.setdefault("upper_arm.R", []).append((Y, 0.12))
    p.setdefault("upper_arm.L", []).append((Y, -0.12))


def legs_walk(p, t, stride=1.0):
    for side, ph in (("R", 0.0), ("L", 0.5)):
        s = sn(t, 1, ph)
        lift = max(0.0, sn(t, 1, ph - 0.18))
        p["thigh." + side] = [(X, 0.42 * stride * s + 0.05)]
        p["shin." + side] = [(X, -(0.12 + 0.95 * lift * stride))]
        p["foot." + side] = [(X, 0.25 * stride * sn(t, 1, ph + 0.12) - 0.05)]


def walk(arm, name="walk", carry=False, march=False):
    a = Anim(arm, name)
    n = 32
    for fr in range(n + 1):
        t = fr / n
        p = {}
        legs_walk(p, t, 0.9 if march else 1.0)
        p["hips"] = [(Z, 0.09 * sn(t)), (Y, 0.035 * sn(t, 1, 0.25)), (X, -0.04)]
        p["spine"] = [(Z, -0.05 * sn(t)), (X, -0.03)]
        p["chest"] = [(Z, -0.06 * sn(t)), (X, 0.02 * sn(t, 2, 0.1))]
        p["neck"] = [(Z, 0.03 * sn(t))]
        p["head"] = [(Z, 0.04 * sn(t)), (X, 0.02 * sn(t, 2, 0.3))]
        for side, ph, sx in (("R", 0.5, 1), ("L", 0.0, -1)):
            s = sn(t, 1, ph)
            p["upper_arm." + side] = [(X, 0.38 * s + 0.05), (Y, sx * 0.14)]
            p["forearm." + side] = [(X, 0.25 + 0.3 * max(0.0, s))]
            p["hand." + side] = [(X, 0.1 * sn(t, 1, ph + 0.15))]
            p["clavicle." + side] = [(X, 0.04 * s)]
        if carry:
            # Left arm up, steadying a load on the shoulder.
            p["upper_arm.L"] = [(Y, 1.55), (X, 0.55)]
            p["forearm.L"] = [(X, 1.9)]
            p["hand.L"] = [(Y, 0.4)]
            p["clavicle.L"] = [(Y, -0.15)]
            p["chest"].append((Y, 0.04))
        if march:
            # Spear sloped on the right shoulder, shield carried on the left arm.
            p["upper_arm.R"] = [(X, 0.15 + 0.06 * sn(t)), (Y, 0.15)]
            p["forearm.R"] = [(X, 1.55)]
            p["hand.R"] = [(Z, 0.2)]
            p["upper_arm.L"] = [(X, 0.4 + 0.05 * sn(t, 1, 0.5)), (Y, -0.25)]
            p["forearm.L"] = [(X, 1.35)]
            p["head"].append((X, 0.05))
        a.key(fr + 1, p, lift=0.028 * sn(t, 2, 0.25) - 0.01)
    a.done()


def idle(arm):
    a = Anim(arm, "idle")
    n = 96
    for fr in range(n + 1):
        t = fr / n
        br = sn(t, 2)
        shift = sn(t, 1)
        p = {}
        p["hips"] = [(Y, 0.04 * shift), (Z, 0.02 * shift)]
        p["spine"] = [(Y, -0.025 * shift), (X, 0.015 * br)]
        p["chest"] = [(X, -0.02 * br), (Y, -0.015 * shift)]
        p["neck"] = [(Z, 0.25 * math.sin(2 * math.pi * t) * ease(abs(math.sin(math.pi * t * 2))))]
        p["head"] = [(X, 0.04 * sn(t, 1, 0.3)), (Z, 0.12 * sn(t, 1, 0.1))]
        p["thigh.R"] = [(Y, 0.03 + 0.03 * shift), (X, 0.02)]
        p["thigh.L"] = [(Y, -0.03 + 0.03 * shift), (X, -0.02)]
        p["shin.R"] = [(X, -0.05 - 0.05 * max(0, -shift))]
        p["shin.L"] = [(X, -0.05 - 0.05 * max(0, shift))]
        p["upper_arm.R"] = [(Y, 0.13), (X, 0.03 * br + 0.04)]
        p["upper_arm.L"] = [(Y, -0.13), (X, 0.03 * br + 0.04)]
        p["forearm.R"] = [(X, 0.2)]
        p["forearm.L"] = [(X, 0.25)]
        p["hand.R"] = [(Z, 0.15)]
        p["hand.L"] = [(Z, -0.15)]
        a.key(fr + 1, p, lift=0.003 * br)
    a.done()


def swing(arm, name, pick=False):
    """Both hands on a haft: raised over the right shoulder on a slow wind-up, brought down
    hard with the body following through, a pause, and up again."""
    a = Anim(arm, name)
    n = 34
    for fr in range(n + 1):
        t = fr / n
        up = ease(t / 0.55) if t < 0.55 else (1.0 - ease((t - 0.55) / 0.13) if t < 0.68 else 0.0)
        strike = ease((t - 0.58) / 0.1) * (1.0 - ease((t - 0.8) / 0.2)) if t > 0.58 else 0.0
        p = {}
        bend = 0.35 if pick else 0.25
        p["hips"] = [(X, -0.1 * strike), (Z, -0.12 * up)]
        p["spine"] = [(X, 0.12 * up - bend * strike), (Z, -0.15 * up)]
        p["chest"] = [(X, 0.08 * up - 0.2 * strike), (Z, -0.1 * up)]
        p["head"] = [(X, -0.15 * strike + 0.1 * up)]
        arm_x = 0.7 + 2.0 * up - 0.3 * strike
        p["upper_arm.R"] = [(X, arm_x), (Y, 0.1 - 0.35 * up), (Z, 0.2)]
        p["upper_arm.L"] = [(X, arm_x - 0.15), (Y, 0.5 + 0.1 * up), (Z, -0.2)]
        p["forearm.R"] = [(X, 0.5 + 0.6 * up - 0.3 * strike)]
        p["forearm.L"] = [(X, 0.8 + 0.4 * up)]
        p["hand.R"] = [(X, -0.3 * up + 0.4 * strike)]
        p["hand.L"] = [(X, -0.2 * up + 0.3 * strike)]
        for side, sx in (("R", 1), ("L", -1)):
            p["thigh." + side] = [(X, 0.2 * strike + (0.15 if side == "L" else -0.1)), (Y, sx * 0.12)]
            p["shin." + side] = [(X, -0.3 * strike - 0.1)]
        a.key(fr + 1, p, lift=-0.06 * strike)
    a.done()


def hammer(arm):
    """Quick blows with the right hand, the left holding the work; a nod with each blow."""
    a = Anim(arm, "hammer")
    n = 18
    for fr in range(n + 1):
        t = fr / n
        up = ease(t / 0.6) if t < 0.6 else 1.0 - ease((t - 0.6) / 0.12)
        hit = 1.0 if 0.72 < t < 0.85 else 0.0
        p = {}
        p["spine"] = [(X, -0.15 - 0.04 * hit)]
        p["chest"] = [(X, -0.08), (Z, -0.08 * up)]
        p["head"] = [(X, -0.2 - 0.05 * hit)]
        p["upper_arm.R"] = [(X, 0.75 + 1.25 * up), (Y, 0.3 * up), (Z, 0.15)]
        p["forearm.R"] = [(X, 0.9 + 0.5 * up)]
        p["hand.R"] = [(X, -0.4 * up + 0.3 * hit)]
        p["upper_arm.L"] = [(X, 0.85), (Y, -0.25), (Z, -0.3)]
        p["forearm.L"] = [(X, 0.9)]
        p["thigh.R"] = [(X, -0.05), (Y, 0.08)]
        p["thigh.L"] = [(X, 0.15), (Y, -0.08)]
        p["shin.L"] = [(X, -0.15)]
        a.key(fr + 1, p)
    a.done()


def dig(arm):
    """Spade: lean in and push it down with the foot, lever, lift and throw over the side."""
    a = Anim(arm, "dig")
    n = 44
    for fr in range(n + 1):
        t = fr / n
        push = ease(t / 0.3) * (1.0 - ease((t - 0.45) / 0.15)) if t < 0.6 else 0.0
        lift = ease((t - 0.45) / 0.2) * (1.0 - ease((t - 0.72) / 0.15)) if t > 0.45 else 0.0
        throw = ease((t - 0.68) / 0.1) * (1.0 - ease((t - 0.82) / 0.15)) if t > 0.68 else 0.0
        p = {}
        p["hips"] = [(X, -0.15 * push), (Z, 0.25 * throw)]
        p["spine"] = [(X, -0.35 * push - 0.2 * lift + 0.1 * throw), (Z, 0.2 * throw)]
        p["chest"] = [(X, -0.1 * push), (Z, 0.15 * throw)]
        p["upper_arm.R"] = [(X, 0.5 + 0.35 * lift + 0.3 * throw), (Y, 0.15)]
        p["forearm.R"] = [(X, 0.9 - 0.4 * push + 0.3 * lift)]
        p["upper_arm.L"] = [(X, 0.9 + 0.5 * lift), (Y, -0.15), (Z, 0.25)]
        p["forearm.L"] = [(X, 1.1 - 0.2 * push)]
        p["thigh.R"] = [(X, 0.35 * push + 0.1)]
        p["shin.R"] = [(X, -0.5 * push - 0.05)]
        p["foot.R"] = [(X, 0.2 * push)]
        p["thigh.L"] = [(X, -0.1 + 0.25 * push)]
        p["shin.L"] = [(X, -0.35 * push - 0.1)]
        a.key(fr + 1, p, lift=-0.08 * push)
    a.done()


def reap(arm):
    """Bent over, the sickle sweeping through the stalks, the left hand gathering."""
    a = Anim(arm, "reap")
    n = 30
    for fr in range(n + 1):
        t = fr / n
        sw = sn(t)
        p = {}
        p["hips"] = [(X, -0.25), (Z, 0.1 * sw)]
        p["spine"] = [(X, -0.35), (Z, 0.1 * sw)]
        p["chest"] = [(X, -0.15), (Z, 0.12 * sw)]
        p["head"] = [(X, 0.3)]
        p["upper_arm.R"] = [(X, 0.9), (Z, 0.5 * sw), (Y, 0.15 + 0.2 * sw)]
        p["forearm.R"] = [(X, 0.4 + 0.2 * max(0, sw))]
        p["upper_arm.L"] = [(X, 0.95), (Z, -0.2 + 0.2 * sw), (Y, -0.15)]
        p["forearm.L"] = [(X, 0.6)]
        p["hand.L"] = [(X, 0.4)]
        for side in ("R", "L"):
            p["thigh." + side] = [(X, 0.45), (Y, 0.1 if side == "R" else -0.1)]
            p["shin." + side] = [(X, -0.55)]
            p["foot." + side] = [(X, 0.12)]
        a.key(fr + 1, p, lift=-0.1)
    a.done()


def net(arm):
    """Hauling a net in hand over hand, leaning back into each pull."""
    a = Anim(arm, "net")
    n = 30
    for fr in range(n + 1):
        t = fr / n
        s = sn(t)
        p = {}
        p["hips"] = [(X, 0.08 + 0.05 * s)]
        p["spine"] = [(X, 0.1 + 0.06 * s), (Z, 0.08 * s)]
        p["head"] = [(X, -0.15)]
        p["upper_arm.R"] = [(X, 1.1 + 0.55 * s), (Y, 0.1)]
        p["upper_arm.L"] = [(X, 1.1 - 0.55 * s), (Y, -0.1)]
        p["forearm.R"] = [(X, 0.5 + 0.5 * max(0, -s))]
        p["forearm.L"] = [(X, 0.5 + 0.5 * max(0, s))]
        p["thigh.R"] = [(X, 0.3), (Y, 0.08)]
        p["thigh.L"] = [(X, -0.2), (Y, -0.08)]
        p["shin.R"] = [(X, -0.25)]
        a.key(fr + 1, p, lift=-0.02)
    a.done()


def stir(arm):
    """Both hands on a paddle, stirring round and round in a big pot or vat."""
    a = Anim(arm, "stir")
    n = 40
    for fr in range(n + 1):
        t = fr / n
        c, s = math.cos(2 * math.pi * t), math.sin(2 * math.pi * t)
        p = {}
        p["hips"] = [(Z, 0.06 * s)]
        p["spine"] = [(X, -0.2 + 0.05 * c), (Z, 0.1 * s)]
        p["chest"] = [(Z, 0.08 * s)]
        p["head"] = [(X, -0.25)]
        p["upper_arm.R"] = [(X, 1.0 + 0.2 * c), (Z, 0.25 * s), (Y, 0.15)]
        p["upper_arm.L"] = [(X, 1.15 + 0.2 * c), (Z, 0.25 * s), (Y, -0.25)]
        p["forearm.R"] = [(X, 0.7 - 0.2 * c)]
        p["forearm.L"] = [(X, 0.9 - 0.2 * c)]
        p["thigh.R"] = [(X, 0.1)]
        p["thigh.L"] = [(X, 0.05)]
        p["shin.R"] = [(X, -0.15)]
        a.key(fr + 1, p)
    a.done()


def stance(arm, name, brace):
    """Soldiers standing: on guard (spear upright at the side, shield on the arm) or braced in
    the shield wall (crouched, shield up, spear levelled over it)."""
    a = Anim(arm, name)
    n = 60
    for fr in range(n + 1):
        t = fr / n
        br = sn(t, 2)
        p = {}
        if brace:
            p["hips"] = [(X, -0.2)]
            p["spine"] = [(X, -0.12)]
            p["chest"] = [(X, 0.05)]
            p["head"] = [(X, 0.2)]
            p["thigh.R"] = [(X, -0.15), (Y, 0.15)]
            p["thigh.L"] = [(X, 0.6), (Y, -0.1)]
            p["shin.R"] = [(X, -0.45)]
            p["shin.L"] = [(X, -0.75)]
            p["upper_arm.L"] = [(X, 1.35), (Y, -0.1), (Z, -0.35)]
            p["forearm.L"] = [(X, 0.5)]
            p["upper_arm.R"] = [(X, 1.55 + 0.03 * br), (Y, 0.35)]
            p["forearm.R"] = [(X, 0.25)]
            lift = -0.14
        else:
            p["hips"] = [(Y, 0.03 * sn(t))]
            p["chest"] = [(X, 0.015 * br)]
            p["head"] = [(Z, 0.1 * sn(t, 1, 0.2))]
            p["thigh.R"] = [(Y, 0.1)]
            p["thigh.L"] = [(Y, -0.1)]
            p["upper_arm.R"] = [(X, 0.15), (Y, 0.2)]
            p["forearm.R"] = [(X, 1.45)]
            p["upper_arm.L"] = [(X, 0.45), (Y, -0.25)]
            p["forearm.L"] = [(X, 1.3)]
            lift = 0.0
        a.key(fr + 1, p, lift=lift + 0.003 * br)
    a.done()


def animate(arm):
    bpy.context.scene.render.fps = FPS
    idle(arm)
    walk(arm)
    walk(arm, "walk_carry", carry=True)
    walk(arm, "march", march=True)
    swing(arm, "chop")
    swing(arm, "pick", pick=True)
    hammer(arm)
    dig(arm)
    reap(arm)
    net(arm)
    stir(arm)
    stance(arm, "guard", False)
    stance(arm, "brace", True)


# --------------------------------------------------------------------------- export

def build(female):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    fig = Figure(female)
    body = fig.flesh()
    cloth = fig.clothes()
    face = fig.face()
    hair = fig.hair_pieces()
    arm = build_rig(fig, body, [])
    # The face rides the head; clothes follow hips, thighs and chest.
    face_o = join(face, "face")
    finish(face_o)
    weight_rigid(face_o, arm, "head")
    for o in cloth:
        finish(o)
    cloth_o = join(cloth, "clothes")
    weight_cloth(cloth_o, arm, fig)
    for name, o in hair.items():
        weight_rigid(o, arm, "head")
    animate(arm)
    name = "villager_f" if female else "villager_m"
    bpy.ops.object.select_all(action="DESELECT")
    for o in [body, face_o, cloth_o, arm] + list(hair.values()):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_normals=True,
                              export_colors=True, export_materials="NONE")
    print("exported", path, len(body.data.polygons), "body faces")


def main():
    os.makedirs(OUT, exist_ok=True)
    build(False)
    build(True)


main()
