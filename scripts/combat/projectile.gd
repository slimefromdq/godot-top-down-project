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
## Added to hits on a returning projectile's way back.
const TAG_RETURN := &"return"

enum Pass { OUTBOUND, RETURN }

## Every target hit, after the hit applied (info.final_amount is set).
## Explosions report each target they damage here too.
signal hit_landed(info: DamageInfo, hurtbox: HurtboxComponent)
## The projectile exploded (ProjectileData explosion) at `at`.
signal exploded(at: Vector2)
## Like hit_landed, with which pass of a returning projectile it was.
signal pass_hit(info: DamageInfo, hurtbox: HurtboxComponent, which_pass: Pass)
## A returning projectile turned around / got back to its caster.
signal turned_back(at: Vector2)
signal returned

var data: ProjectileData
var direction := Vector2.RIGHT
# The template every hit is copied from (amount, type, tags, label, source).
var damage_template: DamageInfo
## Optional. Callable(info: DamageInfo, hurtbox: HurtboxComponent,
## travelled: float) -> DamageInfo, run on each hit's copy before it lands.
## Return null to skip that target. RangedAttackAbility uses it for damage
## falloff by distance and its _build_hit hook.
var hit_modifier: Callable
## Where it was fired from (for distance falloff).
var fired_from := Vector2.ZERO
## False for projectiles born from a split: they never split again.
var can_split := true
## Damage of each split projectile. < 0 = the shot's damage x
## data.split_damage_multiplier. Firing abilities may set it per shot.
var split_damage: float = -1.0

var _exploded := false
## Which pass a returning projectile is on (always OUTBOUND otherwise).
var current_pass: Pass = Pass.OUTBOUND

# Returning motion: the outbound path is a function of distance travelled,
# the return path homes a base point on the caster and adds the bulge.
var _out_distance: float = 0.0
var _return_base := Vector2.ZERO
var _return_length: float = 0.0
var _detonation_only := false

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
	projectile.fired_from = origin
	projectile.rotation = projectile.direction.angle()
	return projectile


# A blast with no flight (a ground-targeted detonation, a meteor): runs the
# data's explosion at `at` right away, using `template` for damage.
# `on_hit` (optional) is connected to hit_landed first, so the caller's
# hooks see every target.
static func explode_at(context: Node, projectile_data: ProjectileData, at: Vector2, dir: Vector2,
		template: DamageInfo, on_hit: Callable = Callable()) -> Projectile:
	var projectile: Projectile = load(SCENE_PATH).instantiate()
	projectile._detonation_only = true
	projectile.data = projectile_data
	projectile.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	projectile.damage_template = template
	if template.attack_id == 0:
		template.attack_id = DamageInfo.new_attack_id()
	if on_hit.is_valid():
		projectile.hit_landed.connect(on_hit)
	context.get_tree().current_scene.add_child(projectile)
	projectile.global_position = at
	projectile.fired_from = at
	projectile._explode(at)
	projectile.queue_free()
	return projectile


func _ready() -> void:
	if _detonation_only:
		return
	if data.visual_scene != null:
		add_child(data.visual_scene.instantiate())
	else:
		queue_redraw()


func _draw() -> void:
	if data != null and data.visual_scene == null:
		draw_circle(Vector2.ZERO, data.radius, Color(1, 0.7, 0.3, 0.8))


func _physics_process(delta: float) -> void:
	if _detonation_only:
		return
	if data.return_to_caster:
		_process_returning(delta)
		return
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
		if data.explode_on_hit and data.explosion_shape != null:
			# The blast replaces the direct hit (it catches this target too).
			_explode(hurtbox.global_position)
			queue_free()
			return
		var info := damage_template.copy()
		info.direction = direction
		info.hit_position = hurtbox.global_position
		info.knockback = direction * data.knockback
		info.add_status(data.on_hit_status)
		if hit_modifier.is_valid():
			info = hit_modifier.call(info, hurtbox, fired_from.distance_to(hurtbox.global_position))
			if info == null:
				continue
		if current_pass == Pass.RETURN and not info.tags.has(TAG_RETURN):
			info.tags.append(TAG_RETURN)
		hurtbox.take_hit(info)
		hit_landed.emit(info, hurtbox)
		pass_hit.emit(info, hurtbox, current_pass)
		_spawn_feedback(data.hit_effect, data.hit_sound, hurtbox.global_position)
		_hits += 1
		if data.pierce >= 0 and _hits > data.pierce:
			if data.return_to_caster and current_pass == Pass.OUTBOUND:
				_start_return()    # out of pierce: come back early
			else:
				queue_free()
			return


func _can_hit(hurtbox: HurtboxComponent) -> bool:
	return not _already_hit.has(hurtbox.get_instance_id()) \
		and Hitbox.can_hit(damage_template.source, hurtbox)


func _expire() -> void:
	if data.explode_on_expire and data.explosion_shape != null:
		_explode(global_position)
	elif not _exploded:
		_spawn_feedback(data.expire_effect, data.expire_sound, global_position)
	queue_free()


# The blast: damage + explosion_status to enemies in explosion_shape,
# explosion_ally_status to allies, then the optional split. Each damaged
# target goes through hit_modifier and hit_landed like a direct hit, so
# the firing ability's hooks and cues still see it.
func _explode(at: Vector2) -> void:
	if _exploded:
		return
	_exploded = true
	var source: Node = damage_template.source if is_instance_valid(damage_template.source) else null
	var amount := damage_template.amount * data.explosion_damage_multiplier
	if data.explosion_damage != null:
		amount = data.explosion_damage.evaluate(StatsComponent.find_on(source))
	for hurtbox in Hitbox.query(self, at, direction, data.explosion_shape, source, Hitbox.Affects.BOTH):
		if Hitbox.can_hit(source, hurtbox):
			var info := damage_template.copy()
			info.amount = amount
			if data.explosion_label != &"":
				info.label = data.explosion_label
			if not info.tags.has(DamageInfo.TAG_AREA):
				info.tags.append(DamageInfo.TAG_AREA)
			var away := at.direction_to(hurtbox.global_position)
			info.direction = away if away != Vector2.ZERO else direction
			info.hit_position = hurtbox.global_position
			info.knockback = info.direction * data.knockback
			info.add_status(data.on_hit_status)
			info.add_status(data.explosion_status)
			if hit_modifier.is_valid():
				info = hit_modifier.call(info, hurtbox, fired_from.distance_to(hurtbox.global_position))
				if info == null:
					continue
			hurtbox.take_hit(info)
			hit_landed.emit(info, hurtbox)
		elif data.explosion_ally_status != null and hurtbox.status_component != null:
			hurtbox.status_component.apply(data.explosion_ally_status, source, direction)
	_spawn_feedback(data.explosion_effect, data.explosion_sound, at)
	exploded.emit(at)
	if can_split and data.split_on_explode and data.split_projectile != null:
		_split(at)


func _split(at: Vector2) -> void:
	var count := maxi(data.split_count, 0)
	var each := split_damage if split_damage >= 0.0 else damage_template.amount * data.split_damage_multiplier
	for i in count:
		var angle := 0.0 if count <= 1 else lerpf(-data.split_fan_degrees / 2.0, data.split_fan_degrees / 2.0, float(i) / (count - 1))
		var template := damage_template.copy()
		template.attack_id = 0    # each child is its own attack
		template.amount = each
		var child := Projectile.fire(self, data.split_projectile, at, direction.rotated(deg_to_rad(angle)), template)
		child.can_split = false
		child.hit_modifier = hit_modifier
		# Children start inside the blast: don't let them re-hit what this
		# projectile already hit directly.
		child._already_hit = _already_hit.duplicate()
		for connection in hit_landed.get_connections():
			child.hit_landed.connect(connection.callable)


func _spawn_feedback(effect: PackedScene, sound: SoundCue, at: Vector2) -> void:
	EffectSpawner.spawn(self, effect, {"position": at, "direction": direction})
	AudioManager.play_sfx(sound, at)


# --- Returning projectiles --------------------------------------------------

func get_range() -> float:
	return data.speed * data.lifetime


func _process_returning(delta: float) -> void:
	_age += delta
	var from := global_position
	var to: Vector2
	if current_pass == Pass.OUTBOUND:
		var length := get_range()
		_out_distance = minf(_out_distance + data.speed * delta, length)
		var t := _out_distance / length if length > 0.0 else 1.0
		to = fired_from + direction * _out_distance \
			+ direction.orthogonal() * data.curve_amount * length * 0.5 * sin(PI * t)
		if data.stops_at_walls:
			var ray := PhysicsRayQueryParameters2D.create(from, to, GameRules.current().wall_mask)
			var wall := get_world_2d().direct_space_state.intersect_ray(ray)
			if not wall.is_empty():
				to = wall.position
				_out_distance = length
		_hit_targets_between(from, to)
		if is_queued_for_deletion():
			return
		global_position = to
		if current_pass == Pass.OUTBOUND and _out_distance >= length:
			_start_return()
	else:
		var caster = damage_template.source    # untyped: it may have been freed
		if not is_instance_valid(caster) or not caster is Node2D:
			_expire()
			return
		var home: Vector2 = caster.global_position
		_return_base = _return_base.move_toward(home, data.speed * delta)
		var left := _return_base.distance_to(home)
		var u := clampf(1.0 - left / maxf(_return_length, 1.0), 0.0, 1.0)
		var heading := (home - _return_base).normalized()
		to = _return_base + heading.orthogonal() * data.curve_amount * _return_length * 0.5 * sin(PI * u)
		_hit_targets_between(from, to)
		if is_queued_for_deletion():
			return
		global_position = to
		if left <= data.radius + 30.0:
			returned.emit()
			queue_free()
			return
	if to != from:
		rotation = (to - from).angle()
	if _age >= data.lifetime + data.return_timeout:
		_expire()


# Turn around: a fresh pass (every target can be hit once more).
func _start_return() -> void:
	if current_pass == Pass.RETURN:
		return
	current_pass = Pass.RETURN
	_already_hit.clear()
	_hits = 0
	_return_base = global_position
	var caster = damage_template.source    # untyped: it may have been freed
	_return_length = global_position.distance_to(caster.global_position) \
		if is_instance_valid(caster) and caster is Node2D else 0.0
	turned_back.emit(global_position)
