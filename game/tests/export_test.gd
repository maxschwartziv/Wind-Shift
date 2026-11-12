extends SceneTree
## Headless check of the route export: GPX and KML parse as XML and hold every route point.
## Run: godot --headless --path game --script res://tests/export_test.gd

func _init() -> void:
	var pkg := LegPackage.load_dir("res://packages/n2e-2025")
	var sim := RaceSim.new(pkg, BoatProfile.starters()[2])
	sim.add_waypoint(Vector2(33.30, -117.75))
	sim.add_waypoint(Vector2(32.90, -117.45))
	var pts := RouteExport.route_points(sim)
	assert(pts.size() == 4, "start, two waypoints, finish")
	var gpx := RouteExport.to_gpx("Test & route", pts)
	var kml := RouteExport.to_kml("Test & route", pts)
	for pair in [["gpx", gpx, "rtept"], ["kml", kml, "Placemark"]]:
		var parser := XMLParser.new()
		assert(parser.open_buffer(pair[1].to_utf8_buffer()) == OK)
		var count := 0
		while parser.read() == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == pair[2]:
				count += 1
		print("%s: %d %s elements" % [pair[0], count, pair[2]])
	print(gpx)
	quit()
