class_name Ghost
extends RefCounted
## A real participant replayed from its recorded track.

const GAP_FADE_S := 3600.0

var name: String
var sail: String
var model: String
var boat_class: String
var class_start_s: float  # seconds after leg start
var start_s: float  # own crossing of the leg's start line, seconds after leg start
var start_estimated: bool  # no AIS fixes at the line: gun time plus the fleet's median delay
var finish_elapsed_s: float
var times: PackedFloat64Array
var lats: PackedFloat64Array
var lons: PackedFloat64Array
var world: PackedVector2Array
var is_ideal := false  # simulated best-VMC boat, not a real participant
var finished := true


static func from_dict(d: Dictionary, leg_start_utc: String) -> Ghost:
	var g := Ghost.new()
	g.name = d["name"]
	g.sail = str(d["sail"])
	g.model = d["model"]
	g.boat_class = d["class"]
	g.class_start_s = Time.get_unix_time_from_datetime_string(d["class_start_utc"]) \
			- Time.get_unix_time_from_datetime_string(leg_start_utc)
	g.start_s = d["start_s"]
	g.start_estimated = d.get("start_estimated", false)
	g.finish_elapsed_s = d["finish_elapsed_s"]
	for f in d["track"]:
		g.times.append(f[0])
		g.lats.append(f[1])
		g.lons.append(f[2])
	return g


## A ghost made from a simulated run (the ideal boats). Starts at the leg start.
static func from_run(name: String, model: String, trail: PackedVector2Array, trail_t: PackedFloat64Array,
		elapsed_s: float, finished: bool) -> Ghost:
	var g := Ghost.new()
	g.name = name
	g.model = model
	g.boat_class = "ideal"
	g.is_ideal = true
	g.finished = finished
	g.finish_elapsed_s = elapsed_s
	g.times = trail_t.duplicate()
	for p in trail:
		g.lats.append(p.x)
		g.lons.append(p.y)
	return g


func finish_time_s() -> float:
	return start_s + finish_elapsed_s


func build_world() -> void:
	world = PackedVector2Array()
	for i in times.size():
		world.append(Geo.to_world(lats[i], lons[i]))


## Index of the last fix at or before t, or -1 before the first fix.
func index_at(t: float) -> int:
	return times.bsearch(t, false) - 1


## {"pos": world point, "heading": deg, "in_gap": bool, "visible": bool}
func state_at(t: float) -> Dictionary:
	var n := times.size()
	if n < 2 or t < times[0]:
		return {"visible": false}
	var i := index_at(t)
	if i >= n - 1:
		return {"visible": true, "pos": world[n - 1], "heading": _heading(n - 2), "in_gap": false, "done": true}
	var dt := times[i + 1] - times[i]
	var f := (t - times[i]) / dt if dt > 0.0 else 1.0  # two fixes at one time: use the later one
	var gap := times[i + 1] - times[i] > GAP_FADE_S
	# Turn the icon gradually: blend each segment's heading with its neighbor's around the shared point.
	var h := lerp_angle(deg_to_rad(_heading(i - 1)), deg_to_rad(_heading(i)), 0.5 + f) if f < 0.5 			else lerp_angle(deg_to_rad(_heading(i)), deg_to_rad(_heading(i + 1)), f - 0.5)
	return {"visible": true, "pos": world[i].lerp(world[i + 1], f), "heading": rad_to_deg(h), "in_gap": gap, "done": false}


func _heading(i: int) -> float:
	i = clampi(i, 0, times.size() - 2)
	var off := Geo.offset_m(Vector2(lats[i], lons[i]), Vector2(lats[i + 1], lons[i + 1]))
	return Geo.bearing(off)
