"""Compare a leg package's wind (ERA5 "actual" and the GFS period forecast) with NOAA NDBC
observations at stations inside the leg's wind grid, over the race window.

Observed speeds are scaled from anemometer height to 10 m with the power law (10/z)^0.11, the usual
open-water exponent. Direction error is the smallest angle between observed and model directions,
counted only when the observed speed is at least 2 m/s.

Run: pipeline/.venv/Scripts/python pipeline/tools/wind_accuracy.py n2e-2025 2025-04-25T18 2025-04-26T12 46086:4.1 LJPC1:18.0 SDBC1:10.4
Each station is ID:anemometer height in meters (from the NDBC station page).
"""

import gzip
import io
import json
import math
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

KN = 1 / 0.514444
GAME = Path(__file__).resolve().parents[2] / "game" / "packages"
STATION_POS = {}  # filled from the NDBC station table


def station_position(sid):
    url = f"https://www.ndbc.noaa.gov/station_page.php?station={sid.lower()}"
    html = urllib.request.urlopen(url, timeout=60).read().decode("utf-8", "replace")
    # The page shows e.g. "32.499 N 118.052 W"
    import re
    m = re.search(r"(\d+\.\d+)\s*N\s+(\d+\.\d+)\s*W", html)
    return float(m.group(1)), -float(m.group(2))


def observations(sid, t0, t1):
    year = datetime.fromtimestamp(t0, timezone.utc).year
    url = f"https://www.ndbc.noaa.gov/view_text_file.php?filename={sid.lower()}h{year}.txt.gz&dir=data/historical/stdmet/"
    text = urllib.request.urlopen(url, timeout=120).read().decode("utf-8", "replace")
    rows = []
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        f = line.split()
        t = datetime(int(f[0]), int(f[1]), int(f[2]), int(f[3]), int(f[4]), tzinfo=timezone.utc).timestamp()
        if t0 <= t <= t1:
            wdir, wspd = float(f[5]), float(f[6])
            if wdir < 900 and wspd < 90:
                rows.append((t, wdir, wspd))
    return rows


class Grid:
    def __init__(self, header, path, times):
        self.h = header
        self.times = np.array(times, dtype=float)
        n = len(times) * header["rows"] * header["cols"] * 2
        self.data = np.fromfile(path, dtype="<f4", count=n).reshape(len(times), header["rows"], header["cols"], 2)

    def sample(self, lat, lon, t):
        h = self.h
        fr = (h["lat_north"] - lat) / h["dlat"]
        fc = (lon - h["lon_west"]) / h["dlon"]
        r, c = int(fr), int(fc)
        if not (0 <= r < h["rows"] - 1 and 0 <= c < h["cols"] - 1):
            return None
        tr, tc = fr - r, fc - c
        i = np.searchsorted(self.times, t) - 1
        i = min(max(i, 0), len(self.times) - 2)
        ft = (t - self.times[i]) / (self.times[i + 1] - self.times[i])
        ft = min(max(ft, 0.0), 1.0)

        def space(k):
            d = self.data[k]
            top = d[r, c] * (1 - tc) + d[r, c + 1] * tc
            bot = d[r + 1, c] * (1 - tc) + d[r + 1, c + 1] * tc
            return top * (1 - tr) + bot * tr

        return space(i) * (1 - ft) + space(i + 1) * ft


def stats(pairs):
    """pairs: (obs_speed, obs_dir, model_u, model_v) in m/s and degrees."""
    sp_err, dir_err = [], []
    for ospd, odir, mu, mv in pairs:
        mspd = math.hypot(mu, mv)
        mdir = (math.degrees(math.atan2(-mu, -mv)) + 360) % 360  # direction the wind comes from
        sp_err.append(mspd - ospd)
        if ospd >= 2.0:
            d = abs((mdir - odir + 180) % 360 - 180)
            dir_err.append(d)
    e = np.array(sp_err)
    return {
        "n": len(pairs),
        "obs_mean_kn": float(np.mean([p[0] for p in pairs]) * KN),
        "bias_kn": float(e.mean() * KN),
        "rmse_kn": float(math.sqrt((e ** 2).mean()) * KN),
        "dir_mae_deg": float(np.mean(dir_err)) if dir_err else float("nan"),
    }


def main():
    leg, t0s, t1s, *stations = sys.argv[1:]
    pkg = GAME / leg
    info = json.loads((pkg / "leg.json").read_text())
    start = datetime.fromisoformat(info["start_utc"].replace("Z", "+00:00")).timestamp()
    t0 = datetime.fromisoformat(t0s).replace(tzinfo=timezone.utc).timestamp()
    t1 = datetime.fromisoformat(t1s).replace(tzinfo=timezone.utc).timestamp()
    w = info["wind"]
    era5 = Grid(w, pkg / w["file"], w["times_s"])
    fc = info["forecast"]
    runs = [(r["available_s"], Grid(fc, pkg / r["file"], r["times_s"])) for r in fc["runs"]]
    print(f"{leg}: {t0s} to {t1s} UTC")
    print(f"{'station':8} {'lat':>7} {'lon':>8} {'height':>6} {'n':>4} {'obs kn':>7} | {'ERA5 bias':>9} {'RMSE':>5} {'dir':>4} | {'GFS bias':>8} {'RMSE':>5} {'dir':>4}")
    for spec in stations:
        sid, z = spec.split(":")
        z = float(z)
        lat, lon = station_position(sid)
        obs = observations(sid, t0, t1)
        scale = (10.0 / z) ** 0.11
        e_pairs, g_pairs = [], []
        for t, odir, ospd in obs:
            ts = t - start
            m = era5.sample(lat, lon, ts)
            run = [g for avail, g in runs if avail <= ts][-1] if any(a <= ts for a, _ in runs) else runs[0][1]
            g = run.sample(lat, lon, ts)
            if m is None or g is None:
                continue
            e_pairs.append((ospd * scale, odir, m[0], m[1]))
            g_pairs.append((ospd * scale, odir, g[0], g[1]))
        if not e_pairs:
            print(f"{sid:8} no usable readings: {len(obs)} in the window, none inside the wind grid")
            continue
        a, b = stats(e_pairs), stats(g_pairs)
        print(f"{sid:8} {lat:7.3f} {lon:8.3f} {z:5.1f}m {a['n']:4d} {a['obs_mean_kn']:7.1f} | {a['bias_kn']:+9.1f} {a['rmse_kn']:5.1f} {a['dir_mae_deg']:4.0f} | {b['bias_kn']:+8.1f} {b['rmse_kn']:5.1f} {b['dir_mae_deg']:4.0f}")


if __name__ == "__main__":
    main()
