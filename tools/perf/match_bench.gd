extends Node

## Headless frame-time benchmark: the real Dream Basin world, 12 bots, a long
## stretch of match time. Prints the average and worst wall time per frame so
## a performance patch can be measured before and after. (The first frame
## includes building the bots' navigation graph.)
## godot --headless res://tools/perf/match_bench.tscn [-- frames]

const WORLD := preload("res://scenes/dream_basin_world.tscn")

var frames := 3600


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		frames = int(args[0])
	_run.call_deferred()


func _run() -> void:
	var world := WORLD.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await get_tree().physics_frame
	seed(7)
	DebugTools.fill_with_bots(1)
	var manager := DebugTools.get_match()
	if manager != null:
		manager.start_playing()
	var player := get_tree().get_first_node_in_group(&"player")
	if player is Hero:
		(player as Hero).set_bot_controlled(true)
	var worst := 0.0
	var nodes := 0.0
	var started := Time.get_ticks_usec()
	for frame in frames:
		var frame_start := Time.get_ticks_usec()
		await get_tree().process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - frame_start) / 1000.0)
		nodes += Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var wall := (Time.get_ticks_usec() - started) / 1000.0
	print("frames %d  wall %.0f ms  (%.3f ms/frame, worst %.1f ms)" % [frames, wall, wall / frames, worst])
	print("nodes avg %.0f" % (nodes / frames))
	get_tree().quit(0)
