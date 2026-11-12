class_name IdealRun
extends RefCounted
## One ideal boat, computed a few milliseconds per frame so picking a boat never freezes the game.
## The web build has no threads, so the work is spread over frames.
##
## Routes go leg by leg through gates where the water path turns around land (WaterPath), so the
## isochrone router never has to find its own way out of a harbor or around a headland.
##
## Both ideal boats move in the actual wind. They differ in what they plan with:
## - Actual ideal: an isochrone route in the actual wind and current, perfect information. The route
##   is the boat's track.
## - Forecast ideal: an isochrone route in the period forecast as issued at the gun. The boat sails it
##   in the actual wind, steering for each route point in turn, and plans a new route from where it is
##   each time a new forecast run comes out.

const MAX_S := 36.0 * 3600.0

var pkg: LegPackage
var boat: BoatProfile
var source: RaceSim.WindSource
var ghost: Ghost
var done := false
var router: IsoRouter
var sim: RaceSim  # sails the forecast ideal's route; also gives both runs their start point
var _run_utc := ""  # forecast run the present route was planned in
var _wind: VectorGrid  # wind the present route is planned in
var _targets := []  # gate lines still to route through, then the finish line: [[a, b], ...]
var _route: Array[Vector3] = []  # (lat, lon, time) of the route planned so far
var _pending_start := Vector2.INF  # start of a plan waiting for the water-path grid
var _copied := 0
var _start_nm := 1.0
var min_tack_s := 0.0
var start_t := 0.0  # race time the run starts, the player's start


func _init(p: LegPackage, b: BoatProfile, src: RaceSim.WindSource, min_tack := 0.0, start := 0.0) -> void:
	pkg = p
	boat = b
	source = src
	min_tack_s = min_tack
	start_t = start
	var name := "Forecast ideal" if src == RaceSim.WindSource.FORECAST else "Actual ideal"
	ghost = Ghost.from_run(name, boat.name, PackedVector2Array(), PackedFloat64Array(), 0.0, false)
	ghost.finish_elapsed_s = INF
	sim = RaceSim.new(pkg, boat)
	sim.steer_source = src
	sim.min_tack_s = min_tack
	sim.mode = RaceSim.Mode.ROUTE  # steers at its first step; set_mode would search headings right away
	if start_t != 0.0:
		sim.start_at(start_t)
	ghost.start_s = start_t
	_start_nm = maxf(sim.distance_to_finish_nm(), 0.001)
	_pending_start = sim.pos  # planning starts in step(), once the water-path grid is ready


## Advance until budget_ms of wall time is used or the run ends.
func step(budget_ms: float) -> void:
	if done:
		return
	var until := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	if _pending_start.is_finite():
		# Building the water-path grid for a leg with land in the way takes about half a second, so it
		# is spread over frames too. The first boat on a leg pays it; later boats reuse the grid.
		var finish_mid := (pkg.finish_line[0] + pkg.finish_line[1]) / 2.0
		if not WaterPath.prepare(pkg, _pending_start, finish_mid, boat.draft_m, budget_ms):
			return
		_plan(_pending_start, start_t)
		_pending_start = Vector2.INF
		return
	if router != null:
		router.step(budget_ms)
		if not router.done:
			return
		_route_ready()
		if done or router != null:  # finished, or the next leg is routing
			return
	# Forecast ideal: sail the route in the actual wind until the next forecast run comes out.
	while Time.get_ticks_usec() < until and sim.state == "racing" and sim.t < start_t + MAX_S:
		sim.advance(RaceSim.STEP_S)
		if sim.state == "racing" and pkg.forecast_at(sim.t)["run_utc"] != _run_utc:
			_plan(sim.pos, sim.t)
			break
	_copy_trail()
	if sim.state != "racing" or sim.t >= start_t + MAX_S:
		_finish_ghost(sim.state == "finished", sim.elapsed_s if sim.state != "racing" else sim.t - start_t)


## Share of the leg covered so far, 0 to 1.
func progress() -> float:
	if done:
		return 1.0
	if source == RaceSim.WindSource.ACTUAL:
		return router.progress() if router != null else 0.0
	return clampf(1.0 - sim.distance_to_finish_nm() / _start_nm, 0.0, 0.99)


## A router for this boat that plans in the given wind grid, with the leg's current and depth.
static func make_router(p: LegPackage, b: BoatProfile, wind: VectorGrid) -> IsoRouter:
	var r := IsoRouter.new()
	r.polar = b.polar
	r.tack_penalty_s = b.tack_penalty_s
	r.gybe_penalty_s = b.gybe_penalty_s
	var draft := b.draft_m + RaceSim.CLEARANCE_M
	r.cond_fn = func(lat: float, lon: float, t: float) -> Dictionary:
		return {"wind": wind.sample(lat, lon, t), "current": p.current.sample(lat, lon, t)}
	r.blocked_fn = func(lat: float, lon: float) -> bool:
		return p.depth_at(lat, lon) < draft
	r.near_fn = NearLand.for_leg(p, draft).is_near
	r.fine_blocked_fn = func(a: Vector2, b2: Vector2, n: int) -> bool:
		for i in range(1, n):
			var q := a.lerp(b2, float(i) / n)
			if p.depth_at(q.x, q.y) < draft:
				return true
		return false
	return r


func _plan(from: Vector2, t: float) -> void:
	var fc := pkg.forecast_at(t)
	_run_utc = fc["run_utc"]
	_wind = pkg.wind if source == RaceSim.WindSource.ACTUAL else fc["grid"]
	# Route leg by leg through a gate at each turn of the water path, then to the finish line.
	var finish_mid := (pkg.finish_line[0] + pkg.finish_line[1]) / 2.0
	_targets = WaterPath.gates(pkg, from, finish_mid, boat.draft_m)
	_targets.append([pkg.finish_line[0], pkg.finish_line[1]])
	_route = []
	_start_leg(from, t)


func _start_leg(from: Vector2, t: float) -> void:
	var target: Array = _targets.pop_front()
	router = make_router(pkg, boat, _wind)
	router.min_tack_s = min_tack_s
	router.setup(from, t, target[0], target[1])


func _route_ready() -> void:
	var leg := router.path()
	var found := router.found
	router = null
	if not _route.is_empty() and not leg.is_empty():
		leg.remove_at(0)  # the leg starts where the last one ended
	_route.append_array(leg)
	if found and not _targets.is_empty():
		var end: Vector3 = _route[_route.size() - 1]
		_start_leg(Vector2(end.x, end.y), end.z)
		return
	var on_finish := found and _targets.is_empty()
	if source == RaceSim.WindSource.ACTUAL:
		for q in _route:
			ghost.lats.append(q.x)
			ghost.lons.append(q.y)
			ghost.times.append(q.z)
			ghost.world.append(Geo.to_world(q.x, q.y))
		_finish_ghost(on_finish, _route[_route.size() - 1].z - start_t)
		return
	# Forecast ideal: steer for each route point after the boat's position; the last one is on the finish line.
	sim.clear_waypoints()
	for i in range(1, _route.size()):
		sim.add_waypoint(Vector2(_route[i].x, _route[i].y))


func _finish_ghost(finished: bool, elapsed: float) -> void:
	done = true
	ghost.finished = finished
	ghost.finish_elapsed_s = elapsed


func _copy_trail() -> void:
	while _copied < sim.trail.size():
		var p := sim.trail[_copied]
		ghost.times.append(sim.trail_t[_copied])
		ghost.lats.append(p.x)
		ghost.lons.append(p.y)
		ghost.world.append(Geo.to_world(p.x, p.y))
		_copied += 1
