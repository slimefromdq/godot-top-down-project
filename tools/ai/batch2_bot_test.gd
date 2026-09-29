extends Node2D

# Bots play hero batch 2 (Biker, Horace, Mochi, Computer, Catgirl, Rocco):
# two mirrored teams of the six on Dream Basin, ultimates kept charged. Each
# hero must leave its spawn, use at least three of its slots and deal damage,
# with no script errors (the runner greps the log for SCRIPT ERROR).
#
#   godot --headless res://tools/ai/batch2_bot_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const MAP := preload("res://scenes/maps/dream_basin.tscn")
const HEROES := [&"biker", &"horace", &"mochi", &"computer", &"catgirl", &"rocco"]
const PLAY_SECONDS := 30.0

var failures := 0
var used: Dictionary = {}       # Hero -> {slot: true}
var dealt: Dictionary = {}      # Hero -> damage
var deaths: Dictionary = {}     # Hero -> times died


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	add_child(MAP.instantiate())
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	await get_tree().physics_frame
	var skill := BotDraft.skill_for(1)
	var bots: Array[Hero] = []
	var index := 0
	for team in MatchManager.TEAMS:
		for id in HEROES:
			var definition: HeroDefinition = load("res://heroes/%s/%s_definition.tres" % [id, id])
			var bot: Hero = BotDraft.spawn_bot(get_tree(), definition, team, skill, 1 + index, index % 6, &"batch2_bots")
			bots.append(bot)
			index += 1
	await get_tree().physics_frame
	# Start both teams facing each other mid-map so the kits get used in a
	# fight within the test's time (not roaming to find one).
	var middle := Vector2.ZERO
	for bot in bots:
		middle += bot.global_position / bots.size()
	for i in bots.size():
		var side := -1.0 if bots[i].team == &"a" else 1.0
		bots[i].teleport_to(middle + Vector2(side * 350.0, (i % 6 - 2.5) * 90.0))
	await get_tree().physics_frame
	for bot in bots:
		used[bot] = {}
		dealt[bot] = 0.0
		deaths[bot] = 0
		bot.health_component.died.connect(func(): deaths[bot] += 1)
		for slot in GameRules.current().slots:
			var ability := bot.get_ability(slot.id)
			if ability != null:
				ability.activated.connect(_on_activated.bind(bot, slot.id))
	CombatEvents.damage_dealt.connect(_on_damage)
	var starts := {}
	for bot in bots:
		starts[bot] = bot.global_position
	manager.start_playing()
	var t := 0.0
	while t < PLAY_SECONDS:
		if t > 8.0:
			for bot in bots:
				var charge := UltimateCharge.find_on(bot) if is_instance_valid(bot) else null
				if charge != null:
					charge.set_charge(charge.maximum)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		var label := "%s (%s)" % [bot.definition.display_name, bot.team]
		_check("%s left its spawn" % label, bot.global_position.distance_to(starts[bot]) > 200.0
			or bot.health_component.is_dead())
	# Kits are judged per hero over both of its bots, so one early death
	# (a diver jumping into six enemies) doesn't fail the hero.
	for id in HEROES:
		var slots := {}
		var died := 0
		var damage := 0.0
		for bot in bots:
			if is_instance_valid(bot) and bot.definition.hero_id == id:
				slots.merge(used[bot])
				died += deaths[bot]
				damage += dealt[bot]
		_check("%s bots dealt damage (%.0f)" % [id, damage], damage > 0.0)
		_check("%s bots used 4+ slots: %s (%d deaths)" % [id, str(slots.keys()), died], slots.size() >= 4)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _on_activated(bot: Hero, slot: StringName) -> void:
	used[bot][slot] = true


func _on_damage(info: DamageInfo) -> void:
	if dealt.has(info.source):
		dealt[info.source] += info.final_amount


func _check(label: String, good: bool) -> void:
	print("%s  %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
