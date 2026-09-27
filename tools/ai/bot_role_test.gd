extends Node2D

# Role-based bot strategy (BotRolePlan), headless:
#   godot --headless res://tools/ai/bot_role_test.tscn
# Part 1, an empty arena: engage radius per role. Part 2, Dream Basin with a
# hand-placed roster and decisions read straight from the strategy tick.
# Part 3, twelve bots with fights off: they roam and spread out instead of
# gathering in the middle.

const HERO := preload("res://scenes/heroes/hero_base.tscn")
const MAP := preload("res://scenes/maps/dream_basin.tscn")
const JOSE := preload("res://heroes/jose/jose_definition.tres")
const AVERY := preload("res://heroes/avery/avery_definition.tres")
const SAM := preload("res://heroes/sam/sam_definition.tres")
const MELODY := preload("res://heroes/melody/melody_definition.tres")

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rules := BotRules.current()
	_check("roles map to jobs", rules.plan_for(HeroDefinition.Role.TANK).job == BotRolePlan.Job.ESCORT
		and rules.plan_for(HeroDefinition.Role.CARRY).job == BotRolePlan.Job.FARM
		and rules.plan_for(HeroDefinition.Role.TEMPO).job == BotRolePlan.Job.PLAYMAKER
		and rules.plan_for(MELODY.role).job == BotRolePlan.Job.PLAYMAKER)
	await _engage_ranges()
	await _decisions()
	await _roaming()
	print("BOT ROLE TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


# A carry only takes on enemies close to it; a tempo reaches farther.
func _engage_ranges() -> void:
	var carry := _hero(JOSE, &"a", Vector2.ZERO, true)
	var tempo := _hero(SAM, &"a", Vector2(0, 3000), true)
	var far_enemy := _hero(AVERY, &"b", Vector2(900, 0))
	var tempo_enemy := _hero(AVERY, &"b", Vector2(900, 3000))
	await _frames(20)
	var carry_bot := _bot(carry)
	_check("a farming carry ignores an enemy 900 px away", carry_bot.target == null
		and far_enemy in carry_bot.visible_enemies)
	_check("a tempo engages at 900 px", _bot(tempo).target == tempo_enemy)
	far_enemy.global_position = Vector2(400, 0)
	await _frames(20)
	_check("the carry fights an enemy that comes close", carry_bot.target == far_enemy)
	far_enemy.global_position = Vector2(1300, 0)
	await _frames(20)
	_check("and lets it go past the chase radius", carry_bot.target == null)
	far_enemy.global_position = Vector2(1000, 0)
	carry.health_component.apply_damage(DamageInfo.create(10.0, far_enemy))
	await _frames(20)
	_check("a bot hit from farther away fights back", carry_bot.target == far_enemy)
	for node in [carry, tempo, far_enemy, tempo_enemy]:
		node.queue_free()
	await _frames(3)


func _decisions() -> void:
	var map := MAP.instantiate()
	add_child(map)
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	await _frames(3)
	manager.start_playing()
	var director := MoteDirector.find(get_tree())
	director.set_physics_process(false)
	# Dawn's side of the Glade: open ground, well away from either Dreamer.
	var base := Vector2(-3500, 1000)
	var carry := _hero(JOSE, &"a", base, true)
	var tank := _hero(AVERY, &"a", base + Vector2(250, 0), true)
	var tempo := _hero(SAM, &"a", base + Vector2(0, 250), true)
	var enemy := _hero(JOSE, &"b", base + Vector2(2800, -900))
	await _frames(5)
	for hero in [carry, tank, tempo]:
		_think(hero, manager)
	_check("nobody idles", [carry, tank, tempo].all(func(h): return _bot(h).intent != &"idle"))
	_check("with nothing to do, bots roam the Mote spawns", _bot(carry).intent == &"roam"
		and str(_bot(carry).goal_key).begins_with("roam:"))

	_give(carry, 6)
	_think(tank, manager)
	_check("a tank escorts the teammate carrying Motes", _bot(tank).intent == &"escort"
		and _bot(tank)._focus == carry)

	_give(carry, 6)
	_think(carry, manager)
	_check("a carry with a stack banks at home", _bot(carry).intent == &"bank")
	MoteCarrier.find_on(carry).clear()
	_give(tank, 10)
	_think(tank, manager)
	_check("a tank with a stack delivers to the enemy", _bot(tank).intent == &"deliver")
	var dusk := Dreamer.find_for(get_tree(), &"b")
	dusk.set_wake(dusk.get_rules().wake_meter_max * 0.7)
	_give(carry, 12)
	_think(carry, manager)
	_check("a carry delivers once the enemy is close to waking", _bot(carry).intent == &"deliver")
	dusk.set_wake(0.0)
	MoteCarrier.find_on(tank).clear()
	MoteCarrier.find_on(carry).clear()

	_give(enemy, 22)  # over the top reveal step: always on the minimap
	await _frames(15)
	_think(tempo, manager)
	_check("a tempo hunts a revealed enemy carrier", _bot(tempo).intent == &"hunt"
		and _bot(tempo)._focus == enemy)
	var tempo2 := _hero(MELODY, &"a", base + Vector2(250, 250), true)
	var tempo3 := _hero(SAM, &"a", base + Vector2(-250, 250), true)
	await _frames(15)
	_think(tempo2, manager)
	_think(tempo3, manager)
	var hunters := [tempo, tempo2, tempo3].filter(func(h): return _bot(h).intent == &"hunt").size()
	_check("at most max_hunters chase one carrier (%d)" % hunters, hunters <= BotRules.current().tempo_plan.max_hunters)
	MoteCarrier.find_on(enemy).clear()

	# Beyond the Mote's own pull range, so it waits to be walked to.
	var mote := director.spawn_mote(carry.global_position + Vector2(0, -800))
	await _frames(2)
	_think(carry, manager)
	_think(tempo3, manager)
	_check("a visible Mote is collected", _bot(carry).intent == &"collect" or _bot(tempo3).intent == &"collect")
	_check("and claimed by one bot only", not (_bot(carry).goal_key == _bot(tempo3).goal_key
		and _bot(carry).intent == &"collect"))
	mote.queue_free()

	var dawn := Dreamer.find_for(get_tree(), &"a")
	dawn.start_stir()
	_think(carry, manager)
	_check("everyone defends a stirring home Dreamer", _bot(carry).intent == &"defend")
	for node in [carry, tank, tempo, tempo2, tempo3, enemy, manager, map]:
		node.queue_free()
	await _frames(3)


func _roaming() -> void:
	var map := MAP.instantiate()
	add_child(map)
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	await _frames(3)
	var rules := BotRules.current()
	rules.strategy_only = true
	var added := DebugTools.fill_with_bots(1)
	await _frames(2)
	var roles := {}
	for hero in manager.get_roster(&"a"):
		roles[hero.definition.role] = true
	_check("fill builds a mixed team (%d roles)" % roles.size(), added == 12 and roles.size() >= 3)
	manager.start_playing()
	Engine.time_scale = 4.0
	await get_tree().create_timer(4.0 * 15.0, true, true, false).timeout
	Engine.time_scale = 1.0
	var bots := manager.get_roster()
	var spread := 0.0
	var far_from_home := 0
	var intents := {}
	var roam_goals := {}
	for hero in bots:
		var input := _bot(hero)
		intents[input.intent] = int(intents.get(input.intent, 0)) + 1
		if input.intent == &"roam":
			roam_goals[input.goal_key] = true
		var nearest := INF
		for other in manager.get_roster(hero.team):
			if other != hero:
				nearest = minf(nearest, hero.global_position.distance_to(other.global_position))
		spread += nearest
		if hero.global_position.distance_to(manager.get_spawn_point(hero.team)) > 2500.0:
			far_from_home += 1
	spread /= bots.size()
	print("intents after 15 s: %s" % [intents])
	_check("no bot idles", not intents.has(&"idle"))
	_check("bots spread out: %.0f px to the nearest teammate on average" % spread, spread > 700.0)
	_check("most bots leave their base (%d/12)" % far_from_home, far_from_home >= 8)
	_check("roaming bots scout different spawns", roam_goals.size() >= mini(intents.get(&"roam", 0), 3))
	rules.strategy_only = false
	DebugTools.clear_bots()
	await _frames(3)
	manager.queue_free()
	map.queue_free()
	await _frames(2)


func _hero(definition: HeroDefinition, team: StringName, at: Vector2, bot: bool = false) -> Hero:
	var hero: Hero = HERO.instantiate()
	hero.definition = definition
	hero.team = team
	hero.position = at
	hero.bot_controlled = bot
	add_child(hero)
	return hero


func _bot(hero: Hero) -> BotHeroInput:
	return hero.get_node(^"BotHeroInput") as BotHeroInput


# One perception + strategy tick now, bypassing the goal commitment.
func _think(hero: Hero, manager: MatchManager) -> void:
	var input := _bot(hero)
	input._commit_until = -INF
	input._perceive(manager)
	input._choose_goal(manager)


func _give(hero: Hero, count: int) -> void:
	var director := MoteDirector.find(get_tree())
	var carrier := MoteCarrier.find_on(hero)
	for i in count:
		carrier.add_mote(director.small_data, 1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
