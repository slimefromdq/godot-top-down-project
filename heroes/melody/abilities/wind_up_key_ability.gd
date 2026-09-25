extends Ability

# Wind-Up Key (RMB): crank an ally's key, release to wind them up.
#
# All the targeting is data: ally_targeting (allies only; allow_self off),
# tether_range, and the Charge group (hold to crank, slower walk, release).
# On release the ally gets data.on_hit_status (move_speed / fire_rate
# multipliers with fade_multipliers, so it runs down like a spring) at
# strength lerp(values/min_strength, 1, charge ratio).
#
# ENCORE (Master Key), asked for on release: the same wind-up also jumps to
# every ally within encore_value(master_key_radius, strength) of the
# target, at the same strength.
#
# Cues: <id>_wind (context.target, .strength), <id>_master_key.

const KEY := preload("res://heroes/melody/abilities/melody_key.gd")

var _encore_strength: float = -1.0


func _activate(_target_position: Vector2) -> String:
	if data.on_hit_status == null:
		return "No status"
	_encore_strength = -1.0
	return ""


func _on_charge_released(_ratio: float, _perfect: bool) -> void:
	var key := KEY.find_on(actor)
	_encore_strength = key.consume_encore(self) if key != null else -1.0


func get_wind_strength() -> float:
	return lerpf(data.get_value(&"min_strength", get_stats()), 1.0, get_charge_ratio())


func _on_active_start() -> void:
	if not is_instance_valid(cast_ally):
		return
	var strength := get_wind_strength()
	var targets: Array[Node2D] = [cast_ally]
	if _encore_strength >= 0.0:
		var radius := KEY.encore_value(data, &"master_key_radius", _encore_strength)
		for hurtbox in Hitbox.query(actor, cast_ally.global_position, Vector2.RIGHT, HitShape.circle(radius),
				actor, Hitbox.Affects.ALLIES):
			var ally := hurtbox.owner as Node2D
			if ally == null or targets.has(ally):
				continue
			if ally == actor and not data.ally_targeting.allow_self:
				continue
			targets.append(ally)
		actor.trigger_cue(StringName(str(ability_id) + "_master_key"), {"position": cast_ally.global_position,
			"target": cast_ally, "target_position": cast_ally.global_position, "radius": radius})
	for ally in targets:
		var status: StatusEffectComponent = ally.get(&"status_component")
		if status != null:
			status.apply(data.on_hit_status, actor, cast_direction, strength)
		actor.trigger_cue(StringName(str(ability_id) + "_wind"), {"position": ally.global_position,
			"target": ally, "target_position": ally.global_position, "strength": strength})
