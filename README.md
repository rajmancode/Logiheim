# Logiheim

A hex strategy map built in **Godot 4.3+**, with terrain generated in **Gaea**.

Gaea exports a heightmap and terrain masks. Logiheim samples them onto a hex grid and draws a **realistic, soft-stepped landscape**. Every hex keeps its own height as a gentle terrace, so the board still reads as hexes, but the ground between them is continuous terrain with real relief, photo-scanned textures, carved rivers, a proper sea, forests, rocks and grass.

![The placeholder island at 20 m hexes: beaches, forests, a river in its carved channel](docs/images/preview_island.png)

![first_project from Gaea: grassland, rock and rivers on soft hex terraces](docs/images/preview_first_project.png)

## Features

- **Hex size:** set by `base_hex_size` in the settings (no longer changed in game; zooming out switches to the coarser, generalised levels).
- **Variable map size:** each map defines its own world size in metres, square or not. The grid fits itself to the map.
- **Soft-stepped terrain:** each hex has a plateau at its stepped height (`step_height`) that slopes smoothly into its neighbours (`step_softness`), with the real Gaea relief layered on top (`terrain_detail`). A final blur (`terrain_smoothing`) rounds off the terrace edges, and a slope limit (`max_slope`, about 51 degrees) cuts back anything steeper, so the ground is never a vertical wall (only waterfall faces are exempt). Rock overhangs — ledges of fractured slabs jutting from the steepest crests — with fallen boulders below them stand in for what a height grid can't do (`overhang_spacing`). The sea floor deepens offshore.
- **Multi-scale / LOD:** several hex scales (default ×1, ×3, ×8). The camera switches to coarser levels as you zoom out. Levels are linked parent ↔ children, so you can use them as regions in gameplay.
- **Photo-scanned textures:** 36 CC0 PBR sets from ambientCG (colour, height, normal, AO, roughness; see `assets/textures/terrain/CREDITS.md`). Each terrain layer has a family of textures chosen per pixel from moisture, height, slope, convexity, river beds, volcanic ground and farmland: grass is lush meadow, plain grass, sparse dry grass or upland moss; forest floor is leaf litter, plain or conifer needles; rock is granite, layered cliff, mossy or dark slate/basalt; sand is beach, dune, wet or pebble shingle; earth is dirt, mud, gravel scree, ploughed soil or volcanic ash; snow has rocky and icy patches. Grass also turns to heather moor, hay meadow or stony upland grass, forest floors show roots, and flat high rock becomes alpine stony ground. Lowland grass blooms into flower meadows. Textures are block-compressed in video memory. Boulders, tree bark, timber props and the lava pool use the same texture set. Layers mix by **height-based blending**, so grass grows between stones and sand fills cracks. Steep ground turns to rock, with scree and bare earth on the slopes below it. Bare rock also shows on ridges and crests, in broken patches on high ground, on sea cliffs down to the water, and as outcrops poking through grassy slopes. Beaches form at the waterline, dunes drift inland on low coasts, slow lowland rivers drop sand bars, and open grassland has worn dry patches. Textures follow the real landscape (`natural_texturing`) instead of painting each hex one colour, with large-scale variation to hide tiling.
- **Sea:** depth-coloured water using the depth buffer, refraction of the sea floor, wind-driven waves, foam lapping at the shoreline, whitecaps in strong wind and sky reflections.
- **Volcano:** only where a whole cone fits (land all round, even ground under it); otherwise the map has none. An inland volcanic cone (`volcano_count`, `volcano_radius`, `volcano_height`) with radial gullies, a crater holding a glowing, churning lava pool and a smoke plume drifting downwind. It is built before water is routed, so rivers run off its flanks. Around it the ground is basalt: dark bare rock and ash on the cone, old lava flows streaking out over the land, columnar jointing (tall prisms with dark joints) on steep faces, and dark basalt boulders.
- **Seeded:** everything procedural (lakes, fjords, volcano, river meanders, wetlands, resources, trails, caves, vegetation, props, animals) comes from the map seed (`seed`, the HUD's seed box, F5, or `--seed=N`). The same seed always builds the same world from the same Gaea terrain.
- **Caves** (`cave_count`): cave systems in the hills with one to three entrances each, holding silver, gems, iron, coal or soapstone (lava tubes on the volcano hold gems and silver). Each entrance is a dark arch in the rock face above a small ledge, framed by fractured rock; the overlay marks it as a cave and hovering shows it.
- **Trails** (`roads_enabled`, `road_spacing`, `road_width`): a network linking natural settlement spots (flat, dry ground near the coast, rivers and lakes), routed with A* around steep ground, rock, snow, wetland and water, merging where routes share a way, crossing rivers on wooden bridges. Trails are cut gently into the ground and drawn as packed earth and gravel with wheel ruts. Their hexes are marked (`level.road`) and halve the movement cost (`level.move_cost(i)`, shown when hovering a hex).
- **Fjords:** rivers that reach the sea through high ground can become fjords: long, narrow, curving sea inlets with a U-shaped trough and steep rock walls, widest at the mouth and narrowing to a rounded head, often with the river falling into it (`fjord_count`, `fjord_min_relief`, `fjord_length`, `fjord_width`, `fjord_depth`).
- **Arable land:** flat, low, fertile ground (best on floodplains) is farmed in irregular parcels like old field systems (noise-warped Voronoi cells), some split into long strips: ploughed furrows, young crops, ripening grain and hay meadow, each with its own furrow direction, with grassy margins and patchy hedgerows. Farm field props are irregular rounded plots.
- **Wetlands** (`wetland_amount`): flat, damp, soft ground, hollows that hold water and high flat plateaus become bog (sphagnum with heather hummocks) or, lower down, swamp and fen (sedge, fen grass, mud) with reed beds, reed clumps and dark pools of standing water that mirror the sky. Trees mostly stay out; farmland gives way.
- **Rivers and lakes:** water is routed over the actual terrain (a priority flood on a 10 m grid), so rivers follow real valleys, join into bigger rivers and collect in lakes where hollows fill up.
  - Width grows with the square root of the land draining into the river, like real rivers (`river_width_scale`). Rivers are born thin at their source and widen over the first few hundred metres. Courses wind naturally (an irregular wander everywhere, plus meanders on flat ground) and widen into estuaries at the sea. Rivers cut valleys: the land around them comes down to a floor just above the water, with walls rising to the surrounding ground (`valley_slope`, `valley_reach`). Where the ground drops away cliff-steep, the drop is gathered into a waterfall, white from lip to plunge pool, with spray at its foot (`waterfall_min_drop`). Wide rivers that reach the sea over low, flat land split into a delta of 2–4 distributaries (`delta_min_width`, `delta_height`, `delta_max_branches`).
  - Water runs in carved channels with muddy beds and banks, and its level never rises downstream, so rivers cut gorges instead of flowing uphill.
  - Flow speed follows the slope (flow-mapped, so fast and slow water never smear). Rapids appear where the real landscape is steep, and small cascades at each terrace step. Trees keep clear of the banks.
  - A Gaea `river` mask adds rivers wherever it is painted.
  - Besides natural hollows, `lake_count` extra lakes are made by damming flat river valleys behind a natural moraine, plus a highland tarn. A Gaea `lake` mask paints lakes exactly. Dams are shaped as sloping moraines, lake shores are smooth curves (a blurred lake mask, gently warped) rather than following the 10 m flow grid, and the lake water is built on the fine terrain grid so the shoreline is where the ground meets the water.
- **Floodplains:** flat, low land along big rivers is levelled into lush meadow on silt, with oxbow ponds. When it rains, the rivers flood: water spreads out from the river over the floodplain and drains away after (`flood` in the HUD). Floodplain hexes are flagged for gameplay and make the best farmland.
- **Natural resources (25, Norse-themed), as deposits:** each resource is a deposit that spans several hexes depending on how abundant it is. Forests and farmland cover many hexes, ore veins a few, gems one. Deposits are richest at their centre, rare finds keep apart, and every lake is one freshwater fishery (`resource_abundance`). No land resource sits on steep ground (over ~35 degrees). Props of different resources never overlap, but resources that naturally go together can share a hex (deer and furs in timber, sheep on farmland, peat with bog iron, coal beside iron ore, reeds on peat, clay or lake ore): the hover info and a second icon show the companion.
  - **Core:** timber, stone, iron ore, fish, farmland.
  - **Precious:** gold in river gravels below mountains, silver, gems, amber on beaches.
  - **Industry:** coal, clay on riverbanks, sea salt.
  - **Wildlife:** game, horses, furs in the cold uplands.
  - **Norse:** bog iron, ship oak, pine tar, soapstone, wool, seals & walrus ivory, whales, peat.
  - **Lakes and wetlands:** lake ore raked from lake beds, reed beds for thatch, freshwater fish.
  - Each shows in the world as a prop made in Blender (ore outcrops, quarry, tar kiln, bog pools, reed beds, salt pans, fish shoals, farm fields...), on every hex of the deposit, drawn larger than life so they read from the strategy camera (`resource_prop_scale`), with real surface detail: stone, sand and soil use the terrain's photo-scanned textures and wood gets a grain pattern. Herds graze the richer hexes.
  - The ground under a deposit is tinted (rusty soil over iron, golden stubble on farmland, pale salt crust...), fading out only at the deposit's outer edge, so a multi-hex deposit reads as one region.
  - A toggleable overlay shows one icon at each deposit's centre with its size in hexes, faint mini badges on its other hexes, and an outline around the whole deposit.
- **Animals (made in Blender):** Fjord horses, Norse sheep, red deer, reindeer, wild boar, red fox, harbour seals, walrus and humpback whales (`tools/blender/make_animals.py`).
  - Each is built from real body measurements: an anatomical skeleton with muscle masses (ribcage, belly, shoulders, haunches, head and jaw) sculpted with metaballs.
  - Each has a fur texture and fur normal map baked in Blender, and a rig with looping walk, graze and idle animations (whale: swim; seals: rest and galumph).
  - On the finest level every animal is alive (`scripts/map/animal_agent.gd`): it grazes, looks around and walks to new spots in its pasture across the terrain, avoiding water. Whales swim circles, and seals mostly rest on the shore. Animals far from the camera pause.
  - Coat colour varies per animal: dun, chestnut, bay and black horses, and white, cream, brown and black sheep.
- **Vegetation and rocks (made in Blender):** three conifer variants, two broadleaf trees, two bushes and five boulders (`tools/blender/make_vegetation.py`). Boulders and ore outcrops come from a shared rock generator (`tools/blender/rock_shapes.py`): fractured flat facets, Voronoi cracks, optional bedded strata and fine grain, with crevice AO baked in; in game they get photo-scanned rock with its normal map, lichen and moss. Forests mix conifers and broadleaf, with more conifers higher up. Trees and grass sway in the wind, leaves let light through, and rocks get moss on top. Dense grass (`grass_density`) is drawn near the camera only. Trees are 7–13 m (`tree_height`), so animals and props stay in proportion to them.
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
| F5 / Seed box / Random | New random seed / type a seed and press Enter (`--seed=N` on the command line) |

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
scripts/map/fjord_maker.gd         fjords: planned along high-coast rivers, cut into every level
scripts/map/volcano_maker.gd       volcano: cone, crater, basalt ground, lava pool and smoke
scripts/map/road_network.gd        trails: settlement spots, A* routes, cut into the ground, ribbons and bridges
scripts/map/rock_features.gd       rock overhangs on steep crests and the boulders fallen below them
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
shaders/resource_ground.gdshader   ground tint under resource deposits
shaders/lava.gdshader              molten lava in volcano craters
shaders/trail.gdshader             trails: earth, gravel, ruts, soft edges
shaders/farm_field.gdshader        farm fields
shaders/fish_shoal.gdshader        fish shoals
shaders/clouds.gdshader            cloud layer
shaders/include/environment.gdshaderinc  shared wind, cloud and wetness state (global shader parameters)
shaders/include/hex_grid.gdshaderinc     hex grid lines and highlights
tools/make_placeholder_terrain.py  placeholder Gaea exports (numpy, pillow)
tools/pack_ambientcg.py            packs ambientCG texture sets
tools/blender/make_vegetation.py   Blender script for trees, bushes and rocks
tools/blender/rock_shapes.py       shared Blender rock generator (boulders, outcrops)
tools/blender/make_resources.py    Blender script for resource props
tools/blender/make_animals.py      Blender script for the animals: anatomy, fur bake, rig, animations (+ animals.json)
tools/make_resource_icons.py       resource icon SVGs
```
