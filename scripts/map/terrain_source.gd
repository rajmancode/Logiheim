class_name TerrainSource
extends RefCounted
## Terrain data exported from Gaea: a heightmap plus optional masks, described by map.json.
## See docs/GAEA_PIPELINE.md for the folder layout and supported formats.

var name := ""
var directory := ""
## World extent in metres: x = east/west, y = north/south (world z).
var world_size := Vector2(1024.0, 1024.0)
## Metres represented by a normalised height of 1.0.
var height_range := 200.0
## Normalised sea level from map.json, or -1 if the map does not define one.
var sea_level := -1.0
var width := 0
var height := 0
## Normalised heights 0..1, row-major, row 0 = world z 0.
var heights := PackedFloat32Array()
## mask name -> MaskImage
var masks: Dictionary = {}


class MaskImage:
	var width := 0
	var height := 0
	var data := PackedByteArray()

	func sample(uv: Vector2) -> float:
		var u := clampf(uv.x, 0.0, 1.0) * (width - 1)
		var v := clampf(uv.y, 0.0, 1.0) * (height - 1)
		var x0 := int(u)
		var y0 := int(v)
		var x1 := mini(x0 + 1, width - 1)
		var y1 := mini(y0 + 1, height - 1)
		var fx := u - x0
		var fy := v - y0
		var a := lerpf(data[y0 * width + x0], data[y0 * width + x1], fx)
		var b := lerpf(data[y1 * width + x0], data[y1 * width + x1], fx)
		return lerpf(a, b, fy) / 255.0


static func load_from_dir(dir: String) -> TerrainSource:
	var json_path := dir.path_join("map.json")
	if not FileAccess.file_exists(json_path):
		push_error("TerrainSource: missing %s" % json_path)
		return null
	var meta = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(meta) != TYPE_DICTIONARY:
		push_error("TerrainSource: %s is not a JSON object" % json_path)
		return null

	var src := TerrainSource.new()
	src.directory = dir
	src.name = str(meta.get("name", dir.get_file()))
	var ws: Array = meta.get("world_size", [1024.0, 1024.0])
	src.world_size = Vector2(float(ws[0]), float(ws[1]))
	src.height_range = float(meta.get("height_range", 200.0))
	src.sea_level = float(meta.get("sea_level", -1.0))

	var hm: Dictionary = meta.get("heightmap", {})
	if not src._load_heightmap(dir, hm):
		return null

	var mask_defs: Dictionary = meta.get("masks", {})
	for key in mask_defs:
		var mask := _load_mask(dir.path_join(str(mask_defs[key])))
		if mask == null:
			push_warning("TerrainSource: could not load mask '%s', falling back to height rules" % key)
			continue
		src.masks[str(key)] = mask
	return src


func uv_of(p: Vector2) -> Vector2:
	return Vector2(p.x / world_size.x, p.y / world_size.y)


## Bilinear normalised height (0..1) at world position p (x, z).
func sample_height(p: Vector2) -> float:
	var u := clampf(p.x / world_size.x, 0.0, 1.0) * (width - 1)
	var v := clampf(p.y / world_size.y, 0.0, 1.0) * (height - 1)
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, width - 1)
	var y1 := mini(y0 + 1, height - 1)
	var fx := u - x0
	var fy := v - y0
	var a := lerpf(heights[y0 * width + x0], heights[y0 * width + x1], fx)
	var b := lerpf(heights[y1 * width + x0], heights[y1 * width + x1], fx)
	return lerpf(a, b, fy)


func sample_mask(mask_name: String, p: Vector2) -> float:
	var m: MaskImage = masks.get(mask_name)
	return m.sample(uv_of(p)) if m != null else 0.0


func _load_heightmap(dir: String, hm: Dictionary) -> bool:
	var file := str(hm.get("file", "heightmap.r16"))
	var path := dir.path_join(file)
	var fmt := str(hm.get("format", file.get_extension())).to_lower()
	width = int(hm.get("width", 0))
	height = int(hm.get("height", 0))

	match fmt:
		"r16", "raw16", "raw":
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.is_empty():
				push_error("TerrainSource: cannot read %s (add *.r16 to the export include filter)" % path)
				return false
			_infer_square(bytes.size() / 2)
			if bytes.size() < width * height * 2:
				push_error("TerrainSource: %s is smaller than %dx%d 16-bit" % [path, width, height])
				return false
			var big_endian := str(hm.get("endian", "little")) == "big"
			heights.resize(width * height)
			for i in width * height:
				var v := bytes.decode_u16(i * 2)
				if big_endian:
					v = ((v & 0xff) << 8) | (v >> 8)
				heights[i] = v / 65535.0
		"r32", "raw32":
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.is_empty():
				push_error("TerrainSource: cannot read %s (add *.r32 to the export include filter)" % path)
				return false
			_infer_square(bytes.size() / 4)
			heights = bytes.to_float32_array()
			heights.resize(width * height)
		_:
			var img := _load_image(path)
			if img == null:
				push_error("TerrainSource: cannot load heightmap image %s" % path)
				return false
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RF)
			width = img.get_width()
			height = img.get_height()
			heights = img.get_data().to_float32_array()

	# Optional remap for float formats that are not already 0..1.
	var lo := float(hm.get("min", 0.0))
	var hi := float(hm.get("max", 1.0))
	if lo != 0.0 or hi != 1.0:
		var inv := 1.0 / maxf(hi - lo, 1e-6)
		for i in heights.size():
			heights[i] = (heights[i] - lo) * inv
	return width > 1 and height > 1


func _infer_square(pixel_count: int) -> void:
	if width <= 0 or height <= 0:
		width = int(sqrt(float(pixel_count)))
		height = width


static func _load_mask(path: String) -> MaskImage:
	var img := _load_image(path)
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_L8)
	var m := MaskImage.new()
	m.width = img.get_width()
	m.height = img.get_height()
	m.data = img.get_data()
	return m


## Loads an image whether it was imported by Godot (exported builds) or is a raw file (editor).
static func _load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			var img := tex.get_image()
			if img != null:
				return img
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	return null
