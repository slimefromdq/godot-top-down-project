extends Node

# Autoload (Project Settings > Globals): AudioManager.
#
# SFX: play_sfx(cue, position) plays a SoundCue anywhere, detached from the
# caller, so a death sound survives its actor being freed. The AudioMix
# (resources/audio/audio_mix.tres) thins a crowded mix first: a voice
# budget, one start per sound file per few milliseconds, off-screen culling,
# and other heroes a little quieter than you (pass `source`).
#
# Music: a priority stack. Anything can request_music(requester, stream,
# priority); the highest priority request plays, with a crossfade. When the
# requester releases (or is freed) the next one resumes. Level music, boss
# themes and character themes all use this.
#
# Layered music (alongside the stack): play_layers(set) starts every stem of a
# MusicLayerSet together, looping and in sync; set_music_tier(tier) fades each
# stem in or out (a stem plays while tier >= its own); play_sting(stream)
# plays a one-shot on the Music bus; stop_layers() fades them all out.

const MUSIC_BUS := &"Music"

var _last_play_msec: Dictionary = {}    # SoundCue -> int
var _voices: Dictionary = {}            # SoundCue -> Array[Node]
var _all_voices: Array[Node] = []       # every SFX player, oldest first
var _stream_msec: Dictionary = {}       # AudioStream -> last start (msec)
## Sounds skipped by the AudioMix since startup (for tests and debugging).
var skipped_sfx: int = 0

var _music_requests: Array[Dictionary] = []
var _music_players: Array[AudioStreamPlayer] = []
var _active_music_player: int = 0
var _current_music: AudioStream

var _layer_set: MusicLayerSet
var _layer_players: Array[AudioStreamPlayer] = []
var _layer_tier: int = -1
var _layer_tweens: Array[Tween] = []


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

# `pitch_scale` multiplies the cue's own random pitch (game feel uses it to
# make heavy hits deeper); `volume_offset_db` is added to its volume.
# `source`: who made the sound. The local player's sounds are never thinned.
func play_sfx(cue: SoundCue, position: Vector2 = Vector2.ZERO, pitch_scale: float = 1.0,
		volume_offset_db: float = 0.0, source: Node = null) -> void:
	if cue == null:
		return
	var stream := cue.pick_stream()
	if stream == null:
		return

	var now := Time.get_ticks_msec()
	if cue.min_interval > 0.0 and now - _last_play_msec.get(cue, -100000) < cue.min_interval * 1000.0:
		return
	var mix := AudioMix.current()
	# Flat (UI, announcer) sounds are never thinned either.
	var own := is_local_source(source) or not cue.positional
	if not own and not _mix_allows(cue, stream, position, now, mix):
		skipped_sfx += 1
		return
	_last_play_msec[cue] = now
	_stream_msec[stream] = now

	var voices: Array = _voices.get_or_add(cue, [])
	voices = voices.filter(func(v): return is_instance_valid(v))
	if cue.max_voices > 0 and voices.size() >= cue.max_voices:
		voices.pop_front().queue_free()
	_voices[cue] = voices
	_all_voices = _all_voices.filter(func(v): return is_instance_valid(v) and not v.is_queued_for_deletion())
	if mix.max_sfx_voices > 0 and _all_voices.size() >= mix.max_sfx_voices:
		# Only reached for your own sounds (or a UI sound): steal the oldest.
		_all_voices.pop_front().queue_free()

	var player: Node
	if cue.positional:
		player = AudioStreamPlayer2D.new()
		player.position = position
		player.max_distance = mix.max_distance
		player.attenuation = mix.attenuation
	else:
		player = AudioStreamPlayer.new()
	player.stream = stream
	var other := source != null and not is_local_source(source)
	player.volume_db = cue.volume_db + volume_offset_db + (mix.other_source_db if other else 0.0)
	player.pitch_scale = randf_range(cue.pitch_min, cue.pitch_max) * pitch_scale
	player.bus = cue.bus
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
	voices.append(player)
	_all_voices.append(player)


## Is `source` (or what owns it) the local player's hero?
static func is_local_source(source: Node) -> bool:
	var node := source
	while node != null and is_instance_valid(node):
		if node.is_in_group(&"player"):
			return node.get(&"bot_controlled") != true
		node = node.get_parent()
	return false


# Whether a sound that isn't the local player's may start now.
func _mix_allows(cue: SoundCue, stream: AudioStream, position: Vector2, now: int, mix: AudioMix) -> bool:
	if cue.bus == MUSIC_BUS:
		return true
	if now - int(_stream_msec.get(stream, -100000)) < mix.same_stream_window * 1000.0:
		return false
	_all_voices = _all_voices.filter(func(v): return is_instance_valid(v) and not v.is_queued_for_deletion())
	if mix.max_sfx_voices > 0 and _all_voices.size() >= mix.max_sfx_voices:
		return false
	if mix.same_stream_max_voices > 0:
		var same := 0
		for voice in _all_voices:
			if voice.stream == stream:
				same += 1
		if same >= mix.same_stream_max_voices:
			return false
	if cue.positional and mix.cull_distance > 0.0:
		var camera := get_viewport().get_camera_2d()
		if camera != null and camera.get_screen_center_position().distance_to(position) > mix.cull_distance:
			return false
	return true


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


# ---------------------------------------------------------------------------
# Layered music
# ---------------------------------------------------------------------------

func play_layers(layer_set: MusicLayerSet, tier: int = 0) -> void:
	stop_layers(0.0)
	_layer_set = layer_set
	if layer_set == null:
		return
	for layer in layer_set.layers:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = -80.0
		player.stream = layer.stream if layer != null else null
		player.finished.connect(_on_layer_finished.bind(player, layer_set))
		add_child(player)
		_layer_players.append(player)
	# Start them all on the same frame so the stems stay in sync.
	for player in _layer_players:
		if player.stream != null:
			player.play()
	_layer_tier = -1
	set_music_tier(tier, 0.0)


# Stems loop even if their import settings don't.
func _on_layer_finished(player: AudioStreamPlayer, layer_set: MusicLayerSet) -> void:
	if _layer_set == layer_set and is_instance_valid(player):
		player.play()


func get_music_tier() -> int:
	return _layer_tier


func get_layer_set() -> MusicLayerSet:
	return _layer_set


## The volume each stem is heading to (-80 = off), for tests and debugging.
func get_layer_targets() -> PackedFloat32Array:
	var targets := PackedFloat32Array()
	if _layer_set == null:
		return targets
	for layer in _layer_set.layers:
		targets.append(layer.volume_db if layer != null and _layer_tier >= layer.tier else -80.0)
	return targets


func set_music_tier(tier: int, fade_time: float = -1.0) -> void:
	if _layer_set == null or tier == _layer_tier:
		return
	_layer_tier = tier
	if fade_time < 0.0:
		fade_time = _layer_set.crossfade_time
	for tween in _layer_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_layer_tweens.clear()
	var targets := get_layer_targets()
	for i in _layer_players.size():
		var player := _layer_players[i]
		if fade_time <= 0.0:
			player.volume_db = targets[i]
			continue
		var tween := create_tween()
		tween.tween_property(player, "volume_db", targets[i], fade_time)
		_layer_tweens.append(tween)


func play_sting(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = MUSIC_BUS
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func stop_layers(fade_time: float = 1.0) -> void:
	for player in _layer_players:
		if fade_time <= 0.0:
			player.queue_free()
		else:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -80.0, fade_time)
			tween.tween_callback(player.queue_free)
	_layer_players.clear()
	_layer_set = null
	_layer_tier = -1


# Loops music even if the file's import settings don't.
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player == _music_players[_active_music_player] and _current_music != null:
		player.play()
