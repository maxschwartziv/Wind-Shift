# Sailing navigation game

A single-player strategic navigation game. The player sails their own boat through one leg of a past race or rally, in that event's historical wind and current, against the real participants replayed from their tracks.

## Events and courses

**Event**:
A past race or rally that the game can replay. It holds one or more legs and the event rules.
_Avoid_: Regatta, competition

**Race**:
An event where motoring is not allowed.

**Rally**:
An event where motoring is allowed, usually with a motoring penalty factor.
_Avoid_: Cruise, passage

**Leg**:
One start-to-finish segment of an event, with its own start time, start line, finish line and optional marks. It is the unit the player plays.
_Avoid_: Stage, race (for a single segment)

**Start line**:
A line between two points that the boats cross at the leg's start time.

**Finish line**:
A line between two points that ends the leg. Rally legs that end at an anchorage use a line across its entrance. A leg may end at a line short of the event's real finish where the fleet's tracks stop.

**Mark**:
A point the boats must round, in order, between start and finish.
_Avoid_: Waypoint (reserved for the player's own steering aids)

**Event rules**:
The rules that vary by event: whether motoring is allowed and the motoring penalty factor.

## Boats

**Player boat**:
The boat the user sails, defined by a boat profile.
_Avoid_: User boat, own boat

**Ghost boat**:
A real participant in a leg, replayed from its recorded track. It does not react to the player.
_Avoid_: Competitor, AI boat, opponent

**Fleet**:
All ghost boats in a leg.

**Ideal boat**:
A simulated boat with the player's boat profile that sails an isochrone route to the finish. Both move in the actual weather. The **actual ideal** plans its route in the actual weather, with perfect information. The **forecast ideal** plans in the period forecast as issued and plans again each time a new forecast comes out. Both race beside the fleet.
_Avoid_: AI boat

**Ghost trail**:
The line a ghost boat leaves behind as it moves.

**Boat profile**:
Everything that defines a player boat: name, polar, draft, tack penalty, gybe penalty and motoring speed.
_Avoid_: Boat settings, boat config

**Polar**:
A table of a boat's speed through the water for each true wind angle and true wind speed, assuming perfect sail trim.
_Avoid_: Polar diagram (for the table), performance curve

**Draft**:
The depth of the boat's keel below the waterline, in meters.

**Tack penalty**, **Gybe penalty**:
The fixed time a boat loses each time it tacks or gybes.

**Motoring speed**:
The boat's speed through the water, in knots, when motoring.

## Wind, water and motion

**True wind speed (TWS)**:
The wind speed the boat feels over the moving water, in knots.

**True wind angle (TWA)**:
The angle between the boat's heading and the direction the true wind comes from, 0–180° on either side.

**True wind direction (TWD)**:
The compass direction the true wind comes from, in degrees.

**Apparent wind**:
The wind felt on the moving boat: the true wind plus a headwind equal to the boat's speed. Its speed is the **apparent wind speed (AWS)** and its angle to the heading the **apparent wind angle (AWA)**.

**No-go zone**:
The wedge either side of the true wind that the boat will not sail into. By default its half-angle is the boat's best upwind angle, the TWA where its polar gives the most speed toward the wind; the player can set their own angle.

**Close hauled**:
A steering mode: the boat sails along the no-go edge on the present tack and tacks by itself when the other tack gives clearly more VMC or the present tack would run aground. It stays on until the player turns it off.

**Course over ground (COG)**:
The boat's direction of travel relative to the seabed, in degrees.

**Speed through the water (STW)**:
The boat's speed relative to the water around it, in knots.
_Avoid_: Boat speed (ambiguous)

**Speed over ground (SOG)**:
The boat's speed relative to the seabed, in knots: its motion through the water plus the current.

**Velocity made good on course (VMC)**:
The part of the boat's velocity over ground that points at the next waypoint, mark or the finish, in knots.
_Avoid_: VMG (VMC is toward a destination, VMG is toward the wind)

**Suggested heading**:
The heading that gives the highest VMC toward the next waypoint (or the finish) right now without grounding in the near future, judged in the period forecast (or the actual weather in perfect forecast mode). The boat then moves in the actual weather. When motoring, the heading that steers straight at the next mark, corrected for current.

**Boat instrument**:
The on-screen dial, north up, that plots SOG for every heading at the player boat's present position. It also marks the present heading, the suggested heading, the bearing to the next target, the true wind and the no-go zone.
_Avoid_: Polar (the plot is not the table), SOG plot

**Leg instrument**:
The same dial drawn for one leg of the route, in the wind and current forecast at the leg's middle for the time the boat gets there. It shows the forecast heading, SOG, STW, TWD, TWS, AWA, AWS, distance, duration and VMC for that leg.

**Actual weather**:
The wind and current the boats sail in, reconstructed after the fact.

**Period forecast**:
The weather forecast as it was issued during the event, shown to the player and updated every 6 game hours. It differs from the actual weather the way the real fleet's forecasts did.
_Avoid_: Forecast (alone, when the source matters)

**Measured wind**:
The actual wind within 2 nm of the player boat, which the boat's instruments read. Inside that circle the wind map shows it instead of the period forecast, and steering decisions use it.

**Imported weather**:
Wind or current read from a GRIB file the player chooses, replacing the leg's forecast wind, actual wind or current for the session.

**Perfect forecast**:
An easy mode where the player sees the actual weather ahead instead of the period forecast. Results record which mode was used.

**Projected track**:
The path the player boat will follow over the next 30 game minutes if it keeps its present heading.

## Steering

**Waypoint**:
A point the player plots on the map for the boat to sail to.
_Avoid_: Mark (a mark belongs to the course)

**Route**:
The player's waypoints in order.

**Route mode**:
The boat sails the route on its own, steering the suggested heading toward the next waypoint and then the finish. It is the default way to control the boat.

**Heading mode**:
Steering to a fixed compass heading.

**TWA lock**:
Steering to a fixed true wind angle, so the heading follows wind shifts.

**Isochrone**:
The line joining every point a boat can reach in the same time from a start point.

**Isochrone route**:
The fastest route to the finish found by growing isochrones one time step at a time until one crosses the finish line, then tracing back.

**Gate**:
A line across the water at a turn of the water path, such as a harbor entrance or the sea off a headland. Isochrone routes pass through each gate in order on the way to the finish.

**Shortest tack**:
The shortest time the player allows between two tacks or gybes, applied to route mode and to the ideal boats.

**Motoring**:
Moving under engine at motoring speed instead of sailing. Allowed only in rallies.

## Time and results

**Race clock**:
The simulated time shared by the player boat, the fleet and the weather. It can be paused and sped up.

**Time compression**:
How many game seconds pass per real second.

**Elapsed time**:
Time from a boat's own crossing of the start line to its crossing of the finish line. Results rank boats by elapsed time, not by finishing order.

**Motoring penalty factor**:
The multiplier, set by the event rules, applied to time spent motoring.

**Corrected time**:
Elapsed time plus motoring time multiplied by the motoring penalty factor.

**Grounding**:
The player boat reaching water shallower than its draft, or land. It ends the leg.
_Avoid_: Crash, collision

**Did not finish (DNF)**:
The result of a leg that ended without crossing the finish line.

**Depth alarm**:
A warning when the depth under the keel drops below a set threshold.
