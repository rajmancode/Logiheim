class_name BorderNoise
extends RefCounted
## Makes hex borders irregular. Instead of moving outline points, every lookup point is
## nudged by a smooth 2D offset field before finding its hex: cell(p) = hex_at(p + offset(p)).
##
## The same field is computed in shaders/include/hex_grid.gdshaderinc (integer-hash value
## noise, identical maths), so grid lines and highlights drawn on the GPU match picking and
## placement done here on the CPU.

const MASK := 0xFFFFFFFF

## Maximum offset in metres.
var amplitude := 0.0
## Noise frequency, 1/metres.
var frequency := 0.05


## Offset for procedural noise (set from the map seed). The hex-border noise itself doesn't use
## it, because the terrain shader mirrors that noise exactly.
static var seed_offset := Vector2.ZERO


## Value noise shifted by the map seed: for everything procedural (coasts, meanders, lakes...).
static func snoise(p: Vector2) -> float:
	return value_noise(p + seed_offset)


func _init(hex_size: float, strength: float) -> void:
	amplitude = maxf(0.0, hex_size * strength)
	frequency = 1.0 / (0.9 * hex_size)


func offset(p: Vector2) -> Vector2:
	if amplitude <= 0.0:
		return Vector2.ZERO
	var q := p * frequency
	var o := Vector2(value_noise(q + Vector2(13.7, 4.1)), value_noise(q + Vector2(-7.3, 21.9)))
	var q2 := q * 2.3
	o += Vector2(value_noise(q2 + Vector2(3.1, -9.4)), value_noise(q2 + Vector2(17.2, 5.6))) * 0.35
	return (o / 1.35 * 2.0 - Vector2.ONE) * amplitude


## Index of the cell whose (irregular) area contains world point p, or -1.
func cell_at(level: HexLevel, p: Vector2) -> int:
	return level.cell_at(p + offset(p))


## Same as env_noise() in the shaders: smooth value noise on an integer lattice, 0..1.
static func value_noise(p: Vector2) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := lattice_hash(ix, iy)
	var b := lattice_hash(ix + 1, iy)
	var c := lattice_hash(ix, iy + 1)
	var d := lattice_hash(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


## 32-bit integer hash, bit-for-bit the same as env_hash() in environment.gdshaderinc.
static func lattice_hash(ix: int, iy: int) -> float:
	var h := _mul(ix & MASK, 1597334677) ^ _mul(iy & MASK, 3812015801)
	h ^= h >> 16
	h = _mul(h, 2146121005)
	h ^= h >> 15
	h = _mul(h, 2221713035)
	h ^= h >> 16
	return float(h) / 4294967295.0


## (a * b) mod 2^32 without overflowing 64-bit ints.
static func _mul(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK
