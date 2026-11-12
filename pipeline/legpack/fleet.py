"""Fleet stage: turn matched AIS tracks into ghost boats for a leg package.

Writes <out>/fleet.json:
  {"ghosts": [{"name", "sail", "model", "class", "class_start_utc", "finish_elapsed_s",
               "track": [[t_s, lat, lon], ...]}]}
t_s is seconds after the leg's start_utc. start_s is the boat's own start-line crossing; finish_elapsed_s runs from it to the finish crossing.
Tracks run from 30 min before the class start to
15 min after the finish crossing, thinned to one fix per 60 s.
"""
import json

import numpy as np
import pandas as pd

LOCAL_OFFSET_H = 7  # PDT = UTC-7 on 25 April 2025
MAX_GAP_MIN = 420  # longer gaps mean the track is not a usable ghost


def crossing_time(tr, line, extended=False):
    """First time the track crosses the segment (or the whole line through it, if extended),
    linear between fixes. None if never."""
    (a_lat, a_lon), (b_lat, b_lon) = line
    p = tr[["longitude", "latitude"]].to_numpy()
    d = np.array([b_lon - a_lon, b_lat - a_lat])
    s = (p[:, 0] - a_lon) * d[1] - (p[:, 1] - a_lat) * d[0]
    for i in np.where(np.sign(s[:-1]) * np.sign(s[1:]) < 0)[0]:
        f = s[i] / (s[i] - s[i + 1])
        x = p[i] + f * (p[i + 1] - p[i])
        if extended or min(a_lon, b_lon) <= x[0] <= max(a_lon, b_lon):
            t0, t1 = tr.t.iloc[i], tr.t.iloc[i + 1]
            return t0 + (t1 - t0) * f
    return None


def build(leg, root, out):
    start = pd.Timestamp(leg["start_utc"]).tz_localize(None)
    ais = pd.read_csv(root / leg["fleet"]["ais_area_csv"], dtype={"mmsi": str},
                      usecols=["mmsi", "base_date_time", "latitude", "longitude"])
    ais["t"] = pd.to_datetime(ais["base_date_time"])
    matched = pd.read_csv(root / leg["fleet"]["matched_csv"], encoding="utf-8",
                          dtype={"mmsi": str, "start_local": str, "start_utc": str, "sail": str}).fillna("")
    matched = matched[matched.match.isin(leg["fleet"]["match_levels"])]
    if leg["fleet"].get("course") and "course" in matched:
        matched = matched[matched.course.fillna("") == leg["fleet"]["course"]]

    ghosts, skipped, pending = [], [], []
    excluded = set(leg["fleet"].get("exclude", []))
    for _, r in matched.iterrows():
        if r["name"] in excluded:
            skipped.append(f"{r['name']} (excluded)")
            continue
        if "start_utc" in r and isinstance(r.start_utc, str) and r.start_utc:
            cls_start = pd.Timestamp(r.start_utc).tz_localize(None)
        else:  # the first leg's matched list gives local start times on 25 April 2025
            cls_start = pd.Timestamp(f"2025-04-25 {r.start_local[:2]}:{r.start_local[2:]}") + pd.Timedelta(hours=LOCAL_OFFSET_H)
        tr = ais[(ais.mmsi == r.mmsi) & (ais.t >= cls_start - pd.Timedelta(minutes=30))].sort_values("t")
        tr = tr.drop_duplicates("t").reset_index(drop=True)
        after_gun = tr[tr.t >= cls_start].reset_index(drop=True)
        # The leg's start line is not the race's real line, so each boat's start is its own
        # crossing of it after the class gun. Boats with no fixes there get an estimate below.
        st = crossing_time(after_gun, leg["start_line"])
        fin = crossing_time(after_gun, leg["finish_line"])
        if fin is None:
            skipped.append(f"{r['name']} (no finish crossing)")
            continue
        tr = tr[tr.t <= fin + pd.Timedelta(minutes=15)]
        worst_gap_min = tr.t.diff().dt.total_seconds().max() / 60
        if worst_gap_min > MAX_GAP_MIN:
            skipped.append(f"{r['name']} (gap {worst_gap_min:.0f} min)")
            continue
        # One fix per minute keeps the file small; AIS spacing inside coverage is about 1.5 min anyway.
        tr = tr.groupby(tr.t.dt.floor("60s")).first().reset_index(drop=True)
        pending.append((r, cls_start, st, fin, tr))

    # Median delay from gun to line among boats with a measured crossing.
    delays = [(st - cs).total_seconds() for _, cs, st, _, _ in pending if st is not None]
    delay = pd.Timedelta(seconds=float(np.median(delays)) if delays else 300.0)
    for r, cls_start, st, fin, tr in pending:
        estimated = st is None
        if estimated:
            st = cls_start + delay
        ghosts.append({
            "name": r["name"].replace("*", "’"),
            "sail": r.sail,
            "model": r.model,
            "class": r.cls,
            "class_start_utc": cls_start.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "start_s": round((st - start).total_seconds()),
            "start_estimated": estimated,
            "finish_elapsed_s": round((fin - st).total_seconds()),
            "track": [[round((t - start).total_seconds()), round(la, 5), round(lo, 5)]
                      for t, la, lo in zip(tr.t, tr.latitude, tr.longitude)],
        })
    print(f"fleet: median gun-to-line delay {delay.total_seconds() / 60:.1f} min, "
          f"estimated starts: {[g['name'] for g in ghosts if g['start_estimated']]}")
    ghosts.sort(key=lambda g: g["finish_elapsed_s"])
    (out / "fleet.json").write_text(json.dumps({"ghosts": ghosts}, separators=(",", ":")), encoding="utf-8")
    print(f"fleet: {len(ghosts)} ghosts, skipped: {skipped}")
    if ghosts:
        e = [g["finish_elapsed_s"] / 3600 for g in ghosts]
        print(f"fleet: elapsed to finish line {min(e):.2f}-{max(e):.2f} h, first {ghosts[0]['name']}")
    return ghosts
