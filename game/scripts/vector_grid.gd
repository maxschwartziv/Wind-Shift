class_name VectorGrid
extends RefCounted
## A time series of (east, north) vectors on a regular lat/lon grid, read from a leg package .bin file.
## Layout: float32 [time][row][col][2], rows north to south.

var lat_north: float
var lon_west: float
var dlat: float
var dlon: float
var rows: int
var cols: int
var times: PackedFloat64Array
var data: PackedFloat32Array


static func load_from(path: String, header: Dictionary, times_s: Array) -> VectorGrid:
	var g := VectorGrid.new()
	g.lat_north = header["lat_north"]
	g.lon_west = header["lon_west"]
	g.dlat = header["dlat"]
	g.dlon = header["dlon"]
	g.rows = int(header["rows"])
	g.cols = int(header["cols"])
	g.times = PackedFloat64Array(times_s)
	g.data = FileAccess.get_file_as_bytes(path).to_float32_array()
	return g


func _cell(ti: int, r: int, c: int) -> Vector2:
	var i := ((ti * rows + r) * cols + c) * 2
	return Vector2(data[i], data[i + 1])


func _space(ti: int, lat: float, lon: float) -> Vector2:
	var fr := clampf((lat_north - lat) / dlat, 0.0, rows - 1.001)
	var fc := clampf((lon - lon_west) / dlon, 0.0, cols - 1.001)
	var r := int(fr)
	var c := int(fc)
	var tr := fr - r
	var tc := fc - c
	var top := _cell(ti, r, c).lerp(_cell(ti, r, c + 1), tc)
	var bottom := _cell(ti, r + 1, c).lerp(_cell(ti, r + 1, c + 1), tc)
	return top.lerp(bottom, tr)


## Vector in m/s at a position and time (seconds after leg start); bilinear in space, linear in time.
func sample(lat: float, lon: float, t: float) -> Vector2:
	var n := times.size()
	if t <= times[0]:
		return _space(0, lat, lon)
	if t >= times[n - 1]:
		return _space(n - 1, lat, lon)
	var i := times.bsearch(t) - 1
	var f := (t - times[i]) / (times[i + 1] - times[i])
	return _space(i, lat, lon).lerp(_space(i + 1, lat, lon), f)


func grid_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for r in rows:
		for c in cols:
			pts.append(Vector2(lat_north - r * dlat, lon_west + c * dlon))
	return pts
