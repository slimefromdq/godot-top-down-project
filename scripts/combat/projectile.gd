extends Node2D
class_name Projectile

# Generic projectile driven by a ProjectileData. Spawn it with
# Projectile.fire(); never set it up by hand.
#
# Like Hitbox it uses shape queries instead of Area2D signals: each tick it
# sweeps a box from where it was to where it is now, so fast projectiles
# can't skip over a thin target between frames (tunnelling), and the result is
# the same on every machine.

const SCENE_PATH := "res://scenes/combat/projectile.tscn"

var data: ProjectileData
var direction := Vector2.RIGHT
# The template every hit is copied from (amount, type, tags, label, source).
var damage_template: DamageInfo

var _age: float = 0.0
var _hits: int = 0
var _already_hit: Dictionary = {}
var _sweep_shape := RectangleShape2D.new()
var _circle_shape := CircleShape2D.new()


# Spawns a projectile into the current scene and returns it.
# `template` carries the damage; its attack_id is shared by all targets so
# pierce never hits the same target twice.
static func fire(context: Node, projectile_data: ProjectileData, origin: Vector2,
		dir: Vector2, template: DamageInfo) -> Projectile:
	var projectile: Projectile = load(SCENE_PATH).instantiate()
	projectile.data = projectile_data
	projectile.direction = dir.normalized()
	projectile.damage_template = template
	if template.attack_id == 0:
		template.attack_id = DamageInfo.new_attack_id()
	if not template.tags.has(DamageInfo.TAG_PROJECTILE):
		template.tags.append(DamageInfo.TAG_PROJECTILE)
	context.get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin
	projectile.rotation = projectile.direction.angle()
	return projectile


func _ready() -> void:
	if data.visual_scene != null:
		add_child(data.visual_scene.instantiate())
	else:
		queue_redraw()


func _draw() -> void:
	if data != null and data.visual_scene == null:
		draw_circle(Vector2.ZERO, data.radius, Color(1, 0.7, 0.3, 0.8))


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * data.speed * delta
	_age += delta

	if data.stops_at_walls:
		var ray := PhysicsRayQueryParameters2D.create(from, to, GameRules.current().wall_mask)
		var wall := get_world_2d().direct_space_state.intersect_ray(ray)
		if not wall.is_empty():
			to = wall.position
			_hit_targets_between(from, to)
			global_position = to
			_expire()
			return

	_hit_targets_between(from, to)
	if not is_queued_for_deletion():
		global_position = to
		if _age >= data.lifetime:
			_expire()


func _hit_targets_between(from: Vector2, to: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = GameRules.current().hurtbox_mask
	var step := to - from
	if step.length() > 0.5:
		_sweep_shape.size = Vector2(step.length(), data.radius * 2.0)
		query.shape = _sweep_shape
		query.transform = Transform2D(step.angle(), from + step / 2.0)
	else:
		_circle_shape.radius = data.radius
		query.shape = _circle_shape
		query.transform = Transform2D(0.0, to)

	# Closest first, so pierce order matches flight order.
	var found: Array[HurtboxComponent] = []
	for result in space.intersect_shape(query, 32):
		var hurtbox := result.collider as HurtboxComponent
		if hurtbox != null and _can_hit(hurtbox):
			found.append(hurtbox)
	found.sort_custom(func(a, b): return from.distance_squared_to(a.global_position) < from.distance_squared_to(b.global_position))

	for hurtbox in found:
		_already_hit[hurtbox.get_instance_id()] = true
		var info := damage_template.copy()
		info.direction = direction
		info.hit_position = hurtbox.global_position
		info.knockback = direction * data.knockback
		info.add_status(data.on_hit_status)
		hurtbox.take_hit(info)
		_spawn_feedback(data.hit_effect, data.hit_sound, hurtbox.global_position)
		_hits += 1
		if data.pierce >= 0 and _hits > data.pierce:
			queue_free()
			return


func _can_hit(hurtbox: HurtboxComponent) -> bool:
	return not _already_hit.has(hurtbox.get_instance_id()) \
		and Hitbox.can_hit(damage_template.source, hurtbox)


func _expire() -> void:
	_spawn_feedback(data.expire_effect, data.expire_sound, global_position)
	queue_free()


func _spawn_feedback(effect: PackedScene, sound: SoundCue, at: Vector2) -> void:
	EffectSpawner.spawn(self, effect, {"position": at, "direction": direction})
	AudioManager.play_sfx(sound, at)
