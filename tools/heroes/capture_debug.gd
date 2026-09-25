extends Node

# Screenshot of the balance tools (F1 panel, F2 inspector, F4 meter) after a
# short fight in the Training Grounds.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/heroes/capture_debug.tscn -- <out_dir>

var out_dir := "user://debug_captures"


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
	get_tree().change_scene_to_file("res://scenes/training_grounds_world.tscn")
	for i in 20:
		await get_tree().process_frame
	var avery := DebugTools.get_player()
	avery.get_node("PlayerHeroInput").set_physics_process(false)
	avery.get_node("PlayerHeroInput").set_process(false)
	var dummy := get_tree().current_scene.get_node("Dummies/Plain") as Node2D
	avery.global_position = dummy.global_position + Vector2(-150, 60)
	DebugTools.set_player_level(6)
	avery.health_component.current_health = 300.0
	avery.request_slot(&"ability_1", dummy.global_position)
	await get_tree().create_timer(0.8).timeout
	for i in 3:
		avery.request_slot(&"primary", dummy.global_position)
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.0).timeout
	DebugTools._inspector.visible = true
	DebugTools.toggle_panel()
	DebugTools._tabs.current_tab = 1
	for i in 10:
		await get_tree().process_frame
	await _shot("debug_tools")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
