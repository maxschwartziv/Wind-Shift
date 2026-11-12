extends Control
## Opening menu: New race, Settings and Quit. New race lists every leg package with its description,
## direct distance, date, fleet size and average wind, then a boat to sail it with.

const MAIN_SCENE := "res://scenes/main.tscn"
const WIND_HOURS := 12.0  # average conditions cover the first 12 hours after the gun

var _home: VBoxContainer
var _races: VBoxContainer
var _boat_pick: OptionButton
var _start_btn: Button
var _selected := ""
var _cards := {}  # leg id -> PanelContainer
var _settings: SettingsMenu
var _profiles: Array[BoatProfile] = []
var _help: HelpPanel
var _race: Node  # the race scene playing behind the menu
var _races_panel: PanelContainer


func _ready() -> void:
	# Test and screenshot runs go straight to the race.
	var thumb := OS.get_cmdline_user_args().has("--thumb-shot")
	var shot := OS.get_cmdline_user_args().has("--menu-shot") or thumb
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and not shot:
			get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
			return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Settings.theme
	# The game plays behind the menu: the fleet at the start, with the instrument.
	Settings.attract = true
	# In its own viewport, so the race's camera moves only the map, not the menu.
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vp := SubViewport.new()
	vp.handle_input_locally = false
	box.add_child(vp)
	var race: Node = load(MAIN_SCENE).instantiate()
	vp.add_child(race)
	_race = box
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.08, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	center.add_child(stack)

	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 14)
	_home.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(_home)
	var title := Label.new()
	title.text = "WIND SHIFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://data/fonts/ArchivoBlack-Regular.ttf"))
	title.add_theme_font_size_override("font_size", Settings.fs(96))
	title.add_theme_color_override("font_color", Color("#ffd43b"))
	title.add_theme_color_override("font_shadow_color", Color("#0a0f0c"))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_color_override("font_outline_color", Color("#0a0f0c"))
	title.add_theme_constant_override("outline_size", 4)
	_home.add_child(title)
	var sub := Label.new()
	sub.text = "Read the weather. Beat the fleet."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", Settings.fs(22))
	sub.add_theme_color_override("font_color", Color("#e8f1ec"))
	sub.add_theme_color_override("font_outline_color", Color("#0a0f0c"))
	sub.add_theme_constant_override("outline_size", 6)
	_home.add_child(sub)
	var looks := [["New race", "flag", _show_races], ["Settings", "settings", func(): _settings.open()],
			["Help", "help", _open_help], ["Quit", "quit", func(): get_tree().quit()]]
	for look in looks:
		if look[0] == "Quit" and OS.has_feature("web"):
			continue  # a browser page cannot close itself
		var b := _menu_button(look[0], look[2])
		b.icon = UiStyle.icon(look[1])
		b.expand_icon = false
		_home.add_child(b)

	_races_panel = PanelContainer.new()
	_races_panel.visible = false
	stack.add_child(_races_panel)
	_races = VBoxContainer.new()
	_races.add_theme_constant_override("separation", 10)
	_races.custom_minimum_size = Vector2(900, 0)
	_races_panel.add_child(_races)
	_build_races()

	_settings = SettingsMenu.new()
	add_child(_settings)
	_settings.open_help = _open_help
	_help = HelpPanel.new()
	_help.theme = Settings.theme
	add_child(_help)
	if thumb:
		_thumb_shot()
	elif shot:
		_menu_shots()


func _menu_shots() -> void:
	# Used by tests: save the home screen and the race list, then quit.
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://menu_home.png")
	Settings.played = true  # show the race list, not the first-game shortcut (tests do not save settings)
	_show_races()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://menu_races.png")
	get_tree().quit()


## Store thumbnails: the title over the race, without the buttons. Saved to store/ in the project folder.
func _thumb_shot() -> void:
	for b in _home.get_children():
		if b is Button:
			b.modulate.a = 0.0  # keep the layout, so the title stays clear of the instrument
	for i in 40:  # the fleet just after the start, along the coast
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://").path_join("../store")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join("screen_full.png"))
	var wide := img.duplicate() as Image
	wide.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	wide.save_png(dir.path_join("thumbnail_1280x720.png"))
	# 630 x 500 cover: crop the middle of the frame to that shape, then scale.
	var h := img.get_height()
	var w := int(h * 630.0 / 500.0)
	var cover := img.get_region(Rect2i((img.get_width() - w) / 2, 0, w, h))
	cover.resize(630, 500, Image.INTERPOLATE_LANCZOS)
	cover.save_png(dir.path_join("cover_630x500.png"))
	get_tree().quit()


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size.x = 380
	b.add_theme_font_size_override("font_size", Settings.fs(20))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## Help pages, drawn with the boat chosen in the race list (or the first starter boat).
func _open_help() -> void:
	var boats := BoatProfile.all()
	var boat: BoatProfile = boats[0]
	for b in boats:
		if b.name == Settings.boat_name:
			boat = b
	_help.open(boat)


func _show_races() -> void:
	if not Settings.played:
		_selected = Settings.FIRST_LEG  # the first game skips the race list
		_start()
		return
	_home.visible = false
	_races_panel.visible = true


func _build_races() -> void:
	var head := Label.new()
	head.text = "Choose a race"
	head.add_theme_font_size_override("font_size", Settings.fs(26))
	_races.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_races.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for leg in LegPackage.list():
		var info := _summary(leg[0])
		if info.is_empty():
			continue
		list.add_child(_card(leg[0], info))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_races.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func():
		_races_panel.visible = false
		_home.visible = true)
	row.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var bl := Label.new()
	bl.text = "Boat"
	row.add_child(bl)
	_boat_pick = OptionButton.new()
	_boat_pick.focus_mode = Control.FOCUS_NONE
	_profiles = BoatProfile.all()
	for i in _profiles.size():
		_boat_pick.add_item(_profiles[i].name)
		if _profiles[i].name == Settings.boat_name:
			_boat_pick.select(i)
	row.add_child(_boat_pick)
	_start_btn = Button.new()
	_start_btn.text = "Start race"
	_start_btn.icon = UiStyle.icon("play")
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.custom_minimum_size = Vector2(160, 40)
	_start_btn.pressed.connect(_start)
	row.add_child(_start_btn)
	_select(Settings.leg_id if _cards.has(Settings.leg_id) else (_cards.keys()[0] if not _cards.is_empty() else ""))


## One race card: name, date, description and the figures.
func _card(id: String, info: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(id)
			if e.double_click:
				_start())
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var name := Label.new()
	name.text = "%s: %s" % [info["event"], info["leg"]]
	name.add_theme_font_size_override("font_size", Settings.fs(18))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var desc := Label.new()
	desc.text = info["description"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 860
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)
	var facts := Label.new()
	facts.text = info["facts"]
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.custom_minimum_size.x = 860
	facts.add_theme_color_override("font_color", Color("#9fc8ff"))
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(facts)
	_cards[id] = card
	return card


func _select(id: String) -> void:
	_selected = id
	for k in _cards:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.17, 0.22) if k == id else Color(0.08, 0.11, 0.15)
		style.border_color = Color("#5fd3c6") if k == id else Color(0.2, 0.25, 0.3)
		style.set_border_width_all(2 if k == id else 1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(12)
		_cards[k].add_theme_stylebox_override("panel", style)
	if _start_btn != null:
		_start_btn.disabled = id == ""


func _start() -> void:
	if _selected == "":
		return
	Settings.leg_id = _selected
	Settings.boat_name = _profiles[_boat_pick.selected].name
	Settings.attract = false
	Settings.played = true
	Settings.apply()
	if _race != null:
		_race.queue_free()
	get_tree().change_scene_to_file(MAIN_SCENE)


## Figures for a race card from the leg's own files: date, direct distance, fleet size and the average
## wind over the area during the first WIND_HOURS after the gun.
func _summary(id: String) -> Dictionary:
	var dir := "res://packages/" + id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/leg.json"))
	if not parsed is Dictionary:
		return {}
	var info: Dictionary = parsed
	var s: Array = info["start_line"]
	var f: Array = info["finish_line"]
	var a := (Vector2(s[0][0], s[0][1]) + Vector2(s[1][0], s[1][1])) / 2.0
	var b := (Vector2(f[0][0], f[0][1]) + Vector2(f[1][0], f[1][1])) / 2.0
	var dist := Geo.distance_nm(a, b)
	var fleet: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + str(info["fleet"])))
	var boats: int = fleet["ghosts"].size() if fleet is Dictionary else 0
	var w: Dictionary = info["wind"]
	var grid := VectorGrid.load_from(dir + "/" + w["file"], w, w["times_s"])
	var sum := Vector2.ZERO
	var speed_sum := 0.0
	var n := 0
	var hourly: Array[float] = []
	for ti in grid.times.size():
		var t: float = grid.times[ti]
		if t < 0.0 or t > WIND_HOURS * 3600.0:
			continue
		var hour_sum := 0.0
		var hour_n := 0
		for p in grid.grid_points():
			var v := grid.sample(p.x, p.y, t)
			sum += v
			speed_sum += v.length()
			hour_sum += v.length()
			n += 1
			hour_n += 1
		hourly.append(hour_sum / maxf(hour_n, 1) / Geo.MS_PER_KN)
	var mean_kn := speed_sum / maxf(n, 1) / Geo.MS_PER_KN
	var from := fposmod(rad_to_deg(atan2(-sum.x, -sum.y)), 360.0)
	var lo: float = hourly.min() if not hourly.is_empty() else 0.0
	var hi: float = hourly.max() if not hourly.is_empty() else 0.0
	var start_unix := Time.get_unix_time_from_datetime_string(info["start_utc"]) + int(info.get("utc_offset_s", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(start_unix))
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var facts := "%d %s %d, first gun %02d:%02d local   ·   %.0f nm direct   ·   %s   ·   wind %.0f kn from %03d° on average over the first %d h (hourly %.0f to %.0f kn)" % [
		d["day"], MONTHS[d["month"] - 1], d["year"], d["hour"], d["minute"], dist,
		("%d real boats" % boats) if boats > 0 else "no fleet", mean_kn, roundi(from), roundi(WIND_HOURS), lo, hi]
	return {"event": info.get("event", id), "leg": info.get("leg", ""), "description": info.get("description", ""), "facts": facts}
