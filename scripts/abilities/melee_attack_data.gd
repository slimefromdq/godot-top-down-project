@tool
extends AbilityData
class_name MeleeAttackData

# Data for MeleeAttackAbility: a single swing or a combo string.
#
# With no combo_steps, the ability swings once using the base AbilityData
# fields (hit_shape, damage, knockback, on_hit_status, feel_preset). That's
# all a simple basic attack or a CC slash needs.

@export_group("Combo")
## Swings in order. Leave empty for a single swing built from the base fields.
@export var combo_steps: Array[AttackStep] = []
## Off = always use the first step (the combo is optional, per data).
@export var combo_enabled: bool = true
## Seconds after a swing ends before the combo resets to step 1.
@export var combo_reset_time: float = 0.6

@export_group("Swing projectile")
## Launched by every swing whose step doesn't set its own projectile.
@export var swing_projectile: ProjectileData
@export var swing_projectile_damage: ScalingValue
@export var swing_projectile_damage_type: DamageInfo.Type = DamageInfo.Type.MAGIC
@export var swing_projectile_label: StringName = &""
## Spawn point, pixels ahead of the hero along the aim.
@export var projectile_spawn_offset: float = 60.0


func get_step_count() -> int:
	if combo_steps.is_empty():
		return 1
	return combo_steps.size() if combo_enabled else 1


# Step i as a full AttackStep, falling back to the base fields.
func get_step(index: int) -> AttackStep:
	if combo_steps.is_empty():
		var step := AttackStep.new()
		step.hit_shape = hit_shape
		step.damage = damage
		step.knockback = knockback
		step.feel_preset = feel_preset
		step.feel_override = feel_override
		return step
	return combo_steps[clampi(index, 0, combo_steps.size() - 1)]


func get_scaling_values() -> Dictionary:
	var result := super()
	for i in combo_steps.size():
		var step := combo_steps[i]
		if step == null:
			continue
		if step.damage != null:
			result["combo_steps/%d/damage" % (i + 1)] = step.damage
		if step.projectile_damage != null:
			result["combo_steps/%d/projectile_damage" % (i + 1)] = step.projectile_damage
	if swing_projectile_damage != null:
		result["swing_projectile_damage"] = swing_projectile_damage
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if combo_steps.is_empty() and hit_shape == null:
		problems.append("'%s' has no hit_shape and no combo_steps" % id)
	for i in combo_steps.size():
		var step := combo_steps[i]
		if step == null:
			problems.append("'%s' combo step %d is empty" % [id, i + 1])
		elif step.hit_shape == null:
			problems.append("'%s' combo step %d has no hit_shape" % [id, i + 1])
		elif step.has_negative():
			problems.append("'%s' combo step %d has negative values" % [id, i + 1])
	if swing_projectile != null and swing_projectile_damage == null:
		problems.append("'%s' has a swing_projectile but no swing_projectile_damage" % id)
	if combo_reset_time < 0.0 or projectile_spawn_offset < 0.0:
		problems.append("'%s' has negative combo/projectile settings" % id)
	return problems
