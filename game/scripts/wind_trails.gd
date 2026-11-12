class_name WindTrails
extends Node2D
## Long wind streaks without particle trails, which the Compatibility renderer lacks: the particles draw
## into an offscreen buffer that is never cleared, and a subtract pass fades it a little every frame,
## so each particle leaves a tail behind it. The buffer is shown at the camera view, and it clears when
## the view jumps or zooms.

const FADE := 0.015  # opacity taken off every trail pixel each frame
const CLEAR_MOVE_PX := 12.0  # smaller moves, such as following the boat, smear the trails slightly

var particles: WindParticles
var camera: Camera2D
var _vp: SubViewport
var _cam: Camera2D
var _sprite: Sprite2D
var _fade: ColorRect
var _last_pos := Vector2.INF
var _last_zoom := Vector2.ZERO


func setup(p: WindParticles, main_cam: Camera2D) -> void:
	particles = p
	camera = main_cam
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_vp.world_2d = World2D.new()
	add_child(_vp)
	_cam = Camera2D.new()
	_vp.add_child(_cam)
	_vp.add_child(particles)
	# Layer -1 draws before the particles each frame, so it fades old dots and leaves new ones bright.
	var layer := CanvasLayer.new()
	layer.layer = -1
	_vp.add_child(layer)
	_fade = ColorRect.new()
	# Subtract blending takes color times alpha off both color and opacity, so equal channels of
	# sqrt(FADE) remove FADE from each and keep the premultiplied color in step with its opacity.
	var k := sqrt(FADE)
	_fade.color = Color(k, k, k, k)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	_fade.material = mat
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	_sprite = Sprite2D.new()
	_sprite.texture = _vp.get_texture()
	var show := CanvasItemMaterial.new()
	show.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_sprite.material = show
	add_child(_sprite)


func _process(_delta: float) -> void:
	var size := Vector2i(get_viewport_rect().size)
	if _vp.size != size:
		_vp.size = size
		_clear()
	var center := camera.get_screen_center_position()
	var moved_px := (center - _last_pos).length() * camera.zoom.x if _last_pos.is_finite() else INF
	if moved_px > CLEAR_MOVE_PX or camera.zoom != _last_zoom:
		_clear()
	_last_pos = center
	_last_zoom = camera.zoom
	_cam.position = center
	_cam.zoom = camera.zoom
	_sprite.position = center
	_sprite.scale = Vector2.ONE / camera.zoom


func _clear() -> void:
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
