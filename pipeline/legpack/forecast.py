"""Period-forecast stage: GFS 0.25 degree 10 m wind forecasts as issued during the leg.

Each GFS run issued in the data window becomes one forecast. Only the 10 m U and V messages are
fetched, by byte range from the NOAA GFS bucket on AWS. A run counts as available 4 h after its
cycle time, roughly when NOAA finishes publishing it.

Writes <out>/forecast_<run>.bin (same layout as wind.bin) and <out>/forecast.json listing the runs.
"""
import json
import tempfile
import urllib.request
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

from legpack.wind import STEP, grid_points

BASE = "https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.{d}/{h}/atmos/gfs.t{h}z.pgrb2.0p25.f{f:03d}"
CREDIT = "Period forecast: NOAA GFS 0.25 degree, as issued (NOAA Open Data Dissemination on AWS)"
AVAILABLE_AFTER_H = 4


def byte_ranges(url):
    lines = urllib.request.urlopen(url + ".idx", timeout=60).read().decode().splitlines()
    out = []
    for i, line in enumerate(lines):
        if (":UGRD:10 m above ground:" in line) or (":VGRD:10 m above ground:" in line):
            start = int(line.split(":")[1])
            end = int(lines[i + 1].split(":")[1]) - 1
            out.append((start, end))
    return out


def fetch_uv(url, lats, lons, tmp):
    """Download the two 10 m wind messages and return uv [row][col][2] on the leg grid."""
    path = Path(tmp) / "msg.grib2"
    with open(path, "wb") as f:
        for a, b in byte_ranges(url):
            req = urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}"})
            f.write(urllib.request.urlopen(req, timeout=120).read())
    ds = xr.open_dataset(path, engine="cfgrib", backend_kwargs={"indexpath": ""})
    sub = ds.sel(latitude=lats, longitude=lons % 360)
    uv = np.stack([sub.u10.values, sub.v10.values], axis=-1).astype("<f4")
    ds.close()
    path.unlink()
    return uv


def build(leg, root, out):
    lats, lons = grid_points(leg["bounds"])
    t0, t1 = (pd.Timestamp(t).tz_localize(None) for t in leg["data_window_utc"])
    start = pd.Timestamp(leg["start_utc"]).tz_localize(None)
    runs = pd.date_range(t0.floor("6h"), t1 - pd.Timedelta(hours=6), freq="6h")
    meta = []
    with tempfile.TemporaryDirectory() as tmp:
        for run in runs:
            hours = range(0, int((t1 - run).total_seconds() // 3600) + 1)
            frames = [fetch_uv(BASE.format(d=run.strftime("%Y%m%d"), h=run.strftime("%H"), f=f), lats, lons, tmp)
                      for f in hours]
            arr = np.stack(frames)
            name = f"forecast_{run.strftime('%Y%m%d%H')}.bin"
            arr.tofile(out / name)
            meta.append({"file": name, "run_utc": run.strftime("%Y-%m-%dT%H:%M:%SZ"),
                         "available_s": round((run + pd.Timedelta(hours=AVAILABLE_AFTER_H) - start).total_seconds()),
                         "times_s": [round((run + pd.Timedelta(hours=f) - start).total_seconds()) for f in hours]})
            kn = np.hypot(arr[..., 0], arr[..., 1]) * 1.94384
            print(f"forecast: run {run:%d %b %H}Z, {len(frames)} h, mean {kn.mean():.1f} kn", flush=True)
    header = {"type": "float32_uv_ms", "credit": CREDIT, "lat_north": float(lats[0]), "lon_west": float(lons[0]),
              "dlat": STEP, "dlon": STEP, "rows": len(lats), "cols": len(lons), "runs": meta}
    (out / "forecast.json").write_text(json.dumps(header, indent=1))
