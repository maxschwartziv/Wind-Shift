class_name UiStyle
## The game's console look: dark navy panels, cyan frames with chamfered corners, amber for the clock
## and titles. Applied to the root theme, so the HUD, menus and dialogs all match.

const NAVY := Color("#0a1a26")
const NAVY_DEEP := Color("#071019")
const CYAN := Color("#2ad4e6")
const CYAN_BRIGHT := Color("#4ff0ff")
const CYAN_DIM := Color("#1f8fa0")
const TRACK := Color("#12424d")
const AMBER := Color("#f0a93a")
const AMBER_TEXT := Color("#ffc164")
const TEXT := Color("#bff6ff")


## A panel or button box with chamfered corners (corner_detail 1 cuts them straight).
static func box(bg: Color, border: Color, width := 1, cut := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(cut)
	s.corner_detail = 1
	s.set_content_margin_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s


static func apply(theme: Theme) -> void:
	var normal := box(Color(0.05, 0.13, 0.19, 0.95), CYAN_DIM, 1, 6)
	var hover := box(Color(0.06, 0.17, 0.24, 0.95), CYAN, 1, 6)
	var pressed := box(Color("#0f3e48"), CYAN_BRIGHT, 1, 6)
	var disabled := box(Color(0.04, 0.09, 0.13, 0.9), Color(0.12, 0.25, 0.3), 1, 6)
	for type in ["Button", "OptionButton", "MenuButton", "CheckButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, Color("#e6fdff"))
		theme.set_color("font_hover_pressed_color", type, Color("#e6fdff"))
		theme.set_color("font_disabled_color", type, Color(0.45, 0.6, 0.65))
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckBox", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("panel", "PanelContainer", box(Color(NAVY, 0.92), CYAN, 1, 10))
	theme.set_stylebox("panel", "PopupMenu", box(NAVY, CYAN, 1, 6))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_stylebox("hover", "PopupMenu", box(Color("#0f3e48"), CYAN_BRIGHT, 1, 4))
	theme.set_stylebox("panel", "TabContainer", box(Color(NAVY, 0.92), CYAN_DIM, 1, 6))
	theme.set_stylebox("tab_selected", "TabContainer", box(Color("#0f3e48"), CYAN, 1, 4))
	theme.set_stylebox("tab_unselected", "TabContainer", box(NAVY, CYAN_DIM, 1, 4))
	theme.set_stylebox("tab_hovered", "TabContainer", box(Color(0.06, 0.17, 0.24), CYAN, 1, 4))
	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", TEXT)
	theme.set_stylebox("panel", "AcceptDialog", box(NAVY, CYAN, 1, 8))
	theme.set_color("title_color", "Window", AMBER_TEXT)
	apply_lamps(theme)


# ---------------------------------------------------------------- icons, lamps, key hints

## Line icons on a 24 by 24 grid, drawn in the button text color.
const ICONS := {
	"route": '<circle cx="5" cy="19" r="2.2"/><circle cx="19" cy="5" r="2.2"/><path d="M7 18 C 13 17, 9 8, 17 6" stroke-dasharray="3 2.5"/>',
	"heading": '<circle cx="12" cy="12" r="9"/><path d="M12 5 L15 14 L12 12.5 L9 14 Z"/>',
	"wind": '<path d="M3 8 H14 A3 3 0 1 0 11 5"/><path d="M3 12 H19 A3 3 0 1 1 16 15"/><path d="M3 16 H10"/>',
	"close_hauled": '<path d="M12 3 L12 20 L4 20 Z"/><path d="M14 6 L20 18"/>',
	"suggest": '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3"/><path d="M12 1.5 V5 M12 19 V22.5 M1.5 12 H5 M19 12 H22.5"/>',
	"clear": '<path d="M5 5 L19 19 M19 5 L5 19"/>',
	"menu": '<path d="M4 6 H20 M4 12 H20 M4 18 H20"/>',
	"settings": '<circle cx="12" cy="12" r="3.5"/><path d="M12 2.5 V6 M12 18 V21.5 M2.5 12 H6 M18 12 H21.5 M5.3 5.3 L7.8 7.8 M16.2 16.2 L18.7 18.7 M18.7 5.3 L16.2 7.8 M7.8 16.2 L5.3 18.7"/>',
	"flag": '<path d="M5 21 V3"/><path d="M5 4 H18 L15 8 L18 12 H5"/>',
	"help": '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5 A2.5 2.5 0 1 1 12 12 V14"/><circle cx="12" cy="17.2" r="0.6"/>',
	"quit": '<path d="M12 3 V11"/><path d="M7 6.5 A7.5 7.5 0 1 0 17 6.5"/>',
	"play": '<path d="M8 5 L19 12 L8 19 Z"/>',
}
static var _icon_cache := {}


static func icon(name: String) -> Texture2D:
	var px := Settings.fs(16)
	var key := "%s@%d" % [name, px]
	if not _icon_cache.has(key):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [TEXT.to_html(false), ICONS[name]]
		var img := Image.new()
		img.load_svg_from_string(svg, px / 24.0)
		_icon_cache[key] = ImageTexture.create_from_image(img)
	return _icon_cache[key]


## A round status lamp, lit green when on, for check boxes.
static func lamp(on: bool, disabled := false) -> Texture2D:
	var d := Settings.fs(14)
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) / 2.0
	var r := d * 0.32
	var fill := Color("#8be06a") if on else Color("#12424d")
	if disabled:
		fill = fill.darkened(0.5)
	for x in d:
		for y in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r + 0.5 - dist, 0.0, 1.0)
			var ring := clampf(1.0 - absf(dist - r - 1.5), 0.0, 1.0) * 0.8
			var col := fill
			col.a = a
			if a < 1.0 and ring > 0.0:
				col = Color(CYAN_DIM, ring)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func apply_lamps(theme: Theme) -> void:
	theme.set_icon("checked", "CheckBox", lamp(true))
	theme.set_icon("unchecked", "CheckBox", lamp(false))
	theme.set_icon("checked_disabled", "CheckBox", lamp(true, true))
	theme.set_icon("unchecked_disabled", "CheckBox", lamp(false, true))


## Icon on the left and, when actions are given, their keys in a small box on the right.
static func dress(b: Button, icon_name: String, actions: Array = []) -> void:
	b.icon = icon(icon_name)
	b.set_meta("icon_name", icon_name)
	if not actions.is_empty():
		var hint := KeyHint.new()
		hint.actions = actions
		b.add_child(hint)
