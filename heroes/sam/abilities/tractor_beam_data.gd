@tool
extends ChargeData
class_name SamTractorData

# Data for Tractor Beam: the dash (a ChargeData) plus what the lifted target
# gets while carried, by team. values/short_distance is the hover-dash with
# no target.

## On an enemy target while carried (a carry that stuns).
@export var enemy_status: StatusEffect
## On an ally target while carried (a carry, untargetable: a rescue).
@export var ally_status: StatusEffect
