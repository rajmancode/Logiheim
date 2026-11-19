"""Pack ambientCG PBR sets into Logiheim's terrain layer textures.

Usage:
    python tools/pack_ambientcg.py <folder with the *_1K-JPG.zip downloads>

For each terrain layer this writes two PNGs to assets/textures/terrain/:
    <layer>_albedo.png   RGB = colour,      A = height (displacement, for height blending)
    <layer>_normal.png   RG  = normal (GL), B = ambient occlusion, A = roughness

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

# Terrain layer -> ambientCG asset id.
LAYERS = {
    "sand": "Ground054",
    "grass": "Grass004",
    "forest_floor": "Ground037",
    "rock": "Rock051",
    "snow": "Snow006",
    "dirt": "Ground067",
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
        Image.fromarray(albedo, "RGBA").save(OUT / f"{layer}_albedo.png", optimize=True)
        Image.fromarray(nrm, "RGBA").save(OUT / f"{layer}_normal.png", optimize=True)
        print(f"{layer:13s} <- {asset}")


if __name__ == "__main__":
    main()
