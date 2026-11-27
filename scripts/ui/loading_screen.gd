class_name LoadingScreen
extends CanvasLayer
## Shown while a map is built. Everything on it is drawn from the map itself: its heightmap,
## rendered as an old sea chart, is revealed from the middle outwards as the build goes on
## (shaders/loading_chart.gdshader). Over it: the title, the map's name, what is being made
## now, a ruled progress bar, a turning ring of procedurally drawn runes, and a line of saga
## that changes now and then.

const SAGA := [
	"The land rises from the sea, as it did when the world was young.",
	"Rivers seek the sea by the oldest roads.",
	"Where the timber grows straight, a keel will follow.",
	"A good harbour is worth more than a hoard of silver.",
	"The wise settler looks for fresh water before gold.",
	"Ore sleeps in the hills; the bold will wake it.",
	"Every fjord is a door; every beach, an invitation.",
	"Cattle die, kinsmen die - but fame never dies.",
	"Many a shore is fair to see, few are good to land on.",
	"Old ways cross the hills where the going is easiest.",
]

var _chart_rect: ColorRect
var _mat: ShaderMaterial
var _stage: Label
var _name: Label
var _saga: Label
var _bar: Control
var _ring: Control
var _root: Control
var _progress := 0.0
var _shown := 0.0
var _saga_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 50
	_rng.randomize()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiStyle.hud_theme()
	add_child(_root)
	_chart_rect = ColorRect.new()
	_chart_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/loading_chart.gdshader")
	_chart_rect.material = _mat
	_root.add_child(_chart_rect)

	var title := Label.new()
	title.text = "LOGIHEIM"
	title.add_theme_font_override("font", UiStyle.font(900))
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	title.add_theme_color_override("font_outline_color", UiStyle.INK)
	title.add_theme_constant_override("outline_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 18
	title.offset_left = -400
	title.offset_right = 400
	_root.add_child(title)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -360
	bottom.offset_right = 360
	bottom.offset_top = -150
	bottom.offset_bottom = -24
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	_root.add_child(bottom)
	_name = _label(26, UiStyle.GOLD, 900)
	bottom.add_child(_name)
	_stage = _label(18, UiStyle.PARCHMENT, 700)
	bottom.add_child(_stage)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(720, 22)
	_bar.draw.connect(_draw_bar)
	bottom.add_child(_bar)
	_saga = _label(15, Color(0.95, 0.9, 0.78, 0.85), 400)
	_saga.add_theme_font_override("font", UiStyle.font(500))
	bottom.add_child(_saga)

	_ring = Control.new()
	_ring.custom_minimum_size = Vector2(96, 96)
	_ring.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ring.offset_left = -130
	_ring.offset_top = -130
	_ring.offset_right = -34
	_ring.offset_bottom = -34
	_ring.draw.connect(_draw_ring)
	_root.add_child(_ring)
	visible = false


func _label(size: int, color: Color, weight: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiStyle.INK)
	l.add_theme_constant_override("outline_size", maxi(4, size / 4))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Shows the screen for a map about to be built: draws its chart from the heightmap.
func begin(source: TerrainSource) -> void:
	visible = true
	_root.modulate.a = 1.0
	_progress = 0.0
	_shown = 0.0
	_name.text = source.name if source != null else ""
	_stage.text = "Setting out"
	_next_saga()
	if source != null:
		_mat.set_shader_parameter("chart", _chart_texture(source))
		_mat.set_shader_parameter("aspect", source.world_size.x / maxf(source.world_size.y, 1.0))
	_mat.set_shader_parameter("progress", 0.0)


func set_progress(stage: String, fraction: float) -> void:
	_stage.text = stage + ("…" if fraction < 1.0 else "")
	_progress = maxf(_progress, fraction)


## Fades the screen out once the map is ready.
func finish() -> void:
	_progress = 1.0
	_stage.text = "The land is ready"
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_root, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: visible = false)


func _process(delta: float) -> void:
	if not visible:
		return
	# The chart catches up with the build smoothly, and keeps creeping during long stages.
	var target := minf(_progress + 0.04, 1.0) if _progress < 1.0 else 1.0
	_shown = move_toward(_shown, target, delta * (0.5 if _shown < _progress else 0.01))
	_mat.set_shader_parameter("progress", _shown)
	_mat.set_shader_parameter("screen_size", _root.get_viewport_rect().size)
	_saga_timer -= delta
	if _saga_timer <= 0.0:
		_next_saga()
	_bar.queue_redraw()
	_ring.queue_redraw()


func _next_saga() -> void:
	_saga.text = "“%s”" % SAGA[_rng.randi() % SAGA.size()]
	_saga_timer = 6.0


## The heightmap as a small chart texture: r = height, g = 1 where it is sea.
func _chart_texture(source: TerrainSource) -> ImageTexture:
	var aspect := source.world_size.x / maxf(source.world_size.y, 1.0)
	var w := 512 if aspect >= 1.0 else int(512 * aspect)
	var h := int(w / aspect)
	var img := Image.create(w, h, false, Image.FORMAT_RGF)
	var sea := source.sea_level if source.sea_level > 0.0 else 0.02
	var has_mask := source.masks.has("water")
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * source.world_size.x, (y + 0.5) / h * source.world_size.y)
			var hv := source.sample_height(p)
			var wet := hv <= sea
			if has_mask and source.sample_mask("water", p) > 0.5:
				wet = true
			var rel := clampf((hv - sea) / maxf(1.0 - sea, 0.01), 0.0, 1.0) if not wet else clampf(hv / maxf(sea, 0.01), 0.0, 1.0)
			img.set_pixel(x, y, Color(rel, 1.0 if wet else 0.0, 0.0))
	return ImageTexture.create_from_image(img)


## A ruled bar: dark track, gold fill, a tick at every tenth, and a bright leading edge.
func _draw_bar() -> void:
	var sz := _bar.size
	var r := Rect2(Vector2(0, 4), Vector2(sz.x, sz.y - 8))
	_bar.draw_rect(r, Color(0.05, 0.04, 0.03, 0.8))
	var f := Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * _shown, r.size.y - 4))
	_bar.draw_rect(f, Color(0.78, 0.58, 0.24))
	_bar.draw_rect(Rect2(f.position, Vector2(f.size.x, f.size.y * 0.4)), Color(1.0, 0.85, 0.5, 0.5))
	for k in range(1, 10):
		var x := r.position.x + r.size.x * k / 10.0
		_bar.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.08, 0.05, 0.03, 0.7), 1.0)
	if _shown > 0.0 and _shown < 1.0:
		var ex := f.end.x
		_bar.draw_circle(Vector2(ex, r.get_center().y), 5.0 + sin(Time.get_ticks_msec() * 0.01) * 1.5, Color(1.0, 0.7, 0.3, 0.8))
	_bar.draw_rect(r, UiStyle.GOLD, false, 2.0)


## A ring of runes, each a few strokes drawn from a seeded random, turning slowly; the rune at
## the top glows.
func _draw_ring() -> void:
	var c := _ring.size * 0.5
	var t := Time.get_ticks_msec() / 1000.0
	var count := 16
	var radius := minf(c.x, c.y) - 10.0
	_ring.draw_arc(c, radius + 9.0, 0.0, TAU, 64, Color(UiStyle.GOLD, 0.6), 1.5)
	_ring.draw_arc(c, radius - 9.0, 0.0, TAU, 64, Color(UiStyle.GOLD, 0.6), 1.5)
	var rng := RandomNumberGenerator.new()
	for i in count:
		rng.seed = i * 7919 + 13
		var a := TAU * i / count + t * 0.6
		var pos := c + Vector2.from_angle(a) * radius
		var up := Vector2.from_angle(a)
		var side := Vector2(-up.y, up.x)
		var glow := pow(maxf(cos(a + PI * 0.5), 0.0), 8.0)
		var col := UiStyle.PARCHMENT.lerp(Color(1.0, 0.75, 0.3), glow)
		col.a = 0.55 + 0.45 * glow
		# A stave, and two or three branches off it.
		var top := pos + up * 6.0
		var bot := pos - up * 6.0
		_ring.draw_line(top, bot, col, 2.0)
		for b in rng.randi_range(1, 3):
			var at := lerpf(-5.0, 5.0, rng.randf())
			var dir := side * (1.0 if rng.randf() < 0.5 else -1.0)
			var tilt := up * rng.randf_range(-4.0, 4.0)
			_ring.draw_line(pos + up * at, pos + up * at + dir * 4.5 + tilt, col, 2.0)
