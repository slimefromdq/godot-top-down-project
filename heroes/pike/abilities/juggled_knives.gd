extends RangedAttackAbility

# Juggled Knives: the generic REGEN gun, plus
#   * every knife adds values/max_hp_ratio of the target's max HP
#   * an ambush (Obsession) knife deals values x ambush_damage_multiplier and
#     carries the passive's ambush_status (a root)
# Five knives orbit her as the ammo display (vfx/knife_orbit.gd, cosmetic).

const TAG_AMBUSH := &"ambush"


func _ready() -> void:
	super()
	if actor != null:
		var orbit: Node2D = preload("res://heroes/pike/vfx/knife_orbit.gd").new()
		orbit.gun = self
		actor.get_node(^"Visuals").add_child.call_deferred(orbit)


func _on_projectile_fired(projectile: Projectile, extra: bool) -> void:
	if extra:
		return
	var passive := controller.get_ability_for_slot(&"passive")
	if passive != null and passive.has_method(&"consume_ambush") and passive.consume_ambush():
		projectile.damage_template.tags.append(TAG_AMBUSH)
		projectile.damage_template.add_status(passive.get_obsession_data().ambush_status)
		actor.trigger_cue(StringName(str(ability_id) + "_ambush"))


func _build_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> DamageInfo:
	if hurtbox.health_component != null:
		info.amount += hurtbox.health_component.max_health * data.get_value(&"max_hp_ratio", get_stats())
	if info.has_tag(TAG_AMBUSH):
		var passive := controller.get_ability_for_slot(&"passive")
		info.amount *= passive.data.get_value(&"ambush_damage_multiplier", get_stats()) if passive != null else 2.0
	return info
