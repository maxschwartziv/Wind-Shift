extends SceneTree
## Headless check on the test-pocket leg: the isochrone route should beat the greedy best-VMC rule,
## which sails straight into the light-wind pocket on the direct line.
## Run: godot --headless --path game --script res://tests/route_test.gd

func _init() -> void:
	var pkg := LegPackage.load_dir("res://packages/test-pocket")
	var b: Dictionary = pkg.info["bounds"]
	Geo.set_origin(b["lat_max"], b["lon_min"])
	var boat: BoatProfile = BoatProfile.starters()[2]
	var greedy := RaceSim.new(pkg, boat)
	greedy.steer_source = RaceSim.WindSource.ACTUAL
	greedy.set_mode(RaceSim.Mode.ROUTE)
	while greedy.state == "racing" and greedy.t < 36 * 3600:
		greedy.advance(RaceSim.STEP_S)
	var t0 := Time.get_ticks_msec()
	var runs := {}
	for src in [RaceSim.WindSource.ACTUAL, RaceSim.WindSource.FORECAST]:
		var run := IdealRun.new(pkg, boat, src)
		while not run.done:
			run.step(1000.0)
		runs[src] = run.ghost
	var ms := Time.get_ticks_msec() - t0
	var actual: Ghost = runs[RaceSim.WindSource.ACTUAL]
	var forecast: Ghost = runs[RaceSim.WindSource.FORECAST]
	print("greedy (best VMC, actual wind): %s %.2f h" % [greedy.state, greedy.elapsed_s / 3600.0])
	print("actual ideal (isochrone, actual wind): %.2f h" % (actual.finish_elapsed_s / 3600.0))
	print("forecast ideal (isochrone in forecast, re-planned at 4 h): %.2f h   [%d ms]" % [forecast.finish_elapsed_s / 3600.0, ms])
	# Closest approach to the pocket centre for each track.
	var centre := Vector2(30.50, -120.50)
	for pair in [["greedy", greedy.trail], ["actual ideal", _pts(actual)], ["forecast ideal", _pts(forecast)]]:
		var best := INF
		for p in pair[1]:
			best = minf(best, Geo.distance_nm(p, centre))
		print("  %s passes %.1f nm from the pocket centre" % [pair[0], best])
	assert(actual.finish_elapsed_s < greedy.elapsed_s, "isochrone route beats the greedy rule around the pocket")
	quit()


func _pts(g: Ghost) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in g.lats.size():
		out.append(Vector2(g.lats[i], g.lons[i]))
	return out
