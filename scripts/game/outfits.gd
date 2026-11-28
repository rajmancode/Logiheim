class_name Outfits
extends RefCounted
## How each trade dresses and what it carries (Villager.setup(..., occupation)): the colours of
## its clothes, its headgear, an apron if it wears one, its cloak, what hangs at its belt and
## on its back, and the tool in its hand. Woodcutters in green wool and fur caps with an axe;
## miners in dark hoods with a pick and a lamp at the belt; smiths bare-armed in a leather
## apron; farmers in straw hats with a sickle and a basket on the back; fishers in knitted caps
## and oiled coats; bakers and brewers in white aprons; hunters in fur with a bow and quiver;
## merchants in fine dyed cloth with fur trim and a fat purse; and so on.
##
## Spec fields: tunic, dress, legs (palettes), women (chance), hat / hat_f (headgear for men /
## women: fur_cap, straw_hat, knit_cap, leather_cap, baker_cap, hood, fine_cap, headband,
## scarf, kerchief, none), cloak (team, fur, team_fur, none), apron (colour) and bib (bool),
## bare_arms, back (quiver, basket, bundle, coil, net, toolbag, none), belt (pouch, knife,
## purse, keys, hammer, horn, lamp), tool (overrides the trade's tool), elder (chance of grey).

const LINEN := Color(0.88, 0.85, 0.76)
const LEATHER := Color(0.42, 0.27, 0.15)
const WOOL_GREY := Color(0.48, 0.47, 0.44)
const STRAW := Color(0.84, 0.72, 0.4)
const FUR := Color(0.42, 0.3, 0.2)
const FUR_GREY := Color(0.55, 0.52, 0.48)
const OILSKIN := Color(0.58, 0.47, 0.22)

const SPECS := {
	"commoner": {"tunic": [Color(0.45, 0.38, 0.28), Color(0.32, 0.4, 0.33), Color(0.5, 0.33, 0.26), Color(0.36, 0.34, 0.44)],
		"women": 0.45, "hat": "none", "cloak": "team", "belt": ["pouch", "knife"]},
	"woodcutter": {"tunic": [Color(0.3, 0.4, 0.26), Color(0.4, 0.34, 0.22), Color(0.25, 0.32, 0.22)], "legs": [Color(0.32, 0.26, 0.18)],
		"women": 0.1, "hat": "fur_cap", "cloak": "none", "belt": ["knife", "pouch"], "back": "none", "tool": "axe"},
	"miner": {"tunic": [Color(0.32, 0.3, 0.28), Color(0.28, 0.26, 0.24), Color(0.38, 0.32, 0.26)], "legs": [Color(0.26, 0.24, 0.22)],
		"women": 0.0, "hat": "hood", "hood_col": Color(0.3, 0.27, 0.24), "cloak": "none", "belt": ["lamp", "pouch"], "tool": "pick", "elder": 0.25},
	"smith": {"tunic": [Color(0.36, 0.3, 0.26), Color(0.3, 0.3, 0.32)], "women": 0.0, "hat": "leather_cap", "cloak": "none",
		"apron": LEATHER, "bib": true, "bare_arms": true, "belt": ["pouch"], "tool": "hammer", "elder": 0.3},
	"farmer": {"tunic": [Color(0.72, 0.62, 0.42), Color(0.6, 0.55, 0.42), Color(0.55, 0.45, 0.3)], "dress": [Color(0.7, 0.58, 0.32), Color(0.45, 0.5, 0.32)],
		"women": 0.5, "hat": "straw_hat", "hat_f": "kerchief", "cloak": "none", "back": "basket", "belt": ["knife"], "tool": "sickle"},
	"herder": {"tunic": [Color(0.5, 0.42, 0.3), Color(0.62, 0.58, 0.5)], "dress": [Color(0.5, 0.42, 0.3)], "women": 0.4,
		"hat": "leather_cap", "hat_f": "scarf", "cloak": "fur", "belt": ["horn", "pouch"], "tool": "crook", "elder": 0.3},
	"fisher": {"tunic": [Color(0.3, 0.36, 0.45), Color(0.4, 0.44, 0.48)], "dress": [Color(0.3, 0.36, 0.45)], "women": 0.3,
		"hat": "knit_cap", "hat_f": "knit_cap", "cloak": "none", "apron": OILSKIN, "back": "coil", "belt": ["knife"], "tool": "net"},
	"hunter": {"tunic": [Color(0.35, 0.3, 0.2), Color(0.28, 0.33, 0.24)], "legs": [Color(0.3, 0.24, 0.16)], "women": 0.2,
		"hat": "fur_cap", "hat_f": "fur_cap", "cloak": "fur", "back": "quiver", "belt": ["knife", "horn"], "tool": "knife"},
	"potter": {"tunic": [Color(0.6, 0.48, 0.36), Color(0.5, 0.4, 0.3)], "dress": [Color(0.55, 0.42, 0.32)], "women": 0.5,
		"hat": "headband", "hat_f": "kerchief", "cloak": "none", "apron": Color(0.62, 0.45, 0.32), "bare_arms": true, "tool": "none"},
	"salter": {"tunic": [Color(0.55, 0.55, 0.52), Color(0.4, 0.44, 0.48)], "dress": [Color(0.5, 0.52, 0.55)], "women": 0.5,
		"hat": "knit_cap", "hat_f": "scarf", "cloak": "none", "apron": LINEN, "tool": "ladle"},
	"peat": {"tunic": [Color(0.35, 0.3, 0.24), Color(0.3, 0.32, 0.26)], "women": 0.2, "hat": "hood", "hood_col": Color(0.36, 0.33, 0.26),
		"cloak": "none", "back": "basket", "tool": "spade"},
	"tarburner": {"tunic": [Color(0.22, 0.2, 0.18), Color(0.3, 0.26, 0.22)], "women": 0.0, "hat": "leather_cap", "cloak": "none",
		"apron": Color(0.18, 0.15, 0.12), "tool": "paddle"},
	"beachcomber": {"tunic": [Color(0.55, 0.5, 0.4), Color(0.45, 0.5, 0.52)], "dress": [Color(0.55, 0.48, 0.38)], "women": 0.6,
		"hat": "straw_hat", "hat_f": "kerchief", "cloak": "none", "back": "basket", "tool": "rake"},
	"brewer": {"tunic": [Color(0.5, 0.35, 0.22), Color(0.42, 0.38, 0.28)], "dress": [Color(0.55, 0.3, 0.2), Color(0.45, 0.4, 0.3)], "women": 0.6,
		"hat": "headband", "hat_f": "kerchief", "cloak": "none", "apron": LINEN, "belt": ["keys"], "tool": "paddle"},
	"baker": {"tunic": [Color(0.75, 0.7, 0.6), Color(0.65, 0.55, 0.42)], "dress": [Color(0.7, 0.62, 0.48)], "women": 0.6,
		"hat": "baker_cap", "hat_f": "baker_cap", "cloak": "none", "apron": Color(0.95, 0.93, 0.88), "bib": true, "bare_arms": true, "tool": "peel"},
	"weaver": {"tunic": [Color(0.5, 0.4, 0.6), Color(0.35, 0.42, 0.6)], "dress": [Color(0.55, 0.4, 0.62), Color(0.3, 0.42, 0.62), Color(0.62, 0.3, 0.3)],
		"women": 0.85, "hat": "headband", "hat_f": "none", "cloak": "team", "belt": ["keys", "pouch"], "tool": "distaff"},
	"tanner": {"tunic": [Color(0.4, 0.32, 0.22)], "women": 0.1, "hat": "leather_cap", "cloak": "none", "apron": LEATHER, "bib": true,
		"bare_arms": true, "tool": "knife"},
	"jeweller": {"tunic": [Color(0.55, 0.18, 0.15), Color(0.2, 0.3, 0.55), Color(0.3, 0.45, 0.3)], "dress": [Color(0.5, 0.15, 0.25)], "women": 0.3,
		"hat": "fine_cap", "hat_f": "none", "cloak": "team", "apron": LEATHER, "belt": ["purse"], "tool": "small_hammer", "elder": 0.4},
	"fletcher": {"tunic": [Color(0.4, 0.42, 0.3), Color(0.45, 0.36, 0.26)], "women": 0.2, "hat": "headband", "cloak": "none",
		"back": "quiver", "belt": ["knife", "pouch"], "tool": "knife"},
	"whaler": {"tunic": [Color(0.3, 0.32, 0.36), Color(0.36, 0.34, 0.3)], "women": 0.0, "hat": "knit_cap", "cloak": "fur",
		"apron": OILSKIN, "back": "coil", "belt": ["knife"], "tool": "harpoon"},
	"shipwright": {"tunic": [Color(0.45, 0.38, 0.3), Color(0.35, 0.4, 0.42)], "women": 0.0, "hat": "leather_cap", "cloak": "none",
		"apron": LEATHER, "back": "toolbag", "belt": ["hammer", "pouch"], "tool": "adze", "elder": 0.3},
	"merchant": {"tunic": [Color(0.6, 0.15, 0.14), Color(0.18, 0.28, 0.6), Color(0.15, 0.42, 0.38)], "dress": [Color(0.6, 0.15, 0.3), Color(0.2, 0.3, 0.6)],
		"women": 0.35, "hat": "fine_cap", "hat_f": "scarf", "cloak": "team_fur", "belt": ["purse", "keys", "knife"], "tool": "none", "elder": 0.4},
	"alewife": {"tunic": [Color(0.5, 0.3, 0.2)], "dress": [Color(0.55, 0.25, 0.18), Color(0.4, 0.45, 0.25)], "women": 0.8,
		"hat": "headband", "hat_f": "kerchief", "cloak": "none", "apron": LINEN, "belt": ["keys", "horn"], "tool": "ladle"},
	"builder": {"tunic": [Color(0.5, 0.42, 0.3), Color(0.42, 0.38, 0.3)], "women": 0.1, "hat": "headband", "cloak": "none",
		"apron": LEATHER, "back": "toolbag", "belt": ["hammer", "pouch"], "tool": "hammer"},
	"chieftain": {"tunic": [Color(0.55, 0.15, 0.15), Color(0.2, 0.25, 0.5)], "dress": [Color(0.5, 0.15, 0.2)], "women": 0.4,
		"hat": "fine_cap", "hat_f": "none", "cloak": "team_fur", "belt": ["purse", "horn", "knife"], "tool": "none", "elder": 0.5},
}

## Which trade works each building.
const BY_BUILDING := {
	"woodcutter": "woodcutter", "quarry": "miner", "mine": "miner", "farm": "farmer", "sheepfold": "herder",
	"horse_farm": "herder", "fishing_hut": "fisher", "hunting_lodge": "hunter", "clay_pit": "potter", "potter": "potter",
	"salt_works": "salter", "smokehouse": "salter", "peat_cutter": "peat", "charcoal": "peat", "tar_kiln": "tarburner",
	"amber_gatherer": "beachcomber", "reed_cutter": "beachcomber", "brewery": "brewer", "bakery": "baker",
	"smithy": "smith", "weaponsmith": "smith", "bloomery": "smith", "weaver": "weaver", "tailor": "weaver",
	"tannery": "tanner", "jeweller": "jeweller", "fletcher": "fletcher", "whaler": "whaler", "sealer": "whaler",
	"shipyard": "shipwright", "trading_post": "merchant", "tavern": "alewife", "town_hall": "chieftain",
	"outpost": "hunter", "barracks": "commoner",
}

static var _cache := {}


static func spec(occ: String) -> Dictionary:
	return SPECS.get(occ, SPECS["commoner"])


static func _cached(key: String, build: Callable) -> Mesh:
	if not _cache.has(key):
		var k := BuildingModels.Kit.new()
		build.call(k)
		_cache[key] = k.commit()
	return _cache[key]


## Headgear, on the head node (the head's centre is at y 0.11, radius 0.12).
static func hat_mesh(kind: String, col: Color) -> Mesh:
	var key: String = "hat_%s_%s" % [kind, col.to_html()]
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	match kind:
		"fur_cap":
			k.frustum(Vector3(0, 0.14, 0.01), 0.142, 0.13, 0.11, FUR, 14)
			k.sphere(Vector3(0, 0.25, 0.01), 0.12, FUR * 0.9, 5, 12)
			k.frustum(Vector3(0, 0.13, 0.01), 0.155, 0.155, 0.05, FUR * 1.25, 14)
		"straw_hat":
			k.cylinder(Vector3(0, 0.19, 0.0), 0.27, 0.018, STRAW, 18)
			k.frustum(Vector3(0, 0.2, 0.0), 0.125, 0.095, 0.11, STRAW * 0.95, 14)
			k.frustum(Vector3(0, 0.2, 0.0), 0.128, 0.126, 0.025, Color(0.55, 0.3, 0.18), 14)
		"knit_cap":
			k.frustum(Vector3(0, 0.13, 0.01), 0.14, 0.07, 0.16, col, 14)
			k.frustum(Vector3(0, 0.125, 0.01), 0.145, 0.143, 0.04, col * 0.8, 14)
			k.sphere(Vector3(0, 0.3, 0.02), 0.04, col * 1.15, 4, 8)
		"leather_cap":
			k.sphere(Vector3(0, 0.15, 0.01), 0.135, LEATHER, 5, 12)
			k.frustum(Vector3(0, 0.12, 0.01), 0.14, 0.14, 0.03, LEATHER * 0.8, 14)
		"baker_cap":
			k.frustum(Vector3(0, 0.14, 0.01), 0.135, 0.15, 0.06, Color(0.96, 0.95, 0.9), 14)
			k.sphere(Vector3(0, 0.25, 0.02), 0.15, Color(0.97, 0.96, 0.92), 5, 12)
		"hood":
			k.frustum(Vector3(0, 0.02, 0.02), 0.16, 0.13, 0.17, col, 12)
			k.sphere(Vector3(0, 0.17, 0.03), 0.145, col, 5, 12)
			k.cone(Vector3(0, 0.25, 0.08), 0.06, 0.12, col, 8)
			k.frustum(Vector3(0, -0.12, 0.02), 0.25, 0.16, 0.14, col * 0.95, 14)
		"fine_cap":
			k.cylinder(Vector3(0, 0.15, 0.01), 0.13, 0.09, BuildingModels.TEAM, 14)
			k.frustum(Vector3(0, 0.13, 0.01), 0.15, 0.15, 0.05, FUR_GREY, 14)
			k.sphere(Vector3(0.0, 0.2, -0.125), 0.025, Color(0.95, 0.78, 0.3), 3, 6)
		"headband":
			k.frustum(Vector3(0, 0.15, 0.01), 0.133, 0.131, 0.03, BuildingModels.TEAM, 14)
		"kerchief":
			k.sphere(Vector3(0, 0.155, 0.02), 0.136, col, 6, 12)
			k.cone(Vector3(0, 0.07, 0.14), 0.06, -0.12, col, 6)
	_cache[key] = k.commit()
	return _cache[key]


## An apron hanging from the belt (on the hips node), long on women; with a bib (on the torso).
static func apron_mesh(col: Color, female: bool) -> Mesh:
	var key: String = "apron_%s_%s" % [col.to_html(), female]
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	var bottom := -0.78 if female else -0.52
	# Clear of the tunic's hem or the dress (which flare out below the belt).
	var top := Vector2(0.17, -0.228)
	var low := Vector2(0.25, -0.345 if female else -0.335)
	k.quad2(Vector3(-top.x, -0.01, top.y), Vector3(top.x, -0.01, top.y), Vector3(low.x, bottom, low.y), Vector3(-low.x, bottom, low.y), col)
	k.box(Vector3(0, -0.01, -0.222), Vector3(0.38, 0.05, 0.03), col * 0.8)
	_cache[key] = k.commit()
	return _cache[key]


static func bib_mesh(col: Color) -> Mesh:
	var key: String = "bib_%s" % col.to_html()
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	k.quad2(Vector3(-0.13, 0.4, -0.212), Vector3(0.13, 0.4, -0.212), Vector3(0.16, 0.02, -0.232), Vector3(-0.16, 0.02, -0.232), col)
	for sd: float in [-1.0, 1.0]:
		k.box(Vector3(sd * 0.11, 0.47, -0.07), Vector3(0.025, 0.02, 0.28), col * 0.8)
	_cache[key] = k.commit()
	return _cache[key]


## A fur cloak (hunters, herders, whalers): a heavy wrap round the shoulders falling behind.
static func fur_cloak_mesh(col: Color) -> Mesh:
	var key: String = "furcloak_%s" % col.to_html()
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	k.frustum(Vector3(0, -0.1, 0.0), 0.27, 0.2, 0.12, col * 1.1, 14)
	var top := [Vector3(-0.25, 0.0, -0.04), Vector3(-0.14, 0.03, 0.04), Vector3(0.14, 0.03, 0.04), Vector3(0.25, 0.0, -0.04)]
	var hem := [Vector3(-0.32, -0.75, 0.04), Vector3(-0.16, -0.78, 0.13), Vector3(0.16, -0.78, 0.13), Vector3(0.32, -0.75, 0.04)]
	for i in 3:
		k.quad2(top[i], top[i + 1], hem[i + 1], hem[i], col)
	for i in 6:
		k.box(Vector3(-0.27 + i * 0.11, -0.77, 0.07), Vector3(0.1, 0.06, 0.05), col * 0.85)
	_cache[key] = k.commit()
	return _cache[key]


## A fur collar over a team cloak (merchants, the chieftain).
static func collar_mesh() -> Mesh:
	var key: String = "collar"
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	k.frustum(Vector3(0, -0.06, 0.0), 0.25, 0.17, 0.1, FUR_GREY, 14)
	_cache[key] = k.commit()
	return _cache[key]


## What hangs on the back (on the torso node; the back is +z).
static func back_mesh(kind: String) -> Mesh:
	var key: String = "back_" + kind
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	match kind:
		"quiver":
			k.cylinder(Vector3(0.08, 0.05, 0.17), 0.055, 0.5, LEATHER, 10, Vector3(-0.3, 1, 0.1).normalized())
			for i in 5:
				k.box(Vector3(-0.07 + i * 0.015, 0.58 + (i % 2) * 0.03, 0.2), Vector3(0.012, 0.1, 0.04), Color(0.9, 0.88, 0.82))
			k.box(Vector3(0.0, 0.3, 0.16), Vector3(0.03, 0.62, 0.02), LEATHER * 0.8, Vector3(0, 0, 0.6))
		"basket":
			k.frustum(Vector3(0, 0.05, 0.25), 0.15, 0.2, 0.36, STRAW * 0.8, 12)
			for y in [0.1, 0.22, 0.34]:
				k.frustum(Vector3(0, y, 0.25), 0.16 + y * 0.12, 0.165 + y * 0.12, 0.02, STRAW * 0.6, 12)
			for sd: float in [-1.0, 1.0]:
				k.box(Vector3(sd * 0.09, 0.3, 0.12), Vector3(0.02, 0.4, 0.02), LEATHER)
		"coil":
			for i in 12:
				var a := TAU * i / 12.0
				k.box(Vector3(cos(a) * 0.16, 0.25 + sin(a) * 0.16, 0.19), Vector3(0.09, 0.05, 0.05), Color(0.62, 0.55, 0.38), Vector3(0, 0, a))
		"toolbag":
			k.box(Vector3(0.0, 0.25, 0.19), Vector3(0.26, 0.24, 0.1), LEATHER)
			k.box(Vector3(0.08, 0.42, 0.19), Vector3(0.03, 0.14, 0.03), BuildingModels.PALE_WOOD)
			k.box(Vector3(-0.06, 0.42, 0.2), Vector3(0.025, 0.12, 0.025), BuildingModels.PALE_WOOD)
	_cache[key] = k.commit()
	return _cache[key]


## Belt kit (on the hips node, the belt at y 0, radius about 0.2).
static func belt_mesh(items: Array) -> Mesh:
	var key: String = "belt_" + ",".join(items)
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	var spots := [Vector3(0.19, -0.04, -0.07), Vector3(-0.19, -0.04, -0.05), Vector3(0.14, -0.05, 0.14), Vector3(-0.14, -0.05, 0.14)]
	for i in mini(items.size(), spots.size()):
		var p: Vector3 = spots[i]
		match String(items[i]):
			"pouch":
				k.box(p + Vector3(0, -0.04, 0), Vector3(0.07, 0.09, 0.06), LEATHER)
				k.box(p + Vector3(0, 0.0, -0.005), Vector3(0.075, 0.03, 0.065), LEATHER * 0.8)
			"knife":
				k.box(p + Vector3(0, -0.08, 0), Vector3(0.025, 0.18, 0.04), LEATHER * 0.7, Vector3(0, 0, 0.25))
				k.box(p + Vector3(0.01, 0.03, 0), Vector3(0.025, 0.06, 0.03), BuildingModels.PALE_WOOD)
			"purse":
				k.sphere(p + Vector3(0, -0.06, 0), 0.05, Color(0.5, 0.25, 0.15), 4, 8)
				k.box(p + Vector3(0, -0.01, 0), Vector3(0.03, 0.03, 0.03), Color(0.9, 0.75, 0.3))
			"keys":
				for j in 3:
					k.box(p + Vector3(j * 0.015 - 0.015, -0.06 - j * 0.01, 0), Vector3(0.01, 0.1, 0.02), BuildingModels.IRON)
			"hammer":
				k.box(p + Vector3(0, -0.1, 0), Vector3(0.025, 0.22, 0.025), BuildingModels.PALE_WOOD)
				k.box(p + Vector3(0, -0.21, 0), Vector3(0.07, 0.04, 0.04), BuildingModels.IRON)
			"horn":
				k.cone(p + Vector3(0, -0.02, 0), 0.04, -0.2, Color(0.85, 0.8, 0.65), 8)
				k.frustum(p + Vector3(0, -0.03, 0), 0.042, 0.042, 0.02, Color(0.85, 0.7, 0.3), 8)
			"lamp":
				k.frustum(p + Vector3(0, -0.12, 0), 0.04, 0.03, 0.08, BuildingModels.IRON, 8)
				k.box(p + Vector3(0, -0.04, 0), Vector3(0.01, 0.08, 0.01), BuildingModels.IRON)
				k.cone(p + Vector3(0, -0.04, 0), 0.015, 0.03, Color(1.0, 0.75, 0.3), 5)
	_cache[key] = k.commit()
	return _cache[key]


## Tools of the trades, held in the right hand (along -z from the hand when the arm hangs).
static func tool_mesh(kind: String) -> Mesh:
	var key: String = "tool_" + kind
	if _cache.has(key):
		return _cache[key]
	var k := BuildingModels.Kit.new()
	var haft := BuildingModels.PALE_WOOD
	var iron := BuildingModels.IRON
	match kind:
		"axe":
			k.box(Vector3(0, 0, -0.38), Vector3(0.04, 0.045, 0.86), haft)
			k.box(Vector3(0, 0.02, -0.76), Vector3(0.035, 0.12, 0.1), iron)
			k.box(Vector3(0, -0.04, -0.79), Vector3(0.03, 0.2, 0.06), iron * 1.3)
		"pick":
			k.box(Vector3(0, 0, -0.35), Vector3(0.04, 0.04, 0.8), haft)
			k.box(Vector3(0, 0.0, -0.72), Vector3(0.045, 0.44, 0.05), iron)
		"hammer":
			k.box(Vector3(0, 0, -0.18), Vector3(0.035, 0.035, 0.42), haft)
			k.box(Vector3(0, 0, -0.4), Vector3(0.09, 0.09, 0.15), iron)
		"small_hammer":
			k.box(Vector3(0, 0, -0.1), Vector3(0.02, 0.02, 0.24), haft)
			k.box(Vector3(0, 0, -0.23), Vector3(0.05, 0.05, 0.08), iron)
		"spade":
			k.box(Vector3(0, 0, -0.4), Vector3(0.035, 0.035, 0.9), haft)
			k.box(Vector3(0, 0, -0.88), Vector3(0.18, 0.02, 0.22), haft * 0.85)
			k.box(Vector3(0, 0, -0.99), Vector3(0.19, 0.022, 0.04), iron)
		"sickle":
			k.box(Vector3(0, 0, -0.1), Vector3(0.03, 0.03, 0.2), haft)
			for i in 5:
				var a := float(i) / 4.0 * PI * 0.8
				k.box(Vector3(0.1 * sin(a), 0, -0.2 - 0.1 * (1.0 - cos(a))), Vector3(0.06, 0.012, 0.025), iron * 1.3, Vector3(0, a, 0))
		"net":
			# A fold of net: a lattice of cord with cork floats along its edge.
			var cord := Color(0.62, 0.56, 0.42)
			for i in 6:
				k.box(Vector3(-0.15 + i * 0.06, -0.16, -0.1), Vector3(0.008, 0.3, 0.008), cord, Vector3(0, 0, 0.1))
			for j in 5:
				k.box(Vector3(0, -0.03 - j * 0.065, -0.1), Vector3(0.34, 0.008, 0.008), cord)
			for i in 4:
				k.sphere(Vector3(-0.13 + i * 0.09, -0.33, -0.1), 0.022, Color(0.78, 0.62, 0.32), 3, 6)
		"paddle":
			k.box(Vector3(0, 0, -0.5), Vector3(0.035, 0.035, 1.1), haft)
			k.box(Vector3(0, 0, -1.05), Vector3(0.12, 0.02, 0.22), haft)
		"peel":
			k.box(Vector3(0, 0, -0.55), Vector3(0.03, 0.03, 1.2), haft)
			k.box(Vector3(0, 0, -1.2), Vector3(0.26, 0.015, 0.3), haft * 1.1)
		"ladle":
			k.box(Vector3(0, 0, -0.22), Vector3(0.025, 0.025, 0.5), haft)
			k.sphere(Vector3(0, -0.03, -0.48), 0.06, haft * 0.9, 4, 8)
		"rake":
			k.box(Vector3(0, 0, -0.45), Vector3(0.03, 0.03, 1.0), haft)
			k.box(Vector3(0, 0, -0.95), Vector3(0.36, 0.03, 0.04), haft)
			for i in 6:
				k.box(Vector3(-0.15 + i * 0.06, -0.04, -0.95), Vector3(0.015, 0.08, 0.015), haft)
		"knife":
			k.box(Vector3(0, 0, -0.05), Vector3(0.025, 0.03, 0.1), haft)
			k.box(Vector3(0, 0, -0.16), Vector3(0.01, 0.04, 0.14), iron * 1.4)
		"harpoon":
			k.box(Vector3(0, 0, -0.5), Vector3(0.035, 0.035, 1.6), haft)
			k.cone(Vector3(0, 0, -1.3), 0.04, -0.25, iron, 6)
			k.box(Vector3(0, 0.04, -1.34), Vector3(0.015, 0.08, 0.015), iron, Vector3(0.6, 0, 0))
		"adze":
			k.box(Vector3(0, 0, -0.25), Vector3(0.035, 0.035, 0.55), haft)
			k.box(Vector3(0, -0.06, -0.52), Vector3(0.09, 0.14, 0.03), iron)
		"crook":
			# A shepherd's crook, upright in the hand.
			k.box(Vector3(0, 0.45, 0), Vector3(0.035, 1.6, 0.035), haft)
			for i in 5:
				var a := float(i) / 4.0 * PI
				k.box(Vector3(0.08 - 0.08 * cos(a), 1.25 + 0.08 * sin(a), 0), Vector3(0.04, 0.04, 0.04), haft)
		"distaff":
			k.box(Vector3(0, 0.25, 0), Vector3(0.025, 0.7, 0.025), haft)
			k.sphere(Vector3(0, 0.55, 0), 0.08, Color(0.92, 0.9, 0.84), 4, 8)
		"none":
			k.box(Vector3(0, -0.02, -0.02), Vector3(0.005, 0.005, 0.005), haft)
		_:
			k.box(Vector3(0, -0.02, -0.02), Vector3(0.005, 0.005, 0.005), haft)
	_cache[key] = k.commit()
	return _cache[key]
