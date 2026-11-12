"""For each matched boat, how close its AIS track gets to the finish line's midpoint, when, and where
the track ends. Helps place a leg's finish line where the AIS tracks actually reach.

Run: pipeline/.venv/Scripts/python pipeline/tools/finish_check.py legs/<id>.json
"""
import json
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from legpack.match import dist_nm  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
leg = json.loads((ROOT / sys.argv[1]).read_text())
(a_lat, a_lon), (b_lat, b_lon) = leg["finish_line"]
f_lat, f_lon = (a_lat + b_lat) / 2, (a_lon + b_lon) / 2
ais = pd.read_csv(ROOT / leg["fleet"]["ais_area_csv"], dtype={"mmsi": str},
                  usecols=["mmsi", "base_date_time", "latitude", "longitude"])
ais["t"] = pd.to_datetime(ais["base_date_time"])
m = pd.read_csv(ROOT / leg["fleet"]["matched_csv"], dtype={"mmsi": str})
rows = []
for _, r in m.iterrows():
    gun = pd.Timestamp(r.start_utc).tz_localize(None)
    tr = ais[(ais.mmsi == r.mmsi) & (ais.t >= gun)].sort_values("t")
    if tr.empty:
        continue
    d = dist_nm(tr.latitude, tr.longitude, f_lat, f_lon)
    i = d.idxmin()
    last = tr.iloc[-1]
    rows.append({"name": r["name"], "closest_nm": round(float(d.min()), 2), "at_h": round((tr.t[i] - gun).total_seconds() / 3600, 1),
                 "closest_lat": round(tr.latitude[i], 4), "closest_lon": round(tr.longitude[i], 4),
                 "last_h": round((last.t - gun).total_seconds() / 3600, 1), "last_lat": round(last.latitude, 3), "last_lon": round(last.longitude, 3)})
print(pd.DataFrame(rows).sort_values("closest_nm").to_string(index=False))
