extends Node2D
class_name FrontalBlocker

# A barrier on an actor's aim arc (a cloak, a shield) that eats enemy
# projectiles while raised. It has its own HP: each projectile it catches
# takes its damage off that HP instead of the actor. It regenerates while
# lowered (after regen_delay) and breaks when emptied; a broken blocker can
# be raised again once it has regenerated to min_raise_ratio.
#
# BlockerAbility (BlockerData) creates and drives one; Projectile asks
# FrontalBlocker.find_blocking() every tick. Melee isn't blocked.
#
# Signals: raised, lowered, absorbed(amount, info), broken.

signal raised
signal lowered
signal absorbed(amount: float, info: DamageInfo)
signal broken

const GROUP := &"frontal_blockers"

## The actor it protects (its aim decides where the arc faces).
var owner_actor: Node2D
var radius: float = 110.0
var arc_degrees: float = 120.0
var max_hp: float = 400.0
var hp: float = 400.0
## Fraction of max HP regained per second while lowered.
var regen_per_second: float = 0.2
## Seconds after lowering (or breaking) before it regenerates.
var regen_delay: float = 1.0
## A broken blocker can be raised again at this fraction of max HP.
var min_raise_ratio: float = 0.2
var color := Color(0.55, 0.05, 0.12, 0.55)

var _raised := false
var _broken := false
var _regen_wait: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 3


func is_raised() -> bool:
	return _raised


func is_broken() -> bool:
	return _broken


func get_hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


func can_raise() -> bool:
	return hp > 0.0 and (not _broken or hp >= max_hp * min_raise_ratio)


func raise() -> bool:
	if _raised or not can_raise():
		return false
	_raised = true
	_broken = false
	raised.emit()
	queue_redraw()
	return true


func lower() -> void:
	if not _raised:
		return
	_raised = false
	_regen_wait = regen_delay
	lowered.emit()
	queue_redraw()


# Change max HP (a level up), keeping the same fraction filled.
func set_max_hp(value: float) -> void:
	var ratio := get_hp_ratio() if max_hp > 0.0 else 1.0
	max_hp = maxf(value, 1.0)
	hp = max_hp * ratio


# The direction the arc faces (the owner's aim).
func get_facing() -> Vector2:
	var aim = owner_actor.get(&"aim_direction") if is_instance_valid(owner_actor) else null
	return aim.normalized() if aim is Vector2 and aim != Vector2.ZERO else Vector2.RIGHT


# A projectile's hit landed on the blocker. Returns the damage absorbed.
func absorb(info: DamageInfo) -> float:
	if not _raised:
		return 0.0
	var amount := minf(info.amount, hp)
	hp -= info.amount
	absorbed.emit(amount, info)
	if hp <= 0.0:
		hp = 0.0
		_broken = true
		_raised = false
		_regen_wait = regen_delay
		broken.emit()
		lowered.emit()
	queue_redraw()
	return amount


func _physics_process(delta: float) -> void:
	if _raised:
		queue_redraw()
		return
	if _regen_wait > 0.0:
		_regen_wait -= delta
		return
	if hp < max_hp:
		hp = minf(hp + max_hp * regen_per_second * delta, max_hp)


# Where a projectile of `source` flying from -> to first meets a raised enemy
# blocker: {"blocker": FrontalBlocker, "point": Vector2}, or {} if none.
static func find_blocking(tree: SceneTree, source, from: Vector2, to: Vector2) -> Dictionary:    # source untyped: may be freed
	if not is_instance_valid(source):
		source = null
	var best := {}
	var best_t := INF
	for node in tree.get_nodes_in_group(GROUP):
		var blocker := node as FrontalBlocker
		if blocker == null or not blocker._raised or not is_instance_valid(blocker.owner_actor):
			continue
		if not _is_enemy(source, blocker.owner_actor):
			continue
		var t := blocker._crossing(from, to)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"blocker": blocker, "point": from.lerp(to, t)}
	return best


static func _is_enemy(source: Node, protected: Node) -> bool:
	if source == null:
		return true    # a shot whose shooter is gone still hits a blocker
	if source == protected:
		return false
	var team := CombatQueries.team_of(source)
	return team == &"" or CombatQueries.team_of(protected) != team


# Fraction along from->to where the segment enters the arc, or -1.
func _crossing(from: Vector2, to: Vector2) -> float:
	var center := global_position
	var d := to - from
	var f := from - center
	var a := d.dot(d)
	if a < 0.0001:
		return -1.0
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var root := sqrt(disc)
	var facing := get_facing()
	var half := deg_to_rad(arc_degrees) / 2.0
	for t in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if t < 0.0 or t > 1.0:
			continue
		var point: Vector2 = from + d * t
		# Only the outside edge, crossed going in, blocks (a shot fired from
		# inside the arc isn't caught on its way out).
		if (point - center).dot(d) > 0.0:
			continue
		if absf(facing.angle_to(point - center)) <= half:
			return t
	return -1.0


func _draw() -> void:
	if not _raised:
		return
	var facing := get_facing()
	var half := deg_to_rad(arc_degrees) / 2.0
	var start := facing.angle() - half
	var alpha := 0.35 + 0.65 * get_hp_ratio()
	draw_arc(Vector2.ZERO, radius, start, start + half * 2.0, 24, Color(color, color.a * alpha), 14.0, true)
	draw_arc(Vector2.ZERO, radius + 7.0, start, start + half * 2.0, 24, Color(1, 0.85, 0.9, 0.5 * alpha), 3.0, true)
