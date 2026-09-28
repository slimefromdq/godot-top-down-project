extends Node2D

# Headless checks for the map's pieces and ambience (Map Liveliness Plan):
# MapMoodProfile sampling, MapMood following the match clock, one
# RegionAmbience per Dream Basin region with a profile and sound bed for
# every region kind, critters scattering from a hero and settling back, the
# sound-bed crossfade, and the Dreamer glow brightening with the wake meter.
#
#   godot --headless res://tools/map/map_pieces_infra_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const DREAM_BASIN := "res://scenes/maps/dream_basin.tscn"
const AMBIENCE := "res://resources/map/dream_basin_ambience.tres"
const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const GLASS := "res://scenes/map/breakable_cover.tscn"
const GEYSER := "res://scenes/map/mote_geyser.tscn"
## Far from Dream Basin's cover, for pieces made by the test.
const TEST_SPOT := Vector2(30000, 30000)

var failures := 0
var hero: Actor


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	print("Map pieces infra test")
	_mood_profile()
	var set := load(AMBIENCE) as AmbienceSet
	check(set != null, "Dream Basin ambience set loads")

	var map: Node2D = load(DREAM_BASIN).instantiate()
	add_child(map)
	await _frames(3)
	var amb := get_tree().get_first_node_in_group(MapAmbience.GROUP) as MapAmbience
	check(amb != null, "Dream Basin has a MapAmbience")
	if amb == null:
		_finish()
		return
	await _regions(amb, map)
	await _critters(amb)
	_beds(amb)
	await _glow(amb)
	await _mood_clock(amb)
	await _shots(amb)
	await _fountains(amb)
	await _bush()
	_placements(map)
	await _glass()
	await _geyser()
	await _clock_jump(amb)
	await _toggles(amb)
	_finish()


func _mood_profile() -> void:
	var p := MapMoodProfile.new()
	p.times = PackedFloat32Array([0.0, 100.0, 200.0])
	p.colors = PackedColorArray([Color.WHITE, Color.BLACK, Color.RED])
	check(p.sample(-5.0) == Color.WHITE, "mood holds its first colour before the first key")
	check(p.sample(50.0).is_equal_approx(Color(0.5, 0.5, 0.5)), "mood interpolates between keys")
	check(p.sample(150.0).is_equal_approx(Color(0.5, 0, 0)), "mood interpolates the next span")
	check(p.sample(999.0) == Color.RED, "mood holds its last colour after the last key")
	check(MapMoodProfile.new().sample(10.0) == Color.WHITE, "an empty-ish mood is white")


func _regions(amb: MapAmbience, map: Node) -> void:
	var zones := 0
	var kinds := {}
	for zone in get_tree().get_nodes_in_group(DreamZone.GROUP):
		if map.is_ancestor_of(zone):
			zones += 1
			kinds[zone.pair_id] = true
	check(zones > 0, "Dream Basin has regions (DreamZones)")
	check(amb.get_regions().size() == zones, "one RegionAmbience per region (%d/%d)" % [amb.get_regions().size(), zones])
	for kind in kinds:
		var profile: AmbienceProfile = amb.ambience.regions.get(kind)
		check(profile != null, "region kind %s has an ambience profile" % kind)
		check(profile != null and profile.loop != null, "region kind %s has a sound bed" % kind)
		check(amb.has_node("Bed_%s" % kind), "a sound bed player exists for %s" % kind)
	for region in amb.get_regions():
		check(region.get_drifter_count() > 0, "%s has drifters" % region.name)
	# A region's own centre-ish point maps back to its kind.
	var r: RegionAmbience = amb.get_regions()[0]
	var inside := _point_inside(r)
	check(amb.region_at(r.to_global(inside)) == r.pair_id, "region_at finds the region a point is in")
	check(amb.region_at(Vector2(99999, 99999)) == &"", "region_at is empty off the map")


func _point_inside(r: RegionAmbience) -> Vector2:
	var sum := Vector2.ZERO
	for p in r.polygon:
		sum += p
	var c := sum / r.polygon.size()
	if r.contains(c):
		return c
	for p in r.polygon:
		var q := p.lerp(c, 0.1)
		if r.contains(q):
			return q
	return c


func _critters(amb: MapAmbience) -> void:
	var region: RegionAmbience
	for r in amb.get_regions():
		if not r.get_critters().is_empty():
			region = r
			break
	check(region != null, "some region has critters")
	if region == null:
		return
	await _frames(2)
	check(not region.is_critter_scared(0), "critters rest with no hero nearby")
	var fake := Node2D.new()
	fake.add_to_group(RegionAmbience.HEROES)
	add_child(fake)
	fake.global_position = region.to_global(region.get_critters()[0].home)
	await _frames(2)
	check(region.is_critter_scared(0), "a hero close by scatters a critter")
	var start: Vector2 = region.get_critters()[0].pos
	await _frames(3)
	check(region.get_critters()[0].pos != start, "a scattered critter flies off")
	fake.queue_free()
	# Settle: run its timer out.
	region.get_critters()[0].scared = 0.001
	await _frames(2)
	check(not region.is_critter_scared(0), "a critter settles back after settle_time")
	check(region.get_critters()[0].pos == region.get_critters()[0].home, "and lands back home")


func _beds(amb: MapAmbience) -> void:
	var kind: StringName = amb.get_regions()[0].pair_id
	amb.update_bed(kind, true, 0.5)
	amb.update_bed(kind, true, 0.5)
	check(is_equal_approx(amb.get_bed_weight(kind), 1.0), "a bed fades fully in while the listener is in its region")
	var bed: AudioStreamPlayer = amb.get_node("Bed_%s" % kind)
	check(bed.playing, "a faded-in bed plays")
	amb.update_bed(kind, false, 0.25)
	check(is_equal_approx(amb.get_bed_weight(kind), 0.75), "a bed fades out gradually")
	for i in 4:
		amb.update_bed(kind, false, 0.25)
	check(amb.get_bed_weight(kind) == 0.0 and not bed.playing, "a silent bed stops")


func _glow(amb: MapAmbience) -> void:
	check(amb.get_glows().size() == 2, "a glow per Dreamer (%d)" % amb.get_glows().size())
	if amb.get_glows().is_empty():
		return
	var glow: DreamerGlow = amb.get_glows()[0]
	var dreamer := glow.dreamer
	dreamer.wake = 0.0
	var asleep := glow.get_strength()
	check(is_equal_approx(asleep, amb.ambience.glow_alpha_asleep), "a sleeping Dreamer glows faintly")
	dreamer.wake = dreamer.get_rules().wake_meter_max * 0.5
	check(glow.get_strength() > asleep, "the glow brightens as the wake meter fills")
	dreamer.wake = 0.0
	await _frames(1)
	check(glow.global_position == dreamer.global_position, "the glow sits on its Dreamer")


func _mood_clock(amb: MapAmbience) -> void:
	check(amb.mood != null, "Dream Basin has a match mood")
	if amb.mood == null:
		return
	var profile := amb.mood.profile
	check(amb.mood.get_target_color() == profile.sample(0.0), "with no match the mood holds its opening colour")
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	await _frames(1)
	manager.clock = 900.0
	check(amb.mood.get_target_color() == profile.sample(900.0), "the mood follows the match clock")
	check(profile.sample(900.0) != profile.sample(0.0), "the late match looks different from the start")
	manager.queue_free()


func _shots(amb: MapAmbience) -> void:
	var region: RegionAmbience
	for r in amb.get_regions():
		if not r.get_critters().is_empty():
			region = r
			break
	if region == null:
		return
	for c in region.get_critters():
		c.scared = 0.0
		c.pos = c.home
	var home: Vector2 = region.get_critters()[0].home
	# A real hero's weapon, the hero parked far away so only the shot counts.
	hero = load(HERO).instantiate()
	add_child(hero)
	hero.global_position = Vector2(99999, 99999)
	await _frames(1)
	check(amb.is_startling(&"fire") and amb.is_startling(&"snipe_fire"), "fire cues are loud")
	check(not amb.is_startling(&"heal"), "a heal cue isn't")
	var near := region.to_global(home) + Vector2(amb.ambience.shot_scatter_radius * 0.5, 0)
	hero.trigger_cue(&"quick_shot_fire", {"position": near})
	check(region.is_critter_scared(0), "a hero's shot nearby scatters critters (via its cue)")
	for c in region.get_critters():
		c.scared = 0.0
		c.pos = c.home
	hero.trigger_cue(&"quick_shot_fire", {"position": region.to_global(home) + Vector2(99999, 0)})
	check(not region.is_critter_scared(0), "a shot far away doesn't")


func _fountains(amb: MapAmbience) -> void:
	var fountains := amb.get_fountains()
	check(fountains.size() == 4, "a ripple per Dream Basin fountain (%d)" % fountains.size())
	if fountains.is_empty():
		return
	var f: FountainRipple = fountains[0]
	check(f.basin_radius > 100.0, "the ripple reads the basin's size from its shape")
	var rippled := false
	var waited := 0.0
	while waited < amb.ambience.ripple_interval * 1.5 and not rippled:
		await get_tree().process_frame
		waited += get_process_delta_time()
		rippled = f.get_ripple_count() > 0
	check(rippled, "fountains ripple on their own")
	var before := f.get_ripple_count()
	amb.startle(f.global_position + Vector2(50, 0))
	check(f.get_ripple_count() == before + 1, "a shot nearby splashes a fountain")
	await get_tree().create_timer(amb.ambience.ripple_life + amb.ambience.ripple_interval * 1.4).timeout
	check(f.get_ripple_count() <= 2, "old ripples fade away")


func _bush() -> void:
	var bush := get_tree().get_first_node_in_group(Bush.GROUP) as Bush
	check(bush != null, "Dream Basin has bushes")
	if bush == null:
		return
	check(not bush.is_rustling(), "a bush is still with nobody passing")
	var body := hero
	if body == null:
		return
	body.global_position = bush.global_position + Vector2(20, 0)
	for i in 4:
		await get_tree().physics_frame
	check(bush.has_occupant(body), "a body walks into a bush")
	check(bush.is_rustling(), "the bush rustles as it enters")
	await get_tree().create_timer(bush.rustle_time + 0.1).timeout
	check(not bush.is_rustling(), "and settles after rustle_time")


func _placements(map: Node) -> void:
	var glass := get_tree().get_nodes_in_group(BreakableCover.GROUP).filter(func(n): return map.is_ancestor_of(n))
	var geysers := get_tree().get_nodes_in_group(MoteGeyser.GROUP).filter(func(n): return map.is_ancestor_of(n))
	check(glass.size() == 6, "Dream Basin has 6 dream-glass panes (%d)" % glass.size())
	check(geysers.size() == 4, "Dream Basin has 4 Mote geysers (%d)" % geysers.size())
	for group in [glass, geysers]:
		var mirrored := true
		for piece in group:
			var twin: Array = group.filter(func(o): return o.global_position.is_equal_approx(-piece.global_position))
			mirrored = mirrored and twin.size() == 1
		check(mirrored, "every %s has a 180° twin" % ("pane" if group == glass else "geyser"))


func _hurtboxes_at(point: Vector2) -> Array:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = GameRules.current().hurtbox_mask
	return get_world_2d().direct_space_state.intersect_point(query).map(func(r): return r.collider)


func _glass() -> void:
	var glass: BreakableCover = load(GLASS).instantiate()
	glass.data = glass.data.duplicate()
	glass.data.regrow_time = 0.5
	glass.data.regrow_warning = 0.3
	glass.data.regrow_retry = 0.05
	add_child(glass)
	glass.global_position = TEST_SPOT
	for i in 3:
		await get_tree().physics_frame
	check(glass.is_solid() and glass.collision_layer == MapLayers.WORLD, "dream-glass starts solid full cover")
	var outside := glass.global_position + Vector2(0, 30 + BreakableCover.HURT_MARGIN * 0.5)
	check(_hurtboxes_at(outside).has(glass.hurtbox), "a shot stopped at the glass's face still hits it")
	check(glass.hurtbox.get_team() == &"", "the glass is on no team (both teams hit it)")
	glass.hurtbox.take_damage(glass.data.max_health * 0.5)
	check(glass.is_solid() and glass.health.get_health_ratio() < 0.6, "damage cracks it without breaking it")
	glass.hurtbox.take_damage(glass.data.max_health)
	check(not glass.is_solid() and glass.collision_layer == 0, "at 0 HP it shatters: no longer blocks")
	await get_tree().physics_frame
	check(not glass.hurtbox.monitorable, "a shattered pane can't be hit")
	await get_tree().create_timer(0.3).timeout
	check(glass.state == BreakableCover.State.WARNING, "it shimmers before regrowing")
	# Someone standing in it: it waits.
	hero.global_position = glass.global_position
	for i in 3:
		await get_tree().physics_frame
	check(glass.is_blocked(), "a hero in the pane blocks the regrow")
	await get_tree().create_timer(0.4).timeout
	check(not glass.is_solid(), "it waits while someone stands there")
	hero.global_position = glass.global_position + Vector2(0, 400)
	await get_tree().create_timer(0.2).timeout
	check(glass.is_solid() and glass.health.get_health_ratio() == 1.0, "it regrows at full HP once they step out")
	glass.queue_free()


func _geyser() -> void:
	var geyser: MoteGeyser = load(GEYSER).instantiate()
	geyser.data = geyser.data.duplicate()
	geyser.data.hits_to_pop = 3
	geyser.data.cooldown = 0.4
	geyser.data.hit_decay_time = 0.3
	add_child(geyser)
	geyser.global_position = TEST_SPOT + Vector2(1500, 0)
	await get_tree().physics_frame
	check(geyser.collision_layer == MapLayers.LOW_COVER, "a geyser is low cover (walk around, shoot over)")
	check(_hurtboxes_at(geyser.global_position).has(geyser.hurtbox), "a geyser can be hit")
	geyser.hurtbox.take_damage(5.0)
	check(geyser.hits == 1, "each hit counts once, whatever its damage")
	await get_tree().create_timer(0.4).timeout
	check(geyser.hits == 0, "hits fade when nobody keeps hitting")
	var before := get_tree().get_nodes_in_group(Mote.GROUP).size()
	var popped := []
	geyser.popped.connect(func(motes): popped.append_array(motes))
	for i in 3:
		geyser.hurtbox.take_damage(1.0)
	check(popped.size() == geyser.data.mote_count, "enough hits pop %d Motes" % geyser.data.mote_count)
	check(get_tree().get_nodes_in_group(Mote.GROUP).size() == before + geyser.data.mote_count, "the Motes are in the world")
	check(not popped.is_empty() and popped.all(func(m): return m.claim_team == &""), "geyser Motes are free for anyone")
	check(not geyser.is_ready(), "a popped geyser goes dormant")
	geyser.hurtbox.take_damage(1.0)
	check(geyser.hits == 0, "a dormant geyser ignores hits")
	await get_tree().create_timer(0.5).timeout
	check(geyser.is_ready(), "it's ready again after its cooldown")
	for m in popped:
		if is_instance_valid(m):
			m.queue_free()
	geyser.queue_free()


func _clock_jump(amb: MapAmbience) -> void:
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	for i in 2:
		await get_tree().physics_frame
	var motes := MoteDirector.find(get_tree())
	var objectives := ObjectiveDirector.find(get_tree())
	check(motes != null and objectives != null, "the match has its directors")
	if motes == null or objectives == null:
		manager.queue_free()
		return
	var r := manager.get_rules()
	var nightmare: NeutralCamp
	for camp in objectives.get_camps():
		if camp.data.announce:
			nightmare = camp
	check(nightmare != null, "Dream Basin has an announced camp (the Nightmare)")

	manager.jump_clock(nightmare.data.first_spawn_time + 5.0)
	check(manager.is_playing() and is_equal_approx(manager.clock, nightmare.data.first_spawn_time + 5.0),
		"jump_clock sets the clock and starts playing")
	var snapped := amb.mood.color
	var wanted := amb.mood.profile.sample(manager.clock)
	check(snapped.is_equal_approx(wanted), "the mood snaps to the new time (%s vs %s)" % [snapped, wanted])
	for i in 3:
		await get_tree().physics_frame
	check(nightmare.is_alive(), "jumping past the Nightmare's time brings it up")

	manager.jump_clock(nightmare.data.first_spawn_time - 60.0)
	for i in 2:
		await get_tree().physics_frame
	check(not nightmare.is_alive() and nightmare.next_spawn_time == nightmare.data.first_spawn_time,
		"jumping back puts it back on its schedule")

	manager.jump_clock(r.zone_first_time + 5.0)
	for i in 3:
		await get_tree().physics_frame
	check(motes.get_zone_phase() == DreamZone.ZoneState.DREAMING, "jumping into a zone's window starts it dreaming")
	manager.jump_clock(10.0)
	await get_tree().physics_frame
	check(motes.get_zone_phase() == DreamZone.ZoneState.OFF and motes.get_next_zone_time() == r.zone_first_time,
		"jumping back ends it and reschedules the first zone")
	check(is_equal_approx(MoteDirector._next_on_schedule(90, 120, 300, 40), 330.0), "the schedule maths skips a finished zone")
	check(is_equal_approx(MoteDirector._next_on_schedule(90, 120, 215, 40), 210.0), "and keeps one still running")

	var glass := get_tree().get_first_node_in_group(BreakableCover.GROUP) as BreakableCover
	glass.shatter()
	manager.jump_clock(30.0)
	check(glass.is_solid(), "a clock jump regrows shattered glass")
	objectives.despawn_all()
	manager.queue_free()
	await get_tree().physics_frame


func _toggles(amb: MapAmbience) -> void:
	check(VisualToggles.is_on(&"mood"), "visual layers start on")
	VisualToggles.set_on(&"mood", false, get_tree())
	check(amb.mood.get_target_color() == Color.WHITE, "mood off: no tint")
	VisualToggles.set_on(&"floor_grid", false, get_tree())
	var grid := get_tree().root.find_children("*", "FloorGrid", true, false)
	check(not grid.is_empty() and not grid[0].visible, "floor grid off: hidden")
	VisualToggles.set_on(&"bush_rustle", false, get_tree())
	var bush := get_tree().get_first_node_in_group(Bush.GROUP) as Bush
	bush.rustle(Vector2.ZERO)
	check(not bush.is_rustling(), "bush rustle off: no rustle")
	VisualToggles.set_on(&"sound_beds", false, get_tree())
	var kind: StringName = amb.get_regions()[0].pair_id
	amb.update_bed(kind, true, 1.0)
	var cam := Camera2D.new()
	add_child(cam)
	cam.global_position = amb.get_regions()[0].to_global(_point_inside(amb.get_regions()[0]))
	cam.make_current()
	await _frames(3)
	check(amb.get_bed_weight(kind) < 1.0, "sound beds off: they fade out even in their region")
	cam.queue_free()
	VisualToggles.set_all(true, get_tree())
	check(VisualToggles.is_on(&"mood") and grid[0].visible, "all on restores everything")


func _finish() -> void:
	print("Map pieces infra test: %d failed" % failures)
	get_tree().quit(failures)
