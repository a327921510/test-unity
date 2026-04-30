extends Node3D

const CAMERA_CONTROLLER_SCRIPT := preload("res://scripts/CameraController3D.gd")
const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const DEBUG_PANEL_SCRIPT := preload("res://scripts/ui/DebugPanel.gd")
const HEX_GRID_RULES_SCRIPT := preload("res://scripts/map/HexGridRules.gd")
const GRID_RADIUS := 24
const HEX_SIZE := 1.2
const TILE_HEIGHT := 0.14
const KAYKIT_ROOT := "res://third_party/kaykit-medieval-hexagon"
const KAYKIT_GLTF_ROOT := "res://third_party/kaykit-medieval-hexagon/Assets/gltf"
const KAYKIT_SAMPLE_TILE := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/tiles/base/hex_grass.gltf"
const KAYKIT_SAMPLE_CITY := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/buildings/red/building_castle_red.gltf"
const KAYKIT_TILE_GRASS := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/tiles/base/hex_grass.gltf"
const KAYKIT_TILE_WATER := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/tiles/base/hex_water.gltf"
const KAYKIT_TILE_SLOPED_HIGH := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/tiles/base/hex_grass_sloped_high.gltf"
const KAYKIT_CITY_NEUTRAL := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/buildings/red/building_castle_red.gltf"
const KAYKIT_UNIT_RED := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/buildings/red/building_tower_catapult_red.gltf"
const KAYKIT_UNIT_GREEN := "res://third_party/kaykit-medieval-hexagon/Assets/gltf/buildings/green/building_tower_catapult_green.gltf"

enum TerrainType {
	PLAIN,
	FOREST,
	MOUNTAIN,
	WATER,
	DESERT
}

@onready var _camera: Camera3D = $Camera3D
@onready var _status_label: Label = $CanvasLayer/StatusLabel
@onready var _grid_root: Node3D = $GridRoot

var _map_min := Vector2(-40.0, -40.0)
var _map_max := Vector2(40.0, 40.0)
var _camera_controller
var _terrain_materials: Dictionary = {}
var _terrain_root: Node3D
var _city_root: Node3D
var _unit_root: Node3D
var _grid_line_root: Node3D
var _path_preview_root: Node3D
var _reachable_root: Node3D
var _game_manager: Node
var _kaykit_ready := false
var _kaykit_models_ready := false
var _model_cache: Dictionary = {}
var _last_settlement_brief := ""
var _last_army_brief := "军事操作: 无"
var _unit_id_seq := 1
var _debug_panel
var _action_logs: Array[String] = []
var _unit_visual_nodes: Dictionary = {}
var _city_visual_nodes: Dictionary = {}
var _city_footprint_cells: Dictionary = {}
var _selected_type := "none"
var _selected_id := ""
const SELECTION_PICK_RADIUS := 1.35
var _selection_marker: MeshInstance3D
var _is_animating_move := false
const STEP_MOVE_INTERVAL_SEC := 0.10
var _path_preview_mesh: MeshInstance3D
var _reachable_cells_nodes: Array[MeshInstance3D] = []

func _ready() -> void:
	_setup_scene_roots()
	_setup_materials()
	_detect_kaykit_pack()
	_build_map_render()
	_recompute_map_bounds()
	_bind_game_manager()
	_setup_debug_panel()
	_camera_controller = CAMERA_CONTROLLER_SCRIPT.new()
	_camera_controller.setup(_camera, _map_min, _map_max)
	_update_status()

func _process(delta: float) -> void:
	_camera_controller.update_frame(delta, get_viewport().get_visible_rect(), get_viewport().get_mouse_position())
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if _is_animating_move:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_set_selection("none", "")
		_clear_path_preview()
		_last_army_brief = "军事操作: 已取消选中"
		_append_action_log("select: cancelled by right click")
		_update_status()
	if _camera_controller.handle_input(event):
		_update_status()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_left_click(event.position)
		return
	if event is InputEventMouseMotion:
		_update_path_preview(event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				if _game_manager != null:
					_game_manager.run_monthly_settlement()
			KEY_SPACE:
				if _game_manager != null:
					_game_manager.end_faction_turn()
			KEY_R:
				if _game_manager != null:
					_game_manager.reset_demo_state()
			KEY_C:
				_try_compose_demo_unit()
			KEY_M:
				_try_move_demo_unit_toward_city()
			KEY_E:
				_try_disband_demo_unit()
			KEY_Y:
				_run_full_demo()

func _setup_scene_roots() -> void:
	for child in _grid_root.get_children():
		child.queue_free()
	_unit_visual_nodes.clear()
	_city_visual_nodes.clear()
	_city_footprint_cells.clear()
	_reachable_cells_nodes.clear()
	_selected_type = "none"
	_selected_id = ""
	_selection_marker = null
	_terrain_root = Node3D.new()
	_terrain_root.name = "TerrainRoot"
	_grid_root.add_child(_terrain_root)
	_city_root = Node3D.new()
	_city_root.name = "CityRoot"
	_grid_root.add_child(_city_root)
	_unit_root = Node3D.new()
	_unit_root.name = "UnitRoot"
	_grid_root.add_child(_unit_root)
	_grid_line_root = Node3D.new()
	_grid_line_root.name = "GridLineRoot"
	_grid_root.add_child(_grid_line_root)
	_path_preview_root = Node3D.new()
	_path_preview_root.name = "PathPreviewRoot"
	_grid_root.add_child(_path_preview_root)
	_reachable_root = Node3D.new()
	_reachable_root.name = "ReachableRoot"
	_grid_root.add_child(_reachable_root)
	_setup_selection_marker()
	_setup_path_preview()

func _setup_selection_marker() -> void:
	_selection_marker = MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = HEX_SIZE * 0.42
	marker_mesh.bottom_radius = HEX_SIZE * 0.42
	marker_mesh.height = 0.05
	marker_mesh.radial_segments = 24
	_selection_marker.mesh = marker_mesh
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.95, 0.2, 0.85)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_marker.material_override = marker_mat
	_selection_marker.visible = false
	_grid_root.add_child(_selection_marker)

func _setup_path_preview() -> void:
	_path_preview_mesh = MeshInstance3D.new()
	_path_preview_mesh.visible = false
	_path_preview_root.add_child(_path_preview_mesh)

func _setup_materials() -> void:
	_terrain_materials.clear()
	_terrain_materials[TerrainType.PLAIN] = _build_terrain_mat(Color(0.36, 0.56, 0.30))
	_terrain_materials[TerrainType.FOREST] = _build_terrain_mat(Color(0.18, 0.38, 0.22))
	_terrain_materials[TerrainType.MOUNTAIN] = _build_terrain_mat(Color(0.42, 0.42, 0.44))
	_terrain_materials[TerrainType.WATER] = _build_terrain_mat(Color(0.14, 0.30, 0.58))
	_terrain_materials[TerrainType.DESERT] = _build_terrain_mat(Color(0.66, 0.59, 0.34))

func _build_map_render() -> void:
	var city_cells := [
		Vector2i(0, 0)
	]
	var red_units := [
		Vector2i(-6, -1),
		Vector2i(0, -4),
		Vector2i(3, 6)
	]
	var green_units := [
		Vector2i(6, 1),
		Vector2i(-2, 7),
		Vector2i(10, -1)
	]
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var cell := Vector2i(q, r)
			_spawn_terrain_tile(cell)
			_spawn_grid_outline(cell)
	if _city_root != null:
		for cell in city_cells:
			_spawn_city(cell)
	if _unit_root != null:
		for cell in red_units:
			_spawn_unit(cell, KAYKIT_UNIT_RED, Color(0.86, 0.20, 0.20))
		for cell in green_units:
			_spawn_unit(cell, KAYKIT_UNIT_GREEN, Color(0.20, 0.65, 0.30))

func _spawn_terrain_tile(cell: Vector2i) -> void:
	var p := _axial_to_world(cell)
	var tile := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = HEX_SIZE * 0.95
	mesh.bottom_radius = HEX_SIZE * 0.95
	mesh.height = TILE_HEIGHT
	mesh.radial_segments = 6
	mesh.rings = 1
	tile.mesh = mesh
	tile.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
	tile.position = Vector3(p.x, TILE_HEIGHT * 0.5, p.y)
	var terrain := _pick_terrain(cell)
	if _kaykit_models_ready:
		var terrain_model := _get_terrain_model_path(terrain)
		if _spawn_kaykit_scene(cell, terrain_model, _terrain_root, 1.1, 0.0):
			return
	tile.material_override = _terrain_materials.get(terrain)
	tile.scale = Vector3(1.0, 1.35, 1.0)
	_terrain_root.add_child(tile)

func _spawn_grid_outline(cell: Vector2i) -> void:
	var line := MeshInstance3D.new()
	var immediate := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.95, 1.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var center := _axial_to_world(cell)
	var points: Array[Vector3] = []
	for i in range(6):
		var angle := deg_to_rad(60.0 * float(i) + 30.0)
		var x := center.x + HEX_SIZE * 0.98 * cos(angle)
		var z := center.y + HEX_SIZE * 0.98 * sin(angle)
		points.append(Vector3(x, TILE_HEIGHT + 0.02, z))
	for i in range(6):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % 6]
		immediate.surface_add_vertex(a)
		immediate.surface_add_vertex(b)
	immediate.surface_end()
	line.mesh = immediate
	_grid_line_root.add_child(line)

func _spawn_city(cell: Vector2i) -> void:
	_register_city_footprint("City-A", cell)
	var city_node: Node3D = null
	if _kaykit_models_ready:
		city_node = _spawn_kaykit_scene(cell, KAYKIT_CITY_NEUTRAL, _city_root, 1.0, TILE_HEIGHT)
	else:
		var p := _axial_to_world(cell)
		var city := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = HEX_SIZE * 0.38
		mesh.bottom_radius = HEX_SIZE * 0.45
		mesh.height = 1.1
		mesh.radial_segments = 8
		city.mesh = mesh
		city.position = Vector3(p.x, 0.72, p.y)
		city.material_override = _build_terrain_mat(Color(0.75, 0.75, 0.82))
		_city_root.add_child(city)
		city_node = city
	if city_node != null:
		_city_visual_nodes["City-A"] = city_node
	_spawn_city_footprint_tiles(cell)

func _spawn_city_footprint_tiles(core_cell: Vector2i) -> void:
	for ring_cell in _hex_neighbors(core_cell):
		var tile := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = HEX_SIZE * 0.90
		mesh.bottom_radius = HEX_SIZE * 0.90
		mesh.height = TILE_HEIGHT * 0.55
		mesh.radial_segments = 6
		tile.mesh = mesh
		tile.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
		var p := _axial_to_world(ring_cell)
		tile.position = Vector3(p.x, TILE_HEIGHT * 0.30, p.y)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.62, 0.68, 0.78)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.85
		tile.material_override = mat
		_city_root.add_child(tile)
		_register_city_footprint("City-A", ring_cell)

func _spawn_unit(cell: Vector2i, model_path: String, tint: Color) -> Node3D:
	if _kaykit_models_ready:
		var kaykit_node := _spawn_kaykit_scene(cell, model_path, _unit_root, 0.72, TILE_HEIGHT)
		if kaykit_node != null:
			return kaykit_node
	var p := _axial_to_world(cell)
	var unit := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.62
	unit.mesh = mesh
	unit.position = Vector3(p.x, 0.48, p.y)
	unit.material_override = _build_terrain_mat(tint)
	_unit_root.add_child(unit)
	return unit

func _spawn_kaykit_scene(cell: Vector2i, scene_path: String, parent: Node3D, uniform_scale: float, y_offset: float) -> Node3D:
	var packed_scene := _get_kaykit_scene(scene_path)
	if packed_scene == null:
		return null
	var instance = packed_scene.instantiate()
	if instance == null or not (instance is Node3D):
		return null
	var p := _axial_to_world(cell)
	var node3d := instance as Node3D
	node3d.position = Vector3(p.x, y_offset, p.y)
	node3d.scale = Vector3.ONE * uniform_scale
	parent.add_child(node3d)
	return node3d

func _get_kaykit_scene(path: String) -> PackedScene:
	if not _model_cache.has(path):
		_model_cache[path] = null
		if ResourceLoader.exists(path):
			var loaded = load(path)
			if loaded is PackedScene:
				_model_cache[path] = loaded
	var packed = _model_cache.get(path)
	if packed is PackedScene:
		return packed as PackedScene
	return null

func _pick_terrain(cell: Vector2i) -> TerrainType:
	var forest_center := Vector2i(-8, 5)
	var mountain_center := Vector2i(9, -3)
	var water_center := Vector2i(-2, -10)
	var forest_radius := 5
	var mountain_radius := 4
	var water_radius := 5

	if _hex_distance(cell, water_center) <= water_radius:
		return TerrainType.WATER
	if _hex_distance(cell, mountain_center) <= mountain_radius:
		return TerrainType.MOUNTAIN
	if _hex_distance(cell, forest_center) <= forest_radius:
		return TerrainType.FOREST
	return TerrainType.PLAIN

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dq + dr) + abs(dr)) / 2)

func _hex_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i(1, 0),
		cell + Vector2i(1, -1),
		cell + Vector2i(0, -1),
		cell + Vector2i(-1, 0),
		cell + Vector2i(-1, 1),
		cell + Vector2i(0, 1)
	]

func _register_city_footprint(city_id: String, cell: Vector2i) -> void:
	if not _city_footprint_cells.has(city_id):
		_city_footprint_cells[city_id] = {}
	var footprint: Dictionary = _city_footprint_cells[city_id]
	footprint[cell] = true
	_city_footprint_cells[city_id] = footprint

func _build_terrain_mat(base_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = 0.92
	mat.metallic = 0.02
	return mat

func _detect_kaykit_pack() -> void:
	var global_root := ProjectSettings.globalize_path(KAYKIT_ROOT)
	var global_gltf_root := ProjectSettings.globalize_path(KAYKIT_GLTF_ROOT)
	_kaykit_ready = DirAccess.dir_exists_absolute(global_root) and DirAccess.dir_exists_absolute(global_gltf_root)
	_kaykit_models_ready = _can_load_kaykit_models()

func _can_load_kaykit_models() -> bool:
	if not _kaykit_ready:
		return false
	var tile_ok := ResourceLoader.exists(KAYKIT_SAMPLE_TILE)
	var city_ok := ResourceLoader.exists(KAYKIT_SAMPLE_CITY)
	return tile_ok and city_ok

func _get_terrain_model_path(terrain: TerrainType) -> String:
	match terrain:
		TerrainType.WATER:
			return KAYKIT_TILE_WATER
		TerrainType.MOUNTAIN:
			return KAYKIT_TILE_SLOPED_HIGH
		_:
			return KAYKIT_TILE_GRASS

func _recompute_map_bounds() -> void:
	var min_x := 999999.0
	var min_z := 999999.0
	var max_x := -999999.0
	var max_z := -999999.0
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var p := _axial_to_world(Vector2i(q, r))
			min_x = min(min_x, p.x)
			min_z = min(min_z, p.y)
			max_x = max(max_x, p.x)
			max_z = max(max_z, p.y)
	var margin := HEX_SIZE * 2.5
	_map_min = Vector2(min_x - margin, min_z - margin)
	_map_max = Vector2(max_x + margin, max_z + margin)
	if _camera_controller != null:
		_camera_controller.set_map_bounds(_map_min, _map_max)

func _axial_to_world(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + cell.y * 0.5)
	var z := HEX_SIZE * 1.5 * cell.y
	return Vector2(x, z)

func _bind_game_manager() -> void:
	var node = get_node_or_null("/root/GameManager")
	if node == null:
		return
	_game_manager = node as Node
	if _game_manager == null:
		return
	_game_manager.monthly_settlement_completed.connect(_on_monthly_settlement_completed)
	_game_manager.game_state_reset.connect(_on_game_state_reset)

func _on_monthly_settlement_completed(turn_count: int, settlement: Dictionary) -> void:
	var city_parts: Array[String] = []
	for city_id in settlement.keys():
		var detail: Dictionary = settlement[city_id]
		var delta: Dictionary = detail.get("delta", {})
		city_parts.append("%s 金+%d 粮+%d 兵源+%d" % [
			city_id,
			int(delta.get("money_delta", 0)),
			int(delta.get("food_delta", 0)),
			int(delta.get("troop_source_delta", 0))
		])
	_last_settlement_brief = "月结算(T%d): %s" % [turn_count, " | ".join(city_parts)]
	_update_status()

func _on_game_state_reset() -> void:
	_last_settlement_brief = "已重置城市与回合状态"
	_last_army_brief = "军事操作: 已清空编制与出征状态"
	_unit_id_seq = 1
	_action_logs.clear()
	_unit_visual_nodes.clear()
	_selected_type = "none"
	_selected_id = ""
	if _debug_panel != null:
		_debug_panel.set_selection_mode(_selected_type, _selected_id)
	_append_action_log("reset: 已重置游戏状态")
	_update_status()

func _setup_debug_panel() -> void:
	_debug_panel = DEBUG_PANEL_SCRIPT.new()
	add_child(_debug_panel)
	_debug_panel.setup(Callable(self, "_on_debug_action"))
	_append_action_log("debug: 操作面板已就绪")

func _on_debug_action(action_id: String) -> void:
	match action_id:
		"compose":
			_try_compose_demo_unit()
		"move":
			_last_army_brief = "军事操作: 已改为左键地块直接移动（需先选中部队）"
			_append_action_log("move: use left click target")
			_update_status()
		"entry":
			_try_disband_demo_unit()
		"monthly":
			if _game_manager != null:
				_game_manager.run_monthly_settlement()
				_append_action_log("monthly: 触发月结算")
		"end_turn":
			if _game_manager != null:
				_game_manager.end_faction_turn()
				_append_action_log("turn: 结束势力回合")
		"full_demo":
			_run_full_demo()
		"reset":
			if _game_manager != null:
				_game_manager.reset_demo_state()
		_:
			_append_action_log("%s: 尚未接入" % action_id)

func _try_compose_demo_unit() -> void:
	if _game_manager == null:
		return
	if _selected_type != "city":
		_last_army_brief = "军事操作: 请先选中城市再编制"
		_append_action_log("compose: failed NO_CITY_SELECTED")
		_update_status()
		return
	var selected_city = _game_manager.get_city(_selected_id)
	if selected_city == null:
		_last_army_brief = "军事操作: 编制失败，选中城市不存在"
		_append_action_log("compose: failed CITY_NOT_FOUND")
		_update_status()
		return
	var unit_id := "A-C%d" % _unit_id_seq
	_unit_id_seq += 1
	var ret: Dictionary = _game_manager.compose_and_dispatch(
		selected_city.id,
		unit_id,
		UNIT_DATA_SCRIPT.ArmsType.SPEARMAN,
		Vector2i(3, 0),
		600,
		"SPEAR",
		800,
		500
	)
	if not ret.get("ok", false):
		_last_army_brief = "军事操作: 编制失败 reason=%s" % str(ret.get("reason", "UNKNOWN"))
		_append_action_log("compose: failed %s" % str(ret.get("reason", "UNKNOWN")))
		_update_status()
		return
	var unit = ret.get("unit")
	_last_army_brief = "军事操作: 编制成功 %s 兵力:%d 粮:%d 金:%d" % [unit.id, unit.troop_source, unit.food, unit.money]
	_append_action_log("compose: ok %s troop=%d" % [unit.id, int(unit.troop_source)])
	var unit_node := _spawn_unit(unit.grid, KAYKIT_UNIT_RED, Color(0.90, 0.20, 0.20))
	if unit_node != null:
		_unit_visual_nodes[unit.id] = unit_node
	_set_selection("unit", unit.id)
	_update_status()

func _try_move_demo_unit_toward_city() -> void:
	if _game_manager == null:
		return
	var unit = _get_selected_unit()
	if unit == null:
		_last_army_brief = "军事操作: 无可移动部队"
		_append_action_log("move: failed NO_UNIT_SELECTED")
		_update_status()
		return
	var old_grid: Vector2i = unit.grid
	if int(unit.execution_state) != int(UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED):
		_last_army_brief = "军事操作: 移动失败，单位已执行"
		_append_action_log("move: failed EXECUTED")
		_update_status()
		return
	var city = _game_manager.get_city("City-A")
	if city == null:
		_last_army_brief = "军事操作: 移动失败，城市不存在"
		_append_action_log("move: failed CITY_NOT_FOUND")
		_update_status()
		return
	var grid_rules = HEX_GRID_RULES_SCRIPT.new()
	var units: Array = _game_manager.get_faction_units(_game_manager.get_current_faction_id())
	grid_rules.setup([city.core_grid], units)
	var candidates := grid_rules.neighbors(unit.grid)
	var best_cell: Vector2i = unit.grid
	var best_dist := _hex_distance(unit.grid, city.core_grid)
	for next_cell in candidates:
		if not grid_rules.is_tile_reachable(unit, next_cell):
			continue
		var next_dist := _hex_distance(next_cell, city.core_grid)
		if next_dist < best_dist:
			best_dist = next_dist
			best_cell = next_cell
	if best_cell == unit.grid:
		_last_army_brief = "军事操作: 移动失败，无可用前进格"
		_append_action_log("move: failed NO_REACHABLE_STEP")
		_update_status()
		return
	var move_ret: Dictionary = grid_rules.move_unit_one_step(unit, best_cell)
	if not move_ret.get("ok", false):
		_last_army_brief = "军事操作: 移动失败 reason=%s" % str(move_ret.get("reason", "UNKNOWN"))
		_append_action_log("move: failed reason=%s" % str(move_ret.get("reason", "UNKNOWN")))
		_update_status()
		return
	_sync_unit_visual(unit)
	_last_army_brief = "军事操作: 移动成功 %s -> %s 剩余MP:%d" % [
		str(old_grid),
		str(best_cell),
		int(unit.remaining_move_points)
	]
	_append_action_log("move: ok to=%s mp=%d" % [str(best_cell), int(unit.remaining_move_points)])
	_update_status()

func _try_move_selected_unit_to_click(screen_pos: Vector2) -> void:
	var unit = _get_selected_unit()
	if unit == null:
		_last_army_brief = "军事操作: 移动失败，未选中部队"
		_append_action_log("move: failed NO_UNIT_SELECTED")
		_update_status()
		return
	if int(unit.execution_state) != int(UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED):
		_last_army_brief = "军事操作: 移动失败，单位已执行"
		_append_action_log("move: failed EXECUTED")
		_update_status()
		return
	var city = _game_manager.get_city("City-A")
	if city == null:
		_last_army_brief = "军事操作: 移动失败，城市不存在"
		_append_action_log("move: failed CITY_NOT_FOUND")
		_update_status()
		return
	var world: Variant = _project_mouse_to_ground(screen_pos)
	if world == null:
		_last_army_brief = "军事操作: 移动失败，点击位置无效"
		_append_action_log("move: failed INVALID_GROUND_CLICK")
		_update_status()
		return
	var target_cell := _world_to_axial(world as Vector3)
	_try_move_selected_unit_to_cell(target_cell)

func _try_move_selected_unit_to_cell(target_cell: Vector2i) -> void:
	var unit = _get_selected_unit()
	if unit == null:
		return
	if unit.grid == target_cell:
		_last_army_brief = "军事操作: 目标与当前位置相同，无需移动"
		_append_action_log("move: skip SAME_CELL %s" % str(target_cell))
		_update_status()
		return
	var units: Array = _game_manager.get_faction_units(_game_manager.get_current_faction_id())
	var grid_rules = HEX_GRID_RULES_SCRIPT.new()
	var city = _game_manager.get_city("City-A")
	if city == null:
		return
	grid_rules.setup([city.core_grid], units)
	var path: Array[Vector2i] = grid_rules.build_path(unit, target_cell)
	if path.is_empty():
		_last_army_brief = "军事操作: 移动失败，目标不可达 %s" % str(target_cell)
		_append_action_log("move: failed UNREACHABLE target=%s" % str(target_cell))
		_update_status()
		return
	var old_grid: Vector2i = unit.grid
	await _move_unit_along_path(unit, path)
	_last_army_brief = "军事操作: 移动成功 %s -> %s 剩余MP:%d" % [
		str(old_grid),
		str(unit.grid),
		int(unit.remaining_move_points)
	]
	_append_action_log("move: ok to=%s mp=%d" % [str(unit.grid), int(unit.remaining_move_points)])
	_refresh_reachable_overlay()
	_update_status()

func _handle_left_click(screen_pos: Vector2) -> void:
	var world: Variant = _project_mouse_to_ground(screen_pos)
	if world == null:
		return
	var world_pos: Vector3 = world
	var hit: Dictionary = _pick_target_from_world(world_pos)
	var prev_selected_type := _selected_type
	var hit_type := str(hit.get("type", "none"))
	var hit_id := str(hit.get("id", ""))
	if prev_selected_type == "unit" and hit_type == "none":
		var target_cell := _world_to_axial(world_pos)
		_try_move_selected_unit_to_cell(target_cell)
		_clear_path_preview()
		return
	if prev_selected_type == "unit" and hit_type == "city":
		await _try_entry_selected_unit_to_city(hit_id)
		_clear_path_preview()
		return
	_set_selection(hit_type, hit_id)
	_append_action_log("select: %s %s" % [_selected_type, _selected_id if _selected_id != "" else "-"])
	_update_status()

func _try_disband_demo_unit() -> void:
	if _game_manager == null:
		return
	var unit = _get_selected_unit()
	if unit == null:
		_last_army_brief = "军事操作: 无可入城部队"
		_update_status()
		return
	var city = _game_manager.get_city("City-A")
	if city == null:
		_last_army_brief = "军事操作: 入城失败，城市不存在"
		_update_status()
		return
	var ret: Dictionary = _game_manager.disband_unit_into_city(unit, city.id, true)
	if not ret.get("ok", false):
		var reason := str(ret.get("reason", "UNKNOWN"))
		var city_grid: Vector2i = city.core_grid if city != null else Vector2i.ZERO
		var distance := _hex_distance(unit.grid, city_grid)
		var fail_detail := "reason=%s dist=%d unit=%s city=%s mp=%d state=%d" % [
			reason,
			distance,
			str(unit.grid),
			str(city_grid),
			int(unit.remaining_move_points),
			int(unit.execution_state)
		]
		_last_army_brief = "军事操作: 入城失败 %s" % fail_detail
		_append_action_log("entry: failed %s" % fail_detail)
		_update_status()
		return
	var returned: Dictionary = ret.get("returned", {})
	var discarded: Dictionary = ret.get("discarded", {})
	_last_army_brief = "军事操作: 入城成功 回库兵:%d 粮:%d 金:%d 溢出兵:%d" % [
		int(returned.get("troop_source", 0)),
		int(returned.get("food", 0)),
		int(returned.get("money", 0)),
		int(discarded.get("troop_source", 0))
	]
	_append_action_log("entry: ok troop+%d food+%d money+%d" % [
		int(returned.get("troop_source", 0)),
		int(returned.get("food", 0)),
		int(returned.get("money", 0))
	])
	_remove_unit_visual(str(unit.id))
	_set_selection("city", city.id)
	_clear_reachable_overlay()
	_update_status()

func _run_full_demo() -> void:
	_append_action_log("full_demo: start")
	_try_compose_demo_unit()
	var guard := 0
	while guard < 8:
		guard += 1
		var unit = _get_selected_unit()
		if unit == null:
			break
		var city = _game_manager.get_city("City-A")
		if city == null:
			break
		if _hex_distance(unit.grid, city.core_grid) <= 1:
			break
		_try_move_demo_unit_toward_city()
	_try_disband_demo_unit()
	_append_action_log("full_demo: done")
	_update_status()

func _append_action_log(line: String) -> void:
	_action_logs.append(line)
	while _action_logs.size() > 12:
		_action_logs.pop_front()
	if _debug_panel != null:
		_debug_panel.set_logs(_action_logs)

func _remove_unit_visual(unit_id: String) -> void:
	var node = _unit_visual_nodes.get(unit_id)
	if node == null:
		return
	if is_instance_valid(node):
		node.queue_free()
	_unit_visual_nodes.erase(unit_id)

func _set_selection(selection_type: String, selected_id: String) -> void:
	_selected_type = selection_type
	_selected_id = selected_id
	if _selected_type != "unit":
		_clear_path_preview()
		_clear_reachable_overlay()
	else:
		_refresh_reachable_overlay()
	if _debug_panel != null:
		_debug_panel.set_selection_mode(_selected_type, _selected_id)

func _get_selected_unit():
	if _game_manager == null or _selected_type != "unit":
		return null
	for unit in _game_manager.get_faction_units(_game_manager.get_current_faction_id()):
		if str(unit.id) == _selected_id:
			return unit
	return null

func _pick_selection(screen_pos: Vector2) -> void:
	var world: Variant = _project_mouse_to_ground(screen_pos)
	if world == null:
		return
	var world_pos: Vector3 = world
	var hit := _pick_target_from_world(world_pos)
	_set_selection(str(hit.get("type", "none")), str(hit.get("id", "")))
	_append_action_log("select: %s %s" % [_selected_type, _selected_id if _selected_id != "" else "-"])
	_update_status()

func _pick_target_from_world(world_pos: Vector3) -> Dictionary:
	var clicked_cell: Vector2i = _world_to_axial(world_pos)
	for city_id in _city_footprint_cells.keys():
		var footprint: Dictionary = _city_footprint_cells[city_id]
		if footprint.has(clicked_cell):
			return {"type": "city", "id": str(city_id)}
	var picked_type := "none"
	var picked_id := ""
	var picked_dist := 1e9
	for city_id in _city_visual_nodes.keys():
		var city_node = _city_visual_nodes[city_id]
		if city_node == null or not is_instance_valid(city_node):
			continue
		var dist: float = city_node.global_position.distance_to(world_pos)
		if dist < SELECTION_PICK_RADIUS and dist < picked_dist:
			picked_dist = dist
			picked_type = "city"
			picked_id = str(city_id)
	for unit_id in _unit_visual_nodes.keys():
		var unit_node = _unit_visual_nodes[unit_id]
		if unit_node == null or not is_instance_valid(unit_node):
			continue
		var dist: float = unit_node.global_position.distance_to(world_pos)
		if dist < SELECTION_PICK_RADIUS and dist < picked_dist:
			picked_dist = dist
			picked_type = "unit"
			picked_id = str(unit_id)
	return {"type": picked_type, "id": picked_id}

func _project_mouse_to_ground(screen_pos: Vector2):
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	if t < 0:
		return null
	return origin + dir * t

func _update_path_preview(screen_pos: Vector2) -> void:
	if _selected_type != "unit" or _game_manager == null:
		_clear_path_preview()
		return
	var unit = _get_selected_unit()
	if unit == null:
		_clear_path_preview()
		return
	var world: Variant = _project_mouse_to_ground(screen_pos)
	if world == null:
		_clear_path_preview()
		return
	var target_cell := _world_to_axial(world as Vector3)
	if target_cell == unit.grid:
		_clear_path_preview()
		return
	var city = _game_manager.get_city("City-A")
	if city == null:
		_clear_path_preview()
		return
	var units: Array = _game_manager.get_faction_units(_game_manager.get_current_faction_id())
	var grid_rules = HEX_GRID_RULES_SCRIPT.new()
	grid_rules.setup([city.core_grid], units)
	var path: Array[Vector2i] = grid_rules.build_path(unit, target_cell)
	if path.is_empty():
		_clear_path_preview()
		return
	_draw_path_preview(unit.grid, path)

func _draw_path_preview(start_cell: Vector2i, path: Array[Vector2i]) -> void:
	if _path_preview_mesh == null:
		return
	var immediate := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.20, 0.95, 1.0, 0.90)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var cursor := start_cell
	for step in path:
		var a2 := _axial_to_world(cursor)
		var b2 := _axial_to_world(step)
		var a := Vector3(a2.x, TILE_HEIGHT + 0.08, a2.y)
		var b := Vector3(b2.x, TILE_HEIGHT + 0.08, b2.y)
		immediate.surface_add_vertex(a)
		immediate.surface_add_vertex(b)
		cursor = step
	immediate.surface_end()
	_path_preview_mesh.mesh = immediate
	_path_preview_mesh.visible = true

func _clear_path_preview() -> void:
	if _path_preview_mesh == null:
		return
	_path_preview_mesh.visible = false
	_path_preview_mesh.mesh = null

func _refresh_reachable_overlay() -> void:
	_clear_reachable_overlay()
	if _game_manager == null or _selected_type != "unit":
		return
	var unit = _get_selected_unit()
	if unit == null:
		return
	var city = _game_manager.get_city("City-A")
	if city == null:
		return
	var units: Array = _game_manager.get_faction_units(_game_manager.get_current_faction_id())
	var grid_rules = HEX_GRID_RULES_SCRIPT.new()
	grid_rules.setup([city.core_grid], units)
	for cell in grid_rules.get_reachable_tiles(unit):
		var node := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = HEX_SIZE * 0.55
		mesh.bottom_radius = HEX_SIZE * 0.55
		mesh.height = 0.03
		mesh.radial_segments = 6
		node.mesh = mesh
		node.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
		var p := _axial_to_world(cell)
		node.position = Vector3(p.x, TILE_HEIGHT * 0.42, p.y)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.85, 0.95, 0.26)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		_reachable_root.add_child(node)
		_reachable_cells_nodes.append(node)

func _clear_reachable_overlay() -> void:
	for node in _reachable_cells_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_reachable_cells_nodes.clear()

func _world_to_axial(world: Vector3) -> Vector2i:
	var qf: float = (sqrt(3.0) / 3.0 * world.x - 1.0 / 3.0 * world.z) / HEX_SIZE
	var rf: float = (2.0 / 3.0 * world.z) / HEX_SIZE
	var sf: float = -qf - rf
	var rq: int = roundi(qf)
	var rr: int = roundi(rf)
	var rs: int = roundi(sf)
	var q_diff: float = absf(float(rq) - qf)
	var r_diff: float = absf(float(rr) - rf)
	var s_diff: float = absf(float(rs) - sf)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(rq, rr)

func _sync_unit_visual(unit) -> void:
	var node = _unit_visual_nodes.get(unit.id)
	if node == null or not is_instance_valid(node):
		return
	var p := _axial_to_world(unit.grid)
	node.position = Vector3(p.x, TILE_HEIGHT, p.y)

func _refresh_selection_highlight() -> void:
	if _selection_marker == null:
		return
	var target_node: Node3D = null
	if _selected_type == "unit":
		var unit_node = _unit_visual_nodes.get(_selected_id)
		if unit_node != null and is_instance_valid(unit_node):
			target_node = unit_node
	elif _selected_type == "city":
		var city_node = _city_visual_nodes.get(_selected_id)
		if city_node != null and is_instance_valid(city_node):
			target_node = city_node
	if target_node == null:
		_selection_marker.visible = false
		return
	_selection_marker.visible = true
	_selection_marker.position = Vector3(target_node.global_position.x, TILE_HEIGHT * 0.25, target_node.global_position.z)

func _try_entry_selected_unit_to_city(city_id: String) -> void:
	var unit = _get_selected_unit()
	if unit == null or _game_manager == null:
		return
	var city = _game_manager.get_city(city_id)
	if city == null:
		return
	var units: Array = _game_manager.get_faction_units(_game_manager.get_current_faction_id())
	var grid_rules = HEX_GRID_RULES_SCRIPT.new()
	grid_rules.setup([city.core_grid], units)
	var footprint := _get_city_footprint_cells(city_id, city.core_grid)
	if not _is_adjacent_to_city_footprint(unit.grid, footprint):
		var candidates := _build_city_entry_ring_targets(footprint)
		var best_path: Array[Vector2i] = []
		for candidate in candidates:
			var p: Array[Vector2i] = grid_rules.build_path(unit, candidate)
			if p.is_empty():
				continue
			if best_path.is_empty() or p.size() < best_path.size():
				best_path = p
		if best_path.is_empty():
			_last_army_brief = "军事操作: 入城失败，无可达邻格"
			_append_action_log("entry: failed NO_ADJACENT_PATH")
			_update_status()
			return
		await _move_unit_along_path(unit, best_path)
	_try_disband_demo_unit()

func _get_city_footprint_cells(city_id: String, fallback_core: Vector2i) -> Array[Vector2i]:
	if _city_footprint_cells.has(city_id):
		var footprint_map: Dictionary = _city_footprint_cells[city_id]
		var cells: Array[Vector2i] = []
		for cell in footprint_map.keys():
			cells.append(cell)
		return cells
	return [fallback_core] + _hex_neighbors(fallback_core)

func _build_city_entry_ring_targets(footprint: Array[Vector2i]) -> Array[Vector2i]:
	var footprint_map := {}
	for cell in footprint:
		footprint_map[cell] = true
	var ring_map := {}
	for cell in footprint:
		for neighbor in _hex_neighbors(cell):
			if footprint_map.has(neighbor):
				continue
			ring_map[neighbor] = true
	var result: Array[Vector2i] = []
	for cell in ring_map.keys():
		result.append(cell)
	return result

func _is_adjacent_to_city_footprint(unit_cell: Vector2i, footprint: Array[Vector2i]) -> bool:
	for cell in footprint:
		if _hex_distance(unit_cell, cell) == 1:
			return true
	return false

func _move_unit_along_path(unit, path: Array[Vector2i]) -> void:
	var city = _game_manager.get_city("City-A") if _game_manager != null else null
	if city == null:
		return
	var units: Array = _game_manager.get_faction_units(_game_manager.get_current_faction_id())
	var grid_rules = HEX_GRID_RULES_SCRIPT.new()
	grid_rules.setup([city.core_grid], units)
	_is_animating_move = true
	for step in path:
		var step_ret: Dictionary = grid_rules.move_unit_one_step(unit, step)
		if not step_ret.get("ok", false):
			break
		_sync_unit_visual(unit)
		_refresh_selection_highlight()
		await get_tree().create_timer(STEP_MOVE_INTERVAL_SEC).timeout
		if int(unit.remaining_move_points) <= 0:
			break
	_is_animating_move = false

func _update_status() -> void:
	var mode_text := "KayKit未检测到，当前使用几何占位渲染"
	if _kaykit_ready:
		mode_text = "KayKit目录已检测到(Assets/gltf)"
	if _kaykit_ready and _kaykit_models_ready:
		mode_text += " | 全部使用KayKit资源渲染"
	elif _kaykit_ready:
		mode_text += " | 模型尚未完成Godot导入(请等导入或重开编辑器)"
	var city_text := "城市数据未初始化"
	var turn_text := ""
	var selection_text := "选中: 无"
	if _selected_type == "city":
		selection_text = "选中: 城市 %s" % _selected_id
	elif _selected_type == "unit":
		selection_text = "选中: 部队 %s" % _selected_id
	selection_text += " | 交互: 左键选中/移动 右键取消"
	_refresh_selection_highlight()
	if _game_manager != null:
		turn_text = "回合T%d 当前势力:%s | 快捷键[C编制 M移动 E入城 T月结算 Space结束势力回合 R重置]" % [
			_game_manager.get_turn_count(),
			_game_manager.get_current_faction_id()
		]
		var cities = _game_manager.get_all_cities()
		if not cities.is_empty():
			var city = cities[0]
			city_text = "城市[%s] 人口:%d 治安:%d 耐久:%d/%d 金:%d 粮:%d 兵源:%d 兵役:%d" % [
				city.id, city.population, city.security, city.durability, city.durability_max,
				city.money, city.food, city.troop_source, city.conscription
			]
	_status_label.text = "%s\n地形渲染: 平原/森林/山地/水域/沙地 | %s\n%s\n%s\n%s\n%s" % [
		_camera_controller.build_status_text(),
		mode_text,
		turn_text,
		selection_text,
		city_text,
		"%s | %s" % [_last_settlement_brief, _last_army_brief]
	]
