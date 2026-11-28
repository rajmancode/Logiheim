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
## An army was selected or let go ({} when none).
signal army_selected(army: Dictionary)
signal message(text: String)
## A resource hex was clicked (-1: let go).
signal resource_selected(cell: int)

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
var _infra: Infrastructure      # roads, hill roads and bridges
var _infra_dirty := false
# The Road tool lays a whole run at once: from the clan's network to the hex under the mouse.
var _road_path: Array = []       # the new hexes it would lay, network end first
var _road_paid := 0              # how many of them the stores can pay for
var _road_ghosts: Array[MeshInstance3D] = []
var _road_ghost_mats: Array[StandardMaterial3D] = []
var _road_last := -1             # the hex last laid to while dragging
var _reach := {}                # settlement index -> {cell: true} it can get to
var _army_views := {}           # army id -> ArmyView
var hover_cell := -1                  # the hex under the mouse (-1 over the interface)
var selected_resource := -1           # the resource hex whose panel is open
var _expand_parent: Dictionary = {}   # the building an expansion being placed belongs to
var _synergy_dirty := true
var selected_army: Dictionary = {}

## The steepest a hex may be to walk across (without a hill road) and to build on; gatherers
## work steeper ground (a mine up the hillside), anything may stand on a terraced hill road hex.
const WALK_SLOPE := 0.75
const GATHER_SLOPE := 1.7
const ROAD_SLOPE := 2.4


func _ready() -> void:
	_ground = SettlementGround.new()
	_ground.name = "SettlementGround"
	add_child(_ground)
	_ground.setup(self)
	_infra = Infrastructure.new()
	_infra.name = "Infrastructure"
	add_child(_infra)
	_infra.setup(self)
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
	for col: Color in [Color(0.4, 1.0, 0.5, 0.3), Color(1.0, 0.75, 0.25, 0.3)]:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		_road_ghost_mats.append(m)


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
	if _infra != null:
		_infra.clear()
	_reach.clear()
	for v in _army_views.values():
		(v as Node).queue_free()
	_army_views.clear()
	selected_army = {}
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
	if d.get("road", false):
		var hexm := CylinderMesh.new()
		hexm.radial_segments = 6
		hexm.top_radius = lv().hex_size * 0.92
		hexm.bottom_radius = lv().hex_size * 0.92
		hexm.height = 0.6
		_ghost.mesh = hexm
	else:
		_ghost.mesh = BuildingModels.shape(String(d.model)).mesh
	_ghost.visible = false
	_ghost_cell = -1
	select({})


func cancel_placement() -> void:
	placing = ""
	_expand_parent = {}
	_ghost.visible = false
	_road_path = []
	_road_last = -1
	_show_road_path()


## Can `id` go up on `cell` for the active settlement? [ok, reason, resource kind]
func check(id: String, cell: int) -> Array:
	var s := me()
	var d: Dictionary = BuildingDefs.DEFS[id]
	var l := lv()
	if cell < 0:
		return [false, "", 0]
	if d.get("road", false):
		return _check_road(s, cell)
	if d.has("expansion_of"):
		var why := _check_expansion(s, d, cell)
		if why != "":
			return [false, why, 0]
	if d.get("outside", false):
		var who := int(_owner.get(cell, -1))
		if who >= 0 and who != active:
			return [false, "Another clan holds this land", 0]
		if who < 0 and _steps_from_land(s, cell) > 10:
			return [false, "Too far from your land (ten hexes at most)", 0]
	elif int(_owner.get(cell, -1)) != active:
		return [false, "Outside your land", 0]
	if HexMapGenerator.is_water(l.terrain[cell]) or l.lake[cell] == 1:
		return [false, "Can't build on water", 0]
	if l.river[cell] == 1:
		return [false, "A river runs here", 0]
	if _wet_share(cell) > (0.6 if (d.get("coast", false) or d.get("needs", null) is String) else 0.25):
		return [false, "Too much of this hex is under water", 0]
	if l.cave.size() > cell and l.cave[cell] >= 0:
		return [false, "A cave mouth is here", 0]
	if _occupied.has(cell):
		return [false, "Already built on", 0]
	var steep := GATHER_SLOPE if (d.category == "harvest" or d.has("near") or d.has("expansion_of")) else WALK_SLOPE
	if d.get("flat", false):
		steep = 0.6
	if s.roads.get(cell, "") == "hill":
		steep = maxf(steep, 1.5)
	if s.roads.has(cell) and not d.get("road", false):
		return [false, "A road runs here", 0]
	if l.slope[cell] > steep:
		return [false, "Too steep - lay a hill road here first" if steep < 1.5 else "Too steep", 0]
	if not d.get("outside", false) and not d.has("expansion_of") and not _reachable(s, cell):
		return [false, "No way to get there - lay a road (a bridge over a river, a hill road up a slope)", 0]
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


## How much of a hex's middle lies at or under the sea (0..1), so buildings don't stand in the surf.
func _wet_share(cell: int) -> float:
	var c := lv().cell_center(cell)
	var surf := hex_map.current_surface()
	var wet := 0
	var n := 0
	for ring: float in [0.0, 0.3, 0.6]:
		for k in (1 if ring == 0.0 else 8):
			n += 1
			if surf.sample(c + Vector2.from_angle(TAU * k / 8.0) * lv().hex_size * ring) < hex_map.sea_y + 0.4:
				wet += 1
	return float(wet) / float(n)


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


## Where an expansion may go: beside its main building or one of its other parts, while the
## building has room for more ("" if it may).
func _check_expansion(s: Settlement, d: Dictionary, cell: int) -> String:
	if _expand_parent.is_empty() or not (d.expansion_of as Array).has(String(_expand_parent.id)):
		return "Expand it from its building's panel"
	if s.expansions_of(_expand_parent).size() >= BuildingDefs.MAX_EXPANSIONS:
		return "No room for more (%d at most)" % BuildingDefs.MAX_EXPANSIONS
	var l := lv()
	var cells := [int(_expand_parent.cell)]
	for e: Dictionary in s.expansions_of(_expand_parent):
		cells.append(int(e.cell))
	for c: int in cells:
		if HexCoords.distance(l.coords[c], l.coords[cell]) == 1:
			return ""
	return "Must join the %s or its other parts" % String(BuildingDefs.DEFS[_expand_parent.id].name).to_lower()


## Starts placing an expansion of a building.
func begin_expansion(parent: Dictionary, ext_id: String) -> void:
	_expand_parent = parent
	begin_placement(ext_id)
	_expand_parent = parent


## Whether new road may run over a hex (leaving out reach and price).
func _road_cell_ok(s: Settlement, j: int) -> bool:
	var l := lv()
	if j < 0 or int(_owner.get(j, -1)) != active or s.roads.has(j) or _occupied.has(j):
		return false
	if (HexMapGenerator.is_water(l.terrain[j]) and l.river[j] == 0) or l.lake[j] == 1:
		return false
	return l.slope[j] <= ROAD_SLOPE


## The run of new road the Road tool would lay to reach `target` from the clan's network (its
## roads, its hall and outposts): the cheapest way over its land - level ground first, hill
## roads and bridges only where they save a long way round. The new hexes in order from the
## network end; [] if there is no way (or the hex is already on the network).
func road_path(s: Settlement, target: int) -> Array:
	if not _road_cell_ok(s, target):
		return []
	var l := lv()
	var dist := {}
	var prev := {}
	var open: Array = []
	for c: int in s.roads:
		dist[c] = 0.0
		open.append(c)
	for b: Dictionary in s.buildings:
		if b.id == "town_hall" or (b.id == "outpost" and s.is_built(b)):
			dist[int(b.cell)] = 0.0
			open.append(int(b.cell))
	var done := {}
	while not open.is_empty():
		# The nearest open hex (a clan's land is a few hundred hexes: a plain scan will do).
		var bi := 0
		for i in range(1, open.size()):
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var c: int = open[bi]
		open.remove_at(bi)
		if done.has(c):
			continue
		done[c] = true
		if c == target:
			break
		for k in 6:
			var j := l.index_of(HexCoords.neighbor(l.coords[c], k))
			if j < 0 or done.has(j) or not _road_cell_ok(s, j):
				continue
			var kind := Infrastructure.kind_for(l, j)
			var step := 1.0 + (3.0 if kind == "bridge" else (1.2 if kind == "hill" else 0.0))
			# Keep on in a straight line where it costs nothing more: roads that run true.
			if prev.has(c):
				var p: int = prev[c]
				var straight := (l.cell_center(j) - l.cell_center(c)).normalized().dot((l.cell_center(c) - l.cell_center(p)).normalized())
				step += 0.12 * (1.0 - straight)
			var nd := float(dist[c]) + step
			if nd < float(dist.get(j, INF)) and nd < 80.0:
				dist[j] = nd
				prev[j] = c
				open.append(j)
	if not prev.has(target):
		return []
	var out: Array = []
	var c := target
	while prev.has(c):
		out.push_front(c)
		c = prev[c]
	return out


## What the Road tool says about laying to `cell`, and the run it would lay.
func _plan_road(cell: int) -> void:
	var s := me()
	_road_path = road_path(s, cell)
	_road_paid = 0
	var total := {}
	for j: int in _road_path:
		for g in Infrastructure.cost_for(Infrastructure.kind_for(lv(), j)).keys():
			total[g] = float(total.get(g, 0)) + float(Infrastructure.cost_for(Infrastructure.kind_for(lv(), j))[g])
	var acc := {}
	for j: int in _road_path:
		var cost := Infrastructure.cost_for(Infrastructure.kind_for(lv(), j))
		for g in cost:
			acc[g] = float(acc.get(g, 0)) + float(cost[g])
		if not s.can_afford(acc):
			break
		_road_paid += 1
	_road_total = total


var _road_total := {}


## The run the Road tool would lay, a hex outline on each: green where it is paid for, amber
## beyond what the stores hold.
func _show_road_path() -> void:
	var l := lv() if hex_map != null and not hex_map.levels.is_empty() else null
	var n := _road_path.size() if l != null else 0
	while _road_ghosts.size() < n:
		var g := MeshInstance3D.new()
		g.mesh = _ghost.mesh
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.scale = Vector3(0.82, 0.5, 0.82)
		g.rotation.y = PI / 6.0
		add_child(g)
		_road_ghosts.append(g)
	for i in _road_ghosts.size():
		var g := _road_ghosts[i]
		g.visible = i < n
		if i < n:
			var c := l.cell_center(int(_road_path[i]))
			g.mesh = _ghost.mesh
			g.position = Vector3(c.x, ground(c) + 0.25, c.y)
			g.material_override = _road_ghost_mats[0 if i < _road_paid else 1]


## A road dragged out over the map: each hex the mouse comes to joins the run.
func road_drag(cell: int) -> void:
	if not running or placing == "" or not BuildingDefs.DEFS[placing].get("road", false):
		return
	if cell < 0 or cell == _road_last:
		return
	_road_last = cell
	_lay_road(cell, false)


## Lays the Road tool's run to `cell` (as far as the stores pay for). Returns false if nothing
## could be laid.
func _lay_road(cell: int, say: bool) -> bool:
	var s := me()
	if cell != _ghost_cell or _road_path.is_empty():
		_plan_road(cell)
	if _road_path.is_empty() or _road_paid == 0:
		if say:
			var r := check(placing, cell)
			message.emit(String(r[1]) if not r[0] and String(r[1]) != "" else ("Not enough to lay that road" if not _road_path.is_empty() else "No way to run a road there from your roads"))
		return false
	for i in _road_paid:
		var j: int = _road_path[i]
		var kind := Infrastructure.kind_for(lv(), j)
		s.pay(Infrastructure.cost_for(kind))
		s.roads[j] = kind
	if say and _road_paid < _road_path.size():
		message.emit("Laid %d of %d hexes of road - not enough for the rest" % [_road_paid, _road_path.size()])
	_infra_dirty = true
	_reach.erase(s.index)
	_ghost_cell = -1
	hover(cell)
	return true


## Whether a road may go on this hex, and what kind: [ok, reason, 0, kind, cost].
func _check_road(s: Settlement, cell: int) -> Array:
	var l := lv()
	if int(_owner.get(cell, -1)) != active:
		return [false, "Outside your land", 0]
	if (HexMapGenerator.is_water(l.terrain[cell]) and l.river[cell] == 0) or l.lake[cell] == 1:
		return [false, "Can't lay a road on open water", 0]
	if s.roads.has(cell):
		return [false, "There is a road here", 0]
	if _occupied.has(cell):
		return [false, "A building stands here", 0]
	if l.slope[cell] > ROAD_SLOPE:
		return [false, "Too steep even for a hill road", 0]
	if not _reachable(s, cell):
		return [false, "Start from land you can reach", 0]
	var kind := Infrastructure.kind_for(l, cell)
	var cost := Infrastructure.cost_for(kind)
	if not s.can_afford(cost):
		return [false, "Not enough: %s" % Goods.describe(_missing(s, cost)), 0, kind, cost]
	return [true, "", 0, kind, cost]


## Whether the clan can get to a hex: it, or a hex beside it, is reached from the hall or an
## outpost over its own land that can be walked - not a river without a bridge, not a slope
## too steep without a hill road.
func _reachable(s: Settlement, cell: int) -> bool:
	var r := _reach_of(s)
	if r.has(cell):
		return true
	var l := lv()
	for k in 6:
		var j := l.index_of(HexCoords.neighbor(l.coords[cell], k))
		if j >= 0 and r.has(j):
			return true
	return false


func _reach_of(s: Settlement) -> Dictionary:
	if _reach.has(s.index):
		return _reach[s.index]
	var l := lv()
	var out := {}
	var queue: Array = []
	for b: Dictionary in s.buildings:
		if b.id == "town_hall" or (b.id == "outpost" and s.is_built(b)):
			out[b.cell] = true
			queue.append(b.cell)
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		for k in 6:
			var j := l.index_of(HexCoords.neighbor(l.coords[c], k))
			if j < 0 or out.has(j) or not s.territory.has(j):
				continue
			if not _walkable(s, j):
				continue
			out[j] = true
			queue.append(j)
	_reach[s.index] = out
	return out


func _walkable(s: Settlement, j: int) -> bool:
	var l := lv()
	if s.roads.has(j):
		return true
	if (HexMapGenerator.is_water(l.terrain[j])) or l.lake[j] == 1 or l.river[j] == 1:
		return false
	return l.slope[j] <= WALK_SLOPE


## Hex steps from a cell to the nearest hex of the clan's land (99 if far).
func _steps_from_land(s: Settlement, cell: int) -> int:
	var l := lv()
	var a := l.coords[cell]
	var best := 99
	for t: int in s.territory:
		best = mini(best, HexCoords.distance(a, l.coords[t]))
	return best


# --------------------------------------------------------------------------- armies

## Gathers the clan's warriors (up to 24) into an army group in front of the hall.
func muster() -> Dictionary:
	var s := me()
	var n := mini(int(s.stock.get("warriors", 0)), 24)
	if n < 2:
		message.emit("Not enough warriors to muster (2 at least - train them at the barracks)")
		return {}
	s.stock["warriors"] = float(s.stock.get("warriors", 0)) - n
	var hall_v: BuildingView = _views.get(s.hall.uid)
	var front := Vector2(s.hall.pos.x, s.hall.pos.z)
	var facing := 0.0
	if hall_v != null:
		var f3 := hall_v.to_global((hall_v.info.door as Vector3) + Vector3(0, 0, -14.0))
		front = Vector2(f3.x, f3.z)
		facing = hall_v.rotation.y
	# They form up on the nearest dry, level, open hex to the hall's door.
	var l := lv()
	var start := front
	var best := INF
	var a0 := l.coords[s.hall.cell]
	for dq in range(-3, 4):
		for dr in range(maxi(-3, -dq - 3), mini(3, -dq + 3) + 1):
			var j := l.index_of(a0 + Vector2i(dq, dr))
			if j < 0 or j == int(s.hall.cell) or _occupied.has(j) or not _walkable(s, j) or s.roads.has(j):
				continue
			var c := l.cell_center(j)
			if hex_map.current_surface().sample(c) < hex_map.sea_y + 0.6:
				continue
			var d := c.distance_to(front)
			if d < best:
				best = d
				start = c
	if best < INF:
		var away := start - Vector2(s.hall.pos.x, s.hall.pos.z)
		facing = atan2(-away.x, -away.y)
	var name: String = Settlement.ARMY_NAMES[(s._next_army - 1) % Settlement.ARMY_NAMES.size()]
	var a := {"id": s._next_army, "name": name.capitalize() if name.begins_with("the") else name, "size": n,
		"formation": "shield_wall", "pos": start, "facing": facing, "path": []}
	a.name = name.substr(0, 1).to_upper() + name.substr(1)
	s._next_army += 1
	s.armies.append(a)
	var v := ArmyView.new()
	add_child(v)
	v.setup(a, s, ground)
	_army_views[_army_key(s, a)] = v
	select_army(a)
	message.emit("%s musters: %d warriors." % [a.name, n])
	return a


func _army_key(s: Settlement, a: Dictionary) -> String:
	return "%d_%d" % [s.index, int(a.id)]


func _army_owner(a: Dictionary) -> Settlement:
	for s in settlements:
		if s.armies.has(a):
			return s
	return null


## The active player's army near a point on the map ({} if none).
func army_at(p: Vector2) -> Dictionary:
	var s := me()
	if s == null:
		return {}
	for a: Dictionary in s.armies:
		var r := 3.0 + sqrt(float(a.size)) * 1.2
		if (a.pos as Vector2).distance_to(p) < r:
			return a
	return {}


func select_army(a: Dictionary) -> void:
	if not selected_army.is_empty():
		var old: ArmyView = _army_views.get(_army_key(_army_owner(selected_army), selected_army)) if _army_owner(selected_army) != null else null
		if old != null:
			old.set_selected(false)
	selected_army = a
	if not a.is_empty():
		select({})
		cancel_placement()
		var v: ArmyView = _army_views.get(_army_key(_army_owner(a), a))
		if v != null:
			v.set_selected(true)
	army_selected.emit(a)


func set_formation(a: Dictionary, f: String) -> void:
	a.formation = f


## Sends an army to a point: the way there over land, round water and cliffs, across rivers
## only by bridges.
func order_army(a: Dictionary, target: Vector2) -> void:
	var l := lv()
	var from := l.cell_at(a.pos)
	var to := l.cell_at(target)
	if to < 0 or not _army_can_cross(to):
		message.emit("The army can't go there")
		return
	if _occupied.has(to):
		message.emit("A building stands there")
		return
	var cells := _army_path(from, to)
	if cells.is_empty():
		message.emit("No way there - rivers need bridges, cliffs need hill roads")
		return
	var pts: Array = []
	for c: int in cells.slice(1, cells.size() - 1):
		pts.append(l.cell_center(c))
	pts.append(target)
	a.path = pts


func _army_can_cross(j: int) -> bool:
	var l := lv()
	if (HexMapGenerator.is_water(l.terrain[j]) and l.river[j] == 0) or l.lake[j] == 1:
		return false
	var road := false
	for s in settlements:
		if s.roads.has(j):
			road = true
	if l.river[j] == 1 and not road:
		return false
	# Round buildings, not through them.
	if _occupied.has(j):
		return false
	return road or l.slope[j] <= GATHER_SLOPE


## A* over the finest hexes for an army: cells from `a` to `b` ([] if no way).
func _army_path(a: int, b: int) -> Array:
	var l := lv()
	if a < 0 or b < 0:
		return []
	var came := {a: -1}
	var cost := {a: 0.0}
	var heap: Array = []
	RoadNetwork._push(heap, [0.0, a])
	var goal := l.cell_center(b)
	var steps := 0
	while not heap.is_empty() and steps < 60000:
		steps += 1
		var top: Array = RoadNetwork._pop(heap)
		var c: int = top[1]
		if c == b:
			break
		for k in 6:
			var j := l.index_of(HexCoords.neighbor(l.coords[c], k))
			if j < 0 or not _army_can_cross(j):
				continue
			var nc: float = float(cost[c]) + 1.0 + l.slope[j] * 1.5
			if not cost.has(j) or nc < float(cost[j]):
				cost[j] = nc
				came[j] = c
				RoadNetwork._push(heap, [nc + l.cell_center(j).distance_to(goal) / l.hex_size, j])
	if not came.has(b):
		return []
	var out: Array = []
	var c2 := b
	while c2 >= 0:
		out.push_front(c2)
		c2 = came[c2]
	return out


## Sends an army's warriors home to the hall's stores.
func disband(a: Dictionary) -> void:
	var s := _army_owner(a)
	if s == null:
		return
	s.stock["warriors"] = float(s.stock.get("warriors", 0)) + int(a.size)
	s.armies.erase(a)
	var key := _army_key(s, a)
	if _army_views.has(key):
		(_army_views[key] as Node).queue_free()
		_army_views.erase(key)
	if selected_army == a:
		selected_army = {}
		army_selected.emit({})
	message.emit("%s is disbanded." % String(a.name))


## Right-click: stop placing, or let go of the selected army. True if it did something.
func right_click() -> bool:
	if placing != "":
		cancel_placement()
		return true
	if not selected_army.is_empty():
		select_army({})
		return true
	return false


## Neighbour bonuses (BuildingDefs.SYNERGIES): each building's speed, and why; and how grand
## each main building looks for the expansions it has.
func _update_synergies() -> void:
	var l := lv()
	for s in settlements:
		for b: Dictionary in s.buildings:
			var bonus := 0.0
			var why: Array = []
			var rules: Array = BuildingDefs.SYNERGIES.get(b.id, [])
			var produces: bool = not BuildingDefs.recipes(String(b.id)).is_empty() and not BuildingDefs.DEFS[b.id].has("influence")
			var store := false
			for o: Dictionary in s.buildings:
				if o == b or not s.is_built(o):
					continue
				if HexCoords.distance(l.coords[int(b.cell)], l.coords[int(o.cell)]) > 2:
					continue
				for rule: Array in rules:
					if (rule[0] as Array).has(String(o.id)) and not why.has(rule[2]):
						bonus += float(rule[1])
						why.append(rule[2])
				if o.id == "warehouse" and produces:
					store = true
			if store:
				bonus += 0.1
				why.append("a storehouse close by")
			b.bonus = 1.0 + minf(bonus, 0.6)
			b.synergy = why
		for b: Dictionary in s.buildings:
			var v: BuildingView = _views.get(b.uid)
			if v != null and int(b.get("parent", -1)) >= 0:
				var pv: BuildingView = _views.get(int(b.get("link", b.parent)))
				if pv != null:
					var d := Vector2(v.position.x, v.position.z).distance_to(Vector2(pv.position.x, pv.position.z))
					v.set_link(d - minf(float(pv.info.size.x), float(pv.info.size.y)) * 0.5 - 1.0)
			if v != null and not BuildingDefs.expansions_for(String(b.id)).is_empty():
				var n := s.expansions_of(b).filter(func(e: Dictionary) -> bool: return s.is_built(e)).size()
				v.set_level(n)


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
	hover_cell = cell
	if placing == "" or not running:
		return
	if cell == _ghost_cell:
		return
	_ghost_cell = cell
	if cell < 0:
		_ghost.visible = false
		_road_path = []
		_show_road_path()
		return
	var r := check(placing, cell)
	_ghost_ok = r[0]
	var c := lv().cell_center(cell)
	_ghost.visible = true
	if BuildingDefs.DEFS[placing].get("road", false):
		_ghost.position = Vector3(c.x, ground(c) + 0.3, c.y)
		_ghost.rotation.y = PI / 6.0
		_plan_road(cell)
		_show_road_path()
		var why := String(r[1])
		if why == "Start from land you can reach" or why.begins_with("Not enough"):
			why = ""
		var run := _road_path.size()
		_ghost_ok = run > 0 and _road_paid > 0
		_ghost_mat.albedo_color = (Color(0.35, 1.0, 0.45, 0.45) if _road_paid == run else Color(1.0, 0.75, 0.25, 0.45)) if _ghost_ok else Color(1.0, 0.3, 0.25, 0.35)
		var kinds := {}
		for j: int in _road_path:
			kinds[Infrastructure.kind_for(lv(), j)] = true
		var what := "Bridge" if kinds.has("bridge") and run == 1 else ("Hill road" if kinds.has("hill") and run == 1 else "Road")
		if _ghost_ok:
			_ghost_label.text = "%s, %d hex%s - %s" % [what, run, "" if run == 1 else "es", Goods.describe(_road_total)]
			if _road_paid < run:
				_ghost_label.text += "\n(stores pay for %d)" % _road_paid
		elif run > 0:
			_ghost_label.text = "Not enough: %s" % Goods.describe(_road_total)
		else:
			_ghost_label.text = why if why != "" else "No way to run a road here from your roads"
		(_ghost_label.get_node("Shadow") as Label3D).text = _ghost_label.text
		_ghost_label.modulate = Color(0.75, 1.0, 0.75) if _ghost_ok else Color(1.0, 0.65, 0.55)
		_ghost_label.position = Vector3(0, 4.0, 0)
		return
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
	if placing == "":
		var p := hex_map.last_pick
		var hit := army_at(Vector2(p.x, p.z))
		if not hit.is_empty():
			select_army(hit)
			return true
		if not selected_army.is_empty() and cell >= 0:
			order_army(selected_army, Vector2(p.x, p.z))
			return true
	if placing != "" and BuildingDefs.DEFS[placing].get("road", false):
		_road_last = cell
		_lay_road(cell, true)
		return true
	if placing != "":
		var r := check(placing, cell)
		if not r[0]:
			message.emit(String(r[1]) if String(r[1]) != "" else "Can't build there")
			return true
		var s := me()
		var d: Dictionary = BuildingDefs.DEFS[placing]
		if d.get("road", false):
			_road_last = cell
			_lay_road(cell, true)
			return true
		s.pay(d.cost)
		var rec := _raise(s, placing, cell, false, int(r[2]), _expand_parent if d.has("expansion_of") else {})
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
	if cell >= 0 and resource_at(cell) != 0:
		selected_resource = cell
		resource_selected.emit(cell)
	return false


## The building under a ray (its box), nearest first: {cell, point}, or {} if none - so a
## click on a roof picks that building, not the hex behind it.
func pick_object(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := INF
	var out := {}
	for uid in _views:
		var v: BuildingView = _views[uid]
		if not is_instance_valid(v) or not v.visible:
			continue
		var inv := v.global_transform.affine_inverse()
		var o := inv * origin
		var d := inv.basis * dir
		var lo := Vector3(-float(v.info.size.x) * 0.5, -0.5, -float(v.info.size.y) * 0.5)
		var hi := Vector3(float(v.info.size.x) * 0.5, float(v.info.height), float(v.info.size.y) * 0.5)
		var t0 := 0.0
		var t1 := INF
		var hit := true
		for a in 3:
			if absf(d[a]) < 1e-6:
				if o[a] < lo[a] or o[a] > hi[a]:
					hit = false
					break
				continue
			var ta := (lo[a] - o[a]) / d[a]
			var tb := (hi[a] - o[a]) / d[a]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		if hit and t0 <= t1 and t0 < best:
			best = t0
			out = {"cell": int(v.record.cell), "point": v.global_position, "t": t0}
	return out


## The main resource on a hex (0 if none).
func resource_at(cell: int) -> int:
	var l := lv()
	if cell < 0 or cell >= l.resource.size():
		return 0
	return int(l.resource[cell])


## "Build <id>" from a resource's panel: raised on that hex if it can be, otherwise placing starts
## so it can go on a hex nearby.
func build_here(id: String, cell: int) -> void:
	begin_placement(id)
	var r := check(id, cell)
	if r[0]:
		click(cell)
		if placing == id:
			cancel_placement()
		return
	message.emit("%s - %s. Place it on a hex nearby." % [String(BuildingDefs.DEFS[id].name), String(r[1]) if String(r[1]) != "" else "can't go on this hex"])


func select(rec: Dictionary) -> void:
	if not rec.is_empty() and not selected_army.is_empty():
		select_army({})
	if not selected.is_empty() and _views.has(selected.uid):
		(_views[selected.uid] as BuildingView).set_selected(false)
	selected = rec
	if selected_resource >= 0:
		selected_resource = -1
		resource_selected.emit(-1)
	if not rec.is_empty() and _views.has(rec.uid):
		(_views[rec.uid] as BuildingView).set_selected(true)
	selection_changed.emit(rec)


func demolish(rec: Dictionary) -> void:
	if rec.is_empty() or rec.id == "town_hall":
		return
	var s: Settlement = settlements[_settlement_of(rec)]
	var d: Dictionary = BuildingDefs.DEFS[rec.id]
	for e: Dictionary in s.expansions_of(rec):
		demolish(e)
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
		_synergy_dirty = true
		_infra_dirty = true
		_reach.clear()
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
func _raise(s: Settlement, id: String, cell: int, built: bool, kind := 0, parent: Dictionary = {}) -> Dictionary:
	var c := lv().cell_center(cell)
	var info := BuildingModels.shape(String(BuildingDefs.DEFS[id].model))
	var pos := Vector3(c.x, _seat(c, info.size), c.y)
	var rec := s.add_building(id, cell, pos, kind, false)
	_occupied[cell] = rec
	var v := BuildingView.new()
	v.position = pos
	v.rotation.y = _facing(c) if id != "town_hall" else _facing_sea(c)
	if not parent.is_empty():
		# An expansion turns to face its main building.
		rec.parent = int(parent.uid)
		# It joins its main building if it touches it, else the part of the works it touches.
		var join: Dictionary = parent
		var l := lv()
		if HexCoords.distance(l.coords[cell], l.coords[int(parent.cell)]) > 1:
			for e: Dictionary in s.expansions_of(parent):
				if e != rec and HexCoords.distance(l.coords[cell], l.coords[int(e.cell)]) == 1:
					join = e
					break
		rec.link = int(join.uid)
		var to := Vector2(join.pos.x, join.pos.z) - c
		v.rotation.y = atan2(-to.x, -to.y)
	v.set_meta("sea_y", hex_map.sea_y)
	add_child(v)
	v.setup(rec, s, ground)
	_views[rec.uid] = v
	_ground_dirty = true
	_synergy_dirty = true
	_infra_dirty = true
	_reach.clear()
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
		bv.conform()
		bv.make_foundation()
	_territory_dirty = true
	_ground_dirty = true
	_infra_dirty = true


# --------------------------------------------------------------------------- land

func _update_territory() -> void:
	_territory_dirty = false
	_reach.clear()
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
		Atmosphere.time_scale = 1.0
		return
	Atmosphere.time_scale = 0.0 if paused else speed
	if _territory_dirty:
		_update_territory()
	if _ground_dirty:
		_ground_dirty = false
		_ground.rebuild(_views.values())
	if _infra_dirty:
		_infra_dirty = false
		_infra.rebuild()
	if _synergy_dirty:
		_synergy_dirty = false
		_update_synergies()
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
			_synergy_dirty = true
			if BuildingDefs.DEFS[b.id].has("territory"):
				_territory_dirty = true
			if s.index == active and b.id != "town_hall":
				message.emit("%s finished." % String(BuildingDefs.DEFS[b.id].name))
		s.just_finished.clear()
