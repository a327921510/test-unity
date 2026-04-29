extends RefCounted
class_name ArmyComposer

const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const REASON_CODES := preload("res://scripts/common/ReasonCodes.gd")

func compose_unit(
	city,
	unit_id: String,
	faction_id: String,
	arms_type: int,
	spawn_grid: Vector2i,
	troop_source: int,
	weapon_type: String,
	food: int,
	money: int
) -> Dictionary:
	if city.owner_faction_id != faction_id:
		return {"ok": false, "reason": REASON_CODES.CITY_OWNER_MISMATCH}
	if troop_source <= 0:
		return {"ok": false, "reason": REASON_CODES.INVALID_TROOP_SOURCE}
	if city.troop_source < troop_source:
		return {"ok": false, "reason": REASON_CODES.CITY_TROOP_SOURCE_NOT_ENOUGH}
	if city.weapon_stock.get(weapon_type, 0) < troop_source:
		return {"ok": false, "reason": REASON_CODES.CITY_WEAPON_NOT_ENOUGH}

	var taken_food: int = min(food, city.food)
	var taken_money: int = min(money, city.money)
	city.troop_source -= troop_source
	city.weapon_stock[weapon_type] = city.weapon_stock.get(weapon_type, 0) - troop_source
	city.food -= taken_food
	city.money -= taken_money

	var unit = UNIT_DATA_SCRIPT.new(unit_id, faction_id, arms_type, spawn_grid, _default_move(arms_type))
	unit.troop_source = troop_source
	unit.weapon_amount = troop_source
	unit.food = taken_food
	unit.money = taken_money
	_apply_arm_stats(unit)
	return {"ok": true, "unit": unit}

func disband_into_city(unit, city) -> Dictionary:
	if city.owner_faction_id != unit.faction_id:
		return {"ok": false, "reason": REASON_CODES.CITY_OWNER_MISMATCH}

	var returned := {
		"troop_source": unit.troop_source,
		"wounded_troop_source": unit.wounded_troop_source,
		"food": unit.food,
		"money": unit.money
	}
	city.troop_source += unit.troop_source
	city.wounded_troop_source += unit.wounded_troop_source
	city.food += unit.food
	city.money += unit.money
	return {"ok": true, "returned": returned}

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

func _apply_arm_stats(unit) -> void:
	match unit.arms_type:
		UNIT_DATA_SCRIPT.ArmsType.CAVALRY:
			unit.attack = 90
			unit.defense = 60
		UNIT_DATA_SCRIPT.ArmsType.SPEARMAN:
			unit.attack = 80
			unit.defense = 70
		UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD:
			unit.attack = 70
			unit.defense = 85
		UNIT_DATA_SCRIPT.ArmsType.ARCHER:
			unit.attack = 75
			unit.defense = 55
			unit.ranged_attack = 95
		UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
			unit.attack = 40
			unit.defense = 70
			unit.ranged_attack = 60
			unit.siege_power = 260
		UNIT_DATA_SCRIPT.ArmsType.TRANSPORT:
			unit.attack = 20
			unit.defense = 35
