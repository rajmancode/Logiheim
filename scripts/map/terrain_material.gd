class_name TerrainMaterial
extends RefCounted
## Builds the hex terrain ShaderMaterial: texture arrays (one layer per terrain type),
## per-terrain tint/roughness and an animated water normal map.

const SHADER_PATH := "res://shaders/hex_terrain.gdshader"
const TEXTURE_DIR := "res://assets/textures/terrain"
const LAYER_SIZE := 512

## Texture used for each HexMapGenerator.Terrain layer (water layers show the seabed at map edges).
const LAYER_TEXTURES := ["sand", "sand", "sand", "grass", "forest_floor", "rock", "snow", "dirt"]
## Used as a flat colour when a layer's texture file is missing.
const FALLBACK_COLORS := [
	Color(0.10, 0.25, 0.40), Color(0.15, 0.40, 0.45), Color(0.80, 0.72, 0.52), Color(0.32, 0.48, 0.20),
	Color(0.20, 0.32, 0.15), Color(0.48, 0.46, 0.43), Color(0.92, 0.94, 0.97), Color(0.40, 0.29, 0.19),
]
## Per-layer tint applied on top of the texture (sRGB). Forest is darkened so it reads apart from grass.
const LAYER_TINTS := [
	Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE,
	Color(0.85, 0.9, 0.8), Color.WHITE, Color.WHITE, Color.WHITE,
]
const ROUGHNESS := [0.06, 0.06, 0.92, 0.88, 0.9, 0.8, 0.55, 0.93]


static func create() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)

	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	var tints := PackedColorArray()
	for i in LAYER_TEXTURES.size():
		var layer_name: String = LAYER_TEXTURES[i]
		var albedo := _load_layer("%s/%s_albedo.jpg" % [TEXTURE_DIR, layer_name])
		var tint: Color = LAYER_TINTS[i]
		if albedo == null:
			albedo = _solid(Color.WHITE)
			tint = FALLBACK_COLORS[i]
		var normal := _load_layer("%s/%s_normal.png" % [TEXTURE_DIR, layer_name])
		if normal == null:
			normal = _solid(Color(0.5, 0.5, 1.0))
		albedo_images.append(albedo)
		normal_images.append(normal)
		tints.append(tint.srgb_to_linear())

	var albedo_array := Texture2DArray.new()
	albedo_array.create_from_images(albedo_images)
	var normal_array := Texture2DArray.new()
	normal_array.create_from_images(normal_images)

	var water_noise := FastNoiseLite.new()
	water_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	water_noise.frequency = 0.02
	water_noise.fractal_octaves = 4
	var water_normal := NoiseTexture2D.new()
	water_normal.width = 512
	water_normal.height = 512
	water_normal.seamless = true
	water_normal.as_normal_map = true
	water_normal.bump_strength = 6.0
	water_normal.generate_mipmaps = true
	water_normal.noise = water_noise

	mat.set_shader_parameter("albedo_array", albedo_array)
	mat.set_shader_parameter("normal_array", normal_array)
	mat.set_shader_parameter("terrain_tint", tints)
	mat.set_shader_parameter("terrain_roughness", PackedFloat32Array(ROUGHNESS))
	mat.set_shader_parameter("water_normal", water_normal)
	return mat


static func _load_layer(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != LAYER_SIZE or img.get_height() != LAYER_SIZE:
		img.resize(LAYER_SIZE, LAYER_SIZE, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


static func _solid(color: Color) -> Image:
	var img := Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.generate_mipmaps()
	return img
