class_name NaturalResources
extends RefCounted
## Natural resources for a Norse world, as deposits that span one or more hexes.
##
## Placed on the finest level from the land itself: terrain type, height, slope, rivers,
## lakes, floodplains, coast and open sea. Rules follow where these things are really found
## (bog iron in wet lowlands, gold in river gravels below mountains, amber on beaches...).
## Each deposit starts at a seed hex and grows over neighbouring hexes that suit the same
## resource, up to a size that matches how abundant it is: forests and farmland cover many
## hexes, ore veins a few, gems one. Deposits are richest at their centre.
## Rare resources are placed first and keep their distance; every lake is one fishery.
## A Gaea mask named "res_<key>" (for example res_iron.png) forces a resource where painted.
## Coarser levels show the rarest resource found among their finest hexes.

enum Kind {
	NONE, TIMBER, OAK, TAR, STONE, SOAPSTONE, IRON, BOG_IRON, COAL, GOLD, SILVER, GEMS,
	FISH, WHALES, SEALS, FARMLAND, WOOL, HORSES, GAME, FURS, CLAY, SALT, PEAT, AMBER,
	REEDS, LAKE_ORE,
}

enum Group { CORE, PRECIOUS, INDUSTRY, WILDLIFE, NORSE }

## key, display name, group, seed chance on a suitable 20 m hex, minimum metres between two
## deposits of the same kind (0 = may cluster), description, deposit size range in 20 m hexes.
## Indexed by Kind.
const INFO := [
	["none", "None", Group.CORE, 0.0, 0, "", 0, 0],
	["timber", "Timber", Group.CORE, 0.012, 0, "Pine and spruce for building", 8, 24],
	["oak", "Ship oak", Group.NORSE, 0.02, 120, "Straight oak for keels and planks", 3, 7],
	["tar", "Pine tar", Group.NORSE, 0.02, 150, "Tar kilns; seals hulls and rigging", 2, 4],
	["stone", "Stone", Group.CORE, 0.012, 120, "Quarry stone for building", 2, 6],
	["soapstone", "Soapstone", Group.NORSE, 0.03, 200, "Carvable stone for pots, moulds and weights", 1, 3],
	["iron", "Iron ore", Group.CORE, 0.03, 200, "Rock iron from mountain veins", 2, 5],
	["bog_iron", "Bog iron", Group.NORSE, 0.05, 120, "Iron gathered from wet lowland bogs", 2, 5],
	["coal", "Coal", Group.INDUSTRY, 0.02, 260, "Seams of coal in the hills", 3, 7],
	["gold", "Gold", Group.PRECIOUS, 0.06, 300, "Gold washed into river gravels", 2, 4],
	["silver", "Silver", Group.PRECIOUS, 0.025, 350, "Silver veins in high rock", 1, 3],
	["gems", "Gems", Group.PRECIOUS, 0.03, 450, "Crystals in the high mountains", 1, 2],
	["fish", "Fish", Group.CORE, 0.03, 0, "Herring and cod on the fishing banks; salmon and trout in lakes", 4, 12],
	["whales", "Whales", Group.NORSE, 0.02, 600, "Whales out in deep water", 4, 10],
	["seals", "Seals & walrus", Group.NORSE, 0.05, 220, "Seal skins, oil and walrus ivory", 2, 5],
	["farmland", "Farmland", Group.CORE, 0.06, 0, "Fertile soil for barley, rye and flax", 4, 14],
	["wool", "Wool", Group.NORSE, 0.025, 0, "Sheep pasture; wool for sails and clothing", 4, 10],
	["horses", "Horses", Group.WILDLIFE, 0.025, 220, "Wild horses on open grassland", 4, 9],
	["game", "Game", Group.WILDLIFE, 0.012, 0, "Deer and boar", 5, 14],
	["furs", "Furs", Group.WILDLIFE, 0.03, 150, "Fox, marten and reindeer in the cold north", 3, 8],
	["clay", "Clay", Group.INDUSTRY, 0.05, 140, "Clay banks for pottery and daub", 1, 4],
	["salt", "Salt", Group.INDUSTRY, 0.05, 200, "Sea salt boiled on the shore", 1, 3],
	["peat", "Peat", Group.NORSE, 0.04, 0, "Peat cut from bogs for fuel", 3, 8],
	["amber", "Amber", Group.PRECIOUS, 0.05, 300, "Amber washed up on sandy beaches", 2, 5],
	["reeds", "Reeds", Group.NORSE, 0.06, 0, "Reed beds for thatch, baskets and arrows", 2, 6],
	["lake_ore", "Lake ore", Group.NORSE, 0.08, 200, "Iron ore raked from lake beds", 1, 3],
]

## Rarest first, so rare finds are never crowded out by common ones.
const PLACEMENT_ORDER := [
	Kind.WHALES, Kind.GEMS, Kind.SILVER, Kind.GOLD, Kind.AMBER, Kind.COAL, Kind.SOAPSTONE,
	Kind.IRON, Kind.LAKE_ORE, Kind.SEALS, Kind.HORSES, Kind.TAR, Kind.OAK, Kind.FURS, Kind.SALT,
	Kind.CLAY, Kind.BOG_IRON, Kind.FARMLAND, Kind.REEDS, Kind.WOOL, Kind.PEAT, Kind.STONE,
	Kind.GAME, Kind.TIMBER, Kind.FISH,
]

const GROUP_NAMES := ["Core", "Precious", "Industry", "Wildlife", "Norse"]
## Resources that naturally share ground with another: deer and furbearers in the woods, sheep
## grazing fallow fields, peat and bog iron in the same bog, coal seams beside iron ore, reeds
## on peaty or clayey wet ground. A hex of the first kind may also hold one of these.
const COMPANIONS := {
	Kind.TIMBER: [Kind.GAME, Kind.FURS],
	Kind.OAK: [Kind.GAME],
	Kind.FARMLAND: [Kind.WOOL],
	Kind.PEAT: [Kind.BOG_IRON, Kind.REEDS],
	Kind.BOG_IRON: [Kind.PEAT],
	Kind.COAL: [Kind.IRON],
	Kind.IRON: [Kind.COAL],
	Kind.CLAY: [Kind.REEDS],
	Kind.LAKE_ORE: [Kind.REEDS],
}
## Chance a hex of a deposit also holds its companion.
const COMPANION_CHANCE := 0.3
## No land resource on ground steeper than this (rise/run, ~35 degrees).
const MAX_SLOPE := 0.7

## Common resources: zoomed out, only their big deposits get an icon.
const COMMON := [Kind.STONE, Kind.GAME, Kind.TIMBER, Kind.FISH, Kind.FARMLAND, Kind.WOOL, Kind.PEAT, Kind.REEDS]
const T := HexMapGenerator.Terrain


static func key(kind: int) -> String:
	return INFO[kind][0]


static func display_name(kind: int) -> String:
	return INFO[kind][1]


static func group(kind: int) -> int:
	return INFO[kind][2]


static func description(kind: int) -> String:
	return INFO[kind][5]


## Places deposits on the finest level, then fills the coarser levels from it.
## Each level's `deposits` lists {kind, center (cell index), size (finest hexes)}.
static func place(levels: Array[HexLevel], source: TerrainSource, sea_y: float, abundance: float, mask_threshold: float, surface: TerrainSurface = null) -> void:
	if levels.is_empty():
		return
	var lv := levels[0]
	var n := lv.cell_count()
	lv.resource.fill(0)
	lv.resource_amount.fill(0)
	lv.deposit.fill(-1)
	lv.deposits.clear()
	var f := _features(lv, sea_y)
	# Hexes along the map's border take no resources (see TerrainSurface.EDGE_MARGIN).
	var edge := PackedByteArray()
	edge.resize(n)
	for i in n:
		if TerrainSource.cut_edge_dist(lv.cell_center(i)) < TerrainSurface.EDGE_MARGIN - 40.0:
			edge[i] = 1
	f["edge"] = edge
	# The steepest ground in each hex (centre and around it), from the finished terrain.
	var steep := PackedFloat32Array()
	steep.resize(n)
	if surface != null:
		for i in n:
			var c := lv.cell_center(i)
			var m := 0.0
			for k in 7:
				var q := c if k == 6 else c + Vector2.from_angle(TAU * k / 6.0) * lv.hex_size * 0.5
				var ny := surface.normal_at(q).y
				m = maxf(m, sqrt(maxf(1.0 / (ny * ny) - 1.0, 0.0)))
			steep[i] = m
	f["steep"] = steep
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(31337)
	var area_scale := maxf(1.0, lv.hex_size * lv.hex_size / 400.0)

	# Painted masks win: each connected painted patch is one deposit.
	for kind in range(1, INFO.size()):
		var mask_name := "res_" + key(kind)
		if not source.masks.has(mask_name):
			continue
		for i in n:
			if lv.resource[i] != 0 or source.sample_mask(mask_name, lv.cell_center(i)) <= mask_threshold:
				continue
			var cells := PackedInt32Array([i])
			lv.resource[i] = kind
			var head := 0
			while head < cells.size():
				var c := cells[head]
				head += 1
				for k in 6:
					var j := lv.index_of(HexCoords.neighbor(lv.coords[c], k))
					if j >= 0 and lv.resource[j] == 0 and source.sample_mask(mask_name, lv.cell_center(j)) > mask_threshold:
						lv.resource[j] = kind
						cells.append(j)
			_commit(lv, kind, cells)

	for kind: int in PLACEMENT_ORDER:
		var chance: float = minf(INFO[kind][3] * abundance * area_scale, 0.9)
		var gap: float = INFO[kind][4]
		var size_min: int = INFO[kind][6]
		var size_max: int = INFO[kind][7]
		var seeds: Array[Vector2] = []
		for i in n:
			if lv.resource[i] != 0:
				continue
			var suit := _suitability(kind, i, lv, f)
			if suit <= 0.0:
				continue
			rng.seed = MapSeed.mix(hash(Vector3i(lv.coords[i].x, lv.coords[i].y, kind * 7919)))
			if rng.randf() > chance * suit:
				continue
			var here := lv.cell_center(i)
			if gap > 0.0:
				var close := false
				for q in seeds:
					if q.distance_to(here) < gap:
						close = true
						break
				if close:
					continue
			# Grow the deposit over neighbouring hexes that suit the same resource.
			var target := maxi(1, roundi(rng.randf_range(size_min, size_max) * sqrt(maxf(abundance, 0.1)) / area_scale))
			var cells := _grow(lv, f, kind, i, target, rng)
			seeds.append(here)
			_commit(lv, kind, cells)

	# Every lake is one freshwater fishery (salmon, trout, char, eel).
	var seen := PackedByteArray()
	seen.resize(n)
	for i in n:
		if lv.lake[i] == 0 or seen[i] == 1:
			continue
		var cells := PackedInt32Array()
		var queue := PackedInt32Array([i])
		seen[i] = 1
		var head := 0
		while head < queue.size():
			var c := queue[head]
			head += 1
			if lv.resource[c] == 0:
				cells.append(c)
			for k in 6:
				var j := lv.index_of(HexCoords.neighbor(lv.coords[c], k))
				if j >= 0 and lv.lake[j] == 1 and seen[j] == 0:
					seen[j] = 1
					queue.append(j)
		if not cells.is_empty():
			_commit(lv, Kind.FISH, cells)

	# Companions: a second resource where two naturally go together.
	if lv.resource2.size() != n:
		lv.resource2.resize(n)
	lv.resource2.fill(0)
	var crng := RandomNumberGenerator.new()
	crng.seed = MapSeed.mix(4747)
	for i in n:
		var a := lv.resource[i]
		if a == 0 or not COMPANIONS.has(a):
			continue
		for b: int in COMPANIONS[a]:
			if _suitability(b, i, lv, f) > 0.0 and crng.randf() < COMPANION_CHANCE:
				lv.resource2[i] = b
				break

	# Coarser levels: the rarest resource among each hex's finest descendants, and the
	# deposits mapped onto them.
	var rank := {}
	for k in PLACEMENT_ORDER.size():
		rank[PLACEMENT_ORDER[k]] = k
	for li in range(1, levels.size()):
		var coarse := levels[li]
		var finer := levels[li - 1]
		coarse.resource.fill(0)
		coarse.resource_amount.fill(0)
		coarse.deposit.fill(-1)
		coarse.deposits.clear()
		for i in finer.cell_count():
			var kind := finer.resource[i]
			var ci := finer.parent[i]
			if kind == 0 or ci < 0:
				continue
			var cur := coarse.resource[ci]
			if cur == 0 or rank[kind] < rank[cur]:
				coarse.resource[ci] = kind
				coarse.resource_amount[ci] = finer.resource_amount[i]
			elif cur == kind:
				coarse.resource_amount[ci] = mini(3, coarse.resource_amount[ci] + 1)
		for d: Dictionary in finer.deposits:
			var ci := finer.parent[d.center]
			if ci >= 0:
				coarse.deposits.append({"kind": d.kind, "center": ci, "size": d.size})


## Breadth-first growth from a seed over free, suitable neighbours (with some randomness so
## deposits get ragged, natural outlines).
static func _grow(lv: HexLevel, f: Dictionary, kind: int, seed_cell: int, target: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var cells := PackedInt32Array([seed_cell])
	lv.resource[seed_cell] = kind
	var head := 0
	while head < cells.size() and cells.size() < target:
		var c := cells[head]
		head += 1
		var order := [0, 1, 2, 3, 4, 5]
		for q in range(5, 0, -1):
			var r := rng.randi_range(0, q)
			var tmp: int = order[q]
			order[q] = order[r]
			order[r] = tmp
		for k: int in order:
			if cells.size() >= target:
				break
			var j := lv.index_of(HexCoords.neighbor(lv.coords[c], k))
			if j < 0 or lv.resource[j] != 0:
				continue
			if _suitability(kind, j, lv, f) <= 0.0 or rng.randf() > 0.8:
				continue
			lv.resource[j] = kind
			cells.append(j)
	return cells


## Records a deposit: richness falls off from the centre (first cell) outwards.
static func _commit(lv: HexLevel, kind: int, cells: PackedInt32Array) -> void:
	var id := lv.deposits.size()
	var center := lv.cell_center(cells[0])
	var far := 1.0
	for c in cells:
		far = maxf(far, lv.cell_center(c).distance_to(center))
	for c in cells:
		var t := lv.cell_center(c).distance_to(center) / far
		lv.resource[c] = kind
		lv.resource_amount[c] = 3 if t < 0.34 else (2 if t < 0.7 else 1)
		lv.deposit[c] = id
	lv.deposits.append({"kind": kind, "center": cells[0], "size": cells.size()})


## Per-hex facts the rules use.
static func _features(lv: HexLevel, sea_y: float) -> Dictionary:
	var n := lv.cell_count()
	var top := maxf(lv.max_top_y() - sea_y, 1.0)
	var rel := PackedFloat32Array()
	var sea_nb := PackedInt32Array()     # neighbouring sea hexes
	var river_nb := PackedInt32Array()   # river or lake hexes within one step
	var lake_nb := PackedInt32Array()    # lake hexes within one step
	var land_dist := PackedInt32Array()  # for water hexes: steps to the nearest land
	rel.resize(n)
	sea_nb.resize(n)
	river_nb.resize(n)
	lake_nb.resize(n)
	land_dist.resize(n)
	land_dist.fill(-1)
	var queue := PackedInt32Array()
	for i in n:
		rel[i] = clampf((lv.top_y(i) - sea_y) / top, 0.0, 1.0)
		var water := _is_sea(lv, i)
		if not water:
			land_dist[i] = 0
			queue.append(i)
		for k in 6:
			var j := lv.index_of(HexCoords.neighbor(lv.coords[i], k))
			if j < 0:
				continue
			if _is_sea(lv, j):
				sea_nb[i] += 1
			if lv.river[j] == 1 or lv.lake[j] == 1:
				river_nb[i] += 1
			if lv.lake[j] == 1:
				lake_nb[i] += 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for k in 6:
			var j := lv.index_of(HexCoords.neighbor(lv.coords[i], k))
			if j >= 0 and land_dist[j] < 0:
				land_dist[j] = land_dist[i] + 1
				queue.append(j)
	# River mouths: river hexes on the coast, then the river hexes and banks next to them.
	var mouth := PackedByteArray()
	mouth.resize(n)
	var core: Array[int] = []
	for i in n:
		if lv.river[i] == 1 and sea_nb[i] > 0 and not _is_sea(lv, i):
			mouth[i] = 1
			core.append(i)
	for ring in 2:
		var grow: Array[int] = []
		for i in core:
			for k in 6:
				var j := lv.index_of(HexCoords.neighbor(lv.coords[i], k))
				if j < 0 or mouth[j] == 1 or _is_sea(lv, j):
					continue
				# First ring: every bank; second ring: only on up the river itself.
				if ring == 0 or lv.river[j] == 1:
					mouth[j] = 1
					grow.append(j)
		core = grow
	return {"rel": rel, "sea_nb": sea_nb, "river_nb": river_nb, "lake_nb": lake_nb, "land_dist": land_dist, "mouth": mouth}


static func _is_sea(lv: HexLevel, i: int) -> bool:
	return HexMapGenerator.is_water(lv.terrain[i]) and lv.lake[i] == 0


## 0 = can't be here, 1 = ideal spot.
static func _suitability(kind: int, i: int, lv: HexLevel, f: Dictionary) -> float:
	# Nothing on steep ground (fish and whales live in the water, so they don't care).
	if kind != Kind.FISH and kind != Kind.WHALES and f.has("steep") and float(f.steep[i]) > MAX_SLOPE:
		return 0.0
	if f.has("edge") and f.edge[i] == 1:
		return 0.0
	# Nothing on land sits in a river's mouth (the estuary and its banks); fish do best there.
	if kind != Kind.FISH and kind != Kind.WHALES and f.has("mouth") and f.mouth[i] == 1:
		return 0.0
	var t := lv.terrain[i]
	var rel: float = f.rel[i]
	var slope := lv.slope[i]
	var sea := _is_sea(lv, i)
	var lake := lv.lake[i] == 1
	var river := lv.river[i] == 1
	var wet: bool = river or lake or f.river_nb[i] > 0
	var coast: bool = f.sea_nb[i] > 0 and not sea
	var land := not sea and not lake
	var flood := lv.floodplain[i] == 1
	if flood:
		wet = true
	match kind:
		Kind.WHALES:
			return 1.0 if sea and f.land_dist[i] >= 4 else 0.0
		Kind.FISH:
			if sea and f.land_dist[i] <= 2:
				# River mouths are the richest fishing.
				return 3.0 if f.river_nb[i] > 0 else 0.7
			return 0.5 if river and lv.river_width[i] > 6.0 else 0.0
		Kind.SEALS:
			return 1.0 if coast and rel < 0.25 and (t == T.ROCK or t == T.SAND) else 0.0
		Kind.AMBER:
			return 1.0 if coast and t == T.SAND else 0.0
		Kind.SALT:
			return 1.0 if coast and (t == T.SAND or slope < 0.3) else 0.0
		Kind.GEMS:
			return 1.0 if land and (t == T.ROCK or t == T.SNOW) and rel > 0.65 else 0.0
		Kind.SILVER:
			return 1.0 if land and t == T.ROCK and rel > 0.5 else 0.0
		Kind.GOLD:
			# Placer gold: rivers just below the mountains.
			return 1.0 if river and rel > 0.2 and rel < 0.7 else 0.0
		Kind.IRON:
			return 1.0 if land and (t == T.ROCK or t == T.DIRT) and rel > 0.3 and rel < 0.85 else 0.0
		Kind.SOAPSTONE:
			return 1.0 if land and t == T.ROCK and rel > 0.25 and rel < 0.7 else 0.0
		Kind.COAL:
			return 1.0 if land and t != T.SNOW and t != T.SAND and rel > 0.2 and rel < 0.6 and slope > 0.25 and slope < 0.9 else 0.0
		Kind.STONE:
			return 1.0 if land and (t == T.ROCK or slope > 0.8) and rel < 0.8 else 0.0
		Kind.BOG_IRON:
			return 1.0 if land and wet and rel < 0.4 and slope < 0.55 and t != T.SAND and t != T.ROCK else 0.0
		Kind.PEAT:
			return 1.0 if land and rel < 0.45 and slope < 0.5 and (wet or t == T.DIRT or t == T.GRASS) and t != T.SAND and t != T.ROCK else 0.0
		Kind.CLAY:
			return 1.0 if land and wet and slope < 0.6 and rel < 0.55 and t != T.ROCK and t != T.SNOW else 0.0
		Kind.FARMLAND:
			if not land or not (t == T.GRASS or t == T.DIRT or t == T.SAND) or slope > 0.6 or rel > 0.55:
				return 0.0
			# Floodplain silt is the most fertile soil there is.
			if flood:
				return 3.0
			return 1.0 if wet else 0.35
		Kind.REEDS:
			return 1.0 if land and slope < 0.5 and (f.lake_nb[i] > 0 or flood) and t != T.ROCK and t != T.SNOW else 0.0
		Kind.LAKE_ORE:
			return 1.0 if lake else 0.0
		Kind.WOOL:
			return 1.0 if land and t == T.GRASS and rel > 0.15 and rel < 0.75 and slope > 0.15 else 0.0
		Kind.HORSES:
			return 1.0 if land and t == T.GRASS and slope < 0.6 and rel < 0.6 else 0.0
		Kind.GAME:
			return 1.0 if land and t == T.FOREST else (0.3 if land and t == T.GRASS else 0.0)
		Kind.FURS:
			return 1.0 if land and (t == T.FOREST or t == T.SNOW) and rel > 0.5 else 0.0
		Kind.TIMBER:
			return 1.0 if land and t == T.FOREST else 0.0
		Kind.OAK:
			return 1.0 if land and t == T.FOREST and rel < 0.4 else 0.0
		Kind.TAR:
			return 1.0 if land and t == T.FOREST and rel > 0.3 else 0.0
	return 0.0
