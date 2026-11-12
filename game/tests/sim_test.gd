extends SceneTree
## Headless checks: polar math, the ideal boats for each starter, and a plotted route.
## Run: godot --headless --path game --script res://tests/sim_test.gd

const PKG := "res://packages/n2e-2025"


func _init() -> void:
	var pkg := LegPackage.load_dir(PKG)
	print("package: %s, %d ghosts, %d forecast runs" % [pkg.info["leg"], pkg.ghosts.size(), pkg.forecasts.size()])
	_check_polar()
	for boat in BoatProfile.starters():
		var t0 := Time.get_ticks_msec()
		var ideals := TestTracks.ideal_ghosts(pkg, boat)
		var ms := Time.get_ticks_msec() - t0
		var parts := PackedStringArray()
		for g in ideals:
			parts.append("%s %s %.2f h (place %d of %d)" % [g.name, "finished" if g.finished else "DNF",
					g.finish_elapsed_s / 3600.0, _place(pkg, g.finish_elapsed_s), pkg.ghosts.size() + 1])
		print("%-34s %s  [%d ms]" % [boat.name, "; ".join(parts), ms])
	_check_route(pkg)
	_check_smooth(pkg)
	quit()


func _place(pkg: LegPackage, elapsed: float) -> int:
	var n := 1
	for g in pkg.ghosts:
		if g.finish_elapsed_s < elapsed:
			n += 1
	return n


func _check_route(pkg: LegPackage) -> void:
	var sim := RaceSim.new(pkg, BoatProfile.starters()[2])
	sim.add_waypoint(Vector2(33.30, -117.75))
	sim.add_waypoint(Vector2(32.90, -117.45))
	while sim.state == "racing" and sim.t < 36 * 3600:
		sim.advance(RaceSim.STEP_S)
	assert(sim.waypoints.is_empty(), "both waypoints reached")
	print("route via 2 waypoints: %s %.2f h, waypoints left %d" % [sim.state, sim.elapsed_s / 3600.0, sim.waypoints.size()])


func _check_polar() -> void:
	var p := Polar.parse("TWA/TWS\t6\t12\n40\t4\t6\n90\t6\t8\n")
	assert(is_equal_approx(p.speed(65, 9), 6.0), "bilinear middle")
	assert(is_equal_approx(p.speed(90, 3), 3.0), "below first column scales to zero")
	assert(is_equal_approx(p.speed(90, 30), 8.0), "above last column clamps")
	assert(is_equal_approx(p.speed(20, 6), 2.0), "added zero row at 0 deg")
	assert(Polar.parse(p.to_text()).speed(65, 9) == p.speed(65, 9), "round trip")
	print("polar checks passed")


## At 10x and 60 frames per second the drawn boat should move a little every frame. Without interpolation
## it would sit still and then jump a whole 10 s step (about 40 m at 8 kn). A heading change at a step
## start still bends the path, which shows as a few meters of difference between frames.
func _check_smooth(pkg: LegPackage) -> void:
	var sim := RaceSim.new(pkg, BoatProfile.starters()[2])
	var last := sim.display_pos()
	var worst := 0.0
	var smallest := INF
	for i in 600:
		sim.advance(10.0 / 60.0)
		var p := sim.display_pos()
		var d := Geo.distance_nm(last, p) * Geo.M_PER_NM
		worst = maxf(worst, d)
		smallest = minf(smallest, d)
		last = p
	assert(worst < 5.0 and smallest > 0.0, "drawn boat moves every frame without step jumps")
	print("smooth drawing at 10x: per-frame move %.2f to %.2f m" % [smallest, worst])
