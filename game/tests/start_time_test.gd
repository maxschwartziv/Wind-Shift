extends SceneTree
## Headless check of a later start: the player's clock and elapsed time start at the chosen time, and
## the ideal boats start with the player.
## Run: godot --headless --path game --script res://tests/start_time_test.gd

func _init() -> void:
	var pkg := LegPackage.load_dir("res://packages/n2e-2025")
	var b: Dictionary = pkg.info["bounds"]
	Geo.set_origin(b["lat_max"], b["lon_min"])
	var boat: BoatProfile = BoatProfile.starters()[2]
	var late := 2.0 * 3600.0
	var sim := RaceSim.new(pkg, boat)
	sim.start_at(late)
	sim.set_mode(RaceSim.Mode.ROUTE)
	while sim.state == "racing" and sim.t < late + 36 * 3600:
		sim.advance(RaceSim.STEP_S)
	var ok1: bool = sim.state == "finished" and absf(sim.elapsed_s - (sim.t - late)) < 1.0 and sim.trail_t[0] == late
	print("player starting 2 h late: %s, elapsed %.2f h, finished at race time %.2f h -> %s" % [sim.state, sim.elapsed_s / 3600.0, sim.t / 3600.0, "PASS" if ok1 else "FAIL"])
	var run := IdealRun.new(pkg, boat, RaceSim.WindSource.ACTUAL, 0.0, late)
	while not run.done:
		run.step(1000.0)
	var g := run.ghost
	var ok2: bool = g.finished and g.times[0] >= late - 1.0 and g.start_s == late and g.finish_elapsed_s < 20 * 3600
	print("actual ideal starting 2 h late: first fix at %.2f h, elapsed %.2f h -> %s" % [g.times[0] / 3600.0, g.finish_elapsed_s / 3600.0, "PASS" if ok2 else "FAIL"])
	quit(0 if ok1 and ok2 else 1)
