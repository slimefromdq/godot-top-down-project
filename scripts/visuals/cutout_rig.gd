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


func get_animation_player() -> AnimationPlayer:
	return get_node_or_null(animation_player_path) as AnimationPlayer


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
