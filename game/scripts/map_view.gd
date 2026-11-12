class_name MapView
extends Node2D
## Imagery tiles and the shallow-water overlay. The level that suits the zoom draws on top of the coarser
## levels, which cover a wider backdrop box, so the map fills the screen past the leg's bounds.

const LEVELS := [8, 10, 12]

var pkg: LegPackage
var camera: Camera2D
var _layers := {}
var _depth: Sprite2D


func setup(p: LegPackage, cam: Camera2D) -> void:
	pkg = p
	camera = cam
	var tiles := {}
	var path := pkg.dir + "/tiles.json"
	if FileAccess.file_exists(path):
		tiles = JSON.parse_string(FileAccess.get_file_as_string(path))
	for z in LEVELS:
		var wide: bool = tiles.has("backdrop") and z <= int(tiles.get("backdrop_z_max", 0))
		_layers[z] = _build_layer(z, tiles["backdrop"] if wide else pkg.info["bounds"])
	_build_depth()


func _tile_xy(lat: float, lon: float, z: int) -> Vector2i:
	var n := pow(2.0, z)
	var x := int((lon + 180.0) / 360.0 * n)
	var y := int((1.0 - asinh(tan(deg_to_rad(lat))) / PI) / 2.0 * n)
	return Vector2i(x, y)


func _build_layer(z: int, b: Dictionary) -> Node2D:
	var layer := Node2D.new()
	add_child(layer)
	var a := _tile_xy(b["lat_max"], b["lon_min"], z)
	var c := _tile_xy(b["lat_min"], b["lon_max"], z)
	var scale_f := pow(2.0, Geo.ZOOM - z)
	for x in range(a.x, c.x + 1):
		for y in range(a.y, c.y + 1):
			var path := "%s/tiles/%d/%d/%d.jpg" % [pkg.dir, z, x, y]
			if not ResourceLoader.exists(path):
				continue
			var s := Sprite2D.new()
			s.texture = load(path)
			s.centered = false
			s.scale = Vector2.ONE * scale_f
			s.position = Vector2(x, y) * 256.0 * scale_f - Geo.origin
			layer.add_child(s)
	return layer


func _build_depth() -> void:
	var h := pkg.depth_header
	var cols := int(h["cols"])
	var rows := int(h["rows"])
	var img := Image.create_from_data(cols, rows, false, Image.FORMAT_RG8, pkg.depth_bytes)
	var b: Dictionary = pkg.info["bounds"]
	var nw := Geo.to_world(b["lat_max"], b["lon_min"])
	var se := Geo.to_world(b["lat_min"], b["lon_max"])
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	_depth = Sprite2D.new()
	_depth.texture = ImageTexture.create_from_image(white)
	_depth.centered = false
	_depth.position = nw
	_depth.scale = se - nw
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/depth.gdshader")
	mat.set_shader_parameter("depth_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("world_origin", Geo.origin)
	mat.set_shader_parameter("rect_pos", nw)
	mat.set_shader_parameter("rect_size", se - nw)
	mat.set_shader_parameter("lat_north", float(h["lat_north"]))
	mat.set_shader_parameter("lon_west", float(h["lon_west"]))
	mat.set_shader_parameter("dlat", float(h["dlat"]))
	mat.set_shader_parameter("dlon", float(h["dlon"]))
	mat.set_shader_parameter("grid_size", Vector2(cols, rows))
	_depth.material = mat
	add_child(_depth)


func set_draft(d: float) -> void:
	(_depth.material as ShaderMaterial).set_shader_parameter("draft", d)


## Depth map: shade the water by depth with contour lines, or show only the shallow-water warning.
func set_depth_map(on: bool) -> void:
	(_depth.material as ShaderMaterial).set_shader_parameter("show_map", on)


func _process(_delta: float) -> void:
	var zoom := camera.zoom.x
	var show := 12 if zoom > 0.35 else (10 if zoom > 0.09 else 8)
	for z in LEVELS:
		_layers[z].visible = z <= show
