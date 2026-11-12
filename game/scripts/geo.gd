class_name Geo
## Web Mercator projection and small-distance geometry.
## World units are zoom-12 tile pixels, shifted so the leg's north-west corner is near (0, 0).

const ZOOM := 12
const WORLD := 256.0 * 4096.0
const M_PER_DEG_LAT := 111320.0
const M_PER_NM := 1852.0
const MS_PER_KN := 0.514444

static var origin := Vector2.ZERO


static func set_origin(lat: float, lon: float) -> void:
	origin = Vector2.ZERO
	origin = to_world(lat, lon)


static func to_world(lat: float, lon: float) -> Vector2:
	var x := (lon + 180.0) / 360.0 * WORLD
	var y := (1.0 - asinh(tan(deg_to_rad(lat))) / PI) / 2.0 * WORLD
	return Vector2(x, y) - origin


static func to_latlon(p: Vector2) -> Vector2:
	var w := p + origin
	var lon := w.x / WORLD * 360.0 - 180.0
	var lat := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * w.y / WORLD))))
	return Vector2(lat, lon)


## Move a lat/lon point by a velocity (east, north in m/s) for dt seconds.
static func move(lat: float, lon: float, v: Vector2, dt: float) -> Vector2:
	var nlat := lat + v.y * dt / M_PER_DEG_LAT
	var nlon := lon + v.x * dt / (M_PER_DEG_LAT * cos(deg_to_rad(lat)))
	return Vector2(nlat, nlon)


## Local east/north offset in meters from a to b (each Vector2(lat, lon)).
static func offset_m(a: Vector2, b: Vector2) -> Vector2:
	return Vector2((b.y - a.y) * M_PER_DEG_LAT * cos(deg_to_rad(a.x)), (b.x - a.x) * M_PER_DEG_LAT)


static func distance_nm(a: Vector2, b: Vector2) -> float:
	return offset_m(a, b).length() / M_PER_NM


## Unit vector (east, north) for a compass heading in degrees.
static func heading_vec(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), cos(r))


## Compass bearing in degrees of an (east, north) vector.
static func bearing(v: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(v.x, v.y)), 360.0)


static func wrap180(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0


## Nearest point on segment a-b to p, all Vector2(lat, lon), measured in local meters around p.
static func nearest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var pa := offset_m(p, a)
	var pb := offset_m(p, b)
	var ab := pb - pa
	var t := clampf(-pa.dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return a.lerp(b, t)


## Fraction f in [0, 1] along p0-p1 where it crosses segment a-b, or -1. Points are Vector2(lat, lon).
static func crossing(p0: Vector2, p1: Vector2, a: Vector2, b: Vector2) -> float:
	var r := p1 - p0
	var s := b - a
	var den := r.x * s.y - r.y * s.x
	if absf(den) < 1e-15:
		return -1.0
	var q := a - p0
	var t := (q.x * s.y - q.y * s.x) / den
	var u := (q.x * r.y - q.y * r.x) / den
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
		return t
	return -1.0
