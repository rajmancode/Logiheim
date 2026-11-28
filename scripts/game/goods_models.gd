class_name GoodsModels
extends RefCounted
## A small model of each good, for its icon (rendered by tools/render_game_icons.gd): the thing
## itself - a stack of logs, cut stone, ore, an ingot, a loaf, a tankard of ale, a sheaf of
## grain, a sword and shield... Built with the buildings' kit, so they share their look.



static func mesh(id: String) -> ArrayMesh:
	var k := BuildingModels.Kit.new()
	seed(hash(id))
	match id:
		"wood":
			for row in 2:
				for i in 3 - row:
					k.log(Vector3(0, 0.3 + row * 0.5, -0.55 + i * 0.55 + row * 0.27), 0.26, 1.8, BuildingModels.PALE_WOOD, Vector3.RIGHT)
		"stone":
			k.box(Vector3(-0.35, 0.3, 0), Vector3(0.9, 0.6, 0.7), BuildingModels.STONE)
			k.box(Vector3(0.45, 0.25, 0.1), Vector3(0.7, 0.5, 0.6), BuildingModels.STONE * 1.05, Vector3(0, 0.3, 0))
			k.box(Vector3(0.0, 0.85, 0.0), Vector3(0.8, 0.5, 0.6), BuildingModels.STONE * 0.95, Vector3(0, -0.2, 0))
		"iron", "coal":
			var col := Color(0.5, 0.28, 0.2) if id == "iron" else Color(0.12, 0.12, 0.13)
			for p in [Vector3(-0.3, 0.3, 0), Vector3(0.35, 0.28, 0.15), Vector3(0.05, 0.7, -0.05), Vector3(0.1, 0.25, -0.4)]:
				k.box(p, Vector3(0.5, 0.45, 0.5), col * (0.9 + 0.2 * randf()), Vector3(randf(), randf(), randf()))
		"silver", "gold":
			var col := Color(0.85, 0.87, 0.9) if id == "silver" else Color(1.0, 0.78, 0.25)
			k.box(Vector3(0, 0.22, 0), Vector3(1.3, 0.4, 0.6), col)
			k.box(Vector3(0.1, 0.62, 0.05), Vector3(1.1, 0.38, 0.5), col * 1.05)
			for i in 3:
				k.cylinder(Vector3(-0.6 + i * 0.4, 0, -0.6), 0.22, 0.08, col, 14)
		"gems":
			for p in [Vector3(0, 0, 0), Vector3(-0.35, 0, 0.15), Vector3(0.32, 0, -0.1), Vector3(0.1, 0, 0.35)]:
				var h := 0.9 if p == Vector3.ZERO else 0.6
				k.frustum(p, 0.18, 0.12, h, Color(0.55, 0.3, 0.85), 6)
				k.cone(p + Vector3(0, h, 0), 0.12, 0.25, Color(0.7, 0.5, 0.95), 6)
		"fish":
			for i in 2:
				var o := Vector3(0, 0.25 + i * 0.32, i * 0.15)
				k.sphere(o, 0.3, Color(0.55, 0.62, 0.66), 5, 10)
				k.box(o + Vector3(0.55, 0, 0), Vector3(0.6, 0.18, 0.12), Color(0.5, 0.58, 0.62))
				k.box(o + Vector3(0.95, 0, 0), Vector3(0.2, 0.45, 0.06), Color(0.45, 0.52, 0.56))
				k.box(o + Vector3(-0.22, 0.05, -0.26), Vector3(0.06, 0.06, 0.04), Color(0.08, 0.08, 0.08))
		"meat":
			k.sphere(Vector3(-0.15, 0.45, 0), 0.45, Color(0.62, 0.25, 0.2), 6, 12)
			k.log(Vector3(0.45, 0.45, 0), 0.08, 0.7, Color(0.92, 0.88, 0.8), Vector3.RIGHT)
			k.sphere(Vector3(0.8, 0.45, 0), 0.12, Color(0.92, 0.88, 0.8), 4, 8)
		"grain":
			for i in 14:
				var a := TAU * i / 14.0
				var off := Vector3(cos(a), 0, sin(a)) * 0.15
				k.log(Vector3(0, 0.7, 0) + off, 0.03, 1.4, Color(0.86, 0.72, 0.36), (Vector3(0, 1, 0) + off * 0.8).normalized())
				k.sphere(Vector3(0, 1.45, 0) + off * 3.0, 0.07, Color(0.92, 0.78, 0.4), 3, 6)
			k.cylinder(Vector3(0, 0.55, 0), 0.2, 0.12, Color(0.55, 0.4, 0.22), 10)
		"bread":
			k.sphere(Vector3(0, 0.35, 0), 0.6, Color(0.78, 0.52, 0.26), 6, 14)
			k.cylinder(Vector3(0, 0.0, 0), 0.58, 0.3, Color(0.7, 0.45, 0.22), 14)
			for i in 3:
				k.box(Vector3(-0.3 + i * 0.3, 0.9, 0), Vector3(0.06, 0.04, 0.6), Color(0.95, 0.82, 0.55))
		"ale":
			k.cylinder(Vector3(0, 0, 0), 0.42, 1.0, BuildingModels.WOOD, 14)
			k.cylinder(Vector3(0, 0.2, 0), 0.44, 0.08, BuildingModels.IRON, 14)
			k.cylinder(Vector3(0, 0.75, 0), 0.44, 0.08, BuildingModels.IRON, 14)
			k.sphere(Vector3(0, 1.0, 0), 0.4, Color(0.98, 0.95, 0.85), 4, 12)
			k.box(Vector3(0.55, 0.5, 0), Vector3(0.12, 0.6, 0.12), BuildingModels.WOOD)
		"wool":
			for p in [Vector3(-0.3, 0.3, 0), Vector3(0.3, 0.3, 0.1), Vector3(0, 0.7, 0)]:
				k.sphere(p, 0.4, Color(0.95, 0.93, 0.88), 6, 12)
		"cloth":
			for i in 4:
				k.box(Vector3(0, 0.12 + i * 0.22, 0), Vector3(1.4 - i * 0.05, 0.2, 0.9), Color(0.55, 0.42, 0.72) if i % 2 == 0 else Color(0.62, 0.5, 0.78))
		"furs":
			k.box(Vector3(0, 0.1, 0), Vector3(1.4, 0.12, 1.0), Color(0.5, 0.36, 0.24))
			k.box(Vector3(0, 0.25, 0), Vector3(1.0, 0.12, 0.7), Color(0.62, 0.46, 0.3))
			k.box(Vector3(0.8, 0.1, 0), Vector3(0.4, 0.12, 0.3), Color(0.5, 0.36, 0.24))
		"clay":
			k.frustum(Vector3(0, 0, 0), 0.4, 0.5, 0.6, Color(0.75, 0.48, 0.32), 14)
			k.frustum(Vector3(0, 0.6, 0), 0.5, 0.3, 0.3, Color(0.75, 0.48, 0.32), 14)
			k.frustum(Vector3(0, 0.9, 0), 0.3, 0.35, 0.15, Color(0.7, 0.44, 0.3), 14)
		"salt":
			k.frustum(Vector3(0, 0, 0), 0.5, 0.45, 0.8, Color(0.72, 0.64, 0.48), 12)
			k.cone(Vector3(0, 0.8, 0), 0.45, 0.4, Color(0.97, 0.97, 0.97), 12)
		"peat":
			for row in 3:
				for i in 2:
					k.box(Vector3(-0.3 + i * 0.6, 0.18 + row * 0.34, (row % 2) * 0.2), Vector3(0.55, 0.3, 0.8), Color(0.33, 0.24, 0.17) * (0.9 + 0.1 * row))
		"tar":
			k.barrel(Vector3(0, 0, 0), 0.5, 1.1)
			k.cylinder(Vector3(0, 1.1, 0), 0.45, 0.03, Color(0.06, 0.05, 0.04), 12)
		"amber":
			for p in [Vector3(0, 0.35, 0), Vector3(0.45, 0.2, 0.2), Vector3(-0.4, 0.22, 0.15)]:
				k.sphere(p, 0.3 if p.x == 0.0 else 0.2, Color(0.95, 0.55, 0.1), 5, 9)
		"tools":
			# A hammer and an axe, crossed.
			k.box(Vector3(0, 0.6, 0), Vector3(0.08, 1.4, 0.08), BuildingModels.PALE_WOOD, Vector3(0, 0, 0.6))
			k.box(Vector3(-0.38, 1.18, 0), Vector3(0.4, 0.2, 0.2), BuildingModels.IRON, Vector3(0, 0, 0.6))
			k.box(Vector3(0, 0.6, 0.1), Vector3(0.08, 1.4, 0.08), BuildingModels.PALE_WOOD, Vector3(0, 0, -0.6))
			k.box(Vector3(0.42, 1.12, 0.1), Vector3(0.1, 0.45, 0.3), BuildingModels.IRON, Vector3(0, 0, -0.6))
		"weapons":
			# A round shield with a sword across it.
			k.disc(Vector3(0, 0.7, 0.05), 0.65, Color(0.75, 0.2, 0.15), Vector3(0, 0, -1))
			k.box(Vector3(0, 0.7, -0.08), Vector3(0.1, 1.5, 0.04), Color(0.8, 0.82, 0.86), Vector3(0, 0, 0.7))
			k.box(Vector3(0.3, 0.32, -0.1), Vector3(0.35, 0.08, 0.06), Color(0.55, 0.45, 0.2), Vector3(0, 0, 0.7))
		"warriors":
			# A helmet with a nose guard, a spear behind.
			k.sphere(Vector3(0, 0.5, 0), 0.45, Color(0.6, 0.62, 0.66), 5, 12)
			k.cylinder(Vector3(0, 0.45, 0), 0.47, 0.1, Color(0.45, 0.46, 0.5), 14)
			k.box(Vector3(0, 0.35, -0.46), Vector3(0.08, 0.35, 0.05), Color(0.5, 0.52, 0.56))
			k.box(Vector3(0.6, 0.7, 0.2), Vector3(0.06, 1.6, 0.06), BuildingModels.PALE_WOOD)
			k.cone(Vector3(0.6, 1.5, 0.2), 0.08, 0.3, BuildingModels.IRON, 6)
		"influence":
			# A rune stone, carved and painted.
			k.box(Vector3(0, 0.75, 0), Vector3(0.7, 1.5, 0.3), BuildingModels.STONE)
			for i in 4:
				k.box(Vector3(0, 0.35 + i * 0.3, -0.16), Vector3(0.4 - 0.05 * (i % 2), 0.05, 0.02), Color(0.75, 0.18, 0.15))
			k.box(Vector3(0, 0.8, -0.16), Vector3(0.05, 1.1, 0.02), Color(0.75, 0.18, 0.15))
		"oak":
			# Squared oak timbers, the end grain showing.
			for i in 3:
				k.box(Vector3(0, 0.25 + (i / 2) * 0.5, -0.3 + (i % 2) * 0.6 + (i / 2) * 0.3), Vector3(1.8, 0.45, 0.5), Color(0.55, 0.4, 0.24) * (0.9 + 0.08 * i))
		"soapstone":
			# A carved soapstone bowl and a block.
			k.frustum(Vector3(-0.3, 0, 0), 0.35, 0.55, 0.45, Color(0.5, 0.56, 0.52), 12)
			k.cylinder(Vector3(-0.3, 0.44, 0), 0.42, 0.03, Color(0.3, 0.34, 0.31), 12)
			k.box(Vector3(0.55, 0.3, 0.2), Vector3(0.5, 0.6, 0.5), Color(0.52, 0.58, 0.54), Vector3(0, 0.4, 0))
		"reeds":
			# A tied bundle of reeds.
			for i in 16:
				var a := TAU * i / 16.0
				var off := Vector3(cos(a), 0, sin(a)) * (0.08 + 0.1 * float(i % 3))
				k.log(Vector3(0, 0.8, 0) + off, 0.03, 1.6, Color(0.74, 0.68, 0.42), (Vector3(0, 1, 0) + off * 0.5).normalized())
			k.cylinder(Vector3(0, 0.6, 0), 0.3, 0.1, Color(0.45, 0.35, 0.2), 10)
		"hides":
			# A folded stack of raw hides.
			for i in 3:
				k.box(Vector3(0, 0.1 + i * 0.16, 0), Vector3(1.4 - i * 0.15, 0.12, 0.9 - i * 0.1), Color(0.62, 0.46, 0.32) * (0.9 + 0.07 * i), Vector3(0, i * 0.25, 0))
		"horses":
			BuildingModels._horse(k, Vector3(0, 0, 0), 0.0)
		"ivory":
			# Two walrus tusks.
			for s2: float in [-1.0, 1.0]:
				k.cone(Vector3(s2 * 0.25, 0.1, 0), 0.14, 1.4, Color(0.94, 0.9, 0.8), 8)
		"stockfish":
			# Split dried fish tied in pairs.
			for i in 3:
				var o := Vector3(-0.5 + i * 0.5, 0.6, 0)
				k.box(o, Vector3(0.28, 1.1, 0.06), Color(0.78, 0.74, 0.6), Vector3(0, 0, 0.1 * (i - 1)))
				k.box(o + Vector3(0, -0.6, 0), Vector3(0.36, 0.2, 0.05), Color(0.72, 0.68, 0.55))
			k.log(Vector3(0, 1.2, 0), 0.03, 1.6, BuildingModels.DARK_WOOD, Vector3.RIGHT)
		"bar_iron":
			# Iron bars, stacked crosswise.
			for row in 2:
				for i in 3:
					var p := Vector3(-0.4 + i * 0.4, 0.12 + row * 0.22, 0) if row == 0 else Vector3(0, 0.12 + row * 0.22, -0.4 + i * 0.4)
					k.box(p, Vector3(0.22, 0.2, 1.3) if row == 0 else Vector3(1.3, 0.2, 0.22), Color(0.4, 0.41, 0.45))
		"leather":
			# A rolled hide of leather, tied.
			k.cylinder(Vector3(-0.7, 0.35, 0), 0.35, 1.4, Color(0.5, 0.32, 0.18), 14, Vector3.RIGHT)
			for x in [-0.3, 0.3]:
				k.cylinder(Vector3(x, 0.35, 0), 0.37, 0.06, Color(0.3, 0.2, 0.1), 14, Vector3.RIGHT)
		"clothing":
			# A folded tunic with a cloak over it, a brooch.
			k.box(Vector3(0, 0.15, 0), Vector3(1.3, 0.3, 1.0), Color(0.35, 0.5, 0.65))
			k.box(Vector3(0.1, 0.38, 0.05), Vector3(1.1, 0.16, 0.8), Color(0.62, 0.22, 0.16))
			k.sphere(Vector3(0.3, 0.5, -0.2), 0.12, Color(0.85, 0.66, 0.25), 4, 8)
		"pottery":
			# A jug and a bowl.
			k.frustum(Vector3(-0.3, 0, 0), 0.3, 0.45, 0.5, Color(0.7, 0.45, 0.3), 14)
			k.frustum(Vector3(-0.3, 0.5, 0), 0.45, 0.2, 0.35, Color(0.7, 0.45, 0.3), 14)
			k.frustum(Vector3(-0.3, 0.85, 0), 0.2, 0.25, 0.2, Color(0.66, 0.42, 0.28), 14)
			k.frustum(Vector3(0.55, 0, 0.2), 0.2, 0.42, 0.3, Color(0.74, 0.48, 0.32), 14)
		"oil":
			# A sealed cask of whale oil and a lamp.
			k.barrel(Vector3(-0.25, 0, 0), 0.45, 0.95)
			k.frustum(Vector3(0.65, 0, 0.1), 0.18, 0.28, 0.18, BuildingModels.IRON, 10)
			k.cone(Vector3(0.65, 0.18, 0.1), 0.06, 0.2, Color(1.0, 0.7, 0.2), 6)
		"arrows":
			# A sheaf of arrows in a quiver.
			k.frustum(Vector3(0, 0, 0), 0.25, 0.3, 0.9, Color(0.5, 0.32, 0.18), 12)
			for i in 7:
				var a := TAU * i / 7.0
				var o := Vector3(cos(a), 0, sin(a)) * 0.13
				k.log(Vector3(0, 1.1, 0) + o, 0.02, 1.0, BuildingModels.PALE_WOOD * 1.2, (Vector3.UP + o * 0.5).normalized())
				k.box(Vector3(0, 1.55, 0) + o * 1.3, Vector3(0.12, 0.2, 0.02), Color(0.9, 0.88, 0.82), Vector3(0, a, 0))
		"ship":
			# A little longship with a striped sail.
			for sd: float in [-1.0, 1.0]:
				for i in 8:
					var t0 := -1.0 + 2.0 * i / 8.0
					var t1 := -1.0 + 2.0 * (i + 1) / 8.0
					var h0 := 0.35 * (1.0 - t0 * t0)
					var h1 := 0.35 * (1.0 - t1 * t1)
					k.quad2(Vector3(t0, 0.3 + 0.3 * t0 * t0, sd * h0), Vector3(t1, 0.3 + 0.3 * t1 * t1, sd * h1), Vector3(t1, 0.05, sd * h1 * 0.3), Vector3(t0, 0.05, sd * h0 * 0.3), BuildingModels.WOOD)
			k.box(Vector3(0, 0.9, 0), Vector3(0.05, 1.3, 0.05), BuildingModels.DARK_WOOD)
			k.quad2(Vector3(-0.05, 1.45, -0.5), Vector3(-0.05, 1.45, 0.5), Vector3(-0.05, 0.6, 0.5), Vector3(-0.05, 0.6, -0.5), Color(0.75, 0.2, 0.15))
			k.quad2(Vector3(-0.06, 1.2, -0.5), Vector3(-0.06, 1.2, 0.5), Vector3(-0.06, 0.95, 0.5), Vector3(-0.06, 0.95, -0.5), Color(0.92, 0.88, 0.8))
		"jewellery":
			# An arm ring, a pair of oval brooches and a string of beads.
			for i in 10:
				var a := TAU * i / 10.0
				k.box(Vector3(cos(a) * 0.5, 0.08, sin(a) * 0.5), Vector3(0.12, 0.1, 0.34), Color(1.0, 0.8, 0.3), Vector3(0, -a, 0))
			for s2: float in [-1.0, 1.0]:
				k.sphere(Vector3(s2 * 0.18, 0.12, 0), 0.16, Color(0.85, 0.66, 0.25), 4, 10)
			for i in 7:
				k.sphere(Vector3(-0.45 + i * 0.15, 0.08, 0.55), 0.06, [Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.7), Color(0.95, 0.6, 0.15)][i % 3], 3, 6)
		_:
			k.box(Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), Color(0.6, 0.6, 0.6))
	return k.commit()
