class_name ArmyView
extends Node3D
## An army group on the map: its warriors (Villager soldiers) each keeping a place in the
## army's formation, a standard-bearer with the clan's flag, and a gold ring under it when
## selected. The army moves along its path (Army.path, from GameWorld) at a marching pace,
## turning to face the way it goes; its warriors walk to their places and stand in the
## formation's stance.
##
## Formations (FORMATIONS): the shield wall (two close ranks, shields up, spears levelled),
## the line (two looser ranks), the boar's snout (svinfylking: a wedge, point forward), the
## column (two abreast, for the march) and the ring (a shield ring facing out on all sides).

const FORMATIONS := ["shield_wall", "line", "wedge", "column", "ring"]
const FORMATION_NAMES := {"shield_wall": "Shield wall", "line": "Line", "wedge": "Boar's snout",
	"column": "Column", "ring": "Shield ring"}
const PACE := 2.6

var army: Dictionary            # {id, name, size, formation, pos: Vector2, facing, path: Array}
var settlement: Settlement
var height_at: Callable
var _soldiers: Array = []
var _bearer: Villager
var _ring: MeshInstance3D
var _mat: ShaderMaterial


func setup(p_army: Dictionary, s: Settlement, ground: Callable) -> void:
	army = p_army
	settlement = s
	height_at = ground
	_mat = BuildingView.building_material(s.color)
	_mat.set_shader_parameter("height", 100.0)
	_mat.set_shader_parameter("people", true)
	var tunics := [s.color.darkened(0.35), Color(0.4, 0.34, 0.26), s.color.darkened(0.5), Color(0.3, 0.3, 0.32)]
	for i in int(army.size):
		var v := Villager.new()
		v.top_level = true
		add_child(v)
		v.setup(s.color, tunics[i % tunics.size()], _mat, ground, "idle", true)
		_soldiers.append(v)
	# The standard-bearer: the clan's flag on a tall pole.
	_bearer = Villager.new()
	_bearer.top_level = true
	add_child(_bearer)
	_bearer.setup(s.color, s.color.darkened(0.2), _mat, ground, "idle", true)
	var k := BuildingModels.Kit.new()
	k.post(Vector3(0.35, 0, 0), 4.2, 0.04, BuildingModels.DARK_WOOD)
	k.sphere(Vector3(0.35, 4.3, 0), 0.1, Color(0.9, 0.72, 0.3), 4, 8)
	var pole := MeshInstance3D.new()
	pole.mesh = k.commit()
	pole.material_override = _mat
	_bearer.add_child(pole)
	var flag := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(1.6, 1.0)
	pm.subdivide_width = 10
	pm.subdivide_depth = 5
	flag.mesh = pm
	flag.position = Vector3(0.35 + 0.8, 3.7, 0)
	flag.material_override = Emblem.flag_material(s.color, s.emblem)
	_bearer.add_child(flag)
	# The selection ring.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.no_depth_test = true
	_ring.material_override = rm
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)
	# Everyone starts in place.
	var slots := slots_for(String(army.formation), _soldiers.size())
	for i in _soldiers.size():
		var w := _world_slot(slots[i])
		(_soldiers[i] as Villager).position = Vector3(w.x, height_at.call(w), w.y)
	var bw := _world_slot(_bearer_slot(slots))
	_bearer.position = Vector3(bw.x, height_at.call(bw), bw.y)


func set_selected(on: bool) -> void:
	_ring.visible = on


func soldier_count() -> int:
	return _soldiers.size()


## Places in a formation for n warriors, as offsets from the army's centre: x to the right, y
## backwards (the army faces -y).
static func slots_for(f: String, n: int) -> Array:
	var out: Array = []
	match f:
		"shield_wall":
			var per := ceili(n / 2.0)
			for i in n:
				var rank := i / per
				var file := i % per
				out.append(Vector2((file - (per - 1) * 0.5) * 0.95, rank * 1.1))
		"line":
			var per := ceili(n / 2.0)
			for i in n:
				var rank := i / per
				var file := i % per
				out.append(Vector2((file - (per - 1) * 0.5) * 1.7 + (0.85 if rank == 1 else 0.0), rank * 2.0))
		"wedge":
			var row := 0
			var placed := 0
			while placed < n:
				var in_row := mini(row + 1, n - placed)
				for k in in_row:
					out.append(Vector2((k - row * 0.5) * 1.3, row * 1.2))
				placed += in_row
				row += 1
		"column":
			for i in n:
				out.append(Vector2((i % 2 - 0.5) * 1.2, (i / 2) * 1.4))
		"ring":
			var r := maxf(1.6, n * 1.0 / TAU)
			for i in n:
				var a := TAU * i / n
				out.append(Vector2(cos(a), sin(a)) * r)
	# Centred front to back.
	if not out.is_empty() and f != "ring":
		var back := 0.0
		for o: Vector2 in out:
			back = maxf(back, o.y)
		for i in out.size():
			out[i] = (out[i] as Vector2) - Vector2(0, back * 0.5)
	return out


func _bearer_slot(slots: Array) -> Vector2:
	if String(army.formation) == "ring":
		return Vector2.ZERO
	var back := 0.0
	for o: Vector2 in slots:
		back = maxf(back, o.y)
	return Vector2(0, back + 1.4)


func _world_slot(o: Vector2) -> Vector2:
	var f: float = army.facing
	var fwd := Vector2(-sin(f), -cos(f))
	var right := Vector2(-fwd.y, fwd.x)
	return (army.pos as Vector2) + right * o.x - fwd * o.y


func _process(delta: float) -> void:
	var path: Array = army.path
	var moving := false
	if not path.is_empty():
		var p: Vector2 = army.pos
		var target: Vector2 = path[0]
		var to := target - p
		if to.length() < 1.0:
			path.pop_front()
		else:
			moving = true
			# Slower while the ranks are still forming up.
			p += to.normalized() * minf(PACE * delta, to.length())
			army.pos = p
			army.facing = lerp_angle(float(army.facing), atan2(-to.x, -to.y), minf(delta * 2.0, 1.0))
	var f := String(army.formation)
	var slots := slots_for("column" if moving and f != "column" and path.size() > 1 else f, _soldiers.size())
	var how := "brace" if f == "shield_wall" and not moving else "guard"
	for i in _soldiers.size():
		var w := _world_slot(slots[i])
		var face: float = army.facing
		if f == "ring" and not moving:
			# Facing outwards from the ring's middle.
			var out := (w - (army.pos as Vector2))
			face = atan2(-out.x, -out.y)
		(_soldiers[i] as Villager).march_to(w, face, how)
	_bearer.march_to(_world_slot(_bearer_slot(slots)), float(army.facing), "guard")
	var c: Vector2 = army.pos
	var r := 2.5
	for o: Vector2 in slots:
		r = maxf(r, o.length() + 1.5)
	_ring.scale = Vector3(r, 1.0, r)
	_ring.global_position = Vector3(c.x, float(height_at.call(c)) + 0.3, c.y)
