extends Node
class_name AudioComponent

# Reusable "how this thing sounds" component: the audio twin of
# VisualsComponent. Add it to anything with a HealthComponent, point it at an
# AudioProfile, and it plays sounds for the same cues the visuals react to.

const META_KEY := &"audio_component"

@export var profile: AudioProfile
## Found automatically on the owner when left empty.
@export var health_component: HealthComponent
## Found automatically on the owner when left empty.
@export var status_component: StatusEffectComponent
## Print every cue this component receives. Use it to discover cue names.
@export var print_cues: bool = false


# Untyped on purpose: callers may pass a reference to an actor that was freed.
static func find_on(node) -> AudioComponent:
	if is_instance_valid(node) and node.has_meta(META_KEY):
		return node.get_meta(META_KEY)
	return null


func _ready() -> void:
	if profile == null:
		profile = AudioProfile.new()
	var root := _get_root()
	root.set_meta(META_KEY, self)

	if health_component == null:
		health_component = VisualsComponent._find_child_of_type(root, "HealthComponent")
	if status_component == null:
		status_component = VisualsComponent._find_child_of_type(root, "StatusEffectComponent")

	if root.has_signal(&"cue_triggered"):
		root.cue_triggered.connect(play_cue)
	if health_component != null:
		health_component.damaged.connect(func(_amount, _source): play_cue(&"hurt"))
		health_component.healed.connect(func(_amount): play_cue(&"heal"))
		health_component.died.connect(_on_died)
	if status_component != null:
		status_component.status_applied.connect(_on_status_applied)

	if profile.theme_music != null:
		AudioManager.request_music(self, profile.theme_music, profile.theme_priority, profile.theme_fade_time)
	play_cue.call_deferred(&"spawn")


func _exit_tree() -> void:
	AudioManager.release_music(self)


func play_cue(cue: StringName, context: Dictionary = {}) -> void:
	if print_cues:
		print("[Audio:%s] cue '%s'" % [_get_root().name, cue])
	play_sound(profile.cues.get(cue), context)


func play_sound(sound: SoundCue, context: Dictionary = {}) -> void:
	if sound == null:
		return
	var root := _get_root()
	var fallback: Vector2 = root.global_position if root is Node2D else Vector2.ZERO
	AudioManager.play_sfx(sound, context.get("position", fallback))


func _on_died() -> void:
	play_cue(&"death")
	var killer_audio := find_on(health_component.last_damage_source)
	if killer_audio != null and killer_audio != self:
		play_sound(killer_audio.profile.kill_sound)
	# A boss theme should end with the boss, not when its body is freed.
	AudioManager.release_music(self)


func _on_status_applied(effect: StatusEffect) -> void:
	play_sound(effect.apply_sound)


func _get_root() -> Node:
	return owner if owner != null else get_parent()
