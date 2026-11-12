"""Build the starter boat profiles from the OpenCPN polar files in game/data/polars (docs/adr/0003).

Usage: python tools/make_starter_boats.py
Boats without a published polar use a similar boat's polar and say so in their name.
Drafts and motoring speeds are approximate class figures; players can edit them.
"""
import json
from pathlib import Path

GAME = Path(__file__).resolve().parents[2] / "game"
POLARS = GAME / "data" / "polars"
OUT = GAME / "data" / "boats"

BOATS = [
    {"name": "Alberg 30 (Alberg 35 polar)", "polar": "Alberg_35.pol", "draft_m": 1.32,
     "tack_penalty_s": 25, "gybe_penalty_s": 20, "motoring_kn": 5.5},
    {"name": "Pearson Alberg 35", "polar": "Alberg_35.pol", "draft_m": 1.57,
     "tack_penalty_s": 25, "gybe_penalty_s": 20, "motoring_kn": 6.0},
    {"name": "Beneteau First 40.7", "polar": "First_40.7.pol", "draft_m": 2.40,
     "tack_penalty_s": 15, "gybe_penalty_s": 15, "motoring_kn": 7.0},
    {"name": "Catalina 400 (Catalina 36 polar)", "polar": "Catalina_36.pol", "draft_m": 1.98,
     "tack_penalty_s": 20, "gybe_penalty_s": 18, "motoring_kn": 7.0},
    {"name": "Catalina 35 (Catalina 36 polar)", "polar": "Catalina_36.pol", "draft_m": 1.75,
     "tack_penalty_s": 20, "gybe_penalty_s": 18, "motoring_kn": 6.5},
]


def main():
    for old in OUT.glob("*.json"):
        old.unlink()
    files = []
    for b in BOATS:
        profile = {k: b[k] for k in ["name", "draft_m", "tack_penalty_s", "gybe_penalty_s", "motoring_kn"]}
        profile["polar"] = (POLARS / b["polar"]).read_text()
        profile["polar_source"] = f"OpenCPN weather_routing_pi, data/polars/{b['polar']} (GPL-3.0)"
        slug = b["name"].split(" (")[0].lower().replace(" ", "-").replace(".", "")
        (OUT / f"{slug}.json").write_text(json.dumps(profile, indent=1))
        files.append(f"{slug}.json")
        print(f"{b['name']}: {b['polar']}")
    (OUT / "index.json").write_text(json.dumps(files, indent=1))


if __name__ == "__main__":
    main()
