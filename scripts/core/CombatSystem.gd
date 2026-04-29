extends RefCounted
class_name CombatSystem

const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const CITY_DATA_SCRIPT := preload("res://scripts/domain/City.gd")
const REASON_CODES := preload("res://scripts/common/ReasonCodes.gd")

func resolve_battle(attacker, defender, terrain_damage_coeff := 1.0) -> Dictionary:
	if attacker.execution_state != UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED:
		return {"ok": false, "reason": REASON_CODES.ATTACKER_ALREADY_EXECUTED}

	var hit_rate: float = clampf(0.75 + 0.05 - 0.05, 0.1, 0.95)
	var hit_roll: float = randf()
	var logs: Array[String] = []
	var defender_loss := 0
	var attacker_loss := 0
	var defender_wounded := 0
	var attacker_wounded := 0

	if hit_roll <= hit_rate:
		var counter_coeff: float = _arms_counter_coeff(attacker.arms_type, defender.arms_type)
		var status_coeff: float = 1.0 - attacker.starvation_penalty_ratio
		var attack_value: int = attacker.ranged_attack if attacker.arms_type == UNIT_DATA_SCRIPT.ArmsType.ARCHER else attacker.attack
		var defense_value: int = defender.ranged_defense if attacker.arms_type == UNIT_DATA_SCRIPT.ArmsType.ARCHER else defender.defense
		var damage := int(floor(max(1.0, float(attack_value - defense_value)) * counter_coeff * terrain_damage_coeff * status_coeff))
		if attacker.arms_type == UNIT_DATA_SCRIPT.ArmsType.ARCHER:
			damage = int(floor(float(damage) * 1.2))
		if attacker.arms_type == UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
			damage = int(floor(float(damage) * 0.7))
		defender_loss = defender.apply_loss(damage)
		defender_wounded = int(floor(float(defender_loss) * 0.4))
		logs.append("命中，伤害=%d" % defender_loss)
	else:
		logs.append("未命中")

	if defender.troop_source > 0 and hit_roll <= hit_rate:
		var counter_damage := int(floor(max(1.0, float(defender.attack - attacker.defense)) * 0.6))
		attacker_loss = attacker.apply_loss(counter_damage)
		attacker_wounded = int(floor(float(attacker_loss) * 0.4))
		logs.append("反击伤害=%d" % attacker_loss)

	attacker.mark_executed()
	return {
		"ok": true,
		"attacker_loss": attacker_loss,
		"defender_loss": defender_loss,
		"attacker_wounded_delta": attacker_wounded,
		"defender_wounded_delta": defender_wounded,
		"attacker_routed": attacker.is_routed,
		"defender_routed": defender.is_routed,
		"logs": logs
	}

func resolve_siege(attacker, city) -> Dictionary:
	if attacker.execution_state != UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED:
		return {"ok": false, "reason": REASON_CODES.ATTACKER_ALREADY_EXECUTED}
	if attacker.faction_id == city.owner_faction_id:
		return {"ok": false, "reason": REASON_CODES.SAME_FACTION_CITY}

	var siege_type_coeff: float = 1.0
	if attacker.arms_type == UNIT_DATA_SCRIPT.ArmsType.CATAPULT:
		siege_type_coeff = 1.8
	var status_coeff: float = 1.0 - attacker.starvation_penalty_ratio
	var siege_damage := int(floor(float(attacker.siege_power) * siege_type_coeff * 1.0 * status_coeff))
	var city_durability_delta: int = -min(siege_damage, city.durability)
	city.durability += city_durability_delta

	var city_troop_delta: int = -min(int(floor(float(attacker.attack) * 0.2)), city.troop_source)
	city.troop_source += city_troop_delta
	var breached: bool = city.durability <= 0 or city.troop_source <= 0
	var owner_changed: bool = false
	if breached:
		city.owner_faction_id = attacker.faction_id
		city.war_state = CITY_DATA_SCRIPT.CityWarState.PEACE
		city.durability = max(500, city.durability_max / 4)
		city.troop_source = max(800, city.troop_source)
		owner_changed = true
	else:
		city.war_state = CITY_DATA_SCRIPT.CityWarState.SIEGE

	attacker.mark_executed()
	return {
		"ok": true,
		"city_durability_delta": city_durability_delta,
		"city_troop_source_delta": city_troop_delta,
		"is_city_breached": breached,
		"city_owner_changed": owner_changed,
		"new_owner_faction_id": city.owner_faction_id,
		"city_under_attack": true,
		"battle_occurred_in_region": true
	}

func _arms_counter_coeff(attacker_arms: int, defender_arms: int) -> float:
	if attacker_arms == UNIT_DATA_SCRIPT.ArmsType.CAVALRY and defender_arms == UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD:
		return 1.25
	if attacker_arms == UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD and defender_arms == UNIT_DATA_SCRIPT.ArmsType.SPEARMAN:
		return 1.25
	if attacker_arms == UNIT_DATA_SCRIPT.ArmsType.SPEARMAN and defender_arms == UNIT_DATA_SCRIPT.ArmsType.CAVALRY:
		return 1.25
	return 1.0
