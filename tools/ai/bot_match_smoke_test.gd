extends Node2D

const MAP := preload("res://scenes/maps/dream_basin.tscn")

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	add_child(MAP.instantiate())
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	var baseline_ms := 0.0
	for frame in 60:
		await get_tree().physics_frame
		baseline_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	baseline_ms /= 60.0
	BotRules.current().profile_bots = true
	BotHeroInput.profile_usec = 0
	BotHeroInput.profile_ticks = 0
	var added := DebugTools.fill_with_bots(1)
	await get_tree().physics_frame
	var bots := get_tree().get_nodes_in_group(DebugTools.BOT_GROUP)
	_check("two teams filled", added == 12 and manager.get_roster(&"a").size() == 6
		and manager.get_roster(&"b").size() == 6)
	var starts: Dictionary = {}
	for bot in bots:
		starts[bot] = bot.global_position
	manager.start_playing()
	var physics_ms := 0.0
	for frame in 240:
		await get_tree().physics_frame
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var moved := 0
	for bot in bots:
		if is_instance_valid(bot) and bot.global_position.distance_to(starts[bot]) > 200.0:
			moved += 1
	_check("bots leave their spawns (%d/%d)" % [moved, bots.size()], moved == bots.size())
	var empty_paths := 0
	for bot in bots:
		if is_instance_valid(bot):
			var input := bot.get_node_or_null(^"BotHeroInput") as BotHeroInput
			if input != null and input._path.is_empty():
				empty_paths += 1
	print("12 bot physics frame: %.3f ms average (baseline %.3f ms, %d empty paths)" % [physics_ms / 240.0, baseline_ms, empty_paths])
	print("Bot controller time: %.3f ms per 12 bot frame" % (BotHeroInput.profile_usec / 240000.0))
	print("BOT MATCH SMOKE TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
