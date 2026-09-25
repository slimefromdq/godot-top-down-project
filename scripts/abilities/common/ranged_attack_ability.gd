extends Ability
class_name RangedAttackAbility

# Generic gun driven by RangedAttackData: the ranged counterpart of
# MeleeAttackAbility. Works in any slot.
#
# Each shot is one cast (feel preset timing, controller buffering, cancel
# windows all apply). The projectile(s) leave at the start of ACTIVE from the
# next muzzle in the cycle. Between shots, a fire-interval timer (from
# shots_per_second and the FIRE_RATE status multiplier) blocks new casts
# quietly, like a cooldown. The ability's own `cooldown` still applies per
# shot if set (0 for most guns).
#
# Ammo and reload live here, not in the controller: they don't block other
# abilities. Everything is public so AI, items and other abilities can drive
# it the same way the player does:
#   get_ammo() / get_max_ammo() / is_reloading() / get_reload_ratio()
#   start_reload() / cancel_reload() / reload_instantly() / add_ammo(n)
#
# Cues (on top of the base <id>_windup/_active/_recovery):
#   <id>_fire          each shot; context.position is the muzzle,
#                      context.muzzle_index / .ammo / .max_ammo
#   <id>_hit           each projectile hit
#   <id>_empty         tried to fire with too little ammo (dry click)
#   <id>_reload_start  context.duration = seconds to full
#   <id>_reload_round  PER_ROUND: one round loaded
#   <id>_reload_end    magazine full
#   <id>_reload_cancel reload stopped early (firing, cancel_reload, death)
#
# Subclass hooks: _build_hit(info, hurtbox) to change a hit before it lands,
# _on_target_hit(info, hurtbox) after, _shot_damage() for the per-projectile
# damage before multipliers.

signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_finished
signal reload_cancelled

## Deterministic spread: seeded from the ability id, so every machine rolls
## the same angles. Reseed it from match state when networking arrives.
var rng := RandomNumberGenerator.new()

var _ammo: int = 0
var _reloading := false
var _reload_elapsed: float = 0.0
var _shot_timer: float = 0.0
var _semi_queued: float = 0.0
var _empty_click_timer: float = 0.0
var _muzzle_index: int = 0


func get_ranged_data() -> RangedAttackData:
	return data as RangedAttackData


func set_data(new_data: AbilityData) -> void:
	super(new_data)
	rng.seed = hash(ability_id)
	_reloading = false
	_ammo = get_max_ammo()


func _ready() -> void:
	super()
	if actor != null:
		actor.health_component.died.connect(cancel_reload)


# --- Public API ----------------------------------------------------------------

func get_ammo() -> int:
	return _ammo


# 0 = infinite magazine.
func get_max_ammo() -> int:
	var ranged := get_ranged_data()
	return ranged.magazine_size if ranged != null else 0


func has_magazine() -> bool:
	return get_max_ammo() > 0


func is_reloading() -> bool:
	return _reloading


# 0..1 progress toward a full magazine (0 when not reloading).
func get_reload_ratio() -> float:
	if not _reloading:
		return 0.0
	var ranged := get_ranged_data()
	var step := ranged.get_reload_time(get_level())
	if ranged.reload_style == RangedAttackData.ReloadStyle.PER_ROUND:
		var partial := _reload_elapsed / step if step > 0.0 else 1.0
		return clampf((_ammo + partial) / float(get_max_ammo()), 0.0, 1.0)
	return clampf(_reload_elapsed / step, 0.0, 1.0) if step > 0.0 else 1.0


# Seconds until the magazine is full (0 when not reloading).
func get_reload_remaining() -> float:
	if not _reloading:
		return 0.0
	var ranged := get_ranged_data()
	var step := ranged.get_reload_time(get_level())
	if ranged.reload_style == RangedAttackData.ReloadStyle.PER_ROUND:
		return maxf(step * (get_max_ammo() - _ammo) - _reload_elapsed, 0.0)
	return maxf(step - _reload_elapsed, 0.0)


# Seconds between shots right now (after FIRE_RATE multipliers).
func get_fire_interval() -> float:
	return get_ranged_data().get_fire_interval(
		StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.FIRE_RATE))


# Begin reloading. False if there's nothing to reload, it's already
# reloading, or the hero is dead.
func start_reload() -> bool:
	if not has_magazine() or _reloading or _ammo >= get_max_ammo():
		return false
	if actor == null or actor.health_component.is_dead():
		return false
	_reloading = true
	_reload_elapsed = 0.0
	var duration := get_reload_remaining()
	reload_started.emit(duration)
	actor.trigger_cue(StringName(str(ability_id) + "_reload_start"), {"duration": duration, "ability": ability_id})
	return true


func cancel_reload() -> void:
	if not _reloading:
		return
	_reloading = false
	_reload_elapsed = 0.0
	reload_cancelled.emit()
	if is_instance_valid(actor):
		actor.trigger_cue(StringName(str(ability_id) + "_reload_cancel"), {"ability": ability_id})


# Fill the magazine now (a dash that reloads, a pickup). Ends any reload.
func reload_instantly() -> void:
	if not has_magazine():
		return
	var changed := _ammo != get_max_ammo()
	_ammo = get_max_ammo()
	if _reloading:
		_finish_reload()
	elif changed:
		ammo_changed.emit(_ammo, get_max_ammo())
		actor.trigger_cue(StringName(str(ability_id) + "_reload_end"), {"ability": ability_id})


# Add rounds (clamped to the magazine). Filling it ends a reload.
func add_ammo(amount: int) -> void:
	if not has_magazine() or amount <= 0:
		return
	_ammo = mini(_ammo + amount, get_max_ammo())
	if _reloading and _ammo >= get_max_ammo():
		_finish_reload()
	else:
		ammo_changed.emit(_ammo, get_max_ammo())


func repeats_while_held(slot_default: bool) -> bool:
	if uses_charge():
		return false
	var ranged := get_ranged_data()
	if ranged == null:
		return slot_default
	return ranged.fire_mode == RangedAttackData.FireMode.AUTO


# --- Cast ------------------------------------------------------------------------

func get_block_reason() -> String:
	var reason := super()
	if reason != "":
		return reason
	var ranged := get_ranged_data()
	if ranged == null:
		return "No ranged data"
	if _shot_timer > StatusEffectComponent.TICK_EPSILON:
		if ranged.fire_mode == RangedAttackData.FireMode.SEMI:
			_semi_queued = ranged.semi_input_buffer
		return "Firing"
	if has_magazine() and _ammo < ranged.ammo_per_shot:
		if _reloading:
			return "Reloading"
		if _empty_click_timer <= 0.0:
			_empty_click_timer = get_fire_interval()
			actor.trigger_cue(StringName(str(ability_id) + "_empty"), {"ability": ability_id})
		if ranged.auto_reload_when_empty:
			start_reload()
			return "Reloading"
		return "Empty"
	if _reloading and ranged.reload_style == RangedAttackData.ReloadStyle.FULL:
		return "Reloading"
	return ""


func _is_silent_block(reason: String) -> bool:
	return super(reason) or reason in ["Firing", "Reloading", "Empty"]


func _activate(_target_position: Vector2) -> String:
	var ranged := get_ranged_data()
	if ranged == null or ranged.projectile == null:
		return "No projectile"
	# PER_ROUND reloads are interrupted by firing (we have a round loaded).
	if _reloading:
		cancel_reload()
	_semi_queued = 0.0
	# A charged shot's interval starts when it's released, not pressed.
	if not uses_charge():
		_start_shot_interval()
	return ""


func _on_charge_released(_ratio: float, _perfect: bool) -> void:
	_start_shot_interval()


# The timer may sit up to one tick below zero; carrying that overflow into
# the next interval keeps the average rate exact at any tick rate (8 shots/s
# at 60 Hz alternates 7- and 8-tick gaps instead of always waiting 8).
func _start_shot_interval() -> void:
	_shot_timer = minf(_shot_timer, 0.0) + get_fire_interval()


func _on_active_start() -> void:
	_fire()


func _fire() -> void:
	var ranged := get_ranged_data()
	var muzzle := Vector2.ZERO
	var muzzle_index := 0
	if not ranged.muzzles.is_empty():
		muzzle_index = _muzzle_index % ranged.muzzles.size()
		muzzle = ranged.muzzles[muzzle_index]
		_muzzle_index = (muzzle_index + 1) % ranged.muzzles.size()
	var aim := cast_direction if cast_direction != Vector2.ZERO else actor.aim_direction
	var origin := actor.global_position + muzzle.rotated(aim.angle())
	var count := maxi(ranged.projectiles_per_shot, 1)
	var damage := _shot_damage() * _damage_multiplier()
	for i in count:
		var direction := aim.rotated(deg_to_rad(_spread_angle(i, count)))
		var template := DamageInfo.create(damage, actor, ranged.damage_type)
		template.tags = ranged.tags.duplicate()
		if was_perfect_release():
			template.tags.append(&"perfect")
		template.label = ranged.get_label()
		template.weight = current_feel.weight if current_feel != null else 1.0
		template.feel = current_feel
		template.add_status(ranged.on_hit_status)
		var projectile := Projectile.fire(actor, ranged.projectile, origin, direction, template)
		projectile.hit_modifier = _modify_hit
		projectile.hit_landed.connect(_on_projectile_hit)

	if has_magazine():
		_ammo = maxi(_ammo - ranged.ammo_per_shot, 0)
		ammo_changed.emit(_ammo, get_max_ammo())
	actor.trigger_cue(StringName(str(ability_id) + "_fire"), {
		"position": origin,
		"direction": aim,
		"ability": ability_id,
		"muzzle_index": muzzle_index,
		"ammo": _ammo,
		"max_ammo": get_max_ammo(),
		"charge_ratio": get_charge_ratio(),
		"perfect": was_perfect_release(),
	})
	if has_magazine() and _ammo < ranged.ammo_per_shot and ranged.auto_reload_when_empty:
		start_reload()


# Degrees off the aim for projectile i of `count`.
func _spread_angle(i: int, count: int) -> float:
	var ranged := get_ranged_data()
	var spread := ranged.spread_degrees
	if spread <= 0.0:
		return 0.0
	if ranged.spread_pattern == RangedAttackData.SpreadPattern.EVEN:
		return 0.0 if count <= 1 else lerpf(-spread / 2.0, spread / 2.0, float(i) / (count - 1))
	return rng.randf_range(-spread / 2.0, spread / 2.0)


# Damage of one projectile before status/perfect multipliers. With a charge,
# lerps `damage` -> values/damage_full by the released ratio.
func _shot_damage() -> float:
	if uses_charge():
		return data.get_charged_value(&"damage", get_stats(), get_charge_ratio())
	return data.damage.evaluate(get_stats()) if data.damage != null else 0.0


func _damage_multiplier() -> float:
	var result := StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE)
	# Optional named value: a perfect release multiplies the damage.
	if was_perfect_release() and data.values.has(&"perfect_damage_multiplier"):
		result *= data.get_value(&"perfect_damage_multiplier", get_stats())
	return result


func _modify_hit(info: DamageInfo, hurtbox: HurtboxComponent, travelled: float) -> DamageInfo:
	var ranged := get_ranged_data()
	if ranged != null:
		info.amount *= ranged.get_falloff_multiplier(travelled)
	return _build_hit(info, hurtbox)


func _on_projectile_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(hurtbox):
		return
	actor.trigger_cue(StringName(str(ability_id) + "_hit"), {
		"position": hurtbox.global_position,
		"direction": info.direction,
		"target": hurtbox.owner,
		"weight": info.weight,
		"damage": info.final_amount,
	})
	_on_target_hit(info, hurtbox)


# Override to change a hit before it lands (or return null to skip it).
func _build_hit(info: DamageInfo, _hurtbox: HurtboxComponent) -> DamageInfo:
	return info


# Override to react after a hit landed (info.final_amount is set).
func _on_target_hit(_info: DamageInfo, _hurtbox: HurtboxComponent) -> void:
	pass


# --- Simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	_shot_timer = maxf(_shot_timer - delta, -delta)
	if _empty_click_timer > 0.0:
		_empty_click_timer -= delta
	if _reloading:
		_advance_reload(delta)
	if _semi_queued > 0.0:
		_semi_queued -= delta
		if _shot_timer <= StatusEffectComponent.TICK_EPSILON and actor != null:
			_semi_queued = 0.0
			try_activate(actor.aim_point)


func _advance_reload(delta: float) -> void:
	var ranged := get_ranged_data()
	var step := ranged.get_reload_time(get_level())
	_reload_elapsed += delta
	if ranged.reload_style == RangedAttackData.ReloadStyle.FULL:
		if _reload_elapsed + StatusEffectComponent.TICK_EPSILON >= step:
			_ammo = get_max_ammo()
			_finish_reload()
		return
	while _reloading and _reload_elapsed + StatusEffectComponent.TICK_EPSILON >= step:
		_reload_elapsed -= step
		_ammo = mini(_ammo + 1, get_max_ammo())
		if _ammo >= get_max_ammo():
			_finish_reload()
		else:
			ammo_changed.emit(_ammo, get_max_ammo())
			actor.trigger_cue(StringName(str(ability_id) + "_reload_round"), {"ability": ability_id, "ammo": _ammo})


func _finish_reload() -> void:
	_reloading = false
	_reload_elapsed = 0.0
	ammo_changed.emit(_ammo, get_max_ammo())
	reload_finished.emit()
	actor.trigger_cue(StringName(str(ability_id) + "_reload_end"), {"ability": ability_id})
