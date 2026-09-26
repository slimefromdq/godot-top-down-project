@tool
extends AbilityData
class_name ButlerHungerData

# Data for Butler's Hunger passive. The numbers are named values:
#   values/max_hunger             100
#   values/hunger_per_hp_percent  Hunger per 1% of max HP lost (1)
#   values/hunger_per_second      Hunger per second in combat (1)
#   values/combat_window          seconds after dealing/taking damage that
#                                 still count as "in combat" (3)
#   values/starving_duration      longest Starving lasts (8)
#   values/recover_armor_delay    seconds after recovering before the armor
#                                 buff lands (the tie-straightening, 0.6)

## Slot -> the Starving form's ability. The ultimate isn't here: it's the
## same in both forms.
@export var starving_abilities: Dictionary[StringName, AbilityData] = {}
## On recovering: rooted while he straightens his tie.
@export var recover_status: StatusEffect
## After recover_armor_delay: bonus armor.
@export var recover_armor_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	if starving_abilities.is_empty():
		problems.append("'%s' has no starving_abilities" % id)
	for slot in starving_abilities:
		var form: AbilityData = starving_abilities[slot]
		if form == null:
			problems.append("'%s' starving slot %s is empty" % [id, slot])
		else:
			for problem in form.validate():
				problems.append("'%s' starving %s: %s" % [id, slot, problem])
	return problems
