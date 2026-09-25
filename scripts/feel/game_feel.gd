extends Node

# Autoload "GameFeel": the shared toolbox for cosmetic feedback, plus the
# global comfort settings (FeelSettings).
#
# THE RULE: everything here is presentation. Nothing in this file changes
# health, positions, cooldowns or timing. In a networked game each client runs
# these effects locally for what it sees; the server never runs them and never
# waits for them.
#
# How hitstop stays cosmetic: it freezes the VisualsComponent (sprite
# animation, pose, trail) of the attacker and target for a few frames. It
# does NOT touch Engine.time_scale, pause the tree, or stop physics. The real
# bodies keep simulating (knockback included); the frozen sprite simply holds
# its spot and then catches up to its body over a few frames. On screen it
# reads as "time stopped on impact", but the simulation never stopped.

const SETTINGS_PATH := "res://resources/feel/feel_settings.tres"

var settings: FeelSettings


func _ready() -> void:
	settings = load(SETTINGS_PATH) if ResourceLoader.exists(SETTINGS_PATH) else FeelSettings.new()
	# A private copy, so live tweaks (debug panel) don't write to disk.
	settings = settings.duplicate()


# Is this node the player sitting at this screen? Only their hits and hurts
# move the camera; watching two dummies fight shouldn't shake your screen.
func is_local(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.is_in_group(&"player")


# Freeze the visuals of each node for `duration` seconds (see top comment).
func hitstop(nodes: Array, duration: float, tremble: float = 0.0, catch_up: float = 0.06) -> void:
	if not settings.hitstop_enabled:
		return
	duration *= settings.hitstop_scale
	if duration <= 0.0:
		return
	for node in nodes:
		var visuals := VisualsComponent.find_on(node)
		if visuals != null:
			visuals.freeze(duration, tremble, catch_up)


func shake(trauma: float) -> void:
	var camera := _camera()
	if camera != null and camera.has_method(&"add_trauma") and trauma > 0.0:
		camera.add_trauma(trauma)


func nudge(direction: Vector2, distance: float) -> void:
	var camera := _camera()
	if camera != null and camera.has_method(&"nudge") and distance > 0.0:
		camera.nudge(direction, distance * settings.camera_nudge_scale)


func flash(node: Node, color: Color, duration: float) -> void:
	if not settings.flash_enabled:
		return
	var visuals := VisualsComponent.find_on(node)
	if visuals != null:
		visuals.flash(color, duration)


# Play a feel sound with an extra pitch factor and a little random jitter.
func play(sound: SoundCue, at: Vector2, pitch_scale: float = 1.0, jitter: float = 0.0) -> void:
	if sound == null:
		return
	AudioManager.play_sfx(sound, at, pitch_scale * (1.0 + randf_range(-jitter, jitter)))


func _camera() -> Camera2D:
	var viewport := get_viewport()
	return viewport.get_camera_2d() if viewport != null else null
