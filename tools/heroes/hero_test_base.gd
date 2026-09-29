extends Node2D

# Shared helpers for the batch-2 hero tests (Biker, Horace, Mochi, Computer,
# Catgirl, Rocco) and batch2_infra_test. A test extends this file, sets
# `hero` in _run() with spawn_hero(), and exits with get_tree().quit(failures).

const AUDIO_COVERAGE := preload("res://tools/heroes/audio_coverage.gd")
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"

var failures := 0
var hero: Hero
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []
var cues: Array[StringName] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	pass


func finish() -> void:
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func spawn_hero(path: String, team: StringName = &"a", at: Vector2 = Vector2.ZERO) -> Hero:
	var h: Hero = load(path).instantiate()
	h.team = team
	h.position = at
	add_child(h)
	h.cue_triggered.connect(func(cue: StringName, _c: Dictionary): cues.append(cue))
	return h


# Slots filled, definition valid, identity, listed, L10 stats near the peers
# of its role (within `tolerance` of their average, Health/Weapon/Magic).
func check_assembly(display_name: String, title: String, role: String, tolerance: float = 0.25) -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate"]:
		_check("slot %s filled" % slot, hero.get_ability(slot) != null, "")
	var d := hero.definition
	_check("definition validates", d.validate().is_empty(), "\n".join(d.validate()))
	_check("name, title and role", d.display_name == display_name and d.title == title and d.get_role_name() == role,
		"%s / %s / %s" % [d.display_name, d.title, d.get_role_name()])
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(x): return x.hero_id == d.hero_id), "")
	for stat in [&"health", &"weapon", &"magic"]:
		var peers: Array[float] = []
		for other in HeroScaffold.find_definitions():
			if other.role == d.role and other.hero_id != d.hero_id and not str(other.hero_id).begins_with("ranged_test") \
					and not other.hero_id in [&"biker", &"horace", &"mochi", &"computer", &"catgirl", &"rocco"]:
				peers.append(other.stats.get(stat).value_at(10))
		if peers.is_empty():
			continue
		var mine: float = d.stats.get(stat).value_at(10)
		var lo: float = peers.min() * (1.0 - tolerance)
		var hi: float = peers.max() * (1.0 + tolerance)
		_check("L10 %s (%.0f) in the %s range (%.0f-%.0f)" % [stat, mine, role, peers.min(), peers.max()],
			mine >= lo and mine <= hi, "")


func reset(at: Vector2) -> void:
	hero.ability_controller.interrupt()
	hero.status_component.clear()
	hero.movement_component.stop_forced_move()
	hero.global_position = at
	hero.velocity = Vector2.ZERO
	hero.move_direction = Vector2.ZERO
	hero.health_component.reset()
	for ability in hero.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
		if ability.get_max_charges() > 1:
			ability._charges = ability.get_max_charges()
	aim(at + Vector2(300, 0))


func aim(at: Vector2) -> void:
	hero.aim_point = at
	hero.aim_direction = (at - hero.global_position).normalized()


# Press a slot every tick for `seconds` (a held gun), aiming at `at`.
func hold_slot(slot: StringName, at: Vector2, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		aim(at)
		hero.request_slot(slot, at)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func press(slot: StringName, at: Vector2) -> bool:
	aim(at)
	return hero.request_slot(slot, at)


func dummy(at: Vector2, hp: float = 50000.0, team: StringName = &"b", magic_resist: float = 0.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.magic_resist = magic_resist
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	d.team = team
	d.return_to_anchor = false
	add_child(d)
	spawned.append(d)
	return d


func wall(at: Vector2, size: Vector2 = Vector2(40, 600)) -> Node2D:
	var w: Node2D = load(WALL).instantiate()
	w.position = at
	add_child(w)
	spawned.append(w)
	var shape := w.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		shape.shape = shape.shape.duplicate()
		shape.shape.size = size
	return w


func clear() -> void:
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	spawned.clear()
	for node in get_tree().current_scene.get_children():
		if node is GroundZone or node is Projectile or node is Deployable or node is FrontalBlocker or node is Mote:
			node.queue_free()
	await get_tree().physics_frame


func hits(target: Node, label: StringName) -> Array[DamageInfo]:
	return hits_log.filter(func(i): return i.target == target and i.label == label)


func total(target: Node, label: StringName) -> float:
	var sum := 0.0
	for i in hits(target, label):
		sum += i.final_amount
	return sum


func find_zone(label: StringName) -> GroundZone:
	var found := GroundZone.find_owned(get_tree(), hero, label)
	return found[0] if not found.is_empty() else null


func test_audio(audio) -> void:
	print("\n-- Audio")
	for c in audio.checks():
		_check(c[0], c[1], c[2])


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= maxf(tolerance, absf(b) * 0.001)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func until(condition: Callable, timeout: float) -> bool:
	var waited := 0.0
	while not condition.call() and waited < timeout:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return condition.call()
