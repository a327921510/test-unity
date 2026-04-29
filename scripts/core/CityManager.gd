extends RefCounted
class_name CityManager

const CITY_DATA_SCRIPT := preload("res://scripts/domain/City.gd")

const BASE_MONEY_PER_POP := 0.12
const BASE_FOOD_PER_POP := 0.18
const BASE_WEAPON_PER_POP := 0.02
const BASE_TROOP_SOURCE_PER_POP := 0.015
const CONSCRIPTION_GAIN_RATE_PER_TURN := 0.001
const WOUNDED_RECOVERY_RATE_PER_TURN := 0.1

func monthly_settlement(city) -> Dictionary:
	city.update_level_by_population()
	_apply_security_decay(city)
	var war_penalty: float = _war_penalty(city.war_state)
	var security_factor: float = 0.5 + float(city.security) / 200.0
	var low_security_factor: float = 0.5 if city.security < 50 else 1.0
	var coeff: float = city.city_coeff()

	var money_output := int(floor(city.population * BASE_MONEY_PER_POP * coeff * security_factor * war_penalty * low_security_factor))
	var food_output := int(floor(city.population * BASE_FOOD_PER_POP * coeff * security_factor * war_penalty * low_security_factor))
	var weapon_output := int(floor(city.population * BASE_WEAPON_PER_POP * coeff * security_factor * war_penalty * low_security_factor))
	var troop_output := int(floor(city.population * BASE_TROOP_SOURCE_PER_POP * coeff * security_factor * war_penalty * low_security_factor))
	var conscription_gain := int(floor(city.population * CONSCRIPTION_GAIN_RATE_PER_TURN))

	var wounded_factor := 1.0
	if city.war_state == CITY_DATA_SCRIPT.CityWarState.INVASION:
		wounded_factor = 0.8
	elif city.war_state == CITY_DATA_SCRIPT.CityWarState.SIEGE:
		wounded_factor = 0.5
	var wounded_recovery := int(floor(city.wounded_troop_source * WOUNDED_RECOVERY_RATE_PER_TURN * wounded_factor))

	city.money += money_output
	city.food += food_output
	city.troop_source += troop_output + wounded_recovery
	city.conscription += conscription_gain
	city.wounded_troop_source -= wounded_recovery
	city.durability = min(city.durability + _durability_recovery(city.level), city.durability_max)
	city.weapon_stock["SPEAR"] = city.weapon_stock.get("SPEAR", 0) + weapon_output

	_apply_population_growth(city)
	return {
		"money_delta": money_output,
		"food_delta": food_output,
		"weapon_delta": weapon_output,
		"troop_source_delta": troop_output,
		"conscription_delta": conscription_gain,
		"wounded_recovery_delta": wounded_recovery
	}

func recruit_once(city) -> Dictionary:
	var consume := 1500
	match city.level:
		CITY_DATA_SCRIPT.CityLevel.SMALL:
			consume = 1000
		CITY_DATA_SCRIPT.CityLevel.MEDIUM:
			consume = 1500
		CITY_DATA_SCRIPT.CityLevel.LARGE:
			consume = 2000
		CITY_DATA_SCRIPT.CityLevel.METROPOLIS:
			consume = 2500
	var real_consume: int = min(consume, city.conscription)
	city.conscription -= real_consume
	city.troop_source += real_consume
	return {"conscription_cost": real_consume, "troop_source_gain": real_consume}

func _apply_security_decay(city) -> void:
	city.security = max(city.security - 2, 0)
	if city.war_state == CITY_DATA_SCRIPT.CityWarState.INVASION:
		city.security = max(city.security - 2, 0)
	if city.war_state == CITY_DATA_SCRIPT.CityWarState.SIEGE:
		city.security = max(city.security - 4, 0)

func _war_penalty(war_state: int) -> float:
	match war_state:
		CITY_DATA_SCRIPT.CityWarState.PEACE:
			return 1.0
		CITY_DATA_SCRIPT.CityWarState.INVASION:
			return 0.9
		CITY_DATA_SCRIPT.CityWarState.SIEGE:
			return 0.01
		_:
			return 1.0

func _durability_recovery(level: int) -> int:
	match level:
		CITY_DATA_SCRIPT.CityLevel.SMALL:
			return 60
		CITY_DATA_SCRIPT.CityLevel.MEDIUM:
			return 90
		CITY_DATA_SCRIPT.CityLevel.LARGE:
			return 130
		CITY_DATA_SCRIPT.CityLevel.METROPOLIS:
			return 180
		_:
			return 90

func _apply_population_growth(city) -> void:
	var growth_rate := 0.003
	var threshold := 55
	match city.level:
		CITY_DATA_SCRIPT.CityLevel.SMALL:
			growth_rate = 0.002
			threshold = 45
		CITY_DATA_SCRIPT.CityLevel.MEDIUM:
			growth_rate = 0.003
			threshold = 55
		CITY_DATA_SCRIPT.CityLevel.LARGE:
			growth_rate = 0.004
			threshold = 65
		CITY_DATA_SCRIPT.CityLevel.METROPOLIS:
			growth_rate = 0.005
			threshold = 75

	if city.war_state == CITY_DATA_SCRIPT.CityWarState.SIEGE:
		city.population -= int(floor(city.population * 0.002))
		return
	if city.security < threshold:
		return

	var war_factor: float = 1.0 if city.war_state == CITY_DATA_SCRIPT.CityWarState.PEACE else 0.4
	var security_bonus := 1.0 + float(city.security - threshold) / 100.0
	city.population += int(floor(city.population * growth_rate * security_bonus * war_factor))
