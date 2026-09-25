extends Node

# Renders review screenshots of the map (needs a display, e.g. xvfb-run):
#   xvfb-run godot --rendering-driver opengl3 res://tools/dream_basin/screenshots.tscn -- <out_dir>

const SHOTS := {
	"overview": [],
	"spawn_a": [Vector2(0, 4000)],
	"cradle": [Vector2(-700, 700)],
	"ruins_a": [Vector2(-2050, 2250)],
	"glade_pad": [Vector2(-2900, 350)],
	"hollow": [Vector2(-4100, 850)],
	"ridge_r": [Vector2(3500, 2100)],
}

var world: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	world = load("res://scenes/dream_basin_world.tscn").instantiate()
	add_child(world)
	var player: Actor = world.get_node("Player")
	var debug: MapDebugView = world.get_node("MapDebugView")
	await _frames(20)
	for shot_name: String in SHOTS:
		var spot: Array = SHOTS[shot_name]
		if spot.is_empty():
			debug.toggle()
			await get_tree().create_timer(0.8).timeout
		else:
			player.global_position = spot[0]
			await _frames(10)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
		if spot.is_empty():
			debug.toggle()
			await get_tree().create_timer(0.8).timeout
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
