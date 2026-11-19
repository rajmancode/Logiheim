# Logiheim

A hex strategy map built in **Godot 4.3+**, with terrain generated in **Gaea**.

Gaea exports a heightmap and terrain masks. Logiheim samples them onto a hex grid and draws **stepped 3D hex tiles** with textures.

![Top-down preview of the placeholder island at 20 m hexes](docs/images/preview_island.png)

## Features

- **Adjustable hex size:** `base_hex_size` (or `[` / `]` in game) rebuilds the grid at any scale.
- **Variable map size:** each map defines its own world size in metres, square or not. The grid fits itself to the map.
- **Hex heights from terrain:** every hex is a prism whose height comes from the Gaea heightmap, quantised to `step_height`. Cliff walls are drawn only where a neighbouring hex is lower.
- **Multi-scale / LOD:** several hex scales (default ×1, ×3, ×8). The camera switches to coarser levels as you zoom out. Levels are linked parent ↔ children, so you can use them as regions in gameplay.
- **Textures:** triplanar texture arrays with one layer per terrain type, normal maps, macro variation to hide tiling, cliff walls that go from soil to rock with fake AO, animated water, grid lines, and hover/selection highlights.
- **Forests:** low-poly conifers placed with a MultiMesh.

## Getting started

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (the standard build, not .NET).
2. Open `project.godot` and press **F5**.
3. Two placeholder maps are included (an island and a non-square valley). Press **M** to switch between them.

| Input | Action |
|---|---|
| WASD / arrows / middle-drag | Pan |
| Mouse wheel | Zoom (switches LOD automatically) |
| Q / E / right-drag | Rotate |
| Left click | Select hex (shows coords, terrain, elevation, parent/children) |
| `[` `]` | Smaller / larger hexes |
| `-` `=` | Vertical exaggeration |
| `1`–`5` / `0` | Force a LOD level / automatic LOD |
| G / T / H | Toggle grid / trees / HUD |

## Using your own Gaea maps

See **[docs/GAEA_PIPELINE.md](docs/GAEA_PIPELINE.md)**. In short, export a 16-bit heightmap and some grayscale masks into `data/gaea/<map>/`, then add a `map.json`.

## Better textures

The textures in `assets/textures/terrain/` are procedural placeholders made by `tools/make_terrain_textures.py`. To use real ones, replace them with CC0 PBR sets (for example from ambientCG or Poly Haven). Keep the same names, `<layer>_albedo.jpg` and `<layer>_normal.png`, and use OpenGL-style (`NormalGL`) normal maps. The layers are `sand, grass, forest_floor, rock, snow, dirt`. They're loaded at 512² into a texture array; change `TerrainMaterial.LAYER_SIZE` for higher resolution.

## Project layout

```
scripts/hex/hex_coords.gd          axial hex math (pointy-top)
scripts/map/terrain_source.gd      loads map.json, heightmap and masks
scripts/map/hex_map_settings.gd    all tunables (Resource)
scripts/map/hex_map_generator.gd   sampling, classification, LOD aggregation, parent links
scripts/map/hex_level.gd           one hex grid's cell data
scripts/map/hex_mesh_builder.gd    chunked stepped-prism meshes
scripts/map/terrain_material.gd    texture arrays and shader setup
scripts/map/tree_scatter.gd        forest MultiMesh
scripts/map/hex_map.gd             HexMap node: build, LOD switching, picking, highlights
scripts/camera/strategy_camera.gd  RTS camera
scripts/main.gd                    demo scene, HUD and controls
shaders/hex_terrain.gdshader       terrain shader
tools/                             Python generators for placeholder data (numpy, pillow)
```
