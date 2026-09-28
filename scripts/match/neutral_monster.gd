extends CharacterBody2D
class_name NeutralMonster

# A neutral objective's body (scenes/match/neutral_monster.tscn): a jungle
# camp's monster or the Nightmare, set up from a NeutralData. The
# ObjectiveDirector spawns it through its NeutralCamp and pays out when it
# dies; this script only fights.
#
# It's on the "neutral" team, so both teams can hit it and it never hits
# other neutrals. Idle until hit; then it fights whoever hit it last:
#   * a volley at them every attack_interval while they're in range, and a
#     ring of bolts every ring_interval (0 = none);
#   * with move_speed above 0 it walks toward them when out of range;
#   * it gives up (walks home, heals, see reset_heal_fraction) when they die, leave
#     leash_radius of its home, or nobody has hit it for reset_time.
#
# Like the training dummy it isn't an Actor: any node with the components
# works in the damage pipeline. Cues through the match profiles:
# <id>_attack, <id>_ring, neutral_reset.

signal slain(killer: Hero)

const TEAM := &"neutral"
const GROUP := &"neutral_monsters"
## Walking home, when move_speed is 0.
const HOME_SPEED := 260.0

@export var data: NeutralData
@export_range(1, 20) var level: int = 1
## The team it's on. Heroes are on "a" and "b", so both can hit it.
var team: StringName = TEAM
var camp: Node2D
var home := Vector2.ZERO
var target: Hero
var aim_direction := Vector2.DOWN

@onready var health_component: HealthComponent = $Components/HealthComponent
@onready var status_component: StatusEffectComponent = $Components/StatusComponent
@onready var movement_component: MovementComponent = $Components/MovementComponent
@onready var stats_component: StatsComponent = $Components/StatsComponent
@onready var visuals: VisualsComponent = $Visuals
@onready var hurtbox: HurtboxComponent = $Hurtbox

var _attack_left: float = 0.0
var _ring_left: float = 0.0
var _since_hit: float = 0.0
var _returning := false


# Stats before HealthComponent reads them (see Hero._enter_tree).
func _enter_tree() -> void:
	var stats := get_node(^"Components/StatsComponent") as StatsComponent
	if data != null and data.stats != null:
		stats.stat_block = data.stats.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stats.level = level


func _ready() -> void:
	add_to_group(GROUP)
	collision_mask |= MapLayers.BARRIERS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if home == Vector2.ZERO:
		home = global_position
	if data == null:
		data = NeutralData.new()
	movement_component.move_speed = maxf(data.move_speed, HOME_SPEED)
	_fit_to_size(data.size * 0.5)
	health_component.damage_taken.connect(_on_damage_taken)
	health_component.died.connect(_on_died)
	if data.look_scene != null:
		var look := data.look_scene.instantiate()
		visuals.add_child(look)
		if look.has_method(&"setup_neutral"):
			look.setup_neutral(self)
	_attack_left = data.attack_interval
	_ring_left = data.ring_interval


# Body, hurtbox and health bar sized to the data (own shapes per instance).
func _fit_to_size(radius: float) -> void:
	var body := CircleShape2D.new()
	body.radius = radius * 0.6    # small enough to reach a Mote under it
	($CollisionShape2D as CollisionShape2D).shape = body
	var hurt := CircleShape2D.new()
	hurt.radius = radius
	($Hurtbox/CollisionShape2D as CollisionShape2D).shape = hurt
	var bar := get_node_or_null(^"HealthBar") as Control
	if bar != null:
		var half := clampf(radius, 40.0, 160.0)
		bar.offset_left = -half
		bar.offset_right = half
		bar.offset_top = -radius - 34.0
		bar.offset_bottom = bar.offset_top + (14.0 if radius >= 60.0 else 10.0)


func is_fighting() -> bool:
	return target != null


func is_returning() -> bool:
	return _returning


func _physics_process(delta: float) -> void:
	if health_component.is_dead():
		return
	_since_hit += delta
	if target != null and not _still_fighting(target):
		_give_up()
	var steer := Vector2.ZERO
	if target != null:
		var to_target := target.global_position - global_position
		aim_direction = to_target.normalized() if to_target.length() > 1.0 else aim_direction
		if data.move_speed > 0.0 and to_target.length() > data.attack_range * 0.8:
			steer = to_target.normalized()
		_tick_attacks(delta)
	else:
		var to_home := home - global_position
		if to_home.length() > 8.0:
			steer = to_home.normalized() * clampf(to_home.length() / 60.0, 0.0, 1.0)
		elif _returning:
			_returning = false
	velocity = movement_component.get_velocity(velocity, steer, delta)
	move_and_slide()


func _still_fighting(hero: Hero) -> bool:
	if not is_instance_valid(hero) or not hero.is_inside_tree() or hero.health_component.is_dead():
		return false
	if hero.global_position.distance_to(home) > data.leash_radius:
		return false
	return _since_hit <= data.reset_time


# Drop the fight: walk home and heal (to full by default, reset_heal_fraction
# of missing HP), so poking it from outside the leash never whittles it down.
func _give_up() -> void:
	target = null
	_returning = true
	status_component.clear()
	if data.reset_heal_fraction >= 1.0:
		health_component.reset()
	else:
		var missing := health_component.max_health - health_component.current_health
		health_component.heal(missing * data.reset_heal_fraction, self)
		health_component.last_damage_source = null
	MatchManager.play_world_cue(self, &"neutral_reset", {"position": global_position})


func _tick_attacks(delta: float) -> void:
	if status_component.is_stunned():
		return
	_attack_left -= delta
	if _attack_left <= 0.0:
		_attack_left = data.attack_interval
		if global_position.distance_to(target.global_position) <= data.attack_range:
			fire_volley(aim_direction)
	if data.ring_interval > 0.0 and data.ring_count > 0:
		_ring_left -= delta
		if _ring_left <= 0.0:
			_ring_left = data.ring_interval
			fire_ring()


## Bolts fanned around `direction` (volley_count over volley_spread degrees).
func fire_volley(direction: Vector2) -> void:
	var count := maxi(data.volley_count, 1)
	var spread := deg_to_rad(data.volley_spread)
	for i in count:
		var offset := 0.0 if count == 1 else lerpf(-spread / 2.0, spread / 2.0, float(i) / (count - 1))
		_fire(direction.rotated(offset))
	MatchManager.play_world_cue(self, StringName("%s_attack" % data.id), {"position": global_position})


## A ring of ring_count bolts all around.
func fire_ring() -> void:
	var start := randf() * TAU
	for i in data.ring_count:
		_fire(Vector2.from_angle(start + TAU * i / data.ring_count))
	MatchManager.play_world_cue(self, StringName("%s_ring" % data.id),
		{"position": global_position, "radius": data.size * 1.5})


func _fire(direction: Vector2) -> void:
	if data.attack_projectile == null:
		return
	var damage := data.attack_damage.evaluate(stats_component) if data.attack_damage != null else 0.0
	var template := DamageInfo.create(damage, self, data.attack_damage_type)
	template.label = StringName("%s_bolt" % data.id)
	Projectile.fire(self, data.attack_projectile, global_position + direction * (data.size * 0.8 + 20.0),
		direction, template)


func _on_damage_taken(info: DamageInfo) -> void:
	var hero := hero_of(info.source)
	if hero == null:
		return
	_since_hit = 0.0
	_returning = false
	if target == null:
		_attack_left = minf(_attack_left, 0.4)    # answer quickly
	target = hero


func _on_died() -> void:
	var killer := hero_of(health_component.last_damage_source)
	target = null
	hurtbox.set_deferred("monitorable", false)
	collision_layer = 0
	set_physics_process(false)
	slain.emit(killer)
	var tween := create_tween()
	tween.tween_property(visuals, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


func trigger_cue(cue: StringName, context: Dictionary = {}) -> void:
	context.merge({"position": global_position, "source": self})
	MatchManager.play_world_cue(self, cue, context)


# The hero behind a damage source (the hero, or its projectile / zone).
static func hero_of(source: Node) -> Hero:
	var node := source
	while node != null and is_instance_valid(node):
		if node is Hero:
			return node
		node = node.get_parent()
	return null
