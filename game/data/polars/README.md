# Starter polars

These `.pol` files come from the OpenCPN Weather Routing plugin, https://github.com/seandepagnier/weather_routing_pi/tree/master/data/polars, downloaded 11 November 2026. The plugin is licensed under GPL-3.0 (`COPYING.txt`). The repository does not record where the polar data came from.

| File | Used for |
|---|---|
| `Alberg_35.pol` | Pearson Alberg 35; stand-in for the Alberg 30 |
| `First_40.7.pol` | Beneteau First 40.7 |
| `Catalina_36.pol` | Stand-in for the Catalina 400 and Catalina 35 |

`Alberg_35.pol` and `Catalina_36.pol` cover 52–150° only. The game adds a zero row at 0° and a 180° row at 85 % of the 150° row (`scripts/polar.gd`).
