extends RefCounted
class_name ArmyComposer

const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const REASON_CODES := preload("res://scripts/common/ReasonCodes.gd")
const UNIT_MONEY_CAP_FIXED := 10000
const UNIT_FOOD_CAP_TURN_SPAN := 20

const ARMS_WEAPON_MAPPING := {
	UNIT_DATA_SCRIPT.ArmsType.CAVALRY: "HORSE",
	UNIT_DATA_SCRIPT.ArmsType.SPEARMAN: "SPEAR",
	UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD: "HALBERD",
	UNIT_DATA_SCRIPT.ArmsType.ARCHER: "BOW",
	UNIT_DATA_SCRIPT.ArmsType.CATAPULT: "CATAPULT",
	UNIT_DATA_SCRIPT.ArmsType.TRANSPORT: "SPEAR"
}

const ARMS_FOOD_COST := {
	UNIT_DATA_SCRIPT.ArmsType.CAVALRY: 2,
	UNIT_DATA_SCRIPT.ArmsType.SPEARMAN: 1,
	UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD: 1,
	UNIT_DATA_SCRIPT.ArmsType.ARCHER: 1,
	UNIT_DATA_SCRIPT.ArmsType.CATAPULT: 3,
	UNIT_DATA_SCRIPT.ArmsType.TRANSPORT: 1
}

func compose_unit(
	city,
	unit_id: String,
	faction_id: String,
	arms_type: int,
	spawn_grid: Vector2i,
	troop_source: int,
	weapon_type: String,
	food: int,
	money: int,
	current_turn_faction_id: String = ""
) -> Dictionary:
	if city.owner_faction_id != faction_id:
		return {"ok": false, "reason": REASON_CODES.CITY_OWNER_MISMATCH}
	if troop_source <= 0:
		return {"ok": false, "reason": REASON_CODES.INVALID_TROOP_SOURCE}
	if int(city.composed_forces_this_turn) >= int(city.max_composable_forces):
		return {"ok": false, "reason": REASON_CODES.CITY_COMPOSE_FORCE_CAP_REACHED}
	if int(city.recruited_troop_source_this_turn) + troop_source > int(city.max_recruitable_troop_source):
		return {"ok": false, "reason": REASON_CODES.CITY_RECRUITABLE_CAP_EXCEEDED}
	if ARMS_WEAPON_MAPPING.get(arms_type, "") != weapon_type:
		return {"ok": false, "reason": REASON_CODES.INVALID_ARMS_WEAPON_MAPPING}
	if city.troop_source < troop_source:
		return {"ok": false, "reason": REASON_CODES.CITY_TROOP_SOURCE_NOT_ENOUGH}
	if arms_type == UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
		if city.catapult_stock <= 0:
			return {"ok": false, "reason": REASON_CODES.CITY_WEAPON_NOT_ENOUGH}
	else:
		if city.weapon_stock.get(weapon_type, 0) < troop_source:
			return {"ok": false, "reason": REASON_CODES.CITY_WEAPON_NOT_ENOUGH}
	if food < 0 or money < 0:
		return {"ok": false, "reason": REASON_CODES.RESOURCE_CARRY_INVALID}

	var draft_food_cap: int = (troop_source + troop_source) * _food_cost(arms_type) * UNIT_FOOD_CAP_TURN_SPAN
	var taken_food: int = min(food, city.food, draft_food_cap)
	var taken_money: int = min(money, city.money, UNIT_MONEY_CAP_FIXED)
	if taken_food < 0 or taken_money < 0:
		return {"ok": false, "reason": REASON_CODES.RESOURCE_CARRY_INVALID}

	city.troop_source -= troop_source
	if arms_type == UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
		city.catapult_stock -= 1
	else:
		city.weapon_stock[weapon_type] = city.weapon_stock.get(weapon_type, 0) - troop_source
	city.food -= taken_food
	city.money -= taken_money
	city.composed_forces_this_turn += 1
	city.recruited_troop_source_this_turn += troop_source

	var unit = UNIT_DATA_SCRIPT.new(unit_id, faction_id, arms_type, spawn_grid, _default_move(arms_type))
	unit.troop_source = troop_source
	unit.weapon_amount = troop_source
	unit.catapult_amount = 1 if arms_type == UNIT_DATA_SCRIPT.ArmsType.CATAPULT else 0
	unit.food = taken_food
	unit.money = taken_money
	unit.wounded_troop_source = 0
	_apply_arm_stats(unit)
	unit.refresh_resource_caps(_food_cost(arms_type), UNIT_FOOD_CAP_TURN_SPAN)
	unit.clamp_carry_resources()
	unit.money_cap = UNIT_MONEY_CAP_FIXED
	unit.is_controllable_in_current_turn = current_turn_faction_id == "" or current_turn_faction_id == faction_id
	unit.execution_state = UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED
	unit.remaining_move_points = unit.move_points
	return {"ok": true, "unit": unit}

func disband_into_city(
	unit,
	city,
	city_core_grid: Vector2i = Vector2i.ZERO,
	require_adjacent: bool = false,
	city_footprint_cells: Array[Vector2i] = []
) -> Dictionary:
	if city.owner_faction_id != unit.faction_id:
		return {"ok": false, "reason": REASON_CODES.CITY_OWNER_MISMATCH}
	if require_adjacent:
		var is_adjacent := false
		if city_footprint_cells.is_empty():
			is_adjacent = _hex_distance(unit.grid, city_core_grid) == 1
		else:
			is_adjacent = _is_adjacent_to_any_cell(unit.grid, city_footprint_cells)
		if not is_adjacent:
			return {"ok": false, "reason": REASON_CODES.TARGET_NOT_ADJACENT}
	if unit.execution_state != UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED or unit.remaining_move_points <= 0:
		return {"ok": false, "reason": REASON_CODES.CITY_ENTRY_PRECHECK_FAILED}

	var capacity: Dictionary = city.accept_capacity_snapshot if city.accept_capacity_snapshot is Dictionary else {}
	if capacity.is_empty():
		capacity = {
			"troop_source": 1_000_000_000,
			"wounded_troop_source": 1_000_000_000,
			"food": 1_000_000_000,
			"money": 1_000_000_000
		}

	var requested := {
		"troop_source": unit.troop_source,
		"wounded_troop_source": unit.wounded_troop_source,
		"food": unit.food,
		"money": unit.money
	}
	var returned := {}
	var discarded := {}
	for key in requested.keys():
		var amount: int = int(requested[key])
		var accepted: int = min(amount, int(capacity.get(key, amount)))
		returned[key] = accepted
		discarded[key] = amount - accepted

	city.troop_source += int(returned["troop_source"])
	city.wounded_troop_source += int(returned["wounded_troop_source"])
	city.food += int(returned["food"])
	city.money += int(returned["money"])
	return {"ok": true, "returned": returned, "discarded": discarded}

func _default_move(arms_type: int) -> int:
	match arms_type:
		UNIT_DATA_SCRIPT.ArmsType.CAVALRY:
			return 5
		UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
			return 2
		UNIT_DATA_SCRIPT.ArmsType.TRANSPORT:
			return 4
		_:
			return 3

func _food_cost(arms_type: int) -> int:
	return int(ARMS_FOOD_COST.get(arms_type, 1))

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dq + dr) + abs(dr)) / 2)

func _is_adjacent_to_any_cell(from_cell: Vector2i, target_cells: Array[Vector2i]) -> bool:
	for cell in target_cells:
		if _hex_distance(from_cell, cell) == 1:
			return true
	return false

func _apply_arm_stats(unit) -> void:
	match unit.arms_type:
		UNIT_DATA_SCRIPT.ArmsType.CAVALRY:
			unit.attack = 90
			unit.defense = 60
			unit.int_stat = 45
			unit.build = 40
		UNIT_DATA_SCRIPT.ArmsType.SPEARMAN:
			unit.attack = 80
			unit.defense = 70
			unit.int_stat = 50
			unit.build = 55
		UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD:
			unit.attack = 70
			unit.defense = 85
			unit.int_stat = 48
			unit.build = 60
		UNIT_DATA_SCRIPT.ArmsType.ARCHER:
			unit.attack = 75
			unit.defense = 55
			unit.ranged_attack = 95
			unit.int_stat = 60
			unit.build = 45
		UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
			unit.attack = 40
			unit.defense = 70
			unit.ranged_attack = 60
			unit.siege_power = 260
			unit.int_stat = 55
			unit.build = 70
		UNIT_DATA_SCRIPT.ArmsType.TRANSPORT:
			unit.attack = 20
			unit.defense = 35
			unit.int_stat = 52
			unit.build = 50
