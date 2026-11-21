class_name TerrainMaterial
extends RefCounted
## Builds the terrain ShaderMaterial: one PBR texture array holding every ground, rock and prop
## texture (TEXTURES), plus a tint per terrain layer. The terrain shader gives each of the 8
## terrain layers a family of these textures (grass: lush, meadow, sparse, moss; rock: granite,
## cliff, mossy, dark; ...) and picks between them per pixel from moisture, height, slope and
## so on. for_level() makes a copy carrying one level's grid settings.
##
## Textures live in assets/textures/terrain/ (see tools/pack_ambientcg.py):
##   <name>_albedo.webp  RGB colour, A height     <name>_normal.webp  RG normal, B AO, A roughness

const SHADER_PATH := "res://shaders/hex_terrain.gdshader"
const TEXTURE_DIR := "res://assets/textures/terrain"
const LAYER_SIZE := 1024

## Every texture, in texture-array order. The shaders refer to them by these indices
## (constants T_* in shaders/hex_terrain.gdshader; index() for scripts).
const TEXTURES := [
	"sand", "sand_dune", "sand_wet", "pebbles",
	"grass", "grass_meadow", "grass_sparse", "moss",
	"forest_floor", "leaf_litter", "needles",
	"rock", "rock_cliff", "rock_mossy", "rock_dark",
	"snow", "snow_rocky", "ice",
	"dirt", "mud", "soil", "gravel", "ash", "lava",
	"bark", "wood",
]
## Metres covered by one repeat of each texture.
const TEXTURE_METRES := [
	7.0, 9.0, 6.0, 3.0,
	4.0, 4.5, 5.0, 3.5,
	4.5, 3.0, 3.5,
	9.0, 12.0, 8.0, 8.0,
	7.0, 8.0, 10.0,
	3.5, 4.0, 4.0, 3.0, 4.0, 6.0,
	2.0, 2.0,
]
## Per-texture colour correction: rgb multiplier (sRGB) and saturation in alpha. Ice loses
## most of its turquoise; sparse grass is darkened so it doesn't wash out; leaf litter less
## autumn-yellow; lava only ever shows as dark crust on the ground.
const TEXTURE_TINTS := {
	"grass_sparse": Color(0.82, 0.85, 0.78, 0.9),
	"leaf_litter": Color(0.8, 0.75, 0.65, 0.65),
	"ice": Color(0.95, 0.98, 1.0, 0.25),
	"moss": Color(0.9, 0.95, 0.85, 0.85),
}
## Tint per layer (sRGB). The sea floor is darker and greener; forest floor a touch darker.
const LAYER_TINTS := [
	Color(0.5, 0.56, 0.5), Color(0.78, 0.8, 0.74), Color.WHITE, Color(0.95, 0.97, 0.9),
	Color(0.82, 0.88, 0.78), Color.WHITE, Color.WHITE, Color(0.9, 0.86, 0.82),
]
## Used as a flat colour when a texture file is missing.
const FALLBACK := Color(0.5, 0.5, 0.48, 0.5)

static var _albedo_array: Texture2DArray
static var _normal_array: Texture2DArray
static var _missing: Array[bool] = []


static func create() -> ShaderMaterial:
	_ensure_arrays()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var tints := PackedColorArray()
	for i in LAYER_TINTS.size():
		tints.append((LAYER_TINTS[i] as Color).srgb_to_linear())
	mat.set_shader_parameter("albedo_array", _albedo_array)
	mat.set_shader_parameter("normal_array", _normal_array)
	mat.set_shader_parameter("layer_tint", tints)
	mat.set_shader_parameter("tex_size", PackedFloat32Array(TEXTURE_METRES))
	var tex_tints := PackedColorArray()
	for t: String in TEXTURES:
		var c: Color = TEXTURE_TINTS.get(t, Color(1, 1, 1, 1))
		var lin := Color(c.r, c.g, c.b).srgb_to_linear()
		tex_tints.append(Color(lin.r, lin.g, lin.b, c.a))
	mat.set_shader_parameter("tex_tint", tex_tints)
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
static func index(texture_name: String) -> int:
	return TEXTURES.find(texture_name)


static func albedo_array() -> Texture2DArray:
	_ensure_arrays()
	return _albedo_array


static func normal_array() -> Texture2DArray:
	_ensure_arrays()
	return _normal_array


static func _ensure_arrays() -> void:
	if _albedo_array != null:
		return
	var t0 := Time.get_ticks_msec()
	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	_missing.clear()
	for i in TEXTURES.size():
		var layer_name: String = TEXTURES[i]
		var albedo := _load_layer("%s/%s_albedo" % [TEXTURE_DIR, layer_name])
		_missing.append(albedo == null)
		if albedo == null:
			push_warning("TerrainMaterial: missing texture %s" % layer_name)
			albedo = _solid(FALLBACK)
		var normal := _load_layer("%s/%s_normal" % [TEXTURE_DIR, layer_name])
		if normal == null:
			normal = _solid(Color(0.5, 0.5, 1.0, 0.85))
		albedo_images.append(albedo)
		normal_images.append(normal)
	_albedo_array = Texture2DArray.new()
	_albedo_array.create_from_images(albedo_images)
	_normal_array = Texture2DArray.new()
	_normal_array.create_from_images(normal_images)
	print("TerrainMaterial: %d textures in %d ms" % [TEXTURES.size(), Time.get_ticks_msec() - t0])


## Loads <base>.webp (or .png).
static func _load_layer(base: String) -> Image:
	var img: Image = null
	for ext in [".webp", ".png"]:
		var path: String = base + ext
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				img = tex.get_image()
		if img == null and FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		if img != null:
			break
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
