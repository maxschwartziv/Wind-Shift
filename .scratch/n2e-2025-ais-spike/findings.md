# Newport to Ensenada 2025: AIS fleet spike

Status: resolved
Date: 11 November 2026

## Question

How many 2025 Newport to Ensenada (N2E) entrants appear in MarineCadastre AIS, and where do their tracks fade?

## Inputs

- Race: 77th N2E, starts 11:00–12:30 PDT on 25 April 2025 (18:00–19:30 UTC). Two courses: Ensenada (124 nm) and San Diego (88 nm). Source: [NOSA](https://nosa.org/fast-exit-ii-wins-the-77th-annual-newport-to-ensenada-international-yacht-race/).
- Entry list: Regatta Network PDF, revision of 23 April 2025, 112 boats (105 Ensenada, 7 San Diego). Parsed to `pipeline/data/n2e2025_entries.csv`.
- AIS: MarineCadastre daily files `csv2/csv2025/ais-2025-04-25|26|27.csv.zst` (about 724 MB compressed), filtered to 31.6–33.8 N, 118.6–116.4 W. 715,950 rows, 1,097 vessels. Saved as `pipeline/data/n2e2025_ais_area.csv` (69 MB).
- Scripts: `pipeline/spike/fetch_ais.py`, `parse_entries.py`, `match_fleet.py`.

## Results

| Measure | Value |
|---|---|
| Ensenada entries matched by name and start-line behavior | 39 of 105 |
| Ensenada entries matched by name only (unverified) | 22 of 105 |
| San Diego entries matched | 1 of 7 |
| Start-line candidates with no entry-list name | 11 (`pipeline/data/review.csv`) |
| Transceiver class of matched boats | 61 Class B, 1 Class A |
| Fix interval inside coverage (median) | 1.5 min |
| Southernmost fix of confirmed boats (median) | 32.37 N, about 30 nm short of Ensenada |
| Last-fix distance short of the Ensenada finish (median) | 57 nm |

Vessel names and MMSI numbers (vessel AIS identity numbers) are not scrambled in 2025. Two review-list names likely match entries: `SV MERLIN` (Merlin, J/99) and `RADIANCE1` (Radiance).

## Coverage gaps

Every confirmed track has the same three gaps:

1. **Offshore hole, about 33.34 N to 32.9 N.** Off Dana Point to Oceanside, roughly 25–30 nm of course. Most boats lose 2–5 hours of fixes here between 20:30 and 01:00 UTC. The hole is in the same place for all boats, so a gap in receiver coverage is the likely cause.
2. **Receiver outage, 06:10–09:00 UTC on 26 April.** Zero fixes from any vessel south of 32.7 N in that window. Many tracks end at 06:10.
3. **Mexican waters.** No fixes south of about 32.2 N. The last 40–60 nm to Ensenada are missing for every boat.

Sampled course is roughly Newport to 33.34 N (about 17 nm) and 32.9 N to 32.4 N (about 35 nm). That is about 40 % of the 124 nm course.

## Finish times

Regatta Network shows "Results for this event have not been posted". The only published results are the trophy-winner PDFs, which list winners, not elapsed times. The race's official tracker is YB (`yb.tl/N2e2025`), and ADR 0002 rules out taking its data without permission.

## Implications

- An N2E 2025 ghost fleet of about 39–61 boats is possible from AIS alone, but about 60 % of each ghost's course would be interpolated (dashed), and without official finish times the last segment has no end point (rule from Q39).
- The San Diego course stays in US waters but has only 1 matched boat.
- A request to NOSA and YB Tracking for the 2025 tracks and finish times would fill all three gaps.

## Decision (11 November 2026)

AIS-only. The leg ends at a line along 32.60 N (117.95 W to 117.14 W), ahead of the coverage loss. 38 ghosts cross it, and their finish times come from the AIS crossing. Triumph is dropped for a 14-hour gap. The package is in `packages/n2e-2025/`.
