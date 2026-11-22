class_name RiverPath
extends RefCounted
## One stretch of river placed on a level: from a source, junction or lake outlet down to the
## sea, a lake, the map edge or the river it joins.

## x, water surface y, z.
var points := PackedVector3Array()
## Water width in metres at each point.
var widths := PackedFloat32Array()
## Distance along the river in metres (drives the flow texture).
var dist := PackedFloat32Array()
## Flow speed in m/s at each point (from the slope).
var speeds := PackedFloat32Array()
## 0 calm .. 1 white water (rapids, falls).
var turbulence := PackedFloat32Array()
var to_sea := false
## The lake this stretch runs into at its end / out of at its start (-1: none), and that lake's
## water level. The ribbon reaches a little way into the lake there and blends into its water.
var lake_in := -1
var lake_out := -1
var lake_in_y := 0.0
var lake_out_y := 0.0
## Indices of points where a waterfall starts (the fall runs to the next point).
var falls := PackedInt32Array()
