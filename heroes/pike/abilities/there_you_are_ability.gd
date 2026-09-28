extends ChargeAbility

# There You Are: with a Beloved within values/teleport_range, Pike blinks to
# just behind them (values/behind_offset, opposite their facing): a teleport
# (Actor.teleport_to), so walls don't matter and no line of sight is needed,
# but a ContainmentRing still does. Beyond range it fails. With no Beloved
# it's the data's plain short dash. Cue: <id>_blink (context.position).

var _blink_to := Vector2.INF


func _get_cast_feel() -> AttackFeel:
	_blink_to = Vector2.INF
	var feel := super()
	var beloved := _beloved()
	if beloved != null:
		_blink_to = _spot_behind(beloved)
		_distance = 0.0
		feel.active = 0.02
	return feel


func _activate(target_position: Vector2) -> String:
	var beloved := _beloved()
	if beloved != null:
		if actor.global_position.distance_to(beloved.global_position) > data.get_value(&"teleport_range", get_stats()):
			return "Out of range"
		if _blink_to == Vector2.INF:
			return "Blocked"
	return super(target_position)


func _on_active_start() -> void:
	super()
	if _blink_to != Vector2.INF and actor.teleport_to(_blink_to):
		actor.trigger_cue(StringName(str(ability_id) + "_blink"), {"position": _blink_to})


func _beloved() -> Node2D:
	var beloved := controller.get_ability_for_slot(&"ability_1")
	return beloved.get_beloved() if beloved != null and beloved.has_method(&"get_beloved") else null


# Behind them (opposite their facing), else beside, else in front: the first
# spot that isn't inside a wall.
func _spot_behind(beloved: Node2D) -> Vector2:
	var facing = beloved.get(&"aim_direction")
	var back: Vector2 = -(facing as Vector2).normalized() if facing is Vector2 and facing != Vector2.ZERO \
		else actor.global_position.direction_to(beloved.global_position)
	var offset := data.get_value(&"behind_offset", get_stats())
	for turn in [0.0, PI / 2.0, -PI / 2.0, PI]:
		var spot: Vector2 = beloved.global_position + back.rotated(turn) * offset
		if _is_free(spot):
			return spot
	return Vector2.INF


func _is_free(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = MapLayers.WORLD | MapLayers.LOW_COVER | MapLayers.PITS | MapLayers.CRYSTAL
	return actor.get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()
