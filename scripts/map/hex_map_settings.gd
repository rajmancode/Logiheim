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

@export_group("Decoration")
@export var trees_enabled := true
## Rough spacing between trees on forest hexes, in metres.
@export var tree_spacing := 7.0
@export_range(1, 64) var max_trees_per_hex := 14
