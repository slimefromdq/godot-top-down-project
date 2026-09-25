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
# So swapping Avery's CC from a stun to a knockback or a pull is just pointing
# her ability at a different .tres.

## Stat keys the built-in components read. Add your own and read them with
## StatusEffectComponent.get_multiplier().
const MOVE_SPEED := &"move_speed"
const FIRE_RATE := &"fire_rate"
const DAMAGE := &"damage"
const DAMAGE_TAKEN := &"damage_taken"

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

@export_group("Stacking")
@export var stack_rule: StackRule = StackRule.REFRESH
## STACK only.
@export_range(1, 99) var max_stacks: int = 1
## EXTEND only. 0 = no cap.
@export var max_duration: float = 0.0

@export_group("Crowd control")
## No moving, no casting, and interrupts the current cast.
@export var stuns: bool = false
## No walking or dashing; casting is still allowed.
@export var roots: bool = false
## No casting abilities; walking is still allowed.
@export var silences: bool = false

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
@export var attached_vfx: PackedScene
## Tint blended over the actor's body while active. Alpha controls strength.
@export var body_tint: Color = Color(1, 1, 1, 0)
## Played once when the effect is applied.
@export var apply_sound: SoundCue


func is_crowd_control() -> bool:
	return stuns or roots or silences or displace_distance > 0.0
