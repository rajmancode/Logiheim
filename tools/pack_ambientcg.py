"""Pack ambientCG PBR sets into Logiheim's terrain layer textures.

Usage:
    python tools/pack_ambientcg.py <folder with the *_1K-JPG.zip downloads>

For each terrain layer this writes two PNGs to assets/textures/terrain/:
    <layer>_albedo.webp  RGB = colour,      A = height (displacement, for height blending)
    <layer>_normal.webp  RG  = normal (GL), B = ambient occlusion, A = roughness

Download the zips from https://ambientcg.com (CC0), e.g.
    https://ambientcg.com/get?file=Grass004_1K-JPG.zip
Needs numpy and pillow.
"""
import io
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

# Texture name -> ambientCG asset id. Order doesn't matter here; the game's texture array
# order is TerrainMaterial.TEXTURES.
LAYERS = {
    # Sand and shore
    "sand": "Ground054",
    "sand_dune": "Ground097",
    "sand_wet": "Ground100",
    "pebbles": "Rocks022",
    # Grass
    "grass": "Grass004",
    "grass_meadow": "Grass001",
    "grass_sparse": "Ground003",
    "moss": "Moss001",
    # Forest floor
    "forest_floor": "Ground037",
    "leaf_litter": "ScatteredLeaves008",
    "needles": "Ground042",
    # Rock
    "rock": "Rock051",
    "rock_cliff": "Rock030",
    "rock_mossy": "Rock063",
    "rock_dark": "Rock035",
    # Snow and ice
    "snow": "Snow006",
    "snow_rocky": "Snow014",
    "ice": "Ice003",
    # Earth
    "dirt": "Ground067",
    "mud": "Ground036",
    "soil": "Ground048",
    "gravel": "Gravel040",
    "ash": "Ground038",
    "lava": "Lava002",
    # Props
    "bark": "Bark014",
    "wood": "Wood049",
    # Wetlands, moor and upland
    "bog_moss": "Moss002",
    "swamp_mud": "Ground050",
    "heath": "Ground073",
    "dry_meadow": "Ground063",
    "tundra": "Ground086",
    "alpine": "Ground047",
    "roots": "Ground076",
    "sedge": "Grass002",
    "fen": "Ground074",
    "reeds": "ThatchedRoof001A",
}
SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures" / "terrain"


def read(z: zipfile.ZipFile, asset: str, kind: str, mode: str) -> np.ndarray:
    name = f"{asset}_1K-JPG_{kind}.jpg"
    if name not in z.namelist():
        return None
    img = Image.open(io.BytesIO(z.read(name))).convert(mode)
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(img)


def main() -> None:
    src = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    for layer, asset in LAYERS.items():
        with zipfile.ZipFile(src / f"{asset}_1K-JPG.zip") as z:
            color = read(z, asset, "Color", "RGB")
            height = read(z, asset, "Displacement", "L")
            normal = read(z, asset, "NormalGL", "RGB")
            ao = read(z, asset, "AmbientOcclusion", "L")
            rough = read(z, asset, "Roughness", "L")
        full = np.full((SIZE, SIZE), 255, np.uint8)
        height = height if height is not None else np.full((SIZE, SIZE), 128, np.uint8)
        ao = ao if ao is not None else full
        rough = rough if rough is not None else np.full((SIZE, SIZE), 200, np.uint8)
        albedo = np.dstack([color, height])
        nrm = np.dstack([normal[..., 0], normal[..., 1], ao, rough])
        # Lossy WebP (with alpha) keeps the repository small; detail survives at these settings.
        Image.fromarray(albedo, "RGBA").save(OUT / f"{layer}_albedo.webp", quality=90, alpha_quality=95, method=6)
        Image.fromarray(nrm, "RGBA").save(OUT / f"{layer}_normal.webp", quality=94, alpha_quality=95, method=6)
        print(f"{layer:13s} <- {asset}")


if __name__ == "__main__":
    main()
