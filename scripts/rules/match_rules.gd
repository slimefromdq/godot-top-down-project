@tool
extends Resource
class_name MatchRules

# Every number the match objective ("Wake the Dreamer") uses: economy,
# leveling, respawns, and later Motes, Dreamers and the endgame.
#
# One shared instance (resources/rules/match_rules.tres), reached like
# GameRules: MatchRules.current(), or MatchRules.override() for a test or a
# playtest mode. Each MatchManager plays on a private copy, which the
# F1 > Match tab edits live.
#
# Groups: Match, Economy, Leveling, Ultimate, Motes, Spawning, Dreamers,
# Wake, Buffs, Objectives, Shop, Late match, Cues.

const DEFAULT_PATH := "res://resources/rules/match_rules.tres"

@export_group("Match")
## Countdown before the match starts. Heroes can move, nobody earns anything.
@export var warmup_time: float = 10.0
## Seconds a dead hero waits before respawning:
## base + per_level x level + the match-time growth below.
@export var respawn_base: float = 5.0
@export var respawn_per_level: float = 0.8
## Respawns get longer as the match goes on: + up to respawn_growth_max
## seconds, rising linearly over the first respawn_growth_time seconds of
## PLAYING. Late deaths cost more, so late fights decide matches.
@export var respawn_growth_max: float = 4.0
@export var respawn_growth_time: float = 1200.0

@export_group("Spawn")
## Each team's spawn area (the bounding box of its spawn markers grown by
## this much) heals its own living heroes: no spawn camping, and a way to
## reset. See SpawnSanctuary.
@export var spawn_area_margin: float = 450.0
## Share of max health healed per second while standing in it...
@export var spawn_heal_pct_per_second: float = 0.3
## ...paid in chunks this many seconds apart.
@export var spawn_heal_interval: float = 0.5

@export_group("Economy")
## Paid to every hero on a team (alive or dead) while the match is PLAYING.
@export var passive_gold_per_second: float = 2.0
@export var passive_xp_per_second: float = 4.0
## Passive income is paid in chunks this many seconds apart.
@export var passive_tick_interval: float = 1.0
## Paid to the hero who lands the killing blow on an enemy hero.
@export var kill_gold: float = 150.0
@export var kill_xp: float = 200.0
## Paid to each other enemy hero who damaged the victim recently.
@export var assist_gold: float = 60.0
@export var assist_xp: float = 100.0
## How recent that damage must be, in seconds.
@export var assist_window: float = 10.0

@export_group("Leveling")
## XP needed to go from level L to L+1
##   = base + growth x (L - 1) + accel x (L - 1)^2,
## so each level costs more than the last, and the late levels much more.
## With 300 / 70 / 12: 7668 XP in total to reach L10, 14292 to reach L13.
@export var xp_level_base: float = 300.0
@export var xp_level_growth: float = 70.0
@export var xp_level_accel: float = 12.0

@export_group("Ultimate")
## In a match, charge-gated slots (SlotDefinition.ultimate_charge: the
## ultimate) ignore their cooldown: every hero starts at 0 charge, earns it
## from the sources below and spends all of it on a cast. Off = ultimates
## use their cooldowns (as on the training maps).
@export var ultimate_charge_enabled: bool = true
## Charge that fills the ultimate.
@export var ult_charge_max: float = 100.0
## Earned by every living hero each second while the match is PLAYING.
@export var ult_charge_per_second: float = 0.35
## Per point of damage dealt to enemy heroes (after resistances).
@export var ult_charge_per_damage: float = 0.03
## Per point of damage taken from enemy heroes (shields included), so
## frontliners charge by soaking.
@export var ult_charge_per_damage_taken: float = 0.015
## Per point of healing done to a teammate (self-heals count at
## ult_charge_self_heal_mult).
@export var ult_charge_per_heal: float = 0.04
@export_range(0.0, 1.0, 0.05) var ult_charge_self_heal_mult: float = 0.25
## Flat charge for a kill and for an assist.
@export var ult_charge_kill: float = 12.0
@export var ult_charge_assist: float = 6.0
## Per Mote value the depositor puts into either Dreamer.
@export var ult_charge_per_mote_value: float = 1.5

@export_group("Motes")
## Most Motes one hero can carry (a Dream Mote takes one slot).
@export var max_carried: int = 25
## Enemy minimap reveal steps by carried VALUE: at reveal_values[i] or more,
## the carrier pings the enemy minimap every reveal_ping_intervals[i]
## seconds (0 = shown all the time). Ascending.
@export var reveal_values: PackedInt32Array = PackedInt32Array([8, 15, 22])
@export var reveal_ping_intervals: PackedFloat32Array = PackedFloat32Array([6.0, 3.0, 0.0])
## Enemy displacements (pushes, pulls, carries, abductions) needed to jostle
## Motes loose. Pushes shorter than jostle_min_distance don't count.
@export var jostle_displacements_required: int = 1
@export var jostle_min_distance: float = 100.0
## For jostle_displacements_required > 1: displacements this far apart
## start the count again.
@export var jostle_window: float = 4.0
## A jostle knocks loose this share of the stack (rounded up), at least one.
## 0.2 = a full stack of 25 loses 5.
@export_range(0.0, 1.0, 0.05) var jostle_drop_fraction: float = 0.2
## Heavy pockets: seconds of extra air time per carried Mote on jump pads
## and trampolines.
@export var heavy_pockets_air_time: float = 0.04
## Death burst: Motes scatter this far from the body.
@export var burst_radius: float = 170.0
## Jostled Motes land about this far from the carrier.
@export var jostle_drop_distance: float = 120.0

@export_group("Spawning")
## Trickle: one small Mote every interval at a free mote_spawn point, while
## fewer than max_loose_motes lie on the map.
@export var trickle_interval: float = 4.0
@export var max_loose_motes: int = 16
## A trickle point is "seen" if a hero is within this range with line of
## sight. Unseen points are preferred.
@export var spawn_sight_range: float = 1300.0
## Dreaming zones: first one at zone_first_time, then every zone_interval
## (counted from the previous zone's start). Announced zone_warning early.
@export var zone_first_time: float = 90.0
@export var zone_interval: float = 120.0
@export var zone_warning: float = 10.0
@export var zone_duration: float = 40.0
## While dreaming, each half spawns a Mote this often, up to
## zone_max_per_half loose Motes in that half.
@export var zone_spawn_interval: float = 1.5
@export var zone_max_per_half: int = 6
## Dream Mote: first at dream_mote_first_time, then dream_mote_interval after
## the previous one is picked up for good (banked, or faded).
@export var dream_mote_first_time: float = 240.0
@export var dream_mote_interval: float = 180.0
@export var dream_mote_warning: float = 15.0

@export_group("Dreamers")
## A carrier standing within this of a Dreamer deposits (the deposit ring).
@export var deposit_radius: float = 300.0
## Seconds before the first Mote of a visit goes in; each next gap is
## deposit_tick_speedup times the last, down to deposit_tick_min.
@export var deposit_tick: float = 0.2
@export_range(0.1, 1.0, 0.05) var deposit_tick_speedup: float = 0.9
@export var deposit_tick_min: float = 0.06
## Banking at your own Dreamer: paid per Mote value, split across the team.
@export var bank_gold_per_value: float = 15.0
@export var bank_xp_per_value: float = 50.0
## Delivering to the enemy Dreamer: paid per value, split across the team.
@export var deliver_gold_per_value: float = 25.0
@export var deliver_xp_per_value: float = 80.0
## The depositor also gets this share of each tick's team payment.
@export_range(0.0, 2.0, 0.05) var depositor_bonus_pct: float = 0.25

@export_group("Wake")
## Delivered value that fills a Dreamer's wake meter. It never drains on its
## own.
@export var wake_meter_max: float = 100.0
## A full meter stirs the Dreamer for this long.
@export var stir_duration: float = 30.0
## The first seconds of a stir refuse deposits (the filling deposit stops
## too), so the defenders always get their final fight.
@export var stir_grace: float = 5.0
## Defenders in this ring fill the Lullaby (larger than the deposit ring).
@export var lullaby_radius: float = 600.0
## Lullaby progress (0..1) per second per living defender in the ring. It
## pauses while any living attacker is inside.
@export var lullaby_rate_per_defender: float = 0.04
## Lullaby progress per value banked at your own stirring Dreamer.
@export var lullaby_per_banked_value: float = 0.02
## A finished Lullaby settles the Dreamer at this share of the wake meter...
@export_range(0.0, 1.0, 0.05) var lullaby_reset_pct: float = 0.6
## ...and a stir that runs out with no final Mote settles it at this.
@export_range(0.0, 1.0, 0.05) var timeout_reset_pct: float = 0.8
## Defenders of a stirring Dreamer respawn this much faster.
@export var stir_defender_respawn_mult: float = 0.75

@export_group("Buffs")
## Every this much banked value gives the whole team the Sweet Dreams buff.
@export var sweet_dreams_threshold: float = 25.0
## The buff; its own duration is replaced by sweet_dreams_duration.
@export var sweet_dreams_status: StatusEffect
@export var sweet_dreams_duration: float = 30.0

@export_group("Objectives")
## Neutral camps (jungle camps and the Nightmare) run on the match clock;
## their own numbers live in each camp's NeutralData. Off = no camp spawns.
@export var objectives_enabled: bool = true
## Mote value dropped by a slain neutral is multiplied by the late-match
## multiplier too, like every other new Mote.
@export var objective_motes_use_late_mult: bool = true

@export_group("Shop")
## What the shop sells.
@export var shop_catalog: ShopCatalog
## Passive items a hero can hold.
@export var item_slots: int = 6
## Active items a hero can hold (each one's ability goes in active_item_slot).
@export var max_active_items: int = 1
## The GameRules slot an active item's ability fills.
@export var active_item_slot: StringName = &"item"
## Selling refunds this share of the item's full cost.
@export_range(0.0, 1.0, 0.05) var sell_refund_pct: float = 0.6
## Heroes within this of their own team's Shop, or anywhere in their spawn
## area, are "in base" and can buy and sell.
@export var shop_radius: float = 700.0
## Dead heroes (waiting to respawn) can shop from anywhere.
@export var shop_while_dead: bool = true
## Debug: shop from anywhere, alive or not (F1 > Match).
@export var shop_anywhere: bool = false

@export_group("Late match")
## After late_match_time, new Motes spawn worth late_match_value_mult times
## as much. This keeps matches from running forever.
@export var late_match_time: float = 900.0
@export var late_match_value_mult: float = 2.0

@export_group("Cues")
## Match-wide looks and sounds (level_up ...). A hero whose own profile has
## the same cue name plays its own instead.
@export var cue_visuals: VisualProfile
@export var cue_audio: AudioProfile
## Cosmetic pitch steps (a major pentatonic): Mote pickups and deposit ticks
## climb it, an octave higher on the second pass.
@export var chime_scale: PackedFloat32Array = PackedFloat32Array([1.0, 1.125, 1.25, 1.5, 1.667])
## Pitches played together when a deposit visit ends: a resolving chord for
## banking, a brighter one for a delivery.
@export var bank_chord: PackedFloat32Array = PackedFloat32Array([1.0, 1.25, 1.5])
@export var deliver_chord: PackedFloat32Array = PackedFloat32Array([1.5, 1.875, 2.25, 3.0])

static var _current: MatchRules


static func current() -> MatchRules:
	if _current == null:
		if ResourceLoader.exists(DEFAULT_PATH):
			_current = load(DEFAULT_PATH)
		else:
			_current = MatchRules.new()
	return _current


# Swap the active rules (tests, alternative playtest modes). null restores
# the default file on the next current().
static func override(rules: MatchRules) -> void:
	_current = rules


func xp_to_next_level(level: int) -> float:
	var steps := float(level - 1)
	return xp_level_base + xp_level_growth * steps + xp_level_accel * steps * steps


# Total XP from level 1 to reach `level`.
func total_xp_for_level(level: int) -> float:
	var total := 0.0
	for l in range(1, level):
		total += xp_to_next_level(l)
	return total


## Seconds between enemy minimap pings for a carried value: -1 = not
## revealed, 0 = shown all the time.
func reveal_interval_for(value: int) -> float:
	var interval := -1.0
	for i in mini(reveal_values.size(), reveal_ping_intervals.size()):
		if value >= reveal_values[i]:
			interval = reveal_ping_intervals[i]
	return interval


## How many Motes a jostle knocks loose from a stack of `count`.
func jostle_drop_count(count: int) -> int:
	return mini(count, maxi(1, ceili(count * jostle_drop_fraction)))


## The n-th chime (1 = first) up the pentatonic scale, over two octaves,
## then round again.
func chime_pitch(n: int) -> float:
	if chime_scale.is_empty():
		return 1.0
	var i := maxi(n - 1, 0) % (chime_scale.size() * 2)
	return chime_scale[i % chime_scale.size()] * (2.0 if i >= chime_scale.size() else 1.0)


## `clock`: seconds of PLAYING so far (MatchManager.clock).
func respawn_time(level: int, clock: float = 0.0) -> float:
	return respawn_base + respawn_per_level * level + respawn_growth(clock)


## The match-time part of the respawn timer at `clock`.
func respawn_growth(clock: float) -> float:
	if respawn_growth_time <= 0.0:
		return respawn_growth_max
	return respawn_growth_max * clampf(clock / respawn_growth_time, 0.0, 1.0)
