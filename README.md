# Logiheim

A hex strategy map built in **Godot 4.3+**, with terrain generated in **Gaea**.

Gaea exports a heightmap and terrain masks. Logiheim samples them onto a hex grid and draws a **realistic, soft-stepped landscape**. Every hex keeps its own height as a gentle terrace, so the board still reads as hexes, but the ground between them is continuous terrain with real relief, photo-scanned textures, carved rivers, a proper sea, forests, rocks and grass.

![The placeholder island at 20 m hexes: beaches, forests, a river in its carved channel](docs/images/preview_island.png)

![first_project from Gaea: grassland, rock and rivers on soft hex terraces](docs/images/preview_first_project.png)

## Features

- **Adjustable hex size:** `base_hex_size` (or `[` / `]` in game) rebuilds the grid at any scale.
- **Variable map size:** each map defines its own world size in metres, square or not. The grid fits itself to the map.
- **Soft-stepped terrain:** each hex has a plateau at its stepped height (`step_height`) that slopes smoothly into its neighbours (`step_softness`), with the real Gaea relief layered on top (`terrain_detail`). The sea floor deepens offshore.
- **Multi-scale / LOD:** several hex scales (default ×1, ×3, ×8). The camera switches to coarser levels as you zoom out. Levels are linked parent ↔ children, so you can use them as regions in gameplay.
- **Photo-scanned textures:** CC0 PBR sets from ambientCG (colour, height, normal, AO, roughness). Layers mix by **height-based blending**, so grass grows between stones and sand fills cracks. Steep ground turns to rock, and beaches form at the waterline. Textures follow the real landscape (`natural_texturing`) instead of painting each hex one colour, with large-scale variation to hide tiling.
- **Sea:** depth-coloured water using the depth buffer, refraction of the sea floor, wind-driven waves, foam lapping at the shoreline, whitecaps in strong wind and sky reflections.
- **Rivers and lakes:** water is routed over the actual terrain (a priority flood on a 10 m grid), so rivers follow real valleys, join into bigger rivers and collect in lakes where hollows fill up.
  - Width grows with the square root of the land draining into the river, like real rivers (`river_width_scale`). Rivers meander on flat ground and widen into estuaries at the sea.
  - Water runs in carved channels with muddy beds and banks, and its level never rises downstream, so rivers cut gorges instead of flowing uphill.
  - Flow speed follows the slope (flow-mapped, so fast and slow water never smear). Rapids appear where the real landscape is steep, and small cascades at each terrace step. Trees keep clear of the banks.
  - A Gaea `river` mask adds rivers wherever it is painted.
  - Besides natural hollows, `lake_count` extra lakes are made by damming flat river valleys behind a natural moraine, plus a highland tarn. A Gaea `lake` mask paints lakes exactly.
- **Floodplains:** flat, low land along big rivers is levelled into lush meadow on silt, with oxbow ponds. When it rains, the rivers flood: water spreads out from the river over the floodplain and drains away after (`flood` in the HUD). Floodplain hexes are flagged for gameplay and make the best farmland.
- **Natural resources (25, Norse-themed), as deposits:** each resource is a deposit that spans several hexes depending on how abundant it is. Forests and farmland cover many hexes, ore veins a few, gems one. Deposits are richest at their centre, rare finds keep apart, and every lake is one freshwater fishery (`resource_abundance`).
  - **Core:** timber, stone, iron ore, fish, farmland.
  - **Precious:** gold in river gravels below mountains, silver, gems, amber on beaches.
  - **Industry:** coal, clay on riverbanks, sea salt.
  - **Wildlife:** game, horses, furs in the cold uplands.
  - **Norse:** bog iron, ship oak, pine tar, soapstone, wool, seals & walrus ivory, whales, peat.
  - **Lakes and wetlands:** lake ore raked from lake beds, reed beds for thatch, freshwater fish.
  - Each shows in the world as a prop made in Blender (ore outcrops, quarry, tar kiln, bog pools, reed beds, salt pans, fish shoals, farm fields...), plus a toggleable icon overlay. Each deposit gets one icon at its centre showing its size in hexes, with faint mini badges on its other hexes.
- **Animals (made in Blender):** Fjord horses, Norse sheep, red deer, reindeer, wild boar, red fox, harbour seals, walrus and humpback whales (`tools/blender/make_animals.py`).
  - Each is built from real body measurements: an anatomical skeleton with muscle masses (ribcage, belly, shoulders, haunches, head and jaw) sculpted with metaballs.
  - Each has a fur texture and fur normal map baked in Blender, and a rig with looping walk, graze and idle animations (whale: swim; seals: rest and galumph).
  - On the finest level every animal is alive (`scripts/map/animal_agent.gd`): it grazes, looks around and walks to new spots in its pasture across the terrain, avoiding water. Whales swim circles, and seals mostly rest on the shore. Animals far from the camera pause.
  - Coat colour varies per animal: dun, chestnut, bay and black horses, and white, cream, brown and black sheep.
- **Vegetation and rocks (made in Blender):** three conifer variants, two broadleaf trees, two bushes and four chiselled boulders (`tools/blender/make_vegetation.py`). Forests mix conifers and broadleaf, with more conifers higher up. Trees and grass sway in the wind, leaves let light through, and rocks get moss on top. Dense grass (`grass_density`) is drawn near the camera only.
- **Hex grid:** drawn by the shaders with irregular, noise-wobbled borders (`border_noise`). The CPU uses the same noise for picking, so what you click is exactly what's outlined. Hover and selection highlights work the same way.
- **Atmosphere:** day/night cycle with sun and moon, drifting clouds that cast moving shadows, wind that drives trees, waves and clouds together, and weather (clear, cloudy, rain) with wet ground, fog and the odd lightning flash.

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
| G / T / H | Toggle grid / trees & bushes / HUD |
| N | Pause / run the day cycle |
| `,` `.` | Time of day −1 h / +1 h |
| R | Weather: clear → cloudy → rain |
| I | Resource icons on / off |

## Using your own Gaea maps

See **[docs/GAEA_PIPELINE.md](docs/GAEA_PIPELINE.md)**. In short, export a 16-bit heightmap and some grayscale masks into `data/gaea/<map>/`, then add a `map.json`.

## Textures and models

- **Terrain textures** come from [ambientCG](https://ambientcg.com) (CC0, see `assets/textures/terrain/CREDITS.md`). To swap one, download another 1K-JPG set, change the asset id in `tools/pack_ambientcg.py` and run `python tools/pack_ambientcg.py <download folder>`. Each layer is packed into `<layer>_albedo.png` (RGB colour + height) and `<layer>_normal.png` (NormalGL + AO + roughness).
- **Trees, bushes and rocks** are generated in Blender: `blender -b --python tools/blender/make_vegetation.py -- assets/models/vegetation`. Any `.glb` with materials named `Bark`, `Leaves` or `Rock` (and vertex-colour AO) can replace them.

## Project layout

```
scripts/hex/hex_coords.gd          axial hex math (pointy-top)
scripts/map/terrain_source.gd      loads map.json, heightmap and masks
scripts/map/hex_map_settings.gd    all tunables (Resource)
scripts/map/hex_map_generator.gd   sampling, classification, LOD aggregation, parent links
scripts/map/hex_level.gd           one hex grid's cell data
scripts/map/terrain_surface.gd     soft-stepped height grid, river carving, texture weights
scripts/map/terrain_mesh_builder.gd chunked terrain meshes
scripts/map/border_noise.gd        irregular hex borders (same noise as the shaders)
scripts/map/hydrology.gd           water flow on the terrain grid: drainage, catchment, lakes, river tracing
scripts/map/river_network.gd       hex-level drainage for gameplay (downstream, flow)
scripts/map/river_mesh_builder.gd  river courses (meanders, junctions), placement per level, river and lake meshes
scripts/map/river_path.gd          one placed river stretch
scripts/map/lake_maker.gd          extra lakes: dammed valleys, tarns, Gaea lake mask
scripts/map/natural_resources.gd   resource types, placement rules, multi-hex deposits
scripts/map/floodplain.gd          floodplains: detection, levelling, oxbow ponds
scripts/map/animal_agent.gd        living animals: graze / idle / walk routine, terrain following
scripts/map/resource_props.gd      resource props, farm fields and fish shoals in the world
scripts/map/terrain_material.gd    PBR texture arrays and per-level material setup
scripts/map/vegetation.gd          trees, bushes and rocks (MultiMesh, chunked)
scripts/map/grass_field.gd         grass near the camera
scripts/map/hex_map.gd             HexMap node: build, LOD switching, picking, highlights
scripts/env/atmosphere.gd          sky, sun/moon, day cycle, weather, wind, clouds, rain
scripts/camera/strategy_camera.gd  RTS camera
scripts/main.gd                    demo scene, HUD and controls
shaders/hex_terrain.gdshader       terrain: height-blended PBR layers, grid, highlights
shaders/water.gdshader             sea: depth colour, refraction, waves, shore foam
shaders/river.gdshader             river water: flow mapping, depth colour, rapids
shaders/tree_wind.gdshader         swaying trees and bushes
shaders/rock.gdshader              boulders with moss
shaders/grass.gdshader             grass blades
shaders/resource_prop.gdshader     resource props (glints on gold, silver, gems, amber)
shaders/farm_field.gdshader        farm fields
shaders/fish_shoal.gdshader        fish shoals
shaders/clouds.gdshader            cloud layer
shaders/include/environment.gdshaderinc  shared wind, cloud and wetness state (global shader parameters)
shaders/include/hex_grid.gdshaderinc     hex grid lines and highlights
tools/make_placeholder_terrain.py  placeholder Gaea exports (numpy, pillow)
tools/pack_ambientcg.py            packs ambientCG texture sets
tools/blender/make_vegetation.py   Blender script for trees, bushes and rocks
tools/blender/make_resources.py    Blender script for resource props
tools/blender/make_animals.py      Blender script for the animals: anatomy, fur bake, rig, animations (+ animals.json)
tools/make_resource_icons.py       resource icon SVGs
```
