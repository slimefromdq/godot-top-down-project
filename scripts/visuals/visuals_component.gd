extends Node2D
class_name VisualsComponent

# Reusable "how this thing looks" component. Put it on a player, enemy,
# training dummy, neutral monster, destructible crate: anything with a
# HealthComponent. Point it at a VisualProfile and it handles:
#
#   * the body sprite (static texture or SpriteFrames with idle/move/hurt/death)
#   * facing the aim direction
#   * hit flash, damage numbers, target highlight
#   * death effects, plus the killer's cosmetic kill effect
#   * status-effect auras and tints
#   * what the local player may see (LocalView): hides this actor while it's
#     hidden in a bush from the viewer's team, and status auras whose
#     StatusEffect.vfx_visible_to leaves the viewer out
#   * any named cue the owner triggers (abilities, weapon, custom)
#
# Cues arrive from the owner's `cue_triggered(cue, context)` signal (Actor has
# it; any script can declare it) or from calling play_cue() directly.
# See docs/VISUALS_AND_AUDIO.md.

const BODY_SHADER := preload("res://shaders/actor_body.gdshader")
const META_KEY := &"visuals_component"

@export var profile: VisualProfile
## Found automatically on the owner when left empty.
@export var health_component: HealthComponent
## Found automatically on the owner when left empty.
@export var status_component: StatusEffectComponent
## Print every cue this component receives. Use it to discover cue names.
@export var print_cues: bool = false

var body: CanvasItem
var _animation_player: AnimationPlayer
var _body_material: ShaderMaterial
var _flash_tween: Tween
var _is_dead := false
var _playing_one_shot := false
var _is_highlighted := false
var _status_vfx: Dictionary = {}    # status id -> Node
var _status_tints: Array[StatusEffect] = []
# True while this component hid the owner (a bush). Only ever undoes its own hide.
var _concealed := false

# Hitstop (see freeze()). All cosmetic: the body keeps moving underneath.
var _freeze_left: float = 0.0
var _freeze_anchor := Vector2.ZERO    # global point the sprite holds
var _freeze_tremble: float = 0.0
var _catch_up_time: float = 0.06
var _catch_up_left: float = 0.0
var _hold_offset := Vector2.ZERO      # current offset from the body
var _rest_position := Vector2.ZERO


# Look up the VisualsComponent that belongs to any node (actor, dummy, ...).
static func find_on(node: Node) -> VisualsComponent:
	if node != null and is_instance_valid(node) and node.has_meta(META_KEY):
		return node.get_meta(META_KEY)
	return null


func _ready() -> void:
	if profile == null:
		profile = VisualProfile.new()
	var root := _get_root()
	root.set_meta(META_KEY, self)

	if health_component == null:
		health_component = _find_child_of_type(root, "HealthComponent")
	if status_component == null:
		status_component = _find_child_of_type(root, "StatusEffectComponent")

	_setup_body()

	if root.has_signal(&"cue_triggered"):
		root.cue_triggered.connect(play_cue)
	if health_component != null:
		health_component.damaged.connect(_on_damaged)
		health_component.healed.connect(_on_healed)
		health_component.died.connect(_on_died)
	if status_component != null:
		status_component.status_applied.connect(_on_status_applied)
		status_component.status_removed.connect(_on_status_removed)

	play_cue.call_deferred(&"spawn")


func _process(delta: float) -> void:
	_update_freeze(delta)
	_refresh_local_view()
	if body == null or _is_dead:
		return
	var root := _get_root()

	if profile.flip_to_face_aim and "aim_direction" in root and "flip_h" in body:
		var aim: Vector2 = root.aim_direction
		if absf(aim.x) > 0.01:
			body.flip_h = aim.x < 0.0

	if body is AnimatedSprite2D and not _playing_one_shot:
		var moving: bool = "velocity" in root and root.velocity.length() > profile.move_animation_threshold
		_play_body_loop(&"move" if moving else &"idle")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func play_cue(cue: StringName, context: Dictionary = {}) -> void:
	if print_cues:
		print("[Visuals:%s] cue '%s'" % [_get_root().name, cue])
	var definition: VisualCue = profile.cues.get(cue)
	if definition == null:
		return
	play_definition(definition, context)


# Plays a VisualCue that isn't in this profile, e.g. another actor's kill effect.
func play_definition(definition: VisualCue, context: Dictionary = {}) -> void:
	context = _complete_context(context)

	if definition.effect_scene != null:
		_spawn_effect(definition, context)
	if definition.body_animation != &"":
		play_body_animation(definition.body_animation)
	if definition.flash_color.a > 0.0:
		flash(definition.flash_color, definition.flash_duration)
	if definition.screen_shake > 0.0:
		var camera := get_viewport().get_camera_2d()
		if camera != null and camera.has_method(&"add_trauma"):
			camera.add_trauma(definition.screen_shake)


func flash(color: Color, duration: float) -> void:
	if body == null or (GameFeel.settings != null and not GameFeel.settings.flash_enabled):
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	if _body_material != null:
		_body_material.set_shader_parameter(&"flash_color", color)
		_body_material.set_shader_parameter(&"flash_amount", color.a)
		_flash_tween.tween_method(
			func(v: float): _body_material.set_shader_parameter(&"flash_amount", v),
			color.a, 0.0, duration)
		# Flashed during hitstop: hold full white until the freeze ends, then
		# fade (the classic "white frame on impact").
		if is_frozen():
			_flash_tween.set_speed_scale(0.0)
	else:
		# Custom material on the body: fall back to modulate.
		body.self_modulate = color
		_flash_tween.tween_property(body, "self_modulate", Color.WHITE, duration)


# HITSTOP. Freeze this sprite for `duration` seconds: animations stop and
# the sprite holds the spot where it was hit (with an optional shiver), then
# eases back onto its body over `catch_up` seconds.
#
# Only the picture freezes. The physics body underneath keeps moving (e.g.
# already flying from knockback), which is why the sprite has to catch up
# afterwards. Nothing in the simulation waits for this.
func freeze(duration: float, tremble: float = 0.0, catch_up: float = 0.06) -> void:
	if duration <= 0.0 or not is_inside_tree():
		return
	if _freeze_left <= 0.0 and _catch_up_left <= 0.0:
		_rest_position = position
		_freeze_anchor = global_position
	elif _freeze_left <= 0.0:
		# Hit again while catching up: hold where the sprite is now.
		_freeze_anchor = global_position
	_freeze_left = maxf(_freeze_left, duration)
	_freeze_tremble = tremble
	_catch_up_time = catch_up
	_catch_up_left = 0.0
	_set_animation_paused(true)


func is_frozen() -> bool:
	return _freeze_left > 0.0


# 0 while frozen, 1 otherwise. Cosmetic effects multiply their own delta by
# this so trails and poses freeze together with the sprite.
func get_time_scale() -> float:
	return 0.0 if is_frozen() else 1.0


func _update_freeze(delta: float) -> void:
	if _freeze_left <= 0.0 and _catch_up_left <= 0.0:
		return
	var parent_2d := get_parent() as Node2D
	if parent_2d == null:
		return
	if _freeze_left > 0.0:
		_freeze_left -= delta
		var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _freeze_tremble
		# Offset that keeps the sprite at the anchor while the body moves on.
		_hold_offset = parent_2d.to_local(_freeze_anchor) - _rest_position + jitter
		if _freeze_left <= 0.0:
			_set_animation_paused(false)
			_hold_offset -= jitter
			_catch_up_left = _catch_up_time
	else:
		_catch_up_left -= delta
		var k := clampf(_catch_up_left / maxf(_catch_up_time, 0.001), 0.0, 1.0)
		_hold_offset *= k if _catch_up_left > 0.0 else 0.0
	position = _rest_position + _hold_offset


func _set_animation_paused(paused: bool) -> void:
	if body is AnimatedSprite2D:
		body.speed_scale = 0.0 if paused else 1.0
	if _animation_player != null:
		_animation_player.speed_scale = 0.0 if paused else 1.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.set_speed_scale(0.0 if paused else 1.0)


# Plays a one-off animation, then returns to idle/move. Checks the body's
# SpriteFrames first, then the AnimationPlayer.
func play_body_animation(animation: StringName) -> void:
	if body is AnimatedSprite2D and body.sprite_frames.has_animation(animation):
		_playing_one_shot = not body.sprite_frames.get_animation_loop(animation)
		body.play(animation)
	elif _animation_player != null and _animation_player.has_animation(animation):
		_animation_player.play(animation)


func set_highlighted(highlighted: bool) -> void:
	if highlighted == _is_highlighted:
		return
	_is_highlighted = highlighted
	_refresh_tint()


# Seconds the owner should stay alive after dying so the death animation and
# linger time can finish.
func get_death_duration() -> float:
	var duration := profile.death_linger_time
	if body is AnimatedSprite2D and body.sprite_frames.has_animation(&"death"):
		var frames: SpriteFrames = body.sprite_frames
		var total := 0.0
		for i in frames.get_frame_count(&"death"):
			total += frames.get_frame_duration(&"death", i)
		var fps := frames.get_animation_speed(&"death")
		if fps > 0.0:
			duration = max(duration, total / fps)
	return duration


# Call after reviving something (e.g. a respawning dummy).
func revive() -> void:
	_is_dead = false
	_playing_one_shot = false
	play_cue(&"spawn")


# A detached copy of the current body frame, for afterimages and ghosts.
func make_body_snapshot() -> Sprite2D:
	if body == null:
		return null
	var ghost := Sprite2D.new()
	if body is AnimatedSprite2D:
		ghost.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
	elif body is Sprite2D:
		ghost.texture = body.texture
		ghost.hframes = body.hframes
		ghost.vframes = body.vframes
		ghost.frame = body.frame
	if ghost.texture == null:
		return null
	ghost.flip_h = body.flip_h
	ghost.offset = body.offset
	ghost.centered = body.centered
	ghost.global_transform = (body as Node2D).global_transform
	return ghost


# ---------------------------------------------------------------------------
# Health and status reactions
# ---------------------------------------------------------------------------

func _on_damaged(amount: float, source: Node) -> void:
	if profile.cues.has(&"hurt"):
		play_cue(&"hurt", {"source": source, "text": amount})
	else:
		flash(Color(1, 1, 1, 0.9), 0.08)
	if not _playing_one_shot:
		play_body_animation(&"hurt")
	if profile.show_damage_numbers and amount > 0.0:
		EffectSpawner.spawn(self, profile.damage_number_scene, {
			"position": _get_root().global_position,
			"text": str(roundi(amount)),
			"color": profile.damage_number_color,
			"align": false,
		})


func _on_healed(amount: float, _source: Node = null) -> void:
	if amount < 0.5:
		return
	play_cue(&"heal", {"text": "+%d" % roundi(amount), "amount": amount})


func _on_died() -> void:
	_is_dead = true
	set_highlighted(false)
	for effect_id in _status_vfx.keys():
		_remove_status_vfx(effect_id)
	play_cue(&"death", {"align": false})
	play_body_animation(&"death")

	var killer := health_component.last_damage_source
	var killer_visuals := find_on(killer)
	if killer_visuals != null and killer_visuals != self and killer_visuals.profile.kill_effect != null:
		play_definition(killer_visuals.profile.kill_effect, {"source": killer, "align": false})


func _on_status_applied(effect: StatusEffect) -> void:
	if effect.attached_vfx != null:
		# The status component and id let the effect read live state, e.g.
		# status_component.get_fade_ratio(status_id) for a key unwinding.
		_status_vfx[effect.id] = EffectSpawner.spawn(self, effect.attached_vfx, {
			"align": false, "status_component": status_component, "status_id": effect.id}, self)
		_refresh_local_view()
	if effect.body_tint.a > 0.0:
		_status_tints.append(effect)
		_refresh_tint()
	_refresh_alpha()


func _on_status_removed(effect: StatusEffect) -> void:
	_remove_status_vfx(effect.id)
	_status_tints.erase(effect)
	_refresh_tint()
	_refresh_alpha()


# Viewer-dependent drawing (LocalView), re-checked every frame: the viewer,
# the bushes and the appliers all change without telling us.
func _refresh_local_view() -> void:
	var root := _get_root()
	if root is Node2D:
		var hide_owner := not _is_dead and not LocalView.is_actor_shown(root)
		if hide_owner != _concealed:
			_concealed = hide_owner
			root.visible = not hide_owner
	if _status_vfx.is_empty() or status_component == null:
		return
	for effect in status_component.get_active_effects():
		var node = _status_vfx.get(effect.id)
		if node is CanvasItem and is_instance_valid(node):
			node.visible = LocalView.can_see_status_vfx(root, effect, status_component)


# True while the owner isn't drawn for the local player (hidden in a bush).
func is_concealed() -> bool:
	return _concealed


# The attached VFX node currently shown for a status (null if none).
func get_status_vfx(effect_id: StringName) -> Node:
	var node = _status_vfx.get(effect_id)
	return node if is_instance_valid(node) else null


func _remove_status_vfx(effect_id: StringName) -> void:
	var node: Node = _status_vfx.get(effect_id)
	_status_vfx.erase(effect_id)
	_free_effect(node)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _get_root() -> Node:
	return owner if owner != null else get_parent()


func _setup_body() -> void:
	_animation_player = _find_child_of_type(self, "AnimationPlayer")

	if profile.sprite_frames != null:
		var animated := AnimatedSprite2D.new()
		animated.name = "Body"
		animated.sprite_frames = profile.sprite_frames
		add_child(animated)
		# The scene's placeholder sprite steps aside for the profile's body.
		for child in get_children():
			if child is Sprite2D:
				child.hide()
		body = animated
	else:
		for child in get_children():
			if child is AnimatedSprite2D or child is Sprite2D:
				body = child
				break
		if body is Sprite2D and profile.texture != null:
			body.texture = profile.texture

	if body == null:
		return
	var body_2d := body as Node2D
	body_2d.scale *= profile.body_scale
	body_2d.position += profile.body_offset
	body.modulate *= profile.body_modulate

	if body.material == null:
		_body_material = ShaderMaterial.new()
		_body_material.shader = BODY_SHADER
		body.material = _body_material
		_refresh_tint()

	if body is AnimatedSprite2D:
		body.animation_finished.connect(func(): _playing_one_shot = false)
		_play_body_loop(&"idle")


func _play_body_loop(animation: StringName) -> void:
	var sprite := body as AnimatedSprite2D
	if sprite.animation == animation and sprite.is_playing():
		return
	if sprite.sprite_frames.has_animation(animation):
		sprite.play(animation)
	elif animation == &"move" and sprite.sprite_frames.has_animation(&"idle"):
		_play_body_loop(&"idle")


# Faded silhouettes (StatusEffect.body_alpha): the lowest active value.
func _refresh_alpha() -> void:
	var alpha := 1.0
	if status_component != null:
		for effect in status_component.get_active_effects():
			alpha = minf(alpha, effect.body_alpha)
	modulate.a = alpha


func _refresh_tint() -> void:
	if _body_material == null:
		return
	var tint := profile.body_tint
	if _is_highlighted:
		tint = profile.target_highlight_color
	elif not _status_tints.is_empty():
		tint = _status_tints.back().body_tint
	_body_material.set_shader_parameter(&"tint_color", tint)


func _complete_context(context: Dictionary) -> Dictionary:
	var root := _get_root()
	var defaults := {"visuals": self, "source": root, "direction": Vector2.ZERO}
	if root is Node2D:
		defaults["position"] = root.global_position
	if "aim_direction" in root:
		defaults["direction"] = root.aim_direction
	context.merge(defaults)
	return context


func _spawn_effect(definition: VisualCue, context: Dictionary) -> void:
	var spawn_context := context.duplicate()
	spawn_context["align"] = definition.align_to_direction and context.get("align", true)

	var effect: Node
	if definition.attach_to_actor:
		spawn_context["position"] = definition.offset
		effect = EffectSpawner.spawn(self, definition.effect_scene, spawn_context, self)
	else:
		var direction: Vector2 = context.get("direction", Vector2.ZERO)
		var offset := definition.offset.rotated(direction.angle()) if spawn_context.align else definition.offset
		spawn_context["position"] = context.get("position", Vector2.ZERO) + offset
		effect = EffectSpawner.spawn(self, definition.effect_scene, spawn_context)

	if effect is CanvasItem:
		effect.modulate *= definition.tint
	if effect is Node2D:
		effect.scale *= definition.scale

	if definition.attach_to_actor:
		var duration := definition.attached_duration
		if duration <= 0.0:
			duration = context.get("duration", 0.0)
		if duration > 0.0:
			get_tree().create_timer(duration, false).timeout.connect(_free_effect.bind(effect))


func _free_effect(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method(&"stop_and_free"):
		node.stop_and_free()
	else:
		node.queue_free()


static func _find_child_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name or (child.get_script() != null and child.get_script().get_global_name() == type_name):
			return child
		var found := _find_child_of_type(child, type_name)
		if found != null:
			return found
	return null
