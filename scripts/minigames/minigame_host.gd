extends Node
class_name MinigameHost

# Plays a MinigameInstance for its actor. Find or make one with
# MinigameHost.find_or_create(actor) (it lives under Components).
#
#   play(minigame, source)
#                    starts it: the data's occupied_status goes on the actor
#                    and, if the actor is the local viewer (LocalView), a
#                    MinigameView overlay opens for them only
#   set_input(move)  this tick's move vector (PlayerHeroInput sends WASD; a
#                    test or a network client can too). A tick with no input
#                    uses the minigame's bot_input().
#   source           who put the actor in it (an abductor), or null for a
#                    practice run. When a sourced minigame ends, the actor
#                    reports Actor.displaced(source, INF): they were moved.
#   press(action)    a key press for the minigame
#   stop()           ends it now ({"stopped": true})
# Signals: started(minigame), finished(minigame, result).

signal started(minigame: MinigameInstance)
signal finished(minigame: MinigameInstance, result: Dictionary)

const NODE_NAME := &"MinigameHost"
const VIEW_SCRIPT := preload("res://scripts/minigames/minigame_view.gd")

var actor: Node2D
var current: MinigameInstance
var source: Node
var _input := Vector2.ZERO
var _has_input := false
var _view: CanvasLayer


static func find_or_create(for_actor: Node) -> MinigameHost:
	var existing := find_on(for_actor)
	if existing != null:
		return existing
	var host := MinigameHost.new()
	host.name = NODE_NAME
	host.actor = for_actor as Node2D
	var parent := for_actor.get_node_or_null(^"Components")
	(parent if parent != null else for_actor).add_child(host)
	return host


static func find_on(for_actor: Node) -> MinigameHost:
	if for_actor == null or not is_instance_valid(for_actor):
		return null
	var node := for_actor.get_node_or_null(NodePath("Components/" + NODE_NAME))
	if node == null:
		node = for_actor.get_node_or_null(NodePath(NODE_NAME))
	return node as MinigameHost


func is_playing() -> bool:
	return current != null and not current.is_done()


func play(minigame: MinigameInstance, by: Node = null) -> bool:
	if is_playing() or minigame == null or minigame.data == null:
		return false
	current = minigame
	source = by
	minigame.actor = actor
	add_child(minigame)
	minigame.finished.connect(_on_finished.bind(minigame))
	var status := CombatQueries.status_of(actor)
	if status != null and minigame.data.occupied_status != null:
		status.apply(minigame.data.occupied_status, actor, Vector2.ZERO, 1.0, minigame.data.max_duration + 1.0)
	minigame._on_start()
	if LocalView.get_viewer() == actor:
		_view = VIEW_SCRIPT.new()
		_view.host = self
		get_tree().current_scene.add_child(_view)
	started.emit(minigame)
	return true


func set_input(move: Vector2) -> void:
	_input = move
	_has_input = true


func press(action: StringName) -> void:
	if is_playing():
		current._on_press(action)


func stop() -> void:
	if is_playing():
		current._complete({"stopped": true})


func _physics_process(delta: float) -> void:
	if not is_playing():
		_has_input = false
		return
	var move := _input if _has_input else current.bot_input()
	_has_input = false
	current.step(delta, move)


func _on_finished(result: Dictionary, minigame: MinigameInstance) -> void:
	var status := CombatQueries.status_of(actor)
	if status != null and minigame.data.occupied_status != null:
		status.remove_from(minigame.data.occupied_status.id, actor)
	if is_instance_valid(_view):
		_view.queue_free()
	_view = null
	var by := source
	source = null
	if is_instance_valid(by) and actor != null and actor.has_signal(&"displaced"):
		actor.displaced.emit(by, INF)
	finished.emit(minigame, result)
	minigame.queue_free.call_deferred()
