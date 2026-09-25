extends Node
class_name HealthComponent

# HP, damage intake, healing and death for anything that can be hurt.
#
# Damage pipeline (apply_damage):
#   1. ignore if already dead, invulnerable or in god mode
#   2. resistances (Armor for physical, Magic Resist for magic, none for true)
#   3. status multipliers (e.g. Shocked: +25% damage taken)
#   4. shields (StatusEffect.shield_amount) soak what's left; a hit fully
#      absorbed stops here (no damage reported, CombatEvents.damage_absorbed)
#   5. if this would kill: emit about_to_die; a listener may cancel it
#   5. report: damaged / damage_taken here, hit_dealt / kill on the attacker's
#      CombatHooks, and the global CombatEvents feed
#
# Nothing in here knows about specific heroes. Avery's revive and heal-on-hit
# plug in through about_to_die and the hooks.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
## Same moment as `damaged`, with the full hit (type, tags, label ...).
signal damage_taken(info: DamageInfo)
signal healed(amount: float, source: Node)
## Emitted before dying. Call event.cancel(hp) to prevent the death.
signal about_to_die(event: DeathEvent)
signal died

## Used when there's no StatsComponent. With one, max HP follows the Health stat.
@export var max_health: float = 200.0
## Optional. Reads the damage_taken multiplier from active status effects.
@export var status_component: StatusEffectComponent
## Optional. Supplies max HP (Health stat) and resistances (Armor, Magic Resist).
@export var stats_component: StatsComponent

var current_health: float
# Whoever landed the most recent hit. Visuals and audio use it on death to
# play the killer's kill effect.
var last_damage_source: Node = null
## Debug: take no damage at all.
var god_mode: bool = false

var _invulnerable_time_left: float = 0.0


func _ready() -> void:
	if stats_component != null:
		max_health = stats_component.get_health()
		stats_component.stats_changed.connect(_on_stats_changed)
	current_health = max_health


# Simulation timer: physics ticks, so it lines up with every other gameplay
# timer and a future server can step it deterministically.
func _physics_process(delta: float) -> void:
	_invulnerable_time_left = max(_invulnerable_time_left - delta, 0.0)


func is_dead() -> bool:
	return current_health <= 0.0


func is_invulnerable() -> bool:
	return _invulnerable_time_left > 0.0


# Longer windows win; a short window never cuts a longer one short.
func set_invulnerable_for(seconds: float) -> void:
	_invulnerable_time_left = max(_invulnerable_time_left, seconds)


func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


func get_resistance(damage_type: DamageInfo.Type) -> float:
	if stats_component == null:
		return 0.0
	match damage_type:
		DamageInfo.Type.PHYSICAL:
			return stats_component.get_stat(StatBlock.ARMOR)
		DamageInfo.Type.MAGIC:
			return stats_component.get_stat(StatBlock.MAGIC_RESIST)
	return 0.0


# What `amount` of a given type would actually remove, before it's applied.
# The stat inspector uses this for effective HP.
func mitigate(amount: float, damage_type: DamageInfo.Type) -> float:
	var result := amount
	if damage_type != DamageInfo.Type.TRUE:
		result *= GameRules.current().resistance_multiplier(get_resistance(damage_type))
	result *= StatusEffectComponent.multiplier_of(status_component, StatusEffect.DAMAGE_TAKEN)
	return result


# Health needed to kill this through its resistances, per damage type.
func get_effective_health(damage_type: DamageInfo.Type) -> float:
	var through := mitigate(1.0, damage_type)
	return current_health / through if through > 0.0 else INF


# Legacy shortcut kept so older code (bullets, debug keys) doesn't change.
func take_damage(amount: float, source: Node = null) -> void:
	apply_damage(DamageInfo.create(amount, source))


# The damage pipeline. Returns the damage actually dealt.
func apply_damage(info: DamageInfo) -> float:
	if is_dead() or is_invulnerable() or god_mode:
		return 0.0

	var root := _get_root()
	info.target = root
	info.final_amount = mitigate(info.amount, info.type)
	if info.final_amount > 0.0 and status_component != null:
		info.absorbed = status_component.absorb_damage(info.final_amount, info)
		info.final_amount -= info.absorbed
	if info.final_amount <= 0.0:
		return 0.0
	if info.source != null:
		last_damage_source = info.source

	var would_die := current_health - info.final_amount <= 0.0
	if would_die:
		var event := DeathEvent.new()
		event.info = info
		about_to_die.emit(event)
		var own_hooks := CombatHooks.find_on(root)
		if own_hooks != null and not event.cancelled:
			own_hooks.about_to_die.emit(event)
		if event.cancelled:
			# The hit still "happened" (meters and hit-dealt hooks see it),
			# it just didn't kill.
			info.final_amount = current_health - maxf(event.restore_health, 1.0) \
				if current_health > event.restore_health else 0.0
			current_health = maxf(event.restore_health, 1.0)
			_report_damage(info)
			CombatEvents.death_prevented.emit(root, event)
			return info.final_amount

	current_health = max(current_health - info.final_amount, 0.0)
	info.killed = current_health <= 0.0
	_report_damage(info)
	if info.killed:
		_die(info)
	return info.final_amount


# Heal, capped at max HP. `label` names the heal source for the meter.
func heal(amount: float, source: Node = null, label: StringName = &"") -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var before := current_health
	current_health = min(current_health + amount, max_health)
	var gained := current_health - before
	healed.emit(gained, source)
	health_changed.emit(current_health, max_health)
	var source_hooks := CombatHooks.find_on(source)
	if source_hooks != null:
		source_hooks.heal_done.emit(gained, _get_root(), label)
	CombatEvents.heal_done.emit(gained, source, _get_root(), label)
	return gained


# Kill outright (debug, out-of-bounds). Still goes through about_to_die.
func kill(source: Node = null) -> void:
	var info := DamageInfo.create(current_health + 1.0, source, DamageInfo.Type.TRUE)
	var was_god := god_mode
	god_mode = false
	apply_damage(info)
	god_mode = was_god


# Full health again, e.g. for a respawning training dummy.
func reset() -> void:
	current_health = max_health
	last_damage_source = null
	health_changed.emit(current_health, max_health)


# The max-HP rule (a deliberate design choice; change it here):
#   * losing max HP (a -Health debuff) clamps current HP to the new max;
#   * gaining max HP from a level-up, an item or a buff being APPLIED also
#     gains that much current HP (MOBA convention);
#   * gaining max HP because a debuff was REMOVED grants nothing: current HP
#     stays where it is (capped at the new max). Otherwise a debuff that
#     clamped you would, on expiry, hand back HP you had already lost, i.e.
#     free healing. StatusEffectComponent passes heal_on_gain = false then.
func set_max_health(value: float, heal_on_gain: bool = true) -> void:
	var gained := value - max_health
	max_health = value
	if not is_dead():
		var grant := maxf(gained, 0.0) if heal_on_gain else 0.0
		current_health = clampf(current_health + grant, 1.0, max_health)
	health_changed.emit(current_health, max_health)


func _on_stats_changed() -> void:
	var new_max := stats_component.get_health()
	if not is_equal_approx(new_max, max_health):
		set_max_health(new_max, stats_component.grants_health_on_gain())


func _report_damage(info: DamageInfo) -> void:
	damaged.emit(info.final_amount, info.source)
	damage_taken.emit(info)
	health_changed.emit(current_health, max_health)
	var own_hooks := CombatHooks.find_on(_get_root())
	if own_hooks != null:
		own_hooks.damage_taken.emit(info)
	var source_hooks := CombatHooks.find_on(info.source)
	if source_hooks != null:
		source_hooks.hit_dealt.emit(info, _get_root())
	CombatEvents.damage_dealt.emit(info)


func _die(info: DamageInfo) -> void:
	var root := _get_root()
	var source_hooks := CombatHooks.find_on(info.source)
	if source_hooks != null:
		source_hooks.kill.emit(root, info)
	var own_hooks := CombatHooks.find_on(root)
	if own_hooks != null:
		own_hooks.death.emit(info)
	CombatEvents.actor_died.emit(root, info)
	died.emit()


func _get_root() -> Node:
	return owner if owner != null else get_parent()
