extends Node
class_name BotHeroInput

## Controller for a Hero. It only writes the Hero intent fields and calls the
## same slot/reload methods as PlayerHeroInput. All decisions are hero agnostic.

@export var skill: BotSkill = preload("res://resources/ai/normal.tres")
@export var seed: int = 1

static var profile_usec: int = 0
static var profile_ticks: int = 0

var hero: Hero
var intent: StringName = &"idle"
var stance: StringName = &"neutral"
var goal: Vector2
var target: Hero
var visible_enemies: Array[Hero] = []
var last_seen_position: Vector2
var last_seen_time: float = -INF
var action: StringName = &"idle"

var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _strategy_left: float = 0.0
var _perception_left: float = 0.0
var _commit_until: float = 0.0
var _reaction_until: float = 0.0
var _aim_error: float = 0.0
var _charge_started: Dictionary = {}
var _held_started: Dictionary = {}
var _last_position: Vector2
var _stuck_elapsed: float = 0.0
var _avoid_side: float = 1.0
var _last_note: int = -1
var _current_phrase: RhythmPhrase
var _navigation: BotNavigation
var _path := PackedVector2Array()
var _path_goal: Vector2
var _path_index: int = 0
var _dodge_start: float = INF
var _dodge_until: float = -INF
var _dodge_direction: Vector2
var _seen_threats: Dictionary = {}


func _ready() -> void:
	hero = get_parent() as Hero
	_rng.seed = seed
	goal = hero.global_position
	_last_position = goal
	# Spread expensive sight and strategy work across physics frames.
	_strategy_left = _rng.randf_range(0.0, BotRules.current().strategy_interval)
	_perception_left = _rng.randf_range(0.0, BotRules.current().perception_interval)
	set_physics_process(true)


func _exit_tree() -> void:
	stop()


func stop() -> void:
	if not is_instance_valid(hero):
		return
	hero.move_direction = Vector2.ZERO
	for slot in GameRules.current().slots:
		var ability := hero.get_ability(slot.id)
		if ability != null and (ability.is_charging() or ability.is_held()):
			hero.release_slot(slot.id, hero.aim_point)
	_charge_started.clear()
	_held_started.clear()


func _physics_process(delta: float) -> void:
	if hero == null or hero.health_component.is_dead():
		return
	if target != null and not is_instance_valid(target):
		target = null
	var rules := BotRules.current()
	var started := Time.get_ticks_usec() if rules.profile_bots else 0
	var manager := MatchManager.find(get_tree())
	if manager != null and manager.state == MatchManager.State.ENDED:
		stop()
		return
	_time += delta
	_perception_left -= delta
	if _perception_left <= 0.0:
		_perception_left = BotRules.current().perception_interval
		_perceive(manager)
	_strategy_left -= delta
	if _strategy_left <= 0.0:
		_strategy_left = BotRules.current().strategy_interval
		_choose_goal(manager)
	_run_tactics(delta)
	if rules.profile_bots:
		profile_usec += Time.get_ticks_usec() - started
		profile_ticks += 1


func _perceive(manager: MatchManager) -> void:
	visible_enemies.clear()
	var actors: Array[Hero] = manager.get_roster() if manager != null else _all_heroes()
	for enemy in actors:
		if enemy == hero or enemy.team == hero.team or enemy.health_component.is_dead():
			continue
		if enemy.global_position.distance_to(hero.global_position) > BotRules.current().enemy_search_radius:
			continue
		if _team_can_see(enemy, actors):
			visible_enemies.append(enemy)
	var next := _best_target()
	if next != target:
		_reaction_until = _time + skill.reaction_time
		_aim_error = deg_to_rad(_rng.randf_range(-skill.aim_error_degrees, skill.aim_error_degrees))
	target = next
	if target != null:
		last_seen_position = target.global_position
		last_seen_time = _time
	elif _time - last_seen_time > skill.memory_time:
		last_seen_time = -INF
	_perceive_threats()


func _perceive_threats() -> void:
	var rules := BotRules.current()
	for id in _seen_threats.keys():
		if _time - float(_seen_threats[id]) > rules.dodge_memory_seconds:
			_seen_threats.erase(id)
	for node in get_tree().get_nodes_in_group(&"bot_projectiles"):
		var projectile := node as Projectile
		if projectile == null or projectile.data == null or projectile.damage_template == null:
			continue
		if CombatQueries.team_of(projectile.damage_template.source) == hero.team:
			continue
		if projectile.global_position.distance_to(hero.global_position) > rules.dodge_scan_radius:
			continue
		if not CombatQueries.walls_clear(hero, projectile):
			continue
		var id := projectile.get_instance_id()
		if _seen_threats.has(id):
			continue
		var relative_velocity := projectile.direction * projectile.data.speed - hero.velocity
		var approach := hero.global_position - projectile.global_position
		var duration := clampf(approach.dot(relative_velocity) / maxf(relative_velocity.length_squared(), 1.0),
			0.0, rules.dodge_horizon)
		var closest := projectile.global_position + relative_velocity * duration
		if closest.distance_to(hero.global_position) > projectile.data.radius + rules.navigation_actor_radius + rules.dodge_margin:
			continue
		_seen_threats[id] = _time
		if _rng.randf() > skill.dodge_chance:
			continue
		var side := projectile.direction.orthogonal().normalized()
		if (hero.global_position - closest).dot(side) < 0.0:
			side = -side
		_start_dodge(side, skill.reaction_time)
	for node in get_tree().get_nodes_in_group(&"bot_zones"):
		var zone := node as GroundZone
		if zone == null or zone.data == null or zone.data.shape == null:
			continue
		if CombatQueries.team_of(zone.source) == hero.team or not CombatQueries.walls_clear(hero, zone):
			continue
		if zone.global_position.distance_to(hero.global_position) > zone.data.shape.get_reach() + rules.navigation_actor_radius:
			continue
		var away := (hero.global_position - zone.global_position).normalized()
		if away != Vector2.ZERO:
			_start_dodge(away, 0.0)


func _start_dodge(direction: Vector2, delay: float) -> void:
	_dodge_direction = direction
	_dodge_start = _time + delay
	_dodge_until = _dodge_start + BotRules.current().dodge_duration


func _all_heroes() -> Array[Hero]:
	var result: Array[Hero] = []
	for node in get_tree().get_nodes_in_group(&"heroes"):
		if node is Hero:
			result.append(node)
	return result


func _team_can_see(enemy: Hero, actors: Array[Hero]) -> bool:
	for ally in actors:
		if ally.team == hero.team and not ally.health_component.is_dead() \
				and CombatQueries.has_line_of_sight(ally, enemy):
			return true
	return false


func _best_target() -> Hero:
	var best: Hero
	var best_score := -INF
	var rules := BotRules.current()
	for enemy in visible_enemies:
		var distance := hero.global_position.distance_to(enemy.global_position)
		var health_fraction := enemy.health_component.current_health / maxf(enemy.health_component.max_health, 1.0)
		var carrier := MoteCarrier.find_on(enemy)
		var score := rules.target_low_health_weight * (1.0 - health_fraction) \
			- rules.target_distance_weight * distance
		if carrier != null:
			score += rules.target_carrier_weight * carrier.get_mote_value()
		if score > best_score:
			best_score = score
			best = enemy
	return best


func _choose_goal(manager: MatchManager) -> void:
	var rules := BotRules.current()
	var carrier := MoteCarrier.find_on(hero)
	var carried := carrier.get_mote_count() if carrier != null else 0
	var health_fraction := hero.health_component.current_health / maxf(hero.health_component.max_health, 1.0)
	var home := Dreamer.find_for(get_tree(), hero.team)
	var enemy_dreamer := Dreamer.find_for(get_tree(), MatchManager.other_team(hero.team))
	if home != null and home.state == Dreamer.State.STIRRING:
		_set_goal(&"defend", &"aggressive", home.global_position, true)
		return
	if health_fraction <= rules.retreat_health_fraction and home != null and target != null:
		_set_goal(&"retreat", &"avoid", home.global_position, true)
		return
	if carried > 0 and home != null and health_fraction <= rules.bank_health_fraction:
		_set_goal(&"bank", &"avoid", home.global_position, true)
		return
	if carried >= rules.deliver_min_motes and enemy_dreamer != null:
		_set_goal(&"deliver", &"neutral", enemy_dreamer.global_position)
		return
	if _time < _commit_until and intent == &"collect" and hero.global_position.distance_to(goal) > rules.goal_reached_distance:
		return
	var best_score := -INF
	var best_mote: Mote
	if carrier == null or carrier.can_pick_up():
		for node in get_tree().get_nodes_in_group(Mote.GROUP):
			var mote := node as Mote
			if mote == null or mote.state == Mote.State.MAGNET:
				continue
			var distance := hero.global_position.distance_to(mote.global_position)
			if distance > rules.mote_search_radius:
				continue
			# The Dream Mote has a public beam. Ordinary Motes need team sight.
			if not mote.data.is_dream and not _team_can_see_point(mote.global_position, manager):
				continue
			var score := rules.objective_mote_weight + mote.value \
				+ (rules.objective_dream_mote_bonus if mote.data.is_dream else 0.0) \
				- distance * rules.objective_distance_weight
			if score > best_score:
				best_score = score
				best_mote = mote
	if best_mote != null:
		_set_goal(&"collect", &"neutral", best_mote.global_position)
	elif carried > 0 and enemy_dreamer != null:
		_set_goal(&"deliver", &"neutral", enemy_dreamer.global_position)
	elif target != null:
		_set_goal(&"hunt", &"aggressive", target.global_position)
	elif _time - last_seen_time <= skill.memory_time:
		_set_goal(&"search", &"neutral", last_seen_position)
	elif home != null:
		_set_goal(&"patrol", &"neutral", home.global_position.lerp(Vector2.ZERO, 0.55))
	else:
		_set_goal(&"patrol", &"neutral", Vector2.ZERO)


func _team_can_see_point(point: Vector2, manager: MatchManager) -> bool:
	var allies: Array[Hero] = manager.get_roster(hero.team) if manager != null else _all_heroes()
	for ally in allies:
		if ally.team != hero.team or ally.health_component.is_dead():
			continue
		var query := PhysicsRayQueryParameters2D.create(ally.global_position, point, GameRules.current().sight_mask)
		if ally.global_position.distance_to(point) < BotRules.current().enemy_search_radius \
				and ally.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false


func _set_goal(next_intent: StringName, next_stance: StringName, point: Vector2, urgent: bool = false) -> void:
	if not urgent and _time < _commit_until and intent != next_intent:
		return
	if intent != next_intent:
		_commit_until = _time + BotRules.current().goal_commit_time
	intent = next_intent
	stance = next_stance
	goal = point


func _run_tactics(delta: float) -> void:
	var rules := BotRules.current()
	var host := MinigameHost.find_on(hero)
	if host != null and host.is_playing():
		hero.move_direction = Vector2.ZERO
		return  # MinigameHost uses its own bot_input() when no input is supplied.
	_play_rhythm()
	var fight := target != null and _time >= _reaction_until and not rules.strategy_only
	var can_attack := fight and CombatQueries.has_line_of_sight(hero, target)
	var destination := goal
	var desired_range := _preferred_range()
	if can_attack:
		if stance == &"avoid":
			destination = goal
		else:
			destination = target.global_position
			var distance := hero.global_position.distance_to(destination)
			if distance <= desired_range * rules.attack_range_fraction:
				# Keep spacing, especially when using a ranged primary.
				destination = hero.global_position
				if distance < desired_range * rules.too_close_range_fraction:
					destination = hero.global_position + (hero.global_position - target.global_position).normalized() * desired_range
	if intent == &"hunt" and target != null:
		goal = target.global_position
	if not can_attack or stance == &"avoid":
		destination = _path_destination(destination)
	var to_goal := destination - hero.global_position
	var direction := to_goal.normalized() if to_goal.length() > rules.goal_reached_distance else Vector2.ZERO
	var dodging := _time >= _dodge_start and _time < _dodge_until
	if dodging:
		direction = _dodge_direction
	if direction != Vector2.ZERO:
		direction = _avoid_walls(direction)
	_update_stuck(delta, direction)
	hero.move_direction = direction
	if can_attack:
		var aim := target.global_position + target.velocity * rules.aim_lead_seconds
		_set_aim(aim)
		_use_abilities()
		action = &"dodge" if dodging else &"fight"
	else:
		_set_aim(destination)
		_release_inactive_slots()
		action = &"dodge" if dodging else intent
	var gun := hero.get_reload_ability()
	if gun != null and gun.has_magazine() and (gun.get_ammo() == 0 or not fight):
		hero.reload()


func _preferred_range() -> float:
	var primary := hero.get_ability(&"primary")
	if primary != null and primary.data != null and primary.data.get_range() > 0.0:
		return primary.data.get_range()
	return BotRules.current().default_attack_range


func _set_aim(point: Vector2) -> void:
	var vector := point - hero.global_position
	if vector.length_squared() <= 1.0:
		return
	hero.aim_direction = vector.rotated(_aim_error).normalized()
	hero.aim_point = hero.global_position + hero.aim_direction * vector.length()


func _use_abilities() -> void:
	var rules := BotRules.current()
	for slot in GameRules.current().slots:
		var ability := hero.get_ability(slot.id)
		if ability == null or ability.data == null or ability is PassiveAbility:
			continue
		var target_point := hero.aim_point
		if ability.data.ally_targeting != null:
			var ally := _needy_ally()
			if ally == null:
				continue
			target_point = ally.global_position
		if ability.is_charging():
			if not _charge_started.has(slot.id):
				_charge_started[slot.id] = _time
			var fraction := lerpf(rules.charge_fraction, 1.0, skill.ability_timing_accuracy)
			if _time - float(_charge_started.get(slot.id, _time)) >= ability.data.charge_time_max * fraction:
				hero.release_slot(slot.id, target_point)
				_charge_started.erase(slot.id)
			continue
		if ability.is_held():
			if not _held_started.has(slot.id):
				_held_started[slot.id] = _time
			if _time - float(_held_started.get(slot.id, _time)) >= rules.held_duration:
				hero.release_slot(slot.id, target_point)
				_held_started.erase(slot.id)
			continue
		var range_limit := ability.data.get_range()
		if range_limit > 0.0 and hero.global_position.distance_to(target_point) > range_limit * rules.ability_range_fraction:
			continue
		if not ability.is_ready() and not ability.repeats_while_held(slot.hold_to_repeat):
			continue
		if hero.request_slot(slot.id, target_point):
			if ability.is_charging():
				_charge_started[slot.id] = _time
			if ability.is_held():
				_held_started[slot.id] = _time


func _needy_ally() -> Hero:
	var manager := MatchManager.find(get_tree())
	var allies: Array[Hero] = manager.get_roster(hero.team) if manager != null else _all_heroes()
	var best: Hero
	var fraction := BotRules.current().wounded_ally_fraction
	for ally in allies:
		if ally.team != hero.team or ally.health_component.is_dead():
			continue
		var hp := ally.health_component.current_health / maxf(ally.health_component.max_health, 1.0)
		if hp < fraction:
			fraction = hp
			best = ally
	return best


func _release_inactive_slots() -> void:
	for slot in GameRules.current().slots:
		var ability := hero.get_ability(slot.id)
		if ability != null and (ability.is_charging() or ability.is_held()):
			hero.release_slot(slot.id, hero.aim_point)
	_charge_started.clear()
	_held_started.clear()


func _play_rhythm() -> void:
	var performer := RhythmPerformer.find_on(hero)
	if performer == null or not performer.is_playing():
		_last_note = -1
		_current_phrase = null
		return
	if performer.phrase != _current_phrase:
		_current_phrase = performer.phrase
		_last_note = -1
	for index in performer.phrase.note_count:
		if index <= _last_note:
			continue
		if performer.time >= performer.phrase.get_beat_time(index):
			performer.press_note()
			_last_note = index
		break


func _path_destination(wanted: Vector2) -> Vector2:
	if _navigation == null:
		_navigation = BotNavigation.for_actor(hero)
	if _navigation == null:
		return wanted
	var cell := BotRules.current().navigation_cell_size
	if _path.is_empty() or wanted.distance_to(_path_goal) > cell:
		_path = _navigation.path(hero.global_position, wanted)
		_path_goal = wanted
		_path_index = 0
	if _path.is_empty():
		return wanted
	# Skipping to a nearby later point handles arrival from a directed map
	# shortcut, including a jump pad's forced flight.
	for index in range(_path_index, _path.size()):
		if hero.global_position.distance_to(_path[index]) < cell * BotRules.current().waypoint_reached_fraction:
			if _navigation.teleport_entries.has(_path[index]) and index + 1 < _path.size() \
					and _path[index + 1] == _navigation.teleport_entries[_path[index]]:
				_path_index = index
				return _path[index]  # Stay on the pad through its channel.
			_path_index = index + 1
	if _path_index >= _path.size():
		return wanted
	return _path[_path_index]


func _avoid_walls(direction: Vector2) -> Vector2:
	var rules := BotRules.current()
	var state := hero.get_world_2d().direct_space_state
	var mask := MapLayers.WORLD | MapLayers.LOW_COVER | MapLayers.LEDGES | MapLayers.BARRIERS
	var from := hero.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + direction * rules.obstacle_probe_distance, mask)
	query.exclude = [hero.get_rid()]
	if state.intersect_ray(query).is_empty():
		return direction
	for side in [_avoid_side, -_avoid_side]:
		var candidate := direction.rotated(rules.obstacle_avoid_angle * side)
		query.to = from + candidate * rules.obstacle_probe_distance
		if state.intersect_ray(query).is_empty():
			_avoid_side = side
			return candidate
	return direction.rotated(rules.obstacle_avoid_angle * _avoid_side)


func _update_stuck(delta: float, direction: Vector2) -> void:
	if direction == Vector2.ZERO or hero.global_position.distance_to(_last_position) > BotRules.current().goal_reached_distance:
		_last_position = hero.global_position
		_stuck_elapsed = 0.0
		return
	_stuck_elapsed += delta
	if _stuck_elapsed >= BotRules.current().stuck_time:
		_avoid_side *= -1.0
		_path.clear()
		_stuck_elapsed = 0.0
