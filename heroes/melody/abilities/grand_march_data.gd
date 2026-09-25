@tool
extends AbilityData
class_name MelodyGrandMarchData

# Grand March (Melody's ultimate). Named values:
#   values/gather_radius           allies within it at cast join the parade
#   values/march_duration          seconds
#   values/perfect_extension       seconds added per PERFECT note
#   values/perfect_shield_strength / values/good_shield_strength

@export_group("Grand March")
@export var march_phrase: RhythmPhrase
## On followers: a follow-trail, breakable compel.
@export var formation_status: StatusEffect
## On Melody and the formation: the move-speed buff.
@export var speed_status: StatusEffect
## Pulsed to Melody and the formation on scored notes.
@export var shield_status: StatusEffect
## March notes also wind the Key.
@export var notes_add_turns: bool = false


func get_scaling_values() -> Dictionary:
	var result := super()
	if shield_status != null and shield_status.shield_amount != null:
		result["shield_status/shield_amount"] = shield_status.shield_amount
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if march_phrase == null:
		problems.append("'%s' has no march_phrase" % id)
	else:
		for problem in march_phrase.validate():
			problems.append("'%s' %s" % [id, problem])
	if formation_status == null or not (formation_status.compel_enabled and formation_status.compel_follow_trail):
		problems.append("'%s' formation_status must be a follow-trail compel" % id)
	if speed_status == null or shield_status == null:
		problems.append("'%s' needs speed_status and shield_status" % id)
	for key in [&"gather_radius", &"march_duration", &"perfect_extension", &"perfect_shield_strength", &"good_shield_strength"]:
		if not values.has(key):
			problems.append("'%s' is missing values/%s" % [id, key])
	return problems
