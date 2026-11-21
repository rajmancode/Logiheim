"""Builds Logiheim's vegetation and rock models in Blender and exports them as .glb.

Run headless (Blender 4.x):
    blender -b --python tools/blender/make_vegetation.py -- assets/models/vegetation

Every model is about 1 unit tall (trees) or 1 unit across (rocks); the game scales them.
Materials are named "Bark", "Leaves" and "Rock" so the game can swap in its own shaders,
and vertex colours (COLOR_0) carry baked ambient occlusion.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models/vegetation"


# --------------------------------------------------------------------------- helpers

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return mat


def new_object(name, bm, mats):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(material(m))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bake_ao(obj, ao_fn):
    """Writes ao_fn(position, normal, material_index) -> 0..1 into a byte colour attribute."""
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index]
            a = max(0.0, min(1.0, ao_fn(v.co, v.normal, poly.material_index)))
            attr.data[li].color = (a, a, a, 1.0)
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = 0


def shade_smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True


def export(obj, name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_colors=True, export_normals=True, export_materials="EXPORT")
    print("exported", path)


def cone_ring(bm, z, radius, segments, rng, droop, star):
    """Ring of vertices; alternate vertices pushed out to make branch tips."""
    verts = []
    rot = rng.uniform(0, math.tau)
    for i in range(segments):
        a = rot + i * math.tau / segments
        r = radius * ((1.0 + star) if i % 2 == 0 else (1.0 - star * 0.6)) * rng.uniform(0.88, 1.12)
        dz = -droop * r * rng.uniform(0.6, 1.3) if i % 2 == 0 else 0.0
        verts.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z + dz)))
    return verts


def cylinder(bm, base, top, r0, r1, segments, mat_index):
    """Tapered cylinder between two points (no caps)."""
    axis = (top - base).normalized()
    side = axis.orthogonal().normalized()
    other = axis.cross(side)
    ring0, ring1 = [], []
    for i in range(segments):
        a = i * math.tau / segments
        d = side * math.cos(a) + other * math.sin(a)
        ring0.append(bm.verts.new(base + d * r0))
        ring1.append(bm.verts.new(top + d * r1))
    for i in range(segments):
        j = (i + 1) % segments
        f = bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        f.material_index = mat_index


def blob(bm, center, radius, rng, mat_index, roughness=0.25, subdiv=2, squash=1.0):
    """Noisy icosphere."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
    seed = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    vmap = {}
    for v in tmp.verts:
        d = v.co.normalized()
        n = noise.noise(d * 2.2 + seed) * 0.6 + noise.noise(d * 5.0 + seed) * 0.4
        r = radius * (1.0 + roughness * n)
        p = center + Vector((d.x * r, d.y * r, d.z * r * squash))
        vmap[v] = bm.verts.new(p)
    for f in tmp.faces:
        nf = bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = mat_index
    tmp.free()


# --------------------------------------------------------------------------- models

def make_conifer(name, seed, tiers, slim):
    rng = random.Random(seed)
    bm = bmesh.new()
    cylinder(bm, Vector((0, 0, -0.02)), Vector((0, 0, 0.97)), 0.03 * slim, 0.006, 6, 0)
    base_z = 0.14
    top_z = 1.0
    for t in range(tiers):
        f = t / (tiers - 1)
        z = base_z + (top_z - base_z) * f * 0.92
        radius = (0.34 * (1.0 - f) + 0.05) * slim * rng.uniform(0.92, 1.08)
        height = 0.2 * (1.0 - f * 0.45)
        ring = cone_ring(bm, z, radius, 16, rng, droop=0.4, star=0.32)
        tip = bm.verts.new((rng.uniform(-0.01, 0.01), rng.uniform(-0.01, 0.01), z + height))
        inner = bm.verts.new((0, 0, z + height * 0.15))
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            bm.faces.new((ring[i], ring[j], tip)).material_index = 1
            bm.faces.new((ring[j], ring[i], inner)).material_index = 1
    obj = new_object(name, bm, ["Bark", "Leaves"])
    obj.data.update()

    def ao(co, n, mi):
        if mi == 0:
            return 0.45 + 0.4 * min(co.z, 1.0)
        radial = math.hypot(co.x, co.y) / (0.4 * slim)
        return 0.35 + 0.45 * min(radial, 1.0) + 0.25 * co.z
    bake_ao(obj, ao)
    return obj


def make_broadleaf(name, seed, crown_blobs):
    rng = random.Random(seed)
    bm = bmesh.new()
    trunk_top = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0.55))
    cylinder(bm, Vector((0, 0, -0.02)), trunk_top, 0.06, 0.035, 8, 0)
    crown_center = Vector((0, 0, 0.7))
    for b in range(4):
        a = b * math.tau / 4 + rng.uniform(-0.4, 0.4)
        tip = trunk_top + Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, rng.uniform(0.12, 0.25)))
        cylinder(bm, trunk_top - Vector((0, 0, 0.05)), tip, 0.022, 0.008, 5, 0)
    for b in range(crown_blobs):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 0.2)
        c = crown_center + Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(-0.08, 0.2)))
        blob(bm, c, rng.uniform(0.16, 0.24), rng, 1, roughness=0.3, subdiv=2, squash=0.85)
    obj = new_object(name, bm, ["Bark", "Leaves"])

    def ao(co, n, mi):
        if mi == 0:
            return 0.45 + 0.4 * min(co.z / 0.6, 1.0)
        d = (co - crown_center).length / 0.42
        up = 0.5 + 0.5 * n.z
        return 0.3 + 0.5 * min(d, 1.0) + 0.2 * up
    bake_ao(obj, ao)
    shade_smooth(obj)
    return obj


def make_bush(name, seed, blobs):
    rng = random.Random(seed)
    bm = bmesh.new()
    for b in range(blobs):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 0.28)
        rad = rng.uniform(0.2, 0.3)
        c = Vector((math.cos(a) * r, math.sin(a) * r, rad * rng.uniform(0.45, 0.8)))
        blob(bm, c, rad, rng, 0, roughness=0.35, subdiv=2, squash=0.8)
    obj = new_object(name, bm, ["Leaves"])

    def ao(co, n, mi):
        return 0.3 + 0.5 * min(co.z / 0.55, 1.0) + 0.2 * (0.5 + 0.5 * n.z)
    bake_ao(obj, ao)
    shade_smooth(obj)
    return obj


def make_rock(name, seed, flat, strata=False):
    """A real-looking boulder (tools/blender/rock_shapes.py): fractured facets, cracks, grain,
    optionally bedded strata; AO from crevices baked into the vertex colours."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from rock_shapes import rock_bmesh, decimate, cavity_ao
    rng = random.Random(seed)
    bm = rock_bmesh(seed, flat, facets=rng.randint(8, 12), strata=strata)
    decimate(bm, 2800)
    bm.verts.index_update()
    ao = {v.index: a for v, a in cavity_ao(bm).items()}
    obj = new_object(name, bm, ["Rock"])
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            a = ao.get(mesh.loops[li].vertex_index, 0.7)
            attr.data[li].color = (a, a, a, 1.0)
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = 0
    # Smooth across gentle curvature, sharp at the fracture edges.
    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(38)
    return obj


MODELS = [
    ("conifer_a", lambda: make_conifer("conifer_a", 11, 11, 1.0)),
    ("conifer_b", lambda: make_conifer("conifer_b", 23, 13, 0.8)),
    ("conifer_c", lambda: make_conifer("conifer_c", 37, 9, 1.15)),
    ("broadleaf_a", lambda: make_broadleaf("broadleaf_a", 5, 8)),
    ("broadleaf_b", lambda: make_broadleaf("broadleaf_b", 9, 11)),
    ("bush_a", lambda: make_bush("bush_a", 3, 5)),
    ("bush_b", lambda: make_bush("bush_b", 8, 7)),
    ("rock_a", lambda: make_rock("rock_a", 1, 0.7)),
    ("rock_b", lambda: make_rock("rock_b", 2, 0.5)),
    ("rock_c", lambda: make_rock("rock_c", 3, 0.9)),
    ("rock_d", lambda: make_rock("rock_d", 4, 0.35)),
    ("rock_e", lambda: make_rock("rock_e", 5, 0.6, strata=True)),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    only = os.environ.get("MODELS", "")
    for name, build in MODELS:
        if only and name not in only.split(","):
            continue
        reset_scene()
        obj = build()
        export(obj, name)


main()
