extends RangedAttackAbility

# Umbrella Rifle: the generic gun, plus Nimbus's shot rules.
#   * Steady Hand (passive) multiplies each shot and is spent by it.
#   * A granted crit (grant_crit(): a successful Parry) makes the next shot
#     crit every target it hits.
#   * Targets under his Overcast (its zone status, applied by him) are always
#     crit and don't use up the shot's pierce.
# A crit multiplies the hit by values/crit_multiplier and tags it "crit".

const TAG_CRIT := &"crit"
const TAG_GUARANTEED := &"guaranteed_crit"

var _crit_ready := false


func grant_crit() -> void:
	_crit_ready = true


func has_crit_ready() -> bool:
	return _crit_ready


func _shot_damage() -> float:
	var passive := _steady_hand()
	return super() * (1.0 + (passive.get_bonus() if passive != null else 0.0))


func _on_projectile_fired(projectile: Projectile, extra: bool) -> void:
	if extra:
		return
	if _crit_ready:
		projectile.damage_template.tags.append(TAG_GUARANTEED)
		_crit_ready = false
	var passive := _steady_hand()
	if passive != null:
		passive.consume()


func _build_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> DamageInfo:
	if info.has_tag(TAG_GUARANTEED) or _in_overcast(hurtbox):
		info.amount *= data.get_value(&"crit_multiplier", get_stats())
		info.tags.append(TAG_CRIT)
	return info


func _hit_is_free_pierce(hurtbox: HurtboxComponent) -> bool:
	return _in_overcast(hurtbox)


# Standing in Nimbus's own Overcast (the ultimate zone's status, from him).
func _in_overcast(hurtbox: HurtboxComponent) -> bool:
	var ultimate := actor.ability_controller.get_ability_for_slot(&"ultimate")
	if ultimate == null or hurtbox.status_component == null:
		return false
	var zone_data := ultimate.data as ZoneAbilityData
	if zone_data == null or zone_data.zone == null or zone_data.zone.status_while_inside == null:
		return false
	return hurtbox.status_component.has_status_from(zone_data.zone.status_while_inside.id, actor)


func _steady_hand() -> Node:
	var passive := actor.ability_controller.get_ability_for_slot(&"passive")
	return passive if passive != null and passive.has_method(&"get_bonus") else null
