extends Node

# Measures hero damage in-engine against a stationary dummy (no armor or
# magic resist, can't die), for balance comparisons:
#
#   sustained(hero_path, level)  primary only, held/clicked for SUSTAIN_TIME;
#                                damage per second (reloads/regen included)
#   burst(hero_path, level)      a scripted combo of the hero's damaging
#                                non-ultimate abilities plus primary fire,
#                                total damage in BURST_TIME
#
# Each run spawns a fresh hero and dummy, so runs don't affect each other.
# Used by tools/heroes/dps_compare (a report) and cosmo_test (assertions).

const DUMMY := "res://scenes/training_dummy.tscn"
const SUSTAIN_TIME := 8.0
const BURST_TIME := 3.0
const TARGET_OFFSET := Vector2(350, 0)

var _dealt: float = 0.0
var _hero: Hero
var _dummy: TrainingDummy


func sustained(hero_path: String, level: int) -> float:
	await _setup(hero_path, level)
	await _hold_primary(SUSTAIN_TIME)
	var result := _dealt / SUSTAIN_TIME
	await _teardown()
	return result


func burst(hero_path: String, level: int) -> float:
	await _setup(hero_path, level)
	var id := _hero.definition.hero_id
	match id:
		&"cosmo": await _burst_cosmo()
		&"jose": await _burst_jose()
		&"avery": await _burst_avery()
		&"melody": await _burst_melody()
		_: await _hold_primary(BURST_TIME)
	var result := _dealt
	await _teardown()
	return result


# --- Combos (BURST_TIME each) -------------------------------------------------

# Crescent -> Tide -> the whole moon volley once Moonlit is at full.
func _burst_cosmo() -> void:
	var at := _dummy.global_position
	_hero.request_slot(&"ability_1", at)
	await _seconds(0.25)
	_hero.request_slot(&"cc", at)
	await _seconds(0.85)    # the crescent is back: Moonlit at full
	var gun := _hero.get_ranged_ability()
	var left := BURST_TIME - 1.1
	while left > 0.0:
		if gun.get_ammo() > 0:
			_hero.request_slot(&"primary", at)
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()


# A perfect Last Word, then revolvers.
func _burst_jose() -> void:
	var at := _dummy.global_position
	_hero.request_slot(&"ability_1", at)
	await _seconds(1.15)
	_hero.release_slot(&"ability_1", at)
	await _hold_primary(BURST_TIME - 1.15)


# Searing Cut and Dawnbreaker, then the combo.
func _burst_avery() -> void:
	var at := _dummy.global_position
	_hero.global_position = at - Vector2(120, 0)
	_aim()
	_hero.request_slot(&"ability_1", at)
	await _seconds(0.6)
	_hero.request_slot(&"cc", at)
	await _seconds(0.6)
	await _hold_primary(BURST_TIME - 1.2)


# A fully wound bash, then notes.
func _burst_melody() -> void:
	var at := _dummy.global_position
	_hero.request_slot(&"movement", at)
	await _seconds(0.8)
	_hero.release_slot(&"movement", at)
	await _seconds(0.4)
	await _hold_primary(BURST_TIME - 1.2)


# --- Plumbing -----------------------------------------------------------------

func _setup(hero_path: String, level: int) -> void:
	_dealt = 0.0
	_hero = load(hero_path).instantiate()
	_hero.team = &"a"
	_hero.start_level = level
	add_child(_hero)
	_hero.global_position = Vector2.ZERO
	_dummy = load(DUMMY).instantiate()
	_dummy.position = TARGET_OFFSET
	_dummy.reset_delay = 999.0
	_dummy.can_die = false
	_dummy.max_health = 1000000.0
	add_child(_dummy)
	CombatEvents.damage_dealt.connect(_on_damage)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_aim()


func _teardown() -> void:
	CombatEvents.damage_dealt.disconnect(_on_damage)
	_hero.queue_free()
	_dummy.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _on_damage(info: DamageInfo) -> void:
	if info.source == _hero and info.target == _dummy:
		_dealt += info.final_amount


func _aim() -> void:
	_hero.aim_point = _dummy.global_position
	_hero.aim_direction = (_dummy.global_position - _hero.global_position).normalized()


func _hold_primary(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_aim()
		_hero.request_slot(&"primary", _dummy.global_position)
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
