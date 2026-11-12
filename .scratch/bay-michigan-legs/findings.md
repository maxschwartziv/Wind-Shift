# Bay Area and Lake Michigan legs

Built on 11 November 2026 with the pipeline's new `ais` and `match` stages. Race choices came from a research pass over 2024 and 2025 races with public entry lists and MarineCadastre AIS coverage.

| Leg | Race | Course | Entries | Found in AIS | Seen at the start | Ghost boats | Fleet elapsed times |
|---|---|---|---|---|---|---|---|
| `spinnaker-cup-2025` | Spinnaker Cup, 24 May 2025 | San Francisco to Monterey, 84 nm | 51 | 38 | 35 | 27 | 7.15–20.95 h |
| `queens-cup-2024` | Queen's Cup, 28 June 2024 | Milwaukee to South Haven, 76 nm | 130 | 43 | 35 | 23 | 9.71–23.92 h |

## Sources

- Entries: Yacht Scoring event 50036 (JSON) and Regatta Network event 27278 (HTML). Only boat name, sail number, design and class are kept.
- Start and finish: the 2025 Spinnaker Cup and 2024 Queen's Cup sailing instructions.
- Depth: Coastal Relief Model volumes 6 and 7 joined on one grid for the Spinnaker Cup (volume 7 stops at 37°N); ETOPO 2022 at 15 arc-seconds minus a lake level of 176.8 m for Lake Michigan.
- Currents: none on Lake Michigan (HYCOM is an ocean model). The Spinnaker Cup should have HYCOM currents, but the HYCOM server returned HTTP 500 and 502 errors on five tries, so that leg ships with still water; its credits and leg note say so.

## Changes to the race's own lines

- Spinnaker Cup start: a north–south line off Crissy Field, 0.9 nm west of the St. Francis Yacht Club start, so each boat's start is its own crossing heading for the Golden Gate. The sailing instructions give no per-class start times, so every class takes the first start, 10:45 PDT.
- Spinnaker Cup finish: the race's line, extended from 0.17 nm to 0.5 nm. Several boats' AIS tracks pass just outside the real line's ends.
- Queen's Cup: 0.6 nm start and 1.5 nm finish lines square to the course through the sailing instructions' marks. Starts are each fleet's first start (14:35, 16:05 or 16:35 CDT).

## Open points

- Skipped boats mostly have AIS tracks that end short of the finish (retired, or AIS off).
- Rebuild the Spinnaker Cup current stage when HYCOM answers again: `python -m legpack.build legs/spinnaker-cup-2025.json current manifest` after removing `current_source` and `current_credit` from the leg file.
- Wind accuracy for both legs is in `.scratch/wind-accuracy/findings.md`. On Lake Michigan ERA5 runs strong mid-lake, so ideal boat times there are optimistic.
