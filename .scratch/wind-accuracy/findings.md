# Wind accuracy against NOAA observations, Newport to Ensenada 2025

Measured on 11 November 2026 with `pipeline/tools/wind_accuracy.py` over the race window, 25 April 2025 18:00 to 26 April 2025 12:00 UTC. Observed speeds are scaled to 10 m with the power law (10/z)^0.11. Direction error counts only readings of 2 m/s or more.

| Station | Where | Anemometer | Readings | Mean observed | ERA5 bias | ERA5 RMS error | ERA5 direction error | GFS bias | GFS RMS error | GFS direction error |
|---|---|---|---|---|---|---|---|---|---|---|
| NDBC 46086 | San Clemente Basin, offshore on the course | 3.2 m | 109 | 10.8 kn | −0.6 kn | 2.4 kn | 7° | −1.9 kn | 2.7 kn | 8° |
| LJPC1 | La Jolla, at the shore | 20.2 m | 18 | 7.3 kn | +0.1 kn | 1.5 kn | 22° | +0.3 kn | 1.9 kn | 13° |

ERA5 is the game's "actual" wind; GFS is the period forecast. Bias is model minus observation; RMS error is the root-mean-square speed error.

## Reading

- Offshore, ERA5 runs about 0.6 kn light, and its speed is off by about 2.4 kn in a typical reading. Direction is within about 7°.
- ERA5 is a 0.25° (about 25 km) reanalysis with hourly values. It cannot show features smaller than its grid: sea-breeze edges near the coast, wind shadows behind headlands, or gusts. The shore station's 22° direction error reflects that.
- The GFS forecast runs about 1.9 kn light offshore, so the forecast ideal and the player see a lighter forecast than the boats sailed in.
- SDBC1 (San Diego Bay) is inside the wind grid but gave no usable readings for the race window.

# Queen's Cup 2024, Lake Michigan

Race window 28 June 2024 19:30 to 29 June 2024 18:00 UTC, same method.

| Station | Where | Anemometer | Readings | Mean observed | ERA5 bias | ERA5 RMS error | ERA5 direction error | GFS bias | GFS RMS error | GFS direction error |
|---|---|---|---|---|---|---|---|---|---|---|
| NDBC 45007 | Mid-lake, on the course | 3.6 m | 136 | 9.2 kn | +3.6 kn | 5.0 kn | 44° | +3.3 kn | 5.2 kn | 46° |
| NDBC 45013 | Off Milwaukee, near the start | 2.0 m | 46 | 9.6 kn | +0.3 kn | 3.0 kn | 22° | −0.3 kn | 3.3 kn | 16° |
| MLWW3 | Milwaukee breakwater | 7.3 m | 134 | 6.7 kn | +2.7 kn | 4.0 kn | 25° | +2.4 kn | 3.6 kn | 23° |
| NDBC 45168 | Off South Haven, near the finish | 3.0 m | 120 | 9.2 kn | +0.0 kn | 4.0 kn | 31° | +2.0 kn | 4.8 kn | 28° |
| NDBC 45029 | Off Holland, east shore | 3.0 m | 132 | 11.3 kn | −0.4 kn | 2.3 kn | 22° | +0.3 kn | 2.7 kn | 23° |

## Reading

- On the lake the models do much worse than off California. Mid-lake, ERA5 runs 3.6 kn strong with a 44° average direction error.
- A likely cause: in late June the lake water is colder than the air, so the air over the lake is stable and lighter than the models' surface layer shows. This is a known physical effect; it was not measured here.
- The ideal boats sail in ERA5 wind, so on this leg they likely sail in more wind than the real fleet had. Their times are optimistic.

# Spinnaker Cup 2025, San Francisco to Monterey

Race window 24 May 2025 17:45 to 25 May 2025 15:00 UTC, same method.

| Station | Where | Anemometer | Readings | Mean observed | ERA5 bias | ERA5 RMS error | ERA5 direction error | GFS bias | GFS RMS error | GFS direction error |
|---|---|---|---|---|---|---|---|---|---|---|
| NDBC 46026 | San Francisco buoy, 18 nm offshore | 4.1 m | 128 | 14.2 kn | +2.8 kn | 3.8 kn | 9° | +4.0 kn | 5.0 kn | 12° |
| FTPC1 | Fort Point, Golden Gate | 7.4 m | 213 | 10.5 kn | +0.2 kn | 2.4 kn | 25° | +1.0 kn | 2.6 kn | 22° |

## Reading

- Offshore, ERA5 ran 2.8 kn strong; GFS ran 4.0 kn strong.
- At the Golden Gate the speed is close on average, but the direction is off by about 25°: the gap funnels the wind along its axis, which a 25 km grid cannot show.
- Across the three legs, ERA5 is typically within 2.4–5 kn RMS of what the boats felt, with a bias from −0.6 to +3.6 kn depending on place. Treat the "actual" wind as a good regional picture, not as what one boat measured.
