"""Manifest stage: merge the leg definition and every stage header into <out>/leg.json, then run sanity checks.

leg.json is the one file the game reads first. Times in the package are seconds after start_utc.
"""
import json

import numpy as np

PARTS = ["wind", "forecast", "current", "depth", "tiles"]


def depth_at(depth, d, lat, lon):
    r = np.clip(np.round((d["lat_north"] - lat) / d["dlat"]).astype(int), 0, d["rows"] - 1)
    c = np.clip(np.round((lon - d["lon_west"]) / d["dlon"]).astype(int), 0, d["cols"] - 1)
    return depth[r, c] / 10.0


def uv_at(arr, h, ti, lat, lon):
    r = int(round((h["lat_north"] - lat) / h["dlat"]))
    c = int(round((lon - h["lon_west"]) / h["dlon"]))
    return arr[ti, r, c]


def direction_from(uv):
    return (np.degrees(np.arctan2(-uv[0], -uv[1])) + 360) % 360


def build(leg, root, out):
    pkg = {k: leg[k] for k in ["id", "event", "event_type", "leg", "description", "note", "time_zone", "utc_offset_s", "start_utc",
                                "start_line", "finish_line", "marks", "rules", "bounds"]}
    pkg["fleet"] = "fleet.json"
    for p in PARTS:
        pkg[p] = json.loads((out / f"{p}.json").read_text())
    pkg["credits"] = [pkg[p]["credit"] for p in PARTS] + [
        "Fleet: AIS positions from MarineCadastre.gov (BOEM and NOAA), U.S. Coast Guard Nationwide AIS"]
    (out / "leg.json").write_text(json.dumps(pkg, indent=1))

    # Sanity checks.
    d = pkg["depth"]
    depth = np.fromfile(out / d["file"], dtype="<i2").reshape(d["rows"], d["cols"])
    ghosts = json.loads((out / "fleet.json").read_text())["ghosts"]
    fixes = np.array([[f[1], f[2]] for g in ghosts for f in g["track"]])
    zs = depth_at(depth, d, fixes[:, 0], fixes[:, 1])
    b = pkg["bounds"]
    inside = ((fixes[:, 0] >= b["lat_min"]) & (fixes[:, 0] <= b["lat_max"]) &
              (fixes[:, 1] >= b["lon_min"]) & (fixes[:, 1] <= b["lon_max"])).mean() * 100
    print(f"check: {len(fixes)} ghost fixes, {inside:.1f}% inside bounds, "
          f"{(zs >= 0).sum()} on land or zero depth, {(zs > -3).sum()} shallower than 3 m")
    for name, (lat, lon) in [("start line west", leg["start_line"][0]), ("start line east", leg["start_line"][1]),
                             ("finish line west", leg["finish_line"][0]), ("finish line east", leg["finish_line"][1])]:
        print(f"check: depth at {name}: {float(depth_at(depth, d, np.array(lat), np.array(lon))):.1f} m")

    w, f = pkg["wind"], pkg["forecast"]
    wind = np.fromfile(out / w["file"], dtype="<f4").reshape(len(w["times_s"]), w["rows"], w["cols"], 2)
    run = f["runs"][0]
    fc = np.fromfile(out / run["file"], dtype="<f4").reshape(len(run["times_s"]), f["rows"], f["cols"], 2)
    # Wind halfway along the course, at the gun and 3 and 6 hours later (nearest stored hour).
    (sa, sb), (fa_, fb) = leg["start_line"], leg["finish_line"]
    mid_lat = (sa[0] + sb[0] + fa_[0] + fb[0]) / 4
    mid_lon = (sa[1] + sb[1] + fa_[1] + fb[1]) / 4
    for t in [0, 3 * 3600, 6 * 3600]:
        wi = int(np.argmin([abs(x - t) for x in w["times_s"]]))
        fi = int(np.argmin([abs(x - t) for x in run["times_s"]]))
        wa = uv_at(wind, w, wi, mid_lat, mid_lon)
        fa = uv_at(fc, f, fi, mid_lat, mid_lon)
        print(f"check: start+{t // 3600} h at {mid_lat:.2f}, {mid_lon:.2f}: ERA5 {np.hypot(*wa) * 1.94384:.1f} kn from "
              f"{direction_from(wa):.0f} deg, GFS {run['run_utc'][8:13]} {np.hypot(*fa) * 1.94384:.1f} kn from {direction_from(fa):.0f} deg")
    total = sum(p.stat().st_size for p in out.rglob("*") if p.is_file()) / 1e6
    print(f"check: package size {total:.1f} MB")
