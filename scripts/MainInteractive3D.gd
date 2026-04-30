extends Node3D

const CAMERA_CONTROLLER_SCRIPT := preload("res://scripts/CameraController3D.gd")
const GRID_RADIUS := 24
const HEX_SIZE := 1.2

@onready var _camera: Camera3D = $Camera3D
@onready var _status_label: Label = $CanvasLayer/StatusLabel
@onready var _grid_root: Node3D = $GridRoot

var _map_min := Vector2(-40.0, -40.0)
var _map_max := Vector2(40.0, 40.0)
var _camera_controller

func _ready() -> void:
	_build_hex_markers()
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

func _build_hex_markers() -> void:
	for child in _grid_root.get_children():
		child.queue_free()

	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var p := _axial_to_world(Vector2i(q, r))
			var marker := MeshInstance3D.new()
			marker.mesh = SphereMesh.new()
			marker.scale = Vector3(0.10, 0.10, 0.10)
			marker.position = Vector3(p.x, 0.0, p.y)
			_grid_root.add_child(marker)

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
	_status_label.text = _camera_controller.build_status_text()
