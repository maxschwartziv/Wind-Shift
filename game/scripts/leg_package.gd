class_name LegPackage
extends RefCounted
## Everything the game knows about one leg: course, rules, fleet, weather, currents, depth.
## Loaded from a static package built by the pipeline (docs/adr/0001).

var dir: String
var info: Dictionary
var start_line: Array[Vector2] = []
var finish_line: Array[Vector2] = []
var marks: Array[Vector2] = []
var wind: VectorGrid
var current: VectorGrid
var forecasts: Array[Dictionary] = []  # {"run_utc", "available_s", "grid"}
var ghosts: Array[Ghost] = []
var depth_bytes: PackedByteArray
var depth_header: Dictionary


static func load_dir(path: String) -> LegPackage:
	var p := LegPackage.new()
	p.dir = path
	p.info = JSON.parse_string(FileAccess.get_file_as_string(path + "/leg.json"))
	for pt in p.info["start_line"]:
		p.start_line.append(Vector2(pt[0], pt[1]))
	for pt in p.info["finish_line"]:
		p.finish_line.append(Vector2(pt[0], pt[1]))
	for pt in p.info["marks"]:
		p.marks.append(Vector2(pt[0], pt[1]))
	var w: Dictionary = p.info["wind"]
	p.wind = VectorGrid.load_from(path + "/" + w["file"], w, w["times_s"])
	var c: Dictionary = p.info["current"]
	p.current = VectorGrid.load_from(path + "/" + c["file"], c, c["times_s"])
	var f: Dictionary = p.info["forecast"]
	for run in f["runs"]:
		p.forecasts.append({"run_utc": run["run_utc"], "available_s": float(run["available_s"]),
				"grid": VectorGrid.load_from(path + "/" + run["file"], f, run["times_s"])})
	p.depth_header = p.info["depth"]
	p.depth_bytes = FileAccess.get_file_as_bytes(path + "/" + p.depth_header["file"])
	var fleet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + "/" + p.info["fleet"]))
	for g in fleet["ghosts"]:
		p.ghosts.append(Ghost.from_dict(g, p.info["start_utc"]))
	return p


## Leg packages in res://packages: [[id, leg name], ...].
## Legs left out of the race lists. The packages stay, for the main menu background and the tests.
const HIDDEN := [
	"n2e-2025",  # Newport to Ensenada 2025: to fix later
]


## [id, "Event: leg"] for each race the player can pick. A hidden leg is listed only when it is `keep`,
## the leg already loaded.
static func list(keep := "") -> Array:
	var out := []
	for id in DirAccess.get_directories_at("res://packages"):
		if id in HIDDEN and id != keep:
			continue
		var path := "res://packages/%s/leg.json" % id
		if FileAccess.file_exists(path):
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			out.append([id, "%s: %s" % [d.get("event", id), d.get("leg", "")]])
	return out


func start_unix() -> float:
	return Time.get_unix_time_from_datetime_string(info["start_utc"])


func utc_offset_s() -> int:
	return int(info.get("utc_offset_s", 0))


## Depth below the surface in meters (positive in water, zero or negative on land). Bilinear.
func depth_at(lat: float, lon: float) -> float:
	var h := depth_header
	var rows := int(h["rows"])
	var cols := int(h["cols"])
	var fr := clampf((float(h["lat_north"]) - lat) / float(h["dlat"]), 0.0, rows - 1.001)
	var fc := clampf((lon - float(h["lon_west"])) / float(h["dlon"]), 0.0, cols - 1.001)
	var r := int(fr)
	var c := int(fc)
	var tr := fr - r
	var tc := fc - c
	var top := lerpf(_elev(r, c, cols), _elev(r, c + 1, cols), tc)
	var bottom := lerpf(_elev(r + 1, c, cols), _elev(r + 1, c + 1, cols), tc)
	return -lerpf(top, bottom, tr)


func _elev(r: int, c: int, cols: int) -> float:
	return depth_bytes.decode_s16((r * cols + c) * 2) / 10.0


## The period forecast the player can see at time t: the newest run already published.
func forecast_at(t: float) -> Dictionary:
	var best: Dictionary = forecasts[0]
	for f in forecasts:
		if f["available_s"] <= t:
			best = f
	return best


func credits() -> Array:
	return info["credits"]
