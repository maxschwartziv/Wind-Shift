class_name SettingsMenu
extends Control
## Settings window: sound (music and effects), controls (key bindings and mouse) and display (text size).
## Every change applies at once and is saved by the Settings autoload.

var _key_buttons := {}  # action -> Button
var _waiting_for := ""  # action whose new key is being captured
var _scale_label: Label
var _menu_btn: Button
## Opens the help pages; set by whoever owns this menu (the race HUD or the main menu).
var open_help: Callable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 560)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.13, 0.98)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = "HeaderLarge"
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	tabs.add_child(_sound_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_sailing_tab())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_menu_btn = Button.new()
	_menu_btn.text = "Main menu"
	_menu_btn.tooltip_text = "Leave this race and go back to the main menu"
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	buttons.add_child(_menu_btn)
	var help := Button.new()
	help.text = "Help"
	help.tooltip_text = "Polars, sailing terms, route planning and the instrument"
	help.focus_mode = Control.FOCUS_NONE
	help.pressed.connect(func():
		if open_help.is_valid():
			visible = false
			open_help.call())
	buttons.add_child(help)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): visible = false)
	buttons.add_child(close)


## Add a tab of the owner's own controls, each with a label beside it: [[label, Control], ...].
func add_tab(tab_name: String, rows: Array) -> void:
	var tabs: TabContainer = find_children("*", "TabContainer", true, false)[0]
	var grid := _grid(tab_name)
	for r in rows:
		var label := Label.new()
		label.text = r[0]
		grid.add_child(label)
		var control: Control = r[1]
		if control.get_parent() != null:
			control.reparent(grid)
		else:
			grid.add_child(control)
	tabs.add_child(grid.get_parent())
	tabs.move_child(grid.get_parent(), 0)
	tabs.current_tab = 0


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_waiting_for = ""
	_refresh_keys()
	# Main menu only during a race; on the menu itself there is nowhere to go back to.
	var scene := get_tree().current_scene
	_menu_btn.visible = scene != null and scene.scene_file_path != "res://scenes/menu.tscn"
	visible = true


func _sound_tab() -> Control:
	var grid := _grid("Sound")
	_toggle(grid, "Music", Settings.music_on, func(on): Settings.music_on = on; Settings.apply())
	_slider(grid, "Music volume", Settings.music_volume, func(v): Settings.music_volume = v; Settings.apply())
	_toggle(grid, "Sound effects", Settings.sfx_on, func(on): Settings.sfx_on = on; Settings.apply())
	_slider(grid, "Sound effects volume", Settings.sfx_volume, func(v):
		Settings.sfx_volume = v
		Settings.apply()
		Settings.play("click"))
	return grid.get_parent()


func _controls_tab() -> Control:
	var grid := _grid("Controls")
	for a in Settings.ACTIONS:
		var label := Label.new()
		label.text = a[1]
		grid.add_child(label)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.x = 160
		b.pressed.connect(_capture.bind(a[0]))
		grid.add_child(b)
		_key_buttons[a[0]] = b
	_toggle(grid, "Swap mouse buttons (right adds waypoints)", Settings.swap_mouse, func(on):
		Settings.swap_mouse = on
		Settings.apply())
	_toggle(grid, "Invert wheel zoom", Settings.invert_zoom, func(on): Settings.invert_zoom = on; Settings.apply())
	var reset := Button.new()
	reset.text = "Reset keys"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		Settings.reset_keys()
		_refresh_keys())
	grid.add_child(Control.new())
	grid.add_child(reset)
	return grid.get_parent()


func _display_tab() -> Control:
	var grid := _grid("Display")
	var label := Label.new()
	label.text = "Text size"
	grid.add_child(label)
	var row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 2.0
	slider.step = 0.125
	slider.value = Settings.text_scale
	slider.custom_minimum_size.x = 200
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	_scale_label = Label.new()
	_scale_label.text = "%d%%" % roundi(Settings.text_scale * 100.0)
	row.add_child(_scale_label)
	grid.add_child(row)
	# Apply when the drag ends, so the layout does not rebuild on every step of the slider.
	slider.value_changed.connect(func(v): _scale_label.text = "%d%%" % roundi(v * 100.0))
	slider.drag_ended.connect(func(_changed):
		Settings.text_scale = slider.value
		Settings.apply())
	return grid.get_parent()


func _sailing_tab() -> Control:
	var grid := _grid("Sailing")
	var label := Label.new()
	label.text = "Shortest tack (route mode and ideal boats)"
	grid.add_child(label)
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	var choices := [0, 5, 10, 15, 20, 30, 45, 60]
	for m in choices:
		pick.add_item("No limit" if m == 0 else "%d min" % m)
	pick.select(maxi(choices.find(Settings.min_tack_min), 0))
	pick.item_selected.connect(func(i):
		Settings.min_tack_min = choices[i]
		Settings.apply())
	grid.add_child(pick)
	var note := Label.new()
	note.text = "The boat holds each tack or gybe at least this long. Changing it recomputes the ideal boats."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 300
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	grid.add_child(note)
	return grid.get_parent()


func _grid(tab_name: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	return grid


func _toggle(grid: GridContainer, text: String, on: bool, cb: Callable) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var check := CheckButton.new()
	check.button_pressed = on
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(cb)
	grid.add_child(check)


func _slider(grid: GridContainer, text: String, value: float, cb: Callable) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 200
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(cb)
	grid.add_child(slider)


func _capture(action: String) -> void:
	_waiting_for = action
	_refresh_keys()
	_key_buttons[action].text = "Press a key"


func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = Settings.key_name(action)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting_for != "" and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode not in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			# A key already bound to another action moves here; that action takes this action's old key.
			for other in Settings.keys:
				if other != _waiting_for and Settings.keys[other] == event.keycode:
					Settings.keys[other] = Settings.keys[_waiting_for]
			Settings.keys[_waiting_for] = event.keycode
			_waiting_for = ""
			Settings.apply()
			_refresh_keys()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_settings"):
		visible = false
		get_viewport().set_input_as_handled()
