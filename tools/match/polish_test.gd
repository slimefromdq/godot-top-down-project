extends Node2D

# Headless checks for the objective's polish systems (M4): the chime scale,
# the announcer (queue, priority interrupts, the events it announces, the
# text toggle), adaptive music tiers (rise at once, fall one step per hold,
# the victory stop), Mote squash pops, dreaming-zone fades, the Dreamer's
# deposit reactions, the minimap's custom icons and big pings, and the wake
# sequence into the victory screen (slow motion, then back to normal speed).
#
#   godot --headless res://tools/match/polish_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DREAMER := "res://scenes/match/dreamer.tscn"
const MINIMAP := "res://scenes/hud/minimap.tscn"

var failures := 0
var manager: MatchManager
var director: MoteDirector
var rules: MatchRules
var dreamer_a: Dreamer
var dreamer_b: Dreamer
var hero: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := GameMap.new()
	add_child(map)
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.trickle_interval = 1e6
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	director = manager.get_node("MoteDirector")
	director.reset_schedule()
	dreamer_a = _dreamer(&"a", Vector2(0, 2000))
	dreamer_b = _dreamer(&"b", Vector2(0, -2000))
	hero = load(HERO).instantiate()
	hero.team = &"a"
	hero.position = Vector2(3000, 0)
	hero.add_to_group(&"player")
	add_child(hero)
	await _frames(3)
	manager.start_warmup()
	await _frames(2)

	_test_chimes()
	await _test_announcer()
	await _test_music()
	await _test_mote_and_zone_fx()
	await _test_dreamer_reactions()
	await _test_minimap_icons()
	await _test_wake_sequence()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_chimes() -> void:
	print("\n-- Chimes")
	var pitches: Array = []
	for n in range(1, 12):
		pitches.append(rules.chime_pitch(n))
	var rising := true
	for i in range(1, 10):
		rising = rising and pitches[i] > pitches[i - 1]
	_check("pickups and deposit ticks climb a pentatonic scale over two octaves", rising
		and is_equal_approx(pitches[5], 2.0) and is_equal_approx(pitches[10], pitches[0]), str(pitches))
	_check("bank and deliver chords (deliver brighter)", rules.bank_chord.size() >= 3
		and rules.deliver_chord[0] > rules.bank_chord[0], "")


func _test_announcer() -> void:
	print("\n-- Announcer")
	var announcer := Announcer.new()
	add_child(announcer)
	announcer.bind(manager)
	announcer.say("Minor thing", Announcer.MINOR)
	# Banners advance on process frames (several physics ticks can pass first).
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a banner shows", announcer.current != null and announcer.current.text == "Minor thing", "")
	announcer.say("Another minor", Announcer.MINOR)
	announcer.say("Big thing", Announcer.CRITICAL)
	_check("a higher priority cuts the current one short", announcer.current.leaving >= 0.0, "")
	_check("...and jumps the queue", announcer.queue[0].text == "Big thing", str(announcer.queue.map(func(b): return b.text)))
	await _seconds(Announcer.SLIDE_OUT + 0.1)
	_check("then shows next", announcer.current != null and announcer.current.text == "Big thing", "")

	director.zone_warning.emit(&"glade", "The Glades", 10.0)
	director.dream_mote_warning.emit(Vector2.ZERO, 15.0)
	dreamer_b.start_stir()
	await _frames(2)
	_check("announces zones, the Dream Mote and a stir", announcer.history.has("The Glades are dreaming!")
		and announcer.history.has("Dream Mote incoming: the Cradle!") and announcer.history.has("Dusk Dreamer is stirring!"),
		str(announcer.history))
	dreamer_b.settle(Dreamer.SETTLE_LULLABY)
	dreamer_a.set_wake(rules.wake_meter_max * 0.5)
	await _frames(1)
	_check("announces settles and wake milestones", announcer.history.has("Lullaby! Dusk Dreamer settles")
		and announcer.history.has("Dawn Dreamer is 25% awake") and announcer.history.has("Dawn Dreamer is 50% awake"),
		str(announcer.history))
	dreamer_a.grant_sweet_dreams()
	_check("Sweet Dreams for your team", announcer.history.has("Sweet Dreams!"), "")
	GameFeel.settings.announcer_text = false
	_check("the text can be hidden (sounds keep playing)", not announcer._text_shown(), "")
	GameFeel.settings.announcer_text = true
	# A deposit toast for the local player, with the gold they earned.
	var carrier := MoteCarrier.find_on(hero)
	carrier.add_mote(director.small_data, 1)
	carrier.add_mote(director.small_data, 1)
	hero.global_position = dreamer_a.global_position + Vector2(0, -220)
	await _until(func(): return carrier.get_mote_count() == 0, 3.0)
	hero.global_position = Vector2(3000, 0)
	await _frames(3)
	var toasted := announcer._toasts.any(func(t): return "Banked 2" in t.text and "gold" in t.text)
	_check("your own bank shows a toast with the gold", toasted, str(announcer._toasts))
	announcer.queue_free()
	dreamer_a.set_wake(0.0)
	dreamer_b.set_wake(0.0)
	dreamer_a.sweet = 0.0


func _test_music() -> void:
	print("\n-- Adaptive music")
	var music: MatchMusic = manager.get_node("MatchMusic")
	_check("the match plays its MusicLayerSet (silent until stems are assigned)",
		AudioManager.get_layer_set() == music.layer_set and music.layer_set.layers.size() >= 4, "")
	_check("calm by default", music.wanted_tier() == MatchMusic.Tier.CALM, "")
	dreamer_a.set_wake(rules.wake_meter_max * 0.6)
	_check("a meter at 50%+ asks for TENSE", music.wanted_tier() == MatchMusic.Tier.TENSE, "")
	dreamer_a.set_wake(0.0)
	var dream := director.spawn_mote(Vector2(4000, 4000), true)
	await _frames(1)
	_check("a Dream Mote on the map asks for TENSE", music.wanted_tier() == MatchMusic.Tier.TENSE, "")
	dream.queue_free()
	await _frames(2)
	dreamer_b.start_stir()
	_check("a stir asks for STIRRING", music.wanted_tier() == MatchMusic.Tier.STIRRING, "")
	music.set_process(false)
	music.tier = MatchMusic.Tier.CALM
	_check("rising is immediate", music.step(MatchMusic.Tier.STIRRING) == MatchMusic.Tier.STIRRING
		and AudioManager.get_music_tier() == MatchMusic.Tier.STIRRING, "")
	var targets := AudioManager.get_layer_targets()
	_check("every stem audible while stirring", Array(targets).all(func(v): return v > -80.0), str(targets))
	_check("falling waits for the hold", music.step(MatchMusic.Tier.CALM) == MatchMusic.Tier.STIRRING, "")
	music._since_change = music.layer_set.min_seconds_per_drop
	_check("then drops ONE tier", music.step(MatchMusic.Tier.CALM) == MatchMusic.Tier.TENSE, "")
	targets = AudioManager.get_layer_targets()
	var tense_ok := true
	for i in music.layer_set.layers.size():
		tense_ok = tense_ok and ((targets[i] > -80.0) == (music.layer_set.layers[i].tier <= 1))
	_check("TENSE: tier 0-1 stems on, stirring stems off", tense_ok, str(targets))
	music._since_change = music.layer_set.min_seconds_per_drop
	_check("and one more after another hold", music.step(MatchMusic.Tier.CALM) == MatchMusic.Tier.CALM, "")
	music.set_process(true)
	dreamer_b.settle(Dreamer.SETTLE_TIMEOUT)
	dreamer_b.set_wake(0.0)


func _test_mote_and_zone_fx() -> void:
	print("\n-- Mote and zone looks")
	var mote := director.spawn_mote(Vector2(3500, 3500))
	await _frames(1)
	var early := mote.get_look_squash()
	await _seconds(Mote.POP_TIME + 0.1)
	_check("a new Mote pops in (grows, wobbles, settles)", early.x < 0.9 and mote.get_look_squash() == Vector2.ONE,
		"%s -> %s" % [early, mote.get_look_squash()])
	mote.queue_free()
	var zone := DreamZone.new()
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([Vector2(-200, -200), Vector2(200, -200), Vector2(200, 200), Vector2(-200, 200)])
	zone.add_child(shape)
	zone.position = Vector2(5000, 5000)
	add_child(zone)
	zone.set_zone_state(DreamZone.ZoneState.WARNING, 0.3)
	await _seconds(0.4)
	var warned := zone.get_presence()
	zone.set_zone_state(DreamZone.ZoneState.DREAMING)
	await _seconds(0.6)
	var dreaming := zone.get_presence()
	zone.set_zone_state(DreamZone.ZoneState.OFF)
	await _seconds(1.7)
	_check("a zone fades in during its warning, fully while dreaming, out after",
		warned > 0.4 and warned < 0.7 and is_equal_approx(dreaming, 1.0) and zone.get_presence() == 0.0,
		"%.2f %.2f %.2f" % [warned, dreaming, zone.get_presence()])
	_check("zones tint the minimap while present", zone.is_in_group(&"minimap_areas"), "")
	zone.queue_free()


func _test_dreamer_reactions() -> void:
	print("\n-- Dreamer reactions")
	var look := dreamer_a.get_node("DreamerLook") as DreamerLook
	dreamer_a.deposit_ticked.emit(hero, 1, false, 1)
	_check("a deposit sends a Mote arcing in", look._flights.size() == 1, "")
	await _seconds(DreamerLook.FLIGHT_TIME + 0.05)
	_check("banked: a gulp", look._gulp > 0.0 and look._flights.is_empty(), "")
	dreamer_a.deposit_ticked.emit(hero, 1, true, 1)
	await _seconds(DreamerLook.FLIGHT_TIME + 0.05)
	_check("delivered: a flinch and a colour burst", look._flinch > 0.0 and look._bursts.size() == 1, "")
	dreamer_a.start_stir()
	await _seconds(0.5)
	_check("stirring: eyes open, the ground ripples", look._eye_open > 0.3 and not look._ripples.is_empty(), "")
	dreamer_a.settle(Dreamer.SETTLE_LULLABY)
	_check("settling: an exhale", look._exhale > 0.0, "")
	hero.global_position = dreamer_a.global_position + Vector2(0, -150)
	await _seconds(0.5)
	_check("the body fades while a hero stands behind it", look.self_modulate.a < 0.7, str(look.self_modulate.a))
	hero.global_position = Vector2(3000, 0)
	await _seconds(0.5)
	_check("...and comes back", look.self_modulate.a > 0.95, "")
	dreamer_a.set_wake(0.0)


func _test_minimap_icons() -> void:
	print("\n-- Minimap")
	var minimap: Minimap = load(MINIMAP).instantiate()
	add_child(minimap)
	await _frames(3)
	var dream := director.spawn_mote(Vector2(4000, 4000), true)
	_check("the Dream Mote and Dreamers draw their own icons", dream.has_method(&"draw_minimap_icon")
		and dreamer_a.has_method(&"draw_minimap_icon"), "")
	minimap.add_ping(Vector2.ZERO, &"", &"stir")
	_check("key-moment pings go to everyone and last longer", minimap.get_pings().back().team == &""
		and minimap.get_pings().back().life > minimap.ping_time, "")
	dream.queue_free()
	minimap.queue_free()
	await _frames(1)


func _test_wake_sequence() -> void:
	print("\n-- The wake sequence")
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	get_tree().change_scene_to_file("res://scenes/dream_basin_world.tscn")
	await _frames(5)
	var world_manager := MatchManager.find(get_tree())
	world_manager.rules.stir_grace = 0.0
	world_manager.start_playing()
	var dusk := Dreamer.find_for(get_tree(), &"b")
	var player := get_tree().get_first_node_in_group(&"player") as Hero
	dusk.set_wake(world_manager.rules.wake_meter_max)
	MoteCarrier.find_on(player).add_mote(load("res://resources/match/small_mote.tres"), 1)
	player.global_position = dusk.global_position + Vector2(0, 220)
	await _until(func(): return world_manager.state == MatchManager.State.ENDED, 3.0)
	await _frames(2)
	_check("waking plays a slow-motion beat first", Engine.time_scale < 1.0 and not get_tree().paused,
		str(Engine.time_scale))
	await get_tree().create_timer(4.0, true, false, true).timeout
	_check("then the victory screen, at normal speed", get_tree().paused and Engine.time_scale == 1.0, "")
	get_tree().paused = false


# --- Helpers ---------------------------------------------------------------------

func _dreamer(team: StringName, at: Vector2) -> Dreamer:
	var dreamer: Dreamer = load(DREAMER).instantiate()
	dreamer.team = team
	dreamer.position = at
	add_child(dreamer)
	return dreamer


func _until(condition: Callable, timeout: float) -> void:
	var t := 0.0
	while not condition.call() and t < timeout:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
