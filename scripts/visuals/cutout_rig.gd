@tool
extends Node2D
class_name CutoutRig

# A cutout ("paper-doll") body: separate art parts (Sprite2D / Polygon2D)
# under this node, animated by a child AnimationPlayer. RigBaker renders it
# into a sprite sheet + SpriteFrames for VisualProfile > Sprite Frames.
#
# This node's origin is the centre of every baked frame, so put it where the
# character's body centre should be (AnimatedSprite2D draws frames centred).
# Parts in the "bake_hidden" group are hidden while baking (e.g. an arm that
# will rotate toward the aim live).
#
# Bake: see tools/visuals/bake_rig.gd and docs/VISUALS_AND_AUDIO.md.

const HIDDEN_GROUP := &"bake_hidden"
enum { LAYER_UPPER, LAYER_LEGS }

## Size of one baked frame in pixels. Leave room for the widest pose.
@export var frame_size: Vector2i = Vector2i(256, 256)
## Frames per second the animations are sampled at and played back at.
@export var fps: float = 12.0
## Animations to bake, in sheet row order. Missing ones are skipped.
@export var bake_animations: Array[StringName] = [&"idle", &"move", &"hurt", &"death"]
## Scale applied while baking (draw large art, bake it smaller).
@export var bake_scale: float = 1.0
## Path of the AnimationPlayer, relative to this node.
@export var animation_player_path: NodePath = ^"AnimationPlayer"
## Optional live part (the weapon arm) that rotates toward the aim in game.
## It's left out of the bake and exported as its own scene; its origin is
## the pivot (shoulder). Empty = no aim part.
@export var aim_part_path: NodePath
## Which way the aim part's art points at rotation 0 (90 = hanging down).
@export_range(-180.0, 180.0, 1.0, "degrees") var aim_part_rest_angle: float = 90.0
## Parts baked into a second "legs" layer (with their children), drawn behind
## the rest. In game the legs play their walk backwards while you move away
## from the aim, so the body keeps facing the mouse. List the legs, and
## anything drawn behind the torso (cape, wings) so the order holds.
## Empty = one layer.
@export var legs_layer_paths: Array[NodePath] = []


func get_animation_player() -> AnimationPlayer:
	return get_node_or_null(animation_player_path) as AnimationPlayer


func get_aim_part() -> Node2D:
	if aim_part_path.is_empty():
		return null
	return get_node_or_null(aim_part_path) as Node2D


## The aim part's pivot relative to this rig's origin (= the frame centre),
## at bake scale, in the rest pose. Call it before any animation has played.
func get_aim_pivot() -> Vector2:
	var part := get_aim_part()
	if part == null:
		return Vector2.ZERO
	var local := Vector2.ZERO
	var node: Node = part
	while node != self and node is Node2D:
		local = (node as Node2D).transform * local
		node = node.get_parent()
	return local * bake_scale


## A standalone copy of the aim part in its rest pose, scaled to the bake
## (origin = pivot, rotation 0), ready to pack as a scene.
func make_aim_part_copy() -> Node2D:
	var part := get_aim_part()
	if part == null:
		return null
	var copy := part.duplicate() as Node2D
	copy.position = Vector2.ZERO
	copy.rotation = 0.0
	copy.scale *= bake_scale
	copy.visible = true
	for node in copy.find_children("*", "", true, false):
		node.owner = copy
	return copy


## The legs layer's root parts (legs_layer_paths that exist).
func get_legs_parts() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	for path in legs_layer_paths:
		var node := get_node_or_null(path) as CanvasItem
		if node != null:
			out.append(node)
	return out


## Shows only one layer for a bake pass: LAYER_UPPER hides the legs parts,
## LAYER_LEGS hides everything else (parents of legs parts only stop drawing
## themselves). Returns what to hand restore_layers() afterwards.
func isolate_layer(layer: int) -> Array:
	var changed := []
	var legs := get_legs_parts()
	if layer == LAYER_UPPER:
		for node in legs:
			changed.append([node, &"visible", node.visible])
			node.visible = false
		return changed
	for node in find_children("*", "CanvasItem", true, false):
		var item := node as CanvasItem
		if legs.any(func(l): return l == item or l.is_ancestor_of(item)):
			continue
		if legs.any(func(l): return item.is_ancestor_of(l)):
			changed.append([item, &"self_modulate", item.self_modulate])
			item.self_modulate = Color(1, 1, 1, 0)
		else:
			changed.append([item, &"visible", item.visible])
			item.visible = false
	return changed


static func restore_layers(changed: Array) -> void:
	changed.reverse()
	for entry in changed:
		(entry[0] as Object).set(entry[1], entry[2])


## Problems that would stop a bake. Empty = ready.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("frame_size must be positive")
	if fps <= 0.0:
		errors.append("fps must be positive")
	if bake_scale <= 0.0:
		errors.append("bake_scale must be positive")
	var player := get_animation_player()
	if player == null:
		errors.append("no AnimationPlayer at %s" % animation_player_path)
	elif get_bake_list().is_empty():
		errors.append("none of %s exist in the AnimationPlayer" % [bake_animations])
	if not aim_part_path.is_empty() and get_aim_part() == null:
		errors.append("no Node2D aim part at %s" % aim_part_path)
	if get_legs_parts().size() != legs_layer_paths.size():
		errors.append("a legs_layer_paths entry is missing: %s" % [legs_layer_paths])
	return errors


## The bake_animations that actually exist, in order.
func get_bake_list() -> Array[StringName]:
	var out: Array[StringName] = []
	var player := get_animation_player()
	if player == null:
		return out
	for anim_name in bake_animations:
		if player.has_animation(anim_name):
			out.append(anim_name)
	return out


## Sample times for one animation. Looping animations leave out the last
## instant (it equals the first), one-shots include it so they end on it.
func get_sample_times(anim_name: StringName) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var anim := get_animation_player().get_animation(anim_name)
	var looping := anim.loop_mode != Animation.LOOP_NONE
	var count := maxi(1, ceili(anim.length * fps - 0.001))
	if not looping:
		count += 1
	for i in count:
		times.append(minf(i / fps, anim.length))
	return times


func is_looping(anim_name: StringName) -> bool:
	return get_animation_player().get_animation(anim_name).loop_mode != Animation.LOOP_NONE
