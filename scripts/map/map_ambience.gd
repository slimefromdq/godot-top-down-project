extends Node2D
class_name MapAmbience

# A map's idle life, from one AmbienceSet (see docs/VISUALS_AND_AUDIO.md >
# Map ambience). Put one in a map scene; on ready it builds:
#   - a RegionAmbience (drifters + critters) for every DreamZone of this map
#     whose pair_id has a profile,
#   - one looping sound bed per pair_id, crossfaded in while the listener
#     (the camera, else the local player) stands in one of its regions,
#   - a MapMood (CanvasModulate) that tints the world over the match,
#   - a DreamerGlow around every Dreamer of this map,
#   - a FountainRipple on every node of this map in the "fountains" group.
# It listens to every Actor's cue_triggered signal (actors never call it): a
# startling cue (AmbienceSet.startle_cues: `fire`, `<ability>_fire` ...)
# scatters critters and splashes fountains near where it happened.
# Presentation only: it reads the map and match, never changes them.

const GROUP := &"map_ambience"
## Quietest a faded-out bed goes before it's paused.
const SILENT_DB := -60.0

@export var ambience: AmbienceSet

var mood: MapMood
var _regions: Array[RegionAmbience] = []
var _beds: Dictionary = {}    # pair_id -> AudioStreamPlayer
var _bed_weight: Dictionary = {}    # pair_id -> 0..1
var _glows: Array[DreamerGlow] = []
var _fountains: Array[FountainRipple] = []


func _ready() -> void:
	add_to_group(GROUP)
	# Zones and Dreamers are siblings further down the scene; wait for them.
	_build.call_deferred()


func _build() -> void:
	if ambience == null:
		return
	var map := _find_map()
	var index := 0
	for zone in get_tree().get_nodes_in_group(DreamZone.GROUP):
		if map and not map.is_ancestor_of(zone):
			continue
		var profile: AmbienceProfile = ambience.regions.get(zone.pair_id)
		var poly: PackedVector2Array = zone.get_minimap_polygon()
		if profile == null or poly.size() < 3:
			continue
		var region := RegionAmbience.new()
		region.name = "Ambience_%s" % zone.name
		region.z_index = 1
		add_child(region)
		region.setup(profile, global_transform.affine_inverse() * poly, zone.pair_id, 7919 * (index + 1))
		_regions.append(region)
		index += 1
		if profile.loop and not _beds.has(zone.pair_id):
			var bed := AudioStreamPlayer.new()
			bed.name = "Bed_%s" % zone.pair_id
			bed.stream = profile.loop
			bed.bus = &"SFX"
			bed.volume_db = SILENT_DB
			bed.finished.connect(bed.play)
			add_child(bed)
			_beds[zone.pair_id] = bed
			_bed_weight[zone.pair_id] = 0.0
	if ambience.mood:
		mood = MapMood.new()
		mood.name = "Mood"
		mood.profile = ambience.mood
		add_child(mood)
	for dreamer in get_tree().get_nodes_in_group(Dreamer.GROUP):
		if map and not map.is_ancestor_of(dreamer):
			continue
		var glow := DreamerGlow.new()
		glow.setup(dreamer, ambience)
		add_child(glow)
		_glows.append(glow)
	for fountain in get_tree().get_nodes_in_group(FountainRipple.GROUP):
		if not fountain is Node2D or map and not map.is_ancestor_of(fountain):
			continue
		var ripple := FountainRipple.new()
		add_child(ripple)
		ripple.global_position = fountain.global_position
		ripple.setup(fountain, ambience, 104729 + _fountains.size())
		_fountains.append(ripple)
	get_tree().node_added.connect(_on_node_added)
	for actor in get_tree().root.find_children("*", "Actor", true, false):
		_listen(actor)


func _on_node_added(node: Node) -> void:
	if node is Actor:
		_listen(node)


func _listen(actor: Actor) -> void:
	if not actor.cue_triggered.is_connected(_on_cue):
		actor.cue_triggered.connect(_on_cue.bind(actor))


func _on_cue(cue: StringName, context: Dictionary, actor: Actor) -> void:
	if not is_startling(cue) or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var at: Vector2 = context.get("position", actor.global_position)
	startle(at)


## Is `cue` loud: one of startle_cues, or `<anything>_<one of them>`?
func is_startling(cue: StringName) -> bool:
	var text := String(cue)
	for loud in ambience.startle_cues:
		if text == loud or text.ends_with("_" + loud):
			return true
	return false


## Something loud happened at a world point: nearby critters scatter and
## nearby fountains ripple.
func startle(world_point: Vector2) -> void:
	var radius := ambience.shot_scatter_radius
	for region in _regions:
		if region.global_position.distance_to(world_point) < region.get_reach() + radius:
			region.startle(world_point, radius)
	for ripple in _fountains:
		var local := ripple.to_local(world_point)
		if local.length() < radius:
			ripple.splash(local)


func get_fountains() -> Array[FountainRipple]:
	return _fountains


func _find_map() -> Node:
	var node := get_parent()
	while node:
		if node.is_in_group(&"game_map"):
			return node
		node = node.get_parent()
	return null


func get_regions() -> Array[RegionAmbience]:
	return _regions


func get_glows() -> Array[DreamerGlow]:
	return _glows


func get_bed_weight(pair_id: StringName) -> float:
	return _bed_weight.get(pair_id, 0.0)


## Which region kind (pair_id) a world point is in, or &"" for none.
func region_at(world_point: Vector2) -> StringName:
	for region in _regions:
		if region.contains(region.to_local(world_point)):
			return region.pair_id
	return &""


func _listener_position() -> Variant:
	var camera := get_viewport().get_camera_2d()
	if camera:
		return camera.get_screen_center_position()
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	return player.global_position if player else null


func _process(delta: float) -> void:
	if _beds.is_empty():
		return
	var at: Variant = _listener_position()
	var here: StringName = region_at(at) if at != null else &""
	var step := 1.0 if ambience.crossfade_time <= 0.0 else delta / ambience.crossfade_time
	for pair_id in _beds:
		update_bed(pair_id, here == pair_id, step)


func update_bed(pair_id: StringName, active: bool, step: float) -> void:
	var bed: AudioStreamPlayer = _beds[pair_id]
	var w: float = move_toward(_bed_weight[pair_id], 1.0 if active else 0.0, step)
	_bed_weight[pair_id] = w
	var profile: AmbienceProfile = ambience.regions[pair_id]
	bed.volume_db = maxf(SILENT_DB, profile.loop_volume_db + linear_to_db(maxf(w, 0.0001)))
	if w > 0.0 and not bed.playing:
		bed.play()
	elif w <= 0.0 and bed.playing:
		bed.stop()
