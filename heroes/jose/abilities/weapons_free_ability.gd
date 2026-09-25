extends Ability

# Weapons Free: Jose's ultimate, a channel.
#
# The cast itself is short (windup/recovery from the feel preset, so a stun
# during the windup cancels it). When it goes active, the CHANNEL starts and
# runs on its own for zone_duration, outside the cast state machine. That's
# what lets Flourish (another cast) happen mid-channel without ending it.
# During the channel:
#   * a CIRCLE zone follows Jose: the kill box everyone can see;
#   * every tick the auto-fire picks the next enemy inside it (in line of
#     sight), rotating through them, and fires the gun's extra shot at them
#     (RangedAttackAbility.fire_extra_shot: its projectile, damage, muzzles
#     and hit hooks, so the Coin execute works; no ammo, no reload), at the
#     gun's fire rate x values/weapons_free_fire_rate;
#   * the controller is locked: only data.allowed_slots may start; the
#     quiet_slots (the manual primary) fail silently, the rest say so;
#   * Jose walks at channel_move_speed_multiplier.
# A stun (and a silence, per data), death, or the timer ends it. Recasting
# ends it only with recast_ends_channel.
#
# Cues: <id>_start, <id>_shot (context.target, .target_position), <id>_end
# (context.interrupted). Optional music stinger from the data.

## The kill box while channelling, else null.
var zone: GroundZone

var _channeling := false
var _channel_left: float = 0.0
var _shot_timer: float = 0.0
var _last_target_id: int = 0
# Key for the channel's walk slow. The cast uses `self`, and ending the cast
# must not clear the channel's slow.
var _slow_key := RefCounted.new()


func get_weapons_free_data() -> WeaponsFreeData:
	return data as WeaponsFreeData


func get_gun() -> RangedAttackAbility:
	var hero := actor as Hero
	return hero.get_ranged_ability(get_weapons_free_data().gun_slot) if hero != null else null


func is_channeling() -> bool:
	return _channeling


func get_channel_time_left() -> float:
	return maxf(_channel_left, 0.0)


# Seconds between auto-shots right now.
func get_fire_interval() -> float:
	var gun := get_gun()
	if gun == null:
		return INF
	var rate := StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.FIRE_RATE) \
		* data.get_value(&"weapons_free_fire_rate", get_stats())
	return gun.get_ranged_data().get_fire_interval(rate)


func get_block_reason() -> String:
	if is_channeling():
		if get_weapons_free_data().recast_ends_channel:
			end_channel(false)
			return "Ended"
		return "Active"
	return super()


func _is_silent_block(reason: String) -> bool:
	return super(reason) or reason in ["Ended", "Active"]


func _activate(_target_position: Vector2) -> String:
	var wf := get_weapons_free_data()
	if wf == null or wf.zone == null:
		return "No zone"
	if get_gun() == null:
		return "No gun"
	return ""


func _on_active_start() -> void:
	_start_channel()


func _start_channel() -> void:
	var wf := get_weapons_free_data()
	_channeling = true
	_channel_left = wf.zone_duration
	_shot_timer = 0.0
	_last_target_id = 0
	# Not an owned zone: it must outlive this short cast. end_channel() ends it.
	zone = GroundZone.spawn(actor, wf.zone, actor.global_position, cast_direction, actor, wf.zone_duration + 1.0)
	controller.lock_abilities(self, wf.allowed_slots, wf.quiet_slots)
	actor.movement_component.set_action_multiplier(_slow_key, wf.channel_move_speed_multiplier)
	if wf.channel_music != null:
		AudioManager.request_music(self, wf.channel_music, wf.channel_music_priority, wf.channel_music_fade)
	actor.trigger_cue(StringName(str(ability_id) + "_start"), {
		"duration": wf.zone_duration,
		"radius": wf.zone.shape.radius if wf.zone.shape != null else 0.0,
	})


# Stop channelling now. Safe to call when not channelling.
func end_channel(interrupted: bool) -> void:
	if not _channeling:
		return
	_channeling = false
	_channel_left = 0.0
	if is_instance_valid(zone):
		zone.end()
	zone = null
	if controller != null:
		controller.unlock_abilities(self)
	if is_instance_valid(actor):
		actor.movement_component.clear_action_multiplier(_slow_key)
		actor.trigger_cue(StringName(str(ability_id) + "_end"), {"interrupted": interrupted})
	var wf := get_weapons_free_data()
	if wf != null and wf.channel_music != null:
		AudioManager.release_music(self, wf.channel_music_fade)


func _physics_process(delta: float) -> void:
	super(delta)
	if is_channeling():
		_tick_channel(delta)


func _tick_channel(delta: float) -> void:
	var wf := get_weapons_free_data()
	var status := actor.status_component
	if actor.health_component.is_dead() or status.is_stunned() \
			or (wf.silence_interrupts and status.is_silenced()):
		end_channel(true)
		return
	_channel_left -= delta
	if _channel_left <= 0.0:
		end_channel(false)
		return
	# Like the gun's own timer: may sit one tick below zero so the average
	# rate is exact at any tick rate.
	_shot_timer = maxf(_shot_timer - delta, -delta)
	if _shot_timer > StatusEffectComponent.TICK_EPSILON:
		return
	var target := _next_target()
	if target == null:
		return    # stays ready: the first target to show up is shot at once
	_fire_at(target)
	_shot_timer = minf(_shot_timer, 0.0) + get_fire_interval()


# Round-robin over the valid targets, in the zone's (stable) order, starting
# after the last one shot.
func _next_target() -> HurtboxComponent:
	if not is_instance_valid(zone):
		return null
	var candidates: Array[HurtboxComponent] = []
	for hurtbox in zone.get_targets_inside():
		if hurtbox.is_valid_target() and Hitbox.can_hit(actor, hurtbox) and _has_line_of_sight(hurtbox):
			candidates.append(hurtbox)
	if candidates.is_empty():
		return null
	var last := -1
	for i in candidates.size():
		if candidates[i].get_instance_id() == _last_target_id:
			last = i
	return candidates[(last + 1) % candidates.size()]


func _has_line_of_sight(hurtbox: HurtboxComponent) -> bool:
	if not get_weapons_free_data().requires_line_of_sight:
		return true
	var query := PhysicsRayQueryParameters2D.create(actor.global_position, hurtbox.global_position,
		GameRules.current().wall_mask)
	return actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _fire_at(hurtbox: HurtboxComponent) -> void:
	_last_target_id = hurtbox.get_instance_id()
	var direction := (hurtbox.global_position - actor.global_position).normalized()
	get_gun().fire_extra_shot(direction, get_weapons_free_data().shot_label)
	actor.trigger_cue(StringName(str(ability_id) + "_shot"), {
		"direction": direction,
		"target": hurtbox.owner,
		"target_position": hurtbox.global_position,
	})


func _exit_tree() -> void:
	end_channel(true)
	super()
