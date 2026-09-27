@tool
extends Resource
class_name NeutralData

# One kind of neutral objective: a jungle camp's monster, or the Nightmare
# (resources/match/neutrals/*.tres). A NeutralCamp placed on the map points
# at one; the ObjectiveDirector spawns it on the match clock and pays out
# when it dies. Every number the objective uses lives here.
#
#   schedule  first_spawn_time, then respawn_time after each kill
#             (0 = once per match: the Nightmare). Announced
#             warning_time early when `announce` is on.
#   fight     neutral until hit; then it shoots whoever hit it last, until
#             they leave leash_radius of its camp (it walks home and heals).
#             A volley every attack_interval, and a ring of bolts every
#             ring_interval (0 = none).
#   rewards   gold and XP to the killer and split over the killer's team,
#             Motes that burst out (only the killer's team can grab them for
#             mote_claim_time), and an optional team status (the
#             Nightmare's buff) for the killer's whole team.

@export var id: StringName = &"neutral"
@export var display_name: String = "Neutral"

@export_group("Stats")
## Authored on the 20-level range like heroes (see StatScaling).
@export var stats: StatBlock
## Its level follows the average level of the heroes in the match...
@export var level_from_heroes: bool = true
## ...plus this (bosses can run ahead of the heroes).
@export var level_bonus: int = 0
## Monsters spawned per camp (a pack), spread around the camp point.
@export_range(1, 6) var count: int = 1
@export var pack_spread: float = 90.0

@export_group("Schedule")
## Match-clock seconds of the first spawn.
@export var first_spawn_time: float = 60.0
## Seconds after a kill before it comes back. 0 = never (once per match).
@export var respawn_time: float = 75.0
## Announced (banner, minimap ping, world cue) this many seconds early...
@export var warning_time: float = 0.0
## ...if on. Its spawn and death get banners too.
@export var announce: bool = false

@export_group("Fight")
@export var attack_projectile: ProjectileData
## Per bolt. Scales with the neutral's level (per_level).
@export var attack_damage: ScalingValue
@export var attack_damage_type: DamageInfo.Type = DamageInfo.Type.PHYSICAL
@export var attack_interval: float = 1.4
@export var attack_range: float = 750.0
## Bolts per volley, fanned over volley_spread degrees.
@export_range(1, 12) var volley_count: int = 1
@export var volley_spread: float = 0.0
## A ring of ring_count bolts every ring_interval while fighting. 0 = none.
@export var ring_interval: float = 0.0
@export_range(0, 48) var ring_count: int = 0
## It drops its target and walks home (healing to full) if the target goes
## this far from the camp point, dies, or nobody has hit it for reset_time.
@export var leash_radius: float = 900.0
@export var reset_time: float = 7.0
## Walking speed (home, and toward its target while out of attack range).
## 0 = stays put.
@export var move_speed: float = 0.0

@export_group("Rewards")
@export var killer_gold: float = 0.0
@export var killer_xp: float = 0.0
## Split over the killer's whole team (dead heroes too).
@export var team_gold: float = 0.0
@export var team_xp: float = 0.0
## Motes that burst out of it (each worth mote_value, times the late-match
## multiplier).
@export var mote_count: int = 0
@export var mote_value: int = 1
@export var mote_data: MoteData
@export var mote_burst_radius: float = 200.0
## Only the killer's team can pick them up for this long.
@export var mote_claim_time: float = 8.0
## Applied to every hero on the killer's team; heroes dead at that moment
## get what's left of it when they respawn.
@export var team_status: StatusEffect
## Overrides the status's own duration when above 0.
@export var team_status_duration: float = 0.0
## Ultimate charge for the killer, and for each teammate.
@export var killer_ult_charge: float = 0.0
@export var team_ult_charge: float = 0.0

@export_group("Look")
## The body. Its root gets setup_neutral(monster) if it has that method.
@export var look_scene: PackedScene
@export var size: float = 60.0
@export var color: Color = Color("a78bfa")
## The minimap icon and off-screen arrow (announced objectives only).
@export var icon_color: Color = Color("c084fc")


func get_level(average_hero_level: float) -> int:
	var level := roundi(average_hero_level) if level_from_heroes else 1
	return clampi(level + level_bonus, 1, StatScaling.LEVEL_DOMAIN)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("neutral has no id")
	if stats == null or stats.health == null or stats.health.value_at(1) <= 0.0:
		problems.append("neutral '%s' needs health" % id)
	if attack_interval <= 0.0 or attack_range < 0.0 or leash_radius <= 0.0:
		problems.append("neutral '%s' needs a positive attack interval and leash" % id)
	if first_spawn_time < 0.0 or respawn_time < 0.0 or warning_time < 0.0:
		problems.append("neutral '%s' has negative timings" % id)
	if mote_count < 0 or mote_value < 0:
		problems.append("neutral '%s' has negative Mote rewards" % id)
	if ring_interval > 0.0 and ring_count <= 0:
		problems.append("neutral '%s' has a ring_interval but no ring_count" % id)
	if team_status != null:
		for problem in team_status.validate():
			problems.append("neutral '%s' team_status: %s" % [id, problem])
	return problems
