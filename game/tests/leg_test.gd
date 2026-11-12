extends SceneTree
## Headless check of a leg package: it loads, the start and finish lie in water deep enough for the
## boat, the fleet's elapsed times look sane, and both ideal boats reach the finish.
## Run: godot --headless --path game --script res://tests/leg_test.gd -- --leg=queens-cup-2024

var failures := 0


func _init() -> void:
	var leg := "n2e-2025"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			leg = arg.trim_prefix("--leg=")
	var pkg := LegPackage.load_dir("res://packages/" + leg)
	var b: Dictionary = pkg.info["bounds"]
	Geo.set_origin(b["lat_max"], b["lon_min"])
	var boat: BoatProfile = BoatProfile.starters()[2]
	print("%s: %s, %d ghosts, %d forecast runs, wind %d times" % [leg, pkg.info["leg"], pkg.ghosts.size(), pkg.forecasts.size(), pkg.wind.times.size()])
	var s := (pkg.start_line[0] + pkg.start_line[1]) / 2.0
	var f := (pkg.finish_line[0] + pkg.finish_line[1]) / 2.0
	_expect(pkg.depth_at(s.x, s.y) > boat.draft_m, "start line midpoint is %.0f m deep" % pkg.depth_at(s.x, s.y))
	_expect(pkg.depth_at(f.x, f.y) > boat.draft_m, "finish line midpoint is %.1f m deep" % pkg.depth_at(f.x, f.y))
	var times := []
	for g in pkg.ghosts:
		times.append(g.finish_elapsed_s / 3600.0)
	times.sort()
	if times.is_empty():
		print("SKIP  no fleet on this leg")
	else:
		_expect(times.size() >= 5 and times[0] > 0.5, "fleet elapsed times %.2f to %.2f h, median %.2f h" % [times[0], times[times.size() - 1], times[times.size() / 2]])
	var w0 := pkg.wind.sample(s.x, s.y, 0.0).length() / Geo.MS_PER_KN
	_expect(w0 > 0.5 and w0 < 40.0, "wind at the start at the gun %.1f kn" % w0)
	var t0 := Time.get_ticks_msec()
	for src in [RaceSim.WindSource.ACTUAL, RaceSim.WindSource.FORECAST]:
		var run := IdealRun.new(pkg, boat, src)
		while not run.done:
			run.step(1000.0)
		var g := run.ghost
		var place := 1
		for o in pkg.ghosts:
			if o.finish_elapsed_s < g.finish_elapsed_s:
				place += 1
		_expect(g.finished, "%s for %s: %s %.2f h, place %d of %d" % [g.name, boat.name, "finished" if g.finished else "did not finish",
				g.finish_elapsed_s / 3600.0, place, pkg.ghosts.size() + 1])
		if src == RaceSim.WindSource.ACTUAL:
			var dry := 0
			for i in g.lats.size() - 1:
				var p0 := Vector2(g.lats[i], g.lons[i])
				var p1 := Vector2(g.lats[i + 1], g.lons[i + 1])
				var n := int(ceil(Geo.offset_m(p0, p1).length() / 50.0))
				for k in n + 1:
					var q := p0.lerp(p1, float(k) / maxf(n, 1))
					if pkg.depth_at(q.x, q.y) < boat.draft_m:
						dry += 1
						break
			_expect(dry == 0, "actual ideal track stays in water deeper than the draft (%d segments touch bottom)" % dry)
	print("ideal boats computed in %d ms" % (Time.get_ticks_msec() - t0))
	print("%s: %s" % [leg, "all passed" if failures == 0 else "%d failed" % failures])
	quit(failures)


func _expect(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1
