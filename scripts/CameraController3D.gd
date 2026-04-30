extends RefCounted

const CAMERA_EDGE_SCROLL_ENABLED := true
const CAMERA_EDGE_THRESHOLD_PX := 24.0
const CAMERA_EDGE_SCROLL_SPEED := 20.0

const CAMERA_DRAG_ON_LEFT_HOLD_ENABLED := true
const CAMERA_DRAG_START_THRESHOLD_PX := 8.0
const CAMERA_DRAG_LONG_PRESS_MS := 180
const CAMERA_DRAG_PAN_SENSITIVITY := 0.035

const CAMERA_ROTATE_ON_RIGHT_HOLD_ENABLED := true
const CAMERA_ROTATE_START_THRESHOLD_PX := 6.0
const CAMERA_ROTATE_LONG_PRESS_MS := 120
const CAMERA_ROTATE_YAW_SENSITIVITY := 0.22
const CAMERA_ROTATE_PITCH_SENSITIVITY := 0.18

const CAMERA_DISTANCE_DEFAULT := 28.0
const CAMERA_DISTANCE_MIN := 14.0
const CAMERA_DISTANCE_MAX := 44.0
const CAMERA_ZOOM_STEP := 2.0
const CAMERA_PITCH_MIN_DEG := 35.0
const CAMERA_PITCH_MAX_DEG := 80.0
const CAMERA_DEFAULT_PITCH_DEG := 60.0

var _camera: Camera3D
var _target_pos := Vector3.ZERO
var _camera_yaw_deg := 0.0
var _camera_pitch_deg := CAMERA_DEFAULT_PITCH_DEG
var _camera_distance := CAMERA_DISTANCE_DEFAULT
var _map_min := Vector2(-40.0, -40.0)
var _map_max := Vector2(40.0, 40.0)

var _is_left_pressed := false
var _is_camera_dragging := false
var _left_press_start := Vector2.ZERO
var _left_press_latest := Vector2.ZERO
var _left_press_started_at_ms := 0

var _is_right_pressed := false
var _is_camera_rotating := false
var _right_press_start := Vector2.ZERO
var _right_press_latest := Vector2.ZERO
var _right_press_started_at_ms := 0

func setup(camera: Camera3D, map_min: Vector2, map_max: Vector2) -> void:
	_camera = camera
	_map_min = map_min
	_map_max = map_max
	_apply_camera_transform()

func set_map_bounds(map_min: Vector2, map_max: Vector2) -> void:
	_map_min = map_min
	_map_max = map_max
	_clamp_target_pos()

func handle_input(event: InputEvent) -> bool:
	var changed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_mouse_down(event.position)
		else:
			_on_left_mouse_up()
			changed = true
		return changed

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_on_right_mouse_down(event.position)
		else:
			_on_right_mouse_up()
			changed = true
		return changed

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_camera_zoom(-CAMERA_ZOOM_STEP)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_camera_zoom(CAMERA_ZOOM_STEP)
			return true

	if event is InputEventMouseMotion:
		if _on_left_mouse_motion(event):
			changed = true
		if _on_right_mouse_motion(event):
			changed = true
	return changed

func update_frame(delta: float, viewport_rect: Rect2, mouse_pos: Vector2) -> void:
	_handle_edge_scroll(delta, viewport_rect, mouse_pos)
	_apply_camera_transform()

func get_mode_text() -> String:
	if _is_camera_dragging:
		return "左键平移中"
	if _is_camera_rotating:
		return "右键旋转中"
	return "空闲"

func build_status_text() -> String:
	return "3D相机测试 | 模式:%s | yaw=%.1f° pitch=%.1f° dist=%.1f\n规则: 仅允许上方向下观察，pitch限制在[%.0f°, %.0f°]，滚轮缩放限制在[%.0f, %.0f]" % [
		get_mode_text(),
		_camera_yaw_deg,
		_camera_pitch_deg,
		_camera_distance,
		CAMERA_PITCH_MIN_DEG,
		CAMERA_PITCH_MAX_DEG,
		CAMERA_DISTANCE_MIN,
		CAMERA_DISTANCE_MAX
	]

func _on_left_mouse_down(screen_pos: Vector2) -> void:
	_is_left_pressed = true
	_is_camera_dragging = false
	_left_press_start = screen_pos
	_left_press_latest = screen_pos
	_left_press_started_at_ms = Time.get_ticks_msec()

func _on_left_mouse_up() -> void:
	_is_left_pressed = false
	_is_camera_dragging = false

func _on_right_mouse_down(screen_pos: Vector2) -> void:
	_is_right_pressed = true
	_is_camera_rotating = false
	_right_press_start = screen_pos
	_right_press_latest = screen_pos
	_right_press_started_at_ms = Time.get_ticks_msec()

func _on_right_mouse_up() -> void:
	_is_right_pressed = false
	_is_camera_rotating = false

func _on_left_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _is_left_pressed or not CAMERA_DRAG_ON_LEFT_HOLD_ENABLED:
		return false
	if _is_camera_rotating:
		return false

	_left_press_latest = event.position
	if not _is_camera_dragging:
		var hold_ms := Time.get_ticks_msec() - _left_press_started_at_ms
		var drag_distance := _left_press_latest.distance_to(_left_press_start)
		if hold_ms < CAMERA_DRAG_LONG_PRESS_MS and drag_distance < CAMERA_DRAG_START_THRESHOLD_PX:
			return false
		_is_camera_dragging = true

	_apply_camera_pan(event.relative)
	return true

func _on_right_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _is_right_pressed or not CAMERA_ROTATE_ON_RIGHT_HOLD_ENABLED:
		return false
	if _is_camera_dragging:
		return false

	_right_press_latest = event.position
	if not _is_camera_rotating:
		var hold_ms := Time.get_ticks_msec() - _right_press_started_at_ms
		var drag_distance := _right_press_latest.distance_to(_right_press_start)
		if hold_ms < CAMERA_ROTATE_LONG_PRESS_MS and drag_distance < CAMERA_ROTATE_START_THRESHOLD_PX:
			return false
		_is_camera_rotating = true

	_camera_yaw_deg = wrapf(_camera_yaw_deg + event.relative.x * CAMERA_ROTATE_YAW_SENSITIVITY, -180.0, 180.0)
	_camera_pitch_deg = clamp(
		_camera_pitch_deg - event.relative.y * CAMERA_ROTATE_PITCH_SENSITIVITY,
		CAMERA_PITCH_MIN_DEG,
		CAMERA_PITCH_MAX_DEG
	)
	return true

func _handle_edge_scroll(delta: float, viewport_rect: Rect2, mouse_pos: Vector2) -> void:
	if not CAMERA_EDGE_SCROLL_ENABLED:
		return
	if _is_camera_dragging or _is_camera_rotating:
		return
	if not viewport_rect.has_point(mouse_pos):
		return

	var input_dir := Vector2.ZERO
	if mouse_pos.x <= CAMERA_EDGE_THRESHOLD_PX:
		input_dir.x -= 1.0
	elif mouse_pos.x >= viewport_rect.size.x - CAMERA_EDGE_THRESHOLD_PX:
		input_dir.x += 1.0
	if mouse_pos.y <= CAMERA_EDGE_THRESHOLD_PX:
		input_dir.y -= 1.0
	elif mouse_pos.y >= viewport_rect.size.y - CAMERA_EDGE_THRESHOLD_PX:
		input_dir.y += 1.0
	if input_dir == Vector2.ZERO:
		return

	var world_dir := _screen_dir_to_world(input_dir.normalized())
	_target_pos += world_dir * CAMERA_EDGE_SCROLL_SPEED * delta
	_clamp_target_pos()

func _apply_camera_pan(screen_delta: Vector2) -> void:
	var pan_dir := _screen_dir_to_world(screen_delta)
	_target_pos -= pan_dir * CAMERA_DRAG_PAN_SENSITIVITY
	_clamp_target_pos()

func _apply_camera_zoom(delta_distance: float) -> void:
	_camera_distance = clamp(_camera_distance + delta_distance, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)

func _screen_dir_to_world(screen_dir: Vector2) -> Vector3:
	var yaw_rad := deg_to_rad(_camera_yaw_deg)
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	var forward := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))
	return right * screen_dir.x + forward * screen_dir.y

func _apply_camera_transform() -> void:
	if _camera == null:
		return
	var yaw_rad := deg_to_rad(_camera_yaw_deg)
	var pitch_rad := deg_to_rad(_camera_pitch_deg)
	var horiz := cos(pitch_rad) * _camera_distance
	var vertical := sin(pitch_rad) * _camera_distance
	var orbit := Vector3(sin(yaw_rad) * horiz, vertical, cos(yaw_rad) * horiz)
	_camera.global_position = _target_pos + orbit
	_camera.look_at(_target_pos, Vector3.UP)

func _clamp_target_pos() -> void:
	_target_pos.x = clamp(_target_pos.x, _map_min.x, _map_max.x)
	_target_pos.z = clamp(_target_pos.z, _map_min.y, _map_max.y)
	_target_pos.y = 0.0
