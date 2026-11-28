class_name Goods
extends RefCounted
## Everything a settlement can hold in stock: raw goods gathered from the land's resources,
## and goods made from them. Each has a display name, a colour (for the stock bar and the
## "+2 Wood" pops over buildings) and, where there is one, the resource icon it shares.

## id: [name, colour, icon key (assets/icons/resources) or "", is food]
const INFO := {
	# Raw goods, from the land.
	"wood": ["Wood", Color(0.62, 0.42, 0.22), "timber", false],
	"oak": ["Ship oak", Color(0.55, 0.4, 0.24), "oak", false],
	"stone": ["Stone", Color(0.62, 0.62, 0.6), "stone", false],
	"soapstone": ["Soapstone", Color(0.5, 0.56, 0.52), "soapstone", false],
	"iron": ["Iron ore", Color(0.6, 0.35, 0.25), "iron", false],
	"coal": ["Coal", Color(0.25, 0.25, 0.27), "coal", false],
	"peat": ["Peat", Color(0.35, 0.25, 0.18), "peat", false],
	"clay": ["Clay", Color(0.75, 0.5, 0.35), "clay", false],
	"reeds": ["Reeds", Color(0.72, 0.68, 0.4), "reeds", false],
	"salt": ["Salt", Color(0.95, 0.95, 0.95), "salt", false],
	"tar": ["Tar", Color(0.15, 0.12, 0.1), "tar", false],
	"wool": ["Wool", Color(0.92, 0.9, 0.84), "wool", false],
	"hides": ["Hides", Color(0.62, 0.46, 0.32), "seals", false],
	"furs": ["Furs", Color(0.5, 0.36, 0.24), "furs", false],
	"grain": ["Grain", Color(0.88, 0.75, 0.38), "farmland", false],
	"horses": ["Horses", Color(0.55, 0.38, 0.25), "horses", false],
	# Food.
	"fish": ["Fish", Color(0.45, 0.62, 0.75), "fish", true],
	"meat": ["Meat", Color(0.7, 0.3, 0.28), "game", true],
	"bread": ["Bread", Color(0.82, 0.6, 0.32), "", true],
	"stockfish": ["Salt fish", Color(0.78, 0.74, 0.6), "", true],
	"ale": ["Ale", Color(0.85, 0.62, 0.2), "", false],
	# Made goods.
	"bar_iron": ["Iron bars", Color(0.45, 0.46, 0.5), "", false],
	"tools": ["Tools", Color(0.55, 0.58, 0.62), "", false],
	"cloth": ["Cloth", Color(0.55, 0.45, 0.7), "", false],
	"leather": ["Leather", Color(0.5, 0.32, 0.18), "", false],
	"clothing": ["Clothing", Color(0.35, 0.5, 0.65), "", false],
	"pottery": ["Pottery", Color(0.7, 0.45, 0.3), "", false],
	"oil": ["Whale oil", Color(0.85, 0.75, 0.35), "whales", false],
	"arrows": ["Arrows", Color(0.6, 0.55, 0.4), "", false],
	"ship": ["Longships", Color(0.42, 0.3, 0.2), "", false],
	# Riches.
	"silver": ["Silver", Color(0.82, 0.84, 0.88), "silver", false],
	"gold": ["Gold", Color(1.0, 0.8, 0.25), "gold", false],
	"gems": ["Gems", Color(0.55, 0.35, 0.85), "gems", false],
	"amber": ["Amber", Color(0.95, 0.6, 0.15), "amber", false],
	"ivory": ["Walrus ivory", Color(0.94, 0.9, 0.8), "seals", false],
	"jewellery": ["Jewellery", Color(0.95, 0.75, 0.35), "", false],
	# War.
	"weapons": ["Weapons", Color(0.7, 0.72, 0.78), "", false],
	"warriors": ["Warriors", Color(0.8, 0.25, 0.2), "", false],
}

## Goods by kind, for the ledger.
const GROUPS := {
	"Raw goods": ["wood", "oak", "stone", "soapstone", "iron", "coal", "peat", "clay", "reeds", "salt", "tar", "wool", "hides", "furs", "grain", "horses"],
	"Food and drink": ["fish", "meat", "bread", "stockfish", "ale"],
	"Made goods": ["bar_iron", "tools", "cloth", "leather", "clothing", "pottery", "oil", "arrows", "ship"],
	"Riches": ["silver", "gold", "gems", "amber", "ivory", "jewellery"],
	"War": ["weapons", "warriors"],
}

## Every good, in ledger order.
const ORDER := ["wood", "oak", "stone", "soapstone", "iron", "coal", "peat", "clay", "reeds", "salt", "tar", "wool", "hides", "furs", "grain", "horses",
	"fish", "meat", "bread", "stockfish", "ale", "bar_iron", "tools", "cloth", "leather", "clothing", "pottery", "oil", "arrows", "ship",
	"silver", "gold", "gems", "amber", "ivory", "jewellery", "weapons", "warriors"]

## What the top bar always shows.
const TOP := ["wood", "stone", "tools", "silver"]

## What people eat, in the order they eat it (salt fish keeps, so it goes last).
const FOOD := ["fish", "meat", "bread", "stockfish"]

## What people want beyond food: [good, people per unit per minute, name of the need]. Each met
## need adds to their contentment.
const NEEDS := [
	["clothing", 12.0, "Clothes"],
	["pottery", 15.0, "Pots and vessels"],
	["ale", 10.0, "Ale"],
	["oil", 14.0, "Lamp oil"],
	["jewellery", 25.0, "Finery"],
]


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
		# A no-break space, so a wrapped line never parts an icon from its number.
		parts.append("[hint=%s]%s[/hint] %s%s" % [display_name(k), pic, prefix, _num(d[k])])
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
