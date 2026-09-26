extends Node2D
class_name AimLaser

# A thin line from its actor along the actor's aim (a sniper's laser sight),
# for as long as it exists. Use it as a status's attached_vfx (it's spawned
# under the actor's VisualsComponent) or attach it with a VisualCue. Drawn in
# world space, so the body's hop/lean doesn't bend it. Stopped by walls
# (GameRules.sight_mask) so it points at what the shot would hit.

@export var length: float = 1800.0
@export var color := Color(1.0, 0.25, 0.3, 0.75)
@export var width: float = 2.0
## Small dot where the line ends.
@export var end_dot_radius: float = 5.0

var _actor: Node2D
var _end := Vector2.ZERO


func setup_cue(context: Dictionary) -> void:
	var status = context.get("status_component")
	if status is Node:
		_actor = status.owner as Node2D
	if _actor == null:
		_actor = context.get("source") as Node2D


func _ready() -> void:
	top_level = true
	z_index = 4
	if _actor == null:
		var node := get_parent()
		while node != null and not node is Actor:
			node = node.get_parent()
		_actor = node as Node2D


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_actor):
		return
	global_position = _actor.global_position
	var aim = _actor.get(&"aim_direction")
	var dir: Vector2 = aim.normalized() if aim is Vector2 and aim != Vector2.ZERO else Vector2.RIGHT
	var to := global_position + dir * length
	var ray := PhysicsRayQueryParameters2D.create(global_position, to, GameRules.current().sight_mask)
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	_end = (hit.position if not hit.is_empty() else to) - global_position
	queue_redraw()


func get_end_point() -> Vector2:
	return global_position + _end


func _draw() -> void:
	draw_line(Vector2.ZERO, _end, color, width, true)
	if end_dot_radius > 0.0:
		draw_circle(_end, end_dot_radius, color)
