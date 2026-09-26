@tool
extends AbilityData
class_name CosmoTideData

# Tide (Cosmo's E): a ground-targeted whirlpool. `zone` pulls enemies to
# its centre (status_while_inside = a blend compel, statuses_from_zone);
# after values/tide_duration it detonates: `detonation` (a ProjectileData
# explosion) for the inherited `damage`. Named values:
#   values/cast_range      the circle is placed at the cursor, at most this far
#   values/tide_duration   seconds of pull before the detonation

@export_group("Tide")
@export var zone: GroundZoneData
@export var detonation: ProjectileData


func get_range() -> float:
	return values[&"cast_range"].base if values.has(&"cast_range") else super()


func validate() -> PackedStringArray:
	var problems := super()
	if zone == null or detonation == null or detonation.explosion_shape == null:
		problems.append("'%s' needs a zone and a detonation with an explosion_shape" % id)
	elif zone != null:
		for problem in zone.validate():
			problems.append("'%s' %s" % [id, problem])
	for key in [&"cast_range", &"tide_duration"]:
		if not values.has(key):
			problems.append("'%s' is missing values/%s" % [id, key])
	return problems
