# Leg package pipeline

Builds a static leg package for the game from free historical data (ADR 0001). Output goes to `../game/packages/<leg id>/`.

## Setup

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
```

## Build

```bash
.venv/Scripts/python -m legpack.build legs/queens-cup-2024.json
```

Pass stage names after the leg file to run only those stages: `ais match fleet wind forecast current depth tiles manifest`. Run `manifest` last; it merges the stage headers into `leg.json` and prints sanity checks.

The `ais` stage downloads the AIS days and the `match` stage pairs them with the entry list in `data/<id>_entries.csv`. The repository keeps the entry lists and match files; the AIS extracts and depth downloads are fetched again on the first build. The Newport to Ensenada leg was built with the earlier scripts in `spike/`.

## Package contents

| File | Content | Source |
|---|---|---|
| `leg.json` | Course, rules, grid headers, credits | Leg definition in `legs/` |
| `fleet.json` | Ghost boats: class start, elapsed time to the finish line, track as [seconds after start, lat, lon] | MarineCadastre AIS |
| `wind.bin` | Actual wind, float32 (east, north) m/s, [hour][row][col] | ERA5 via Open-Meteo |
| `forecast_<run>.bin` | Period forecast per GFS run, same layout as `wind.bin` | NOAA GFS 0.25° on AWS |
| `current.bin` | Surface current, float32 (east, north) m/s, [hour][row][col] | HYCOM ESPC-D-V02 |
| `depth.bin` | Elevation in decimeters, int16, water negative, [row][col] | NOAA Coastal Relief Model vol. 6 and 7, or ETOPO 2022 |
| `tiles/z/x/y.jpg` | Imagery, Web Mercator, zoom 6–12; zoom 6–10 also cover a wider backdrop box so a zoomed-out view fills the screen | EOxCloudless 2016 |

Grid rows run north to south and columns west to east. Package times are seconds after `start_utc`.

## Source notes

- Open-Meteo data is CC BY 4.0, so baked wind in a package can be redistributed, commercially included, with the credit in `leg.json`. The free Open-Meteo API itself is for non-commercial calls. The pipeline calls it once per leg at build time. For commercial builds, use an Open-Meteo API subscription or fetch ERA5 from the Copernicus Climate Data Store (free account).
- HYCOM stands in for Copernicus Marine, which needs an account.
- The Coastal Relief Model covers 32–37 N, 126–114 W only. Legs outside it need GEBCO or ETOPO.

## Other tools

| Script | What it does |
|---|---|
| `tools/make_audio.py` | Synthesizes the sound effects and music loop into `game/data/audio/`. |
| `tools/make_test_leg.py` | Builds the synthetic `test-pocket` leg: varying wind and a light-wind pocket on the direct line. |
| `tools/make_test_gribs.py` | Writes GRIB1 and GRIB2 test files with ecCodes for `game/tests/grib_test.gd`. |
| `tools/entries.py` | Fetches the Spinnaker Cup and Queen's Cup entry lists into `data/<id>_entries.csv`. |
| `tools/finish_check.py` | Lists how close each matched boat's AIS track comes to the finish line's midpoint, to help place a leg's finish line. |
| `tools/wind_accuracy.py` | Compares a leg's ERA5 and GFS wind with NOAA NDBC observations over the race window. |

## Stages for new legs

`ais` downloads the MarineCadastre days in `fleet.ais_dates` and keeps rows inside the leg bounds. `match` pairs each row of `fleet.entries_csv` (name, sail, model, class, start_utc) with an AIS vessel of the same normalized name. `depth_source` picks `crm_vol6`, `crm_vol7` or the ETOPO 2022 tiles; lakes also set `lake_level_m` and `current_source: "none"`.
