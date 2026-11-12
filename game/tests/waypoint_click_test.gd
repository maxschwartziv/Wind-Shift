extends SceneTree
## Windowed check: a left click on each waypoint moves the wind map to the boat's arrival time there.
## Run: godot --path game --script res://tests/waypoint_click_test.gd

var main: Node


func _initialize() -> void:
	var settings := root.get_node("Settings")
	settings.save_enabled = false
	settings.leg_id = "n2e-2025"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _click(screen: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		main._unhandled_input(e)


func _run() -> void:
	for i in 10:
		await process_frame
	main.paused = true
	main.follow = false
	var start: Vector2 = main.sim.pos
	for k in [1, 2]:
		main.sim.add_waypoint(start + Vector2(-0.06 * k, 0.03 * k))
	for i in 60:  # the leg forecast refreshes every 0.5 s
		await process_frame
	var ok := true
	for i in main.sim.waypoints.size():
		main.view_live = true
		main.overlay.view_t = main.sim.t
		var wp: Vector2 = main.sim.waypoints[i]
		var screen: Vector2 = main.get_canvas_transform() * Geo.to_world(wp.x, wp.y)
		var eta: float = main._waypoint_eta(i)
		_click(screen)
		await process_frame
		var moved: bool = not main.view_live and absf(main.overlay.view_t - eta) < 1.0
		print("WP%d at %s: eta %.0f s, wind map %.0f s, hit %d -> %s" % [i + 1, screen, eta, main.overlay.view_t, main._waypoint_at(screen), "PASS" if moved else "FAIL"])
		ok = ok and moved
	# Place a third waypoint and click it at once, before the leg forecast refreshes.
	main.sim.add_waypoint(start + Vector2(-0.2, 0.1))
	var screen3: Vector2 = main.get_canvas_transform() * Geo.to_world(start.x - 0.2, start.y + 0.1)
	main.view_live = true
	_click(screen3)
	var fresh: bool = not main.view_live and absf(main.overlay.view_t - main._waypoint_eta(2)) < 1.0
	print("WP3 clicked right after placing it -> %s" % ("PASS" if fresh else "FAIL"))
	ok = ok and fresh
	print("waypoint clicks -> %s" % ("PASS" if ok else "FAIL"))
	quit()
