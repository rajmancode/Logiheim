class_name HexCoords
extends RefCounted
## Pointy-top hex math using axial coordinates (q, r).
##
## World mapping (x, z plane): x = size * sqrt(3) * (q + r / 2), z = size * 1.5 * r.
## `size` is the circumradius (centre to corner). Rows use "odd-r" offset layout.
## Reference: https://www.redblobgames.com/grids/hexagons/

const SQRT3 := 1.7320508075688772

## Neighbour direction for edge k, where edge k joins corner k and corner k + 1.
const DIRECTIONS = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]


static func axial_to_world(a: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (a.x + a.y * 0.5), size * 1.5 * a.y)


static func world_to_axial(p: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return cube_round(q, r)


static func cube_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## Corner k offset from the hex centre (x, z). Corner 0 is at -30 degrees.
static func corner(k: int, size: float) -> Vector2:
	var angle := deg_to_rad(60.0 * k - 30.0)
	return Vector2(cos(angle), sin(angle)) * size


static func corners(size: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in 6:
		out.append(corner(k, size))
	return out


static func offset_to_axial(o: Vector2i) -> Vector2i:
	return Vector2i(o.x - (o.y - (o.y & 1)) / 2, o.y)


static func axial_to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + (a.y - (a.y & 1)) / 2, a.y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


static func neighbor(a: Vector2i, k: int) -> Vector2i:
	var d: Vector2i = DIRECTIONS[k]
	return a + d


## True if point p (relative to a hex centre) lies inside a pointy-top hex of the given size.
static func contains(p: Vector2, size: float) -> bool:
	var d := p.abs()
	return maxf(d.x, 0.5 * d.x + 0.8660254 * d.y) <= 0.8660254 * size
