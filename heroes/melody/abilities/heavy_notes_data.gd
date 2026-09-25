@tool
extends RangedAttackData
class_name MelodyHeavyNotesData

# Heavy Notes (Melody's primary): a RangedAttackData whose projectile
# explodes (ProjectileData Explosion group). The encore (Chord) fires
# `chord_projectile` instead: the same note, but it splits into a fan on
# exploding. Named values:
#   values/chord_note_damage   damage of each split note (encore: BASE x strength)

@export_group("Encore: Chord")
@export var chord_projectile: ProjectileData


func validate() -> PackedStringArray:
	var problems := super()
	if chord_projectile == null:
		problems.append("'%s' has no chord_projectile" % id)
	else:
		for problem in chord_projectile.validate():
			problems.append("'%s' chord %s" % [id, problem])
		if not chord_projectile.split_on_explode:
			problems.append("'%s' chord_projectile doesn't split" % id)
	if not values.has(&"chord_note_damage"):
		problems.append("'%s' is missing values/chord_note_damage" % id)
	return problems
