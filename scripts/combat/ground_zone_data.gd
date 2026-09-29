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
## Apply `status` / `status_while_inside` as coming from the ZONE itself,
## not its owner. A compel then pulls toward the zone's centre (a
## whirlpool) and ends when the zone does. Damage is still the owner's.
@export var statuses_from_zone: bool = false

@export_group("Ramp")
## Damage ramp (see ZoneRamp): each damage tick on a target hits
## 1 + ramp_per_tick x (ticks it has already taken) times harder, up to
## ramp_max. With 1 s ticks, 0.5 = "+50% per second inside". 0 = no ramp.
@export var ramp_per_tick: float = 0.0
## Highest damage multiplier the ramp reaches.
@export var ramp_max: float = 1.0
## Seconds a target must stay outside every zone sharing the ramp before it
## starts over.
@export var ramp_reset_after: float = 1.0
## Zones with the same owner and key share one ramp per target (an aura and
## the clouds its hero throws). Empty = the zone's meter_label.
@export var ramp_key: StringName = &""
## Targets inside are at full ramp at once (a "breach": max damage now).
@export var ramp_starts_full: bool = false

@export_group("Death intercept")
## A safety net: an ally inside (by `affects`) who would die is saved instead,
## once per ally per zone: the death is cancelled (about_to_die), health set
## to intercept_health_ratio of max, moved next to the zone's owner and given
## intercept_status. GroundZone.death_intercepted reports each save.
@export var intercepts_deaths: bool = false
## Health left after a save, as a fraction of max health.
@export_range(0.0, 1.0, 0.01) var intercept_health_ratio: float = 0.15
## Pixels from the owner the saved ally is put down. < 0 = don't move them.
@export var intercept_move_to_owner: float = 90.0
## Put on the saved ally (e.g. a moment of untargetable).
@export var intercept_status: StatusEffect

@export_group("Leftover")
## Spawned where this zone was when it ran its course or was end()ed (a
## residue, embers): same owner, facing the same way. Not spawned when the
## zone is freed without ending (a map change).
@export var leaves_zone: GroundZoneData

@export_group("Detonation")
## The zone can be detonated (GroundZone.detonate(), or the trigger below):
## this explosion template (its Explosion group: shape, explosion_damage,
## explosion_status...) goes off at the zone's centre as the owner's hit,
## and the zone is consumed. Empty = can't be detonated.
@export var detonation: ProjectileData
## Detonates by itself when its OWNER stands in it while carrying a status
## with this id (a bike's Burnout driving over its own oil). Empty = only
## scripts detonate it.
@export var detonated_by_owner_status: StringName = &""
## Most zones of this data (by meter_label) one owner may have; spawning
## another ends the oldest. 0 = no cap.
@export var max_per_owner: int = 0

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
## Draw order. Zones sit under characters at -5; a zone whose edge must stay
## readable over other ground effects (a danger ring) goes a little higher,
## still below 0 (characters).
@export var draw_z_index: int = -5


func has_ramp() -> bool:
	return ramp_per_tick > 0.0


func get_ramp_key() -> StringName:
	return ramp_key if ramp_key != &"" else meter_label


func has_negative() -> bool:
	return duration < 0.0 or tick_interval < 0.0 or max_duration < 0.0 \
		or ramp_per_tick < 0.0 or ramp_reset_after < 0.0 or max_per_owner < 0 \
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
	if ramp_per_tick > 0.0 and ramp_max < 1.0:
		problems.append("zone ramps but ramp_max is below 1")
	if leaves_zone == self:
		problems.append("zone leaves itself behind (endless)")
	for effect in [status, status_while_inside]:
		if effect != null:
			for problem in effect.validate():
				problems.append("zone " + problem)
	return problems
