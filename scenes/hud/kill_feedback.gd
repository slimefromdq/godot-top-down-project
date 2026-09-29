extends CanvasLayer
class_name KillFeedback

# Kill confirmation for the local player: when your hero lands the killing
# blow on an enemy hero you hear a sharp chime (it climbs in pitch with your
# streak) and a marker snaps in above centre: a crosshair X, the victim's name
# and the gold it paid. An assist gets a small, quiet version. Read-only: it
# listens to MatchManager.hero_killed and never touches the fight.

const SOUND := preload("res://resources/audio/sfx/kill_confirm.tres")
const KILL_TIME := 1.6
const ASSIST_TIME := 1.1
const STREAK_NAMES := ["", "", "DOUBLE KILL", "TRIPLE KILL", "QUADRA KILL", "PENTA KILL"]

var match_manager: MatchManager
## Recent markers, for tests and the debug panel: {text, sub, color, age, life, big}.
var markers: Array = []
var kills_shown: int = 0

var _canvas: Control
var _streak_time: float = -100.0
var _streak: int = 0
## Seconds between two kills that still count as a multi-kill.
const MULTI_WINDOW := 6.0


func _ready() -> void:
	layer = 7
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)


func bind(manager: MatchManager) -> void:
	match_manager = manager
	if manager != null:
		manager.hero_killed.connect(_on_hero_killed)


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func _on_hero_killed(victim: Hero, killer: Hero, assisters: Array[Hero]) -> void:
	var player := get_player()
	if player == null or victim == null or victim.team == player.team:
		return
	var rules := match_manager.get_rules() if match_manager != null else MatchRules.current()
	var victim_name := victim.definition.display_name.to_upper() if victim.definition != null else "ENEMY"
	if killer == player:
		var now := Time.get_ticks_msec() / 1000.0
		_streak = _streak + 1 if now - _streak_time <= MULTI_WINDOW else 1
		_streak_time = now
		show_kill(victim_name, rules.kill_gold, _streak)
	elif player in assisters:
		show_assist(victim_name, rules.assist_gold)


## The marker and sound for your own kill. `streak` is kills in quick
## succession (1 = a plain kill).
func show_kill(victim_name: String, gold: float, streak: int = 1) -> void:
	var color := Color("fca5a5") if streak < 3 else Color("fde047")
	var title: String = "ELIMINATED" if streak < 2 else STREAK_NAMES[mini(streak, STREAK_NAMES.size() - 1)]
	# A newer kill replaces the last one instead of stacking over the fight.
	markers = markers.filter(func(m): return not m.big)
	markers.append({"text": title, "sub": "%s   +%d" % [victim_name, roundi(gold)],
		"color": color, "age": 0.0, "life": KILL_TIME, "big": true})
	kills_shown += 1
	AudioManager.play_sfx(SOUND, Vector2.ZERO, minf(1.0 + 0.08 * (streak - 1), 1.5))
	_canvas.queue_redraw()


func show_assist(victim_name: String, gold: float) -> void:
	markers.append({"text": "ASSIST", "sub": "%s   +%d" % [victim_name, roundi(gold)],
		"color": Color("bae6fd"), "age": 0.0, "life": ASSIST_TIME, "big": false})
	AudioManager.play_sfx(SOUND, Vector2.ZERO, 0.8, -8.0)
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	if markers.is_empty():
		return
	for m in markers:
		m.age += delta
	markers = markers.filter(func(m): return m.age < m.life)
	_canvas.queue_redraw()


func _draw_all() -> void:
	var font := ThemeDB.fallback_font
	var view := _canvas.size
	var y := view.y * 0.26
	for i in range(markers.size() - 1, -1, -1):
		var m: Dictionary = markers[i]
		var t: float = m.age / m.life
		var pop := 1.0 + 0.6 * pow(1.0 - clampf(m.age / 0.18, 0.0, 1.0), 2.0)    # snaps in big, settles
		var fade := 1.0 - smoothstep(0.7, 1.0, t)
		var color: Color = m.color
		var centre := Vector2(view.x / 2.0, y)
		if m.big:
			_draw_crosshair(centre + Vector2(0, -6), pop, Color(color, fade), m.age)
			y += 84.0
		var size := int((34 if m.big else 22) * pop)
		var text_at := Vector2(0, y - 8.0 + (0.0 if m.big else 20.0))
		_canvas.draw_string_outline(font, text_at, m.text, HORIZONTAL_ALIGNMENT_CENTER, view.x, size, 8, Color(0, 0, 0, 0.85 * fade))
		_canvas.draw_string(font, text_at, m.text, HORIZONTAL_ALIGNMENT_CENTER, view.x, size, Color(color, fade))
		var sub_at := text_at + Vector2(0, 26.0 if m.big else 20.0)
		_canvas.draw_string_outline(font, sub_at, m.sub, HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, 6, Color(0, 0, 0, 0.8 * fade))
		_canvas.draw_string(font, sub_at, m.sub, HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, Color(1, 1, 1, 0.92 * fade))
		y += 70.0


# A crosshair X with an expanding ring: the "you got them" mark.
func _draw_crosshair(centre: Vector2, pop: float, color: Color, age: float) -> void:
	var r := 22.0 * pop
	var dark := Color(0, 0, 0, color.a * 0.8)
	for offset in [Vector2(2, 2), Vector2.ZERO]:
		var c: Color = dark if offset != Vector2.ZERO else color
		for sign_x in [-1.0, 1.0]:
			_canvas.draw_line(centre + offset + Vector2(sign_x * r * 0.35, -r * 0.35), centre + offset + Vector2(sign_x * r, -r), c, 5.0)
			_canvas.draw_line(centre + offset + Vector2(sign_x * r * 0.35, r * 0.35), centre + offset + Vector2(sign_x * r, r), c, 5.0)
	var ring := clampf(age / 0.5, 0.0, 1.0)
	_canvas.draw_arc(centre, r * (1.0 + 1.6 * ring), 0.0, TAU, 32, Color(color, color.a * (1.0 - ring)), 3.0)
