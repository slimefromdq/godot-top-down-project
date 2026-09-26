extends Ability
class_name SelfStatusAbility

# Generic "buff yourself" driven by SelfStatusData: when the active phase
# starts, count enemies around the caster and apply self_status at the
# resulting strength (see SelfStatusData). A shield that grows when you're
# surrounded, a stance that's stronger in a crowd.
#
# Cue: <id>_applied (context.enemies, .strength, .radius) when it lands.
#
# hold_to_keep (data): the status stays while the key is held and ends on
# release (a scope, a guard stance); its own duration is the longest hold.
# The cast itself is over at once, so other abilities stay usable meanwhile.
# Cue: <id>_released.

## Enemies counted by the last cast.
var last_enemy_count: int = 0
## Strength the last cast applied its status at.
var last_strength: float = 0.0
var _holding := false


func get_self_status_data() -> SelfStatusData:
	return data as SelfStatusData


# hold_to_keep: the status is on and the key hasn't been let go.
func is_held() -> bool:
	if not _holding:
		return false
	var self_data := get_self_status_data()
	if self_data == null or self_data.self_status == null \
			or not actor.status_component.has_status_from(self_data.self_status.id, actor):
		_holding = false    # ran its full duration, or was cleansed
	return _holding


func release_hold(_target_position: Vector2) -> bool:
	if not is_held():
		return false
	_holding = false
	actor.status_component.remove_from(get_self_status_data().self_status.id, actor)
	actor.trigger_cue(StringName(str(ability_id) + "_released"))
	return true


func _activate(_target_position: Vector2) -> String:
	var self_data := get_self_status_data()
	if self_data == null or self_data.self_status == null:
		return "No status"
	return ""


# Enemies within count_radius right now. Public so AI can decide when a
# cast is worth it.
func count_enemies() -> int:
	var self_data := get_self_status_data()
	var found := Hitbox.query(actor, actor.global_position, Vector2.RIGHT,
		HitShape.circle(self_data.count_radius), actor)
	if self_data.count_heroes_only:
		found = found.filter(func(h: HurtboxComponent): return h.owner != null and h.owner.is_in_group(&"heroes"))
	return found.size()


func _on_active_start() -> void:
	var self_data := get_self_status_data()
	last_enemy_count = count_enemies()
	last_strength = self_data.get_strength(last_enemy_count)
	actor.status_component.apply(self_data.self_status, actor, Vector2.ZERO, last_strength)
	if self_data.hold_to_keep:
		_holding = true
	actor.trigger_cue(StringName(str(ability_id) + "_applied"), {"enemies": last_enemy_count,
		"strength": last_strength, "radius": self_data.count_radius,
		"duration": self_data.self_status.duration})
