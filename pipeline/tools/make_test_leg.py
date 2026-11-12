"""Build the synthetic test leg game/packages/test-pocket: open water, varying wind, and a pocket of
light wind sitting on the straight line between start and finish.

The leg tests routing. A boat that steers straight at the finish sails into the light-wind pocket;
an isochrone route goes around it. The period forecast has two runs: the first misses the pocket,
the second (published 4 h after the gun) shows it, so the forecast ideal finds it late.

Run: pipeline/.venv/Scripts/python pipeline/tools/make_test_leg.py
"""

import json
import math
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parents[2] / "game" / "packages" / "test-pocket"
KN = 0.514444

# Area: open Pacific, about 160 nm off Point Conception. Deep water everywhere.
LAT_N, LAT_S = 31.1, 29.9
LON_W, LON_E = -121.0, -120.0
START = [[30.85, -120.53], [30.85, -120.47]]
FINISH = [[30.15, -120.62], [30.15, -120.38]]
POCKET = (30.50, -120.50)  # centre, on the straight line from start to finish
POCKET_RADIUS_NM = 7.0
TIMES_S = list(range(-6 * 3600, 30 * 3600 + 1, 3600))
GRID_D = 0.05  # degrees between wind grid points (3 nm north-south)


def wind_uv(lat: float, lon: float, t: float, pocket: bool) -> tuple[float, float]:
    """Wind toward (east, north) in m/s at a point and time (seconds after the gun)."""
    hours = t / 3600.0
    # Base wind from the northwest, veering from 300 to 320 deg over the first 10 hours.
    from_deg = 300.0 + 20.0 * min(max(hours, 0.0), 10.0) / 10.0
    # Speed varies across the course: 10 kn on the west side rising to 15 kn on the east side,
    # with a slow 1.5 kn swell and fade over 3 hours.
    east = (lon - LON_W) / (LON_E - LON_W)
    kn = 10.0 + 5.0 * east + 1.5 * math.sin(2 * math.pi * hours / 3.0)
    if pocket:
        dy = (lat - POCKET[0]) * 60.0
        dx = (lon - POCKET[1]) * 60.0 * math.cos(math.radians(lat))
        d = math.hypot(dx, dy)
        kn *= 1.0 - 0.8 * math.exp(-((d / POCKET_RADIUS_NM) ** 2))
    to = math.radians(from_deg + 180.0)
    return kn * KN * math.sin(to), kn * KN * math.cos(to)


def grid(times: list[int], pocket: bool) -> np.ndarray:
    rows = int(round((LAT_N - LAT_S) / GRID_D)) + 1
    cols = int(round((LON_E - LON_W) / GRID_D)) + 1
    data = np.zeros((len(times), rows, cols, 2), dtype="<f4")
    for ti, t in enumerate(times):
        for r in range(rows):
            for c in range(cols):
                data[ti, r, c] = wind_uv(LAT_N - r * GRID_D, LON_W + c * GRID_D, t, pocket)
    return data


def header(credit: str, file: str | None = None) -> dict:
    h = {
        "type": "float32_uv_ms",
        "credit": credit,
        "lat_north": LAT_N,
        "lon_west": LON_W,
        "dlat": GRID_D,
        "dlon": GRID_D,
        "rows": int(round((LAT_N - LAT_S) / GRID_D)) + 1,
        "cols": int(round((LON_E - LON_W) / GRID_D)) + 1,
    }
    if file:
        h["file"] = file
    return h


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    grid(TIMES_S, True).tofile(OUT / "wind.bin")
    wind = header("Test map: synthetic wind with a light-wind pocket", "wind.bin") | {"times_s": TIMES_S}

    runs = []
    for name, available, pocket in [("2025060112", -7200, False), ("2025060118", 4 * 3600, True)]:
        file = f"forecast_{name}.bin"
        grid(TIMES_S, pocket).tofile(OUT / file)
        runs.append({"file": file, "run_utc": f"{name[:4]}-{name[4:6]}-{name[6:8]}T{name[8:]}:00:00Z",
                     "available_s": available, "times_s": TIMES_S})
    forecast = header("Test map: synthetic forecast; the first run misses the pocket") | {"runs": runs}

    # No current: a 2 x 2 grid of zeros.
    current_times = [TIMES_S[0], TIMES_S[-1]]
    np.zeros((2, 2, 2, 2), dtype="<f4").tofile(OUT / "current.bin")
    current = {"file": "current.bin", "type": "float32_uv_ms", "credit": "Test map: no current",
               "lat_north": LAT_N, "lon_west": LON_W, "dlat": LAT_N - LAT_S, "dlon": LON_E - LON_W,
               "rows": 2, "cols": 2, "times_s": current_times}

    # Depth: 3000 m everywhere, int16 decimetres of elevation (negative under water).
    dd = 0.01
    rows = int(round((LAT_N - LAT_S) / dd)) + 1
    cols = int(round((LON_E - LON_W) / dd)) + 1
    np.full((rows, cols), -30000, dtype="<i2").tofile(OUT / "depth.bin")
    depth = {"file": "depth.bin", "type": "int16_dm", "credit": "Test map: 3000 m deep everywhere",
             "lat_north": LAT_N, "lon_west": LON_W, "dlat": dd, "dlon": dd, "rows": rows, "cols": cols}

    (OUT / "fleet.json").write_text(json.dumps({"ghosts": []}))
    leg = {
        "id": "test-pocket",
        "event": "Test map",
        "event_type": "race",
        "leg": "Light-wind pocket test",
        "description": "A made-up open-water course for testing routing: varying wind and a pocket of light air on the direct line. No fleet.",
        "note": "Synthetic wind for testing routing. A pocket of light wind sits on the straight line from start to finish.",
        "time_zone": "UTC",
        "utc_offset_s": 0,
        "start_utc": "2025-06-01T18:00:00Z",
        "start_line": START,
        "finish_line": FINISH,
        "marks": [],
        "rules": {"motoring_allowed": False, "motoring_penalty_factor": None},
        "bounds": {"lat_min": LAT_S, "lat_max": LAT_N, "lon_min": LON_W, "lon_max": LON_E},
        "fleet": "fleet.json",
        "wind": wind,
        "forecast": forecast,
        "current": current,
        "depth": depth,
        "tiles": {"dir": "tiles", "scheme": "xyz", "z_min": 6, "z_max": 12, "format": "jpg", "credit": ""},
        "credits": ["Test map: synthetic wind and forecast, no current, uniform depth, no imagery"],
    }
    (OUT / "leg.json").write_text(json.dumps(leg, indent=1))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
