class_name BuildingModels
extends RefCounted
## Procedural Norse buildings, made from a small kit of parts (plank walls, turf and thatch
## roofs, stone plinths, round logs, barrels, posts, fences) into one vertex-coloured mesh per
## kind. Faces in the owner's colour (banners, shields, painted boards) are marked with vertex
## alpha 0 and tinted by shaders/building.gdshader. Local space: the door faces -Z, y = 0 is
## the ground; buildings stand on a stone or timber plinth that reaches down into the slope.
##
## shape(kind) -> {mesh, height, size: Vector2 (footprint), chimney: Vector3 (or none),
##                 door: Vector3, work: Vector3 (where its people work), flag: Vector3 (or none),
##                 cart: bool, boat: bool, fires: [[Vector3, kind]] - torches, braziers, the forge,
##                 ovens and hearths (kind: torch, brazier, forge, hearth), lit by BuildingView}

const WOOD := Color(0.42, 0.28, 0.16)
const DARK_WOOD := Color(0.26, 0.17, 0.1)
const PALE_WOOD := Color(0.62, 0.47, 0.3)
const TURF := Color(0.33, 0.43, 0.2)
const THATCH := Color(0.68, 0.55, 0.3)
const STONE := Color(0.5, 0.49, 0.46)
const DARK_STONE := Color(0.32, 0.31, 0.3)
const EARTH := Color(0.36, 0.28, 0.2)
const IRON := Color(0.22, 0.22, 0.24)
const TEAM := Color(1, 1, 1, 0.0)   # tinted to the owner's colour
const SHINGLE := Color(0.47, 0.38, 0.38)  # weathered wooden shingles (drawn as such by the shader)
const WINDOW := Color(0.11, 0.07, 0.031)
const PAINT := Color(1, 0, 1, 1)  # painted in the household's colour (doors, shutters)  # a window or door opening: dark by day, lit from within at night

static var _cache := {}


## How much bigger than life-size-ish the models are drawn, so a settlement reads from afar.
const SCALE := 1.3


static func shape(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var k := Kit.new()
	k.s = SCALE
	seed(hash(kind))
	var info := {"height": 6.0, "size": Vector2(8, 8), "chimney": null, "door": Vector3(0, 0, -4), "work": Vector3(0, 0, -7),
		"flag": null, "cart": false, "boat": false}
	match kind:
		"hall":
			# The great hall: a long shingled hall with a gallery round it, carved and painted
			# gables with dragon heads, a carved portal; before it two tall pillars hung with the
			# owner's banners, fire baskets either side of the steps and a painted rune stone.
			_longhouse(k, Vector3(0, 0, 1.5), 22.0, 9.5, 3.6, SHINGLE, true, {"gallery": true, "boards": true})
			for s: float in [-1.0, 1.0]:
				_pillar(k, Vector3(s * 4.2, 0, -7.5), 8.5)
				_banner_cloth(k, Vector3(s * 4.2 + s * 0.15, 8.0, -7.5), 1.4, 3.6)
				_torch(k, Vector3(s * 4.2, 3.2, -7.78), Vector3(0, 0, -1))
				_brazier(k, Vector3(s * 2.0, 0, -6.0))
			_rune_stone(k, Vector3(7.5, 0, -7.0), 0.3)
			for i in 3:
				k.box(Vector3(0, 0.1 + i * 0.12, -4.4 - i * 0.55), Vector3(3.4 - i * 0.3, 0.2, 0.6), STONE)
			k.post(Vector3(-9.0, 0, -6.5), 10.0, 0.16, DARK_WOOD)
			info.flag = Vector3(-9.0, 9.6, -6.5)
			info.height = 13.0
			info.size = Vector2(25, 17)
			info.chimney = Vector3(0, 12.4, 1.5)
			info.door = Vector3(0, 0, -4.6)
			info.work = Vector3(5.0, 0, -8.0)
		"longhouse":
			_longhouse(k, Vector3(0, 0, 0.5), 15.0, 7.0, 2.9, TURF, false, {"boards": true})
			# A woodpile against the gable, a bench by the door, a little turf shed behind.
			_woodpile(k, Vector3(9.6, 0, 0.5), 3.5, PI * 0.5)
			k.box(Vector3(2.6, 0.45, -3.3), Vector3(2.2, 0.12, 0.45), PALE_WOOD)
			for x in [1.7, 3.5]:
				k.box(Vector3(x, 0.22, -3.3), Vector3(0.15, 0.45, 0.4), DARK_WOOD)
			_house(k, Vector3(-9.0, 0, 2.5), 4.0, 3.2, 1.8, TURF)
			for i in 2:
				k.barrel(Vector3(-5.0 + i * 0.95, 0, -3.6), 0.42, 0.95)
			info.height = 8.5
			info.size = Vector2(21, 10)
			info.chimney = Vector3(2.0, 7.4, 0.5)
			info.door = Vector3(0, 0, -3.1)
		"storehouse":
			# A stabbur: a store on stone feet that rats cannot climb, the upper floor jutting out
			# over the lower, a steep shingled roof; casks and crates about.
			for x in [-2.8, 2.8]:
				for z in [-2.8, 2.8]:
					k.box(Vector3(x, 0.4, z), Vector3(0.9, 0.8, 0.9), STONE)
					k.box(Vector3(x, 1.0, z), Vector3(1.2, 0.3, 1.2), DARK_STONE)
			k.box(Vector3(0, 1.3, 0), Vector3(7.0, 0.3, 7.0), DARK_WOOD)
			k.planks(Vector3(0, 1.45, 0), Vector3(6.2, 2.6, 6.2), WOOD)
			k.box(Vector3(0, 4.15, 0), Vector3(8.0, 0.3, 8.0), DARK_WOOD)
			k.planks(Vector3(0, 4.3, 0), Vector3(7.6, 2.3, 7.6), WOOD)
			for x in [-3.8, 3.8]:
				for z in [-3.8, 3.8]:
					k.post(Vector3(x, 4.3, z), 2.3, 0.14, DARK_WOOD)
			k.roof(Vector3(0, 6.5, 0), 9.2, 9.0, 3.6, SHINGLE)
			_portal(k, Vector3(0, 1.45, -3.12), 1.8, false)
			_torch_post(k, Vector3(-1.4, 0, -5.4))
			# Steps up to the door.
			for i in 3:
				k.box(Vector3(0, 0.25 + i * 0.4, -4.6 + i * 0.5), Vector3(1.6, 0.18, 0.5), DARK_WOOD)
			for i in 4:
				k.barrel(Vector3(-5.2 + (i % 2) * 0.95, (i / 2) * 1.0, -2.0 + (i % 2) * 0.2), 0.42, 0.95)
			for i in 3:
				k.box(Vector3(4.8, 0.4 + i * 0.75, -1.5 + (i % 2) * 0.4), Vector3(1.1, 0.75, 1.0), PALE_WOOD, Vector3(0, i * 0.3, 0))
			info.height = 10.5
			info.size = Vector2(12, 10)
			info.door = Vector3(0, 0, -5.0)
		"tavern":
			# The mead hall: a shingled hall with a gallery, carved gables, a painted sign; a
			# trestle table and benches in front, casks stacked by the wall.
			_longhouse(k, Vector3(0, 0, 1.0), 16.0, 7.5, 3.0, SHINGLE, true, {"gallery": true})
			_trestle(k, Vector3(-3.5, 0, -6.2))
			_trestle(k, Vector3(3.5, 0, -6.2))
			for i in 5:
				var row := 0 if i < 3 else 1
				k.barrel(Vector3(7.8 + (i - row * 3) * 0.95 + row * 0.47, row * 0.95, -2.4), 0.45, 0.95)
			_pillar(k, Vector3(5.5, 0, -6.5), 4.0)
			k.box(Vector3(5.5, 3.2, -6.85), Vector3(1.6, 1.0, 0.1), TEAM)
			k.box(Vector3(5.5, 3.2, -6.92), Vector3(0.5, 0.5, 0.04), Color(0.85, 0.65, 0.25))
			_brazier(k, Vector3(0, 0, -7.4))
			info.height = 10.0
			info.size = Vector2(20, 14)
			info.chimney = Vector3(-3.0, 9.2, 1.0)
			info.door = Vector3(0, 0, -3.8)
			info.work = Vector3(-3.5, 0, -7.5)
		"hof":
			# A stave temple: on a stone base, a gallery with a lean-to roof all round, then three
			# tiers of crossing shingled roofs, each gable crowned with a dragon, and a spire.
			k.box(Vector3(0, 0.3, 0), Vector3(13.5, 1.2, 13.5), STONE)
			for i in 3:
				k.box(Vector3(0, 0.1 + i * 0.15, -7.2 - i * 0.5), Vector3(3.4 - i * 0.4, 0.2, 0.6), STONE)
			# Gallery: posts round the outside and a skirt of roof.
			for s in 4:
				var ang := PI * 0.5 * s
				var f := Vector3(cos(ang), 0, sin(ang))
				var sd := Vector3(-f.z, 0, f.x)
				for i in 7:
					if s == 3 and i == 3:
						continue
					k.post(f * 6.2 + sd * (-6.0 + i * 2.0) + Vector3(0, 0.9, 0), 2.2, 0.16, DARK_WOOD)
				var a0 := f * 6.7 + sd * 6.7 + Vector3(0, 3.0, 0)
				var a1 := f * 6.7 - sd * 6.7 + Vector3(0, 3.0, 0)
				var b0 := f * 4.4 + sd * 4.4 + Vector3(0, 4.6, 0)
				var b1 := f * 4.4 - sd * 4.4 + Vector3(0, 4.6, 0)
				var gn := (f * 1.6 + Vector3(0, 2.3, 0)).normalized()
				k.roof_face(a0, a1, b0, b1, SHINGLE)
				k.quad(a0 - Vector3(0, 0.2, 0), a1 - Vector3(0, 0.2, 0), b1 - Vector3(0, 0.2, 0), b0 - Vector3(0, 0.2, 0), -gn, DARK_WOOD * 0.7)
			k.planks(Vector3(0, 0.9, 0), Vector3(8.8, 5.2, 8.8), DARK_WOOD)
			var y := 6.1
			var w := 10.0
			for ti in 3:
				var h: float = [2.6, 2.4, 2.0][ti]
				k.roof(Vector3(0, y, 0), w, w, h, SHINGLE)
				k.roof(Vector3(0, y, 0), w, w, h, SHINGLE, true)
				for s in 4:
					var ang := PI * 0.5 * s
					_dragon(k, Vector3(cos(ang), 0, sin(ang)) * (w * 0.5 + 0.2) + Vector3(0, y + h + 0.1, 0), Vector3(cos(ang), 0, sin(ang)))
				if ti < 2:
					var nw: float = w * 0.56
					k.planks(Vector3(0, y + h - 0.2, 0), Vector3(nw - 0.6, 2.2, nw - 0.6), DARK_WOOD)
					y += h + 2.0
					w = nw
				else:
					y += h
			k.cone(Vector3(0, y - 0.2, 0), 1.1, 3.4, SHINGLE, 4)
			k.post(Vector3(0, y + 3.0, 0), 1.6, 0.06, IRON)
			_portal(k, Vector3(0, 0.9, -4.42), 2.4, true)
			for sd: float in [-1.0, 1.0]:
				_brazier(k, Vector3(sd * 2.4, 0, -8.6))
			info.height = y + 4.5
			info.size = Vector2(14, 14)
			info.door = Vector3(0, 0, -8.0)
		"brewery":
			_house(k, Vector3(-2.5, 0, 0.5), 9.0, 6.5, 2.7, THATCH)
			# Two great mash tuns, a copper on a hearth under a lean-to, casks in a pyramid.
			for i in 2:
				var c := Vector3(4.0 + i * 2.6, 0, 1.6)
				k.cylinder(c, 1.2, 1.9, DARK_WOOD, 14)
				for yy in [0.35, 1.0, 1.65]:
					k.cylinder(c + Vector3(0, yy, 0), 1.24, 0.1, IRON, 14)
			k.box(Vector3(5.2, 0.5, -1.8), Vector3(2.0, 1.0, 1.8), STONE)
			k.cylinder(Vector3(5.2, 1.0, -1.8), 0.75, 0.6, Color(0.62, 0.36, 0.2), 12)
			k.fires.append([Vector3(5.2, 0.45, -2.75), "hearth"])
			_lean_to(k, Vector3(5.2, 0, -1.8), 3.4, 3.0, 2.8)
			for i in 6:
				var row: int = [0, 0, 0, 1, 1, 2][i]
				var cl: int = [0, 1, 2, 0, 1, 0][i]
				k.barrel(Vector3(-7.8 + cl * 0.95 + row * 0.47, row * 0.9, -3.4), 0.44, 0.9)
			info.height = 7.5
			info.size = Vector2(16, 9)
			info.chimney = Vector3(5.2, 3.2, -1.8)
			info.door = Vector3(-2.5, 0, -2.8)
			info.work = Vector3(5.2, 0, -3.4)
		"bakery":
			_house(k, Vector3(-2.5, 0, 0.5), 8.5, 6.5, 2.7, THATCH)
			# A big domed oven on a stone footing under its own turf roof; flour sacks, a woodpile.
			var oc := Vector3(4.2, 0, 0.3)
			k.cylinder(oc, 2.0, 0.8, STONE, 14)
			k.cylinder(oc + Vector3(0, 0.8, 0), 1.7, 0.8, Color(0.62, 0.4, 0.26), 14)
			k.sphere(oc + Vector3(0, 1.6, 0), 1.7, Color(0.62, 0.4, 0.26), 6, 14)
			k.box(oc + Vector3(0, 1.3, -1.6), Vector3(0.8, 0.7, 0.3), Color(0.08, 0.05, 0.03))
			k.fires.append([oc + Vector3(0, 1.2, -1.85), "hearth"])
			k.box(oc + Vector3(0.6, 3.3, 0.6), Vector3(0.5, 1.6, 0.5), DARK_STONE)
			_lean_to(k, oc, 4.6, 4.2, 3.7)
			for i in 4:
				k.sphere(Vector3(-7.4 + i * 0.7, 0.35, -3.6 + (i % 2) * 0.3), 0.4, Color(0.86, 0.8, 0.66), 4, 8)
			_woodpile(k, Vector3(4.2, 0, 3.4), 3.0, 0.0)
			info.height = 7.5
			info.size = Vector2(15, 9)
			info.chimney = oc + Vector3(0.6, 4.1, 0.6)
			info.door = Vector3(-2.5, 0, -2.8)
			info.work = oc + Vector3(0, 0, -2.6)
		"smithy":
			# A forge: a stone back wall, a turf roof on stout posts, the hearth with its bellows
			# and chimney, the anvil on its block, a quenching tub, a rack of finished work; and
			# the smith's house behind.
			_house(k, Vector3(0, 0, 4.2), 8.0, 4.5, 2.4, TURF)
			k.box(Vector3(0, 1.3, 1.4), Vector3(8.0, 2.6, 0.7), STONE)
			for x in [-3.8, 0.0, 3.8]:
				k.post(Vector3(x, 0, -2.6), 3.2, 0.24, DARK_WOOD)
			k.box(Vector3(0, 3.2, -2.6), Vector3(8.4, 0.3, 0.35), DARK_WOOD)
			k.roof(Vector3(0, 3.2, -0.6), 9.0, 5.0, 1.8, TURF)
			k.box(Vector3(1.8, 0.6, 0.4), Vector3(2.4, 1.2, 1.6), STONE)
			k.box(Vector3(1.8, 1.25, 0.4), Vector3(1.4, 0.1, 0.9), Color(0.9, 0.35, 0.08))
			k.fires.append([Vector3(1.8, 1.4, 0.4), "forge"])
			k.box(Vector3(1.8, 3.4, 1.0), Vector3(1.0, 4.0, 0.9), DARK_STONE)
			k.box(Vector3(3.5, 0.9, 0.6), Vector3(1.0, 0.6, 1.2), EARTH, Vector3(0, 0, 0.2))
			k.cylinder(Vector3(-0.8, 0, -0.8), 0.4, 0.7, DARK_WOOD, 10)
			k.box(Vector3(-0.8, 0.85, -0.8), Vector3(1.0, 0.3, 0.4), IRON)
			k.barrel(Vector3(-2.4, 0, -0.2), 0.5, 0.8)
			k.box(Vector3(-3.0, 1.2, 0.9), Vector3(1.8, 0.1, 0.1), DARK_WOOD)
			for i in 4:
				k.box(Vector3(-3.7 + i * 0.45, 0.8, 0.85), Vector3(0.06, 1.2, 0.04), IRON, Vector3(0, 0, 0.12))
			info.height = 7.0
			info.size = Vector2(10, 10)
			info.chimney = Vector3(1.8, 5.5, 1.0)
			info.door = Vector3(0, 0, -2.6)
			info.work = Vector3(-0.8, 0, -1.8)
		"hut":
			_house(k, Vector3.ZERO, 7.0, 5.5, 2.4, THATCH)
			for i in 2:
				k.barrel(Vector3(4.3, 0, -1.4 + i * 1.0), 0.4, 0.9)
			info.height = 6.0
			info.size = Vector2(10, 7)
			info.chimney = Vector3(-1.5, 5.0, 0)
			info.door = Vector3(0, 0, -2.8)
		"weaver":
			_house(k, Vector3(-2.0, 0, 0.8), 7.0, 5.5, 2.4, THATCH)
			# A warp-weighted loom under a lean-to, cloth hanging on a line to dry.
			_lean_to(k, Vector3(3.6, 0, -0.4), 3.4, 3.4, 3.2)
			k.post(Vector3(2.6, 0, -0.2), 2.6, 0.08, DARK_WOOD)
			k.post(Vector3(4.6, 0, -0.2), 2.6, 0.08, DARK_WOOD)
			k.log(Vector3(3.6, 2.5, -0.2), 0.07, 2.4, DARK_WOOD, Vector3.RIGHT)
			k.quad2(Vector3(2.75, 2.4, -0.25), Vector3(4.45, 2.4, -0.25), Vector3(4.45, 0.9, -0.25), Vector3(2.75, 0.9, -0.25), TEAM)
			for i in 8:
				k.box(Vector3(2.8 + i * 0.22, 0.6, -0.25), Vector3(0.12, 0.18, 0.12), STONE)
			for x in [-5.5, -1.0]:
				k.post(Vector3(x, 0, -3.6), 2.2, 0.06, DARK_WOOD)
			k.log(Vector3(-3.25, 2.1, -3.6), 0.03, 4.5, DARK_WOOD, Vector3.RIGHT)
			for i in 3:
				var cc: Color = [Color(0.62, 0.5, 0.78), Color(0.78, 0.72, 0.6), Color(0.45, 0.55, 0.7)][i]
				k.quad2(Vector3(-5.1 + i * 1.4, 2.05, -3.6), Vector3(-4.0 + i * 1.4, 2.05, -3.6), Vector3(-4.0 + i * 1.4, 0.9, -3.6), Vector3(-5.1 + i * 1.4, 0.9, -3.6), cc)
			info.height = 6.0
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-3.5, 5.0, 0.8)
			info.door = Vector3(-2.0, 0, -2.0)
			info.work = Vector3(3.6, 0, -1.4)
		"lodge":
			_house(k, Vector3(-1.5, 0, 0.8), 7.5, 5.5, 2.4, TURF)
			# Antlers over the door, hides stretched on frames, a pile of furs.
			for s: float in [-1.0, 1.0]:
				k.log(Vector3(-1.5 + s * 0.45, 3.0, -2.05), 0.04, 0.9, PALE_WOOD * 1.3, Vector3(s, 1.0, 0).normalized())
				k.log(Vector3(-1.5 + s * 0.7, 3.35, -2.05), 0.03, 0.5, PALE_WOOD * 1.3, Vector3(s * 0.3, 1.0, 0).normalized())
			for i in 2:
				var fc := Vector3(3.2 + i * 2.0, 0, -1.0 + i * 0.6)
				k.post(fc + Vector3(-0.8, 0, 0), 2.2, 0.06, DARK_WOOD)
				k.post(fc + Vector3(0.8, 0, 0), 2.2, 0.06, DARK_WOOD)
				k.log(fc + Vector3(0, 2.1, 0), 0.05, 1.8, DARK_WOOD, Vector3.RIGHT)
				k.log(fc + Vector3(0, 0.4, 0), 0.05, 1.8, DARK_WOOD, Vector3.RIGHT)
				k.quad2(fc + Vector3(-0.65, 1.95, 0), fc + Vector3(0.65, 1.95, 0), fc + Vector3(0.5, 0.55, 0), fc + Vector3(-0.5, 0.55, 0), Color(0.6, 0.45, 0.3))
			for i in 4:
				k.box(Vector3(-6.0 + i * 0.25, 0.25 + i * 0.12, -2.8), Vector3(1.2, 0.1, 0.9), Color(0.45, 0.32, 0.22) * (0.9 + 0.1 * i))
			info.height = 6.0
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-3.5, 5.0, 0.8)
			info.door = Vector3(-1.5, 0, -2.0)
			info.work = Vector3(4.2, 0, -2.2)
		"claypit":
			_house(k, Vector3(-2.5, 0, 1.0), 6.0, 4.8, 2.2, TURF)
			# A dug pit, a heap of clay, pots set out to dry on boards.
			k.box(Vector3(3.2, 0.02, -0.5), Vector3(4.0, 0.06, 3.0), Color(0.26, 0.18, 0.12))
			k.cone(Vector3(5.8, 0, 1.6), 1.3, 1.0, Color(0.68, 0.44, 0.3), 10)
			k.box(Vector3(-2.5, 0.5, -2.8), Vector3(3.6, 0.1, 0.8), PALE_WOOD)
			for i in 5:
				var pc := Vector3(-4.0 + i * 0.75, 0.55, -2.8)
				k.frustum(pc, 0.18, 0.26, 0.3, Color(0.72, 0.46, 0.32), 10)
				k.frustum(pc + Vector3(0, 0.3, 0), 0.26, 0.14, 0.2, Color(0.72, 0.46, 0.32), 10)
			info.height = 5.5
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-4.0, 4.6, 1.0)
			info.door = Vector3(-2.5, 0, -1.4)
			info.work = Vector3(3.2, 0, -1.0)
		"saltworks":
			_house(k, Vector3(-2.5, 0, 1.0), 6.5, 5.0, 2.3, THATCH)
			# A wide iron pan on a stone hearth, white heaps of salt, barrels of brine.
			k.box(Vector3(3.6, 0.4, -0.2), Vector3(3.6, 0.8, 2.6), STONE)
			k.box(Vector3(3.6, 0.88, -0.2), Vector3(3.3, 0.16, 2.3), IRON)
			k.box(Vector3(3.6, 0.95, -0.2), Vector3(3.0, 0.04, 2.0), Color(0.82, 0.86, 0.88))
			k.fires.append([Vector3(3.6, 0.45, -1.55), "hearth"])
			for i in 3:
				k.cone(Vector3(1.0 + i * 1.3, 0, -3.0), 0.55, 0.8, Color(0.97, 0.97, 0.97), 10)
			for i in 3:
				k.barrel(Vector3(6.2, 0, -1.2 + i * 1.0), 0.42, 0.95)
			info.height = 5.5
			info.size = Vector2(13, 8)
			info.chimney = Vector3(3.6, 1.4, 0.8)
			info.door = Vector3(-2.5, 0, -1.6)
			info.work = Vector3(3.6, 0, -1.8)
		"peat":
			_house(k, Vector3(-2.5, 0, 1.0), 6.0, 4.8, 2.2, TURF)
			# Peats stacked in little open towers to dry, and in a long rick.
			for i in 3:
				var pc := Vector3(1.6 + i * 1.6, 0, -1.6 + (i % 2) * 1.2)
				for lv in 4:
					for s in 4:
						var ang := PI * 0.5 * s + lv * 0.4
						k.box(pc + Vector3(cos(ang) * 0.35, 0.15 + lv * 0.28, sin(ang) * 0.35), Vector3(0.5, 0.25, 0.22), Color(0.32, 0.23, 0.16) * (0.85 + 0.05 * lv), Vector3(0, ang, 0))
			for i in 6:
				k.box(Vector3(-4.6 + i * 0.6, 0.25, -3.0), Vector3(0.55, 0.5, 0.8), Color(0.3, 0.22, 0.15) * (0.9 + 0.04 * (i % 3)))
			info.height = 5.5
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-4.0, 4.6, 1.0)
			info.door = Vector3(-2.5, 0, -1.4)
			info.work = Vector3(3.0, 0, -2.6)
		"amber":
			_house(k, Vector3(-1.5, 0, 1.0), 6.0, 4.6, 2.2, THATCH)
			# A sorting table with baskets, more baskets by the door.
			k.box(Vector3(3.2, 0.8, -1.2), Vector3(2.4, 0.1, 1.2), PALE_WOOD)
			for x in [2.2, 4.2]:
				k.post(Vector3(x, 0, -1.2), 0.8, 0.06, DARK_WOOD)
			for i in 3:
				k.frustum(Vector3(2.4 + i * 0.8, 0.85, -1.2), 0.18, 0.26, 0.25, THATCH, 10)
				k.sphere(Vector3(2.4 + i * 0.8, 1.12, -1.2), 0.12, Color(0.95, 0.58, 0.12), 3, 6)
			for i in 2:
				k.frustum(Vector3(5.2, 0, -2.6 + i * 0.9), 0.35, 0.45, 0.6, THATCH, 10)
			info.height = 5.5
			info.size = Vector2(11, 8)
			info.chimney = Vector3(-3.0, 4.6, 1.0)
			info.door = Vector3(-1.5, 0, -1.4)
			info.work = Vector3(3.2, 0, -2.4)
		"woodcutter":
			_house(k, Vector3(-3.0, 0, 1.0), 7.0, 5.5, 2.4, TURF)
			# A big log pile, firewood stacked in a rick, a saw-horse and the chopping block.
			for row in 3:
				for i in 5 - row:
					k.log(Vector3(3.6, 0.35 + row * 0.6, -1.6 + i * 0.65 + row * 0.32), 0.3, 4.2, PALE_WOOD, Vector3.RIGHT)
			_woodpile(k, Vector3(-3.0, 0, 4.4), 6.0, 0.0)
			k.cylinder(Vector3(1.4, 0, -3.2), 0.5, 0.65, WOOD, 10)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(4.6 + s * 0.6, 0.45, -3.2), Vector3(0.08, 1.0, 0.08), DARK_WOOD, Vector3(0, 0, s * 0.4))
			k.log(Vector3(4.6, 0.85, -3.2), 0.14, 2.2, PALE_WOOD, Vector3.BACK)
			info.height = 6.0
			info.size = Vector2(13, 9)
			info.chimney = Vector3(-4.8, 5.0, 1.0)
			info.door = Vector3(-3.0, 0, -1.8)
			info.work = Vector3(1.4, 0, -4.2)
		"quarry":
			# A rock face cut in steps, a lifting crane of three poles with a block on its rope, a
			# lean-to for the tools and rows of cut blocks.
			for i in 3:
				k.box(Vector3(0.5, 0.9 + i * 0.9, 3.2 + i * 0.8), Vector3(9.0 - i * 1.5, 1.8, 1.6), DARK_STONE, Vector3(0, 0.05 * i, 0))
			_lean_to(k, Vector3(-3.6, 0, -0.2), 3.6, 3.0, 2.8)
			_torch_post(k, Vector3(-1.4, 0, -2.2))
			for i in 8:
				k.box(Vector3(0.8 + (i % 4) * 1.15, 0.4 + (i / 4) * 0.8, -1.2 + (i % 2) * 0.25), Vector3(1.05, 0.75, 0.85), STONE)
			var tc := Vector3(3.2, 0, 1.0)
			for a in 3:
				var ang := TAU * a / 3.0
				k.log(tc + Vector3(cos(ang) * 1.1, 2.4, sin(ang) * 1.1), 0.09, 5.0, DARK_WOOD, Vector3(-cos(ang) * 0.3, 1, -sin(ang) * 0.3).normalized())
			k.log(tc + Vector3(0, 3.0, 0), 0.015, 2.6, Color(0.5, 0.45, 0.35), Vector3.UP)
			k.box(tc + Vector3(0, 1.5, 0), Vector3(0.8, 0.6, 0.7), STONE)
			info.height = 6.0
			info.size = Vector2(11, 10)
			info.work = Vector3(2.5, 0, -2.6)
			info.cart = true
		"mine":
			# A timbered adit into a rocky hill, a spoil heap, a winch, the miners' hut.
			k.cone(Vector3(0, 0, 3.0), 6.0, 5.0, DARK_STONE, 10)
			k.cone(Vector3(2.5, 0, 4.0), 4.0, 3.5, STONE * 0.8, 9)
			k.box(Vector3(0, 0.1, -1.0), Vector3(2.8, 2.6, 1.2), Color(0.04, 0.035, 0.03))
			for x in [-1.6, 1.6]:
				k.post(Vector3(x, 0, -1.6), 2.9, 0.24, DARK_WOOD)
			k.box(Vector3(0, 2.9, -1.6), Vector3(4.0, 0.45, 0.5), DARK_WOOD)
			k.box(Vector3(0, 3.35, -1.65), Vector3(1.8, 0.35, 0.1), TEAM)
			for sd: float in [-1.0, 1.0]:
				_torch(k, Vector3(sd * 1.6, 2.2, -1.85), Vector3(0, 0, -1))
			k.cone(Vector3(5.4, 0, -2.0), 2.2, 1.6, Color(0.4, 0.36, 0.32), 8)
			for x in [-0.8, 0.8]:
				k.post(Vector3(x - 3.0, 0, -3.0), 1.4, 0.08, DARK_WOOD)
			k.log(Vector3(-3.0, 1.2, -3.0), 0.18, 1.6, WOOD, Vector3.RIGHT)
			_house(k, Vector3(-6.0, 0, 0.5), 5.0, 4.2, 2.1, TURF)
			info.height = 6.5
			info.size = Vector2(16, 11)
			info.door = Vector3(0, 0, -2.2)
			info.work = Vector3(0, 0, -3.6)
			info.chimney = Vector3(-7.2, 4.4, 0.5)
			info.cart = true
		"fishing_hut":
			_house(k, Vector3(-2.5, 0, 1.0), 7.0, 5.0, 2.3, THATCH)
			# Drying racks hung with fish, a net on poles, an upturned boat on trestles.
			for r in 2:
				var z := -2.0 + r * 1.4
				k.post(Vector3(1.8, 0, z), 2.0, 0.08, DARK_WOOD)
				k.post(Vector3(5.2, 0, z), 2.0, 0.08, DARK_WOOD)
				k.log(Vector3(3.5, 1.9, z), 0.05, 3.6, DARK_WOOD, Vector3.RIGHT)
				for f in 6:
					k.box(Vector3(2.2 + f * 0.55, 1.55, z), Vector3(0.18, 0.6, 0.05), Color(0.6, 0.62, 0.58))
			for x in [-6.2, -4.2]:
				k.post(Vector3(x, 0, -3.2), 2.4, 0.06, DARK_WOOD)
			k.quad2(Vector3(-6.2, 2.3, -3.2), Vector3(-4.2, 2.3, -3.2), Vector3(-4.4, 0.6, -3.25), Vector3(-6.0, 0.6, -3.25), Color(0.45, 0.42, 0.36))
			for x in [2.2, 4.8]:
				k.box(Vector3(x, 0.4, 2.8), Vector3(0.2, 0.8, 1.4), DARK_WOOD)
			var hull := [Vector3(1.0, 1.3, 2.8), Vector3(2.0, 0.9, 2.2), Vector3(5.0, 0.9, 2.2), Vector3(6.0, 1.3, 2.8), Vector3(5.0, 0.9, 3.4), Vector3(2.0, 0.9, 3.4)]
			for i in 6:
				var ha: Vector3 = hull[i]
				var hb: Vector3 = hull[(i + 1) % 6]
				k.quad2(ha, hb, Vector3(hb.x * 0.95 + 0.2, 1.45, 2.8), Vector3(ha.x * 0.95 + 0.2, 1.45, 2.8), WOOD)
			info.height = 5.5
			info.size = Vector2(13, 8)
			info.chimney = Vector3(-4.0, 4.8, 1.0)
			info.door = Vector3(-2.5, 0, -1.6)
			info.work = Vector3(3.4, 0, -3.4)
			info.boat = true
		"farm":
			# The farmhouse and, beside it, a byre; a haystack, a fence along the front.
			_longhouse(k, Vector3(-2.5, 0, 1.5), 11.0, 6.0, 2.6, THATCH, false, {"boards": true})
			_house(k, Vector3(7.2, 0, 1.5), 5.0, 4.4, 2.1, TURF)
			k.cone(Vector3(6.6, 0, -3.4), 1.6, 3.0, Color(0.82, 0.7, 0.36), 12)
			k.post(Vector3(6.6, 0, -3.4), 3.6, 0.05, DARK_WOOD)
			_fence(k, Vector3(0.0, 0, -5.8), 13.0, 0.0)
			k.barrel(Vector3(-7.5, 0, -2.0), 0.42, 0.9)
			info.height = 7.0
			info.size = Vector2(19, 12)
			info.chimney = Vector3(-4.2, 5.9, 1.5)
			info.door = Vector3(-2.5, 0, -1.6)
			info.work = Vector3(2.0, 0, -8.0)
		"fold":
			_house(k, Vector3(-4.0, 0, 2.0), 5.0, 4.2, 2.1, TURF)
			for side in 4:
				var ang := PI * 0.5 * side
				_fence(k, Vector3(1.8, 0, -0.5) + Vector3(cos(ang), 0, sin(ang)) * 4.0, 8.0, ang + PI * 0.5)
			# A hay rack in the pen, a water trough.
			k.cone(Vector3(1.8, 0, 0.6), 1.0, 1.6, Color(0.82, 0.7, 0.36), 10)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(1.8 + s * 0.9, 0.7, 0.6), Vector3(0.08, 1.4, 0.08), DARK_WOOD, Vector3(0, 0, s * 0.3))
			k.box(Vector3(3.4, 0.3, -2.4), Vector3(1.8, 0.5, 0.6), WOOD)
			info.height = 5.0
			info.size = Vector2(13, 10)
			info.chimney = Vector3(-5.2, 4.2, 2.0)
			info.work = Vector3(1.8, 0, -0.5)
		"kiln":
			# A tar pit mound, smoking, with pine roots stacked beside and barrels of tar.
			k.cone(Vector3(2.0, 0, 0), 3.0, 2.5, EARTH, 12)
			k.cylinder(Vector3(2.0, 2.3, 0), 0.55, 0.6, DARK_STONE, 8)
			k.box(Vector3(2.0, 0.15, -3.0), Vector3(1.2, 0.3, 0.8), Color(0.06, 0.05, 0.04))
			k.fires.append([Vector3(2.0, 0.7, -2.6), "hearth"])
			_house(k, Vector3(-4.0, 0, 1.0), 5.0, 4.2, 2.1, TURF)
			_woodpile(k, Vector3(6.2, 0, 0.5), 3.0, PI * 0.5)
			for i in 3:
				k.barrel(Vector3(-0.5 + i * 0.95, 0, -3.2), 0.42, 0.95)
			info.height = 5.0
			info.size = Vector2(14, 8)
			info.chimney = Vector3(2.0, 3.0, 0)
			info.work = Vector3(2.0, 0, -3.2)
		"tower":
			# A stone footing, four great posts braced with crossed timbers, a railed fighting
			# platform hung with shields, a roof, and the flag above.
			var h := 11.0
			k.box(Vector3(0, 0.9, 0), Vector3(5.6, 1.8, 5.6), STONE)
			for x in [-1.8, 1.8]:
				for z in [-1.8, 1.8]:
					k.post(Vector3(x, 1.8, z), h - 1.8, 0.26, DARK_WOOD)
			for yy in [4.5, 8.0]:
				for s in 4:
					var ang := PI * 0.5 * s
					var f := Vector3(cos(ang), 0, sin(ang)) * 1.8
					var sd := Vector3(-sin(ang), 0, cos(ang))
					k.box(Vector3(f.x, yy, f.z), Vector3(0.14 + absf(sd.x) * 3.8, 0.16, 0.14 + absf(sd.z) * 3.8), DARK_WOOD)
					k.box(Vector3(f.x, yy - 1.5, f.z), Vector3(0.1 + absf(sd.x) * 4.4, 0.12, 0.1 + absf(sd.z) * 4.4), DARK_WOOD, Vector3(0.6 * absf(sd.z), 0, 0.6 * absf(sd.x)))
			k.box(Vector3(0, h, 0), Vector3(5.2, 0.3, 5.2), WOOD)
			for s in 4:
				var ang := PI * 0.5 * s
				var out := Vector3(cos(ang), 0, sin(ang))
				var o := out * 2.55
				var sd := Vector3(-sin(ang), 0, cos(ang))
				k.box(Vector3(o.x, h + 0.6, o.z), Vector3(0.1 + absf(sd.x) * 5.0, 1.0, 0.1 + absf(sd.z) * 5.0), PALE_WOOD)
				for i in 3:
					k.disc(Vector3(o.x, h + 0.55, o.z) + sd * (-1.5 + i * 1.5) + out * 0.08, 0.42, TEAM, out)
			for x in [-2.4, 2.4]:
				for z in [-2.4, 2.4]:
					k.post(Vector3(x, h, z), 2.0, 0.1, DARK_WOOD)
			k.roof(Vector3(0, h + 2.0, 0), 6.0, 6.0, 2.2, SHINGLE)
			_brazier(k, Vector3(1.4, h + 0.15, 1.4))
			k.post(Vector3(0, h + 3.8, 0), 2.4, 0.07, DARK_WOOD)
			k.box(Vector3(0, h * 0.5, -1.95), Vector3(0.5, h, 0.08), DARK_WOOD)
			info.flag = Vector3(0, h + 6.0, 0)
			info.height = h + 6.2
			info.size = Vector2(6, 6)
			info.door = Vector3(0, 0, -3.2)
			info.work = Vector3(0, h + 0.3, 0)
		"barracks":
			_longhouse(k, Vector3(0, 0, 3.0), 17.0, 7.5, 3.0, SHINGLE, true, {"gallery": true})
			# A fenced yard with a straw target and training posts, a rack of spears.
			_fence(k, Vector3(0, 0, -7.5), 16.0, 0.0)
			for s: float in [-1.0, 1.0]:
				_fence(k, Vector3(s * 8.0, 0, -4.0), 7.0, PI * 0.5)
			for i in 3:
				k.post(Vector3(2.5 + i * 2.0, 0, -5.6), 1.8, 0.15, PALE_WOOD)
				k.box(Vector3(2.5 + i * 2.0, 1.4, -5.6), Vector3(1.0, 0.12, 0.12), PALE_WOOD)
			k.cylinder(Vector3(-5.5, 1.1, -5.2), 0.6, 0.25, THATCH, 14, Vector3.BACK)
			k.box(Vector3(-5.5, 0.5, -5.0), Vector3(0.08, 1.0, 0.08), DARK_WOOD)
			for i in 6:
				k.log(Vector3(-3.4 + i * 0.35, 1.3, -4.8), 0.035, 2.6, DARK_WOOD, Vector3(0, 1, 0.2).normalized())
			k.box(Vector3(-2.5, 1.8, -4.9), Vector3(2.6, 0.1, 0.1), DARK_WOOD)
			info.height = 10.0
			info.size = Vector2(18, 15)
			info.chimney = Vector3(3.0, 9.0, 3.0)
			info.door = Vector3(0, 0, -1.0)
			info.work = Vector3(4.5, 0, -6.6)
		"stable":
			# A long low stable, a paddock fence, a hay rack and horses at the rail.
			_longhouse(k, Vector3(-2.0, 0, 2.5), 11.0, 5.0, 2.2, TURF, false)
			for side in 4:
				var ang := PI * 0.5 * side
				_fence(k, Vector3(3.0, 0, -3.5) + Vector3(cos(ang), 0, sin(ang)) * 3.5, 7.0, ang + PI * 0.5)
			for i in 2:
				_horse(k, Vector3(2.0 + i * 2.4, 0, -3.0 - i * 1.2), 0.4 + i * 1.9)
			k.cone(Vector3(-6.5, 0, -2.0), 1.2, 2.2, Color(0.82, 0.7, 0.36), 10)
			info.height = 6.0
			info.size = Vector2(14, 13)
			info.chimney = Vector3(-4.0, 5.0, 2.5)
			info.door = Vector3(-2.0, 0, -0.1)
			info.work = Vector3(3.0, 0, -3.5)
		"reeds":
			# A reed-thatched hut and sheaves of reeds stood up to dry in stooks.
			_house(k, Vector3(-2.0, 0, 1.0), 6.0, 4.6, 2.2, THATCH)
			for i in 5:
				var c := Vector3(2.4 + (i % 3) * 1.4, 0, -2.0 + (i / 3) * 1.8)
				for j in 6:
					var a := TAU * j / 6.0
					k.log(c + Vector3(cos(a) * 0.25, 1.0, sin(a) * 0.25), 0.07, 2.0, Color(0.74, 0.68, 0.42), Vector3(-cos(a) * 0.15, 1, -sin(a) * 0.15).normalized())
			info.height = 5.0
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-3.5, 4.4, 1.0)
			info.door = Vector3(-2.0, 0, -1.4)
			info.work = Vector3(3.0, 0, -3.0)
		"smokehouse":
			# A low smokehouse, racks of fish drying, salt barrels.
			_house(k, Vector3(-2.5, 0, 1.0), 7.0, 5.0, 2.2, TURF)
			for r in 3:
				var z := -2.4 + r * 1.2
				k.post(Vector3(1.6, 0, z), 2.0, 0.07, DARK_WOOD)
				k.post(Vector3(5.6, 0, z), 2.0, 0.07, DARK_WOOD)
				k.log(Vector3(3.6, 1.9, z), 0.05, 4.2, DARK_WOOD, Vector3.RIGHT)
				for f in 7:
					k.box(Vector3(2.0 + f * 0.55, 1.5, z), Vector3(0.2, 0.7, 0.05), Color(0.78, 0.74, 0.6))
			for i in 3:
				k.barrel(Vector3(-6.6 + i * 0.95, 0, -2.6), 0.42, 0.9)
				k.cylinder(Vector3(-6.6 + i * 0.95, 0.9, -2.6), 0.36, 0.06, Color(0.95, 0.95, 0.95), 8)
			info.height = 5.5
			info.size = Vector2(14, 8)
			info.chimney = Vector3(-2.5, 4.6, 1.0)
			info.door = Vector3(-2.5, 0, -1.6)
			info.work = Vector3(3.6, 0, -3.4)
		"charcoal":
			# A smouldering stack under turf, wood split and stacked ready, the burner's shelter.
			k.cone(Vector3(1.5, 0, 0), 2.6, 2.2, TURF, 12)
			k.cone(Vector3(1.5, 1.9, 0), 0.6, 0.5, Color(0.12, 0.1, 0.08), 8)
			k.fires.append([Vector3(1.5, 0.3, -2.4), "hearth"])
			_woodpile(k, Vector3(-3.5, 0, -1.0), 4.0, 0.0)
			_lean_to(k, Vector3(-3.5, 0, 2.0), 3.6, 2.6, 2.5)
			info.height = 4.0
			info.size = Vector2(11, 8)
			info.chimney = Vector3(1.5, 2.6, 0)
			info.work = Vector3(1.5, 0, -3.0)
		"bloomery":
			# Two clay shaft furnaces on a stone hearth, bellows, a pile of ore, a quenching trough.
			_house(k, Vector3(-3.5, 0, 1.5), 6.0, 4.6, 2.2, TURF)
			k.box(Vector3(2.5, 0.25, 0), Vector3(5.0, 0.5, 3.0), STONE)
			for i in 2:
				var c := Vector3(1.4 + i * 2.2, 0.5, 0.3)
				k.frustum(c, 0.8, 0.5, 2.2, Color(0.66, 0.42, 0.28), 10)
				k.box(c + Vector3(0, 0.3, -0.75), Vector3(0.4, 0.5, 0.15), Color(0.08, 0.05, 0.03))
				k.fires.append([c + Vector3(0, 0.45, -0.85), "forge"])
				k.box(c + Vector3(0.0, 0.6, 1.0), Vector3(0.6, 0.4, 0.8), EARTH, Vector3(0.3, 0, 0))
			k.cone(Vector3(5.6, 0, -2.0), 1.1, 0.8, Color(0.5, 0.3, 0.22), 9)
			k.box(Vector3(0.5, 0.25, -2.4), Vector3(1.6, 0.5, 0.6), WOOD)
			info.height = 5.0
			info.size = Vector2(13, 8)
			info.chimney = Vector3(1.4, 2.8, 0.3)
			info.door = Vector3(-3.5, 0, -0.9)
			info.work = Vector3(2.5, 0, -2.2)
		"potter":
			# A hut, a domed kiln, a wheel under a lean-to, pots on boards.
			_house(k, Vector3(-3.0, 0, 1.0), 6.5, 4.8, 2.3, THATCH)
			var kc := Vector3(3.6, 0, 1.0)
			k.cylinder(kc, 1.4, 0.7, STONE, 12)
			k.sphere(kc + Vector3(0, 0.7, 0), 1.3, Color(0.64, 0.42, 0.28), 6, 12)
			k.box(kc + Vector3(0, 0.5, -1.3), Vector3(0.6, 0.5, 0.2), Color(0.08, 0.05, 0.03))
			k.fires.append([kc + Vector3(0, 0.55, -1.45), "hearth"])
			_lean_to(k, Vector3(0.8, 0, -2.2), 2.6, 2.4, 2.4)
			k.cylinder(Vector3(0.8, 0, -2.2), 0.4, 0.6, DARK_WOOD, 12)
			k.cylinder(Vector3(0.8, 0.6, -2.2), 0.3, 0.05, Color(0.7, 0.46, 0.32), 12)
			k.box(Vector3(-3.0, 0.6, -2.6), Vector3(3.4, 0.08, 0.7), PALE_WOOD)
			for i in 6:
				var pc := Vector3(-4.4 + i * 0.55, 0.64, -2.6)
				k.frustum(pc, 0.14, 0.2, 0.22, Color(0.72, 0.46, 0.32), 10)
				k.frustum(pc + Vector3(0, 0.22, 0), 0.2, 0.1, 0.16, Color(0.72, 0.46, 0.32), 10)
			info.height = 5.5
			info.size = Vector2(13, 8)
			info.chimney = kc + Vector3(0, 2.0, 0)
			info.door = Vector3(-3.0, 0, -1.4)
			info.work = Vector3(0.8, 0, -3.0)
		"tannery":
			# Square pits of brown liquor framed in planks, hides stretched on frames.
			_house(k, Vector3(-3.5, 0, 1.5), 6.0, 4.6, 2.2, TURF)
			for i in 4:
				var pc := Vector3(1.0 + (i % 2) * 2.0, 0, -1.6 + (i / 2) * 2.0)
				k.box(pc + Vector3(0, 0.15, 0), Vector3(1.7, 0.3, 1.7), WOOD)
				k.box(pc + Vector3(0, 0.29, 0), Vector3(1.4, 0.04, 1.4), Color(0.3, 0.2, 0.1))
			for i in 2:
				var fc := Vector3(5.6, 0, -1.6 + i * 2.0)
				k.post(fc + Vector3(0, 0, -0.8), 2.2, 0.06, DARK_WOOD)
				k.post(fc + Vector3(0, 0, 0.8), 2.2, 0.06, DARK_WOOD)
				k.quad2(fc + Vector3(0, 1.9, -0.65), fc + Vector3(0, 1.9, 0.65), fc + Vector3(0, 0.5, 0.5), fc + Vector3(0, 0.5, -0.5), Color(0.55, 0.38, 0.24))
			info.height = 5.0
			info.size = Vector2(13, 8)
			info.chimney = Vector3(-5.0, 4.4, 1.5)
			info.door = Vector3(-3.5, 0, -0.9)
			info.work = Vector3(2.0, 0, -2.8)
		"tailor":
			# A house, cloth and garments hanging on lines, a cutting table.
			_house(k, Vector3(-2.0, 0, 1.0), 7.5, 5.5, 2.4, THATCH)
			for x in [2.6, 6.0]:
				k.post(Vector3(x, 0, -2.2), 2.2, 0.06, DARK_WOOD)
			k.log(Vector3(4.3, 2.1, -2.2), 0.03, 3.4, DARK_WOOD, Vector3.RIGHT)
			for i in 3:
				var cc: Color = [Color(0.62, 0.22, 0.16), Color(0.28, 0.36, 0.55), Color(0.45, 0.55, 0.3)][i]
				var x := 2.9 + i * 1.05
				k.quad2(Vector3(x, 2.05, -2.2), Vector3(x + 0.85, 2.05, -2.2), Vector3(x + 0.75, 0.9, -2.22), Vector3(x + 0.1, 0.9, -2.22), cc)
				k.quad2(Vector3(x, 2.0, -2.2), Vector3(x - 0.3, 1.5, -2.22), Vector3(x - 0.15, 1.4, -2.22), Vector3(x + 0.05, 1.8, -2.2), cc)
			k.box(Vector3(-2.0, 0.8, -3.6), Vector3(2.4, 0.1, 1.0), PALE_WOOD)
			k.box(Vector3(-2.0, 0.87, -3.6), Vector3(1.6, 0.04, 0.7), Color(0.55, 0.45, 0.7))
			info.height = 6.0
			info.size = Vector2(13, 9)
			info.chimney = Vector3(-4.0, 5.0, 1.0)
			info.door = Vector3(-2.0, 0, -1.8)
			info.work = Vector3(-2.0, 0, -4.4)
		"jeweller":
			# A neat shingled house with a small forge, a bench with tools and a strongbox.
			_longhouse(k, Vector3(-1.5, 0, 1.5), 8.0, 5.5, 2.5, SHINGLE, false, {"boards": true})
			k.box(Vector3(4.0, 0.5, -0.5), Vector3(1.2, 1.0, 1.2), STONE)
			k.box(Vector3(4.0, 1.05, -0.5), Vector3(0.7, 0.1, 0.7), Color(0.9, 0.4, 0.1))
			k.fires.append([Vector3(4.0, 1.2, -0.5), "hearth"])
			k.box(Vector3(4.0, 2.2, -0.2), Vector3(0.45, 2.2, 0.45), DARK_STONE)
			k.box(Vector3(1.6, 0.8, -2.4), Vector3(2.0, 0.1, 0.8), PALE_WOOD)
			for x in [0.8, 2.4]:
				k.post(Vector3(x, 0, -2.4), 0.8, 0.05, DARK_WOOD)
			for i in 4:
				k.box(Vector3(1.0 + i * 0.4, 0.88, -2.4), Vector3(0.12, 0.06, 0.12), [Color(1.0, 0.8, 0.25), Color(0.82, 0.84, 0.88), Color(0.95, 0.6, 0.15), Color(0.55, 0.35, 0.85)][i])
			k.box(Vector3(-5.0, 0.35, -2.0), Vector3(1.0, 0.7, 0.7), DARK_WOOD)
			k.box(Vector3(-5.0, 0.35, -2.37), Vector3(0.8, 0.08, 0.04), IRON)
			info.height = 6.5
			info.size = Vector2(12, 9)
			info.chimney = Vector3(4.0, 3.4, -0.2)
			info.door = Vector3(-1.5, 0, -1.3)
			info.work = Vector3(1.6, 0, -3.2)
		"fletcher":
			# A hut, bundles of shafts, a rack of finished arrows, a butt to test them on.
			_house(k, Vector3(-2.0, 0, 1.0), 6.5, 5.0, 2.3, THATCH)
			k.box(Vector3(2.8, 0.8, -1.8), Vector3(2.0, 0.1, 0.8), PALE_WOOD)
			for x in [2.0, 3.6]:
				k.post(Vector3(x, 0, -1.8), 0.8, 0.05, DARK_WOOD)
			for i in 10:
				k.log(Vector3(1.9 + i * 0.2, 0.9, -1.8), 0.015, 0.75, PALE_WOOD * 1.2, Vector3(0, 0, 1))
			k.box(Vector3(5.6, 1.0, -0.5), Vector3(0.1, 2.0, 1.2), DARK_WOOD)
			for i in 12:
				k.log(Vector3(5.5, 0.4 + (i % 6) * 0.25, -0.9 + (i / 6) * 0.6), 0.015, 0.8, PALE_WOOD * 1.2, Vector3(0.2, 1, 0).normalized())
			k.cylinder(Vector3(4.0, 0.8, 3.2), 0.6, 0.4, THATCH, 12, Vector3.BACK)
			info.height = 5.5
			info.size = Vector2(12, 9)
			info.chimney = Vector3(-3.5, 4.8, 1.0)
			info.door = Vector3(-2.0, 0, -1.6)
			info.work = Vector3(2.8, 0, -2.8)
		"whaler":
			# A whale's jawbones as an arch, a try-pot boiling blubber, barrels of oil, a boat.
			_house(k, Vector3(-3.5, 0, 2.0), 7.0, 5.0, 2.4, TURF)
			for s: float in [-1.0, 1.0]:
				var p := Vector3(1.8 + s * 1.4, 0, -2.5)
				k.log(p + Vector3(-s * 0.4, 1.8, 0), 0.18, 3.8, Color(0.92, 0.88, 0.78), Vector3(-s * 0.4, 1, 0).normalized())
			k.box(Vector3(4.5, 0.4, 0.8), Vector3(1.8, 0.8, 1.8), STONE)
			k.cylinder(Vector3(4.5, 0.8, 0.8), 0.75, 0.7, IRON, 12)
			k.fires.append([Vector3(4.5, 0.4, -0.15), "hearth"])
			for i in 5:
				k.barrel(Vector3(-0.5 + (i % 3) * 0.95, (i / 3) * 0.95, 3.2), 0.45, 0.95)
			var hull := [Vector3(-7.5, 0.6, -2.5), Vector3(-6.0, 0.15, -3.2), Vector3(-2.0, 0.15, -3.2), Vector3(-0.8, 0.6, -2.5), Vector3(-2.0, 0.15, -1.8), Vector3(-6.0, 0.15, -1.8)]
			for i in 6:
				var ha: Vector3 = hull[i]
				var hb: Vector3 = hull[(i + 1) % 6]
				k.quad2(ha, hb, Vector3(hb.x * 0.98, -0.25, -2.5), Vector3(ha.x * 0.98, -0.25, -2.5), WOOD)
			info.height = 5.5
			info.size = Vector2(15, 10)
			info.chimney = Vector3(4.5, 1.6, 0.8)
			info.door = Vector3(-3.5, 0, -0.6)
			info.work = Vector3(1.8, 0, -3.8)
		"sealer":
			# A turf hut, skins pegged out to dry, a rack of tusks, a skin boat.
			_house(k, Vector3(-2.0, 0, 1.0), 6.0, 4.6, 2.1, TURF)
			for i in 3:
				var c := Vector3(2.2 + i * 1.5, 0.05, -1.5 + (i % 2) * 0.8)
				k.box(c, Vector3(1.2, 0.04, 0.9), Color(0.45, 0.4, 0.36), Vector3(0, i * 0.4, 0))
			k.box(Vector3(5.0, 1.0, 1.5), Vector3(1.4, 0.08, 0.08), DARK_WOOD)
			for i in 4:
				k.cone(Vector3(4.5 + i * 0.3, 0.98, 1.5), 0.04, -0.5, Color(0.94, 0.9, 0.8), 6)
			k.box(Vector3(-5.5, 0.35, -2.4), Vector3(2.6, 0.5, 0.9), Color(0.55, 0.42, 0.3))
			info.height = 5.0
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-3.5, 4.2, 1.0)
			info.door = Vector3(-2.0, 0, -1.3)
			info.work = Vector3(3.6, 0, -2.6)
		"shipyard":
			# A longship rising on its slipway: keel and curved stem and stern posts, overlapping
			# strakes, the mast lying beside; a shed for timber, a tar pot.
			var L := 14.0
			k.box(Vector3(0, 0.2, 0), Vector3(L + 2.0, 0.4, 0.6), DARK_WOOD)
			for i in 7:
				var x := -L * 0.5 + i * L / 6.0
				k.box(Vector3(x, 0.4, 0), Vector3(0.4, 0.8, 3.6), DARK_WOOD)
			var stake := func(t: float, row: int) -> Vector3:
				var hw2 := 1.6 * sqrt(maxf(1.0 - t * t, 0.0)) * (0.55 + 0.45 * row / 5.0)
				return Vector3(t * L * 0.5, 0.9 + row * 0.32 + 0.9 * t * t, hw2)
			for side: float in [-1.0, 1.0]:
				for row in 5:
					for i in 10:
						var t0 := -1.0 + 2.0 * i / 10.0
						var t1 := -1.0 + 2.0 * (i + 1) / 10.0
						var a0: Vector3 = stake.call(t0, row)
						var a1: Vector3 = stake.call(t1, row)
						var b0: Vector3 = stake.call(t0, row + 1)
						var b1: Vector3 = stake.call(t1, row + 1)
						a0.z *= side
						a1.z *= side
						b0.z *= side
						b1.z *= side
						k.quad2(a0, a1, b1 + Vector3(0, 0.05, 0), b0 + Vector3(0, 0.05, 0), WOOD * (0.85 + 0.05 * row))
			for e: float in [-1.0, 1.0]:
				for j in 5:
					var a := float(j) / 4.0
					k.box(Vector3(e * (L * 0.5 + 0.3 + a * 0.6), 1.0 + a * 2.6, 0), Vector3(0.3, 0.7, 0.25), DARK_WOOD, Vector3(0, 0, -e * (0.2 + a * 0.5)))
			_dragon(k, Vector3(L * 0.5 + 1.0, 3.8, 0), Vector3(1, 0, 0))
			k.log(Vector3(0, 0.25, 3.5), 0.15, 10.0, PALE_WOOD, Vector3.RIGHT)
			_lean_to(k, Vector3(-5.0, 0, -4.2), 4.0, 2.6, 3.0)
			for i in 6:
				k.log(Vector3(-5.0, 0.3 + (i / 3) * 0.5, -4.6 + (i % 3) * 0.45), 0.2, 3.6, PALE_WOOD, Vector3.RIGHT)
			k.barrel(Vector3(4.0, 0, -3.5), 0.5, 0.8)
			k.fires.append([Vector3(4.0, 0.2, -4.2), "hearth"])
			info.height = 6.0
			info.size = Vector2(18, 11)
			info.door = Vector3(0, 0, -2.5)
			info.work = Vector3(0, 0, -3.0)
		"trading_post":
			# A shingled hall with a gallery, market stalls with awnings in the owner's colour,
			# a set of scales, goods stacked, a mooring post.
			_longhouse(k, Vector3(0, 0, 3.0), 13.0, 6.5, 2.8, SHINGLE, false, {"gallery": true, "boards": true})
			for i in 3:
				var c := Vector3(-4.5 + i * 4.5, 0, -4.2)
				for x in [-1.0, 1.0]:
					for z in [-0.6, 0.6]:
						k.post(c + Vector3(x, 0, z), 2.0 if z > 0 else 1.7, 0.06, DARK_WOOD)
				k.box(c + Vector3(0, 0.85, 0), Vector3(2.2, 0.1, 1.3), PALE_WOOD)
				k.quad2(c + Vector3(-1.2, 1.7, -0.8), c + Vector3(1.2, 1.7, -0.8), c + Vector3(1.2, 2.05, 0.7), c + Vector3(-1.2, 2.05, 0.7), TEAM)
				k.barrel(c + Vector3(-0.6, 0.9, 0), 0.25, 0.4)
				k.box(c + Vector3(0.5, 1.05, 0), Vector3(0.6, 0.3, 0.5), [Color(0.5, 0.36, 0.24), Color(0.94, 0.9, 0.8), Color(0.55, 0.45, 0.7)][i])
			k.post(Vector3(7.5, 0, -2.0), 1.6, 0.08, DARK_WOOD)
			k.box(Vector3(7.5, 1.6, -2.0), Vector3(1.2, 0.05, 0.05), IRON)
			for s: float in [-1.0, 1.0]:
				k.cylinder(Vector3(7.5 + s * 0.55, 1.25, -2.0), 0.2, 0.04, Color(0.8, 0.65, 0.3), 10)
			_torch_post(k, Vector3(-7.5, 0, -3.5))
			_torch_post(k, Vector3(7.5, 0, -4.5))
			info.height = 8.5
			info.size = Vector2(18, 14)
			info.chimney = Vector3(-2.0, 7.6, 3.0)
			info.door = Vector3(0, 0, -0.8)
			info.work = Vector3(0, 0, -5.4)
		"roadsign":
			# A paved stretch of road, a waymark stone and a signpost.
			for i in 7:
				for j in 3:
					k.box(Vector3(-4.2 + i * 1.4 + (j % 2) * 0.5, 0.08, -1.0 + j * 1.0), Vector3(1.25, 0.2, 0.9), STONE * (0.85 + 0.05 * ((i + j) % 3)))
			_rune_stone(k, Vector3(2.5, 0, 2.2), 0.2)
			k.post(Vector3(-2.5, 0, 2.0), 3.0, 0.1, DARK_WOOD)
			k.box(Vector3(-1.9, 2.6, 2.0), Vector3(1.3, 0.3, 0.08), PALE_WOOD, Vector3(0, 0, 0.1))
			k.box(Vector3(-3.1, 2.1, 2.0), Vector3(1.3, 0.3, 0.08), PALE_WOOD, Vector3(0, 0, -0.1))
			info.height = 4.0
			info.size = Vector2(10, 6)
			info.door = Vector3(0, 0, -2.0)
		"outpost":
			# A stockade of sharpened stakes round a hut and a watch platform, a gate in front.
			var R := 7.0
			for i in 40:
				var a := TAU * i / 40.0
				if absf(wrapf(a - PI * 1.5, -PI, PI)) < 0.22:
					continue
				var p := Vector3(cos(a) * R, 0, sin(a) * R)
				var h := 2.6 + 0.3 * float(i % 3)
				k.post(p, h, 0.16, WOOD * (0.9 + 0.05 * float(i % 3)))
				k.cone(p + Vector3(0, h, 0), 0.17, 0.4, WOOD, 5)
			for s: float in [-1.0, 1.0]:
				k.post(Vector3(s * 1.6, 0, -R), 3.6, 0.22, DARK_WOOD)
			k.box(Vector3(0, 3.5, -R), Vector3(3.6, 0.3, 0.3), DARK_WOOD)
			_house(k, Vector3(-1.5, 0, 2.5), 6.0, 4.4, 2.2, TURF)
			for x in [2.6, 5.0]:
				for z in [-3.0, -0.6]:
					k.post(Vector3(x, 0, z), 4.2, 0.12, DARK_WOOD)
			k.box(Vector3(3.8, 4.2, -1.8), Vector3(3.2, 0.2, 3.0), WOOD)
			_brazier(k, Vector3(3.8, 4.3, -1.8))
			k.post(Vector3(5.2, 4.3, -3.2), 5.0, 0.07, DARK_WOOD)
			info.flag = Vector3(5.2, 9.0, -3.2)
			_woodpile(k, Vector3(-4.0, 0, -2.0), 2.5, 0.0)
			info.height = 9.5
			info.size = Vector2(15, 15)
			info.chimney = Vector3(-3.0, 4.6, 2.5)
			info.door = Vector3(0, 0, -R)
			info.work = Vector3(0, 0, -R - 2.0)
		"ext_field":
			# Furrowed strips of ripe grain behind a wattle fence, a stook or two.
			for i in 7:
				var x := -5.0 + i * 1.65
				k.box(Vector3(x, 0.12, 0), Vector3(1.2, 0.24, 9.0), EARTH * 0.9)
				for j in 9:
					k.cone(Vector3(x + (j % 2) * 0.25 - 0.12, 0.2, -4.0 + j * 1.0), 0.45, 0.9, Color(0.86, 0.72, 0.36) * (0.92 + 0.08 * float((i + j) % 3)), 6)
			for side: float in [-1.0, 1.0]:
				_fence(k, Vector3(0, 0, side * 5.2), 11.5, 0.0)
			for i in 2:
				k.cone(Vector3(5.6, 0, -2.5 + i * 3.5), 0.6, 1.4, Color(0.82, 0.7, 0.36), 10)
			info.height = 2.5
			info.size = Vector2(13, 11)
			info.door = Vector3(0, 0, -5.5)
			info.work = Vector3(0, 0, 0)
		"ext_woodlot":
			# Stumps of felled trees, trunks waiting to be hauled, a sawbuck and a cart path.
			for i in 7:
				var a := TAU * i / 7.0
				k.cylinder(Vector3(cos(a) * 3.5, 0, sin(a) * 3.0), 0.35 + 0.08 * float(i % 3), 0.5, WOOD, 9)
				k.cylinder(Vector3(cos(a) * 3.5, 0.5, sin(a) * 3.0), 0.3, 0.02, PALE_WOOD * 1.1, 9)
			for row in 2:
				for i in 4 - row:
					k.log(Vector3(-1.0, 0.35 + row * 0.62, -1.2 + i * 0.7 + row * 0.35), 0.32, 6.0, WOOD, Vector3.RIGHT)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(2.5 + s * 0.5, 0.5, 1.5), Vector3(0.08, 1.1, 0.08), DARK_WOOD, Vector3(0, 0, s * 0.45))
			k.log(Vector3(2.5, 0.95, 1.5), 0.18, 2.6, PALE_WOOD, Vector3.BACK)
			info.height = 3.0
			info.size = Vector2(10, 9)
			info.door = Vector3(0, 0, -4.0)
			info.work = Vector3(2.0, 0, 0)
		"ext_quarry":
			# A stepped face of cut rock, blocks on a sled, a ramp of timbers.
			for i in 4:
				k.box(Vector3(0, 0.75 + i * 0.75, 2.0 + i * 0.9), Vector3(8.0 - i * 1.4, 1.5, 1.8), DARK_STONE * (0.95 + 0.05 * float(i % 2)), Vector3(0, 0.04 * i, 0))
			for i in 6:
				k.box(Vector3(-2.4 + (i % 3) * 1.2, 0.38 + (i / 3) * 0.76, -1.5), Vector3(1.05, 0.72, 0.85), STONE)
			k.box(Vector3(2.6, 0.12, -1.6), Vector3(1.4, 0.15, 2.2), WOOD)
			k.box(Vector3(2.6, 0.55, -1.6), Vector3(1.0, 0.7, 0.9), STONE)
			info.height = 4.5
			info.size = Vector2(10, 9)
			info.door = Vector3(0, 0, -4.0)
			info.work = Vector3(0, 0, -0.5)
		"ext_shaft":
			# A winding frame over a timbered shaft, a windlass, a spoil heap, an ore bucket.
			k.box(Vector3(0, 0.3, 0), Vector3(3.0, 0.6, 3.0), DARK_WOOD)
			k.box(Vector3(0, 0.62, 0), Vector3(2.0, 0.06, 2.0), Color(0.04, 0.035, 0.03))
			for x in [-1.4, 1.4]:
				for z in [-1.4, 1.4]:
					k.log(Vector3(x * 0.7, 2.4, z * 0.7), 0.13, 5.0, DARK_WOOD, Vector3(-x * 0.12, 1, -z * 0.12).normalized())
			k.box(Vector3(0, 4.7, 0), Vector3(2.4, 0.3, 0.3), DARK_WOOD)
			k.cylinder(Vector3(0, 4.9, -0.0), 0.35, 0.2, WOOD, 10, Vector3.RIGHT)
			k.log(Vector3(0, 2.7, 0), 0.015, 4.0, Color(0.55, 0.48, 0.35), Vector3.UP)
			k.barrel(Vector3(0, 1.0, 0), 0.3, 0.5)
			k.cone(Vector3(3.6, 0, 1.5), 2.0, 1.6, Color(0.42, 0.36, 0.3), 9)
			for s: float in [-1.0, 1.0]:
				k.post(Vector3(-2.6, 0, s * 0.8), 1.2, 0.08, DARK_WOOD)
			k.log(Vector3(-2.6, 1.1, 0), 0.16, 1.8, WOOD, Vector3.BACK)
			info.height = 6.0
			info.size = Vector2(10, 8)
			info.door = Vector3(0, 0, -2.0)
			info.work = Vector3(-1.6, 0, -1.4)
		"ext_jetty":
			# A plank jetty out over the water on posts, a boat moored, nets drying.
			for i in 8:
				k.box(Vector3(0, 0.55, -4.0 + i * 1.15), Vector3(2.2, 0.12, 1.05), PALE_WOOD * (0.9 + 0.05 * float(i % 3)))
			for i in 5:
				for s: float in [-1.0, 1.0]:
					k.post(Vector3(s * 1.05, -2.0, -4.0 + i * 2.1), 2.7, 0.11, DARK_WOOD)
			var hull := [Vector3(2.0, 0.6, -1.5), Vector3(2.6, 0.1, -0.5), Vector3(2.6, 0.1, 2.5), Vector3(2.0, 0.6, 3.5), Vector3(3.4, 0.1, 2.5), Vector3(3.4, 0.1, -0.5)]
			for i in 6:
				var ha: Vector3 = hull[i]
				var hb: Vector3 = hull[(i + 1) % 6]
				k.quad2(ha, hb, Vector3(3.0, -0.3, hb.z * 0.9), Vector3(3.0, -0.3, ha.z * 0.9), WOOD)
			for x in [-2.0, -2.0]:
				k.post(Vector3(x, 0, -4.5), 2.2, 0.06, DARK_WOOD)
			k.post(Vector3(-2.0, 0, -2.2), 2.2, 0.06, DARK_WOOD)
			k.quad2(Vector3(-2.0, 2.1, -4.5), Vector3(-2.0, 2.1, -2.2), Vector3(-2.05, 0.7, -2.4), Vector3(-2.05, 0.7, -4.3), Color(0.45, 0.42, 0.36))
			info.height = 3.0
			info.size = Vector2(8, 10)
			info.door = Vector3(0, 0, -5.0)
			info.work = Vector3(0, 0, 2.5)
		"ext_pasture":
			# A fenced pasture with a field shelter and a hay rack.
			for side in 4:
				var ang := PI * 0.5 * side
				_fence(k, Vector3(cos(ang), 0, sin(ang)) * 5.0, 10.0, ang + PI * 0.5)
			_lean_to(k, Vector3(2.8, 0, 2.6), 3.6, 2.6, 2.4)
			k.cone(Vector3(-2.0, 0, -1.5), 1.0, 1.6, Color(0.82, 0.7, 0.36), 10)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(-2.0 + s * 0.9, 0.7, -1.5), Vector3(0.08, 1.4, 0.08), DARK_WOOD, Vector3(0, 0, s * 0.3))
			k.box(Vector3(1.0, 0.3, -3.2), Vector3(1.8, 0.5, 0.6), WOOD)
			info.height = 3.0
			info.size = Vector2(11, 11)
			info.door = Vector3(0, 0, -5.0)
			info.work = Vector3(0, 0, 0)
		"ext_peat", "ext_clay", "ext_reeds":
			# A worked bank: dug ground, stacks drying, a barrow.
			k.box(Vector3(0, 0.03, 0), Vector3(6.0, 0.06, 4.0), Color(0.24, 0.17, 0.12) if kind != "ext_reeds" else Color(0.35, 0.4, 0.22))
			var col := Color(0.32, 0.23, 0.16) if kind == "ext_peat" else (Color(0.7, 0.45, 0.32) if kind == "ext_clay" else Color(0.74, 0.68, 0.42))
			for i in 5:
				var c := Vector3(-3.0 + i * 1.5, 0, 3.0 + (i % 2) * 0.8)
				if kind == "ext_reeds":
					for j in 6:
						var a := TAU * j / 6.0
						k.log(c + Vector3(cos(a) * 0.25, 1.0, sin(a) * 0.25), 0.07, 2.0, col, Vector3(-cos(a) * 0.15, 1, -sin(a) * 0.15).normalized())
				else:
					for lv in 3:
						k.box(c + Vector3(0, 0.15 + lv * 0.28, 0), Vector3(0.9 - lv * 0.2, 0.25, 0.5), col * (0.9 + 0.05 * lv))
			k.box(Vector3(3.2, 0.35, -1.5), Vector3(0.7, 0.3, 1.1), WOOD)
			k.cylinder(Vector3(3.2, 0.2, -2.1), 0.2, 0.08, DARK_WOOD, 10, Vector3.RIGHT)
			info.height = 2.5
			info.size = Vector2(9, 8)
			info.door = Vector3(0, 0, -4.0)
			info.work = Vector3(0, 0, 0)
	# (The footing down to the ground is built per building, to fit where it stands:
	# BuildingView.make_foundation.)
	info.mesh = k.commit()
	var fires: Array = []
	for f: Array in k.fires:
		fires.append([(f[0] as Vector3) * SCALE, f[1]])
	info.fires = fires
	# Everything about the model scales with it.
	info.height = float(info.height) * SCALE
	info.size = (info.size as Vector2) * SCALE
	for key in ["chimney", "door", "work", "flag"]:
		if info[key] != null:
			info[key] = (info[key] as Vector3) * SCALE
	_cache[kind] = info
	return info


## A horse standing, turned by `ang`: body, legs, neck and head, mane and tail.
static func _horse(k: Kit, base: Vector3, ang: float) -> void:
	var f := Vector3(cos(ang), 0, -sin(ang))
	var sd := Vector3(-f.z, 0, f.x)
	var col := Color(0.42, 0.28, 0.18)
	k.box(base + Vector3(0, 1.15, 0), Vector3(absf(f.x) * 1.5 + absf(sd.x) * 0.5, 0.55, absf(f.z) * 1.5 + absf(sd.z) * 0.5), col)
	for a: float in [-0.55, 0.55]:
		for b: float in [-0.18, 0.18]:
			k.post(base + f * a + sd * b, 0.9, 0.06, col * 0.85)
	k.log(base + f * 0.85 + Vector3(0, 1.55, 0), 0.14, 0.8, col, (f + Vector3(0, 1.1, 0)).normalized())
	k.log(base + f * 1.2 + Vector3(0, 1.85, 0), 0.11, 0.55, col, (f + Vector3(0, -0.6, 0)).normalized())
	k.log(base + f * 0.75 + Vector3(0, 1.7, 0), 0.05, 0.7, Color(0.15, 0.1, 0.08), (f + Vector3(0, 1.1, 0)).normalized())
	k.log(base - f * 0.85 + Vector3(0, 1.0, 0), 0.05, 0.6, Color(0.15, 0.1, 0.08), (-f + Vector3(0, -1.5, 0)).normalized())


## A carved pillar: a stout post with bands of the owner's colour and a capital.
static func _pillar(k: Kit, base: Vector3, h: float) -> void:
	k.box(base + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9), STONE)
	k.post(base + Vector3(0, 0.6, 0), h - 0.6, 0.26, DARK_WOOD)
	for y in [1.6, h * 0.55, h - 0.8]:
		k.box(base + Vector3(0, y, 0), Vector3(0.6, 0.22, 0.6), TEAM)
	k.box(base + Vector3(0, h + 0.1, 0), Vector3(0.75, 0.3, 0.75), DARK_WOOD)


## A long banner of the owner's cloth hanging from a cross-bar at `top`, `w` wide, `h` long.
static func _banner_cloth(k: Kit, top: Vector3, w: float, h: float) -> void:
	k.log(top, 0.05, w + 0.4, DARK_WOOD, Vector3.BACK)
	k.quad2(top + Vector3(0, -0.05, -w * 0.5), top + Vector3(0, -0.05, w * 0.5), top + Vector3(0, -h, w * 0.5), top + Vector3(0, -h, -w * 0.5), TEAM)
	k.quad2(top + Vector3(0, -h, -w * 0.5), top + Vector3(0, -h, w * 0.5), top + Vector3(0, -h - w * 0.5, 0), top + Vector3(0, -h - w * 0.5, 0), TEAM)


## A fire basket on an iron tripod, with glowing coals.
static func _brazier(k: Kit, base: Vector3) -> void:
	for a in 3:
		var ang := TAU * a / 3.0
		k.log(base + Vector3(cos(ang) * 0.25, 0.65, sin(ang) * 0.25), 0.04, 1.4, IRON, Vector3(-cos(ang) * 0.3, 1, -sin(ang) * 0.3).normalized())
	k.frustum(base + Vector3(0, 1.25, 0), 0.25, 0.55, 0.45, IRON, 10)
	k.cone(base + Vector3(0, 1.6, 0), 0.45, 0.3, Color(0.95, 0.45, 0.1), 8)
	k.fires.append([base + Vector3(0, 1.75, 0), "brazier"])


## A torch in an iron bracket on a wall at `p`, leaning out along `out`.
static func _torch(k: Kit, p: Vector3, out: Vector3) -> void:
	var o := out.normalized()
	k.box(p + o * 0.1, Vector3(0.12, 0.12, 0.12) + Vector3(absf(o.x), 0, absf(o.z)) * 0.12, IRON)
	var dir := (o * 0.45 + Vector3.UP).normalized()
	var tip := p + o * 0.2 + dir * 0.75
	k.log(p + o * 0.2 + dir * 0.35, 0.045, 0.75, DARK_WOOD, dir)
	k.cylinder(tip - dir * 0.18, 0.08, 0.2, Color(0.12, 0.08, 0.05), 8, dir)
	k.fires.append([tip + Vector3(0, 0.12, 0), "torch"])


## A torch on its own pole, stuck in the ground at `base`.
static func _torch_post(k: Kit, base: Vector3) -> void:
	k.post(base, 2.4, 0.07, DARK_WOOD)
	k.frustum(base + Vector3(0, 2.4, 0), 0.07, 0.12, 0.25, Color(0.12, 0.08, 0.05), 8)
	k.fires.append([base + Vector3(0, 2.8, 0), "torch"])


## A small window (a wind-eye) in a wall facing `n`: a frame round a dark opening that glows
## with firelight from inside at night, and an open shutter.
static func _window(k: Kit, c: Vector3, n: Vector3, w: float, h: float) -> void:
	var f := n.normalized()
	var side := Vector3(-f.z, 0, f.x)
	var p := c + f * 0.04
	k.quad(p - side * w * 0.5 - Vector3(0, h * 0.5, 0), p + side * w * 0.5 - Vector3(0, h * 0.5, 0),
		p + side * w * 0.5 + Vector3(0, h * 0.5, 0), p - side * w * 0.5 + Vector3(0, h * 0.5, 0), f, WINDOW)
	for sd: float in [-1.0, 1.0]:
		k.box(p + f * 0.03 + side * sd * (w * 0.5 + 0.05), Vector3(0.1, h + 0.2, 0.1) if absf(f.z) > 0.5 else Vector3(0.1, h + 0.2, 0.1), DARK_WOOD)
		k.box(p + f * 0.03 + Vector3(0, sd * (h * 0.5 + 0.05), 0), side.abs() * (w + 0.2) + Vector3(0, 0.1, 0) + f.abs() * 0.1, DARK_WOOD)
	# The shutter, swung open against the wall.
	k.box(p + f * 0.06 + side * (w * 0.5 + 0.1 + w * 0.5), side.abs() * w + Vector3(0, h, 0) + f.abs() * 0.05, PAINT)


## A rune stone, carved and painted in bands of the owner's colour.
static func _rune_stone(k: Kit, base: Vector3, lean: float) -> void:
	k.box(base + Vector3(0, 1.3, 0), Vector3(1.3, 2.6, 0.5), STONE, Vector3(0, 0.4, lean * 0.1))
	for i in 4:
		k.box(base + Vector3(0, 0.6 + i * 0.5, 0) + Basis.from_euler(Vector3(0, 0.4, 0)) * Vector3(0, 0, -0.27), Vector3(0.9 - 0.1 * (i % 2), 0.08, 0.03), TEAM, Vector3(0, 0.4, 0))


## A long woodpile `length` long through `c`, turned by `ang`, under a little turf top.
static func _woodpile(k: Kit, c: Vector3, length: float, ang: float) -> void:
	var dir := Vector3(cos(ang), 0, -sin(ang))
	var across := Vector3(-dir.z, 0, dir.x)
	var n := int(length / 0.5)
	for row in 4:
		for i in n:
			k.log(c + dir * (-length * 0.5 + (i + 0.5) * length / n) + Vector3(0, 0.15 + row * 0.27, 0), 0.13, 0.9, PALE_WOOD * (0.9 + 0.1 * float((i + row) % 3)), across)
	k.box(c + Vector3(0, 1.25, 0), Vector3(absf(dir.x) * length + absf(across.x) * 1.2, 0.12, absf(dir.z) * length + absf(across.z) * 1.2), TURF)


## A lean-to: a turf roof on four posts over `c`, `l` x `w`, `h` high at the back.
static func _lean_to(k: Kit, c: Vector3, l: float, w: float, h: float) -> void:
	for x in [-l * 0.5 + 0.2, l * 0.5 - 0.2]:
		k.post(c + Vector3(x, 0, -w * 0.5 + 0.2), h - 0.7, 0.12, DARK_WOOD)
		k.post(c + Vector3(x, 0, w * 0.5 - 0.2), h, 0.12, DARK_WOOD)
	var a := c + Vector3(-l * 0.5 - 0.2, h - 0.8, -w * 0.5 - 0.3)
	var b := c + Vector3(l * 0.5 + 0.2, h - 0.8, -w * 0.5 - 0.3)
	var d := c + Vector3(-l * 0.5 - 0.2, h + 0.1, w * 0.5 + 0.2)
	var e := c + Vector3(l * 0.5 + 0.2, h + 0.1, w * 0.5 + 0.2)
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0:
		n = -n
	k.roof_face(a, b, d, e, TURF)
	k.quad(a - Vector3(0, 0.15, 0), b - Vector3(0, 0.15, 0), e - Vector3(0, 0.15, 0), d - Vector3(0, 0.15, 0), -n, DARK_WOOD * 0.7)


## A trestle table with a bench either side.
static func _trestle(k: Kit, c: Vector3) -> void:
	k.box(c + Vector3(0, 0.85, 0), Vector3(3.0, 0.1, 0.9), PALE_WOOD)
	for x in [-1.2, 1.2]:
		k.box(c + Vector3(x, 0.42, 0), Vector3(0.1, 0.84, 0.7), DARK_WOOD)
	for z in [-0.85, 0.85]:
		k.box(c + Vector3(0, 0.45, z), Vector3(3.0, 0.08, 0.35), PALE_WOOD)
		for x in [-1.2, 1.2]:
			k.box(c + Vector3(x, 0.22, z), Vector3(0.1, 0.44, 0.3), DARK_WOOD)


## A carved door portal at `base` (its foot) on a wall facing -Z: posts banded in the owner's
## colour, a round arch over the door and the planked leaf with iron straps.
static func _portal(k: Kit, base: Vector3, h: float, grand: bool) -> void:
	var hw := 1.0 if grand else 0.75
	for s: float in [-1.0, 1.0]:
		# The posts carved in relief: a stack of swelling and narrowing blocks, interlace cut
		# into the face, painted bands.
		var y := 0.0
		var j := 0
		while y < h - 0.05:
			var bh := minf(0.24, h - y)
			var wide := 0.32 if j % 2 == 0 else 0.26
			k.box(base + Vector3(s * hw, y + bh * 0.5, -0.08), Vector3(wide, bh, wide), DARK_WOOD * (1.0 if j % 2 == 0 else 0.85))
			if j % 2 == 1:
				k.box(base + Vector3(s * hw, y + bh * 0.5, -0.23), Vector3(0.14, 0.14, 0.04), DARK_WOOD * 1.15, Vector3(0, 0, PI * 0.25))
			y += bh
			j += 1
		k.box(base + Vector3(s * hw, h * 0.35, -0.16), Vector3(0.34, 0.12, 0.1), TEAM)
		k.box(base + Vector3(s * hw, h * 0.75, -0.16), Vector3(0.34, 0.12, 0.1), TEAM)
	# The leaf: boards, and iron strap hinges with curled ends.
	k.boards(base + Vector3(-hw + 0.12, 0, 0.04), base + Vector3(hw - 0.12, 0, 0.04), h - 0.05, Vector3(0, 0, -1), PAINT)
	for y in [0.3, 0.72]:
		k.box(base + Vector3(-0.1, h * y, -0.06), Vector3(hw * 2.0 - 0.5, 0.07, 0.04), IRON)
		k.cylinder(base + Vector3(hw - 0.42, h * y, -0.04), 0.07, 0.05, IRON, 8, Vector3(0, 0, -1))
		k.box(base + Vector3(hw - 0.5, h * y + 0.07, -0.06), Vector3(0.05, 0.12, 0.04), IRON, Vector3(0, 0, 0.6))
	const N := 7
	for i in N:
		var a := PI * (i + 0.5) / N
		k.box(base + Vector3(cos(a) * hw, h + sin(a) * hw * 0.7, -0.1), Vector3(0.34, 0.3, 0.3), DARK_WOOD, Vector3(0, 0, a - PI * 0.5))


## A carved dragon's head and neck rising from `base`, looking out along `out`.
static func _dragon(k: Kit, base: Vector3, out: Vector3) -> void:
	var f := out.normalized()
	var p := base
	for d: Vector3 in [Vector3(0, 1, 0) + f * 0.3, Vector3(0, 1, 0) + f * 0.9, f + Vector3(0, 0.25, 0)]:
		var dn := d.normalized()
		k.log(p + dn * 0.3, 0.12, 0.65, DARK_WOOD, dn)
		p += dn * 0.55
	# Head with an open jaw, a painted crest.
	k.log(p + f * 0.25, 0.16, 0.6, DARK_WOOD, f + Vector3(0, -0.1, 0))
	k.log(p + f * 0.25 + Vector3(0, -0.2, 0), 0.07, 0.5, DARK_WOOD, f + Vector3(0, -0.4, 0))
	k.box(p + Vector3(0, 0.22, 0) - f * 0.05, Vector3(0.12, 0.25, 0.12), TEAM)


## A Viking longhouse: walls bowed outwards along the length (widest in the middle), a
## hog-backed roof whose ridge dips towards the ends, deep eaves with a fascia board, slanted
## buttress posts propping the walls, a stone footing, crossed gable boards (dragon heads on a
## hall), a smoke louver on the ridge, and a framed door with iron straps in the long side.
## opts: gallery - a covered walk on posts along both long walls (svalgang); boards - painted
## barge boards up the gables in the owner's colour.
static func _longhouse(k: Kit, c: Vector3, length: float, width: float, wall: float, roof_col: Color, carved: bool, opts := {}) -> void:
	const N := 12
	var hl := length * 0.5
	var bow := 0.14
	var sag := 0.16
	var roof_h := width * 0.78
	var over := 0.7
	# The footing: laid stones round the edge, rubble fill inside.
	k.box(c + Vector3(0, 0.1, 0), Vector3(length + 0.2, 0.5, width + 0.2), DARK_STONE)
	for sd: float in [-1.0, 1.0]:
		k.stones(c + Vector3(-hl - 0.3, -0.12, sd * (width * 0.5 + 0.12)), c + Vector3(hl + 0.3, -0.12, sd * (width * 0.5 + 0.12)), 0.62, 0.5, 2, STONE)
		k.stones(c + Vector3(sd * (hl + 0.12), -0.12, -width * 0.5), c + Vector3(sd * (hl + 0.12), -0.12, width * 0.5), 0.62, 0.5, 2, STONE)
	var hw := func(t: float) -> float: return width * 0.5 * (1.0 - bow * t * t)
	var ridge := func(t: float) -> float: return 0.4 + wall + roof_h * (1.0 - sag * t * t)
	for i in N:
		var t0 := -1.0 + 2.0 * i / N
		var t1 := -1.0 + 2.0 * (i + 1) / N
		var x0 := c.x + t0 * hl
		var x1 := c.x + t1 * hl
		for sd: float in [-1.0, 1.0]:
			var z0: float = c.z + sd * hw.call(t0)
			var z1: float = c.z + sd * hw.call(t1)
			var n := Vector3(0, 0, sd)
			# Wall: upright boards between a sill beam and a wall plate.
			k.boards(Vector3(x0, 0.4, z0), Vector3(x1, 0.4, z1), wall, n, WOOD)
			var seg := Vector3(x1 - x0, 0, z1 - z0)
			k.log(Vector3((x0 + x1) * 0.5, 0.48, (z0 + z1) * 0.5) + n * 0.1, 0.1, seg.length() + 0.05, DARK_WOOD, seg)
			k.log(Vector3((x0 + x1) * 0.5, 0.4 + wall - 0.08, (z0 + z1) * 0.5) + n * 0.1, 0.13, seg.length() + 0.05, DARK_WOOD, seg)
			# Roof: eave (overhanging, a little lower) up to the ridge.
			var e0 := Vector3(x0 - (over if i == 0 else 0.0), 0.15 + wall, z0 + sd * over)
			var e1 := Vector3(x1 + (over if i == N - 1 else 0.0), 0.15 + wall, z1 + sd * over)
			var r0 := Vector3(e0.x, ridge.call(t0), c.z)
			var r1 := Vector3(e1.x, ridge.call(t1), c.z)
			var rn := (e1 - e0).cross(r0 - e0).normalized()
			if rn.y < 0.0:
				rn = -rn
			k.roof_face(e0, e1, r0, r1, roof_col)
			# Rafter ends showing under the eave.
			if i > 0:
				k.log(Vector3(x0, 0.15 + wall - 0.4, z0 + sd * over * 0.55), 0.08, 1.0, DARK_WOOD, Vector3(0, -0.45, sd).normalized())
			k.quad(e0 + Vector3(0, -0.25, 0), e1 + Vector3(0, -0.25, 0), r1 + Vector3(0, -0.25, 0), r0 + Vector3(0, -0.25, 0), -rn, DARK_WOOD * 0.8)
			# Fascia: the roof's thick edge along the eave.
			k.quad(e0 + Vector3(0, -0.25, 0), e1 + Vector3(0, -0.25, 0), e1, e0, Vector3(0, 0, sd), DARK_WOOD)
			# Ridge cap.
			k.box((r0 + r1) * 0.5 + Vector3(0, 0.1, 0), Vector3(absf(x1 - x0) + 0.05, 0.22, 0.5), DARK_WOOD)
		# The gallery: posts out from the wall, a low rail, a roof under the main eaves.
		if opts.get("gallery", false) and i > 0 and i < N - 1:
			var gh := wall * 0.62
			for sd: float in [-1.0, 1.0]:
				var z0g: float = c.z + sd * (hw.call(t0) + over + 1.3)
				var z1g: float = c.z + sd * (hw.call(t1) + over + 1.3)
				if not (sd < 0.0 and i == N / 2):
					k.post(Vector3(x0, 0.4, z0g), gh, 0.13, DARK_WOOD)
				if not (sd < 0.0 and (i == N / 2 or i == N / 2 - 1)):
					k.box(Vector3((x0 + x1) * 0.5, 0.95, (z0g + z1g) * 0.5), Vector3(absf(x1 - x0), 0.1, 0.12), PALE_WOOD)
				var gi0 := Vector3(x0, 0.15 + wall - 0.35, c.z + sd * (hw.call(t0) + 0.3))
				var gi1 := Vector3(x1, 0.15 + wall - 0.35, c.z + sd * (hw.call(t1) + 0.3))
				var go0 := Vector3(x0, 0.4 + gh + 0.1, z0g + sd * 0.4)
				var go1 := Vector3(x1, 0.4 + gh + 0.1, z1g + sd * 0.4)
				var gn := (gi1 - gi0).cross(go0 - gi0).normalized()
				if gn.y < 0.0:
					gn = -gn
				k.roof_face(go0, go1, gi0, gi1, roof_col)
				k.quad(gi0 - Vector3(0, 0.15, 0), gi1 - Vector3(0, 0.15, 0), go1 - Vector3(0, 0.15, 0), go0 - Vector3(0, 0.15, 0), -gn, DARK_WOOD * 0.7)
	# Gable ends: planked, and crossed boards above the ridge ends.
	for sd: float in [-1.0, 1.0]:
		var x := c.x + sd * hl
		var w2: float = hw.call(1.0)
		# The gable wall: boards rising to the roof line, stout corner posts.
		var gtop: float = ridge.call(1.0) - 0.3 - 0.4
		k.boards(Vector3(x, 0.4, c.z - w2), Vector3(x, 0.4, c.z), wall, Vector3(sd, 0, 0), WOOD, gtop)
		k.boards(Vector3(x, 0.4, c.z), Vector3(x, 0.4, c.z + w2), gtop, Vector3(sd, 0, 0), WOOD, wall)
		for zs: float in [-1.0, 1.0]:
			k.post(Vector3(x, 0.4, c.z + zs * w2), wall, 0.17, DARK_WOOD)
		var top: float = ridge.call(1.0)
		var ex := x + sd * (over + 0.1)
		k.box(Vector3(ex, top + 0.45, c.z - 0.4), Vector3(0.16, 1.5, 0.16), DARK_WOOD, Vector3(0.55, 0, 0))
		k.box(Vector3(ex, top + 0.45, c.z + 0.4), Vector3(0.16, 1.5, 0.16), DARK_WOOD, Vector3(-0.55, 0, 0))
		if carved:
			# Dragons rising from the crossed boards, looking out from the gable.
			_dragon(k, Vector3(ex, top + 0.9, c.z - 0.55), Vector3(sd, 0, -0.35))
			_dragon(k, Vector3(ex, top + 0.9, c.z + 0.55), Vector3(sd, 0, 0.35))
		if opts.get("boards", false) or carved:
			# Barge boards up the gable's roof edges, painted.
			for zs: float in [-1.0, 1.0]:
				var ep := Vector3(ex - sd * 0.05, 0.15 + wall, c.z + zs * (w2 + over))
				var rp := Vector3(ex - sd * 0.05, top + 0.05, c.z)
				var dir := (rp - ep).normalized()
				k.box((ep + rp) * 0.5, Vector3(0.14, 0.32, ep.distance_to(rp) + 0.2), TEAM if opts.get("boards", false) else DARK_WOOD, Vector3(atan2(-dir.y, dir.z), 0, 0))
	# Wind-eyes along the walls and high in the gables, lit from the fire within at night.
	for sd: float in [-1.0, 1.0]:
		for t: float in [-0.55, 0.55]:
			if length < 8.0 and sd > 0.0:
				continue
			var wz: float = c.z + sd * hw.call(t)
			_window(k, Vector3(c.x + t * hl, 0.4 + wall * 0.62, wz), Vector3(0, 0, sd), 0.7, 0.5)
		var gx := c.x + sd * hl
		_window(k, Vector3(gx, 0.4 + wall + roof_h * 0.35, c.z), Vector3(sd, 0, 0), 0.45, 0.4)
	# Smoke louver on the ridge.
	var rt: float = ridge.call(0.0)
	k.box(c + Vector3(0, rt + 0.35, 0), Vector3(1.3, 0.5, 0.9), DARK_WOOD)
	k.roof(c + Vector3(0, rt + 0.6, 0), 1.6, 1.3, 0.45, roof_col)
	# The door: posts and a lintel round a planked leaf with iron straps.
	var dz: float = c.z - hw.call(0.0) - 0.06
	# Torches either side of the door.
	for sd: float in [-1.0, 1.0]:
		_torch(k, Vector3(c.x + sd * (1.7 if carved else 1.25), 0.4 + (1.5 if opts.get("gallery", false) else 2.1), dz), Vector3(0, 0, -1))
	if carved:
		_portal(k, Vector3(c.x, 0.4, dz), 2.6, true)
		k.box(Vector3(c.x, 0.4, dz - 0.5), Vector3(2.6, 0.15, 0.9), STONE)
		return
	k.box(Vector3(c.x - 0.8, 0.4 + 1.15, dz), Vector3(0.2, 2.3, 0.2), DARK_WOOD)
	k.box(Vector3(c.x + 0.8, 0.4 + 1.15, dz), Vector3(0.2, 2.3, 0.2), DARK_WOOD)
	k.box(Vector3(c.x, 0.4 + 2.35, dz - 0.02), Vector3(2.1, 0.25, 0.24), DARK_WOOD)
	k.box(Vector3(c.x, 0.4 + 1.1, dz + 0.02), Vector3(1.4, 2.2, 0.08), PAINT)
	# Shields hung by the door, in the owner's colour.
	if length >= 10.0:
		for sd: float in [-1.0, 1.0]:
			k.disc(Vector3(c.x + sd * 2.6, 0.4 + wall * 0.55, dz - 0.04), 0.45, TEAM, Vector3(0, 0, -1))
	for y in [0.6, 1.7]:
		k.box(Vector3(c.x, 0.4 + y, dz - 0.03), Vector3(1.3, 0.08, 0.04), IRON)
	k.box(Vector3(c.x, 0.4, dz - 0.5), Vector3(2.2, 0.15, 0.9), STONE)


## A small house: the same build, shorter and less bowed.
static func _house(k: Kit, c: Vector3, length: float, width: float, wall: float, roof_col: Color) -> void:
	_longhouse(k, c, length, width, wall, roof_col, false)


## A wattle fence `length` long through c, turned by `ang` (radians, about y).
static func _fence(k: Kit, c: Vector3, length: float, ang: float) -> void:
	var dir := Vector3(cos(ang), 0, -sin(ang))
	var n := int(length / 1.5) + 1
	for i in n:
		k.post(c + dir * (-length * 0.5 + i * length / (n - 1)), 1.1, 0.07, DARK_WOOD)
	for y in [0.45, 0.9]:
		k.log(c + Vector3(0, y, 0), 0.05, length, WOOD, dir)


## A scaffold of poles and ledgers around a footprint, for buildings going up.
static func scaffold(size: Vector2, height: float) -> ArrayMesh:
	var k := Kit.new()
	var hx := size.x * 0.5 + 0.8
	var hz := size.y * 0.5 + 0.8
	var nx := maxi(2, int(size.x / 3.5) + 1)
	var nz := maxi(2, int(size.y / 3.5) + 1)
	var pts: Array[Vector3] = []
	for i in nx:
		var x := -hx + 2.0 * hx * i / (nx - 1)
		pts.append(Vector3(x, 0, -hz))
		pts.append(Vector3(x, 0, hz))
	for i in range(1, nz - 1):
		var z := -hz + 2.0 * hz * i / (nz - 1)
		pts.append(Vector3(-hx, 0, z))
		pts.append(Vector3(hx, 0, z))
	for p in pts:
		k.post(p, height + 1.0, 0.07, PALE_WOOD)
	var y := 1.8
	while y < height:
		for s: float in [-1.0, 1.0]:
			k.log(Vector3(0, y, s * hz), 0.05, hx * 2.0, PALE_WOOD, Vector3.RIGHT)
			k.log(Vector3(s * hx, y, 0), 0.05, hz * 2.0, PALE_WOOD, Vector3.BACK)
		y += 2.0
	return k.commit()


## A banner on a cross-bar (the owner's colour), hanging from (0, 0, 0).
static func banner() -> ArrayMesh:
	if _cache.has("_banner"):
		return _cache["_banner"]
	var k := Kit.new()
	k.log(Vector3(0.9, 0, 0), 0.04, 2.0, DARK_WOOD, Vector3.RIGHT)
	k.quad2(Vector3(0, 0, 0), Vector3(1.8, 0, 0), Vector3(1.8, -2.4, 0), Vector3(0, -2.4, 0), TEAM)
	k.quad2(Vector3(0, -2.4, 0), Vector3(1.8, -2.4, 0), Vector3(0.9, -3.0, 0), Vector3(0.9, -3.0, 0), TEAM)
	var m := k.commit()
	_cache["_banner"] = m
	return m


## A little handcart (for mines and quarries).
static func cart() -> ArrayMesh:
	if _cache.has("_cart"):
		return _cache["_cart"]
	var k := Kit.new()
	k.box(Vector3(0, 0.75, 0), Vector3(1.2, 0.5, 0.8), WOOD)
	k.box(Vector3(0, 1.05, 0), Vector3(1.0, 0.18, 0.6), DARK_STONE)
	for s: float in [-1.0, 1.0]:
		k.cylinder(Vector3(0, 0.0, s * 0.45), 0.35, 0.1, DARK_WOOD, 10, Vector3(0, 0, 1))
	k.log(Vector3(-1.1, 0.8, 0), 0.04, 1.0, DARK_WOOD, Vector3.RIGHT)
	var m := k.commit()
	_cache["_cart"] = m
	return m


## A small rowing boat (for fishing huts).
static func boat() -> ArrayMesh:
	if _cache.has("_boat"):
		return _cache["_boat"]
	var k := Kit.new()
	var hull := [Vector3(-2.2, 0.5, 0), Vector3(-1.2, 0.0, -0.7), Vector3(1.2, 0.0, -0.7), Vector3(2.2, 0.5, 0), Vector3(1.2, 0.0, 0.7), Vector3(-1.2, 0.0, 0.7)]
	var keel := [Vector3(-1.2, -0.35, 0), Vector3(1.2, -0.35, 0)]
	for i in 6:
		var a: Vector3 = hull[i]
		var b: Vector3 = hull[(i + 1) % 6]
		var bot: Vector3 = keel[0] if a.x < 0 and b.x <= 0 else keel[1]
		k.quad2(a, b, Vector3(b.x * 0.9, -0.3, 0), Vector3(a.x * 0.9, -0.3, 0), WOOD)
		k.quad2(a + Vector3(0, 0.12, 0), b + Vector3(0, 0.12, 0), b, a, DARK_WOOD)
	k.box(Vector3(0, 0.15, 0), Vector3(0.3, 0.08, 1.3), PALE_WOOD)
	var m := k.commit()
	_cache["_boat"] = m
	return m


## A person: tunic, legs, head and a hood in the owner's colour. Built facing -Z.
static func person(tunic: Color) -> Dictionary:
	var key := "_person_%s" % tunic.to_html()
	if _cache.has(key):
		return _cache[key]
	var body := Kit.new()
	body.cylinder(Vector3(0, 0.75, 0), 0.24, 0.65, tunic, 8)
	body.cone(Vector3(0, 0.55, 0), 0.32, 0.3, tunic, 8)
	body.box(Vector3(0, 1.55, 0), Vector3(0.28, 0.3, 0.28), Color(0.85, 0.68, 0.55))
	body.cone(Vector3(0, 1.62, 0), 0.22, 0.3, TEAM, 8)
	var legs := Kit.new()
	legs.box(Vector3(-0.1, 0.38, 0), Vector3(0.13, 0.76, 0.14), Color(0.3, 0.24, 0.18))
	legs.box(Vector3(0.1, 0.38, 0), Vector3(0.13, 0.76, 0.14), Color(0.3, 0.24, 0.18))
	var arm := Kit.new()
	arm.box(Vector3(0, -0.3, 0), Vector3(0.11, 0.6, 0.11), tunic)
	arm.box(Vector3(0, -0.62, -0.25), Vector3(0.05, 0.05, 0.7), DARK_WOOD)
	arm.box(Vector3(0, -0.62, -0.62), Vector3(0.1, 0.22, 0.08), IRON)
	var out := {"body": body.commit(), "legs": legs.commit(), "arm": arm.commit()}
	_cache[key] = out
	return out


## A tiny mesh kit: vertex-coloured faces, wound to face their normals.
class Kit:
	var st := SurfaceTool.new()
	var s := 1.0   # everything is drawn this much bigger
	var fires: Array = []   # [position, kind] of everything that burns

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func commit() -> ArrayMesh:
		return st.commit()

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		var m := material_of(col)
		# Alpha says what the shader paints: 0 the owner's colour, 0.5 the household's paint
		# (brightness in rgb), 1 the colour as it is. Set here, never by scaling a colour.
		var out := Color(col.r, col.g, col.b, 1.0)
		if m == 5.0:
			out = Color(col.r, col.r, col.r, 0.0)
		elif _is_paint(col):
			out = Color(col.r, col.r, col.r, 0.5)
		for p in [a, b, c]:
			st.set_color(out)
			st.set_normal(n)
			st.set_uv(Vector2(m, 0.0))
			st.add_vertex(p * s)

	## Which surface a colour is (shaders/building.gdshader draws each its own way):
	## 0 timber (boards, beams), 1 thatch, 2 turf, 3 stone, 4 iron, 5 the owner's cloth, 6 plain,
	## 7 wooden shingles.
	static func _is_paint(col: Color) -> bool:
		return col.g < 0.01 and col.r > 0.05 and absf(col.r - col.b) < 0.01

	static func material_of(col: Color) -> float:
		if col.a < 0.25 and absf(col.r - col.g) < 0.01 and absf(col.g - col.b) < 0.01 and col.r > 0.2:
			return 5.0
		if _is_paint(col):
			return 0.0
		if col.is_equal_approx(WINDOW):
			return 9.0
		var mx := maxf(col.r, maxf(col.g, col.b))
		var mn := minf(col.r, minf(col.g, col.b))
		if mx - mn < 0.05:
			return 4.0 if mx < 0.25 else 3.0
		if col.r > col.g + 0.04 and absf(col.g - col.b) < 0.012 and col.r < 0.75:
			return 7.0
		if col.g > col.r * 1.05 and col.g > col.b:
			return 2.0
		if col.r > 0.5 and col.g > col.r * 0.78 and col.b < col.g * 0.7:
			return 1.0
		if col.r > col.g and col.g > col.b:
			return 0.0
		return 6.0

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		tri(a, b, c, n, col)
		tri(a, c, d, n, col)

	## A two-sided quad (cloth, boards): both faces.
	func quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		var n := (b - a).cross(c - a).normalized()
		if n.length() < 0.5:
			n = Vector3.UP
		quad(a, b, c, d, n, col)
		# The back face a hair behind, so the two never fight over the same depth.
		var o := -n * 0.004
		quad(a + o, b + o, c + o, d + o, -n, col)

	## A box centred at c; `tilt` rotates it (Euler, radians) about its centre.
	func box(c: Vector3, s: Vector3, col: Color, tilt := Vector3.ZERO) -> void:
		var bs := Basis.from_euler(tilt)
		var h := s * 0.5
		var faces := [
			[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)]]
		for f in faces:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var o := n * h
			var du := u * h
			var dv := v * h
			var shade := 0.82 + 0.18 * maxf(n.y, 0.0) - 0.08 * maxf(-n.y, 0.0)
			quad(c + bs * (o - du - dv), c + bs * (o + du - dv), c + bs * (o + du + dv), c + bs * (o - du + dv), bs * n, col * shade)

	## Plank walls round a box: a dark core with upright boards on all four sides and stout
	## posts at the corners.
	func planks(base: Vector3, sz: Vector3, col: Color) -> void:
		box(base + Vector3(0, sz.y * 0.5, 0), sz - Vector3(0.1, 0.0, 0.1), col * 0.4)
		var hx := sz.x * 0.5
		var hz := sz.z * 0.5
		boards(base + Vector3(-hx, 0, -hz), base + Vector3(hx, 0, -hz), sz.y, Vector3(0, 0, -1), col)
		boards(base + Vector3(-hx, 0, hz), base + Vector3(hx, 0, hz), sz.y, Vector3(0, 0, 1), col)
		boards(base + Vector3(-hx, 0, -hz), base + Vector3(-hx, 0, hz), sz.y, Vector3(-1, 0, 0), col)
		boards(base + Vector3(hx, 0, -hz), base + Vector3(hx, 0, hz), sz.y, Vector3(1, 0, 0), col)
		for x in [-hx, hx]:
			for z in [-hz, hz]:
				box(base + Vector3(x, sz.y * 0.5, z), Vector3(0.24, sz.y, 0.24), DARK_WOOD)

	## Upright boards standing side by side along a ground line a -> b (y is their foot), `h`
	## high (rising to `h_end` at b if given), facing `out`: each its own width of the run,
	## shade and slight lean, a dark gap and a backing behind them.
	func boards(a: Vector3, b: Vector3, h: float, out: Vector3, col: Color, h_end := -1.0) -> void:
		var d := b - a
		var run := Vector2(d.x, d.z).length()
		if run < 0.05:
			return
		var dir := d / run
		var o := out.normalized()
		var ang := atan2(-dir.z, dir.x)
		var he := h if h_end < 0.0 else h_end
		var back := -o * 0.03
		var back_col := DARK_WOOD * 0.6 if col.a < 0.75 else col * 0.3
		quad(a + back, b + back, b + back + Vector3(0, he, 0), a + back + Vector3(0, h, 0), o, back_col)
		var n := maxi(1, int(ceil(run / 0.3)))
		var w := run / n
		for i in n:
			var t := (i + 0.5) / n
			var bh := lerpf(h, he, t)
			if bh < 0.05:
				continue
			var p := a.lerp(b, t) + o * (0.03 + randf() * 0.025)
			box(p + Vector3(0, bh * 0.5, 0), Vector3(w - 0.035, bh + randf() * 0.05, 0.08), col * (0.82 + randf() * 0.3), Vector3(0, ang, (randf() - 0.5) * 0.015))

	## A wall of laid stones along a -> b (y is its foot), `h` high in `courses` rows, `depth`
	## thick: each stone its own length, shade and set.
	func stones(a: Vector3, b: Vector3, h: float, depth: float, courses: int, col: Color) -> void:
		var d := b - a
		var run := Vector2(d.x, d.z).length()
		if run < 0.05:
			return
		var dir := d / run
		var ang := atan2(-dir.z, dir.x)
		var ch := h / courses
		for r in courses:
			var x := -randf() * 0.4
			while x < run:
				var x0 := maxf(x, 0.0)
				var x1 := minf(x + randf_range(0.45, 0.95), run)
				if x1 - x0 > 0.08:
					var p := a + dir * ((x0 + x1) * 0.5) + Vector3(0, ch * (r + 0.5), 0)
					box(p, Vector3(x1 - x0 - 0.05, ch - 0.04 + randf() * 0.05, depth + randf() * 0.1), col * (0.75 + randf() * 0.4),
						Vector3((randf() - 0.5) * 0.06, ang + (randf() - 0.5) * 0.06, (randf() - 0.5) * 0.06))
				x = x1 + 0.03

	## A roof face from its eave (e0 -> e1) up to the ridge (r0 -> r1), built up the way it is
	## laid: thatch in thick courses, shingles in rows of single shingles, each course stepping
	## out over the one below with its butt edge showing; turf as a lumpy mat over a thick edge
	## of birch bark. Anything else is one plain face.
	func roof_face(e0: Vector3, e1: Vector3, r0: Vector3, r1: Vector3, col: Color) -> void:
		var n := (e1 - e0).cross(r0 - e0).normalized()
		if n.y < 0.0:
			n = -n
		var m := material_of(col)
		var slope := (r0 - e0).length()
		if m == 1.0 or m == 7.0:
			var thatch := m == 1.0
			var row := 0.42 if thatch else 0.3
			var lip := 0.17 if thatch else 0.05
			var rows := maxi(2, int(ceil(slope / row)))
			var cols := 1 if thatch else maxi(1, int(ceil((e1 - e0).length() / 0.3)))
			for i in rows:
				# Per course, the same everywhere along the roof, so segments meet cleanly.
				var hsh := fposmod(sin(float(i) * 12.9898 + slope) * 43758.5453, 1.0)
				var t0 := float(i) / rows
				var t1 := minf(float(i + 1) / rows + 0.4 / rows, 1.0)
				for j in cols:
					var g := 0.015 / maxf((e1 - e0).length(), 0.1) if cols > 1 else 0.0
					var u0 := float(j) / cols + g
					var u1 := float(j + 1) / cols - g
					var off := 0.0 if thatch or i % 2 == 0 else 0.5 / cols
					u0 = clampf(u0 - off, 0.0, 1.0)
					u1 = clampf(u1 - off, 0.0, 1.0)
					if u1 - u0 < 0.002:
						continue
					var lo0 := e0.lerp(r0, t0)
					var lo1 := e1.lerp(r1, t0)
					var hi0 := e0.lerp(r0, t1)
					var hi1 := e1.lerp(r1, t1)
					var a0 := lo0.lerp(lo1, u0)
					var a1 := lo0.lerp(lo1, u1)
					var b0 := hi0.lerp(hi1, u0)
					var b1 := hi0.lerp(hi1, u1)
					var l := lip * (0.8 + 0.4 * (hsh if thatch else randf()))
					var sh := col * (0.86 + 0.22 * (hsh if thatch else randf()))
					quad(a0 + n * l, a1 + n * l, b1, b0, n, sh)
					quad(a0, a1, a1 + n * l, a0 + n * l, (a0 - b0).normalized(), sh * 0.72)
		elif m == 2.0:
			var rows := maxi(2, int(ceil(slope / 0.55)))
			var cols := maxi(1, int(ceil((e1 - e0).length() / 0.55)))
			var lump := func(q: Vector3) -> float:
				return 0.2 + 0.07 * sin(q.x * 2.3 + q.z * 1.7) + 0.05 * sin(q.x * 5.1 - q.z * 3.7 + q.y * 2.0)
			for i in rows:
				for j in cols:
					var c00 := e0.lerp(r0, float(i) / rows).lerp(e1.lerp(r1, float(i) / rows), float(j) / cols)
					var c01 := e0.lerp(r0, float(i) / rows).lerp(e1.lerp(r1, float(i) / rows), float(j + 1) / cols)
					var c10 := e0.lerp(r0, float(i + 1) / rows).lerp(e1.lerp(r1, float(i + 1) / rows), float(j) / cols)
					var c11 := e0.lerp(r0, float(i + 1) / rows).lerp(e1.lerp(r1, float(i + 1) / rows), float(j + 1) / cols)
					var p00: Vector3 = c00 + n * float(lump.call(c00))
					var p01: Vector3 = c01 + n * float(lump.call(c01))
					var p10: Vector3 = c10 + n * float(lump.call(c10))
					var p11: Vector3 = c11 + n * float(lump.call(c11))
					var qn := (p01 - p00).cross(p10 - p00).normalized()
					if qn.dot(n) < 0.0:
						qn = -qn
					quad(p00, p01, p11, p10, qn, col * (0.9 + 0.15 * sin(c00.x * 3.0 + c00.z)))
			# The turf's thick edge over a layer of birch bark at the eave.
			var bark := Color(0.62, 0.55, 0.45)
			quad(e0, e1, e1 + n * float(lump.call(e1)), e0 + n * float(lump.call(e0)), (e0 - r0).normalized(), bark)
		else:
			quad(e0, e1, r1, r0, n, col)

	## A gabled roof whose eaves sit at `base` (ridge along x), `l` long, `w` wide, `h` high.
	## `along_z`: the ridge runs along z instead (for crossing roofs).
	func roof(base: Vector3, l: float, w: float, h: float, col: Color, along_z := false) -> void:
		var m := func(v: Vector3) -> Vector3: return Vector3(v.z, v.y, v.x) if along_z else v
		var hl := l * 0.5
		var hw := w * 0.5
		var r0: Vector3 = base + m.call(Vector3(-hl, h, 0))
		var r1: Vector3 = base + m.call(Vector3(hl, h, 0))
		for sd: float in [-1.0, 1.0]:
			var e0: Vector3 = base + m.call(Vector3(-hl, 0, sd * hw))
			var e1: Vector3 = base + m.call(Vector3(hl, 0, sd * hw))
			var n: Vector3 = m.call(Vector3(0, hw, sd * h).normalized())
			roof_face(e0, e1, r0, r1, col)
			# Underside, darker.
			quad(e0 + Vector3(0, -0.12, 0), e1 + Vector3(0, -0.12, 0), r1 + Vector3(0, -0.12, 0), r0 + Vector3(0, -0.12, 0), -n, DARK_WOOD * 0.6)
		# Gable ends, walled in boards.
		for sd: float in [-1.0, 1.0]:
			var x := sd * (hl - 0.5)
			tri(base + m.call(Vector3(x, 0, -hw + 0.5)), base + m.call(Vector3(x, 0, hw - 0.5)), base + m.call(Vector3(x, h - 0.4, 0)), m.call(Vector3(sd, 0, 0)), DARK_WOOD * 0.4)
			boards(base + m.call(Vector3(x, 0, -hw + 0.5)), base + m.call(Vector3(x, 0, 0)), 0.02, m.call(Vector3(sd, 0, 0)), DARK_WOOD, (h - 0.4) * 0.98)
			boards(base + m.call(Vector3(x, 0, 0)), base + m.call(Vector3(x, 0, hw - 0.5)), (h - 0.4) * 0.98, m.call(Vector3(sd, 0, 0)), DARK_WOOD, 0.02)
		# Ridge.
		var rs: Vector3 = m.call(Vector3(l, 0.25, 0.4))
		box((r0 + r1) * 0.5 + Vector3(0, 0.08, 0), rs, DARK_WOOD)

	func post(base: Vector3, h: float, r: float, col: Color) -> void:
		box(base + Vector3(0, h * 0.5, 0), Vector3(r * 2.0, h, r * 2.0), col)

	## A round log centred at c, `length` long along `dir`.
	func log(c: Vector3, r: float, length: float, col: Color, dir: Vector3) -> void:
		var f := dir.normalized()
		var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
		var u := f.cross(up).normalized()
		var v := u.cross(f).normalized()
		var p := c - f * length * 0.5
		var q := c + f * length * 0.5
		const SIDES := 7
		for i in SIDES:
			var a0 := TAU * i / SIDES
			var a1 := TAU * (i + 1) / SIDES
			var o0 := (u * cos(a0) + v * sin(a0)) * r
			var o1 := (u * cos(a1) + v * sin(a1)) * r
			var n := (u * cos((a0 + a1) * 0.5) + v * sin((a0 + a1) * 0.5)).normalized()
			quad(p + o0, q + o0, q + o1, p + o1, n, col * (0.85 + 0.15 * maxf(n.y, 0.0)))
			tri(p, p + o0, p + o1, -f, col * 1.3)
			tri(q, q + o0, q + o1, f, col * 1.3)

	## An upright cylinder with its base at c (or along `axis`).
	func cylinder(c: Vector3, r: float, h: float, col: Color, sides := 10, axis := Vector3.UP) -> void:
		var f := axis.normalized()
		var up := Vector3.RIGHT if absf(f.x) < 0.9 else Vector3.FORWARD
		var u := f.cross(up).normalized()
		var v := u.cross(f).normalized()
		var top := c + f * h
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var o0 := (u * cos(a0) + v * sin(a0)) * r
			var o1 := (u * cos(a1) + v * sin(a1)) * r
			var n := (u * cos((a0 + a1) * 0.5) + v * sin((a0 + a1) * 0.5)).normalized()
			quad(c + o0, top + o0, top + o1, c + o1, n, col * (0.85 + 0.15 * maxf(n.y, 0.0)))
			tri(top, top + o0, top + o1, f, col * 1.05)
			tri(c, c + o0, c + o1, -f, col * 0.7)

	## A tapered cylinder standing on c: radius r0 at the bottom, r1 at the top.
	func frustum(c: Vector3, r0: float, r1: float, h: float, col: Color, sides := 10) -> void:
		var top := c + Vector3(0, h, 0)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var dm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
			var n := (dm * h + Vector3(0, r0 - r1, 0)).normalized()
			quad(c + d0 * r0, c + d1 * r0, top + d1 * r1, top + d0 * r1, n, col * (0.88 + 0.12 * maxf(n.y, 0.0)))
			tri(top, top + d0 * r1, top + d1 * r1, Vector3.UP, col)
			tri(c, c + d0 * r0, c + d1 * r0, Vector3.DOWN, col * 0.8)

	## A sphere of radius r round c (a low-poly globe).
	func sphere(c: Vector3, r: float, col: Color, rings := 6, sides := 10) -> void:
		for j in rings:
			var p0 := PI * j / rings - PI * 0.5
			var p1 := PI * (j + 1) / rings - PI * 0.5
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var v := func(p: float, a: float) -> Vector3: return Vector3(cos(p) * cos(a), sin(p), cos(p) * sin(a))
				var q0: Vector3 = v.call(p0, a0)
				var q1: Vector3 = v.call(p0, a1)
				var q2: Vector3 = v.call(p1, a1)
				var q3: Vector3 = v.call(p1, a0)
				var n := (q0 + q1 + q2 + q3).normalized()
				quad(c + q0 * r, c + q1 * r, c + q2 * r, c + q3 * r, n, col * (0.9 + 0.1 * maxf(n.y, 0.0)))

	func cone(c: Vector3, r: float, h: float, col: Color, sides := 10) -> void:
		var top := c + Vector3(0, h, 0)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r
			var n := (p0 - top).cross(p1 - top).normalized()
			if n.y < 0.0:
				n = -n
			tri(p0, p1, top, n, col * (0.8 + 0.2 * n.y))

	func barrel(c: Vector3, r: float, h: float) -> void:
		cylinder(c, r, h, WOOD, 8)
		cylinder(c + Vector3(0, h * 0.2, 0), r * 1.04, 0.08, IRON, 8)
		cylinder(c + Vector3(0, h * 0.75, 0), r * 1.04, 0.08, IRON, 8)

	## A round board (a shield) facing `n`.
	func disc(c: Vector3, r: float, col: Color, n: Vector3) -> void:
		var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
		var u := n.cross(up).normalized()
		var v := u.cross(n).normalized()
		const SIDES := 12
		for i in SIDES:
			var a0 := TAU * i / SIDES
			var a1 := TAU * (i + 1) / SIDES
			tri(c, c + (u * cos(a0) + v * sin(a0)) * r, c + (u * cos(a1) + v * sin(a1)) * r, n, col)
		# A boss in the middle.
		box(c + n * 0.05, Vector3(0.18, 0.18, 0.18), IRON)
