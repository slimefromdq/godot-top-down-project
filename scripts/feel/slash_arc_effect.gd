extends Node2D
class_name SlashArcEffect

# A swing drawn as a band that sweeps across the attack's arc, then fades.
# Spawned by a VisualCue on "<ability>_active"; it reads the swing's real
# reach and width from the cue context, so the picture always matches the
# hitbox the designer tuned.
#
# Context: radius, arc_degrees, step (alternates sweep direction per combo
# step), weight (heavier = thicker, brighter).

@export var color: Color = Color(1.0, 0.85, 0.45, 0.9)
@export var edge_color: Color = Color(1.0, 1.0, 0.9, 1.0)
## Inner edge of the band as a fraction of the radius.
@export_range(0.0, 1.0) var inner_ratio: float = 0.55
@export var sweep_time: float = 0.08
@export var fade_time: float = 0.18
@export var segments: int = 24

var radius: float = 150.0
var arc_degrees: float = 120.0
var weight: float = 1.0
var reverse := false
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	radius = context.get("radius", radius)
	arc_degrees = context.get("arc_degrees", arc_degrees)
	weight = context.get("weight", 1.0)
	reverse = int(context.get("step", 1)) % 2 == 0


func _process(delta: float) -> void:
	_t += delta
	if _t >= sweep_time + fade_time:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var half := deg_to_rad(arc_degrees) / 2.0
	var sweep := clampf(_t / maxf(sweep_time, 0.001), 0.0, 1.0)
	var fade := 1.0 - clampf((_t - sweep_time) / maxf(fade_time, 0.001), 0.0, 1.0)
	var from := -half if not reverse else half
	var to := lerpf(from, -from, sweep)
	var outer: PackedVector2Array = []
	var inner: PackedVector2Array = []
	var inner_r := radius * lerpf(inner_ratio, inner_ratio * 0.8, clampf(weight - 1.0, 0.0, 1.0))
	for i in segments + 1:
		var a := lerpf(from, to, float(i) / segments)
		outer.append(Vector2.from_angle(a) * radius)
		inner.append(Vector2.from_angle(a) * inner_r)
	inner.reverse()
	var band := outer + inner
	var c := color
	c.a *= fade
	if band.size() >= 3:
		draw_colored_polygon(band, c)
	var e := edge_color
	e.a *= fade
	draw_polyline(outer, e, 3.0 + 2.0 * weight, true)
