extends RefCounted
class_name EffectSpawner

# Static helper that puts an effect scene into the world. Used by
# VisualsComponent and by anything without one (projectiles, pickups, traps).
#
# Off-screen culling: a short-lived world effect (one whose root has a
# `lifetime` of CULL_MAX_LIFETIME seconds or less: sparks, rings, damage
# numbers) is skipped when it would start more than CULL_MARGIN pixels
# outside the local camera's view. It would be gone before anyone could look,
# and particles simulate every frame whether or not they're seen. Attached
# effects (a parent is given), longer ones and camera-less runs (headless
# tests) always spawn. Presentation only: sounds and gameplay are unaffected.

## Pixels around the visible area that still count as on screen.
const CULL_MARGIN := 500.0
const CULL_MAX_LIFETIME := 3.0

## Test switch: false spawns everything.
static var cull_offscreen := true
# PackedScene -> whether it's short-lived enough to cull.
static var _short_lived: Dictionary = {}


## Spawns at context.position, facing context.direction (unless context.align
## is false). With a parent, position is treated as local to that parent.
## Returns the new node, or null when there is nothing to spawn.
static func spawn(from: Node, scene: PackedScene, context: Dictionary = {}, parent: Node = null) -> Node:
	if scene == null or from == null or not from.is_inside_tree():
		return null
	if parent == null:
		if cull_offscreen and _is_offscreen(from, context) and _is_short_lived(scene):
			return null
		parent = from.get_tree().current_scene

	var effect := scene.instantiate()
	# Place it before it enters the tree so particles start in the right spot.
	# The current scene root sits at the origin, so position == global here.
	if effect is Node2D:
		effect.position = context.get("position", Vector2.ZERO)
		var direction: Vector2 = context.get("direction", Vector2.ZERO)
		if context.get("align", true) and direction != Vector2.ZERO:
			effect.rotation = direction.angle()
	parent.add_child(effect)

	if effect.has_method("setup_cue"):
		effect.setup_cue(context)
	return effect


static func _is_offscreen(from: Node, context: Dictionary) -> bool:
	var viewport := from.get_viewport()
	if viewport == null or viewport.get_camera_2d() == null:
		return false
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	view = view.grow(CULL_MARGIN)
	var at: Vector2 = context.get("position", Vector2.ZERO)
	var end: Vector2 = context.get("target_position", at)    # beams
	return not view.has_point(at) and not view.has_point(end)


static func _is_short_lived(scene: PackedScene) -> bool:
	if not _short_lived.has(scene):
		var probe := scene.instantiate()
		var lifetime = probe.get(&"lifetime")
		_short_lived[scene] = lifetime is float and lifetime > 0.0 and lifetime <= CULL_MAX_LIFETIME
		probe.free()
	return _short_lived[scene]
