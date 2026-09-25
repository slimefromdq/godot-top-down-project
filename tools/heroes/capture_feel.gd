extends Node

# Saves screenshots of Avery's finisher (windup, release, impact) in the
# Training Grounds, for eyeballing the feel without playing.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/heroes/capture_feel.tscn -- <out_dir>

var out_dir := "user://feel_captures"


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
	for i in 30:
		await get_tree().process_frame
	var avery := get_tree().get_first_node_in_group(&"player") as Hero
	var dummy := get_tree().current_scene.get_node("Dummies/Plain") as Node2D
	avery.global_position = dummy.global_position + Vector2(-150, 30)
	avery.get_node("PlayerHeroInput").set_physics_process(false)
	avery.get_node("PlayerHeroInput").set_process(false)
	for i in 20:
		await get_tree().process_frame
	var primary := avery.get_ability(&"primary") as MeleeAttackAbility
	primary._step_index = 2
	primary._time_since_swing = 0.0
	avery.aim_direction = (dummy.global_position - avery.global_position).normalized()
	avery.request_slot(&"primary", dummy.global_position)
	await _wait_phase(primary, Ability.Phase.WINDUP)
	await _seconds(0.2)
	await _shot("1_windup")
	await _wait_phase(primary, Ability.Phase.ACTIVE)
	await _shot("2_release")
	await _seconds(0.06)
	await _shot("3_impact")
	await _seconds(0.1)
	await _shot("4_follow_through")
	get_tree().quit()


func _wait_phase(ability: Ability, phase: Ability.Phase) -> void:
	while ability.phase != phase:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
