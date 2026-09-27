extends Node

# Screenshots of the match HUD (clock, gold, level and XP bar), the F1 > Match
# tab, the respawn countdown, and Motes (loose, a carried stack, the Dream
# Mote and its off-screen arrow, a dreaming zone, the M-view spawn overlay),
# and the Dreamers (idle with the wake meters, stirring with the Lullaby), in
# Dream Basin.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/match/capture_match.tscn -- <out_dir>

var out_dir := "user://match_captures"


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
	await _shot("match_warmup")
	var manager := MatchManager.find(get_tree())
	manager.start_playing()
	manager.clock = 7 * 60 + 42
	DebugTools.give_player(1234.0, 0.0)
	DebugTools.give_player(0.0, 1500.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("match_hud")
	DebugTools.toggle_panel()
	DebugTools._tabs.current_tab = DebugTools._tabs.get_tab_count() - 2
	for i in 10:
		await get_tree().process_frame
	await _shot("match_debug_tab")
	DebugTools.toggle_panel()

	# Motes: a few loose around the player, then a full carried stack.
	var player := DebugTools.get_player()
	var director := MoteDirector.find(get_tree())
	player.get_node("PlayerHeroInput").set_physics_process(false)
	for i in 4:
		director.spawn_mote(player.global_position + Vector2(260 + 150 * i, -160 + 90 * (i % 2)))
	director.spawn_mote(player.global_position + Vector2(-420, -120), true)
	await get_tree().create_timer(0.8).timeout
	await _shot("motes_loose")
	DebugTools.give_player_motes(25)
	player.global_position += Vector2(0, -520)
	await get_tree().create_timer(0.8).timeout
	await _shot("motes_carried")
	# The Dream Mote far away: off-screen arrow. A dreaming zone nearby.
	director.clear_motes()
	director.spawn_mote(Vector2.ZERO, true)
	director.force_next_zone()
	var zone: DreamZone = director.get_zone_pairs()[director.get_active_pair()][0]
	player.global_position = zone.get_spawn_points()[0].global_position + Vector2(0, 200)
	await get_tree().create_timer(director.get_rules().zone_warning + 3.0).timeout
	await _shot("motes_zone_and_arrow")
	DebugTools.set_mote_overlay_enabled(true)
	var view := get_tree().current_scene.get_node("MapDebugView") as MapDebugView
	view.toggle()
	await get_tree().create_timer(0.8).timeout
	await _shot("motes_overlay")
	view.toggle()
	DebugTools.set_mote_overlay_enabled(false)
	await get_tree().create_timer(0.5).timeout

	# Dreamers: Dawn's asleep near the player (carrying, so arrows show),
	# then Dusk's stirring with a Lullaby under way.
	director.clear_motes()
	var dawn := Dreamer.find_for(get_tree(), &"a")
	var dusk := Dreamer.find_for(get_tree(), &"b")
	dawn.set_wake(35.0)
	dawn.sweet = 12.0
	dusk.set_wake(70.0)
	player.global_position = dawn.global_position + Vector2(-420, -380)
	DebugTools.give_player_motes(12)
	await get_tree().create_timer(1.0).timeout
	await _shot("dreamer_idle")
	player.global_position = dusk.global_position + Vector2(0, 420)
	dusk.start_stir()
	dusk.lullaby = 0.35
	await get_tree().create_timer(0.6).timeout
	await _shot("dreamer_stirring")
	# Avery's revive would cancel the death: die as Jose instead.
	var jose := DebugTools.swap_player(load("res://heroes/jose/jose_definition.tres"))
	await get_tree().create_timer(0.3).timeout
	jose.health_component.kill()
	await get_tree().create_timer(0.5).timeout
	await _shot("match_respawn")
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
