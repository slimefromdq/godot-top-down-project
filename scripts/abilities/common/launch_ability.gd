extends Ability
class_name LaunchAbility

# Generic leap driven by LaunchData: on the active phase, Actor.launch() toward
# the cast target (clamped to max_distance), over low cover and ledges. With
# steer_speed, the caster's move input slides the landing point in flight
# (Actor.retarget_launch). The cast ends at once; the flight goes on, so the
# hero can shoot while airborne.
#
# Cues: <id>_launch (context.target_position), <id>_land (context.position).

var _start := Vector2.ZERO
var _flying := false


func get_launch_data() -> LaunchData:
	return data as LaunchData


func _activate(_target_position: Vector2) -> String:
	if actor.is_airborne():
		return "Airborne"
	return ""


func _on_active_start() -> void:
	var launch := get_launch_data()
	_start = actor.global_position
	var target := _start + (cast_target - _start).limit_length(launch.max_distance)
	if launch.self_status != null:
		actor.status_component.apply(launch.self_status, actor)
	if not actor.landed.is_connected(_on_landed):
		actor.landed.connect(_on_landed)
	_flying = true
	actor.launch(target, launch.air_time, launch.arc_height)
	actor.trigger_cue(StringName(str(ability_id) + "_launch"), {"target_position": target})


func is_flying() -> bool:
	return _flying


func _physics_process(delta: float) -> void:
	super(delta)
	if not _flying or not actor.is_airborne():
		return
	var launch := get_launch_data()
	if launch.steer_speed <= 0.0 or actor.move_direction == Vector2.ZERO:
		return
	var target := actor.get_launch_target() + actor.move_direction.limit_length(1.0) * launch.steer_speed * delta
	target = _start + (target - _start).limit_length(launch.max_distance)
	actor.retarget_launch(target)


func _on_landed() -> void:
	if not _flying:
		return
	_flying = false
	var launch := get_launch_data()
	if launch.landing_status != null:
		actor.status_component.apply(launch.landing_status, actor)
	actor.trigger_cue(StringName(str(ability_id) + "_land"), {"position": actor.global_position})
