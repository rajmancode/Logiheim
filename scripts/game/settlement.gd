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
##
## Buildings work recipes: each cycle the first recipe whose goods are all in stock (so a smith
## burns peat when the coal is gone). Gatherers and many workshops wear tools; with none left
## they work at 60%. Beyond food, people want clothes, pots, ale, lamp oil and finery
## (Goods.NEEDS): each want met adds to their contentment, which speeds growth and work and
## brings influence. Longships and warriors add renown (influence) too. Production and use of
## every good is tallied per minute for the ledger.

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
## How well each want is met, 0..1, by good (Goods.NEEDS); and their average.
var needs := {}
var contentment := 0.5
## Goods made and used per minute (smoothed), for the ledger.
var made_rate := {}
var used_rate := {}
var _made := {}
var _used := {}
var _rate_timer := 0.0
var _need_timer := 0.0
var _tool_wear := 0.0

const START_STOCK := {"wood": 80, "stone": 40, "fish": 20, "grain": 10, "bread": 10, "tools": 8, "clothing": 4, "pottery": 4}
const NEED_TIME := 30.0
const RATE_TIME := 5.0
const TOOL_WEAR := 0.06    # tools worn out per cycle of a building that uses them
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
		if k != "warriors" and k != "ship":
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
	return influence_parts().values().reduce(func(a: float, b: float) -> float: return a + b, 0.0)


## Where influence comes from, per second: {source: amount}.
func influence_parts() -> Dictionary:
	var r := 0.0
	for b: Dictionary in buildings:
		var d: Dictionary = BuildingDefs.DEFS[b.id]
		if is_built(b) and d.has("influence") and (int(d.get("workers", 0)) == 0 or int(b.staff) > 0):
			r += float(d.influence)
	return {"Buildings": r, "Contentment": contentment * 0.03 * population,
		"Longships": 0.3 * float(stock.get("ship", 0)), "Warriors": 0.05 * float(stock.get("warriors", 0))}


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
	var tools_left := float(stock.get("tools", 0)) >= 1.0
	for b: Dictionary in buildings:
		if not is_built(b):
			continue
		var d: Dictionary = BuildingDefs.DEFS[b.id]
		var recs := BuildingDefs.recipes(b.id, int(b.kind))
		if recs.is_empty():
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
		var r := _pick_recipe(recs)
		if r.is_empty():
			# Name what's missing for the recipe nearest to being possible.
			var miss := PackedStringArray()
			for rr: Dictionary in recs:
				var m := PackedStringArray()
				for k in (rr.uses as Dictionary):
					if float(stock.get(k, 0)) < float(rr.uses[k]):
						m.append(Goods.display_name(k))
				if miss.is_empty() or m.size() < miss.size():
					miss = m
			b.status = "Waiting for %s" % " and ".join(miss)
			b.working = false
			if d.has("influence"):
				b.status = _passive_status(d)
			continue
		var uses: Dictionary = r.uses
		var gains: Dictionary = r.makes
		# Full stores stop only what would add to them (a workshop turning many goods into
		# fewer, or a merchant selling, still frees room).
		var net := 0.0
		for k in gains:
			if k != "influence" and k != "warriors" and k != "ship":
				net += float(gains[k])
		for k in uses:
			net -= float(uses[k])
		var full := stored() >= float(storage()) and net > 0.0
		if full:
			b.status = "Stores are full"
			b.working = false
			continue
		b.working = true
		var speed := float(b.staff) / float(need) if need > 0 else 1.0
		speed *= 0.85 + 0.3 * contentment
		var slow: bool = d.get("tools", false) and not tools_left
		if slow:
			speed *= 0.6
		b.timer = float(b.timer) + dt * speed
		var cycle := float(d.get("cycle", 10.0))
		b.status = "Working - %s every %ds%s" % [Goods.describe(gains).replace("influence", "Influence"), int(cycle), " (no tools: slow)" if slow else ""]
		if b.timer >= cycle:
			b.timer = float(b.timer) - cycle
			for k in uses:
				take(k, float(uses[k]))
			for k in gains:
				if k == "influence":
					influence += float(gains[k])
				else:
					give(k, float(gains[k]))
			if d.get("tools", false):
				_tool_wear += TOOL_WEAR
				if _tool_wear >= 1.0 and float(stock.get("tools", 0)) >= 1.0:
					_tool_wear -= 1.0
					take("tools", 1.0)
			events.append({"building": b, "gains": gains, "uses": uses})
	# Influence from halls, temples, towers, contentment, ships and warriors.
	influence += influence_rate() * dt
	# Wants beyond food: every so often each is met from the stores, or not.
	_need_timer += dt
	if _need_timer >= NEED_TIME:
		_need_timer = 0.0
		var total := 0.0
		for n: Array in Goods.NEEDS:
			var good: String = n[0]
			var want := float(population) / float(n[1]) * NEED_TIME / 60.0
			var have := minf(float(stock.get(good, 0)), want)
			if have > 0.0:
				take(good, have)
			var met := have / maxf(want, 0.001)
			needs[good] = lerpf(float(needs.get(good, 0.0)), met, 0.5)
			total += float(needs[good])
		contentment = total / Goods.NEEDS.size()
	# The ledger: made and used per minute.
	_rate_timer += dt
	if _rate_timer >= RATE_TIME:
		for k in Goods.INFO:
			made_rate[k] = lerpf(float(made_rate.get(k, 0.0)), float(_made.get(k, 0.0)) * 60.0 / _rate_timer, 0.35)
			used_rate[k] = lerpf(float(used_rate.get(k, 0.0)), float(_used.get(k, 0.0)) * 60.0 / _rate_timer, 0.35)
		_made.clear()
		_used.clear()
		_rate_timer = 0.0
	# People: grow while there's room and food; eat; go hungry.
	_grow_timer += dt * (0.6 + 0.8 * contentment)
	if _grow_timer >= GROW_TIME:
		_grow_timer = 0.0
		if population < housing() and food() > 0.0:
			population += 1
	_eat_timer += dt
	if _eat_timer >= EAT_TIME:
		_eat_timer = 0.0
		var need := ceili(population / 4.0)
		for f in Goods.FOOD:
			var eat := minf(float(stock.get(f, 0)), float(need))
			take(f, eat)
			need -= int(eat)
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


## The first recipe with everything it uses in stock, or {}.
func _pick_recipe(recs: Array) -> Dictionary:
	for r: Dictionary in recs:
		if can_afford(r.get("uses", {})):
			return r
	return {}


## Takes goods out of the stores (tallied for the ledger).
func take(good: String, amount: float) -> void:
	stock[good] = float(stock.get(good, 0)) - amount
	_used[good] = float(_used.get(good, 0.0)) + amount


## Puts goods into the stores (tallied for the ledger).
func give(good: String, amount: float) -> void:
	stock[good] = float(stock.get(good, 0)) + amount
	_made[good] = float(_made.get(good, 0.0)) + amount


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
