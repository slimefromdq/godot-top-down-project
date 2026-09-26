extends RangedAttackAbility

# Moonshot: the generic gun (moonshot.tres: SEMI, REGEN, magic) whose
# magazine is set by Waxing Moon. The only addition: each shot leaves from
# the moon it launches, its place in the orbit, not a fixed muzzle.

const WAXING := preload("res://heroes/cosmo/abilities/waxing_moon.gd")


func _get_shot_origin(aim: Vector2, muzzle: Vector2) -> Vector2:
	var passive := WAXING.find_on(actor)
	if passive == null or get_ammo() <= 0:
		return super(aim, muzzle)
	# The last ready moon leaves (the orbit draws the first `ammo` as ready).
	return actor.global_position + passive.get_moon_offset(get_ammo() - 1, get_max_ammo())
