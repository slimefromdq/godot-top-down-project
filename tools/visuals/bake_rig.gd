extends SceneTree

# Bakes a CutoutRig scene into a sprite sheet + SpriteFrames for
# VisualProfile > Sprite Frames.
#
#   godot --script res://tools/visuals/bake_rig.gd -- <rig.tscn> [<out_frames.tres>]
#
# Writes <out>.png (the sheet) next to <out>.tres; the default out is the rig
# path with "_frames". It needs a renderer, so NOT --headless. In a cloud
# session wrap it:
#   xvfb-run -a godot --rendering-driver opengl3 --script res://tools/visuals/bake_rig.gd -- <rig.tscn>
# Then run `godot --headless --import` so the new PNG is imported.
# Exits 0 on success, 1 on failure.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <rig.tscn> [<out_frames.tres>]")
		quit(1)
		return
	var rig_path: String = args[0]
	var frames_path: String = args[1] if args.size() > 1 else rig_path.get_basename() + "_frames.tres"
	var sheet_path := frames_path.get_basename() + ".png"

	var scene := load(rig_path) as PackedScene
	var rig := scene.instantiate() as CutoutRig if scene != null else null
	if rig == null:
		push_error("%s is not a scene whose root uses cutout_rig.gd" % rig_path)
		quit(1)
		return
	root.add_child(rig)

	var result: Dictionary = await RigBaker.bake(rig, root, sheet_path)
	if not result.errors.is_empty():
		for e in result.errors:
			push_error(e)
		quit(1)
		return
	var err := RigBaker.save(result, sheet_path, frames_path)
	if err != OK:
		push_error("save failed: %s" % error_string(err))
		quit(1)
		return
	var frames: SpriteFrames = result.frames
	for anim_name in frames.get_animation_names():
		print("  %s: %d frames" % [anim_name, frames.get_frame_count(anim_name)])
	print("baked %s -> %s + %s" % [rig_path, frames_path, sheet_path])
	quit(0)
