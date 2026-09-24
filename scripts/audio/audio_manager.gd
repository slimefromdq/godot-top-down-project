extends Node

# Autoload (Project Settings > Globals): AudioManager.
#
# SFX: play_sfx(cue, position) plays a SoundCue anywhere, detached from the
# caller, so a death sound survives its actor being freed.
#
# Music: a priority stack. Anything can request_music(requester, stream,
# priority); the highest priority request plays, with a crossfade. When the
# requester releases (or is freed) the next one resumes. Level music, boss
# themes and character themes all use this.

const MUSIC_BUS := &"Music"

var _last_play_msec: Dictionary = {}    # SoundCue -> int
var _voices: Dictionary = {}            # SoundCue -> Array[Node]

var _music_requests: Array[Dictionary] = []
var _music_players: Array[AudioStreamPlayer] = []
var _active_music_player: int = 0
var _current_music: AudioStream


func _ready() -> void:
	# Keep music and one-shot sounds running while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = -80.0
		player.finished.connect(_on_music_finished.bind(player))
		add_child(player)
		_music_players.append(player)


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

func play_sfx(cue: SoundCue, position: Vector2 = Vector2.ZERO) -> void:
	if cue == null:
		return
	var stream := cue.pick_stream()
	if stream == null:
		return

	var now := Time.get_ticks_msec()
	if cue.min_interval > 0.0 and now - _last_play_msec.get(cue, -100000) < cue.min_interval * 1000.0:
		return
	_last_play_msec[cue] = now

	var voices: Array = _voices.get_or_add(cue, [])
	voices = voices.filter(func(v): return is_instance_valid(v))
	if cue.max_voices > 0 and voices.size() >= cue.max_voices:
		voices.pop_front().queue_free()
	_voices[cue] = voices

	var player: Node
	if cue.positional:
		player = AudioStreamPlayer2D.new()
		player.position = position
	else:
		player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = cue.volume_db
	player.pitch_scale = randf_range(cue.pitch_min, cue.pitch_max)
	player.bus = cue.bus
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
	voices.append(player)


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

func request_music(requester: Object, stream: AudioStream, priority: int = 0, fade_time: float = 1.0) -> void:
	release_music(requester, fade_time, false)
	_music_requests.append({
		"requester": weakref(requester),
		"stream": stream,
		"priority": priority,
		"order": Time.get_ticks_usec(),
	})
	_refresh_music(fade_time)


func release_music(requester: Object, fade_time: float = 1.0, refresh: bool = true) -> void:
	_music_requests = _music_requests.filter(func(r): return r.requester.get_ref() != requester)
	if refresh:
		_refresh_music(fade_time)


func stop_all_music(fade_time: float = 1.0) -> void:
	_music_requests.clear()
	_refresh_music(fade_time)


func _refresh_music(fade_time: float) -> void:
	# Forget requesters that were freed without releasing.
	_music_requests = _music_requests.filter(func(r): return r.requester.get_ref() != null)

	var best: Dictionary = {}
	for request in _music_requests:
		if best.is_empty() or request.priority > best.priority \
				or (request.priority == best.priority and request.order > best.order):
			best = request

	var next_stream: AudioStream = best.get("stream")
	if next_stream == _current_music:
		return
	_current_music = next_stream
	_crossfade_to(next_stream, fade_time)


func _crossfade_to(stream: AudioStream, fade_time: float) -> void:
	var old_player := _music_players[_active_music_player]
	_active_music_player = 1 - _active_music_player
	var new_player := _music_players[_active_music_player]

	var tween := create_tween().set_parallel()
	tween.tween_property(old_player, "volume_db", -80.0, fade_time)
	tween.chain().tween_callback(old_player.stop)

	if stream != null:
		new_player.stream = stream
		new_player.volume_db = -80.0
		new_player.play()
		create_tween().tween_property(new_player, "volume_db", 0.0, fade_time)


# Loops music even if the file's import settings don't.
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player == _music_players[_active_music_player] and _current_music != null:
		player.play()
