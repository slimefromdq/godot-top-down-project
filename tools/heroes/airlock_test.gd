extends Node2D

# Headless checks for the minigame framework (MinigameHost / MinigameInstance)
# and the airlock (AirlockMinigame, resources/minigames/airlock.tres).
#
#   godot --headless res://tools/heroes/airlock_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const AIRLOCK := "res://resources/minigames/airlock.tres"

var failures := 0
var hero: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	hero = load(HERO).instantiate()
	hero.team = &"a"
	add_child(hero)
	await _physics_frames(3)
	_test_data()
	await _test_perfect_run()
	await _test_stand_still()
	await _test_bot_and_straight_line()
	await _test_host_rules()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _airlock() -> AirlockData:
	return load(AIRLOCK)


func _test_data() -> void:
	print("\n-- Data")
	var room := _airlock()
	_check("airlock data validates", room.validate().is_empty(), "\n".join(room.validate()))
	_check("a flawless run is tuned to ~1.5 s", absf(room.perfect_time() - 1.5) < 0.05, "%.2f s" % room.perfect_time())
	_check("forced exit at 4 s", room.max_duration == 4.0, "")


# Plays one airlock on the hero; `driver` is Callable(game) -> Vector2 each
# tick (null = the minigame's own bot). Returns the result.
func _play(driver: Callable) -> Dictionary:
	var host := MinigameHost.find_or_create(hero)
	var game := AirlockMinigame.new(_airlock())
	var done := [{}]
	game.finished.connect(func(result): done[0] = result)
	host.play(game)
	var waited := 0.0
	while done[0].is_empty() and waited < 6.0:
		if driver.is_valid():
			host.set_input(driver.call(game))
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return done[0]


# A scripted "good player": each tick, the first of these moves that stays
# clear of everything for the next few ticks.
func _dodger(game: AirlockMinigame) -> Vector2:
	var room := game.get_airlock()
	var options := [Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2(1, 1).normalized(), Vector2.UP, Vector2.DOWN, Vector2.ZERO]
	var dt := get_physics_process_delta_time()
	for move in options:
		if _clear(game, room, move, dt, 14):
			return move
	return Vector2.RIGHT


func _clear(game: AirlockMinigame, room: AirlockData, move: Vector2, dt: float, ticks: int) -> bool:
	var at: Vector2 = game.player
	for i in range(1, ticks + 1):
		at += move * room.player_speed * dt
		at.y = clampf(at.y, room.player_radius, room.room_size.y - room.player_radius)
		for hazard in game.hazards:
			var future := AirlockMinigame.Hazard.new()
			future.kind = hazard.kind
			future.position = hazard.position + hazard.velocity * dt * i
			if game.hazard_hits(future, at, room.player_radius + 4.0):
				return false
		if game.arm_out and game.arm_hand.distance_to(at) < room.arm_radius + room.player_radius + 4.0:
			return false
	return true


func _test_perfect_run() -> void:
	print("\n-- A good run")
	var result := await _play(_dodger)
	_check("a scripted perfect run escapes", result.get("escaped", false), str(result))
	_check("...in 1.4 - 1.7 s", result.get("time", 0.0) >= 1.4 and result.get("time", 0.0) <= 1.7, "%.2f s" % result.get("time", 0.0))
	_check("...without being hit", result.get("hits", -1) == 0, str(result.get("hits", -1)))


func _test_stand_still() -> void:
	print("\n-- Standing still")
	var result := await _play(func(_g): return Vector2.ZERO)
	_check("a run that stands still exits at 4 s", result.get("timeout", false)
		and absf(result.get("time", 0.0) - 4.0) < 0.05, str(result))


func _test_bot_and_straight_line() -> void:
	print("\n-- Walking straight / the AI bot")
	var straight := await _play(func(_g): return Vector2.RIGHT)
	_check("walking straight at the door gets hit (the hazards matter)", straight.get("hits", 0) > 0, str(straight))
	var bot := await _play(Callable())
	_check("an AI victim (no input: bot_input) walks for the door and gets out", bot.get("escaped", false)
		and bot.get("time", 0.0) > 1.6 and bot.get("time", 0.0) < 4.0, str(bot))


func _test_host_rules() -> void:
	print("\n-- MinigameHost")
	var host := MinigameHost.find_or_create(hero)
	# The host's rules on an empty room (no hazards, no arm).
	var empty: AirlockData = _airlock().duplicate()
	empty.heart_lanes = PackedFloat32Array()
	empty.bubble_columns = PackedFloat32Array()
	empty.arm_delay = 999.0
	var game := AirlockMinigame.new(empty)
	var ended := [{}]
	host.finished.connect(func(_game, result): ended[0] = result)
	_check("the host starts it", host.play(game) and host.is_playing(), "")
	_check("...and the actor is occupied (rooted, silenced)", hero.status_component.has_status(&"minigame_occupied")
		and hero.status_component.is_rooted() and hero.status_component.is_silenced(), "")
	_check("one at a time", not host.play(AirlockMinigame.new(_airlock())), "")
	# Walk into the door zone straight away: the goal can't end it early.
	game.player = Vector2(_airlock().door_x + 20.0, 20.0)
	game.hazards.clear()
	var waited := 0.0
	while host.is_playing() and waited < 2.0:
		host.set_input(Vector2.ZERO)
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("reaching the goal early still waits for min_duration", ended[0].get("escaped", false)
		and absf(ended[0].get("time", 0.0) - _airlock().min_duration) < 0.05, str(ended[0]))
	_check("...and ending frees the actor", not hero.status_component.has_status(&"minigame_occupied"), "")
	ended[0] = {}
	host.play(AirlockMinigame.new(_airlock()))
	await _physics_frames(2)
	host.stop()
	_check("stop() ends it", not host.is_playing() and ended[0].get("stopped", false), str(ended[0]))
	_check("the view only opens for the local viewer (not this test hero)", host._view == null, "")

	# The local viewer gets the overlay (with the map inset); it closes after.
	LocalView.set_viewer(hero)
	host.play(AirlockMinigame.new(empty))
	await _frames(3)
	var view = host._view
	_check("the local viewer gets the overlay, with a live map inset", is_instance_valid(view)
		and view.find_children("*", "SubViewport", true, false).size() == 1, "")
	host.stop()
	await _frames(2)
	_check("...which closes when it ends", not is_instance_valid(view), "")
	LocalView.clear_viewer()

	# F1 > Tools > Airlock practice runs it on the player.
	hero.add_to_group(&"player")
	var message: String = DebugTools.start_airlock_practice()
	_check("F1 > Tools > Airlock practice starts it on the player", host.is_playing(), message)
	host.stop()
	hero.remove_from_group(&"player")


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
