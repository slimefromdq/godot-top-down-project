extends CharacterBody2D
class_name TrainingDummy

# A target for testing damage, abilities and game feel. It isn't an Actor: it
# shows that VisualsComponent, AudioComponent, StatsComponent and the damage
# pipeline work on any node with a HealthComponent.
#
# It's a moving body (not a static one) so knockback and pulls visibly shove
# it; it then walks back to where it was placed. It regenerates after a short
# break in damage, reports DPS, and can either die and respawn (to preview
# death and kill effects) or be unkillable (it cancels its own death through
# the same about_to_die hook a revive uses).

signal cue_triggered(cue: StringName, context: Dictionary)

## When false, health stops at 1 instead of dying.
@export var can_die: bool = true
@export var respawn_delay: float = 2.0
## Seconds without damage before health refills.
@export var reset_delay: float = 3.0
## Window used for the DPS readout.
@export var dps_window: float = 3.0
## Team id. Empty = neutral (anyone can hit it).
@export var team: StringName = &""

@export_group("Stats")
@export var max_health: float = 300.0
@export var armor: float = 0.0
@export var magic_resist: float = 0.0
## Only matters for dummies that fight back (their attacks scale with it).
@export_range(1, 20) var level: int = 1

@export_group("Fight back")
## Shoot at the nearest hero in range. Toggle live with set_fight_back().
@export var fight_back: bool = false
## Team used while fighting back, so fighting dummies don't shoot each other.
@export var fight_back_team: StringName = &"dummies"
@export var attack_projectile: ProjectileData = preload("res://resources/dummies/dummy_bolt.tres")
@export var attack_interval: float = 1.5
@export var attack_range: float = 800.0
## Damage per bolt at level 1, plus attack_damage_per_level for each level above.
@export var attack_damage: float = 30.0
@export var attack_damage_per_level: float = 6.0
@export var attack_damage_type: DamageInfo.Type = DamageInfo.Type.PHYSICAL
## Bolts start this far out, clear of the dummy's own body.
@export var attack_spawn_offset: float = 60.0

@export_group("Anchor")
## Walks back to its spawn point after being displaced.
@export var return_to_anchor: bool = true
## Within this distance of the anchor it stands still.
@export var anchor_tolerance: float = 6.0
## Slows down over this distance as it arrives (no overshoot wobble).
@export var anchor_slowdown_distance: float = 60.0

@export_group("Ally")
## Walk back and forth between the anchor and anchor + patrol_offset, so
## move-speed buffs and slows show. Zero = stand still. Displacement
## (knockback, pulls) still works; it resumes the walk afterwards.
@export var patrol_offset: Vector2 = Vector2.ZERO
## Replace the DPS readout with the buffs it's under (move speed, fire rate,
## damage multipliers and shield): for an ally dummy on the player's team.
@export var buff_readout: bool = false

@onready var health_component: HealthComponent = $Components/HealthComponent
@onready var status_component: StatusEffectComponent = $Components/StatusComponent
@onready var movement_component: MovementComponent = $Components/MovementComponent
@onready var stats_component: StatsComponent = $Components/StatsComponent
@onready var visuals: VisualsComponent = $Visuals
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var dps_label: Label = $DpsLabel

var aim_direction := Vector2.DOWN
var anchor := Vector2.ZERO
# Patrolling: heading to anchor + patrol_offset (true) or back to the anchor.
var _patrol_out: bool = true

var _time_since_damage: float = 0.0
# Damage since the dummy last reset to full health.
var _total_taken: float = 0.0
var _attack_timer: float = 0.0
var _team_before_fighting: StringName = &""
var _damage_log: Array[Vector2] = []    # (time, amount) pairs
var _time: float = 0.0


# Build the stat block from the exported numbers before the health component
# reads it (see Hero._enter_tree for why this happens in _enter_tree).
func _enter_tree() -> void:
	var stats := get_node(^"Components/StatsComponent") as StatsComponent
	if stats.stat_block == null:
		stats.stat_block = make_stat_block()
	stats.level = level


func _ready() -> void:
	add_to_group(&"minimap_units")
	add_to_group(&"training_dummies")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	anchor = global_position
	health_component.damaged.connect(_on_damaged)
	health_component.about_to_die.connect(_on_about_to_die)
	health_component.died.connect(_on_died)
	_team_before_fighting = team
	set_fight_back(fight_back)
	if buff_readout:
		dps_label.grow_horizontal = Control.GROW_DIRECTION_BOTH    # longer text stays centred


# Live reconfiguration (debug panel): new HP / resistances / level.
func configure(new_max_health: float, new_armor: float, new_magic_resist: float, new_level: int) -> void:
	max_health = new_max_health
	armor = new_armor
	magic_resist = new_magic_resist
	level = new_level
	stats_component.stat_block = make_stat_block()
	stats_component.level = level
	stats_component.stats_changed.emit()
	health_component.reset()


func set_fight_back(enabled: bool) -> void:
	fight_back = enabled
	team = fight_back_team if enabled else _team_before_fighting
	_attack_timer = attack_interval


# On a team of its own (not neutral), e.g. the ally dummy on the player's team.
func is_teamed() -> bool:
	return _team_before_fighting != &""


func make_stat_block() -> StatBlock:
	var block := StatBlock.new()
	block.health = StatScaling.make(max_health)
	block.armor = StatScaling.make(armor)
	block.magic_resist = StatScaling.make(magic_resist)
	block.weapon = StatScaling.make(0.0)
	block.magic = StatScaling.make(0.0)
	return block


func _physics_process(delta: float) -> void:
	var to_anchor := get_patrol_target() - global_position
	var steer := Vector2.ZERO
	if patrol_offset != Vector2.ZERO and to_anchor.length() <= anchor_tolerance:
		_patrol_out = not _patrol_out
		to_anchor = get_patrol_target() - global_position
	if patrol_offset != Vector2.ZERO:
		steer = to_anchor.normalized()    # full speed: the walk is the readout
	elif return_to_anchor and to_anchor.length() > anchor_tolerance:
		steer = to_anchor.normalized() * clampf(to_anchor.length() / anchor_slowdown_distance, 0.0, 1.0)
	velocity = movement_component.get_velocity(velocity, steer, delta)
	move_and_slide()
	if fight_back and not health_component.is_dead():
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_interval
			_shoot_nearest_hero()


func _shoot_nearest_hero() -> void:
	if attack_projectile == null or status_component.is_stunned():
		return
	var best: Node2D = null
	var best_distance := attack_range
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var hero := node as Hero
		if hero == null or hero.health_component.is_dead() or hero.team == team:
			continue
		var distance := global_position.distance_to(hero.global_position)
		if distance <= best_distance:
			best = hero
			best_distance = distance
	if best == null:
		return
	aim_direction = (best.global_position - global_position).normalized()
	var damage := attack_damage + attack_damage_per_level * (level - 1)
	var template := DamageInfo.create(damage, self, attack_damage_type)
	template.label = &"dummy_bolt"
	Projectile.fire(self, attack_projectile, global_position + aim_direction * attack_spawn_offset, aim_direction, template)


func _process(delta: float) -> void:
	_time += delta
	_time_since_damage += delta
	if _time_since_damage >= reset_delay and not health_component.is_dead() \
			and health_component.current_health < health_component.max_health:
		health_component.reset()
		_total_taken = 0.0

	_damage_log = _damage_log.filter(func(entry): return _time - entry.x <= dps_window)
	var total := 0.0
	for entry in _damage_log:
		total += entry.y
	if buff_readout:
		dps_label.text = get_buff_text()
	else:
		dps_label.text = "DPS %d   total %d" % [roundi(total / dps_window), roundi(_total_taken)]


# Where it's walking to: the anchor, or the far end of its patrol.
func get_patrol_target() -> Vector2:
	return anchor + patrol_offset if patrol_offset != Vector2.ZERO and _patrol_out else anchor


# "speed x1.35  fire x1.20  shield 80", only the stats that are buffed or
# debuffed; "no buffs" otherwise.
func get_buff_text() -> String:
	var parts: PackedStringArray = []
	for stat in [[StatusEffect.MOVE_SPEED, "speed"], [StatusEffect.FIRE_RATE, "fire"], [StatusEffect.DAMAGE, "damage"]]:
		var multiplier := status_component.get_multiplier(stat[0])
		if not is_equal_approx(multiplier, 1.0):
			parts.append("%s x%.2f" % [stat[1], multiplier])
	var shield := status_component.get_shield_total()
	if shield > 0.0:
		parts.append("shield %d" % roundi(shield))
	return "  ".join(parts) if not parts.is_empty() else "no buffs"


func trigger_cue(cue: StringName, context: Dictionary = {}) -> void:
	context.merge({"position": global_position, "source": self})
	cue_triggered.emit(cue, context)


func _on_damaged(amount: float, _source: Node) -> void:
	_time_since_damage = 0.0
	_total_taken += amount
	_damage_log.append(Vector2(_time, amount))


func _on_about_to_die(event: DeathEvent) -> void:
	if not can_die:
		event.cancel(1.0, self)


func _on_died() -> void:
	status_component.clear()
	visuals.hide()
	hurtbox.set_deferred("monitorable", false)
	collision_layer = 0
	await get_tree().create_timer(respawn_delay, false).timeout
	if not is_inside_tree():
		return
	global_position = anchor
	health_component.reset()
	collision_layer = 2
	hurtbox.set_deferred("monitorable", true)
	visuals.show()
	visuals.revive()
