class_name Sfx
extends Node
## The game's sounds (assets/sfx, made by tools/make_sfx.py). Main adds one; anything calls
## Sfx.play("name") for a sound heard everywhere, or Sfx.play_at("name", pos) for one out in
## the world (louder near the camera, gone far off). Every button in the interface clicks when
## pressed and ticks softly under the mouse, and tabs turn like a page, without being wired up
## one by one. The world sounds round the player in loops - the sea, the wind (with its
## strength), birdsong by day, crickets by night, rain - set each frame by set_ambience().
## Volume: UiSettings.sound (0..1, the Options panel).

static var _me: Sfx

const AMBIENT := ["amb_sea", "amb_wind", "amb_birds", "amb_crickets", "amb_rain"]
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _players3: Array[AudioStreamPlayer3D] = []
var _last := {}
var _amb := {}            # name -> AudioStreamPlayer
var _amb_want := {}       # name -> 0..1


func _ready() -> void:
	_me = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 16:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 40.0
		p.max_distance = 260.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players3.append(p)
	for n: String in AMBIENT:
		var p := AudioStreamPlayer.new()
		var st := _stream(n)
		if st is AudioStreamWAV:
			var w := st as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		p.stream = st
		p.volume_db = -80.0
		add_child(p)
		_amb[n] = p
		_amb_want[n] = 0.0
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)


func _hook_tree(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_hook_tree(c)


func _exit_tree() -> void:
	if _me == self:
		_me = null


static func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if _me != null:
		_me._play(name, vol_db, pitch, null)


static func play_at(name: String, pos: Vector3, vol_db := 0.0) -> void:
	if _me != null:
		_me._play(name, vol_db, 1.0, pos)


## How loud each world loop should be now, 0..1 (missing ones fade out).
static func set_ambience(levels: Dictionary) -> void:
	if _me == null:
		return
	for n: String in AMBIENT:
		_me._amb_want[n] = float(levels.get(n, 0.0))


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := "res://assets/sfx/%s.wav" % name
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


func _master_db() -> float:
	return linear_to_db(maxf(UiSettings.sound, 0.0001))


func _play(name: String, vol_db: float, pitch: float, pos: Variant) -> void:
	if UiSettings.sound <= 0.001:
		return
	var st := _stream(name)
	if st == null:
		return
	# The same sound twice at once only stacks up into a din.
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last.get(name, -1.0)) < (0.045 if name == "ui_hover" else 0.03):
		return
	_last[name] = now
	var p: Node = null
	if pos == null:
		for q in _players:
			if not q.playing:
				p = q
				break
		if p == null:
			p = _players[0]
			_players.push_back(_players.pop_front())
	else:
		for q in _players3:
			if not q.playing:
				p = q
				break
		if p == null:
			p = _players3[0]
			_players3.push_back(_players3.pop_front())
		(p as AudioStreamPlayer3D).global_position = pos
	p.set("stream", st)
	p.set("volume_db", vol_db + _master_db())
	p.set("pitch_scale", pitch * randf_range(0.95, 1.05))
	p.call("play")


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta * 1.5)
	for n: String in AMBIENT:
		var p: AudioStreamPlayer = _amb[n]
		var want := float(_amb_want[n]) * UiSettings.sound
		var cur := db_to_linear(p.volume_db) if p.volume_db > -79.0 else 0.0
		cur = lerpf(cur, want, k)
		p.volume_db = linear_to_db(maxf(cur, 0.00001))
		if cur > 0.002 and not p.playing:
			p.play(randf() * 5.0)
		elif cur <= 0.002 and p.playing and want <= 0.0:
			p.stop()


## Every button clicks and every tab bar turns a page, wherever it is in the interface.
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.pressed.connect(func() -> void: Sfx.play("ui_click", -4.0))
		b.mouse_entered.connect(func() -> void:
			if not b.disabled:
				Sfx.play("ui_hover", -10.0))
	elif n is TabContainer:
		(n as TabContainer).tab_changed.connect(func(_i: int) -> void: Sfx.play("ui_tab", -3.0))
	elif n is TabBar:
		(n as TabBar).tab_changed.connect(func(_i: int) -> void: Sfx.play("ui_tab", -3.0))
