extends Node

# Screenshots of the objective's look, for before/after comparisons:
# an idle Dreamer, a stirring Dreamer (Lullaby under way), a full Mote stack,
# the Dream Mote telegraph, and the HUD during a stir. Dream Basin.
#
#   xvfb-run godot --rendering-driver opengl3 res://tools/match/capture_objective.tscn -- <out_dir> [prefix]

var out_dir := "user://objective_captures"
var prefix := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		prefix = args[1] + "_"
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
	manager.start_playing()
	manager.clock = 9 * 60 + 5.0
	var director := MoteDirector.find(get_tree())
	director.clear_motes()
	var player := DebugTools.get_player()
	player.get_node("PlayerHeroInput").set_physics_process(false)
	player.get_node("PlayerHeroInput").set_process_unhandled_input(false)
	var dawn := Dreamer.find_for(get_tree(), &"a")
	var dusk := Dreamer.find_for(get_tree(), &"b")

	# 1. Idle Dreamer (Dawn's, some wake, some Sweet Dreams).
	dawn.set_wake(42.0)
	dawn.sweet = 12.0
	dusk.set_wake(68.0)
	player.global_position = dawn.global_position + Vector2(-420, -250)
	await _wait(1.2)
	await _shot("dreamer_idle")

	# 2. A full Mote stack.
	player.global_position = Vector2(-600, 900)
	DebugTools.give_player_motes(25)
	await _wait(1.0)
	await _shot("mote_stack")
	director.clear_motes()

	# 3. The Dream Mote telegraph (announced, not spawned yet). Let the
	# director notice the cleared Dream Mote first, then pull its timer in.
	await _wait(0.2)
	director._next_dream_time = manager.clock + director.get_rules().dream_mote_warning - 4.0
	director._dream_warned = false
	player.global_position = director.get_dream_point() + Vector2(-380, 260)
	await _wait(1.5)
	await _shot("dream_mote_telegraph")

	# 4 + 5. Dusk's Dreamer stirring with a Lullaby under way, and the HUD.
	director.clear_motes()
	dusk.start_stir()
	dusk.lullaby = 0.4
	player.global_position = dusk.global_position + Vector2(-650, 250)
	DebugTools.give_player_motes(8)
	await _wait(1.2)
	await _shot("dreamer_stirring")
	await _shot("hud_stir")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if shot_name == "hud_stir":
		image = image.get_region(Rect2i(0, 0, image.get_width(), 220))
	image.save_png(out_dir.path_join(prefix + shot_name + ".png"))
