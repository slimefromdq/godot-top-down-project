extends RangedAttackAbility

# Heavy Notes: the generic gun firing exploding notes (all data). The only
# addition is the ENCORE (Chord): when the Key is wound, a shot fires
# data.chord_projectile, which splits into a fan of notes on exploding,
# each dealing encore_value(chord_note_damage, strength).

const KEY := preload("res://heroes/melody/abilities/melody_key.gd")

var _chord_strength: float = -1.0


func _activate(target_position: Vector2) -> String:
	var failure := super(target_position)
	if failure != "":
		return failure
	var key := KEY.find_on(actor)
	_chord_strength = key.consume_encore(self) if key != null else -1.0
	return ""


func is_chord_pending() -> bool:
	return _chord_strength >= 0.0


func _get_shot_projectile(perfect: bool, extra: bool) -> ProjectileData:
	if is_chord_pending() and not extra:
		return (data as MelodyHeavyNotesData).chord_projectile
	return super(perfect, extra)


func _on_projectile_fired(projectile: Projectile, extra: bool) -> void:
	if is_chord_pending() and not extra:
		projectile.split_damage = KEY.encore_value(data, &"chord_note_damage", _chord_strength) \
			* _damage_multiplier(false)
		_chord_strength = -1.0
