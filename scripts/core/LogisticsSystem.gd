extends RefCounted
class_name LogisticsSystem

const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")

func supply(transport, target, payload: Dictionary, is_reachable: bool) -> Dictionary:
	if not is_reachable:
		return {"ok": false, "reason": "SUPPLY_OUT_OF_RANGE"}
	if transport.arms_type != UNIT_DATA_SCRIPT.ArmsType.TRANSPORT:
		return {"ok": false, "reason": "NOT_TRANSPORT_UNIT"}
	if transport.execution_state != UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED:
		return {"ok": false, "reason": "TRANSPORT_ALREADY_EXECUTED"}
	if transport.supply_action_used_this_turn:
		return {"ok": false, "reason": "SUPPLY_ACTION_LIMIT_REACHED"}

	var add_troop: int = int(payload.get("troop_source", 0))
	var add_food: int = int(payload.get("food", 0))
	var add_money: int = int(payload.get("money", 0))
	var max_troop_by_weapon: int = min(transport.weapon_amount, target.troop_source + target.weapon_amount)
	add_troop = min(add_troop, transport.troop_source, max_troop_by_weapon)
	add_food = min(add_food, transport.food)
	add_money = min(add_money, transport.money)

	if add_troop <= 0 and add_food <= 0 and add_money <= 0:
		return {"ok": false, "reason": "NOTHING_TO_SUPPLY"}

	var old_troop: int = target.troop_source
	var old_tp: float = target.tactic_point
	if add_troop > 0:
		transport.troop_source -= add_troop
		transport.weapon_amount -= add_troop
		target.troop_source += add_troop
		target.weapon_amount += add_troop
		target.tactic_point = (float(add_troop) * transport.tactic_point + float(old_troop) * old_tp) / float(old_troop + add_troop)
	if add_food > 0:
		transport.food -= add_food
		target.food += add_food
	if add_money > 0:
		transport.money -= add_money
		target.money += add_money

	transport.supply_action_used_this_turn = true
	transport.mark_executed()
	return {
		"ok": true,
		"delta": {"troop_source": add_troop, "food": add_food, "money": add_money},
		"target_tactic_point": target.tactic_point
	}

func apply_starvation(unit) -> Dictionary:
	if unit.food > 0:
		unit.starvation_penalty_ratio = 0.0
		return {"triggered": false, "loss": 0}

	var loss := int(floor(unit.troop_source * 0.10))
	var real_loss: int = unit.apply_loss(loss)
	unit.starvation_penalty_ratio = 0.10
	return {"triggered": true, "loss": real_loss}
