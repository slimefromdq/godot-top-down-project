extends Node2D
class_name TeamIndicator

# Who is who, at a glance. Every Hero gets one (Hero._ready):
#
#   * a ring on the ground under the hero in its team colour
#     (MatchManager.team_color: Dawn mint, Dusk coral). The local player's
#     ring is thicker, with a white rim, so you can always find yourself;
#   * a nameplate above the health bar (the hero's display name, in the team
#     colour; "You" is added for the local player);
#   * the health bar's fill in the team colour;
#   * a pointer on the ring showing where the hero is aiming (the placeholder
#     bodies don't flip, so their letters stay readable).
#
# Pure presentation: it reads the hero's team every frame (the debug "Play as
# team" switch can change it) and never touches gameplay. It sits under the
# hero, so it hides with it (death, bushes).

@export var ring_radius: float = 64.0
@export var ring_width: float = 6.0
@export var local_ring_width: float = 9.0
@export var fill_alpha: float = 0.16
@export var nameplate_offset: Vector2 = Vector2(-80, -118)
@export var nameplate_font_size: int = 17
@export var no_team_color := Color(0.85, 0.85, 0.9)
## The ring is drawn more saturated than the HUD team colour, so it reads on
## its own team's pastel floor.
@export var ring_saturation_boost: float = 0.3
@export var pointer_size: float = 15.0

var hero: Hero
var _label: Label
var _bar_fill: StyleBoxFlat
var _team: StringName = &"?"
var _local := false


func _ready() -> void:
	hero = get_parent() as Hero
	z_index = -1    # under the body, over the floor
	_label = Label.new()
	_label.name = "Nameplate"
	_label.position = nameplate_offset
	_label.size = Vector2(-nameplate_offset.x * 2.0, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", nameplate_font_size)
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 2    # above other heroes' bodies
	_label.z_as_relative = false
	add_child(_label)
	var bar := hero.get_node_or_null(^"HealthBar") as ProgressBar
	if bar != null:
		_bar_fill = StyleBoxFlat.new()
		_bar_fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override(&"fill", _bar_fill)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0, 0, 0, 0.65)
		back.set_corner_radius_all(2)
		back.set_border_width_all(1)
		back.border_color = Color(0, 0, 0, 0.9)
		bar.add_theme_stylebox_override(&"background", back)
	_refresh()


func _process(_delta: float) -> void:
	var local := hero.is_in_group(&"player") and not hero.bot_controlled
	if hero.team != _team or local != _local:
		_refresh()
	queue_redraw()    # the aim pointer turns every frame


func get_color() -> Color:
	return MatchManager.team_color(hero.team) if hero.team in MatchManager.TEAMS else no_team_color


func _refresh() -> void:
	_team = hero.team
	_local = hero.is_in_group(&"player") and not hero.bot_controlled
	var color := get_color()
	var display := hero.definition.display_name if hero.definition != null else str(hero.name)
	_label.text = "%s (You)" % display if _local else display
	_label.add_theme_color_override(&"font_color", color if not _local else color.lightened(0.35))
	if _bar_fill != null:
		_bar_fill.bg_color = color
	queue_redraw()


func get_ring_color() -> Color:
	var color := get_color()
	return Color.from_hsv(color.h, minf(color.s + ring_saturation_boost, 1.0), color.v * 0.9)


func _draw() -> void:
	var color := get_ring_color()
	draw_circle(Vector2.ZERO, ring_radius, Color(color, fill_alpha))
	if _local:
		draw_arc(Vector2.ZERO, ring_radius + local_ring_width * 0.5 + 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.9), 3.0, true)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 64, Color(0, 0, 0, 0.55), (local_ring_width if _local else ring_width) + 3.0, true)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 64, color, local_ring_width if _local else ring_width, true)
	var aim := hero.aim_direction
	if aim.length_squared() > 0.01:
		aim = aim.normalized()
		var side := aim.orthogonal()
		var base := aim * (ring_radius + 2.0)
		var tip := aim * (ring_radius + 2.0 + pointer_size)
		var tri := PackedVector2Array([tip, base + side * pointer_size * 0.7, base - side * pointer_size * 0.7])
		draw_colored_polygon(tri, color)
		draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.7), 2.0, true)
