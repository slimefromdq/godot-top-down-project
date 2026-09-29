extends Ability
class_name DeployAbility

# Generic "place a thing" driven by DeployData: on the active phase, spawn
# the data's Deployable at the cursor (clamped to place_range) or at the
# caster. Enforces max_per_owner (oldest removed, or the cast refused with
# block_while_capped) and cooldown_after_gone.
#
# Cues: <id>_placed (context.position, .deployable). The deployable itself
# fires <id>_destroyed / <id>_expired on the owner.

var _pending_cooldown := false


func get_deploy_data() -> DeployData:
	return data as DeployData


func get_deployed() -> Array[Deployable]:
	return Deployable.find_owned(actor, ability_id)


func _activate(_target_position: Vector2) -> String:
	var deploy := get_deploy_data()
	if deploy == null or deploy.deployable_script == null:
		return "Nothing to deploy"
	if deploy.block_while_capped and get_deployed().size() >= deploy.max_per_owner:
		return "Already deployed"
	return ""


func _spend_cooldown() -> void:
	if get_deploy_data().cooldown_after_gone and UltimateCharge.for_ability(self) == null:
		_pending_cooldown = true
		return
	super()


func _on_active_start() -> void:
	var deploy := get_deploy_data()
	var at := actor.global_position
	if not deploy.place_at_caster:
		at = cast_target
		if deploy.place_range > 0.0:
			at = actor.global_position + (cast_target - actor.global_position).limit_length(deploy.place_range)
	var existing := get_deployed()
	while existing.size() >= deploy.max_per_owner:
		existing.pop_front().remove(&"replaced")
	var placed := Deployable.spawn(actor, deploy, at, ability_id)
	if deploy.cooldown_after_gone:
		placed.gone.connect(_on_gone)
	actor.trigger_cue(StringName(str(ability_id) + "_placed"), {"position": at, "deployable": placed})
	_on_deployed(placed)


# Override to set a fresh deployable up further (a hero's own kind).
func _on_deployed(_deployable: Deployable) -> void:
	pass


func _on_gone(_reason: StringName) -> void:
	if _pending_cooldown and is_instance_valid(actor):
		_pending_cooldown = false
		cooldown_remaining = 0.0 if cooldowns_disabled else get_cooldown()
