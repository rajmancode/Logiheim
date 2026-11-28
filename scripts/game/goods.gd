class_name Goods
extends RefCounted
## Everything a settlement can hold in stock: raw goods gathered from the land's resources,
## and goods made from them. Each has a display name, a colour (for the stock bar and the
## "+2 Wood" pops over buildings) and, where there is one, the resource icon it shares.

## id: [name, colour, icon key (assets/icons/resources) or "", is food]
const INFO := {
	"wood": ["Wood", Color(0.62, 0.42, 0.22), "timber", false],
	"stone": ["Stone", Color(0.62, 0.62, 0.6), "stone", false],
	"iron": ["Iron ore", Color(0.6, 0.35, 0.25), "iron", false],
	"coal": ["Coal", Color(0.25, 0.25, 0.27), "coal", false],
	"silver": ["Silver", Color(0.82, 0.84, 0.88), "silver", false],
	"gold": ["Gold", Color(1.0, 0.8, 0.25), "gold", false],
	"gems": ["Gems", Color(0.55, 0.35, 0.85), "gems", false],
	"fish": ["Fish", Color(0.45, 0.62, 0.75), "fish", true],
	"meat": ["Meat", Color(0.7, 0.3, 0.28), "game", true],
	"grain": ["Grain", Color(0.88, 0.75, 0.38), "farmland", false],
	"bread": ["Bread", Color(0.82, 0.6, 0.32), "", true],
	"ale": ["Ale", Color(0.85, 0.62, 0.2), "", false],
	"wool": ["Wool", Color(0.92, 0.9, 0.84), "wool", false],
	"cloth": ["Cloth", Color(0.55, 0.45, 0.7), "", false],
	"furs": ["Furs", Color(0.5, 0.36, 0.24), "furs", false],
	"clay": ["Clay", Color(0.75, 0.5, 0.35), "clay", false],
	"salt": ["Salt", Color(0.95, 0.95, 0.95), "salt", false],
	"peat": ["Peat", Color(0.35, 0.25, 0.18), "peat", false],
	"tar": ["Tar", Color(0.15, 0.12, 0.1), "tar", false],
	"amber": ["Amber", Color(0.95, 0.6, 0.15), "amber", false],
	"tools": ["Tools", Color(0.55, 0.58, 0.62), "", false],
	"weapons": ["Weapons", Color(0.7, 0.72, 0.78), "", false],
	"warriors": ["Warriors", Color(0.8, 0.25, 0.2), "", false],
}

## The order goods are listed in the stock bar.
const ORDER := ["wood", "stone", "clay", "peat", "tar", "iron", "coal", "tools", "weapons", "grain",
	"fish", "meat", "bread", "ale", "wool", "cloth", "furs", "salt", "amber", "silver", "gold", "gems", "warriors"]

## What people eat, in the order they eat it.
const FOOD := ["fish", "meat", "bread"]


static func display_name(id: String) -> String:
	return INFO[id][0] if INFO.has(id) else id.capitalize()


static func color(id: String) -> Color:
	return INFO[id][1] if INFO.has(id) else Color.WHITE


## The good's coin (assets/icons/goods, made by tools/make_game_icons.py), "influence" too;
## the map resource's badge if there is no coin.
static func icon(id: String) -> Texture2D:
	var path := icon_path(id)
	if path != "":
		return load(path)
	if not INFO.has(id) or String(INFO[id][2]) == "":
		return null
	return HexMap.icon_texture(INFO[id][2])


static func icon_path(id: String) -> String:
	var path := "res://assets/icons/goods/%s.png" % id
	return path if ResourceLoader.exists(path) else ""


## A cost or output as BBCode for a RichTextLabel: each good's coin and the amount.
static func bbcode(d: Dictionary, size := 20, prefix := "") -> String:
	var parts := PackedStringArray()
	for k in d:
		var path := icon_path(k)
		var pic := "[img=%dx%d]%s[/img]" % [size, size, path] if path != "" else display_name(k)
		parts.append("[hint=%s]%s[/hint] %s%s" % [display_name(k), pic, prefix, _num(d[k])])
	return "   ".join(parts)


## "12 Wood, 5 Stone" for a cost or output dictionary.
static func describe(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in d:
		parts.append("%s %s" % [_num(d[k]), display_name(k)])
	return ", ".join(parts)


static func _num(v) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f
