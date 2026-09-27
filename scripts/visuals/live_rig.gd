@tool
extends Node2D
class_name LiveRig

# An 8-direction cutout body drawn live (no bake). Layout:
#
#   LiveRig
#   ├─ Lower     legs, and anything drawn behind the torso (cape, wings)
#   │   └─ Down / DownRight / Right / UpRight / Up    one posed set per facing
#   └─ Upper     torso, head, arms
#       └─ Down / DownRight / Right / UpRight / Up
#
# Only one set per half is visible. The three left facings reuse the right
# ones mirrored (the half's scale.x = -1). Child order inside a set is its
# draw order, so each facing can layer differently (the arm behind the body
# when facing up). Upper faces the aim; Lower faces where you walk, or faces
# the aim and steps backwards when you walk away from it (pick_legs()).
#
# Tags (node metadata, set in the Inspector):
#   sway: float           rotates on a sine wave (cape, wings); value = strength
#   stride_texture: Texture2D   a Sprite2D swaps to it every other step (legs)
#   rest_angle: float     on the aim part: which way its art points at rotation
#                         0, degrees (90 = hanging down)
# The aim part is the node named `aim_part_name` in the visible Upper set; it
# rotates toward the aim every update, its origin is the pivot (shoulder).
#
# Drive it with update(aim, velocity, delta) every frame, plus hurt() / die() /
# revive(). All motion numbers are in `motion` (RigMotion).

## Directions, clockwise from right on screen (y down).
enum { RIGHT, DOWN_RIGHT, DOWN, DOWN_LEFT, LEFT, UP_LEFT, UP, UP_RIGHT }
## The posed set each direction shows, and whether it's mirrored.
const SET_NAMES: Array[StringName] = [&"Right", &"DownRight", &"Down", &"DownRight", &"Right", &"UpRight", &"Up", &"UpRight"]
const MIRRORED: Array[bool] = [false, false, false, true, true, true, false, false]

@export var motion: RigMotion
@export var aim_part_name: StringName = &"AimArm"
## Which facing the editor shows (both halves), for posing.
@export var preview_direction: int = DOWN:
	set(value):
		preview_direction = wrapi(value, 0, 8)
		if is_inside_tree():
			show_direction(preview_direction, preview_direction)

var direction: int = DOWN
var legs_direction: int = DOWN
var walking_backwards := false
## Multiplies the rig's clock (hitstop freezes it with 0).
var time_scale: float = 1.0

var _t := 0.0
var _walk_phase := 0.0
var _move_blend := 0.0
var _hurt_left := 0.0
var _dead_t := -1.0
var _upper_rest := Vector2.ZERO
var _lower_rest := Vector2.ZERO
var _alive_modulate := Color.WHITE


func _ready() -> void:
	if motion == null and not Engine.is_editor_hint():
		motion = RigMotion.new()
	var upper := get_upper()
	var lower := get_lower()
	if upper != null:
		_upper_rest = upper.position
	if lower != null:
		_lower_rest = lower.position
	show_direction(preview_direction, preview_direction)
	direction = preview_direction
	legs_direction = preview_direction


func get_upper() -> Node2D:
	return get_node_or_null(^"Upper") as Node2D


func get_lower() -> Node2D:
	return get_node_or_null(^"Lower") as Node2D


## Problems that would stop the rig working. Empty = ready.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for half_name in [&"Upper", &"Lower"]:
		var half := get_node_or_null(NodePath(half_name)) as Node2D
		if half == null:
			errors.append("no %s node" % half_name)
			continue
		for set_name in [&"Down", &"DownRight", &"Right", &"UpRight", &"Up"]:
			if half.get_node_or_null(NodePath(set_name)) == null:
				errors.append("%s has no %s set" % [half_name, set_name])
	return errors


# --- Picking directions (pure) ------------------------------------------------

## The direction an angle points (radians, screen space). Stays on `current`
## until the angle is `hysteresis_deg` past the edge of its slice.
static func direction_of(angle: float, current: int = -1, hysteresis_deg: float = 10.0) -> int:
	var nearest := wrapi(roundi(angle / (PI / 4.0)), 0, 8)
	if current < 0 or nearest == current:
		return nearest
	var off := absf(angle_difference(angle, current * PI / 4.0))
	return current if off < PI / 8.0 + deg_to_rad(hysteresis_deg) else nearest


## Where the legs face and whether they step backwards. Standing: face the
## torso. Walking within 90 degrees of the aim: face the walk. Walking away
## from the aim: face the torso and step backwards. Never more than two
## directions (90 degrees) off the torso.
static func pick_legs(aim: Vector2, velocity: Vector2, torso: int, current_legs: int,
		was_backwards: bool, move_threshold: float, hysteresis_deg: float = 10.0) -> Dictionary:
	if velocity.length() <= move_threshold:
		return {"direction": torso, "backwards": false}
	var off := absf(angle_difference(aim.angle(), velocity.angle()))
	var limit := PI / 2.0 + deg_to_rad(-hysteresis_deg if was_backwards else hysteresis_deg)
	if off > limit:
		return {"direction": torso, "backwards": true}
	var legs := direction_of(velocity.angle(), current_legs, hysteresis_deg)
	var steps := wrapi(legs - torso + 4, 0, 8) - 4
	if absi(steps) > 2:
		legs = wrapi(torso + signi(steps) * 2, 0, 8)
	return {"direction": legs, "backwards": false}


static func is_mirrored(dir: int) -> bool:
	return MIRRORED[wrapi(dir, 0, 8)]


static func set_name_of(dir: int) -> StringName:
	return SET_NAMES[wrapi(dir, 0, 8)]


# --- Showing ------------------------------------------------------------------

func show_direction(upper_dir: int, lower_dir: int) -> void:
	_show_half(get_upper(), upper_dir)
	_show_half(get_lower(), lower_dir)


func _show_half(half: Node2D, dir: int) -> void:
	if half == null:
		return
	var wanted := set_name_of(dir)
	for child in half.get_children():
		if child is CanvasItem:
			child.visible = child.name == wanted
	half.scale.x = absf(half.scale.x) * (-1.0 if is_mirrored(dir) else 1.0)


## The visible posed set of a half.
func get_active_set(half: Node2D, dir: int) -> Node2D:
	return half.get_node_or_null(NodePath(set_name_of(dir))) as Node2D if half != null else null


## The aim part in the visible Upper set, or null.
func get_aim_part() -> Node2D:
	var active := get_active_set(get_upper(), direction)
	return active.find_child(String(aim_part_name), true, false) as Node2D if active != null else null


# --- Driving ------------------------------------------------------------------

func update(aim: Vector2, velocity: Vector2, delta: float) -> void:
	delta *= time_scale
	if _dead_t >= 0.0:
		_animate_death(delta)
		return
	if aim != Vector2.ZERO:
		direction = direction_of(aim.angle(), direction, motion.direction_hysteresis_deg)
	var legs := pick_legs(aim, velocity, direction, legs_direction, walking_backwards,
			motion.move_threshold, motion.direction_hysteresis_deg)
	legs_direction = legs.direction
	walking_backwards = legs.backwards
	show_direction(direction, legs_direction)
	_animate(velocity, delta)
	_aim(aim if aim != Vector2.ZERO else Vector2.from_angle(direction * PI / 4.0))


func hurt() -> void:
	_hurt_left = motion.hurt_time


func die() -> void:
	if _dead_t < 0.0:
		_dead_t = 0.0
		_alive_modulate = modulate


func revive() -> void:
	_dead_t = -1.0
	_hurt_left = 0.0
	rotation = 0.0
	modulate = _alive_modulate
	var upper := get_upper()
	var lower := get_lower()
	if upper != null:
		upper.position = _upper_rest
	if lower != null:
		lower.position = _lower_rest


func is_dead() -> bool:
	return _dead_t >= 0.0


## A frozen copy of how the rig looks now (afterimages, ghosts).
func make_snapshot() -> Node2D:
	var copy := duplicate() as Node2D
	copy.set_script(null)
	copy.global_transform = global_transform
	return copy


# 1 facing right, -1 mirrored: which way "back" is for tilts.
func _facing_sign() -> float:
	return -1.0 if is_mirrored(direction) else 1.0


func _animate(velocity: Vector2, delta: float) -> void:
	var upper := get_upper()
	var lower := get_lower()
	_t += delta
	var walking := velocity.length() > motion.move_threshold
	_move_blend = move_toward(_move_blend, 1.0 if walking else 0.0, delta * motion.blend_speed)
	var step_dir := -1.0 if walking_backwards else 1.0
	_walk_phase += delta * motion.steps_per_second * _move_blend * step_dir

	var bob := sin(_t * TAU * motion.idle_bob_hz) * motion.idle_bob_px * (1.0 - _move_blend)
	var bounce := -absf(sin(_walk_phase * PI)) * motion.walk_bounce_px * _move_blend
	if upper != null:
		upper.position = _upper_rest + Vector2(0, bob + bounce)
	if lower != null:
		lower.position = _lower_rest + Vector2(0, bounce)

	var sway_deg := lerpf(motion.idle_sway_deg, motion.walk_sway_deg, _move_blend)
	var odd_step := walking and posmod(floori(_walk_phase), 2) == 1
	for half in [upper, lower]:
		var active := get_active_set(half, direction if half == upper else legs_direction)
		if active == null:
			continue
		for node in active.find_children("*", "Node2D", true, false):
			if node.has_meta(&"sway"):
				var rest: float = node.get_meta(&"_rest_rotation", node.rotation)
				node.set_meta(&"_rest_rotation", rest)
				node.rotation = rest + deg_to_rad(sway_deg * float(node.get_meta(&"sway"))) \
						* sin(_t * TAU * motion.sway_hz)
			if node is Sprite2D and node.has_meta(&"stride_texture"):
				var rest_tex: Texture2D = node.get_meta(&"_rest_texture", node.texture)
				node.set_meta(&"_rest_texture", rest_tex)
				node.texture = node.get_meta(&"stride_texture") if odd_step else rest_tex

	_hurt_left = maxf(_hurt_left - delta, 0.0)
	var hurt_k := sin(PI * (1.0 - _hurt_left / motion.hurt_time)) if _hurt_left > 0.0 else 0.0
	rotation = -deg_to_rad(motion.hurt_tilt_deg) * hurt_k * _facing_sign()


func _animate_death(delta: float) -> void:
	_dead_t += delta
	var k := clampf(_dead_t / motion.death_time, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - k, 2.0)
	rotation = -deg_to_rad(motion.death_tip_deg) * eased * _facing_sign()
	var drop := Vector2(0, motion.death_drop_px * eased)
	var upper := get_upper()
	var lower := get_lower()
	if upper != null:
		upper.position = _upper_rest + drop
	if lower != null:
		lower.position = _lower_rest + drop
	var fade := clampf((_dead_t - motion.death_time) / maxf(motion.death_fade_time, 0.001), 0.0, 1.0)
	modulate = Color(_alive_modulate, _alive_modulate.a * (1.0 - fade))


# Point the aim part along `aim` in world space, whatever its parents' flip
# or tilt.
func _aim(aim: Vector2) -> void:
	var part := get_aim_part()
	if part == null or part.get_parent() == null:
		return
	var parent := part.get_parent() as Node2D
	var local := parent.global_transform.affine_inverse().basis_xform(aim)
	part.rotation = local.angle() - deg_to_rad(float(part.get_meta(&"rest_angle", 90.0)))
