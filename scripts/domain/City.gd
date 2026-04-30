extends RefCounted
class_name CityData

enum CityLevel {
	SMALL,
	MEDIUM,
	LARGE,
	METROPOLIS
}

enum CityWarState {
	PEACE,
	INVASION,
	SIEGE
}

var id: String
var owner_faction_id: String
var core_grid: Vector2i
var level: CityLevel = CityLevel.SMALL
var war_state: CityWarState = CityWarState.PEACE

var population := 800000
var security := 80
var durability := 5000
var durability_max := 5000

var money := 30000
var food := 50000
var troop_source := 6000
var wounded_troop_source := 0
var conscription := 4000
var catapult_stock := 1
var catapult_progress := 0.0
var max_composable_forces := 4
var max_recruitable_troop_source := 6000
var composed_forces_this_turn := 0
var recruited_troop_source_this_turn := 0
var accept_capacity_snapshot := {}
var weapon_stock := {
	"SPEAR": 6000,
	"HALBERD": 6000,
	"BOW": 5000,
	"HORSE": 4000
}

func _init(p_id: String, p_owner_faction_id: String, p_core_grid: Vector2i) -> void:
	id = p_id
	owner_faction_id = p_owner_faction_id
	core_grid = p_core_grid

func update_level_by_population() -> void:
	if population >= 1500000:
		level = CityLevel.METROPOLIS
	elif population >= 1000000:
		level = CityLevel.LARGE
	elif population >= 500000:
		level = CityLevel.MEDIUM
	else:
		level = CityLevel.SMALL

func city_coeff() -> float:
	match level:
		CityLevel.SMALL:
			return 0.8
		CityLevel.MEDIUM:
			return 1.0
		CityLevel.LARGE:
			return 1.2
		CityLevel.METROPOLIS:
			return 1.5
		_:
			return 1.0
