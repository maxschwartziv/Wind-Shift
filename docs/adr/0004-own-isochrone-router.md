# The isochrone router is written for this game, not ported

The ideal boats plan with an isochrone router written in GDScript for this game. The open routers that do the job (OpenCPN Weather Routing, dakk/libweatherrouting, gweatherrouting) are GPL-3.0, and porting their code would put the game's code under GPL-3.0. ADR 0003 already keeps the GPL polars as separate data files for the same reason. hrosailing (Apache-2.0) was rejected because it computes reachable points but does not route to a destination. The router follows the published method (time steps, pruning by bearing sector from the start, trace back from the first finish crossing) and was written from that description, not from those projects' code.

## Consequences

- The router's pruning keeps the point furthest from the start in each bearing sector, which cannot find a way out of a harbor or around a headland: a boat that reached away from the exit counts as further than one beating toward it. Routes therefore go leg by leg through gates at the turns of the shortest water path (found with Godot's AStarGrid2D on the depth grid). On the Spinnaker Cup this took the actual ideal from 12.6 h with a route across the Presidio to 11.5 h out through the Golden Gate.
- Near shore (water under 200 m deep) each route segment is checked for land every 50 m.

- The router runs a few milliseconds per frame because the web build has no threads. One route for the Newport to Ensenada leg takes about 4 to 8 s of computing.
- On a steady reach the router finds routes within about 0.2% of the best-VMC rule, limited by its step sizes. On the test-pocket leg it beats that rule by 31 minutes by sailing around the light-wind pocket.
