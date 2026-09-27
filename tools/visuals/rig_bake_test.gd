extends Node2D

# Headless checks for the cutout rig bake (CutoutRig + RigBaker):
#   the template rig is valid, sampled at the right frame counts, packed into
#   one sheet a row per animation, turned into SpriteFrames with the right
#   loop flags, and the committed template bake loads.
# Rendering itself needs a GPU, so it's only checked to refuse --headless;
# bake for real with tools/visuals/bake_rig.gd.
#
#   godot --headless res://tools/visuals/rig_bake_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const TEMPLATE := "res://resources/visuals/rig_template/rig_template.tscn"
const TEMPLATE_FRAMES := "res://resources/visuals/rig_template/rig_template_frames.tres"

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := (load(TEMPLATE) as PackedScene).instantiate() as CutoutRig
	add_child(rig)
	_check("template root is a CutoutRig", rig != null, "")
	_check("template validates", rig.validate().is_empty(), str(rig.validate()))
	_check("bake list is idle, move, hurt, death",
			rig.get_bake_list() == [&"idle", &"move", &"hurt", &"death"], str(rig.get_bake_list()))

	# idle 1.0s loop, move 0.5s loop, hurt 0.3s, death 0.6s at 12 fps.
	var counts := {&"idle": 12, &"move": 6, &"hurt": 5, &"death": 9}
	for anim_name in counts:
		var n := rig.get_sample_times(anim_name).size()
		_check("%s samples %d frames" % [anim_name, counts[anim_name]], n == counts[anim_name], str(n))
	_check("idle/move loop, hurt/death don't",
			rig.is_looping(&"idle") and rig.is_looping(&"move")
			and not rig.is_looping(&"hurt") and not rig.is_looping(&"death"), "")
	var death := rig.get_sample_times(&"death")
	_check("one-shots end on their last instant", is_equal_approx(death[death.size() - 1], 0.6), str(death))

	# Missing animations are skipped; no player is an error.
	rig.bake_animations = [&"idle", &"nope"]
	_check("missing animations are skipped", rig.get_bake_list() == [&"idle"], str(rig.get_bake_list()))
	rig.animation_player_path = ^"Nope"
	_check("a rig with no AnimationPlayer is refused", not rig.validate().is_empty(), "")
	rig.animation_player_path = ^"AnimationPlayer"
	rig.bake_animations = [&"idle", &"move", &"hurt", &"death"]

	# Aim part: the template's sword arm, hanging down from the shoulder.
	_check("template has an aim part", rig.get_aim_part() != null, "")
	_check("aim pivot is the shoulder relative to the frame centre",
			rig.get_aim_pivot() == Vector2(-12, -18), str(rig.get_aim_pivot()))
	rig.bake_scale = 0.5
	_check("aim pivot follows bake scale", rig.get_aim_pivot() == Vector2(-6, -9), str(rig.get_aim_pivot()))
	var copy := rig.make_aim_part_copy()
	_check("aim part copy is at its pivot, scaled, with its children",
			copy.position == Vector2.ZERO and copy.scale == Vector2(0.5, 0.5) and copy.get_child_count() == 1
			and copy.get_child(0).owner == copy, "")
	copy.free()
	rig.bake_scale = 1.0
	rig.aim_part_path = ^"Hips/Nope"
	_check("a missing aim part is refused", not rig.validate().is_empty(), "")
	rig.aim_part_path = ^"Hips/Torso/ArmFront"

	if not RigBaker.can_render():
		var result: Dictionary = await RigBaker.render(rig, self)
		_check("render refuses --headless with a reason", not result.errors.is_empty(), "")
		_check("the rig is back where it was", rig.get_parent() == self, "")
		_check("the aim part is visible again", rig.get_aim_part().visible, "")

	_test_pack_and_frames()

	var baked := load(TEMPLATE_FRAMES) as SpriteFrames
	_check("committed template bake loads", baked != null and baked.get_animation_names().size() == 4, "")
	if baked != null:
		_check("committed bake has a texture", baked.get_frame_texture(&"idle", 0) != null, "")
		_check("committed bake hurt is a one-shot", not baked.get_animation_loop(&"hurt"), "")
	var aim_scene := load(RigBaker.aim_scene_path(TEMPLATE_FRAMES)) as PackedScene
	_check("committed bake has its aim part scene", aim_scene != null
			and aim_scene.instantiate().name == &"ArmFront", "")

	print("rig_bake_test: %d failed" % failures)
	get_tree().quit(failures)


func _test_pack_and_frames() -> void:
	var size := Vector2i(4, 4)
	var red := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var order: Array[StringName] = [&"a", &"b"]
	var packed := RigBaker.pack({&"a": [red, blue, red], &"b": [blue]}, order, size)
	var sheet: Image = packed.sheet
	_check("sheet is widest row x rows", sheet.get_size() == Vector2i(12, 8), str(sheet.get_size()))
	_check("frames land in their cells", sheet.get_pixel(5, 1) == Color.BLUE
			and sheet.get_pixel(9, 1) == Color.RED and sheet.get_pixel(1, 5) == Color.BLUE, "")
	_check("unused cells stay clear", sheet.get_pixel(5, 5).a == 0.0, "")

	var frames := RigBaker.build_frames(ImageTexture.create_from_image(sheet), packed.cells, order,
			10.0, {&"a": true, &"b": false})
	_check("SpriteFrames has only the baked animations",
			Array(frames.get_animation_names()) == ["a", "b"], str(frames.get_animation_names()))
	_check("frame counts match", frames.get_frame_count(&"a") == 3 and frames.get_frame_count(&"b") == 1, "")
	_check("speed and loop are carried", frames.get_animation_speed(&"a") == 10.0
			and frames.get_animation_loop(&"a") and not frames.get_animation_loop(&"b"), "")
	var third := frames.get_frame_texture(&"a", 2) as AtlasTexture
	_check("atlas regions point at the cells", third != null and third.region == Rect2(8, 0, 4, 4), "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		failures += 1
		print("  FAIL  ", label, "  ", detail)
