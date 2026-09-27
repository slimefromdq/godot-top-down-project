extends Node2D

# Headless checks for the 8-direction live rig pipeline:
#   SheetCutter / SheetSpec   cutting a character sheet into part PNGs
#   VisualsComponent          a hero whose profile has a live_rig (Avery)
#   LiveRig                   picking directions (with hysteresis), the legs
#                             rule (strafe / backpedal / 90-degree clamp),
#                             mirroring, the aim part, idle/walk/sway/stride,
#                             hurt, death and snapshots
#
#   godot --headless res://tools/visuals/live_rig_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const BG := Color(0.88, 0.88, 0.88)
const INK := Color(0.1, 0.1, 0.15)
const PALE := Color(0.97, 0.97, 0.95)

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_cutter()
	_test_direction_of()
	_test_pick_legs()
	await _test_rig()
	await _test_in_game()
	print("live_rig_test: %d failed" % failures)
	get_tree().quit(failures)


# --- SheetCutter ----------------------------------------------------------------

# A 2x2 sheet of 40 px cells on a grey background with white grid lines:
#   row "box":   an outlined box with a white inside, plus a stray 2 px dot
#   row "flame": a C shape (open at the top) whose pale inside leaks out
func _make_sheet() -> Image:
	var img := Image.create_empty(80, 80, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for i in 80:
		for edge in [0, 40, 79]:
			img.set_pixel(edge, i, Color.WHITE)
			img.set_pixel(i, edge, Color.WHITE)
	for column in 2:
		var ox := column * 40
		# box: outline 10..29, white inside
		img.fill_rect(Rect2i(ox + 10, 10, 20, 20), INK)
		img.fill_rect(Rect2i(ox + 12, 12, 16, 16), PALE)
		img.fill_rect(Rect2i(ox + 33, 33, 2, 2), INK)
		# C shape: walls on the left, right and bottom, gap in the middle of the top
		img.fill_rect(Rect2i(ox + 10, 50, 20, 2), INK)
		img.fill_rect(Rect2i(ox + 20, 50, 4, 2), PALE)
		img.fill_rect(Rect2i(ox + 10, 50, 2, 20), INK)
		img.fill_rect(Rect2i(ox + 28, 50, 2, 20), INK)
		img.fill_rect(Rect2i(ox + 10, 68, 20, 2), INK)
		img.fill_rect(Rect2i(ox + 12, 52, 16, 16), PALE)
	return img


func _test_cutter() -> void:
	var path := ProjectSettings.globalize_path("user://live_rig_test_sheet.png")
	_make_sheet().save_png(path)
	var spec := SheetSpec.new()
	spec.source_path = path
	spec.column_edges = PackedInt32Array([0, 40, 80])
	spec.row_edges = PackedInt32Array([0, 40, 80])
	spec.column_names = PackedStringArray(["down", "right"])
	spec.row_names = PackedStringArray(["box", "flame"])
	spec.export_columns = PackedStringArray(["right"])
	spec.out_dir = "user://live_rig_test_parts"
	spec.restore_enclosed_rows = PackedStringArray(["flame"])
	_check("a matching spec validates", spec.validate().is_empty(), str(spec.validate()))

	var result := SheetCutter.cut(spec)
	_check("cuts one PNG per part for the exported columns only", result.errors.is_empty()
			and result.written.size() == 2 and result.written[0].ends_with("box/right.png"), str(result))
	var box := Image.load_from_file(ProjectSettings.globalize_path("user://live_rig_test_parts/box/right.png"))
	_check("the part is trimmed to its art (stray dot dropped)", box != null and box.get_size() == Vector2i(20, 20),
			str(box.get_size() if box != null else null))
	if box != null:
		_check("background keyed out, white inside the outline kept",
				box.get_pixel(10, 10).a == 1.0 and box.get_pixel(10, 10).v > 0.9, str(box.get_pixel(10, 10)))

	var sheet := _make_sheet()
	var plain := SheetCutter.cut_cell(sheet, spec.cell_rect(1, 1), spec, false)
	var restored := SheetCutter.cut_cell(sheet, spec.cell_rect(1, 1), spec, true)
	_check("a leaking pale inside is lost without restore", plain.get_pixel(4, 12).a == 0.0, str(plain.get_pixel(4, 12)))
	_check("restore_enclosed_rows puts it back at restored_alpha",
			absf(restored.get_pixel(4, 12).a - spec.restored_alpha) < 0.01, str(restored.get_pixel(4, 12)))

	var bad := SheetSpec.new()
	bad.column_edges = PackedInt32Array([0, 40])
	bad.column_names = PackedStringArray(["down", "right"])
	bad.export_columns = PackedStringArray(["up"])
	_check("a mismatched spec is refused", bad.validate().size() >= 3, str(bad.validate()))


# --- Pure direction logic ---------------------------------------------------------

func _test_direction_of() -> void:
	var cases := [[0.0, LiveRig.RIGHT], [PI / 2, LiveRig.DOWN], [-PI / 2, LiveRig.UP], [PI, LiveRig.LEFT],
			[deg_to_rad(135), LiveRig.DOWN_LEFT], [deg_to_rad(-45), LiveRig.UP_RIGHT]]
	var ok := cases.all(func(c): return LiveRig.direction_of(c[0]) == c[1])
	_check("angles snap to the 8 directions", ok, "")
	_check("just past a boundary keeps the current direction (hysteresis)",
			LiveRig.direction_of(deg_to_rad(25), LiveRig.RIGHT, 10.0) == LiveRig.RIGHT, "")
	_check("well past it turns", LiveRig.direction_of(deg_to_rad(35), LiveRig.RIGHT, 10.0) == LiveRig.DOWN_RIGHT, "")
	var mirrors := [LiveRig.DOWN_LEFT, LiveRig.LEFT, LiveRig.UP_LEFT]
	var sets_ok := true
	for d in 8:
		sets_ok = sets_ok and LiveRig.is_mirrored(d) == mirrors.has(d)
	_check("the three left directions are mirrors", sets_ok
			and LiveRig.set_name_of(LiveRig.LEFT) == &"Right" and LiveRig.set_name_of(LiveRig.UP_LEFT) == &"UpRight"
			and LiveRig.set_name_of(LiveRig.DOWN_LEFT) == &"DownRight", "")


func _test_pick_legs() -> void:
	var R := LiveRig.RIGHT
	var still := LiveRig.pick_legs(Vector2.RIGHT, Vector2.ZERO, R, R, false, 20.0)
	_check("standing: legs face the torso", still.direction == R and not still.backwards, str(still))
	var forward := LiveRig.pick_legs(Vector2.RIGHT, Vector2(200, 0), R, R, false, 20.0)
	_check("walking toward the aim: forward", forward.direction == R and not forward.backwards, str(forward))
	var strafe := LiveRig.pick_legs(Vector2.RIGHT, Vector2(0, 200), R, R, false, 20.0)
	_check("strafing down while aiming right: legs face down", strafe.direction == LiveRig.DOWN
			and not strafe.backwards, str(strafe))
	var back := LiveRig.pick_legs(Vector2.RIGHT, Vector2(-200, 0), R, R, false, 20.0)
	_check("walking away from the aim: legs face the torso and step backwards",
			back.direction == R and back.backwards, str(back))
	var diagonal_back := LiveRig.pick_legs(Vector2.RIGHT, Vector2(-150, 150), R, R, false, 20.0)
	_check("walking down-left while aiming right: backpedal", diagonal_back.backwards, str(diagonal_back))
	var sticky := LiveRig.pick_legs(Vector2.RIGHT, Vector2.from_angle(deg_to_rad(95)) * 200, R, R, true, 20.0)
	var fresh := LiveRig.pick_legs(Vector2.RIGHT, Vector2.from_angle(deg_to_rad(95)) * 200, R, R, false, 20.0)
	_check("backpedal has hysteresis at 90 degrees", sticky.backwards and not fresh.backwards, "")
	var clamped := LiveRig.pick_legs(Vector2.RIGHT, Vector2(0, 200), LiveRig.UP_RIGHT, LiveRig.UP_RIGHT, false, 20.0)
	_check("legs never face more than 90 degrees off the torso", clamped.direction == LiveRig.DOWN_RIGHT, str(clamped))


# --- A LiveRig built in code ---------------------------------------------------------

func _poly(parent: Node, part_name: String, rect: Rect2, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = part_name
	p.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	p.color = color
	parent.add_child(p)
	return p


func _make_rig() -> LiveRig:
	var rig := LiveRig.new()
	rig.motion = RigMotion.new()
	var tex_a := ImageTexture.create_from_image(Image.create_empty(4, 4, false, Image.FORMAT_RGBA8))
	var tex_b := ImageTexture.create_from_image(Image.create_empty(4, 8, false, Image.FORMAT_RGBA8))
	for half_name in ["Lower", "Upper"]:
		var half := Node2D.new()
		half.name = half_name
		rig.add_child(half)
		for set_name in ["Down", "DownRight", "Right", "UpRight", "Up"]:
			var set := Node2D.new()
			set.name = set_name
			half.add_child(set)
			if half_name == "Lower":
				var legs := Sprite2D.new()
				legs.name = "Legs"
				legs.texture = tex_a
				legs.set_meta(&"stride_texture", tex_b)
				set.add_child(legs)
				_poly(set, "Cape", Rect2(-6, -20, 12, 20), Color.CYAN).set_meta(&"sway", 1.0)
			else:
				var torso := _poly(set, "Torso", Rect2(-8, -30, 16, 20), Color.WHITE)
				var arm := Node2D.new()
				arm.name = "AimArm"
				arm.position = Vector2(6, -26)
				arm.set_meta(&"rest_angle", 90.0)
				torso.add_child(arm)
				_poly(arm, "Sword", Rect2(-1, 0, 2, 20), Color.GRAY)
	return rig


func _step(rig: LiveRig, aim: Vector2, velocity: Vector2, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		rig.update(aim, velocity, 1.0 / 60.0)
		t += 1.0 / 60.0


func _aim_points(rig: LiveRig, aim: Vector2) -> bool:
	var part := rig.get_aim_part()
	if part == null:
		return false
	var points := part.global_transform.basis_xform(Vector2.from_angle(deg_to_rad(90.0))).normalized()
	return points.dot(aim.normalized()) > 0.99


func _test_rig() -> void:
	var rig := _make_rig()
	add_child(rig)
	_check("a full rig validates", rig.validate().is_empty(), str(rig.validate()))

	var all_ok := true
	var detail := ""
	for d in 8:
		var aim := Vector2.from_angle(d * PI / 4.0)
		_step(rig, aim, Vector2.ZERO, 0.1)
		var upper := rig.get_upper()
		var visible_sets := upper.get_children().filter(func(c): return c.visible).map(func(c): return c.name)
		var ok: bool = rig.direction == d and visible_sets == [LiveRig.set_name_of(d)] \
				and (upper.scale.x < 0.0) == LiveRig.is_mirrored(d) and _aim_points(rig, aim)
		if not ok:
			detail += " dir %d: %s scale %.0f" % [d, visible_sets, upper.scale.x]
		all_ok = all_ok and ok
	_check("each of the 8 aims shows one set (mirrored on the left) with the arm on the aim", all_ok, detail)

	var off_axis := Vector2.from_angle(deg_to_rad(-60))
	_step(rig, off_axis, Vector2.ZERO, 0.1)
	_check("the arm aims between directions too", _aim_points(rig, off_axis), "")

	_step(rig, Vector2.RIGHT, Vector2(0, 200), 0.3)
	_check("strafing: upper faces the aim, legs face the walk", rig.direction == LiveRig.RIGHT
			and rig.legs_direction == LiveRig.DOWN and rig.get_lower().get_node(^"Down").visible, "")

	var phase_before: float = rig._walk_phase
	_step(rig, Vector2.RIGHT, Vector2(-200, 0), 0.3)
	_check("backing away: legs face the aim and step backwards", rig.walking_backwards
			and rig.legs_direction == LiveRig.RIGHT and rig._walk_phase < phase_before, "")

	var lower := rig.get_lower()
	var legs := lower.get_node(^"Right/Legs") as Sprite2D
	var textures := {}
	var bounces := {}
	for i in 60:
		rig.update(Vector2.RIGHT, Vector2(200, 0), 1.0 / 60.0)
		textures[legs.texture] = true
		bounces[snappedf(lower.position.y, 0.5)] = true
	_check("walking swaps the stride texture and bounces the legs", textures.size() == 2 and bounces.size() > 3,
			"%d textures, %d heights" % [textures.size(), bounces.size()])
	var cape := lower.get_node(^"Right/Cape") as Node2D
	var angles := {}
	for i in 30:
		rig.update(Vector2.RIGHT, Vector2.ZERO, 1.0 / 30.0)
		angles[snappedf(cape.rotation, 0.001)] = true
	_check("sway parts swing", angles.size() > 5, str(angles.size()))

	rig.hurt()
	_step(rig, Vector2.RIGHT, Vector2.ZERO, rig.motion.hurt_time * 0.5)
	var tilted := absf(rig.rotation) > deg_to_rad(rig.motion.hurt_tilt_deg) * 0.8
	var aims_while_tilted := _aim_points(rig, Vector2.RIGHT)
	_step(rig, Vector2.RIGHT, Vector2.ZERO, rig.motion.hurt_time)
	_check("hurt tilts, the arm keeps aiming, then it settles", tilted and aims_while_tilted
			and is_zero_approx(rig.rotation), "")

	rig.time_scale = 0.0
	var before := rig.get_upper().position
	_step(rig, Vector2.RIGHT, Vector2.ZERO, 0.5)
	_check("time_scale 0 freezes the motion", rig.get_upper().position == before, "")
	rig.time_scale = 1.0

	var snapshot := rig.make_snapshot()
	_check("snapshot is a frozen copy showing the same set", snapshot.get_script() == null
			and snapshot.get_node(^"Upper/Right").visible and not snapshot.get_node(^"Upper/Down").visible, "")
	snapshot.free()

	rig.die()
	_step(rig, Vector2.RIGHT, Vector2.ZERO, rig.motion.death_time + rig.motion.death_fade_time + 0.1)
	_check("death tips over and fades out", rig.is_dead() and rig.modulate.a < 0.01
			and absf(rig.rotation) > deg_to_rad(rig.motion.death_tip_deg) * 0.9, "")
	rig.revive()
	_step(rig, Vector2.RIGHT, Vector2.ZERO, 0.05)
	_check("revive restores the rig", not rig.is_dead() and rig.modulate.a == 1.0 and absf(rig.rotation) < 0.01, "")

	rig.get_lower().get_node(^"Up").free()
	_check("a missing facing set is refused", not rig.validate().is_empty(), "")
	rig.queue_free()


# --- Wired into a hero (Avery's profile has live_rig) ---------------------------------

func _test_in_game() -> void:
	var hero: Hero = load("res://heroes/avery/avery.tscn").instantiate()
	hero.team = &"a"
	add_child(hero)
	await get_tree().process_frame
	var visuals := VisualsComponent.find_on(hero)
	var rig := visuals.body as LiveRig
	_check("Avery's body is her live rig", rig != null and rig.validate().is_empty(), "")
	if rig == null:
		hero.queue_free()
		return
	_check("rig parts share the body's flash material", rig.material != null
			and rig.find_children("*", "Sprite2D", true, false).all(func(p): return p.use_parent_material), "")
	var ok := true
	for d in [LiveRig.UP, LiveRig.LEFT, LiveRig.DOWN_RIGHT]:
		hero.aim_direction = Vector2.from_angle(d * PI / 4.0)
		for i in 3:
			await get_tree().process_frame
		ok = ok and rig.direction == d and _aim_points(rig, hero.aim_direction)
	_check("the rig follows the hero's aim, arm on target", ok, "")
	visuals.play_body_animation(&"hurt")
	for i in 6:
		await get_tree().process_frame
	_check("the hurt animation tilts the rig", absf(rig.rotation) > 0.01, str(rig.rotation))
	var ghost := visuals.make_body_snapshot()
	_check("afterimages copy the rig", ghost != null and ghost.get_node_or_null(^"Upper") != null, "")
	if ghost != null:
		ghost.free()
	visuals.play_body_animation(&"death")
	_check("death lasts the rig's tip and fade", is_equal_approx(visuals.get_death_duration(),
			maxf(visuals.profile.death_linger_time, rig.motion.death_time + rig.motion.death_fade_time)), "")
	_check("death plays on the rig", rig.is_dead(), "")
	visuals.revive()
	_check("revive brings it back", not rig.is_dead(), "")
	hero.queue_free()


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		failures += 1
		print("  FAIL  ", label, "  ", detail)
