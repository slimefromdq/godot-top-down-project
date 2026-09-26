extends PassiveAbility

# Crumple Zone: always_status stays on Tilly (knockbacks and pulls on her are
# shorter), and every landing from a launch (a trampoline, a jump pad) gives
# her landing_status (a burst of speed). Cue: <id>_landed.


func get_crumple_data() -> TillyCrumpleZoneData:
	return data as TillyCrumpleZoneData


func _ready() -> void:
	super()
	if actor != null:
		actor.landed.connect(_on_landed)


func _physics_process(delta: float) -> void:
	super(delta)
	var crumple := get_crumple_data()
	if actor == null or crumple == null or crumple.always_status == null or actor.health_component.is_dead():
		return
	# Re-applied if anything removed it (a cleanse, a respawn reset).
	if not actor.status_component.has_status_from(crumple.always_status.id, actor):
		actor.status_component.apply(crumple.always_status, actor)


func _on_landed() -> void:
	var crumple := get_crumple_data()
	if crumple == null or crumple.landing_status == null or actor.health_component.is_dead():
		return
	actor.status_component.apply(crumple.landing_status, actor)
	actor.trigger_cue(StringName(str(ability_id) + "_landed"))
