extends Node

const CITY_DATA_SCRIPT := preload("res://scripts/domain/City.gd")
const CITY_MANAGER_SCRIPT := preload("res://scripts/core/CityManager.gd")
const TURN_MANAGER_SCRIPT := preload("res://scripts/core/TurnManager.gd")
const ARMY_COMPOSER_SCRIPT := preload("res://scripts/core/ArmyComposer.gd")

signal monthly_settlement_completed(turn_count: int, settlement: Dictionary)
signal game_state_reset()

var _city_manager := CITY_MANAGER_SCRIPT.new()
var _turn_manager := TURN_MANAGER_SCRIPT.new()
var _army_composer := ARMY_COMPOSER_SCRIPT.new()
var _cities: Dictionary = {}
var _factions: Array[String] = ["A", "B"]
var _faction_units: Dictionary = {"A": [], "B": []}

func _ready() -> void:
	reset_demo_state()

func reset_demo_state() -> void:
	_cities.clear()
	for faction in _faction_units.keys():
		_faction_units[faction].clear()
	var city_a = CITY_DATA_SCRIPT.new("City-A", "A", Vector2i(0, 0))
	city_a.population = 820000
	city_a.security = 78
	city_a.update_level_by_population()
	city_a.durability_max = _durability_max_for_level(city_a.level)
	city_a.durability = city_a.durability_max
	_cities[city_a.id] = city_a

	_turn_manager.setup(_factions, _faction_units)
	game_state_reset.emit()

func get_turn_count() -> int:
	return _turn_manager.current_turn_count()

func get_current_faction_id() -> String:
	return _turn_manager.current_faction_id()

func get_all_cities() -> Array:
	return _cities.values()

func get_city(city_id: String):
	return _cities.get(city_id)

func get_faction_units(faction_id: String) -> Array:
	return _faction_units.get(faction_id, [])

func end_faction_turn() -> Dictionary:
	var before_turn := _turn_manager.current_turn_count()
	_turn_manager.end_turn()
	_reset_city_compose_usage()
	var settlement: Dictionary = {}
	if _turn_manager.current_turn_count() > before_turn:
		settlement = run_monthly_settlement()
	return {
		"turn_count": _turn_manager.current_turn_count(),
		"current_faction_id": _turn_manager.current_faction_id(),
		"monthly_settlement": settlement
	}

func compose_and_dispatch(
	city_id: String,
	unit_id: String,
	arms_type: int,
	spawn_grid: Vector2i,
	troop_source: int,
	weapon_type: String,
	food: int,
	money: int
) -> Dictionary:
	var city = _cities.get(city_id)
	if city == null:
		return {"ok": false, "reason": "CITY_NOT_FOUND"}
	var faction_id: String = city.owner_faction_id
	var ret: Dictionary = _army_composer.compose_unit(
		city,
		unit_id,
		faction_id,
		arms_type,
		spawn_grid,
		troop_source,
		weapon_type,
		food,
		money,
		_turn_manager.current_faction_id()
	)
	if not ret.get("ok", false):
		return ret
	var unit = ret.get("unit")
	_faction_units[faction_id].append(unit)
	return ret

func disband_unit_into_city(unit, city_id: String, require_adjacent: bool = true) -> Dictionary:
	var city = _cities.get(city_id)
	if city == null:
		return {"ok": false, "reason": "CITY_NOT_FOUND"}
	var ret: Dictionary = _army_composer.disband_into_city(
		unit,
		city,
		city.core_grid,
		require_adjacent,
		_build_city_footprint(city.core_grid)
	)
	if not ret.get("ok", false):
		return ret
	_faction_units[unit.faction_id].erase(unit)
	return ret

func run_monthly_settlement() -> Dictionary:
	var settlement := {}
	for city_id in _cities.keys():
		var city = _cities[city_id]
		var monthly_delta: Dictionary = _city_manager.monthly_settlement(city, _turn_manager.current_turn_count())
		settlement[city_id] = {
			"delta": monthly_delta,
			"snapshot": _city_snapshot(city)
		}
	monthly_settlement_completed.emit(_turn_manager.current_turn_count(), settlement)
	return settlement

func _city_snapshot(city) -> Dictionary:
	return {
		"id": city.id,
		"owner_faction_id": city.owner_faction_id,
		"level": city.level,
		"population": city.population,
		"security": city.security,
		"durability": city.durability,
		"durability_max": city.durability_max,
		"money": city.money,
		"food": city.food,
		"troop_source": city.troop_source,
		"conscription": city.conscription,
		"wounded_troop_source": city.wounded_troop_source
	}

func _durability_max_for_level(level: int) -> int:
	match level:
		CITY_DATA_SCRIPT.CityLevel.SMALL:
			return 3000
		CITY_DATA_SCRIPT.CityLevel.MEDIUM:
			return 5000
		CITY_DATA_SCRIPT.CityLevel.LARGE:
			return 8000
		CITY_DATA_SCRIPT.CityLevel.METROPOLIS:
			return 12000
		_:
			return 5000

func _reset_city_compose_usage() -> void:
	for city in _cities.values():
		city.composed_forces_this_turn = 0
		city.recruited_troop_source_this_turn = 0

func _build_city_footprint(core: Vector2i) -> Array[Vector2i]:
	return [
		core,
		core + Vector2i(1, 0),
		core + Vector2i(1, -1),
		core + Vector2i(0, -1),
		core + Vector2i(-1, 0),
		core + Vector2i(-1, 1),
		core + Vector2i(0, 1)
	]
