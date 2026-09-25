extends Node2D
class_name GroundZone

# Runtime half of GroundZoneData. Lives in the world (not on the caster), so it
# keeps burning after the caster moves on or dies.
#
# Damage is snapshotted when the zone is spawned: a trail laid at level 3
# keeps level-3 damage even if the caster levels up while it burns. That
# keeps zones predictable and makes them easy to replicate later.

var data: GroundZoneData
var source: Node
var direction := Vector2.RIGHT

var _age: float = 0.0
var _tick_timer: float = 0.0
var _tick_amount: float = 0.0
# One attack id for the zone's whole life: meters see one "attack", while
# each tick still applies separately.
var _attack_id: int = 0


static func spawn(context: Node, zone_data: GroundZoneData, at: Vector2, dir: Vector2, from: Node) -> GroundZone:
	var zone := GroundZone.new()
	zone.data = zone_data
	zone.source = from
	zone.direction = dir if dir != Vector2.ZERO else Vector2.RIGHT
	zone._tick_amount = zone_data.tick_damage.evaluate(StatsComponent.find_on(from)) \
		if zone_data.tick_damage != null else 0.0
	zone._attack_id = DamageInfo.new_attack_id()
	zone.z_index = -5    # under characters
	context.get_tree().current_scene.add_child(zone)
	zone.global_position = at
	return zone


func _ready() -> void:
	if data.visual_scene != null:
		var visual := data.visual_scene.instantiate()
		add_child(visual)
		if visual is Node2D:
			visual.rotation = direction.angle()
	# First tick right away: stepping into fire should hurt immediately.
	_tick()


func _physics_process(delta: float) -> void:
	_age += delta
	_tick_timer += delta
	if data.tick_interval > 0.0 and _tick_timer + StatusEffectComponent.TICK_EPSILON >= data.tick_interval:
		_tick_timer -= data.tick_interval
		_tick()
	if _age >= data.duration:
		queue_free()
	elif data.visual_scene == null:
		queue_redraw()


func _tick() -> void:
	if data.shape == null:
		return
	var owner_source := source if is_instance_valid(source) else null
	for hurtbox in Hitbox.query(self, global_position, direction, data.shape, owner_source):
		var info := DamageInfo.create(_tick_amount, owner_source, data.damage_type)
		info.tags = [DamageInfo.TAG_AREA, DamageInfo.TAG_DOT]
		info.label = data.meter_label
		info.attack_id = _attack_id
		info.weight = 0.0
		info.direction = direction
		info.hit_position = hurtbox.global_position
		info.add_status(data.status)
		if _tick_amount > 0.0:
			hurtbox.take_hit(info)
		elif data.status != null and hurtbox.status_component != null:
			hurtbox.status_component.apply(data.status, owner_source, direction)


func _draw() -> void:
	if data == null or data.shape == null:
		return
	var fade := clampf(1.0 - _age / maxf(data.duration, 0.01), 0.0, 1.0)
	var color := data.color
	color.a *= fade
	match data.shape.kind:
		HitShape.Kind.LINE:
			draw_set_transform(Vector2.ZERO, direction.angle())
			draw_rect(Rect2(0, -data.shape.width / 2.0, data.shape.length, data.shape.width), color)
			draw_set_transform(Vector2.ZERO)
		_:
			draw_circle(direction * data.shape.forward_offset, data.shape.radius, color)
