extends Node2D

# 六边形网格基础参数：当前用于相机操作专项验证。
const HEX_SIZE := 30.0
const GRID_RADIUS := 80
const ORIGIN := Vector2(640, 360)

# 边缘滚屏参数：热区、开关与速度可直接在此调手感。
const CAMERA_EDGE_SCROLL_ENABLED := true
const CAMERA_EDGE_THRESHOLD_PX := 32.0
const CAMERA_EDGE_SCROLL_SPEED := 280.0

# 拖拽参数：支持长按触发，也支持快速短拖触发。
const CAMERA_DRAG_ON_EMPTY_LEFT_HOLD_ENABLED := true
const CAMERA_DRAG_START_THRESHOLD_PX := 8.0
const CAMERA_DRAG_LONG_PRESS_MS := 180

enum InteractionState {
	IDLE,
	CAMERA_DRAGGING
}

var _state: InteractionState = InteractionState.IDLE
var _camera_offset := Vector2.ZERO
var _min_camera_offset := Vector2.ZERO
var _max_camera_offset := Vector2.ZERO
var _status_label: Label
var _landmarks: Array[Vector2i] = []

var _is_left_pressed := false
var _is_camera_dragging := false
var _left_press_screen_pos := Vector2.ZERO
var _left_press_latest_pos := Vector2.ZERO
var _left_press_started_at_ms := 0

# 初始化：生成参照物、计算相机边界、刷新首帧。
func _ready() -> void:
	_generate_landmarks()
	_recompute_camera_bounds()
	_update_status("相机测试模式：超大地图 + 随机参照物，支持边缘滚屏 + 长按拖拽。")
	queue_redraw()

func _process(delta: float) -> void:
	_handle_edge_scroll(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_mouse_down(event.position)
		else:
			_on_left_mouse_up()
		return

	if event is InputEventMouseMotion:
		_on_left_mouse_motion(event)

func _draw() -> void:
	_draw_grid()
	_draw_landmarks()

# 记录按下时刻与位置，用于后续判断是否进入拖拽态。
func _on_left_mouse_down(screen_pos: Vector2) -> void:
	_is_left_pressed = true
	_is_camera_dragging = false
	_left_press_screen_pos = screen_pos
	_left_press_latest_pos = screen_pos
	_left_press_started_at_ms = Time.get_ticks_msec()

# 左键释放时统一退出拖拽态，恢复到空闲输入态。
func _on_left_mouse_up() -> void:
	if not _is_left_pressed:
		return
	_is_left_pressed = false
	_is_camera_dragging = false
	_state = InteractionState.IDLE
	_update_status("相机测试模式：仅保留网格和相机操作（边缘滚屏 + 长按拖拽）。")

func _on_left_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_left_pressed:
		return
	if not CAMERA_DRAG_ON_EMPTY_LEFT_HOLD_ENABLED:
		return
	_left_press_latest_pos = event.position

	# 触发口径：
	# - 传统长按：达到长按阈值后进入拖拽
	# - 快速短拖：位移先达到阈值也可立即进入拖拽，改善“左击-拖动-松手”手感
	if not _is_camera_dragging:
		var hold_ms := Time.get_ticks_msec() - _left_press_started_at_ms
		var drag_distance := _left_press_latest_pos.distance_to(_left_press_screen_pos)
		var reach_long_press := hold_ms >= CAMERA_DRAG_LONG_PRESS_MS
		var reach_drag_distance := drag_distance >= CAMERA_DRAG_START_THRESHOLD_PX
		if not reach_long_press and not reach_drag_distance:
			return
		_is_camera_dragging = true
		_state = InteractionState.CAMERA_DRAGGING
		_update_status("拖拽中：边缘滚屏已暂停。")
		# 首帧进入拖拽时补偿按下点到当前位置的位移，避免快速拖动出现“丢帧感”。
		_apply_camera_offset_delta(_left_press_latest_pos - _left_press_screen_pos)
		queue_redraw()
		return

	_apply_camera_offset_delta(event.relative)
	queue_redraw()

func _handle_edge_scroll(delta: float) -> void:
	if not CAMERA_EDGE_SCROLL_ENABLED:
		return
	# 拖拽期间暂停边缘滚屏，避免两套相机输入叠加。
	if _is_camera_dragging or _state == InteractionState.CAMERA_DRAGGING:
		return

	var viewport_rect := get_viewport_rect()
	var mouse_pos := get_viewport().get_mouse_position()
	if not viewport_rect.has_point(mouse_pos):
		return

	var scroll_dir := Vector2.ZERO
	if mouse_pos.x <= CAMERA_EDGE_THRESHOLD_PX:
		scroll_dir.x += 1.0
	elif mouse_pos.x >= viewport_rect.size.x - CAMERA_EDGE_THRESHOLD_PX:
		scroll_dir.x -= 1.0

	if mouse_pos.y <= CAMERA_EDGE_THRESHOLD_PX:
		scroll_dir.y += 1.0
	elif mouse_pos.y >= viewport_rect.size.y - CAMERA_EDGE_THRESHOLD_PX:
		scroll_dir.y -= 1.0

	if scroll_dir == Vector2.ZERO:
		return

	# 对角方向统一归一化，防止斜向速度大于水平/垂直速度。
	_apply_camera_offset_delta(scroll_dir.normalized() * CAMERA_EDGE_SCROLL_SPEED * delta)
	queue_redraw()

# 相机位移统一入口：所有位移都经过边界夹取，防止滚出可玩区域。
func _apply_camera_offset_delta(delta: Vector2) -> void:
	_camera_offset += delta
	_camera_offset.x = clamp(_camera_offset.x, _min_camera_offset.x, _max_camera_offset.x)
	_camera_offset.y = clamp(_camera_offset.y, _min_camera_offset.y, _max_camera_offset.y)

# 根据当前网格范围反推相机可移动边界。
func _recompute_camera_bounds() -> void:
	var viewport_size := get_viewport_rect().size
	var min_world := Vector2(999999, 999999)
	var max_world := Vector2(-999999, -999999)
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var p := _axial_to_pixel_no_offset(Vector2i(q, r))
			min_world.x = min(min_world.x, p.x)
			min_world.y = min(min_world.y, p.y)
			max_world.x = max(max_world.x, p.x)
			max_world.y = max(max_world.y, p.y)

	var margin := HEX_SIZE * 2.0
	var raw_min := Vector2(
		viewport_size.x - (max_world.x + margin),
		viewport_size.y - (max_world.y + margin)
	)
	var raw_max := Vector2(
		-(min_world.x - margin),
		-(min_world.y - margin)
	)

	_min_camera_offset = Vector2(min(raw_min.x, raw_max.x), min(raw_min.y, raw_max.y))
	_max_camera_offset = Vector2(max(raw_min.x, raw_max.x), max(raw_min.y, raw_max.y))

	# 边界重算后立即做一次夹取，避免历史偏移落在新边界之外。
	_apply_camera_offset_delta(Vector2.ZERO)

func _draw_grid() -> void:
	# 仅绘制视口附近网格，避免超大地图全量绘制导致卡顿。
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size).grow(HEX_SIZE * 2.0)
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var center := _axial_to_pixel(Vector2i(q, r))
			if not viewport_rect.has_point(center):
				continue
			var points := PackedVector2Array()
			for i in range(6):
				var angle := PI / 180.0 * (60.0 * i - 30.0)
				points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.35, 0.35, 0.35), 1.5)

# 绘制随机参照物，便于肉眼判断相机移动是否平滑/正确。
func _draw_landmarks() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size).grow(HEX_SIZE * 2.0)
	for cell in _landmarks:
		var center := _axial_to_pixel(cell)
		if not viewport_rect.has_point(center):
			continue
		draw_circle(center, HEX_SIZE * 0.24, Color(1.0, 0.75, 0.2, 0.9))
		draw_arc(center, HEX_SIZE * 0.42, 0.0, TAU, 16, Color(0.2, 0.2, 0.2, 0.8), 1.4)

func _axial_to_pixel(cell: Vector2i) -> Vector2:
	return _axial_to_pixel_no_offset(cell) + _camera_offset

func _axial_to_pixel_no_offset(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + cell.y * 0.5)
	var y := HEX_SIZE * 1.5 * cell.y
	return ORIGIN + Vector2(x, y)

# 固定随机种子，保证每次启动参照物分布一致，便于回归测试。
func _generate_landmarks() -> void:
	_landmarks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260430
	var target_count := 180
	var occupied := {}
	while _landmarks.size() < target_count:
		var q := rng.randi_range(-GRID_RADIUS, GRID_RADIUS)
		var r := rng.randi_range(-GRID_RADIUS, GRID_RADIUS)
		var s := -q - r
		if abs(s) > GRID_RADIUS:
			continue
		var key := "%d,%d" % [q, r]
		if occupied.has(key):
			continue
		occupied[key] = true
		_landmarks.append(Vector2i(q, r))

func _update_status(text: String) -> void:
	if _status_label == null:
		_status_label = get_node_or_null("HelloLabel")
	if _status_label != null:
		_status_label.text = text
