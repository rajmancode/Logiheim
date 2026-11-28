class_name Settlement
extends RefCounted
## One player's settlement and its economy (pure logic; GameWorld draws it).
##
## People live in houses (the town hall and longhouses) and grow while there is food and room;
## they eat fish, meat and bread. They staff buildings in the order they were raised. A
## building under construction gets built a little every second (faster with idle hands to
## help); once standing, it works through its cycle as fast as its staff allow, using and
## making goods - unless something it uses has run out or the stores are full. Influence comes
## from the town hall, temples, towers and mead halls, and is spent to push the town hall's
## land outwards.

signal changed

var index := 0
var player_name := ""
var color := Color.WHITE
var stock := {}
var buildings: Array = []     # records, see add_building()
var population := 4
var influence := 0.0
var expansions := 0
var hall: Dictionary = {}
## Hexes (finest level cell indices) this settlement holds: cell -> true.
var territory := {}

## Buildings finished since the world last looked (it reports and clears them).
var just_finished: Array = []
var _grow_timer := 0.0
var _eat_timer := 0.0
var _hungry := 0
var _next_id := 1

const START_STOCK := {"wood": 60, "stone": 30, "fish": 20, "grain": 10, "bread": 10, "tools": 4}
const GROW_TIME := 8.0
const EAT_TIME := 12.0


func _init(p_index: int, p_name: String, p_color: Color) -> void:
	index = p_index
	player_name = p_name
	color = p_color
	stock = START_STOCK.duplicate()


## A new building record. Construction starts at once (its cost is paid by the caller).
func add_building(id: String, cell: int, pos: Vector3, resource_kind := 0, built := false) -> Dictionary:
	var b := {"uid": _next_id, "id": id, "cell": cell, "pos": pos, "kind": resource_kind,
		"progress": 1.0 if built else 0.0, "timer": 0.0, "staff": 0, "status": "", "node": null,
		"working": false}
	_next_id += 1
	buildings.append(b)
	if id == "town_hall":
		hall = b
	changed.emit()
	return b


func remove_building(b: Dictionary) -> void:
	buildings.erase(b)
	changed.emit()


func is_built(b: Dictionary) -> bool:
	return float(b.progress) >= 1.0


func count(id: String) -> int:
	return buildings.filter(func(b): return b.id == id).size()


func housing() -> int:
	var h := 0
	for b: Dictionary in buildings:
		if is_built(b) or b.id == "town_hall":
			h += int(BuildingDefs.DEFS[b.id].get("housing", 0))
	return h


func storage() -> int:
	var s := 0
	for b: Dictionary in buildings:
		if is_built(b) or b.id == "town_hall":
			s += int(BuildingDefs.DEFS[b.id].get("storage", 0))
	return s


func stored() -> float:
	var t := 0.0
	for k in stock:
		if k != "warriors":
			t += float(stock[k])
	return t


func food() -> float:
	var t := 0.0
	for f in Goods.FOOD:
		t += float(stock.get(f, 0))
	return t


func workers_needed() -> int:
	var n := 0
	for b: Dictionary in buildings:
		if is_built(b):
			n += int(BuildingDefs.DEFS[b.id].get("workers", 0))
	return n


func idle() -> int:
	var used := 0
	for b: Dictionary in buildings:
		used += int(b.staff)
	return maxi(population - used, 0)


func influence_rate() -> float:
	var r := 0.0
	for b: Dictionary in buildings:
		var d: Dictionary = BuildingDefs.DEFS[b.id]
		if is_built(b) and d.has("influence") and (int(d.get("workers", 0)) == 0 or int(b.staff) > 0):
			r += float(d.influence)
	return r


func expand_cost() -> int:
	return 25 * (expansions + 1)


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if float(stock.get(k, 0)) < float(cost[k]) - 0.001:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost:
		stock[k] = float(stock.get(k, 0)) - float(cost[k])


func refund(cost: Dictionary, share: float) -> void:
	for k in cost:
		stock[k] = float(stock.get(k, 0)) + floorf(float(cost[k]) * share)


## Advances the settlement by dt seconds. Returns production events for the visuals:
## [{building, gains: {good: amount}}].
func tick(dt: float) -> Array:
	var events: Array = []
	# Staff: people fill the standing buildings in the order they were raised.
	var free := population
	for b: Dictionary in buildings:
		var need := int(BuildingDefs.DEFS[b.id].get("workers", 0)) if is_built(b) else 0
		b.staff = mini(need, free)
		free -= b.staff
	# Construction: everything being built goes up together; idle hands speed it along.
	var sites := buildings.filter(func(b): return not is_built(b))
	if not sites.is_empty():
		var hands := clampf(float(free) / float(sites.size()), 0.0, 3.0)
		var rate := 0.5 + 0.25 * hands
		for b: Dictionary in sites:
			var d: Dictionary = BuildingDefs.DEFS[b.id]
			b.progress = minf(float(b.progress) + dt * rate / maxf(float(d.build_time), 1.0), 1.0)
			b.status = "Being built - %d%%" % int(float(b.progress) * 100.0)
			b.working = false
			if is_built(b):
				b.status = "Finished"
				just_finished.append(b)
				changed.emit()
	# Work.
	for b: Dictionary in buildings:
		if not is_built(b):
			continue
		var d: Dictionary = BuildingDefs.DEFS[b.id]
		var gains := _gains(b, d)
		if gains.is_empty():
			b.working = int(b.staff) > 0 or int(d.get("workers", 0)) == 0
			if b.status == "Finished" or b.status.begins_with("Being"):
				b.status = "Standing"
			if d.has("influence") or d.has("housing") or d.has("storage"):
				b.status = _passive_status(d)
			continue
		var need := int(d.get("workers", 0))
		if need > 0 and int(b.staff) == 0:
			b.status = "Idle - no one to work here"
			b.working = false
			continue
		var uses: Dictionary = d.get("uses", {})
		var missing := ""
		for k in uses:
			if float(stock.get(k, 0)) < float(uses[k]):
				missing = Goods.display_name(k)
		var full := stored() >= float(storage()) and not gains.has("influence")
		if missing != "":
			b.status = "Waiting for %s" % missing
			b.working = false
			continue
		if full:
			b.status = "Stores are full"
			b.working = false
			continue
		b.working = true
		var speed := float(b.staff) / float(need) if need > 0 else 1.0
		b.timer = float(b.timer) + dt * speed
		var cycle := float(d.get("cycle", 10.0))
		b.status = "Working - %s every %ds" % [Goods.describe(gains).replace("influence", "Influence"), int(cycle)]
		if b.timer >= cycle:
			b.timer = float(b.timer) - cycle
			for k in uses:
				stock[k] = float(stock.get(k, 0)) - float(uses[k])
			for k in gains:
				if k == "influence":
					influence += float(gains[k])
				else:
					stock[k] = float(stock.get(k, 0)) + float(gains[k])
			events.append({"building": b, "gains": gains, "uses": uses})
	# Influence from halls, temples and towers.
	influence += influence_rate() * dt
	# People: grow while there's room and food; eat; go hungry.
	_grow_timer += dt
	if _grow_timer >= GROW_TIME:
		_grow_timer = 0.0
		if population < housing() and food() > 0.0:
			population += 1
	_eat_timer += dt
	if _eat_timer >= EAT_TIME:
		_eat_timer = 0.0
		var need := ceili(population / 4.0)
		for f in Goods.FOOD:
			var take := minf(float(stock.get(f, 0)), float(need))
			stock[f] = float(stock.get(f, 0)) - take
			need -= int(take)
			if need <= 0:
				break
		if need > 0:
			_hungry += 1
			if _hungry >= 3 and population > 2:
				population -= 1
				_hungry = 0
		else:
			_hungry = 0
	return events


func _gains(b: Dictionary, d: Dictionary) -> Dictionary:
	if d.has("yields"):
		return d.yields.get(int(b.kind), {})
	return d.get("makes", {})


func _passive_status(d: Dictionary) -> String:
	var parts := PackedStringArray()
	if d.has("housing"):
		parts.append("homes for %d" % int(d.housing))
	if d.has("storage"):
		parts.append("stores %d" % int(d.storage))
	if d.has("influence"):
		parts.append("+%.1f influence/s" % float(d.influence))
	var t := ", ".join(parts)
	return t.substr(0, 1).to_upper() + t.substr(1)
