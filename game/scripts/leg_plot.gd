class_name LegPlot
extends SogPlot
## Boat instrument with pages. Page 0 shows the boat now, which covers the leg it is sailing. Each later
## page shows one of the legs after it (waypoint to waypoint, then last waypoint to the finish) in the
## wind and current forecast at the leg's middle, at the time the boat gets there. Prev and Next step
## through the pages.

signal leg_changed(index: int)

var legs: Array = []  # RaceSim.leg_forecast
var index := 0  # page: 0 is the boat now; page n shows legs[n], the nth leg after the present one
var _prev: Button
var _next: Button


func _ready() -> void:
	super()
	_prev = _nav_button("< Prev", -1)
	_next = _nav_button("Next >", 1)


func _nav_button(text: String, step: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(6, 6)
	b.pressed.connect(func(): select(index + step))
	add_child(b)
	return b


func select(i: int) -> void:
	index = clampi(i, 0, _last_page())
	leg_changed.emit(index)
	queue_redraw()


func set_legs(new_legs: Array) -> void:
	legs = new_legs
	index = clampi(index, 0, _last_page())


func _last_page() -> int:
	return maxi(legs.size() - 1, 0)


func _draw() -> void:
	for b in [_prev, _next]:
		b.add_theme_font_size_override("font_size", Settings.fs(17))
		b.custom_minimum_size = Vector2(Settings.fs(86), Settings.fs(34))
	_next.position = Vector2(size.x - _next.size.x - 6.0, 6.0)
	var help := get_node_or_null("Help") as Control
	if help != null:
		help.add_theme_font_size_override("font_size", Settings.fs(17))
		help.custom_minimum_size = Vector2(Settings.fs(34), Settings.fs(34))
		help.position = Vector2(_next.position.x - help.size.x - 6.0, 6.0 + (_next.size.y - help.size.y) / 2.0)
	_prev.disabled = index <= 0
	_next.disabled = index >= _last_page()
	super()
	var title: String = "Now" if index == 0 else _leg_name(index)
	var sub := ""
	if index > 0 and index < legs.size():
		var wait := maxf(float(legs[index]["start_t"]) - sim.t, 0.0)
		sub = "starts in %s" % _duration(wait)
	var x0 := _prev.position.x + _prev.size.x + 8.0
	var x1 := (help.position.x if help != null else _next.position.x) - 8.0
	var mid := (x0 + x1) / 2.0
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(15)).x
	draw_string(font, Vector2(mid - w / 2.0, Settings.fs(20)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(15), TEXT)
	if sub != "":
		var w2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(11)).x
		draw_string(font, Vector2(mid - w2 / 2.0, Settings.fs(36)), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(11), MUTED)


func _view() -> Dictionary:
	if index == 0:
		var now := super()
		now["header_h"] = float(Settings.fs(44))
		return now
	if index >= legs.size() or not legs[index].has("cond"):
		return {}
	var leg: Dictionary = legs[index]
	var cond: Dictionary = leg["cond"]
	var sog := PackedFloat64Array()
	var best := 0.0
	var best_vmc := -INF
	for h in 360:
		var v := sim.ground_velocity(float(h), cond)
		sog.append(v.length() / Geo.MS_PER_KN)
		var vmc := v.dot(Geo.heading_vec(leg["bearing"])) / Geo.MS_PER_KN
		if vmc > best_vmc:
			best_vmc = vmc
			best = h
	var awa: float = leg["awa"]
	return {
		"header_h": float(Settings.fs(44)),
		"sog": sog,
		"heading": leg["heading"],
		"sog_kn": leg["sog_kn"],
		"best": best,
		"best_vmc": best_vmc,
		"target": leg["bearing"],
		"target_name": _leg_end(index),
		"wind_from": leg["twd"],
		"beat": sim.no_go_deg if sim.no_go_deg > 0.0 else beat_angle(sim.boat.polar, leg["tws_kn"]),
		"motoring": sim.motoring,
		"tl_cap": "Forecast heading",
		"tl": "%03d°  SOG %.1f" % [roundi(leg["heading"]) % 360, leg["sog_kn"]],
		"tr_cap": "%.1f nm  %s" % [leg["dist_nm"], _duration(leg["dur_s"])],
		"tr": "VMC %.1f kn" % leg["vmc_kn"],
		"bottom": [
			["TWD %03d°  TWS %.0f kn" % [roundi(leg["twd"]) % 360, leg["tws_kn"]], WIND, "STW %.1f" % leg["stw_kn"], TEXT],
			["AWA %d° %s  AWS %.0f kn" % [roundi(absf(awa)), "stbd" if awa > 0.0 else "port", leg["aws_kn"]], TEXT],
		],
	}


## Leg i, counted from 0, runs from the boat or waypoint i to waypoint i + 1 or the finish.
func _can_pick() -> bool:
	return index == 0 and super()


func _leg_start(i: int) -> String:
	return "Boat" if i == 0 else "WP%d" % i


func _leg_end(i: int) -> String:
	return "Finish" if i == legs.size() - 1 else "WP%d" % (i + 1)


func _leg_name(i: int) -> String:
	return "%s to %s" % [_leg_start(i), _leg_end(i)]


func _duration(s: float) -> String:
	var m := roundi(s / 60.0)
	return "%d h %02d min" % [m / 60, m % 60]
