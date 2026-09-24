extends StaticBody2D
class_name TrainingDummy

# A stationary target for testing damage, abilities and visuals. It isn't an
# Actor: it shows that VisualsComponent and AudioComponent work on any node
# that has a HealthComponent (and, optionally, a cue_triggered signal).
#
# It regenerates after a short break in damage, reports DPS, and can either
# die and respawn (to preview death and kill effects) or be unkillable.

signal cue_triggered(cue: StringName, context: Dictionary)

## When false, health stops at 1 instead of dying.
@export var can_die: bool = true
@export var respawn_delay: float = 2.0
## Seconds without damage before health refills.
@export var reset_delay: float = 3.0
## Window used for the DPS readout.
@export var dps_window: float = 3.0

@onready var health_component: HealthComponent = $Components/HealthComponent
@onready var status_component: StatusEffectComponent = $Components/StatusComponent
@onready var visuals: VisualsComponent = $Visuals
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var dps_label: Label = $DpsLabel

var _time_since_damage: float = 0.0
var _damage_log: Array[Vector2] = []    # (time, amount) pairs
var _time: float = 0.0


func _ready() -> void:
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)


func _process(delta: float) -> void:
	_time += delta
	_time_since_damage += delta
	if _time_since_damage >= reset_delay and not health_component.is_dead() \
			and health_component.current_health < health_component.max_health:
		health_component.reset()

	_damage_log = _damage_log.filter(func(entry): return _time - entry.x <= dps_window)
	var total := 0.0
	for entry in _damage_log:
		total += entry.y
	dps_label.text = "DPS %d" % roundi(total / dps_window)


func trigger_cue(cue: StringName, context: Dictionary = {}) -> void:
	context.merge({"position": global_position, "source": self})
	cue_triggered.emit(cue, context)


func _on_damaged(amount: float, _source: Node) -> void:
	_time_since_damage = 0.0
	_damage_log.append(Vector2(_time, amount))
	if not can_die and health_component.current_health <= 1.0:
		health_component.current_health = 1.0


func _on_died() -> void:
	if not can_die:
		return
	status_component.clear()
	visuals.hide()
	hurtbox.set_deferred("monitorable", false)
	collision_layer = 0
	await get_tree().create_timer(respawn_delay, false).timeout
	health_component.reset()
	collision_layer = 2
	hurtbox.set_deferred("monitorable", true)
	visuals.show()
	visuals.revive()
