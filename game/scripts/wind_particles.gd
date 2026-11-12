class_name WindParticles
extends GPUParticles2D
## Wind shown as drifting particles over the camera view, above a smooth wind speed color field.
## WindTrails draws them into a fading buffer so each one leaves a tail. Both use the same wind as the wind arrows: the source and time chosen for the wind map.

const COUNT := 9000
const LIFETIME_S := 3.0

var pkg: LegPackage
var camera: Camera2D
## Smooth color field under the particles; add it to the scene below this node.
var field: Polygon2D
var _mat: ShaderMaterial
var _field_mat: ShaderMaterial
var _wind_img: Image
var _wind_tex: ImageTexture
var _grid: VectorGrid
var _bounds := Rect2()  # the leg's area in world units


func setup(p: LegPackage, cam: Camera2D) -> void:
	pkg = p
	camera = cam
	amount = COUNT
	lifetime = LIFETIME_S
	preprocess = LIFETIME_S
	local_coords = false
	visibility_rect = Rect2(-1e7, -1e7, 2e7, 2e7)
	texture = _trail_texture()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/wind_particles.gdshader")
	process_material = _mat
	_field_mat = ShaderMaterial.new()
	_field_mat.shader = load("res://shaders/wind_field.gdshader")
	field = Polygon2D.new()
	field.material = _field_mat
	var b: Dictionary = pkg.info["bounds"]
	var nw := Geo.to_world(b["lat_max"], b["lon_min"])
	var se := Geo.to_world(b["lat_min"], b["lon_max"])
	field.polygon = PackedVector2Array([nw, Vector2(se.x, nw.y), se, Vector2(nw.x, se.y)])
	_bounds = Rect2(nw, se - nw)

	_param("world_origin", Geo.origin)
	_param("bin_colors", PackedColorArray(WindPalette.COLORS))
	_param("bin_edges", PackedFloat32Array(WindPalette.EDGES_KN))
	var h := pkg.depth_header
	var depth_img := Image.create_from_data(int(h["cols"]), int(h["rows"]), false, Image.FORMAT_RG8, pkg.depth_bytes)
	_param("depth_tex", ImageTexture.create_from_image(depth_img))
	_param("depth_size", Vector2(float(h["cols"]), float(h["rows"])))
	_param("d_lat_north", float(h["lat_north"]))
	_param("d_lon_west", float(h["lon_west"]))
	_param("d_dlat", float(h["dlat"]))
	_param("d_dlon", float(h["dlon"]))


func _trail_texture() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _param(param: StringName, value: Variant) -> void:
	_mat.set_shader_parameter(param, value)
	_field_mat.set_shader_parameter(param, value)


## Show the actual wind (m/s east, north) inside a circle around the boat; on false hides it.
func set_observation(on: bool, center_world: Vector2, radius_world: float, wind: Vector2) -> void:
	_param("obs_on", 1.0 if on else 0.0)
	_param("obs_center", center_world)
	_param("obs_radius", radius_world)
	_param("obs_wind", wind)


## Refresh the wind texture for grid g at time t (seconds after leg start) and the spawn area.
func update_wind(g: VectorGrid, t: float) -> void:
	if g != _grid:
		_grid = g
		_wind_img = Image.create(g.cols, g.rows, false, Image.FORMAT_RGF)
		_wind_tex = ImageTexture.create_from_image(_wind_img)
		_param("wind_tex", _wind_tex)
		_param("wind_size", Vector2(g.cols, g.rows))
		_param("lat_north", g.lat_north)
		_param("lon_west", g.lon_west)
		_param("dlat", g.dlat)
		_param("dlon", g.dlon)
	for r in g.rows:
		for c in g.cols:
			var v := g.sample(g.lat_north - r * g.dlat, g.lon_west + c * g.dlon, t)
			_wind_img.set_pixel(c, r, Color(v.x, v.y, 0.0))
	_wind_tex.update(_wind_img)
	# Spawn only where the camera view overlaps the leg's area; nothing is drawn outside the map.
	var view_size := get_viewport_rect().size / camera.zoom
	var view := Rect2(camera.get_screen_center_position() - view_size / 2.0, view_size)
	var area := view.intersection(_bounds)
	emitting = visible and area.has_area()
	_mat.set_shader_parameter("rect_pos", area.position)
	_mat.set_shader_parameter("rect_size", area.size)
	_mat.set_shader_parameter("bounds_pos", _bounds.position)
	_mat.set_shader_parameter("bounds_size", _bounds.size)
	_mat.set_shader_parameter("world_per_px", 1.0 / camera.zoom.x)
