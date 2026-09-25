extends Node2D
class_name Hitbox

# Finds what an attack touches. Put one on an actor; abilities call it.
#
# Why shape queries instead of an Area2D's "area_entered" signal?
# An Area2D only reports targets as they ENTER, and one physics frame late. A
# dummy already standing inside the arc when the swing starts would never
# "enter", so it would be missed. Instead, every tick while an attack is
# active, we ask the physics engine "which hurtboxes are inside this shape
# right now?". That's deterministic, catches everything, and a server can run
# the exact same query later.
#
# Per-attack hit registration: each attack has an attack_id; a target hit once
# by that id is skipped for the rest of the attack, so a swing that stays
# active for several ticks still hits each target exactly once.
#
# Usage:
#   var id := hitbox.begin(shape, direction, make_info)   # active frames start
#   ...                                                     # queried each tick
#   hitbox.end(id)                                          # active frames end
# or hitbox.sweep(shape, direction, make_info) for a one-tick check.

## Emitted for every target an attack connects with, after the hit applies.
signal hit_landed(info: DamageInfo, hurtbox: HurtboxComponent)

## Who an area effect touches (GroundZoneData.affects). ENEMIES follows
## can_hit(); ALLIES are the source's teammates INCLUDING the source itself;
## BOTH is either.
enum Affects { ENEMIES, ALLIES, BOTH }

## Draw active shapes in-game, for tuning reach and width.
@export var debug_draw: bool = false

var _attacks: Dictionary = {}    # attack_id -> Attack


class Attack:
	var shape: HitShape
	var direction: Vector2
	# Callable(hurtbox: HurtboxComponent) -> DamageInfo. Built per target so
	# an ability can vary damage by target (e.g. diminishing returns).
	var make_info: Callable
	var already_hit: Dictionary = {}    # hurtbox instance id -> true
	var hit_count: int = 0


func get_actor() -> Node2D:
	return (owner if owner != null else get_parent()) as Node2D


# Start an attack's active window. Checks immediately, then every tick until
# end(). Returns the attack id (already set on every DamageInfo it produces).
func begin(shape: HitShape, direction: Vector2, make_info: Callable, attack_id: int = 0) -> int:
	if attack_id == 0:
		attack_id = DamageInfo.new_attack_id()
	var attack := Attack.new()
	attack.shape = shape
	attack.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	attack.make_info = make_info
	_attacks[attack_id] = attack
	_check(attack_id)
	queue_redraw()
	return attack_id


func end(attack_id: int) -> void:
	_attacks.erase(attack_id)
	queue_redraw()


func end_all() -> void:
	_attacks.clear()
	queue_redraw()


func is_active(attack_id: int) -> bool:
	return _attacks.has(attack_id)


# How many targets an attack has hit so far.
func get_hit_count(attack_id: int) -> int:
	var attack: Attack = _attacks.get(attack_id)
	return attack.hit_count if attack != null else 0


# One-tick check (explosions, bursts). Returns the hurtboxes hit.
func sweep(shape: HitShape, direction: Vector2, make_info: Callable, attack_id: int = 0) -> Array[HurtboxComponent]:
	var id := begin(shape, direction, make_info, attack_id)
	var hit: Array[HurtboxComponent] = []
	var attack: Attack = _attacks[id]
	for key in attack.already_hit:
		var node := instance_from_id(key) as HurtboxComponent
		if node != null:
			hit.append(node)
	end(id)
	return hit


func _physics_process(_delta: float) -> void:
	for attack_id in _attacks.keys():
		if _attacks.has(attack_id):
			_check(attack_id)


func _check(attack_id: int) -> void:
	var attack: Attack = _attacks[attack_id]
	for hurtbox in find_targets(attack.shape, attack.direction):
		var key := hurtbox.get_instance_id()
		if attack.already_hit.has(key):
			continue
		attack.already_hit[key] = true
		var info: DamageInfo = attack.make_info.call(hurtbox)
		if info == null:
			continue
		info.attack_id = attack_id
		if info.direction == Vector2.ZERO:
			info.direction = attack.direction
		info.hit_position = hurtbox.global_position
		attack.hit_count += 1
		hurtbox.take_hit(info)
		hit_landed.emit(info, hurtbox)
		if not _attacks.has(attack_id):
			return    # a hit ended the attack (e.g. the attacker died)


# Every valid enemy hurtbox inside `shape`. Public so AI and targeting
# previews can ask "would this hit anything?" without dealing damage.
func find_targets(shape: HitShape, direction: Vector2) -> Array[HurtboxComponent]:
	var actor := get_actor()
	return query(actor, actor.global_position, direction, shape, actor)


# The shared search behind Hitbox, GroundZone and area bursts: every hurtbox
# `source` is allowed to hit inside `shape`, placed at `origin` facing
# `direction`. `context` is any node in the world (for physics access).
static func query(context: Node2D, origin: Vector2, direction: Vector2, shape: HitShape,
		source: Node, affects: Affects = Affects.ENEMIES) -> Array[HurtboxComponent]:
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	origin += direction * shape.forward_offset
	var params := PhysicsShapeQueryParameters2D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = GameRules.current().hurtbox_mask

	match shape.kind:
		HitShape.Kind.LINE:
			var rect := RectangleShape2D.new()
			rect.size = Vector2(shape.length, shape.width)
			params.shape = rect
			params.transform = Transform2D(direction.angle(), origin + direction * shape.length / 2.0)
		_:
			# ARC searches the full circle, then filters by angle below.
			var circle := CircleShape2D.new()
			circle.radius = shape.radius
			params.shape = circle
			params.transform = Transform2D(0.0, origin)

	var results: Array[HurtboxComponent] = []
	for hit in context.get_world_2d().direct_space_state.intersect_shape(params, 64):
		var hurtbox := hit.collider as HurtboxComponent
		if hurtbox == null or not affects_target(source, hurtbox, affects):
			continue
		if shape.kind == HitShape.Kind.ARC and not _inside_arc(hurtbox, origin, direction, shape):
			continue
		results.append(hurtbox)
	return results


# Team rules in one place: never yourself, never a teammate, anyone may hit
# a neutral (team-less) target, and a neutral source hits everyone.
static func can_hit(source: Node, hurtbox: HurtboxComponent) -> bool:
	if not hurtbox.is_valid_target():
		return false
	if source == null or not is_instance_valid(source):
		return true
	if hurtbox.owner == source or hurtbox.get_parent() == source:
		return false
	var team = source.get(&"team")
	return team == null or team == &"" or hurtbox.get_team() != team


static func affects_target(source: Node, hurtbox: HurtboxComponent, affects: Affects) -> bool:
	match affects:
		Affects.ALLIES:
			return is_ally(source, hurtbox)
		Affects.BOTH:
			return can_hit(source, hurtbox) or is_ally(source, hurtbox)
	return can_hit(source, hurtbox)


# Same team as `source`, or `source` itself. A neutral (team-less) source
# has no allies but itself.
static func is_ally(source: Node, hurtbox: HurtboxComponent) -> bool:
	if not hurtbox.is_valid_target() or source == null or not is_instance_valid(source):
		return false
	if hurtbox.owner == source or hurtbox.get_parent() == source:
		return true
	var team = source.get(&"team")
	return team != null and team != &"" and hurtbox.get_team() == team


# The target counts if any part of its body (approximated as a circle)
# overlaps the slice, not just its centre: widen the allowed angle by the
# target's angular size at that distance.
static func _inside_arc(hurtbox: HurtboxComponent, origin: Vector2, direction: Vector2, shape: HitShape) -> bool:
	var to_target := hurtbox.global_position - origin
	var distance := to_target.length()
	var target_radius := hurtbox.get_radius()
	if distance <= target_radius:
		return true
	if distance - target_radius > shape.radius:
		return false
	var half_arc := deg_to_rad(shape.arc_degrees) / 2.0
	var angular_size := asin(clampf(target_radius / distance, 0.0, 1.0))
	return absf(direction.angle_to(to_target)) <= half_arc + angular_size


func _process(_delta: float) -> void:
	if debug_draw and not _attacks.is_empty():
		queue_redraw()


func _draw() -> void:
	if not debug_draw:
		return
	var color := Color(1, 0.3, 0.2, 0.3)
	for attack: Attack in _attacks.values():
		var shape := attack.shape
		var dir := attack.direction
		var origin := dir * shape.forward_offset
		match shape.kind:
			HitShape.Kind.ARC:
				var half := deg_to_rad(shape.arc_degrees) / 2.0
				var points := PackedVector2Array([origin])
				for i in 17:
					points.append(origin + dir.rotated(lerpf(-half, half, i / 16.0)) * shape.radius)
				draw_colored_polygon(points, color)
			HitShape.Kind.CIRCLE:
				draw_circle(origin, shape.radius, color)
			HitShape.Kind.LINE:
				draw_set_transform(origin + dir * shape.length / 2.0, dir.angle())
				draw_rect(Rect2(-shape.length / 2.0, -shape.width / 2.0, shape.length, shape.width), color)
				draw_set_transform(Vector2.ZERO)
