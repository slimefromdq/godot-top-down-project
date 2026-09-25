@tool
extends Resource
class_name GroundZoneData

# A patch of ground that hurts (or debuffs) whoever stands in it for a while:
# a fire trail, a poison pool, a healing circle later. Spawned with
# GroundZone.spawn().

@export var shape: HitShape
## Seconds the zone lasts.
@export var duration: float = 1.5
## Seconds between damage ticks. The first tick happens on spawn.
@export var tick_interval: float = 0.5
## Damage per tick, from the spawner's stats at spawn time. Empty = no damage
## (a purely visual or status-only zone).
@export var tick_damage: ScalingValue
@export var damage_type: DamageInfo.Type = DamageInfo.Type.MAGIC
## Applied on every tick to everyone inside (e.g. a burn or a slow).
@export var status: StatusEffect
@export var meter_label: StringName = &"zone"

@export_group("Presentation")
## Scene instanced as the zone's look. Empty = a simple drawn circle.
@export var visual_scene: PackedScene
@export var color: Color = Color(1.0, 0.45, 0.1, 0.35)


func has_negative() -> bool:
	return duration < 0.0 or tick_interval < 0.0 \
		or (shape != null and shape.has_negative()) \
		or (tick_damage != null and tick_damage.has_negative())
