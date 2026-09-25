@tool
extends AbilityData
class_name MelodyPerformanceData

# Performance (Melody's E): a RhythmPhrase; every PERFECT/GOOD note winds
# the Key and pulses `shield_status` to allies within values/pulse_radius.
# Named values:
#   values/pulse_radius
#   values/perfect_shield_strength   shield strength on a PERFECT (1 = full)
#   values/good_shield_strength      shield strength on a GOOD

@export_group("Performance")
@export var phrase: RhythmPhrase
## Shield pulsed per scored note (its shield_amount is the full pulse).
@export var shield_status: StatusEffect


func get_scaling_values() -> Dictionary:
	var result := super()
	if shield_status != null and shield_status.shield_amount != null:
		result["shield_status/shield_amount"] = shield_status.shield_amount
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if phrase == null:
		problems.append("'%s' has no phrase" % id)
	else:
		for problem in phrase.validate():
			problems.append("'%s' %s" % [id, problem])
	if shield_status == null or shield_status.shield_amount == null:
		problems.append("'%s' needs a shield_status with a shield_amount" % id)
	for key in [&"pulse_radius", &"perfect_shield_strength", &"good_shield_strength"]:
		if not values.has(key):
			problems.append("'%s' is missing values/%s" % [id, key])
	return problems
