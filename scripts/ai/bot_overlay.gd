extends Node2D
class_name BotOverlay

## Local debug view of bot decisions. No gameplay state is changed here.

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var hero := node as Hero
		if hero == null:
			continue
		var input := hero.get_node_or_null(^"BotHeroInput") as BotHeroInput
		if input == null:
			continue
		var color := MatchManager.team_color(hero.team)
		var previous := hero.global_position
		for index in range(input._path_index, input._path.size()):
			draw_line(previous, input._path[index], color.darkened(0.2), 4.0)
			previous = input._path[index]
		draw_line(hero.global_position, input.goal, color, 2.0)
		draw_circle(input.goal, 12.0, color)
		if is_instance_valid(input.target):
			draw_line(hero.global_position, input.target.global_position, Color.ORANGE_RED, 3.0)
		if font != null:
			draw_string(font, hero.global_position + Vector2(-90, -80),
				"%s: %s / %s / %s" % [hero.name, input.intent, input.stance, input.action],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
