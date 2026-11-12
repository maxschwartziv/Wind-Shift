extends SceneTree
## Windowed check of the race behind the main menu: no race report, the replay slows to a stop, holds,
## and starts again.
## Run: godot --path game --script res://tests/attract_test.gd

var main: Node


func _initialize() -> void:
	var settings := root.get_node("Settings")
	settings.save_enabled = false
	settings.attract = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	main._attract_to_s = main.sim.t + 3600.0  # reach the slowdown after about 1 s at 3600x
	var peak := 0.0
	var stopped := false
	var looped := false
	var last: float = main.sim.t
	var t0 := Time.get_ticks_msec()
	var prev := t0
	while Time.get_ticks_msec() - t0 < 12000:
		await process_frame
		var now := Time.get_ticks_msec()
		var rate: float = (main.sim.t - last) / maxf((now - prev) / 1000.0, 0.001)
		prev = now
		if main.sim.t < last:
			looped = true
			break
		peak = maxf(peak, rate)
		if main._attract_end > 0.0 and main.sim.t == last:
			stopped = true
		last = main.sim.t
	var report: bool = main.hud._results.visible
	print("peak %.0fx, stopped %s, looped %s, race report shown %s" % [peak, stopped, looped, report])
	print("attract replay -> %s" % ("PASS" if stopped and looped and not report else "FAIL"))
	quit()
