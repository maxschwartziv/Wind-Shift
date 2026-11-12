class_name HelpAnim
extends Control
## Animated diagrams for the help panel. Each page has its own drawing; the wind comes from the top
## (north) in every diagram, and curves use the player boat's polar at 10 kn of true wind.

enum Page { POLAR, WIND, COURSE, VMC, NO_GO, ROUTING, INSTRUMENT, STEERING, NONE }

const BG := Color(0.086, 0.125, 0.165)
const RING := Color("#3a4a58")
const TEXT := Color("#e8eef2")
const MUTED := Color("#8fa1ae")
const HEADING := Color("#f5a442")
const SUGGEST := Color("#5fd3c6")
const WIND := Color("#9fc8ff")
const SOG := Color("#8be06a")
const SET := Color("#c9a0ff")
const NO_GO := Color("#f0603a")
const TWS := 10.0

var page := Page.POLAR
var polar: Polar
var font: Font
var t := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(460, 460)
	clip_contents = true


func show_page(p: Page) -> void:
	page = p
	t = 0.0
	if p == Page.ROUTING and _router == null:
		_build_route()
	visible = p != Page.NONE
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()


func _draw() -> void:
	if polar == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	match page:
		Page.POLAR:
			_polar()
		Page.WIND:
			_wind()
		Page.COURSE:
			_course()
		Page.VMC:
			_vmc()
		Page.NO_GO:
			_no_go()
		Page.ROUTING:
			_routing()
		Page.INSTRUMENT:
			_instrument()
		Page.STEERING:
			_steering()


# Polar: the boat turns through every heading and traces its speed curve.
func _polar() -> void:
	var c := size / 2.0 + Vector2(0, 14)
	var k := _scale(160.0)
	_speed_rings(c, k)
	_wind_arrow(c, 190.0)
	var heading := fmod(t * 40.0, 360.0)
	draw_polyline(_curve(c, k, 0.0, 360.0), Color(SOG, 0.25), 2.0, true)
	draw_polyline(_curve(c, k, 0.0, heading), SOG, 3.0, true)
	var twa := absf(Geo.wrap180(heading))
	var p := c + _dir(heading) * _stw(heading) * k
	draw_line(c, p, HEADING, 2.0, true)
	draw_circle(p, 5.0, HEADING)
	_boat(c, heading, 16.0, HEADING)
	_label(Vector2(14, 26), "TWA %d°" % roundi(twa), 18, TEXT)
	_label(Vector2(14, 50), "STW %.1f kn" % _stw(heading), 18, SOG)
	_label(Vector2(size.x - 14, 26), "TWS %d kn" % roundi(TWS), 14, WIND, true)


# Wind terms: true wind plus the wind of the boat's own motion makes the apparent wind.
func _wind() -> void:
	var c := size / 2.0 + Vector2(0, 20)
	var k := 16.0
	var heading := 90.0 + 55.0 * sin(t * 0.6)
	var stw := _stw(heading)
	var true_air := Vector2(0, 1) * TWS  # air moving toward the south, screen down
	var boat_v := _dir(heading) * stw
	var app_air := true_air - boat_v
	_arrow(c - true_air * k, c, WIND, 3.0)
	_arrow(c + boat_v * k, c, MUTED, 2.0)
	_arrow(c - app_air * k, c, TEXT, 3.0)
	_boat(c, heading, 18.0, HEADING)
	draw_dashed_line(c, c + _dir(heading) * 140.0, Color(HEADING, 0.6), 1.5, 5.0)
	var twa := absf(Geo.wrap180(0.0 - heading))
	var awa := absf(Geo.wrap180(rad_to_deg(atan2(-app_air.x, app_air.y)) - heading))
	_label(c - true_air * k + Vector2(8, 0), "true wind", 13, WIND)
	_label(c + boat_v * k + Vector2(8, 14), "wind from boat speed", 13, MUTED)
	_label(c - app_air * k + Vector2(-60, -6), "apparent wind", 13, TEXT)
	_label(Vector2(14, 26), "TWS %.1f kn   TWA %d°" % [TWS, roundi(twa)], 16, WIND)
	_label(Vector2(14, 50), "AWS %.1f kn   AWA %d°" % [app_air.length(), roundi(awa)], 16, TEXT)
	_label(Vector2(14, 74), "STW %.1f kn" % stw, 16, MUTED)


# Course terms: speed through the water plus the current gives speed and course over ground.
func _course() -> void:
	var c := Vector2(size.x * 0.32, size.y * 0.62)
	var k := 28.0
	var heading := 60.0
	var stw := 6.0
	var cur := _dir(fmod(t * 30.0, 360.0)) * 1.8
	var stw_end := c + _dir(heading) * stw * k
	var sog_end := stw_end + cur * k
	draw_dashed_line(c, c + _dir(heading) * 260.0, Color(HEADING, 0.5), 1.5, 5.0)
	_arrow(c, stw_end, TEXT, 3.0)
	_arrow(stw_end, sog_end, SET, 3.0)
	_arrow(c, sog_end, SOG, 3.0)
	_boat(c, heading, 16.0, HEADING)
	var sog := (sog_end - c) / k
	var cog := fposmod(rad_to_deg(atan2(sog.x, -sog.y)), 360.0)
	_label(stw_end + Vector2(-70, -10), "STW", 14, TEXT)
	_label(sog_end + Vector2(10, 4), "current", 14, SET)
	_label((c + sog_end) / 2.0 + Vector2(10, 18), "SOG", 14, SOG)
	_label(Vector2(14, 26), "HDG %03d°   STW %.1f kn" % [roundi(heading), stw], 16, HEADING)
	_label(Vector2(14, 50), "current %.1f kn" % cur.length(), 16, SET)
	_label(Vector2(14, 74), "COG %03d°   SOG %.1f kn" % [roundi(cog), sog.length()], 16, SOG)


# VMC: the heading sweeps around; the part of SOG that points at the waypoint is the VMC.
func _vmc() -> void:
	var c := size / 2.0 + Vector2(0, 20)
	var k := _scale(150.0)
	var tgt := 25.0
	_speed_rings(c, k)
	_wind_arrow(c, 180.0)
	draw_polyline(_curve(c, k, 0.0, 360.0), SOG, 2.0, true)
	var wp := c + _dir(tgt) * 175.0
	draw_dashed_line(c, wp, SUGGEST, 1.5, 6.0)
	draw_circle(wp, 6.0, SUGGEST)
	_label(wp + Vector2(10, 4), "waypoint", 13, SUGGEST)
	var best := 0.0
	var best_vmc := -INF
	for h in 360:
		var v := _stw(h) * cos(deg_to_rad(h - tgt))
		if v > best_vmc:
			best_vmc = v
			best = h
	var heading := tgt + 110.0 * sin(t * 0.5)
	var sog := _stw(heading)
	var vmc := sog * cos(deg_to_rad(heading - tgt))
	var p := c + _dir(heading) * sog * k
	var proj := c + _dir(tgt) * vmc * k
	draw_line(c, p, HEADING, 2.5, true)
	draw_dashed_line(p, proj, Color(HEADING, 0.7), 1.0, 3.0)
	if vmc > 0.0:
		draw_line(c, proj, SUGGEST, 5.0)
	draw_circle(p, 5.0, HEADING)
	draw_circle(c + _dir(best) * _stw(best) * k, 6.0, SUGGEST)
	_label(Vector2(14, 26), "heading %03d°   SOG %.1f kn" % [roundi(fposmod(heading, 360.0)), sog], 16, HEADING)
	_label(Vector2(14, 50), "VMC %.1f kn" % vmc, 16, SUGGEST)
	_label(Vector2(14, 74), "best %03d°   VMC %.1f kn" % [roundi(best), best_vmc], 14, MUTED)


# No-go zone: a boat bound for a mark upwind tacks along the edges of the wedge.
func _no_go() -> void:
	var beat := SogPlot.beat_angle(polar, TWS)
	var mark := Vector2(size.x / 2.0, 70.0)
	var start := Vector2(size.x / 2.0, size.y - 50.0)
	var leg := 70.0 / sin(deg_to_rad(beat))
	var pts := PackedVector2Array([start])
	var side := 1.0
	while pts[pts.size() - 1].y > mark.y + 10.0:
		var last := pts[pts.size() - 1]
		var next := last + Vector2(side * sin(deg_to_rad(beat)), -cos(deg_to_rad(beat))) * leg
		if next.y < mark.y:
			next = mark
		pts.append(next)
		side = -side
		leg = 140.0 / sin(deg_to_rad(beat))
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var d := fmod(t * 70.0, total + 60.0)
	var pos := pts[pts.size() - 1]
	var heading := 0.0
	var walked := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if d <= walked + seg:
			pos = pts[i].lerp(pts[i + 1], (d - walked) / seg)
			var v := pts[i + 1] - pts[i]
			heading = rad_to_deg(atan2(v.x, -v.y))
			break
		walked += seg
	draw_polyline(pts, Color(HEADING, 0.35), 1.5, true)
	var wedge := PackedVector2Array([pos])
	for i in 13:
		wedge.append(pos + _dir(-beat + 2.0 * beat * i / 12.0) * 110.0)
	draw_colored_polygon(wedge, Color(NO_GO, 0.15))
	draw_dashed_line(pos, wedge[1], NO_GO, 1.0, 3.0)
	draw_dashed_line(pos, wedge[wedge.size() - 1], NO_GO, 1.0, 3.0)
	draw_circle(mark, 7.0, SUGGEST)
	_label(mark + Vector2(12, 5), "mark", 13, SUGGEST)
	_boat(pos, heading, 14.0, HEADING)
	_wind_arrow(Vector2(size.x - 60.0, size.y / 2.0), 50.0)
	_label(Vector2(14, 26), "no-go: %d° either side of the wind" % roundi(beat), 16, NO_GO)
	_label(Vector2(14, 50), "tack angle %d°" % roundi(2.0 * beat), 16, TEXT)


# Instrument: a still copy of the boat instrument with numbered parts.
func _instrument() -> void:
	var c := size / 2.0 + Vector2(0, 10)
	var k := _scale(150.0)
	var r := 160.0
	var wind_from := 0.0
	var beat := SogPlot.beat_angle(polar, TWS)
	var wedge := PackedVector2Array([c])
	for i in 13:
		wedge.append(c + _dir(wind_from - beat + 2.0 * beat * i / 12.0) * r)
	draw_colored_polygon(wedge, Color(NO_GO, 0.13))
	draw_arc(c, r, 0, TAU, 96, RING, 1.5, true)
	draw_polyline(_curve(c, k, 0.0, 360.0), SOG, 2.5, true)
	var tgt := 140.0
	draw_dashed_line(c, c + _dir(tgt) * r, SUGGEST, 1.5, 6.0)
	_wind_arrow(c, r)
	var best := 0.0
	var best_vmc := -INF
	for h in 360:
		var v := _stw(h) * cos(deg_to_rad(h - tgt))
		if v > best_vmc:
			best_vmc = v
			best = h
	var heading := 110.0
	var now := c + _dir(heading) * _stw(heading) * k
	draw_line(c, now, HEADING, 3.0, true)
	draw_circle(now, 5.0, HEADING)
	var bp := c + _dir(best) * _stw(best) * k
	draw_circle(bp, 6.0, SUGGEST)
	var notes := [
		[now, "1"], [bp, "2"], [c + _dir(tgt) * r, "3"], [c + _dir(wind_from) * (r + 12.0), "4"],
		[c + _dir(wind_from) * r * 0.6, "5"], [c + _dir(250.0) * _stw(250.0) * k, "6"],
	]
	for n in notes:
		var at: Vector2 = n[0] + Vector2(10, -10)
		draw_circle(at, 10.0, TEXT)
		_label(at + Vector2(-4, 5), n[1], 13, BG)


# Routing: the isochrone router on a small made-up sea, 30 nm from start to finish, with wind from the
# northwest, a light-wind pocket on the direct line and an island. Each isochrone appears in turn,
# then the route traced back from the finish, then a boat sailing it.
const R_POCKET := Vector2(-0.25, 0.0)  # (lat, lon) of the light-wind pocket
const R_ISLAND := Vector2(-0.10, 0.09)
const R_FINISH_LAT := -0.5
var _router: IsoRouter
var _route: Array[Vector3] = []


func _sea_wind(lat: float, lon: float) -> Vector2:
	var d := Vector2(lat, lon).distance_to(R_POCKET) / 0.09
	var kn := 12.0 * (1.0 - 0.85 * exp(-d * d))
	return Geo.heading_vec(300.0 + 180.0) * kn * Geo.MS_PER_KN


func _build_route() -> void:
	_router = IsoRouter.new()
	_router.polar = polar
	_router.dt = 1800.0
	_router.heading_step = 5.0
	_router.fine_span = 0.0
	_router.sector_deg = 2.0
	_router.sector_m = 0.0
	_router.cond_fn = func(lat: float, lon: float, _t: float) -> Dictionary:
		return {"wind": _sea_wind(lat, lon), "current": Vector2.ZERO}
	_router.blocked_fn = func(lat: float, lon: float) -> bool:
		return Vector2(lat, lon).distance_to(R_ISLAND) < 0.045
	_router.setup(Vector2.ZERO, 0.0, Vector2(R_FINISH_LAT, -0.2), Vector2(R_FINISH_LAT, 0.2))
	while not _router.done:
		_router.step(1000.0)
	_route = _router.path()


func _routing() -> void:
	var k := 640.0  # pixels per degree
	var o := Vector2(size.x / 2.0, 70.0)
	var to_px := func(lat: float, lon: float) -> Vector2: return o + Vector2(lon * k, -lat * k)
	# Sea features: light-wind pocket, island, start and finish.
	for ring in [1.0, 0.7, 0.4]:
		draw_circle(to_px.call(R_POCKET.x, R_POCKET.y), 0.09 * k * ring, Color(0.35, 0.55, 1.0, 0.10))
	_label(to_px.call(R_POCKET.x, R_POCKET.y) + Vector2(-34, 4), "light wind", 12, WIND)
	draw_circle(to_px.call(R_ISLAND.x, R_ISLAND.y), 0.045 * k, Color(0.55, 0.45, 0.3))
	_label(to_px.call(R_ISLAND.x, R_ISLAND.y) + Vector2(-18, 4), "island", 11, BG)
	draw_line(to_px.call(R_FINISH_LAT, -0.2), to_px.call(R_FINISH_LAT, 0.2), Color(1, 0.9, 0.2), 3.0)
	_label(to_px.call(R_FINISH_LAT, 0.2) + Vector2(-50, 18), "finish", 12, Color(1, 0.9, 0.2))
	draw_dashed_line(to_px.call(0.0, 0.0), to_px.call(R_FINISH_LAT, 0.0), Color(1, 1, 1, 0.3), 1.0, 5.0)
	var wind_at := Vector2(size.x - 50.0, 80.0)
	var wd := Geo.heading_vec(300.0 + 180.0)
	_arrow(wind_at - Vector2(wd.x, -wd.y) * 30.0, wind_at + Vector2(wd.x, -wd.y) * 20.0, WIND, 3.0)
	_label(wind_at + Vector2(-30, 40), "wind", 12, WIND)

	# Timeline: one isochrone every 0.8 s, then the route, then a boat sailing it, then a pause.
	var n := _router.isochrones.size()
	var shown := mini(int(t / 0.8), n)
	var route_t := n * 0.8
	var sail_t := route_t + 1.5
	var loop := sail_t + 5.0
	if t > loop:
		t = 0.0
	for i in range(1, shown):
		var iso: Dictionary = _router.isochrones[i]
		var pts := PackedVector2Array()
		for j in iso["lat"].size():
			pts.append(to_px.call(iso["lat"][j], iso["lon"][j]))
		var newest := i == shown - 1 and t < route_t
		if pts.size() >= 2:
			draw_polyline(pts, Color(SOG, 0.9 if newest else 0.35), 2.0 if newest else 1.2, true)
		if newest:
			# Fan of headings from a few front points, to show how the next isochrone grows.
			for j in range(0, iso["lat"].size(), 8):
				var p: Vector2 = to_px.call(iso["lat"][j], iso["lon"][j])
				draw_circle(p, 2.0, SOG)
	if t >= route_t and _route.size() >= 2:
		var line := PackedVector2Array()
		for q in _route:
			line.append(to_px.call(q.x, q.y))
		draw_polyline(line, HEADING, 3.0, true)
		if t >= sail_t:
			var f := clampf((t - sail_t) / 4.0, 0.0, 1.0)
			var idx := f * (line.size() - 1)
			var a := int(floor(idx))
			var b := mini(a + 1, line.size() - 1)
			var pos := line[a].lerp(line[b], idx - a)
			var dv := line[b] - line[a]
			_boat(pos, rad_to_deg(atan2(dv.x, -dv.y)), 12.0, HEADING)
	draw_circle(to_px.call(0.0, 0.0), 5.0, TEXT)
	_label(to_px.call(0.0, 0.0) + Vector2(8, -6), "start", 12, TEXT)
	var hours := float(maxi(shown - 1, 0)) * _router.dt / 3600.0
	_label(Vector2(14, 26), "isochrone %d: %.1f h after the start" % [maxi(shown - 1, 0), hours], 16, SOG)
	if t >= route_t:
		_label(Vector2(14, 50), "fastest route: %.1f h" % (_router.finish_t / 3600.0), 16, HEADING)


func _stw(heading: float) -> float:
	return polar.speed(absf(Geo.wrap180(0.0 - heading)), TWS)


## Pixels per knot so the fastest point of the curve reaches the given radius.
func _scale(radius: float) -> float:
	var top := 1.0
	for h in range(0, 181, 5):
		top = maxf(top, _stw(h))
	return radius / top


func _curve(c: Vector2, k: float, from_deg: float, to_deg: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := from_deg
	while h <= to_deg:
		pts.append(c + _dir(h) * _stw(h) * k)
		h += 2.0
	if pts.size() < 2:
		pts.append(c)
	return pts


func _speed_rings(c: Vector2, k: float) -> void:
	for v in range(2, 11, 2):
		draw_arc(c, v * k, 0, TAU, 64, Color("#26343f"), 1.0)
		_label(c + Vector2(3, -v * k - 2), str(v), 10, MUTED)


func _wind_arrow(c: Vector2, r: float) -> void:
	_arrow(c + Vector2(0, -r - 22), c + Vector2(0, -r + 12), WIND, 3.0)


func _boat(c: Vector2, heading: float, sz: float, color: Color) -> void:
	var shape := [Vector2(0, -1), Vector2(0.38, 0.2), Vector2(0.3, 0.9), Vector2(-0.3, 0.9), Vector2(-0.38, 0.2), Vector2(0, -1)]
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(c + p.rotated(deg_to_rad(heading)) * sz)
	draw_colored_polygon(pts, BG)
	draw_polyline(pts, color, 2.0, true)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	if from.distance_to(to) < 3.0:
		return
	draw_line(from, to, color, width, true)
	var d := (to - from).normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to + d * 2.0, to - d * 11.0 + side * 5.5, to - d * 11.0 - side * 5.5]), color)


func _label(at: Vector2, text: String, size_px: int, color: Color, right := false) -> void:
	if right:
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(size_px)).x
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(size_px), color)


func _dir(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), -cos(r))


# ---------------------------------------------------------------- steering modes
# Each mode plays for STEER_S seconds, named on a copy of the steering bar. In HDG, TWA and close hauled
# the wind swings back and forth, so the difference between holding a heading and holding a wind angle
# shows; in route mode the wind holds steady and the boat sails the waypoints.

const STEER_S := 6.0
const STEER_MODES := ["ROUTE", "HDG", "TWA", "CLOSE HLD"]
const STEER_PX_S := 46.0  # boat speed in the drawing, pixels per second


func _steer_wind(mode: int, tl: float) -> float:
	return 0.0 if mode == 0 else 28.0 * sin(TAU * tl / STEER_S)


## Waypoints for route mode, in drawing pixels.
func _steer_route() -> PackedVector2Array:
	return PackedVector2Array([Vector2(90, size.y - 70), Vector2(170, size.y - 210), Vector2(330, size.y - 250), Vector2(380, 130)])


## Heading the mode steers at local time tl, from position p with route index i. Returns [heading, i].
func _steer_heading(mode: int, tl: float, p: Vector2, i: int, tack: float) -> float:
	var wf := _steer_wind(mode, tl)
	match mode:
		0:
			var wps := _steer_route()
			var v := wps[mini(i, wps.size() - 1)] - p
			return rad_to_deg(atan2(v.x, -v.y))
		1:
			return 40.0
		2:
			return wf + 75.0
		_:
			return wf + tack * SogPlot.beat_angle(polar, TWS)


func _steering() -> void:
	var mode := int(t / STEER_S) % STEER_MODES.size()
	var tl := fmod(t, STEER_S)
	# The steering bar, as in the game, with the amber underline on the mode playing.
	var x := 14.0
	for m in STEER_MODES.size():
		var w := font.get_string_size(STEER_MODES[m], HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(14)).x + 20.0
		var r := Rect2(x, 12, w, 30)
		draw_rect(r, Color("#0f3e48") if m == mode else Color(0.05, 0.13, 0.19), true)
		draw_rect(r, UiStyle.CYAN_BRIGHT if m == mode else UiStyle.CYAN_DIM, false, 1.0)
		_label(r.position + Vector2(10, 21), STEER_MODES[m], 14, Color.WHITE if m == mode else UiStyle.TEXT)
		if m == mode:
			draw_rect(Rect2(r.position.x + 5, r.end.y - 3, w - 10, 3), UiStyle.AMBER)
		x += w
	# Sail the mode from its start to now, in small steps.
	var starts := [Vector2(90, size.y - 70), Vector2(110, size.y - 70), Vector2(70, size.y * 0.62), Vector2(size.x * 0.4, size.y - 50)]
	var p: Vector2 = starts[mode]
	var i := 1
	var tack := 1.0
	var since_tack := 0.0
	var trail := PackedVector2Array([p])
	var h := 0.0
	var step := 0.05
	var s := 0.0
	while s < tl:
		h = _steer_heading(mode, s, p, i, tack)
		p += _dir(h) * STEER_PX_S * step
		since_tack += step
		if mode == 0 and i < _steer_route().size() and p.distance_to(_steer_route()[i]) < 6.0:
			i += 1
		if mode == 3 and since_tack > 1.9:
			tack = -tack  # the other tack pays: close hauled tacks by itself
			since_tack = 0.0
		s += step
		trail.append(p)
	h = _steer_heading(mode, tl, p, i, tack)
	draw_polyline(trail, Color(HEADING, 0.4), 1.5, true)
	var wf := _steer_wind(mode, tl)
	var wc := Vector2(size.x - 56, size.y - 80)
	draw_circle(wc, 34.0, Color(WIND, 0.08))
	_arrow(wc - _dir(wf + 180.0) * 26.0, wc + _dir(wf + 180.0) * 26.0, WIND, 3.0)
	_label(wc + Vector2(-16, 52), "wind", 13, WIND)
	match mode:
		0:
			var wps := _steer_route()
			draw_dashed_line(starts[0], wps[1], Color(1, 1, 1, 0.7), 1.5, 8.0)
			for k in range(1, wps.size()):
				if k > 1:
					draw_dashed_line(wps[k - 1], wps[k], Color(1, 1, 1, 0.7), 1.5, 8.0)
				draw_arc(wps[k], 7.0, 0, TAU, 20, Color.WHITE, 2.0)
				_label(wps[k] + Vector2(10, -8), str(k), 14, Color.WHITE)
			_label(Vector2(14, 72), "Steers to each waypoint in turn.", 15, TEXT)
		1:
			draw_line(p, p + _dir(h) * 90.0, Color(HEADING, 0.7), 1.5, true)
			_twa_arc(p, wf, h)
			_label(Vector2(14, 72), "Holds the heading.", 15, TEXT)
			_label(Vector2(14, 94), "The wind angle changes.", 15, TEXT)
		2:
			_twa_arc(p, wf, h)
			_label(Vector2(14, 72), "Holds the wind angle.", 15, TEXT)
			_label(Vector2(14, 94), "The heading turns with the wind.", 15, TEXT)
		3:
			var beat := SogPlot.beat_angle(polar, TWS)
			var wedge := PackedVector2Array([p])
			for k in 13:
				wedge.append(p + _dir(wf - beat + 2.0 * beat * k / 12.0) * 90.0)
			draw_colored_polygon(wedge, Color(NO_GO, 0.15))
			_label(Vector2(14, 72), "Sails the no-go edge.", 15, TEXT)
			_label(Vector2(14, 94), "Tacks by itself.", 15, TEXT)
	_boat(p, h, 14.0, HEADING)


## Arc from the wind direction to the heading: the true wind angle.
func _twa_arc(p: Vector2, wind_from: float, heading: float) -> void:
	draw_line(p, p + _dir(wind_from) * 60.0, Color(WIND, 0.6), 1.5, true)
	var a0 := deg_to_rad(wind_from - 90.0)
	var a1 := deg_to_rad(heading - 90.0)
	draw_arc(p, 40.0, minf(a0, a1), maxf(a0, a1), 24, SUGGEST, 2.0, true)
	_label(p + _dir((wind_from + heading) / 2.0) * 54.0 + Vector2(-12, 5), "TWA", 13, SUGGEST)
