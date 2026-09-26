extends RefCounted
class_name LocalView

# Whose screen this is. Some things are drawn only for some players: an
# enemy hidden in a bush, or a status VFX limited by
# StatusEffect.vfx_visible_to. Only drawing is filtered here; gameplay never
# asks LocalView anything.
#
# The viewer is the local player (group "player"). Tests and future
# spectator/replay modes can set_viewer() another actor. With no viewer at
# all (a headless tool with no player), everything is shown.

static var _viewer_override: Node2D
static var _has_override := false


static func get_viewer() -> Node2D:
	if _has_override:
		return _viewer_override if is_instance_valid(_viewer_override) else null
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(&"player") as Node2D if tree != null else null


# Look through `viewer`'s eyes instead of the local player's. null = nobody
# (everything shown).
static func set_viewer(viewer: Node2D) -> void:
	_viewer_override = viewer
	_has_override = true


static func clear_viewer() -> void:
	_viewer_override = null
	_has_override = false


# Should `actor` be drawn at all? False only when it's hidden in a bush from
# the viewer's team (CombatQueries.is_hidden_from).
static func is_actor_shown(actor: Node2D) -> bool:
	var viewer := get_viewer()
	return viewer == null or not CombatQueries.is_hidden_from(actor, viewer)


# Should the attached VFX of `effect` on `target` be drawn for the viewer?
static func can_see_status_vfx(target: Node, effect: StatusEffect, status: StatusEffectComponent) -> bool:
	if effect.vfx_visible_to == StatusEffect.VfxVisibleTo.EVERYONE:
		return true
	var viewer := get_viewer()
	if viewer == null:
		return true
	var target_team := CombatQueries.team_of(target)
	var same_team := viewer == target or (target_team != &"" and CombatQueries.team_of(viewer) == target_team)
	match effect.vfx_visible_to:
		StatusEffect.VfxVisibleTo.TARGET_ALLIES:
			return same_team
		StatusEffect.VfxVisibleTo.TARGET_ENEMIES:
			return not same_team
		StatusEffect.VfxVisibleTo.TARGET_AND_APPLIER:
			return viewer == target or (status != null and viewer == status.get_applier(effect.id))
		StatusEffect.VfxVisibleTo.LISTED:
			return status != null and status.get_vfx_viewers(effect.id).has(viewer)
	return true
