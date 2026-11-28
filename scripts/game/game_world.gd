class_name GameWorld
extends Node3D
## The game once the players have landed: their settlements, buildings and land.
##
## Each player starts with a town hall raised at their landing site. The town hall claims the
## hexes within a few steps of it as the settlement's land; spending influence pushes that out
## a step at a time ("Expand"), and watchtowers claim land round themselves. Buildings may only
## go up on your own land, on dry, fairly level ground no other building stands on; gatherers
## must stand on the resource they gather (a woodcutter in timber, a mine on ore...), a fishing
## hut on the shore by fish. The land is drawn as a border in the settlement's colour.
##
## Clicking a building selects it (`selected`); while placing, a see-through model follows
## the mouse, green where it may go and red (with the reason) where it may not.

signal selection_changed(record: Dictionary)
signal message(text: String)

var hex_map: HexMap
var settlements: Array[Settlement] = []
var active := 0
var speed := 1.0
var paused := false
var running := false
var placing := ""
var selected: Dictionary = {}

var _views := {}          # uid -> BuildingView
var _owner := {}          # finest-level cell -> settlement index
var _occupied := {}       # finest-level cell -> record
var _borders: Array[MeshInstance3D] = []
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_label: Label3D
var _ghost_cell := -1
var _ghost_ok := false
var _territory_dirty := true
var _ground: SettlementGround   # plots and paths worn into the land
var _ground_dirty := false


func _ready() -> void:
	_ground = SettlementGround.new()
	_ground.name = "SettlementGround"
	add_child(_ground)
	_ground.setup(self)
	_ghost = MeshInstance3D.new()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.no_depth_test = false
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_ghost_label = UiStyle.map_label("", 34, UiStyle.PARCHMENT, Vector2(0, 0), 14)
	_ghost.add_child(_ghost_label)


func lv() -> HexLevel:
	return hex_map.levels[0]


func ground(p: Vector2) -> float:
	return hex_map.ground_height(p)


## Starts the game: a settlement per player, each with its town hall going up at its landing.
func start(map: HexMap, players: Array, sites: Array) -> void:
	clear()
	hex_map = map
	if not hex_map.level_changed.is_connected(_on_level_changed):
		hex_map.level_changed.connect(_on_level_changed)
	for k in players.size():
		var p: Dictionary = players[k]
		var s := Settlement.new(k, String(p.name), p.color)
		s.emblem = p.get("emblem", Emblem.default_for(k))
		settlements.append(s)
		var site: Dictionary = sites[p.site]
		var cell := lv().nearest_cell(site.p)
		_raise(s, "town_hall", cell, true)
	active = 0
	running = true
	_territory_dirty = true
	message.emit("%s has come ashore. Raise your settlement!" % settlements[0].player_name)


func clear() -> void:
	running = false
	placing = ""
	selected = {}
	for v in _views.values():
		(v as Node).queue_free()
	_views.clear()
	for b in _borders:
		b.queue_free()
	_borders.clear()
	settlements.clear()
	_owner.clear()
	_occupied.clear()
	if _ground != null:
		_ground.clear()
	if _ghost != null:
		_ghost.visible = false


func me() -> Settlement:
	return settlements[active] if active < settlements.size() else null


func set_active(i: int) -> void:
	if settlements.is_empty():
		return
	active = posmod(i, settlements.size())
	cancel_placement()
	select({})


# --------------------------------------------------------------------------- placing

func begin_placement(id: String) -> void:
	placing = id
	var d: Dictionary = BuildingDefs.DEFS[id]
	_ghost.mesh = BuildingModels.shape(String(d.model)).mesh
	_ghost.visible = false
	_ghost_cell = -1
	select({})


func cancel_placement() -> void:
	placing = ""
	_ghost.visible = false


## Can `id` go up on `cell` for the active settlement? [ok, reason, resource kind]
func check(id: String, cell: int) -> Array:
	var s := me()
	var d: Dictionary = BuildingDefs.DEFS[id]
	var l := lv()
	if cell < 0:
		return [false, "", 0]
	if int(_owner.get(cell, -1)) != active:
		return [false, "Outside your land", 0]
	if HexMapGenerator.is_water(l.terrain[cell]) or l.lake[cell] == 1:
		return [false, "Can't build on water", 0]
	if l.river[cell] == 1:
		return [false, "A river runs here", 0]
	if l.cave.size() > cell and l.cave[cell] >= 0:
		return [false, "A cave mouth is here", 0]
	if _occupied.has(cell):
		return [false, "Already built on", 0]
	if l.slope[cell] > 0.75:
		return [false, "Too steep", 0]
	if d.get("unique", false) and s.count(id) > 0:
		return [false, "You already have one", 0]
	var kind := 0
	var needs = d.get("needs", null)
	if needs is Array:
		for r in [l.resource[cell], l.resource2[cell] if l.resource2.size() > cell else 0]:
			if r != 0 and (needs as Array).has(r):
				kind = r
				break
		if kind == 0:
			var names := PackedStringArray()
			for r in needs:
				names.append(NaturalResources.display_name(r))
			return [false, "Needs %s on this hex" % " or ".join(names), 0]
	elif needs is String and needs == "fish":
		if not _fish_near(cell):
			return [false, "Needs fish in the water beside it", 0]
	if d.has("near"):
		kind = _resource_near(cell, d.near, 2)
		if kind == 0:
			var names := PackedStringArray()
			for r in d.near:
				names.append(NaturalResources.display_name(r))
			return [false, "Needs %s within two hexes" % " or ".join(names), 0]
	if d.get("coast", false) and not _coastal(cell):
		return [false, "Must stand on the coast", kind]
	if not s.can_afford(d.cost):
		return [false, "Not enough: %s" % Goods.describe(_missing(s, d.cost)), kind]
	return [true, "", kind]


## The first of `kinds` on the hex or within `radius` hexes of it (0 if none).
func _resource_near(cell: int, kinds: Array, radius: int) -> int:
	var l := lv()
	var a := l.coords[cell]
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var j := l.index_of(a + Vector2i(dq, dr))
			if j < 0:
				continue
			for r in [l.resource[j], l.resource2[j] if l.resource2.size() > j else 0]:
				if r != 0 and kinds.has(r):
					return r
	return 0


## Beside the sea: a neighbouring hex is water.
func _coastal(cell: int) -> bool:
	var l := lv()
	for k in 6:
		var j := l.index_of(HexCoords.neighbor(l.coords[cell], k))
		if j >= 0 and HexMapGenerator.is_water(l.terrain[j]) and l.lake[j] == 0:
			return true
	return false


func _fish_near(cell: int) -> bool:
	var l := lv()
	var a := l.coords[cell]
	for dq in range(-2, 3):
		for dr in range(maxi(-2, -dq - 2), mini(2, -dq + 2) + 1):
			var j := l.index_of(a + Vector2i(dq, dr))
			if j >= 0 and (l.resource[j] == NaturalResources.Kind.FISH or (l.resource2.size() > j and l.resource2[j] == NaturalResources.Kind.FISH)):
				if HexMapGenerator.is_water(l.terrain[j]) or l.lake[j] == 1:
					return true
	return false


func _missing(s: Settlement, cost: Dictionary) -> Dictionary:
	var m := {}
	for k in cost:
		var short := float(cost[k]) - float(s.stock.get(k, 0))
		if short > 0.0:
			m[k] = ceilf(short)
	return m


## The mouse over a hex while placing: move the ghost there and colour it.
func hover(cell: int) -> void:
	if placing == "" or not running:
		return
	if cell == _ghost_cell:
		return
	_ghost_cell = cell
	if cell < 0:
		_ghost.visible = false
		return
	var r := check(placing, cell)
	_ghost_ok = r[0]
	var c := lv().cell_center(cell)
	_ghost.visible = true
	_ghost.position = Vector3(c.x, _seat(c, BuildingModels.shape(String(BuildingDefs.DEFS[placing].model)).size), c.y)
	_ghost.rotation.y = _facing(c)
	_ghost_mat.albedo_color = Color(0.35, 1.0, 0.45, 0.45) if _ghost_ok else Color(1.0, 0.3, 0.25, 0.45)
	_ghost_label.text = String(BuildingDefs.DEFS[placing].name) if _ghost_ok else String(r[1])
	(_ghost_label.get_node("Shadow") as Label3D).text = _ghost_label.text
	_ghost_label.modulate = Color(0.75, 1.0, 0.75) if _ghost_ok else Color(1.0, 0.65, 0.55)
	_ghost_label.position = Vector3(0, float(BuildingModels.shape(String(BuildingDefs.DEFS[placing].model)).height) + 2.5, 0)


## A click on the map. Returns true if the game used it.
func click(cell: int) -> bool:
	if not running:
		return false
	if placing != "":
		var r := check(placing, cell)
		if not r[0]:
			message.emit(String(r[1]) if String(r[1]) != "" else "Can't build there")
			return true
		var s := me()
		var d: Dictionary = BuildingDefs.DEFS[placing]
		s.pay(d.cost)
		var rec := _raise(s, placing, cell, false, int(r[2]))
		message.emit("%s is being built." % String(d.name))
		# Keep placing more of the same with shift held; otherwise done.
		if not Input.is_key_pressed(KEY_SHIFT):
			cancel_placement()
		select(rec)
		return true
	if _occupied.has(cell):
		select(_occupied[cell])
		return true
	select({})
	return false


func select(rec: Dictionary) -> void:
	if not selected.is_empty() and _views.has(selected.uid):
		(_views[selected.uid] as BuildingView).set_selected(false)
	selected = rec
	if not rec.is_empty() and _views.has(rec.uid):
		(_views[rec.uid] as BuildingView).set_selected(true)
	selection_changed.emit(rec)


func demolish(rec: Dictionary) -> void:
	if rec.is_empty() or rec.id == "town_hall":
		return
	var s: Settlement = settlements[_settlement_of(rec)]
	var d: Dictionary = BuildingDefs.DEFS[rec.id]
	s.refund(d.cost, 0.5 if s.is_built(rec) else 1.0)
	s.remove_building(rec)
	_occupied.erase(rec.cell)
	if _views.has(rec.uid):
		var v: BuildingView = _views[rec.uid]
		var tw := v.create_tween()
		tw.tween_property(v, "scale", Vector3(1, 0.01, 1), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(v.queue_free)
		_views.erase(rec.uid)
		_ground_dirty = true
	if d.has("territory"):
		_territory_dirty = true
	select({})
	message.emit("%s pulled down." % String(d.name))


func expand() -> void:
	var s := me()
	if s == null:
		return
	if s.influence < s.expand_cost():
		message.emit("Not enough influence (%d needed)." % s.expand_cost())
		return
	s.influence -= s.expand_cost()
	s.expansions += 1
	_territory_dirty = true
	message.emit("Your land reaches further.")


func _settlement_of(rec: Dictionary) -> int:
	for k in settlements.size():
		if settlements[k].buildings.has(rec):
			return k
	return active


## A building record and its view, on `cell`.
func _raise(s: Settlement, id: String, cell: int, built: bool, kind := 0) -> Dictionary:
	var c := lv().cell_center(cell)
	var info := BuildingModels.shape(String(BuildingDefs.DEFS[id].model))
	var pos := Vector3(c.x, _seat(c, info.size), c.y)
	var rec := s.add_building(id, cell, pos, kind, false)
	_occupied[cell] = rec
	var v := BuildingView.new()
	v.position = pos
	v.rotation.y = _facing(c) if id != "town_hall" else _facing_sea(c)
	v.set_meta("sea_y", hex_map.sea_y)
	add_child(v)
	v.setup(rec, s, ground)
	_views[rec.uid] = v
	_ground_dirty = true
	_clear_ground(c, maxf(info.size.x, info.size.y) * 0.75 + 4.0)
	if built:
		rec.progress = 0.0
	return rec


## Base height for a footprint: the lowest ground under it (the plinth fills the slope).
## Base height for a footprint: a little above the middle of the ground under it, so the
## building is dug into the slope on the high side and stands on a dry-stone terrace on the low
## side (BuildingView.make_foundation); never below the sea.
func _seat(c: Vector2, size: Vector2) -> float:
	var hs: Array = []
	var r := maxf(size.x, size.y) * 0.4
	hs.append(hex_map.current_surface().sample(c))
	for ring in [0.5, 1.0]:
		for k in 12:
			hs.append(hex_map.current_surface().sample(c + Vector2.from_angle(TAU * k / 12.0) * r * ring))
	hs.sort()
	var y: float = hs[int(hs.size() * 0.55)]
	return maxf(y, hex_map.sea_y + 0.5) + 0.05


## Doors face the town hall (or, for the hall, the sea).
func _facing(c: Vector2) -> float:
	var s := me()
	if s == null or s.hall.is_empty():
		return 0.0
	var h: Vector3 = s.hall.pos
	var to := Vector2(h.x, h.z) - c
	if to.length() < 1.0:
		return 0.0
	return atan2(-to.x, -to.y)


func _facing_sea(c: Vector2) -> float:
	var best := Vector2.ZERO
	for k in 16:
		var dir := Vector2.from_angle(TAU * k / 16.0)
		var depth := 0.0
		for r in [20.0, 40.0, 70.0]:
			depth += maxf(hex_map.sea_y - hex_map.surfaces[0].sample(c + dir * r), 0.0)
		best += dir * depth
	if best.length() < 0.01:
		return 0.0
	return atan2(-best.x, -best.y)


## Trees, bushes and boulders under a new building are cleared away.
func _clear_ground(c: Vector2, r: float) -> void:
	for root_i in mini(2, hex_map.get("_level_roots").size()):
		var root: Node = hex_map.get("_level_roots")[root_i]
		for n in root.get_children():
			var mmi := n as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			var nm := String(mmi.name)
			if not (nm.begins_with("conifer") or nm.begins_with("broadleaf") or nm.begins_with("bush") or nm.begins_with("rock")):
				continue
			var mm := mmi.multimesh
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				if Vector2(t.origin.x, t.origin.z).distance_to(c) < r:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin))


func _on_level_changed(_i: int) -> void:
	# Re-seat buildings on this level's ground (coarser levels are smoothed a little).
	for v in _views.values():
		var bv := v as BuildingView
		var p := Vector2(bv.position.x, bv.position.z)
		bv.position.y = _seat(p, bv.info.size)
		bv.make_foundation()
	_territory_dirty = true
	_ground_dirty = true


# --------------------------------------------------------------------------- land

func _update_territory() -> void:
	_territory_dirty = false
	_owner.clear()
	var l := lv()
	for s in settlements:
		s.territory.clear()
	# Each settlement claims round its hall and towers; land already claimed stays with its first owner.
	for s in settlements:
		var centres: Array = []
		for b: Dictionary in s.buildings:
			var d: Dictionary = BuildingDefs.DEFS[b.id]
			if d.has("territory") and (s.is_built(b) or b.id == "town_hall"):
				var r := int(d.territory) + (s.expansions if b.id == "town_hall" else 0)
				centres.append([l.coords[b.cell], r])
		for cen: Array in centres:
			var a: Vector2i = cen[0]
			var r: int = cen[1]
			for dq in range(-r, r + 1):
				for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
					var j := l.index_of(a + Vector2i(dq, dr))
					if j < 0 or (_owner.has(j) and _owner[j] != s.index):
						continue
					_owner[j] = s.index
					s.territory[j] = true
	for b in _borders:
		b.queue_free()
	_borders.clear()
	for s in settlements:
		_borders.append(_border_mesh(s))


## The settlement's border: a smooth ribbon round its land (BorderRibbon): an inked rim and a
## bright line in the owner's colour with a glint running along it, a stitched line inside and
## a soft wash of colour fading into the land.
func _border_mesh(s: Settlement) -> MeshInstance3D:
	var l := lv()
	var data := MeshData.new()
	var loops := BorderRibbon.loops(l, s.territory.keys(), func(j: int) -> bool: return s.territory.has(j))
	BorderRibbon.add_ribbons(data, loops, hex_map.current_surface(), hex_map.sea_y, 16.0, 4.0, 0.45, s.color)
	var mi := MeshInstance3D.new()
	mi.name = "Border"
	mi.mesh = data.to_mesh()
	mi.material_override = BorderRibbon.material(0, 4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --------------------------------------------------------------------------- time

func _process(delta: float) -> void:
	if not running:
		return
	if _territory_dirty:
		_update_territory()
	if _ground_dirty:
		_ground_dirty = false
		_ground.rebuild(_views.values())
	if paused:
		return
	var dt := delta * speed
	for s in settlements:
		var events := s.tick(dt)
		for e: Dictionary in events:
			var rec: Dictionary = e.building
			if _views.has(rec.uid) and s.index == active:
				(_views[rec.uid] as BuildingView).pop(e.gains, e.get("uses", {}))
		for b: Dictionary in s.just_finished:
			_ground_dirty = true
			if BuildingDefs.DEFS[b.id].has("territory"):
				_territory_dirty = true
			if s.index == active and b.id != "town_hall":
				message.emit("%s finished." % String(BuildingDefs.DEFS[b.id].name))
		s.just_finished.clear()
