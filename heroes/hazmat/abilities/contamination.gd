extends PassiveAbility

# Contamination: Hazmat's gas aura. The passive's data is a ZoneAbilityData;
# its zone (follow_owner, a ramp) is spawned around him for good and
# respawned whenever it's gone (after a revive, or after suspend()).
#
# Other kit pieces share its ramp through get_ramp_key(): the Sprayer gives
# a head start on it, and Canister / Containment Breach zones use the same key.

var aura: GroundZone
var _suspended_left: float = 0.0


func get_zone_data() -> ZoneAbilityData:
	return data as ZoneAbilityData


func get_ramp_key() -> StringName:
	var zone_data := get_zone_data()
	return zone_data.zone.get_ramp_key() if zone_data != null and zone_data.zone != null else &""


# Take the aura away for `seconds` (Containment Breach replaces it).
func suspend(seconds: float) -> void:
	_suspended_left = maxf(_suspended_left, seconds)
	if is_instance_valid(aura):
		aura.end()
	aura = null


func is_suspended() -> bool:
	return _suspended_left > 0.0


func _physics_process(delta: float) -> void:
	super(delta)
	if actor == null or not actor.is_inside_tree():
		return
	if _suspended_left > 0.0:
		_suspended_left -= delta
		return
	if not is_instance_valid(aura) and not actor.health_component.is_dead():
		var zone_data := get_zone_data()
		if zone_data != null and zone_data.zone != null:
			aura = GroundZone.spawn(actor, zone_data.zone, actor.global_position, actor.aim_direction, actor, INF)
