extends Node2D

# Headless checks for the Phase 0 shared systems:
#   S1 Resolve (GameRules.resolve_*): hard CC after hard CC is shortened
#   S2 line of sight (CombatQueries.has_line_of_sight): walls, low cover,
#      bushes (one-way), reveals; the F1 sight-lines overlay
#   S3 bush concealment: what the local player's screen hides (LocalView)
#   S4 viewer-filtered status VFX (StatusEffect.vfx_visible_to)
#
#   godot --headless res://tools/heroes/shared_systems_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"
const VFX := "res://effects/shocked_sparks.tscn"
const EPS := 0.02

var failures := 0
var hero: Hero
var spawned: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	hero = _hero(Vector2.ZERO, &"a")
	await _physics_frames(3)

	await _test_resolve()
	await _test_line_of_sight()
	await _test_concealment()
	await _test_vfx_filter()

	LocalView.clear_viewer()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- S1 Resolve ---------------------------------------------------------------

func _test_resolve() -> void:
	print("\n-- S1 Resolve")
	var rules := GameRules.current()
	_check("rules hold the numbers", rules.resolve_status != null and rules.resolve_duration == 2.0
		and rules.resolve_cc_multiplier == 0.5,
		"status %s, %.2f s, x%.2f" % [rules.resolve_status, rules.resolve_duration, rules.resolve_cc_multiplier])

	var dummy := _dummy(Vector2(300, 0))
	var status := dummy.status_component
	await _physics_frames(2)

	var stun := _status(&"test_stun", 0.4)
	stun.stuns = true
	status.apply(stun, hero)
	_check("first stun is full length", absf(status.get_time_left(&"test_stun") - 0.4) < EPS,
		"%.3f s" % status.get_time_left(&"test_stun"))
	_check("not Resolved while stunned", not status.is_resolved(), "")
	await _until(func(): return not status.has_status(&"test_stun"), 1.0)
	_check("stun ending grants Resolve", status.is_resolved()
		and absf(status.get_time_left(rules.resolve_status.id) - 2.0) < 0.05,
		"%.3f s left" % status.get_time_left(rules.resolve_status.id))

	status.apply(stun, hero)
	_check("second stun in a row is half as long", absf(status.get_time_left(&"test_stun") - 0.2) < EPS,
		"%.3f s" % status.get_time_left(&"test_stun"))
	status.remove(&"test_stun")

	var root := _status(&"test_root", 0.6)
	root.roots = true
	status.apply(root, hero)
	_check("a root is shortened too", absf(status.get_time_left(&"test_root") - 0.3) < EPS,
		"%.3f s" % status.get_time_left(&"test_root"))
	status.remove(&"test_root")

	var taunt := _status(&"test_taunt", 0.6)
	taunt.compel_enabled = true
	status.apply(taunt, hero)
	_check("a taunt (compel over input) is shortened", absf(status.get_time_left(&"test_taunt") - 0.3) < EPS,
		"%.3f s" % status.get_time_left(&"test_taunt"))
	status.remove(&"test_taunt")

	var soft_pull := _status(&"test_soft_pull", 0.6)
	soft_pull.compel_enabled = true
	soft_pull.compel_overrides_input = false
	status.apply(soft_pull, hero)
	_check("a pull you can walk out of is not shortened",
		absf(status.get_time_left(&"test_soft_pull") - 0.6) < EPS, "%.3f s" % status.get_time_left(&"test_soft_pull"))
	status.remove(&"test_soft_pull")

	var carry := _status(&"test_carry", 5.0)
	carry.stuns = true
	carry.carry_enabled = true
	status.apply(carry, hero)
	_check("a carry is not shortened", absf(status.get_time_left(&"test_carry") - 5.0) < EPS,
		"%.3f s" % status.get_time_left(&"test_carry"))

	var self_stun := _status(&"test_self_stun", 5.0)
	self_stun.stuns = true
	status.apply(self_stun, dummy)
	_check("self-applied CC is not shortened", absf(status.get_time_left(&"test_self_stun") - 5.0) < EPS,
		"%.3f s" % status.get_time_left(&"test_self_stun"))

	var exempt := _status(&"test_exempt", 5.0)
	exempt.stuns = true
	exempt.ignores_resolve = true
	status.apply(exempt, hero)
	_check("ignores_resolve is not shortened", absf(status.get_time_left(&"test_exempt") - 5.0) < EPS,
		"%.3f s" % status.get_time_left(&"test_exempt"))

	# Let Resolve run out, then check the exempt ones grant none.
	await _until(func(): return not status.is_resolved(), 2.5)
	_check("Resolve ends after its duration", not status.is_resolved(), "")
	status.remove(&"test_carry")
	status.remove(&"test_self_stun")
	status.remove(&"test_exempt")
	_check("carries, self CC and exempt CC grant no Resolve", not status.is_resolved(), "")

	status.apply(stun, hero)
	_check("after Resolve ends, stuns are full length again",
		absf(status.get_time_left(&"test_stun") - 0.4) < EPS, "%.3f s" % status.get_time_left(&"test_stun"))
	status.clear()
	_check("clear() (reset/death) grants no Resolve", not status.is_resolved(), "")
	_clear()
	await _physics_frames(2)


# --- S2 Line of sight -----------------------------------------------------------

func _test_line_of_sight() -> void:
	print("\n-- S2 Line of sight")
	hero.global_position = Vector2.ZERO
	var dummy := _dummy(Vector2(600, 0))
	await _physics_frames(3)
	_check("clear in the open", CombatQueries.has_line_of_sight(hero, dummy), "")

	var wall: Node2D = load(WALL).instantiate()
	wall.position = Vector2(300, 0)
	add_child(wall)
	spawned.append(wall)
	await _physics_frames(2)
	_check("blocked by a wall", not CombatQueries.has_line_of_sight(hero, dummy), "")
	_check("blocked by a wall, both ways", not CombatQueries.has_line_of_sight(dummy, hero), "")
	wall.queue_free()
	await _physics_frames(2)

	var low := StaticBody2D.new()
	low.collision_layer = MapLayers.LOW_COVER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 400)
	shape.shape = rect
	low.add_child(shape)
	low.position = Vector2(300, 0)
	add_child(low)
	spawned.append(low)
	await _physics_frames(2)
	_check("low cover doesn't block sight", CombatQueries.has_line_of_sight(hero, dummy), "")
	low.queue_free()

	var bush := _bush(Vector2(600, 0))
	await _physics_frames(3)
	_check("the bush knows who's inside", bush.has_occupant(dummy) and not bush.has_occupant(hero), "")
	_check("can't see into a bush from outside", not CombatQueries.has_line_of_sight(hero, dummy), "")
	_check("from inside a bush you see out", CombatQueries.has_line_of_sight(dummy, hero), "")

	var reveal := _status(&"test_reveal", 1.0)
	reveal.reveals = true
	dummy.status_component.apply(reveal, hero)
	_check("a revealed actor is seen inside a bush", CombatQueries.has_line_of_sight(hero, dummy), "")
	dummy.status_component.remove(&"test_reveal")
	_check("reveal ending hides it again", not CombatQueries.has_line_of_sight(hero, dummy), "")

	hero.global_position = Vector2(560, 0)
	await _physics_frames(3)
	_check("two actors in the same bush see each other", CombatQueries.has_line_of_sight(hero, dummy), "")

	DebugTools.set_sight_lines_enabled(true)
	await _frames(2)
	var overlay := get_tree().current_scene.get_node_or_null(^"SightLinesOverlay")
	_check("F1 > Tools > Sight lines adds the overlay to the map", overlay is SightLinesOverlay, "")
	DebugTools.set_sight_lines_enabled(false)
	await _frames(2)
	_check("turning it off removes the overlay", not is_instance_valid(overlay), "")
	hero.global_position = Vector2.ZERO
	_clear()
	await _physics_frames(3)


# --- S3 Concealment ---------------------------------------------------------------

func _test_concealment() -> void:
	print("\n-- S3 Bush concealment")
	hero.global_position = Vector2.ZERO
	LocalView.set_viewer(hero)
	var dummy := _dummy(Vector2(600, 0))
	dummy.team = &"b"
	var open_dummy := _dummy(Vector2(0, 400))
	open_dummy.team = &"b"
	_bush(Vector2(600, 0))
	# The bush learns who's inside on physics steps; drawing updates on frames.
	await _physics_frames(3)
	await _frames(2)
	var visuals := VisualsComponent.find_on(dummy)
	_check("an enemy in a bush isn't drawn for the viewer", not dummy.visible and visuals.is_concealed(), "")
	_check("an enemy in the open is drawn", open_dummy.visible, "")

	var ally := _hero(Vector2(560, 20), &"a")
	spawned.append(ally)
	await _physics_frames(3)
	await _frames(2)
	_check("a teammate in the bush shares vision", dummy.visible and not visuals.is_concealed(), "")
	ally.global_position = Vector2(-600, 0)
	await _physics_frames(3)
	await _frames(2)
	_check("hidden again once the teammate leaves", not dummy.visible, "")

	var reveal := _status(&"test_reveal", 1.0)
	reveal.reveals = true
	dummy.status_component.apply(reveal, hero)
	await _frames(2)
	_check("a revealed enemy is drawn", dummy.visible, "")
	dummy.status_component.remove(&"test_reveal")

	dummy.team = &"a"
	await _frames(2)
	_check("the viewer's own teammates are always drawn", dummy.visible, "")
	dummy.team = &"b"

	LocalView.set_viewer(null)
	await _frames(2)
	_check("with no viewer everything is drawn", dummy.visible, "")
	LocalView.clear_viewer()
	_clear()
	await _physics_frames(3)


# --- S4 Viewer-filtered VFX ---------------------------------------------------------

func _test_vfx_filter() -> void:
	print("\n-- S4 Viewer-filtered VFX")
	hero.global_position = Vector2.ZERO
	var target := _dummy(Vector2(300, 0))
	target.team = &"b"
	var third := _hero(Vector2(0, 300), &"c")
	var target_ally := _hero(Vector2(0, -300), &"b")
	spawned.append(third)
	spawned.append(target_ally)
	await _physics_frames(3)

	var mark := _status(&"test_mark", 5.0)
	mark.attached_vfx = load(VFX)
	mark.vfx_visible_to = StatusEffect.VfxVisibleTo.TARGET_AND_APPLIER
	target.status_component.apply(mark, hero)
	var visuals := VisualsComponent.find_on(target)
	var node := visuals.get_status_vfx(&"test_mark") as CanvasItem
	_check("the status spawned its VFX", node != null, "")
	if node == null:
		return
	var seen_by := func(viewer: Node2D) -> bool:
		LocalView.set_viewer(viewer)
		await _frames(2)
		return node.visible
	_check("target-and-applier: hidden for a third actor", not await seen_by.call(third), "")
	_check("target-and-applier: shown to the applier", await seen_by.call(hero), "")
	_check("target-and-applier: shown to the target", await seen_by.call(target), "")

	mark.vfx_visible_to = StatusEffect.VfxVisibleTo.TARGET_ALLIES
	_check("target allies: shown to the target's teammate", await seen_by.call(target_ally), "")
	_check("target allies: hidden from an enemy", not await seen_by.call(hero), "")

	mark.vfx_visible_to = StatusEffect.VfxVisibleTo.TARGET_ENEMIES
	_check("target enemies: shown to an enemy", await seen_by.call(third), "")
	_check("target enemies: hidden from the target", not await seen_by.call(target), "")

	mark.vfx_visible_to = StatusEffect.VfxVisibleTo.LISTED
	target.status_component.set_vfx_viewers(&"test_mark", [third])
	_check("listed: shown to a listed actor", await seen_by.call(third), "")
	_check("listed: hidden from everyone else", not await seen_by.call(hero), "")

	mark.vfx_visible_to = StatusEffect.VfxVisibleTo.EVERYONE
	_check("everyone: shown to anyone", await seen_by.call(third), "")

	LocalView.clear_viewer()
	_clear()
	await _physics_frames(2)


# --- Helpers ----------------------------------------------------------------------

func _hero(at: Vector2, team: StringName) -> Hero:
	var h: Hero = load(HERO).instantiate()
	h.team = team
	add_child(h)
	h.global_position = at
	return h


func _dummy(at: Vector2, hp: float = 5000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	add_child(d)
	spawned.append(d)
	return d


func _bush(at: Vector2) -> Bush:
	var bush := Bush.new()
	bush.radius = 120.0
	bush.position = at
	add_child(bush)
	spawned.append(bush)
	return bush


func _status(id: StringName, duration: float) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	return effect


func _clear() -> void:
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	spawned.clear()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# Waits (physics ticks) until `condition` is true or `timeout` seconds pass.
func _until(condition: Callable, timeout: float) -> void:
	var waited := 0.0
	while not condition.call() and waited < timeout:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
