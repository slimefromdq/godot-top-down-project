extends Node
class_name MinigameInstance

# One run of a minigame for one actor. Subclass it (AirlockMinigame) and
# override the hooks; MinigameHost plays it and routes input to it.
#
# It runs on physics ticks (deterministic, so it can be simulated anywhere a
# server wants). Each tick the host supplies a move vector: the player's
# WASD, a test's script, or else bot_input() (what an AI victim does).
# Presses (the host's press(action)) arrive in _on_press, so a rhythm phrase
# could run inside a minigame later.
#
# finish(result) ends it, but never before data.min_duration (it waits);
# data.max_duration ends it with {"timeout": true}. Every result also gets
# "time" (seconds played).
#
# Hooks: _on_start(), _tick(delta, move), _on_press(action), bot_input(),
# draw_view(canvas: CanvasItem, rect: Rect2) (the overlay; presentation only).

signal finished(result: Dictionary)

var data: MinigameData
var actor: Node2D
var elapsed: float = 0.0
var result: Dictionary = {}

var _pending: Dictionary = {}
var _done := false


func _init(minigame_data: MinigameData = null) -> void:
	data = minigame_data


func is_done() -> bool:
	return _done


# End with `outcome` (waits for min_duration if it's too early).
func finish(outcome: Dictionary) -> void:
	if _done or not _pending.is_empty():
		return
	_pending = outcome
	if elapsed >= data.min_duration:
		_complete(_pending)


# Called by the host each physics tick.
func step(delta: float, move: Vector2) -> void:
	if _done:
		return
	elapsed += delta
	if _pending.is_empty():
		_tick(delta, move.limit_length(1.0))
	if not _pending.is_empty() and elapsed >= data.min_duration:
		_complete(_pending)
	elif elapsed >= data.max_duration and not _done:
		_complete({"timeout": true})


func _complete(outcome: Dictionary) -> void:
	if _done:
		return
	_done = true
	result = outcome.duplicate()
	result["time"] = elapsed
	finished.emit(result)


# Hooks. All optional.
func _on_start() -> void: pass
func _tick(_delta: float, _move: Vector2) -> void: pass
func _on_press(_action: StringName) -> void: pass
## What a victim with no player or script at the controls does.
func bot_input() -> Vector2:
	return Vector2.ZERO
func draw_view(_canvas: CanvasItem, _rect: Rect2) -> void: pass
