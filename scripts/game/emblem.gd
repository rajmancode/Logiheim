class_name Emblem
extends RefCounted
## A clan's emblem: the field in the clan's colour, a second colour, a pattern dividing them
## and a charge in the middle. Flown on a flag from every building (shaders/flag.gdshader) and
## shown on a shield in the interface (shaders/emblem_ui.gdshader). Chosen per player before
## setting sail (EmblemEditor in the landing chooser).
##
## As a Dictionary: {charge: String, pattern: int, metal: Color} (the field is the player's
## colour).

const CHARGES := ["raven", "wolf", "longship", "axes", "tree", "serpent", "valknut", "sun_wheel", "hammer", "boar"]
const CHARGE_NAMES := {"raven": "Raven", "wolf": "Wolf", "longship": "Longship", "axes": "Crossed axes",
	"tree": "World tree", "serpent": "World serpent", "valknut": "Valknut", "sun_wheel": "Sun wheel",
	"hammer": "Thor's hammer", "boar": "Boar"}
const PATTERNS := ["Plain", "Bordure", "Per pale", "Per fess", "Chevron", "Quarterly", "Saltire", "Pale", "Bend"]
## Second colours: gold, silver, black and a few dyes.
const METALS := [Color(0.95, 0.8, 0.35), Color(0.9, 0.9, 0.86), Color(0.12, 0.1, 0.09), Color(0.85, 0.2, 0.15),
	Color(0.18, 0.32, 0.62), Color(0.22, 0.5, 0.3), Color(0.55, 0.3, 0.12)]
## Clan colours to choose from.
const FIELDS := [Color(0.85, 0.2, 0.18), Color(0.2, 0.45, 0.9), Color(0.25, 0.7, 0.3), Color(0.95, 0.75, 0.2),
	Color(0.6, 0.3, 0.8), Color(0.92, 0.92, 0.9), Color(0.12, 0.12, 0.14), Color(0.9, 0.5, 0.15), Color(0.15, 0.62, 0.65), Color(0.55, 0.12, 0.2)]


## The emblem a new player starts with: player k's charge, a pattern, gold or silver.
static func default_for(k: int) -> Dictionary:
	return {"charge": CHARGES[(k * 3) % CHARGES.size()], "pattern": [0, 2, 1, 5, 4, 6][k % 6], "metal": METALS[k % 2]}


static func charge_texture(charge: String) -> Texture2D:
	var path := "res://assets/emblems/%s.png" % charge
	return load(path) if ResourceLoader.exists(path) else null


## Sets an emblem material's (flag or shield) uniforms.
static func apply(mat: ShaderMaterial, field: Color, e: Dictionary) -> void:
	mat.set_shader_parameter("charge", charge_texture(String(e.get("charge", "raven"))))
	mat.set_shader_parameter("field", field)
	mat.set_shader_parameter("metal", e.get("metal", METALS[0]))
	mat.set_shader_parameter("pattern", int(e.get("pattern", 0)))


## A shield showing the emblem, for the interface.
static func shield(field: Color, e: Dictionary, size := 40.0) -> TextureRect:
	var r := TextureRect.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	r.texture = ImageTexture.create_from_image(img)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.custom_minimum_size = Vector2(size * 0.85, size)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/emblem_ui.gdshader")
	apply(mat, field, e)
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static var _flag_shader: Shader


## A flag material in a clan's colours.
static func flag_material(field: Color, e: Dictionary) -> ShaderMaterial:
	if _flag_shader == null:
		_flag_shader = load("res://shaders/flag.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _flag_shader
	apply(mat, field, e)
	mat.set_shader_parameter("phase", randf() * 6.28)
	return mat
