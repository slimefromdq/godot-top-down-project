extends RangedAttackAbility

# Coin: mark for death.
#
# The throw is a plain RangedAttackAbility skillshot (coin.tres): one
# projectile that stops at the first enemy, low damage, and on_hit_status =
# the mark (data/jose_coin_mark.tres). A miss spends the cooldown like any
# cast. This script owns what the mark MEANS, in one place, by listening to
# Jose's own CombatHooks:
#
#   EXECUTE  hit_dealt: any hit FROM JOSE (every ability, any future one)
#            that leaves a target carrying HIS mark at or below
#            values/execute_threshold of its max HP triggers a real kill: a
#            TRUE-damage DamageInfo labelled "<id>_execute" (coin_execute),
#            sized to get through damage-taken multipliers. It goes through
#            the normal pipeline, so it shows in the damage meter, credits
#            the kill and plays kill feedback. Teammates' hits never reach
#            Jose's hit_dealt, so they can't execute.
#   RESET    status_target_died: a target carrying his mark died, killed by
#            anyone (an execute included): the Coin comes back off cooldown.
#
# Cues: <id>_execute (at the victim), <id>_reset (the coin flips back).

const TAG_EXECUTE := &"execute"


func _ready() -> void:
	super()
	var hooks: CombatHooks = actor.get(&"combat_hooks") if actor != null else null
	if hooks == null:
		return
	hooks.hit_dealt.connect(_on_hit_dealt)
	hooks.status_target_died.connect(_on_status_target_died)


func get_mark() -> StatusEffect:
	return data.on_hit_status


func get_execute_threshold() -> float:
	return data.get_value(&"execute_threshold", get_stats())


func is_marked_by_me(target: Node) -> bool:
	var mark := get_mark()
	var status := _status_of(target)
	return mark != null and status != null and status.has_status_from(mark.id, actor)


func _on_hit_dealt(info: DamageInfo, target: Node) -> void:
	if info.killed or info.has_tag(TAG_EXECUTE) or not is_marked_by_me(target):
		return
	var health := _health_of(target)
	if health == null or health.is_dead():
		return
	if health.current_health > health.max_health * get_execute_threshold():
		return
	# Decided now, applied right after this hit finishes processing, so the
	# meter reads "hit, then execute" and the hit's own reporting completes.
	_execute.call_deferred(target, info.direction)


func _execute(target: Node, direction: Vector2) -> void:
	if not is_instance_valid(target) or not is_instance_valid(actor):
		return
	var health := _health_of(target)
	if health == null or health.is_dead():
		return
	# TRUE damage skips armor; dividing by what gets through covers
	# damage-taken multipliers. Invulnerability and revives (about_to_die)
	# still apply: an execute is a hit, not a delete.
	var through := health.mitigate(1.0, DamageInfo.Type.TRUE)
	if through <= 0.0:
		return
	var info := DamageInfo.create(health.current_health / through + 1.0, actor, DamageInfo.Type.TRUE)
	info.label = StringName(str(ability_id) + "_execute")
	info.tags = [TAG_EXECUTE, DamageInfo.TAG_ABILITY]
	info.weight = 2.0
	info.direction = direction
	info.hit_position = (target as Node2D).global_position if target is Node2D else Vector2.ZERO
	actor.trigger_cue(StringName(str(ability_id) + "_execute"), {
		"position": info.hit_position, "target": target, "direction": direction})
	health.apply_damage(info)


func _on_status_target_died(status_id: StringName, target: Node, _info: DamageInfo) -> void:
	var mark := get_mark()
	if mark == null or status_id != mark.id:
		return
	reset_cooldown()
	actor.trigger_cue(StringName(str(ability_id) + "_reset"), {
		"target": target, "target_position": (target as Node2D).global_position if target is Node2D else actor.global_position})


static func _status_of(target: Node) -> StatusEffectComponent:
	if not is_instance_valid(target):
		return null
	var status = target.get(&"status_component")
	if status is StatusEffectComponent:
		return status
	return target.get_node_or_null(^"Components/StatusComponent") as StatusEffectComponent


static func _health_of(target: Node) -> HealthComponent:
	if not is_instance_valid(target):
		return null
	var health = target.get(&"health_component")
	if health is HealthComponent:
		return health
	return target.get_node_or_null(^"Components/HealthComponent") as HealthComponent
