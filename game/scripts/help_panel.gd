class_name HelpPanel
extends Control
## Help pages opened from the "?" on the boat instrument: text on the left, an animated diagram on the right.

var _polar: Polar
var _boat_name := ""
var _title: Label
var _text: RichTextLabel
var _anim: HelpAnim
var _pages: Array[Dictionary] = []


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
	panel.custom_minimum_size = Vector2(1180, 640)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.13, 0.98)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 190
	row.add_child(nav)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", Settings.fs(22))
	body.add_child(_title)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	body.add_child(content)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.custom_minimum_size = Vector2(480, 560)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", Settings.fs(15))
	_text.add_theme_font_size_override("bold_font_size", Settings.fs(15))
	content.add_child(_text)
	_anim = HelpAnim.new()
	content.add_child(_anim)

	_pages = _page_list()
	for i in _pages.size():
		var b := Button.new()
		b.text = _pages[i]["title"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_show.bind(i))
		nav.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): visible = false)
	nav.add_child(close)


func open(boat: BoatProfile) -> void:
	_polar = boat.polar
	_boat_name = boat.name
	_anim.polar = _polar
	_pages = _page_list()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_theme_font_size_override("font_size", Settings.fs(22))
	_text.add_theme_font_size_override("normal_font_size", Settings.fs(15))
	_text.add_theme_font_size_override("bold_font_size", Settings.fs(15))
	visible = true
	_show(0)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()


func _show(i: int) -> void:
	_title.text = _pages[i]["title"]
	_text.text = _pages[i]["text"]
	_anim.show_page(_pages[i]["anim"])


func _polar_table() -> String:
	if _polar == null:
		return ""
	var winds := [6.0, 10.0, 14.0, 20.0]
	var s := "[table=5][cell][b]TWA \\ TWS[/b]  [/cell]"
	for w in winds:
		s += "[cell][b]%d kn[/b]  [/cell]" % w
	for a in [45.0, 60.0, 90.0, 120.0, 150.0, 180.0]:
		s += "[cell]%d°[/cell]" % a
		for w in winds:
			s += "[cell]%.1f[/cell]" % _polar.speed(a, w)
	return s + "[/table]"


func _page_list() -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	pages.append({"title": "Polar", "anim": HelpAnim.Page.POLAR, "text": "\n".join([
		"A [b]polar[/b] is a table of a boat's speed through the water (STW) for each true wind angle (TWA) and true wind speed (TWS). Rows are TWA in degrees. Columns are TWS in knots (kn; 1 kn is 1 nautical mile per hour).",
		"",
		"The game assumes perfect sail trim, so the boat always sails at its polar speed. Tacks and gybes cost a fixed time set in the boat profile.",
		"",
		"[b]%s polar, STW in kn[/b]" % _boat_name,
		_polar_table(),
		"",
		"Drawn around a circle with the wind from the top, each heading becomes one point: its direction is the heading and its distance from the center is the STW. The animation turns the boat through every heading in 10 kn of wind and draws that curve.",
		"",
		"Speed falls to zero head to wind. It peaks with the wind on the beam or just behind it, and drops again dead downwind.",
	])})
	pages.append({"title": "Wind terms", "anim": HelpAnim.Page.WIND, "text": "\n".join([
		"[b]TWS, true wind speed[/b]: the wind speed over the water, in kn. Over a current, the game measures it against the moving water, so a current running with the wind lowers the TWS.",
		"",
		"[b]TWD, true wind direction[/b]: the compass direction the true wind comes from, in degrees.",
		"",
		"[b]TWA, true wind angle[/b]: the angle between the boat's heading and the true wind, 0–180° on each side. [b]Port[/b] means wind over the left side of the boat, [b]starboard (stbd)[/b] over the right side.",
		"",
		"[b]AWS, apparent wind speed[/b] and [b]AWA, apparent wind angle[/b]: the wind felt on the moving boat. It is the true wind plus a headwind equal to the boat's own speed. Sailing toward the wind raises the AWS and moves the AWA forward; sailing away from it does the opposite.",
		"",
		"The polar uses TWA and TWS. The leg pages of the instrument show AWA and AWS, the values a boat's wind instrument reads.",
		"",
		"The boat measures the actual wind within 2 nm of itself. Inside that circle the wind map shows the measured wind, and the instrument and suggested heading use it. Beyond the circle the map shows the period forecast.",
		"",
		"In the animation the boat swings between close reaching and broad reaching. Blue is the true wind, gray the headwind from the boat's speed, white the apparent wind.",
	])})
	pages.append({"title": "Course terms", "anim": HelpAnim.Page.COURSE, "text": "\n".join([
		"[b]HDG, heading[/b]: the compass direction the bow points, in degrees.",
		"",
		"[b]STW, speed through the water[/b]: the boat's speed relative to the water around it, in kn. It comes from the polar.",
		"",
		"[b]Current[/b]: the water's own motion over the ground, in kn. The game reads it from the HYCOM ocean model for the event dates.",
		"",
		"[b]SOG, speed over ground[/b] and [b]COG, course over ground[/b]: the boat's speed and direction relative to the seabed. They are the STW along the heading plus the current.",
		"",
		"The map draws these three arrows from your boat: white STW, purple current, green SOG. The animation turns a 1.8 kn current around a boat sailing 6 kn on 060°. A current from behind adds speed; a current from the side pushes the COG away from the heading.",
	])})
	pages.append({"title": "VMC and suggested heading", "anim": HelpAnim.Page.VMC, "text": "\n".join([
		"[b]VMC, velocity made good on course[/b]: the part of the SOG that points at the next waypoint, mark or finish line, in kn. It equals SOG × cos(angle between COG and the bearing to the target).",
		"",
		"[b]VMG, velocity made good[/b]: the same idea measured toward the wind instead of toward a target. The game uses VMC.",
		"",
		"[b]Suggested heading[/b]: the heading with the highest VMC right now, leaving out headings that ground the boat within 30 minutes. It is a greedy rule: it does not look ahead at wind changes.",
		"",
		"[b]WP1[/b]: the first waypoint of your route.",
		"",
		"In the animation the heading sweeps across the curve. The orange point is the present heading, the cyan bar its VMC, and the cyan dot the heading with the best VMC. The fastest heading is often not the best one.",
	])})
	pages.append({"title": "No-go zone and tacking", "anim": HelpAnim.Page.NO_GO, "text": "\n".join([
		"A sailboat cannot sail straight into the wind. The [b]no-go zone[/b] is the wedge either side of the wind inside the boat's best upwind angle: the TWA where the polar gives the most speed toward the wind.",
		"",
		"To reach a point upwind, the boat sails along one edge of the wedge, then turns through the wind to the other edge. That turn is a [b]tack[/b]. Turning the stern through the wind is a [b]gybe[/b].",
		"",
		"The best upwind angle depends on the boat and the TWS. The animation uses your boat's polar at 10 kn.",
		"",
		"The instrument shades the no-go zone in red at the present TWS.",
	])})
	pages.append({"title": "Route planning", "anim": HelpAnim.Page.ROUTING, "text": "\n".join([
		"The [b]actual ideal[/b] and [b]forecast ideal[/b] boats sail routes planned with [b]isochrones[/b]. An isochrone is the line joining every point the boat can reach in the same time.",
		"",
		"The router grows one isochrone per time step. From each point on the newest isochrone it sails every heading for one step, at the polar speed for the wind and current there. Tacks and gybes lose their penalty time.",
		"",
		"It then keeps only the outermost point in each narrow wedge of bearing from the start. Points behind the front are slower ways to the same place, so the router drops them. Points that cross land or water shallower than the draft are dropped too.",
		"",
		"The first isochrone to cross the finish line gives the fastest time. Following each point back to the point it came from gives the route.",
		"",
		"The animation runs the router on a small made-up sea with half-hour steps. The direct line runs through a light-wind pocket, so the fastest route bends around it and around the island.",
		"",
		"The actual ideal plans in the actual wind, with perfect information. The forecast ideal plans in the period forecast and plans again each time a new forecast comes out. The suggested heading on the instrument uses a simpler rule: the best VMC right now.",
		"",
		"The [b]shortest tack[/b] setting stops routes and route mode from tacking or gybing again sooner than the time you set.",
	])})
	pages.append({"title": "Steering modes", "anim": HelpAnim.Page.STEERING, "text": "\n".join([
		"The STEERING panel has four modes. One is on at a time, shown with an amber underline.",
		"",
		"[b]ROUTE[/b] follows your waypoints. Once each game minute it steers the heading with the best VMC toward the next waypoint, or the finish after the last one. It tacks only when the other tack gives at least 10% more VMC and the shortest tack time has passed. Clicking the map to add a waypoint turns route mode on.",
		"",
		"[b]HDG[/b] holds a compass heading. The Left and Right keys turn 1°, or 10° with Shift. Clicking the instrument dial steers that heading and turns HDG on. When the wind shifts, the heading stays and the TWA changes.",
		"",
		"[b]TWA[/b] holds the true wind angle. When the wind shifts, the boat turns with it and the TWA stays.",
		"",
		"[b]CLOSE HLD[/b] (close hauled) sails along the edge of the no-go zone and follows wind shifts. It tacks by itself when the other tack gives at least 10% more VMC, or when the present tack would run aground within 5 minutes, and waits at least the shortest tack time between tacks.",
		"",
		"The Enter key steers the suggested heading once and turns HDG on. [b]Clear route[/b] removes your waypoints. [b]Motoring[/b] runs the engine in races that allow it; motoring time counts against you by the race's penalty factor.",
	])})
	pages.append({"title": "Instrument", "anim": HelpAnim.Page.INSTRUMENT, "text": "\n".join([
		"The instrument is north up, like the map. On the Now page the green curve is the SOG for every heading at the boat's present position, in the wind the boat measures and the present current. The rings are speed in kn. Prev and Next show the legs after the present one, in the forecast for when the boat gets there.",
		"",
		"[b]1[/b]  Orange needle and dot: your present heading and its SOG.",
		"[b]2[/b]  Cyan dot: the suggested heading, the one with the best VMC.",
		"[b]3[/b]  Dashed cyan line: the bearing to the next waypoint, mark or finish line.",
		"[b]4[/b]  Blue arrow: the true wind, pointing the way it blows.",
		"[b]5[/b]  Red wedge: the no-go zone.",
		"[b]6[/b]  Green curve: SOG on each heading.",
		"",
		"Top left: present heading and SOG. Top right: suggested heading and its VMC. Bottom: TWS, TWA and STW.",
		"",
		"On the Now page, click anywhere on the dial to steer that heading. The boat switches to heading mode. Moving the pointer over the dial shows the heading and its SOG before you click.",
		"",
		"Drag either edge of the red no-go wedge to set your own no-go angle. Route mode and the suggested heading then never sail closer to the wind than that. Right-click inside the wedge to go back to the polar's own angle.",
		"",
		"[b]Close hauled[/b] (the CLOSE HLD key under STEERING) stays on until you pick another steering mode. The boat sails along the no-go edge, follows wind shifts and your changes to the no-go angle, and tacks by itself when the other tack gives at least 10% more VMC toward the next waypoint, mark or finish, or when the present tack would run aground within 5 minutes. It waits at least the shortest tack time set in Settings between tacks.",
	])})
	pages.append({"title": "All terms", "anim": HelpAnim.Page.NONE, "text": "\n".join([
		"[b]AWA[/b]  apparent wind angle, degrees",
		"[b]AWS[/b]  apparent wind speed, kn",
		"[b]COG[/b]  course over ground, degrees",
		"[b]DNF[/b]  did not finish",
		"[b]ERA5[/b]  the reanalysis the actual wind comes from: hourly, on a 0.25° (about 25 km) grid",
		"[b]GFS[/b]  Global Forecast System, the NOAA model the period forecast comes from",
		"[b]GRIB[/b]  gridded binary, the standard file format for weather data; Import GRIB reads wind and current from GRIB1 and GRIB2 files",
		"[b]HDG[/b]  heading, degrees",
		"[b]kn[/b]  knot, 1 nautical mile per hour (0.514 m/s)",
		"[b]Depth map[/b]  water shaded light (shallow) to dark (deep), with contour lines at 2, 5, 10, 20, 50, 100, 200, 500, 1000 and 2000 m; red where shallower than the draft",
		"[b]nm[/b]  nautical mile, 1852 m",
		"[b]Polar[/b]  table of STW by TWA and TWS",
		"[b]Port, stbd[/b]  wind over the left or right side of the boat",
		"[b]SOG[/b]  speed over ground, kn",
		"[b]STW[/b]  speed through the water, kn",
		"[b]TWA[/b]  true wind angle, degrees",
		"[b]TWD[/b]  true wind direction, degrees, where the wind comes from",
		"[b]TWS[/b]  true wind speed, kn",
		"[b]UTC[/b]  Coordinated Universal Time",
		"[b]VMC[/b]  velocity made good on course, kn toward the target",
		"[b]VMG[/b]  velocity made good, kn toward the wind",
		"[b]WP1[/b]  first waypoint of the route",
	])})
	return pages
