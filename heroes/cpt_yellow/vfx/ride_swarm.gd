extends Node2D

# Swarm Ride: the army streams under him and trails behind while he rides.
# Follows the riding ability (context.charge_ability) and frees itself the
# moment the ride ends.

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var bug_count: int = 22
@export var bug_size: float = 20.0
@export var trail_length: float = 170.0

var _ability: Ability
var _t := 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	var ability = context.get("charge_ability")
	if ability is Ability:
		_ability = ability


func _process(delta: float) -> void:
	_t += delta
	if _ability == null or not is_instance_valid(_ability) or not _ability.is_charging():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var heading: Vector2 = _ability.call(&"get_heading") if _ability.has_method(&"get_heading") else Vector2.RIGHT
	var side := heading.orthogonal()
	# Dust/speed lines behind.
	for i in 5:
		var off := side * (i - 2) * 22.0
		draw_line(off - heading * 60.0, off - heading * (60.0 + trail_length * 0.8), Color(1, 0.9, 0.4, 0.25), 4.0)
	for i in bug_count:
		var along := fposmod(i * 37.0 + _t * 420.0, trail_length + 80.0) - 60.0
		var lane := sin(i * 2.1 + _t * 6.0) * (40.0 + along * 0.15)
		var at := -heading * along + side * lane + Vector2(0, 18)
		var alpha := clampf(1.0 - along / (trail_length + 20.0), 0.15, 1.0)
		Bug.draw_bug(self, at, heading, bug_size, alpha, 0.5 + 0.5 * sin(_t * 50.0 + i))
