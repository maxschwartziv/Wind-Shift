class_name RouteExport
## The player's route as a file for chart plotters: GPX 1.1 (Navionics, Garmin, Raymarine, B&G,
## OpenCPN and most plotting apps) or KML (Google Earth). The route runs from the boat through each
## waypoint to the nearest point of the finish line.


## [[name, Vector2(lat, lon)], ...] for the boat, each waypoint and the finish.
static func route_points(sim: RaceSim) -> Array:
	var pts := [["Start", sim.pos]]
	for i in sim.waypoints.size():
		pts.append(["WP%d" % (i + 1), sim.waypoints[i]])
	var last: Vector2 = pts[pts.size() - 1][1]
	pts.append(["Finish", Geo.nearest_on_segment(last, sim.pkg.finish_line[0], sim.pkg.finish_line[1])])
	return pts


static func to_gpx(route_name: String, pts: Array) -> String:
	var lines := PackedStringArray([
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<gpx version="1.1" creator="Wind Shift" xmlns="http://www.topografix.com/GPX/1/1">',
		"  <metadata><name>%s</name></metadata>" % _xml(route_name),
	])
	for p in pts:
		lines.append('  <wpt lat="%.6f" lon="%.6f"><name>%s</name><sym>Waypoint</sym></wpt>' % [p[1].x, p[1].y, _xml(p[0])])
	lines.append("  <rte>")
	lines.append("    <name>%s</name>" % _xml(route_name))
	for p in pts:
		lines.append('    <rtept lat="%.6f" lon="%.6f"><name>%s</name></rtept>' % [p[1].x, p[1].y, _xml(p[0])])
	lines.append("  </rte>")
	lines.append("</gpx>")
	return "\n".join(lines) + "\n"


static func to_kml(route_name: String, pts: Array) -> String:
	var coords := PackedStringArray()
	for p in pts:
		coords.append("%.6f,%.6f,0" % [p[1].y, p[1].x])  # KML order is lon,lat
	var lines := PackedStringArray([
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<kml xmlns="http://www.opengis.net/kml/2.2">',
		"<Document>",
		"  <name>%s</name>" % _xml(route_name),
		'  <Style id="route"><LineStyle><color>ff1a8cff</color><width>3</width></LineStyle></Style>',
		"  <Placemark><name>%s</name><styleUrl>#route</styleUrl><LineString><tessellate>1</tessellate><coordinates>%s</coordinates></LineString></Placemark>" % [_xml(route_name), " ".join(coords)],
	])
	for p in pts:
		lines.append("  <Placemark><name>%s</name><Point><coordinates>%.6f,%.6f,0</coordinates></Point></Placemark>" % [_xml(p[0]), p[1].y, p[1].x])
	lines.append("</Document>")
	lines.append("</kml>")
	return "\n".join(lines) + "\n"


## Hand the text to the player: a download in the browser, a save dialog on desktop.
static func save(owner: Node, file_name: String, text: String, mime: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, mime)
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = file_name
	dialog.filters = PackedStringArray(["*.%s" % file_name.get_extension()])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	owner.add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


static func _xml(s: String) -> String:
	return s.xml_escape(true)
