class_name MapSeed
extends RefCounted
## The map seed. Everything procedural (lakes, fjords, volcano, rivers' meanders, wetlands,
## resources, trails, caves, vegetation, props, animals) draws its randomness from here, so the
## same seed always builds the same world and a new seed builds a different one from the same
## Gaea terrain. Set from HexMapSettings.seed at the start of every build.

static var value := 1


static func set_seed(s: int) -> void:
	value = s
	# Offsets the procedural noise (not the hex-border noise, which the GPU mirrors exactly).
	var r := RandomNumberGenerator.new()
	r.seed = hash(s)
	BorderNoise.seed_offset = Vector2(r.randf_range(-5000.0, 5000.0), r.randf_range(-5000.0, 5000.0))


## A seed for one use: mixes the map seed with a salt (any int, e.g. a fixed number per system
## or a hash of a position).
static func mix(salt: int) -> int:
	return hash(Vector2i(value, salt))
