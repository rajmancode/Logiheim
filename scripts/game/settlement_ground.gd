class_name SettlementGround
extends Node3D
## The ground a settlement wears into the land as it grows.
##
## Plots: under and round every building, a patch of worked ground made of what suits the
## place (shaders/yard.gdshader): trampled earth and straw on open land, needles and chips in
## the forest, sand and pebbles on the shore, flagstones on rock, a plank floor on bog, packed
## snow up high. It spreads out as the building goes up.
##
## Paths: from each building's door a footpath winds to the nearest door that is already
## nearer the town hall, so the paths branch out from the hall like a tree as the settlement
## spreads. They use the map's trail surface (shaders/trail.gdshader), so they too follow the
## ground: earth and ruts, sand, set stones, log corduroy over bog, snow. A path is a narrow
## track while its building is going up and widens once it stands.
##
## Grass, bushes and stones under the plots and paths are cleared away.

const PATH_WIDTH := 2.6
const TRACK_WIDTH := 1.4
const ACROSS := 4
const RINGS := 7
const SEGS := 40

var world: GameWorld
var _yard_mat: ShaderMaterial
var _path_mat: ShaderMaterial
var _yards: MeshInstance3D
var _paths: MeshInstance3D


func setup(p_world: GameWorld) -> void:
	world = p_world
	_yard_mat = ShaderMaterial.new()
	_yard_mat.shader = load("res://shaders/yard.gdshader")
	_yard_mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
	_yard_mat.render_priority = -2
	_path_mat = ShaderMaterial.new()
	_path_mat.shader = load("res://shaders/trail.gdshader")
	_path_mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
	_path_mat.set_shader_parameter("normal_array", TerrainMaterial.normal_array())
	_path_mat.set_shader_parameter("trail_width", PATH_WIDTH)
	_path_mat.render_priority = -1
	_yards = MeshInstance3D.new()
	_yards.name = "Plots"
	_yards.material_override = _yard_mat
	_yards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_yards)
	_paths = MeshInstance3D.new()
	_paths.name = "Paths"
	_paths.material_override = _path_mat
	_paths.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paths)


func clear() -> void:
	if _yards != null:
		_yards.mesh = null
		_paths.mesh = null


## Redraws every plot and path (after a building is placed, finished or pulled down, or the
## map level changes).
func rebuild(views: Array) -> void:
	var surface := world.hex_map.current_surface()
	if surface == null:
		return
	var sea := world.hex_map.sea_y
	var yard := _Arrays.new()
	var path := _Arrays.new()
	var cleared := PackedVector2Array()
	var radii := PackedFloat32Array()
	var plots := PackedVector2Array()
	var plot_r := PackedFloat32Array()
	for s in world.settlements:
		var mine: Array = []
		for v in views:
			var bv := v as BuildingView
			if is_instance_valid(bv) and bv.settlement == s:
				mine.append(bv)
		if mine.is_empty():
			continue
		for bv: BuildingView in mine:
			var built := s.is_built(bv.record)
			_add_yard(yard, bv, surface, 1.0 if built else 0.65, 0.06 + 0.012 * (cleared.size() % 4))
			var c := Vector2(bv.position.x, bv.position.z)
			cleared.append(c)
			radii.append(maxf(bv.info.size.x, bv.info.size.y) * 0.5 + 3.0)
			plots.append(c)
			plot_r.append(maxf(bv.info.size.x, bv.info.size.y) * 0.55)
		# Paths: nearest-first from the hall, each joining the closest door already reached.
		var hall: BuildingView = null
		for bv: BuildingView in mine:
			if bv.record.id == "town_hall":
				hall = bv
		if hall == null:
			continue
		var hp := Vector2(hall.position.x, hall.position.z)
		mine.sort_custom(func(a: BuildingView, b: BuildingView) -> bool:
			return Vector2(a.position.x, a.position.z).distance_to(hp) < Vector2(b.position.x, b.position.z).distance_to(hp))
		var reached: Array = [hall]
		var by_uid := {}
		for bv: BuildingView in mine:
			by_uid[int(bv.record.uid)] = bv
		for bv: BuildingView in mine:
			if bv == hall:
				continue
			var a := _front(bv)
			var best: BuildingView = hall
			var bd := INF
			if by_uid.has(int(bv.record.get("parent", -1))):
				# An expansion: a track to its main building.
				best = by_uid[int(bv.record.parent)]
				bd = -1.0
			for r: BuildingView in reached:
				if bd < 0.0:
					break
				var d := _front(r).distance_to(a)
				if d < bd:
					bd = d
					best = r
			reached.append(bv)
			var w := PATH_WIDTH if s.is_built(bv.record) and s.is_built(best.record) else TRACK_WIDTH
			var pts := _route(bv, best)
			var keep := PackedVector2Array()
			for q in pts:
				keep.append(q)
			_add_path(path, keep, w, surface, sea)
			for q in keep:
				cleared.append(q)
				radii.append(w * 0.6 + 0.4)
	_yards.mesh = yard.commit()
	_paths.mesh = path.commit()
	_clear_props(cleared, radii, ["Grass", "conifer", "broadleaf", "bush", "rock"])
	# The map's resource markers (a stand of timber, a boulder of ore) only where the building
	# itself stands.
	_clear_props(plots, plot_r, ["Res_"])


## Where a building's path starts: a little way out from its door.
func _front(bv: BuildingView) -> Vector2:
	var p := bv.to_global((bv.info.door as Vector3) + Vector3(0, 0, -2.5))
	return Vector2(p.x, p.z)


func _out_dir(bv: BuildingView) -> Vector2:
	var f := bv.global_transform.basis * Vector3(0, 0, -1)
	return Vector2(f.x, f.z).normalized()


## A winding line from one door to another: out of each door, then curving between them.
func _route(a: BuildingView, b: BuildingView) -> PackedVector2Array:
	var p0 := _front(a)
	var p3 := _front(b)
	var d := p0.distance_to(p3)
	var p1 := p0 + _out_dir(a) * minf(d * 0.35, 9.0)
	var p2 := p3 + _out_dir(b) * minf(d * 0.35, 9.0)
	var n := maxi(4, int(d / 1.6))
	var out := PackedVector2Array()
	var seed_v := float(hash(Vector2i(int(p0.x), int(p0.y))) % 1000) * 0.01
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		var q := p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t
		# A gentle meander, none at the ends.
		var tan := (p0 * -3.0 * u * u + p1 * (3.0 * u * u - 6.0 * u * t) + p2 * (6.0 * u * t - 3.0 * t * t) + p3 * 3.0 * t * t).normalized()
		var side := Vector2(-tan.y, tan.x)
		q += side * sin(t * PI * 2.0 + seed_v) * minf(d * 0.04, 1.2) * sin(t * PI)
		out.append(q)
	return out


## A plot: an oval round the footprint (a little longer towards the door), frayed at the edge.
func _add_yard(arr: _Arrays, bv: BuildingView, surface: TerrainSurface, grow: float, lift: float) -> void:
	var size: Vector2 = bv.info.size
	var rx := (size.x * 0.5 + 3.5) * grow
	var rz := (size.y * 0.5 + 3.5) * grow
	var kinds: Array = RoadNetwork._ground_kinds(PackedVector2Array([Vector2(bv.position.x, bv.position.z)]), surface)[0]
	var base := arr.verts.size()
	for ri in RINGS + 1:
		var r := float(ri) / RINGS
		for si in SEGS:
			var ang := TAU * si / SEGS
			var lz := sin(ang) * rz * r
			# Further out in front of the door, where the work is done.
			if lz < 0.0:
				lz *= 1.25
			var lp := Vector3(cos(ang) * rx * r, 0, lz)
			var q3 := bv.to_global(lp)
			var q := Vector2(q3.x, q3.z)
			var y := surface.sample_mesh(q) + lift
			# Inside the footing the ground is levelled to the floor (a terrace on a slope).
			var hx := size.x * 0.5 * BuildingView.FOOT
			var hz := size.y * 0.5 * BuildingView.FOOT
			if absf(lp.x) <= hx + 0.05 and absf(lp.z) <= hz + 0.05:
				y = maxf(y, bv.global_position.y + 0.03)
			arr.verts.append(Vector3(q.x, y, q.y))
			arr.normals.append(surface.normal_at(q))
			arr.uvs.append(Vector2(r, 0))
			arr.colors.append(kinds[0])
			arr.uv2s.append(kinds[1])
			if ri == 0:
				break
	# Centre fan, then rings of quads.
	for si in SEGS:
		arr.tri(base, base + 1 + si, base + 1 + (si + 1) % SEGS)
	for ri in range(1, RINGS):
		var r0 := base + 1 + (ri - 1) * SEGS
		var r1 := base + 1 + ri * SEGS
		for si in SEGS:
			var sj := (si + 1) % SEGS
			arr.tri(r0 + si, r1 + si, r1 + sj)
			arr.tri(r0 + si, r1 + sj, r0 + sj)


## A path strip along pts, `w` wide, draped on the ground; left out where it would be in water.
func _add_path(arr: _Arrays, pts: PackedVector2Array, w: float, surface: TerrainSurface, sea: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var kinds := RoadNetwork._ground_kinds(pts, surface)
	var along := 0.0
	var prev := -1
	for k in n:
		if k > 0:
			along += pts[k].distance_to(pts[k - 1])
		if surface.sample(pts[k]) < sea + 0.15:
			prev = -1
			continue
		var d := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-d.y, d.x) * w * 0.5
		var base := arr.verts.size()
		for c in ACROSS + 1:
			var u := float(c) / ACROSS
			var q := pts[k] + side * (u * 2.0 - 1.0)
			arr.verts.append(Vector3(q.x, surface.sample_mesh(q) + 0.11, q.y))
			arr.normals.append(surface.normal_at(q))
			arr.uvs.append(Vector2(u, along))
			var gk: Array = kinds[k]
			arr.colors.append(gk[0])
			arr.uv2s.append(gk[1])
		if prev >= 0:
			for c in ACROSS:
				arr.tri(prev + c, base + c, prev + c + 1)
				arr.tri(prev + c + 1, base + c, base + c + 1)
		prev = base


## Hides grass clumps, bushes, trees and boulders standing on the plots and paths.
func _clear_props(pts: PackedVector2Array, radii: PackedFloat32Array, prefixes: Array) -> void:
	if pts.is_empty():
		return
	var lo := pts[0]
	var hi := pts[0]
	var rmax := 0.0
	for i in pts.size():
		lo = lo.min(pts[i])
		hi = hi.max(pts[i])
		rmax = maxf(rmax, radii[i])
	var roots: Array = world.hex_map.get("_level_roots")
	for root_i in mini(2, roots.size()):
		for n in (roots[root_i] as Node).find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := n as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			var nm := String(mmi.name)
			var hit := false
			for pre: String in prefixes:
				if nm.begins_with(pre):
					hit = true
			if not hit:
				continue
			var mm := mmi.multimesh
			var box := mmi.global_transform * mm.get_aabb()
			if box.size.length() > 0.01 and box.position.x > hi.x + rmax + 5.0 or box.end.x < lo.x - rmax - 5.0 or box.position.z > hi.y + rmax + 5.0 or box.end.z < lo.y - rmax - 5.0:
				continue
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				var g := mmi.global_transform * t.origin
				var o := Vector2(g.x, g.z)
				if o.x < lo.x - rmax or o.x > hi.x + rmax or o.y < lo.y - rmax or o.y > hi.y + rmax:
					continue
				for j in pts.size():
					if o.distance_squared_to(pts[j]) < radii[j] * radii[j]:
						mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin))
						break


## Mesh arrays being filled.
class _Arrays:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## A triangle, wound to face up.
	func tri(a: int, b: int, c: int) -> void:
		var cy := (verts[b] - verts[a]).cross(verts[c] - verts[a]).y
		if cy < 0.0:
			indices.append_array([a, b, c])
		else:
			indices.append_array([a, c, b])

	func commit() -> ArrayMesh:
		if indices.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
