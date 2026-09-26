extends RangedAttackAbility

# Moonshot: the generic gun (moonshot.tres: SEMI, REGEN, magic, piercing)
# whose magazine is set by Waxing Moon. The only additions: each shot leaves
# from the moon it launches, its place in the orbit, not a fixed muzzle, and
# flies at the cursor from there, so a whole volley converges on one target.

const WAXING := preload("res://heroes/cosmo/abilities/waxing_moon.gd")
const MIN_CONVERGE_DISTANCE := 40.0
const MAX_CONVERGE_ANGLE := PI / 3.0


func _get_shot_origin(aim: Vector2, muzzle: Vector2) -> Vector2:
	var passive := WAXING.find_on(actor)
	if passive == null or get_ammo() <= 0:
		return super(aim, muzzle)
	# The last ready moon leaves (the orbit draws the first `ammo` as ready).
	return actor.global_position + passive.get_moon_offset(get_ammo() - 1, get_max_ammo())


# Converge on the cursor, unless it's so close that a far-side moon would
# fly back across her: then straight along the aim.
func _get_shot_direction(aim: Vector2, origin: Vector2) -> Vector2:
	var to_cursor: Vector2 = actor.aim_point - origin
	if to_cursor.length() < MIN_CONVERGE_DISTANCE:
		return aim
	var direction := to_cursor.normalized()
	return direction if absf(direction.angle_to(aim)) < MAX_CONVERGE_ANGLE else aim
