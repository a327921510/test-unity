extends Node2D

const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const CITY_DATA_SCRIPT := preload("res://scripts/domain/City.gd")
const HEX_GRID_RULES_SCRIPT := preload("res://scripts/map/HexGridRules.gd")
const TURN_MANAGER_SCRIPT := preload("res://scripts/core/TurnManager.gd")
const DEBUG_PANEL_SCRIPT := preload("res://scripts/ui/DebugPanel.gd")

const HEX_SIZE := 30.0
const GRID_RADIUS := 4
const ORIGIN := Vector2(640, 360)
const EDGE_THRESHOLD_PX := 24.0
const EDGE_SCROLL_SPEED := 380.0
const UNIT_STEP_TIME_SEC := 0.12
const DRAG_START_THRESHOLD_PX := 8.0
const DRAG_LONG_PRESS_MS := 180

enum InteractionState {
	IDLE,
	CITY_SELECTED,
	UNIT_SELECTED,
	UNIT_MOVE_TARGETING,
	UNIT_MOVING
}

var _state: InteractionState = InteractionState.IDLE
var _grid_rules
var _turn_manager
var _city_alpha
var _unit_a
var _unit_b
var _unit_transport
var _unit_list: Array = []
var _selected_city = null
var _selected_unit = null
var _reachable_tiles: Array[Vector2i] = []
var _move_path: Array[Vector2i] = []
var _move_step_timer := 0.0
var _camera_offset := Vector2.ZERO
var _min_camera_offset := Vector2.ZERO
var _max_camera_offset := Vector2.ZERO
var _status_label: Label
var _context_label: Label
var _debug_panel
var _is_left_pressed := false
var _left_press_started_on_empty := false
var _is_camera_dragging := false
var _left_press_screen_pos := Vector2.ZERO
var _left_press_latest_pos := Vector2.ZERO
var _left_press_started_at_ms := 0

func _ready() -> void:
	_initialize_demo()
	_build_debug_panel()
	_build_interaction_panel()
	_recompute_camera_bounds()
	_update_status("鼠标边缘滚屏已启用。左键选择城市/部队，右键或Esc取消。选中部队后点击可达格执行逐格移动。")
	queue_redraw()

func _process(delta: float) -> void:
	_handle_edge_scroll(delta)
	_process_unit_moving(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_mouse_down(event.position)
			else:
				_on_left_mouse_up(event.position)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_clear_selection("已取消选择。")
			queue_redraw()
			return

	if event is InputEventMouseMotion:
		_on_left_mouse_motion(event)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_clear_selection("已取消选择。")
			KEY_M:
				if _selected_unit != null:
					_enter_move_targeting()
			KEY_SPACE:
				_turn_manager.end_turn()
				_update_status("结束回合，当前势力=%s，回合=%d" % [_turn_manager.current_faction_id(), _turn_manager.current_turn_count()])
			KEY_R:
				_initialize_demo()
				_clear_selection("已重置演示状态。")
			_:
				return
		queue_redraw()

func _draw() -> void:
	_draw_grid()
	_draw_city_block_preview()
	_draw_city_label(_city_alpha)
	_draw_reachable_tiles()
	_draw_unit(_unit_a, Color(0.2, 0.7, 1.0), "A")
	_draw_unit(_unit_b, Color(1.0, 0.4, 0.4), "B")
	_draw_unit(_unit_transport, Color(0.7, 1.0, 0.4), "T")
	_draw_selection_rings()

func _initialize_demo() -> void:
	_city_alpha = CITY_DATA_SCRIPT.new("City-A", "A", Vector2i(2, 2))
	_unit_a = UNIT_DATA_SCRIPT.new("A-1", "A", UNIT_DATA_SCRIPT.ArmsType.SPEARMAN, Vector2i(0, 0), 3)
	_unit_b = UNIT_DATA_SCRIPT.new("B-1", "B", UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD, Vector2i(3, 0), 3)
	_unit_transport = UNIT_DATA_SCRIPT.new("A-T", "A", UNIT_DATA_SCRIPT.ArmsType.TRANSPORT, Vector2i(0, 1), 4)
	_unit_list = [_unit_a, _unit_b, _unit_transport]

	_turn_manager = TURN_MANAGER_SCRIPT.new()
	_turn_manager.setup(["A", "B"], {"A": [_unit_a, _unit_transport], "B": [_unit_b]})

	_grid_rules = HEX_GRID_RULES_SCRIPT.new()
	_grid_rules.setup([_city_alpha.core_grid], _unit_list)

	_state = InteractionState.IDLE
	_selected_city = null
	_selected_unit = null
	_reachable_tiles.clear()
	_move_path.clear()
	_move_step_timer = 0.0

func _handle_left_click(screen_pos: Vector2) -> void:
	if _state == InteractionState.UNIT_MOVING:
		return

	var world_pos := screen_pos
	var picked_unit = _pick_unit(world_pos)
	if picked_unit != null:
		_select_unit(picked_unit)
		return

	if _is_click_on_city(world_pos):
		_select_city(_city_alpha)
		return

	var clicked_cell: Vector2i = _pick_grid_cell(world_pos)
	if _state == InteractionState.UNIT_MOVE_TARGETING and _selected_unit != null:
		_try_start_move(clicked_cell)
		return

	_clear_selection("未选中对象。")

# 处理左键按下：记录按压上下文，用于区分点击和长按拖拽。
# 输入: screen_pos(按下时屏幕坐标)
# 输出: 更新拖拽状态缓存，不直接触发业务点击。
func _on_left_mouse_down(screen_pos: Vector2) -> void:
	_is_left_pressed = true
	_is_camera_dragging = false
	_left_press_screen_pos = screen_pos
	_left_press_latest_pos = screen_pos
	_left_press_started_at_ms = Time.get_ticks_msec()
	_left_press_started_on_empty = _pick_unit(screen_pos) == null and not _is_click_on_city(screen_pos)

# 处理左键抬起：若已拖拽则结束拖拽；否则按普通点击分发。
# 输入: screen_pos(抬起时屏幕坐标)
# 输出: 触发点击选择或仅结束拖拽。
func _on_left_mouse_up(screen_pos: Vector2) -> void:
	if not _is_left_pressed:
		return
	var was_dragging := _is_camera_dragging
	_is_left_pressed = false
	_is_camera_dragging = false
	_left_press_started_on_empty = false
	if was_dragging:
		_update_status("已结束拖拽视角。")
		return
	_handle_left_click(screen_pos)

# 处理左键按住移动：满足长按+位移阈值后进入地图拖拽。
# 输入: event(鼠标移动事件)
# 输出: 更新相机偏移并刷新画面。
func _on_left_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_left_pressed:
		return
	_left_press_latest_pos = event.position
	if not _left_press_started_on_empty:
		return
	if _state == InteractionState.UNIT_MOVING:
		return
	if not _is_camera_dragging:
		var hold_ms := Time.get_ticks_msec() - _left_press_started_at_ms
		var drag_distance := _left_press_latest_pos.distance_to(_left_press_screen_pos)
		if hold_ms < DRAG_LONG_PRESS_MS or drag_distance < DRAG_START_THRESHOLD_PX:
			return
		_is_camera_dragging = true
		_update_status("长按空地拖拽中：正在移动地图视角。")
	_apply_camera_offset_delta(event.relative)
	queue_redraw()

func _select_city(city) -> void:
	_selected_city = city
	_selected_unit = null
	_reachable_tiles.clear()
	_state = InteractionState.CITY_SELECTED
	_update_context_panel()
	_update_status("已选中城市 %s。右侧显示城市操作面板入口。" % city.id)

func _select_unit(unit) -> void:
	if unit.faction_id != _turn_manager.current_faction_id():
		_update_status("当前为 %s 势力回合，不能操作 %s 势力单位。" % [_turn_manager.current_faction_id(), unit.faction_id])
		return
	_selected_city = null
	_selected_unit = unit
	_state = InteractionState.UNIT_SELECTED
	_reachable_tiles = _grid_rules.get_reachable_tiles(unit)
	_update_context_panel()
	_update_status("已选中部队 %s。已显示可移动范围，点击可达格可执行移动。" % unit.id)

func _enter_move_targeting() -> void:
	if _selected_unit == null:
		return
	_state = InteractionState.UNIT_MOVE_TARGETING
	_reachable_tiles = _grid_rules.get_reachable_tiles(_selected_unit)
	_update_context_panel()
	_update_status("移动目标选择中：请点击一个可达格。")

func _try_start_move(target: Vector2i) -> void:
	if _selected_unit == null:
		return
	if not _grid_rules.is_tile_reachable(_selected_unit, target):
		_update_status("目的地不可达：%s" % str(target))
		return
	_move_path = _grid_rules.build_path(_selected_unit, target)
	if _move_path.is_empty():
		_update_status("未找到路径。")
		return
	_state = InteractionState.UNIT_MOVING
	_move_step_timer = UNIT_STEP_TIME_SEC
	_update_context_panel()
	_update_status("部队 %s 开始逐格移动到 %s。" % [_selected_unit.id, str(target)])

func _process_unit_moving(delta: float) -> void:
	if _state != InteractionState.UNIT_MOVING or _selected_unit == null:
		return
	_move_step_timer -= delta
	if _move_step_timer > 0.0:
		return
	_move_step_timer = UNIT_STEP_TIME_SEC
	if _move_path.is_empty():
		_finish_movement()
		return
	var step_cell: Vector2i = _move_path.pop_front()
	var result: Dictionary = _grid_rules.move_unit_one_step(_selected_unit, step_cell)
	if not result["ok"]:
		_state = InteractionState.UNIT_SELECTED
		_update_status("移动中断，原因=%d" % result["reason"])
		_reachable_tiles = _grid_rules.get_reachable_tiles(_selected_unit)
		_update_context_panel()
		queue_redraw()
		return
	queue_redraw()

func _finish_movement() -> void:
	_state = InteractionState.UNIT_SELECTED
	_reachable_tiles = _grid_rules.get_reachable_tiles(_selected_unit)
	_update_context_panel()
	_update_status("移动完成：%s 当前坐标=%s，剩余行动力=%d" % [
		_selected_unit.id, str(_selected_unit.grid), _selected_unit.remaining_move_points
	])

func _clear_selection(status_text: String) -> void:
	_state = InteractionState.IDLE
	_selected_city = null
	_selected_unit = null
	_reachable_tiles.clear()
	_move_path.clear()
	_update_context_panel()
	_update_status(status_text)

func _build_interaction_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InteractionUI"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.offset_left = 980
	panel.offset_top = 20
	panel.offset_right = 1260
	panel.offset_bottom = 350
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var title := Label.new()
	title.text = "交互操作面板"
	vb.add_child(title)

	_context_label = Label.new()
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_label.custom_minimum_size = Vector2(250, 280)
	vb.add_child(_context_label)

	_update_context_panel()

func _update_context_panel() -> void:
	if _context_label == null:
		return
	match _state:
		InteractionState.IDLE:
			_context_label.text = "状态: 空闲\n- 左键点击部队: 选中并显示可达范围\n- 左键点击城市: 显示城市面板\n- 空地左键长按拖拽: 视角平移\n- 鼠标移到边缘: 视角滚动"
		InteractionState.CITY_SELECTED:
			_context_label.text = "状态: 已选中城市\n城市: %s\n操作入口:\n- 发展(占位)\n- 征募(占位)\n- 编制(占位)\n\n右键/Esc: 取消选择" % _selected_city.id
		InteractionState.UNIT_SELECTED:
			_context_label.text = "状态: 已选中部队\n部队: %s\n剩余行动力: %d\n操作入口:\n- 移动(左键可达格)\n- 攻击(占位)\n- 战法(占位)\n- 补给(占位)\n\n按 M: 进入移动目标模式" % [
				_selected_unit.id, _selected_unit.remaining_move_points
			]
		InteractionState.UNIT_MOVE_TARGETING:
			_context_label.text = "状态: 选择移动目标\n部队: %s\n请左键点击可达格。\n右键/Esc: 返回部队选中态。" % _selected_unit.id
		InteractionState.UNIT_MOVING:
			_context_label.text = "状态: 部队移动中\n部队: %s\n沿路径逐格推进中..." % _selected_unit.id

func _build_debug_panel() -> void:
	_debug_panel = DEBUG_PANEL_SCRIPT.new()
	_debug_panel.name = "DebugUI"
	add_child(_debug_panel)
	_debug_panel.setup(Callable(self, "_handle_debug_action"))

func _handle_debug_action(action_id: String) -> void:
	match action_id:
		"move":
			_enter_move_targeting()
		"end_turn":
			_turn_manager.end_turn()
			_update_status("结束回合，当前势力=%s，回合=%d" % [_turn_manager.current_faction_id(), _turn_manager.current_turn_count()])
		"reset":
			_initialize_demo()
			_clear_selection("已重置演示状态。")
		_:
			_update_status("该按钮在交互演示里保留为占位：%s" % action_id)
	queue_redraw()

func _update_status(text: String) -> void:
	if _status_label == null:
		_status_label = get_node_or_null("HelloLabel")
	if _status_label != null:
		_status_label.text = text

func _handle_edge_scroll(delta: float) -> void:
	if _is_camera_dragging:
		return
	var viewport_rect := get_viewport_rect()
	var mouse_pos := get_viewport().get_mouse_position()
	if not viewport_rect.has_point(mouse_pos):
		return
	var scroll_dir := Vector2.ZERO
	if mouse_pos.x <= EDGE_THRESHOLD_PX:
		scroll_dir.x += 1.0
	elif mouse_pos.x >= viewport_rect.size.x - EDGE_THRESHOLD_PX:
		scroll_dir.x -= 1.0
	if mouse_pos.y <= EDGE_THRESHOLD_PX:
		scroll_dir.y += 1.0
	elif mouse_pos.y >= viewport_rect.size.y - EDGE_THRESHOLD_PX:
		scroll_dir.y -= 1.0
	if scroll_dir == Vector2.ZERO:
		return
	_apply_camera_offset_delta(scroll_dir.normalized() * EDGE_SCROLL_SPEED * delta)
	queue_redraw()

# 相机偏移应用函数，统一做边界夹取。
# 输入: delta(本次相机偏移增量)
# 输出: 更新并夹取 _camera_offset。
func _apply_camera_offset_delta(delta: Vector2) -> void:
	_camera_offset += delta
	_camera_offset.x = clamp(_camera_offset.x, _min_camera_offset.x, _max_camera_offset.x)
	_camera_offset.y = clamp(_camera_offset.y, _min_camera_offset.y, _max_camera_offset.y)

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
	_min_camera_offset = Vector2(
		viewport_size.x - (max_world.x + margin),
		viewport_size.y - (max_world.y + margin)
	)
	_max_camera_offset = Vector2(
		-(min_world.x - margin),
		-(min_world.y - margin)
	)

func _draw_grid() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var center := _axial_to_pixel(Vector2i(q, r))
			var points := PackedVector2Array()
			for i in range(6):
				var angle := PI / 180.0 * (60.0 * i - 30.0)
				points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.35, 0.35, 0.35), 1.5)

func _draw_city_block_preview() -> void:
	var center := _axial_to_pixel(_city_alpha.core_grid)
	draw_circle(center, HEX_SIZE * 0.4, Color(0.9, 0.75, 0.25, 0.8))
	for cell in _grid_rules.neighbors(_city_alpha.core_grid):
		draw_circle(_axial_to_pixel(cell), HEX_SIZE * 0.16, Color(0.9, 0.75, 0.25, 0.35))

func _draw_city_label(city) -> void:
	var center := _axial_to_pixel(city.core_grid)
	var font := ThemeDB.fallback_font
	if font != null:
		var t := "City:%s Owner:%s" % [city.id, city.owner_faction_id]
		draw_string(font, center + Vector2(-70, -HEX_SIZE * 0.8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.95, 0.7))

func _draw_reachable_tiles() -> void:
	if _selected_unit == null:
		return
	for cell in _reachable_tiles:
		draw_circle(_axial_to_pixel(cell), HEX_SIZE * 0.22, Color(0.2, 0.95, 0.35, 0.6))

func _draw_selection_rings() -> void:
	if _selected_city != null:
		draw_arc(_axial_to_pixel(_selected_city.core_grid), HEX_SIZE * 0.55, 0.0, TAU, 24, Color(1.0, 0.9, 0.2), 3.0)
	if _selected_unit != null:
		draw_arc(_axial_to_pixel(_selected_unit.grid), HEX_SIZE * 0.5, 0.0, TAU, 24, Color(0.2, 1.0, 1.0), 3.0)

func _draw_unit(unit, color: Color, tag: String) -> void:
	if unit == null or unit.is_routed:
		return
	var center := _axial_to_pixel(unit.grid)
	draw_circle(center, HEX_SIZE * 0.35, color)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, center + Vector2(-6, 5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)

func _pick_unit(world_pos: Vector2):
	for unit in _unit_list:
		if unit == null or unit.is_routed:
			continue
		if world_pos.distance_to(_axial_to_pixel(unit.grid)) <= HEX_SIZE * 0.5:
			return unit
	return null

func _is_click_on_city(world_pos: Vector2) -> bool:
	if world_pos.distance_to(_axial_to_pixel(_city_alpha.core_grid)) <= HEX_SIZE * 0.65:
		return true
	for cell in _grid_rules.neighbors(_city_alpha.core_grid):
		if world_pos.distance_to(_axial_to_pixel(cell)) <= HEX_SIZE * 0.3:
			return true
	return false

func _pick_grid_cell(world_pos: Vector2) -> Vector2i:
	var best_cell := Vector2i.ZERO
	var best_distance := INF
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var cell := Vector2i(q, r)
			var dist := world_pos.distance_to(_axial_to_pixel(cell))
			if dist < best_distance:
				best_distance = dist
				best_cell = cell
	return best_cell

func _axial_to_pixel(cell: Vector2i) -> Vector2:
	return _axial_to_pixel_no_offset(cell) + _camera_offset

func _axial_to_pixel_no_offset(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + cell.y * 0.5)
	var y := HEX_SIZE * 1.5 * cell.y
	return ORIGIN + Vector2(x, y)
