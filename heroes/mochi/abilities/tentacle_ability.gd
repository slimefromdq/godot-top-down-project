extends DeployAbility

# Tentacle: E places the tentacle (DeployData, max 1, 8 s). While it is out,
# E again swaps Mochi onto its spot (a teleport; refused through a
# ContainmentRing) and the tentacle is gone. The swap is free: the cooldown
# was spent on the placement. Cue: tentacle_swap (context.position, .from).

var _swapping := false


func get_tentacle() -> Deployable:
	var out := get_deployed()
	return out[0] if not out.is_empty() else null


func is_ready() -> bool:
	return get_tentacle() != null or super()


# Bots: place it whenever it's ready; swap only to escape (below
# values/bot_swap_health of max health) or before it expires.
func bot_should_use(_target_point: Vector2) -> bool:
	var tentacle := get_tentacle()
	if tentacle == null:
		return true
	return actor.health_component.get_health_ratio() < data.get_value(&"bot_swap_health", get_stats()) \
		or tentacle.life_left < 1.0


func _activate(target_position: Vector2) -> String:
	_swapping = get_tentacle() != null
	return "" if _swapping else super(target_position)


func _spend_cooldown() -> void:
	if not _swapping:
		super()


func _on_active_start() -> void:
	if not _swapping:
		super()
		return
	var tentacle := get_tentacle()
	if tentacle == null:
		return
	var from := actor.global_position
	if actor.teleport_to(tentacle.global_position):
		actor.trigger_cue(&"tentacle_swap", {"position": actor.global_position, "from": from})
		tentacle.remove(&"swapped")
	_swapping = false
