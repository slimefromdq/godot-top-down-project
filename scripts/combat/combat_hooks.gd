extends Node
class_name CombatHooks

# The one place passives and abilities subscribe to combat events for their
# actor. Put it under Components; HealthComponent and StatsComponent find it
# automatically and report into it.
#
#   hit_dealt(info, target)   this actor's damage landed on target (on_hit_dealt)
#   damage_taken(info)        this actor was hurt                  (on_damage_taken)
#   kill(victim, info)        this actor landed a killing blow     (on_kill)
#   death(info)               this actor died (after about_to_die) (on_death)
#   level_up(level)           this actor's level changed           (on_level_up)
#   about_to_die(event)       cancellable; see DeathEvent
#   heal_done(amount, target, label)  this actor healed someone (incl. itself)
#   parried(kind, attacker, info)  this actor's parry status (StatusEffect.parries)
#       caught a hit: kind &"projectile" (reflected back) or &"melee"
#       (attacker stunned by parry_melee_status). info = the caught hit.
#
# Status notifications, on the APPLIER (whoever applied the status):
#   status_target_died(status_id, target, info)  a target carrying this actor's
#       status died, killed by anyone (info = the killing blow). Fires before
#       the status is removed. "Reset my cooldown when my mark dies" lives here.
#   status_expired(status_id, target)            it ran its full duration
#   status_removed(status_id, target, reason)    it ended for ANY reason:
#       &"expired", &"removed" (cleanse, zone exit, another applier took
#       over a shared status), &"target_died", &"applier_died"
#
# Why a separate node instead of signals on HealthComponent? A hit involves two
# actors. "Avery heals when SHE hits" is an event on the attacker, but the
# damage is processed on the victim. HealthComponent (victim side) reports into
# the attacker's hooks, so passives only ever listen to their own actor.

signal hit_dealt(info: DamageInfo, target: Node)
signal damage_taken(info: DamageInfo)
signal kill(victim: Node, info: DamageInfo)
signal death(info: DamageInfo)
signal level_up(level: int)
signal about_to_die(event: DeathEvent)
signal heal_done(amount: float, target: Node, label: StringName)
signal status_target_died(status_id: StringName, target: Node, info: DamageInfo)
signal status_expired(status_id: StringName, target: Node)
signal status_removed(status_id: StringName, target: Node, reason: StringName)
signal parried(kind: StringName, attacker: Node, info: DamageInfo)

const META_KEY := &"combat_hooks"


func _enter_tree() -> void:
	_get_root().set_meta(META_KEY, self)


func _ready() -> void:
	var stats := StatsComponent.find_on(_get_root())
	if stats != null:
		stats.level_changed.connect(func(lvl: int): level_up.emit(lvl))


# The hooks of any actor (or null). Accepts the actor root or any node whose
# owner is the actor (e.g. a hurtbox).
static func find_on(node: Node) -> CombatHooks:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_meta(META_KEY):
		return node.get_meta(META_KEY)
	if node.owner != null and node.owner.has_meta(META_KEY):
		return node.owner.get_meta(META_KEY)
	return null


func _get_root() -> Node:
	return owner if owner != null else get_parent()
