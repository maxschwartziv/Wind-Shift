"""Match stage: pair race entries with AIS vessels by name.

Reads the leg's entries_csv (columns: name, sail, model, class, start_utc) and its AIS area CSV.
An entry matches a vessel whose AIS name is the same after normalizing (upper case, letters and digits
only). "name+start" means the vessel was also within start_radius_nm of the start line between
15 minutes before and 60 minutes after its class start; "name" means it was only seen in the area
during the race. Writes the leg's matched_csv and prints coverage.
"""
import re

import numpy as np
import pandas as pd


def norm(name):
    s = str(name).upper().replace("*", "'")
    s = re.sub(r"\bUSA\b", "", s)
    return re.sub(r"[^A-Z0-9]", "", s)


def dist_nm(lat1, lon1, lat2, lon2):
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dlat, dlon = p2 - p1, np.radians(lon2 - lon1)
    a = np.sin(dlat / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dlon / 2) ** 2
    return 2 * 3440.065 * np.arcsin(np.sqrt(a))


def build(leg, root, out):
    fl = leg["fleet"]
    entries = pd.read_csv(root / fl["entries_csv"], dtype=str).fillna("")
    ais = pd.read_csv(root / fl["ais_area_csv"], dtype={"mmsi": str, "vessel_name": str},
                      usecols=["mmsi", "base_date_time", "latitude", "longitude", "vessel_name"])
    ais["t"] = pd.to_datetime(ais["base_date_time"])
    ais["key"] = ais["vessel_name"].map(norm)
    (a_lat, a_lon), (b_lat, b_lon) = leg["start_line"]
    s_lat, s_lon = (a_lat + b_lat) / 2, (a_lon + b_lon) / 2
    radius = fl.get("start_radius_nm", 2.0)
    rows, missing = [], []
    for _, e in entries.iterrows():
        key = norm(e["name"])
        gun = pd.Timestamp(e["start_utc"]).tz_localize(None)
        cand = ais[(ais.key == key) & (ais.t >= gun - pd.Timedelta(hours=1)) & (ais.t <= gun + pd.Timedelta(hours=48))]
        if key == "" or cand.empty:
            missing.append(e["name"])
            continue
        best, level = None, None
        for mmsi, tr in cand.groupby("mmsi"):
            near = tr[(tr.t >= gun - pd.Timedelta(minutes=15)) & (tr.t <= gun + pd.Timedelta(minutes=60))]
            at_start = bool(len(near)) and bool((dist_nm(near.latitude, near.longitude, s_lat, s_lon) <= radius).any())
            score = (1 if at_start else 0, len(tr))
            if best is None or score > best[0]:
                best, level = (score, mmsi), ("name+start" if at_start else "name")
        rows.append({"name": e["name"], "sail": e["sail"], "model": e["model"], "cls": e["class"],
                     "start_utc": e["start_utc"], "mmsi": best[1], "match": level, "course": fl.get("course", "")})
    m = pd.DataFrame(rows, columns=["name", "sail", "model", "cls", "start_utc", "mmsi", "match", "course"])
    m.to_csv(root / fl["matched_csv"], index=False, encoding="utf-8")
    n_start = int((m.match == "name+start").sum())
    print(f"match: {len(entries)} entries, {len(m)} found in AIS ({n_start} seen at the start), {len(missing)} not found")
    if missing:
        print("match: not found: " + ", ".join(missing[:40]) + (" ..." if len(missing) > 40 else ""))
