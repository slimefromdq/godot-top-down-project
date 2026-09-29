extends ChargeAbility

# Crazed Devotion: a bash dash (generic ChargeAbility: every enemy run through
# is cut once) plus the execute rule, decided here from Pike's own hit
# events, like Jose's Coin:
#
#   EXECUTE  a target the dash hit that is left at or below
#            values/execute_threshold + values/execute_per_bleed_stack per
#            stack of Bleeding of its max HP is killed by a TRUE-damage hit
#            labelled "<id>_execute" (sized to get through damage-taken
#            multipliers and shields; invulnerability and revives still apply).
#   CRAZED   any kill by the dash (the cut or the execute) brings it back off
#            cooldown.
#
# Cues: <id>_execute (at the victim), <id>_reset.

const TAG_EXECUTE := &"execute"
const BLEED_ID := &"pike_bleed"


func get_execute_threshold(target: Node) -> float:
	var stacks := 0
	var status := CombatQueries.status_of(target)
	if status != null:
		stacks = status.get_stacks(BLEED_ID)
	return data.get_value(&"execute_threshold", get_stats()) \
		+ data.get_value(&"execute_per_bleed_stack", get_stats()) * stacks


func _on_bash_landed(info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var mine := _bash_id != 0 and info.attack_id == _bash_id
	super(info, hurtbox)
	if not mine:
		return
	var target := ZoneRamp.target_of(hurtbox)
	if info.killed:
		_crazed(target)
		return
	var health := hurtbox.health_component
	if health == null or health.is_dead() or health.current_health > health.max_health * get_execute_threshold(target):
		return
	# After this hit finishes processing, so the meter reads "cut, then execute".
	_execute.call_deferred(target, health, info.direction)


func _execute(target: Node, health: HealthComponent, direction: Vector2) -> void:
	if not is_instance_valid(target) or not is_instance_valid(actor) or health.is_dead():
		return
	var through := health.mitigate(1.0, DamageInfo.Type.TRUE)
	if through <= 0.0:
		return
	var status := CombatQueries.status_of(target)
	var shields := status.get_shield_total() if status != null else 0.0
	var info := DamageInfo.create((health.current_health + shields) / through + 1.0, actor, DamageInfo.Type.TRUE)
	info.label = StringName(str(ability_id) + "_execute")
	info.tags = [TAG_EXECUTE, DamageInfo.TAG_ABILITY]
	info.weight = 2.0
	info.direction = direction
	info.hit_position = (target as Node2D).global_position if target is Node2D else Vector2.ZERO
	actor.trigger_cue(StringName(str(ability_id) + "_execute"), {
		"position": info.hit_position, "target": target, "direction": direction})
	health.apply_damage(info)
	if health.is_dead():
		_crazed(target)


func _crazed(target: Node) -> void:
	reset_cooldown()
	actor.trigger_cue(StringName(str(ability_id) + "_reset"), {
		"target": target, "target_position": (target as Node2D).global_position if target is Node2D else actor.global_position})
