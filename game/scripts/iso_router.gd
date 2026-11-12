class_name IsoRouter
extends RefCounted
## Isochrone router: finds the fastest route from a start point to a finish line for a boat's polar.
##
## An isochrone is the set of points the boat can reach in the same time. The router grows one
## isochrone per time step:
##   1. From every point on the newest isochrone, sail every heading for one step in the wind and
##      current at that point. Tacks and gybes lose their penalty time.
##   2. Group the new points into narrow sectors by bearing from the start and keep only the one
##      furthest from the start in each sector. That point is the front; the rest are behind it.
##   3. Drop points whose path crosses water shallower than the draft.
##   4. Stop at the first step where a path crosses the finish line, at the earliest crossing.
## The route is then read backward from the finishing point through each point's parent.
##
## The work runs a few milliseconds at a time (step()), because the web build has no threads.
## Conditions come from cond_fn and land from blocked_fn, so the help animation can run it on a
## made-up sea.

const MAX_STEPS := 400

## (lat, lon, time s) -> {"wind": Vector2 m/s east/north, "current": Vector2 m/s}
var cond_fn: Callable
## (lat, lon) -> true where the boat cannot go
var blocked_fn: Callable
## Optional (lat, lon) -> true near land. There a path is checked every FINE_CHECK_M, so it cannot cut
## across a narrow headland between the three coarse checks.
var near_fn: Callable
## Optional (a, b, n) -> true if any of n - 1 evenly spaced points between a and b is blocked; one call
## for the whole fine check instead of one per point.
var fine_blocked_fn: Callable
const FINE_CHECK_M := 100.0
var polar: Polar
var tack_penalty_s := 0.0
var gybe_penalty_s := 0.0
var dt := 900.0  # seconds per isochrone
var min_tack_s := 0.0  # shortest time allowed between tacks or gybes; 0 for no limit
var heading_step := 5.0  # degrees between headings tried all round
var fine_step := 1.0  # degrees between headings tried near the direct course
var fine_span := 15.0  # degrees either side of the direct course tried at fine_step
var cone := 100.0  # degrees either side of the direct course tried at all
var sector_deg := 2.0  # widest bearing sector used to prune, in degrees
var sector_m := 800.0  # if above 0, sectors narrow as the front moves out so each spans about this many meters
var start := Vector2.ZERO
var start_t := 0.0
var finish_a := Vector2.ZERO
var finish_b := Vector2.ZERO

var done := false
var found := false
var finish_t := INF
## Isochrones so far: each is {"lat", "lon", "twa", "since" (PackedFloat64Array), "parent" (PackedInt32Array), "t"}.
## "since" is the time since the point's path last tacked or gybed.
var isochrones: Array[Dictionary] = []

var _parent_i := 0  # next point of the newest isochrone to expand
var _best_dist: Dictionary = {}  # sector -> squared distance from start, for the isochrone being built
var _best: Dictionary = {}  # sector -> [lat, lon, twa, parent]
var _finish := []  # [time, lat, lon, parent index] of the earliest crossing in this step
var _start_to_finish_m := 1.0
var _closest_m := INF
var _sector_now := 1.0  # sector width in degrees for the isochrone being built
var _front_m := 0.0  # distance of the furthest point from the start so far


func setup(from: Vector2, from_t: float, line_a: Vector2, line_b: Vector2) -> void:
	start = from
	start_t = from_t
	finish_a = line_a
	finish_b = line_b
	_start_to_finish_m = maxf(Geo.offset_m(start, Geo.nearest_on_segment(start, finish_a, finish_b)).length(), 1.0)
	_closest_m = _start_to_finish_m
	_sector_now = sector_deg
	_front_m = 0.0
	isochrones = [{
		"lat": PackedFloat64Array([start.x]), "lon": PackedFloat64Array([start.y]),
		"twa": PackedFloat64Array([0.0]), "since": PackedFloat64Array([INF]), "parent": PackedInt32Array([-1]), "t": start_t,
	}]


## Work until budget_ms of wall time is used or the route is found.
func step(budget_ms: float) -> void:
	var until := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	while not done and Time.get_ticks_usec() < until:
		var iso: Dictionary = isochrones[isochrones.size() - 1]
		if _parent_i < iso["lat"].size():
			_expand(iso, _parent_i)
			_parent_i += 1
		else:
			_close_step(iso)


## Share of the start-to-finish distance covered by the furthest point so far, 0 to 1.
func progress() -> float:
	return 1.0 if done else clampf(1.0 - _closest_m / _start_to_finish_m, 0.0, 0.99)


## The route as [lat, lon, time] points from the start to the finish crossing (or to the point
## nearest the finish if none was found).
func path() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var level := isochrones.size() - 1
	var idx := 0
	if found:
		# The crossing's parent is a point on the newest isochrone.
		out.append(Vector3(_finish[1], _finish[2], _finish[0]))
		idx = _finish[3]
	else:
		idx = _nearest_index(isochrones[level])
	while level >= 0 and idx >= 0:
		var iso: Dictionary = isochrones[level]
		out.append(Vector3(iso["lat"][idx], iso["lon"][idx], iso["t"]))
		idx = iso["parent"][idx]
		level -= 1
	out.reverse()
	return out


func _expand(iso: Dictionary, i: int) -> void:
	var lat: float = iso["lat"][i]
	var lon: float = iso["lon"][i]
	var t: float = iso["t"]
	var parent_twa: float = iso["twa"][i]
	var since: float = iso["since"][i]
	var here := Vector2(lat, lon)
	# Conditions at the middle of the step in time, so a building or dying breeze is not lagged by half a step.
	var cond: Dictionary = cond_fn.call(lat, lon, t + dt * 0.5)
	var current: Vector2 = cond["current"]
	var rel: Vector2 = cond["wind"] - current
	var tws := rel.length() / Geo.MS_PER_KN
	var from := Geo.bearing(-rel)
	for h in _headings(here):
		var twa := Geo.wrap180(from - h)
		var stw := polar.speed(absf(twa), tws)
		if stw > 0.05:
			var sail_s := dt
			var turned := false
			if parent_twa != 0.0 and signf(twa) != signf(parent_twa):
				if absf(twa) < 90.0 and absf(parent_twa) < 90.0:
					sail_s -= tack_penalty_s
					turned = true
				elif absf(twa) >= 90.0 and absf(parent_twa) >= 90.0:
					sail_s -= gybe_penalty_s
					turned = true
				# A change of side the short way round through 90° costs nothing, like in the sim.
			if turned and since < min_tack_s:
				continue
			var disp := Geo.heading_vec(h) * stw * Geo.MS_PER_KN * maxf(sail_s, 0.0) + current * dt
			var p := Geo.move(lat, lon, disp / dt, dt)
			_consider(here, p, twa, 0.0 if turned else since + dt, i, t)


## Headings to try from a point: every heading_step degrees within cone of the course straight at the
## finish line, plus every fine_step degrees within fine_span of it, where the fastest routes usually run.
## Headings further off are skipped: points they reach end up behind the front and are pruned anyway.
func _headings(here: Vector2) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var direct := Geo.bearing(Geo.offset_m(here, Geo.nearest_on_segment(here, finish_a, finish_b)))
	var h := 0.0
	while h < 360.0:
		if absf(Geo.wrap180(h - direct)) <= cone:
			out.append(h)
		h += heading_step
	var d := -fine_span
	while d <= fine_span:
		out.append(fposmod(direct + d, 360.0))
		d += fine_step
	return out


func _consider(here: Vector2, p: Vector2, twa: float, since: float, parent: int, t: float) -> void:
	var f := Geo.crossing(here, p, finish_a, finish_b)
	if f >= 0.0:
		var ft := t + dt * f
		if _finish.is_empty() or ft < _finish[0]:
			if not _path_blocked(here, here.lerp(p, f)):
				var c := here.lerp(p, f)
				_finish = [ft, c.x, c.y, parent]
		return
	var off := Geo.offset_m(start, p)
	var sector := int(floor(fposmod(Geo.bearing(off), 360.0) / _sector_now))
	var d2 := off.length_squared()
	if d2 <= _best_dist.get(sector, -1.0):
		return
	# Check land only for points that would take over their sector.
	if _path_blocked(here, p):
		return
	_best_dist[sector] = d2
	_best[sector] = [p.x, p.y, twa, parent, since]


func _path_blocked(a: Vector2, b: Vector2) -> bool:
	var near := false
	for k in [0.34, 0.67, 1.0]:
		var q := a.lerp(b, k)
		if blocked_fn.call(q.x, q.y):
			return true
		if not near and near_fn.is_valid() and near_fn.call(q.x, q.y):
			near = true
	if near:
		var n := int(ceil(Geo.offset_m(a, b).length() / FINE_CHECK_M))
		if fine_blocked_fn.is_valid():
			return fine_blocked_fn.call(a, b, n)
		for i in range(1, n):
			var q := a.lerp(b, float(i) / n)
			if blocked_fn.call(q.x, q.y):
				return true
	return false


func _close_step(iso: Dictionary) -> void:
	if not _finish.is_empty():
		found = true
		finish_t = _finish[0]
		done = true
		return
	if _best.is_empty() or isochrones.size() >= MAX_STEPS:
		done = true
		return
	var next := {"lat": PackedFloat64Array(), "lon": PackedFloat64Array(), "twa": PackedFloat64Array(),
			"since": PackedFloat64Array(), "parent": PackedInt32Array(), "t": iso["t"] + dt}
	var keys := _best.keys()
	keys.sort()  # keep the front in bearing order, which the help drawing uses
	for s in keys:
		var b: Array = _best[s]
		next["lat"].append(b[0])
		next["lon"].append(b[1])
		next["twa"].append(b[2])
		next["parent"].append(b[3])
		next["since"].append(b[4])
		var to_finish := Geo.offset_m(Vector2(b[0], b[1]), Geo.nearest_on_segment(Vector2(b[0], b[1]), finish_a, finish_b)).length()
		_closest_m = minf(_closest_m, to_finish)
	isochrones.append(next)
	for k2 in _best_dist:
		_front_m = maxf(_front_m, sqrt(_best_dist[k2]))
	_sector_now = sector_deg
	if sector_m > 0.0 and _front_m > 0.0:
		_sector_now = clampf(rad_to_deg(sector_m / _front_m), 0.1, sector_deg)
	_best.clear()
	_best_dist.clear()
	_parent_i = 0


func _nearest_index(iso: Dictionary) -> int:
	var best := 0
	var best_d := INF
	for i in iso["lat"].size():
		var p := Vector2(iso["lat"][i], iso["lon"][i])
		var d := Geo.offset_m(p, Geo.nearest_on_segment(p, finish_a, finish_b)).length()
		if d < best_d:
			best_d = d
			best = i
	return best
