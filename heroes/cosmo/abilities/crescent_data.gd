@tool
extends RangedAttackData
class_name CosmoCrescentData

# Crescent (Cosmo's RMB): a returning (return_to_caster, curve_amount),
# piercing magic projectile. Each enemy it hits is Moonlit. Named values:
#   values/moonlit_amp        incoming magic multiplier after one pass (1.2 = +20%)
#   values/moonlit_amp_full   ...after being hit on BOTH passes
# moonlit_status is a +100% "unit" (incoming_magic_multiplier 2.0) applied
# at strength (amp - 1), so the named values are the real numbers; a
# refresh keeps the stronger application.

@export_group("Moonlit")
@export var moonlit_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	if moonlit_status == null:
		problems.append("'%s' has no moonlit_status" % id)
	elif not is_equal_approx(moonlit_status.incoming_magic_multiplier, 2.0):
		problems.append("'%s' moonlit_status must be a +100%% unit (incoming_magic_multiplier 2.0)" % id)
	if projectile != null and not projectile.return_to_caster:
		problems.append("'%s' projectile doesn't return" % id)
	for key in [&"moonlit_amp", &"moonlit_amp_full"]:
		if not values.has(key):
			problems.append("'%s' is missing values/%s" % [id, key])
	return problems
