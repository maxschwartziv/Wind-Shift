class_name WeatherImport
## Turns a GRIB file into the game's wind or current grids for the loaded leg. Each GRIB field is
## interpolated onto a regular grid over the leg's area (plus a margin), so any GRIB area, scanning
## order or longitude convention (0 to 360 or -180 to 180) works. East and north components are
## paired by valid time.

const MARGIN_DEG := 0.5
const MIN_STEP_DEG := 0.02


## Result: {"ok": bool, "message": String, "grid": VectorGrid or null, "times": int, "first_unix", "last_unix"}.
## kind is "wind" or "current".
static func build(bytes: PackedByteArray, kind: String, pkg: LegPackage) -> Dictionary:
	var dec := Grib.decode(bytes)
	var by_time := {}  # valid_unix -> {"u": field, "v": field}
	for f in dec["fields"]:
		if f["kind"] != kind:
			continue
		var key: float = f["valid_unix"]
		if not by_time.has(key):
			by_time[key] = {}
		by_time[key][f["comp"]] = f
	var times := []
	for key in by_time:
		if by_time[key].has("u") and by_time[key].has("v"):
			times.append(key)
	times.sort()
	if times.is_empty():
		var why := "No %s found in this file." % ("10 m wind (U and V)" if kind == "wind" else "ocean current (U and V)")
		if not dec["errors"].is_empty():
			why += " " + "; ".join(dec["errors"])
		return {"ok": false, "message": why, "grid": null}

	var first: Dictionary = by_time[times[0]]["u"]["grid"]
	var step := maxf(_step(first), MIN_STEP_DEG)
	var b: Dictionary = pkg.info["bounds"]
	var lat_n: float = b["lat_max"] + MARGIN_DEG
	var lon_w: float = b["lon_min"] - MARGIN_DEG
	var rows := int(ceil((b["lat_max"] - b["lat_min"] + 2.0 * MARGIN_DEG) / step)) + 1
	var cols := int(ceil((b["lon_max"] - b["lon_min"] + 2.0 * MARGIN_DEG) / step)) + 1
	var g := VectorGrid.new()
	g.lat_north = lat_n
	g.lon_west = lon_w
	g.dlat = step
	g.dlon = step
	g.rows = rows
	g.cols = cols
	g.times = PackedFloat64Array()
	var data := PackedFloat32Array()
	data.resize(times.size() * rows * cols * 2)
	var covered := 0
	var cells := 0
	var start := pkg.start_unix()
	for ti in times.size():
		var pair: Dictionary = by_time[times[ti]]
		g.times.append(float(times[ti]) - start)
		for r in rows:
			for c in cols:
				var lat := lat_n - r * step
				var lon := lon_w + c * step
				var u := _sample(pair["u"], lat, lon)
				var v := _sample(pair["v"], lat, lon)
				var i := ((ti * rows + r) * cols + c) * 2
				var inside: bool = lat <= b["lat_max"] and lat >= b["lat_min"] and lon >= b["lon_min"] and lon <= b["lon_max"]
				if inside and ti == 0:
					cells += 1
				if is_nan(u) or is_nan(v):
					u = 0.0  # outside the file's area, or land in a current file
					v = 0.0
				elif inside and ti == 0:
					covered += 1
				data[i] = u
				data[i + 1] = v
	g.data = data
	var share := float(covered) / maxf(cells, 1)
	if share < 0.5 and kind == "wind":
		return {"ok": false, "message": "This file's area covers %d%% of the leg; it needs to cover the leg." % roundi(share * 100.0), "grid": null}
	var msg := "Imported %d %s fields, %s to %s UTC, %.2f° grid." % [times.size(), kind,
			_date(times[0]), _date(times[times.size() - 1]), step]
	if share < 0.98:
		msg += " The file covers %d%% of the leg; the rest is set to zero." % roundi(share * 100.0)
	if dec["skipped"] > 0:
		msg += " %d other messages were skipped." % dec["skipped"]
	return {"ok": true, "message": msg, "grid": g, "times": times.size(), "first_unix": times[0], "last_unix": times[times.size() - 1]}


## Grid spacing in degrees, the larger of the two directions.
static func _step(grid: Dictionary) -> float:
	var dlat: float = absf(grid["la2"] - grid["la1"]) / maxf(grid["nj"] - 1, 1)
	var dlon: float = absf(_east_span(grid)) / maxf(grid["ni"] - 1, 1)
	return maxf(dlat, dlon)


## Degrees from the first to the last longitude in the scanning direction.
static func _east_span(grid: Dictionary) -> float:
	var west := (int(grid["scan"]) & 0x80) != 0
	var d: float = grid["lo2"] - grid["lo1"]
	if west:
		d = -fposmod(-d, 360.0)
	else:
		d = fposmod(d, 360.0)
	if d == 0.0 and grid["ni"] > 1:
		d = 360.0 * (-1.0 if west else 1.0)
	return d


## Bilinear value of a field at a point; NAN outside the field or where all neighbors are missing.
static func _sample(f: Dictionary, lat: float, lon: float) -> float:
	var grid: Dictionary = f["grid"]
	var ni: int = grid["ni"]
	var nj: int = grid["nj"]
	var span := _east_span(grid)
	var dlon: float = span / maxf(ni - 1, 1)
	var dlat: float = (grid["la2"] - grid["la1"]) / maxf(nj - 1, 1)
	var fi: float = fposmod(lon - grid["lo1"], 360.0) / dlon if dlon > 0.0 else fposmod(grid["lo1"] - lon, 360.0) / -dlon
	var global_lon := absf(absf(span) + absf(dlon) - 360.0) < 1e-3
	var fj: float = (lat - grid["la1"]) / dlat if dlat != 0.0 else 0.0
	if fj < 0.0 or fj > nj - 1:
		return NAN
	if not global_lon and fi > ni - 1:
		return NAN
	var i0 := int(floor(fi))
	var j0 := mini(int(floor(fj)), nj - 2)
	var ti: float = fi - i0
	var tj: float = fj - j0
	var total := 0.0
	var weight := 0.0
	for dj in 2:
		for di in 2:
			var ii := i0 + di
			if global_lon:
				ii = posmod(ii, ni)
			elif ii > ni - 1:
				continue
			var jj := clampi(j0 + dj, 0, nj - 1)
			var v := _at(f, ii, jj)
			if is_nan(v):
				continue
			var w: float = (ti if di == 1 else 1.0 - ti) * (tj if dj == 1 else 1.0 - tj)
			total += v * w
			weight += w
	return total / weight if weight > 1e-6 else NAN


## Value at grid column i (scanning order along a row) and row j.
static func _at(f: Dictionary, i: int, j: int) -> float:
	var grid: Dictionary = f["grid"]
	var k := i * int(grid["nj"]) + j if (int(grid["scan"]) & 0x20) != 0 else j * int(grid["ni"]) + i
	return f["values"][k]


static func _date(unix: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%d/%02d %02d:%02dZ" % [d["day"], d["month"], d["hour"], d["minute"]]


## Ask the player for a GRIB file. done is called with (file name, bytes); nothing happens on cancel.
## The browser build uses a file input element; desktop uses a native open dialog.
static var _js_callback: JavaScriptObject  # kept alive while the browser picker is open


static func pick_file(owner: Node, done: Callable) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			window.godotPickGrib = function (callback) {
				const input = document.createElement('input');
				input.type = 'file';
				input.accept = '.grb,.grb2,.grib,.grib2,.bin';
				input.onchange = () => {
					const file = input.files[0];
					if (!file) return;
					const reader = new FileReader();
					reader.onload = () => {
						const bytes = new Uint8Array(reader.result);
						let text = '';
						for (let i = 0; i < bytes.length; i += 32768) {
							text += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
						}
						callback(file.name, btoa(text));
					};
					reader.readAsArrayBuffer(file);
				};
				input.click();
			};
		""", true)
		_js_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
			done.call(str(args[0]), Marshalls.base64_to_raw(str(args[1]))))
		JavaScriptBridge.get_interface("window").godotPickGrib(_js_callback)
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.grb, *.grb2, *.grib, *.grib2, *.bin ; GRIB files", "* ; All files"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String):
		done.call(path.get_file(), FileAccess.get_file_as_bytes(path))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	owner.add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))
