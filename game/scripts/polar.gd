class_name Polar
extends RefCounted
## Boat speed through the water (kn) for each true wind angle (rows, 0-180 deg) and true wind speed
## (columns, kn), assuming perfect sail trim. Reads and writes the common tab/semicolon .pol layout.

var twa: PackedFloat64Array
var tws: PackedFloat64Array
var stw: Array[PackedFloat64Array] = []


static func parse(text: String) -> Polar:
	var p := Polar.new()
	var lines := text.replace("\r", "").split("\n", false)
	var header := _numbers(lines[0])
	p.tws = PackedFloat64Array(header)
	for i in range(1, lines.size()):
		var nums := _numbers(lines[i])
		if nums.size() < 2:
			continue
		p.twa.append(nums[0])
		var row := PackedFloat64Array()
		for j in p.tws.size():
			row.append(nums[j + 1] if j + 1 < nums.size() else 0.0)
		p.stw.append(row)
	p._complete()
	return p


## Many published polars cover only part of the circle, often 52-150 deg. Fill the rest:
## a zero row at 0 deg (speed falls linearly toward head to wind), and a 180 deg row at
## 85 % of the last row (a dead run is slower than a broad reach).
func _complete() -> void:
	if twa.is_empty():
		return
	if twa[0] > 0.0:
		var zero := PackedFloat64Array()
		zero.resize(tws.size())
		twa.insert(0, 0.0)
		stw.insert(0, zero)
	if twa[twa.size() - 1] < 180.0:
		var last := stw[stw.size() - 1]
		var run := PackedFloat64Array()
		for v in last:
			run.append(snappedf(v * 0.85, 0.01))
		twa.append(180.0)
		stw.append(run)


## Numbers in a line split on tabs, semicolons, commas or spaces; non-numeric fields are skipped.
static func _numbers(line: String) -> Array:
	var out := []
	for field in line.replace(";", " ").replace("\t", " ").replace(",", " ").split(" ", false):
		if field.is_valid_float():
			out.append(field.to_float())
	return out


func to_text() -> String:
	var lines := PackedStringArray()
	var head := PackedStringArray(["TWA\\TWS"])
	for s in tws:
		head.append(str(s))
	lines.append("\t".join(head))
	for i in twa.size():
		var row := PackedStringArray([str(twa[i])])
		for v in stw[i]:
			row.append("%.2f" % v)
		lines.append("\t".join(row))
	return "\n".join(lines) + "\n"


func is_valid() -> bool:
	return twa.size() >= 2 and tws.size() >= 2 and stw.size() == twa.size()


## Speed through the water in knots. angle is |TWA| in degrees, wind in knots.
## Bilinear between cells; below the first wind column speed falls linearly to zero at 0 kn.
func speed(angle: float, wind: float) -> float:
	angle = clampf(absf(angle), twa[0], twa[twa.size() - 1])
	var i := clampi(twa.bsearch(angle) - 1, 0, twa.size() - 2)
	var fa := (angle - twa[i]) / (twa[i + 1] - twa[i])
	var scale := 1.0
	var w := wind
	if wind < tws[0]:
		scale = maxf(wind, 0.0) / tws[0]
		w = tws[0]
	w = minf(w, tws[tws.size() - 1])
	var j := clampi(tws.bsearch(w) - 1, 0, tws.size() - 2)
	var fw := (w - tws[j]) / (tws[j + 1] - tws[j])
	var low := lerpf(stw[i][j], stw[i][j + 1], fw)
	var high := lerpf(stw[i + 1][j], stw[i + 1][j + 1], fw)
	return lerpf(low, high, fa) * scale


## TWA (deg) with the highest speed toward the wind at a TWS (kn): the best upwind angle.
func beat_angle(wind: float) -> float:
	var best := 45.0
	var best_vmg := -1.0
	for a in range(20, 91):
		var vmg := speed(a, wind) * cos(deg_to_rad(a))
		if vmg > best_vmg:
			best_vmg = vmg
			best = a
	return best
