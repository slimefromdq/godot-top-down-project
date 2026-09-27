extends Node

# Screenshots of a 6 v 6 bot match in Dream Basin: the team rings,
# nameplates and placeholder bodies up close, the top team bars (health and
# ultimate for your team), and the M map view after the bots have spread out
# to roam. Also prints each bot's intent, so the role jobs can be eyeballed.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/ai/capture_bots.tscn -- <out_dir>

var out_dir := "user://bot_captures"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	get_tree().change_scene_to_file("res://scenes/dream_basin_world.tscn")
	for i in 20:
		await get_tree().process_frame
	var manager := MatchManager.find(get_tree())
	var player := DebugTools.get_player()
	player.get_node("PlayerHeroInput").set_physics_process(false)
	DebugTools.fill_with_bots(1)
	manager.start_playing()
	await get_tree().create_timer(1.0).timeout
	await _shot("bots_spawn")
	# Everyone in a line near the player, to compare the looks.
	var x := -900.0
	for hero in manager.get_roster():
		if hero != player:
			var input := hero.get_node_or_null(^"BotHeroInput") as BotHeroInput
			if input != null:
				input.set_physics_process(false)
				hero.move_direction = Vector2.ZERO
			hero.global_position = player.global_position + Vector2(x, -260.0 if hero.team == &"a" else 260.0)
			x += 300.0 if hero.team == &"a" else 0.0
	x = -900.0
	for hero in manager.get_roster(&"b"):
		hero.global_position = player.global_position + Vector2(x, 260.0)
		x += 300.0
	for hero in manager.get_roster():
		var charge := UltimateCharge.find_on(hero)
		if charge != null:
			charge.set_charge(randf_range(10.0, 100.0))
	await get_tree().create_timer(0.8).timeout
	await _shot("bots_lineup")
	for hero in manager.get_roster():
		var input := hero.get_node_or_null(^"BotHeroInput") as BotHeroInput
		if input != null:
			input.set_physics_process(true)
			hero.global_position = manager.get_spawn_point(hero.team)
	Engine.time_scale = 4.0
	await get_tree().create_timer(25.0, true, false, false).timeout    # game seconds
	Engine.time_scale = 1.0
	for hero in manager.get_roster():
		var input := hero.get_node_or_null(^"BotHeroInput") as BotHeroInput
		if input != null:
			var carrier := MoteCarrier.find_on(hero)
			print("%s %s (%s): %s / %s at %s, carrying %d, hp %d%%, ult %d%%" % [hero.team,
				hero.definition.display_name, hero.definition.get_role_name(), input.intent, input.action,
				hero.global_position.round(), carrier.get_mote_value(),
				roundi(100.0 * hero.health_component.current_health / hero.health_component.max_health),
				roundi(100.0 * manager.get_ultimate_ratio(hero))])
	var view := get_tree().current_scene.get_node("MapDebugView") as MapDebugView
	view.toggle()
	await get_tree().create_timer(0.5).timeout
	await _shot("bots_map_view")
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
