extends Node2D
class_name SlashTrail

# The visible swing: a band that sweeps across the attack's real arc over the
# real active frames, with fire thrown off the blade tip, then fades.
#
# FeelComponent spawns it on the hero's VisualsComponent at the moment the
# active frames start, so it rides along with the lunge and freezes together
# with the hero during hitstop (it reads the visuals' time scale).
#
# Context (setup_cue): radius, arc_degrees, step (even steps sweep the other
# way), duration (active time), color, width, particles, visuals.

@export var inner_ratio: float = 0.55
@export var fade_time: float = 0.16
@export var min_sweep_time: float = 0.05
@export var segments: int = 28
@export var edge_color: Color = Color(1.0, 1.0, 0.92, 1.0)
@export var ember_gradient: Gradient

var radius: float = 150.0
var arc_degrees: float = 120.0
var color: Color = Color(1.0, 0.85, 0.45, 0.9)
var width: float = 1.0
var reverse := false
var sweep_time: float = 0.08
var visuals: VisualsComponent

var _t: float = 0.0
var _embers: CPUParticles2D


func setup_cue(context: Dictionary) -> void:
	radius = context.get("radius", radius)
	arc_degrees = context.get("arc_degrees", arc_degrees)
	color = context.get("color", color)
	width = context.get("width", width)
	reverse = int(context.get("step", 1)) % 2 == 0
	sweep_time = maxf(context.get("duration", sweep_time), min_sweep_time)
	visuals = context.get("visuals")
	var particles: int = context.get("particles", 0)
	if particles > 0:
		_make_embers(particles)


func _process(delta: float) -> void:
	var scale_t := visuals.get_time_scale() if is_instance_valid(visuals) else 1.0
	_t += delta * scale_t
	if _embers != null:
		_embers.speed_scale = maxf(scale_t, 0.001)
		_embers.position = _tip()
		_embers.emitting = _t < sweep_time
	if _t >= sweep_time + fade_time + (_embers.lifetime if _embers != null else 0.0):
		queue_free()
	queue_redraw()


func _angles() -> Vector2:
	var half := deg_to_rad(arc_degrees) / 2.0
	return Vector2(half, -half) if reverse else Vector2(-half, half)


func _tip() -> Vector2:
	var a := _angles()
	var sweep := clampf(_t / sweep_time, 0.0, 1.0)
	return Vector2.from_angle(lerpf(a.x, a.y, sweep)) * radius


func _draw() -> void:
	var fade := 1.0 - clampf((_t - sweep_time) / fade_time, 0.0, 1.0)
	if fade <= 0.0:
		return
	var a := _angles()
	var sweep := clampf(_t / sweep_time, 0.0, 1.0)
	# Ease-out: the blade is fastest at the start of the swing.
	var eased := 1.0 - pow(1.0 - sweep, 2.0)
	var to := lerpf(a.x, a.y, eased)
	var inner_r := radius * lerpf(1.0, inner_ratio, clampf(width, 0.0, 2.0) / 2.0 + 0.25)
	var outer: PackedVector2Array = []
	var inner: PackedVector2Array = []
	var colors: PackedColorArray = []
	for i in segments + 1:
		var k := float(i) / segments
		var angle := lerpf(a.x, to, k)
		outer.append(Vector2.from_angle(angle) * radius)
		inner.append(Vector2.from_angle(angle) * inner_r)
	# Older part of the trail (k near 0) is fainter than the blade edge.
	var band: PackedVector2Array = outer.duplicate()
	var rev := inner.duplicate()
	rev.reverse()
	band.append_array(rev)
	for i in band.size():
		var k := float(i if i <= segments else band.size() - 1 - i) / segments
		var c := color
		c.a *= fade * lerpf(0.15, 1.0, k)
		colors.append(c)
	if band.size() >= 3 and to != a.x:
		draw_polygon(band, colors)
	var e := edge_color
	e.a *= fade
	draw_polyline(outer, e, 2.0 + 2.5 * width, true)


func _make_embers(amount: int) -> void:
	_embers = CPUParticles2D.new()
	_embers.amount = amount
	_embers.lifetime = 0.35
	_embers.local_coords = false
	_embers.spread = 60.0
	_embers.gravity = Vector2(0, -60)
	_embers.initial_velocity_min = 60.0
	_embers.initial_velocity_max = 180.0
	_embers.damping_min = 120.0
	_embers.damping_max = 200.0
	_embers.scale_amount_min = 3.0
	_embers.scale_amount_max = 7.0
	_embers.color_ramp = ember_gradient
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = material
	_embers.position = _tip()
	add_child(_embers)
