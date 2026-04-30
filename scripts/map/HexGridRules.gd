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

func get_reachable_tiles(unit) -> Array[Vector2i]:
	var reachable_map: Dictionary = {}
	var frontier: Array[Vector2i] = [unit.grid]
	var best_cost: Dictionary = {unit.grid: 0}
	while frontier.size() > 0:
		var current: Vector2i = frontier.pop_front()
		var current_cost: int = best_cost[current]
		for next_cell in neighbors(current):
			if _city_blocked_cells.has(next_cell):
				continue
			if _occupied_cells.has(next_cell) and _occupied_cells[next_cell] != unit:
				continue
			var next_cost := current_cost + 1
			if next_cost > unit.remaining_move_points:
				continue
			if not best_cost.has(next_cell) or next_cost < best_cost[next_cell]:
				best_cost[next_cell] = next_cost
				frontier.append(next_cell)
				if next_cell != unit.grid:
					reachable_map[next_cell] = true
	var result: Array[Vector2i] = []
	for cell in reachable_map.keys():
		result.append(cell)
	return result

func is_tile_reachable(unit, tile: Vector2i) -> bool:
	if tile == unit.grid:
		return true
	for reachable in get_reachable_tiles(unit):
		if reachable == tile:
			return true
	return false

func build_path(unit, target: Vector2i) -> Array[Vector2i]:
	if target == unit.grid:
		return []
	if _city_blocked_cells.has(target):
		return []
	if _occupied_cells.has(target) and _occupied_cells[target] != unit:
		return []
	var frontier: Array[Vector2i] = [unit.grid]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {unit.grid: 0}
	var f_score: Dictionary = {unit.grid: hex_distance(unit.grid, target)}
	while frontier.size() > 0:
		var current: Vector2i = _pop_lowest_f(frontier, f_score)
		if current == target:
			break
		for next_cell in neighbors(current):
			if _city_blocked_cells.has(next_cell):
				continue
			if _occupied_cells.has(next_cell) and _occupied_cells[next_cell] != unit and next_cell != target:
				continue
			var tentative_g: int = int(g_score.get(current, 1_000_000_000)) + 1
			if tentative_g > unit.remaining_move_points:
				continue
			if tentative_g < int(g_score.get(next_cell, 1_000_000_000)):
				came_from[next_cell] = current
				g_score[next_cell] = tentative_g
				f_score[next_cell] = tentative_g + hex_distance(next_cell, target)
				if not frontier.has(next_cell):
					frontier.append(next_cell)
	if not came_from.has(target):
		return []
	var reverse_path: Array[Vector2i] = []
	var cursor: Vector2i = target
	while cursor != unit.grid:
		reverse_path.append(cursor)
		cursor = came_from[cursor]
	reverse_path.reverse()
	return reverse_path

func _pop_lowest_f(frontier: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best_idx := 0
	var best_cell: Vector2i = frontier[0]
	var best_f: int = int(f_score.get(best_cell, 1_000_000_000))
	for idx in range(1, frontier.size()):
		var cell: Vector2i = frontier[idx]
		var score: int = int(f_score.get(cell, 1_000_000_000))
		if score < best_f:
			best_f = score
			best_idx = idx
			best_cell = cell
	frontier.remove_at(best_idx)
	return best_cell

func move_unit_one_step(unit, next_cell: Vector2i) -> Dictionary:
	if not is_adjacent(unit.grid, next_cell):
		return {"ok": false, "reason": MoveReason.INSUFFICIENT_MOVE_POINT}
	return try_move_unit(unit, next_cell)

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
