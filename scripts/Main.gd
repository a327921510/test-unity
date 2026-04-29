extends Node2D

const RULE_CONFIGS_SCRIPT := preload("res://scripts/config/RuleConfigs.gd")
const TURN_MANAGER_SCRIPT := preload("res://scripts/core/TurnManager.gd")
const UNIT_DATA_SCRIPT := preload("res://scripts/domain/Unit.gd")
const CITY_DATA_SCRIPT := preload("res://scripts/domain/City.gd")
const HEX_GRID_RULES_SCRIPT := preload("res://scripts/map/HexGridRules.gd")
const ARMY_COMPOSER_SCRIPT := preload("res://scripts/core/ArmyComposer.gd")
const CITY_MANAGER_SCRIPT := preload("res://scripts/core/CityManager.gd")
const LOGISTICS_SYSTEM_SCRIPT := preload("res://scripts/core/LogisticsSystem.gd")
const COMBAT_SYSTEM_SCRIPT := preload("res://scripts/core/CombatSystem.gd")

const HEX_SIZE := 30.0
const GRID_RADIUS := 4
const ORIGIN := Vector2(640, 360)

var _turn_manager
var _grid_rules
var _army_composer
var _city_manager
var _logistics
var _combat
var _unit_a
var _unit_b
var _unit_transport
var _city_alpha
var _unit_list: Array = []
var _status_text := ""

func _ready() -> void:
	_initialize_demo()
	_update_status("启动完成。按键: M移动 C编制 E入城 S补给 F野战 G攻城 T月结算 Space结束回合 R重置。")
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				_try_move_current_unit()
			KEY_C:
				_try_compose_unit()
			KEY_E:
				_try_city_entry_disband()
			KEY_S:
				_try_supply()
			KEY_F:
				_try_battle()
			KEY_G:
				_try_siege()
			KEY_T:
				_run_monthly_settlement()
			KEY_SPACE:
				_apply_turn_end_logistics()
				_turn_manager.end_turn()
				_update_status("结束回合，当前势力：%s，回合：%d" % [_turn_manager.current_faction_id(), _turn_manager.current_turn_count()])
			KEY_R:
				_initialize_demo()
				_update_status("已重置演示状态。")
			_:
				return
		queue_redraw()

func _draw() -> void:
	_draw_grid()
	_draw_city_block_preview()
	_draw_city_label(_city_alpha)
	_draw_unit(_unit_a, Color(0.2, 0.7, 1.0), "A")
	_draw_unit(_unit_b, Color(1.0, 0.4, 0.4), "B")
	_draw_unit(_unit_transport, Color(0.7, 1.0, 0.4), "T")

func _initialize_demo() -> void:
	_army_composer = ARMY_COMPOSER_SCRIPT.new()
	_city_manager = CITY_MANAGER_SCRIPT.new()
	_logistics = LOGISTICS_SYSTEM_SCRIPT.new()
	_combat = COMBAT_SYSTEM_SCRIPT.new()
	_city_alpha = CITY_DATA_SCRIPT.new("City-A", "A", Vector2i(2, 2))

	_unit_a = UNIT_DATA_SCRIPT.new("A-1", "A", UNIT_DATA_SCRIPT.ArmsType.SPEARMAN, Vector2i(0, 0), 3)
	_unit_b = UNIT_DATA_SCRIPT.new("B-1", "B", UNIT_DATA_SCRIPT.ArmsType.HALBERD_SHIELD, Vector2i(3, 0), 3)
	_unit_transport = UNIT_DATA_SCRIPT.new("A-T", "A", UNIT_DATA_SCRIPT.ArmsType.TRANSPORT, Vector2i(0, 1), 4)
	_unit_transport.food = 3500
	_unit_transport.money = 1500
	_unit_transport.troop_source = 1500
	_unit_transport.weapon_amount = 1500
	_unit_b.food = 0

	_turn_manager = TURN_MANAGER_SCRIPT.new()
	var factions: Array[String] = ["A", "B"]
	_turn_manager.setup(
		factions,
		{
			"A": [_unit_a, _unit_transport],
			"B": [_unit_b]
		}
	)

	_grid_rules = HEX_GRID_RULES_SCRIPT.new()
	var city_cells: Array[Vector2i] = [Vector2i(2, 2)]
	_unit_list = [_unit_a, _unit_b, _unit_transport]
	_grid_rules.setup(city_cells, _unit_list)

	print("RULE_FREEZE_VERSION=", RULE_CONFIGS_SCRIPT.RULE_FREEZE_VERSION)
	print("Current faction=", _turn_manager.current_faction_id(), ", turn=", _turn_manager.current_turn_count())

func _try_move_current_unit() -> void:
	var faction: String = _turn_manager.current_faction_id()
	var unit = _unit_a if faction == "A" else _unit_b
	if unit.execution_state == UNIT_DATA_SCRIPT.ExecutionState.EXECUTED:
		_update_status("势力 %s 主战单位已执行，无法移动。" % faction)
		return
	var target: Vector2i = unit.grid + (Vector2i(1, 0) if faction == "A" else Vector2i(-1, 0))
	var result: Dictionary = _grid_rules.try_move_unit(unit, target)
	var reason: int = result["reason"]
	_update_status(
		"势力 %s 尝试移动到 %s，结果=%s，剩余行动力=%d" % [
			faction,
			str(target),
			_reason_to_text(reason),
			unit.remaining_move_points
		]
	)

func _try_compose_unit() -> void:
	var faction: String = _turn_manager.current_faction_id()
	if faction != "A":
		_update_status("仅在 A 势力回合演示编制。")
		return
	var spawn := Vector2i(-1, 0)
	var result: Dictionary = _army_composer.compose_unit(
		_city_alpha, "A-N%s" % str(Time.get_unix_time_from_system()), "A",
		UNIT_DATA_SCRIPT.ArmsType.CAVALRY, spawn, 800, "HORSE", 1200, 800
	)
	if not result["ok"]:
		_update_status("编制失败：%s" % result["reason"])
		return
	var new_unit = result["unit"]
	_unit_list.append(new_unit)
	_grid_rules.register_unit(new_unit)
	_update_status("编制成功：%s 已出征，城市兵源=%d，城市粮=%d" % [new_unit.id, _city_alpha.troop_source, _city_alpha.food])

func _try_city_entry_disband() -> void:
	if not _grid_rules.is_city_entry_allowed(_unit_a, _city_alpha.core_grid):
		_update_status("入城失败：需相邻城市且未执行且剩余行动力>0。")
		return
	var result: Dictionary = _army_composer.disband_into_city(_unit_a, _city_alpha)
	if not result["ok"]:
		_update_status("入城失败：%s" % result["reason"])
		return
	_grid_rules.remove_unit(_unit_a)
	_unit_a.is_routed = true
	_update_status("入城拆解成功：回库兵源=%d，城市兵源=%d，城市伤员=%d" % [
		result["returned"]["troop_source"], _city_alpha.troop_source, _city_alpha.wounded_troop_source
	])

func _try_supply() -> void:
	var reachable: bool = _grid_rules.is_supply_reachable(_unit_transport.grid, _unit_a.grid)
	var result: Dictionary = _logistics.supply(_unit_transport, _unit_a, {"troop_source": 300, "food": 600, "money": 200}, reachable)
	if not result["ok"]:
		_update_status("补给失败：%s" % result["reason"])
		return
	_update_status("补给成功：兵源+%d 粮+%d 钱+%d，目标战法点=%.1f" % [
		result["delta"]["troop_source"], result["delta"]["food"], result["delta"]["money"], result["target_tactic_point"]
	])

func _try_battle() -> void:
	if _grid_rules.hex_distance(_unit_a.grid, _unit_b.grid) > 1:
		_update_status("战斗失败：目标不在相邻格。")
		return
	var result: Dictionary = _combat.resolve_battle(_unit_a, _unit_b, 1.0)
	if not result["ok"]:
		_update_status("战斗失败：%s" % result["reason"])
		return
	if _unit_b.is_routed:
		_grid_rules.remove_unit(_unit_b)
	_update_status("野战完成：敌损=%d 我损=%d；%s" % [
		result["defender_loss"], result["attacker_loss"], ",".join(result["logs"])
	])

func _try_siege() -> void:
	if not _grid_rules.is_adjacent(_unit_a.grid, _city_alpha.core_grid):
		_update_status("攻城失败：需要在城市邻格。")
		return
	var result: Dictionary = _combat.resolve_siege(_unit_a, _city_alpha)
	if not result["ok"]:
		_update_status("攻城失败：%s" % result["reason"])
		return
	_update_status("攻城完成：耐久变化=%d，城内兵源变化=%d，破城=%s，易主=%s(%s)" % [
		result["city_durability_delta"], result["city_troop_source_delta"],
		str(result["is_city_breached"]), str(result["city_owner_changed"]), result["new_owner_faction_id"]
	])

func _run_monthly_settlement() -> void:
	var result: Dictionary = _city_manager.monthly_settlement(_city_alpha)
	_update_status("月结算：钱+%d 粮+%d 兵器+%d 兵源+%d(含伤员恢复+%d) 征兵+%d" % [
		result["money_delta"], result["food_delta"], result["weapon_delta"], result["troop_source_delta"],
		result["wounded_recovery_delta"], result["conscription_delta"]
	])

func _apply_turn_end_logistics() -> void:
	for unit in _unit_list:
		if unit == null or unit.is_routed:
			continue
		var starve: Dictionary = _logistics.apply_starvation(unit)
		if starve["triggered"]:
			print("STARVATION unit=%s loss=%d" % [unit.id, starve["loss"]])

func _update_status(text: String) -> void:
	_status_text = "Freeze=%s | 当前势力=%s | 回合=%d\n%s" % [
		RULE_CONFIGS_SCRIPT.RULE_FREEZE_VERSION,
		_turn_manager.current_faction_id(),
		_turn_manager.current_turn_count(),
		text
	]
	var label: Label = get_node_or_null("HelloLabel")
	if label != null:
		label.text = _status_text

func _draw_grid() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s := -q - r
			if abs(s) > GRID_RADIUS:
				continue
			var center := _axial_to_pixel(Vector2i(q, r))
			var points := PackedVector2Array()
			for i in range(6):
				var angle := PI / 180.0 * (60.0 * i - 30.0)
				points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(0.35, 0.35, 0.35), 1.5)

func _draw_city_block_preview() -> void:
	var center := _axial_to_pixel(_city_alpha.core_grid)
	draw_circle(center, HEX_SIZE * 0.4, Color(0.9, 0.75, 0.25, 0.8))
	for cell in _grid_rules.neighbors(_city_alpha.core_grid):
		draw_circle(_axial_to_pixel(cell), HEX_SIZE * 0.16, Color(0.9, 0.75, 0.25, 0.35))

func _draw_city_label(city) -> void:
	var center := _axial_to_pixel(city.core_grid)
	var font := ThemeDB.fallback_font
	if font != null:
		var t := "City:%s HP:%d/%d TS:%d Owner:%s" % [city.id, city.durability, city.durability_max, city.troop_source, city.owner_faction_id]
		draw_string(font, center + Vector2(-120, -HEX_SIZE * 0.8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.95, 0.7))

func _draw_unit(unit, color: Color, tag: String) -> void:
	if unit == null or unit.is_routed:
		return
	var center := _axial_to_pixel(unit.grid)
	draw_circle(center, HEX_SIZE * 0.35, color)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, center + Vector2(-6, 5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)

func _axial_to_pixel(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + cell.y * 0.5)
	var y := HEX_SIZE * 1.5 * cell.y
	return ORIGIN + Vector2(x, y)

func _reason_to_text(reason: int) -> String:
	match reason:
		HEX_GRID_RULES_SCRIPT.MoveReason.OK:
			return "OK"
		HEX_GRID_RULES_SCRIPT.MoveReason.TARGET_OCCUPIED:
			return "TARGET_OCCUPIED"
		HEX_GRID_RULES_SCRIPT.MoveReason.TARGET_BLOCKED_BY_CITY:
			return "TARGET_BLOCKED_BY_CITY"
		HEX_GRID_RULES_SCRIPT.MoveReason.INSUFFICIENT_MOVE_POINT:
			return "INSUFFICIENT_MOVE_POINT"
		HEX_GRID_RULES_SCRIPT.MoveReason.STOPPED_BY_ZOC:
			return "STOPPED_BY_ZOC"
		_:
			return "UNKNOWN"
