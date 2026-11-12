class_name WaterPath
## Turning points of the shortest water path between two points, ignoring wind: the places where a
## straight line would cross land and the path has to bend, such as a harbor entrance or a headland.
## The isochrone router routes leg by leg through a gate at each turning point, because its pruning
## (furthest point in each bearing sector from the start) cannot find its own way around land.
##
## The path is found with AStarGrid2D on the leg's depth grid, coarsened to about CELL_M, with water
## shallower than the draft plus MARGIN_M treated as land so the path keeps off the shore. It is then
## pulled tight: each turning point is the furthest path point still in clear sight of the last one.

const CELL_M := 180.0
const MARGIN_M := 6.0  # extra depth beyond the draft the path keeps under it
const SIGHT_STEP_M := 60.0

static var _cache := {}  # "<leg dir>|<min depth>" -> {"astar", "factor", "rows", "cols"}


## Turning points from a to b (not including a or b), in order. Empty when a straight line is clear.
static func turning_points(pkg: LegPackage, a: Vector2, b: Vector2, draft_m: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var min_depth := draft_m + MARGIN_M
	if _clear(pkg, a, b, min_depth):
		return out
	var g := _grid(pkg, min_depth)
	var astar: AStarGrid2D = g["astar"]
	var from := _nearest_open(astar, _cell(pkg, g, a))
	var to := _nearest_open(astar, _cell(pkg, g, b))
	if from.x < 0 or to.x < 0:
		return out
	var cells := astar.get_id_path(from, to)
	if cells.size() < 2:
		return out
	var pts: Array[Vector2] = []
	for c in cells:
		pts.append(_latlon(pkg, g, c))
	pts.append(b)
	# Pull the path tight: from each anchor, the furthest path point still in clear sight becomes the
	# next turning point. A doubling then halving search keeps it to a few sight checks per turn.
	var anchor := a
	var i := 0
	var last := pts.size() - 1
	while i < last:
		if _clear(pkg, anchor, pts[last], min_depth):
			break
		var lo := i  # in sight (or the anchor itself)
		var step := 1
		var hi := mini(i + step, last)
		while hi < last and _clear(pkg, anchor, pts[hi], min_depth):
			lo = hi
			step *= 2
			hi = mini(i + step, last)
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if _clear(pkg, anchor, pts[mid], min_depth):
				lo = mid
			else:
				hi = mid
		var turn := pts[maxi(lo, i + 1)]
		out.append(turn)
		anchor = turn
		i = maxi(lo, i + 1)
	return out


## True when the straight line between two points stays in water at least min_depth deep.
static func _clear(pkg: LegPackage, a: Vector2, b: Vector2, min_depth: float) -> bool:
	var n := int(ceil(Geo.offset_m(a, b).length() / SIGHT_STEP_M))
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / n)
		if pkg.depth_at(q.x, q.y) < min_depth:
			return false
	return true


static func _grid(pkg: LegPackage, min_depth: float) -> Dictionary:
	var g := _grid_entry(pkg, min_depth)
	while not _build_rows(pkg, g, 1e9):
		pass
	return g


## Build the path grid a few milliseconds at a time: true once the grid for this leg and depth is ready.
## Straight-line legs need no grid, so this is true at once for them.
static func prepare(pkg: LegPackage, a: Vector2, b: Vector2, draft_m: float, budget_ms: float) -> bool:
	var min_depth := draft_m + MARGIN_M
	if _clear(pkg, a, b, min_depth):
		return true
	return _build_rows(pkg, _grid_entry(pkg, min_depth), budget_ms)


static func _grid_entry(pkg: LegPackage, min_depth: float) -> Dictionary:
	var key := "%s|%.1f" % [pkg.dir, min_depth]
	if _cache.has(key):
		return _cache[key]
	var h := pkg.depth_header
	var cell_m := float(h["dlat"]) * 111320.0
	var factor := maxi(1, roundi(CELL_M / cell_m))
	var rows := int(h["rows"]) / factor
	var cols := int(h["cols"]) / factor
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var g := {"astar": astar, "factor": factor, "rows": rows, "cols": cols, "min_depth": min_depth, "next_row": 0}
	_cache[key] = g
	return g


## Mark land cells row by row until budget_ms is used; true when every row is done.
static func _build_rows(pkg: LegPackage, g: Dictionary, budget_ms: float) -> bool:
	var until := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var astar: AStarGrid2D = g["astar"]
	var factor: int = g["factor"]
	var cols: int = g["cols"]
	var min_depth: float = g["min_depth"]
	var full_cols := int(pkg.depth_header["cols"])
	var bytes := pkg.depth_bytes
	var r: int = g["next_row"]
	while r < g["rows"] and Time.get_ticks_usec() < until:
		var base := (r * factor + factor / 2) * full_cols
		for c in cols:
			var elev := bytes.decode_s16((base + c * factor + factor / 2) * 2) / 10.0
			if -elev < min_depth:
				astar.set_point_solid(Vector2i(c, r), true)
		r += 1
	g["next_row"] = r
	return r >= g["rows"]


static func _cell(pkg: LegPackage, g: Dictionary, p: Vector2) -> Vector2i:
	var h := pkg.depth_header
	var f: int = g["factor"]
	var r := int((float(h["lat_north"]) - p.x) / float(h["dlat"]) / f)
	var c := int((p.y - float(h["lon_west"])) / float(h["dlon"]) / f)
	return Vector2i(clampi(c, 0, g["cols"] - 1), clampi(r, 0, g["rows"] - 1))


static func _latlon(pkg: LegPackage, g: Dictionary, c: Vector2i) -> Vector2:
	var h := pkg.depth_header
	var f: int = g["factor"]
	return Vector2(float(h["lat_north"]) - (c.y * f + f / 2.0) * float(h["dlat"]),
			float(h["lon_west"]) + (c.x * f + f / 2.0) * float(h["dlon"]))


## The nearest open cell to c within 30 cells, or (-1, -1).
static func _nearest_open(astar: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 31):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Gate lines for the isochrone router between a and b: one per turning point, square to the path and
## reaching across the water on both sides of the turning point, so a route may pass anywhere a boat could. Turning points closer than MERGE_NM to the last kept one or to b are dropped;
## one near a is kept, since a harbor or channel exit is often right after the start.
const GATE_NM := 4.0  # longest reach of a gate line each way from its turning point
const MERGE_NM := 1.0


static var _gate_cache := {}  # "<leg dir>|<a>|<b>|<draft>" -> gates


static func gates(pkg: LegPackage, a: Vector2, b: Vector2, draft_m: float) -> Array:
	var key := "%s|%s|%s|%.2f" % [pkg.dir, a, b, draft_m]
	if not _gate_cache.has(key):
		_gate_cache[key] = _gates(pkg, a, b, draft_m)
	return _gate_cache[key].duplicate(true)


static func _gates(pkg: LegPackage, a: Vector2, b: Vector2, draft_m: float) -> Array:
	var kept: Array[Vector2] = []
	for p in turning_points(pkg, a, b, draft_m):
		if Geo.distance_nm(p, b) < MERGE_NM:
			continue
		if kept.is_empty() or Geo.distance_nm(p, kept[kept.size() - 1]) >= MERGE_NM:
			kept.append(p)
	var out := []
	for i in kept.size():
		var prev: Vector2 = a if i == 0 else kept[i - 1]
		var next: Vector2 = b if i == kept.size() - 1 else kept[i + 1]
		var dir := (Geo.offset_m(prev, kept[i]).normalized() + Geo.offset_m(kept[i], next).normalized()).normalized()
		var side := Vector2(-dir.y, dir.x)  # east/north meters, square to the path
		# Extend each way until the water gets too shallow: a channel gate spans the channel, a headland
		# gate runs out to sea.
		var min_depth := draft_m + MARGIN_M
		var inner := _walk(pkg, kept[i], -side, min_depth)
		var outer := _walk(pkg, kept[i], side, min_depth)
		out.append([inner, outer])
	return out


## The last point in water at least min_depth deep walking from p along dir (east/north unit vector),
## up to GATE_NM.
static func _walk(pkg: LegPackage, p: Vector2, dir: Vector2, min_depth: float) -> Vector2:
	var last := p
	var steps := int(GATE_NM * Geo.M_PER_NM / 100.0)
	for k in range(1, steps + 1):
		var q := Geo.move(p.x, p.y, dir * 100.0 * k, 1.0)
		if pkg.depth_at(q.x, q.y) < min_depth:
			break
		last = q
	return last

