extends RefCounted
class_name HexGridRules

enum MoveReason {
	OK,
	TARGET_OCCUPIED,
	TARGET_BLOCKED_BY_CITY,
	INSUFFICIENT_MOVE_POINT,
	STOPPED_BY_ZOC
}

var _occupied_cells: Dictionary = {}
var _city_core_cells: Array[Vector2i] = []
var _city_blocked_cells: Dictionary = {}

func setup(city_core_cells: Array[Vector2i], units: Array) -> void:
	_city_core_cells = city_core_cells.duplicate()
	_rebuild_city_blocked_cells()
	_occupied_cells.clear()
	for unit in units:
		_occupied_cells[unit.grid] = unit

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dq + dr) + abs(dr)) / 2)

func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(1, -1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1)
	]
	var result: Array[Vector2i] = []
	for dir in dirs:
		result.append(cell + dir)
	return result

func try_move_unit(unit, target: Vector2i) -> Dictionary:
	if _occupied_cells.has(target):
		return {"ok": false, "reason": MoveReason.TARGET_OCCUPIED}
	if _city_blocked_cells.has(target):
		return {"ok": false, "reason": MoveReason.TARGET_BLOCKED_BY_CITY}

	var cost := hex_distance(unit.grid, target)
	if cost <= 0:
		return {"ok": true, "reason": MoveReason.OK}
	if unit.remaining_move_points < cost:
		return {"ok": false, "reason": MoveReason.INSUFFICIENT_MOVE_POINT}

	_occupied_cells.erase(unit.grid)
	unit.grid = target
	unit.remaining_move_points -= cost
	_occupied_cells[unit.grid] = unit

	if _is_in_enemy_zoc(unit):
		unit.remaining_move_points = 0
		return {"ok": true, "reason": MoveReason.STOPPED_BY_ZOC}
	return {"ok": true, "reason": MoveReason.OK}

func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return hex_distance(a, b) == 1

func is_city_entry_allowed(unit, city_core: Vector2i) -> bool:
	if not is_adjacent(unit.grid, city_core):
		return false
	return unit.execution_state == unit.ExecutionState.UNEXECUTED and unit.remaining_move_points > 0

func is_supply_reachable(from_grid: Vector2i, to_grid: Vector2i) -> bool:
	return is_adjacent(from_grid, to_grid)

func remove_unit(unit) -> void:
	if _occupied_cells.has(unit.grid) and _occupied_cells[unit.grid] == unit:
		_occupied_cells.erase(unit.grid)

func register_unit(unit) -> void:
	_occupied_cells[unit.grid] = unit

func _rebuild_city_blocked_cells() -> void:
	_city_blocked_cells.clear()
	for core in _city_core_cells:
		_city_blocked_cells[core] = true
		for ring_cell in neighbors(core):
			_city_blocked_cells[ring_cell] = true

func _is_in_enemy_zoc(unit) -> bool:
	for nearby in neighbors(unit.grid):
		if not _occupied_cells.has(nearby):
			continue
		var other = _occupied_cells[nearby]
		if other.faction_id != unit.faction_id:
			return true
	return false
