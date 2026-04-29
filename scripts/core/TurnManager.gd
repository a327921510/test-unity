extends RefCounted
class_name TurnManager

var _faction_order: Array[String] = []
var _faction_units: Dictionary = {}
var _current_faction_idx := 0
var _turn_count := 1

func setup(factions: Array[String], faction_units: Dictionary) -> void:
	_faction_order = factions.duplicate()
	_faction_units = faction_units
	_current_faction_idx = 0
	_turn_count = 1
	_reset_current_faction_units()

func current_faction_id() -> String:
	if _faction_order.is_empty():
		return ""
	return _faction_order[_current_faction_idx]

func current_turn_count() -> int:
	return _turn_count

func end_turn() -> void:
	_mark_current_faction_executed()
	if _faction_order.is_empty():
		return
	_current_faction_idx = (_current_faction_idx + 1) % _faction_order.size()
	if _current_faction_idx == 0:
		_turn_count += 1
	_reset_current_faction_units()

func _reset_current_faction_units() -> void:
	var faction := current_faction_id()
	for unit in _faction_units.get(faction, []):
		unit.reset_turn_state()

func _mark_current_faction_executed() -> void:
	var faction := current_faction_id()
	for unit in _faction_units.get(faction, []):
		unit.mark_executed()
