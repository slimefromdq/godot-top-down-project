extends Node

# Screenshots of the match HUD (clock, gold, level and XP bar), the F1 > Match
# tab, and the respawn countdown, in Dream Basin.
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
