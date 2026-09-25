extends Ability

# Phoenix Rebirth (ultimate). A revive built entirely on the cancellable
# about_to_die hook:
#
#   1. Avery takes a lethal hit. HealthComponent asks "about to die?" before
#      applying it.
#   2. If this is off cooldown, we cancel the death (she's left at 1 HP),
#      start the cooldown and put her into the rebirth state: stunned (can't
#      act) and invulnerable for rebirth_duration.
#   3. When the rebirth ends she heals to restore_health_ratio of max HP and,
#      if enabled, releases a fire burst around her.
#
# If it's on cooldown, we do nothing and she dies normally. The key does
# nothing but report that it's passive.
#
# Cues: phoenix_rebirth (sequence starts), phoenix_rebirth_end (she rises,
# with context.radius for the burst visuals).

var _reviving := false
var _time_left: float = 0.0


func _ready() -> void:
	super()
	# The actor is set before _ready (see AbilityController.add_ability).
	actor.combat_hooks.about_to_die.connect(_on_about_to_die)


func get_rebirth_data() -> PhoenixRebirthData:
	return data as PhoenixRebirthData


func is_reviving() -> bool:
	return _reviving


func _activate(_target_position: Vector2) -> String:
	return "Passive: triggers when you'd die"


func _on_about_to_die(event: DeathEvent) -> void:
	if _reviving:
		# A second lethal hit during the rebirth (e.g. true damage through
		# invulnerability) is absorbed too, without burning another cooldown.
		event.cancel(1.0, self)
		return
	if event.cancelled or not is_ready():
		return
	var rebirth := get_rebirth_data()
	event.cancel(1.0, self)
	cooldown_remaining = 0.0 if cooldowns_disabled else get_cooldown()
	activated.emit()
	_reviving = true
	_time_left = rebirth.rebirth_duration

	if rebirth.cleanse_on_trigger:
		actor.status_component.clear()
	actor.ability_controller.interrupt()
	actor.health_component.set_invulnerable_for(rebirth.rebirth_duration + rebirth.invulnerable_after)
	if rebirth.rebirth_state != null:
		actor.status_component.apply(rebirth.rebirth_state, actor)
	actor.trigger_cue(&"phoenix_rebirth", {"duration": rebirth.rebirth_duration})


func _physics_process(delta: float) -> void:
	super(delta)
	if not _reviving:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_rise()


func _rise() -> void:
	_reviving = false
	var rebirth := get_rebirth_data()
	var health := actor.health_component
	if rebirth.rebirth_state != null:
		actor.status_component.remove(rebirth.rebirth_state.id)
	var target_hp := health.max_health * rebirth.restore_health_ratio
	health.heal(target_hp - health.current_health, actor, &"phoenix_rebirth")
	var radius := rebirth.hit_shape.get_reach() if rebirth.hit_shape != null else 0.0
	actor.trigger_cue(&"phoenix_rebirth_end", {"radius": radius, "weight": 2.5})
	if rebirth.burst_enabled:
		_burst(rebirth)


func _burst(rebirth: PhoenixRebirthData) -> void:
	if rebirth.hit_shape == null or rebirth.damage == null:
		return
	var amount := rebirth.damage.evaluate(get_stats())
	var attack_id := DamageInfo.new_attack_id()
	for hurtbox in Hitbox.query(actor, actor.global_position, actor.aim_direction, rebirth.hit_shape, actor):
		var away := (hurtbox.global_position - actor.global_position).normalized()
		var info := DamageInfo.create(amount, actor, rebirth.damage_type)
		info.tags = rebirth.tags.duplicate()
		info.tags.append(DamageInfo.TAG_AREA)
		info.label = rebirth.get_label()
		info.attack_id = attack_id
		info.direction = away
		info.hit_position = hurtbox.global_position
		info.knockback = away * rebirth.knockback
		info.weight = 2.5
		info.add_status(rebirth.on_hit_status)
		info.add_status(rebirth.burst_extra_status)
		hurtbox.take_hit(info)
