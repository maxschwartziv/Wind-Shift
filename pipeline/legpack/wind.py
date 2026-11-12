"""Actual-wind stage: hourly ERA5 10 m wind on the native 0.25 degree grid, via the Open-Meteo archive API.

Writes <out>/wind.bin: float32 little-endian, shape [time][row][col][2] with (east, north) in m/s,
rows north to south, columns west to east. Header goes to <out>/wind.json.
"""
import json
import math
import urllib.parse
import urllib.request

import numpy as np
import pandas as pd

ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
CREDIT = "Wind: ERA5 reanalysis (Copernicus Climate Change Service), served by Open-Meteo.com (CC BY 4.0)"
STEP = 0.25


def grid_points(b):
    lat_n = math.ceil(b["lat_max"] / STEP) * STEP
    lat_s = math.floor(b["lat_min"] / STEP) * STEP
    lon_w = math.floor(b["lon_min"] / STEP) * STEP
    lon_e = math.ceil(b["lon_max"] / STEP) * STEP
    lats = np.arange(lat_n, lat_s - 1e-9, -STEP)
    lons = np.arange(lon_w, lon_e + 1e-9, STEP)
    return lats, lons


def fetch(url, params, lats, lons):
    """Query every grid point in one call; return speed and direction arrays [time][row][col] and times."""
    pts = [(la, lo) for la in lats for lo in lons]
    q = dict(params, latitude=",".join(f"{p[0]:.2f}" for p in pts), longitude=",".join(f"{p[1]:.2f}" for p in pts),
             wind_speed_unit="ms", timezone="GMT", cell_selection="nearest")
    with urllib.request.urlopen(url + "?" + urllib.parse.urlencode(q), timeout=120) as r:
        res = json.load(r)
    if isinstance(res, dict):
        res = [res]
    return res


def to_uv(res, lats, lons, speed_key, dir_key):
    times = pd.to_datetime(res[0]["hourly"]["time"])
    spd = np.array([r["hourly"][speed_key] for r in res], dtype=float).T.reshape(len(times), len(lats), len(lons))
    drc = np.array([r["hourly"][dir_key] for r in res], dtype=float).T.reshape(len(times), len(lats), len(lons))
    # Meteorological direction is where the wind comes from; the vector points where it goes.
    rad = np.radians(drc)
    u, v = -spd * np.sin(rad), -spd * np.cos(rad)
    return times, np.nan_to_num(np.stack([u, v], axis=-1)).astype("<f4")


def header(leg, file, credit, lats, lons, times):
    start = pd.Timestamp(leg["start_utc"]).tz_localize(None)
    return {"file": file, "type": "float32_uv_ms", "credit": credit,
            "lat_north": float(lats[0]), "lon_west": float(lons[0]), "dlat": STEP, "dlon": STEP,
            "rows": len(lats), "cols": len(lons),
            "times_s": [round((t - start).total_seconds()) for t in times]}


def build(leg, root, out):
    lats, lons = grid_points(leg["bounds"])
    t0, t1 = (pd.Timestamp(t).tz_localize(None) for t in leg["data_window_utc"])
    res = fetch(ARCHIVE, {"start_date": t0.date(), "end_date": t1.date(), "models": "era5",
                          "hourly": "wind_speed_10m,wind_direction_10m"}, lats, lons)
    times, uv = to_uv(res, lats, lons, "wind_speed_10m", "wind_direction_10m")
    keep = (times >= t0) & (times <= t1)
    times, uv = times[keep], uv[keep]
    uv.tofile(out / "wind.bin")
    (out / "wind.json").write_text(json.dumps(header(leg, "wind.bin", CREDIT, lats, lons, times), indent=1))
    kn = np.hypot(uv[..., 0], uv[..., 1]) * 1.94384
    print(f"wind: {len(times)} h x {len(lats)}x{len(lons)} points, {kn.min():.1f}-{kn.max():.1f} kn, mean {kn.mean():.1f} kn")
