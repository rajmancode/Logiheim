"""Builds the animals (sheep, horse, red deer, reindeer, boar, fox, seal, walrus, whale).

Run headless (Blender 4.x):
    blender -b --python tools/blender/make_animals.py -- assets/models/animals

Each animal is sculpted from an anatomical skeleton: every bone is filled with blending
metaballs that taper with the bone radii (like clay over an armature), the field becomes a
smoothed mesh, and the result is painted by body region (coat, belly, legs, mane,
muzzle, hooves, eyes...). Real size in metres; Blender X = forward, Z = up (glTF Y up).

Every vertex also gets animation weights in a second UV map "anim":
    u = how much it moves with the head (0 at the neck base .. 1 for the head),
    v = tail weight (0 at the root .. 1 at the tip); for the whale, position along the body.
shaders/animal.gdshader uses them (plus the pivots written to animals.json) to make the
animals graze, look around, chew, swish their tails and, for the whale, swim.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models/animals"
META = {}


# --------------------------------------------------------------------------- skeleton -> mesh

class Skeleton:
    def __init__(self):
        self.co = []      # Vector
        self.r = []       # radius
        self.edges = []   # (a, b, label, t0, t1)

    def node(self, co, r):
        self.co.append(Vector(co))
        self.r.append(r)
        return len(self.co) - 1

    def chain(self, points, label, t0=0.0, t1=1.0, start=None):
        """points: list of (co, r). Returns node indices. Optionally starts from an existing node."""
        ids = [start] if start is not None else []
        for co, r in points:
            ids.append(self.node(co, r))
        n = len(ids) - 1
        for k in range(n):
            a, b = ids[k], ids[k + 1]
            self.edges.append((a, b, label, t0 + (t1 - t0) * k / n, t0 + (t1 - t0) * (k + 1) / n))
        return ids

    def nearest(self, p):
        """Label, t and radius-normalised distance of the bone nearest to p."""
        best = (None, 0.0, 1e9)
        for a, b, label, t0, t1 in self.edges:
            pa, pb = self.co[a], self.co[b]
            ab = pb - pa
            l2 = max(ab.length_squared, 1e-9)
            s = max(0.0, min(1.0, (p - pa).dot(ab) / l2))
            q = pa + ab * s
            r = self.r[a] + (self.r[b] - self.r[a]) * s
            d = (p - q).length / max(r, 1e-4)
            if d < best[2]:
                best = (label, t0 + (t1 - t0) * s, d)
        return best


def meta_object(name, sk, resolution, target_faces=6000):
    """Fills every bone with a chain of blending metaballs (tapering with the bone radii),
    converts the field to a mesh, smooths it and decimates to about `target_faces`."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    # With stiffness 2 a lone ball's surface sits at ~0.575 x its radius; overlapping balls
    # fatten a little, hence 0.85.
    k = 0.85 / 0.575
    for a, b, *_ in sk.edges:
        pa, pb = sk.co[a], sk.co[b]
        ra, rb = sk.r[a], sk.r[b]
        n = max(2, math.ceil((pb - pa).length / max(min(ra, rb) * 0.7, 1e-3)))
        for i in range(n + 1):
            t = i / n
            e = mb.elements.new()
            e.co = pa.lerp(pb, t)
            e.radius = (ra + (rb - ra) * t) * k
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
    sm.factor = 0.5
    sm.iterations = 4
    bpy.ops.object.modifier_apply(modifier="smooth")
    faces = len(obj.data.polygons)
    if faces > target_faces:
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = target_faces / faces
        bpy.ops.object.modifier_apply(modifier="dec")
    return obj


def add_spheres(obj, spheres):
    """Adds small spheres (eyes, nostrils) as extra geometry: [(co, r, label)]."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    extra = []
    for co, r, label in spheres:
        geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        for v in geo["verts"]:
            v.co += Vector(co)
            extra.append((v, label))
    bm.to_mesh(obj.data)
    bm.free()
    return {i for i in range(len(obj.data.vertices) - len(extra), len(obj.data.vertices))}, [l for _, l in extra]


def finish(obj, sk, paint, anim, extra_ids=(), extra_labels=(), displace=None, decimate=0.6):
    """Paints vertex colours, writes the anim UVs, decimates and returns the object."""
    mesh = obj.data
    extra_map = dict(zip(sorted(extra_ids), extra_labels))
    labels = {}
    for v in mesh.vertices:
        if v.index in extra_map:
            labels[v.index] = (extra_map[v.index], 1.0)
        else:
            label, t, _ = sk.nearest(v.co)
            labels[v.index] = (label, t)
    if displace:
        for v in mesh.vertices:
            label, t = labels[v.index]
            v.co += v.normal * displace(v.co, label, t)
    col = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    mesh.uv_layers.new(name="UVMap")
    an = mesh.uv_layers.new(name="anim")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            v = mesh.vertices[vi]
            label, t = labels[vi]
            c = paint(v.co, v.normal, label, t)
            col.data[li].color = (c[0], c[1], c[2], 1.0)
            an.data[li].uv = anim(v.co, label, t)
    mesh.color_attributes.active_color = col
    mesh.uv_layers.active = mesh.uv_layers["UVMap"]
    if decimate < 1.0:
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = decimate
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="dec")
    return obj


def to_godot(co):
    """Blender (x, y, z) -> glTF/Godot (x, z, -y)."""
    return [round(co[0], 4), round(co[2], 4), round(-co[1], 4)]


def export(obj, name, meta):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_colors=True, export_texcoords=True, export_normals=True)
    META[name] = meta
    print("exported", path, len(obj.data.polygons), "faces")


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def mottle(co, amount=0.08, freq=6.0):
    return 1.0 + noise.noise(co * freq) * amount


# --------------------------------------------------------------------------- quadrupeds

def quadruped(name, p, coat, seed=0):
    """p: proportions in metres. coat: colour rules. Returns the finished object and meta."""
    rng = random.Random(seed)
    sk = Skeleton()
    L, H = p["length"], p["height"]
    br = p["body_r"]
    zb = H - br * 0.95
    sx, hx = L / 2, -L / 2
    # Spine: rump -> belly -> chest (the chest node carries the neck and front legs).
    spine = sk.chain([((hx - p.get("rump", 0.1), 0, zb + br * 0.05), p["hip_r"]),
                      ((hx * 0.3, 0, zb), br),
                      ((sx * 0.4, 0, zb + br * 0.05), br * 1.02),
                      ((sx, 0, zb + br * 0.12), p["chest_r"])], "body")
    hip, chest = spine[0], spine[-1]
    # Body masses: a deep brisket under the chest, withers over the shoulders, haunches.
    sk.chain([((sx * 0.5, 0, zb - br * 0.28), br * 0.62)], "body", start=chest)
    sk.chain([((sx * 0.7, 0, zb + br * 0.42), br * 0.55)], "body", start=chest)
    for s_ in (-1, 1):
        sk.chain([((hx + p["hip_r"] * 0.1, s_ * br * 0.3, zb - br * 0.05), p["hip_r"] * 0.7)], "body", start=hip)
    # Neck and head.
    na = math.radians(p["neck_angle"])
    nb = Vector((sx + p["chest_r"] * 0.35, 0, zb + br * 0.35))
    ne = nb + Vector((math.cos(na), 0, math.sin(na))) * p["neck_len"]
    nm = nb.lerp(ne, 0.5) + Vector((0, 0, p["neck_len"] * 0.04))
    sk.edges.append((chest, sk.node(nb, p["neck_r0"]), "neck", 0.0, 0.15))
    neck = sk.chain([(nm, (p["neck_r0"] + p["neck_r1"]) / 2), (ne, p["neck_r1"])], "neck", 0.15, 1.0, start=len(sk.co) - 1)
    ha = math.radians(-p["head_angle"])
    hb = ne + Vector((p["head_r"] * 0.3, 0, p["head_r"] * 0.2))
    hm = hb + Vector((math.cos(ha), 0, math.sin(ha))) * p["head_len"] * 0.55
    he = hb + Vector((math.cos(ha), 0, math.sin(ha))) * p["head_len"]
    head = sk.chain([(hb, p["head_r"]), (hm, p["head_r"] * 0.8), (he, p["muzzle_r"])], "head", start=neck[-1])
    # Ears.
    for s in (-1, 1):
        base = hb + Vector((-p["head_r"] * 0.3, s * p["head_r"] * 0.55, p["head_r"] * 0.6))
        tip = base + Vector((-p["ear_len"] * 0.3, s * p["ear_len"] * p.get("ear_spread", 0.5), p["ear_len"] * 0.8))
        sk.chain([(base, p["ear_r"]), (tip, p["ear_r"] * 0.35)], "ear", start=head[0])
    # Antlers: a beam that sweeps back and up, with tines.
    if p.get("antler"):
        a = p["antler"]
        for s in (-1, 1):
            base = hb + Vector((-p["head_r"] * 0.1, s * p["head_r"] * 0.4, p["head_r"] * 0.85))
            prev = base
            ids = [head[0]]
            for k in range(a["segments"]):
                f = (k + 1) / a["segments"]
                pt = base + Vector((-a["back"] * f, s * a["spread"] * math.sin(f * 1.6), a["height"] * f))
                ids = sk.chain([(pt, a["r"] * (1.0 - 0.6 * f))], "antler", start=ids[-1])
                if k < a["segments"] - 1 and k % a.get("tine_every", 1) == 0:
                    tine = pt + Vector((a["tine"] * 0.8, s * a["tine"] * 0.25, a["tine"] * 0.6))
                    sk.chain([(tine, a["r"] * 0.35)], "antler", start=ids[-1])
                prev = pt
            if a.get("brow"):
                brow = base + Vector((a["brow"], s * 0.05, a["brow"] * 0.3))
                sk.chain([(brow, a["r"] * 0.45)], "antler", start=head[0])
    # Tusks.
    if p.get("tusk"):
        for s in (-1, 1):
            tb = he + Vector((-p["muzzle_r"] * 0.6, s * p["muzzle_r"] * 0.8, -p["muzzle_r"] * 0.2))
            tt = tb + Vector((p["tusk"] * 0.2, s * p["tusk"] * 0.35, p["tusk"]))
            sk.chain([(tb, 0.02), (tt, 0.008)], "tusk", start=head[-1])
    # Legs: front from the chest, back from the hip, with knees and hocks.
    lat = br * 0.55
    for s in (-1, 1):
        for front in (True, False):
            x = sx - p["chest_r"] * 0.25 if front else hx + p["hip_r"] * 0.2
            top = Vector((x, s * lat, zb - br * 0.35))
            knee = Vector((x + (0.0 if front else -H * 0.07), s * lat * 0.95, H * 0.4))
            ankle = Vector((x + (0.0 if front else -H * 0.02), s * lat * 0.95, H * 0.13))
            hoof = Vector((x + H * 0.02, s * lat * 0.95, p["hoof_r"]))
            r0 = p["leg_r"] * (1.9 if not front else 1.5)
            sk.chain([(top, r0), (knee, p["leg_r"] * 0.75), (ankle, p["leg_r"] * 0.6), (hoof, p["hoof_r"])],
                     "leg", start=hip if not front else chest)
    # Tail.
    tb = Vector((hx - p.get("rump", 0.1) - p["hip_r"] * 0.7, 0, zb + br * 0.35))
    td = math.radians(p["tail_droop"])
    tt = tb + Vector((-math.cos(td), 0, -math.sin(td))) * p["tail_len"]
    tm = tb.lerp(tt, 0.5)
    sk.chain([(tb, p["tail_r"]), (tm, p["tail_r"] * p.get("tail_mid", 0.9)), (tt, p["tail_r"] * p.get("tail_tip", 0.4))], "tail", start=hip)

    obj = meta_object(name, sk, min(H * 0.016, 0.02), p.get("faces", 6000))
    # Eyes sit on the side of the head, a little forward of the head's widest point.
    eye_r = p["head_r"] * 0.16
    eyes = []
    hdir = Vector((math.cos(ha), 0, math.sin(ha)))
    for s in (-1, 1):
        ec = hb + hdir * p["head_len"] * 0.22 + Vector((0, s * p["head_r"] * 0.86, p["head_r"] * 0.35))
        eyes.append((ec, eye_r, "eye"))
    ids, labs = add_spheres(obj, eyes)

    def paint(co, n, label, t):
        if label == "eye":
            return (0.03, 0.025, 0.02)
        if label == "head" and t > 0.93:
            return (0.06, 0.05, 0.045)  # nose
        return coat(co, n, label, t, zb, br)

    def anim(co, label, t):
        hw = 0.0
        if label == "neck":
            hw = t * t * (3 - 2 * t)
        elif label in ("head", "ear", "antler", "tusk", "eye", "nose"):
            hw = 1.0
        tw = t if label == "tail" else 0.0
        return (hw, tw)

    finish(obj, sk, paint, anim, ids, labs, p.get("displace"), 1.0)
    meta = {"neck_pivot": to_godot(nb), "tail_pivot": to_godot(tb), "head_down": p["graze"],
            "tail_swish": p.get("swish", 0.35), "mode": 0, "length": L}
    return obj, meta


def leg_shade(z, H, base, dark, hoof, low=0.35):
    if z < 0.06:
        return hoof
    return mix(dark, base, (z / H - 0.08) / low)


def sheep():
    H = 0.72
    p = dict(length=0.85, height=H, body_r=0.27, hip_r=0.25, chest_r=0.25, rump=0.08,
             neck_len=0.26, neck_angle=40, neck_r0=0.12, neck_r1=0.09, head_len=0.26, head_r=0.085,
             muzzle_r=0.055, head_angle=40, ear_len=0.1, ear_r=0.025, ear_spread=0.9,
             leg_r=0.05, hoof_r=0.03, tail_len=0.16, tail_r=0.06, tail_droop=70, graze=1.1, swish=0.25)
    wool = (0.88, 0.85, 0.78)
    face = (0.16, 0.13, 0.11)

    def coat(co, n, label, t, zb, br):
        if label in ("head", "ear"):
            return mix(face, wool, 0.0)
        if label == "leg":
            return leg_shade(co.z, H, (0.3, 0.27, 0.24), face, (0.08, 0.07, 0.06), 0.6)
        m = mottle(co, 0.06, 14.0)
        return tuple(c * m for c in wool)

    def displace(co, label, t):
        if label in ("body", "neck", "tail"):
            return 0.02 + 0.025 * noise.noise(co * 18.0)
        return 0.0
    p["displace"] = displace
    return quadruped("sheep", p, coat, 1)


def horse():
    H = 1.38
    p = dict(length=1.15, height=H, body_r=0.3, hip_r=0.3, chest_r=0.31, rump=0.14,
             neck_len=0.8, neck_angle=50, neck_r0=0.21, neck_r1=0.13, head_len=0.6, head_r=0.13,
             muzzle_r=0.085, head_angle=55, ear_len=0.13, ear_r=0.03, ear_spread=0.2,
             leg_r=0.085, hoof_r=0.065, tail_len=0.62, tail_r=0.09, tail_droop=72, tail_mid=1.1, tail_tip=0.7,
             graze=1.25, swish=0.45)
    body = (0.42, 0.28, 0.16)
    dark = (0.08, 0.06, 0.05)

    def coat(co, n, label, t, zb, br):
        m = mottle(co, 0.05, 8.0)
        if label == "tail":
            return dark
        if label == "neck" and n.z > 0.35 and co.y * co.y < 0.004:
            return dark  # mane along the top of the neck
        if label == "head":
            muzzle = max(0.0, t - 0.75) * 4.0
            return mix(tuple(c * m for c in body), (0.2, 0.15, 0.12), muzzle)
        if label == "leg":
            return leg_shade(co.z, H, body, dark, (0.06, 0.05, 0.05), 0.35)
        belly = max(0.0, -n.z) * 0.25
        return mix(tuple(c * m for c in body), (0.55, 0.42, 0.3), belly)
    return quadruped("horse", p, coat, 2)


def deer(name="deer", reindeer=False):
    H = 1.2 if not reindeer else 1.1
    p = dict(length=0.95 if not reindeer else 1.0, height=H, body_r=0.27 if not reindeer else 0.3,
             hip_r=0.26, chest_r=0.27, rump=0.1, neck_len=0.5 if not reindeer else 0.42, neck_angle=55 if not reindeer else 45,
             neck_r0=0.15 if not reindeer else 0.17, neck_r1=0.09, head_len=0.38, head_r=0.1, muzzle_r=0.06,
             head_angle=50, ear_len=0.16, ear_r=0.035, ear_spread=0.7, leg_r=0.06, hoof_r=0.04,
             tail_len=0.14, tail_r=0.045, tail_droop=60, graze=1.25, swish=0.5)
    p["faces"] = 9000
    if reindeer:
        p["antler"] = dict(segments=5, back=0.45, spread=0.32, height=0.75, r=0.035, tine=0.16, tine_every=1, brow=0.2)
    else:
        p["antler"] = dict(segments=4, back=0.35, spread=0.35, height=0.8, r=0.032, tine=0.18, tine_every=1, brow=0.18)
    coat_col = (0.48, 0.3, 0.17) if not reindeer else (0.42, 0.38, 0.33)
    pale = (0.78, 0.68, 0.52) if not reindeer else (0.88, 0.86, 0.8)
    antler = (0.58, 0.5, 0.4)

    def coat(co, n, label, t, zb, br):
        if label == "antler":
            return mix(antler, (0.9, 0.86, 0.78), t)
        m = mottle(co, 0.05, 9.0)
        base = tuple(c * m for c in coat_col)
        if label == "leg":
            return leg_shade(co.z, H, base, (0.18, 0.14, 0.1), (0.06, 0.05, 0.04), 0.3)
        if label == "tail" or (label == "body" and co.x < -0.45 and n.x < -0.3):
            return pale  # pale rump patch
        if reindeer and label == "neck":
            return mix(base, pale, 0.7)  # white neck mane
        if label == "head" and t > 0.8:
            return (0.12, 0.1, 0.08)
        belly = max(0.0, -n.z) * 0.6
        return mix(base, pale, belly)
    return quadruped(name, p, coat, 3 if not reindeer else 4)


def boar():
    H = 0.82
    p = dict(length=0.85, height=H, body_r=0.3, hip_r=0.27, chest_r=0.33, rump=0.05,
             neck_len=0.2, neck_angle=10, neck_r0=0.25, neck_r1=0.2, head_len=0.42, head_r=0.16,
             muzzle_r=0.07, head_angle=28, ear_len=0.11, ear_r=0.035, ear_spread=0.4,
             leg_r=0.055, hoof_r=0.035, tail_len=0.22, tail_r=0.03, tail_droop=75, tusk=0.08, graze=0.7, swish=0.6)
    hair = (0.22, 0.17, 0.12)

    def coat(co, n, label, t, zb, br):
        if label == "tusk":
            return (0.92, 0.88, 0.78)
        m = mottle(co, 0.12, 20.0)
        base = tuple(c * m for c in hair)
        if label == "head" and t > 0.85:
            return (0.3, 0.22, 0.2)  # snout disc
        if label == "leg":
            return leg_shade(co.z, H, base, (0.1, 0.08, 0.06), (0.05, 0.04, 0.04), 0.4)
        if n.z > 0.6 and label in ("body", "neck"):
            return tuple(c * 0.7 for c in base)  # bristly dark ridge
        return base

    def displace(co, label, t):
        return 0.008 * noise.noise(co * 40.0) if label in ("body", "neck") else 0.0
    p["displace"] = displace
    return quadruped("boar", p, coat, 5)


def fox():
    H = 0.4
    p = dict(length=0.5, height=H, body_r=0.11, hip_r=0.1, chest_r=0.11, rump=0.04,
             neck_len=0.15, neck_angle=40, neck_r0=0.065, neck_r1=0.05, head_len=0.17, head_r=0.06,
             muzzle_r=0.022, head_angle=12, ear_len=0.09, ear_r=0.025, ear_spread=0.25,
             leg_r=0.025, hoof_r=0.018, tail_len=0.42, tail_r=0.06, tail_droop=20, tail_mid=1.2, tail_tip=0.6,
             graze=0.9, swish=0.5)
    red = (0.72, 0.36, 0.12)
    white = (0.92, 0.9, 0.85)
    black = (0.08, 0.06, 0.05)

    def coat(co, n, label, t, zb, br):
        if label == "tail":
            return white if t > 0.82 else red
        if label == "leg":
            return black if co.z < H * 0.45 else red
        if label == "ear":
            return black if t > 0.6 else red
        if label in ("head", "neck", "body") and n.z < -0.2:
            return white  # white throat and chest
        m = mottle(co, 0.06, 30.0)
        return tuple(c * m for c in red)
    return quadruped("fox", p, coat, 6)


# --------------------------------------------------------------------------- marine

def seal(name="seal", walrus=False):
    sk = Skeleton()
    s = 1.0 if not walrus else 1.9
    r = 0.24 * s if not walrus else 0.28 * s
    body = sk.chain([((-0.75 * s, 0, 0.1 * s), 0.09 * s), ((-0.35 * s, 0, 0.17 * s), r * 0.9),
                     ((0.1 * s, 0, 0.2 * s), r), ((0.45 * s, 0, 0.22 * s), r * 0.85)], "body")
    neck = sk.chain([((0.7 * s, 0, 0.3 * s), r * 0.6)], "neck", start=body[-1])
    head = sk.chain([((0.88 * s, 0, 0.38 * s), r * 0.55), ((1.02 * s, 0, 0.36 * s), r * 0.38)], "head", start=neck[-1])
    for sd in (-1, 1):
        sk.chain([((0.35 * s, sd * r * 0.9, 0.06 * s), 0.05 * s), ((0.45 * s, sd * r * 1.5, 0.02 * s), 0.035 * s)], "leg", start=body[2])
        sk.chain([((-0.9 * s, sd * 0.12 * s, 0.06 * s), 0.04 * s), ((-1.05 * s, sd * 0.2 * s, 0.05 * s), 0.025 * s)], "tail", start=body[0])
    if walrus:
        for sd in (-1, 1):
            sk.chain([((1.0 * s, sd * 0.06 * s, 0.26 * s), 0.025 * s), ((1.0 * s, sd * 0.09 * s, -0.05 * s), 0.01 * s)], "tusk", start=head[-1])
    obj = meta_object(name, sk, 0.02 * s, 4000)
    he = sk.co[head[0]]
    ids, labs = add_spheres(obj, [(he + Vector((0.06 * s, sd * r * 0.62, 0.08 * s)), 0.024 * s, "eye") for sd in (-1, 1)])
    base = (0.4, 0.4, 0.38) if not walrus else (0.45, 0.32, 0.25)

    def paint(co, n, label, t):
        if label == "eye":
            return (0.02, 0.02, 0.02)
        if label == "tusk":
            return (0.93, 0.9, 0.8)
        if not walrus:
            spots = 0.75 if noise.noise(co * 14.0) > 0.35 else 1.0  # harbour-seal spots
            belly = max(0.0, -n.z) * 0.5
            return mix(tuple(c * spots for c in base), (0.62, 0.6, 0.55), belly)
        m = mottle(co, 0.1, 12.0)
        return tuple(c * m for c in base)

    def anim(co, label, t):
        hw = 0.0
        if label == "neck":
            hw = 0.5
        elif label in ("head", "eye", "tusk"):
            hw = 1.0
        return (hw, t if label == "tail" else 0.0)

    def displace(co, label, t):
        return 0.015 * s * noise.noise(co * 8.0) if walrus and label == "body" else 0.0
    finish(obj, sk, paint, anim, ids, labs, displace, 1.0)
    meta = {"neck_pivot": to_godot(sk.co[body[-1]]), "tail_pivot": to_godot(sk.co[body[0]]),
            "head_down": -0.5, "tail_swish": 0.3, "mode": 0, "length": 2.0 * s}
    return obj, meta


def whale():
    sk = Skeleton()
    # Humpback, ~12 m; origin at the waterline with the back just breaking the surface.
    body = sk.chain([((5.5, 0, -0.9), 0.55), ((3.5, 0, -0.6), 1.25), ((1.0, 0, -0.55), 1.45),
                     ((-2.0, 0, -0.65), 1.2), ((-4.5, 0, -0.75), 0.6), ((-6.0, 0, -0.8), 0.28)], "body")
    for s in (-1, 1):
        sk.chain([((2.6, s * 1.4, -1.3), 0.22), ((1.8, s * 3.2, -2.0), 0.16), ((1.0, s * 4.4, -2.5), 0.08)], "fin", start=body[2])
        sk.chain([((-6.5, s * 1.0, -0.8), 0.14), ((-6.9, s * 1.9, -0.75), 0.06)], "fluke", start=body[-1])
    sk.chain([((-2.5, 0, 0.55), 0.12)], "dorsal", start=body[3])
    obj = meta_object("whale", sk, 0.1, 5000)
    ids, labs = add_spheres(obj, [((4.4, s * 1.45, -1.0), 0.1, "eye") for s in (-1, 1)])

    def paint(co, n, label, t):
        if label == "eye":
            return (0.02, 0.02, 0.02)
        dark = (0.1, 0.11, 0.13)
        if label == "fin" and n.z < 0:
            return (0.8, 0.8, 0.78)
        belly = max(0.0, -n.z)
        # Throat grooves: pale stripes underneath the head.
        if belly > 0.5 and co.x > 1.5 and math.sin(co.y * 22.0) > 0.4:
            return (0.6, 0.6, 0.58)
        return mix(dark, (0.72, 0.72, 0.7), belly * 0.9)

    def anim(co, label, t):
        along = max(0.0, min(1.0, (5.5 - co.x) / 12.5))
        return (0.0, along)
    finish(obj, sk, paint, anim, ids, labs, None, 1.0)
    return obj, {"neck_pivot": [0, 0, 0], "tail_pivot": [0, 0, 0], "head_down": 0.0, "tail_swish": 0.0, "mode": 1, "length": 12.5}


MODELS = [
    ("sheep", sheep), ("horse", horse), ("deer", lambda: deer("deer")), ("reindeer", lambda: deer("reindeer", True)),
    ("boar", boar), ("fox", fox), ("seal", lambda: seal("seal")), ("walrus", lambda: seal("walrus", True)), ("whale", whale),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, build in MODELS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj, meta = build()
        export(obj, name, meta)
    with open(os.path.join(OUT, "animals.json"), "w") as f:
        json.dump(META, f, indent=1)
    print("wrote animals.json")


main()
