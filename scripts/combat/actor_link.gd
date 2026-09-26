extends Node2D
class_name ActorLink

# Two actors linked for a while (Sam's Friendship Bracelet). Options:
#   leash_distance  > 0: they can't get further apart than this. Every physics
#                   tick, whoever moved away is put back on the line at
#                   exactly the leash distance; if both pulled apart, both
#                   give half.
#   heal_share      > 0: this fraction of the healing either one receives
#                   also heals the other (shared healing doesn't bounce back).
#   link_status     optional: kept on both ends while linked (for the look,
#                   and for scripts asking "are they linked?").
# It ends at its duration, or when either end dies or is removed.
# Signal: ended. Spawn with ActorLink.spawn().

signal ended

const GROUP := &"actor_links"

var a: Node2D
var b: Node2D
var source: Node
var duration: float = 4.0
var leash_distance: float = 0.0
var heal_share: float = 0.0
var link_status: StatusEffect
var color := Color(0.6, 1.0, 0.85, 0.8)

var _age: float = 0.0
var _ended := false
var _sharing := false
var _last_a := Vector2.ZERO
var _last_b := Vector2.ZERO


static func spawn(context: Node, first: Node2D, second: Node2D, link_duration: float, from: Node = null,
		leash: float = 0.0, share: float = 0.0, status: StatusEffect = null) -> ActorLink:
	var link := ActorLink.new()
	link.a = first
	link.b = second
	link.source = from
	link.duration = link_duration
	link.leash_distance = leash
	link.heal_share = share
	link.link_status = status
	context.get_tree().current_scene.add_child(link)
	return link


func _ready() -> void:
	add_to_group(GROUP)
	top_level = true
	z_index = 3
	_last_a = a.global_position
	_last_b = b.global_position
	for end in [a, b]:
		var health = end.get(&"health_component")
		if health is HealthComponent:
			health.healed.connect(_on_healed.bind(end))
		if link_status != null:
			var status := CombatQueries.status_of(end)
			if status != null:
				status.apply(link_status, source)


func has_ended() -> bool:
	return _ended


func get_other(end: Node) -> Node2D:
	return b if end == a else a if end == b else null


func end() -> void:
	if _ended:
		return
	_ended = true
	for node in [a, b]:
		if not is_instance_valid(node):
			continue
		var health = node.get(&"health_component")
		if health is HealthComponent:
			for connection in health.healed.get_connections():
				if connection.callable.get_object() == self:
					health.healed.disconnect(connection.callable)
		if link_status != null:
			var status := CombatQueries.status_of(node)
			if status != null:
				status.remove_from(link_status.id, source)
	ended.emit()
	queue_free()


func _physics_process(delta: float) -> void:
	if _ended:
		return
	_age += delta
	if _age >= duration or StatusEffectComponent.is_actor_gone(a) or StatusEffectComponent.is_actor_gone(b):
		end()
		return
	if leash_distance > 0.0:
		_apply_leash()
	_last_a = a.global_position
	_last_b = b.global_position
	queue_redraw()


func _apply_leash() -> void:
	var gap := a.global_position.distance_to(b.global_position)
	if gap <= leash_distance:
		return
	var excess := gap - leash_distance
	# Who pulled away this tick (how much each one's move widened the gap).
	var a_away := maxf(a.global_position.distance_to(_last_b) - _last_a.distance_to(_last_b), 0.0)
	var b_away := maxf(b.global_position.distance_to(_last_a) - _last_b.distance_to(_last_a), 0.0)
	var total := a_away + b_away
	var a_share := 0.5 if total <= 0.0 else a_away / total
	var dir := a.global_position.direction_to(b.global_position)
	# Never pull anyone through a ContainmentRing: the other end gives instead.
	var tree := get_tree()
	var a_to := a.global_position + dir * excess
	var b_to := b.global_position - dir * excess
	if ContainmentRing.crosses_any(tree, a.global_position, a_to):
		a_share = 0.0
	if ContainmentRing.crosses_any(tree, b.global_position, b_to):
		a_share = 1.0 if a_share > 0.0 else -1.0
	if a_share < 0.0:
		return    # both would cross: the ring wins, the leash waits
	a.global_position += dir * excess * a_share
	b.global_position -= dir * excess * (1.0 - a_share)


func _on_healed(amount: float, _from: Node, end_node: Node2D) -> void:
	if _sharing or heal_share <= 0.0 or amount <= 0.0 or _ended:
		return
	var other := get_other(end_node)
	var health = other.get(&"health_component") if is_instance_valid(other) else null
	if not health is HealthComponent:
		return
	_sharing = true
	health.heal(amount * heal_share, source if is_instance_valid(source) else null, &"link_share")
	_sharing = false


func _draw() -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	draw_line(a.global_position, b.global_position, Color(color, 0.35), 6.0, true)
	draw_line(a.global_position, b.global_position, color, 2.0, true)
