class_name RiverPath
extends RefCounted
## One river segment: from a river hex's centre to its downstream hex (or into the sea).

## x, water surface y, z.
var points := PackedVector3Array()
## Water width in metres at each point.
var widths := PackedFloat32Array()
## Distance along the river from its source, in metres (drives the flow texture).
var dist := PackedFloat32Array()
var to_sea := false
