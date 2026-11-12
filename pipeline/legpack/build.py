"""Build a leg package.

Usage: python -m legpack.build legs/<id>.json [stage ...]
Stages: ais match fleet wind forecast current depth tiles manifest (default: all). ais and match need leg["fleet"]["ais_dates"] and entries_csv.
Output goes to ../game/packages/<id>/.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGES = ["ais", "match", "fleet", "wind", "forecast", "current", "depth", "tiles", "manifest"]


def main(leg_path, stages):
    leg = json.loads((ROOT / leg_path).read_text())
    out = ROOT.parent / "game" / "packages" / leg["id"]
    out.mkdir(parents=True, exist_ok=True)
    for stage in stages or STAGES:
        mod = __import__(f"legpack.{stage}", fromlist=["build"])
        mod.build(leg, ROOT, out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
