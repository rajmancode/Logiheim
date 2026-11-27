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
##                 cart: bool, boat: bool}

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

static var _cache := {}


static func shape(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var k := Kit.new()
	var info := {"height": 6.0, "size": Vector2(8, 8), "chimney": null, "door": Vector3(0, 0, -4), "work": Vector3(0, 0, -7),
		"flag": null, "cart": false, "boat": false}
	match kind:
		"hall":
			_longhouse(k, Vector3.ZERO, 18.0, 8.5, 3.4, TURF, true)
			k.post(Vector3(-5.5, 0, -6.0), 9.0, 0.18, DARK_WOOD)
			info.flag = Vector3(-5.5, 8.6, -6.0)
			info.height = 9.0
			info.size = Vector2(18, 9)
			info.chimney = Vector3(0, 7.6, 0)
			info.door = Vector3(0, 0, -4.4)
			info.work = Vector3(2.5, 0, -7.5)
			# Shields along the wall, in the owner's colour.
			for x in [-6.0, -3.0, 3.0, 6.0]:
				k.disc(Vector3(x, 2.2, -4.32), 0.55, TEAM, Vector3(0, 0, -1))
		"longhouse":
			_longhouse(k, Vector3.ZERO, 14.0, 6.5, 2.7, TURF, false)
			info.height = 7.0
			info.size = Vector2(14, 7)
			info.chimney = Vector3(2.0, 5.8, 0)
			info.door = Vector3(0, 0, -3.4)
		"storehouse":
			# A loft store on posts, away from damp and rats.
			for x in [-2.6, 2.6]:
				for z in [-2.6, 2.6]:
					k.post(Vector3(x, 0, z), 1.4, 0.22, DARK_WOOD)
			k.box(Vector3(0, 1.45, 0), Vector3(6.4, 0.25, 6.4), DARK_WOOD)
			k.planks(Vector3(0, 1.6, 0), Vector3(6, 2.6, 6), WOOD)
			k.roof(Vector3(0, 4.2, 0), 7.0, 7.0, 3.2, THATCH)
			k.box(Vector3(0, 0.8, -3.6), Vector3(1.0, 0.12, 1.6), DARK_WOOD, Vector3(0.6, 0, 0))
			for i in 3:
				k.barrel(Vector3(-4.5 + i * 0.9, 0, -2.0), 0.4, 0.9)
			info.height = 7.5
			info.size = Vector2(7, 7)
			info.door = Vector3(0, 0, -4.0)
		"tavern":
			_longhouse(k, Vector3.ZERO, 13.0, 7.0, 2.8, THATCH, false)
			for i in 4:
				k.barrel(Vector3(-4.5 + i * 1.0, 0, -4.4), 0.45, 1.0)
			k.post(Vector3(3.0, 0, -4.6), 3.2, 0.12, DARK_WOOD)
			k.box(Vector3(3.0, 2.6, -4.65), Vector3(1.4, 0.8, 0.08), TEAM)
			info.height = 7.0
			info.size = Vector2(13, 7)
			info.chimney = Vector3(-3.0, 6.2, 0)
			info.door = Vector3(0, 0, -3.6)
		"hof":
			# A temple of stacked roofs, dragon-headed gables, on a stone base.
			k.box(Vector3(0, 0.3, 0), Vector3(10, 1.2, 10), STONE)
			k.planks(Vector3(0, 0.9, 0), Vector3(8, 3.2, 8), DARK_WOOD)
			k.roof(Vector3(0, 4.1, 0), 9.4, 9.4, 2.0, DARK_WOOD)
			k.planks(Vector3(0, 5.2, 0), Vector3(5, 2.4, 5), DARK_WOOD)
			k.roof(Vector3(0, 7.6, 0), 6.2, 6.2, 2.0, DARK_WOOD)
			k.planks(Vector3(0, 8.6, 0), Vector3(2.4, 1.8, 2.4), DARK_WOOD)
			k.roof(Vector3(0, 10.4, 0), 3.4, 3.4, 2.4, DARK_WOOD)
			for z in [-1.0, 1.0]:
				k.box(Vector3(0, 7.4, z * 3.3), Vector3(0.25, 1.2, 0.25), DARK_WOOD, Vector3(z * 0.6, 0, 0))
			k.box(Vector3(0, 2.0, -4.05), Vector3(1.6, 2.2, 0.1), TEAM)
			info.height = 13.0
			info.size = Vector2(10, 10)
			info.door = Vector3(0, 0, -5.0)
		"brewery":
			_house(k, Vector3(-1.5, 0, 0), 8.0, 6.0, 2.6, THATCH)
			k.cylinder(Vector3(4.2, 0, 0), 1.3, 1.6, DARK_WOOD, 10)
			k.cylinder(Vector3(4.2, 1.6, 0), 1.35, 0.12, IRON, 10)
			for i in 3:
				k.barrel(Vector3(3.6 + (i % 2) * 0.9, 0, -2.6 + i * 0.4), 0.45, 1.0)
			info.height = 6.5
			info.size = Vector2(11, 7)
			info.chimney = Vector3(-3.0, 5.6, 0)
			info.door = Vector3(-1.5, 0, -3.1)
			info.work = Vector3(4.2, 0, -2.5)
		"bakery":
			_house(k, Vector3(-1.5, 0, 0), 7.5, 6.0, 2.6, THATCH)
			# A domed clay oven with its own chimney.
			k.cylinder(Vector3(4.0, 0, 0.5), 1.5, 1.0, Color(0.6, 0.38, 0.25), 12)
			k.cone(Vector3(4.0, 1.0, 0.5), 1.5, 1.1, Color(0.6, 0.38, 0.25), 12)
			k.box(Vector3(4.0, 2.4, 0.8), Vector3(0.45, 1.4, 0.45), DARK_STONE)
			info.height = 6.5
			info.size = Vector2(10, 7)
			info.chimney = Vector3(4.0, 3.2, 0.8)
			info.door = Vector3(-1.5, 0, -3.1)
			info.work = Vector3(4.0, 0, -1.6)
		"smithy":
			# Open-sided forge: a roof on posts over a stone hearth, anvil in front.
			for x in [-3.2, 3.2]:
				for z in [-2.4, 2.4]:
					k.post(Vector3(x, 0, z), 3.0, 0.2, DARK_WOOD)
			k.roof(Vector3(0, 3.0, 0), 7.6, 6.0, 1.8, TURF)
			k.box(Vector3(1.6, 0.6, 1.0), Vector3(2.2, 1.2, 2.0), STONE)
			k.box(Vector3(1.6, 3.0, 1.4), Vector3(0.8, 3.4, 0.8), DARK_STONE)
			k.box(Vector3(-0.6, 0.45, -0.6), Vector3(0.5, 0.9, 0.5), DARK_WOOD)
			k.box(Vector3(-0.6, 0.98, -0.6), Vector3(0.9, 0.2, 0.35), IRON)
			info.height = 5.2
			info.size = Vector2(8, 6)
			info.chimney = Vector3(1.6, 4.8, 1.4)
			info.door = Vector3(0, 0, -2.6)
			info.work = Vector3(-0.6, 0, -1.4)
		"hut":
			_house(k, Vector3.ZERO, 6.0, 5.0, 2.2, THATCH)
			for i in 2:
				k.barrel(Vector3(3.6, 0, -1.4 + i * 1.0), 0.4, 0.9)
			info.height = 5.0
			info.size = Vector2(7, 5)
			info.chimney = Vector3(-1.5, 4.2, 0)
			info.door = Vector3(0, 0, -2.6)
		"woodcutter":
			_house(k, Vector3(-2.0, 0, 0.5), 6.0, 5.0, 2.2, TURF)
			# Log pile and a chopping block.
			for row in 3:
				for i in 4 - row:
					k.log(Vector3(3.2, 0.35 + row * 0.6, -1.2 + i * 0.65 + row * 0.32), 0.3, 3.0, PALE_WOOD, Vector3.RIGHT)
			k.cylinder(Vector3(1.2, 0, -3.0), 0.45, 0.6, WOOD, 8)
			info.height = 5.0
			info.size = Vector2(8, 6)
			info.chimney = Vector3(-3.5, 4.2, 0.5)
			info.door = Vector3(-2.0, 0, -2.1)
			info.work = Vector3(1.2, 0, -4.0)
		"quarry":
			# A lean-to, cut blocks and a lifting tripod.
			k.post(Vector3(-3.5, 0, 1.5), 2.6, 0.18, DARK_WOOD)
			k.post(Vector3(-0.5, 0, 1.5), 2.6, 0.18, DARK_WOOD)
			k.box(Vector3(-2.0, 2.2, 0.8), Vector3(3.6, 0.15, 2.4), TURF, Vector3(-0.35, 0, 0))
			for i in 6:
				k.box(Vector3(1.5 + (i % 3) * 1.1, 0.4 + (i / 3) * 0.8, -1.0 + (i % 2) * 0.3), Vector3(1.0, 0.75, 0.8), STONE)
			for a in 3:
				var ang := TAU * a / 3.0
				k.log(Vector3(2.5 + cos(ang) * 0.9, 2.0, 2.0 + sin(ang) * 0.9), 0.08, 4.2, DARK_WOOD, Vector3(-cos(ang) * 0.3, 1, -sin(ang) * 0.3).normalized())
			info.height = 4.5
			info.size = Vector2(8, 6)
			info.work = Vector3(2.5, 0, -2.5)
			info.cart = true
		"mine":
			# A timbered adit into a mound of rock, a spoil heap, a hut.
			k.cone(Vector3(0, 0, 2.5), 5.0, 4.0, DARK_STONE, 10)
			k.box(Vector3(0, 0.1, -0.8), Vector3(2.6, 2.4, 1.2), Color(0.04, 0.035, 0.03))
			k.post(Vector3(-1.4, 0, -1.4), 2.6, 0.2, DARK_WOOD)
			k.post(Vector3(1.4, 0, -1.4), 2.6, 0.2, DARK_WOOD)
			k.box(Vector3(0, 2.6, -1.4), Vector3(3.4, 0.35, 0.4), DARK_WOOD)
			k.cone(Vector3(4.6, 0, -1.5), 1.8, 1.4, Color(0.4, 0.36, 0.32), 8)
			_house(k, Vector3(-5.0, 0, -0.5), 4.5, 4.0, 2.0, TURF)
			info.height = 5.0
			info.size = Vector2(12, 8)
			info.door = Vector3(0, 0, -2.0)
			info.work = Vector3(0, 0, -3.5)
			info.cart = true
		"fishing_hut":
			_house(k, Vector3(-2.0, 0, 0.5), 6.0, 4.6, 2.2, THATCH)
			# Drying racks hung with fish.
			for r in 2:
				var z := -1.6 + r * 1.4
				k.post(Vector3(1.6, 0, z), 2.0, 0.08, DARK_WOOD)
				k.post(Vector3(4.6, 0, z), 2.0, 0.08, DARK_WOOD)
				k.log(Vector3(3.1, 1.9, z), 0.05, 3.2, DARK_WOOD, Vector3.RIGHT)
				for f in 5:
					k.box(Vector3(2.0 + f * 0.55, 1.55, z), Vector3(0.18, 0.6, 0.05), Color(0.6, 0.62, 0.58))
			info.height = 4.8
			info.size = Vector2(8, 5)
			info.chimney = Vector3(-3.5, 4.2, 0.5)
			info.door = Vector3(-2.0, 0, -1.9)
			info.work = Vector3(3.0, 0, -3.0)
			info.boat = true
		"farm":
			_longhouse(k, Vector3(-1.5, 0, 1.0), 10.0, 5.5, 2.4, THATCH, false)
			k.cone(Vector3(5.5, 0, -1.5), 1.5, 2.6, Color(0.82, 0.7, 0.36), 10)
			_fence(k, Vector3(1.0, 0, -4.5), 9.0, 0.0)
			info.height = 6.0
			info.size = Vector2(12, 8)
			info.chimney = Vector3(-3.0, 5.0, 1.0)
			info.door = Vector3(-1.5, 0, -1.8)
			info.work = Vector3(2.0, 0, -7.0)
		"fold":
			_house(k, Vector3(-3.0, 0, 1.5), 4.5, 4.0, 2.0, TURF)
			for side in 4:
				var ang := PI * 0.5 * side
				_fence(k, Vector3(1.5, 0, -0.5) + Vector3(cos(ang), 0, sin(ang)) * 3.5, 7.0, ang + PI * 0.5)
			k.cone(Vector3(1.5, 0, -0.5), 0.9, 1.4, Color(0.82, 0.7, 0.36), 8)
			info.height = 4.0
			info.size = Vector2(10, 8)
			info.work = Vector3(1.5, 0, -0.5)
		"kiln":
			k.cone(Vector3(1.5, 0, 0), 2.6, 2.2, EARTH, 10)
			k.cylinder(Vector3(1.5, 2.0, 0), 0.5, 0.6, DARK_STONE, 8)
			_house(k, Vector3(-3.0, 0, 0.5), 4.5, 4.0, 2.0, TURF)
			for i in 3:
				k.log(Vector3(1.5, 0.3 + i * 0.55, -3.2), 0.25, 2.6, PALE_WOOD, Vector3.RIGHT)
			info.height = 4.0
			info.size = Vector2(9, 6)
			info.chimney = Vector3(1.5, 2.8, 0)
			info.work = Vector3(1.5, 0, -2.4)
		"tower":
			# Four tall posts, braced, a railed platform and a little roof; a flag on top.
			var h := 9.0
			for x in [-1.6, 1.6]:
				for z in [-1.6, 1.6]:
					k.post(Vector3(x, 0, z), h + 1.2, 0.22, DARK_WOOD)
			for y in [2.5, 5.5]:
				k.box(Vector3(0, y, -1.6), Vector3(3.4, 0.15, 0.15), DARK_WOOD)
				k.box(Vector3(0, y, 1.6), Vector3(3.4, 0.15, 0.15), DARK_WOOD)
				k.box(Vector3(-1.6, y, 0), Vector3(0.15, 0.15, 3.4), DARK_WOOD)
				k.box(Vector3(1.6, y, 0), Vector3(0.15, 0.15, 3.4), DARK_WOOD)
			k.box(Vector3(0, h, 0), Vector3(4.4, 0.25, 4.4), WOOD)
			for s in 4:
				var ang := PI * 0.5 * s
				var o := Vector3(cos(ang), 0, sin(ang)) * 2.15
				k.box(Vector3(o.x, h + 0.55, o.z), Vector3(0.1 + absf(sin(ang)) * 4.2, 0.9, 0.1 + absf(cos(ang)) * 4.2), PALE_WOOD)
			k.roof(Vector3(0, h + 2.2, 0), 4.6, 4.6, 1.6, THATCH)
			k.post(Vector3(0, h + 3.4, 0), 2.0, 0.07, DARK_WOOD)
			k.box(Vector3(0, h * 0.5, -1.8), Vector3(0.5, h, 0.08), DARK_WOOD)
			info.flag = Vector3(0, h + 5.2, 0)
			info.height = h + 5.5
			info.size = Vector2(5, 5)
			info.door = Vector3(0, 0, -2.0)
			info.work = Vector3(0, h + 0.2, 0)
		"barracks":
			_longhouse(k, Vector3(0, 0, 1.5), 15.0, 7.0, 2.8, TURF, false)
			# A weapon rack and training posts.
			for i in 5:
				k.log(Vector3(-4.0 + i * 0.4, 1.0, -4.0), 0.04, 2.0, DARK_WOOD, Vector3(0, 1, 0.25).normalized())
			k.box(Vector3(-3.2, 1.6, -4.1), Vector3(2.4, 0.1, 0.1), DARK_WOOD)
			for i in 3:
				k.post(Vector3(2.0 + i * 1.8, 0, -5.5), 1.7, 0.15, PALE_WOOD)
				k.box(Vector3(2.0 + i * 1.8, 1.3, -5.5), Vector3(0.9, 0.12, 0.12), PALE_WOOD)
			for x in [-6.0, -1.5, 3.0]:
				k.disc(Vector3(x, 2.0, -2.03), 0.55, TEAM, Vector3(0, 0, -1))
			info.height = 7.5
			info.size = Vector2(15, 10)
			info.chimney = Vector3(3.0, 6.4, 1.5)
			info.door = Vector3(0, 0, -2.1)
			info.work = Vector3(3.8, 0, -6.5)
	# Every building stands on a plinth reaching down into the slope.
	var sz: Vector2 = info.size
	k.box(Vector3(0, -1.6, 0), Vector3(sz.x + 0.6, 3.4, sz.y + 0.6), Color(0.38, 0.35, 0.3))
	info.mesh = k.commit()
	_cache[kind] = info
	return info


## A longhouse: stone footing, plank walls bowed slightly, a steep roof (turf or thatch) with
## crossed gable boards at each end, door in the long side.
static func _longhouse(k: Kit, c: Vector3, length: float, width: float, wall: float, roof_col: Color, carved: bool) -> void:
	k.box(c + Vector3(0, 0.15, 0), Vector3(length + 0.4, 0.5, width + 0.4), STONE)
	k.planks(c + Vector3(0, 0.4, 0), Vector3(length, wall, width), WOOD)
	k.roof(c + Vector3(0, 0.4 + wall, 0), length + 1.0, width + 1.6, width * 0.75, roof_col)
	var top := 0.4 + wall + width * 0.75
	for s: float in [-1.0, 1.0]:
		var e := c + Vector3(s * (length * 0.5 + 0.5), 0, 0)
		# Crossed gable boards (dragon heads on a hall).
		k.box(e + Vector3(0, top + 0.5, -0.45), Vector3(0.18, 1.6, 0.18), DARK_WOOD, Vector3(0.5, 0, 0))
		k.box(e + Vector3(0, top + 0.5, 0.45), Vector3(0.18, 1.6, 0.18), DARK_WOOD, Vector3(-0.5, 0, 0))
		if carved:
			k.box(e + Vector3(0, top + 1.3, -0.9), Vector3(0.3, 0.3, 0.7), DARK_WOOD)
	k.box(c + Vector3(0, 1.4, -width * 0.5 - 0.06), Vector3(1.4, 2.2, 0.1), DARK_WOOD)
	k.box(c + Vector3(0, 2.7, -width * 0.5 - 0.12), Vector3(2.0, 0.2, 0.2), DARK_WOOD)


## A small house: plank walls on a stone footing and a steep roof, door in the front.
static func _house(k: Kit, c: Vector3, length: float, width: float, wall: float, roof_col: Color) -> void:
	k.box(c + Vector3(0, 0.12, 0), Vector3(length + 0.3, 0.4, width + 0.3), STONE)
	k.planks(c + Vector3(0, 0.3, 0), Vector3(length, wall, width), WOOD)
	k.roof(c + Vector3(0, 0.3 + wall, 0), length + 0.8, width + 1.2, width * 0.7, roof_col)
	k.box(c + Vector3(0, 1.2, -width * 0.5 - 0.06), Vector3(1.1, 1.9, 0.1), DARK_WOOD)


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

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func commit() -> ArrayMesh:
		return st.commit()

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		for p in [a, b, c]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		tri(a, b, c, n, col)
		tri(a, c, d, n, col)

	## A two-sided quad (cloth, boards): both faces.
	func quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		var n := (b - a).cross(c - a).normalized()
		if n.length() < 0.5:
			n = Vector3.UP
		quad(a, b, c, d, n, col)
		quad(a, b, c, d, -n, col)

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

	## Plank walls: a box whose sides are striped in boards of slightly different shades.
	func planks(base: Vector3, s: Vector3, col: Color) -> void:
		var boards := maxi(2, int(maxf(s.x, s.z) / 0.35))
		box(base + Vector3(0, s.y * 0.5, 0), s, col)
		# Board seams: thin dark strips proud of the wall on the long sides.
		var n := int(s.x / 0.5)
		for i in n:
			var x := -s.x * 0.5 + (i + 0.5) * s.x / n
			for zs: float in [-1.0, 1.0]:
				box(base + Vector3(x, s.y * 0.5, zs * (s.z * 0.5 + 0.015)), Vector3(0.05, s.y, 0.03), col * (0.7 + 0.1 * float(i % 3)))
		boards = boards

	## A gabled roof whose eaves sit at `base` (ridge along x), `l` long, `w` wide, `h` high.
	func roof(base: Vector3, l: float, w: float, h: float, col: Color) -> void:
		var hl := l * 0.5
		var hw := w * 0.5
		var r0 := base + Vector3(-hl, h, 0)
		var r1 := base + Vector3(hl, h, 0)
		for s: float in [-1.0, 1.0]:
			var e0 := base + Vector3(-hl, 0, s * hw)
			var e1 := base + Vector3(hl, 0, s * hw)
			var n := Vector3(0, hw, s * h).normalized()
			quad(e0, e1, r1, r0, n, col)
			# Underside, darker.
			quad(e0 + Vector3(0, -0.12, 0), e1 + Vector3(0, -0.12, 0), r1 + Vector3(0, -0.12, 0), r0 + Vector3(0, -0.12, 0), -n, col * 0.5)
		# Gable ends, walled in planks.
		for s: float in [-1.0, 1.0]:
			var x := s * (hl - 0.5)
			tri(base + Vector3(x, 0, -hw + 0.5), base + Vector3(x, 0, hw - 0.5), base + Vector3(x, h - 0.4, 0), Vector3(s, 0, 0), DARK_WOOD)
		# Ridge.
		box((r0 + r1) * 0.5 + Vector3(0, 0.08, 0), Vector3(l, 0.25, 0.4), col * 0.85)

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
