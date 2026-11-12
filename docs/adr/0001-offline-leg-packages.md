# Event data is preprocessed offline into static leg packages

An offline pipeline fetches historical wind, current, depth, imagery and fleet tracks and bakes each leg into a static package hosted with the game. The game never calls data APIs at runtime. Most sources (ERA5, Copernicus Marine, MarineCadastre) need accounts or keys, send no CORS headers, or are too slow to query from a browser, and baked packages keep every replay of a leg identical.

## Consequences

- Adding an event means running the pipeline and publishing a new package.
- Package size is a design limit: about 20 MB per leg (wind 0.25° hourly, currents 1/12° 3-hourly).
- The map's attributions (Copernicus, GEBCO, OSM, Sentinel-2 cloudless) come from the package's sources.
