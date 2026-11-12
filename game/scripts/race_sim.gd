class_name RaceSim
extends RefCounted
## The player boat on one leg. Advances in fixed 10 s steps of game time, so a run with the same
## inputs gives the same result at any time compression.

signal ended(state: String)
signal maneuver(kind: String)  # "tack" or "gybe"
signal waypoint_reached

const STEP_S := 10.0
const LOOKAHEAD_S := 1800.0
const LOOKAHEAD_STEP_S := 60.0
const GROUND_CHECK_S := 10.0
## Steering keeps this much water under the keel; only the boat's actual grounding uses the bare draft.
const CLEARANCE_M := 1.5
const SAVE_EVERY_S := 3600.0

enum Mode { ROUTE, HEADING, TWA_LOCK, CLOSE_HAULED }
enum WindSource { ACTUAL, FORECAST }

const AUTO_EVERY_S := 60.0
## A waypoint counts as reached inside this distance.
const ARRIVE_NM := 0.15
## The boat measures the actual wind within this distance of itself, so steering decisions there use it
## even when the rest of the map shows the forecast.
const MEASURE_NM := 2.0
## Route mode keeps its tack unless the other tack gives at least this much more VMC.
const AUTO_TACK_GAIN := 1.10

var pkg: LegPackage
var boat: BoatProfile

# Race clock: seconds after the leg's start time.
var t := 0.0
## Race time the player chose to start (seconds after the leg's first gun); elapsed time runs from it.
var start_t := 0.0
var pos := Vector2.ZERO  # (lat, lon)
var heading := 180.0
var mode := Mode.ROUTE
## Waypoints the player plotted, (lat, lon), sailed in order in route mode.
var waypoints: Array[Vector2] = []
## Wind used for steering decisions: the suggested heading, route mode, the projected track and the
## instrument curve. The boat always moves in the actual wind, whatever this is set to.
## FORECAST: the period forecast, what the fleet knew. ACTUAL: perfect information.
var steer_source := WindSource.FORECAST
var _next_auto_t := 0.0
var twa_lock := 0.0  # signed TWA held in TWA lock; positive means wind over starboard
var motoring := false
var motoring_s := 0.0
var penalty_left_s := 0.0
var min_tack_s := 0.0
## Close hauled mode: which tack, +1 starboard (wind over the right side), -1 port.
var close_side := 1.0
## Close hauled mode tacks when the present tack would ground within this time, checked every
## CLOSE_CHECK_S, so in a channel it short-tacks near each shore the way a crew would.
const CLOSE_GROUND_S := 90.0
const CLOSE_CHECK_S := 20.0
## The player's no-go angle in degrees either side of the wind; 0 uses the polar's best upwind angle.
## Route mode and the suggested heading never sail closer to the wind than this.
var no_go_deg := 0.0  # route mode waits this long after a tack or gybe before it tacks or gybes again
var _last_maneuver_t := -INF
var state := "racing"  # racing, finished, dnf
var end_reason := ""
var elapsed_s := 0.0
var trail: PackedVector2Array = []  # (lat, lon) every 60 s
var trail_t: PackedFloat64Array = []  # race time of each trail point

# Conditions at the boat, refreshed every step.
var wind := Vector2.ZERO  # air over ground, m/s (east, north)
var current := Vector2.ZERO  # water over ground, m/s
var tws := 0.0  # kn, wind over the moving water
var wind_from := 0.0  # deg
var twa := 0.0  # signed deg
var stw := 0.0  # kn
var velocity := Vector2.ZERO  # over ground, m/s
var depth := 0.0  # m

var _accum := 0.0
var _last_trail_t := -INF
var _saves: Array[Dictionary] = []


func _init(p: LegPackage, b: BoatProfile) -> void:
	pkg = p
	boat = b
	var a := p.start_line[0]
	var c := p.start_line[1]
	pos = (a + c) / 2.0
	_refresh()
	heading = Geo.bearing(Geo.offset_m(pos, target()))
	_refresh()
	trail.append(pos)
	trail_t.append(t)
	_save()


## Start the boat at race time t0 instead of the first gun: clock, trail and saves begin there.
func start_at(t0: float) -> void:
	t = t0
	start_t = t0
	_next_auto_t = t0
	_last_trail_t = -INF
	trail = PackedVector2Array([pos])
	trail_t = PackedFloat64Array([t0])
	_saves.clear()
	_refresh()
	_save()


func motoring_allowed() -> bool:
	return bool(pkg.info["rules"]["motoring_allowed"])


## Next waypoint, else next mark, else the nearest point of the finish line.
func target() -> Vector2:
	if waypoints.size() > 0:
		return waypoints[0]
	if pkg.marks.size() > 0:
		return pkg.marks[0]
	return Geo.nearest_on_segment(pos, pkg.finish_line[0], pkg.finish_line[1])


func distance_to_finish_nm() -> float:
	return Geo.distance_nm(pos, target())


func vmc_kn() -> float:
	var to := Geo.offset_m(pos, target()).normalized()
	return velocity.dot(to) / Geo.MS_PER_KN


func sog_kn() -> float:
	return velocity.length() / Geo.MS_PER_KN


func cog() -> float:
	return Geo.bearing(velocity)


## Wind and current at a point, and the wind the boat feels over the moving water.
## True where the boat measures the wind itself: within MEASURE_NM of it, at the present time.
func measures(at: Vector2, time: float) -> bool:
	return absf(time - t) < 60.0 and Geo.distance_nm(at, pos) <= MEASURE_NM


## Moving the boat always uses ACTUAL, the default; steering decisions pass steer_source.
func conditions(at: Vector2, time: float, source: int = WindSource.ACTUAL) -> Dictionary:
	if source == WindSource.FORECAST and measures(at, time):
		source = WindSource.ACTUAL
	var w: Vector2
	if source == WindSource.FORECAST:
		w = pkg.forecast_at(time)["grid"].sample(at.x, at.y, time)
	else:
		w = pkg.wind.sample(at.x, at.y, time)
	var c := pkg.current.sample(at.x, at.y, time)
	var rel := w - c
	return {"wind": w, "current": c, "tws": rel.length() / Geo.MS_PER_KN, "from": Geo.bearing(-rel)}


## Speed through the water (kn) on a heading in given conditions, ignoring penalties.
func boat_speed(h: float, cond: Dictionary) -> float:
	if motoring:
		return boat.motoring_kn
	return boat.polar.speed(Geo.wrap180(cond["from"] - h), cond["tws"])


## Velocity over ground (m/s) on a heading in given conditions.
func ground_velocity(h: float, cond: Dictionary) -> Vector2:
	return Geo.heading_vec(h) * boat_speed(h, cond) * Geo.MS_PER_KN + cond["current"]


func _refresh() -> void:
	var cond := conditions(pos, t)
	wind = cond["wind"]
	current = cond["current"]
	tws = cond["tws"]
	wind_from = cond["from"]
	if mode == Mode.TWA_LOCK and not motoring:
		heading = fposmod(wind_from - twa_lock, 360.0)
	elif mode == Mode.CLOSE_HAULED and not motoring:
		# Hold the no-go edge on the present tack; positive TWA is wind over starboard.
		heading = fposmod(wind_from - close_side * close_hauled_angle(), 360.0)
	twa = Geo.wrap180(wind_from - heading)
	stw = 0.0 if penalty_left_s > 0.0 else boat_speed(heading, cond)
	velocity = Geo.heading_vec(heading) * stw * Geo.MS_PER_KN + current
	depth = pkg.depth_at(pos.x, pos.y)


func set_heading(h: float) -> void:
	if state != "racing":
		return
	var before := twa
	heading = fposmod(h, 360.0)
	if mode == Mode.TWA_LOCK:
		twa_lock = Geo.wrap180(wind_from - heading)
	_check_maneuver(before, Geo.wrap180(wind_from - heading))
	_refresh()


func set_mode(m: Mode) -> void:
	mode = m
	if mode == Mode.TWA_LOCK:
		twa_lock = twa
	if mode == Mode.CLOSE_HAULED:
		close_side = 1.0 if twa >= 0.0 else -1.0
		var before := twa
		_refresh()
		_check_maneuver(before, twa)
		_next_auto_t = t + CLOSE_CHECK_S
	if mode == Mode.ROUTE:
		_next_auto_t = t
		_auto_steer()


## Half-angle of the no-go zone in degrees: the player's, or the polar's best upwind angle now.
func close_hauled_angle() -> float:
	return no_go_deg if no_go_deg > 0.0 else boat.polar.beat_angle(tws)


## Re-apply the steering mode after the player changes a setting such as the no-go angle.
func reapply() -> void:
	_refresh()


## Close hauled mode: tack when the present tack would ground soon, or when the other tack gives
## clearly more VMC toward the next target and the shortest tack time has passed.
func _close_hauled_tack() -> void:
	if motoring:
		return
	var cond := conditions(pos, t, steer_source)
	var angle := close_hauled_angle()
	var to := Geo.offset_m(pos, target()).normalized()
	var here_h := fposmod(float(cond["from"]) - close_side * angle, 360.0)
	var other_h := fposmod(float(cond["from"]) + close_side * angle, 360.0)
	var here_v := ground_velocity(here_h, cond)
	var other_v := ground_velocity(other_h, cond)
	var here_grounds := _ground_time(here_v, CLOSE_GROUND_S) < INF
	var other_grounds := _ground_time(other_v, CLOSE_GROUND_S) < INF
	var gain := other_v.dot(to) > maxf(here_v.dot(to), 0.0) * AUTO_TACK_GAIN + 0.05
	var allowed := t - _last_maneuver_t >= min_tack_s
	if (here_grounds and not other_grounds) or (gain and allowed and not other_grounds):
		close_side = -close_side
		var before := twa
		_refresh()
		_check_maneuver(before, twa)


## Route mode: take the best-VMC heading toward the next waypoint (or the finish), but stay on this tack unless the other tack
## is clearly better, so the boat does not tack back and forth as the bearing to the finish moves.
func _auto_steer() -> void:
	var s := suggestion()
	if s["heading"] < 0.0:
		return
	var h: float = s["heading"]
	if s["same_tack_heading"] >= 0.0 and s["vmc_kn"] < s["same_tack_vmc_kn"] * AUTO_TACK_GAIN:
		h = s["same_tack_heading"]
	elif s["same_tack_heading"] >= 0.0 and t - _last_maneuver_t < min_tack_s:
		h = s["same_tack_heading"]  # too soon after the last tack or gybe
	if absf(Geo.wrap180(h - heading)) > 0.5:
		var before := twa
		heading = fposmod(h, 360.0)
		_check_maneuver(before, Geo.wrap180(wind_from - heading))
		_refresh()


func add_waypoint(at: Vector2) -> void:
	waypoints.append(at)
	_next_auto_t = t


## Remove the waypoint nearest to a point if it lies within max_nm. Returns true if one was removed.
func remove_waypoint_near(at: Vector2, max_nm: float) -> bool:
	var best := -1
	var best_d := max_nm
	for i in waypoints.size():
		var d := Geo.distance_nm(at, waypoints[i])
		if d < best_d:
			best = i
			best_d = d
	if best < 0:
		return false
	waypoints.remove_at(best)
	_next_auto_t = t
	return true


func clear_waypoints() -> void:
	waypoints.clear()
	_next_auto_t = t


func set_motoring(on: bool) -> void:
	motoring = on and motoring_allowed()
	_refresh()


func _check_maneuver(before: float, after: float) -> void:
	if motoring or signf(before) == signf(after) or before == 0.0 or after == 0.0:
		return
	if absf(before) < 90.0 and absf(after) < 90.0:
		penalty_left_s += boat.tack_penalty_s
		_last_maneuver_t = t
		maneuver.emit("tack")
	elif absf(before) >= 90.0 and absf(after) >= 90.0:
		penalty_left_s += boat.gybe_penalty_s
		_last_maneuver_t = t
		maneuver.emit("gybe")


## Race time for drawing: the last step plus the game time since it, so the boats and the clock move
## every frame at low game speeds instead of jumping once per step.
func display_t() -> float:
	return t + (_accum if state == "racing" else 0.0)


## Boat position for drawing at display_t(): the last step's position carried on at the present
## velocity. The next step lands on the same point unless the heading changes.
func display_pos() -> Vector2:
	if state != "racing" or _accum <= 0.0:
		return pos
	return Geo.move(pos.x, pos.y, velocity, _accum)


## Advance the race clock by game seconds, in fixed steps.
func advance(game_s: float) -> void:
	_accum += game_s
	while _accum >= STEP_S and state == "racing":
		_accum -= STEP_S
		_step()


func _step() -> void:
	if mode == Mode.ROUTE and t >= _next_auto_t:
		_next_auto_t = t + AUTO_EVERY_S
		_auto_steer()
	elif mode == Mode.CLOSE_HAULED and t >= _next_auto_t:
		_next_auto_t = t + CLOSE_CHECK_S
		_close_hauled_tack()
	var before := twa
	_refresh()
	_check_maneuver(before, twa)
	var start := pos
	var next := Geo.move(pos.x, pos.y, velocity, STEP_S)
	if penalty_left_s > 0.0:
		penalty_left_s = maxf(0.0, penalty_left_s - STEP_S)
	if motoring:
		motoring_s += STEP_S
	var f := Geo.crossing(start, next, pkg.finish_line[0], pkg.finish_line[1])
	if f >= 0.0:
		pos = start.lerp(next, f)
		t += STEP_S * f
		elapsed_s = t - start_t
		_end("finished", "Crossed the finish line")
		return
	pos = next
	t += STEP_S
	_refresh()
	if depth < boat.draft_m:
		elapsed_s = t - start_t
		_end("dnf", "Grounded in %.1f m of water (draft %.1f m)" % [maxf(depth, 0.0), boat.draft_m])
		return
	if waypoints.size() > 0 and Geo.distance_nm(pos, waypoints[0]) < ARRIVE_NM:
		waypoints.pop_front()
		_next_auto_t = t
		waypoint_reached.emit()
	if t - _last_trail_t >= 60.0:
		trail.append(pos)
		trail_t.append(t)
		_last_trail_t = t
	if fmod(t, SAVE_EVERY_S) < STEP_S * 0.5:
		_save()


func _end(s: String, reason: String) -> void:
	state = s
	end_reason = reason
	trail.append(pos)
	trail_t.append(t)
	ended.emit(s)


## Elapsed plus motoring time times the event's penalty factor.
func corrected_s() -> float:
	var factor = pkg.info["rules"]["motoring_penalty_factor"]
	return elapsed_s + motoring_s * (factor if factor != null else 1.0)


## Points the boat would pass over the next 30 game minutes on heading h with present conditions,
## and the index of the first point shallower than the draft (-1 if none).
func projected_track(h: float) -> Dictionary:
	var cond := conditions(pos, t, steer_source)
	var v := ground_velocity(h, cond)
	var pts: PackedVector2Array = [pos]
	var ground := -1
	var p := pos
	var s := LOOKAHEAD_STEP_S
	while s <= LOOKAHEAD_S:
		p = Geo.move(p.x, p.y, v, LOOKAHEAD_STEP_S)
		pts.append(p)
		if ground < 0 and pkg.depth_at(p.x, p.y) < boat.draft_m:
			ground = pts.size() - 1
		s += LOOKAHEAD_STEP_S
	return {"points": pts, "ground_index": ground}


## Seconds until a boat moving at v from here reaches water shallower than the draft, checked every
## GROUND_CHECK_S up to limit_s; INF if it stays in deep water that long. The short interval (about
## 30 m at 6 kn, the sim's own step) keeps a path from jumping over a narrow point of land, and the
## clearance keeps it off shoals that only touch the draft between checks.
func _ground_time(v: Vector2, limit_s: float) -> float:
	var s := 0.0
	var step := GROUND_CHECK_S
	while s + step <= limit_s + 0.1:
		s += step
		var p := Geo.move(pos.x, pos.y, v, s)
		if pkg.depth_at(p.x, p.y) < boat.draft_m + CLEARANCE_M:
			return s
		if s >= 300.0:
			step = 60.0  # past five minutes the boat re-steers long before it gets there
		elif s >= 120.0:
			step = 30.0
	return INF


## Heading with the highest VMC right now that does not ground before it reaches the target or within
## 30 game minutes, whichever comes first, and does not sail inside the player's no-go angle. In narrow
## water where every heading grounds, the heading that stays in deep water longest.
## Under motor this is the current-corrected course to steer at the target.
func suggestion() -> Dictionary:
	var cond := conditions(pos, t, steer_source)
	var off := Geo.offset_m(pos, target())
	var to := off.normalized()
	var dist_m := off.length()
	var best := {"heading": -1.0, "vmc_kn": -INF, "sog_kn": 0.0, "same_tack_heading": -1.0, "same_tack_vmc_kn": -INF}
	var side := signf(Geo.wrap180(cond["from"] - heading))
	var candidates := []
	for h in 360:
		if not motoring and no_go_deg > 0.0 and absf(Geo.wrap180(cond["from"] - h)) < no_go_deg:
			continue
		var v := ground_velocity(float(h), cond)
		candidates.append([v.dot(to), float(h), v])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	# Check grounding only for the best candidates, in order, until one is safe on each tack. Headings
	# beyond the best 120 by VMC lose too much to matter, so the search stops there.
	for ci in mini(candidates.size(), 120):
		var cand: Array = candidates[ci]
		var same: bool = motoring or signf(Geo.wrap180(cond["from"] - cand[1])) == side
		if best["heading"] >= 0.0 and (not same or best["same_tack_heading"] >= 0.0):
			continue
		var speed: float = cand[2].length()
		var limit := minf(LOOKAHEAD_S, dist_m / maxf(speed, 0.3) + LOOKAHEAD_STEP_S)
		if _ground_time(cand[2], limit) < INF:
			continue
		if best["heading"] < 0.0:
			best["heading"] = cand[1]
			best["vmc_kn"] = cand[0] / Geo.MS_PER_KN
			best["sog_kn"] = speed / Geo.MS_PER_KN
		if same and best["same_tack_heading"] < 0.0:
			best["same_tack_heading"] = cand[1]
			best["same_tack_vmc_kn"] = cand[0] / Geo.MS_PER_KN
		if best["same_tack_heading"] >= 0.0:
			break
	if best["heading"] < 0.0 and not candidates.is_empty():
		# Every heading grounds soon: take the one with the longest run of deep water, preferring VMC.
		var longest := -1.0
		for i in range(0, candidates.size(), 3):  # every third heading is close enough here
			var cand: Array = candidates[i]
			var gt := _ground_time(cand[2], 600.0)
			if gt > longest + 1.0:
				longest = gt
				best["heading"] = cand[1]
				best["vmc_kn"] = cand[0] / Geo.MS_PER_KN
				best["sog_kn"] = cand[2].length() / Geo.MS_PER_KN
		best["same_tack_heading"] = best["heading"]
		best["same_tack_vmc_kn"] = best["vmc_kn"]
	return best


## Predicted sailing on each leg of the route: boat to waypoint 1, between waypoints, last waypoint
## to the finish. Each leg is split into pieces; on each piece the boat steers the best-VMC heading
## toward the leg's end in the wind of the given source at the time it gets there. Speeds and winds
## are averaged over time. Apparent wind is the wind over the water seen from the moving boat.
const LEG_PIECES := 6

func leg_forecast(source: int) -> Array[Dictionary]:
	var legs: Array[Dictionary] = []
	var points: Array[Vector2] = [pos]
	points.append_array(waypoints)
	var last := points[points.size() - 1]
	points.append(Geo.nearest_on_segment(last, pkg.finish_line[0], pkg.finish_line[1]))
	var time := t
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var leg := {"from": a, "to": b, "start_t": time, "dur_s": 0.0}
		var sums := {"stw": 0.0, "sog": 0.0, "tws": 0.0, "aws": 0.0, "tw": Vector2.ZERO, "awa": 0.0, "hdg": Vector2.ZERO}
		var total_s := 0.0
		for k in LEG_PIECES:
			var p := a.lerp(b, (k + 0.5) / LEG_PIECES)
			var piece_m := Geo.offset_m(a.lerp(b, float(k) / LEG_PIECES), a.lerp(b, (k + 1.0) / LEG_PIECES)).length()
			var cond := conditions(p, time, source)
			if k == LEG_PIECES / 2:
				leg["cond"] = cond
			var to := Geo.offset_m(a, b).normalized()
			# Coarse search every 6 deg, then refine to 1 deg around the best.
			var best_h := 0.0
			var best_vmc := -INF
			for h in range(0, 360, 6):
				var vmc := ground_velocity(float(h), cond).dot(to)
				if vmc > best_vmc:
					best_vmc = vmc
					best_h = float(h)
			var coarse := best_h
			for dh in range(-5, 6):
				var vmc := ground_velocity(coarse + dh, cond).dot(to)
				if vmc > best_vmc:
					best_vmc = vmc
					best_h = fposmod(coarse + dh, 360.0)
			var dt := piece_m / maxf(best_vmc, 0.05)
			var stw_kn := boat_speed(best_h, cond)
			var rel: Vector2 = cond["wind"] - cond["current"]  # air over water, m/s
			var app := rel - Geo.heading_vec(best_h) * stw_kn * Geo.MS_PER_KN  # air seen from the boat
			sums["stw"] += stw_kn * dt
			sums["sog"] += ground_velocity(best_h, cond).length() / Geo.MS_PER_KN * dt
			sums["tws"] += float(cond["tws"]) * dt
			sums["tw"] += rel * dt
			sums["aws"] += app.length() / Geo.MS_PER_KN * dt
			sums["awa"] += Geo.wrap180(Geo.bearing(-app) - best_h) * dt
			sums["hdg"] += Geo.heading_vec(best_h) * dt
			time += dt
			total_s += dt
		leg["dur_s"] = total_s
		leg["stw_kn"] = sums["stw"] / total_s
		leg["sog_kn"] = sums["sog"] / total_s
		leg["tws_kn"] = sums["tws"] / total_s
		leg["twd"] = fposmod(Geo.bearing(-sums["tw"]), 360.0)
		leg["aws_kn"] = sums["aws"] / total_s
		leg["awa"] = sums["awa"] / total_s
		leg["heading"] = fposmod(Geo.bearing(sums["hdg"]), 360.0)
		leg["bearing"] = Geo.bearing(Geo.offset_m(a, b))
		leg["dist_nm"] = Geo.distance_nm(a, b)
		leg["vmc_kn"] = leg["dist_nm"] / maxf(total_s / 3600.0, 1e-6)
		legs.append(leg)
	return legs


## SOG (kn) and STW (kn) for every whole-degree heading at the boat's present position.
func sog_by_heading() -> Dictionary:
	var cond := conditions(pos, t, steer_source)
	var sog := PackedFloat64Array()
	var spd := PackedFloat64Array()
	for h in 360:
		var s := boat_speed(float(h), cond)
		spd.append(s)
		sog.append((Geo.heading_vec(float(h)) * s * Geo.MS_PER_KN + cond["current"]).length() / Geo.MS_PER_KN)
	return {"sog": sog, "stw": spd}


func _save() -> void:
	_saves.append(snapshot())


func snapshot() -> Dictionary:
	return {"t": t, "pos": pos, "heading": heading, "mode": mode, "twa_lock": twa_lock, "motoring": motoring,
			"motoring_s": motoring_s, "penalty_left_s": penalty_left_s, "trail": trail.duplicate(), "trail_t": trail_t.duplicate(),
			"waypoints": waypoints.duplicate(),
			"last_trail_t": _last_trail_t}


func last_save() -> Dictionary:
	return _saves[_saves.size() - 1]


func restore(s: Dictionary) -> void:
	t = s["t"]
	pos = s["pos"]
	heading = s["heading"]
	mode = s["mode"]
	twa_lock = s["twa_lock"]
	motoring = s["motoring"]
	motoring_s = s["motoring_s"]
	penalty_left_s = s["penalty_left_s"]
	trail = s["trail"].duplicate()
	trail_t = s["trail_t"].duplicate()
	waypoints = s["waypoints"].duplicate()
	_last_trail_t = s["last_trail_t"]
	state = "racing"
	end_reason = ""
	elapsed_s = 0.0
	_accum = 0.0
	_next_auto_t = t
	while _saves.size() > 0 and float(_saves[_saves.size() - 1]["t"]) > t:
		_saves.pop_back()
	_refresh()
