@tool
extends MeleeAttackData
class_name MochiGazeData

# Cone Stare: a CC-only cone (the melee swing) whose on_hit_status stuns,
# plus a second status on everyone it catches (the Magic Resist shred).

@export var shred_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	if shred_status != null:
		for problem in shred_status.validate():
			problems.append("'%s' shred_status: %s" % [id, problem])
	return problems
