extends Node2D

# Headless checks for the minigame framework (MinigameHost / MinigameInstance)
# and the airlock maze (AirlockMinigame, resources/minigames/airlock.tres).
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
	await _test_perfect_runs()
	await _test_stand_still_and_straight()
	await _test_bot()
	await _test_host_rules()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _airlock() -> AirlockData:
	return load(AIRLOCK)


func _test_data() -> void:
	print("\n-- Data")
	var room := _airlock()
	_check("airlock data validates", room.validate().is_empty(), "\n".join(room.validate()))
	_check("several maze layouts", room.layouts.size() >= 3, str(room.layouts.size()))
	_check("forced exit at 4 s", room.max_duration == 4.0, "")


# Plays one airlock on the hero; `driver` is Callable(game) -> Vector2 each
# tick (an invalid Callable = the minigame's own bot). Returns the result.
func _play(driver: Callable, layout: int = -1) -> Dictionary:
	var host := MinigameHost.find_or_create(hero)
	var game := AirlockMinigame.new(_airlock(), layout)
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


func _test_perfect_runs() -> void:
	print("\n-- A flawless run through each maze")
	for i in _airlock().layouts.size():
		var result := await _play(func(g): return g.direction_home(g.player), i)
		_check("maze %d: a scripted perfect run escapes in 1.4 - 1.7 s" % i, result.get("escaped", false)
			and result.get("time", 0.0) >= 1.4 and result.get("time", 0.0) <= 1.7, str(result))


func _test_stand_still_and_straight() -> void:
	print("\n-- Standing still / walking straight")
	var still := await _play(func(_g): return Vector2.ZERO, 0)
	_check("a run that stands still exits at 4 s", still.get("timeout", false)
		and absf(still.get("time", 0.0) - 4.0) < 0.05, str(still))
	var straight := await _play(func(_g): return Vector2.RIGHT, 0)
	_check("walking straight at the door hits a wall and never gets out (the maze matters)", straight.get("timeout", false), str(straight))


func _test_bot() -> void:
	print("\n-- AI victims")
	var bot := await _play(Callable(), 2)
	_check("an AI victim (bot_input) finds the way out, slower than a good player", bot.get("escaped", false)
		and bot.get("time", 0.0) > 1.7 and bot.get("time", 0.0) < 4.0, str(bot))
	var picks := {}
	for i in 12:
		var game := AirlockMinigame.new(_airlock())
		game.actor = hero
		game._on_start()
		picks[game.layout_index] = true
		game.free()
	_check("each run picks a layout at random", picks.size() >= 2, str(picks.keys()))


func _test_host_rules() -> void:
	print("\n-- MinigameHost")
	var host := MinigameHost.find_or_create(hero)
	var game := AirlockMinigame.new(_airlock(), 0)
	var ended := [{}]
	host.finished.connect(func(_game, result): ended[0] = result)
	_check("the host starts it", host.play(game) and host.is_playing(), "")
	_check("...and the actor is occupied (silenced)", hero.status_component.has_status(&"minigame_occupied")
		and hero.status_component.is_silenced(), "")
	_check("one at a time", not host.play(AirlockMinigame.new(_airlock())), "")
	# Put the player in the door straight away: the goal can't end it early.
	game.player = Vector2(_airlock().door_x + 20.0, 150.0)
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

	LocalView.set_viewer(hero)
	host.play(AirlockMinigame.new(_airlock()))
	await _frames(3)
	var view = host._view
	_check("the local viewer gets the overlay, with a live map inset", is_instance_valid(view)
		and view.find_children("*", "SubViewport", true, false).size() == 1, "")
	host.stop()
	await _frames(2)
	_check("...which closes when it ends", not is_instance_valid(view), "")
	LocalView.clear_viewer()

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
