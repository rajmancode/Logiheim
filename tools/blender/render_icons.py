"""Renders a realistic picture of every resource for the map icons.

Run headless (Blender 4.x), from the project root:
    blender -b --python tools/blender/render_icons.py -- <out_dir>

Each resource is shown by its own game model (props from assets/models/resources, animals
from assets/models/animals, trees from assets/models/vegetation) or a small model made here
(fish, wheat sheaf, cave mouth), lit by a sunny sky in Cycles and rendered with a
transparent background to <out_dir>/<key>.png. Props get the photo-scanned terrain textures
(rock, wood, soil...) under their painted colours, with bump from the texture's height, so they
look like the real thing. tools/make_resource_icons.py then puts each picture in its badge.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(ROOT, "build", "icon_renders")
RES = os.path.join(ROOT, "assets", "models", "resources")
ANI = os.path.join(ROOT, "assets", "models", "animals")
VEG = os.path.join(ROOT, "assets", "models", "vegetation")
TEX = os.path.join(ROOT, "assets", "textures", "terrain")

# key -> (list of (glb path, offset, scale, yaw), texture for props, view yaw, view pitch)
R = lambda n: os.path.join(RES, n + ".glb")
A = lambda n: os.path.join(ANI, n + ".glb")
V = lambda n: os.path.join(VEG, n + ".glb")
ICONS = {
    "timber": ([(V("conifer_a"), (-1.2, 1.6, 0), 9.0, 0), (V("conifer_b"), (2.0, 2.2, 0), 7.0, 1), (R("log_pile"), (0, -1.5, 0), 0.8, 0.3)], "wood", 30, 18),
    "oak": ([(V("broadleaf_b"), (0, 0, 0), 9.0, 0)], "bark", 30, 12),
    "tar": ([(R("tar_kiln"), (0, 0, 0), 1.0, 0)], "wood", 35, 20),
    "stone": ([(R("quarry"), (0, 0, 0), 1.0, 0)], "rock", 35, 28),
    "soapstone": ([(R("outcrop_soapstone"), (0, 0, 0), 1.0, 0)], "rock_mossy", 35, 25),
    "iron": ([(R("outcrop_iron"), (0, 0, 0), 1.0, 0)], "rock", 35, 25),
    "bog_iron": ([(R("bog"), (0, 0, 0), 1.0, 0)], "mud", 35, 35),
    "coal": ([(R("outcrop_coal"), (0, 0, 0), 1.0, 0)], "coal", 35, 25),
    "gold": ([(R("gold_gravel"), (0, 0, 0), 1.0, 0)], "pebbles", 35, 35),
    "silver": ([(R("outcrop_silver"), (0, 0, 0), 1.0, 0)], "rock", 35, 25),
    "gems": ([(R("crystals"), (0, 0, 0), 1.0, 0)], "rock", 35, 18),
    "fish": ("@fish", None, 25, 22),
    "whales": ([(A("whale"), (0, 0, 0), 1.0, 0)], None, 60, 15),
    "seals": ([(A("seal"), (0, 0, 0), 1.0, 0)], None, 50, 15),
    "farmland": ("@sheaf", None, 30, 12),
    "wool": ([(A("sheep"), (0, 0, 0), 1.0, 0)], None, 55, 12),
    "horses": ([(A("horse"), (0, 0, 0), 1.0, 0)], None, 55, 10),
    "game": ([(A("deer"), (0, 0, 0), 1.0, 0)], None, 55, 10),
    "furs": ([(A("fox"), (0, 0, 0), 1.0, 0)], None, 55, 12),
    "clay": ([(R("clay_pit"), (0, 0, 0), 1.0, 0)], "mud", 35, 35),
    "salt": ([(R("salt_pans"), (0, 0, 0), 1.0, 0)], "sand", 35, 35),
    "peat": ([(R("peat_stack"), (0, 0, 0), 1.0, 0)], "soil", 35, 22),
    "amber": ([(R("amber"), (0, 0, 0), 1.0, 0)], "sand", 35, 30),
    "reeds": ([(R("reeds"), (0, 0, 0), 1.0, 0)], "reeds", 35, 15),
    "lake_ore": ([(R("bog"), (0, 0, 0), 1.0, 0)], "mud", 35, 35),
    "cave": ("@cave", None, 0, 8),
}
# Props built from mixed materials: which texture goes under the wood-coloured parts.
WOOD_PROPS = {"log_pile", "tar_kiln", "peat_stack"}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 384
    sc.view_settings.view_transform = "Filmic"
    sc.view_settings.look = "Medium High Contrast"
    sc.view_settings.exposure = -0.6
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(40)
    sky.sun_rotation = math.radians(200)
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.18
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.6
    sun.data.angle = math.radians(4)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 0.5
    fill.rotation_euler = (math.radians(70), 0, math.radians(150))
    sc.collection.objects.link(fill)


def image(name):
    path = os.path.join(TEX, name + "_albedo.webp")
    return bpy.data.images.load(path, check_existing=True) if os.path.exists(path) else None


def textured(mat, tex_name, glint=False, scale=0.6):
    """Base colour = painted colour (vertex 'Col') x photo texture (box-projected), with bump."""
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    img = image(tex_name)
    col = vc.outputs["Color"]
    if img is not None:
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.projection = "BOX"
        t.projection_blend = 0.3
        nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
        # Detail in luminance only, so the painted colour stays.
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        nt.links.new(t.outputs["Color"], bw.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY_ADD"
        nt.links.new(bw.outputs[0], mul.inputs[0])
        mul.inputs[1].default_value = 1.6
        mul.inputs[2].default_value = 0.25
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        nt.links.new(vc.outputs["Color"], mix.inputs[6])
        comb = nt.nodes.new("ShaderNodeCombineColor")
        for k in range(3):
            nt.links.new(mul.outputs[0], comb.inputs[k])
        nt.links.new(comb.outputs[0], mix.inputs[7])
        col = mix.outputs[2]
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.5
        nt.links.new(t.outputs["Alpha"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.25 if glint else 0.8
    bsdf.inputs["Metallic"].default_value = 0.75 if glint else 0.0


def _darken(mat, k):
    """Multiplies the base colour by k (a grey level, or an (r, g, b) tint)."""
    k = (k, k, k) if isinstance(k, (int, float)) else k
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    link = bsdf.inputs["Base Color"].links[0]
    src = link.from_socket
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    mul.inputs[7].default_value = (k[0], k[1], k[2], 1)
    nt.links.new(src, mul.inputs[6])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])


def plain(mat, rgb, rough=0.7, metal=0.0, tex=None):
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if rough >= 1.0:
        for name in ("Specular IOR Level", "Specular"):
            if name in bsdf.inputs:
                bsdf.inputs[name].default_value = 0.0


def import_glb(path, offset, scale, yaw, tex):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for o in roots:
        o.location = Vector(offset) + o.location
        o.scale = o.scale * scale
        o.rotation_euler.z += yaw
    name = os.path.splitext(os.path.basename(path))[0]
    for o in new:
        if o.type != "MESH":
            continue
        if o.name.startswith("Icosphere"):
            o.hide_render = True
            continue
        for slot in o.material_slots:
            m = slot.material
            if m is None:
                continue
            if m.name.startswith("Body") and tex == "coal":
                textured(m, "rock_dark")
                m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0, 0, 0, 1)
                _darken(m, 0.12)
            elif m.name.startswith("Body") and tex:
                textured(m, "wood" if name in WOOD_PROPS and tex != "wood" else tex)
            elif m.name.startswith("Glint"):
                textured(m, "rock", glint=True)
            elif m.name.startswith("Bark"):
                textured(m, "bark", scale=4.0)
                _darken(m, (0.42, 0.3, 0.2))
            elif m.name.startswith("Leaves"):
                plain(m, (0.12, 0.3, 0.07), 0.6)
                # leaves: keep vertex-colour AO
                nt = m.node_tree
                vc = nt.nodes.new("ShaderNodeVertexColor")
                vc.layer_name = "Col"
                mix = nt.nodes.new("ShaderNodeMix")
                mix.data_type = "RGBA"
                mix.blend_type = "MULTIPLY"
                mix.inputs[0].default_value = 1.0
                mix.inputs[6].default_value = (0.045, 0.13, 0.03, 1)
                nt.links.new(vc.outputs["Color"], mix.inputs[7])
                nt.links.new(mix.outputs[2], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return new


def make_fish():
    for k, (x, y, z, s) in enumerate(((0, 0, 0.3, 1.0), (0.4, 1.0, 0.0, 0.8))):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1)
        body = bpy.context.object
        body.scale = (1.0 * s, 0.32 * s, 0.24 * s)
        body.location = (x, y, z)
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.42 * s, depth=0.6 * s)
        tail = bpy.context.object
        tail.rotation_euler = (0, math.radians(90), 0)
        tail.scale = (0.25, 1.0, 1.0)
        tail.location = (x - 1.1 * s, y, z)
        mat = bpy.data.materials.new("fish%d" % k)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        coord = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["Generated"], sep.inputs[0])
        nt.links.new(sep.outputs["Z"], ramp.inputs[0])
        ramp.color_ramp.elements[0].color = (0.55, 0.57, 0.55, 1)
        ramp.color_ramp.elements[1].color = (0.05, 0.12, 0.16, 1)
        ramp.color_ramp.elements[1].position = 0.55
        nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = 0.35
        bsdf.inputs["Roughness"].default_value = 0.35
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.3 * s, depth=0.35 * s)
        fin = bpy.context.object
        fin.scale = (1.0, 0.12, 1.0)
        fin.location = (x - 0.05 * s, y, z + 0.28 * s)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.06 * s, location=(x + 0.72 * s, y - 0.2 * s, z + 0.06 * s))
        eye = bpy.context.object
        dark = bpy.data.materials.new("eye%d" % k)
        plain(dark, (0.01, 0.01, 0.01), 0.2)
        eye.data.materials.append(dark)
        for o in (body, tail, fin):
            o.data.materials.append(mat)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.shade_smooth()


def make_sheaf():
    rng = random.Random(3)
    gold = bpy.data.materials.new("straw")
    plain(gold, (0.55, 0.36, 0.09), 0.7)
    # A tied sheaf: stalks cross at the band and fan out above and below it.
    band = Vector((0, 0, 1.0))
    for k in range(80):
        a = rng.uniform(0, math.tau)
        lean = rng.uniform(0.1, 0.42)
        d = Vector((math.cos(a) * lean, math.sin(a) * lean, 1.0)).normalized()
        h = rng.uniform(2.2, 2.6)
        mid = band + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, rng.uniform(0.0, 0.25)))
        bpy.ops.mesh.primitive_cylinder_add(vertices=5, radius=0.022, depth=h)
        st = bpy.context.object
        st.rotation_mode = "QUATERNION"
        st.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
        st.location = mid
        st.data.materials.append(gold)
        top = mid + d * (h / 2)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.07, location=top + d * 0.12)
        ear = bpy.context.object
        ear.scale = (1, 1, 2.6)
        ear.rotation_mode = "QUATERNION"
        ear.rotation_quaternion = st.rotation_quaternion
        ear.data.materials.append(gold)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.05, location=(0, 0, 1.0))
    bpy.context.object.data.materials.append(gold)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1.6, depth=0.1, location=(0, 0, -0.05))
    soil = bpy.data.materials.new("soil")
    soil.use_nodes = True
    textured(soil, "soil", scale=0.8)
    bpy.context.object.data.materials.append(soil)


def make_cave():
    rng = random.Random(5)
    rock = bpy.data.materials.new("rock")
    textured(rock, "rock_cliff", scale=0.5)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import bmesh
    from rock_shapes import rock_bmesh
    for k in range(9):
        a = math.pi * k / 8
        bm = rock_bmesh(40 + k, rng.uniform(0.6, 0.9), facets=8, radius=0.5, subdiv=4)
        me = bpy.data.meshes.new("r")
        bm.to_mesh(me)
        o = bpy.data.objects.new("r", me)
        bpy.context.scene.collection.objects.link(o)
        s = rng.uniform(1.3, 1.9)
        o.scale = (s, s, s)
        o.location = (math.cos(a) * 1.7, 0, math.sin(a) * 1.8 - 0.2)
        o.rotation_euler = (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3))
        col = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for d in col.data:
            d.color = (0.55, 0.53, 0.5, 1)
        me.materials.append(rock)
        for p in me.polygons:
            p.use_smooth = True
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.5, location=(0, 0.6, 0.2))
    hole = bpy.context.object
    hole.scale = (1.0, 0.6, 1.15)
    dark = bpy.data.materials.new("dark")
    plain(dark, (0.005, 0.004, 0.004), 1.0)
    hole.data.materials.append(dark)


def frame(view_yaw, pitch):
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in sc.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    centre = (lo + hi) / 2
    radius = (hi - lo).length / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 60
    d = radius / math.tan(cam.data.angle / 2) * 1.02
    yaw = math.radians(-90 + view_yaw)
    p = math.radians(pitch)
    cam.location = centre + Vector((math.cos(yaw) * math.cos(p), math.sin(yaw) * math.cos(p), math.sin(p))) * d
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()


def main():
    os.makedirs(OUT, exist_ok=True)
    only = os.environ.get("ICONS", "")
    for key, (parts, tex, view_yaw, pitch) in ICONS.items():
        if only and key not in only.split(","):
            continue
        reset()
        if parts == "@fish":
            make_fish()
        elif parts == "@sheaf":
            make_sheaf()
        elif parts == "@cave":
            make_cave()
        else:
            for path, offset, scale, yaw in parts:
                import_glb(path, offset, scale, yaw, tex)
        frame(view_yaw, pitch)
        bpy.context.scene.render.filepath = os.path.join(OUT, key + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", key)


main()
