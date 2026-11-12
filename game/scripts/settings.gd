extends Node
## Player settings, saved to user://settings.cfg: music and sound effects, key bindings, mouse options
## and UI text size. Also owns the Music and SFX audio buses and their players. Loaded as the
## "Settings" autoload.

signal changed

const PATH := "user://settings.cfg"
const BASE_FONT := 16
const SOUNDS := ["click", "remove", "tack", "waypoint", "finish", "ground"]

## Remappable keyboard actions in menu order: [action, label, default key].
const ACTIONS := [
	["steer_left", "Steer left 1° (hold Shift for 10°)", KEY_LEFT],
	["steer_right", "Steer right 1° (hold Shift for 10°)", KEY_RIGHT],
	["cycle_mode", "Next steering mode", KEY_T],
	["apply_suggestion", "Steer the suggested heading", KEY_ENTER],
	["pause", "Pause", KEY_SPACE],
	["speed_up", "Faster", KEY_EQUAL],
	["slow_down", "Slower", KEY_MINUS],
	["view_back", "Wind map 1 hour back", KEY_BRACKETLEFT],
	["view_forward", "Wind map 1 hour ahead", KEY_BRACKETRIGHT],
	["follow_boat", "Follow the boat", KEY_F],
	["open_settings", "Settings", KEY_ESCAPE],
]

var music_on := true
var music_volume := 0.5  # 0 to 1
var sfx_on := true
var sfx_volume := 0.8
var swap_mouse := false  # right button adds waypoints, left removes
var invert_zoom := false
var text_scale := 1.0  # 1.0 to 2.0
var leg_id := "queens-cup-2024"  # leg package under res://packages
const FIRST_LEG := "queens-cup-2024"  # the first New race goes straight to this leg
var played := false  # a race has been started from the main menu before
var boat_name := "Beneteau First 40.7"  # boat profile chosen in the race menu
var min_tack_min := 0  # shortest time between tacks or gybes in route mode and for the ideal boats, minutes; 0 for no limit
var keys := {}  # action -> keycode
## The race scene plays behind the main menu: no HUD but the instrument, no input, a looping replay.
var attract := false
var save_enabled := true  # tests turn this off so they leave the saved settings alone

var theme := Theme.new()
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _streams := {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	for name in SOUNDS:
		_streams[name] = load("res://data/audio/%s.wav" % name)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)
	var song: AudioStreamWAV = load("res://data/audio/music.wav")
	song.loop_mode = AudioStreamWAV.LOOP_FORWARD
	song.loop_begin = 0
	song.loop_end = song.data.size() / 2  # 16-bit mono: two bytes per sample
	_music = AudioStreamPlayer.new()
	_music.stream = song
	_music.bus = "Music"
	add_child(_music)
	for a in ACTIONS:
		keys[a[0]] = a[2]
	_load()
	# Test runs (screenshots, a forced leg) never write the player's saved settings.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			save_enabled = false
	UiStyle.apply(theme)  # once: rebuilding the styles on every save restyled every control and stalled a frame
	get_tree().root.theme = theme
	apply()


## Push every setting to the audio buses, input map and theme, then save.
func apply() -> void:
	_bus("Music", music_on, music_volume)
	_bus("SFX", sfx_on, sfx_volume)
	if music_on and not _music.playing:
		_music.play()
	elif not music_on:
		_music.stop()
	for a in ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.keycode = keys[action]
		InputMap.action_add_event(action, ev)
		if action == "speed_up" and keys[action] == KEY_EQUAL:
			_add_key(action, KEY_KP_ADD)
		elif action == "slow_down" and keys[action] == KEY_MINUS:
			_add_key(action, KEY_KP_SUBTRACT)
		elif action == "apply_suggestion" and keys[action] == KEY_ENTER:
			_add_key(action, KEY_KP_ENTER)
	if theme.default_font_size != fs(BASE_FONT):
		theme.default_font_size = fs(BASE_FONT)  # changing the theme restyles every control, so only when needed
		UiStyle.apply_lamps(theme)
	_save()
	changed.emit()


## A font size in pixels scaled by the UI text size setting.
func fs(px: float) -> int:
	return roundi(px * text_scale)


func play(sound: String) -> void:
	if not sfx_on or not _streams.has(sound):
		return
	for p in _sfx:
		if not p.playing:
			p.stream = _streams[sound]
			p.play()
			return


func key_name(action: String) -> String:
	var code: int = keys.get(action, KEY_NONE)
	const SYMBOLS := {KEY_EQUAL: "=", KEY_MINUS: "-", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
			KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'",
			KEY_BACKSLASH: "\\", KEY_QUOTELEFT: "`"}
	return SYMBOLS.get(code, OS.get_keycode_string(code))


func reset_keys() -> void:
	for a in ACTIONS:
		keys[a[0]] = a[2]
	apply()


func _add_key(action: String, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	InputMap.action_add_event(action, ev)


func _bus(name: String, on: bool, volume: float) -> void:
	var i := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(i, not on or volume <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume, 0.0001)))


func _save() -> void:
	if not save_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_on", sfx_on)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("mouse", "swap", swap_mouse)
	cfg.set_value("mouse", "invert_zoom", invert_zoom)
	cfg.set_value("display", "text_scale", text_scale)
	cfg.set_value("sailing", "min_tack_min", min_tack_min)
	cfg.set_value("game", "leg_id", leg_id)
	cfg.set_value("game", "boat_name", boat_name)
	cfg.set_value("game", "played", played)
	for action in keys:
		cfg.set_value("keys", action, keys[action])
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_on = cfg.get_value("audio", "music_on", music_on)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_on = cfg.get_value("audio", "sfx_on", sfx_on)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	swap_mouse = cfg.get_value("mouse", "swap", swap_mouse)
	invert_zoom = cfg.get_value("mouse", "invert_zoom", invert_zoom)
	text_scale = cfg.get_value("display", "text_scale", text_scale)
	min_tack_min = cfg.get_value("sailing", "min_tack_min", min_tack_min)
	leg_id = cfg.get_value("game", "leg_id", leg_id)
	boat_name = cfg.get_value("game", "boat_name", boat_name)
	played = cfg.get_value("game", "played", played)
	if not FileAccess.file_exists("res://packages/%s/leg.json" % leg_id):
		leg_id = "n2e-2025"
	for action in keys:
		keys[action] = cfg.get_value("keys", action, keys[action])


const HOVER_SCALE := 1.06  # buttons grow this much under the pointer
const HOVER_S := 0.08  # seconds to grow or shrink


## Every button in the game grows under the pointer and clicks when pressed.
func _on_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var b := node as BaseButton
	if b.has_meta("console_hooked"):
		return  # moved to a new parent; already hooked
	b.set_meta("console_hooked", true)
	b.mouse_entered.connect(_hover.bind(b, true))
	b.mouse_exited.connect(_hover.bind(b, false))
	b.pressed.connect(func(): play("click"))


func _hover(b: BaseButton, on: bool) -> void:
	if b.disabled and on:
		return
	b.pivot_offset = b.size / 2.0
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), HOVER_S)
	b.z_index = 1 if on else 0  # drawn over its neighbors while grown
