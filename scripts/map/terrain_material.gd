class_name TerrainMaterial
extends RefCounted
## Builds the terrain ShaderMaterial: PBR texture arrays (one layer per terrain type) plus
## per-layer scale and tint. for_level() makes a copy carrying one level's grid settings.
##
## Layer textures live in assets/textures/terrain/ (see tools/pack_ambientcg.py):
##   <name>_albedo.png  RGB colour, A height      <name>_normal.png  RG normal, B AO, A roughness

const SHADER_PATH := "res://shaders/hex_terrain.gdshader"
const TEXTURE_DIR := "res://assets/textures/terrain"
const LAYER_SIZE := 1024

## Texture used for each HexMapGenerator.Terrain layer (the two water layers are the sea floor).
const LAYER_TEXTURES := ["sand", "sand", "sand", "grass", "forest_floor", "rock", "snow", "dirt"]
## Metres covered by one repeat of each layer's texture.
const LAYER_METRES := [7.0, 6.0, 5.0, 4.0, 4.5, 9.0, 7.0, 3.5]
## Tint per layer (sRGB). The sea floor is darker and greener; forest floor a touch darker.
const LAYER_TINTS := [
	Color(0.5, 0.56, 0.5), Color(0.78, 0.8, 0.74), Color.WHITE, Color(0.95, 0.97, 0.9),
	Color(0.82, 0.88, 0.78), Color.WHITE, Color.WHITE, Color(0.9, 0.86, 0.82),
]
## Used as a flat colour when a layer's texture file is missing.
const FALLBACK_COLORS := [
	Color(0.55, 0.5, 0.4), Color(0.7, 0.65, 0.5), Color(0.80, 0.72, 0.52), Color(0.32, 0.48, 0.20),
	Color(0.20, 0.32, 0.15), Color(0.48, 0.46, 0.43), Color(0.92, 0.94, 0.97), Color(0.40, 0.29, 0.19),
]

static var _albedo_array: Texture2DArray
static var _normal_array: Texture2DArray
static var _missing: Array[bool] = []


static func create() -> ShaderMaterial:
	_ensure_arrays()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var tints := PackedColorArray()
	for i in LAYER_TEXTURES.size():
		var tint: Color = FALLBACK_COLORS[i] if _missing[i] else LAYER_TINTS[i]
		tints.append(tint.srgb_to_linear())
	mat.set_shader_parameter("albedo_array", _albedo_array)
	mat.set_shader_parameter("normal_array", _normal_array)
	mat.set_shader_parameter("layer_tint", tints)
	mat.set_shader_parameter("layer_size", PackedFloat32Array(LAYER_METRES))
	mat.set_shader_parameter("flood_ripples", _ripples())
	return mat


static var _ripple_tex: NoiseTexture2D


static func _ripples() -> NoiseTexture2D:
	if _ripple_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		_ripple_tex = NoiseTexture2D.new()
		_ripple_tex.width = 256
		_ripple_tex.height = 256
		_ripple_tex.seamless = true
		_ripple_tex.as_normal_map = true
		_ripple_tex.bump_strength = 6.0
		_ripple_tex.generate_mipmaps = true
		_ripple_tex.noise = noise
	return _ripple_tex


## A material for one level: hex grid parameters and sea level. Built fresh rather than
## duplicated from `base`, because duplicating drops the vec4 array (layer_tint).
static func for_level(_base: ShaderMaterial, level: HexLevel, noise: BorderNoise, sea_y: float) -> ShaderMaterial:
	var mat := create()
	set_grid(mat, level, noise)
	mat.set_shader_parameter("sea_level", sea_y)
	return mat


## Points any material using hex_grid.gdshaderinc at a level's grid.
static func set_grid(mat: ShaderMaterial, level: HexLevel, noise: BorderNoise) -> void:
	mat.set_shader_parameter("grid_hex_size", level.hex_size)
	mat.set_shader_parameter("grid_origin", level.origin)
	mat.set_shader_parameter("grid_noise_amp", noise.amplitude)
	mat.set_shader_parameter("grid_noise_freq", noise.frequency)
	mat.set_shader_parameter("hover_cell", Vector3.ZERO)
	mat.set_shader_parameter("select_cell", Vector3.ZERO)


## The arrays are shared by every level's material and by the rock shader.
static func albedo_array() -> Texture2DArray:
	_ensure_arrays()
	return _albedo_array


static func normal_array() -> Texture2DArray:
	_ensure_arrays()
	return _normal_array


static func _ensure_arrays() -> void:
	if _albedo_array != null:
		return
	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	_missing.clear()
	for i in LAYER_TEXTURES.size():
		var layer_name: String = LAYER_TEXTURES[i]
		var albedo := _load_layer("%s/%s_albedo.png" % [TEXTURE_DIR, layer_name])
		_missing.append(albedo == null)
		if albedo == null:
			albedo = _solid(Color(1.0, 1.0, 1.0, 0.5))
		var normal := _load_layer("%s/%s_normal.png" % [TEXTURE_DIR, layer_name])
		if normal == null:
			normal = _solid(Color(0.5, 0.5, 1.0, 0.85))
		albedo_images.append(albedo)
		normal_images.append(normal)
	_albedo_array = Texture2DArray.new()
	_albedo_array.create_from_images(albedo_images)
	_normal_array = Texture2DArray.new()
	_normal_array.create_from_images(normal_images)


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
