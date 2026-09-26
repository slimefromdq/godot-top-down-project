@tool
extends AbilityData
class_name CosmoWaxingMoonData

# Waxing Moon (Cosmo's passive). Her moons are her primary's magazine:
# moon count = how many moon_breakpoints her level has reached.
# Named values:
#   values/orbit_radius   px from her centre
#   values/orbit_speed    radians per second (cosmetic AND where shots leave)
#   values/moonlit_full   the amp her burst estimate assumes (CSV only)

@export_group("Moons")
## Levels at which she gains a moon (1 moon at level 1, 2 at 4, ...).
@export var moon_breakpoints: Array[int] = [1, 4, 7, 10]
## Optional: primary regen interval (s) by moon count (index 0 = 1 moon).
## Empty = the primary's own regen_interval.
@export var regen_interval_by_moons: Array[float] = []
## The slot of the gun whose magazine is the moons.
@export var gun_slot: StringName = &"primary"
## Cue triggered on each new moon.
@export var wax_cue: StringName = &"cosmo_wax"


func get_moon_count(level: int) -> int:
	var count := 0
	for at_level in moon_breakpoints:
		if level >= at_level:
			count += 1
	return maxi(count, 1)


func get_regen_interval(moons: int) -> float:
	if regen_interval_by_moons.is_empty():
		return -1.0
	return regen_interval_by_moons[clampi(moons - 1, 0, regen_interval_by_moons.size() - 1)]


# Her derived balance rows (source "derived"): moons, the primary's
# sustained DPS at this level, a full moon volley, and the burst combo
# Crescent (out, then back amped) -> Tide -> volley with Moonlit at full.
func get_hero_metrics(definition: HeroDefinition, level: int) -> Dictionary:
	var gun := definition.get_ability(gun_slot) as RangedAttackData
	var crescent := definition.get_ability(&"ability_1")
	var tide := definition.get_ability(&"cc")
	if gun == null or gun.damage == null:
		return {}
	var weapon := definition.stats.value_at(StatBlock.WEAPON, level)
	var magic := definition.stats.value_at(StatBlock.MAGIC, level)
	var moons := get_moon_count(level)
	var shot := gun.damage.evaluate_at(level, weapon, magic)
	var regen := get_regen_interval(moons)
	if regen <= 0.0:
		regen = gun.regen_interval
	var amp_single := crescent.get_value(&"moonlit_amp", null) if crescent != null else 1.0
	var amp_full := crescent.get_value(&"moonlit_amp_full", null) if crescent != null else 1.0
	var pass_damage := crescent.damage.evaluate_at(level, weapon, magic) if crescent != null and crescent.damage != null else 0.0
	var tide_damage := tide.damage.evaluate_at(level, weapon, magic) if tide != null and tide.damage != null else 0.0
	var volley := shot * moons
	return {
		"moons": moons,
		"primary_sustained_dps": shot / regen if regen > 0.0 else 0.0,
		"moon_volley": volley,
		"burst_combo": pass_damage + pass_damage * amp_single + (tide_damage + volley) * amp_full,
	}


func validate() -> PackedStringArray:
	var problems := super()
	if moon_breakpoints.is_empty() or moon_breakpoints[0] != 1:
		problems.append("'%s' moon_breakpoints must start at level 1" % id)
	for i in range(1, moon_breakpoints.size()):
		if moon_breakpoints[i] <= moon_breakpoints[i - 1]:
			problems.append("'%s' moon_breakpoints must increase" % id)
	for key in [&"orbit_radius", &"orbit_speed"]:
		if not values.has(key):
			problems.append("'%s' is missing values/%s" % [id, key])
	return problems
