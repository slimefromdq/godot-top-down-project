@tool
extends Resource
class_name StatusEffect

# A timed buff or debuff. Make one as a .tres (right-click > New Resource >
# StatusEffect) and hand it to an ability, projectile or hit. The same resource
# works on players, enemies and dummies.
#
# One resource type covers every kind of status, by combining optional parts:
#   * stat multipliers   slow (move_speed 0.6), damage amp (damage_taken 1.25)
#   * crowd control      stun / root / silence flags
#   * displacement       knockback or pull, applied once when the status lands
#   * damage over time   burn, poison: a ScalingValue ticked every interval
#   * compel             forced march toward the applier (a taunt, a charm)
#   * stat modifiers     StatModifiers on the target's StatsComponent
#                        (-20% Health, +30 Armor) while active
#   * shield             absorbs damage before health; ends when depleted
#
# StatusEffectComponent.apply() takes an optional `strength` (0..1+) that
# scales how far the stat multipliers move from 1.0 and the shield, e.g. a
# buff charged to 60%, and an optional duration override.
# So swapping Avery's CC from a stun to a knockback or a pull is just pointing
# her ability at a different .tres.

## Stat keys the built-in components read. Add your own and read them with
## StatusEffectComponent.get_multiplier().
const MOVE_SPEED := &"move_speed"
const FIRE_RATE := &"fire_rate"
const DAMAGE := &"damage"
const DAMAGE_TAKEN := &"damage_taken"
## Incoming damage of one type only ("weapon" damage is PHYSICAL here).
## Set them with the incoming_*_multiplier fields below, or as keys in
## stat_multipliers. TRUE damage has no per-type multiplier.
const DAMAGE_TAKEN_PHYSICAL := &"damage_taken_physical"
const DAMAGE_TAKEN_MAGIC := &"damage_taken_magic"

## What happens when the same status is applied again while active.
enum StackRule {
	REFRESH,            ## Reset the timer to full duration (default).
	EXTEND,             ## Add the duration on top, up to max_duration.
	STACK,              ## Add a stack (up to max_stacks) and refresh the timer.
	IGNORE_IF_ACTIVE,   ## Keep the current one untouched.
}

## Which way a displacement pushes the target.
enum DisplaceDirection {
	ALONG_HIT,          ## The direction the hit travelled (a sword's swing).
	AWAY_FROM_SOURCE,   ## Straight away from the attacker.
	TOWARD_SOURCE,      ## A pull.
}

## Re-applying an effect with the same id follows stack_rule.
@export var id: StringName = &"status"
@export var display_name: String = "Status"
@export var duration: float = 3.0
## Multipliers, keyed by stat name: move_speed, fire_rate, damage, damage_taken.
## 1.0 means unchanged, 1.5 means +50%, 0.5 means -50%. With STACK, each
## stack applies the multiplier again (0.9 at 3 stacks = 0.729).
@export var stat_multipliers: Dictionary[StringName, float] = {}
## Incoming PHYSICAL (weapon) damage x this while active (0.5 = half).
## Same rules as stat_multipliers: strength, fading and stacks apply.
@export var incoming_physical_multiplier: float = 1.0
## Incoming MAGIC damage x this while active (1.3 = +30%).
@export var incoming_magic_multiplier: float = 1.0
## The multipliers fade linearly from their full value back to 1.0 over the
## duration (a wind-up that runs down). Visuals can read the remaining
## fraction with StatusEffectComponent.get_fade_ratio().
@export var fade_multipliers: bool = false

@export_group("Stacking")
@export var stack_rule: StackRule = StackRule.REFRESH
## STACK only.
@export_range(1, 99) var max_stacks: int = 1
## EXTEND only. 0 = no cap.
@export var max_duration: float = 0.0
## Each applier gets its own copy (own timer, stacks, modifiers and death
## notification) instead of sharing one. Use it for marks and anything whose
## applier must be told what happened. Off = one shared copy per target, and
## the latest applier owns it.
@export var stack_per_applier: bool = false
## End the status early when whoever applied it dies or is removed. Compel
## always behaves this way.
@export var ends_if_applier_dies: bool = false

@export_group("Crowd control")
## No moving, no casting, and interrupts the current cast.
@export var stuns: bool = false
## No walking or dashing; casting is still allowed.
@export var roots: bool = false
## No casting abilities; walking is still allowed.
@export var silences: bool = false
## Can't be hit or targeted at all (hits, zones and statuses skip the
## hurtbox) while active. Not invisibility: pair it with body_alpha.
@export var untargetable: bool = false

@export_group("Displacement")
## Pixels pushed when the status lands. 0 = none. The push is a short forced
## move (not an impulse) so the distance is exact and identical on every
## machine, which matters for networking.
@export var displace_distance: float = 0.0
@export var displace_duration: float = 0.15
@export var displace_direction: DisplaceDirection = DisplaceDirection.ALONG_HIT
## TOWARD_SOURCE only: a pull stops this far from the attacker so it doesn't
## drag the target through them.
@export var pull_stop_distance: float = 80.0

@export_group("Compel")
## Forced march: the target walks toward the applier's CURRENT position every
## physics tick (a taunt, a charm). Stuns and roots still stop it, and a
## displacement (knockback) plays out first, then the march resumes. Ends
## early if the applier dies. Casting is still allowed unless `silences`.
@export var compel_enabled: bool = false
## Fraction of the TARGET's current move speed used for the march.
@export var compel_speed_multiplier: float = 1.0
## Stops walking this close to the applier.
@export var compel_stop_distance: float = 80.0
## Ignore the target's own steering (player input or AI) while compelled.
## Off = the march is added on top of it, so the target can resist.
## Movement only: compelled targets can always shoot and cast.
@export var compel_overrides_input: bool = true
## Formation mode: instead of walking at the applier, walk to a point on the
## applier's recent path, compel_trail_spacing x slot pixels behind them
## (slots in order of joining). Followers form a line that takes her turns.
@export var compel_follow_trail: bool = false
@export var compel_trail_spacing: float = 110.0
## Followers can break free: by holding movement input against the
## formation for compel_break_hold_time, by using a movement ability (if
## compel_break_on_movement_ability), or via break_formation() (AI).
@export var compel_breakable: bool = false
@export var compel_break_hold_time: float = 0.4
@export var compel_break_on_movement_ability: bool = true

@export_group("Shield")
## Damage absorbed before health, snapshotted from the APPLIER's stats when
## applied (times the application's strength). The status ends when the
## shield is used up. Reapplying: REFRESH/EXTEND keep the larger of the
## remaining and the new shield; STACK adds them.
@export var shield_amount: ScalingValue

@export_group("Stat modifiers")
## Applied to the TARGET's StatsComponent while active (scaled by stacks),
## removed exactly when the status ends. Max HP changes follow
## HealthComponent's rule (losing max HP clamps; the removal of a debuff
## never grants current HP).
@export var stat_modifiers: Array[StatModifier] = []

@export_group("Damage over time")
## Damage per tick, evaluated from the APPLIER's stats when applied (snapshot).
## Leave empty for no DoT.
@export var tick_damage: ScalingValue
@export var tick_interval: float = 0.5
@export var tick_damage_type: DamageInfo.Type = DamageInfo.Type.MAGIC
## Damage-meter label for the ticks, e.g. "burn".
@export var tick_label: StringName = &""

@export_group("Presentation")
## Scene attached to the affected actor for as long as the effect lasts.
## Overhead marks use this too: give the scene its own upward offset (see
## scenes/combat/overhead_marker.tscn).
@export var attached_vfx: PackedScene
## Tint blended over the actor's body while active. Alpha controls strength.
@export var body_tint: Color = Color(1, 1, 1, 0)
## Body opacity while active (a faded silhouette). 1 = unchanged; the
## lowest active value wins.
@export_range(0.0, 1.0, 0.05) var body_alpha: float = 1.0
## Played once when the effect is applied.
@export var apply_sound: SoundCue


# The multiplier this status applies to `stat` at full strength: the
# stat_multipliers entry, times the incoming_*_multiplier field for the
# per-type damage stats.
func get_stat_multiplier(stat: StringName) -> float:
	var result: float = stat_multipliers.get(stat, 1.0)
	if stat == DAMAGE_TAKEN_PHYSICAL:
		result *= incoming_physical_multiplier
	elif stat == DAMAGE_TAKEN_MAGIC:
		result *= incoming_magic_multiplier
	return result


static func damage_taken_stat(damage_type: DamageInfo.Type) -> StringName:
	match damage_type:
		DamageInfo.Type.PHYSICAL: return DAMAGE_TAKEN_PHYSICAL
		DamageInfo.Type.MAGIC: return DAMAGE_TAKEN_MAGIC
	return &""


func is_crowd_control() -> bool:
	return stuns or roots or silences or displace_distance > 0.0 or compel_enabled


func ends_with_applier() -> bool:
	return ends_if_applier_dies or compel_enabled


# Problems a designer should fix. Empty = fine.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("status has no id")
	if duration < 0.0 or max_duration < 0.0 or displace_distance < 0.0 or displace_duration < 0.0 \
			or pull_stop_distance < 0.0 or tick_interval < 0.0:
		problems.append("status '%s' has negative timings/distances" % id)
	if tick_damage != null and tick_damage.has_negative():
		problems.append("status '%s' tick_damage has negative numbers" % id)
	if compel_enabled and (compel_speed_multiplier <= 0.0 or compel_stop_distance < 0.0):
		problems.append("status '%s' compel needs a positive speed and stop distance" % id)
	if shield_amount != null and shield_amount.has_negative():
		problems.append("status '%s' shield_amount has negative numbers" % id)
	if compel_follow_trail and (compel_trail_spacing <= 0.0 or compel_break_hold_time < 0.0):
		problems.append("status '%s' follow_trail needs a positive spacing" % id)
	for i in stat_modifiers.size():
		if stat_modifiers[i] == null:
			problems.append("status '%s' stat modifier %d is empty" % [id, i + 1])
		elif not StatBlock.ALL.has(stat_modifiers[i].stat):
			problems.append("status '%s' stat modifier %d has unknown stat '%s'" % [id, i + 1, stat_modifiers[i].stat])
	return problems
