class_name LandingMarkers
extends Node3D
## The landing sites on the map: a tall banner on a pole at each, with the place's name. Free
## sites fly a pale banner; a claimed one flies its player's colour with their name under the
## place's. The site in focus stands out (a ring on the ground, the banner bobbing).

var _items: Array = []   # {root, flag: MeshInstance3D, mat, label: Label3D, owner: Label3D, ring, p}
var _focused := -1
var _t := 0.0


func build(sites: Array) -> void:
	for c in get_children():
		c.queue_free()
	_items.clear()
	_focused = -1
	for i in sites.size():
		var s: Dictionary = sites[i]
		var p: Vector2 = s.p
		var root := Node3D.new()
		root.position = Vector3(p.x, float(s.y), p.y)
		add_child(root)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.35
		cyl.height = 16.0
		pole.mesh = cyl
		pole.position = Vector3(0, 8.0, 0)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.32, 0.21, 0.12)
		pole.material_override = wood
		root.add_child(pole)
		# The banner: a long cloth hanging from a cross-bar, cut in a swallowtail.
		var flag := MeshInstance3D.new()
		flag.mesh = _banner_mesh()
		flag.position = Vector3(0.3, 15.5, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.86, 0.74)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		flag.material_override = mat
		root.add_child(flag)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 9.0
		torus.outer_radius = 10.5
		ring.mesh = torus
		ring.position = Vector3(0, 0.5, 0)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(1.0, 0.85, 0.4, 0.8)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = rmat
		ring.visible = false
		root.add_child(ring)
		var label := UiStyle.map_label(String(s.name), 46, UiStyle.PARCHMENT, Vector2(0, 0), 13)
		label.position = Vector3(0, 19.0, 0)
		root.add_child(label)
		var owner_label := UiStyle.map_label("", 36, UiStyle.GOLD, Vector2(0, -40), 13)
		owner_label.position = Vector3(0, 19.0, 0)
		root.add_child(owner_label)
		_items.append({"root": root, "flag": flag, "mat": mat, "label": label, "owner": owner_label, "ring": ring, "p": p})


## Colours and names from the players' landings; `focused` is the site shown in the chooser.
func update_state(players: Array, focused: int) -> void:
	_focused = focused
	for i in _items.size():
		var it: Dictionary = _items[i]
		var who := -1
		for k in players.size():
			if players[k].site == i:
				who = k
		(it.mat as StandardMaterial3D).albedo_color = players[who].color if who >= 0 else Color(0.9, 0.86, 0.74)
		(it.owner as Label3D).text = players[who].name if who >= 0 else ""
		var sh := (it.owner as Label3D).get_node_or_null("Shadow") as Label3D
		if sh != null:
			sh.text = (it.owner as Label3D).text
		(it.owner as Label3D).modulate = (players[who].color as Color).lightened(0.35) if who >= 0 else UiStyle.GOLD
		(it.ring as MeshInstance3D).visible = i == focused


## Only the claimed landings stay up once play starts.
func keep_claimed(players: Array) -> void:
	for i in _items.size():
		var claimed := false
		for p: Dictionary in players:
			if p.site == i:
				claimed = true
		(_items[i].root as Node3D).visible = claimed
		(_items[i].ring as MeshInstance3D).visible = false
	_focused = -1


func show_all() -> void:
	for it: Dictionary in _items:
		(it.root as Node3D).visible = true


## The site whose banner is nearest p (within `reach` metres), or -1.
func site_near(p: Vector2, reach := 45.0) -> int:
	var best := -1
	var bd := reach
	for i in _items.size():
		var d := (_items[i].p as Vector2).distance_to(p)
		if d < bd and (_items[i].root as Node3D).visible:
			bd = d
			best = i
	return best


func _process(delta: float) -> void:
	_t += delta
	for i in _items.size():
		var it: Dictionary = _items[i]
		var flag := it.flag as MeshInstance3D
		# The banner stirs in the wind; the one in focus lifts and turns to the viewer.
		flag.rotation = Vector3(0, sin(_t * 1.3 + i) * 0.25, sin(_t * 2.1 + i * 1.7) * 0.05)
		var lift := (sin(_t * 3.0) * 0.6 + 1.2) if i == _focused else 0.0
		flag.position.y = 15.5 + lift
		if i == _focused:
			(it.ring as MeshInstance3D).rotation.y = _t * 0.8


static var _banner: ArrayMesh


static func _banner_mesh() -> ArrayMesh:
	if _banner != null:
		return _banner
	# A cloth 6 m wide and 8 m long hanging down from the bar, with a swallowtail cut.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 6.0
	var h := 8.0
	var pts := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, -h, 0), Vector3(w * 0.5, -h * 0.7, 0), Vector3(0, -h, 0)]
	st.set_normal(Vector3(0, 0, 1))
	for tri in [[0, 1, 3], [1, 2, 3], [0, 3, 4]]:
		for k in tri:
			st.add_vertex(pts[k])
	# The bar it hangs from.
	_banner = st.commit()
	return _banner
