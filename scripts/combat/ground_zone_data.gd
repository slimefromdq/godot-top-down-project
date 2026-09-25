@tool
extends Resource
class_name GroundZoneData

# A patch of ground that hurts (or debuffs, or buffs) whoever stands in it for
# a while: a fire trail, a poison pool, a healing circle, or a persistent cone
# in front of a hero (follow_owner + face_aim + an ARC shape). Spawned with
# GroundZone.spawn(), or Ability.spawn_owned_zone() to tie it to a cast.

@export var shape: HitShape
## Seconds the zone lasts. An ability can override it per spawn.
@export var duration: float = 1.5
## Seconds between damage ticks. The first tick happens on spawn.
@export var tick_interval: float = 0.5
## Damage per tick, from the spawner's stats at spawn time. Empty = no damage
## (a purely visual or status-only zone). Damage only ever hits targets the
## owner may hit (enemies), whatever `affects` says.
@export var tick_damage: ScalingValue
@export var damage_type: DamageInfo.Type = DamageInfo.Type.MAGIC
## Applied on every tick to everyone affected (e.g. a burn or a slow). It
## runs its own duration after they leave.
@export var status: StatusEffect
## Applied on every tick to everyone affected and removed the moment they
## leave the zone (or it ends): an aura. Give it a duration a bit longer than
## tick_interval so it never flickers off between ticks.
@export var status_while_inside: StatusEffect
@export var meter_label: StringName = &"zone"

@export_group("Ownership")
## Stay centred on the owner (the actor that spawned it) every tick.
@export var follow_owner: bool = false
## Rotate with the owner's aim every tick (an ARC shape becomes a cone that
## always points where the hero aims).
@export var face_aim: bool = false
## Who it affects: statuses and target_* signals use this; damage never hits
## allies.
@export var affects: Hitbox.Affects = Hitbox.Affects.ENEMIES
## End the zone when its owner dies or is removed.
@export var ends_if_owner_dies: bool = false
## Hard cap in seconds, even when an ability overrides the duration. 0 = none.
@export var max_duration: float = 0.0
## Spawned with Ability.spawn_owned_zone(): keep going after the cast ends or
## is interrupted. Off = the zone ends with the cast.
@export var outlives_cast: bool = false

@export_group("Presentation")
## Scene instanced as the zone's look. Empty = a simple drawn shape.
@export var visual_scene: PackedScene
@export var color: Color = Color(1.0, 0.45, 0.1, 0.35)
## Edge line, so the danger radius reads at a glance. Alpha 0 = no outline.
@export var outline_color: Color = Color(1, 1, 1, 0)
@export var outline_width: float = 4.0


func has_negative() -> bool:
	return duration < 0.0 or tick_interval < 0.0 or max_duration < 0.0 \
		or (shape != null and shape.has_negative()) \
		or (tick_damage != null and tick_damage.has_negative())


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if shape == null:
		problems.append("zone has no shape")
	if has_negative():
		problems.append("zone has negative values")
	if face_aim and shape != null and shape.kind == HitShape.Kind.CIRCLE and shape.forward_offset == 0.0:
		problems.append("zone faces the aim but is a centred CIRCLE (rotation does nothing)")
	for effect in [status, status_while_inside]:
		if effect != null:
			for problem in effect.validate():
				problems.append("zone " + problem)
	return problems
