extends Node

# Headless behaviour test for the Dream Basin mobility systems. Drives the real
# player with simulated input inside the real map and checks where it ends up.
#
#   godot --headless res://tools/dream_basin/smoke_test.tscn
#
# (Run as a scene, not with --script, so autoloads like AudioManager exist.)
#
# Exits with the number of failed checks (0 = all passed).

const WORLD := "res://scenes/dream_basin_world.tscn"

var world: Node
var player: Actor
var failures := 0


func _ready() -> void:
	world = load(WORLD).instantiate()
	add_child(world)
	_run.call_deferred()


func _run() -> void:
	player = world.get_node("Player")
	await _frames(10)

	await _test_ledge_blocks_climbing()
	await _test_ledge_allows_drop()
	await _test_jump_pad_climbs_cliff()
	await _test_one_way_teleporter()
	await _test_two_way_teleporter()
	await _test_speed_strip()
	_test_shots_cross_ledges_and_low_cover()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_ledge_blocks_climbing() -> void:
	# Basin side of the left Wild's cliff (x = -2750), walking west into it.
	_place(Vector2(-2450, -150))
	await _hold("move_left", 1.5)
	_check("ledge blocks climbing", player.global_position.x > -2750 + 40,
		"x=%.0f" % player.global_position.x)


func _test_ledge_allows_drop() -> void:
	# High side (Glade), walking east off the cliff into the basin.
	_place(Vector2(-3000, -150))
	await _hold("move_right", 1.5)
	_check("ledge allows dropping", player.global_position.x > -2600,
		"x=%.0f" % player.global_position.x)


func _test_jump_pad_climbs_cliff() -> void:
	var pad: JumpPad = world.get_node("DreamBasin/Mobility/JumpPads/GladeSpringA")
	var landing := pad.get_landing_position()
	_place(pad.global_position + Vector2(160, 0))
	await _hold("move_left", 0.3)
	_check("jump pad launches", player.is_airborne(), "")
	await _seconds(pad.air_time + 0.3)
	var error := player.global_position.distance_to(landing)
	_check("jump pad lands on target (up the cliff)", error < 40 and not player.is_airborne(),
		"landed %.0f px from target" % error)
	_check("mask restored after landing", player.collision_mask & MapLayers.JUMPABLE == MapLayers.JUMPABLE, "")


func _test_one_way_teleporter() -> void:
	var entrance: Teleporter = world.get_node("DreamBasin/Mobility/Teleporters/DawnDoor_Entrance")
	var exit: Teleporter = world.get_node("DreamBasin/Mobility/Teleporters/DawnDoor_Exit")
	_place(entrance.global_position)
	await _seconds(entrance.channel_time + 0.4)
	_check("spawn door sends to the Hollow", player.global_position.distance_to(exit.global_position) < 60, "")
	await _seconds(1.5)
	_check("spawn door exit is one-way", player.global_position.distance_to(exit.global_position) < 60, "")


func _test_two_way_teleporter() -> void:
	var a: Teleporter = world.get_node("DreamBasin/Mobility/Teleporters/DreamRift_A")
	var b: Teleporter = world.get_node("DreamBasin/Mobility/Teleporters/DreamRift_B")
	_place(a.global_position)
	await _seconds(0.3)
	_check("channel is not instant", player.global_position.distance_to(a.global_position) < 60, "")
	await _seconds(a.channel_time + 0.2)
	_check("dream rift sends A -> B", player.global_position.distance_to(b.global_position) < 60, "")
	await _seconds(2.0)
	_check("arrival doesn't bounce back", player.global_position.distance_to(b.global_position) < 60, "")
	# Step off and back on while the link rests: nothing should happen.
	_place(b.global_position + Vector2(400, 0))
	await _frames(3)
	_place(b.global_position)
	await _seconds(b.channel_time + 0.3)
	_check("link cooldown blocks immediate return", player.global_position.distance_to(b.global_position) < 60, "")
	await _seconds(b.cooldown)
	_check("works again after cooldown", player.global_position.distance_to(a.global_position) < 60, "")


func _test_speed_strip() -> void:
	var strip: SpeedStrip = world.get_node("DreamBasin/Mobility/SpeedStrips/LamplightRoad1")
	var base_speed := player.movement_component.get_move_speed()
	_place(strip.global_position - Vector2(strip.size.x * 0.45, 0))
	await _hold("move_right", 0.5)
	var along := player.velocity.x
	_check("speed strip boosts along its axis", along > base_speed * 1.4,
		"%.0f vs base %.0f" % [along, base_speed])
	_place(strip.global_position + Vector2(0, strip.size.y * 0.3))
	await _hold("move_down", 0.25)
	_check("speed strip ignores crossing", player.velocity.length() < base_speed * 1.1,
		"%.0f" % player.velocity.length())
	await _seconds(0.5)


func _test_shots_cross_ledges_and_low_cover() -> void:
	var bullet: Area2D = load("res://scenes/bullet.tscn").instantiate()
	var mask := bullet.collision_mask
	bullet.free()
	var space := player.get_world_2d().direct_space_state
	# Across the left Wild's cliff, basin -> Glade.
	var across_ledge := PhysicsRayQueryParameters2D.create(Vector2(-2450, -150), Vector2(-3000, -150), mask)
	_check("bullets cross ledges", space.intersect_ray(across_ledge).is_empty(), "")
	var low: CoverBody = world.get_node("DreamBasin/Cover/LowCover").get_child(0)
	var through_low := PhysicsRayQueryParameters2D.create(low.global_position + Vector2(-400, 0),
		low.global_position + Vector2(400, 0), mask)
	var hit := space.intersect_ray(through_low)
	_check("bullets fly over low cover", hit.is_empty() or hit.collider != low, "")
	var walk_mask := player.collision_mask
	_check("characters collide with low cover and ledges",
		walk_mask & (MapLayers.LOW_COVER | MapLayers.LEDGES) == (MapLayers.LOW_COVER | MapLayers.LEDGES), "")


# --- helpers -----------------------------------------------------------------

func _place(point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _seconds(seconds)
	Input.action_release(action)
	await _frames(2)


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
