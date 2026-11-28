class_name BuildingDefs
extends RefCounted
## Every building a settlement can raise: what it costs, how long it takes to build, how many
## people it needs, where it may stand, and what it does once it stands.
##
## Fields (all but name/category optional):
##   name, category (see CATEGORIES), desc
##   cost: {good: amount}          build_time: seconds of building work
##   workers: people it needs      model: BuildingModels shape
##   needs: resource kinds the hex must hold (harvesters), or "fish" (water with fish beside)
##   near: resource kinds that must be on the hex or within two hexes of it (whales and seals,
##         which live in the water or on the skerries)
##   coast: must stand beside the sea
##   yields: {resource kind: {good: amount}} - what a harvester gathers, by the resource it found
##   recipes: [{uses: {good: amount}, makes: {good: amount}}] - what it makes each cycle; it
##            works the first recipe it has everything for (so a smith uses peat when the coal
##            runs out, a trading post sells whatever is plentiful)
##   uses / makes: a single recipe, the same as recipes: [{uses, makes}]
##   cycle: seconds per batch       tools: wears tools as it works (slow without them)
##   housing, storage, influence (per second), territory (hexes of land it claims, radius)
##   unique: only one per settlement     chimney: smoke while working

const K := NaturalResources.Kind
const CATEGORIES := ["harvest", "food", "industry", "crafts", "sea", "people", "roads", "military"]
const CATEGORY_NAMES := {"harvest": "Gather", "food": "Food", "industry": "Industry", "crafts": "Crafts",
	"sea": "Sea & Trade", "people": "People", "roads": "Roads & Outposts", "military": "Military"}

const DEFS := {
	# --- People and the town --------------------------------------------------------------
	"town_hall": {"name": "Town Hall", "category": "people", "model": "hall", "unique": true,
		"desc": "The heart of the settlement: houses the first families, stores goods and spreads your influence over the land.",
		"cost": {}, "build_time": 1.0, "housing": 10, "storage": 300, "influence": 0.5, "territory": 4, "chimney": true},
	"longhouse": {"name": "Longhouse", "category": "people", "model": "longhouse",
		"desc": "A turf-roofed longhouse: room for eight more people.",
		"cost": {"wood": 25, "stone": 5}, "build_time": 30.0, "housing": 8, "chimney": true},
	"warehouse": {"name": "Storehouse", "category": "people", "model": "storehouse",
		"desc": "A store on stone feet, away from damp and rats: room for 300 more goods.",
		"cost": {"wood": 30, "stone": 10}, "build_time": 30.0, "storage": 300},
	"tavern": {"name": "Mead Hall", "category": "people", "model": "tavern", "workers": 1,
		"desc": "Ale, song and boasting: turns ale into influence.",
		"cost": {"wood": 30, "stone": 10}, "build_time": 35.0, "uses": {"ale": 1}, "makes": {"influence": 3}, "cycle": 12.0, "chimney": true},
	"hof": {"name": "Hof", "category": "people", "model": "hof",
		"desc": "A temple to the gods: a steady stream of influence, and much more when finery is offered.",
		"cost": {"wood": 30, "stone": 30, "gold": 2}, "build_time": 45.0, "influence": 0.4,
		"recipes": [{"uses": {"jewellery": 1}, "makes": {"influence": 10}}], "cycle": 30.0},
	# --- Gathering (stand on a resource hex) ----------------------------------------------
	"woodcutter": {"name": "Woodcutter", "category": "harvest", "model": "woodcutter", "workers": 2, "tools": true,
		"desc": "Fells trees. Build in timber, ship oak or pine.",
		"cost": {"wood": 10}, "build_time": 20.0, "needs": [K.TIMBER, K.OAK, K.TAR], "cycle": 8.0,
		"yields": {K.TIMBER: {"wood": 2}, K.OAK: {"oak": 1, "wood": 1}, K.TAR: {"wood": 2}}},
	"quarry": {"name": "Quarry", "category": "harvest", "model": "quarry", "workers": 2, "tools": true,
		"desc": "Cuts stone. Build on stone or soapstone.",
		"cost": {"wood": 15}, "build_time": 25.0, "needs": [K.STONE, K.SOAPSTONE], "cycle": 10.0,
		"yields": {K.STONE: {"stone": 2}, K.SOAPSTONE: {"soapstone": 1, "stone": 1}}},
	"mine": {"name": "Mine", "category": "harvest", "model": "mine", "workers": 3, "tools": true,
		"desc": "Digs ore. Build on iron, bog or lake ore, coal, silver, gold or gems.",
		"cost": {"wood": 20, "stone": 10}, "build_time": 35.0, "needs": [K.IRON, K.BOG_IRON, K.LAKE_ORE, K.COAL, K.SILVER, K.GOLD, K.GEMS], "cycle": 12.0,
		"yields": {K.IRON: {"iron": 2}, K.BOG_IRON: {"iron": 1}, K.LAKE_ORE: {"iron": 1}, K.COAL: {"coal": 2},
			K.SILVER: {"silver": 1}, K.GOLD: {"gold": 1}, K.GEMS: {"gems": 1}}},
	"hunting_lodge": {"name": "Hunting Lodge", "category": "harvest", "model": "lodge", "workers": 2, "tools": true,
		"desc": "Hunts deer, boar and fur animals for meat, hides and furs. Build by game or furs.",
		"cost": {"wood": 12}, "build_time": 20.0, "needs": [K.GAME, K.FURS], "cycle": 12.0,
		"yields": {K.GAME: {"meat": 2, "hides": 1}, K.FURS: {"furs": 2, "meat": 1}}},
	"farm": {"name": "Farmstead", "category": "harvest", "model": "farm", "workers": 2, "tools": true,
		"desc": "Grows barley and rye. Build on farmland.",
		"cost": {"wood": 20}, "build_time": 25.0, "needs": [K.FARMLAND], "cycle": 14.0,
		"yields": {K.FARMLAND: {"grain": 3}}},
	"sheepfold": {"name": "Sheepfold", "category": "harvest", "model": "fold", "workers": 1,
		"desc": "Keeps sheep for wool and mutton. Build on sheep pasture.",
		"cost": {"wood": 15}, "build_time": 20.0, "needs": [K.WOOL], "cycle": 12.0,
		"yields": {K.WOOL: {"wool": 2, "meat": 1}}},
	"horse_farm": {"name": "Horse Farm", "category": "harvest", "model": "stable", "workers": 2,
		"desc": "Catches and breaks wild horses, fed on grain. Build where horses run.",
		"cost": {"wood": 25, "stone": 5}, "build_time": 30.0, "needs": [K.HORSES], "cycle": 25.0,
		"uses": {"grain": 1}, "yields": {K.HORSES: {"horses": 1}}},
	"reed_cutter": {"name": "Reed Cutter", "category": "harvest", "model": "reeds", "workers": 1,
		"desc": "Cuts reeds for arrow shafts. Build in a reed bed.",
		"cost": {"wood": 8}, "build_time": 15.0, "needs": [K.REEDS], "cycle": 10.0, "yields": {K.REEDS: {"reeds": 3}}},
	"clay_pit": {"name": "Clay Digger", "category": "harvest", "model": "claypit", "workers": 1, "tools": true,
		"desc": "Digs clay from the bank. Build on clay.",
		"cost": {"wood": 10}, "build_time": 15.0, "needs": [K.CLAY], "cycle": 10.0, "yields": {K.CLAY: {"clay": 2}}},
	"peat_cutter": {"name": "Peat Cutter", "category": "harvest", "model": "peat", "workers": 1, "tools": true,
		"desc": "Cuts peat for fuel. Build on peat or bog iron.",
		"cost": {"wood": 8}, "build_time": 15.0, "needs": [K.PEAT, K.BOG_IRON], "cycle": 10.0, "yields": {K.PEAT: {"peat": 3}, K.BOG_IRON: {"peat": 2}}},
	"salt_works": {"name": "Salt Works", "category": "harvest", "model": "saltworks", "workers": 1,
		"desc": "Boils sea water for salt over a peat or wood fire. Build on salt.",
		"cost": {"wood": 12, "stone": 5}, "build_time": 20.0, "needs": [K.SALT], "cycle": 12.0, "chimney": true,
		"recipes": [{"uses": {"peat": 1}, "makes": {"salt": 3}}, {"uses": {"wood": 1}, "makes": {"salt": 2}}]},
	"tar_kiln": {"name": "Tar Kiln", "category": "harvest", "model": "kiln", "workers": 1,
		"desc": "Burns resinous pine slowly in a pit for tar. Build on pine tar.",
		"cost": {"wood": 15, "stone": 5}, "build_time": 25.0, "needs": [K.TAR], "cycle": 12.0, "uses": {"wood": 1}, "yields": {K.TAR: {"tar": 2}}, "chimney": true},
	"amber_gatherer": {"name": "Amber Gatherer", "category": "harvest", "model": "amber", "workers": 1,
		"desc": "Combs the beach for amber. Build on amber.",
		"cost": {"wood": 8}, "build_time": 15.0, "needs": [K.AMBER], "cycle": 15.0, "yields": {K.AMBER: {"amber": 1}}},
	# --- Food ------------------------------------------------------------------------------
	"fishing_hut": {"name": "Fishing Hut", "category": "food", "model": "fishing_hut", "workers": 2, "tools": true,
		"desc": "Nets fish from the water. Build on the shore by fish.",
		"cost": {"wood": 12}, "build_time": 20.0, "needs": "fish", "cycle": 10.0, "makes": {"fish": 3}},
	"bakery": {"name": "Bakery", "category": "food", "model": "bakery", "workers": 2,
		"desc": "Bakes bread from grain.",
		"cost": {"wood": 20, "stone": 15}, "build_time": 30.0, "uses": {"grain": 2}, "makes": {"bread": 3}, "cycle": 12.0, "chimney": true},
	"brewery": {"name": "Brewery", "category": "food", "model": "brewery", "workers": 2,
		"desc": "Brews ale from grain: for the mead hall, and for your people.",
		"cost": {"wood": 25, "stone": 10}, "build_time": 30.0, "uses": {"grain": 2}, "makes": {"ale": 2}, "cycle": 12.0, "chimney": true},
	"smokehouse": {"name": "Salting House", "category": "food", "model": "smokehouse", "workers": 2,
		"desc": "Salts and dries fish so it keeps through the winter: more food from the same catch.",
		"cost": {"wood": 20, "stone": 5}, "build_time": 25.0, "uses": {"fish": 3, "salt": 1}, "makes": {"stockfish": 5}, "cycle": 14.0, "chimney": true},
	# --- Industry ----------------------------------------------------------------------------
	"charcoal": {"name": "Charcoal Burner", "category": "industry", "model": "charcoal", "workers": 1,
		"desc": "Smoulders wood under turf into charcoal, for when there is no coal to dig.",
		"cost": {"wood": 15}, "build_time": 20.0, "uses": {"wood": 3}, "makes": {"coal": 1}, "cycle": 15.0, "chimney": true},
	"bloomery": {"name": "Bloomery", "category": "industry", "model": "bloomery", "workers": 2, "tools": true,
		"desc": "Smelts iron ore into bars of iron in a clay furnace, fired with coal or peat.",
		"cost": {"wood": 20, "stone": 25}, "build_time": 35.0, "cycle": 15.0, "chimney": true,
		"recipes": [{"uses": {"iron": 2, "coal": 1}, "makes": {"bar_iron": 1}}, {"uses": {"iron": 2, "peat": 2}, "makes": {"bar_iron": 1}}]},
	"smithy": {"name": "Smithy", "category": "industry", "model": "smithy", "workers": 2,
		"desc": "Forges tools from iron bars. Every gatherer and many workshops wear tools out.",
		"cost": {"wood": 20, "stone": 20}, "build_time": 35.0, "cycle": 15.0, "chimney": true,
		"recipes": [{"uses": {"bar_iron": 1, "coal": 1}, "makes": {"tools": 2}}, {"uses": {"bar_iron": 1, "peat": 2}, "makes": {"tools": 1}}]},
	"potter": {"name": "Potter", "category": "industry", "model": "potter", "workers": 1, "tools": true,
		"desc": "Throws and fires pots from clay, or carves vessels from soapstone.",
		"cost": {"wood": 15, "stone": 10}, "build_time": 25.0, "cycle": 12.0, "chimney": true,
		"recipes": [{"uses": {"clay": 2, "peat": 1}, "makes": {"pottery": 3}}, {"uses": {"clay": 2, "wood": 1}, "makes": {"pottery": 2}}, {"uses": {"soapstone": 1}, "makes": {"pottery": 2}}]},
	"tannery": {"name": "Tannery", "category": "industry", "model": "tannery", "workers": 2,
		"desc": "Cures hides into leather in salt and bark pits. It smells.",
		"cost": {"wood": 20}, "build_time": 25.0, "uses": {"hides": 2, "salt": 1}, "makes": {"leather": 2}, "cycle": 16.0},
	# --- Crafts ----------------------------------------------------------------------------
	"weaver": {"name": "Weaving Hut", "category": "crafts", "model": "weaver", "workers": 1,
		"desc": "Weaves wool into cloth for clothes and sails.",
		"cost": {"wood": 15}, "build_time": 20.0, "uses": {"wool": 2}, "makes": {"cloth": 1}, "cycle": 12.0},
	"tailor": {"name": "Clothier", "category": "crafts", "model": "tailor", "workers": 1, "tools": true,
		"desc": "Sews clothes: tunics and dresses from cloth and leather, cloaks from furs.",
		"cost": {"wood": 20}, "build_time": 25.0, "cycle": 14.0,
		"recipes": [{"uses": {"cloth": 1, "leather": 1}, "makes": {"clothing": 3}}, {"uses": {"furs": 2}, "makes": {"clothing": 2}}, {"uses": {"cloth": 2}, "makes": {"clothing": 1}}]},
	"jeweller": {"name": "Jeweller", "category": "crafts", "model": "jeweller", "workers": 1, "tools": true,
		"desc": "Makes brooches, arm rings and beads from gold, silver, gems, amber and ivory.",
		"cost": {"wood": 20, "stone": 15, "silver": 2}, "build_time": 30.0, "cycle": 18.0, "chimney": true,
		"recipes": [{"uses": {"gold": 1, "gems": 1}, "makes": {"jewellery": 4}}, {"uses": {"silver": 1, "amber": 1}, "makes": {"jewellery": 2}},
			{"uses": {"silver": 1, "ivory": 1}, "makes": {"jewellery": 2}}, {"uses": {"gold": 1}, "makes": {"jewellery": 2}}, {"uses": {"amber": 2}, "makes": {"jewellery": 1}}]},
	"fletcher": {"name": "Fletcher", "category": "crafts", "model": "fletcher", "workers": 1,
		"desc": "Makes arrows from reed shafts and wood.",
		"cost": {"wood": 15}, "build_time": 20.0, "uses": {"reeds": 2, "wood": 1}, "makes": {"arrows": 6}, "cycle": 12.0},
	# --- Sea and trade -----------------------------------------------------------------------
	"whaler": {"name": "Whaling Station", "category": "sea", "model": "whaler", "workers": 3, "tools": true,
		"desc": "Hunts whales from the shore for oil and meat. Build on the coast near whales.",
		"cost": {"wood": 30, "stone": 5}, "build_time": 35.0, "near": [K.WHALES], "coast": true, "cycle": 24.0, "chimney": true,
		"yields": {K.WHALES: {"oil": 3, "meat": 4}}},
	"sealer": {"name": "Sealing Camp", "category": "sea", "model": "sealer", "workers": 2, "tools": true,
		"desc": "Hunts seals and walrus for hides, oil and ivory. Build near seals.",
		"cost": {"wood": 15}, "build_time": 20.0, "near": [K.SEALS], "cycle": 16.0,
		"yields": {K.SEALS: {"hides": 1, "oil": 1, "ivory": 1}}},
	"shipyard": {"name": "Shipyard", "category": "sea", "model": "shipyard", "workers": 4, "tools": true,
		"desc": "Builds longships from oak, tar, a woollen sail and iron rivets. Each ship adds to your renown. Build on the coast.",
		"cost": {"wood": 40, "stone": 10}, "build_time": 45.0, "coast": true, "cycle": 60.0,
		"uses": {"oak": 4, "tar": 2, "cloth": 2, "bar_iron": 1}, "makes": {"ship": 1}},
	"trading_post": {"name": "Trading Post", "category": "sea", "model": "trading_post", "workers": 2,
		"desc": "Merchants buy what you have plenty of for silver: finery, ivory, furs, oil, tar, salt fish, salt, amber. Build on the coast.",
		"cost": {"wood": 35, "stone": 10}, "build_time": 35.0, "coast": true, "cycle": 15.0,
		"recipes": [{"uses": {"jewellery": 1}, "makes": {"silver": 3}}, {"uses": {"ivory": 2}, "makes": {"silver": 2}},
			{"uses": {"furs": 3}, "makes": {"silver": 1}}, {"uses": {"oil": 3}, "makes": {"silver": 1}},
			{"uses": {"tar": 3}, "makes": {"silver": 1}}, {"uses": {"stockfish": 8}, "makes": {"silver": 1}},
			{"uses": {"salt": 5}, "makes": {"silver": 1}}, {"uses": {"amber": 2}, "makes": {"silver": 1}}]},
	# --- Roads and outposts ---------------------------------------------------------------------
	"road": {"name": "Road", "category": "roads", "model": "roadsign", "road": true,
		"desc": "Lay a road hex by hex from land you can reach. On a river it becomes a bridge, up a steep slope a hill road climbing in switchbacks: the way across rivers and up onto hills, so you can build there. Keeps placing until you stop (right-click or Esc).",
		"cost": {"wood": 1, "stone": 1}, "build_time": 0.0},
	"outpost": {"name": "Outpost", "category": "roads", "model": "outpost", "workers": 1, "outside": true,
		"desc": "A fortified camp away from home: claims the land two hexes round it and keeps a small store, so you can gather resources far from the hall. Build within ten hexes of your land, on land nobody holds.",
		"cost": {"wood": 40, "stone": 15}, "build_time": 35.0, "territory": 2, "storage": 100, "chimney": true},
	# --- Expansions (built from a gatherer's panel onto a hex beside it or its other parts) ----------
	"field": {"name": "Field", "category": "harvest", "model": "ext_field", "workers": 1, "expansion_of": ["farm"], "flat": true,
		"desc": "Another field ploughed beside the farmstead.", "cost": {"wood": 6}, "build_time": 15.0},
	"woodlot": {"name": "Wood Lot", "category": "harvest", "model": "ext_woodlot", "workers": 1, "expansion_of": ["woodcutter"],
		"needs": [K.TIMBER, K.OAK, K.TAR], "desc": "Felling further into the woods.", "cost": {"wood": 8}, "build_time": 15.0},
	"quarry_face": {"name": "Quarry Face", "category": "harvest", "model": "ext_quarry", "workers": 1, "expansion_of": ["quarry"],
		"needs": [K.STONE, K.SOAPSTONE], "desc": "A new face opened in the rock.", "cost": {"wood": 10}, "build_time": 18.0},
	"shaft": {"name": "Shaft", "category": "harvest", "model": "ext_shaft", "workers": 1, "expansion_of": ["mine"],
		"needs": [K.IRON, K.BOG_IRON, K.LAKE_ORE, K.COAL, K.SILVER, K.GOLD, K.GEMS], "desc": "Another shaft sunk into the vein, with a winding frame.",
		"cost": {"wood": 14, "stone": 6}, "build_time": 22.0},
	"jetty": {"name": "Jetty", "category": "food", "model": "ext_jetty", "workers": 1, "expansion_of": ["fishing_hut"], "needs": "fish",
		"desc": "A jetty and another boat on the fishing grounds.", "cost": {"wood": 10}, "build_time": 15.0},
	"pasture": {"name": "Pasture", "category": "harvest", "model": "ext_pasture", "workers": 1, "expansion_of": ["sheepfold", "horse_farm"], "flat": true,
		"desc": "More grazing, fenced, with a shelter.", "cost": {"wood": 8}, "build_time": 15.0},
	"peat_bank": {"name": "Peat Bank", "category": "harvest", "model": "ext_peat", "workers": 1, "expansion_of": ["peat_cutter"],
		"needs": [K.PEAT, K.BOG_IRON], "desc": "Another bank of peat being cut.", "cost": {"wood": 4}, "build_time": 10.0},
	"clay_bank": {"name": "Clay Bank", "category": "harvest", "model": "ext_clay", "workers": 1, "expansion_of": ["clay_pit"],
		"needs": [K.CLAY], "desc": "Another clay pit dug.", "cost": {"wood": 4}, "build_time": 10.0},
	"reed_bed": {"name": "Reed Bed", "category": "harvest", "model": "ext_reeds", "workers": 1, "expansion_of": ["reed_cutter"],
		"needs": [K.REEDS], "desc": "More reeds cut and stooked.", "cost": {"wood": 4}, "build_time": 10.0},
	# --- Military ------------------------------------------------------------------------------
	"watchtower": {"name": "Watchtower", "category": "military", "model": "tower", "workers": 1,
		"desc": "Keeps watch and claims the land around it for your settlement.",
		"cost": {"wood": 20, "stone": 10}, "build_time": 30.0, "territory": 3, "influence": 0.1},
	"weaponsmith": {"name": "Weaponsmith", "category": "military", "model": "smithy", "workers": 2,
		"desc": "Forges spears, axes and swords from iron bars.",
		"cost": {"wood": 20, "stone": 20}, "build_time": 35.0, "cycle": 18.0, "chimney": true,
		"recipes": [{"uses": {"bar_iron": 2, "coal": 1}, "makes": {"weapons": 2}}, {"uses": {"bar_iron": 2, "peat": 2}, "makes": {"weapons": 1}}]},
	"barracks": {"name": "Barracks", "category": "military", "model": "barracks", "workers": 0,
		"desc": "Trains warriors: riders with horses, spearmen with weapons, archers with arrows. Each adds to your renown.",
		"cost": {"wood": 40, "stone": 20}, "build_time": 45.0, "cycle": 20.0, "chimney": true,
		"recipes": [{"uses": {"weapons": 1, "horses": 1, "meat": 1}, "makes": {"warriors": 2}}, {"uses": {"weapons": 1, "meat": 1}, "makes": {"warriors": 1}},
			{"uses": {"arrows": 10, "meat": 1}, "makes": {"warriors": 1}}]},
}


## Up to how many expansions a gatherer may have, and what each adds to its output.
const MAX_EXPANSIONS := 3
const EXPANSION_SHARE := 0.6

## Buildings working faster beside others: id -> [[neighbours (any of), bonus, why]]. Within two
## hexes; bonuses add up (to +60% at most). Any producer also gains from a storehouse close by.
const SYNERGIES := {
	"bakery": [[["farm"], 0.15, "grain fresh from the farm"], [["brewery"], 0.05, "a shared fire"]],
	"brewery": [[["farm"], 0.15, "grain fresh from the farm"], [["tavern"], 0.1, "the mead hall at its door"]],
	"smokehouse": [[["fishing_hut"], 0.2, "the catch straight off the boats"], [["salt_works"], 0.15, "salt to hand"]],
	"bloomery": [[["mine"], 0.2, "ore straight from the mine"], [["charcoal"], 0.15, "charcoal to hand"]],
	"smithy": [[["bloomery"], 0.2, "iron hot from the bloomery"], [["charcoal", "mine"], 0.1, "fuel to hand"]],
	"weaponsmith": [[["bloomery"], 0.2, "iron hot from the bloomery"], [["barracks"], 0.1, "warriors to try the blades"]],
	"tannery": [[["hunting_lodge", "sealer"], 0.15, "hides fresh from the hunt"], [["salt_works"], 0.1, "salt to hand"]],
	"tailor": [[["weaver"], 0.15, "cloth off the loom"], [["tannery"], 0.1, "leather to hand"]],
	"weaver": [[["sheepfold"], 0.15, "wool from the fold"]],
	"potter": [[["clay_pit"], 0.2, "clay dug at the door"], [["peat_cutter", "charcoal"], 0.1, "fuel for the kiln"]],
	"jeweller": [[["trading_post"], 0.15, "merchants' gold and amber"], [["mine"], 0.1, "metal from the mine"]],
	"fletcher": [[["reed_cutter"], 0.15, "reeds fresh cut"], [["woodcutter"], 0.1, "wood to hand"]],
	"shipyard": [[["woodcutter"], 0.15, "timber from the woods"], [["tar_kiln"], 0.15, "tar to hand"], [["weaver"], 0.1, "sailcloth"]],
	"trading_post": [[["warehouse"], 0.15, "goods ready in store"], [["shipyard"], 0.1, "ships coming and going"]],
	"charcoal": [[["woodcutter"], 0.15, "wood straight from the woods"]],
	"tar_kiln": [[["woodcutter"], 0.1, "wood straight from the woods"]],
	"tavern": [[["longhouse"], 0.1, "neighbours to drink with"], [["brewery"], 0.1, "ale fresh from the brewery"]],
	"hof": [[["tavern"], 0.1, "feasts after the offerings"]],
	"barracks": [[["weaponsmith"], 0.15, "arms fresh from the forge"], [["watchtower"], 0.05, "watch kept close"]],
	"salt_works": [[["peat_cutter"], 0.15, "peat for the fires"]],
	"farm": [[["sheepfold", "horse_farm"], 0.1, "dung for the fields"]],
	"whaler": [[["smokehouse", "salt_works"], 0.1, "the catch kept"]],
}


## The buildings (not expansions) that gather a resource, best first.
static func harvesters_for(kind: int) -> Array:
	var out: Array = []
	for k in DEFS:
		var d: Dictionary = DEFS[k]
		if d.has("expansion_of"):
			continue
		var needs = d.get("needs", null)
		if (needs is Array and (needs as Array).has(kind)) or (d.has("near") and (d.near as Array).has(kind)) \
				or (needs is String and needs == "fish" and kind == NaturalResources.Kind.FISH):
			out.append(k)
	return out


static func is_expansion(id: String) -> bool:
	return DEFS.has(id) and DEFS[id].has("expansion_of")


## The expansions a building can grow.
static func expansions_for(id: String) -> Array:
	var out: Array = []
	for k in DEFS:
		if DEFS[k].has("expansion_of") and (DEFS[k].expansion_of as Array).has(id):
			out.append(k)
	return out


## The building's tile (assets/icons/buildings, made by tools/make_game_icons.py).
static func icon(id: String) -> Texture2D:
	var path := "res://assets/icons/buildings/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func in_category(cat: String) -> Array:
	var out: Array = []
	for id in DEFS:
		if DEFS[id].category == cat and id != "town_hall" and not DEFS[id].has("expansion_of"):
			out.append(id)
	return out


## Everything a building can make, as recipes [{uses, makes}]; for a harvester, what it gathers
## from `kind` (all its kinds if kind is 0).
static func recipes(id: String, kind := 0) -> Array:
	var d: Dictionary = DEFS[id]
	if d.has("recipes"):
		return d.recipes
	if d.has("yields"):
		var out: Array = []
		var ys: Dictionary = d.yields
		for k in ys:
			if kind == 0 or int(k) == kind:
				out.append({"uses": d.get("uses", {}), "makes": ys[k]})
		return out
	if d.has("makes"):
		return [{"uses": d.get("uses", {}), "makes": d.makes}]
	return []
