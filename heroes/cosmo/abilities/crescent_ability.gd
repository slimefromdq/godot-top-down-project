extends RangedAttackAbility

# Crescent: the generic gun firing a returning, curving, piercing crescent
# (all data). This script applies Moonlit on hits:
#   first pass (either way)          strength moonlit_amp - 1
#   RETURN pass on an enemy that was
#   also hit on the way out          strength moonlit_amp_full - 1
# Moonlit is a +100% incoming-magic unit, so the multiplier becomes the
# named value; a refresh keeps the stronger one.
# Cue: <id>_moonlit (context.target, .full).

# attack_id -> {target instance id: true} hit on the way out.
var _outbound: Dictionary = {}


func get_crescent_data() -> CosmoCrescentData:
	return data as CosmoCrescentData


func _activate(target_position: Vector2) -> String:
	var failure := super(target_position)
	if failure == "" and _outbound.size() > 4:
		_outbound.clear()    # older crescents are long gone
	return failure


func _on_target_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var status := hurtbox.status_component
	if status == null or get_crescent_data().moonlit_status == null:
		return
	var hit_out: Dictionary = _outbound.get_or_add(info.attack_id, {})
	var target_id := hurtbox.get_instance_id()
	var full := false
	if info.has_tag(Projectile.TAG_RETURN):
		full = hit_out.has(target_id)
	else:
		hit_out[target_id] = true
	var amp := data.get_value(&"moonlit_amp_full" if full else &"moonlit_amp", get_stats())
	status.apply(get_crescent_data().moonlit_status, actor, info.direction, amp - 1.0)
	actor.trigger_cue(StringName(str(ability_id) + "_moonlit"), {
		"position": hurtbox.global_position, "target": hurtbox.owner, "full": full})
