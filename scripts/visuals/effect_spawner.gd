extends RefCounted
class_name EffectSpawner

# Static helper that puts an effect scene into the world. Used by
# VisualsComponent and by anything without one (projectiles, pickups, traps).


## Spawns at context.position, facing context.direction (unless context.align
## is false). With a parent, position is treated as local to that parent.
## Returns the new node, or null when there is nothing to spawn.
static func spawn(from: Node, scene: PackedScene, context: Dictionary = {}, parent: Node = null) -> Node:
	if scene == null or from == null or not from.is_inside_tree():
		return null
	if parent == null:
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
