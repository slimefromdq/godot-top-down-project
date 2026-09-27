extends Node

## Per-visual render cost (run with a real renderer, not --headless): plays
## the bot match for a while, pauses it so the picture holds still, then
## hides every CanvasItem of one script/class at a time and reports the frame
## time, draw calls and primitives saved. Hiding a node hides its children
## too, so a hero's row includes everything drawn under it.

const WORLD := preload("res://scenes/dream_basin_world.tscn")
const WINDOW := 20


func _ready() -> void:
	_run.call_deferred()


func _window() -> Array:
	var started := Time.get_ticks_usec()
	var calls := 0.0
	var prims := 0.0
	for i in WINDOW:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	return [(Time.get_ticks_usec() - started) / 1000.0 / WINDOW, calls / WINDOW, prims / WINDOW]


func _key(node: Node) -> String:
	var script: Script = node.get_script()
	return script.resource_path.get_file() if script != null else node.get_class()


func _run() -> void:
	var world := WORLD.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await get_tree().physics_frame
	seed(7)
	DebugTools.fill_with_bots(1)
	DebugTools.get_match().start_playing()
	var player := get_tree().get_first_node_in_group(&"player")
	(player as Hero).set_bot_controlled(true)
	for i in 300:
		await get_tree().process_frame
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var all := get_tree().root.find_children("*", "CanvasItem", true, false)
	var counts: Dictionary = {}
	for node in all:
		counts[_key(node)] = counts.get(_key(node), 0) + 1
	var base: Array = await _window()
	print("base %.2f ms  %.0f draw calls  %.0f primitives" % base)
	var results: Array = []
	for key in counts:
		var hidden: Array = []
		for node in get_tree().root.find_children("*", "CanvasItem", true, false):
			if _key(node) == key and node.visible:
				node.visible = false
				hidden.append(node)
		if hidden.is_empty():
			continue
		var off: Array = await _window()
		for node in hidden:
			if is_instance_valid(node):
				node.visible = true
		var again: Array = await _window()
		var ref := [(base[0] + again[0]) * 0.5, (base[1] + again[1]) * 0.5, (base[2] + again[2]) * 0.5]
		base = again
		results.append([ref[0] - off[0], ref[1] - off[1], ref[2] - off[2], key, counts[key]])
	results.sort_custom(func(a, b): return a[1] > b[1])
	for r in results.slice(0, 30):
		print("saves %6.2f ms %6.0f calls %8.0f prims  %s (x%d)" % r)
	get_tree().quit(0)
