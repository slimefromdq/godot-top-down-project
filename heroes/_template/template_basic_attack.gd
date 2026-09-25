extends MeleeAttackAbility

# TEMPLATE ability script. Copy this pattern for any ability that needs its
# own behaviour. (No class_name on purpose: every copied hero gets its own
# copy of this file, and two scripts can't share a class_name.)
#
# Everything numeric lives in the .tres this script is paired with
# (template_basic_attack.tres). The script only says what's DIFFERENT about
# this ability. A plain melee swing needs nothing here at all; the overrides
# below are shown commented out as a menu of the hooks you can use.
#
# Timed-cast hooks (from Ability):
#   _activate(target) -> String   validate; return "" or a failure reason
#   _on_windup_start()            anticipation
#   _on_active_start()            MeleeAttackAbility opens the hitbox here
#   _on_active_tick(delta)
#   _on_active_end()
#   _on_recovery_start()
#   _on_cast_end(interrupted)
#
# Melee hooks (from MeleeAttackAbility):
#   _build_hit(info, hurtbox) -> DamageInfo   change a hit before it lands
#   _on_target_hit(info, hurtbox)             react after it lands
#
# Hero-wide events: actor.combat_hooks (hit_dealt, damage_taken, kill,
# death, level_up, about_to_die).


# func _on_target_hit(info: DamageInfo, _hurtbox: HurtboxComponent) -> void:
# 	# Example: heal 10% of damage dealt.
# 	actor.health_component.heal(info.final_amount * 0.1, actor, &"lifesteal")
