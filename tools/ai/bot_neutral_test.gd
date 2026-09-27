extends Node2D

# Bots and neutral objectives, headless:
#   godot --headless res://tools/ai/bot_neutral_test.tscn
# An open arena with a match, one jungle camp and the Nightmare's lair.
# Decisions: a bot with nothing to do jungles a camp in reach (and not one
# out of reach, or when hurt, or past the per-camp cap), fights its monster,
# drops it for an enemy hero, fights back a neutral that attacks it, and
# the team goes for the Nightmare only with enough of it alive. Then a
# real clear: two bots kill a Sleepwalker on their own.
#
# Exits with the number of failed checks (0 = all passed).

const HERO := preload("res://scenes/heroes/hero_base.tscn")
const JOSE := preload("res://heroes/jose/jose_definition.tres")
const AVERY := preload("res://heroes/avery/avery_definition.tres")
const SLEEPWALKER := "res://resources/match/neutrals/sleepwalker.tres"
const NIGHTMARE := "res://resources/match/neutrals/nightmare.tres"

var failures := 0
var manager: MatchManager
var director: ObjectiveDirector
var jungle: NeutralCamp
var lair: NeutralCamp


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := GameMap.new()
	map.bounds = Rect2(-5000, -5000, 10000, 10000)
	for entry in [[&"spawn_a", Vector2(0, 3500)], [&"spawn_b", Vector2(0, -3500)]]:
		var marker := Marker2D.new()
		marker.position = entry[1]
		marker.add_to_group(entry[0])
		map.add_child(marker)
	jungle = _camp(SLEEPWALKER, Vector2(-1500, 0))
	lair = _camp(NIGHTMARE, Vector2(2500, 0))
	add_child(map)
	var rules := MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.trickle_interval = 1e6
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	rules.passive_gold_per_second = 0.0
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	director = manager.get_node("ObjectiveDirector")
	await _frames(2)
	manager.start_warmup()
	manager.clock = 1.0
	director.reset_schedule()

	await _decisions()
	await _real_clear()
	print("BOT NEUTRAL TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


func _decisions() -> void:
	var carry := _hero(JOSE, &"a", Vector2(-1500, 1200), true)
	var bot := _bot(carry)
	await _frames(3)
	_think(carry)
	_check("no camp up: no jungling", bot.intent != &"jungle")
	director.spawn_camp(jungle)
	await _frames(1)
	_think(carry)
	_check("a camp in reach: the bot goes to jungle it", bot.intent == &"jungle")
	_check("it stands off at range, not on top of it", bot.goal.distance_to(jungle.global_position) > 100.0)
	carry.global_position = jungle.global_position + Vector2(0, 450)
	await _frames(5)
	var monster := jungle.get_living_monsters()[0]
	_check("near the camp it fights the monster", bot.neutral_target == monster and bot.target == null)
	var hp := monster.health_component.current_health
	await _frames(150)
	_check("and damages it", monster.health_component.current_health < hp)

	var mate := _hero(JOSE, &"a", jungle.global_position + Vector2(300, 400), true)
	var third := _hero(JOSE, &"a", jungle.global_position + Vector2(-300, 400), true)
	await _frames(3)
	_think(mate)
	_think(third)
	var on_camp := [bot, _bot(mate), _bot(third)].filter(func(b): return b.intent == &"jungle").size()
	_check("at most jungle_bots_per_camp per camp (%d)" % BotRules.current().jungle_bots_per_camp,
		on_camp == BotRules.current().jungle_bots_per_camp)
	third.queue_free()

	var enemy := _hero(AVERY, &"b", carry.global_position + Vector2(350, 0))
	await _frames(20)
	_check("an enemy hero comes first", bot.target == enemy and bot.neutral_target == null)
	enemy.queue_free()
	await _frames(20)
	_check("then back to the monster", bot.target == null and bot.neutral_target == monster)

	carry.health_component.current_health = carry.health_component.max_health * 0.3
	carry.global_position = jungle.global_position + Vector2(0, 1200)
	bot._camp = null
	bot.intent = &"idle"
	_think(carry)
	_check("hurt: doesn't start a camp", bot.intent != &"jungle")
	carry.health_component.reset()
	carry.global_position = jungle.global_position + Vector2(0, 3000)
	_think(carry)
	_check("out of jungle_radius: doesn't go", bot.intent != &"jungle")

	var wanderer := _hero(JOSE, &"a", Vector2(0, 2500), true)
	await _frames(3)
	var wander_bot := _bot(wanderer)
	var biter := jungle.get_living_monsters()[0]
	wanderer.global_position = biter.global_position + Vector2(0, 500)
	wanderer.health_component.apply_damage(DamageInfo.create(5.0, biter))
	await _frames(3)
	_check("a neutral that hits a bot gets fought back", wander_bot.neutral_target == biter)
	wanderer.queue_free()

	# The Nightmare: the team goes only with enough of it alive.
	director.spawn_camp(lair)
	await _frames(1)
	carry.global_position = Vector2(0, 1200)
	mate.global_position = Vector2(200, 1200)
	await _frames(2)
	_think(carry)
	var needed := BotRules.current().nightmare_min_team_alive
	_check("Nightmare up, 2 of %d needed alive: they stay out" % needed, bot.intent != &"nightmare")
	var extra: Array[Hero] = []
	for i in needed - 2:
		extra.append(_hero(JOSE, &"a", Vector2(-200 - 100 * i, 1200), true))
	await _frames(3)
	_think(carry)
	_check("enough of the team alive: they go for the Nightmare", bot.intent == &"nightmare")
	carry.global_position = lair.global_position + Vector2(-600, 0)
	await _frames(5)
	_check("and fight it", bot.neutral_target == lair.get_living_monsters()[0])
	for node in [carry, mate] + extra:
		node.queue_free()
	director.despawn_all()
	await _frames(3)


# Two bots clear a Sleepwalker on their own, from spawning next to it.
func _real_clear() -> void:
	director.spawn_camp(jungle)
	await _frames(1)
	var cleared: Array = []
	director.objective_cleared.connect(func(camp, team, _killer): cleared.append([camp, team]))
	var a := _hero(JOSE, &"a", jungle.global_position + Vector2(-200, 900), true)
	var b := _hero(JOSE, &"a", jungle.global_position + Vector2(200, 900), true)
	for i in 60 * 40:
		await get_tree().physics_frame
		if not cleared.is_empty():
			break
	_check("two bots clear a Sleepwalker by themselves", cleared.size() == 1 and cleared[0] == [jungle, &"a"])
	a.queue_free()
	b.queue_free()


func _camp(path: String, at: Vector2) -> NeutralCamp:
	var camp := NeutralCamp.new()
	camp.data = load(path)
	camp.position = at
	add_child(camp)
	return camp


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
func _think(hero: Hero) -> void:
	var input := _bot(hero)
	input._commit_until = -INF
	input._perceive(manager)
	input._choose_goal(manager)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
