# Fleet tracks come only from redistributable sources or the player

Hosted leg packages use fleet tracks only from sources that allow redistribution (MarineCadastre AIS, which covers US waters only) or that the tracker and event organizer shared with written permission. The game also imports GPX or CSV tracks the player supplies, kept in the browser. Scraping PredictWind or YB Tracking was rejected: both have no export or API, their endpoints are undocumented, and their terms likely forbid redistribution.

## Consequences

- The first playable leg sits in US waters until a tracker or organizer grants permission (for example PredictWind for the Baja Ha-Ha).
- Legs that leave US waters lose their AIS ghosts at the boundary unless tracker data is licensed.
