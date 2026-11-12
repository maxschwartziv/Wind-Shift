extends Node
## Windowed check: switch boats while the game runs and report the slowest frame.
## Run: godot --path game res://tests/frame_test.tscn [-- --leg=<id>]

var main: Node
var worst_ms := 0.0
var frames := 0
var _last := 0


func _ready() -> void:
	# Always measure on the first leg at normal text size, without saving over the player's settings.
	Settings.save_enabled = false
	Settings.leg_id = "n2e-2025"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			Settings.leg_id = arg.trim_prefix("--leg=")
	Settings.text_scale = 1.0
	Settings.apply()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	frames += 1
	if frames > 5:
		worst_ms = maxf(worst_ms, ms)
		if ms > 30.0:
			print("slow frame %d: %.1f ms" % [frames, ms])
	if frames == 30:
		# Click due east of the instrument's dial center: the boat should steer 090 in heading mode.
		var plot: SogPlot = main.hud.plot
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = plot._dial_c + Vector2(plot._dial_r * 0.5, 0)
		plot._gui_input(ev)
		var ok: bool = main.sim.mode == RaceSim.Mode.HEADING and absf(Geo.wrap180(main.sim.heading - 90.0)) < 1.0
		print("click on the dial: heading %.0f, mode %s -> %s" % [main.sim.heading, main.sim.mode, "PASS" if ok else "FAIL"])
	if frames == 40:
		# Drag the starboard edge of the no-go wedge out to 60 degrees, then press Close hauled.
		var plot: SogPlot = main.hud.plot
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = plot._dial_c + plot._dir(plot._wind_from + plot._beat) * plot._dial_r * 0.6
		plot._gui_input(press)
		var move := InputEventMouseMotion.new()
		move.position = plot._dial_c + plot._dir(plot._wind_from + 60.0) * plot._dial_r * 0.6
		plot._gui_input(move)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = move.position
		plot._gui_input(release)
		var drag_ok: bool = absf(main.sim.no_go_deg - 60.0) < 1.0
		main.hud.action.emit("set_mode", RaceSim.Mode.CLOSE_HAULED)  # the CLOSE HLD steering key
		var close_ok: bool = main.sim.mode == RaceSim.Mode.CLOSE_HAULED and absf(absf(main.sim.twa) - 60.0) < 1.0
		# Dragging the edge while close hauled moves the heading with it.
		plot._beat = main.sim.no_go_deg  # the dial redraws next frame; use the new edge now
		var press2 := InputEventMouseButton.new()
		press2.button_index = MOUSE_BUTTON_LEFT
		press2.pressed = true
		press2.position = plot._dial_c + plot._dir(plot._wind_from + plot._beat) * plot._dial_r * 0.6
		plot._gui_input(press2)
		var move2 := InputEventMouseMotion.new()
		move2.position = plot._dial_c + plot._dir(plot._wind_from + 50.0) * plot._dial_r * 0.6
		plot._gui_input(move2)
		plot._gui_input(release)
		var follow_ok: bool = absf(absf(main.sim.twa) - 50.0) < 1.0
		print("close hauled follows the edge: TWA %.0f -> %s" % [main.sim.twa, "PASS" if follow_ok else "FAIL"])
		print("no-go drag: %.0f deg -> %s; close hauled: mode %s, TWA %.0f -> %s" % [main.sim.no_go_deg,
				"PASS" if drag_ok else "FAIL", main.sim.mode, main.sim.twa, "PASS" if close_ok else "FAIL"])
	if frames == 55:
		main.sim.add_waypoint(Vector2(33.30, -117.75))
	if frames == 60:
		main._on_action("boat", 0)
	if frames == 62:
		var kept: bool = main.sim.waypoints.size() == 1
		main.camera.position += Vector2(500, 300)  # the player has panned away from the boat
		var cam: Vector2 = main.camera.position
		main._on_action("start_time", 1800.0)
		kept = kept and main.sim.waypoints.size() == 1
		main._on_action("start_time", 0.0)
		print("waypoints kept through boat and start-time changes -> %s" % ("PASS" if kept else "FAIL"))
		await get_tree().process_frame
		print("camera still after start-time change -> %s" % ("PASS" if main.camera.position == cam else "FAIL"))
	if frames == 120:
		main._on_action("boat", 3)
	if frames == 400:
		print("ideal progress %.0f%%, slowest frame %.1f ms over %d frames" % [main.hud.ideal_progress * 100.0, worst_ms, frames])
		main._on_action("boat", 0)
	if frames == 420:
		print("after switching back to a cached boat: slowest frame %.1f ms" % worst_ms)
		get_viewport().get_texture().get_image().save_png("user://frame_test.png")
		get_tree().quit()
