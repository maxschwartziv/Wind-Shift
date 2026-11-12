class_name WindPalette
## Wind speed colors shared by the wind particles, the wind arrows and the legend.

## Lower edge of each band in knots; the last band has no upper edge.
const EDGES_KN: Array[float] = [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 25.0]
const COLORS: Array[Color] = [
	Color("#6fa8ff"),  # 0-4 kn
	Color("#5fd3c6"),  # 4-8
	Color("#8be06a"),  # 8-12
	Color("#f2e05a"),  # 12-16
	Color("#f5a442"),  # 16-20
	Color("#f0603a"),  # 20-25
	Color("#d24fd0"),  # 25+
]


static func color(kn: float) -> Color:
	var c := COLORS[0]
	for i in EDGES_KN.size():
		if kn >= EDGES_KN[i]:
			c = COLORS[i]
	return c


static func label(i: int) -> String:
	if i == EDGES_KN.size() - 1:
		return "%d+" % int(EDGES_KN[i])
	return "%d-%d" % [int(EDGES_KN[i]), int(EDGES_KN[i + 1])]
