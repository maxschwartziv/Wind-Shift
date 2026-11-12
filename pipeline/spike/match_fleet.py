"""Spike: match race-area AIS vessels to the 2025 N2E entry list and report coverage.

Usage: python match_fleet.py AIS_AREA_CSV ENTRIES_CSV OUT_DIR
Writes matched.csv, review.csv and prints a summary.
"""
import re
import sys
from pathlib import Path

import pandas as pd

# Start area off Newport Beach (Balboa Pier), starts 11:00-12:30 PDT = 18:00-19:30 UTC on 25 April 2025.
START_LAT, START_LON = 33.59, -117.90
START_RADIUS_NM = 3.0
START_FROM, START_TO = pd.Timestamp("2025-04-25 17:45"), pd.Timestamp("2025-04-25 20:00")
BORDER_LAT = 32.534  # US-Mexico boundary at the coast
ENSENADA_LAT, ENSENADA_LON = 31.86, -116.62
SAN_DIEGO_LAT, SAN_DIEGO_LON = 32.68, -117.24  # off Point Loma


def norm(name):
    s = str(name).upper().replace("*", "'")
    s = re.sub(r"\bUSA\b", "", s)
    return re.sub(r"[^A-Z0-9]", "", s)


def dist_nm(lat1, lon1, lat2, lon2):
    import numpy as np
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dlat, dlon = p2 - p1, np.radians(lon2 - lon1)
    a = np.sin(dlat / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dlon / 2) ** 2
    return 2 * 3440.065 * np.arcsin(np.sqrt(a))


def main(ais_path, entries_path, out_dir):
    out = Path(out_dir)
    ais = pd.read_csv(ais_path, dtype={"mmsi": str, "vessel_name": str, "transceiver": str})
    ais["t"] = pd.to_datetime(ais["base_date_time"])
    ais["key"] = ais["vessel_name"].map(norm)
    entries = pd.read_csv(entries_path, dtype=str)
    entries["key"] = entries["name"].map(norm)

    # Vessels moving through the start area during the start window.
    win = ais[(ais.t >= START_FROM) & (ais.t <= START_TO)]
    near = win[dist_nm(win.latitude, win.longitude, START_LAT, START_LON) <= START_RADIUS_NM]
    starters = set(near.loc[near.sog >= 2.5, "mmsi"])
    # A racer heads south afterward: some fix south of 33.2 N within the next 30 h.
    later = ais[(ais.t > START_FROM) & (ais.t <= START_TO + pd.Timedelta(hours=30))]
    went_south = set(later.loc[later.latitude < 33.2, "mmsi"])
    start_line_candidates = starters & went_south

    names = ais.groupby("mmsi").agg(vessel_name=("vessel_name", "last"), key=("key", "last"),
                                    vessel_type=("vessel_type", "last"), transceiver=("transceiver", "last"),
                                    length=("length", "last"))
    by_key = {}
    for mmsi, row in names.iterrows():
        if row.key:
            by_key.setdefault(row.key, []).append(mmsi)

    rows = []
    for _, e in entries.iterrows():
        cands = by_key.get(e.key, [])
        # Prefer a same-name vessel that also behaved like a starter.
        strong = [m for m in cands if m in start_line_candidates]
        pick = strong[0] if strong else (cands[0] if len(cands) == 1 else None)
        how = "name+start" if strong else ("name only" if pick else "")
        rows.append({**e.drop("key").to_dict(), "mmsi": pick, "match": how, "same_name_vessels": len(cands)})
    matched = pd.DataFrame(rows)

    # Coverage for each matched boat after its start.
    cov = []
    for _, r in matched[matched.mmsi.notna()].iterrows():
        tr = ais[(ais.mmsi == r.mmsi) & (ais.t >= START_FROM)].sort_values("t")
        if tr.empty:
            cov.append({"mmsi": r.mmsi, "fixes": 0})
            continue
        last = tr.iloc[-1]
        fin_lat, fin_lon = (ENSENADA_LAT, ENSENADA_LON) if r.course == "N2E" else (SAN_DIEGO_LAT, SAN_DIEGO_LON)
        gaps = tr.t.diff().dt.total_seconds().div(60)
        cov.append({"mmsi": r.mmsi, "fixes": len(tr), "last_fix_utc": last.t, "last_lat": last.latitude,
                    "last_lon": last.longitude, "nm_short_of_finish": round(float(dist_nm(last.latitude, last.longitude, fin_lat, fin_lon)), 1),
                    "max_gap_min": round(float(gaps.max()), 1) if len(tr) > 1 else None,
                    "reached_border": bool((tr.latitude <= BORDER_LAT).any())})
    matched = matched.merge(pd.DataFrame(cov), on="mmsi", how="left")
    matched = matched.merge(names[["vessel_name", "transceiver", "vessel_type"]], left_on="mmsi", right_index=True, how="left")
    matched.to_csv(out / "matched.csv", index=False)

    # Start-line candidates with no entry-list name: for manual review.
    used = set(matched.mmsi.dropna())
    review = names.loc[sorted(start_line_candidates - used)].reset_index()
    review.to_csv(out / "review.csv", index=False)

    found = matched[matched.mmsi.notna()]
    print(f"AIS rows in area: {len(ais)}, vessels: {ais.mmsi.nunique()}")
    print(f"Start-line candidates (moving in start area, then south): {len(start_line_candidates)}")
    for course, g in matched.groupby("course"):
        f = g[g.mmsi.notna()]
        print(f"{course}: {len(f)} of {len(g)} entries matched "
              f"({(f.match == 'name+start').sum()} name+start, {(f.match == 'name only').sum()} name only)")
    if len(found):
        print(f"Transceiver class among matched: {found.transceiver.value_counts(dropna=False).to_dict()}")
        n2e = found[found.course == "N2E"]
        print(f"N2E matched reaching the border: {n2e.reached_border.sum()} of {len(n2e)}")
        print(f"N2E last-fix distance short of Ensenada (nm): median {n2e.nm_short_of_finish.median()}, "
              f"min {n2e.nm_short_of_finish.min()}, max {n2e.nm_short_of_finish.max()}")
        print(f"Max gap between fixes (min): median {found.max_gap_min.median()}")
    print(f"Unnamed start-line candidates for review: {len(review)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
