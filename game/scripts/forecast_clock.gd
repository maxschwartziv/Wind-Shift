class_name ForecastClock
extends Control
## The race clock and the wind map's time on one dial. The arc spans the leg's weather data with hour
## ticks; the bright part runs up to the wind map's time, marked by an amber tick, and a dot marks the
## race clock. The race clock reads in the middle, the wind map's time and source under it, then the
## clock keys. Dragging along the arc moves the wind map's time.

signal view_time_changed(t: float)
signal key(name: String)  # "slower", "pause", "faster", "now"

const ARC_FROM := PI + 0.36  # left end, radians from +x (screen y down)
const ARC_TO := TAU - 0.36

var t0 := 0.0  # race seconds at the left end of the arc
var t1 := 1.0  # and at the right end
var race_t := 0.0
var view_t := 0.0
var clock_text := "00:00"
var subtitle := ""
var speed_text := ""
var hour_fmt: Callable  # race seconds -> local hour label, "14"
var font: Font
var _speed: Label
var _dragging := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(480, 210)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.position = Vector2(0, 0)
	add_child(row)
	for k in [["<<", "slower", "Slower"], ["||", "pause", "Pause or run the race clock"], [">>", "faster", "Faster"]]:
		var b := Button.new()
		b.text = k[0]
		b.tooltip_text = k[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 30)
		var name: String = k[1]
		b.pressed.connect(func(): key.emit(name))
		row.add_child(b)
	_speed = Label.new()
	_speed.custom_minimum_size.x = 54
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.add_theme_color_override("font_color", UiStyle.CYAN_BRIGHT)
	row.add_child(_speed)
	var now := Button.new()
	now.text = "NOW"
	now.tooltip_text = "Back to the wind at the race clock"
	now.focus_mode = Control.FOCUS_NONE
	now.custom_minimum_size = Vector2(54, 30)
	now.pressed.connect(func(): key.emit("now"))
	row.add_child(now)
	_row = row


var _row: HBoxContainer


func _center() -> Vector2:
	return Vector2(size.x / 2.0, size.y * 0.98)


func _radius() -> float:
	return minf(size.x * 0.42, size.y * 0.8)


func _angle(t: float) -> float:
	var f := clampf((t - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	return lerpf(ARC_FROM, ARC_TO, f)


func _draw() -> void:
	_speed.text = speed_text
	_row.position = Vector2((size.x - _row.size.x) / 2.0, size.y - _row.size.y - 4.0)
	var c := _center()
	var r := _radius()
	draw_arc(c, r, ARC_FROM, ARC_TO, 96, UiStyle.TRACK, 7.0, true)
	draw_arc(c, r, ARC_FROM, _angle(view_t), 64, UiStyle.CYAN_BRIGHT, 7.0, true)
	# Hour ticks every 3 hours of local time, labeled under the arc.
	var h := ceilf(t0 / 3600.0) * 3600.0
	while h <= t1:
		var a := _angle(h)
		var dir := Vector2(cos(a), sin(a))
		var label: String = hour_fmt.call(h) if hour_fmt.is_valid() else ""
		var every3 := label != "" and int(label) % 3 == 0
		draw_line(c + dir * (r + 5.0), c + dir * (r + (12.0 if every3 else 8.0)), UiStyle.CYAN_DIM, 1.0)
		if every3:
			var p := c + dir * (r + 22.0)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(11)).x
			draw_string(font, p + Vector2(-w / 2.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(11), UiStyle.CYAN_DIM)
		h += 3600.0
	# Race clock: a dot on the arc. Wind map time: an amber tick.
	var ar := _angle(race_t)
	draw_circle(c + Vector2(cos(ar), sin(ar)) * r, 5.0, UiStyle.AMBER_TEXT)
	var av := _angle(view_t)
	var dv := Vector2(cos(av), sin(av))
	draw_line(c + dv * (r - 10.0), c + dv * (r + 14.0), UiStyle.AMBER, 3.0, true)
	# Middle text.
	var big := Settings.fs(36)
	var w1 := font.get_string_size(clock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	draw_string(font, Vector2((size.x - w1) / 2.0, size.y * 0.5), clock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, UiStyle.AMBER_TEXT)
	var small := Settings.fs(13)
	var w2 := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, Vector2((size.x - w2) / 2.0, size.y * 0.5 + small + 8.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiStyle.CYAN_BRIGHT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _on_arc(event.position)
		if _dragging:
			_scrub(event.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_scrub(event.position)
		accept_event()


func _on_arc(p: Vector2) -> bool:
	var d := p.distance_to(_center())
	var a := fposmod(atan2(p.y - _center().y, p.x - _center().x), TAU)
	return absf(d - _radius()) <= 22.0 and a >= ARC_FROM - 0.05 and a <= ARC_TO + 0.05


func _scrub(p: Vector2) -> void:
	var a := clampf(fposmod(atan2(p.y - _center().y, p.x - _center().x), TAU), ARC_FROM, ARC_TO)
	var t := lerpf(t0, t1, (a - ARC_FROM) / (ARC_TO - ARC_FROM))
	view_time_changed.emit(roundf(t / 600.0) * 600.0)
