extends Control
class_name TeamBar

# One team's roster along the top of the match HUD (MatchHud puts Dawn left
# of its wake meter and Dusk right of its own). Every hero gets a card: the
# hero's portrait (its VisualProfile body texture) in a team-coloured frame,
# and its name. Dead heroes grey out with their respawn countdown.
#
# Only for the local player's own team, each card also shows the hero's
# health and ultimate charge (UltimateCharge; gold and pulsing when full).
# Your own card has a white frame.
#
# Read-only: it polls the MatchManager's roster every frame.

@export var team: StringName = &"a"
## Cards run toward the clock: Dawn right-aligned, Dusk left-aligned.
@export var align_right: bool = true
@export var card_size := Vector2(54, 54)
@export var card_gap: float = 5.0
@export var max_cards: int = 6
@export var health_color := Color("6ee7a8")
@export var health_low_color := Color("f87171")
@export var ult_color := Color("fbbf24")

var match_manager: MatchManager


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(card_size.x * max_cards + card_gap * (max_cards - 1), card_size.y + 36)


func _process(_delta: float) -> void:
	if match_manager == null or not is_instance_valid(match_manager):
		match_manager = MatchManager.find(get_tree())
	queue_redraw()


## The heroes shown, in a stable order (the local player first on its team).
func get_heroes() -> Array[Hero]:
	if match_manager == null:
		return []
	var heroes := match_manager.get_roster(team)
	heroes.sort_custom(func(a: Hero, b: Hero):
		if a.is_in_group(&"player") != b.is_in_group(&"player"):
			return a.is_in_group(&"player")
		return a.get_instance_id() < b.get_instance_id())
	return heroes.slice(0, max_cards)


## True when this bar shows health and ultimate (the local player's team).
func shows_details() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Hero
	return player != null and player.team == team


func _draw() -> void:
	var heroes := get_heroes()
	var details := shows_details()
	var color := MatchManager.team_color(team)
	var font := get_theme_default_font()
	var step := card_size.x + card_gap
	var width := step * heroes.size() - card_gap
	var x0 := size.x - width if align_right else 0.0
	for i in heroes.size():
		var hero := heroes[i]
		_draw_card(hero, Rect2(Vector2(x0 + step * i, 0.0), card_size), color, details, font)


func _draw_card(hero: Hero, rect: Rect2, color: Color, details: bool, font: Font) -> void:
	var dead := hero.health_component.is_dead()
	draw_rect(rect, Color(0.06, 0.07, 0.1, 0.85))
	var profile := hero.definition.visual_profile if hero.definition != null else null
	var texture := profile.texture if profile != null else null
	var tint := Color(0.35, 0.35, 0.4) if dead else Color.WHITE
	if texture != null:
		draw_texture_rect(texture, rect.grow(-6), false, tint)
	else:
		draw_circle(rect.get_center(), rect.size.x * 0.36, Color(color, 0.8) * tint)
	var own := hero.is_in_group(&"player") and not hero.bot_controlled
	draw_rect(rect, Color.WHITE if own else color, false, 3.0 if own else 2.0)
	if dead and match_manager != null:
		var left := match_manager.get_respawn_left(hero)
		if left > 0.0:
			_centered(font, "%d" % ceili(left), rect.get_center() + Vector2(0, 9), 26, Color.WHITE)
	var y := rect.end.y + 3.0
	if details:
		var hp := hero.health_component.current_health / maxf(hero.health_component.max_health, 1.0)
		if dead:
			hp = 0.0
		draw_rect(Rect2(rect.position.x, y, rect.size.x, 7), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(rect.position.x, y, rect.size.x * hp, 7), health_low_color.lerp(health_color, clampf(hp * 2.0 - 0.3, 0.0, 1.0)))
		y += 9.0
		var ult := match_manager.get_ultimate_ratio(hero) if match_manager != null else -1.0
		if ult >= 0.0:
			var full := ult >= 1.0
			var glow := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 150.0) if full else 1.0
			draw_rect(Rect2(rect.position.x, y, rect.size.x, 5), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(rect.position.x, y, rect.size.x * ult, 5), Color(ult_color, glow) if full else ult_color.darkened(0.25))
			if full:
				draw_rect(Rect2(rect.position.x - 1, y - 1, rect.size.x + 2, 7), Color(1, 1, 1, 0.6 * glow), false, 1.0)
		y += 7.0
	var display := hero.definition.display_name if hero.definition != null else str(hero.name)
	_centered(font, display, Vector2(rect.get_center().x, y + 11.0), 12, color.lightened(0.2) if not dead else Color(0.6, 0.6, 0.65))


func _centered(font: Font, text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := baseline_center - Vector2(width / 2.0, 0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
