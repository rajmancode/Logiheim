class_name HexMapSettings
extends Resource
## Tunable parameters for turning Gaea terrain into a hex map.

## Map seed: the same seed always builds the same world from the same Gaea terrain; another
## seed gives other lakes, fjords, rivers' courses, wetlands, resources, trails, caves...
@export var seed := 1

@export_group("Grid")
## Circumradius of the finest hexes, in metres.
@export_range(2.0, 500.0, 0.5, "suffix:m") var base_hex_size := 20.0
## Hex size multipliers for each level of detail. Level 0 is the finest.
@export var lod_factors := PackedFloat32Array([1.0, 3.0, 8.0])
## A coarser level becomes active when camera distance > its hex size * this factor.
@export var lod_distance_factor := 15.0
## Chunk edge length in hexes. Each chunk is one mesh, for frustum culling.
@export_range(4, 64) var chunk_size := 16

@export_group("Terrain")
## Terrain vertices per hex size (5 m spacing for 20 m hexes at 4).
@export_range(1.0, 10.0, 0.5) var terrain_resolution := 4.0
## How far each hex's flat plateau blends into its neighbours, in hex sizes.
## About 1.0 gives hard-ish terraces, 1.6 smooth hills (the hex steps almost vanish).
@export_range(0.9, 2.0, 0.05) var step_softness := 1.5
## Blur passes over the finished terrain: rounds off terrace edges (0 = off).
@export_range(0, 8) var terrain_smoothing := 3
## Steepest the ground may be (rise/run; 1.25 is about 51 degrees). Steeper ground is cut back
## from the top. Waterfall faces are exempt. 0 = no limit.
@export_range(0.0, 3.0, 0.05) var max_slope := 1.25
## Island shape: land height above the sea is scaled by distance from the coast, from
## coast_height at the shore to inland_height `coast_reach` metres inland - low-lying coasts,
## hilly heart. 1 and 1 leave the Gaea terrain as it is.
@export_range(0.1, 1.5, 0.05) var coast_height := 0.3
@export_range(0.3, 2.0, 0.05) var inland_height := 0.5
@export var coast_reach := 400.0
## Rock overhangs jutting from the steepest crests, at most one per this many metres (0 = none).
@export var overhang_spacing := 90.0
## How much of the real Gaea relief shows inside each hex (0 = flat plateaus).
@export_range(0.0, 1.5, 0.05) var terrain_detail := 0.5
## Sea floor depth in metres right off the coast, and how much it deepens per metre offshore.
@export var seabed_depth := 2.5
@export var seabed_slope := 0.06
## Rise/run above which the ground turns to bare rock.
@export var cliff_slope := 0.85
## How much ground textures follow the real landscape (Gaea masks, height, slope) instead of
## each hex's single terrain type. 0 = one texture per hex, 1 = fully natural.
@export_range(0.0, 1.0, 0.05) var natural_texturing := 0.65

@export_group("Borders")
## How far hex borders wobble, as a fraction of the hex size. 0 gives perfect hexagons.
@export_range(0.0, 0.3, 0.01) var border_noise := 0.13

@export_group("Elevation")
## Vertical exaggeration applied to the Gaea height range.
@export_range(0.1, 10.0, 0.05) var height_scale := 1.0
## Height of one elevation step (stepped tiles), in metres.
@export_range(0.5, 100.0, 0.5, "suffix:m") var step_height := 6.0

@export_group("Classification")
## Normalised sea level used when map.json does not define one.
@export_range(0.0, 1.0) var sea_level := 0.3
## Normalised depth below sea level that counts as deep water (no deep_water mask).
@export_range(0.0, 1.0) var shallow_depth := 0.04
## Normalised height above sea level that counts as beach (no sand mask).
@export_range(0.0, 1.0) var beach_height := 0.02
## Normalised height above which land is snow (no snow mask).
@export_range(0.0, 1.0) var snow_level := 0.8
## Rise/run above which land is rock (no rock mask). 0.75 is about 37 degrees.
@export var rock_slope := 0.75
## Average mask value above which a hex takes that mask's terrain.
@export_range(0.0, 1.0) var mask_threshold := 0.45
## Share of open, gentle land that becomes forest when the map has no forest mask (0 = none).
@export_range(0.0, 1.0) var forest_fallback := 0.45

@export_group("Rivers")
@export var rivers_enabled := true
## A river starts where the land draining into a point exceeds this share of all land.
## Lower = more, smaller streams. A "river" mask from Gaea adds rivers on top of this rule.
@export_range(0.0005, 0.1, 0.0005) var river_catchment := 0.006
## River width in metres where 1 km^2 drains into it. Width grows with the square root of
## the catchment, like real rivers (a river draining 4 km^2 is twice as wide).
@export_range(1.0, 60.0, 0.5) var river_width_scale := 30.0
@export_range(1.0, 20.0, 0.5) var river_min_width := 1.2
@export_range(5.0, 200.0, 1.0) var river_max_width := 80.0
## On coarse levels rivers are drawn at least this fraction of the hex size wide, so they
## stay readable from far away.
@export_range(0.0, 0.3, 0.01) var river_min_width_per_hex := 0.06
## How much rivers wind on flat ground (1 = natural meanders about 12 widths long).
@export_range(0.0, 2.0, 0.05) var river_meander := 1.0
## Rivers at least this wide (m) that reach the sea over low land split into a delta.
@export var delta_min_width := 10.0
## Land up to this many metres above the sea counts as delta plain (the first hex terrace
## above the sea is one step_height up).
@export var delta_height := 8.0
@export_range(2, 6) var delta_max_branches := 4
## Where the ground under a river drops at least this many metres, cliff-steep, within ~15 m,
## the drop is gathered into one waterfall (0 = no waterfalls). Falls are kept 150 m apart.
@export var waterfall_min_drop := 8.0
## Valleys: rivers cut the land around them down to a floor just above the water, with walls
## rising this steeply (rise/run) up to the surrounding ground, within valley_reach metres.
@export var valley_slope := 0.4
@export var valley_reach := 220.0
## Hollows at least this big and deep fill up as lakes.
@export var lake_min_area := 8000.0
@export var lake_min_depth := 2.0
## Extra lakes made by damming flat river valleys (plus one highland tarn), on top of natural
## hollows and any Gaea "lake" mask. 0 = none.
@export_range(0, 12) var lake_count := 3
## Rough size of each generated lake, m^2 (tarns are half this).
@export var lake_target_area := 40000.0

@export_group("Fjords")
## Long, steep-sided sea inlets cut along rivers that reach the sea through high ground.
@export_range(0, 8) var fjord_count := 2
## Banks must stand at least this high (m above the sea) on average for a fjord.
@export var fjord_min_relief := 18.0
@export var fjord_length := 650.0
## Width at the mouth (narrows towards the head) and depth below the sea, metres.
@export var fjord_width := 80.0
@export var fjord_depth := 22.0

@export_group("Trails")
## A network of trails between natural settlement spots; units move faster along them.
@export var roads_enabled := true
## Rough distance between settlement spots, and trail width, metres.
@export var road_spacing := 260.0
@export var road_width := 3.5

@export_group("Caves")
## Cave systems in the hills (1-3 entrances each), holding ore, coal, silver or gems.
@export_range(0, 10) var cave_count := 3
@export_group("Landforms")
## Coastal landforms (beaches, cliffs, sea stacks, spits, a lagoon, a tombolo, an atoll) and
## oxbow lakes, each only where the map has room for it.
@export var landforms_enabled := true

@export_group("Wetlands")
## How much bog, swamp and fen forms on flat, damp ground (0 = none).
@export_range(0.0, 2.0, 0.05) var wetland_amount := 1.0

@export_group("Volcano")
## Volcanic cones placed inland, with a crater, lava, smoke and basalt around them.
@export_range(0, 3) var volcano_count := 1
@export var volcano_radius := 380.0
@export var volcano_height := 105.0

@export_group("Floodplains")
@export var floodplains_enabled := true
## Only rivers at least this wide (m) have floodplains.
@export var floodplain_min_width := 6.0
## How far a floodplain reaches from the river, in river widths.
@export var floodplain_reach := 9.0
## Land up to this many metres above the river can flood.
@export var floodplain_depth := 3.5
## One oxbow pond per this many m^2 of floodplain.
@export var floodplain_pond_every := 40000.0

@export_group("Resources")
@export var resources_enabled := true
## Multiplies how often every resource appears (2 = twice as many).
@export_range(0.0, 4.0, 0.05) var resource_abundance := 1.0
## Props are drawn this much larger than life on the finest level (and more on coarser
## levels) so they read from the strategy camera.
@export_range(1.0, 5.0, 0.1) var resource_prop_scale := 1.8

@export_group("Vegetation")
@export var trees_enabled := true
## Rough spacing between trees on forest hexes, in metres.
@export var tree_spacing := 5.0
@export_range(1, 128) var max_trees_per_hex := 64
## Real tree height range in metres (scaled up a little on coarse levels so they stay readable).
@export var tree_height := Vector2(7.0, 13.0)
@export var rocks_enabled := true
@export var grass_enabled := true
## Grass clumps per square metre on grassy ground (finest level only).
@export_range(0.0, 2.0, 0.01) var grass_density := 0.6
## Grass is drawn only this close to the camera, in metres.
@export var grass_view_distance := 260.0
