extends SceneTree
## Headless checks of the GRIB reader against files written by ecCodes (pipeline/tools/make_test_gribs.py)
## and one real NOAA GFS file. The test fields are linear, so interpolated values must match exactly.
## Run: godot --headless --path game --script res://tests/grib_test.gd

const DIR := "res://tests/data/"
var failures := 0


func _init() -> void:
	var pkg := LegPackage.load_dir("res://packages/n2e-2025")
	var start := pkg.start_unix()  # 2025-04-25 18:00Z; the test files are 12:00Z +0 h and +3 h
	for name in ["g2_simple.grb2", "g2_complex.grb2", "g2_complex_sd.grb2", "g2_south_first_lon180.grb2", "g1_simple.grb"]:
		_check_linear(name, "wind", pkg, start)
	_check_linear("g1_current.grb", "current", pkg, start)
	_check_land(pkg)
	var r := WeatherImport.build(FileAccess.get_file_as_bytes(DIR + "g2_jpeg.grb2"), "wind", pkg)
	_expect(not r["ok"] and r["message"].contains("JPEG 2000"), "JPEG 2000 file is refused with a reason: " + r["message"])
	_check_gfs()
	print("GRIB checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(failures)


func _expected(lat: float, lon: float, hour: float) -> Vector2:
	return Vector2(5.0 + (lat - 33.0) + 0.5 * (lon + 118.0) + 0.1 * hour,
			-3.0 + 0.3 * (lat - 33.0) - 0.2 * (lon + 118.0) + 0.05 * hour)


func _check_linear(name: String, kind: String, pkg: LegPackage, start: float) -> void:
	var t0 := Time.get_ticks_msec()
	var r := WeatherImport.build(FileAccess.get_file_as_bytes(DIR + name), kind, pkg)
	if not r["ok"]:
		_expect(false, "%s: %s" % [name, r["message"]])
		return
	var g: VectorGrid = r["grid"]
	var worst := 0.0
	for p in [Vector2(33.0, -118.0), Vector2(32.61, -117.33), Vector2(33.71, -118.2), Vector2(32.4, -117.0)]:
		for hour in [0.0, 1.5, 3.0]:
			var t: float = (12.0 + hour) * 3600.0 - (start - Time.get_unix_time_from_datetime_string("2025-04-25T00:00:00Z"))
			var got := g.sample(p.x, p.y, t)
			worst = maxf(worst, got.distance_to(_expected(p.x, p.y, hour)))
	_expect(worst < 0.01 and g.times.size() == 2, "%s: %d times, worst error %.4f m/s  [%d ms]" % [name, g.times.size(), worst, Time.get_ticks_msec() - t0])


func _check_land(pkg: LegPackage) -> void:
	var r := WeatherImport.build(FileAccess.get_file_as_bytes(DIR + "g2_current_land.grb2"), "current", pkg)
	var g: VectorGrid = r["grid"]
	var start := pkg.start_unix()
	var t := 12.0 * 3600.0 - (start - Time.get_unix_time_from_datetime_string("2025-04-25T00:00:00Z"))
	var sea := g.sample(33.0, -118.0, t).distance_to(_expected(33.0, -118.0, 0.0))
	var land := g.sample(34.9, -116.1, t).length()
	_expect(r["ok"] and sea < 0.01 and land < 0.01, "current with land bitmap: sea error %.4f, land value %.4f m/s" % [sea, land])


func _check_gfs() -> void:
	var t0 := Time.get_ticks_msec()
	var dec := Grib.decode(FileAccess.get_file_as_bytes(DIR + "gfs_20250425_12z_f003_uv10.grb2"))
	var ms := Time.get_ticks_msec() - t0
	var ref: Array = JSON.parse_string(FileAccess.get_file_as_string(DIR + "gfs_reference.json"))
	var worst := 0.0
	for i in ref.size():
		var f: Dictionary = dec["fields"][i]
		for pt in ref[i]["points"]:
			var v := WeatherImport._sample(f, pt[0], pt[1])
			worst = maxf(worst, absf(v - pt[2]))
	_expect(dec["fields"].size() == 2 and worst < 0.01, "real GFS 0.25° global file: %d fields, worst error %.4f m/s  [%d ms decode]" % [dec["fields"].size(), worst, ms])


func _expect(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1
