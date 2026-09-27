extends Node
class_name BotHeroInput

## Controller for a Hero. It only writes the Hero intent fields and calls the
## same slot/reload methods as PlayerHeroInput. All decisions are hero agnostic:
## the hero's role picks a BotRolePlan (BotRules.plan_for) and the plan's
## weights shape the strategy.
##
## Strategy (every BotRules.strategy_interval), in priority order:
##   defend a stirring home Dreamer / finish or deny a stirring enemy one,
##   retreat when low, deposit a stack (bank or deliver, by the plan), then
##   the role's job (ESCORT a carrier, PLAYMAKER hunts carriers and joins
##   teammates' fights), the Dream Mote, the nearest unclaimed Mote, and
##   otherwise ROAM: scout the Mote spawns the team hasn't seen for longest,
##   spread away from teammates' roam goals.
## Teammates' bots share their `goal_key` so two bots don't chase the same
## Mote, roam point, carrier or hunt target.
##
## Tactics (every physics tick): only enemies inside the plan's
## engage_radius (or whoever hit us recently, or a hunted target) become a
## target, so bots fight what is in front of them instead of converging on
## every fight they can see. Travelling bots (deliver, bank, retreat) shoot
## on the move instead of turning to chase.

@export var skill: BotSkill = preload("res://resources/ai/normal.tres")
@export var seed: int = 1

static var profile_usec: int = 0
static var profile_ticks: int = 0

var hero: Hero
var plan: BotRolePlan
var intent: StringName = &"idle"
var stance: StringName = &"neutral"
var goal: Vector2
## What this bot has claimed for its team ("mote:123", "roam:4",
## "escort:567", "hunt:890"); &"" = nothing exclusive.
var goal_key: StringName = &""
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
# The hero an escort / hunt / assist follows.
var _focus: Hero
# Roam points (Mote spawns) and when this bot last saw each one.
var _roam_points: Array[Vector2] = []
var _visited: Dictionary = {}    # index -> time
var _roam_index: int = -1
# Self defence: the enemy that last hurt us, and when.
var _attacker: Hero
var _attacked_time: float = -INF
# Enemy carriers the team knows about: Hero -> [position, time]. Revealed
# carriers update at their minimap ping rate.
var _known_carriers: Dictionary = {}


func _ready() -> void:
	hero = get_parent() as Hero
	_rng.seed = seed
	goal = hero.global_position
	_last_position = goal
	var role := hero.definition.role if hero.definition != null else HeroDefinition.Role.FLEX
	plan = BotRules.current().plan_for(role)
	hero.health_component.damage_taken.connect(_on_damage_taken)
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
	if _focus != null and not is_instance_valid(_focus):
		_focus = null
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


func _on_damage_taken(info: DamageInfo) -> void:
	var node := info.source
	while node != null and is_instance_valid(node) and not node is Hero:
		node = node.get_parent()
	var attacker := node as Hero
	if attacker != null and attacker.team != hero.team:
		_attacker = attacker
		_attacked_time = _time


# ---------------------------------------------------------------------------
# Perception
# ---------------------------------------------------------------------------

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
	_perceive_carriers(actors)
	_mark_roam_points()
	_perceive_threats()


# Enemy carriers the team knows of: seen ones exactly, revealed ones (the
# minimap pings) at their ping rate.
func _perceive_carriers(actors: Array[Hero]) -> void:
	for enemy in _known_carriers.keys():
		if not is_instance_valid(enemy) or enemy.health_component.is_dead():
			_known_carriers.erase(enemy)
	for enemy in actors:
		if enemy.team == hero.team or enemy.health_component.is_dead():
			continue
		var carrier := MoteCarrier.find_on(enemy)
		if carrier == null or carrier.get_mote_count() == 0:
			_known_carriers.erase(enemy)
			continue
		var interval := carrier.get_reveal_interval()
		var known: Array = _known_carriers.get(enemy, [])
		if enemy in visible_enemies or interval == 0.0:
			_known_carriers[enemy] = [enemy.global_position, _time]
		elif interval > 0.0 and (known.is_empty() or _time - float(known[1]) >= interval):
			_known_carriers[enemy] = [enemy.global_position, _time]


func _mark_roam_points() -> void:
	var points := _get_roam_points()
	var seen := BotRules.current().roam_seen_distance
	for index in points.size():
		if hero.global_position.distance_to(points[index]) <= seen:
			_visited[index] = _time


func _perceive_threats() -> void:
	var rules := BotRules.current()
	for id in _seen_threats.keys():
		if _time - float(_seen_threats[id]) > rules.dodge_memory_seconds:
			_seen_threats.erase(id)
	for node in get_tree().get_nodes_in_group(&"bot_projectiles"):
		var projectile := node as Projectile
		if projectile == null or projectile.data == null or projectile.damage_template == null:
			continue
		# The shooter may be gone (freed) while its shot is still flying.
		var shooter = projectile.damage_template.source
		if is_instance_valid(shooter) and CombatQueries.team_of(shooter) == hero.team:
			continue
		if projectile.global_position.distance_squared_to(hero.global_position) > rules.dodge_scan_radius * rules.dodge_scan_radius:
			continue
		# Cheap checks before the wall raycast.
		var id := projectile.get_instance_id()
		if _seen_threats.has(id):
			continue
		if not CombatQueries.walls_clear(hero, projectile):
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
		var owner_node = zone.source
		if is_instance_valid(owner_node) and CombatQueries.team_of(owner_node) == hero.team:
			continue
		if zone.global_position.distance_to(hero.global_position) > zone.data.shape.get_reach() + rules.navigation_actor_radius:
			continue
		if not CombatQueries.walls_clear(hero, zone):
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


# Only enemies this bot should fight: inside the plan's engage radius, the
# current target until it gets past the chase radius, whoever hit us
# recently, a hunted target, and anyone near a Dreamer we're defending.
func _best_target() -> Hero:
	var best: Hero
	var best_score := -INF
	var rules := BotRules.current()
	var defending := intent == &"defend" or intent == &"attack"
	for enemy in visible_enemies:
		var distance := hero.global_position.distance_to(enemy.global_position)
		var limit := plan.engage_radius
		if enemy == target or (enemy == _focus and intent == &"hunt") or defending:
			limit = plan.chase_radius
		if enemy == _attacker and _time - _attacked_time <= rules.self_defence_time:
			limit = maxf(limit, plan.chase_radius)
		if distance > limit:
			continue
		var health_fraction := enemy.health_component.current_health / maxf(enemy.health_component.max_health, 1.0)
		var carrier := MoteCarrier.find_on(enemy)
		var score := rules.target_low_health_weight * (1.0 - health_fraction) \
			- rules.target_distance_weight * distance
		if carrier != null:
			score += rules.target_carrier_weight * carrier.get_mote_value()
		if enemy == _focus:
			score += rules.target_low_health_weight
		if score > best_score:
			best_score = score
			best = enemy
	return best


# ---------------------------------------------------------------------------
# Strategy
# ---------------------------------------------------------------------------

func _choose_goal(manager: MatchManager) -> void:
	var rules := BotRules.current()
	var carrier := MoteCarrier.find_on(hero)
	var carried := carrier.get_mote_value() if carrier != null else 0
	var health_fraction := hero.health_component.current_health / maxf(hero.health_component.max_health, 1.0)
	var home := Dreamer.find_for(get_tree(), hero.team)
	var enemy_dreamer := Dreamer.find_for(get_tree(), MatchManager.other_team(hero.team))
	# The Dreamers first: they decide the match.
	if home != null and home.is_stirring():
		_set_goal(&"defend", &"aggressive", home.global_position, true)
		return
	if enemy_dreamer != null and enemy_dreamer.is_stirring():
		if carried > 0 and enemy_dreamer.accepts_deposits():
			_set_goal(&"deliver", &"travel", enemy_dreamer.global_position, true)
			return
		if plan.job != BotRolePlan.Job.FARM or carried > 0:
			# Stand in their ring: it pauses the Lullaby.
			_set_goal(&"attack", &"aggressive", enemy_dreamer.global_position, true)
			return
	# Low with an enemy in sight: fall back to the spawn area, which heals, and
	# stay there until healed (a reset). Without one, fall back to the Dreamer.
	var sanctuary := manager.get_sanctuary(hero.team) if manager != null else null
	var healing := intent == &"retreat" and health_fraction < rules.retreat_until_fraction
	if (health_fraction <= plan.retreat_health_fraction and target != null) or healing:
		if sanctuary != null:
			var inside := sanctuary.contains(hero.global_position)
			_set_goal(&"retreat", &"avoid", hero.global_position if inside else sanctuary.area.get_center(), true)
			return
		if home != null and target != null:
			_set_goal(&"retreat", &"avoid", home.global_position, true)
			return
	# Hurt with Motes: secure them at home, unless the enemy Dreamer is nearer.
	if carried > 0 and home != null and health_fraction <= rules.bank_health_fraction \
			and (enemy_dreamer == null or hero.global_position.distance_to(home.global_position)
				<= hero.global_position.distance_to(enemy_dreamer.global_position)):
		_set_goal(&"bank", &"travel", home.global_position, true)
		return
	if carried >= plan.deposit_value or (carrier != null and carrier.has_dream_mote()) \
			or (carrier != null and not carrier.can_pick_up() and carried > 0):
		var deposit := _deposit_dreamer(home, enemy_dreamer, carried)
		if deposit != null:
			_set_goal(&"deliver" if deposit == enemy_dreamer else &"bank", &"travel", deposit.global_position, true)
			return
	if _time < _commit_until and intent in [&"collect", &"roam"] \
			and hero.global_position.distance_to(goal) > rules.goal_reached_distance \
			and _claim_still_valid():
		return
	if _choose_job():
		return
	if _choose_dream_mote(manager):
		return
	var mote := _best_mote(manager, carrier)
	if mote != null:
		_set_goal(&"collect", &"neutral", mote.global_position, false, _key(&"mote", mote))
		return
	if carried > 0 and carried >= plan.deposit_value / 2 and target == null:
		var deposit := _deposit_dreamer(home, enemy_dreamer, carried)
		if deposit != null:
			_set_goal(&"deliver" if deposit == enemy_dreamer else &"bank", &"travel", deposit.global_position)
			return
	_choose_roam(home, enemy_dreamer)


# Bank or deliver: the plan's preference, the enemy's wake meter, and how
# many enemies are known to wait near their Dreamer.
func _deposit_dreamer(home: Dreamer, enemy_dreamer: Dreamer, carried: int) -> Dreamer:
	if enemy_dreamer == null:
		return home
	if home == null:
		return enemy_dreamer
	var deliver := not plan.prefers_bank or enemy_dreamer.get_wake_ratio() >= plan.deliver_when_enemy_wake \
		or hero.get_level() >= plan.deliver_from_level
	if deliver and carried >= plan.deposit_value:
		var guards := 0
		for enemy in visible_enemies:
			if enemy.global_position.distance_to(enemy_dreamer.global_position) < 1500.0:
				guards += 1
		if guards >= plan.gauntlet_enemies:
			deliver = false
	if not enemy_dreamer.accepts_deposits():
		deliver = false
	return enemy_dreamer if deliver else home


func _choose_job() -> bool:
	match plan.job:
		BotRolePlan.Job.ESCORT:
			var carrier := _best_ally_carrier(plan.escort_min_value, BotRolePlan.Job.ESCORT)
			if carrier != null:
				_focus = carrier
				_set_goal(&"escort", &"neutral", _escort_point(carrier), true, _key(&"escort", carrier))
				return true
			return _choose_hunt()
		BotRolePlan.Job.PLAYMAKER:
			if _choose_hunt():
				return true
			var ally := _ally_in_fight()
			if ally != null:
				_focus = ally
				_set_goal(&"assist", &"aggressive", ally.global_position, true)
				return true
			var carrier := _best_ally_carrier(plan.escort_min_value, BotRolePlan.Job.PLAYMAKER)
			if carrier != null:
				_focus = carrier
				_set_goal(&"escort", &"neutral", _escort_point(carrier), false, _key(&"escort", carrier))
				return true
	return false


func _choose_hunt() -> bool:
	var best: Hero
	var best_value := 0
	for enemy in _known_carriers:
		if not is_instance_valid(enemy):
			continue
		var where: Vector2 = _known_carriers[enemy][0]
		if hero.global_position.distance_to(where) > plan.hunt_radius:
			continue
		var key := _key(&"hunt", enemy)
		if goal_key != key and _claim_count(key) >= plan.max_hunters:
			continue
		var value := MoteCarrier.find_on(enemy).get_mote_value()
		if value < plan.hunt_min_value and not MoteCarrier.find_on(enemy).has_dream_mote():
			continue
		if value > best_value:
			best_value = value
			best = enemy
	if best == null:
		return false
	_focus = best
	_set_goal(&"hunt", &"aggressive", _known_carriers[best][0], true, _key(&"hunt", best))
	return true


# The ally carrying the most (at least `min_value`) that no other bot of this
# job is already following.
func _best_ally_carrier(min_value: int, job: BotRolePlan.Job) -> Hero:
	var best: Hero
	var best_value := min_value - 1
	for ally in _team_heroes():
		if ally == hero or ally.health_component.is_dead():
			continue
		var carrier := MoteCarrier.find_on(ally)
		var value := carrier.get_mote_value() if carrier != null else 0
		if value <= best_value:
			continue
		var key := _key(&"escort", ally)
		if goal_key != key and _claimed_by_job(key, job):
			continue
		best_value = value
		best = ally
	return best


# A teammate within assist_radius with a seen enemy close to them.
func _ally_in_fight() -> Hero:
	var rules := BotRules.current()
	var best: Hero
	var best_distance := plan.assist_radius
	for ally in _team_heroes():
		if ally == hero or ally.health_component.is_dead():
			continue
		var distance := hero.global_position.distance_to(ally.global_position)
		if distance > best_distance:
			continue
		for enemy in visible_enemies:
			if enemy.global_position.distance_to(ally.global_position) <= rules.ally_fight_radius:
				best = ally
				best_distance = distance
				break
	return best


func _escort_point(carrier: Hero) -> Vector2:
	var ahead := carrier.velocity.normalized() if carrier.velocity.length() > 20.0 else Vector2.ZERO
	return carrier.global_position + ahead * plan.escort_distance


# The Dream Mote: be at the Cradle when it's announced, chase it while it's
# loose (it's public), hunt whoever carries it.
func _choose_dream_mote(manager: MatchManager) -> bool:
	var director := MoteDirector.find(get_tree())
	if director == null or manager == null or not manager.is_playing():
		return false
	var point := director.get_dream_point()
	for mote in director.get_loose_motes(true):
		if mote.is_dream() and mote.state != Mote.State.MAGNET \
				and hero.global_position.distance_to(mote.global_position) <= plan.dream_mote_radius:
			var carrier := MoteCarrier.find_on(hero)
			if carrier == null or carrier.can_pick_up():
				_set_goal(&"collect", &"neutral", mote.global_position, true, _key(&"dream", mote))
				return true
	if director.dream_mote_exists():
		return false  # Carried: the hunt / escort jobs handle it.
	var until := director.get_next_dream_time() - director.get_clock()
	if until > 0.0 and until <= director.get_rules().dream_mote_warning \
			and hero.global_position.distance_to(point) <= plan.dream_mote_radius:
		_set_goal(&"contest", &"neutral", point, true)
		return true
	return false


func _best_mote(manager: MatchManager, carrier: MoteCarrier) -> Mote:
	if carrier != null and not carrier.can_pick_up():
		return null
	var rules := BotRules.current()
	var best_score := -INF
	var best: Mote
	for node in get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote == null or mote.state == Mote.State.MAGNET:
			continue
		var distance := hero.global_position.distance_to(mote.global_position)
		if distance > rules.mote_search_radius:
			continue
		var key := _key(&"mote", mote)
		if goal_key != key and _claim_count(key) > 0:
			continue
		# The Dream Mote has a public beam. Ordinary Motes need team sight.
		if not mote.data.is_dream and not _team_can_see_point(mote.global_position, manager):
			continue
		var score := rules.mote_weight + mote.value \
			+ (rules.dream_mote_bonus if mote.data.is_dream else 0.0) \
			- distance * rules.mote_distance_weight
		if score > best_score:
			best_score = score
			best = mote
	return best


# Scouting: the Mote spawn the team has gone longest without seeing, on the
# plan's side of the map, away from teammates' roam goals.
func _choose_roam(home: Dreamer, enemy_dreamer: Dreamer) -> void:
	var points := _get_roam_points()
	if points.is_empty():
		var fallback := home.global_position if home != null else Vector2.ZERO
		_set_goal(&"roam", &"neutral", fallback)
		return
	var rules := BotRules.current()
	if _roam_index >= 0 and _roam_index < points.size() and intent == &"roam" \
			and hero.global_position.distance_to(points[_roam_index]) > rules.roam_seen_distance \
			and _claim_count(_key_index(&"roam", _roam_index)) == 0:
		_set_goal(&"roam", &"neutral", points[_roam_index], false, _key_index(&"roam", _roam_index))
		return
	var team_seen := _team_visits()
	var ally_goals := _ally_roam_goals()
	var best_score := -INF
	var best_index := -1
	for index in points.size():
		var point := points[index]
		var distance := hero.global_position.distance_to(point)
		if distance < rules.roam_min_distance:
			continue
		if _claim_count(_key_index(&"roam", index)) > 0:
			continue
		var unseen := minf(_time - float(team_seen.get(index, -1000.0)), 120.0)
		var score := unseen * plan.unseen_weight - distance * plan.distance_weight
		if home != null and enemy_dreamer != null \
				and point.distance_to(enemy_dreamer.global_position) < point.distance_to(home.global_position):
			score += plan.enemy_half_bias
		for other in ally_goals:
			if point.distance_to(other) < plan.spread_radius:
				score -= plan.spread_penalty
		score += _rng.randf_range(0.0, 60.0)  # break ties between mirrored points
		if score > best_score:
			best_score = score
			best_index = index
	if best_index < 0:
		best_index = _rng.randi_range(0, points.size() - 1)
	_roam_index = best_index
	_set_goal(&"roam", &"neutral", points[best_index], true, _key_index(&"roam", best_index))


func _get_roam_points() -> Array[Vector2]:
	if _roam_points.is_empty():
		for node in get_tree().get_nodes_in_group(&"mote_spawn"):
			if node is Node2D:
				_roam_points.append((node as Node2D).global_position)
	return _roam_points


# ---------------------------------------------------------------------------
# Team knowledge (other bots on this team)
# ---------------------------------------------------------------------------

func _team_heroes() -> Array[Hero]:
	var manager := MatchManager.find(get_tree())
	var result: Array[Hero] = []
	var all := manager.get_roster(hero.team) if manager != null else _all_heroes()
	for ally in all:
		if ally.team == hero.team:
			result.append(ally)
	return result


func _ally_bots() -> Array[BotHeroInput]:
	var result: Array[BotHeroInput] = []
	for ally in _team_heroes():
		if ally == hero or ally.health_component.is_dead():
			continue
		var bot := ally.get_node_or_null(^"BotHeroInput") as BotHeroInput
		if bot != null:
			result.append(bot)
	return result


func _claim_count(key: StringName) -> int:
	var count := 0
	for bot in _ally_bots():
		if bot.goal_key == key:
			count += 1
	return count


func _claimed_by_job(key: StringName, job: BotRolePlan.Job) -> bool:
	for bot in _ally_bots():
		if bot.goal_key == key and bot.plan != null and bot.plan.job == job:
			return true
	return false


# Our claim is still ours alone (a teammate may have taken the same Mote).
func _claim_still_valid() -> bool:
	if goal_key == &"":
		return true
	if str(goal_key).begins_with("mote:"):
		var id := int(str(goal_key).get_slice(":", 1))
		var mote := instance_from_id(id) as Mote
		if mote == null or not is_instance_valid(mote) or mote.state == Mote.State.MAGNET:
			return false
	for bot in _ally_bots():
		if bot.goal_key == goal_key and bot.get_instance_id() < get_instance_id():
			return false
	return true


func _team_visits() -> Dictionary:
	var merged := _visited.duplicate()
	for bot in _ally_bots():
		for index in bot._visited:
			merged[index] = maxf(float(merged.get(index, -1000.0)), float(bot._visited[index]) - bot._time + _time)
	return merged


func _ally_roam_goals() -> Array[Vector2]:
	var goals: Array[Vector2] = []
	for bot in _ally_bots():
		if bot.intent == &"roam":
			goals.append(bot.goal)
	return goals


static func _key(kind: StringName, node: Object) -> StringName:
	return StringName("%s:%d" % [kind, node.get_instance_id()])


static func _key_index(kind: StringName, index: int) -> StringName:
	return StringName("%s:%d" % [kind, index])


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


func _set_goal(next_intent: StringName, next_stance: StringName, point: Vector2, urgent: bool = false,
		key: StringName = &"") -> void:
	if not urgent and _time < _commit_until and intent != next_intent:
		return
	if intent != next_intent:
		_commit_until = _time + BotRules.current().goal_commit_time
	if next_intent not in [&"escort", &"hunt", &"assist"]:
		_focus = null
	intent = next_intent
	stance = next_stance
	goal = point
	goal_key = key


# ---------------------------------------------------------------------------
# Tactics
# ---------------------------------------------------------------------------

func _run_tactics(delta: float) -> void:
	var rules := BotRules.current()
	var host := MinigameHost.find_on(hero)
	if host != null and host.is_playing():
		hero.move_direction = Vector2.ZERO
		return  # MinigameHost uses its own bot_input() when no input is supplied.
	_play_rhythm()
	_follow_focus()
	var fight := target != null and _time >= _reaction_until and not rules.strategy_only
	var can_attack := fight and CombatQueries.has_line_of_sight(hero, target)
	# Travelling bots (deliver, bank, retreat) shoot on the move; an escort
	# only turns to fight near its carrier.
	var chase := can_attack and stance != &"avoid" and stance != &"travel"
	if chase and intent == &"escort" and _focus != null:
		chase = target.global_position.distance_to(_focus.global_position) <= plan.escort_distance * 3.0
	var destination := goal
	var desired_range := _preferred_range()
	if chase:
		destination = target.global_position
		var distance := hero.global_position.distance_to(destination)
		if distance <= desired_range * rules.attack_range_fraction:
			# Keep spacing, especially when using a ranged primary.
			destination = hero.global_position
			if distance < desired_range * rules.too_close_range_fraction:
				destination = hero.global_position + (hero.global_position - target.global_position).normalized() * desired_range
	else:
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
		_use_abilities(chase)
		action = &"dodge" if dodging else (&"fight" if chase else &"shoot")
	else:
		_set_aim(destination)
		_release_inactive_slots()
		action = &"dodge" if dodging else intent
	var gun := hero.get_reload_ability()
	if gun != null and gun.has_magazine() and (gun.get_ammo() == 0 or not fight):
		hero.reload()


# Escorts, hunts and assists follow a moving hero between strategy ticks.
func _follow_focus() -> void:
	if _focus == null:
		return
	if _focus.health_component.is_dead():
		_focus = null
		return
	match intent:
		&"escort":
			goal = _escort_point(_focus)
		&"assist":
			goal = _focus.global_position
		&"hunt":
			if _focus in visible_enemies:
				goal = _focus.global_position
			elif _known_carriers.has(_focus):
				goal = _known_carriers[_focus][0]


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


# `engaging`: the bot is turning to fight. A travelling bot keeps its
# movement abilities for travel instead of dashing into the target.
func _use_abilities(engaging: bool = true) -> void:
	var rules := BotRules.current()
	for slot in GameRules.current().slots:
		var ability := hero.get_ability(slot.id)
		if ability == null or ability.data == null or ability is PassiveAbility:
			continue
		if not engaging and ability.is_movement_ability() and not ability.is_charging() and not ability.is_held():
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
