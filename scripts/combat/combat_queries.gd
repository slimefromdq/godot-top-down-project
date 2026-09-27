extends RefCounted
class_name CombatQueries

# Questions about the battlefield that more than one system asks. Static and
# hero-agnostic: pass any actors or dummies.
#
#   has_line_of_sight(from, to)   Can `from` see `to`? Blocked by walls on
#                                 GameRules.sight_mask (full cover; you see
#                                 over low cover and ledges) and by bushes:
#                                 from outside a bush you can't see anyone
#                                 inside it. It's one-way: from inside you
#                                 see out, and two actors in the same bush
#                                 see each other. A revealed actor
#                                 (StatusEffect.reveals) ignores the bush rule.
#                                 An invisible actor is never seen by its
#                                 enemies.
#   is_hidden_from(actor, viewer) What the viewer's screen hides: `actor` is
#                                 not on the viewer's team and is either
#                                 invisible, or in a bush that neither the
#                                 viewer nor any of its teammates shares
#                                 (vision is shared by team); a revealed
#                                 actor is never hidden.
#   is_revealed(actor)            A StatusEffect.reveals status is on it.
#   is_invisible(actor)           A StatusEffect.invisible status is on it
#                                 and no reveals status.
#   team_of(node)                 The node's `team` (&"" = neutral).


static func has_line_of_sight(from: Node2D, to: Node2D) -> bool:
	if not is_instance_valid(from) or not is_instance_valid(to):
		return false
	if from == to:
		return true
	if not is_revealed(to):
		if is_invisible(to) and _are_enemies(from, to):
			return false
		if not _shares_bush_if_inside(from, to):
			return false
	return walls_clear(from, to)


# Only the wall part of line of sight: nothing on GameRules.sight_mask
# between the two. The two bodies themselves never block.
static func walls_clear(from: Node2D, to: Node2D) -> bool:
	if not from.is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters2D.create(from.global_position, to.global_position,
		GameRules.current().sight_mask)
	var exclude: Array[RID] = []
	for node in [from, to]:
		if node is CollisionObject2D:
			exclude.append(node.get_rid())
	query.exclude = exclude
	return from.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


static func is_hidden_from(actor: Node2D, viewer: Node2D) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(viewer) or actor == viewer:
		return false
	var viewer_team := team_of(viewer)
	if viewer_team != &"" and team_of(actor) == viewer_team:
		return false
	var bushes := Bush.bushes_of(actor)
	var status := status_of(actor)
	if status == null:
		if bushes.is_empty():
			return false
	elif status.is_revealed():
		return false
	elif status.is_invisible():
		return true
	elif bushes.is_empty():
		return false
	for bush in bushes:
		for other in bush.get_occupants():
			if other == viewer:
				return false
			if viewer_team != &"" and other != actor and team_of(other) == viewer_team \
					and not StatusEffectComponent.is_actor_gone(other):
				return false
	return true


static func is_revealed(actor: Node) -> bool:
	var status := status_of(actor)
	return status != null and status.is_revealed()


static func is_invisible(actor: Node) -> bool:
	var status := status_of(actor)
	return status != null and status.is_invisible() and not status.is_revealed()


static func team_of(node: Node) -> StringName:
	if not is_instance_valid(node):
		return &""
	var team = node.get(&"team")
	return StringName(team) if team != null else &""


static func status_of(node: Node) -> StatusEffectComponent:
	if not is_instance_valid(node):
		return null
	var status = node.get(&"status_component")
	if status is StatusEffectComponent:
		return status
	return node.get_node_or_null(^"Components/StatusComponent") as StatusEffectComponent


# On different teams, or either one neutral.
static func _are_enemies(a: Node, b: Node) -> bool:
	var team_a := team_of(a)
	var team_b := team_of(b)
	return team_a != team_b or team_a == &""


# True unless `to` is in a bush that `from` isn't in.
static func _shares_bush_if_inside(from: Node2D, to: Node2D) -> bool:
	var to_bushes := Bush.bushes_of(to)
	if to_bushes.is_empty():
		return true
	for bush in to_bushes:
		if bush.has_occupant(from):
			return true
	return false
