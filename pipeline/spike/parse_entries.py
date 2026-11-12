"""Spike: parse the text of the 2025 N2E entry list PDF into a CSV.

Usage: python parse_entries.py ENTRIES_TXT OUT_CSV
"""
import csv
import re
import sys

HEADER = re.compile(r"Newport to (Ensenada|San Diego) Course Start (\d{4})")
# name, sail number (optional USA prefix), model, RLC, OWC, PF, class
ROW = re.compile(r"^(?P<name>.+?) (?P<sail>(?:USA ?)?\d+) (?P<model>.+?) (?P<rlc>-?\d+) (?P<owc>-?\d+) (?P<pf>[\d.]+) (?P<cls>N2[A-Z0-9-]+)$")


def main(txt_path, out_path):
    course = start = None
    rows = []
    for line in open(txt_path, encoding="utf-8"):
        line = line.strip()
        h = HEADER.search(line)
        if h:
            course = "N2E" if h.group(1) == "Ensenada" else "N2SD"
            start = h.group(2)
            continue
        m = ROW.match(line)
        if m and course:
            rows.append({"course": course, "start_local": start, **m.groupdict()})
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["course", "start_local", "name", "sail", "model", "rlc", "owc", "pf", "cls"])
        w.writeheader()
        w.writerows(rows)
    by_course = {}
    for r in rows:
        by_course[r["course"]] = by_course.get(r["course"], 0) + 1
    print(f"{len(rows)} entries: {by_course}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
