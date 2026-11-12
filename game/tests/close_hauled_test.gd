extends SceneTree
## Headless check of close hauled mode in narrow water: from the Spinnaker Cup start, beating toward a
## waypoint off the Golden Gate, the boat tacks by itself and does not run aground.
## Run: godot --headless --path game --script res://tests/close_hauled_test.gd

func _init() -> void:
	var pkg := LegPackage.load_dir("res://packages/spinnaker-cup-2025")
	var b: Dictionary = pkg.info["bounds"]
	Geo.set_origin(b["lat_max"], b["lon_min"])
	var sim := RaceSim.new(pkg, BoatProfile.starters()[2])
	sim.steer_source = RaceSim.WindSource.ACTUAL
	sim.add_waypoint(Vector2(37.825, -122.50))
	sim.set_mode(RaceSim.Mode.CLOSE_HAULED)
	var tacks := [0]
	sim.maneuver.connect(func(_k): tacks[0] += 1)
	var start := sim.pos
	while sim.state == "racing" and sim.t < 2400.0:
		sim.advance(10.0)
	var gained := Geo.distance_nm(start, Vector2(37.825, -122.50)) - Geo.distance_nm(sim.pos, Vector2(37.825, -122.50))
	var ok: bool = sim.state == "racing" and tacks[0] >= 1 and gained > 0.3
	print("close hauled 40 min: %s, %d tacks, %.2f nm closer to the waypoint, depth %.0f m -> %s" % [sim.state, tacks[0], gained, sim.depth, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
