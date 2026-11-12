extends Node2D
## Loads the leg, builds the map, particles, overlay, camera and HUD, and runs the race clock.

const CLICK_MOVE_PX := 6.0  # a press that moves less than this is a click, not a drag
const REMOVE_RADIUS_PX := 16.0

var pkg: LegPackage
var profiles: Array[BoatProfile]
var boat_index := 2
var sim: RaceSim
var map: MapView
var overlay: Overlay
var particles: WindParticles
var trails: WindTrails
var camera: Camera2D
var hud: Hud
var speed_index := 2
var paused := false
var _field_on := true  # the Wind colors box; the depth map hides the colors while it is on
var _depth_on := false
var _plan: PlanPrompt
var follow := true
var view_live := true  # wind map time follows the race clock
var suggestion := {}
const ATTRACT_LEG := "n2e-2025"  # the biggest fleet, behind the main menu
const ATTRACT_FROM_S := 600.0  # replay from 10 minutes after the first gun, with the fleet at the start
const ATTRACT_ZOOM := 7.0
var _attract_to_s := 2.0 * 3600.0  # start slowing down when 80% of the fleet has finished
const ATTRACT_SLOW_S := 4.0  # real seconds to slow from full speed to a stop
const ATTRACT_HOLD_S := 3.0  # real seconds paused before the replay starts again
var _attract_end := -1.0  # real seconds since the slowdown began, or -1 while at full speed
const IDEAL_BUDGET_MS := 6.0  # wall time per frame spent routing and sailing the ideal boats
var _ideal_runs: Array[IdealRun] = []
var _ideal_cache := {}  # boat name -> Array[Ghost] of finished ideal boats
var _suggest_timer := 0.0
var _legs_timer := 0.0
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _middle_drag := false
var start_offset := 0.0  # the player's start, seconds after the first gun
var _hover_wp := -1  # waypoint under the pointer, -1 for none
var _test_mouse := Vector2.INF  # screenshot tests set a fixed mouse position here


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			Settings.leg_id = arg.trim_prefix("--leg=")
	pkg = LegPackage.load_dir("res://packages/" + (ATTRACT_LEG if Settings.attract else Settings.leg_id))
	var b: Dictionary = pkg.info["bounds"]
	Geo.set_origin(b["lat_max"], b["lon_min"])
	for g in pkg.ghosts:
		g.build_world()
	profiles = BoatProfile.all()
	for i in profiles.size():
		if profiles[i].name == Settings.boat_name:
			boat_index = i

	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * 0.5
	add_child(camera)
	map = MapView.new()
	add_child(map)
	map.setup(pkg, camera)
	particles = WindParticles.new()
	particles.setup(pkg, camera)
	add_child(particles.field)
	trails = WindTrails.new()
	add_child(trails)
	trails.setup(particles, camera)
	overlay = Overlay.new()
	overlay.pkg = pkg
	overlay.camera = camera
	add_child(overlay)
	hud = Hud.new()
	add_child(hud)
	hud.setup(pkg, profiles, boat_index, pkg.wind.times[pkg.wind.times.size() - 1])
	hud.action.connect(_on_action)
	hud.plot.no_go_changed.connect(func(deg: float):
		sim.no_go_deg = deg
		sim.reapply())  # a close-hauled heading follows the new edge at once
	hud.plot.heading_picked.connect(func(h: float):
		if sim.mode != RaceSim.Mode.HEADING:
			sim.set_mode(RaceSim.Mode.HEADING)
		sim.set_heading(h)
		Settings.play("click"))
	Settings.changed.connect(_on_settings_changed)
	_new_sim()
	camera.position = Geo.to_world(sim.pos.x, sim.pos.y)
	camera.force_update_scroll()
	particles.update_wind(overlay.wind_grid(), 0.0)
	particles.restart()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--import="):  # tests: --import=<kind>:<res:// path>
			var parts := arg.trim_prefix("--import=").split(":", true, 1)
			_import_weather(parts[0], parts[1].get_file(), FileAccess.get_file_as_bytes(parts[1]))
	if Settings.attract:
		_setup_attract()
		return
	# A new race waits paused at the start, with the whole course in view, while the player plans.
	# Tests turn saving off and run the clock from the first frame.
	if Settings.save_enabled or OS.get_cmdline_user_args().has("--plan-shot"):
		paused = true
		_fit_course.call_deferred()
		_plan = PlanPrompt.new()
		_plan.theme = Settings.theme
		hud.add_child(_plan)
		_plan.dismissed.connect(hud.flash_start_pick)  # next: pick a start time
		hud.move_child(_plan, mini(mini(hud.settings.get_index(), hud.help.get_index()), hud.hover_card.get_index()))  # above the panels, under the windows
	if OS.get_cmdline_user_args().has("--results-shot"):
		_results_shot_and_quit.call_deferred()
	if OS.get_cmdline_user_args().has("--plan-shot"):
		_plan_shot_and_quit.call_deferred()
	if OS.get_cmdline_user_args().has("--screenshot"):
		_screenshot_and_quit()
	elif OS.get_cmdline_user_args().has("--help-shots"):
		_help_shots_and_quit()
	elif OS.get_cmdline_user_args().has("--settings-shots"):
		_settings_shots_and_quit()


## A fresh race for the chosen boat and start time. keep_route carries the player's waypoints over.
func _new_sim(keep_route := false) -> void:
	var route: Array[Vector2] = []
	if keep_route and sim != null:
		route = sim.waypoints.duplicate()
	sim = RaceSim.new(pkg, profiles[boat_index])
	for w in route:
		sim.add_waypoint(w)
	sim.min_tack_s = Settings.min_tack_min * 60.0
	if start_offset != 0.0:
		sim.start_at(start_offset)
	sim.ended.connect(func(st):
		if Settings.attract:
			return  # no sound or race report behind the main menu
		Settings.play("finish" if st == "finished" else "ground")
		hud.show_results())
	sim.maneuver.connect(func(_kind): Settings.play("tack"))
	sim.waypoint_reached.connect(func(): Settings.play("waypoint"))
	overlay.sim = sim
	if not Settings.attract:
		_start_ideals(sim.boat)
	hud.bind(sim)
	map.set_draft(sim.boat.draft_m)
	view_live = true
	suggestion = {}
	_suggest_timer = 0.0  # the next frame computes it, so a boat switch is not one long frame


## Show cached ideal boats for this profile, or start sailing them a few ms per frame.
func _start_ideals(boat: BoatProfile) -> void:
	_ideal_runs.clear()
	var ideals: Array[Ghost] = []
	if _ideal_cache.has(_ideal_key(boat)):
		ideals = _ideal_cache[_ideal_key(boat)]
	else:
		for src in [RaceSim.WindSource.FORECAST, RaceSim.WindSource.ACTUAL]:
			var run := IdealRun.new(pkg, boat, src, Settings.min_tack_min * 60.0, start_offset)
			_ideal_runs.append(run)
			ideals.append(run.ghost)
	overlay.ideals = ideals
	hud.ideals = ideals


## Ideal boats depend on the boat and the shortest tack setting.
func _ideal_key(boat: BoatProfile) -> String:
	return "%s|%d|%d" % [boat.name, Settings.min_tack_min, roundi(start_offset)]


func _on_settings_changed() -> void:
	sim.min_tack_s = Settings.min_tack_min * 60.0
	if not _ideal_cache.has(_ideal_key(sim.boat)) and (_ideal_runs.is_empty() or _ideal_runs[0].min_tack_s != Settings.min_tack_min * 60.0):
		_start_ideals(sim.boat)


func _step_ideals() -> void:
	if _ideal_runs.is_empty():
		hud.ideal_progress = 1.0
		return
	var all_done := true
	var total := 0.0
	for run in _ideal_runs:
		run.step(IDEAL_BUDGET_MS / _ideal_runs.size())
		all_done = all_done and run.done
		total += run.progress()
	hud.ideal_progress = total / _ideal_runs.size()
	if all_done:
		var ghosts: Array[Ghost] = []
		for run in _ideal_runs:
			ghosts.append(run.ghost)
		_ideal_cache[_ideal_key(_ideal_runs[0].boat)] = ghosts
		_ideal_runs.clear()


func _process(delta: float) -> void:
	if _plan != null and _plan.visible:
		if not paused:
			_plan.visible = false  # the race has started
		else:
			var vp := get_viewport().get_visible_rect().size
			_plan.position = ((vp - _plan.size) / 2.0).max(Vector2(10, 10))  # center screen
	if Settings.attract:
		_attract_step(delta)
		_follow_fleet(delta)
	_step_ideals()
	# The player steers by what the wind map shows: the period forecast, or the actual wind in perfect forecast.
	sim.steer_source = RaceSim.WindSource.ACTUAL if overlay.show_actual else RaceSim.WindSource.FORECAST
	if not paused and not Settings.attract:
		sim.advance(delta * Hud.SPEEDS[speed_index])
	_suggest_timer -= delta
	if _suggest_timer <= 0.0:
		_suggest_timer = 0.2
		suggestion = sim.suggestion() if sim.state == "racing" else {}
	# The leg forecast runs on its own frames, offset from the suggestion, to keep frame times even.
	_legs_timer -= delta
	if _legs_timer <= 0.0 and _suggest_timer < 0.15:
		_legs_timer = 0.5
		_refresh_legs()
	overlay.selected_leg = hud.leg_plot.index if hud.leg_plot.index > 0 else -1  # page 0 is the boat now
	if follow:
		var dp := sim.display_pos()
		camera.position = Geo.to_world(dp.x, dp.y)
	if view_live:
		overlay.view_t = sim.display_t()
	overlay.suggestion = suggestion
	_update_waypoint_hover()
	overlay.use_utc = hud.use_utc
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var mouse := get_viewport().get_mouse_position() if not _test_mouse.is_finite() else _test_mouse
	var in_window := Rect2(Vector2.ZERO, get_viewport_rect().size).has_point(mouse)
	var modal := hud.help.visible or hud.settings.visible
	hud.hover_card.overlay = overlay
	if _test_mouse.is_finite():
		over_ui = false
	var world_mouse := get_canvas_transform().affine_inverse() * mouse
	hud.hover_card.mouse = mouse
	hud.hover_card.hover = world_mouse if in_window and not over_ui and not modal and not _dragging and not _middle_drag else Vector2.INF
	hud.hover_card.queue_redraw()
	var ease := 1.0 - exp(-10.0 * delta)
	overlay.shown_heading = rad_to_deg(lerp_angle(deg_to_rad(overlay.shown_heading), deg_to_rad(sim.heading), ease))
	overlay.queue_redraw()
	if particles.visible or particles.field.visible:
		particles.update_wind(overlay.wind_grid(), overlay.view_t)
		_update_measured_wind()
	hud.refresh(0 if paused else speed_index, suggestion, overlay.view_t, overlay.show_actual)


func _on_action(name: String, value: Variant) -> void:
	match name:
		"boat":
			boat_index = value
			Settings.boat_name = profiles[value].name
			Settings.apply()
			_new_sim(true)
		"menu":
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		"start_time":
			start_offset = value
			_new_sim(true)
			follow = false  # the camera stays where the player left it; F follows the boat again
		"import":
			_import_weather(value[0], value[1], value[2])
		"leg":
			Settings.leg_id = value
			Settings.apply()
			get_tree().reload_current_scene()
		"pause":
			paused = not paused
		"speed":
			paused = false
			speed_index = clampi(speed_index + value, 1, Hud.SPEEDS.size() - 1)
		"mode":
			sim.set_mode((sim.mode + 1) % RaceSim.Mode.size())
		"set_mode":
			if not (value == RaceSim.Mode.CLOSE_HAULED and sim.motoring):
				sim.set_mode(value)
		"apply":
			if suggestion.get("heading", -1.0) >= 0.0:
				if sim.mode == RaceSim.Mode.ROUTE:
					sim.set_mode(RaceSim.Mode.HEADING)
				sim.set_heading(suggestion["heading"])
		"clear_route":
			sim.clear_waypoints()
		"motoring":
			sim.set_motoring(value)
		"view_source":
			overlay.show_actual = value
		"view_time":
			view_live = absf(value - sim.t) < 300.0
			overlay.view_t = value
		"view_now":
			view_live = true
		"layer_particles":
			particles.visible = value
			particles.emitting = value
			trails.visible = value
		"layer_depth":
			map.set_depth_map(value)
			_depth_on = value
			particles.field.visible = _field_on and not _depth_on  # the depth map reads best without the wind colors
		"layer_field":
			_field_on = value
			particles.field.visible = _field_on and not _depth_on
		"layer_wind":
			overlay.show_wind = value
		"layer_current":
			overlay.show_current = value
		"layer_trails":
			overlay.show_trails = value
		"layer_labels":
			overlay.show_labels = value
		"layer_tests":
			overlay.show_tests = value
		"restart":
			if value and sim.state == "dnf":
				sim.restore(sim.last_save())
				hud.bind(sim)
			else:
				_new_sim()


func _steer_manually(delta_deg: float) -> void:
	if sim.mode == RaceSim.Mode.ROUTE:
		sim.set_mode(RaceSim.Mode.HEADING)
	sim.set_heading(sim.heading + delta_deg)


func _shift_view(hours: float) -> void:
	view_live = false
	overlay.view_t = clampf(overlay.view_t + hours * 3600.0, 0.0, pkg.wind.times[pkg.wind.times.size() - 1])


func _unhandled_input(event: InputEvent) -> void:
	if Settings.attract:
		return
	if event is InputEventKey and event.pressed:
		var step := 10.0 if event.shift_pressed else 1.0
		if event.is_action_pressed("open_settings", true):
			if not hud.help.visible:
				hud.settings.open()
		elif event.is_action_pressed("steer_left", true):
			_steer_manually(-step)
		elif event.is_action_pressed("steer_right", true):
			_steer_manually(step)
		elif event.is_action_pressed("cycle_mode"):
			_on_action("mode", null)
		elif event.is_action_pressed("apply_suggestion"):
			_on_action("apply", null)
		elif event.is_action_pressed("pause"):
			_on_action("pause", null)
		elif event.is_action_pressed("speed_up"):
			_on_action("speed", 1)
		elif event.is_action_pressed("slow_down"):
			_on_action("speed", -1)
		elif event.is_action_pressed("view_back", true):
			_shift_view(-1.0)
		elif event.is_action_pressed("view_forward", true):
			_shift_view(1.0)
		elif event.is_action_pressed("follow_boat"):
			follow = true
	elif event is InputEventMouseButton:
		var add_button := MOUSE_BUTTON_RIGHT if Settings.swap_mouse else MOUSE_BUTTON_LEFT
		var remove_button := MOUSE_BUTTON_LEFT if Settings.swap_mouse else MOUSE_BUTTON_RIGHT
		var zoom_in := MOUSE_BUTTON_WHEEL_DOWN if Settings.invert_zoom else MOUSE_BUTTON_WHEEL_UP
		var zoom_out := MOUSE_BUTTON_WHEEL_UP if Settings.invert_zoom else MOUSE_BUTTON_WHEEL_DOWN
		if event.button_index == zoom_in and event.pressed:
			_zoom_at(1.15)
		elif event.button_index == zoom_out and event.pressed:
			_zoom_at(1.0 / 1.15)
		elif event.button_index == add_button:
			if event.pressed:
				_pressed = true
				_dragging = false
				_press_pos = event.position
			else:
				if _pressed and not _dragging and sim.state == "racing":
					var on_wp := _waypoint_at(event.position)
					if on_wp >= 0:
						_show_weather_at(on_wp)  # a click on a waypoint shows the forecast for when the boat gets there
					else:
						sim.add_waypoint(Geo.to_latlon(get_global_mouse_position()))
						Settings.play("click")
					if sim.mode != RaceSim.Mode.ROUTE:
						sim.set_mode(RaceSim.Mode.ROUTE)
				_pressed = false
				_dragging = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_drag = event.pressed
		elif event.button_index == remove_button and event.pressed:
			var at := Geo.to_latlon(get_global_mouse_position())
			var nm_per_px := 1.0 / camera.zoom.x * _world_px_m(at.x) / Geo.M_PER_NM
			if sim.remove_waypoint_near(at, REMOVE_RADIUS_PX * nm_per_px):
				Settings.play("remove")
	elif event is InputEventMouseMotion and _middle_drag:
		follow = false
		camera.position -= event.relative / camera.zoom.x
	elif event is InputEventMouseMotion and _pressed:
		if not _dragging and event.position.distance_to(_press_pos) > CLICK_MOVE_PX:
			_dragging = true
		if _dragging:
			follow = false
			camera.position -= event.relative / camera.zoom.x


## Replace the leg's forecast wind, actual wind or current with a GRIB file for this session.
func _import_weather(kind: String, file_name: String, bytes: PackedByteArray) -> void:
	var r := WeatherImport.build(bytes, "current" if kind == "current" else "wind", pkg)
	if not r["ok"]:
		hud.show_message("GRIB not imported", "%s

%s" % [file_name, r["message"]])
		return
	var g: VectorGrid = r["grid"]
	match kind:
		"wind_forecast":
			pkg.forecasts = [{"run_utc": "", "label": "imported " + file_name, "available_s": -1e12, "grid": g}]
		"wind_actual":
			pkg.wind = g
		"current":
			pkg.current = g
	var what: String = {"wind_forecast": "forecast wind", "wind_actual": "actual wind", "current": "current"}[kind]
	pkg.info["credits"].append("Imported %s: %s" % [what, file_name])
	_ideal_cache.clear()
	_start_ideals(sim.boat)
	hud.show_message("GRIB imported", "The %s now comes from %s.

%s" % [what, file_name, r["message"]])


## Index of the waypoint within 16 px of a screen point, or -1.
func _waypoint_at(screen: Vector2) -> int:
	var canvas := get_canvas_transform()
	for i in sim.waypoints.size():
		if (canvas * Geo.to_world(sim.waypoints[i].x, sim.waypoints[i].y)).distance_to(screen) <= 16.0:
			return i
	return -1


## Forecast time of arrival at waypoint i (race seconds), or -1 for no such waypoint.
func _waypoint_eta(i: int) -> float:
	if i < 0 or i >= sim.waypoints.size() or sim.state != "racing":
		return -1.0
	if overlay.legs.size() != sim.waypoints.size() + 1:
		_refresh_legs()  # a waypoint placed in the last 0.5 s has no leg forecast yet
	var legs: Array = overlay.legs
	return float(legs[i]["start_t"]) + float(legs[i]["dur_s"])


## Move the wind map to the forecast time of arrival at waypoint i.
func _show_weather_at(i: int) -> void:
	var eta := _waypoint_eta(i)
	if eta < 0.0:
		return
	view_live = false
	overlay.view_t = clampf(eta, 0.0, pkg.wind.times[pkg.wind.times.size() - 1])
	Settings.play("click")


## Hover text on the waypoint under the pointer: its arrival time and what a click does.
func _update_waypoint_hover() -> void:
	var mouse := get_viewport().get_mouse_position() if not _test_mouse.is_finite() else _test_mouse
	_hover_wp = _waypoint_at(mouse) if sim.state == "racing" else -1
	var eta := _waypoint_eta(_hover_wp)
	if _hover_wp < 0 or eta < 0.0:
		overlay.waypoint_hint = {}
		return
	var at := hud.clock_text(eta).split("  ")[1].split(" ")[0]
	overlay.waypoint_hint = {"index": _hover_wp, "text": "WP%d: show wind at arrival (%s)" % [_hover_wp + 1, at]}


## Inside the circle where the boat measures the wind, the wind map shows the actual wind, while the
## map shows the forecast for the present time.
func _update_measured_wind() -> void:
	var dp := sim.display_pos()
	var on := not overlay.show_actual and view_live and sim.state == "racing" and not Settings.attract
	var radius := RaceSim.MEASURE_NM * Geo.M_PER_NM / _world_px_m(dp.x)
	particles.set_observation(on, Geo.to_world(dp.x, dp.y), radius, pkg.wind.sample(dp.x, dp.y, sim.display_t()))
	overlay.measure_on = on


## Meters per world unit (zoom-12 pixel) at a latitude.
func _world_px_m(lat: float) -> float:
	return 40075016.686 * cos(deg_to_rad(lat)) / Geo.WORLD


func _zoom_at(f: float) -> void:
	var before := get_global_mouse_position()
	camera.zoom = (camera.zoom * f).clamp(Vector2.ONE * 0.02, Vector2.ONE * 8.0)
	if not follow:
		camera.position += before - get_global_mouse_position()


func _screenshot_and_quit() -> void:
	# Used by tests: plot two waypoints, show the ideal tracks, advance 2 hours, save a PNG,
	# then a zoomed-in PNG with labels 25 minutes after the start, and quit.
	if Settings.leg_id == "n2e-2025":
		sim.add_waypoint(Vector2(33.30, -117.75))
		sim.add_waypoint(Vector2(32.90, -117.45))
	overlay.show_tests = true
	if OS.get_cmdline_user_args().has("--depth-map"):
		map.set_depth_map(true)
		particles.field.visible = false
		overlay.show_wind = true
	while not _ideal_runs.is_empty():  # finish the ideal boats first so their tracks show
		for run in _ideal_runs:
			run.step(1000.0)
		_step_ideals()
	if Settings.leg_id != "n2e-2025":
		follow = false
		var mid := (pkg.start_line[0] + pkg.finish_line[0]) / 2.0
		camera.position = Geo.to_world(mid.x, mid.y)
		var span := Geo.to_world(pkg.start_line[0].x, pkg.start_line[0].y) - Geo.to_world(pkg.finish_line[0].x, pkg.finish_line[0].y)
		camera.zoom = Vector2.ONE * clampf(0.8 * minf(1600.0 / maxf(absf(span.x), 1.0), 900.0 / maxf(absf(span.y), 1.0)), 0.05, 2.0)
	var early := sim.snapshot()
	sim.advance(2 * 3600.0)
	for i in 180:
		await get_tree().process_frame
	if sim.waypoints.size() > 0:
		# Hover over waypoint 1, save the hint, then click it.
		_test_mouse = get_canvas_transform() * Geo.to_world(sim.waypoints[0].x, sim.waypoints[0].y)
		for i in 40:
			await get_tree().process_frame
		var before := overlay.view_t
		get_viewport().get_texture().get_image().save_png("user://screenshot_waypoint_hint.png")
		_show_weather_at(0)
		_test_mouse = Vector2.INF
		for i in 20:
			await get_tree().process_frame
		print("show weather: wind map time %.2f h -> %.2f h" % [before / 3600.0, overlay.view_t / 3600.0])
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshot.png")
	camera.zoom = Vector2.ONE * 3.0
	overlay.show_labels = true
	overlay.show_tests = false
	follow = false
	var start_mid := (pkg.start_line[0] + pkg.start_line[1]) / 2.0
	camera.position = Geo.to_world(33.555, -117.885) if Settings.leg_id == "n2e-2025" else Geo.to_world(start_mid.x, start_mid.y)
	for i in 30:
		await get_tree().process_frame
	sim.restore(early)
	sim.advance(25 * 60.0)
	_test_mouse = Vector2(330, 470)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://screenshot_zoom.png")
	print("screenshot: ", ProjectSettings.globalize_path("user://screenshot.png"))
	get_tree().quit()


func _help_shots_and_quit() -> void:
	# Used by tests: open each help page, let its animation run, save a PNG per page, and quit.
	hud.help.open(sim.boat)
	for i in hud.help._pages.size():
		hud.help._show(i)
		for f in 90:
			await get_tree().process_frame
		if i == 5:  # route planning: jump to the end of the search, where the route shows
			hud.help._anim.t = hud.help._anim._router.isochrones.size() * 0.8 + 3.0
			for f in 5:
				await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://help_%d.png" % i)
		if hud.help._anim.page == HelpAnim.Page.STEERING:  # one frame per steering mode
			for m in 4:
				hud.help._anim.t = m * HelpAnim.STEER_S + 4.5
				for f in 3:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://help_steering_%d.png" % m)
	print("help shots: ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()


func _settings_shots_and_quit() -> void:
	# Used by tests: each settings tab, the game at 150% text with leg 2 selected, then restore the scale.
	sim.add_waypoint(Vector2(33.30, -117.75))
	sim.add_waypoint(Vector2(32.90, -117.45))
	hud.settings.open()
	var tabs: TabContainer = hud.settings.find_children("*", "TabContainer", true, false)[0]
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		for f in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://settings_%d.png" % i)
	hud.settings.visible = false
	var old_scale := Settings.text_scale
	Settings.text_scale = 1.5
	Settings.apply()
	for f in 40:
		await get_tree().process_frame
	hud.leg_plot.select(1)
	for f in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://text_150.png")
	Settings.text_scale = old_scale
	Settings.apply()
	print("settings shots: ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()


## Behind the main menu: the fleet at the start with names, the live instrument, no other HUD, running
## at 60x from just after the first gun and looping.
func _setup_attract() -> void:
	for child in hud.get_children():
		if child is Control and child != hud.plot:
			(child as Control).visible = false
	hud.plot.get_node("Help").visible = false
	sim.start_at(ATTRACT_FROM_S)
	speed_index = Hud.SPEEDS.size() - 1
	overlay.show_labels = true
	follow = false
	overlay.hide_player = true
	var finishes: Array[float] = []
	for g in pkg.ghosts:
		if g.finished:
			finishes.append(g.finish_time_s())
	finishes.sort()
	if not finishes.is_empty():
		_attract_to_s = finishes[int(finishes.size() * 0.8)]
	camera.zoom = Vector2.ONE * ATTRACT_ZOOM
	camera.position = _fleet_view()


## Camera target behind the main menu: the middle of the boats still racing, placed in the lower left,
## clear of the title and buttons.
func _fleet_view() -> Vector2:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for g in pkg.ghosts:
		var st := g.state_at(sim.t)
		if st.get("visible", false) and not st.get("done", false):
			xs.append(st.pos.x)
			ys.append(st.pos.y)
	if xs.is_empty():
		return camera.position
	xs.sort()
	ys.sort()
	var mid := Vector2(xs[xs.size() / 2], ys[ys.size() / 2])
	return mid + Vector2(360.0, -150.0) / camera.zoom.x


func _follow_fleet(delta: float) -> void:
	camera.position = camera.position.lerp(_fleet_view(), minf(1.0, delta * 2.0))
	if sim.t < ATTRACT_FROM_S + 60.0:
		camera.position = _fleet_view()  # jump back to the start on each loop


## Replay clock behind the main menu: full speed until 80% of the fleet has finished, then slow to a
## stop, hold, and start again. The fleet keeps moving after the hidden player boat finishes or grounds.
func _attract_step(delta: float) -> void:
	var rate: float = Hud.SPEEDS[speed_index]
	if _attract_end < 0.0 and sim.t >= _attract_to_s:
		_attract_end = 0.0
	if _attract_end >= 0.0:
		_attract_end += delta
		if _attract_end >= ATTRACT_SLOW_S + ATTRACT_HOLD_S:
			_attract_end = -1.0
			sim.start_at(ATTRACT_FROM_S)
			return
		var f := clampf(1.0 - _attract_end / ATTRACT_SLOW_S, 0.0, 1.0)
		rate *= f * f  # ease out to a stop
	var step := delta * rate
	if sim.state == "racing":
		sim.advance(step)
	else:
		sim.t += step


func _refresh_legs() -> void:
	var src := RaceSim.WindSource.ACTUAL if overlay.show_actual else RaceSim.WindSource.FORECAST
	overlay.legs = sim.leg_forecast(src) if sim.state == "racing" else []
	hud.leg_plot.set_legs(overlay.legs)


## Camera on the whole course, from the start line to the finish line, in the map area between the
## left-hand panels and the instrument on the right.
func _fit_course() -> void:
	for i in 3:  # let the panels lay out first
		await get_tree().process_frame
	var pts: Array[Vector2] = []
	for q in pkg.start_line + pkg.finish_line:
		pts.append(Geo.to_world(q.x, q.y))
	for m in pkg.marks:
		pts.append(Geo.to_world(m.x, m.y))
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	var vp := get_viewport().get_visible_rect().size
	var left := maxf(hud._race_pod.size.x, hud._layers_pod.size.x) + 20.0
	var right := vp.x - hud.plot.get_global_rect().position.x + 20.0
	var avail := Vector2(maxf(vp.x - left - right, 300.0), vp.y - 200.0)
	var z := clampf(0.85 * minf(avail.x / maxf(r.size.x, 1.0), avail.y / maxf(r.size.y, 1.0)), 0.02, 4.0)
	camera.zoom = Vector2.ONE * z
	# Shift the course center to the middle of the open map area.
	var screen_mid := Vector2(left + avail.x / 2.0, 100.0 + avail.y / 2.0)
	camera.position = r.get_center() + (vp / 2.0 - screen_mid) / z
	follow = false


func _plan_shot_and_quit() -> void:
	# Used by tests: the paused start screen with the plan prompt, saved as a PNG.
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://plan_start.png")
	for t in [0.3, 1.2, 1.8]:  # the start time button: pointer on its way, list open, new time picked
		_plan._t = t
		_plan.set_process(false)
		_plan._anim.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://plan_pick_%d.png" % roundi(t * 10))
	_plan.set_process(true)
	_plan._show_warning()
	for i in 360:  # until the boat is in the light air
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://plan_warning.png")
	_plan.visible = false
	_plan.dismissed.emit()
	for i in 9:  # the first pop at its largest
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://plan_flash.png")
	map.set_depth_map(true)
	_on_action("layer_depth", true)
	_on_action("layer_depth", false)
	print("wind colors back after the depth map -> %s" % ("PASS" if particles.field.visible else "FAIL"))
	get_tree().quit()


func _results_shot_and_quit() -> void:
	# Used by tests: the race report, with its buttons, saved as a PNG.
	for i in 30:
		await get_tree().process_frame
	hud.show_results()
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://results.png")
	var r: Rect2 = hud._results.get_global_rect()
	print("race report inside the window -> %s" % ("PASS" if get_viewport().get_visible_rect().encloses(r) else "FAIL"))
	get_tree().quit()
