extends Node2D

# Cosmetic, the abducted status's attached_vfx, drawn for everyone: a chrome
# UFO with a bubble dome floating over the victim (the victim is under it),
# a ground shadow where they'll drop, and a little name tag of who's inside
# so their team can follow.

var _status: StatusEffectComponent
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	_status = context.get("status_component")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var bob := sin(_t * 4.0) * 6.0
	draw_set_transform(Vector2(0, 40), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 70.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	var hull := Vector2(0, -150 + bob)
	draw_set_transform(hull, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 80.0, Color(0.82, 0.85, 0.92))
	draw_set_transform(Vector2.ZERO)
	draw_circle(hull + Vector2(0, -18), 30.0, Color(0.7, 0.95, 1.0, 0.6))
	# The beam holding them.
	draw_colored_polygon(PackedVector2Array([hull + Vector2(-30, 10), hull + Vector2(30, 10), Vector2(50, 30), Vector2(-50, 30)]),
		Color(0.6, 1.0, 0.8, 0.18))
	var who := _status.owner if _status != null else null
	var name_tag: String = str(who.get(&"definition").display_name) if who != null and who.get(&"definition") != null \
		else (str(who.name) if who != null else "?")
	draw_string(ThemeDB.fallback_font, hull + Vector2(-60, -48), name_tag, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color.WHITE)
