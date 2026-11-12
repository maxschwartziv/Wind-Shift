class_name SogPlot
extends Control
## Boat instrument, north up: speed over ground for every heading at the boat's present position on a
## compass ring. Shades the no-go wedge where the polar gives no speed, draws a line to the next
## waypoint (or mark, or finish), marks the best-VMC heading and the present heading on the curve,
## and shows the wind.

const BG := Color(0.086, 0.125, 0.165, 0.88)
const RING := Color("#3a4a58")
const SPEED_RING := Color("#26343f")
const TEXT := Color("#e8eef2")
const MUTED := Color("#8fa1ae")
const HEADING := Color("#f5a442")
const SUGGEST := Color("#5fd3c6")
const WIND := Color("#9fc8ff")
const SOG := Color("#8be06a")
const NO_GO := Color("#f0603a")

## The player clicked a heading on the dial.
signal heading_picked(heading: float)
## The player dragged an edge of the no-go wedge (degrees either side of the wind), or reset it (0).
signal no_go_changed(degrees: float)

const EDGE_GRAB_DEG := 8.0  # how close to a wedge edge, in degrees, a press grabs it
const NO_GO_MIN := 15.0
const NO_GO_MAX := 90.0

var sim: RaceSim
var suggestion := {}
var font: Font
var _dial_c := Vector2.ZERO
var _dial_r := 0.0
var _dial_k := 0.0
var _hover := Vector2.INF  # mouse position over the dial, INF when away
var _wind_from := 0.0  # as last drawn
var _beat := 45.0  # no-go half-angle as last drawn
var _dragging_edge := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(340, 300)


func _draw() -> void:
	if sim == null:
		return
	var v := _view()
	if v.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var head: float = v.get("header_h", 0.0)
	var top_h := float(Settings.fs(40)) + head
	var bottom_h: float = float(Settings.fs(18)) * v["bottom"].size() + 6.0
	var c := Vector2(size.x / 2.0, top_h + (size.y - top_h - bottom_h) / 2.0)
	var radius := minf(size.x - 40.0, size.y - top_h - bottom_h - 24.0) / 2.0
	var sog: PackedFloat64Array = v["sog"]
	var top := 2.0
	for s in sog:
		top = maxf(top, s)
	top = ceilf(top / 2.0) * 2.0
	var k := radius / top
	_dial_c = c
	_dial_r = radius
	_dial_k = k

	for ring in range(2, int(top) + 1, 2):
		draw_arc(c, ring * k, 0, TAU, 64, SPEED_RING, 1.0)
		_label(c + Vector2(3, -ring * k - 2), str(ring), 10, MUTED)
	_wind_from = v["wind_from"]
	_beat = v["beat"]
	if not v["motoring"]:
		_draw_no_go(c, radius, v["wind_from"], v["beat"])
		if _can_pick() and (_dragging_edge or (_hover.is_finite() and _near_edge(_hover))):
			# Grabbable edges: drawn bold while the pointer is on one or dragging it.
			for side in [-1.0, 1.0]:
				draw_line(c, c + _dir(_wind_from + side * _beat) * radius, NO_GO, 3.0, true)
			_label(c + _dir(_wind_from) * radius * 0.35 + Vector2(-20, 4), "%d°" % roundi(_beat), 13, NO_GO)
	_draw_compass(c, radius)
	draw_polyline(_curve(c, sog, k), SOG, 2.5, true)

	var tgt: float = v["target"]
	draw_dashed_line(c, c + _dir(tgt) * radius, SUGGEST, 1.5, 6.0)
	_label(c + _dir(tgt) * radius + Vector2(8, 14), v["target_name"], 12, SUGGEST)
	var wf := _dir(v["wind_from"])
	_arrow(c + wf * (radius + 18), c + wf * (radius - 16), WIND, 3.0)

	var best: float = v["best"]
	if best >= 0.0:
		var bp := c + _dir(best) * sog[roundi(best) % 360] * k
		draw_dashed_line(bp, c + _dir(tgt) * float(v["best_vmc"]) * k, SUGGEST, 1.0, 3.0)
	var now := c + _dir(v["heading"]) * float(v["sog_kn"]) * k
	draw_line(c, now, HEADING, 3.0, true)
	_dot(now, HEADING, 5.0)
	if best >= 0.0:
		_dot(c + _dir(best) * sog[roundi(best) % 360] * k, SUGGEST, 6.0)

	if _can_pick() and _hover.is_finite() and not _dragging_edge and not _near_edge(_hover):
		var hh := fposmod(rad_to_deg(atan2(_hover.x - c.x, -(_hover.y - c.y))), 360.0)
		var hs: float = sog[roundi(hh) % 360]
		draw_dashed_line(c, c + _dir(hh) * radius, Color(TEXT, 0.7), 1.5, 4.0)
		_dot(c + _dir(hh) * hs * k, TEXT, 4.0)
		_label(c + _dir(hh) * (radius - 4.0) + Vector2(6, -6), "steer %03d°  SOG %.1f" % [roundi(hh) % 360, hs], 12, TEXT)

	var y1 := head + Settings.fs(16)
	var y2 := head + Settings.fs(36)
	_label(Vector2(10, y1), v["tl_cap"], 11, MUTED)
	_label(Vector2(10, y2), v["tl"], 15, HEADING)
	_label(Vector2(size.x - 10, y1), v["tr_cap"], 11, MUTED, true)
	_label(Vector2(size.x - 10, y2), v["tr"], 15, SUGGEST, true)
	var lines: Array = v["bottom"]
	for i in lines.size():
		var y := size.y - 8.0 - Settings.fs(18) * (lines.size() - 1 - i)
		_label(Vector2(10, y), lines[i][0], 13, lines[i][1])
		if lines[i].size() > 2:
			_label(Vector2(size.x - 10, y), lines[i][2], 13, lines[i][3], true)


## Click on the dial to steer that heading; moving over it previews the heading and its SOG.
func _gui_input(event: InputEvent) -> void:
	if not _can_pick() or _dial_r <= 0.0:
		_hover = Vector2.INF
		return
	if event is InputEventMouseMotion:
		_hover = event.position if event.position.distance_to(_dial_c) <= _dial_r * 1.1 and event.position.distance_to(_dial_c) > 6.0 else Vector2.INF
		if _dragging_edge:
			var a := absf(Geo.wrap180(_bearing_of(event.position) - _wind_from))
			no_go_changed.emit(clampf(a, NO_GO_MIN, NO_GO_MAX))
			accept_event()
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _hover.is_finite() and _near_edge(_hover) else Control.CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var d: Vector2 = event.position - _dial_c
		if not event.pressed:
			_dragging_edge = false
		elif d.length() <= _dial_r * 1.1 and d.length() > 6.0:
			if _near_edge(event.position):
				_dragging_edge = true
			else:
				heading_picked.emit(_bearing_of(event.position))
			accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click inside the wedge goes back to the polar's own best upwind angle.
		if event.position.distance_to(_dial_c) <= _dial_r and absf(Geo.wrap180(_bearing_of(event.position) - _wind_from)) < _beat:
			no_go_changed.emit(0.0)
			accept_event()


func _bearing_of(p: Vector2) -> float:
	var d := p - _dial_c
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


## True when a point on the dial lies on one of the no-go wedge's edges.
func _near_edge(p: Vector2) -> bool:
	if sim == null or sim.motoring:
		return false
	var dist := p.distance_to(_dial_c)
	if dist < _dial_r * 0.25 or dist > _dial_r * 1.1:
		return false
	var off := absf(Geo.wrap180(_bearing_of(p) - _wind_from))
	return absf(off - _beat) <= EDGE_GRAB_DEG


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2.INF


## True when the dial shows the boat now, so a click can steer it.
func _can_pick() -> bool:
	return sim != null and sim.state == "racing"


## What the dial shows, read from the boat's present state. The leg instrument overrides this.
func _view() -> Dictionary:
	var data := sim.sog_by_heading()
	var best: float = suggestion.get("heading", -1.0)
	var side := "stbd" if sim.twa >= 0 else "port"
	return {
		"sog": data["sog"],
		"heading": sim.heading,
		"sog_kn": sim.sog_kn(),
		"best": best,
		"best_vmc": suggestion.get("vmc_kn", 0.0),
		"target": Geo.bearing(Geo.offset_m(sim.pos, sim.target())),
		"target_name": _target_name(),
		"wind_from": sim.wind_from,
		"beat": sim.no_go_deg if sim.no_go_deg > 0.0 else beat_angle(sim.boat.polar, sim.tws),
		"motoring": sim.motoring,
		"tl_cap": "Now",
		"tl": "%03d°  SOG %.1f" % [roundi(sim.heading) % 360, sim.sog_kn()],
		"tr_cap": "Best VMC",
		"tr": "none" if best < 0.0 else "%03d°  %.1f kn" % [roundi(best) % 360, suggestion["vmc_kn"]],
		"bottom": [["TWS %.1f kn  TWA %d° %s" % [sim.tws, roundi(absf(sim.twa)), side], WIND,
				"STW %.1f" % sim.stw + ("  maneuver" if sim.penalty_left_s > 0 else ""), TEXT]],
	}


## Wedge either side of the wind inside the best upwind angle: the true wind angle (TWA) where the polar
## gives the most speed toward the wind. Sailing closer to the wind than this makes slower progress
## upwind, so boats tack instead. Not drawn when motoring.
func _draw_no_go(c: Vector2, radius: float, wind_from: float, half: float) -> void:
	var pts := PackedVector2Array([c])
	for i in 25:
		pts.append(c + _dir(wind_from - half + 2.0 * half * i / 24.0) * radius)
	draw_colored_polygon(pts, Color(NO_GO, 0.13))
	draw_dashed_line(c, pts[1], Color(NO_GO, 0.8), 1.0, 3.0)
	draw_dashed_line(c, pts[pts.size() - 1], Color(NO_GO, 0.8), 1.0, 3.0)
	_label(c + _dir(wind_from) * radius * 0.62 + Vector2(-14, 4), "no-go", 11, NO_GO)


## TWA (deg) with the highest speed toward the wind for a polar at a TWS (kn).
static func beat_angle(polar: Polar, tws: float) -> float:
	return polar.beat_angle(tws)


func _draw_compass(c: Vector2, radius: float) -> void:
	draw_arc(c, radius, 0, TAU, 96, RING, 1.5, true)
	for d in range(0, 360, 10):
		var inner := radius - (9.0 if d % 30 == 0 else 4.0)
		draw_line(c + _dir(d) * radius, c + _dir(d) * inner, RING, 1.0)
	var names := ["N", "E", "S", "W"]
	for i in 4:
		_label(c + _dir(i * 90) * (radius + 9) + Vector2(-4, 4), names[i], 12, MUTED)


func _target_name() -> String:
	if sim.waypoints.size() > 0:
		return "WP1"
	if sim.pkg.marks.size() > 0:
		return "Mark"
	return "Finish"


func _label(at: Vector2, text: String, size_px: int, color: Color, right := false) -> void:
	var align := HORIZONTAL_ALIGNMENT_LEFT
	if right:
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(size_px)).x
	draw_string(font, at, text, align, -1, Settings.fs(size_px), color)


func _dot(at: Vector2, color: Color, r: float) -> void:
	draw_circle(at, r + 1.5, BG)
	draw_circle(at, r, color)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)
	var d := (to - from).normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to + d * 2.0, to - d * 9.0 + side * 4.5, to - d * 9.0 - side * 4.5]), color)


func _dir(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), -cos(r))


func _curve(c: Vector2, vals: PackedFloat64Array, k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for h in 361:
		pts.append(c + _dir(h) * vals[h % 360] * k)
	return pts
