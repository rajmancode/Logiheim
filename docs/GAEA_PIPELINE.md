# Gaea → Logiheim pipeline

Gaea makes the terrain. Logiheim reads what Gaea exports and turns it into hex tiles. Gaea runs only on Windows, so this repo includes placeholder exports (`tools/make_placeholder_terrain.py`). That lets the game run before you have real maps.

## Folder layout

Each map is a folder under `data/gaea/`. Any folder that contains a `map.json` appears in the game; press **M** to cycle through them.

```
data/gaea/my_map/
  map.json
  heightmap.r16        # or .r32 / .exr / .png
  water.png            # optional masks, 8-bit grayscale, any resolution
  sand.png
  rock.png
  snow.png
  forest.png
  river.png            # optional, adds rivers where it is painted
  lake.png             # optional, paints lakes exactly
  res_iron.png         # optional, forces a resource (res_<key>, see below)
```

## map.json

```json
{
  "name": "My Map",
  "world_size": [4096, 2048],
  "height_range": 400,
  "sea_level": 0.22,
  "heightmap": { "file": "heightmap.r16", "format": "r16", "width": 2048, "height": 1024 },
  "masks": { "water": "water.png", "sand": "sand.png", "rock": "rock.png", "snow": "snow.png", "forest": "forest.png" }
}
```

| Field | Meaning |
|---|---|
| `world_size` | Map size in metres, `[x, z]`. This is how you get **variable map sizes**: it can differ from the pixel size, and the map doesn't have to be square. Match it to the terrain size you set in Gaea. |
| `height_range` | How many metres a height value of 1.0 represents. Use the height setting from your Gaea project. |
| `sea_level` | Normalised (0–1) water line. Optional; if it's missing, `HexMapSettings.sea_level` is used. |
| `heightmap.format` | `r16` (16-bit unsigned, little-endian), `r32` (32-bit float), or any image Godot can load (`exr`, `png`). For raw files, also give `width`/`height`; if you leave them out the map is assumed square. Add `"endian": "big"` if needed. For floats outside 0–1, add `"min"`/`"max"`. |
| `masks` | Optional. Recognised names: `water`, `deep_water`, `sand`, `rock`, `snow`, `forest`, `dirt`, `river`, `lake`, and `res_<key>` for resources. |

Use a 16-bit or float heightmap. Godot reduces 16-bit PNGs to 8 bits when it loads them, which produces visible banding.

## What to export from Gaea

1. **Heightmap.** Export the final terrain in a 16-bit raw format (`.r16`/`.raw`) or 32-bit (`.r32`/`.exr`). Row 0 of the image is the map's north edge (world z = 0).
2. **Masks.** Connect data/selector nodes to their own export (output) nodes, and export each one as an 8-bit grayscale PNG. Mask values go from 0 to 1, and a hex counts as that terrain when its average mask value is above `mask_threshold` (default 0.45). Useful sources:
   - `water`: a height selector below sea level, or the result of a lake/sea node.
   - `rock`: a slope selector, or erosion *wear*/*deposits* data inverted.
   - `snow`: Gaea's snow node output, or a height selector near the peaks.
   - `sand`: a narrow height band just above sea level, or erosion deposits near the shore.
   - `forest`: soil/flow/moisture-style data, minus rock and snow.
   - `river` (optional): a Flow / Rivers node output. Logiheim treats it as extra rain, so rivers form where it is bright. Logiheim works out rivers from the heightmap on its own, so you only need this to force rivers where you want them.
3. Make every export cover the **same area**. The resolutions can differ.

Node and format names vary between Gaea versions, so treat the list above as intent rather than exact menu paths.

Any mask you leave out falls back to a height or slope rule in `HexMapSettings` (sea level, beach height, snow level, rock slope). A heightmap on its own already gives a playable map.

## How a hex gets its data

- **Finest level (level 0):** the heightmap and masks are sampled at the hex centre plus six points 60% of the way to the corners. Height is the average of those samples, slope is the sample range divided by the hex width, and each mask is averaged.
- **Classification order:** water → snow → rock → sand → forest → dirt → grass. If a mask exists it decides; otherwise the fallback rule does.
- **Elevation:** `round(height × height_range × height_scale / step_height)`. Water sits flat at sea level, and land is always at least one step above it.
- **Rivers and lakes** (`scripts/map/hydrology.gd`): water is routed over the finest level's terrain on a 10 m grid. A priority flood from the sea and the map edge gives every point one downstream neighbour and fills hollows to their spill level. Hollows larger than `lake_min_area` and deeper than `lake_min_depth` become lakes. Catchment then accumulates downstream, and a river starts wherever it passes `river_catchment` × the total land area.
  - The courses are smoothed and given meanders on flat ground, and tributaries end exactly on the river they join. The same courses are used on every level.
  - Width = `river_width_scale` × √(catchment in km²), between `river_min_width` and `river_max_width`. Coarse levels draw rivers at least `river_min_width_per_hex` × the hex size wide.
  - A hex is marked as river (`level.river`, `level.river_width`) where a river passes through it, and as lake (`level.lake`) when its centre is under a lake. `level.downstream` / `level.flow` still give hex-to-hex drainage for gameplay.
- **Extra lakes** (`scripts/map/lake_maker.gd`): `lake_count` lakes are added by damming the flattest river valleys (raising an imaginary dam until the lake reaches `lake_target_area`), including one highland tarn. A `lake` mask lakes the painted area (water covers about 85% of it). The ground is deepened inside the basin and raised into a natural dam wherever the water would spill, so rivers flow in and out of these lakes like natural ones.
- **Floodplains** (`scripts/map/floodplain.gd`): land next to rivers at least `floodplain_min_width` wide, within `floodplain_reach` river widths and no more than `floodplain_depth` m above the water, is levelled into a flat valley floor with oxbow ponds. Each terrain vertex stores its floodplain strength and river level, and the terrain shader paints floodwater where the ground lies below river level + `flood` × depth. `flood` is a global shader parameter that Atmosphere raises during rain. `level.floodplain` flags the hexes.
- **Resources** (`scripts/map/natural_resources.gd`): resources come as deposits. A seed hex is chosen by rules on terrain, height, slope, rivers, lakes, floodplains, coast and open sea. The deposit then grows over neighbouring suitable hexes to a size range per kind (`INFO`), and is richest at its centre. Rare kinds are placed first and keep a minimum distance from each other. Every lake becomes one fish deposit. `level.deposit` gives each hex's deposit index and `level.deposits` lists them. To force one, paint a mask named `res_<key>`. The keys are `timber, oak, tar, stone, soapstone, iron, bog_iron, coal, gold, silver, gems, fish, whales, seals, farmland, wool, horses, game, furs, clay, salt, peat, amber, reeds, lake_ore`. Each connected painted patch becomes one deposit. Data is in `level.resource` and `level.resource_amount` (1–3).
- **Coarser levels:** each coarse hex takes the majority terrain of the finest hexes inside it and their mean land height. Every level stores `parent` and `children` links to the next level, so gameplay can move between scales (a region contains tiles, for example).

## Exporting the game

Godot only packs files it recognises as resources, so add `*.json, *.r16, *.r32` to **Export → Resources → Filters to export non-resource files**. PNG/EXR masks are imported as textures and packed automatically.
