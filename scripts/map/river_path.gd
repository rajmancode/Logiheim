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
