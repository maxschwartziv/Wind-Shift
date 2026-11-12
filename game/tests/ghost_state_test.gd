extends SceneTree
## Headless check: a ghost track with two fixes at the same time gives a finite position and heading.
## Run: godot --headless --path game --script res://tests/ghost_state_test.gd


func _initialize() -> void:
	var trail := PackedVector2Array([Vector2(43.0, -87.8), Vector2(43.0, -87.8), Vector2(42.9, -87.6)])
	var times := PackedFloat64Array([0.0, 0.0, 600.0])
	var g := Ghost.from_run("test", "test", trail, times, 600.0, true)
	g.build_world()
	var ok := true
	for t in [0.0, 1.0, 300.0, 600.0]:
		var st := g.state_at(t)
		ok = ok and (st["pos"] as Vector2).is_finite() and is_finite(st["heading"])
	print("ghost with repeated fix times -> %s" % ("PASS" if ok else "FAIL"))
	quit()
