extends CanvasLayer
class_name EndMatchScreen

# The end of a match: Victory or Defeat for the local player's team, their
# K/D/A and Motes banked, both teams' totals, and Back to menu. Fed the
# result GameState.finish_match() built, so later stats screens can use the
# same data.

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
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var won: bool = result.get("won", false)
	var winner: StringName = result.get("winner", &"")
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	var panel := MenuUI.panel(36)
	panel.add_child(box)
	var title := MenuUI.label("VICTORY" if won else "DEFEAT", 72, Color("fde68a") if won else Color("fca5a5"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := MenuUI.label("%s wins" % MatchManager.team_name(winner), 26, MatchManager.team_color(winner))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var totals := {}
	for row in result.get("heroes", []):
		if row.is_player:
			var mine := MenuUI.label("You (%s):  %d / %d / %d  K/D/A     %d Motes banked, %d delivered" % [
				row.name, row.kills, row.deaths, row.assists, row.motes_banked, row.motes_delivered], 24)
			mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(mine)
		var t: Dictionary = totals.get(row.team, {"kills": 0, "banked": 0, "delivered": 0})
		t.kills += row.kills
		t.banked += row.motes_banked
		t.delivered += row.motes_delivered
		totals[row.team] = t
	for team in MatchManager.TEAMS:
		var t: Dictionary = totals.get(team, {"kills": 0, "banked": 0, "delivered": 0})
		var line := MenuUI.label("%s:  %d kills, %d Motes banked, %d delivered" % [
			MatchManager.team_name(team), t.kills, t.banked, t.delivered], 20, MatchManager.team_color(team))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
	box.add_child(Control.new())
	var back := MenuUI.button("Back to menu", GameState.leave_match)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	_root.add_child(MenuUI.centered(panel))
	add_child(_root)
	visible = true
	back.grab_focus()
