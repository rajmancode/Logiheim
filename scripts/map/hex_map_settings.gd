class_name HexMapSettings
extends Resource
## Tunable parameters for turning Gaea terrain into a hex map.

@export_group("Grid")
## Circumradius of the finest hexes, in metres.
@export_range(2.0, 500.0, 0.5, "suffix:m") var base_hex_size := 20.0
## Hex size multipliers for each level of detail. Level 0 is the finest.
@export var lod_factors := PackedFloat32Array([1.0, 3.0, 8.0])
## A coarser level becomes active when camera distance > its hex size * this factor.
@export var lod_distance_factor := 15.0
## Chunk edge length in hexes. Each chunk is one mesh, for frustum culling.
@export_range(4, 64) var chunk_size := 16

@export_group("Borders")
## How far hex outlines wobble, as a fraction of the hex size. 0 gives perfect hexagons.
@export_range(0.0, 0.3, 0.01) var border_noise := 0.13
## Points per hex edge for the wobble. Keep it even so rivers cross at an outline point.
@export_range(1, 8) var border_segments := 4

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
## A hex becomes river when the land draining through it exceeds this share of all land.
## Lower = more, smaller rivers. A "river" mask from Gaea adds rivers on top of this rule.
@export_range(0.001, 0.2, 0.001) var river_catchment := 0.012
## River width where it starts, as a fraction of the hex size.
@export_range(0.02, 0.5) var river_width := 0.14
## Widest a river can get, as a fraction of the hex size.
@export_range(0.05, 0.9) var river_max_width := 0.42

@export_group("Decoration")
@export var trees_enabled := true
## Rough spacing between trees on forest hexes, in metres.
@export var tree_spacing := 7.0
@export_range(1, 64) var max_trees_per_hex := 14
