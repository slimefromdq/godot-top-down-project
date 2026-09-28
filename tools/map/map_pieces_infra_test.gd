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


func _finish() -> void:
	print("Map pieces infra test: %d failed" % failures)
	get_tree().quit(failures)
