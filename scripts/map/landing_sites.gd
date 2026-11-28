class_name LandingSites
extends RefCounted
## Where players may come ashore: coastal hexes on the finest level that a crew could beach a
## ship on and build beside - low, gentle ground right at the sea, clear of cliffs, river
## channels and the cut-away map edge. Each is scored for what a new settlement needs (a beach,
## fresh water, good land and resources within a few hexes, a sheltered bay) and the best are
## kept, spread out so no two players land on top of each other. Each gets a Norse place name.

## Hexes around a site that count as its lands (resources, water) - about 120 m on 20 m hexes.
const REACH := 6
const T := HexMapGenerator.Terrain

## Each: {cell, p: Vector2, y, score (0..1), stars (1..5), name, beach: bool, water: bool,
## shelter: float, resources: Dictionary kind -> hexes, tags: PackedStringArray}.
var sites: Array = []


static func find(hm: HexMap, count := 10) -> LandingSites:
	var ls := LandingSites.new()
	if hm.levels.is_empty() or hm.surfaces.is_empty():
		return ls
	var lv: HexLevel = hm.levels[0]
	var s: TerrainSurface = hm.surfaces[0]
	var n := lv.cell_count()
	var sea := PackedByteArray()
	sea.resize(n)
	for i in n:
		sea[i] = 1 if HexMapGenerator.is_water(lv.terrain[i]) and lv.lake[i] == 0 else 0
	var cands: Array = []
	for i in n:
		if sea[i] == 1 or lv.lake[i] == 1 or lv.river[i] == 1:
			continue
		var sea_nb := 0
		for k in 6:
			var j := lv.index_of(HexCoords.neighbor(lv.coords[i], k))
			if j >= 0 and sea[j] == 1:
				sea_nb += 1
		if sea_nb == 0 or sea_nb >= 5:
			continue
		# The best spot in the hex to come ashore: low, gentle ground (its centre may be in the
		# water or up a bank).
		var c := Vector2(INF, INF)
		var h := 0.0
		var best := INF
		var hc := lv.cell_center(i)
		for k in 13:
			var q := hc if k == 0 else hc + Vector2.from_angle(TAU * float(k % 6) / 6.0 + (0.5 if k > 6 else 0.0)) * lv.hex_size * (0.45 if k <= 6 else 0.8)
			var hq := s.sample(q) - s.sea_y
			if hq < 0.5 or hq > 8.0 or s.river_at(q) > 0.4:
				continue
			var ny := (s.normal_at(q).y + s.normal_at(q + Vector2(4, 0)).y + s.normal_at(q - Vector2(4, 0)).y + s.normal_at(q + Vector2(0, 4)).y + s.normal_at(q - Vector2(0, 4)).y) / 5.0
			if ny < 0.88:
				continue
			# Lowest and flattest wins (a beach rather than a bank top).
			var cost := hq * 0.3 + (1.0 - ny) * 20.0
			if cost < best:
				best = cost
				c = q
				h = hq
		if c.x == INF:
			continue
		if TerrainSource.cut_edge_dist(c) < TerrainSurface.EDGE_MARGIN:
			continue
		# Not a cliff top: the ground must come down to the water on the sea side.
		var to_sea := Vector2.ZERO
		for k in 6:
			var j := lv.index_of(HexCoords.neighbor(lv.coords[i], k))
			if j >= 0 and sea[j] == 1:
				to_sea += lv.cell_center(j) - hc
		to_sea = to_sea.normalized()
		var drop := s.sample(c) - s.sample(c + to_sea * lv.hex_size * 1.2)
		if drop > 7.0:
			continue
		cands.append(_score(lv, s, sea, i, c, h, sea_nb))
	cands.sort_custom(func(a, b): return a.score > b.score)
	# The best, spread out: no two closer than a share of the map.
	var size := hm.source.world_size
	var spacing := clampf(sqrt(size.x * size.y / float(count)) * 0.55, 220.0, 700.0)
	var names := {}
	for cand: Dictionary in cands:
		if ls.sites.size() >= count:
			break
		var ok := true
		for o: Dictionary in ls.sites:
			if (o.p as Vector2).distance_to(cand.p) < spacing:
				ok = false
				break
		if not ok:
			continue
		cand.name = _place_name(cand, names)
		ls.sites.append(cand)
	# Stars from the weakest landing this map offers (2) to the best (5): on a rich map the
	# difference between sites still shows.
	var top := -INF
	var low := INF
	for st: Dictionary in ls.sites:
		top = maxf(top, st.score)
		low = minf(low, st.score)
	for st: Dictionary in ls.sites:
		var f: float = (st.score - low) / maxf(top - low, 0.001)
		st.stars = clampi(2 + int(round(f * 3.0)), 2, 5) if ls.sites.size() > 1 else 5
	return ls


## Every landing gets what a settlement cannot start without, within its first lands (4 hexes):
## timber, stone and farmland on the land, fish in the water. Whatever is missing is laid down
## as a small deposit on free, suitable ground nearby (before the map's props, icons and
## trails are made, so it looks and works like any other).
static func ensure_basics(lv: HexLevel, sites: Array) -> void:
	const K := NaturalResources.Kind
	const R := 4
	for site: Dictionary in sites:
		var a0 := lv.coords[int(site.cell)]
		var land: Array = []
		var sea: Array = []
		var have := {}
		for dq in range(-R, R + 1):
			for dr in range(maxi(-R, -dq - R), mini(R, -dq + R) + 1):
				var j := lv.index_of(a0 + Vector2i(dq, dr))
				if j < 0:
					continue
				for r in [lv.resource[j], lv.resource2[j] if lv.resource2.size() > j else 0]:
					if r != 0:
						have[r] = true
				var dist := HexCoords.distance(a0, lv.coords[j])
				if HexMapGenerator.is_water(lv.terrain[j]) and lv.lake[j] == 0:
					if dist <= 3 and lv.resource[j] == 0:
						sea.append(j)
				elif lv.lake[j] == 0 and lv.river[j] == 0 and lv.resource[j] == 0 and dist >= 2 and lv.slope[j] < 1.2 						and (lv.cave.size() <= j or lv.cave[j] < 0):
					land.append(j)
		var added := {}
		for kind: int in [K.TIMBER, K.STONE, K.FARMLAND]:
			if have.has(kind) or land.is_empty():
				continue
			# Timber on the wooded or higher ground, stone on the highest and roughest, farmland
			# on the flattest.
			var best := -1
			var bs := -INF
			for j: int in land:
				if lv.resource[j] != 0:
					continue
				var sc := 0.0
				match kind:
					K.TIMBER:
						sc = (2.0 if lv.terrain[j] == HexMapGenerator.Terrain.FOREST else 0.0) + lv.height[j] * 2.0 - lv.slope[j] * 0.3
					K.STONE:
						sc = lv.height[j] * 4.0 + lv.slope[j] + (2.0 if lv.terrain[j] == HexMapGenerator.Terrain.ROCK else 0.0)
					K.FARMLAND:
						sc = -lv.slope[j] * 3.0 + (1.0 if lv.terrain[j] == HexMapGenerator.Terrain.GRASS else 0.0)
				if sc > bs:
					bs = sc
					best = j
			if best < 0:
				continue
			var cells := PackedInt32Array([best])
			lv.resource[best] = kind
			var head := 0
			var target := 3 if kind == K.STONE else 4
			while head < cells.size() and cells.size() < target:
				var c := cells[head]
				head += 1
				for k in 6:
					var j := lv.index_of(HexCoords.neighbor(lv.coords[c], k))
					if j >= 0 and land.has(j) and lv.resource[j] == 0 and cells.size() < target:
						lv.resource[j] = kind
						cells.append(j)
			NaturalResources._commit(lv, kind, cells)
			added[kind] = cells.size()
		if not have.has(K.FISH) and not sea.is_empty():
			sea.sort_custom(func(x: int, y: int) -> bool: return HexCoords.distance(a0, lv.coords[x]) < HexCoords.distance(a0, lv.coords[y]))
			var cells := PackedInt32Array()
			for j: int in sea.slice(0, 3):
				cells.append(j)
			NaturalResources._commit(lv, K.FISH, cells)
			added[K.FISH] = cells.size()
		for k in added:
			site.resources[k] = int(site.resources.get(k, 0)) + int(added[k])
			if not (site.tags as PackedStringArray).has(NaturalResources.display_name(k)):
				(site.tags as PackedStringArray).append(NaturalResources.display_name(k))


static func _score(lv: HexLevel, s: TerrainSurface, sea: PackedByteArray, i: int, c: Vector2, h: float, sea_nb: int) -> Dictionary:
	var res := {}
	var water := false
	var flat := 0
	var count := 0
	var a := lv.coords[i]
	for dq in range(-REACH, REACH + 1):
		for dr in range(maxi(-REACH, -dq - REACH), mini(REACH, -dq + REACH) + 1):
			var j := lv.index_of(a + Vector2i(dq, dr))
			if j < 0:
				continue
			count += 1
			if lv.river[j] == 1 or lv.lake[j] == 1:
				water = true
			if sea[j] == 0 and lv.slope[j] < 0.4:
				flat += 1
			for r in [lv.resource[j], lv.resource2[j] if lv.resource2.size() > j else 0]:
				if r != 0:
					res[r] = res.get(r, 0) + 1
	var beach := s.weight_at(c, T.SAND) > 0.35
	# Shelter: fewer sea neighbours = tucked into a bay rather than out on a point.
	var shelter := clampf((5.0 - float(sea_nb)) / 4.0, 0.0, 1.0)
	var variety := 0.0
	var essentials := [NaturalResources.Kind.TIMBER, NaturalResources.Kind.FISH, NaturalResources.Kind.FARMLAND, NaturalResources.Kind.STONE]
	for k in res:
		variety += 1.6 if essentials.has(k) else 1.0
	var score := 0.0
	score += 1.2 if beach else 0.0
	score += 1.5 if water else 0.0
	score += shelter * 0.8
	score += float(flat) / maxf(count, 1.0) * 1.5
	score += minf(variety, 8.0) * 0.45
	score -= absf(h - 2.5) * 0.08
	var tags := PackedStringArray()
	if beach:
		tags.append("Beach")
	if water:
		tags.append("Fresh water")
	if shelter > 0.6:
		tags.append("Sheltered")
	var kinds := res.keys()
	kinds.sort_custom(func(x, y): return res[x] > res[y])
	for k in kinds.slice(0, 4):
		tags.append(NaturalResources.display_name(k))
	return {"cell": i, "p": c, "y": s.sample(c), "score": score, "stars": 1, "name": "",
		"beach": beach, "water": water, "shelter": shelter, "resources": res, "tags": tags}


## A Norse-sounding place name from what the place is like: a bay (-vik), a headland (-nes),
## a beach (-strand), a river mouth (-os), a harbour (-havn)...
static func _place_name(site: Dictionary, used: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(hash(site.cell) + 7717)
	var first := ["Hvit", "Svart", "Rauð", "Grøn", "Stein", "Sand", "Ulf", "Rav", "Ørn", "Bjørn", "Hjort", "Ask",
		"Eik", "Furu", "Selje", "Sild", "Lax", "Tor", "Frey", "Od", "Hel", "Kald", "Varm", "Lang", "Bred", "Djup",
		"Gull", "Jarn", "Kol", "Myr", "Ros", "Skog", "Fjell", "Storm", "Vind", "Mån", "Sol", "Hav"]
	var ends: Array = []
	if site.water:
		ends.append_array(["os", "aros", "elv"])
	if site.shelter > 0.6:
		ends.append_array(["vik", "vik", "havn", "våg"])
	else:
		ends.append_array(["nes", "nes", "odde"])
	if site.beach:
		ends.append_array(["strand", "sand", "ør"])
	ends.append_array(["by", "stad", "heim"])
	for attempt in 20:
		var nm: String = first[rng.randi() % first.size()] + ends[rng.randi() % ends.size()]
		nm = nm.substr(0, 1).to_upper() + nm.substr(1)
		if not used.has(nm):
			used[nm] = true
			return nm
	return "Landing %d" % (used.size() + 1)
