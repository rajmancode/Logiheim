class_name HexMap
extends Node3D
## Loads a Gaea export, builds every hex level (LOD) and shows one at a time.
##
## Per level: a soft-stepped TerrainSurface, carved river channels and river water, trees,
## bushes and rocks, and (finest level only) grass. One sea surface is shared by all levels.
## Grid lines and highlights are drawn by the terrain and water shaders.

signal generated
signal level_changed(level_index: int)

@export var settings: HexMapSettings

var source: TerrainSource
var levels: Array[HexLevel] = []
var surfaces: Array[TerrainSurface] = []
## River paths per level (Array of Array[RiverPath]), for gameplay and debugging.
var river_paths: Array = []
## Water flow per level (lakes, catchment), or null when rivers are off.
var hydrology: Array = []
var active_level := -1
var auto_lod := true
## World y of the sea surface.
var sea_y := 0.0

var _level_roots: Array[Node3D] = []
## Border noise per level, shared by shaders (grid) and picking.
var _noises: Array[BorderNoise] = []
var _materials: Array[ShaderMaterial] = []
var _base_material: ShaderMaterial
var _water: MeshInstance3D
var _water_material: ShaderMaterial
var _wave_normal: NoiseTexture2D
var _lake_materials: Array[ShaderMaterial] = []
var _show_grid := true
var _show_icons := true
var _icon_roots: Array[Node3D] = []
## Fjords cut into this map (for tools and debugging).
var fjord_plan: FjordMaker
var volcano_plan: VolcanoMaker
var road_plan: RoadNetwork
var cave_plan: CaveSystem
## Cave being explored (-1 = on the surface), and the node holding the cave interiors.
var underground := -1
var _cave_root: Node3D


## Loads map.json from map_dir and builds the map. Returns false if loading failed.
func load_map(map_dir: String) -> bool:
	var src := TerrainSource.load_from_dir(map_dir)
	if src == null:
		return false
	source = src
	rebuild()
	return true


## Rebuilds all levels from the current source and settings (e.g. after changing hex size).
func rebuild() -> void:
	if source == null:
		return
	if settings == null:
		settings = HexMapSettings.new()
	MapSeed.set_seed(settings.seed)
	if _base_material == null:
		_base_material = TerrainMaterial.create()
	_clear()

	var t0 := Time.get_ticks_msec()
	var gen := HexMapGenerator.new(source, settings)
	levels = gen.build_levels()
	var courses: Array = []
	var lakes: LakeMaker = null
	var fjords: FjordMaker = null
	var volcano: VolcanoMaker = null
	var roads: RoadNetwork = null
	var caves: CaveSystem = null
	sea_y = gen.sea_y()
	for level in levels:
		var t1 := Time.get_ticks_msec()
		var root := Node3D.new()
		root.name = "Level%d" % level.level_index
		root.visible = false
		add_child(root)
		var noise := BorderNoise.new(level.hex_size, settings.border_noise)
		var surface := TerrainSurface.new(level, source, settings, gen)
		# Volcanoes first: everything after (rivers, lakes, fjords) works on the land with them.
		if level.level_index == 0:
			volcano = VolcanoMaker.plan(surface, settings)
			volcano_plan = volcano
		volcano.apply(surface)
		volcano.mark_level(level, surface)
		var paths: Array[RiverPath] = []
		var hydro: Hydrology = null
		if settings.rivers_enabled:
			# Water flow on this level's own terrain (lakes, water levels); the river
			# courses themselves come from the finest level so every level agrees.
			var stride := 2 if level.level_index == 0 else 1
			if level.level_index == 0:
				# Plan fjords and extra lakes on the finest terrain, then shape every level.
				hydro = Hydrology.from_surface(surface, stride, settings, source)
				fjords = FjordMaker.plan(hydro, settings)
				if fjords.count() > 0:
					fjords.apply(surface)
					hydro = Hydrology.from_surface(surface, stride, settings, source)
				lakes = LakeMaker.plan(hydro, source, settings)
				fjord_plan = fjords
			elif fjords != null:
				fjords.apply(surface)
			if fjords != null:
				fjords.mark_level(level, surface)
			if lakes != null:
				lakes.apply(surface)
			hydro = Hydrology.from_surface(surface, stride, settings, source)
			if level.level_index == 0:
				courses = RiverMeshBuilder.courses(hydro, settings)
			paths = RiverMeshBuilder.place(courses, level, surface, hydro, noise, settings, source)
			surface.mark_lakes(hydro)
			surface.carve(paths)
		# Caves (planned on the finest level) come first so trails can lead to them.
		if level.level_index == 0:
			caves = CaveSystem.plan(level, surface, settings)
			cave_plan = caves
		# Trails: planned on the finest level once rivers and lakes are known.
		if level.level_index == 0:
			var dests: Array = []
			for sy: Dictionary in caves.systems:
				for e: Dictionary in sy.entrances:
					dests.append((e.p as Vector2) + (e.dir as Vector2) * 12.0)
			roads = RoadNetwork.plan(level, surface, settings, dests)
			road_plan = roads
		roads.apply(level, surface)
		# No near-vertical walls: cap the slope once all shaping is done.
		surface.limit_slopes(settings.max_slope, paths)
		# Rivers never run above the ground beside them: settle the water onto the final banks.
		if not paths.is_empty():
			RiverMeshBuilder.settle(paths, surface)
			surface.carve_channels(paths)
		# Lakes from the final ground: shaping since the first pass (valleys, trails, the slope
		# limit) may have lowered a shore, so the water level is worked out again here; a lake
		# can then never stand higher than the ground that holds it.
		if hydro != null:
			hydro = Hydrology.from_surface(surface, 2 if level.level_index == 0 else 1, settings, source)
			for i in level.cell_count():
				level.lake[i] = 1 if hydro.lake_at(level.cell_center(i)) >= 0 else 0
		# Cave mouths: a ledge cut into the finished ground on every level.
		caves.apply(level, surface)
		var fp := Floodplain.build(level, surface, paths, settings)
		surface.finish_weights()
		var mat := TerrainMaterial.for_level(_base_material, level, noise, sea_y)
		mat.set_shader_parameter("flood_rise", settings.floodplain_depth + 0.9)
		mat.set_shader_parameter("relief", maxf(level.max_top_y() - sea_y, 10.0))
		mat.set_shader_parameter("show_grid", _show_grid)
		TerrainMeshBuilder.build(surface, mat, root)
		RiverMeshBuilder.build(paths, root)
		volcano.build_effects(surface, root)
		if level.level_index <= 1:
			roads.build_meshes(surface, root)
			caves.build_meshes(surface, root)
			RockFeatures.build(level, surface, settings, root)
		if level.level_index <= 1:
			RiverMeshBuilder.build_falls(paths, root)
		var lake_mat := RiverMeshBuilder.lake_material(_get_wave_normal())
		TerrainMaterial.set_grid(lake_mat, level, noise)
		lake_mat.set_shader_parameter("show_grid", _show_grid)
		_lake_materials.append(lake_mat)
		if hydro != null:
			RiverMeshBuilder.build_lakes(hydro, surface, lake_mat, root)
		fp.build_meshes(lake_mat, root)
		Vegetation.build(level, surface, settings, root)
		if level.level_index == 0 and settings.grass_enabled:
			GrassField.build(surface, settings, root)
		_level_roots.append(root)
		_noises.append(noise)
		_materials.append(mat)
		surfaces.append(surface)
		river_paths.append(paths)
		hydrology.append(hydro)
		print("HexMap: level %d (%.0f m hexes, %d x %d terrain) in %d ms" % [
			level.level_index, level.hex_size, surface.nx, surface.nz, Time.get_ticks_msec() - t1])
	if settings.resources_enabled:
		NaturalResources.place(levels, source, sea_y, settings.resource_abundance, settings.mask_threshold, surfaces[0])
		if cave_plan != null:
			cave_plan.place_resources(levels)
		for li in levels.size():
			ResourceProps.build_ground(levels[li], surfaces[li], _level_roots[li])
		for li in mini(2, levels.size()):
			ResourceProps.build(levels[li], surfaces[li], hydrology[li], _level_roots[li], settings.resource_prop_scale * (1.0 + 1.2 * li))
		_build_resource_icons()
		_build_cave_markers()
	if cave_plan != null and not cave_plan.systems.is_empty():
		_cave_root = Node3D.new()
		_cave_root.name = "CaveInteriors"
		add_child(_cave_root)
		cave_plan.build_interiors(surfaces[0], _cave_root)
	_build_water()
	print("HexMap: built %d levels for '%s' in %d ms" % [levels.size(), source.name, Time.get_ticks_msec() - t0])

	active_level = -1
	set_level(0)
	generated.emit()


func _clear() -> void:
	underground = -1
	if _cave_root != null:
		_cave_root.queue_free()
		_cave_root = null
	if _water != null:
		_water.visible = true
	for root in _level_roots:
		root.queue_free()
	_level_roots.clear()
	_icon_roots.clear()
	_noises.clear()
	_materials.clear()
	_lake_materials.clear()
	surfaces.clear()
	river_paths.clear()
	hydrology.clear()
	levels.clear()


func _build_water() -> void:
	if _water == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = load("res://shaders/water.gdshader")
		_water_material.set_shader_parameter("wave_normal", _get_wave_normal())
		_water = MeshInstance3D.new()
		_water.name = "Sea"
		_water.material_override = _water_material
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water)
	var size := source.world_size
	var plane := PlaneMesh.new()
	plane.size = size * 3.0
	plane.subdivide_width = 300
	plane.subdivide_depth = 300
	_water.mesh = plane
	_water.position = Vector3(size.x * 0.5, sea_y, size.y * 0.5)
	_water_material.set_shader_parameter("show_grid", _show_grid)


func _get_wave_normal() -> NoiseTexture2D:
	if _wave_normal == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		_wave_normal = NoiseTexture2D.new()
		_wave_normal.width = 512
		_wave_normal.height = 512
		_wave_normal.seamless = true
		_wave_normal.as_normal_map = true
		_wave_normal.bump_strength = 6.0
		_wave_normal.generate_mipmaps = true
		_wave_normal.noise = noise
	return _wave_normal


func current_level() -> HexLevel:
	return levels[active_level] if active_level >= 0 and active_level < levels.size() else null


func current_surface() -> TerrainSurface:
	return surfaces[active_level] if active_level >= 0 and active_level < surfaces.size() else null


## The cave system whose entrance is nearest to world point p (within max_dist), or -1.
func nearest_cave(p: Vector2, max_dist := 600.0) -> int:
	if cave_plan == null:
		return -1
	var best := -1
	var best_d := max_dist
	for si in cave_plan.systems.size():
		for e: Dictionary in cave_plan.systems[si].entrances:
			var d := (e.p as Vector2).distance_to(p)
			if d < best_d:
				best_d = d
				best = si
	return best


## Goes underground into cave system si: hides the surface world and shows the cave inside.
## Returns {"view": Vector3, "bounds": AABB} for the camera.
func enter_cave(si: int) -> Dictionary:
	if cave_plan == null or si < 0 or si >= cave_plan.systems.size():
		return {}
	var sy: Dictionary = cave_plan.systems[si]
	if not sy.has("interior"):
		return {}
	underground = si
	for root in _level_roots:
		root.visible = false
	if _water != null:
		_water.visible = false
	for n in _cave_root.get_children():
		n.visible = n == sy.interior
	return {"view": sy.view, "bounds": sy.bounds}


## Back to the surface.
func exit_cave() -> void:
	if underground < 0:
		return
	underground = -1
	for n in _cave_root.get_children():
		n.visible = false
	if _water != null:
		_water.visible = true
	for k in _level_roots.size():
		_level_roots[k].visible = k == active_level


## Cave floor height under p while exploring.
func cave_floor(p: Vector2) -> float:
	return cave_plan.floor_at(underground, p) if underground >= 0 else 0.0


func set_level(i: int) -> void:
	i = clampi(i, 0, levels.size() - 1)
	if i == active_level or underground >= 0:
		return
	active_level = i
	for k in _level_roots.size():
		_level_roots[k].visible = k == i
	if _water_material != null:
		TerrainMaterial.set_grid(_water_material, levels[i], _noises[i])
	set_highlight("hover", -1)
	set_highlight("select", -1)
	level_changed.emit(i)


## Picks the coarsest level whose hexes are still big enough on screen, with a little hysteresis.
func update_lod(camera_distance: float) -> void:
	if not auto_lod or levels.is_empty() or underground >= 0:
		return
	var want := 0
	for i in range(1, levels.size()):
		var threshold := levels[i].hex_size * settings.lod_distance_factor
		if i <= active_level:
			threshold *= 0.9
		if camera_distance > threshold:
			want = i
	set_level(want)


## kind is "hover" or "select"; cell -1 clears it. The shaders draw it.
func set_highlight(kind: String, cell: int) -> void:
	var level := current_level()
	var value := Vector3.ZERO
	if level != null and cell >= 0:
		var a := level.coords[cell]
		value = Vector3(a.x, a.y, 1.0)
	var param := kind + "_cell"
	if active_level >= 0 and active_level < _materials.size():
		_materials[active_level].set_shader_parameter(param, value)
	if active_level >= 0 and active_level < _lake_materials.size():
		_lake_materials[active_level].set_shader_parameter(param, value)
	if _water_material != null:
		_water_material.set_shader_parameter(param, value)


## Cave entrances: always marked (not part of the I overlay) on every level, at the mouth
## itself, with a label.
func _build_cave_markers() -> void:
	if cave_plan == null or cave_plan.systems.is_empty():
		return
	var tex: Texture2D = load("res://assets/icons/resources/cave.svg") if ResourceLoader.exists("res://assets/icons/resources/cave.svg") else null
	for li in levels.size():
		var root := Node3D.new()
		root.name = "CaveMarkers"
		_level_roots[li].add_child(root)
		var hs := levels[li].hex_size
		for si in cave_plan.systems.size():
			for e: Dictionary in cave_plan.systems[si].entrances:
				var p: Vector2 = e.p
				var pos := Vector3(p.x, surfaces[li].sample(p) + 6.0 + hs * 0.15, p.y)
				if tex != null:
					var sp := Sprite3D.new()
					sp.texture = tex
					sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					sp.fixed_size = true
					sp.pixel_size = 0.00045
					sp.no_depth_test = true
					sp.shaded = false
					sp.render_priority = 12
					sp.position = pos
					sp.visibility_range_end = hs * 60.0
					root.add_child(sp)
				var lb := Label3D.new()
				lb.text = "Cave %d" % (si + 1)
				lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lb.fixed_size = true
				lb.pixel_size = 0.0003
				lb.font_size = 34
				lb.outline_size = 10
				lb.modulate = Color(1.0, 0.8, 0.5)
				lb.no_depth_test = true
				lb.render_priority = 13
				lb.offset = Vector2(0, -95)
				lb.position = pos
				lb.visibility_range_end = hs * 60.0
				root.add_child(lb)


## Resource icons: one badge per resource hex on each level, always facing the camera at a
## fixed size on screen, with "x2"/"x3" for richer deposits.
func _build_resource_icons() -> void:
	var textures: Dictionary = {}
	for li in levels.size():
		var level := levels[li]
		var root := Node3D.new()
		root.name = "ResourceIcons"
		root.visible = _show_icons
		_level_roots[li].add_child(root)
		_icon_roots.append(root)
		var outline := ResourceProps.build_outlines(level, surfaces[li], sea_y)
		if outline != null:
			root.add_child(outline)
		var centers := {}
		for d: Dictionary in level.deposits:
			centers[d.center] = d
		for i in level.cell_count():
			var kind := level.resource[i]
			if kind == 0:
				continue
			var d: Dictionary = centers.get(i, {})
			var is_center: bool = not d.is_empty() and int(d.kind) == kind
			# Zoomed out, show what's worth fighting over: common finds only in big deposits.
			if li > 0 and kind in NaturalResources.COMMON and (not is_center or d.size < 8):
				continue
			if not is_center and li > 1:
				continue
			if not textures.has(kind):
				var path := "res://assets/icons/resources/%s.svg" % NaturalResources.key(kind)
				textures[kind] = load(path) if ResourceLoader.exists(path) else null
			var tex: Texture2D = textures[kind]
			if tex == null:
				continue
			var c := level.cell_center(i)
			var pos := Vector3(c.x, maxf(surfaces[li].sample(c), sea_y) + level.hex_size * 0.25, c.y)
			var sprite := Sprite3D.new()
			sprite.texture = tex
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.fixed_size = true
			# The deposit's centre gets the full badge; its other hexes a small, faint one so
			# you can see how far it spreads.
			sprite.pixel_size = 0.00042 if is_center else 0.0002
			sprite.modulate = Color(1, 1, 1, 1.0 if is_center else 0.6)
			sprite.no_depth_test = true
			sprite.shaded = false
			sprite.render_priority = 10 if is_center else 9
			sprite.position = pos
			# Fade out far away so the horizon doesn't fill with icons.
			var reach := level.hex_size * (40.0 if is_center else 18.0)
			sprite.visibility_range_end = reach
			sprite.visibility_range_end_margin = reach * 0.2
			sprite.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(sprite)
			# A companion resource sharing the hex gets its own small badge beside the main one.
			if li == 0 and level.resource2.size() == level.cell_count() and level.resource2[i] != 0:
				var k2 := level.resource2[i]
				if not textures.has(k2):
					var path2 := "res://assets/icons/resources/%s.svg" % NaturalResources.key(k2)
					textures[k2] = load(path2) if ResourceLoader.exists(path2) else null
				if textures[k2] != null:
					var s2 := Sprite3D.new()
					s2.texture = textures[k2]
					s2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					s2.fixed_size = true
					s2.pixel_size = sprite.pixel_size * 0.75
					s2.no_depth_test = true
					s2.shaded = false
					s2.render_priority = sprite.render_priority + 1
					s2.position = pos
					s2.offset = Vector2(70, 40) if is_center else Vector2(90, 50)
					s2.visibility_range_end = reach
					s2.visibility_range_end_margin = reach * 0.2
					s2.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
					root.add_child(s2)
			if is_center and d.get("cave", false):
				var cl := Label3D.new()
				cl.text = "cave"
				cl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				cl.fixed_size = true
				cl.pixel_size = 0.0003
				cl.font_size = 32
				cl.outline_size = 10
				cl.modulate = Color(0.95, 0.85, 0.6)
				cl.no_depth_test = true
				cl.render_priority = 11
				cl.offset = Vector2(0, -70)
				cl.position = pos
				cl.visibility_range_end = reach
				root.add_child(cl)
			if is_center and d.size > 1:
				var label := Label3D.new()
				label.text = "%d" % d.size
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.fixed_size = true
				label.pixel_size = 0.00034
				label.font_size = 40
				label.outline_size = 12
				label.no_depth_test = true
				label.render_priority = 11
				label.offset = Vector2(52, -46)
				label.position = pos
				label.visibility_range_end = reach
				label.visibility_range_end_margin = reach * 0.2
				label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				root.add_child(label)


func set_resource_icons_visible(on: bool) -> void:
	_show_icons = on
	for r in _icon_roots:
		r.visible = on


func resource_icons_visible() -> bool:
	return _show_icons


func set_grid_visible(on: bool) -> void:
	_show_grid = on
	for m in _materials:
		m.set_shader_parameter("show_grid", on)
	for m in _lake_materials:
		m.set_shader_parameter("show_grid", on)
	if _water_material != null:
		_water_material.set_shader_parameter("show_grid", on)


## Ground (or sea surface) height at a world point on the active level.
func ground_height(p: Vector2) -> float:
	var s := current_surface()
	return maxf(s.sample(p), sea_y) if s != null else 0.0


## Finds where a ray hits the active level's terrain or sea. Returns a cell index or -1.
func pick(origin: Vector3, dir: Vector3) -> int:
	var level := current_level()
	var s := current_surface()
	if level == null or s == null or dir.y > -1e-4:
		return -1
	var top := level.max_top_y() + settings.terrain_detail * source.height_range * settings.height_scale + 20.0
	var t := maxf(0.0, (origin.y - top) / -dir.y)
	var t_end := (origin.y - (sea_y - 1.0)) / -dir.y
	var step := s.spacing * 1.5
	var prev := t
	var hit := -1.0
	while t <= t_end:
		var p := origin + dir * t
		if p.y <= ground_height(Vector2(p.x, p.z)):
			hit = t
			break
		prev = t
		t += step
	if hit < 0.0:
		return -1
	# Refine between the last miss and the hit.
	var lo := prev
	var hi := hit
	for k in 8:
		var mid := (lo + hi) * 0.5
		var p := origin + dir * mid
		if p.y <= ground_height(Vector2(p.x, p.z)):
			hi = mid
		else:
			lo = mid
	var q := origin + dir * hi
	return _noises[active_level].cell_at(level, Vector2(q.x, q.z))


## Height of the surface under a world point on the active level (for the camera pivot).
func surface_height(p: Vector2) -> float:
	return ground_height(p)
