class_name KeyHint
extends Control
## The keyboard key for a button, in a small box at the button's right end. Follows key rebinding.

var actions: Array = []  # Settings action names; two steer actions show as one arrow pair


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.changed.connect(_fit)
	_fit.call_deferred()
	var b := get_parent() as BaseButton
	b.mouse_entered.connect(queue_redraw)
	b.mouse_exited.connect(queue_redraw)
	b.toggled.connect(func(_on): queue_redraw())
	b.resized.connect(_cover)
	_cover()


## Cover the whole button, so the key box sits at its right end.
func _cover() -> void:
	position = Vector2.ZERO
	size = (get_parent() as Control).size
	queue_redraw()


func _text() -> String:
	var names := []
	for a in actions:
		var s := OS.get_keycode_string(Settings.keys[a])
		names.append({"Left": "←", "Right": "→", "Escape": "ESC", "BracketLeft": "[", "BracketRight": "]",
				"Equal": "=", "Minus": "-"}.get(s, s.to_upper()))
	return "".join(names) if names.size() == 2 and names[0] == "←" else " ".join(names)


func _font_px() -> int:
	return Settings.fs(10)


func _box_w() -> float:
	return get_theme_default_font().get_string_size(_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px()).x + 8.0


## Widen the button so its label and icon stay clear of the key box.
func _fit() -> void:
	var b := get_parent() as Button
	if b == null:
		return
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = 0.0
	b.custom_minimum_size.x = b.get_minimum_size().x + _box_w() + 8.0
	queue_redraw()


func _draw() -> void:
	var w := _box_w()
	var h := float(_font_px()) + 6.0
	var r := Rect2(size.x - w - 8.0, (size.y - h) / 2.0, w, h)
	var b := get_parent() as Button
	var lit := b != null and (b.is_hovered() or b.button_pressed)
	var col := UiStyle.CYAN_BRIGHT if lit else UiStyle.CYAN_DIM
	draw_rect(r, col, false, 1.0)
	draw_string(get_theme_default_font(), Vector2(r.position.x + 4.0, r.position.y + h - 4.0), _text(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px(), col)
