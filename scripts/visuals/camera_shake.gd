extends Camera2D
class_name ShakeCamera

# Trauma-based screen shake plus a directional nudge.
#
# Trauma (0-1) goes up when something hits and decays linearly; the shake
# offset is trauma SQUARED, so small hits barely register while big ones
# punch, and everything settles quickly. Smooth noise (instead of a new
# random offset every frame) keeps it from feeling jittery or nauseating.
# Strength, cap and speed all come from GameFeel.settings.
#
# The nudge is a separate, gentle lean in a direction (a swing), which eases
# back to centre on its own.
#
# Look-ahead shifts the view toward the cursor (the owner's aim) by a set
# distance, easing in and out: a scope. It's requested by a status on the
# owner (StatusEffect.camera_look_ahead) or by any script with
# request_look_ahead() / release_look_ahead(); the largest request wins. Only
# this camera's view moves: gameplay never reads it.

## Per-camera multiplier on top of the global setting (e.g. 0 for a cutscene).
@export_range(0.0, 2.0, 0.05) var shake_strength: float = 1.0
## Trauma lost per second.
@export var decay: float = 2.5
## How fast a nudge returns to centre (higher = snappier).
@export var nudge_return: float = 12.0
## Largest total nudge in pixels.
@export var max_nudge: float = 24.0
## How fast the view eases into and out of a look-ahead (higher = snappier).
@export var look_ahead_ease: float = 6.0

var _trauma: float = 0.0
var _nudge := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _time: float = 0.0
var _look := Vector2.ZERO
var _look_requests: Dictionary = {}    # requester -> distance


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = randi()


func add_trauma(amount: float) -> void:
	var cap := GameFeel.settings.max_trauma if GameFeel.settings != null else 1.0
	_trauma = minf(_trauma + amount, cap)


func get_trauma() -> float:
	return _trauma


func nudge(direction: Vector2, distance: float) -> void:
	if direction == Vector2.ZERO:
		return
	_nudge = (_nudge + direction.normalized() * distance).limit_length(max_nudge)


# Lean the view `distance` px toward the cursor until released.
func request_look_ahead(requester: Object, distance: float) -> void:
	_look_requests[requester] = distance


func release_look_ahead(requester: Object) -> void:
	_look_requests.erase(requester)


# The look-ahead distance wanted right now (statuses and requests).
func get_look_ahead_distance() -> float:
	var distance := 0.0
	for requester in _look_requests.keys():
		if is_instance_valid(requester):
			distance = maxf(distance, _look_requests[requester])
		else:
			_look_requests.erase(requester)
	var status := CombatQueries.status_of(get_parent())
	if status != null:
		distance = maxf(distance, status.get_camera_look_ahead())
	return distance


# The current (eased) look-ahead offset.
func get_look_offset() -> Vector2:
	return _look


func _process(delta: float) -> void:
	_time += delta
	_trauma = maxf(_trauma - decay * delta, 0.0)
	var settings: FeelSettings = GameFeel.settings
	var intensity := shake_strength * (settings.shake_intensity if settings != null else 1.0)
	var power := _trauma * _trauma * intensity
	var frequency := settings.shake_frequency if settings != null else 18.0
	var max_offset := settings.max_shake_offset if settings != null else Vector2(16, 12)
	var shake := Vector2(
		max_offset.x * power * _noise.get_noise_2d(_time * frequency * 10.0, 0.0),
		max_offset.y * power * _noise.get_noise_2d(0.0, _time * frequency * 10.0))
	_nudge = _nudge.lerp(Vector2.ZERO, 1.0 - exp(-nudge_return * delta))
	var aim = get_parent().get(&"aim_direction") if get_parent() != null else null
	var wanted := Vector2.ZERO
	if aim is Vector2 and aim != Vector2.ZERO:
		wanted = aim.normalized() * get_look_ahead_distance()
	_look = _look.lerp(wanted, 1.0 - exp(-look_ahead_ease * delta))
	offset = shake + _nudge + _look
