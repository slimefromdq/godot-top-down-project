extends Node

# Screenshots of the map events on the real Dream Basin: the Black Market
# stall with its countdown and the HUD pill, its shop window, the Island portal
# at shimmer distance and up close, the Island room, and a Wanderer mid-flight.
# Not a test.
#
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
#       res://tools/match/capture_map_events.tscn -- <out_dir>

var out_dir := "user://map_event_captures"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
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
	var events := MapEvents.find(get_tree())
	manager.start_playing()
	manager.jump_clock(305.0)
	var player := DebugTools.get_player()
	player.get_node("PlayerHeroInput").set_physics_process(false)
	MoteDirector.find(get_tree()).clear_motes()
	await _wait(0.6)

	# 1. The Black Market, its countdown and the pill.
	var stall := events.market.market
	print("market: ", stall.side, " at ", stall.global_position)
	player.global_position = stall.global_position + Vector2(-200, 380)
	var carrier := MoteCarrier.find_on(player)
	DebugTools.give_player_motes(6)
	manager.grant_actor(player, 900.0, 0.0, MatchManager.REASON_DEBUG)
	await _wait(1.0)
	await _shot("market_stall")

	# 2. The shop window.
	player.global_position = stall.global_position + Vector2(0, 220)
	await _wait(0.3)
	var hud := get_tree().get_first_node_in_group(MatchHud.GROUP) as MatchHud
	hud.events_hud.panel.open()
	await _wait(0.5)
	await _shot("market_window")
	events.market.purchase(player, events.get_rules().get_item(&"overclock"))
	await _wait(0.3)
	await _shot("market_bought")
	hud.events_hud.panel.close()

	# 3. The portal: at shimmer distance, then up close with the prompt.
	var portal := events.island.portal
	print("portal at ", portal.global_position)
	player.global_position = portal.global_position + Vector2(0, 900)
	await _wait(0.8)
	await _shot("portal_shimmer")
	player.global_position = portal.global_position + Vector2(0, 200)
	await _wait(0.6)
	await _shot("portal_near")

	# 4. The Island.
	events.island.request_enter(player)
	await _wait(0.8)
	await _shot("island")
	events.island.request_leave(player)

	# 5. A Wanderer, hit and running.
	events.force_spawn_wanderer()
	await _wait(0.3)
	var w := events.wanderer.wanderer
	player.global_position = w.global_position + Vector2(-300, 0)
	w.health_component.apply_damage(DamageInfo.create(25.0, player, DamageInfo.Type.TRUE))
	await _wait(0.5)
	player.global_position = w.global_position + Vector2(-350, 0)
	await _wait(0.4)
	await _shot("wanderer_flee")
	print("captures in ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
