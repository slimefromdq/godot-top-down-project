extends Ability

# Tide: place a whirlpool at the cursor (clamped to cast_range). For
# tide_duration the zone pulls enemies toward its centre with a blend
# compel (they can struggle out slowly), then it detonates for AoE magic
# damage via Projectile.explode_at. The circle is the telegraph.
#
# The tide is placed, not channelled: it keeps going if she moves or dies.
# Cues: tide_start (context.position, .radius, .duration), tide_detonate.

var _center := Vector2.ZERO
var _zone: GroundZone
var _time_left: float = 0.0


func get_tide_data() -> CosmoTideData:
	return data as CosmoTideData


func get_center() -> Vector2:
	return _center


func is_pulling() -> bool:
	return _time_left > 0.0


func _activate(target_position: Vector2) -> String:
	var tide := get_tide_data()
	if tide == null or tide.zone == null or tide.detonation == null:
		return "No tide"
	var reach := data.get_value(&"cast_range", get_stats())
	_center = actor.global_position + (target_position - actor.global_position).limit_length(reach)
	return ""


func _on_active_start() -> void:
	var tide := get_tide_data()
	var duration := data.get_value(&"tide_duration", get_stats())
	if is_instance_valid(_zone):
		_zone.end()
	_zone = GroundZone.spawn(actor, tide.zone, _center, cast_direction, actor, duration + 0.1)
	_time_left = duration
	actor.trigger_cue(StringName(str(ability_id) + "_start"), {"position": _center,
		"radius": tide.zone.shape.radius if tide.zone.shape != null else 0.0, "duration": duration})


func _physics_process(delta: float) -> void:
	super(delta)
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_detonate()


func _detonate() -> void:
	var template := DamageInfo.create(data.damage.evaluate(get_stats())
		* StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE), actor, data.damage_type)
	template.label = data.get_label()
	template.tags = data.tags.duplicate()
	template.weight = 1.5
	Projectile.explode_at(actor, get_tide_data().detonation, _center, cast_direction, template)
	if is_instance_valid(_zone):
		_zone.end()
	_zone = null
	actor.trigger_cue(StringName(str(ability_id) + "_detonate"), {"position": _center})
