extends Node3D

const CAMERA_CONTROLLER_SCRIPT := preload("res://scripts/CameraController3D.gd")
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
var _kaykit_ready := false
var _kaykit_models_ready := false
var _model_cache: Dictionary = {}

func _ready() -> void:
	_setup_scene_roots()
	_setup_materials()
	_detect_kaykit_pack()
	_build_map_render()
	_recompute_map_bounds()
	_camera_controller = CAMERA_CONTROLLER_SCRIPT.new()
	_camera_controller.setup(_camera, _map_min, _map_max)
	_update_status()

func _process(delta: float) -> void:
	_camera_controller.update_frame(delta, get_viewport().get_visible_rect(), get_viewport().get_mouse_position())
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if _camera_controller.handle_input(event):
		_update_status()

func _setup_scene_roots() -> void:
	for child in _grid_root.get_children():
		child.queue_free()
	_terrain_root = Node3D.new()
	_terrain_root.name = "TerrainRoot"
	_grid_root.add_child(_terrain_root)
	_city_root = Node3D.new()
	_city_root.name = "CityRoot"
	_grid_root.add_child(_city_root)
	_unit_root = Node3D.new()
	_unit_root.name = "UnitRoot"
	_grid_root.add_child(_unit_root)

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

func _spawn_city(cell: Vector2i) -> void:
	if _kaykit_models_ready and _spawn_kaykit_scene(cell, KAYKIT_CITY_NEUTRAL, _city_root, 1.0, TILE_HEIGHT):
		return
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

func _spawn_unit(cell: Vector2i, model_path: String, tint: Color) -> void:
	if _kaykit_models_ready and _spawn_kaykit_scene(cell, model_path, _unit_root, 0.72, TILE_HEIGHT):
		return
	var p := _axial_to_world(cell)
	var unit := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.62
	unit.mesh = mesh
	unit.position = Vector3(p.x, 0.48, p.y)
	unit.material_override = _build_terrain_mat(tint)
	_unit_root.add_child(unit)

func _spawn_kaykit_scene(cell: Vector2i, scene_path: String, parent: Node3D, uniform_scale: float, y_offset: float) -> bool:
	var packed_scene := _get_kaykit_scene(scene_path)
	if packed_scene == null:
		return false
	var instance = packed_scene.instantiate()
	if instance == null or not (instance is Node3D):
		return false
	var p := _axial_to_world(cell)
	var node3d := instance as Node3D
	node3d.position = Vector3(p.x, y_offset, p.y)
	node3d.scale = Vector3.ONE * uniform_scale
	parent.add_child(node3d)
	return true

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

func _update_status() -> void:
	var mode_text := "KayKit未检测到，当前使用几何占位渲染"
	if _kaykit_ready:
		mode_text = "KayKit目录已检测到(Assets/gltf)"
	if _kaykit_ready and _kaykit_models_ready:
		mode_text += " | 全部使用KayKit资源渲染"
	elif _kaykit_ready:
		mode_text += " | 模型尚未完成Godot导入(请等导入或重开编辑器)"
	_status_label.text = "%s\n地形渲染: 平原/森林/山地/水域/沙地 | %s" % [_camera_controller.build_status_text(), mode_text]
