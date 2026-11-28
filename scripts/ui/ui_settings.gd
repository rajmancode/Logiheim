class_name UiSettings
extends RefCounted
## The player's interface preferences, kept in user://settings.cfg between games: how big the
## interface is drawn, where its parts sit, and whether production pops over buildings.

const PATH := "user://settings.cfg"

static var scale := 1.0              ## 0.75 .. 1.5
static var bar_top := true           ## the resource bar at the top (else the bottom)
static var build_bottom := true      ## the build menu at the bottom (else the top)
static var panel_left := true        ## the selected building's panel on the left (else right)
static var ledger_right := true      ## the ledger on the right (else left)
static var pops := true              ## "+2 Wood" coins rising over working buildings
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	scale = clampf(float(cf.get_value("hud", "scale", 1.0)), 0.75, 1.5)
	bar_top = bool(cf.get_value("hud", "bar_top", true))
	build_bottom = bool(cf.get_value("hud", "build_bottom", true))
	panel_left = bool(cf.get_value("hud", "panel_left", true))
	ledger_right = bool(cf.get_value("hud", "ledger_right", true))
	pops = bool(cf.get_value("hud", "pops", true))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("hud", "scale", scale)
	cf.set_value("hud", "bar_top", bar_top)
	cf.set_value("hud", "build_bottom", build_bottom)
	cf.set_value("hud", "panel_left", panel_left)
	cf.set_value("hud", "ledger_right", ledger_right)
	cf.set_value("hud", "pops", pops)
	cf.save(PATH)


static func reset() -> void:
	scale = 1.0
	bar_top = true
	build_bottom = true
	panel_left = true
	ledger_right = true
	pops = true
