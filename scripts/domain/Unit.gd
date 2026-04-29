extends RefCounted
class_name UnitData

enum ArmsType {
	CAVALRY,
	SPEARMAN,
	HALBERD_SHIELD,
	ARCHER,
	CATAPULT,
	TRANSPORT
}

enum ExecutionState {
	UNEXECUTED,
	EXECUTED
}

var id: String
var faction_id: String
var arms_type: ArmsType
var grid: Vector2i
var move_points: int
var remaining_move_points: int
var execution_state: ExecutionState = ExecutionState.UNEXECUTED
var troop_source: int = 1000
var weapon_amount: int = 1000
var wounded_troop_source: int = 0
var money: int = 1000
var food: int = 1000
var tactic_point: float = 100.0
var is_routed: bool = false
var attack: int = 80
var defense: int = 60
var ranged_attack: int = 60
var ranged_defense: int = 55
var siege_power: int = 120
var starvation_penalty_ratio: float = 0.0
var supply_action_used_this_turn: bool = false

func _init(
	p_id: String,
	p_faction_id: String,
	p_arms_type: ArmsType,
	p_grid: Vector2i,
	p_move_points: int
) -> void:
	id = p_id
	faction_id = p_faction_id
	arms_type = p_arms_type
	grid = p_grid
	move_points = p_move_points
	remaining_move_points = p_move_points

func reset_turn_state() -> void:
	execution_state = ExecutionState.UNEXECUTED
	remaining_move_points = move_points
	supply_action_used_this_turn = false

func mark_executed() -> void:
	execution_state = ExecutionState.EXECUTED
	remaining_move_points = 0

func apply_loss(loss: int) -> int:
	var real_loss: int = min(loss, troop_source)
	troop_source -= real_loss
	var weapon_loss: int = min(real_loss, weapon_amount)
	weapon_amount -= weapon_loss
	var wounded_delta := int(floor(real_loss * 0.4))
	wounded_troop_source += wounded_delta
	if troop_source <= 0:
		is_routed = true
		wounded_troop_source = 0
	return real_loss
