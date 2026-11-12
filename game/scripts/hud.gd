class_name Hud
extends CanvasLayer
## Controls, readouts, wind map time, legend, boat instrument and the results panel.

signal action(name: String, value: Variant)

const SPEEDS := [0, 10, 60, 300, 900, 3600]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var sim: RaceSim
var pkg: LegPackage
var plot: SogPlot
var leg_plot: LegPlot
var help: HelpPanel
var _top: HFlowContainer
var _wind_row: HBoxContainer
var _stats_panel: PanelContainer
var settings: SettingsMenu
var hover_card: HoverCard
var _help_line: Label
var _bottom: VBoxContainer
var _legend: PanelContainer
var start_pick: OptionButton
var _results_scroll: ScrollContainer
var _credits: Label
var _legend_labels: Array[Label] = []
var use_utc := false
var ideals: Array[Ghost] = []
var ideal_progress := 1.0  # share of the ideal boats' runs computed
var used_actual := false  # actual wind viewed during the race: the result counts as perfect forecast
var _stats: Label
var _clock: Label
var _speed: Label
var _alarm: Label
var _mode_btn: Button
var _boat_pick: OptionButton
var _source_pick: OptionButton
var _time_slider: HSlider
var _time_label: Label
var _motor: CheckBox
var _results: PanelContainer
var _results_text: Label


func setup(p: LegPackage, profiles: Array[BoatProfile], boat_index: int, max_view_t: float) -> void:
	pkg = p
	var top := HFlowContainer.new()
	_top = top
	top.position = Vector2(10, 8)
	top.size = Vector2(1580, 0)
	top.anchor_right = 1.0
	top.offset_right = -10
	top.add_theme_constant_override("h_separation", 8)
	add_child(top)

	_boat_pick = OptionButton.new()
	for b in profiles:
		_boat_pick.add_item(b.name)
	_boat_pick.select(boat_index)
	_boat_pick.item_selected.connect(func(i): action.emit("boat", i))
	top.add_child(_button("Menu", func(): action.emit("menu", null)))
	top.add_child(_boat_pick)
	var leg_pick := OptionButton.new()
	leg_pick.focus_mode = Control.FOCUS_NONE
	var legs := LegPackage.list(Settings.leg_id)
	for i in legs.size():
		leg_pick.add_item(legs[i][1])
		if legs[i][0] == Settings.leg_id:
			leg_pick.select(i)
	leg_pick.item_selected.connect(func(i): action.emit("leg", legs[i][0]))
	top.add_child(leg_pick)
	top.add_child(_button("Settings", func(): settings.open()))
	start_pick = _start_picker()
	top.add_child(start_pick)
	top.add_child(_button("Pause", func(): action.emit("pause", null)))
	top.add_child(_button("Slower", func(): action.emit("speed", -1)))
	_speed = Label.new()
	top.add_child(_speed)
	top.add_child(_button("Faster", func(): action.emit("speed", 1)))
	_mode_btn = _button("Heading mode", func(): action.emit("mode", null))
	_mode_btn.custom_minimum_size.x = 150
	top.add_child(_mode_btn)
	top.add_child(_button("Clear route", func(): action.emit("clear_route", null)))
	var export := MenuButton.new()
	export.text = "Export route"
	export.flat = false
	export.focus_mode = Control.FOCUS_NONE
	export.get_popup().add_item("GPX (Navionics, Garmin, Raymarine, B&G, OpenCPN)", 0)
	export.get_popup().add_item("KML (Google Earth)", 1)
	export.get_popup().id_pressed.connect(_export_route)
	top.add_child(export)
	var grib := MenuButton.new()
	grib.text = "Import GRIB"
	grib.flat = false
	grib.focus_mode = Control.FOCUS_NONE
	grib.get_popup().add_item("Wind, as the forecast", 0)
	grib.get_popup().add_item("Wind, as the actual weather", 1)
	grib.get_popup().add_item("Current", 2)
	grib.get_popup().id_pressed.connect(func(id: int):
		var kind: String = ["wind_forecast", "wind_actual", "current"][id]
		WeatherImport.pick_file(self, func(file_name: String, bytes: PackedByteArray):
			action.emit("import", [kind, file_name, bytes])))
	top.add_child(grib)
	_motor = CheckBox.new()
	_motor.text = "Motoring"
	_motor.toggled.connect(func(on): action.emit("motoring", on))
	top.add_child(_motor)
	var layers := {"Depth map": "depth", "Wind colors": "field", "Wind particles": "particles", "Wind arrows": "wind", "Current": "current",
			"Trails": "trails", "Labels": "labels", "Test tracks": "tests"}
	for name in layers:
		var cb := CheckBox.new()
		cb.text = name
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = name in ["Wind colors", "Wind particles", "Trails"]
		cb.toggled.connect(func(on): action.emit("layer_" + layers[name], on))
		top.add_child(cb)
	var utc := CheckBox.new()
	utc.text = "UTC"
	utc.focus_mode = Control.FOCUS_NONE
	utc.toggled.connect(func(on): use_utc = on)
	top.add_child(utc)

	var wind_row := HBoxContainer.new()
	_wind_row = wind_row
	wind_row.position = Vector2(10, 82)
	wind_row.add_theme_constant_override("separation", 8)
	add_child(wind_row)
	var wl := Label.new()
	wl.text = "Wind map"
	wind_row.add_child(wl)
	_source_pick = OptionButton.new()
	_source_pick.add_item("Forecast as issued")
	_source_pick.add_item("Actual wind")
	_source_pick.focus_mode = Control.FOCUS_NONE
	_source_pick.item_selected.connect(func(i): action.emit("view_source", i == 1))
	wind_row.add_child(_source_pick)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = max_view_t
	_time_slider.step = 600.0
	_time_slider.custom_minimum_size = Vector2(520, 24)
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.value_changed.connect(func(v): action.emit("view_time", v))
	wind_row.add_child(_time_slider)
	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 360
	wind_row.add_child(_time_label)
	wind_row.add_child(_button("Now", func(): action.emit("view_now", null)))

	var panel := PanelContainer.new()
	_stats_panel = panel
	panel.position = Vector2(10, 118)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", Settings.fs(18))
	box.add_child(_clock)
	_stats = Label.new()
	box.add_child(_stats)
	# The stats panel is hidden; its readouts are on the instrument and the map. Two notices that still
	# matter (depth alarm, ideal boats computing) show on their own, only when they apply.
	panel.visible = false
	_alarm = Label.new()
	_alarm.add_theme_color_override("font_color", Color(1, 0.35, 0.25))
	_alarm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_alarm.add_theme_constant_override("outline_size", 4)
	_alarm.add_theme_font_size_override("font_size", Settings.fs(16))
	add_child(_alarm)

	_build_legend()

	leg_plot = LegPlot.new()
	plot = leg_plot
	plot.anchor_left = 1.0
	plot.anchor_top = 1.0
	plot.anchor_right = 1.0
	plot.anchor_bottom = 1.0
	plot.offset_left = -370
	plot.offset_top = -400
	plot.offset_right = -10
	plot.offset_bottom = -60
	add_child(plot)

	# Help line and credits stack up from the bottom edge and wrap, so larger text pushes them upward.
	var bottom := VBoxContainer.new()
	_bottom = bottom
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 10
	bottom.offset_right = -10
	bottom.offset_bottom = -4
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 2)
	add_child(bottom)
	bottom.add_child(_legend)
	var help_line := Label.new()
	_help_line = help_line
	help_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_line.add_theme_font_size_override("font_size", Settings.fs(12))
	bottom.add_child(help_line)
	var credits := Label.new()
	credits.text = " | ".join(pkg.credits())
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credits = credits
	credits.add_theme_font_size_override("font_size", Settings.fs(10))
	credits.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	bottom.add_child(credits)

	_results = PanelContainer.new()
	_results.anchor_left = 0.5
	_results.anchor_top = 0.5
	_results.anchor_right = 0.5
	_results.anchor_bottom = 0.5
	# Centered and sized to its content; the ranking scrolls so the buttons stay on screen.
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results.grow_vertical = Control.GROW_DIRECTION_BOTH
	_results.visible = false
	add_child(_results)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 10)
	_results.add_child(rbox)
	_results_scroll = ScrollContainer.new()
	_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rbox.add_child(_results_scroll)
	_results_text = Label.new()
	_results_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_results_text.custom_minimum_size.x = 620
	_results_scroll.add_child(_results_text)
	var rbtns := HBoxContainer.new()
	rbox.add_child(rbtns)
	rbtns.add_child(_button("Restart leg", func(): action.emit("restart", false)))
	rbtns.add_child(_button("Restart from last save", func(): action.emit("restart", true)))
	rbtns.add_child(_button("Close", func(): _results.visible = false))

	var ask := Button.new()
	ask.name = "Help"
	ask.text = " ? "
	ask.tooltip_text = "Polars, terms and this instrument"
	ask.focus_mode = Control.FOCUS_NONE
	plot.add_child(ask)
	help = HelpPanel.new()
	add_child(help)
	ask.pressed.connect(func(): help.open(sim.boat))
	hover_card = HoverCard.new()
	add_child(hover_card)
	settings = SettingsMenu.new()
	add_child(settings)
	settings.open_help = func(): help.open(sim.boat)
	_arrange_console()
	_dress_buttons()
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()


func _build_legend() -> void:
	var legend := PanelContainer.new()
	legend.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_legend = legend
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	legend.add_child(row)
	var title := Label.new()
	title.text = "Wind (kn)"
	row.add_child(title)
	for i in WindPalette.COLORS.size():
		var sw := ColorRect.new()
		sw.color = WindPalette.COLORS[i]
		sw.custom_minimum_size = Vector2(22, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var l := Label.new()
		l.text = WindPalette.label(i)
		l.add_theme_font_size_override("font_size", Settings.fs(12))
		_legend_labels.append(l)
		row.add_child(l)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func bind(s: RaceSim) -> void:
	sim = s
	plot.sim = s
	_motor.disabled = not s.motoring_allowed()
	_motor.button_pressed = false
	_results.visible = false
	used_actual = _source_pick.selected == 1


func clock_text(t: float) -> String:
	var unix := pkg.start_unix() + t
	var label := "UTC"
	if not use_utc:
		unix += pkg.utc_offset_s()
		label = "local (UTC%+d)" % (pkg.utc_offset_s() / 3600)
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%d %s %d  %02d:%02d %s" % [d["day"], MONTHS[d["month"] - 1], d["year"], d["hour"], d["minute"], label]


func refresh(speed_index: int, suggestion: Dictionary, view_t: float, show_actual: bool) -> void:
	if show_actual and sim.state == "racing":
		used_actual = true
	_speed.text = "Paused" if SPEEDS[speed_index] == 0 else "%dx" % SPEEDS[speed_index]
	match sim.mode:
		RaceSim.Mode.TWA_LOCK:
			_mode_btn.text = "TWA lock %+d" % roundi(sim.twa_lock)
		RaceSim.Mode.CLOSE_HAULED:
			_mode_btn.text = "Close hauled %s" % ("stbd" if sim.close_side > 0.0 else "port")
		RaceSim.Mode.ROUTE:
			_mode_btn.text = "Route: %d waypoints" % sim.waypoints.size()
		_:
			_mode_btn.text = "Heading mode"
	var el := sim.t - sim.start_t
	_clock.text = "%s   elapsed %d:%02d" % [clock_text(sim.t), int(el / 3600), int(fmod(el, 3600) / 60)]
	# Heading, suggested heading, wind, STW and SOG are on the instrument.
	_stats.text = "\n".join([
		"COG         %03d deg" % (roundi(sim.cog()) % 360),
		"VMC now     %.1f kn" % sim.vmc_kn(),
		"Current     %.1f kn" % (sim.current.length() / Geo.MS_PER_KN),
		"Depth       %.0f m (draft %.1f m)" % [sim.depth, sim.boat.draft_m],
		("To waypoint %.1f nm" if sim.waypoints.size() > 0 else "To finish   %.1f nm") % sim.distance_to_finish_nm(),
	])
	if ideal_progress < 1.0:
		_stats.text += "\nIdeal boats computing %d%%" % roundi(ideal_progress * 100.0)
	var notices := PackedStringArray()
	if sim.depth - sim.boat.draft_m < 5.0:
		notices.append("Depth alarm: %.1f m under the keel" % (sim.depth - sim.boat.draft_m))
	if ideal_progress < 1.0:
		notices.append("Ideal boats computing %d%%" % roundi(ideal_progress * 100.0))
	_alarm.text = "\n".join(notices)
	_time_slider.set_value_no_signal(view_t)
	var source := "actual wind"
	if not show_actual:
		var fc := pkg.forecast_at(sim.t)
		if fc.has("label"):
			source = fc["label"]
		else:
			var run := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_string(fc["run_utc"])))
			source = "GFS run %d %s %02dZ" % [run["day"], MONTHS[run["month"] - 1], run["hour"]]
	var ahead := view_t - sim.t
	var rel := "now" if absf(ahead) < 300.0 else ("%+.1f h" % (ahead / 3600.0))
	_time_label.text = "%s (%s), %s" % [clock_text(view_t), rel, source]
	plot.suggestion = suggestion
	_place_instruments()
	_refresh_console(view_t, source, rel)
	plot.queue_redraw()


func show_results() -> void:
	var lines := PackedStringArray()
	if sim.state == "finished":
		lines.append("Finished. Elapsed %s." % _hms(sim.elapsed_s))
		if sim.motoring_s > 0:
			lines.append("Motoring %s, corrected %s." % [_hms(sim.motoring_s), _hms(sim.corrected_s())])
	else:
		lines.append("Did not finish." + ("" if sim.end_reason == "" else " %s." % sim.end_reason))
	lines.append("Forecast mode: %s." % ("perfect (actual wind viewed)" if used_actual else "period forecast"))
	lines.append("")
	var rows := []
	for g in pkg.ghosts:
		rows.append([g.finish_elapsed_s, g.name + _model_note(g.model) + (" *" if g.start_estimated else "")])
	if ideal_progress < 1.0:
		lines.append("Ideal boats still computing; they are left out of this ranking.")
	for g in ideals:
		if g.finished and ideal_progress >= 1.0:
			rows.append([g.finish_elapsed_s, "~ " + g.name + _model_note(g.model)])
	if sim.state == "finished":
		rows.append([sim.elapsed_s, ">> You: " + sim.boat.name])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	lines.append("Ranked by elapsed time from each boat's start-line crossing to its finish-line crossing:")
	for i in rows.size():
		if rows.size() <= 18 or i < 10 or rows[i][1].begins_with(">>") or i >= rows.size() - 3:
			lines.append("%2d. %s  %s" % [i + 1, _hms(rows[i][0]), rows[i][1]])
		elif i == 10:
			lines.append("    ...")
	lines.append("")
	lines.append("* Start time estimated: no AIS fixes at the start line.")
	lines.append("~ Ideal boat: your polar, best VMC to the finish, in the period forecast or the actual wind.")
	_results_text.text = "\n".join(lines)
	_results.visible = true
	_place_results.call_deferred()


## The ranking scrolls once it is taller than the window allows; the panel sits in the middle.
func _place_results() -> void:
	var vp := get_viewport().get_visible_rect().size
	_results_scroll.custom_minimum_size = Vector2(_results_text.custom_minimum_size.x + 16.0,
			minf(_results_text.get_minimum_size().y, vp.y - 160.0))
	_results.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_results.reset_size()
	_results.position = ((vp - _results.size) / 2.0).max(Vector2(10, 10))


func _hms(s: float) -> String:
	return "%d:%02d:%02d" % [int(s / 3600), int(fmod(s, 3600) / 60), int(fmod(s, 60))]


## Rescale the fixed font sizes and list the present key bindings in the help line.
func _on_settings_changed() -> void:
	_clock.add_theme_font_size_override("font_size", Settings.fs(18))
	_help_line.add_theme_font_size_override("font_size", Settings.fs(12))
	_credits.add_theme_font_size_override("font_size", Settings.fs(10))
	for l in _legend_labels:
		l.add_theme_font_size_override("font_size", Settings.fs(12))
	var add := "Right-click" if Settings.swap_mouse else "Click"
	var remove := "Click" if Settings.swap_mouse else "Right-click"
	var k := func(a): return Settings.key_name(a)
	_help_line.text = "%s map: add waypoint   %s: remove waypoint   %s: steering mode   %s/%s: heading   %s: pause   %s/%s: time   %s %s: wind map hour   %s: follow boat   %s: settings   Wheel, drag or middle button: map" % [
		add, remove, k.call("cycle_mode"), k.call("steer_left"), k.call("steer_right"), k.call("pause"),
		k.call("speed_up"), k.call("slow_down"), k.call("view_back"), k.call("view_forward"), k.call("follow_boat"),
		k.call("open_settings")]


## Bottom-right instruments sit above the legend, help line and credits and grow with the text size.
func _place_instruments() -> void:
	var lift := (_bottom.size.y if _bottom.visible else 0.0) + 10.0
	var k := clampf(Settings.text_scale, 1.0, 1.3) if Settings.attract else clampf(Settings.text_scale, 1.0, 1.5)
	# The steering keys sit under the polar, at its width.
	if _steer_pod != null and _steer_pod.visible:
		var pod_w := 380.0 * k
		_steer_row.custom_minimum_size.x = pod_w - 20.0  # the pod's side margins
		_steer_pod.size = Vector2(pod_w, 0)
		var vp := get_viewport().get_visible_rect().size
		_steer_pod.position = Vector2(vp.x - 10.0 - pod_w, vp.y - lift - _steer_pod.size.y)
		lift += _steer_pod.size.y + 8.0
	# Shrink the instrument on short windows so its top stays on screen.
	var kh := minf(k, (get_viewport().get_visible_rect().size.y - lift - 10.0) / 390.0)
	plot.offset_bottom = -lift
	plot.offset_top = -lift - 390.0 * kh
	plot.offset_left = -10.0 - 380.0 * k


func _export_route(id: int) -> void:
	var pts := RouteExport.route_points(sim)
	var name := "%s route" % pkg.info.get("leg", "Sailing")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").left(13)
	if id == 0:
		RouteExport.save(self, "route_%s.gpx" % stamp, RouteExport.to_gpx(name, pts), "application/gpx+xml")
	else:
		RouteExport.save(self, "route_%s.kml" % stamp, RouteExport.to_kml(name, pts), "application/vnd.google-earth.kml+xml")


## A short message in a dialog, such as the result of a GRIB import.
func show_message(title: String, text: String) -> void:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(520, 0)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


## Start time picker: the player's own start, 2 h before to 8 h after the first gun in 30 min steps,
## kept inside the leg's weather data with at least 6 h of it left.
func _start_picker() -> OptionButton:
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.tooltip_text = "Your start time. Changing it restarts the race; the ideal boats start with you."
	var last_wind: float = pkg.wind.times[pkg.wind.times.size() - 1]
	var first_wind: float = pkg.wind.times[0]
	var offsets := []
	var t := -2.0 * 3600.0
	while t <= 8.0 * 3600.0:
		if t >= first_wind and t <= last_wind - 6.0 * 3600.0:
			offsets.append(t)
		t += 1800.0
	for o in offsets:
		var label := "Start %s" % clock_text(o).split("  ")[1].split(" ")[0]
		if o == 0.0:
			label += " (gun)"
		pick.add_item(label)
	pick.select(maxi(offsets.find(0.0), 0))
	pick.item_selected.connect(func(i): action.emit("start_time", offsets[i]))
	return pick


# ---------------------------------------------------------------- console layout
# Title plate and forecast clock at top center, race pod top left, layers pod top right, steering pod
# bottom center. The controls built in setup() are moved into the pods.

var _plate: PanelContainer
var _plate_label: Label
var _clock_dial: ForecastClock
var _race_pod: PanelContainer
var _layers_pod: PanelContainer
var _steer_pod: PanelContainer
var _steer_row: HFlowContainer  # wraps to the polar's width
var _mode_keys := {}
var _mode_bar: HBoxContainer  # RaceSim.Mode -> Button


## A pod: a framed panel with a small amber tag and a flowing row of controls. Returns [panel, row].
func _pod(tag: String, width: float) -> Array:
	var panel := PanelContainer.new()
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var t := Label.new()
	t.text = tag
	t.add_theme_color_override("font_color", UiStyle.AMBER)
	t.add_theme_font_size_override("font_size", Settings.fs(10))
	box.add_child(t)
	var row := HFlowContainer.new()
	row.custom_minimum_size.x = width
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	return [panel, row]


func _arrange_console() -> void:
	var race: Array = _pod("RACE", 440.0)
	var layers: Array = _pod("LAYERS", 340.0)
	var steer: Array = _pod("STEERING", 520.0)
	_race_pod = race[0]
	_layers_pod = layers[0]
	_steer_pod = steer[0]
	var race_row: HFlowContainer = race[1]
	var layer_row: HFlowContainer = layers[1]
	var steer_row: HFlowContainer = steer[1]
	_steer_row = steer_row

	# Steering: one key per mode, then the route tools.
	# The modes sit joined in one bar; the active one has an amber underline.
	_mode_bar = HBoxContainer.new()
	_mode_bar.add_theme_constant_override("separation", 0)
	steer_row.add_child(_mode_bar)
	var modes := [[RaceSim.Mode.ROUTE, "ROUTE"], [RaceSim.Mode.HEADING, "HDG"], [RaceSim.Mode.TWA_LOCK, "TWA"], [RaceSim.Mode.CLOSE_HAULED, "CLOSE HLD"]]
	for m in modes:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var mode: int = m[0]
		b.pressed.connect(func(): action.emit("set_mode", mode))
		_mode_bar.add_child(b)
		_mode_keys[mode] = b
	_dress_mode_bar()

	for child in _top.get_children():
		if child == _mode_btn:
			child.visible = false
			child.reparent(steer_row)
		elif child == _speed:
			child.visible = false
			child.reparent(steer_row)
		elif child is CheckBox and child != _motor and (child as CheckBox).text != "UTC":
			child.reparent(layer_row)
		elif child == _motor:
			child.reparent(steer_row)
		elif child is Button and not child is OptionButton and not child is MenuButton and not child is CheckBox and (child as Button).text in ["Pause", "Slower", "Faster"]:
			child.queue_free()  # the forecast clock has its own keys
		elif child is Button and (child as Button).text in ["Clear route"]:
			child.reparent(steer_row)
		else:
			child.reparent(race_row)
	# Route export, weather import and the UTC clock live in Settings, on a Race tab.
	var to_settings := []
	for child in race_row.get_children():
		if child is MenuButton and (child as MenuButton).text == "Export route":
			to_settings.append(["Route", child])
		elif child is MenuButton and (child as MenuButton).text == "Import GRIB":
			to_settings.append(["Weather files", child])
		elif child is CheckBox and (child as CheckBox).text == "UTC":
			(child as CheckBox).text = "Show times in UTC"
			to_settings.append(["Clock", child])
	settings.add_tab("Race", to_settings)
	_source_pick.reparent(layer_row)
	layer_row.move_child(_source_pick, 0)
	_top.visible = false
	_wind_row.visible = false

	# Title plate: race and boat on an amber, slanted plate.
	_plate = PanelContainer.new()
	var ps := UiStyle.box(Color("#140f06"), UiStyle.AMBER, 1, 0)
	ps.skew = Vector2(-0.25, 0)
	ps.content_margin_left = 22
	ps.content_margin_right = 22
	_plate.add_theme_stylebox_override("panel", ps)
	_plate_label = Label.new()
	_plate_label.add_theme_color_override("font_color", Color("#ffd38a"))
	_plate.add_child(_plate_label)
	add_child(_plate)

	_clock_dial = ForecastClock.new()
	add_child(_clock_dial)
	_clock_dial.t0 = pkg.wind.times[0]
	_clock_dial.t1 = pkg.wind.times[pkg.wind.times.size() - 1]
	_clock_dial.hour_fmt = func(t: float) -> String:
		var unix := pkg.start_unix() + t + (0 if use_utc else pkg.utc_offset_s())
		return "%d" % Time.get_datetime_dict_from_unix_time(int(unix))["hour"]
	_clock_dial.view_time_changed.connect(func(t): action.emit("view_time", t))
	_clock_dial.key.connect(_clock_key)
	# Windows stay above the console: hover card, then results, help and settings on top.
	for top_node in [hover_card, _results, help, settings]:
		move_child(top_node, get_child_count() - 1)
	# Controls under a CanvasLayer do not inherit the window's theme, so give each top-level one the
	# game's console theme.
	for child in get_children():
		if child is Control:
			(child as Control).theme = Settings.theme
	for child in race_row.get_children():
		if child is OptionButton and (child as OptionButton).item_count > 0 and (child as OptionButton).get_item_text(0).length() > 30:
			(child as OptionButton).clip_text = true
			(child as OptionButton).fit_to_longest_item = false
			(child as OptionButton).custom_minimum_size.x = 260


func _clock_key(k: String) -> void:
	if k == "slower":
		action.emit("speed", -1)
	elif k == "faster":
		action.emit("speed", 1)
	elif k == "pause":
		action.emit("pause", null)
	elif k == "now":
		action.emit("view_now", null)


func _refresh_console(view_t: float, source: String, rel: String) -> void:
	if _clock_dial == null:
		return
	_plate_label.text = ("%s  ·  %s" % [pkg.info.get("leg", ""), sim.boat.name]).to_upper()
	_clock_dial.race_t = sim.display_t()
	_clock_dial.view_t = view_t
	_clock_dial.clock_text = clock_text(sim.display_t()).split("  ")[1].split(" ")[0]
	var src := "ACTUAL" if source == "actual wind" else source.to_upper().replace("GFS RUN ", "GFS ")
	_clock_dial.subtitle = "WIND MAP %s (%s) · %s" % [clock_text(view_t).split("  ")[1].split(" ")[0], rel.to_upper(), src]
	_clock_dial.speed_text = _speed.text.to_upper()
	_clock_dial.queue_redraw()
	for m in _mode_keys:
		(_mode_keys[m] as Button).set_pressed_no_signal(sim.mode == m)
	var vp := get_viewport().get_visible_rect().size
	_race_pod.position = Vector2(10, 10)
	_layers_pod.position = Vector2(10, vp.y - _bottom.size.y - _layers_pod.size.y - 10.0)
	_plate.position = Vector2((vp.x - _plate.size.x) / 2.0, 8)
	var k := clampf(Settings.text_scale, 1.0, 1.15)
	_clock_dial.size = Vector2(480, 210) * k
	_clock_dial.position = Vector2((vp.x - _clock_dial.size.x) / 2.0, _plate.position.y + _plate.size.y + 2.0)
	_alarm.position = Vector2(10, _race_pod.position.y + _race_pod.size.y + 8.0)


## Icons and keys on the steering bar, and joined segment styles: only the bar's outer corners are cut.
func _dress_mode_bar() -> void:
	var dress := {RaceSim.Mode.ROUTE: ["route", []], RaceSim.Mode.HEADING: ["heading", ["steer_left", "steer_right"]],
			RaceSim.Mode.TWA_LOCK: ["wind", []], RaceSim.Mode.CLOSE_HAULED: ["close_hauled", []]}
	var keys := _mode_bar.get_children()
	for i in keys.size():
		var b: Button = keys[i]
		var mode: int = _mode_keys.find_key(b)
		UiStyle.dress(b, dress[mode][0], dress[mode][1])
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := Settings.theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
			if i > 0:
				sb.corner_radius_top_left = 0
				sb.corner_radius_bottom_left = 0
				sb.border_width_left = 0
			if i < keys.size() - 1:
				sb.corner_radius_top_right = 0
				sb.corner_radius_bottom_right = 0
			b.add_theme_stylebox_override(state, sb)
		b.draw.connect(func():
			if b.button_pressed:
				b.draw_rect(Rect2(6.0, b.size.y - 3.0, b.size.x - 12.0, 3.0), UiStyle.AMBER))


## Icons and keys on the other console buttons, found by their labels.
func _dress_buttons() -> void:
	var looks := {"Clear route": ["clear", []],
			"Menu": ["menu", []], "Settings": ["settings", ["open_settings"]]}
	for pod in [_race_pod, _steer_pod]:
		for b in pod.find_children("*", "Button", true, false):
			if b is OptionButton or b is CheckBox or b.get_parent() == _mode_bar:
				continue
			var look = looks.get((b as Button).text)
			if look != null:
				UiStyle.dress(b, look[0], look[1])


## Draw the eye to the start time picker: it pops larger and flashes amber three times.
func flash_start_pick() -> void:
	var b := start_pick
	b.pivot_offset = b.size / 2.0
	b.z_index = 2
	var tw := b.create_tween()
	for i in 3:
		tw.tween_property(b, "scale", Vector2.ONE * 1.2, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "modulate", Color(2.0, 1.5, 0.6), 0.18)
		tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(b, "modulate", Color.WHITE, 0.22)
	tw.tween_callback(func(): b.z_index = 0)


## " (model)" after a boat name, or nothing when the entry list gives no model.
func _model_note(model: String) -> String:
	return "" if model.strip_edges() == "" else " (%s)" % model
