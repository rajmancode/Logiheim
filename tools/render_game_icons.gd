extends SceneTree
## Renders the pictures for the game's icons: every building from its own model and every good
## from its model (scripts/game/goods_models.gd), on a transparent background, three-quarter
## view, lit from the upper left. tools/make_game_icons.py then frames them into badges.
##
## Usage (needs a window, not --headless):
##   godot --path . -s tools/render_game_icons.gd -- <out dir>
## writes <out dir>/buildings/<id>.png and <out dir>/goods/<id>.png (512 px).

const SIZE := 512


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://icon_renders"
	DirAccess.make_dir_recursive_absolute(out + "/buildings")
	DirAccess.make_dir_recursive_absolute(out + "/goods")
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 28.0
	vp.add_child(cam)
	cam.current = true
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	var mat := BuildingView.building_material(Color(0.72, 0.16, 0.12))
	mi.material_override = mat
	var jobs: Array = []
	for id in BuildingDefs.DEFS:
		var d: Dictionary = BuildingDefs.DEFS[id]
		var shp := BuildingModels.shape(String(d.model))
		mat.set_shader_parameter("height", float(shp.height))
		jobs.append(["buildings", id, shp.mesh, true])
	for id in Goods.INFO.keys() + ["influence"]:
		jobs.append(["goods", id, GoodsModels.mesh(id), false])
	# Let the shaders compile before the first picture (it came out empty otherwise).
	for f in 30:
		await process_frame
	for j: Array in jobs:
		var m: Mesh = j[2]
		mi.mesh = m
		mat.set_shader_parameter("build", 1.0)
		mat.set_shader_parameter("height", 40.0)
		var box := m.get_aabb()
		if j[3]:
			# Buildings: leave out the plinth under the ground.
			box = box.intersection(AABB(box.position + Vector3(0, -box.position.y, 0), Vector3(box.size.x, box.end.y, box.size.z)))
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var dir := Vector3(0.75, 0.62, -1.0).normalized()
		cam.position = c + dir * r / sin(deg_to_rad(cam.fov * 0.5)) * 0.98
		cam.look_at(c)
		for f in 4:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png("%s/%s/%s.png" % [out, j[0], j[1]])
		print("ICON ", j[0], "/", j[1])
	# What the badges need to know: each building's category and what it gives, each good's colour.
	var manifest := {"buildings": {}, "goods": {}}
	for id in BuildingDefs.DEFS:
		var d: Dictionary = BuildingDefs.DEFS[id]
		var product := ""
		var recs := BuildingDefs.recipes(id)
		if not recs.is_empty() and not (recs[0].makes as Dictionary).is_empty():
			product = String((recs[0].makes as Dictionary).keys()[0])
		manifest.buildings[id] = {"category": d.category, "product": product}
	for id in Goods.INFO.keys() + ["influence"]:
		manifest.goods[id] = {"color": (Goods.color(id) if Goods.INFO.has(id) else Color(0.55, 0.35, 0.75)).to_html(false)}
	var f := FileAccess.open(out + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	quit()
