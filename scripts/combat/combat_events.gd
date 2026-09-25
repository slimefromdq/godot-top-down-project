extends Node

# Autoload "CombatEvents": a global feed of every hit and heal in the match.
#
# Per-actor CombatHooks are for gameplay (passives listen to their own actor).
# This feed is for observers that care about everyone: the damage meter,
# the stat inspector, a future kill feed or network replication log.
# Gameplay code should never listen here; that keeps hero logic local.

signal damage_dealt(info: DamageInfo)
signal heal_done(amount: float, source: Node, target: Node, label: StringName)
signal actor_died(victim: Node, info: DamageInfo)
signal death_prevented(victim: Node, event: DeathEvent)
## A shield soaked damage. `shield_source` applied the shield; `info` is the
## hit (may be null).
signal damage_absorbed(amount: float, shield_source: Node, target: Node, status_id: StringName, info: DamageInfo)
