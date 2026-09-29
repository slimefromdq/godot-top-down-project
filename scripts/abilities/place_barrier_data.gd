@tool
extends AbilityData
class_name PlaceBarrierData

# Data for PlaceBarrierAbility: put a PlacedBarrier (a projectile-blocking
# shield with charges) at the cursor, facing away from the caster.

@export_group("Barrier")
## Farthest placement from the caster (the cursor is clamped).
@export var place_range: float = 300.0
## Curve radius and width of the barrier (px, degrees).
@export var barrier_radius: float = 110.0
@export var arc_degrees: float = 100.0
## Projectiles it catches before dropping.
@export var charges: int = 3
## Seconds for one spent charge to come back.
@export var recharge_time: float = 3.0
## Seconds it stays.
@export var lifetime: float = 4.0
@export var color: Color = Color(0.75, 0.8, 0.95, 0.75)


func get_range() -> float:
	return ability_range if ability_range > 0.0 else place_range


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {"charges": charges, "lifetime": lifetime}


func validate() -> PackedStringArray:
	var problems := super()
	if place_range < 0.0 or barrier_radius <= 0.0 or charges < 1 or recharge_time < 0.0 or lifetime <= 0.0:
		problems.append("'%s' barrier numbers are invalid" % id)
	return problems
