# Wind Shift

Wind Shift is a sailing navigation game. You race a real fleet on its own course, in the wind of that day, and plan from the forecast that was issued at the time.

The fleet replays from recorded AIS tracks (the position reports boats broadcast). The actual wind comes from ERA5 hourly data, and you plan from the GFS forecast as issued. Your boat sails to its polar, and sail trim is always perfect, so every decision is a navigation decision. Two ideal boats race with you: one plans in the actual wind with perfect information, and one plans from the forecast.

The game ships with three races:

| Race | Course | Date |
|---|---|---|
| Queen's Cup | Milwaukee to South Haven, across Lake Michigan | 28 June 2024 |
| Spinnaker Cup | San Francisco to Monterey | 24 May 2025 |
| Light-wind pocket test | A made-up course for testing routing | none |

A fourth race, Newport to Ensenada (25 April 2025), plays behind the main menu and is hidden from the race lists.

## Play in a browser

1. Download `Wind-Shift-web.zip` from the [latest release](https://github.com/maxschwartziv/Wind-Shift/releases/latest).
2. Unzip it.
3. Serve the `Wind-Shift` folder over HTTP and open the page. Opening `index.html` straight from disk does not work. With Python installed:

   ```bash
   python -m http.server 8000 --directory Wind-Shift
   ```

   Then open http://localhost:8000 in a desktop browser.

The download is 120 MB, most of it map imagery and weather for the three races.

To host the game on a website, upload the contents of the `Wind-Shift` folder to any static web host.

## Run the game from source

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (standard build, not .NET).
2. Open Godot, choose **Import**, and select `game/project.godot`.
3. Press **F5** to run from the main menu.

The first time you open the project, Godot imports the map tiles and sounds. This takes a few minutes.

To run without the editor:

```bash
godot --path game
```

### Web build

1. In Godot, install the export templates: **Editor > Manage Export Templates > Download and Install**.
2. Choose **Project > Export > Add > Web**, then **Export Project**.
3. Serve the export folder over HTTP. Opening the HTML file from disk does not work. One way is:

```bash
python -m http.server 8000 --directory build/web
```

The project uses the Compatibility renderer and no threads, so the web build runs without special server headers.

## Play

A new race opens paused, with the whole course in view.

1. Pick a start time in the RACE panel.
2. Click the map to place waypoints to the finish line. The wind colors show the forecast.
3. Press Space to start the race clock.

Once the race runs, your boat measures the actual wind within 2 nautical miles (nm) of it, and that wind sets its speed. The forecast can be wrong, so watch the measured wind and change course.

| Input | Action |
|---|---|
| Left click on the map | Add a waypoint |
| Left click on a waypoint | Show the forecast for the time you arrive there |
| Right click | Remove a waypoint |
| Click on the polar | Steer that heading |
| Drag an edge of the red no-go wedge | Set your no-go angle |
| T | Next steering mode |
| Left / Right | Turn 1° (10° with Shift) |
| Enter | Steer the suggested heading |
| Space | Pause or run the race clock |
| = / - | Faster / slower clock |
| [ / ] | Wind map one hour back / ahead |
| F | Follow the boat |
| Escape | Settings |
| Wheel, drag or middle button | Zoom and pan the map |

Settings lets you change these keys, the text size, sound and the shortest tack time. The **?** button on the instrument opens help pages with animations for polars, wind terms, steering modes and route planning.

## Tests

Headless tests run from the repository root:

```bash
godot --headless --path game --script res://tests/sim_test.gd
godot --headless --path game --script res://tests/leg_test.gd -- --leg=queens-cup-2024
godot --headless --path game --script res://tests/close_hauled_test.gd
godot --headless --path game --script res://tests/start_time_test.gd
godot --headless --path game --script res://tests/ghost_state_test.gd
```

Windowed tests open a game window:

```bash
godot --path game res://tests/frame_test.tscn
godot --path game --script res://tests/waypoint_click_test.gd
godot --path game --script res://tests/attract_test.gd
```

Each test prints its checks, and a failed check prints `FAIL`. The tests do not change your saved settings.

## Add a race

Races are built offline into leg packages under `game/packages/`. The game reads only these files and calls no data services while it runs. The pipeline in `pipeline/` downloads the data and builds a package. See [pipeline/README.md](pipeline/README.md) for every stage and source.

1. Set up Python. The pipeline was built with Python 3.13.

   ```bash
   cd pipeline
   python -m venv .venv
   .venv/Scripts/python -m pip install -r requirements.txt
   ```

   On macOS or Linux, use `.venv/bin/python` in place of `.venv/Scripts/python`.

2. Copy a leg file in `pipeline/legs/` and edit it for the new race:
   - start and finish lines, as [latitude, longitude] pairs
   - `start_utc`, the time zone and the UTC offset
   - `bounds`, the area the package covers
   - `data_window_utc`, the hours of weather to fetch
   - the depth source, and the current source (`"none"` for lakes)
   - `fleet.ais_dates`, the days of AIS data to download
3. Make the entry list `pipeline/data/<id>_entries.csv` with the columns `name,sail,model,class,start_utc`. `tools/entries.py` shows how the shipped races' lists were fetched from the race results pages.
4. Build the package:

   ```bash
   .venv/Scripts/python -m legpack.build legs/<id>.json
   ```

   Each AIS day file covers all U.S. waters, so the `ais` stage takes several minutes per day.
5. Check the new package:

   ```bash
   godot --headless --path game --script res://tests/leg_test.gd -- --leg=<id>
   ```

The new race appears in the race list the next time the game starts.

## Data sources

| Data | Source | License |
|---|---|---|
| Fleet tracks | [MarineCadastre](https://marinecadastre.gov/ais/) AIS, from the U.S. Coast Guard Nationwide AIS | U.S. public domain |
| Actual wind | ERA5 reanalysis (Copernicus Climate Change Service), served by [Open-Meteo](https://open-meteo.com/) | CC BY 4.0 |
| Forecast wind | NOAA GFS 0.25°, as issued, from [NOAA Open Data Dissemination on AWS](https://registry.opendata.aws/noaa-gfs-bdp-pds/) | U.S. public domain |
| Current | [HYCOM](https://www.hycom.org/) ESPC-D-V02 | U.S. public domain |
| Depth | NOAA NCEI Coastal Relief Model and ETOPO 2022 | U.S. public domain |
| Imagery | [EOxCloudless 2016](https://cloudless.eox.at) by EOX IT Services GmbH, contains modified Copernicus Sentinel data 2016 | CC BY 4.0 |

Each package lists its credits in `leg.json`, and the game shows them at the bottom of the screen. The Open-Meteo API is free for non-commercial use; a commercial build should fetch ERA5 from the Copernicus Climate Data Store or use an Open-Meteo subscription.

The boat polars in `game/data/polars/` carry their own license; see `game/data/polars/COPYING.txt`. The title font, Archivo Black, is under the SIL Open Font License; see `game/data/fonts/OFL.txt`. The game code is under the MIT License in `LICENSE`.

## Repository layout

| Folder | Content |
|---|---|
| `game/` | The Godot project: scenes, scripts, shaders, polars, sounds and leg packages |
| `game/tests/` | Headless and windowed tests |
| `pipeline/` | Python pipeline that builds leg packages |
| `docs/adr/` | Architecture decision records |
| `GLOSSARY.md` | Sailing and game terms used in the code and the help pages |
| `store/` | Store thumbnail and cover images |
