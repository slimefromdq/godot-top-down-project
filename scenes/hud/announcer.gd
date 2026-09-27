extends CanvasLayer
class_name Announcer

# The match announcer: big glossy banners that slide in at top centre, under
# the wake meters. They queue, and a higher-priority banner cuts the current
# one short (a stir interrupts a zone banner). Every banner plays a sound
# (MatchRules.cue_audio "banner", or "banner_major" for the big moments);
# voice lines can replace those later. FeelSettings.announcer_text off hides
# the text but keeps the sounds.
#
# Also: a small toast above the ability bar for the local player's own banks
# and deliveries (with the gold they earned), floating "+gold" text at the
# depositor, and minimap pings for a stir and a Dream Mote spawn.
#
# Neutral objectives (ObjectiveDirector): announced ones (the Nightmare)
# get banners for their warning, spawn and death; any camp the local
# player's team clears gets a toast with the gold they got.
#
# Read-only: listens to the MatchManager, its MoteDirector and the Dreamers.
# The MatchHud adds one; say(text, priority) works from anywhere for tests.

const SLIDE_IN := 0.35
const SLIDE_OUT := 0.25
const HOLD := 2.4
const TOAST_TIME := 2.8

## Priorities: higher interrupts lower.
const MINOR := 1
const NORMAL := 2
const MAJOR := 3
const CRITICAL := 4

class Banner:
	var text: String
	var priority: int
	var color: Color
	var sound: StringName
	var age: float = 0.0
	var leaving: float = -1.0    # >= 0 once it's sliding out

var _was_busy := false
var match_manager: MatchManager
var current: Banner
var queue: Array[Banner] = []
## Recent banners (text), newest last: for tests and the debug panel.
var history: PackedStringArray = []

var _canvas: Control
var _toasts: Array = []        # {text, color, age}
var _visit_gold: float = 0.0


func _ready() -> void:
	layer = 6
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)


func bind(manager: MatchManager) -> void:
	match_manager = manager
	if manager == null:
		return
	manager.stir_started.connect(func(team):
		say("%s Dreamer is stirring!" % MatchManager.team_name(team), CRITICAL, MatchManager.team_color(team), &"banner_major")
		var dreamer := manager.get_dreamer(team)
		if dreamer != null:
			get_tree().call_group(&"minimaps", &"add_ping", dreamer.global_position, &"", &"stir"))
	manager.settled.connect(func(team, how):
		var team_label := MatchManager.team_name(team)
		say(("Lullaby! %s Dreamer settles" if how == Dreamer.SETTLE_LULLABY else "%s Dreamer settles") % team_label,
			MAJOR, Color("c4b5fd")))
	manager.wake_milestone.connect(func(team, mark):
		say("%s Dreamer is %d%% awake" % [MatchManager.team_name(team), roundi(mark * 100)],
			NORMAL if mark >= 0.75 else MINOR, MatchManager.team_color(team)))
	manager.gold_changed.connect(_on_gold)
	for team in MatchManager.TEAMS:
		var dreamer := manager.get_dreamer(team)
		if dreamer == null:
			continue
		dreamer.sweet_dreams_granted.connect(func(): _on_sweet_dreams(team))
		dreamer.deposit_finished.connect(_on_deposit_finished)
	var director := manager.get_node_or_null(^"MoteDirector") as MoteDirector
	if director != null:
		director.dream_mote_warning.connect(func(_p, _s):
			say("Dream Mote incoming: the Cradle!", NORMAL, Color("e9d5ff")))
		director.zone_warning.connect(func(_id, zone_name, _s):
			say("%s are dreaming!" % zone_name, MINOR, Color("ddd6fe")))
		director.dream_mote_picked_up.connect(func(actor):
			say("%s has the Dream Mote!" % MatchManager.team_name(actor.team), NORMAL, MatchManager.team_color(actor.team)))
		director.dream_mote_spawned.connect(func(mote):
			get_tree().call_group(&"minimaps", &"add_ping", mote.global_position, &"", &"dream_mote"))
	var objectives := manager.get_node_or_null(^"ObjectiveDirector") as ObjectiveDirector
	if objectives != null:
		objectives.objective_warning.connect(func(camp: NeutralCamp, seconds: float):
			say("%s stirs in %d s!" % [camp.get_display_name(), ceili(seconds)], MAJOR, camp.data.icon_color, &"banner_major"))
		objectives.objective_spawned.connect(func(camp: NeutralCamp):
			if camp.data.announce:
				say("%s has awoken!" % camp.get_display_name(), MAJOR, camp.data.icon_color, &"banner_major"))
		objectives.objective_cleared.connect(_on_objective_cleared)


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


## Queue a banner. A higher priority than the one showing cuts it short.
func say(text: String, priority: int = NORMAL, color: Color = Color.WHITE, sound: StringName = &"banner") -> void:
	var banner := Banner.new()
	banner.text = text
	banner.priority = priority
	banner.color = color
	banner.sound = sound
	history.append(text)
	if current != null and priority > current.priority and current.leaving < 0.0:
		current.leaving = 0.0
	var at := queue.size()
	for i in queue.size():
		if queue[i].priority < priority:
			at = i
			break
	queue.insert(at, banner)


func toast(text: String, color: Color) -> void:
	_toasts.append({"text": text, "color": color, "age": 0.0})


func _on_sweet_dreams(team: StringName) -> void:
	var player := get_player()
	var own := player != null and player.team == team
	say("Sweet Dreams!" if own else "%s has Sweet Dreams" % MatchManager.team_name(team), MINOR, Color("fbcfe8"))


func _on_objective_cleared(camp: NeutralCamp, team: StringName, _killer: Hero) -> void:
	if camp.data.announce:
		if team == &"":
			say("%s fades away" % camp.get_display_name(), MAJOR, camp.data.icon_color)
		else:
			say("%s slays %s!" % [MatchManager.team_name(team), camp.get_display_name()], CRITICAL,
				MatchManager.team_color(team), &"banner_major")
		return
	var player := get_player()
	if player != null and player.team == team:
		toast("%s cleared" % camp.get_display_name(), camp.data.icon_color)


func _on_gold(actor: Hero, amount: float, reason: StringName) -> void:
	if actor == get_player() and reason in [&"bank", &"deliver", &"depositor_bonus"]:
		_visit_gold += amount


func _on_deposit_finished(hero: Hero, total: int, delivered: bool) -> void:
	if hero != get_player():
		return
	var gold := roundi(_visit_gold)
	_visit_gold = 0.0
	toast("%s %d  +%d gold" % ["Delivered" if delivered else "Banked", total, gold],
		MatchManager.team_color(hero.team) if not delivered else Color("fde68a"))
	MatchManager.play_world_cue(hero, &"gold_gain", {"position": hero.global_position, "text": "+%d" % gold,
		"color": Color("fde047")})


func _process(delta: float) -> void:
	if current == null and not queue.is_empty():
		current = queue.pop_front()
		_play_sound(current.sound)
	if current != null:
		current.age += delta
		if current.leaving < 0.0 and current.age >= SLIDE_IN + HOLD:
			current.leaving = 0.0
		if current.leaving >= 0.0:
			current.leaving += delta
			if current.leaving >= SLIDE_OUT:
				current = null
	for t in _toasts:
		t.age += delta
	_toasts = _toasts.filter(func(t): return t.age < TOAST_TIME)
	# Idle (nothing showing): one last redraw to clear, then none.
	var busy := current != null or not _toasts.is_empty()
	if busy or _was_busy:
		_canvas.queue_redraw()
	_was_busy = busy


func _play_sound(cue: StringName) -> void:
	var rules := match_manager.get_rules() if match_manager != null else MatchRules.current()
	if rules.cue_audio != null:
		AudioManager.play_sfx(rules.cue_audio.cues.get(cue, rules.cue_audio.cues.get(&"banner")))


func _text_shown() -> bool:
	return GameFeel.settings == null or GameFeel.settings.announcer_text


func _draw_all() -> void:
	if not _text_shown():
		return
	var font := ThemeDB.fallback_font
	var view := _canvas.size
	if current != null:
		var k := 1.0
		if current.leaving >= 0.0:
			k = 1.0 - current.leaving / SLIDE_OUT
		elif current.age < SLIDE_IN:
			var x := current.age / SLIDE_IN
			k = 1.0 + 2.7 * pow(x - 1.0, 3) + 1.7 * pow(x - 1.0, 2)    # ease out, a little overshoot
		var size := 40
		var width := font.get_string_size(current.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 80.0
		var rect := Rect2(Vector2((view.x - width) / 2.0, lerpf(-90.0, 118.0, k)), Vector2(width, 66))
		_draw_glossy_panel(rect, current.color)
		var baseline := rect.position + Vector2(0, 46)
		_canvas.draw_string_outline(font, baseline, current.text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, 8,
			Color(0.1, 0.08, 0.2, 0.9))
		_canvas.draw_string(font, baseline, current.text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, Color.WHITE)
	var y := view.y - 200.0
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var fade := clampf((TOAST_TIME - t.age) / 0.6, 0.0, 1.0)
		var at := Vector2(0, y - t.age * 12.0)
		_canvas.draw_string_outline(font, at, t.text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 22, 6, Color(0, 0, 0, 0.8 * fade))
		_canvas.draw_string(font, at, t.text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 22, Color(t.color, fade))
		y -= 30.0


# A bubbly glossy pill: soft gradient body, a highlight band on top, a rim.
func _draw_glossy_panel(rect: Rect2, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.darkened(0.35), 0.92)
	box.set_corner_radius_all(int(rect.size.y / 2.0))
	box.border_color = Color(1, 1, 1, 0.8)
	box.set_border_width_all(3)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 8
	_canvas.draw_style_box(box, rect)
	var shine := StyleBoxFlat.new()
	shine.bg_color = Color(1, 1, 1, 0.28)
	shine.set_corner_radius_all(int(rect.size.y / 3.0))
	_canvas.draw_style_box(shine, Rect2(rect.position + Vector2(10, 5), Vector2(rect.size.x - 20, rect.size.y * 0.42)))
