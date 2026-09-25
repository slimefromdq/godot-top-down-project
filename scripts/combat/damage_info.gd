extends RefCounted
class_name DamageInfo

# Everything about one hit, in one object. Every source of damage (a sword
# swing, a projectile, a burn tick, a legacy bullet) builds one of these and
# hands it to a HurtboxComponent or HealthComponent, so there is exactly one
# damage pipeline to reason about, log, and later send over the network.
#
# The attacker fills in the "request" fields. HealthComponent fills in the
# "result" fields after resistances, so hooks like heal-on-hit can react to
# what actually landed.

enum Type { PHYSICAL, MAGIC, TRUE }

# Common tags. Tags are free-form StringNames; these are just the ones the
# built-in systems set.
const TAG_MELEE := &"melee"
const TAG_PROJECTILE := &"projectile"
const TAG_ABILITY := &"ability"
const TAG_BASIC := &"basic_attack"
const TAG_DOT := &"dot"
const TAG_AREA := &"area"

# --- Request --------------------------------------------------------------
## Damage before resistances.
var amount: float = 0.0
var type: Type = Type.PHYSICAL
## The actor (or other node) responsible. Used for kill credit and hooks.
var source: Node = null
var tags: Array[StringName] = []
## Groups hits that belong to one swing/cast/projectile. A Hitbox never hits
## the same target twice with the same attack_id; Searing Cut counts targets
## per attack_id for its diminishing returns.
var attack_id: int = 0
## What the damage meter files this under ("blade", "crescent", "burn", ...).
var label: StringName = &""
## World-space impulse applied to the target's MovementComponent.
var knockback: Vector2 = Vector2.ZERO
## Statuses applied on hit (stun, slow, burn ...).
var statuses: Array[StatusEffect] = []
## Direction the hit travelled, for knockback, VFX and directional statuses.
var direction: Vector2 = Vector2.ZERO
## Where it landed, for VFX.
var hit_position: Vector2 = Vector2.ZERO
## Attack "weight" for game feel (0 = light jab, 1 = normal, 2+ = finisher).
## Cosmetic systems (hitstop, shake) scale with it; gameplay never reads it.
var weight: float = 1.0
## The feel preset of the swing that produced this hit, for hitstop / shake /
## sound. Cosmetic only: never read by gameplay, never sent over a network.
var feel: AttackFeel = null

# --- Result (filled in by HealthComponent) --------------------------------
## Damage actually removed from health, after resistances and multipliers.
var final_amount: float = 0.0
## True if this hit dealt the killing blow.
var killed: bool = false
## The node that took the hit (the target's root).
var target: Node = null


static var _next_attack_id: int = 1


# A fresh id for a new swing, cast or projectile.
static func new_attack_id() -> int:
	_next_attack_id += 1
	return _next_attack_id


static func create(damage: float, from: Node = null, damage_type: Type = Type.PHYSICAL) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = damage
	info.source = from
	info.type = damage_type
	return info


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func add_status(effect: StatusEffect) -> DamageInfo:
	if effect != null:
		statuses.append(effect)
	return self


# A copy with the same request fields, for hitting several targets with one
# attack (each target gets its own result fields).
func copy() -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.type = type
	info.source = source
	info.tags = tags.duplicate()
	info.attack_id = attack_id
	info.label = label
	info.knockback = knockback
	info.statuses = statuses.duplicate()
	info.direction = direction
	info.hit_position = hit_position
	info.weight = weight
	info.feel = feel
	return info


static func type_name(damage_type: Type) -> String:
	return ["physical", "magic", "true"][damage_type]
