"""Current stage: hourly surface currents from HYCOM ESPC-D-V02 (1/12 degree) over the leg bounds.

Writes <out>/current.bin: float32 little-endian, shape [time][row][col][2] with (east, north) in m/s,
rows north to south, columns west to east. Land and missing cells are 0.
The grid header goes to <out>/current.json.
"""
import json
import urllib.parse
import urllib.request

import numpy as np
import pandas as pd
import xarray as xr

NCSS = "https://ncss.hycom.org/thredds/ncss/grid/ESPC-D-V02/ice/{year}"
CREDIT = "Currents: HYCOM ESPC-D-V02 global 1/12 degree analysis (U.S. Navy / HYCOM consortium)"


def build(leg, root, out):
    b = leg["bounds"]
    t0, t1 = leg["data_window_utc"]
    if leg.get("current_source") == "none":
        # Lakes: HYCOM is an ocean model and has no data there. Write a still-water grid.
        np.zeros((2, 2, 2, 2), dtype="<f4").tofile(out / "current.bin")
        start = pd.Timestamp(leg["start_utc"]).tz_localize(None)
        times = [round((pd.Timestamp(t).tz_localize(None) - start).total_seconds()) for t in (t0, t1)]
        header = {"file": "current.bin", "type": "float32_uv_ms", "credit": leg.get("current_credit", "Currents: none (lake, still water)"),
                  "lat_north": b["lat_max"], "lon_west": b["lon_min"], "dlat": b["lat_max"] - b["lat_min"],
                  "dlon": b["lon_max"] - b["lon_min"], "rows": 2, "cols": 2, "times_s": times}
        (out / "current.json").write_text(json.dumps(header, indent=1))
        print("current: none, still water")
        return
    q = [("var", "ssu"), ("var", "ssv"), ("north", b["lat_max"] + 0.1), ("south", b["lat_min"] - 0.1),
         ("west", b["lon_min"] - 0.1), ("east", b["lon_max"] + 0.1), ("time_start", t0), ("time_end", t1),
         ("accept", "netcdf4")]
    url = NCSS.format(year=t0[:4]) + "?" + urllib.parse.urlencode(q)
    raw = root / "data" / f"{leg['id']}_hycom.nc"
    if not raw.exists():
        urllib.request.urlretrieve(url, raw)
    ds = xr.open_dataset(raw)
    lat_name = "lat" if "lat" in ds.coords else "latitude"
    lon_name = "lon" if "lon" in ds.coords else "longitude"
    u, v = ds.ssu.squeeze(), ds.ssv.squeeze()
    u = u.sortby(lat_name, ascending=False).sortby(lon_name)
    v = v.sortby(lat_name, ascending=False).sortby(lon_name)
    arr = np.stack([u.values, v.values], axis=-1)
    arr = np.nan_to_num(arr, nan=0.0).astype("<f4")
    arr.tofile(out / "current.bin")
    lat, lon = u[lat_name].values, u[lon_name].values
    lon = np.where(lon > 180, lon - 360, lon)
    times = pd.to_datetime(u.time.values)
    start = pd.Timestamp(leg["start_utc"]).tz_localize(None)
    header = {"file": "current.bin", "type": "float32_uv_ms", "credit": CREDIT,
              "lat_north": float(lat[0]), "lon_west": float(lon[0]),
              "dlat": float(lat[0] - lat[1]), "dlon": float(lon[1] - lon[0]),
              "rows": len(lat), "cols": len(lon),
              "times_s": [round((t - start).total_seconds()) for t in times]}
    (out / "current.json").write_text(json.dumps(header, indent=1))
    speed_kn = np.hypot(arr[..., 0], arr[..., 1]) * 1.94384
    print(f"current: {len(times)} times x {len(lat)}x{len(lon)} cells, max {speed_kn.max():.2f} kn, "
          f"mean over water {speed_kn[speed_kn > 0].mean():.2f} kn")
