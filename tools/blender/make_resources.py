"""Builds the natural-resource props (ore outcrops, quarry, kiln, animals...) and exports .glb.

Run headless (Blender 4.x):
    blender -b --python tools/blender/make_resources.py -- assets/models/resources

Models are in real metres (Z up in Blender, Y up after export). Colours are baked into vertex
colours (COLOR_0) with a little ambient occlusion. Faces that should sparkle (gold, silver,
gems, amber) use a material named "Glint"; everything else uses "Body".
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models/resources"
BODY, GLINT = 0, 1


# --------------------------------------------------------------------------- helpers

class Builder:
    """Collects faces with a colour each, then becomes one mesh object."""

    def __init__(self):
        self.bm = bmesh.new()
        self.colors = {}  # face -> (r, g, b)

    def add_faces(self, faces, color, mat=BODY):
        for f in faces:
            f.material_index = mat
            self.colors[f] = color

    def merge(self, other_bm, color, mat=BODY, transform=None):
        vmap = {}
        for v in other_bm.verts:
            co = v.co.copy()
            if transform:
                co = transform(co)
            vmap[v] = self.bm.verts.new(co)
        faces = []
        for f in other_bm.faces:
            faces.append(self.bm.faces.new([vmap[v] for v in f.verts]))
        other_bm.free()
        if callable(color):
            for f in faces:
                f.material_index = mat
                c = f.calc_center_median()
                self.colors[f] = color(c)
        else:
            self.add_faces(faces, color, mat)
        return faces

    def finish(self, name, ao_height=1.0, smooth=True):
        self.bm.normal_update()
        mesh = bpy.data.meshes.new(name)
        # Remember colours by face index before converting.
        self.bm.faces.index_update()
        face_colors = {f.index: c for f, c in self.colors.items()}
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mname in ("Body", "Glint"):
            mesh.materials.append(bpy.data.materials.get(mname) or bpy.data.materials.new(mname))
        attr = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for poly in mesh.polygons:
            base = face_colors.get(poly.index, (0.5, 0.5, 0.5))
            for li in poly.loop_indices:
                v = mesh.vertices[mesh.loops[li].vertex_index]
                ao = 0.55 + 0.45 * min(max(v.co.z / ao_height, 0.0), 1.0)
                attr.data[li].color = (base[0] * ao, base[1] * ao, base[2] * ao, 1.0)
            poly.use_smooth = smooth
        mesh.color_attributes.active_color = attr
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def ico(radius, subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    return bm


def cube(sx, sy, sz):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    return bm


def cyl(r1, r2, depth, segs=8):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    return bm


def noisy(bm, amount, freq, seed):
    s = Vector((seed * 3.1, seed * 7.3, seed * 1.7))
    for v in bm.verts:
        d = v.co.normalized() if v.co.length > 0 else Vector((0, 0, 1))
        v.co += d * noise.noise(v.co * freq + s) * amount
    return bm


def at(offset, rot_z=0.0, scale=(1, 1, 1), tilt=None):
    """Transform: scale, optional tilt (axis, angle), rotate about Z, then move."""
    cz, sz = math.cos(rot_z), math.sin(rot_z)

    def f(co):
        co = Vector((co.x * scale[0], co.y * scale[1], co.z * scale[2]))
        if tilt:
            axis, ang = tilt
            co.rotate(__import__("mathutils").Matrix.Rotation(ang, 3, axis))
        co = Vector((co.x * cz - co.y * sz, co.x * sz + co.y * cz, co.z))
        return co + Vector(offset)
    return f


def export(obj, name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_colors=True)
    print("exported", path)


# --------------------------------------------------------------------------- props

BROWN_WOOD = (0.36, 0.24, 0.14)
LOG_END = (0.72, 0.56, 0.36)
ROCK = (0.46, 0.45, 0.43)
EARTH = (0.26, 0.19, 0.12)


def log_pile(seed=1):
    rng = random.Random(seed)
    b = Builder()
    rows = [5, 4, 3, 2]
    for r, count in enumerate(rows):
        for k in range(count):
            y = (k - (count - 1) / 2) * 0.44
            z = 0.22 + r * 0.38
            length = rng.uniform(3.6, 4.4)
            log = cyl(0.21, 0.2, length, 9)
            # Logs lie along X; colour ends lighter.
            faces = b.merge(log, BROWN_WOOD, BODY, at((rng.uniform(-0.2, 0.2), y, z), 0.0, (1, 1, 1),
                                                         (Vector((0, 1, 0)), math.pi / 2)))
            for f in faces:
                if abs(f.normal.x) > 0.9:
                    b.colors[f] = LOG_END
    for k in range(3):
        a = rng.uniform(0, math.tau)
        stump = cyl(0.3, 0.27, 0.5, 9)
        faces = b.merge(stump, BROWN_WOOD, BODY, at((math.cos(a) * 4.0, math.sin(a) * 3.0, 0.2)))
        for f in faces:
            if f.normal.z > 0.9:
                b.colors[f] = LOG_END
    return b.finish("log_pile", 1.6)


def tar_kiln(seed=2):
    rng = random.Random(seed)
    b = Builder()
    mound = noisy(ico(3.0, 3), 0.25, 0.8, seed)
    b.merge(mound, lambda c: (0.17, 0.13, 0.1) if c.z > 0.9 else EARTH, BODY, at((0, 0, -0.6), 0, (1.2, 1.0, 0.55)))
    # Dark tar pit at the foot, and a stack of split pine beside it.
    pit = cyl(1.0, 1.0, 0.1, 12)
    b.merge(pit, (0.03, 0.025, 0.02), GLINT, at((3.7, 0, 0.02)))
    for k in range(6):
        log = cyl(0.12, 0.12, 2.2, 6)
        b.merge(log, BROWN_WOOD, BODY, at((-3.8, (k % 3 - 1) * 0.26, 0.13 + (k // 3) * 0.24), 0, (1, 1, 1),
                                         (Vector((0, 1, 0)), math.pi / 2)))
    return b.finish("tar_kiln", 1.6)


def quarry(seed=3):
    rng = random.Random(seed)
    b = Builder()
    for k in range(9):
        sx, sy, sz = rng.uniform(0.9, 1.6), rng.uniform(0.7, 1.1), rng.uniform(0.5, 0.8)
        x = rng.uniform(-3, 3)
        y = rng.uniform(-2, 2)
        z = sz / 2 if k < 6 else sz * 1.5
        shade = rng.uniform(0.85, 1.1)
        b.merge(cube(sx, sy, sz), tuple(c * shade for c in (0.62, 0.6, 0.56)), BODY,
                at((x, y, z), rng.uniform(-0.3, 0.3)))
    # Rubble.
    for k in range(10):
        b.merge(noisy(ico(rng.uniform(0.15, 0.3), 1), 0.05, 3, k), (0.55, 0.53, 0.5), BODY,
                at((rng.uniform(-4, 4), rng.uniform(-3, 3), 0.05)))
    return b.finish("quarry", 2.0, smooth=False)


def outcrop(name, vein, glint, seed):
    """Weathered rock with coloured mineral veins."""
    rng = random.Random(seed)
    b = Builder()
    s = Vector((seed * 5.3, seed * 2.9, seed * 8.1))

    def color(c):
        v = noise.noise(Vector((c.x * 0.9, c.y * 0.9, c.z * 2.6)) + s)
        return vein if v > 0.22 else ROCK
    for k in range(3):
        rock = noisy(ico(1.0, 3), 0.25, 1.2, seed + k)
        sc = rng.uniform(1.0, 1.8)
        faces = b.merge(rock, color, BODY, at((rng.uniform(-1.6, 1.6), rng.uniform(-1.2, 1.2), -0.2), rng.uniform(0, 6),
                                             (sc * 1.3, sc, sc * rng.uniform(0.7, 1.1))))
        if glint:
            for f in faces:
                if b.colors[f] == vein:
                    f.material_index = GLINT
    return b.finish(name, 2.0, smooth=False)


def crystals(seed=9):
    rng = random.Random(seed)
    b = Builder()
    b.merge(noisy(ico(1.2, 2), 0.2, 1.2, seed), ROCK, BODY, at((0, 0, -0.4), 0, (1.3, 1.1, 0.6)))
    for k in range(9):
        h = rng.uniform(0.8, 2.0)
        prism = cyl(0.22, 0.0, h, 6)
        hue = rng.choice([(0.45, 0.2, 0.75), (0.25, 0.45, 0.85), (0.7, 0.2, 0.45)])
        b.merge(prism, hue, GLINT, at((rng.uniform(-0.8, 0.8), rng.uniform(-0.6, 0.6), 0.3 + h / 2), rng.uniform(0, 6),
                                     (1, 1, 1), (Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized(),
                                                 rng.uniform(0.0, 0.5))))
    return b.finish("crystals", 2.0, smooth=False)


def gold_gravel(seed=10):
    rng = random.Random(seed)
    b = Builder()
    for k in range(70):
        r = rng.uniform(0.08, 0.22)
        gold = rng.random() < 0.18
        col = (0.9, 0.68, 0.18) if gold else rng.choice([(0.5, 0.46, 0.4), (0.42, 0.38, 0.33), (0.58, 0.53, 0.46)])
        b.merge(noisy(ico(r, 1), r * 0.25, 4, k), col, GLINT if gold else BODY,
                at((rng.gauss(0, 1.4), rng.gauss(0, 0.8), r * 0.4), 0, (1.2, 1, 0.7)))
    # A gold pan.
    b.merge(cyl(0.4, 0.28, 0.1, 14), (0.3, 0.28, 0.26), BODY, at((1.8, 0.6, 0.05)))
    return b.finish("gold_gravel", 0.4)


def amber(seed=11):
    rng = random.Random(seed)
    b = Builder()
    for k in range(14):
        r = rng.uniform(0.07, 0.16)
        b.merge(noisy(ico(r, 1), r * 0.2, 4, k), (0.95, 0.52, 0.08), GLINT, at((rng.gauss(0, 1.0), rng.gauss(0, 1.0), r * 0.5)))
    # Driftwood.
    b.merge(cyl(0.12, 0.08, 2.4, 6), (0.6, 0.55, 0.47), BODY, at((0.4, -1.2, 0.1), 0.4, (1, 1, 1), (Vector((0, 1, 0)), math.pi / 2)))
    return b.finish("amber", 0.3)


def bog(seed=12):
    rng = random.Random(seed)
    b = Builder()
    for k in range(4):
        r = rng.uniform(0.8, 1.6)
        b.merge(cyl(r, r, 0.04, 14), (0.42, 0.2, 0.06), GLINT, at((rng.uniform(-2.5, 2.5), rng.uniform(-2, 2), 0.02), 0, (1.3, 1, 1)))
    for k in range(14):
        h = rng.uniform(0.8, 1.6)
        b.merge(cyl(0.05, 0.0, h, 5), rng.choice([(0.4, 0.42, 0.2), (0.5, 0.45, 0.25)]), BODY,
                at((rng.uniform(-3, 3), rng.uniform(-2.5, 2.5), h / 2), 0, (1, 1, 1),
                   (Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized(), rng.uniform(0, 0.25))))
    return b.finish("bog", 1.5)


def peat_stack(seed=13):
    rng = random.Random(seed)
    b = Builder()
    for row in range(3):
        for k in range(6):
            for lvl in range(2 if k % 2 == 0 else 3):
                shade = rng.uniform(0.8, 1.15)
                b.merge(cube(0.45, 0.25, 0.2), (0.2 * shade, 0.13 * shade, 0.08 * shade), BODY,
                        at((k * 0.5 - 1.25, row * 1.4 - 1.4, 0.1 + lvl * 0.2), rng.uniform(-0.15, 0.15)))
    # The cut face of the bog.
    b.merge(cube(4.0, 0.3, 0.5), (0.15, 0.1, 0.06), BODY, at((0, 2.4, 0.0)))
    return b.finish("peat_stack", 0.8, smooth=False)


def clay_pit(seed=14):
    rng = random.Random(seed)
    b = Builder()
    b.merge(cyl(2.8, 2.4, 0.15, 16), (0.62, 0.32, 0.18), BODY, at((0, 0, 0.0), 0, (1.3, 1, 1)))
    for k in range(5):
        r = rng.uniform(0.22, 0.32)
        b.merge(cyl(r, r * 0.8, r * 2.2, 10), (0.7, 0.4, 0.24), BODY, at((3.6 + (k % 3) * 0.6, (k // 3) * 0.7 - 0.3, r * 1.1)))
    for k in range(8):
        b.merge(cube(0.4, 0.2, 0.12), (0.66, 0.36, 0.2), BODY, at((-3.5 + (k % 4) * 0.42, -1.0 + (k // 4) * 0.22, 0.06 + (k // 4) * 0.12)))
    return b.finish("clay_pit", 0.6, smooth=False)


def salt_pans(seed=15):
    rng = random.Random(seed)
    b = Builder()
    for k in range(4):
        x = (k % 2) * 3.2 - 1.6
        y = (k // 2) * 2.6 - 1.3
        b.merge(cube(2.8, 2.2, 0.12), (0.45, 0.4, 0.34), BODY, at((x, y, 0.06)))
        b.merge(cube(2.5, 1.9, 0.02), (0.93, 0.93, 0.9), GLINT, at((x, y, 0.13)))
    for k in range(3):
        b.merge(cyl(0.5, 0.0, 0.7, 10), (0.95, 0.95, 0.92), BODY, at((4.0, k * 1.2 - 1.2, 0.35)))
    return b.finish("salt_pans", 0.6, smooth=False)


def whale(seed=16):
    b = Builder()
    dark = (0.16, 0.18, 0.2)
    # Origin is the waterline: the back breaks the surface, the rest is under water.
    b.merge(noisy(ico(1.0, 3), 0.03, 2, seed), dark, BODY, at((0, 0, -0.6), 0, (7.0, 2.0, 1.6)))
    b.merge(noisy(ico(0.5, 2), 0.02, 2, seed), dark, BODY, at((6.6, 0, 0.1), 0, (1.0, 1.0, 0.25)))
    fluke = cube(0.8, 3.0, 0.12)
    b.merge(fluke, dark, BODY, at((8.2, 0, 1.0), 0, (1, 1, 1), (Vector((0, 1, 0)), -0.5)))
    return b.finish("whale", 2.0)


def seal(name, seed, walrus=False):
    rng = random.Random(seed)
    b = Builder()
    col = (0.32, 0.27, 0.22) if walrus else (0.42, 0.42, 0.4)
    length = 3.0 if walrus else 1.7
    b.merge(noisy(ico(1.0, 2), 0.04, 2, seed), col, BODY, at((0, 0, length * 0.18), 0, (length * 0.5, length * 0.22, length * 0.18)))
    b.merge(ico(length * 0.11, 2), col, BODY, at((length * 0.5, 0, length * 0.3)))
    if walrus:
        for s in (-1, 1):
            b.merge(cyl(0.04, 0.01, 0.6, 6), (0.95, 0.92, 0.82), BODY, at((length * 0.6, s * 0.1, 0.6), 0, (1, 1, 1), (Vector((0, 1, 0)), 0.3)))
    return b.finish(name, length * 0.4)


def quadruped(name, body_col, leg_len, body_len, body_h, neck=0.5, head=0.25, wool=False, antlers=0.0, dark_head=False, seed=0):
    rng = random.Random(seed)
    b = Builder()
    torso_z = leg_len + body_h * 0.5
    torso = noisy(ico(1.0, 3 if wool else 2), 0.12 if wool else 0.02, 4.0, seed)
    b.merge(torso, body_col, BODY, at((0, 0, torso_z), 0, (body_len * 0.5, body_h * 0.42, body_h * 0.5)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.merge(cyl(0.05 * body_h * 3, 0.035 * body_h * 3, leg_len, 6), (0.12, 0.1, 0.08) if wool else body_col, BODY,
                    at((sx * body_len * 0.32, sy * body_h * 0.22, leg_len / 2)))
    head_col = (0.1, 0.09, 0.08) if dark_head else body_col
    nx = body_len * 0.5
    b.merge(cyl(0.09 * body_h * 2, 0.07 * body_h * 2, neck, 6), body_col, BODY,
            at((nx + neck * 0.25, 0, torso_z + neck * 0.4), 0, (1, 1, 1), (Vector((0, 1, 0)), 0.6)))
    hx, hz = nx + neck * 0.55, torso_z + neck * 0.8
    b.merge(ico(1.0, 2), head_col, BODY, at((hx, 0, hz), 0, (head * 1.4, head * 0.6, head * 0.6)))
    if antlers > 0:
        for s in (-1, 1):
            for k in range(3):
                b.merge(cyl(0.025, 0.01, antlers * (0.6 + 0.2 * k), 5), (0.55, 0.47, 0.36), BODY,
                        at((hx - 0.05 + k * 0.08, s * (0.1 + k * 0.06), hz + head * 0.4 + antlers * 0.3), 0, (1, 1, 1),
                           (Vector((1, 0, 0)), s * (0.4 + 0.25 * k))))
    return b.finish(name, torso_z + body_h)


MODELS = [
    ("log_pile", log_pile),
    ("tar_kiln", tar_kiln),
    ("quarry", quarry),
    ("outcrop_iron", lambda: outcrop("outcrop_iron", (0.55, 0.22, 0.1), False, 21)),
    ("outcrop_silver", lambda: outcrop("outcrop_silver", (0.85, 0.86, 0.88), True, 22)),
    ("outcrop_coal", lambda: outcrop("outcrop_coal", (0.06, 0.06, 0.06), False, 23)),
    ("outcrop_soapstone", lambda: outcrop("outcrop_soapstone", (0.5, 0.56, 0.5), False, 24)),
    ("crystals", crystals),
    ("gold_gravel", gold_gravel),
    ("amber", amber),
    ("bog", bog),
    ("peat_stack", peat_stack),
    ("clay_pit", clay_pit),
    ("salt_pans", salt_pans),
    ("whale", whale),
    ("seal", lambda: seal("seal", 30)),
    ("walrus", lambda: seal("walrus", 31, True)),
    ("sheep", lambda: quadruped("sheep", (0.9, 0.88, 0.82), 0.4, 1.1, 0.75, 0.25, 0.18, wool=True, dark_head=True, seed=40)),
    ("horse", lambda: quadruped("horse", (0.45, 0.3, 0.18), 0.85, 1.9, 0.75, 0.75, 0.3, seed=41)),
    ("deer", lambda: quadruped("deer", (0.55, 0.38, 0.22), 0.8, 1.5, 0.55, 0.6, 0.22, antlers=0.4, seed=42)),
    ("reindeer", lambda: quadruped("reindeer", (0.55, 0.52, 0.48), 0.75, 1.6, 0.65, 0.55, 0.24, antlers=0.7, seed=43)),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, build in MODELS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = build()
        export(obj, name)


main()
