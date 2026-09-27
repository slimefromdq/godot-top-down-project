extends SceneTree

# Bakes a CutoutRig scene into a sprite sheet + SpriteFrames for
# VisualProfile > Sprite Frames.
#
#   godot --script res://tools/visuals/bake_rig.gd -- <rig.tscn> [<out_frames.tres>] [--profile <visuals.tres>]
#
# Writes <out>.png (the sheet) next to <out>.tres; the default out is the rig
# path with "_frames". A rig with an aim part also gets <out>_aim.tscn.
# --profile points that VisualProfile at the bake (sprite frames + aim part).
# It needs a renderer, so NOT --headless. In a cloud session wrap it:
#   xvfb-run -a godot --rendering-driver opengl3 --script res://tools/visuals/bake_rig.gd -- <rig.tscn>
# Then run `godot --headless --import` so the new PNG is imported.
# Exits 0 on success, 1 on failure.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var profile_path := ""
	var at := args.find("--profile")
	if at != -1:
		profile_path = args[at + 1] if at + 1 < args.size() else ""
		args = args.slice(0, at) + args.slice(at + 2)
	if args.is_empty() or (at != -1 and profile_path == ""):
		push_error("usage: -- <rig.tscn> [<out_frames.tres>] [--profile <visuals.tres>]")
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
	if result.aim_scene != null:
		print("  aim part: %s  pivot %s  rest %.0f deg" % [RigBaker.aim_scene_path(frames_path),
				result.aim_pivot, result.aim_rest_angle])
	if profile_path != "":
		var profile := load(profile_path) as VisualProfile
		if profile == null:
			push_error("%s is not a VisualProfile" % profile_path)
			quit(1)
			return
		RigBaker.apply_to_profile(result, frames_path, profile)
		err = ResourceSaver.save(profile, profile_path)
		if err != OK:
			push_error("saving %s failed: %s" % [profile_path, error_string(err)])
			quit(1)
			return
		print("  updated %s" % profile_path)
	var frames: SpriteFrames = result.frames
	for anim_name in frames.get_animation_names():
		print("  %s: %d frames" % [anim_name, frames.get_frame_count(anim_name)])
	print("baked %s -> %s + %s" % [rig_path, frames_path, sheet_path])
	quit(0)
