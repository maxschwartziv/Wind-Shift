class_name NearLand
extends RefCounted
## Which water lies within RADIUS_M of land (or of water shallower than a depth), on a grid of about
## CELL_M cells filled in on first use. The isochrone router asks for every candidate segment, so a
## lookup is one array read once its cell is known.

const CELL_M := 180.0
const RADIUS_M := 1200.0
## Water deeper than this counts as clear without scanning: on these coasts land is never within
## RADIUS_M of it. The scan itself reads every second cell (360 m apart), enough to find a shore.
const DEEP_M := 150.0

var pkg: LegPackage
var min_depth: float
var _flags := PackedByteArray()  # 0 not computed, 1 clear, 2 near land
var _rows := 0
var _cols := 0
var _lat_n := 0.0
var _lon_w := 0.0
var _cell_deg := CELL_M / 111320.0

static var _cache := {}  # "<leg dir>|<min depth>" -> NearLand


static func for_leg(p: LegPackage, depth_m: float) -> NearLand:
	var key := "%s|%.1f" % [p.dir, depth_m]
	if not _cache.has(key):
		var n := NearLand.new()
		n.pkg = p
		n.min_depth = depth_m
		var b: Dictionary = p.info["bounds"]
		n._lat_n = b["lat_max"] + 0.2
		n._lon_w = b["lon_min"] - 0.2
		n._rows = int((b["lat_max"] - b["lat_min"] + 0.4) / n._cell_deg) + 1
		n._cols = int((b["lon_max"] - b["lon_min"] + 0.4) / n._cell_deg) + 1
		n._flags.resize(n._rows * n._cols)
		_cache[key] = n
	return _cache[key]


func is_near(lat: float, lon: float) -> bool:
	var r := int((_lat_n - lat) / _cell_deg)
	var c := int((lon - _lon_w) / _cell_deg)
	if r < 0 or c < 0 or r >= _rows or c >= _cols:
		return true
	var i := r * _cols + c
	var f := _flags[i]
	if f == 0:
		f = 2 if _scan(_lat_n - (r + 0.5) * _cell_deg, _lon_w + (c + 0.5) * _cell_deg) else 1
		_flags[i] = f
	return f == 2


func _scan(lat: float, lon: float) -> bool:
	if pkg.depth_at(lat, lon) > DEEP_M:
		return false
	var n := int(RADIUS_M / CELL_M)
	var dlon_cell := _cell_deg / maxf(cos(deg_to_rad(lat)), 0.1)
	for di in range(-n, n + 1, 2):
		for dj in range(-n, n + 1, 2):
			if di * di + dj * dj <= n * n and pkg.depth_at(lat + di * _cell_deg, lon + dj * dlon_cell) < min_depth:
				return true
	return false
