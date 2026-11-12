"""Fetch race entry lists into the CSV the match stage reads: name, sail, model, class, start_utc.
Only boat fields are kept; skipper, owner, crew and hometown are left out.

Run: pipeline/.venv/Scripts/python pipeline/tools/entries.py spinnaker-cup-2025
     pipeline/.venv/Scripts/python pipeline/tools/entries.py queens-cup-2024
"""
import io
import json
import sys
import urllib.request
from pathlib import Path

import pandas as pd

DATA = Path(__file__).resolve().parents[1] / "data"
UA = {"User-Agent": "leg-package-builder"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def spinnaker_cup_2025():
    # Yacht Scoring event 50036. Every class starts in one sequence from 10:45 PDT; the sailing
    # instructions do not give per-class times, so all boats take the first start.
    d = json.loads(get("https://api.yachtscoring.com/v1/public/event/50036/boats?size=100"))
    rows = []
    for b in d["rows"]:
        sail = "".join(x for x in [b.get("sailPrefix") or "", b.get("sailNumber") or ""] if x)
        rows.append({"name": b["name"].strip(), "sail": sail, "model": (b.get("design") or "").strip(),
                     "class": (b.get("split") or {}).get("splitClassName", ""), "start_utc": "2025-05-24T17:45:00Z"})
    return pd.DataFrame(rows)


def queens_cup_2024():
    # Regatta Network event 27278: one table per scoring group; a boat can appear in several.
    html = get("https://www.regattanetwork.com/clubmgmt/applet_registrant_list.php?regatta_id=27278&custom_report_id=33")
    rows = {}
    for t in pd.read_html(io.BytesIO(html)):
        if t.shape[1] < 5 or str(t.iloc[0, 2]) != "Boat Name":
            continue
        for _, r in t.iloc[1:].iterrows():
            name = str(r[2]).strip()
            cls = str(r[4]).strip()
            if not name or name == "nan":
                continue
            low = cls.lower()
            # First start of each fleet: warning plus 5 minutes (sailing instructions 5.2 and 10.1), CDT = UTC-5.
            if "cruis" in low:
                start = "2024-06-28T19:35:00Z"
            elif "short" in low or "double" in low or "single" in low:
                start = "2024-06-28T21:05:00Z"
            else:
                start = "2024-06-28T21:35:00Z"
            sail = str(r[3]).replace("-", "").strip()
            prev = rows.get(name)
            # Prefer the earliest start if a boat is listed in two fleets.
            if prev is None or start < prev["start_utc"]:
                rows[name] = {"name": name, "sail": sail, "model": "", "class": cls, "start_utc": start}
    return pd.DataFrame(list(rows.values()))


if __name__ == "__main__":
    leg = sys.argv[1]
    df = {"spinnaker-cup-2025": spinnaker_cup_2025, "queens-cup-2024": queens_cup_2024}[leg]()
    path = DATA / f"{leg}_entries.csv"
    df.to_csv(path, index=False, encoding="utf-8")
    print(f"{path.name}: {len(df)} boats")
    print(df.head(5).to_string())
