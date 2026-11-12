class_name HoverCard
extends Control
## Wind sample under the mouse: TWS, and the TWA a boat would sail at if it headed for this point from
## the last waypoint (or from the boat), drawn as a small dial with the boat, the wind and the no-go
## zone, plus the boat's polar curve (STW on every heading in that wind). Uses the wind map's source and time, like the wind particles. Drawn above the HUD.

const W := 260.0
const H := 130.0

var overlay: Overlay
var hover := Vector2.INF  # world point under the mouse; INF hides the card
var mouse := Vector2.ZERO  # the same point in screen pixels
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _draw() -> void:
	if overlay != null and not overlay.waypoint_hint.is_empty():
		_draw_hint(overlay.waypoint_hint["text"])
		return
	if not hover.is_finite() or overlay == null or overlay.sim == null:
		return
	var sim := overlay.sim
	var pkg := overlay.pkg
	var at := Geo.to_latlon(hover)
	if pkg.depth_at(at.x, at.y) <= 0.0:
		return
	var w := overlay.wind_sample(at, overlay.view_t)
	var cur := pkg.current.sample(at.x, at.y, overlay.view_t)
	var rel := w - cur
	var tws := rel.length() / Geo.MS_PER_KN
	var from := fposmod(Geo.bearing(-rel), 360.0)
	var origin: Vector2 = sim.waypoints[sim.waypoints.size() - 1] if sim.waypoints.size() > 0 else sim.display_pos()
	var origin_name := "WP%d" % sim.waypoints.size() if sim.waypoints.size() > 0 else "boat"
	var heading := fposmod(Geo.bearing(Geo.offset_m(origin, at)), 360.0)
	var twa := Geo.wrap180(from - heading)
	var stw := sim.boat.polar.speed(absf(twa), tws)
	var beat := SogPlot.beat_angle(sim.boat.polar, tws)

	var k := Settings.text_scale
	var card := Vector2(W, H) * k
	var off := Vector2(18, 18)
	var vp := get_viewport_rect().size
	if mouse.x + off.x + card.x > vp.x:
		off.x = -18 - card.x
	if mouse.y + off.y + card.y > vp.y:
		off.y = -18 - card.y
	var o := mouse + off
	draw_circle(mouse, 4.0, Color.WHITE)
	draw_rect(Rect2(o, card), Color(0.086, 0.125, 0.165, 0.94))
	var c := o + Vector2(62, 65) * k
	var r := 50.0 * k
	draw_arc(c, r, 0, TAU, 48, Color("#3a4a58"), 1.5, true)
	var wedge := PackedVector2Array([c])
	for i in 13:
		wedge.append(c + _dir(from - beat + 2.0 * beat * i / 12.0) * r)
	draw_colored_polygon(wedge, Color(SogPlot.NO_GO, 0.18))
	# Polar curve: STW on every heading in this wind, scaled so the fastest heading reaches the ring.
	var top := 0.1
	for a in range(0, 181, 5):
		top = maxf(top, sim.boat.polar.speed(a, tws))
	var curve := PackedVector2Array()
	for hh in range(0, 361, 3):
		curve.append(c + _dir(hh) * sim.boat.polar.speed(absf(Geo.wrap180(from - hh)), tws) / top * r)
	draw_polyline(curve, SogPlot.SOG, 2.0, true)
	var hv := _dir(heading)
	var side := Vector2(-hv.y, hv.x)
	var bs := 11.0 * k
	var on_curve := c + hv * stw / top * r
	draw_line(c, on_curve, SogPlot.HEADING, 2.0, true)
	draw_circle(on_curve, 4.0 * k, SogPlot.HEADING)
	draw_colored_polygon(PackedVector2Array([c + hv * bs, c - hv * bs * 0.7 + side * bs * 0.45, c - hv * bs * 0.7 - side * bs * 0.45]), SogPlot.HEADING)
	var wf := _dir(from)
	var ws := Vector2(-wf.y, wf.x)
	var tip := c + wf * (bs + 3.0)
	draw_line(c + wf * (r + 10.0 * k), tip + wf * 8.0, SogPlot.WIND, 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip - wf * 2.0, tip + wf * 9.0 + ws * 4.5, tip + wf * 9.0 - ws * 4.5]), SogPlot.WIND)
	var lines := [
		["TWS %.1f kn" % tws, 15, SogPlot.WIND],
		["from %03d°" % roundi(from), 12, SogPlot.MUTED],
		["TWA %d° %s" % [roundi(absf(twa)), "stbd" if twa >= 0.0 else "port"], 15, SogPlot.HEADING],
		["HDG %03d° from %s" % [roundi(heading) % 360, origin_name], 12, SogPlot.MUTED],
		["STW %.1f kn" % stw, 13, SogPlot.TEXT],
	]
	var x := o.x + 126.0 * k
	var y := o.y + 26.0 * k
	for l in lines:
		draw_string(font, Vector2(x, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs(l[1]), l[2])
		y += Settings.fs(l[1]) + 5.0 * k


func _dir(deg: float) -> Vector2:
	var rad := deg_to_rad(deg)
	return Vector2(sin(rad), -cos(rad))


## Hover text for a waypoint, in a dark box beside the pointer, above the HUD.
func _draw_hint(text: String) -> void:
	var size_px := Settings.fs(14)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x + 16.0
	var h := float(size_px) + 14.0
	var o := mouse + Vector2(18, 14)
	var vp := get_viewport_rect().size
	if o.x + w > vp.x:
		o.x = mouse.x - 18.0 - w
	if o.y + h > vp.y:
		o.y = mouse.y - 14.0 - h
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.086, 0.125, 0.165, 0.94))
	draw_string(font, o + Vector2(8, h - 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(1, 0.9, 0.2))
