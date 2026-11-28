class_name Atmosphere
extends Node3D
## Sky, sun and moon, day/night cycle, weather, wind, drifting clouds and rain.
##
## Shared state goes to every shader through global shader parameters (declared in
## project.godot, read in shaders/include/environment.gdshaderinc). Terrain, rivers, trees and
## the cloud layer therefore agree on wind, cloud positions and wetness.

enum Weather { CLEAR, CLOUDY, RAIN }
const WEATHER_NAMES := ["Clear", "Cloudy", "Rain"]
## Target values for each weather. The current state eases towards them.
const WEATHER_PRESETS := [
	{"coverage": 0.34, "rain": 0.0, "wind": 0.3, "fog": 0.00008, "light": 1.0},
	{"coverage": 0.6, "rain": 0.0, "wind": 0.55, "fog": 0.00014, "light": 0.72},
	{"coverage": 0.86, "rain": 1.0, "wind": 0.9, "fog": 0.00028, "light": 0.45},
]
const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Hours, 0..24.
@export var time_of_day := 10.0
## Real minutes for one in-game day.
@export var day_length_minutes := 8.0
@export var cycle_running := true
@export var weather := Weather.CLEAR
## 0 in daylight, 1 at night (also darker under heavy cloud): when torches are lit and windows glow.
static var night := 0.0
## Where the wind blows (unit, in the xz plane) and how hard (0..1), for flags.
static var wind_now_dir := Vector2.RIGHT
static var wind_now_strength := 0.3

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment

var coverage := 0.34
var rain := 0.0
var wind := 0.3
var fog := 0.00008
var light := 1.0
var wetness := 0.0
## 0 dry .. 1 rivers in full flood: rises over a couple of minutes of rain, drains slowly.
var flood := 0.0
var wind_angle := 0.6
var wind_now := 0.3
var wind_time := 0.0
var cloud_offset := Vector2.ZERO

var _sky: ProceduralSkyMaterial
var _cloud_mat: ShaderMaterial
var _clouds: MeshInstance3D
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _noise := FastNoiseLite.new()
var _t := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.05
	_build_environment()
	_build_lights()
	_build_clouds()
	_build_rain()
	_update(0.0)


## Fits clouds and shadows to a map: world_size in metres (x, z), top_y = highest hex top.
func configure(world_size: Vector2, top_y: float) -> void:
	var span := maxf(world_size.x, world_size.y)
	var height := maxf(top_y + 220.0, 320.0)
	RenderingServer.global_shader_parameter_set("cloud_height", height)
	RenderingServer.global_shader_parameter_set("cloud_scale", 1.0 / clampf(span * 0.3, 300.0, 4000.0))
	var plane := _clouds.mesh as PlaneMesh
	plane.size = Vector2.ONE * span * 4.0
	_clouds.position = Vector3(world_size.x * 0.5, height, world_size.y * 0.5)
	_cloud_mat.set_shader_parameter("near_fade", span * 0.05)
	_cloud_mat.set_shader_parameter("near_fade_end", span * 0.3)
	_cloud_mat.set_shader_parameter("fade_center", world_size * 0.5)
	_cloud_mat.set_shader_parameter("fade_radius", Vector2(span * 0.9, span * 1.8))
	sun.directional_shadow_max_distance = span * 2.0


## Keeps the rain around what the camera is looking at. Call every frame.
func update_view(pivot: Vector3, view_distance: float) -> void:
	var s := view_distance * 0.9
	_rain.scale = Vector3.ONE * s
	_rain.position = pivot + Vector3(0.0, 0.7 * s, 0.0)


func cycle_weather() -> void:
	weather = ((weather + 1) % WEATHER_NAMES.size()) as Weather


func shift_time(hours: float) -> void:
	time_of_day = fposmod(time_of_day + hours, 24.0)


## One HUD line: time, weather and wind.
func describe() -> String:
	var hh := int(time_of_day)
	var mm := int((time_of_day - hh) * 60.0)
	var from := -Vector2(cos(wind_angle), sin(wind_angle))
	var bearing := fposmod(rad_to_deg(atan2(from.x, -from.y)), 360.0)
	var compass: String = COMPASS[int(round(bearing / 45.0)) % 8]
	var flooding := ""
	if flood > 0.05:
		flooding = "   rivers flooding %d%%" % roundi(flood * 100.0)
	return "%02d:%02d %s   %s   wind %d km/h from %s%s" % [
		hh, mm, "" if cycle_running else "(paused)", WEATHER_NAMES[weather], roundi(5.0 + wind_now * 60.0), compass, flooding]


## True while exploring a cave: no sun, moon, clouds or rain down there.
var underground := false


func _process(delta: float) -> void:
	_update(delta)
	if underground:
		sun.visible = false
		moon.visible = false
		_clouds.visible = false
		_rain.visible = false
	else:
		_clouds.visible = true
		_rain.visible = true


func _update(delta: float) -> void:
	_t += delta
	if cycle_running and day_length_minutes > 0.0:
		time_of_day = fposmod(time_of_day + delta * 24.0 / (day_length_minutes * 60.0), 24.0)

	var target: Dictionary = WEATHER_PRESETS[weather]
	var k := 1.0 - exp(-delta * 0.35)
	coverage = lerpf(coverage, target.coverage, k)
	rain = lerpf(rain, target.rain, k)
	wind = lerpf(wind, target.wind, k)
	fog = lerpf(fog, target.fog, k)
	light = lerpf(light, target.light, k)
	wetness = move_toward(wetness, rain, delta * (0.12 if rain > wetness else 0.015))
	var flood_target := smoothstep(0.4, 1.0, rain)
	flood = move_toward(flood, flood_target, delta * (0.008 if flood_target > flood else 0.004))

	# Wind direction wanders slowly; gusts come and go.
	wind_angle += _noise.get_noise_1d(_t * 0.3) * delta * 0.2
	wind_now = clampf(wind * (0.8 + 0.45 * _noise.get_noise_1d(_t * 2.0 + 100.0)), 0.0, 1.0)
	wind_time += delta * (0.5 + wind_now * 1.6)
	var wind_dir := Vector2(cos(wind_angle), sin(wind_angle))
	wind_now_dir = wind_dir
	wind_now_strength = wind_now
	cloud_offset += wind_dir * (6.0 + 30.0 * wind_now) * delta

	# Occasional lightning in heavy rain.
	_flash = maxf(0.0, _flash - delta * 6.0)
	if rain > 0.75 and _rng.randf() < delta * 0.12:
		_flash = 1.0

	var sun_dir := _update_sky()

	RenderingServer.global_shader_parameter_set("wind_direction", wind_dir)
	RenderingServer.global_shader_parameter_set("wind_strength", wind_now)
	RenderingServer.global_shader_parameter_set("wind_time", wind_time)
	RenderingServer.global_shader_parameter_set("cloud_offset", cloud_offset)
	RenderingServer.global_shader_parameter_set("cloud_coverage", coverage)
	RenderingServer.global_shader_parameter_set("cloud_shadow_strength", 0.5 * (1.0 - 0.6 * smoothstep(0.6, 0.9, coverage)))
	RenderingServer.global_shader_parameter_set("sun_direction", sun_dir)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("flood", flood)

	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	_rain.emitting = rain > 0.03
	_rain_process.direction = Vector3(wind_dir.x * 0.3 * wind_now, -1.0, wind_dir.y * 0.3 * wind_now)


## Sun and moon position, light colours, sky, fog and cloud colours. Returns the sun direction.
func _update_sky() -> Vector3:
	var h := (time_of_day - 12.0) / 24.0 * TAU
	var sin_e := cos(h) * 0.8 - 0.03
	var elev := asin(clampf(sin_e, -1.0, 1.0))
	# Sun rises in the east (+x), crosses the south side of the sky, sets in the west.
	var horiz := Vector2(-sin(h), cos(h)).rotated(deg_to_rad(-35.0))
	var sun_dir := Vector3(horiz.x * cos(elev), sin(elev), horiz.y * cos(elev)).normalized()

	var day := smoothstep(-0.08, 0.2, sin_e)
	night = clampf(1.0 - smoothstep(-0.05, 0.25, sin_e) + 0.25 * (1.0 - light), 0.0, 1.0)
	var golden := (1.0 - smoothstep(0.0, 0.45, sin_e)) * day
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_energy = 1.3 * day * light
	sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.55, 0.32), golden)
	sun.visible = day > 0.002

	var moon_dir := Vector3(-sun_dir.x, maxf(-sun_dir.y, 0.35), -sun_dir.z).normalized()
	moon.basis = Basis.looking_at(-moon_dir, Vector3.UP)
	moon.light_energy = 0.25 * (1.0 - day) * (0.4 + 0.6 * light)
	moon.visible = day < 0.998

	var overcast := clampf((coverage - 0.35) * 1.6, 0.0, 0.85)
	var grey := Color(0.5, 0.53, 0.57)
	var top := Color(0.012, 0.018, 0.045).lerp(Color(0.32, 0.5, 0.75).lerp(Color(0.28, 0.33, 0.55), golden), day)
	var horizon := Color(0.04, 0.05, 0.09).lerp(Color(0.7, 0.76, 0.82).lerp(Color(0.95, 0.62, 0.42), golden), day)
	top = top.lerp(grey * (0.15 + 0.85 * day), overcast)
	horizon = horizon.lerp(grey * (0.2 + 0.8 * day), overcast)
	var flash := Color(0.8, 0.85, 1.0) * _flash * 0.6
	_sky.sky_top_color = top + flash
	_sky.sky_horizon_color = horizon + flash
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = horizon * 0.35

	environment.ambient_light_energy = lerpf(0.35, 0.8, day) * (0.7 + 0.3 * light) + _flash * 1.5
	environment.fog_density = fog
	environment.fog_light_color = horizon

	var cloud_light := Color.WHITE.lerp(Color(1.0, 0.72, 0.55), golden) * (0.12 + 0.88 * day) * (0.7 + 0.3 * light)
	cloud_light += flash
	_cloud_mat.set_shader_parameter("light_color", cloud_light)
	_cloud_mat.set_shader_parameter("shade_color", cloud_light * Color(0.55, 0.58, 0.66))
	_cloud_mat.set_shader_parameter("opacity", 0.75 + 0.2 * overcast)
	return sun_dir


func _build_environment() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 2.0
	environment.ssao_intensity = 1.5
	environment.fog_enabled = true
	environment.fog_density = fog
	environment.fog_aerial_perspective = 0.4
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.1

	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 4000.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _build_clouds() -> void:
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://shaders/clouds.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000.0, 8000.0)
	_clouds = MeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.mesh = plane
	_clouds.material_override = _cloud_mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_clouds)


## Rain is a particle box in local coordinates that update_view() scales with the zoom, so it
## looks about the same at any camera distance.
func _build_rain() -> void:
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.emission_box_extents = Vector3(0.75, 0.02, 0.75)
	_rain_process.direction = Vector3(0.0, -1.0, 0.0)
	_rain_process.spread = 3.0
	_rain_process.initial_velocity_min = 0.9
	_rain_process.initial_velocity_max = 1.1
	_rain_process.gravity = Vector3(0.0, -0.3, 0.0)

	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop_mat.billboard_keep_scale = true
	var drop := QuadMesh.new()
	drop.size = Vector2(0.0009, 0.022)
	drop.material = drop_mat

	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 8000
	_rain.lifetime = 0.9
	_rain.local_coords = true
	_rain.emitting = false
	_rain.process_material = _rain_process
	_rain.draw_pass_1 = drop
	_rain.visibility_aabb = AABB(Vector3(-1.0, -1.5, -1.0), Vector3(2.0, 2.5, 2.0))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
