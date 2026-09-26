extends Ability

# Starfall (Q): a channelled meteor storm around where she cast it.
#
# A short cast starts the CHANNEL (like Jose's Weapons Free, it runs outside
# the cast state machine). For channel_duration:
#   * channel_status pins her (move_speed x 0, so New Moon still works) and
#     resist_status cuts incoming PHYSICAL damage by starfall_weapon_resist
#     (applied in HealthComponent.mitigate with every other damage status);
#   * meteors land at random points within storm_radius (uniform over the
#     disc, from a seeded RNG: deterministic), at the data's meteor rate,
#     scaled by her moon count when scale_with_moons. Each shows a shadow
#     for impact_delay, then detonates (Projectile.explode_at): Moonlit
#     targets take the amp like any magic hit.
# Ends when time runs out, or per the data flags: stun, silence, recasting
# Q, or using her movement ability (New Moon). Meteors already falling
# still land.
#
# Cues: starfall_start, starfall_meteor_warn (context.position,
# .duration, .radius: the blast), starfall_impact, starfall_end (context.interrupted).

const WAXING := preload("res://heroes/cosmo/abilities/waxing_moon.gd")

## Deterministic meteor placement. Reseed from match state for networking.
var rng := RandomNumberGenerator.new()
var center := Vector2.ZERO

var _channeling := false
var _time_left: float = 0.0
var _meteor_accum: float = 0.0
var _pending: Array = []    # [position: Vector2, time_left: float]
var _zone: GroundZone
var _movement: Ability


func get_starfall_data() -> CosmoStarfallData:
	return data as CosmoStarfallData


func is_channeling() -> bool:
	return _channeling


func get_time_left() -> float:
	return _time_left if _channeling else 0.0


func get_meteor_rate() -> float:
	var passive := WAXING.find_on(actor)
	return get_starfall_data().get_meteor_rate(passive.moons if passive != null else 1)


func _ready() -> void:
	super()
	rng.seed = hash(ability_id)


func get_block_reason() -> String:
	if _channeling:
		if get_starfall_data().ends_on_recast:
			end_channel(false)
			return "Ended"
		return "Active"
	return super()


func _is_silent_block(reason: String) -> bool:
	return super(reason) or reason in ["Ended", "Active"]


func _activate(_target_position: Vector2) -> String:
	var starfall := get_starfall_data()
	if starfall == null or starfall.meteor == null:
		return "No meteors"
	return ""


func _on_active_start() -> void:
	_start_channel()


func _start_channel() -> void:
	var starfall := get_starfall_data()
	var duration := data.get_value(&"channel_duration", get_stats())
	var radius := data.get_value(&"storm_radius", get_stats())
	center = actor.global_position
	_channeling = true
	_time_left = duration
	_meteor_accum = 0.0
	actor.status_component.apply(starfall.channel_status, actor, Vector2.ZERO, 1.0, duration + 1.0)
	actor.status_component.apply(starfall.resist_status, actor, Vector2.ZERO,
		data.get_value(&"starfall_weapon_resist", get_stats()), duration + 1.0)
	# The storm's edge, at storm_radius (a runtime copy: presentation only).
	var edge: GroundZoneData = starfall.storm_zone.duplicate()
	edge.shape = HitShape.circle(radius)
	_zone = GroundZone.spawn(actor, edge, center, Vector2.RIGHT, actor, duration + 1.0)
	_movement = (actor as Hero).get_ability(&"movement") if actor is Hero else null
	if starfall.ends_on_movement and _movement != null and not _movement.activated.is_connected(_on_movement_used):
		_movement.activated.connect(_on_movement_used)
	if starfall.channel_music != null:
		AudioManager.request_music(self, starfall.channel_music, starfall.channel_music_priority, 0.3)
	actor.trigger_cue(StringName(str(ability_id) + "_start"), {"position": center, "radius": radius, "duration": duration})


func end_channel(interrupted: bool) -> void:
	if not _channeling:
		return
	_channeling = false
	_time_left = 0.0
	var starfall := get_starfall_data()
	if is_instance_valid(actor):
		actor.status_component.remove_from(starfall.channel_status.id, actor)
		actor.status_component.remove_from(starfall.resist_status.id, actor)
		actor.trigger_cue(StringName(str(ability_id) + "_end"), {"interrupted": interrupted})
	if is_instance_valid(_zone):
		_zone.end()
	_zone = null
	if _movement != null and _movement.activated.is_connected(_on_movement_used):
		_movement.activated.disconnect(_on_movement_used)
	if starfall.channel_music != null:
		AudioManager.release_music(self, 0.3)


func _on_movement_used() -> void:
	end_channel(true)


func _physics_process(delta: float) -> void:
	super(delta)
	_land_meteors(delta)
	if not _channeling:
		return
	var starfall := get_starfall_data()
	var status := actor.status_component
	if actor.health_component.is_dead() or (starfall.ends_on_stun and status.is_stunned()) \
			or (starfall.ends_on_silence and status.is_silenced()):
		end_channel(true)
		return
	_time_left -= delta
	if _time_left <= 0.0:
		end_channel(false)
		return
	_meteor_accum += get_meteor_rate() * delta
	while _meteor_accum >= 1.0:
		_meteor_accum -= 1.0
		_drop_meteor()


func _drop_meteor() -> void:
	# Uniform over the disc: sqrt on the radius.
	var radius := data.get_value(&"storm_radius", get_stats()) * sqrt(rng.randf())
	var at := center + Vector2.from_angle(rng.randf() * TAU) * radius
	var delay := data.get_value(&"impact_delay", get_stats())
	_pending.append([at, delay])
	var meteor := get_starfall_data().meteor
	var blast := meteor.explosion_shape.radius if meteor.explosion_shape != null else meteor.radius
	actor.trigger_cue(StringName(str(ability_id) + "_meteor_warn"), {"position": at, "duration": delay, "radius": blast})


func _land_meteors(delta: float) -> void:
	for meteor in _pending.duplicate():
		meteor[1] -= delta
		if meteor[1] > 0.0:
			continue
		_pending.erase(meteor)
		if not is_instance_valid(actor):
			continue
		var template := DamageInfo.create(data.damage.evaluate(get_stats())
			* StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE), actor, data.damage_type)
		template.label = data.get_label()
		template.tags = data.tags.duplicate()
		template.weight = 0.6
		Projectile.explode_at(actor, get_starfall_data().meteor, meteor[0], Vector2.DOWN, template)
		actor.trigger_cue(StringName(str(ability_id) + "_impact"), {"position": meteor[0]})


func _exit_tree() -> void:
	end_channel(true)
	super()
