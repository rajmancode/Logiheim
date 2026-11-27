class_name BuildingDefs
extends RefCounted
## Every building a settlement can raise: what it costs, how long it takes to build, how many
## people it needs, where it may stand, and what it does once it stands.
##
## Fields (all but name/category optional):
##   name, category ("harvest", "crafts", "people", "military"), desc
##   cost: {good: amount}          build_time: seconds of building work
##   workers: people it needs      model: BuildingModels shape
##   needs: resource kinds the hex must hold (harvesters), or "fish" (water with fish beside)
##   yields: {resource kind: {good: amount}} - what a harvester gathers, by the hex's resource
##   makes: {good: amount} per cycle, uses: {good: amount} per cycle, cycle: seconds
##   housing, storage, influence (per second), territory (hexes of land it claims, radius)
##   unique: only one per settlement     chimney: smoke while working

const K := NaturalResources.Kind
const CATEGORIES := ["harvest", "crafts", "people", "military"]
const CATEGORY_NAMES := {"harvest": "Gather", "crafts": "Crafts", "people": "People", "military": "Military"}

const DEFS := {
	# --- People and the town --------------------------------------------------------------
	"town_hall": {"name": "Town Hall", "category": "people", "model": "hall", "unique": true,
		"desc": "The heart of the settlement: houses the first families, stores goods and spreads your influence over the land.",
		"cost": {}, "build_time": 1.0, "housing": 10, "storage": 300, "influence": 0.5, "territory": 4, "chimney": true},
	"longhouse": {"name": "Longhouse", "category": "people", "model": "longhouse",
		"desc": "A turf-roofed longhouse: room for eight more people.",
		"cost": {"wood": 25, "stone": 5}, "build_time": 30.0, "housing": 8, "chimney": true},
	"warehouse": {"name": "Storehouse", "category": "people", "model": "storehouse",
		"desc": "Raised on posts away from damp and rats: room for 300 more goods.",
		"cost": {"wood": 30, "stone": 10}, "build_time": 30.0, "storage": 300},
	"tavern": {"name": "Mead Hall", "category": "people", "model": "tavern", "workers": 1,
		"desc": "Ale, song and boasting: turns ale into influence.",
		"cost": {"wood": 30, "stone": 10}, "build_time": 35.0, "uses": {"ale": 1}, "makes": {"influence": 3}, "cycle": 12.0, "chimney": true},
	"hof": {"name": "Hof", "category": "people", "model": "hof",
		"desc": "A temple to the gods: a steady stream of influence.",
		"cost": {"wood": 30, "stone": 30, "gold": 2}, "build_time": 45.0, "influence": 0.4},
	# --- Crafts ---------------------------------------------------------------------------
	"brewery": {"name": "Brewery", "category": "crafts", "model": "brewery", "workers": 2,
		"desc": "Brews ale from grain.",
		"cost": {"wood": 25, "stone": 10}, "build_time": 30.0, "uses": {"grain": 2}, "makes": {"ale": 2}, "cycle": 12.0, "chimney": true},
	"bakery": {"name": "Bakery", "category": "crafts", "model": "bakery", "workers": 2,
		"desc": "Bakes bread from grain: food that keeps.",
		"cost": {"wood": 20, "stone": 15}, "build_time": 30.0, "uses": {"grain": 2}, "makes": {"bread": 3}, "cycle": 12.0, "chimney": true},
	"smithy": {"name": "Smithy", "category": "crafts", "model": "smithy", "workers": 2,
		"desc": "Forges tools from iron ore and coal.",
		"cost": {"wood": 20, "stone": 20}, "build_time": 35.0, "uses": {"iron": 1, "coal": 1}, "makes": {"tools": 1}, "cycle": 15.0, "chimney": true},
	"weaver": {"name": "Weaving Hut", "category": "crafts", "model": "hut", "workers": 1,
		"desc": "Weaves wool into cloth for sails and clothes.",
		"cost": {"wood": 15}, "build_time": 20.0, "uses": {"wool": 2}, "makes": {"cloth": 1}, "cycle": 12.0},
	# --- Gathering (stand on a resource hex) ----------------------------------------------
	"woodcutter": {"name": "Woodcutter", "category": "harvest", "model": "woodcutter", "workers": 2,
		"desc": "Fells trees for wood. Build in timber.",
		"cost": {"wood": 10}, "build_time": 20.0, "needs": [K.TIMBER, K.OAK, K.TAR], "cycle": 8.0,
		"yields": {K.TIMBER: {"wood": 2}, K.OAK: {"wood": 3}, K.TAR: {"wood": 2}}},
	"quarry": {"name": "Quarry", "category": "harvest", "model": "quarry", "workers": 2,
		"desc": "Cuts stone. Build on stone or soapstone.",
		"cost": {"wood": 15}, "build_time": 25.0, "needs": [K.STONE, K.SOAPSTONE], "cycle": 10.0,
		"yields": {K.STONE: {"stone": 2}, K.SOAPSTONE: {"stone": 2}}},
	"mine": {"name": "Mine", "category": "harvest", "model": "mine", "workers": 3,
		"desc": "Digs ore. Build on iron, coal, silver, gold or gems.",
		"cost": {"wood": 20, "stone": 10}, "build_time": 35.0, "needs": [K.IRON, K.BOG_IRON, K.LAKE_ORE, K.COAL, K.SILVER, K.GOLD, K.GEMS], "cycle": 12.0,
		"yields": {K.IRON: {"iron": 2}, K.BOG_IRON: {"iron": 1}, K.LAKE_ORE: {"iron": 1}, K.COAL: {"coal": 2},
			K.SILVER: {"silver": 1}, K.GOLD: {"gold": 1}, K.GEMS: {"gems": 1}}},
	"fishing_hut": {"name": "Fishing Hut", "category": "harvest", "model": "fishing_hut", "workers": 2,
		"desc": "Nets fish from the water. Build on the shore by fish.",
		"cost": {"wood": 12}, "build_time": 20.0, "needs": "fish", "cycle": 10.0, "makes": {"fish": 3}},
	"hunting_lodge": {"name": "Hunting Lodge", "category": "harvest", "model": "hut", "workers": 2,
		"desc": "Hunts deer, boar and fur animals. Build by game or furs.",
		"cost": {"wood": 12}, "build_time": 20.0, "needs": [K.GAME, K.FURS], "cycle": 12.0,
		"yields": {K.GAME: {"meat": 2, "furs": 1}, K.FURS: {"furs": 2, "meat": 1}}},
	"farm": {"name": "Farmstead", "category": "harvest", "model": "farm", "workers": 2,
		"desc": "Grows grain. Build on farmland.",
		"cost": {"wood": 20}, "build_time": 25.0, "needs": [K.FARMLAND], "cycle": 14.0,
		"yields": {K.FARMLAND: {"grain": 3}}},
	"sheepfold": {"name": "Sheepfold", "category": "harvest", "model": "fold", "workers": 1,
		"desc": "Keeps sheep or horses. Build by wool or horses.",
		"cost": {"wood": 15}, "build_time": 20.0, "needs": [K.WOOL, K.HORSES], "cycle": 12.0,
		"yields": {K.WOOL: {"wool": 2, "meat": 1}, K.HORSES: {"meat": 1, "wool": 1}}},
	"clay_pit": {"name": "Clay Digger", "category": "harvest", "model": "hut", "workers": 1,
		"desc": "Digs clay from the riverbank. Build on clay.",
		"cost": {"wood": 10}, "build_time": 15.0, "needs": [K.CLAY], "cycle": 10.0, "yields": {K.CLAY: {"clay": 2}}},
	"salt_works": {"name": "Salt Works", "category": "harvest", "model": "hut", "workers": 1,
		"desc": "Boils sea water for salt. Build on salt.",
		"cost": {"wood": 12, "stone": 5}, "build_time": 20.0, "needs": [K.SALT], "cycle": 12.0, "yields": {K.SALT: {"salt": 2}}, "chimney": true},
	"peat_cutter": {"name": "Peat Cutter", "category": "harvest", "model": "hut", "workers": 1,
		"desc": "Cuts peat for fuel. Build on peat or bog iron.",
		"cost": {"wood": 8}, "build_time": 15.0, "needs": [K.PEAT, K.BOG_IRON], "cycle": 10.0, "yields": {K.PEAT: {"peat": 3}, K.BOG_IRON: {"peat": 2}}},
	"tar_kiln": {"name": "Tar Kiln", "category": "harvest", "model": "kiln", "workers": 1,
		"desc": "Burns pine for tar. Build on pine tar.",
		"cost": {"wood": 15, "stone": 5}, "build_time": 25.0, "needs": [K.TAR], "cycle": 12.0, "uses": {"wood": 1}, "yields": {K.TAR: {"tar": 1}}, "chimney": true},
	"amber_gatherer": {"name": "Amber Gatherer", "category": "harvest", "model": "hut", "workers": 1,
		"desc": "Combs the beach for amber. Build on amber.",
		"cost": {"wood": 8}, "build_time": 15.0, "needs": [K.AMBER], "cycle": 15.0, "yields": {K.AMBER: {"amber": 1}}},
	# --- Military -------------------------------------------------------------------------
	"watchtower": {"name": "Watchtower", "category": "military", "model": "tower", "workers": 1,
		"desc": "Keeps watch and claims the land around it for your settlement.",
		"cost": {"wood": 20, "stone": 10}, "build_time": 30.0, "territory": 3, "influence": 0.1},
	"weaponsmith": {"name": "Weaponsmith", "category": "military", "model": "smithy", "workers": 2,
		"desc": "Forges spears, axes and swords from iron ore and coal.",
		"cost": {"wood": 20, "stone": 20}, "build_time": 35.0, "uses": {"iron": 2, "coal": 1}, "makes": {"weapons": 1}, "cycle": 18.0, "chimney": true},
	"barracks": {"name": "Barracks", "category": "military", "model": "barracks", "workers": 0,
		"desc": "Trains warriors from your people, with weapons and meat.",
		"cost": {"wood": 40, "stone": 20}, "build_time": 45.0, "uses": {"weapons": 1, "meat": 1}, "makes": {"warriors": 1}, "cycle": 20.0, "chimney": true},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func in_category(cat: String) -> Array:
	var out: Array = []
	for id in DEFS:
		if DEFS[id].category == cat and id != "town_hall":
			out.append(id)
	return out
