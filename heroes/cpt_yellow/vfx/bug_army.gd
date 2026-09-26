extends Node2D

# Cosmetic only: Cpt. Yellow's body IS his army. A mound of bugs under the
# commander, one bug per slice of health: losing HP knocks bugs off (they
# scatter and fade), healing brings them flying back into place. No gameplay
# reads this.
#
# Spawned by the "spawn" cue (attached to the actor). A second spawn cue
# (a revive) finds the existing army and leaves it alone.

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")
const META := &"cpt_yellow_bug_army"

## Bugs at full health.
@export var bug_count: int = 28
## Bugs still shown at 1 HP, so he never looks empty while alive.
@export var min_bugs: int = 3
@export var mound_radius: Vector2 = Vector2(66, 36)
@export var mound_offset: Vector2 = Vector2(0, 14)
@export var bug_size: float = 20.0
@export var fall_time: float = 0.6
@export var rejoin_time: float = 0.35

var _health: HealthComponent
var _slots: Array[Vector2] = []
var _shown: int = 0
# Per slot: seconds left of its rejoin flight (0 = seated).
var _rejoin: Array[float] = []
# Falling bugs: [position, velocity, age].
var _falling: Array = []
var _t := 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	var visuals = context.get("visuals")
	if visuals is VisualsComponent:
		var existing = visuals.get_meta(META) if visuals.has_meta(META) else null
		if is_instance_valid(existing) and existing != self:
			queue_free()
			return
		visuals.set_meta(META, self)
		_health = visuals.health_component
	_build_slots()
	_shown = _target_count()
	if _health != null:
		_health.health_changed.connect(func(_c, _m): _sync())


# Golden-angle scatter inside the mound ellipse, back rows first so the
# front bugs overlap them.
func _build_slots() -> void:
	_slots.clear()
	for i in bug_count:
		var r := sqrt((i + 0.5) / bug_count)
		var a := i * 2.39996
		_slots.append(mound_offset + Vector2(cos(a) * mound_radius.x, sin(a) * mound_radius.y) * r)
	_slots.sort_custom(func(p, q): return p.y < q.y)
	_rejoin.resize(bug_count)
	_rejoin.fill(0.0)


func get_shown_count() -> int:
	return _shown


func _target_count() -> int:
	if _health == null or _health.is_dead():
		return 0 if _health != null else bug_count
	return clampi(ceili(bug_count * _health.get_health_ratio()), min_bugs, bug_count)


func _sync() -> void:
	var target := _target_count()
	while _shown > target:
		_shown -= 1
		var slot := _slots[_shown]
		var away := (slot - mound_offset).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		_falling.append([slot, (away + Vector2(randf_range(-0.4, 0.4), 0.6)) * randf_range(180.0, 300.0), 0.0])
	while _shown < target:
		_rejoin[_shown] = rejoin_time
		_shown += 1


func _process(delta: float) -> void:
	_t += delta
	for i in _shown:
		_rejoin[i] = maxf(_rejoin[i] - delta, 0.0)
	for bug in _falling:
		bug[2] += delta
		bug[1] += Vector2(0, 700.0) * delta
		bug[0] += bug[1] * delta
	_falling = _falling.filter(func(b): return b[2] < fall_time)
	queue_redraw()


func _draw() -> void:
	for i in _shown:
		var at := _slots[i] + Vector2(sin(_t * 7.0 + i), cos(_t * 9.0 + i * 1.7)) * 2.0
		var k := _rejoin[i] / rejoin_time if rejoin_time > 0.0 else 0.0
		if k > 0.0:
			# Flying back in from outside the mound.
			var from := _slots[i] + (_slots[i] - mound_offset).normalized() * 160.0 + Vector2(0, -60)
			at = at.lerp(from, k * k)
		var facing := Vector2.RIGHT.rotated(i * 1.3 + sin(_t * 2.0 + i) * 0.4)
		Bug.draw_bug(self, at, facing, bug_size, 1.0, 0.5 + 0.5 * sin(_t * 40.0 + i))
	for bug in _falling:
		var fade: float = 1.0 - bug[2] / fall_time
		Bug.draw_bug(self, bug[0], (bug[1] as Vector2).rotated(bug[2] * 12.0), bug_size, fade, 0.0)
