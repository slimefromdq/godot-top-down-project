extends Resource
class_name StatusEffect

# A timed buff or debuff. Make one as a .tres (right-click > New Resource >
# StatusEffect) and hand it to a BuffAbility, a TargetedAbility or a
# projectile. The same resource works on players, enemies and dummies.

## Stat keys the built-in components read. Add your own and read them with
## StatusEffectComponent.get_multiplier().
const MOVE_SPEED := &"move_speed"
const FIRE_RATE := &"fire_rate"
const DAMAGE := &"damage"
const DAMAGE_TAKEN := &"damage_taken"

## Re-applying an active effect refreshes its timer instead of stacking.
@export var id: StringName = &"status"
@export var display_name: String = "Status"
@export var duration: float = 3.0
## Multipliers, keyed by stat name: move_speed, fire_rate, damage, damage_taken.
## 1.0 means unchanged, 1.5 means +50%, 0.5 means -50%.
@export var stat_multipliers: Dictionary[StringName, float] = {}

@export_group("Presentation")
## Scene attached to the affected actor for as long as the effect lasts.
@export var attached_vfx: PackedScene
## Tint blended over the actor's body while active. Alpha controls strength.
@export var body_tint: Color = Color(1, 1, 1, 0)
## Played once when the effect is applied.
@export var apply_sound: SoundCue
