extends Node2D

# Headless checks for the Phase 0 shared systems:
#   S1 Resolve (GameRules.resolve_*): hard CC after hard CC is shortened
#   S2 line of sight (CombatQueries.has_line_of_sight): walls, low cover,
#      bushes (one-way), reveals; the F1 sight-lines overlay
#   S3 bush concealment: what the local player's screen hides (LocalView)
#   S3c ShapeBatch: shapes recorded into one triangle list
#   S3b invisibility (StatusEffect.invisible): sight, drawing, reveals; the
#       test hero's Cloak (Ranged Test (auto), item key)
#   S4 viewer-filtered status VFX (StatusEffect.vfx_visible_to)
#   S5 grass patches (Bush.polygon): hide, reveal radius, reveal on firing
#   S6 the four obstacle types (hard wall, pit, crystal, grass): walking,
#      dashes, jump arcs, sight, shots and a real piercing projectile
#   S7 wall slams (MovementComponent.wall_impact): pushes and knockback into
#      hard walls and crystal count; pits, low cover and your own dash don't
#   S8 the global TTK knob (GameRules.ttk_damage_multiplier)
#
#   godot --headless res://tools/heroes/shared_systems_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"
const VFX := "res://effects/shocked_sparks.tscn"
const HARD_WALL := "res://scenes/map/hard_wall.tscn"
const PIT := "res://scenes/map/pit.tscn"
const CRYSTAL := "res://scenes/map/crystal_wall.tscn"
const GRASS := "res://scenes/map/grass_patch.tscn"
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
	await _test_invisibility()
	_test_shape_batch()
	await _test_vfx_filter()
	await _test_grass()
	await _test_obstacle_types()
	await _test_wall_slams()
	await _test_ttk_multiplier()

	LocalView.clear_viewer()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- S8 TTK multiplier -----------------------------------------------------------

func _test_ttk_multiplier() -> void:
	print("\n-- S8 TTK multiplier")
	var rules := GameRules.current()
	var authored := rules.ttk_damage_multiplier
	_check("the rules start at 1.15", is_equal_approx(authored, 1.15), "x%.2f" % authored)
	var dummy := _dummy(Vector2(300, 0))
	await _physics_frames(2)
	var dealt := dummy.health_component.apply_damage(DamageInfo.create(100.0, hero, DamageInfo.Type.TRUE))
	_check("every hit is multiplied by it", is_equal_approx(dealt, 100.0 * authored), "%.1f" % dealt)
	rules.ttk_damage_multiplier = 1.0
	dealt = dummy.health_component.apply_damage(DamageInfo.create(100.0, hero, DamageInfo.Type.TRUE))
	_check("1.0 turns it off", is_equal_approx(dealt, 100.0), "%.1f" % dealt)
	rules.ttk_damage_multiplier = authored


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


# --- S3c ShapeBatch -----------------------------------------------------------------

func _test_shape_batch() -> void:
	print("\n-- S3c ShapeBatch")
	var batch := ShapeBatch.new()
	_check("starts empty", batch.is_empty(), "")
	batch.draw_rect(Rect2(0, 0, 10, 10), Color.RED)
	_check("a rect is two triangles", batch.get_triangle_count() == 2, str(batch.get_triangle_count()))
	batch.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]), Color.BLUE)
	_check("a four-point polygon is two more", batch.get_triangle_count() == 4, str(batch.get_triangle_count()))
	batch.draw_circle(Vector2.ZERO, 10.0, Color.WHITE)
	_check("a circle is a fan of at least 12", batch.get_triangle_count() >= 16, str(batch.get_triangle_count()))
	var before := batch.get_triangle_count()
	AeroDraw.gloss_circle(batch, Vector2.ZERO, 30.0, Color.GREEN)
	AeroDraw.gloss_rect_shapes(batch, Rect2(0, 0, 80, 40), Color.GREEN, 8.0)
	_check("AeroDraw draws into a batch", batch.get_triangle_count() > before, "")
	var moved := ShapeBatch.new()
	moved.draw_set_transform(Vector2(100, 0), 0.0, Vector2(2, 2))
	moved.draw_rect(Rect2(0, 0, 10, 10), Color.RED)
	_check("draw_set_transform applies", moved._vertices[2].is_equal_approx(Vector2(120, 20)), str(moved._vertices[2]))
	batch.clear()
	_check("clear empties it", batch.is_empty(), "")


# --- S3b Invisibility ---------------------------------------------------------------

func _test_invisibility() -> void:
	print("\n-- S3b Invisibility")
	hero.global_position = Vector2.ZERO
	LocalView.set_viewer(hero)
	var enemy := _dummy(Vector2(500, 0))
	enemy.team = &"b"
	var ally := _dummy(Vector2(-500, 0))
	ally.team = &"a"
	var cloak := _status(&"test_cloak", 2.0)
	cloak.invisible = true
	enemy.status_component.apply(cloak, enemy)
	await _physics_frames(2)
	await _frames(2)
	_check("an invisible enemy in the open is unseen", not CombatQueries.has_line_of_sight(hero, enemy)
		and CombatQueries.is_invisible(enemy), "")
	_check("...and not drawn for the viewer", not enemy.visible, "")
	_check("it still sees out", CombatQueries.has_line_of_sight(enemy, hero), "")
	_check("its own team still sees it", CombatQueries.has_line_of_sight(hero, ally) and not CombatQueries.is_hidden_from(enemy,
		enemy), "")
	var reveal := _status(&"test_reveal", 1.0)
	reveal.reveals = true
	enemy.status_component.apply(reveal, hero)
	await _frames(2)
	_check("reveals beats invisible", CombatQueries.has_line_of_sight(hero, enemy) and enemy.visible, "")
	enemy.status_component.remove(&"test_reveal")
	enemy.status_component.remove(&"test_cloak")
	await _frames(2)
	_check("visible again when it ends", CombatQueries.has_line_of_sight(hero, enemy) and enemy.visible, "")

	# The test hero's Cloak (Ranged Test (auto), item key): a SelfStatusData
	# whose status is invisible.
	var cloaked: Hero = load("res://scenes/heroes/hero_base.tscn").instantiate()
	cloaked.definition = load("res://tools/heroes/ranged_test/ranged_test_auto_definition.tres")
	cloaked.team = &"b"
	add_child(cloaked)
	cloaked.global_position = Vector2(0, 600)
	spawned.append(cloaked)
	await _physics_frames(2)
	cloaked.request_slot(&"item", Vector2(300, 600))
	await _until(func(): return CombatQueries.is_invisible(cloaked), 1.0)
	await _frames(2)
	_check("the test hero's Cloak makes it invisible", CombatQueries.is_invisible(cloaked)
		and not CombatQueries.has_line_of_sight(hero, cloaked) and not cloaked.visible, "")
	LocalView.clear_viewer()
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


# --- S5 Grass patches -------------------------------------------------------------

func _test_grass() -> void:
	print("\n-- S5 Grass patches")
	var rules := GameRules.current()
	hero.global_position = Vector2.ZERO
	var enemy := _dummy(Vector2(700, 0))
	enemy.team = &"b"
	var grass: Bush = _obstacle(GRASS, Vector2(700, 0), _box(160, 140)) as Bush
	await _physics_frames(3)
	_check("a grass patch is a Bush with a polygon", grass.is_patch() and grass.has_occupant(enemy), "")
	_check("grass hides who's inside (sight)", not CombatQueries.has_line_of_sight(hero, enemy), "")
	_check("grass hides who's inside (drawing)", CombatQueries.is_hidden_from(enemy, hero), "")
	_check("from inside grass you see out", CombatQueries.has_line_of_sight(enemy, hero), "")
	hero.global_position = Vector2(700 - rules.grass_reveal_radius + 30, 0)
	await _physics_frames(2)
	_check("within the reveal radius you see into grass", CombatQueries.has_line_of_sight(hero, enemy)
		and not CombatQueries.is_hidden_from(enemy, hero), "%.0f px" % rules.grass_reveal_radius)
	hero.global_position = Vector2(700 - rules.grass_reveal_radius - 60, 0)
	await _physics_frames(2)
	_check("just outside it you don't", not CombatQueries.has_line_of_sight(hero, enemy), "")
	var ally := _hero(Vector2(700, rules.grass_reveal_radius - 40), &"a")
	spawned.append(ally)
	await _physics_frames(2)
	_check("a teammate within the radius shares it", not CombatQueries.is_hidden_from(enemy, hero), "")
	ally.global_position = Vector2(-600, 0)
	await _physics_frames(2)

	Bush.note_fired(enemy)
	_check("firing reveals you in grass", CombatQueries.has_line_of_sight(hero, enemy)
		and not CombatQueries.is_hidden_from(enemy, hero), "")
	await _seconds(rules.grass_fire_reveal_time + 0.15)
	_check("the reveal wears off", not CombatQueries.has_line_of_sight(hero, enemy), "%.1f s" % rules.grass_fire_reveal_time)

	# A real ability use counts as firing: the hero in grass, seen from outside.
	enemy.global_position = Vector2(-700, 0)
	hero.global_position = Vector2(700, 0)
	await _seconds(0.6)
	await _physics_frames(3)
	_check("the hero is hidden in grass before shooting", not CombatQueries.has_line_of_sight(enemy, hero), "")
	hero.aim_direction = Vector2.LEFT
	hero.request_slot(&"primary", Vector2(-700, 0))
	_check("using an ability reveals you", CombatQueries.has_line_of_sight(enemy, hero), "")
	hero.global_position = Vector2.ZERO
	_clear()
	await _seconds(0.6)


# --- S6 Obstacle types ---------------------------------------------------------------

func _test_obstacle_types() -> void:
	print("\n-- S6 Obstacle types")
	# [name, scene, layer, sight passes, shots pass, jump arc passes]
	var cases := [
		["hard wall", HARD_WALL, MapLayers.WORLD, false, false, false],
		["pit", PIT, MapLayers.PITS, true, true, true],
		["crystal", CRYSTAL, MapLayers.CRYSTAL, true, false, false],
	]
	for c: Array in cases:
		hero.global_position = Vector2.ZERO
		var target := _dummy(Vector2(700, 0))
		var body := _obstacle(c[1], Vector2(350, 0), _box(60, 260)) as CoverBody
		await _physics_frames(3)
		_check("%s is on its own layer" % c[0], body.collision_layer == c[2], "layer %d" % body.collision_layer)
		_check("%s: sight %s" % [c[0], "passes" if c[3] else "blocked"],
			CombatQueries.has_line_of_sight(hero, target) == c[3], "")
		_check("%s: shots %s" % [c[0], "pass" if c[4] else "blocked"], CombatQueries.shot_clear(hero, target) == c[4], "")

		# A real piercing shot (pierce 3): walls stop it whatever its pierce.
		var shot := ProjectileData.new()
		shot.speed = 3000.0
		shot.lifetime = 0.5
		shot.pierce = 3
		shot.radius = 12.0
		var before := target.health_component.current_health
		Projectile.fire(hero, shot, Vector2(60, 0), Vector2.RIGHT, DamageInfo.create(10.0, hero))
		await _seconds(0.45)
		var hit := target.health_component.current_health < before
		_check("%s: a piercing projectile %s" % [c[0], "crosses it" if c[4] else "stops at it"], hit == c[4], "")

		# Walking (a dash) stops at all three.
		target.global_position = Vector2(700, 0)
		target.return_to_anchor = false
		await _physics_frames(2)
		target.movement_component.displace(Vector2.LEFT, 600.0, 0.4)
		await _seconds(0.6)
		_check("%s: a dash stops at it" % c[0], target.global_position.x > 380.0 + 30.0,
			"x=%.0f" % target.global_position.x)

		# A jump arc flies over pits (MapLayers.JUMPABLE), not walls or crystal.
		hero.global_position = Vector2(0, 60)
		await _physics_frames(2)
		hero.launch(Vector2(600, 60), 0.5, 100.0)
		await _seconds(0.8)
		_check("%s: a jump arc %s" % [c[0], "flies over it" if c[5] else "is stopped"],
			(hero.global_position.x > 500.0) == c[5], "x=%.0f" % hero.global_position.x)
		_clear()
		await _physics_frames(3)

	hero.global_position = Vector2.ZERO
	var walker := _dummy(Vector2(700, 0))
	walker.return_to_anchor = false
	var grass := _obstacle(GRASS, Vector2(350, 0), _box(100, 200))
	await _physics_frames(3)
	var target_hp := walker.health_component.current_health
	walker.movement_component.displace(Vector2.LEFT, 600.0, 0.4)
	await _seconds(0.6)
	_check("grass: you walk (dash) through it", walker.global_position.x < 200.0, "x=%.0f" % walker.global_position.x)
	walker.global_position = Vector2(700, 0)
	await _physics_frames(2)
	_check("grass: shots and sight pass (from outside to outside)", CombatQueries.shot_clear(hero, walker)
		and CombatQueries.has_line_of_sight(hero, walker), "")
	Projectile.fire(hero, _plain_shot(), Vector2(60, 0), Vector2.RIGHT, DamageInfo.create(10.0, hero))
	await _seconds(0.45)
	_check("grass: a projectile flies through it", walker.health_component.current_health < target_hp, "")
	grass.queue_free()
	_clear()
	await _physics_frames(3)


# --- S7 Wall slams -------------------------------------------------------------------

func _test_wall_slams() -> void:
	print("\n-- S7 Wall slams")
	var rules := GameRules.current()
	_check("rules hold the numbers", rules.wall_impact_mask & MapLayers.WORLD != 0
		and rules.wall_impact_mask & MapLayers.CRYSTAL != 0 and rules.wall_impact_mask & MapLayers.PITS == 0
		and rules.wall_impact_min_speed > 0.0, "mask %d, min %.0f px/s" % [rules.wall_impact_mask, rules.wall_impact_min_speed])
	var push := _status(&"test_push", 0.3)
	push.displace_distance = 350.0
	push.displace_duration = 0.25
	push.displace_direction = StatusEffect.DisplaceDirection.AWAY_FROM_SOURCE
	# [name, scene, height override (-1 = scene's), slams]
	var cases := [
		["hard wall", HARD_WALL, -1, true],
		["crystal", CRYSTAL, -1, true],
		["pit", PIT, -1, false],
		["low cover", HARD_WALL, CoverBody.Height.LOW, false],
	]
	for c: Array in cases:
		hero.global_position = Vector2.ZERO
		var victim := _dummy(Vector2(400, 0))
		victim.return_to_anchor = false
		var body := _obstacle(c[1], Vector2(620, 0), _box(40, 300)) as CoverBody
		if c[2] >= 0:
			body.height = c[2]
		var impacts := []
		var cues := []
		victim.movement_component.wall_impact.connect(func(n, speed, source, wall): impacts.append([n, speed, source, wall]))
		victim.cue_triggered.connect(func(cue, context): if cue == &"wall_impact": cues.append(context))
		await _physics_frames(3)
		victim.status_component.apply(push, hero)
		await _seconds(0.5)
		var ok: bool = impacts.size() == 1 if c[3] else impacts.is_empty()
		_check("pushed into %s: %s" % [c[0], "a wall slam" if c[3] else "no slam"], ok, "%d impacts" % impacts.size())
		if c[3] and impacts.size() == 1:
			var impact: Array = impacts[0]
			_check("  %s slam reports who, which way, how hard" % c[0], impact[2] == hero and impact[3] == body
				and impact[0].dot(Vector2.LEFT) > 0.9 and impact[1] >= rules.wall_impact_min_speed,
				"%.0f px/s" % impact[1])
			_check("  %s slam fires the wall_impact cue" % c[0], cues.size() == 1 and cues[0].get("knocked_by") == hero, "")
		victim.status_component.clear()
		_clear()
		await _physics_frames(3)

	# A hit's knockback impulse (not a timed push) into a wall.
	var victim2 := _dummy(Vector2(450, 0))
	victim2.return_to_anchor = false
	_obstacle(HARD_WALL, Vector2(620, 0), _box(40, 300))
	var impacts2 := []
	victim2.movement_component.wall_impact.connect(func(n, speed, source, wall): impacts2.append(source))
	await _physics_frames(3)
	var info := DamageInfo.create(1.0, hero)
	info.knockback = Vector2(1400, 0)
	(victim2.get_node(^"Hurtbox") as HurtboxComponent).take_hit(info)
	await _seconds(0.4)
	_check("a knockback impulse into a wall is a slam", impacts2.size() == 1 and impacts2[0] == hero, "%d" % impacts2.size())

	# Your own dash into a wall is not.
	victim2.global_position = Vector2(450, 0)
	await _physics_frames(2)
	impacts2.clear()
	victim2.movement_component.displace(Vector2.RIGHT, 300.0, 0.2)
	await _seconds(0.4)
	_check("your own dash into a wall is no slam", impacts2.is_empty(), "")

	# A soft nudge (under the minimum speed) is no slam either.
	victim2.global_position = Vector2(560, 0)
	await _physics_frames(2)
	var nudge := _status(&"test_nudge", 0.5)
	nudge.displace_distance = 40.0
	nudge.displace_duration = 0.4
	nudge.displace_direction = StatusEffect.DisplaceDirection.AWAY_FROM_SOURCE
	victim2.status_component.apply(nudge, hero)
	await _seconds(0.6)
	_check("a slow nudge into a wall is no slam", impacts2.is_empty(), "")
	_clear()
	await _physics_frames(3)


func _obstacle(path: String, at: Vector2, polygon: PackedVector2Array) -> Node2D:
	var node: Node2D = load(path).instantiate()
	node.position = at
	if node is Bush:
		(node as Bush).polygon = polygon
	else:
		(node.get_node(^"Shape") as CollisionPolygon2D).polygon = polygon
	add_child(node)
	spawned.append(node)
	return node


func _box(half_w: float, half_h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
		Vector2(half_w, half_h), Vector2(-half_w, half_h)])


func _plain_shot() -> ProjectileData:
	var shot := ProjectileData.new()
	shot.speed = 3000.0
	shot.lifetime = 0.5
	shot.radius = 12.0
	return shot


func _seconds(t: float) -> void:
	var waited := 0.0
	while waited < t:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()


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
