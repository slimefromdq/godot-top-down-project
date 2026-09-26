@tool
extends AbilityData
class_name RangedAttackData

# Data for RangedAttackAbility: a gun. Works in any slot (a primary rifle, a
# shotgun ability, a charged precision shot on RMB).
#
# Damage per projectile is the inherited `damage` ScalingValue (with
# charge_enabled, lerped toward values/damage_full by the charge ratio). The
# flight itself is `projectile` (ProjectileData), shared with any ability.
#
# Each shot is one cast, timed by `feel_preset` like any other ability, so
# keep a gun's preset short (small windup, recovery cancellable early).
# `shots_per_second` gates how often a new shot may start; the FIRE_RATE
# status multiplier scales it.

enum FireMode {
	AUTO,   ## Holding the key keeps firing.
	SEMI,   ## One shot per press; a press slightly early is buffered.
}

enum SpreadPattern {
	RANDOM, ## Each projectile gets a random angle within the spread.
	EVEN,   ## Projectiles fan out evenly across the spread (a shotgun wall).
}

enum ReloadStyle {
	FULL,       ## The whole magazine after reload_time.
	PER_ROUND,  ## One round every reload_time; firing interrupts it (revolver, shotgun).
	REGEN,      ## Rounds come back one every regen_interval, firing or not. No reloading (R does nothing).
}

@export_group("Projectile")
@export var projectile: ProjectileData
@export var projectiles_per_shot: int = 1
## Total cone in degrees. 0 = dead accurate.
@export var spread_degrees: float = 0.0
@export var spread_pattern: SpreadPattern = SpreadPattern.RANDOM
## Extra random spread (total degrees) at full walking speed, scaled by how
## fast the shooter is moving. 0 = off: standing still and walking are
## equally accurate.
@export var moving_spread_degrees: float = 0.0
## charge_enabled only: fired instead of `projectile` on a perfect release
## (a thicker tracer, a faster bolt). Empty = same projectile.
@export var perfect_projectile: ProjectileData
## Spawn points relative to the aim: x = forward, y = to the right. Shots
## cycle through them in order (alternating dual pistols = two entries).
@export var muzzles: Array[Vector2] = [Vector2(60, 0)]

@export_group("Fire")
@export var fire_mode: FireMode = FireMode.AUTO
## Shots per second before status multipliers (FIRE_RATE).
@export var shots_per_second: float = 4.0
## SEMI only: a press up to this many seconds before the next shot is
## allowed still fires (fast clicking isn't eaten).
@export var semi_input_buffer: float = 0.12

@export_group("Ammo")
## Rounds per magazine. 0 = infinite, never reloads.
@export var magazine_size: int = 0
@export var ammo_per_shot: int = 1

@export_group("Reload")
## FULL: seconds for the whole magazine. PER_ROUND: seconds per round.
@export var reload_time: float = 1.5
## Added per level above 1 (negative = faster reloads later).
@export var reload_per_level: float = 0.0
@export var auto_reload_when_empty: bool = true
@export var reload_style: ReloadStyle = ReloadStyle.FULL
## REGEN only: seconds per regenerated round.
@export var regen_interval: float = 2.0

@export_group("Damage falloff")
## Full damage up to falloff_start pixels from the muzzle, then a linear drop
## to falloff_min_multiplier at falloff_end. All 0 = no falloff.
@export var falloff_start: float = 0.0
@export var falloff_end: float = 0.0
@export_range(0.0, 1.0, 0.05) var falloff_min_multiplier: float = 0.0


func has_magazine() -> bool:
	return magazine_size > 0


func get_reload_time(level: int) -> float:
	return maxf(reload_time + reload_per_level * (level - 1), 0.0)


# Seconds for a reload from empty to full.
func get_full_reload_time(level: int) -> float:
	if reload_style == ReloadStyle.REGEN:
		return regen_interval * magazine_size
	if reload_style == ReloadStyle.PER_ROUND:
		return get_reload_time(level) * magazine_size
	return get_reload_time(level)


func get_fire_interval(fire_rate_multiplier: float = 1.0) -> float:
	var rate := shots_per_second * fire_rate_multiplier
	return 1.0 / rate if rate > 0.0 else INF


func has_falloff() -> bool:
	return falloff_end > falloff_start


func get_falloff_multiplier(distance: float) -> float:
	if not has_falloff() or distance <= falloff_start:
		return 1.0
	var t := clampf((distance - falloff_start) / (falloff_end - falloff_start), 0.0, 1.0)
	return lerpf(1.0, falloff_min_multiplier, t)


func get_shots_per_magazine() -> int:
	return magazine_size / maxi(ammo_per_shot, 1) if has_magazine() else 0


func get_range() -> float:
	if ability_range > 0.0:
		return ability_range
	return projectile.get_range() if projectile != null else 0.0


# Fire rate, magazine, reload and DPS for the balance CSV. DPS assumes every
# projectile hits at full damage (no falloff, no charge).
#   burst_dps      firing continuously, ignoring reloads
#   sustained_dps  including a full reload every magazine
func get_balance_metrics(level: int, weapon: float, magic: float) -> Dictionary:
	var per_shot := damage.evaluate_at(level, weapon, magic) * projectiles_per_shot if damage != null else 0.0
	var burst := per_shot * shots_per_second
	var sustained := burst
	var shots := get_shots_per_magazine()
	if reload_style == ReloadStyle.REGEN and regen_interval > 0.0:
		# Rounds come back one per interval: that's the long-run fire rate.
		sustained = minf(burst, per_shot * ammo_per_shot / regen_interval) if ammo_per_shot > 0 else burst
	elif has_magazine() and shots > 0 and shots_per_second > 0.0:
		var cycle := shots / shots_per_second + get_full_reload_time(level)
		sustained = per_shot * shots / cycle if cycle > 0.0 else burst
	return {
		"shots_per_second": shots_per_second,
		"magazine_size": magazine_size,
		"reload_time": get_full_reload_time(level),
		"damage_per_shot": per_shot,
		"burst_dps": burst,
		"sustained_dps": sustained,
	}


func validate() -> PackedStringArray:
	var problems := super()
	if projectile == null:
		problems.append("'%s' has no projectile" % id)
	else:
		for problem in projectile.validate():
			problems.append("'%s' %s" % [id, problem])
	if damage == null:
		problems.append("'%s' has no damage" % id)
	if shots_per_second <= 0.0:
		problems.append("'%s' shots_per_second must be above 0" % id)
	if projectiles_per_shot < 1:
		problems.append("'%s' projectiles_per_shot must be at least 1" % id)
	if perfect_projectile != null and perfect_projectile.has_negative():
		problems.append("'%s' perfect_projectile has negative values" % id)
	if spread_degrees < 0.0 or moving_spread_degrees < 0.0 or semi_input_buffer < 0.0 or reload_time < 0.0:
		problems.append("'%s' has negative spread/buffer/reload" % id)
	if magazine_size < 0 or ammo_per_shot < 1:
		problems.append("'%s' magazine_size must be >= 0 and ammo_per_shot >= 1" % id)
	elif has_magazine() and ammo_per_shot > magazine_size:
		problems.append("'%s' ammo_per_shot is larger than the magazine" % id)
	if reload_style == ReloadStyle.REGEN and regen_interval <= 0.0:
		problems.append("'%s' REGEN needs a positive regen_interval" % id)
	if falloff_start < 0.0 or falloff_end < 0.0 or (falloff_end > 0.0 and falloff_end < falloff_start):
		problems.append("'%s' falloff range is invalid" % id)
	return problems
