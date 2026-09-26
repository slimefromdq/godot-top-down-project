extends Node2D

# Cosmetic, the Beloved mark's attached_vfx. Who sees what (LocalView):
#   the Beloved and Pike        a big heart over the Beloved's head
#   the Beloved's teammates     a small one
#   everyone else               nothing
# It beats faster the closer Pike is, and glows once she's within glow_range
# (her teleport range).

@export var glow_range: float = 900.0
@export var color := Color(1.0, 0.4, 0.68)

var _status: StatusEffectComponent
var _status_id: StringName
var _beat: float = 0.0


func setup_cue(context: Dictionary) -> void:
	_status = context.get("status_component")
	_status_id = context.get("status_id", &"")


func _process(delta: float) -> void:
	var pike := _pike()
	var target := _status.owner as Node2D if _status != null else null
	var distance := pike.global_position.distance_to(target.global_position) if pike != null and target != null else 2000.0
	_beat += delta * lerpf(6.0, 1.5, clampf(distance / 1500.0, 0.0, 1.0))
	queue_redraw()


func _pike() -> Node2D:
	return _status.get_applier(_status_id) as Node2D if _status != null else null


# 1 = big, 0.5 = small, 0 = hidden, for the local viewer.
func get_size_for_viewer() -> float:
	var viewer := LocalView.get_viewer()
	var target := _status.owner if _status != null else null
	if viewer == null or viewer == target or viewer == _pike():
		return 1.0
	var team := CombatQueries.team_of(target)
	return 0.5 if team != &"" and CombatQueries.team_of(viewer) == team else 0.0


func _draw() -> void:
	var size := get_size_for_viewer()
	if size <= 0.0:
		return
	var pulse := 1.0 + 0.12 * maxf(sin(_beat * TAU), 0.0)
	var scale_px := 16.0 * size * pulse
	var at := Vector2(0, -130.0 if size >= 1.0 else -115.0)
	var pike := _pike()
	var target := _status.owner as Node2D if _status != null else null
	if pike != null and target != null and pike.global_position.distance_to(target.global_position) <= glow_range:
		draw_circle(at, scale_px * 1.9, Color(color, 0.25))
	draw_circle(at + Vector2(-scale_px * 0.5, 0), scale_px * 0.6, color)
	draw_circle(at + Vector2(scale_px * 0.5, 0), scale_px * 0.6, color)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-scale_px * 1.08, scale_px * 0.18),
		at + Vector2(scale_px * 1.08, scale_px * 0.18), at + Vector2(0, scale_px * 1.3)]), color)
