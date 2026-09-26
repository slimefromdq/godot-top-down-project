extends Node

# Screenshots of Cpt. Yellow's kit in the Training Grounds, swapped in the
# same way as F1 -> "Play as" (DebugTools.swap_player). Checks that the
# Swarm Ride landing telegraph and the CHARGE! wind-up read clearly.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/heroes/capture_cpt_yellow.tscn -- <out_dir>

const DEFINITION := "res://heroes/cpt_yellow/cpt_yellow_definition.tres"

var out_dir := "user://cpt_yellow_captures"
var yellow: Hero


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
	yellow = DebugTools.swap_player(load(DEFINITION))
	await get_tree().process_frame
	yellow.get_node("PlayerHeroInput").set_physics_process(false)
	yellow.get_node("PlayerHeroInput").set_process(false)
	DebugTools.set_player_level(5)
	var dummies := get_tree().current_scene.get_node("Dummies")
	var pack := (dummies.get_node("Pack3") as Node2D).global_position
	yellow.global_position = pack + Vector2(700, 60)
	_aim(pack)
	await _wait(0.6)
	await _shot("1_idle_army")

	for i in 6:
		yellow.request_slot(&"primary", pack)
		await _wait(0.1)
	await _shot("2_stinger_volley")
	await _wait(0.4)

	yellow.request_slot(&"cc", pack)
	await _wait(0.35)
	await _shot("3_sting_latched")

	# Swarm Ride into the pack, land in the middle of it.
	yellow.request_slot(&"ability_1", pack)
	await _wait(0.35)
	await _shot("4_swarm_ride")
	await _wait(0.2)
	yellow.release_slot(&"ability_1", pack)
	await _wait(0.12)
	await _shot("5_landing_telegraph")
	await _wait(0.2)
	await _shot("6_landing_burst")
	await _wait(0.6)

	yellow.request_slot(&"movement", yellow.global_position)
	await _wait(0.3)
	await _shot("7_rally")
	await _wait(2.0)

	await _wait(2.5)    # let the pack come back
	yellow.global_position = pack + Vector2(650, 0)
	_aim(pack)
	yellow.request_slot(&"ultimate", pack)
	await _wait(0.35)
	await _shot("8_charge_windup")
	await _wait(0.45)
	await _shot("9_charge_wave")
	await _wait(0.6)
	await _shot("10_charge_drop")

	yellow.hurtbox.take_hit(DamageInfo.create(yellow.health_component.max_health * 0.6, null, DamageInfo.Type.TRUE))
	await _wait(0.2)
	await _shot("11_bugs_falling_off")
	get_tree().quit()


func _aim(at: Vector2) -> void:
	yellow.aim_point = at
	yellow.aim_direction = (at - yellow.global_position).normalized()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
