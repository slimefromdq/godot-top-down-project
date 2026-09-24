extends Ability
class_name BuffAbility

# BUFF: applies a StatusEffect to the caster. The numbers (fire rate, speed,
# damage, damage taken) live in the StatusEffect resource, and so does the
# aura/tint shown while it lasts.
#
# Cues: <ability_id> on cast. The status' own attached_vfx, body_tint and
# apply_sound handle the lasting look.

@export var effect: StatusEffect
## Instantly fills the magazine on cast.
@export var refill_ammo: bool = true


func _activate(_target_position: Vector2) -> String:
	if effect == null:
		return "No effect"
	actor.status_component.apply(effect)
	if refill_ammo:
		actor.weapon_component.refill()
	actor.trigger_cue(ability_id, {"duration": effect.duration})
	return ""
