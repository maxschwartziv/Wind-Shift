class_name Overlay
extends Node2D
## Everything drawn over the map: course lines, wind and current arrows, ghost boats and trails,
## the player boat, its trail, projected track and the suggested heading.

const PLAYER_COLOR := Color(1.0, 0.55, 0.1)
const GHOST_COLOR := Color(0.85, 0.92, 1.0)
const SUGGEST_COLOR := Color(0.2, 0.95, 0.95)
const CURRENT_COLOR := Color(0.4, 0.8, 1.0, 0.8)

var pkg: LegPackage
var sim: RaceSim
var camera: Camera2D
var show_wind := false
var show_current := false
var show_trails := true
var show_labels := false
## Wind map: show the actual wind instead of the period forecast, and the time it shows.
var show_actual := false
var view_t := 0.0
var ideals: Array[Ghost] = []  # forecast-ideal and actual-ideal boats
var show_tests := false  # full tracks of the ideal boats
var suggestion := {}
var shown_heading := 0.0  # player icon heading, eased toward the sim heading
var use_utc := false  # arrival times in UTC instead of the leg's local time
var measure_on := false
var hide_player := false  # behind the main menu only the fleet shows
var waypoint_hint := {}  # {"index", "text"} for the waypoint under the pointer  # the map shows the boat's measured wind in a circle around it
var selected_leg := 0  # leg shown on the leg instrument
var legs: Array = []  # RaceSim.leg_forecast for the route
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


## Screen pixels to world units at the present zoom.
func px(v: float) -> float:
	return v / camera.zoom.x


## Text at a world point, offset and sized in screen pixels, so it stays sharp at every zoom.
func _text(at: Vector2, offset_px: Vector2, text: String, size_px: int, color: Color) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE / camera.zoom.x)
	draw_string_outline(font, offset_px, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(size_px), 3, Color(0, 0, 0, 0.6))
	draw_string(font, offset_px, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(size_px), color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	_draw_course()
	if show_wind:
		_draw_wind()
	if show_current:
		_draw_current()
	_draw_test_tracks()
	_draw_ghosts()
	_draw_ideals()
	_draw_route()
	_draw_player()


func _draw_course() -> void:
	var s := pkg.start_line
	draw_line(Geo.to_world(s[0].x, s[0].y), Geo.to_world(s[1].x, s[1].y), Color.WHITE, px(3))
	var f := pkg.finish_line
	var a := Geo.to_world(f[0].x, f[0].y)
	var b := Geo.to_world(f[1].x, f[1].y)
	draw_dashed_line(a, b, Color(1, 0.9, 0.2), px(3), px(14))
	_text(a, Vector2(6, -8), "Finish line", 14, Color(1, 0.9, 0.2))


func _arrow(at: Vector2, v: Vector2, color: Color, length_px: float) -> void:
	# v is (east, north); screen y points south.
	var dir := Vector2(v.x, -v.y).normalized()
	var tip := at + dir * px(length_px)
	draw_line(at, tip, color, px(1.5))
	draw_line(tip, tip - dir.rotated(0.45) * px(7), color, px(1.5))
	draw_line(tip, tip - dir.rotated(-0.45) * px(7), color, px(1.5))


## Wind grid the map shows: the actual wind, or the newest forecast run published by the present race time.
func wind_grid() -> VectorGrid:
	return pkg.wind if show_actual else pkg.forecast_at(sim.t)["grid"]


## Wind on the map at a point (m/s east, north): the map's source, except the actual wind inside the
## circle where the boat measures it.
func wind_sample(at: Vector2, time: float) -> Vector2:
	if measure_on and Geo.distance_nm(at, sim.display_pos()) <= RaceSim.MEASURE_NM:
		return pkg.wind.sample(at.x, at.y, time)
	return wind_grid().sample(at.x, at.y, time)


const ARROW_SPACING_PX := 70.0

## Wind arrows on a screen grid about ARROW_SPACING_PX apart, interpolated between the data points,
## over water inside the leg's area. Every other arrow carries its speed in knots.
func _draw_wind() -> void:
	var view := get_viewport_rect().size / camera.zoom
	var center := camera.get_screen_center_position()
	var step := px(ARROW_SPACING_PX)
	var b: Dictionary = pkg.info["bounds"]
	var x0 := floorf((center.x - view.x / 2.0) / step) * step
	var y0 := floorf((center.y - view.y / 2.0) / step) * step
	var row := 0
	var y := y0
	while y <= center.y + view.y / 2.0:
		var x := x0 + (step / 2.0 if row % 2 == 1 else 0.0)
		var col_i := 0
		while x <= center.x + view.x / 2.0:
			var ll := Geo.to_latlon(Vector2(x, y))
			if ll.x >= b["lat_min"] and ll.x <= b["lat_max"] and ll.y >= b["lon_min"] and ll.y <= b["lon_max"] and pkg.depth_at(ll.x, ll.y) > 0.0:
				var v := wind_sample(ll, view_t)
				var kn := v.length() / Geo.MS_PER_KN
				var col := WindPalette.color(kn)
				_arrow(Vector2(x, y), v, col, 14.0 + kn * 1.6)
				if (row + col_i) % 2 == 0:
					_text(Vector2(x, y), Vector2(4, 14), "%d" % roundi(kn), 11, col)
			x += step
			col_i += 1
		y += step
		row += 1


const IDEAL_COLORS := {"Forecast ideal": Color(0.95, 0.35, 0.95), "Actual ideal": Color(0.3, 1.0, 0.45)}


func _draw_test_tracks() -> void:
	if not show_tests:
		return
	for g in ideals:
		var col: Color = IDEAL_COLORS[g.name]
		if g.world.size() >= 2:
			draw_polyline(g.world, Color(col, 0.8), px(2.5))
			var tag := "%s: computing" % g.name
			if is_finite(g.finish_elapsed_s):
				tag = "%s: %s %d:%02d" % [g.name, "finished" if g.finished else "did not finish",
						int(g.finish_elapsed_s / 3600), int(fmod(g.finish_elapsed_s, 3600) / 60)]
			var off := Vector2(8, 18 if g.name == "Actual ideal" else -6)
			_text(g.world[g.world.size() - 1], off, tag, 14, col)


func _draw_ideals() -> void:
	for g in ideals:
		var st := g.state_at(sim.display_t())
		if not st["visible"]:
			continue
		var col: Color = IDEAL_COLORS[g.name]
		if show_trails and not show_tests:
			var i := g.index_at(sim.display_t())
			if i >= 1:
				var pts := g.world.slice(0, i + 1)
				pts.append(st["pos"])
				draw_polyline(pts, Color(col, 0.5), px(1.5))
		_boat_shape(st["pos"], st["heading"], 8.0, col, true)
		_text(st["pos"], Vector2(9, 4), g.name, 12, col)


func _draw_route() -> void:
	if sim.waypoints.is_empty() or sim.state != "racing":
		return
	var dp := sim.display_pos()
	var prev := Geo.to_world(dp.x, dp.y)
	for i in sim.waypoints.size():
		var w := Geo.to_world(sim.waypoints[i].x, sim.waypoints[i].y)
		draw_dashed_line(prev, w, Color(1, 1, 1, 0.8), px(1.5), px(10))
		draw_arc(w, px(7), 0, TAU, 20, Color.WHITE, px(2))
		_text(w, Vector2(9, -6), str(i + 1), 13, Color.WHITE)
		_eta_label(w, i)
		if waypoint_hint.get("index", -1) == i:
			draw_arc(w, px(11), 0, TAU, 24, Color(1, 0.9, 0.2), px(2))
		prev = w
	if legs.size() == sim.waypoints.size() + 1:
		var f: Vector2 = legs[legs.size() - 1]["to"]
		var fw := Geo.to_world(f.x, f.y)
		draw_circle(fw, px(4), Color(1, 0.9, 0.2))
		_text(fw, Vector2(9, -6), "Finish", 13, Color(1, 0.9, 0.2))
		_eta_label(fw, legs.size() - 1)
	_draw_selected_leg()


## Time to reach the end of leg i, from the leg forecast, and the clock time of arrival.
func _eta_label(at: Vector2, i: int) -> void:
	if i >= legs.size() or legs.size() != sim.waypoints.size() + 1:
		return
	var arrive: float = legs[i]["start_t"] + legs[i]["dur_s"]
	var left := maxf(arrive - sim.display_t(), 0.0)
	var m := roundi(left / 60.0)
	var unix := pkg.start_unix() + arrive + (0 if use_utc else pkg.utc_offset_s())
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	var text := "%d h %02d min  ·  %02d:%02d%s" % [m / 60, m % 60, d["hour"], d["minute"], " UTC" if use_utc else ""]
	_text(at, Vector2(9, 10), text, 12, Color(1, 1, 1, 0.9))


## The leg shown on the leg instrument, drawn over the route line.
func _draw_selected_leg() -> void:
	if selected_leg < 0 or selected_leg >= legs.size() or sim.state != "racing":
		return
	var leg: Dictionary = legs[selected_leg]
	var a: Vector2 = sim.display_pos() if selected_leg == 0 else leg["from"]
	var b: Vector2 = leg["to"]
	draw_line(Geo.to_world(a.x, a.y), Geo.to_world(b.x, b.y), Color(SUGGEST_COLOR, 0.55), px(5), true)


func _duration(s: float) -> String:
	var m := roundi(s / 60.0)
	return "%d h %02d min" % [m / 60, m % 60]


func _draw_current() -> void:
	var g := pkg.current
	for r in range(0, g.rows, 2):
		for c in range(0, g.cols, 2):
			var lat := g.lat_north - r * g.dlat
			var lon := g.lon_west + c * g.dlon
			if pkg.depth_at(lat, lon) <= 0.0:
				continue
			var v := g.sample(lat, lon, view_t)
			var kn := v.length() / Geo.MS_PER_KN
			if kn < 0.05:
				continue
			_arrow(Geo.to_world(lat, lon), v, CURRENT_COLOR, 8.0 + kn * 40.0)


func _boat_shape(at: Vector2, heading: float, size_px: float, color: Color, filled: bool) -> void:
	var r := deg_to_rad(heading)
	var fwd := Vector2(sin(r), -cos(r))
	var side := Vector2(-fwd.y, fwd.x)
	var s := px(size_px)
	var pts := PackedVector2Array([at + fwd * s, at - fwd * s * 0.7 + side * s * 0.45, at - fwd * s * 0.7 - side * s * 0.45])
	if not (at.is_finite() and is_finite(heading)):
		return  # a bad fix would fail triangulation
	if filled:
		_fill(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, px(1.5))


func _draw_ghosts() -> void:
	for g in pkg.ghosts:
		var st := g.state_at(sim.display_t())
		if not st["visible"]:
			continue
		if show_trails:
			var i := g.index_at(sim.display_t())
			if i >= 1:
				var pts := g.world.slice(0, i + 1)
				pts.append(st["pos"])
				draw_polyline(pts, Color(GHOST_COLOR, 0.35), px(1.2))
		var faded: bool = st["in_gap"]
		_boat_shape(st["pos"], st["heading"], 7.0, Color(GHOST_COLOR, 0.45 if faded else 0.95), not faded)
		if show_labels:
			_text(st["pos"], Vector2(8, 4), g.name, 12, Color(GHOST_COLOR, 0.9))


func _draw_player() -> void:
	if hide_player:
		return
	var pts := PackedVector2Array()
	for p in sim.trail:
		pts.append(Geo.to_world(p.x, p.y))
	var dp := sim.display_pos()
	var here := Geo.to_world(dp.x, dp.y)
	pts.append(here)
	if pts.size() >= 2:
		draw_polyline(pts, PLAYER_COLOR, px(2))
	if sim.state == "racing":
		var proj := sim.projected_track(sim.heading)
		var track: PackedVector2Array = proj["points"]
		var gi: int = proj["ground_index"]
		for i in range(track.size() - 1):
			var col := Color(1, 0.2, 0.15) if (gi >= 0 and i + 1 >= gi) else Color(PLAYER_COLOR, 0.6)
			draw_line(Geo.to_world(track[i].x, track[i].y), Geo.to_world(track[i + 1].x, track[i + 1].y), col, px(2))
		if suggestion.get("heading", -1.0) >= 0.0:
			var d := Geo.heading_vec(suggestion["heading"])
			draw_dashed_line(here, here + Vector2(d.x, -d.y) * px(90), SUGGEST_COLOR, px(2), px(8))
	if measure_on:
		var r := RaceSim.MEASURE_NM * Geo.M_PER_NM / (40075016.686 * cos(deg_to_rad(dp.x)) / Geo.WORLD)
		draw_arc(here, r, 0, TAU, 96, Color(1, 1, 1, 0.45), px(1.5), true)
		_text(here + Vector2(0, -r), Vector2(-46, -6), "measured wind", 11, Color(1, 1, 1, 0.75))
	if sim.state == "racing":
		_draw_vectors(here)
	_boat_shape(here, shown_heading, 10.0, PLAYER_COLOR, true)


const VECTOR_PX_PER_KN := 14.0
const STW_COLOR := Color("#e8eef2")
const SET_COLOR := Color("#c9a0ff")  # current vector at the boat
const SOG_COLOR := Color("#8be06a")

## Speed through the water plus the current gives the speed over ground, drawn from the boat at one scale.
func _draw_vectors(here: Vector2) -> void:
	var k := px(VECTOR_PX_PER_KN)
	var hv := Geo.heading_vec(sim.heading)
	var stw_end := here + Vector2(hv.x, -hv.y) * sim.stw * k
	var cur_kn := Vector2(sim.current.x, -sim.current.y) / Geo.MS_PER_KN
	var sog_end := stw_end + cur_kn * k
	_vector(here, stw_end, STW_COLOR)
	if cur_kn.length() > 0.02:
		_vector(stw_end, sog_end, SET_COLOR)
		_text(sog_end, Vector2(8, 4), "current %.1f kn" % cur_kn.length(), 11, SET_COLOR)
	_vector(here, sog_end, SOG_COLOR)
	_text(stw_end, Vector2(8, -8), "STW %.1f" % sim.stw, 11, STW_COLOR)
	_text(sog_end, Vector2(8, 18), "SOG %.1f" % sim.sog_kn(), 11, SOG_COLOR)


func _vector(from: Vector2, to: Vector2, color: Color) -> void:
	if from.distance_to(to) < px(2):
		return
	draw_line(from, to, color, px(3), true)
	var d := (to - from).normalized()
	var side := Vector2(-d.y, d.x)
	var h := px(10)
	_fill(PackedVector2Array([to, to - d * h + side * h * 0.45, to - d * h - side * h * 0.45]), color)


## A filled polygon drawn relative to its first point. World coordinates run to several hundred
## thousand, and Godot's triangulation fails on small shapes that far from the origin.
func _fill(pts: PackedVector2Array, color: Color) -> void:
	var o := pts[0]
	var local := PackedVector2Array()
	for q in pts:
		local.append(q - o)
	draw_set_transform(o)
	draw_colored_polygon(local, color)
	draw_set_transform(Vector2.ZERO)
