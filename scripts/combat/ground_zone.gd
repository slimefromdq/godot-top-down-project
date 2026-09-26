extends Node2D
class_name GroundZone

# Runtime half of GroundZoneData. Lives in the world (not on the caster), so it
# keeps burning after the caster moves on or dies (unless its data says it
# follows / ends with its owner).
#
# Damage is snapshotted when the zone is spawned: a trail laid at level 3
# keeps level-3 damage even if the caster levels up while it burns. That
# keeps zones predictable and makes them easy to replicate later.
#
# Every physics tick the zone works out who is inside (by the data's
# `affects` rule) and reports changes; every tick_interval it "ticks" everyone
# inside. Ability scripts can react per target without subclassing:
#   target_entered(hurtbox)   started being inside
#   target_ticked(hurtbox)    a tick landed on them (after damage/statuses)
#   target_exited(hurtbox)    left, died, or the zone ended
#
# Ramp (data.ramp_per_tick): damage per target grows with every tick it takes,
# shared with the owner's other zones of the same ramp key (see ZoneRamp).
# Leftover (data.leaves_zone): a zone spawned where this one ended.

signal target_entered(hurtbox: HurtboxComponent)
signal target_ticked(hurtbox: HurtboxComponent)
signal target_exited(hurtbox: HurtboxComponent)
## The zone is about to disappear (duration, owner death, or end()).
signal ended

var data: GroundZoneData
var source: Node
var direction := Vector2.RIGHT
## Seconds this zone lasts (data.duration unless overridden at spawn).
var duration: float = 0.0

var _age: float = 0.0
var _tick_timer: float = 0.0
var _tick_amount: float = 0.0
# One attack id for the zone's whole life: meters see one "attack", while
# each tick still applies separately.
var _attack_id: int = 0
var _inside: Dictionary = {}    # hurtbox instance id -> HurtboxComponent
var _ended := false


static func spawn(context: Node, zone_data: GroundZoneData, at: Vector2, dir: Vector2, from: Node,
		duration_override: float = -1.0) -> GroundZone:
	var zone := GroundZone.new()
	zone.data = zone_data
	zone.source = from
	zone.direction = dir if dir != Vector2.ZERO else Vector2.RIGHT
	zone.duration = duration_override if duration_override >= 0.0 else zone_data.duration
	if zone_data.max_duration > 0.0:
		zone.duration = minf(zone.duration, zone_data.max_duration)
	zone._tick_amount = zone_data.tick_damage.evaluate(StatsComponent.find_on(from)) \
		if zone_data.tick_damage != null else 0.0
	zone._attack_id = DamageInfo.new_attack_id()
	zone.z_index = zone_data.draw_z_index    # under characters
	# Place it BEFORE it enters the tree: _ready runs the first tick, which
	# must happen where the zone is, not at the world origin. (The scene root
	# sits at the origin, so position == global here.)
	zone.position = at
	zone._follow_owner()
	context.get_tree().current_scene.add_child(zone)
	zone.global_position = at if not zone_data.follow_owner else zone.global_position
	return zone


func _ready() -> void:
	if data.visual_scene != null:
		var visual := data.visual_scene.instantiate()
		add_child(visual)
		if visual is Node2D:
			visual.rotation = direction.angle()
	# First tick right away: stepping into fire should hurt immediately.
	_update_inside()
	_touch_ramps()
	_tick()


func is_inside(hurtbox: HurtboxComponent) -> bool:
	return hurtbox != null and _inside.has(hurtbox.get_instance_id())


func get_targets_inside() -> Array[HurtboxComponent]:
	var result: Array[HurtboxComponent] = []
	for hurtbox in _inside.values():
		if is_instance_valid(hurtbox):
			result.append(hurtbox)
	return result


func get_age() -> float:
	return _age


# End now: everyone inside "exits" (losing status_while_inside), then free.
func end() -> void:
	if _ended:
		return
	_ended = true
	for key in _inside.keys():
		_exit(key)
	ended.emit()
	if data.leaves_zone != null and is_inside_tree():
		GroundZone.spawn(self, data.leaves_zone, global_position, direction, _owner_source())
	queue_free()


# Ramping zones: everyone inside is "still in the gas" this physics tick.
func _touch_ramps() -> void:
	if not data.has_ramp():
		return
	var key := data.get_ramp_key()
	for hurtbox in get_targets_inside():
		var target := ZoneRamp.target_of(hurtbox)
		ZoneRamp.touch(_owner_source(), key, target, data.ramp_reset_after)
		if data.ramp_starts_full:
			ZoneRamp.raise_steps(_owner_source(), key, target,
				ZoneRamp.steps_to_max(data.ramp_per_tick, data.ramp_max))


func _physics_process(delta: float) -> void:
	if _ended:
		return
	if data.ends_if_owner_dies and StatusEffectComponent.is_actor_gone(source):
		end()
		return
	_age += delta
	_follow_owner()
	_update_inside()
	_touch_ramps()
	_tick_timer += delta
	if data.tick_interval > 0.0 and _tick_timer + StatusEffectComponent.TICK_EPSILON >= data.tick_interval:
		_tick_timer -= data.tick_interval
		_tick()
	if _age >= duration:
		end()
	elif data.visual_scene == null:
		queue_redraw()


func _follow_owner() -> void:
	var owner_2d := source as Node2D
	if owner_2d == null or not is_instance_valid(owner_2d):
		return
	if data.follow_owner:
		global_position = owner_2d.global_position
	if data.face_aim:
		var aim = owner_2d.get(&"aim_direction")
		if aim is Vector2 and aim != Vector2.ZERO:
			direction = aim.normalized()
			for child in get_children():
				if child is Node2D:
					child.rotation = direction.angle()


func _owner_source() -> Node:
	return source if is_instance_valid(source) else null


func _update_inside() -> void:
	if data.shape == null:
		return
	var now := {}
	for hurtbox in Hitbox.query(self, global_position, direction, data.shape, _owner_source(), data.affects):
		now[hurtbox.get_instance_id()] = hurtbox
	for key in _inside.keys():
		if not now.has(key):
			_exit(key)
	for key in now:
		if not _inside.has(key):
			_inside[key] = now[key]
			# Auras apply on entry, not at the next tick; damage waits for it.
			var hurtbox: HurtboxComponent = now[key]
			if data.status_while_inside != null and hurtbox.status_component != null:
				hurtbox.status_component.apply(data.status_while_inside, _status_source(), direction)
			target_entered.emit(hurtbox)


func _exit(key: int) -> void:
	# Untyped until checked: the target may have been freed while inside.
	var node = _inside.get(key)
	_inside.erase(key)
	if not is_instance_valid(node):
		return
	var hurtbox := node as HurtboxComponent
	if data.status_while_inside != null and hurtbox.status_component != null:
		hurtbox.status_component.remove_from(data.status_while_inside.id, _status_source())
	target_exited.emit(hurtbox)


# Who the zone's statuses come from: its owner, or the zone itself
# (statuses_from_zone: a pull toward the centre).
func _status_source() -> Node:
	return self if data.statuses_from_zone else _owner_source()


func _tick() -> void:
	var owner_source := _owner_source()
	var status_source := _status_source()
	for hurtbox in get_targets_inside():
		if not hurtbox.is_valid_target():
			continue
		var hittable := Hitbox.can_hit(owner_source, hurtbox)
		if _tick_amount > 0.0 and hittable:
			var amount := _tick_amount
			var ramp_target: Node = null
			if data.has_ramp():
				ramp_target = ZoneRamp.target_of(hurtbox)
				amount *= ZoneRamp.multiplier(owner_source, data.get_ramp_key(), ramp_target,
					data.ramp_per_tick, data.ramp_max)
			var info := DamageInfo.create(amount, owner_source, data.damage_type)
			info.tags = [DamageInfo.TAG_AREA, DamageInfo.TAG_DOT]
			info.label = data.meter_label
			info.attack_id = _attack_id
			info.weight = 0.0
			info.direction = direction
			info.hit_position = hurtbox.global_position
			if not data.statuses_from_zone:
				info.add_status(data.status)
				info.add_status(data.status_while_inside)
			hurtbox.take_hit(info)
			if ramp_target != null:
				ZoneRamp.add_step(owner_source, data.get_ramp_key(), ramp_target)
		if (not hittable or _tick_amount <= 0.0 or data.statuses_from_zone) \
				and is_instance_valid(hurtbox) and hurtbox.status_component != null and hurtbox.is_valid_target():
			hurtbox.status_component.apply(data.status, status_source, direction)
			hurtbox.status_component.apply(data.status_while_inside, status_source, direction)
		if is_instance_valid(hurtbox):
			target_ticked.emit(hurtbox)


func _exit_tree() -> void:
	# Freed without end() (map change): don't leave auras behind.
	if not _ended:
		_ended = true
		for key in _inside.keys():
			_exit(key)


func _draw() -> void:
	if data == null or data.shape == null:
		return
	var fade := clampf(1.0 - _age / maxf(duration, 0.01), 0.0, 1.0) if not is_inf(duration) else 1.0
	# Zones that follow their owner are "auras": keep them visible.
	if data.follow_owner:
		fade = maxf(fade, 0.6)
	var color := data.color
	color.a *= fade
	var shape := data.shape
	var origin := direction * shape.forward_offset
	match shape.kind:
		HitShape.Kind.LINE:
			draw_set_transform(Vector2.ZERO, direction.angle())
			draw_rect(Rect2(shape.forward_offset, -shape.width / 2.0, shape.length, shape.width), color)
			draw_set_transform(Vector2.ZERO)
		HitShape.Kind.ARC:
			var half := deg_to_rad(shape.arc_degrees) / 2.0
			var points := PackedVector2Array([origin])
			for i in 17:
				points.append(origin + direction.rotated(lerpf(-half, half, i / 16.0)) * shape.radius)
			draw_colored_polygon(points, color)
			if data.outline_color.a > 0.0:
				points.append(origin)
				draw_polyline(points, data.outline_color, data.outline_width, true)
		_:
			draw_circle(origin, shape.radius, color)
			if data.outline_color.a > 0.0:
				draw_arc(origin, shape.radius, 0.0, TAU, 64, data.outline_color, data.outline_width, true)
