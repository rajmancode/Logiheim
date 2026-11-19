class_name BorderNoise
extends RefCounted
## Wobbles hex outlines so the map doesn't look like perfect hexagons.
##
## The displacement is a 2D noise field that depends only on world position, and corner
## points are snapped before sampling. Two hexes that share an edge therefore compute exactly
## the same outline, so tops and cliff walls still meet without gaps or overlaps.

## Maximum displacement in metres.
var amplitude := 0.0
## Points per hex edge (more = smoother wobble).
var segments := 1

var _nx := FastNoiseLite.new()
var _ny := FastNoiseLite.new()


func _init(hex_size: float, strength: float, p_segments: int) -> void:
	amplitude = maxf(0.0, hex_size * strength)
	segments = maxi(1, p_segments)
	var seed_value := 1337
	for n: FastNoiseLite in [_nx, _ny]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.3 / hex_size
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		n.seed = seed_value
		seed_value += 4242


func displace(p: Vector2) -> Vector2:
	if amplitude <= 0.0:
		return p
	return p + Vector2(_nx.get_noise_2dv(p), _ny.get_noise_2dv(p)) * amplitude


## Displaced outline of edge k of the hex at `center` (corner k to corner k + 1), as
## segments + 1 world points. Neighbours get the same points in reverse order.
func hex_edge(center: Vector2, size: float, k: int) -> PackedVector2Array:
	var a := _corner(center, size, k)
	var b := _corner(center, size, (k + 1) % 6)
	var flip := b.x < a.x or (b.x == a.x and b.y < a.y)
	var p0 := b if flip else a
	var p1 := a if flip else b
	var out := PackedVector2Array()
	for s in segments + 1:
		out.append(displace(p0.lerp(p1, float(s) / segments)))
	if flip:
		out.reverse()
	return out


## Displaced midpoint of edge k (where a river crosses into the neighbour).
func edge_mid(center: Vector2, size: float, k: int) -> Vector2:
	var a := _corner(center, size, k)
	var b := _corner(center, size, (k + 1) % 6)
	return displace((a + b) * 0.5)


static func _corner(center: Vector2, size: float, k: int) -> Vector2:
	return (center + HexCoords.corner(k, size)).snapped(Vector2(0.001, 0.001))
