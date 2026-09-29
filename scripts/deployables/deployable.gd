extends Node2D
class_name Deployable

# Base class for placed objects (turrets, a healing post, a drone, a
# tentacle). Made by DeployAbility from DeployData; a hero script can also
# call Deployable.spawn().
#
#   owner_actor    who placed it (its team, its stats for every number)
#   health         data.deploy_health (owner's stats): a HurtboxComponent +
#                  HealthComponent + StatusEffectComponent, so enemy shots,
#                  zones and statuses (a stun, a silence) work on it like on
#                  anyone. No deploy_health = not hittable.
#   lifetime       data.lifetime seconds (0 = until destroyed)
#   cap            data.max_per_owner, enforced by DeployAbility
#   cleanup        removed when its owner dies or leaves the tree
#
# Subclasses override _deploy_ready() and _deploy_tick(delta), read their
# numbers with get_value(&"name"), and check is_disabled() (stunned or
# silenced) before acting. Signal gone(reason): &"destroyed", &"expired",
# &"owner_died", &"replaced" or &"removed". Owner cues:
# <kind>_destroyed / <kind>_expired (context.position).

signal gone(reason: StringName)

const GROUP := &"deployables"

var owner_actor: Node2D
var data: DeployData
## The ability id that made it: its kind (for caps and finding it again).
var kind: StringName = &""
var team: StringName = &""
var life_left: float = 0.0
var health_component: HealthComponent
var status_component: StatusEffectComponent
var hurtbox: HurtboxComponent
var _gone := false
var _age: float = 0.0


static func spawn(owner_node: Node2D, deploy_data: DeployData, at: Vector2, kind_id: StringName) -> Deployable:
	var node: Deployable = deploy_data.deployable_script.new()
	node.owner_actor = owner_node
	node.data = deploy_data
	node.kind = kind_id
	node.team = CombatQueries.team_of(owner_node)
	node.position = at
	owner_node.get_tree().current_scene.add_child(node)
	node.global_position = at
	return node


## This owner's deployables of `kind_id` (every kind if empty), oldest first.
static func find_owned(owner_node: Node, kind_id: StringName = &"") -> Array[Deployable]:
	var result: Array[Deployable] = []
	if owner_node == null or not owner_node.is_inside_tree():
		return result
	for node in owner_node.get_tree().get_nodes_in_group(GROUP):
		var d := node as Deployable
		if d != null and not d._gone and d.owner_actor == owner_node and (kind_id == &"" or d.kind == kind_id):
			result.append(d)
	return result


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"minimap_units")
	z_index = 1
	life_left = data.lifetime
	_build_body()
	if data.visual_scene != null:
		add_child(data.visual_scene.instantiate())
	var owner_health := _owner_health()
	if owner_health != null:
		owner_health.died.connect(remove.bind(&"owner_died"))
	_deploy_ready()


func _build_body() -> void:
	if data.deploy_health == null:
		return
	status_component = StatusEffectComponent.new()
	status_component.name = "StatusComponent"
	health_component = HealthComponent.new()
	health_component.name = "HealthComponent"
	health_component.max_health = maxf(data.deploy_health.evaluate(get_owner_stats()), 1.0)
	health_component.status_component = status_component
	status_component.health_component = health_component
	add_child(status_component)
	add_child(health_component)
	hurtbox = HurtboxComponent.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 16
	hurtbox.collision_mask = 0
	hurtbox.health_component = health_component
	hurtbox.status_component = status_component
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.body_radius
	shape.shape = circle
	hurtbox.add_child(shape)
	add_child(hurtbox)
	health_component.died.connect(remove.bind(&"destroyed"))
	health_component.health_changed.connect(func(_c, _m): queue_redraw())


func get_owner_stats() -> StatsComponent:
	return StatsComponent.find_on(owner_actor)


## A named value from the data, from the owner's stats.
func get_value(key: StringName) -> float:
	return data.get_value(key, get_owner_stats())


func get_age() -> float:
	return _age


func is_disabled() -> bool:
	return status_component != null and (status_component.is_stunned() or status_component.is_silenced())


func is_gone() -> bool:
	return _gone


## Remove it now (reason for the gone signal).
func remove(reason: StringName = &"removed") -> void:
	if _gone:
		return
	_gone = true
	_on_removed(reason)
	gone.emit(reason)
	if reason in [&"destroyed", &"expired"] and is_instance_valid(owner_actor) and owner_actor.has_method(&"trigger_cue"):
		owner_actor.trigger_cue(StringName("%s_%s" % [kind, reason]), {"position": global_position})
	queue_free()


func _physics_process(delta: float) -> void:
	if _gone:
		return
	if not is_instance_valid(owner_actor) or not owner_actor.is_inside_tree():
		remove(&"owner_died")
		return
	_age += delta
	if data.lifetime > 0.0:
		life_left -= delta
		if life_left <= 0.0:
			remove(&"expired")
			return
	_deploy_tick(delta)
	queue_redraw()


func _owner_health() -> HealthComponent:
	var health = owner_actor.get(&"health_component") if owner_actor != null else null
	return health if health is HealthComponent else null


# Enemies of the owner inside `radius`, nearest first (shots need a clear
# line: CombatQueries.shot_clear).
func find_enemies(radius: float, need_clear_shot: bool = true) -> Array[HurtboxComponent]:
	var found := Hitbox.query(self, global_position, Vector2.RIGHT, HitShape.circle(radius), owner_actor)
	found = found.filter(func(h: HurtboxComponent): return h.owner != self and h.get_parent() != self \
		and (not need_clear_shot or CombatQueries.shot_clear(self, h)))
	found.sort_custom(func(a, b): return a.global_position.distance_squared_to(global_position) \
		< b.global_position.distance_squared_to(global_position))
	return found


## Fire the data's projectile toward `direction` as the owner's damage.
func fire_projectile(direction: Vector2, damage: float, damage_type: DamageInfo.Type, label: StringName) -> Projectile:
	if data.projectile == null or direction == Vector2.ZERO:
		return null
	var template := DamageInfo.create(damage * StatusEffectComponent.multiplier_of(
		CombatQueries.status_of(owner_actor), StatusEffect.DAMAGE), owner_actor, damage_type)
	template.label = label
	template.tags = data.tags.duplicate()
	var origin := global_position + direction.normalized() * data.body_radius
	return Projectile.fire(self, data.projectile, origin, direction, template)


# Subclass hooks.
func _deploy_ready() -> void: pass
func _deploy_tick(_delta: float) -> void: pass
func _on_removed(_reason: StringName) -> void: pass


# Placeholder look: a disc in the data's colour, a team ring, a health arc.
func _draw() -> void:
	if data.visual_scene == null:
		draw_circle(Vector2.ZERO, data.body_radius, data.color)
		draw_arc(Vector2.ZERO, data.body_radius, 0.0, TAU, 24, MatchManager.team_color(team), 3.0, true)
	if health_component != null and health_component.max_health > 0.0:
		var ratio := health_component.get_health_ratio()
		draw_arc(Vector2.ZERO, data.body_radius + 8.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 24, Color(0.4, 1, 0.5, 0.9), 4.0, true)
	if data.lifetime > 0.0:
		var t := clampf(life_left / data.lifetime, 0.0, 1.0)
		draw_arc(Vector2.ZERO, data.body_radius + 14.0, -PI / 2.0, -PI / 2.0 + TAU * t, 24, Color(1, 1, 1, 0.35), 2.0, true)
