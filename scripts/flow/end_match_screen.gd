extends CanvasLayer
class_name EndMatchScreen

# The end of a match: Victory or Defeat for the local player's team, the MVP
# (best score on the winning team) in a spotlight card next to the ACE (best
# on the losing team), and a scoreboard of both teams with K/D/A, damage,
# healing, Motes and gold. Fed the result GameState.finish_match() built.
# Scores come from MatchRules.mvp_score, so the weights are data.

const MVP_COLOR := Color("fde68a")
const ACE_COLOR := Color("c4b5fd")
const YOU_COLOR := Color(1, 1, 1, 0.08)

var _root: Control


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func show_result(result: Dictionary) -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(MenuUI.THEME):
		_root.theme = load(MenuUI.THEME)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var won: bool = result.get("won", false)
	var winner: StringName = result.get("winner", &"")
	var rows: Array = result.get("heroes", [])
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	var panel := MenuUI.panel(28)
	panel.add_child(box)

	var title := MenuUI.label("VICTORY" if won else "DEFEAT", 64, MVP_COLOR if won else Color("fca5a5"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := MenuUI.label("%s wins  -  %s" % [MatchManager.team_name(winner), format_time(result.get("duration", 0.0))],
		22, MatchManager.team_color(winner))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var spotlight := HBoxContainer.new()
	spotlight.alignment = BoxContainer.ALIGNMENT_CENTER
	spotlight.add_theme_constant_override(&"separation", 18)
	var mvp: Variant = find_row(rows, &"is_mvp")
	var ace: Variant = find_row(rows, &"is_ace")
	if mvp != null:
		spotlight.add_child(_spotlight_card(mvp, "MVP", MVP_COLOR, 1.0))
	if ace != null:
		spotlight.add_child(_spotlight_card(ace, "ACE", ACE_COLOR, 0.8))
	if spotlight.get_child_count() > 0:
		box.add_child(spotlight)

	box.add_child(_scoreboard(rows, winner))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	var again := MenuUI.button("Play again", _play_again, 240.0)
	buttons.add_child(again)
	buttons.add_child(MenuUI.button("Back to menu", GameState.leave_match, 240.0))
	box.add_child(buttons)
	_root.add_child(MenuUI.centered(panel))
	add_child(_root)
	visible = true
	again.grab_focus()


func _play_again() -> void:
	get_tree().paused = false
	if GameState.in_launched_game:
		GameState.launch()
	else:
		get_tree().reload_current_scene()


# --- Pieces --------------------------------------------------------------------

static func find_row(rows: Array, flag: StringName) -> Variant:
	for row in rows:
		if row.get(flag, false):
			return row
	return null


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


# One big card: the badge, the portrait, the name and the standout numbers.
func _spotlight_card(row: Dictionary, badge: String, color: Color, scale: float) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", MenuUI.card_style(Color(color.darkened(0.75), 0.9), color))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	card.add_child(h)
	var portrait_size := 112.0 * scale
	var portrait: Texture2D = row.get("portrait")
	if portrait != null:
		var pic := TextureRect.new()
		pic.texture = portrait
		pic.custom_minimum_size = Vector2(portrait_size, portrait_size)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(pic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	h.add_child(v)
	v.add_child(MenuUI.label("%s  %s" % ["*" if badge == "MVP" else "+", badge], int(30 * scale), color))
	var who := "%s%s" % [row.name, "  (you)" if row.is_player else ""]
	v.add_child(MenuUI.label(who, int(24 * scale), MatchManager.team_color(row.team)))
	v.add_child(MenuUI.label("%d / %d / %d   K/D/A" % [row.kills, row.deaths, row.assists], int(20 * scale)))
	v.add_child(MenuUI.label("%s damage   %s healing" % [_k(row.get("damage_dealt", 0.0)), _k(row.get("healing_done", 0.0))],
		int(18 * scale), Color(1, 1, 1, 0.85)))
	if row.get("best_streak", 0) >= 2:
		v.add_child(MenuUI.label("Best streak: %d" % row.best_streak, int(18 * scale), Color(1, 1, 1, 0.85)))
	return card


const COLUMNS := ["Hero", "K / D / A", "Damage", "Taken", "Healing", "Motes", "Gold"]


func _scoreboard(rows: Array, winner: StringName) -> Control:
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size() + 1
	grid.add_theme_constant_override(&"h_separation", 22)
	grid.add_theme_constant_override(&"v_separation", 4)
	grid.add_child(MenuUI.label("", 16))
	for column in COLUMNS:
		var head := MenuUI.label(column, 16, Color(1, 1, 1, 0.6))
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column == "Hero" else HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(head)
	var teams: Array = [winner]
	for team in MatchManager.TEAMS:
		if team != winner:
			teams.append(team)
	for team in teams:
		for row in rows:
			if row.team != team:
				continue
			var tint := MatchManager.team_color(team)
			var badge := "*" if row.get("is_mvp", false) else ("+" if row.get("is_ace", false) else "")
			var cells := [
				badge,
				"%s%s" % [row.name, " (you)" if row.is_player else ""],
				"%d / %d / %d" % [row.kills, row.deaths, row.assists],
				_k(row.get("damage_dealt", 0.0)),
				_k(row.get("damage_taken", 0.0)),
				_k(row.get("healing_done", 0.0)),
				"%d / %d" % [row.motes_banked, row.motes_delivered],
				str(roundi(row.gold)),
			]
			for i in cells.size():
				var color := MVP_COLOR if i == 0 and row.get("is_mvp", false) else (ACE_COLOR if i == 0 else tint)
				var cell := MenuUI.label(cells[i], 18, color if i <= 1 else Color(1, 1, 1, 0.92))
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i <= 1 else HORIZONTAL_ALIGNMENT_RIGHT
				if i == 1 and row.is_player:
					cell.add_theme_color_override(&"font_color", Color.WHITE)
				grid.add_child(cell)
	return grid


static func _k(value: float) -> String:
	return "%.1fk" % (value / 1000.0) if value >= 1000.0 else str(roundi(value))
