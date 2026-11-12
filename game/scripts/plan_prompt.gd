class_name PlanPrompt
extends PanelContainer
## Shown while a new race waits paused at the start: pick a start time, plot waypoints to the finish
## through the forecast wind, then start the clock. The animation loops: the start time is picked on a
## dial, waypoints go down around a patch of light wind, and the boat sails the route.
## "Got it" turns to a second page: the forecast is only a forecast. Its animation shows a boat sailing
## the forecast breeze into a patch of light air the forecast missed; the boat's measured wind circle
## shows the real wind as it goes, and the boat slows.

signal dismissed

const LOOP_S := 9.0
const MAP := Vector2(480, 270)

const WARN_LOOP_S := 10.0
const REVEAL_PX := 46.0  # the boat's measured wind circle, in animation pixels

var font: Font
var _anim: Control
var _t := 0.0
var _page := 0  # 0: plan your race, 1: forecast warning
var _title: Label
var _lines: Array[Label] = []
var _boat_x := 0.0  # warning page: the boat's distance along its route, 0 to 1
var _seen: Array[Vector2] = []  # warning page: boat positions so far, in animation pixels


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	_title = title
	title.text = "Plan your race"
	title.add_theme_color_override("font_color", UiStyle.AMBER_TEXT)
	title.add_theme_font_size_override("font_size", Settings.fs(24))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = MAP.x
	box.add_child(title)
	_anim = Control.new()
	_anim.custom_minimum_size = MAP
	_anim.clip_contents = true
	_anim.draw.connect(_draw_anim)
	box.add_child(_anim)
	for line in [
		"1. Pick a start time in the RACE panel.",
		"2. Click the map to place waypoints to reach the finish line. Avoid forecasted low wind areas. Plan for wind shifts.",
		"3. Press Space to start the race.",
	]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", Settings.fs(16))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = MAP.x
		box.add_child(l)
		_lines.append(l)
	var ok := Button.new()
	ok.text = "Got it"
	ok.focus_mode = Control.FOCUS_NONE
	ok.add_theme_font_size_override("font_size", Settings.fs(16))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func():
		if _page == 0:
			_show_warning()
		else:
			visible = false
			dismissed.emit())
	box.add_child(ok)


func _show_warning() -> void:
	_page = 1
	_t = 0.0
	_title.text = "Warning! This is only the wind forecast."
	_lines[0].text = "Predictions are never 100%. The real wind can be lighter, stronger or from another direction."
	_lines[1].text = "Your boat measures the real wind around it as it sails. Watch for patches the forecast missed and change course."
	_lines[2].visible = false
	_restart_warning()


func _restart_warning() -> void:
	_boat_x = 0.0
	_seen.clear()


func _process(delta: float) -> void:
	if not visible:
		return
	if _page == 0:
		_t = fmod(_t + delta, LOOP_S)
	else:
		_t += delta
		if _t >= WARN_LOOP_S:
			_t = 0.0
			_restart_warning()
		elif _t > 0.6:
			# The boat's speed follows the real wind where it is.
			var p := _warn_route(_boat_x)
			_boat_x = minf(_boat_x + delta * 0.022 * _real_wind(p / MAP), 1.0)
			_seen.append(p)
	_anim.queue_redraw()


## Made-up wind speed in knots: a steady breeze with a pocket of light air in the middle of the course.
func _wind(p: Vector2) -> float:
	var pocket := p.distance_to(Vector2(0.5, 0.55))
	return 6.0 + 9.0 * smoothstep(0.08, 0.32, pocket) + 2.0 * p.y


func _px(p: Vector2) -> Vector2:
	return p * MAP


func _draw_anim() -> void:
	if _page == 1:
		_draw_warning()
		return
	var a := _anim
	# Wind colors.
	var cell := 15.0
	for x in range(0, int(MAP.x), int(cell)):
		for y in range(0, int(MAP.y), int(cell)):
			var c := WindPalette.color(_wind(Vector2(x + cell / 2.0, y + cell / 2.0) / MAP))
			c.a = 0.55
			a.draw_rect(Rect2(x, y, cell, cell), c)
	a.draw_rect(Rect2(Vector2.ZERO, MAP), UiStyle.CYAN_DIM, false, 1.0)
	# Start (lower left) and finish (upper right) lines.
	var start := Vector2(0.1, 0.8)
	var finish := Vector2(0.9, 0.22)
	a.draw_line(_px(start + Vector2(-0.04, -0.05)), _px(start + Vector2(0.04, 0.05)), Color.WHITE, 2.0)
	a.draw_line(_px(finish + Vector2(-0.04, -0.05)), _px(finish + Vector2(0.04, 0.05)), Color(1, 0.9, 0.2), 2.0)
	a.draw_string(font, _px(finish) + Vector2(-58, -14), "Finish", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.2))
	a.draw_string(font, _px(start) + Vector2(-20, 26), "Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# The straight line runs through the light air; the planned route goes around it.
	a.draw_dashed_line(_px(start), _px(finish), Color(1, 1, 1, 0.25), 1.0, 6.0)
	var route: Array[Vector2] = [start, Vector2(0.3, 0.88), Vector2(0.78, 0.78), finish]

	_draw_start_pick()

	# Phase 2, 2 to 5 s: waypoints go down one by one and the route joins them.
	var placed := clampi(floori((_t - 2.0) / 0.9) + 1, 0, route.size() - 1)
	for i in range(1, placed + 1):
		a.draw_dashed_line(_px(route[i - 1]), _px(route[i]), Color.WHITE, 1.5, 8.0)
		if i < route.size() - 1:
			a.draw_arc(_px(route[i]), 6.0, 0, TAU, 16, Color.WHITE, 2.0)
			a.draw_string(font, _px(route[i]) + Vector2(8, -6), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	if _t >= 2.0 and _t < 5.0 and placed < route.size() - 1:
		# Pointer heading for the next waypoint.
		var f := fmod(_t - 2.0, 0.9) / 0.9
		var from := _px(route[placed])
		var p := from.lerp(_px(route[placed + 1]), smoothstep(0.0, 0.7, f))
		_pointer(p, f > 0.75)

	# Phase 3, 5.5 to 8.5 s: the boat sails the route.
	var boat_f := smoothstep(5.5, 8.5, _t)
	var pos := _along(route, boat_f) if _t >= 5.5 else route[0]
	var ahead := _along(route, minf(boat_f + 0.02, 1.0))
	var dir := (_px(ahead) - _px(pos)).normalized() if ahead != pos else Vector2(1, -0.3).normalized()
	var bp := _px(pos)
	var side := Vector2(-dir.y, dir.x)
	a.draw_colored_polygon(PackedVector2Array([bp + dir * 8.0, bp - dir * 5.0 + side * 4.0, bp - dir * 5.0 - side * 4.0]), HelpAnim.HEADING)


## Phase 1, 0 to 2 s: the start time button from the RACE panel. The pointer opens its list, picks a
## later start, and the list closes with the new time on the button.
func _draw_start_pick() -> void:
	var a := _anim
	var times := ["Start 14:35 (gun)", "Start 15:05", "Start 15:35", "Start 16:05"]
	var chosen := 2
	var r := Rect2(12, 12, 170, 30)
	var open := _t >= 0.6 and _t < 1.6
	var label: String = times[chosen] if _t >= 1.6 else times[0]
	a.draw_style_box(UiStyle.box(Color(0.05, 0.13, 0.19, 0.97), UiStyle.CYAN_BRIGHT if open else UiStyle.CYAN_DIM, 1, 6), r)
	a.draw_string(font, r.position + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEXT)
	var v := r.position + Vector2(r.size.x - 16, 13)
	a.draw_polyline(PackedVector2Array([v, v + Vector2(4, 4), v + Vector2(8, 0)]), UiStyle.TEXT, 1.5)
	var row_h := 22.0
	if open:
		var list := Rect2(r.position + Vector2(0, r.size.y + 2), Vector2(r.size.x, row_h * times.size() + 6))
		a.draw_style_box(UiStyle.box(UiStyle.NAVY, UiStyle.CYAN, 1, 6), list)
		var hover := 0 if _t < 1.0 else chosen
		for i in times.size():
			var row := Rect2(list.position + Vector2(3, 3 + row_h * i), Vector2(list.size.x - 6, row_h))
			if i == hover:
				a.draw_rect(row, Color("#0f3e48"))
			a.draw_string(font, row.position + Vector2(8, 16), times[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE if i == hover else UiStyle.TEXT)
	# Pointer: to the button, click, down to the chosen time, click.
	if _t < 2.0:
		var at_button := r.position + Vector2(120, 18)
		var at_row := r.position + Vector2(90, r.size.y + 2 + 3 + row_h * chosen + 14)
		var p := at_button
		if _t < 0.5:
			p = Vector2(120, 110).lerp(at_button, smoothstep(0.0, 0.5, _t))
		elif _t >= 1.0:
			p = at_button.lerp(at_row, smoothstep(1.0, 1.4, _t))
		_pointer(p, (_t >= 0.5 and _t < 0.65) or (_t >= 1.45 and _t < 1.6))


func _pointer(p: Vector2, clicked: bool) -> void:
	var pts := PackedVector2Array([p, p + Vector2(0, 14), p + Vector2(4, 10), p + Vector2(9, 12)])
	_anim.draw_colored_polygon(pts, Color.WHITE)
	if clicked:
		_anim.draw_arc(p, 9.0, 0, TAU, 16, Color(1, 1, 1, 0.7), 1.5)


## Point a fraction f of the way along a polyline, by length.
func _along(pts: Array[Vector2], f: float) -> Vector2:
	var total := 0.0
	for i in range(1, pts.size()):
		total += _px(pts[i]).distance_to(_px(pts[i - 1]))
	var want := total * f
	for i in range(1, pts.size()):
		var seg := _px(pts[i]).distance_to(_px(pts[i - 1]))
		if want <= seg:
			return pts[i - 1].lerp(pts[i], want / maxf(seg, 0.001))
		want -= seg
	return pts[pts.size() - 1]


# ---------------------------------------------------------------- forecast warning page

## Forecast: a steady breeze everywhere.
func _forecast_wind(p: Vector2) -> float:
	return 14.0 + 1.0 * sin(p.x * 5.0) * cos(p.y * 4.0)  # stays in the 12 to 16 kn color


## Real wind: the same breeze with a patch of light air on the route that the forecast does not show.
func _real_wind(p: Vector2) -> float:
	var hole := p.distance_to(Vector2(0.56, 0.5))
	return lerpf(2.5, _forecast_wind(p), smoothstep(0.06, 0.2, hole))


## The planned route, a straight line across the middle, f from 0 to 1. Returns animation pixels.
func _warn_route(f: float) -> Vector2:
	return _px(Vector2(0.08, 0.56).lerp(Vector2(0.92, 0.44), f))


func _draw_warning() -> void:
	var a := _anim
	var cell := 15.0
	for x in range(0, int(MAP.x), int(cell)):
		for y in range(0, int(MAP.y), int(cell)):
			var mid := Vector2(x + cell / 2.0, y + cell / 2.0)
			# Inside any circle the boat has sailed through, the map shows the wind it measured.
			var measured := false
			for i in range(0, _seen.size(), 4):
				if _seen[i].distance_to(mid) < REVEAL_PX:
					measured = true
					break
			var kn := _real_wind(mid / MAP) if measured else _forecast_wind(mid / MAP)
			var c := WindPalette.color(kn)
			c.a = 0.6
			a.draw_rect(Rect2(x, y, cell, cell), c)
	a.draw_rect(Rect2(Vector2.ZERO, MAP), UiStyle.CYAN_DIM, false, 1.0)
	a.draw_dashed_line(_warn_route(0.0), _warn_route(1.0), Color.WHITE, 1.5, 8.0)
	a.draw_line(_warn_route(1.0) + Vector2(-6, -9), _warn_route(1.0) + Vector2(6, 9), Color(1, 0.9, 0.2), 2.5)
	a.draw_string(font, _warn_route(1.0) + Vector2(-60, -16), "Finish", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.2))
	a.draw_string(font, Vector2(10, 22), "forecast", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEXT)
	# Trail: one dot per half second of travel, so the dots bunch up where the boat slows.
	for i in range(0, _seen.size(), 30):
		a.draw_circle(_seen[i], 2.0, Color(1, 1, 1, 0.8))
	var bp := _warn_route(_boat_x)
	a.draw_arc(bp, REVEAL_PX, 0, TAU, 40, Color(1, 1, 1, 0.55), 1.5)
	a.draw_string(font, bp + Vector2(-44, -REVEAL_PX - 6), "measured wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	var dir := (_warn_route(1.0) - _warn_route(0.0)).normalized()
	var side := Vector2(-dir.y, dir.x)
	a.draw_colored_polygon(PackedVector2Array([bp + dir * 9.0, bp - dir * 6.0 + side * 5.0, bp - dir * 6.0 - side * 5.0]), HelpAnim.HEADING)
	if _real_wind(bp / MAP) < 6.0:
		a.draw_string(font, bp + Vector2(-46, REVEAL_PX + 18), "not in the forecast", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.AMBER_TEXT)
