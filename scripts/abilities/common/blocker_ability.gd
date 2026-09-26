extends Ability
class_name BlockerAbility

# Generic hold-to-raise barrier driven by BlockerData. Press: the blocker
# (a FrontalBlocker child of the actor, built on first use and kept, so its
# HP carries over) goes up on the aim arc, raised_status goes on, and every
# slot but allowed_slots_while_raised is locked. Release (or the blocker
# breaking) lowers it; letting go on purpose also applies lowered_status.
# The ability bar shows its HP as a meter.
#
# Cues: <id>_raised, <id>_lowered, <id>_absorbed (context.amount), <id>_broken.

var blocker: FrontalBlocker


func get_blocker_data() -> BlockerData:
	return data as BlockerData


func _ready() -> void:
	super()
	if actor == null:
		return
	var blocker_data := get_blocker_data()
	blocker = FrontalBlocker.new()
	blocker.name = str(ability_id).to_pascal_case() + "Blocker"
	blocker.owner_actor = actor
	_sync_blocker()
	blocker.hp = blocker.max_hp
	actor.add_child.call_deferred(blocker)
	blocker.absorbed.connect(func(amount, _info):
		actor.trigger_cue(StringName(str(ability_id) + "_absorbed"), {"amount": amount}))
	blocker.broken.connect(_on_broken)


func _sync_blocker() -> void:
	var blocker_data := get_blocker_data()
	blocker.radius = blocker_data.radius
	blocker.arc_degrees = blocker_data.arc_degrees
	blocker.regen_per_second = blocker_data.regen_per_second
	blocker.regen_delay = blocker_data.regen_delay
	blocker.min_raise_ratio = blocker_data.min_raise_ratio
	blocker.color = blocker_data.color
	if blocker_data.blocker_hp != null:
		blocker.set_max_hp(blocker_data.blocker_hp.evaluate(get_stats()))


func _activate(_target_position: Vector2) -> String:
	if blocker == null or not blocker.can_raise():
		return "Broken"
	return ""


func _on_active_start() -> void:
	_sync_blocker()
	if not blocker.raise():
		return
	var blocker_data := get_blocker_data()
	if blocker_data.raised_status != null:
		actor.status_component.apply(blocker_data.raised_status, actor)
	controller.lock_abilities(self, blocker_data.allowed_slots_while_raised, blocker_data.quiet_slots_while_raised)
	actor.trigger_cue(StringName(str(ability_id) + "_raised"))


func is_held() -> bool:
	return blocker != null and blocker.is_raised()


func release_hold(_target_position: Vector2) -> bool:
	if not is_held():
		return false
	blocker.lower()
	_after_lowered(true)
	return true


func get_hud_meter() -> float:
	return blocker.get_hp_ratio() if blocker != null else -1.0


func set_dormant(dormant: bool) -> void:
	super(dormant)
	if dormant and is_held():
		blocker.lower()
		_after_lowered(false)


func _on_broken() -> void:
	_after_lowered(false)
	actor.trigger_cue(StringName(str(ability_id) + "_broken"))


func _after_lowered(on_purpose: bool) -> void:
	var blocker_data := get_blocker_data()
	if blocker_data.raised_status != null:
		actor.status_component.remove_from(blocker_data.raised_status.id, actor)
	controller.unlock_abilities(self)
	if on_purpose and blocker_data.lowered_status != null:
		actor.status_component.apply(blocker_data.lowered_status, actor)
	actor.trigger_cue(StringName(str(ability_id) + "_lowered"))


func _physics_process(delta: float) -> void:
	super(delta)
	# Stunned or dead: the blocker drops.
	if is_held() and (actor.health_component.is_dead() or actor.status_component.is_stunned()):
		blocker.lower()
		_after_lowered(false)
