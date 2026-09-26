extends Node

# Screenshots of Cosmo's kit in the Training Grounds, swapped in the same way
# as F1 -> "Play as" (DebugTools.swap_player), at level 10 (4 moons). Prints
# the damage she dealt per step.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/heroes/capture_cosmo.tscn -- <out_dir>

const DEFINITION := "res://heroes/cosmo/cosmo_definition.tres"

var out_dir := "user://cosmo_captures"
var cosmo: Hero
var _dealt := 0.0
var _hits := 0


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
	cosmo = DebugTools.swap_player(load(DEFINITION))
	await get_tree().process_frame
	cosmo.get_node("PlayerHeroInput").set_physics_process(false)
	cosmo.get_node("PlayerHeroInput").set_process(false)
	CombatEvents.damage_dealt.connect(func(info: DamageInfo):
		if info.source == cosmo:
			_dealt += info.final_amount
			_hits += 1)
	DebugTools.set_player_level(10)
	var dummies := get_tree().current_scene.get_node("Dummies")
	var pack := (dummies.get_node("Pack3") as Node2D).global_position
	cosmo.global_position = pack + Vector2(420, 60)
	_aim(pack)
	await _wait(0.6)
	await _shot("1_orbit")

	_step("crescent")
	cosmo.request_slot(&"ability_1", pack)
	await _wait(0.3)
	await _shot("2_crescent_out")
	await _wait(0.6)
	await _shot("3_moonlit")
	_report("crescent (both passes)")

	_step("tide")
	cosmo.request_slot(&"cc", pack)
	await _wait(0.6)
	await _shot("4_tide_pull")
	await _wait(1.0)
	_report("tide")

	_step("volley")
	for i in 8:
		cosmo.request_slot(&"primary", pack)
		await _wait(0.1)    # SEMI at 10 shots/s
		if i == 5:
			await _shot("5_volley")
	await _wait(0.6)
	_report("8-moon volley (piercing the pack)")

	_step("new moon")
	cosmo.request_slot(&"movement", cosmo.global_position + Vector2(0, 300))
	await _wait(0.2)
	await _shot("6_new_moon")
	await _wait(0.8)

	await _wait(3.0)    # let the pack respawn
	_step("starfall")
	cosmo.global_position = pack + Vector2(200, 60)
	cosmo.request_slot(&"ultimate", pack)
	await _wait(1.4)
	await _shot("7_starfall")
	await _wait(2.6)
	_report("starfall (full channel, meteors on the pack)")
	get_tree().quit()


func _step(name: String) -> void:
	_dealt = 0.0
	_hits = 0
	print("--- ", name)


func _report(what: String) -> void:
	print("%s: %.0f damage in %d hits" % [what, _dealt, _hits])


func _aim(at: Vector2) -> void:
	cosmo.aim_point = at
	cosmo.aim_direction = (at - cosmo.global_position).normalized()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
