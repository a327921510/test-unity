extends SceneTree

const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const CITY_DATA_SCRIPT := preload("res://scripts/domain/City.gd")
const HEX_GRID_RULES_SCRIPT := preload("res://scripts/map/HexGridRules.gd")
const ARMY_COMPOSER_SCRIPT := preload("res://scripts/core/ArmyComposer.gd")
const CITY_MANAGER_SCRIPT := preload("res://scripts/core/CityManager.gd")
const LOGISTICS_SYSTEM_SCRIPT := preload("res://scripts/core/LogisticsSystem.gd")
const COMBAT_SYSTEM_SCRIPT := preload("res://scripts/core/CombatSystem.gd")

var _failed := false

func _init() -> void:
	randomize()
	var city = CITY_DATA_SCRIPT.new("City-A", "A", Vector2i(2, 2))
	var attacker = UNIT_DATA_SCRIPT.new("A-1", "A", UNIT_DATA_SCRIPT.ArmsType.SPEARMAN, Vector2i(0, 0), 3)
	var defender = UNIT_DATA_SCRIPT.new("B-1", "B", UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD, Vector2i(1, 0), 3)
	var transport = UNIT_DATA_SCRIPT.new("A-T", "A", UNIT_DATA_SCRIPT.ArmsType.TRANSPORT, Vector2i(0, 1), 4)
	transport.food = 2000
	transport.money = 1000
	transport.troop_source = 1000
	transport.weapon_amount = 1000

	var grid = HEX_GRID_RULES_SCRIPT.new()
	var city_cells: Array[Vector2i] = [city.core_grid]
	grid.setup(city_cells, [attacker, defender, transport])
	var composer = ARMY_COMPOSER_SCRIPT.new()
	var city_mgr = CITY_MANAGER_SCRIPT.new()
	var logistics = LOGISTICS_SYSTEM_SCRIPT.new()
	var combat = COMBAT_SYSTEM_SCRIPT.new()

	var compose_ret: Dictionary = composer.compose_unit(
		city, "A-N1", "A", UNIT_DATA_SCRIPT.ArmsType.CAVALRY, Vector2i(-1, 0), 500, "HORSE", 400, 300
	)
	_assert(compose_ret["ok"], "compose should pass")

	var supply_ret: Dictionary = logistics.supply(transport, attacker, {"troop_source": 100, "food": 200, "money": 100}, true)
	_assert(supply_ret["ok"], "supply should pass")

	var battle_ret: Dictionary = combat.resolve_battle(attacker, defender, 1.0)
	_assert(battle_ret["ok"], "battle should pass")

	attacker.execution_state = UNIT_DATA_SCRIPT.ExecutionState.UNEXECUTED
	city.owner_faction_id = "B"
	attacker.grid = Vector2i(2, 1)
	grid.remove_unit(attacker)
	grid.register_unit(attacker)
	var siege_ret: Dictionary = combat.resolve_siege(attacker, city)
	_assert(siege_ret["ok"], "siege should pass")

	var settle_ret: Dictionary = city_mgr.monthly_settlement(city)
	_assert(settle_ret["food_delta"] >= 0, "monthly settlement should produce food")
	if _failed:
		return
	print("TEST_PASS: full rule loop smoke test passed.")
	quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("TEST_FAIL: %s" % msg)
		quit(1)
