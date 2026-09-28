extends Node2D
class_name DreamerGlow

# A soft team-coloured glow on the ground around a Dreamer: faint while it
# sleeps, brighter as its wake meter fills, and pulsing while it stirs.
# Made by MapAmbience from the AmbienceSet's Dreamer Glow values; reads the
# Dreamer, never changes it.

const RINGS := 10

var dreamer: Dreamer
var settings: AmbienceSet
var _t := 0.0


func setup(p_dreamer: Dreamer, p_settings: AmbienceSet) -> void:
	dreamer = p_dreamer
	settings = p_settings
	z_index = -1


func get_strength() -> float:
	if dreamer == null or not is_instance_valid(dreamer):
		return 0.0
	var a := lerpf(settings.glow_alpha_asleep, settings.glow_alpha_full, dreamer.get_wake_ratio())
	if dreamer.is_stirring():
		var pulse := 0.5 + 0.5 * sin(_t * TAU * settings.stir_pulse_speed)
		a *= 1.0 + settings.stir_pulse_amount * pulse
	return clampf(a, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	if dreamer == null or not is_instance_valid(dreamer):
		queue_free()
		return
	global_position = dreamer.global_position
	visible = VisualToggles.is_on(&"dreamer_glow")
	if visible and ScreenCull.is_near(self, settings.glow_radius):
		queue_redraw()


func _draw() -> void:
	var col: Color = MatchManager.TEAM_COLORS.get(dreamer.team, Color.WHITE)
	var strength := get_strength()
	# Stacked translucent discs fake a radial falloff.
	for i in RINGS:
		var f := float(i + 1) / RINGS
		var c := col
		c.a = strength / RINGS
		draw_circle(Vector2.ZERO, settings.glow_radius * f, c)
