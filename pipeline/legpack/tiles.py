"""Imagery stage: Sentinel-2 cloudless 2016 Web Mercator tiles (CC BY 4.0) covering the leg bounds.

Writes <out>/tiles/<z>/<x>/<y>.jpg for zoom levels Z_MIN..Z_MAX and <out>/tiles.json. Levels up to
BACKDROP_Z_MAX also cover a wider backdrop box around the leg, so a zoomed-out view fills the screen.
Depth shading is drawn by the game from depth.bin, so it is not baked into the tiles.
"""
import io
import json
import math
import time
import urllib.request

from PIL import Image

URL = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/{z}/{y}/{x}.jpg"
CREDIT = ("Imagery: EOxCloudless 2016 by EOX IT Services GmbH, https://cloudless.eox.at "
          "(contains modified Copernicus Sentinel data 2016), CC BY 4.0")
Z_MIN, Z_MAX = 6, 12
BACKDROP_Z_MAX = 10


def backdrop(b):
    """The leg bounds widened on every side by the larger of their two spans, in degrees."""
    pad = max(b["lat_max"] - b["lat_min"], b["lon_max"] - b["lon_min"])
    return {"lat_min": b["lat_min"] - pad, "lat_max": b["lat_max"] + pad,
            "lon_min": b["lon_min"] - pad, "lon_max": b["lon_max"] + pad}


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = int((lon + 180) / 360 * n)
    y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
    return x, y


def build(leg, root, out):
    count = 0
    wide = backdrop(leg["bounds"])
    for z in range(Z_MIN, Z_MAX + 1):
        b = wide if z <= BACKDROP_Z_MAX else leg["bounds"]
        x0, y0 = tile_xy(b["lat_max"], b["lon_min"], z)
        x1, y1 = tile_xy(b["lat_min"], b["lon_max"], z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                path = out / "tiles" / str(z) / str(x) / f"{y}.jpg"
                if path.exists():
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                req = urllib.request.Request(URL.format(z=z, x=x, y=y), headers={"User-Agent": "leg-package-builder"})
                data = urllib.request.urlopen(req, timeout=60).read()
                if data[:4] == b"\x89PNG":
                    # EOX serves solid open-ocean tiles as palette PNG; store every tile as JPEG.
                    Image.open(io.BytesIO(data)).convert("RGBA").convert("RGB").save(path, "JPEG", quality=85)
                else:
                    path.write_bytes(data)
                count += 1
                time.sleep(0.1)  # keep the request rate gentle
    files = list((out / "tiles").rglob("*.jpg"))
    size = sum(f.stat().st_size for f in files) / 1e6
    (out / "tiles.json").write_text(json.dumps({"dir": "tiles", "scheme": "xyz", "z_min": Z_MIN, "z_max": Z_MAX,
                                                 "format": "jpg", "credit": CREDIT,
                                                 "backdrop_z_max": BACKDROP_Z_MAX, "backdrop": wide}, indent=1))
    print(f"tiles: {len(files)} tiles ({count} fetched now), {size:.1f} MB")
