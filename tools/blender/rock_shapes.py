"""Shared rock generator for make_vegetation.py (boulders) and make_resources.py (outcrops).

A rock is grown from a dense icosphere:
  1. a lumpy base shape (low-frequency noise, stretched and squashed);
  2. fracture facets: several random planes; everything beyond a plane is pressed flat onto it
     (with a little roughness), which gives the flat broken faces of real boulders while keeping
     the mesh dense enough for detail;
  3. cracks: thin grooves along the edges of Voronoi cells;
  4. optional strata: fine horizontal banding like bedded sandstone or slate;
  5. grain: fine noise over everything.
Then it is decimated to a game-friendly size. cavity_ao() gives per-vertex ambient occlusion
from local concavity (crevices and the underside darker), for baking into vertex colours.
"""
import math
import random

import bmesh
from mathutils import Vector, noise


def rock_bmesh(seed, flat=0.7, facets=9, cracks=True, strata=False, radius=0.5, subdiv=5):
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    s = Vector((rng.uniform(-90, 90), rng.uniform(-90, 90), rng.uniform(-90, 90)))
    stretch = Vector((rng.uniform(0.85, 1.3), rng.uniform(0.75, 1.1), flat))
    # 1. Lumpy base.
    for v in bm.verts:
        d = v.co.normalized()
        n = noise.noise(d * 1.3 + s) * 0.2 + noise.noise(d * 3.2 + s) * 0.07
        r = radius * (1.0 + n)
        v.co = Vector((d.x * r * stretch.x, d.y * r * stretch.y, d.z * r * stretch.z))
    # 2. Fracture facets.
    for k in range(facets):
        nrm = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.35, 1.0))).normalized()
        extent = max(v.co.dot(nrm) for v in bm.verts)
        cut = extent * rng.uniform(0.6, 0.86)
        rough = rng.uniform(0.004, 0.012) * radius / 0.5
        so = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
        for v in bm.verts:
            d = v.co.dot(nrm)
            if d > cut:
                # Press onto the plane; slight waviness so the face isn't glass-flat.
                v.co -= nrm * (d - cut)
                v.co += nrm * noise.noise(v.co * 9.0 + so) * rough
    # 3. Cracks along Voronoi cell edges.
    if cracks:
        cs = Vector((rng.uniform(-40, 40), rng.uniform(-40, 40), rng.uniform(-40, 40)))
        freq = rng.uniform(1.6, 2.4) / radius * 0.5
        for v in bm.verts:
            dist, _pts = noise.voronoi(v.co * freq + cs, distance_metric="DISTANCE")
            edge = dist[1] - dist[0]
            # Wide enough to span several vertices, so the grooves read as cracks, not pits.
            if edge < 0.22:
                t = 1.0 - edge / 0.22
                depth = t * t * (3.0 - 2.0 * t) * 0.026 * radius / 0.5
                v.co -= v.co.normalized() * depth
    # 4. Strata.
    if strata:
        so = rng.uniform(0, 10)
        for v in bm.verts:
            band = math.sin(v.co.z * 55.0 / radius * 0.5 + noise.noise(v.co * 3.0) * 2.0 + so)
            v.co += Vector((v.co.x, v.co.y, 0.0)).normalized() * band * 0.006 * radius / 0.5
    # 5. Grain.
    gs = Vector((rng.uniform(-30, 30), rng.uniform(-30, 30), rng.uniform(-30, 30)))
    for v in bm.verts:
        v.co += v.co.normalized() * noise.noise(v.co * 22.0 / radius * 0.5 + gs) * 0.005 * radius / 0.5
    # Flat underside so it sits on the ground.
    low = min(v.co.z for v in bm.verts)
    floor_z = low + (max(v.co.z for v in bm.verts) - low) * 0.12
    for v in bm.verts:
        if v.co.z < floor_z:
            v.co.z = floor_z
    bm.normal_update()
    return bm


def decimate(bm, target_faces):
    """Collapse-decimates a bmesh in place down to about target_faces triangles."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    ratio = min(1.0, target_faces / max(len(bm.faces), 1))
    if ratio < 1.0:
        import bpy
        mesh = bpy.data.meshes.new("_dec")
        bm.to_mesh(mesh)
        obj = bpy.data.objects.new("_dec", mesh)
        bpy.context.scene.collection.objects.link(obj)
        mod = obj.modifiers.new("d", "DECIMATE")
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="d")
        bm.clear()
        bm.from_mesh(obj.data)
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(mesh)
    bm.normal_update()
    return bm


def cavity_ao(bm):
    """Per-vertex AO from concavity and height: {vert: 0..1}."""
    bm.verts.ensure_lookup_table()
    zs = [v.co.z for v in bm.verts]
    lo, hi = min(zs), max(zs)
    out = {}
    for v in bm.verts:
        nb = [e.other_vert(v).co for e in v.link_edges]
        if nb:
            avg = sum(nb, Vector()) / len(nb)
            # Positive when the neighbours sit "above" the vertex along its normal: a crevice.
            conc = (avg - v.co).dot(v.normal)
            spread = max(sum((p - v.co).length for p in nb) / len(nb), 1e-5)
            c = max(-1.0, min(1.0, conc / spread * 3.0))
        else:
            c = 0.0
        h = (v.co.z - lo) / max(hi - lo, 1e-5)
        out[v] = max(0.15, min(1.0, 0.55 + 0.35 * h - 0.45 * max(c, 0.0) + 0.1 * max(-c, 0.0)))
    return out
