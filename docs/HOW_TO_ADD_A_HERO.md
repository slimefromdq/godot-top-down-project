# How to add a hero

After adding a hero, give it a placeholder body (`sprites/heroes/<hero>.svg`,
see VISUALS_AND_AUDIO.md) and try it as a bot through F1 > Bots. Check that it can
move, use its slots, and take part in a match; bot control reads the hero's
`AbilityData` and has no hero-specific script.

A hero is **data plus a few small scripts**. The systems (health, damage,
hitboxes, projectiles, statuses, the cast state machine, movement, game feel,
HUD, debug tools, balance export) are shared and never need editing for a new
hero.

Avery (`heroes/avery/`) is the worked example throughout. Rook
(`heroes/rook/`) was made by following exactly these steps, with nothing but
a definition and one ability script. Jose (`heroes/jose/`) is the ranged
example: three of his five slots are pure data (see "What Jose took" below).

---

## The pieces

```
heroes/<name>/
├── <name>_definition.tres    HeroDefinition: who the hero is (everything below plugs in here)
├── <name>_feel.tres          FeelProfile: timing + weight presets (light / heavy / finisher ...)
├── <name>_hero.tscn          the hero scene: hero_base.tscn + the definition
├── <name>_basic_attack.tres  AbilityData for one slot
└── <name>_basic_attack.gd    ability script (optional: most slots reuse a generic one)
```

| Resource | Holds | Avery's |
|---|---|---|
| `HeroDefinition` | name, title, role, stats, slot → ability map, feel, visuals, audio | `avery_definition.tres` |
| `StatBlock` / `StatScaling` | Health, Weapon, Magic, Armor, Magic Resist: base + growth, optional curve | inside the definition |
| `AbilityData` (+ subclasses) | cooldown, cost, hit shape, damage/heal `ScalingValue`s, statuses, feel preset, **which script runs it** | `abilities/*.tres` |
| `ScalingValue` | `base + per_level·(lvl−1) + weapon_ratio·Weapon + magic_ratio·Magic` | every damage/heal number |
| `FeelProfile` / `AttackFeel` | windup / active / recovery, lunge, slow, cancel windows, hitstop, shake, trail, sounds | `avery_feel.tres` |
| `StatusEffect` | slow, stun, root, silence, knockback/pull, burn, compel, stat modifiers; stacking rules | `data/avery_sunbrand_status.tres`, `data/avery_burn.tres` |
| `ProjectileData`, `GroundZoneData` | projectile flight / ground fire | `data/sun_crescent.tres`, `data/fire_trail.tres` |

Slots come from `resources/rules/game_rules.tres`: `primary` (LMB),
`ability_1` (RMB), `ability_2` (F), `movement` (Shift), `cc` (E),
`ultimate` (Q). Rebinding a key or adding a slot type is a data edit there.

---

## Step by step

### 1. Copy the template

**Project → Tools → New Hero from Template…**, type a name (e.g. `Rook`).

This creates `heroes/rook/` with every file renamed and every internal path
rewritten, so the new hero never points back into `_template`. The new
scene opens automatically, and it already runs: it has a working basic attack.

> Headless alternative: `HeroScaffold.create("Rook")`.

### 2. Fill in the definition

Open `<name>_definition.tres`. Set **display name, title, role, description**,
then the **stats**: each stat is a `StatScaling` with `base` (level 1) and
`growth` (average gain per level).

* **Consistent hero** (Avery): leave `curve` empty → linear growth.
* **Power spike** (Rook's Weapon): add a `Curve`. X = progress from level 1
  (0) to level 20 (1); Y = fraction of the total growth unlocked. A curve that
  stays low then rises = late spike. The level-20 value is the same as linear,
  so heroes stay comparable in the CSV.

The read-only **Validation** line at the bottom of the inspector lists
problems live: missing required slots, abilities without data or script,
negative numbers. A work-in-progress hero with only a basic attack shows its
empty slots there; that's expected (Rook does).

### 3. Give each slot an ability

For each slot in the definition's `abilities` dictionary, point at an
`AbilityData` resource. Its `ability_script` decides what runs:

| You want | Use | Script to write |
|---|---|---|
| a melee swing or combo, optionally throwing a projectile per swing | `MeleeAttackData` + `MeleeAttackAbility` | none |
| a telegraphed dash / charge, optionally leaving a ground trail | `ChargeData` + `ChargeAbility` | none |
| a quick roll the way you're walking, with an immunity window | `ChargeData` with `direction_mode = MOVE_INPUT_OR_AIM`, `invulnerable_duration` | none |
| a melee CC (stun, knockback, pull) | `MeleeAttackData` with `on_hit_status` | none |
| a gun: rifle, revolver, shotgun, dual pistols (any slot) | `RangedAttackData` + `RangedAttackAbility` | none |
| hold to charge, release to fire (any timed ability) | the **Charge** group on any `AbilityData` + `data.get_charged_value()` | none for guns |
| a taunt / charm (target walks toward you) | `StatusEffect` with `compel_enabled` | none |
| a debuff or buff that changes stats (-20% Health, +30 Armor) | `StatusEffect.stat_modifiers` | none |
| react when your marked target dies / your status ends | `actor.combat_hooks.status_target_died` / `status_expired` / `status_removed` | a small script |
| a cone or aura that follows you for a while | `ZoneAbilityData` + `ZoneAbility` (zone with `follow_owner`, `face_aim`) | none |
| custom per-target zone logic | `spawn_owned_zone()` from any ability + the zone's `target_*` signals | a small script |
| a channel that blocks some abilities but not others | `controller.lock_abilities(self, allowed_slots, quiet_slots)` / `unlock_abilities(self)` | a small script |
| another ability firing your gun (autofire, turrets) | `hero.get_ranged_ability().fire_extra_shot(direction, label)` | a small script |
| a timing minigame (hit notes on the beat) | `RhythmPhrase` + `RhythmPerformer.find_or_create(actor).play(phrase, cue_prefix)` | a small script (react to `note_graded`) |
| a shield (absorb) | `StatusEffect.shield_amount` | none |
| a projectile that explodes (on hit / at range), optionally splitting | `ProjectileData` Explosion group (+ Split subgroup) | none |
| a buff that runs down over its duration | `StatusEffect.fade_multipliers`; `apply(..., strength)` for charge-scaled buffs | none |
| cast on an ally near the cursor, optionally tethered | `AbilityData.ally_targeting` (`AllyTargeting`) + `tether_range`; `cast_ally` in the script | none |
| a formation / parade line behind the caster | compel status with `compel_follow_trail` (+ `compel_breakable`) | none |
| a charged dash that goes further and hits harder | `ChargeData` with `charge_enabled`, `min_distance`, `hit_shape` + `damage` / `values/damage_full` + `on_hit_status` | none |
| a passive with stacks on the ability bar | the optional `passive` slot + `PassiveAbility` (override `get_hud_pips`) | a small script |
| take more/less damage of one type (a magic amp, a weapon resist) | `StatusEffect.incoming_physical_multiplier` / `incoming_magic_multiplier` | none |
| untargetable for a moment (a vanish), faded body | `StatusEffect.untargetable`, `body_alpha` | none |
| a boomerang (out and back, optionally curved) | `ProjectileData.return_to_caster`, `curve_amount`; return hits carry `Projectile.TAG_RETURN` | none |
| a blast with no projectile (ground-targeted, meteor) | `Projectile.explode_at(actor, data, at, dir, template, on_hit)` | a small script |
| ammo that regenerates (no reloading) | `RangedAttackData.reload_style = REGEN` + `regen_interval`; `set_max_ammo()` / `set_regen_interval()` at runtime | none |
| a pull you can slowly walk out of, toward a zone | compel with `compel_overrides_input = false` (strength = `compel_speed_multiplier`) as a zone status with `statuses_from_zone` | none |
| a blink up to the cursor, then an effect on yourself | `ChargeData` with a high `speed`, `stop_at_target`, `self_status` | none |
| a hero-level number in the CSV (a combo's burst) | override `AbilityData.get_hero_metrics(definition, level)` (source "derived") | a small data script |
| hold to ride fast and steer, then land with a telegraphed burst | `RideData` + `RideAbility` (the ride is the Charge phase: `charge_time_max` = longest ride) | none |
| drive the body along a direction you steer every tick (a mount) | `movement_component.set_cruise(self, dir, speed)` / `clear_cruise(self)` | a small script |
| a buff/shield on yourself that grows with enemies nearby | `SelfStatusData` + `SelfStatusAbility` (`strength_base` + `strength_per_enemy`) | none |
| enemies swept up and carried along with you, then dropped | `StatusEffect.carry_enabled` as a dash's `on_hit_status` + `ChargeData.end_on_hit_status_on_arrival` / `arrival_status` | none |
| a dash telegraph of its own length | `ChargeData.telegraph_time` | none |
| a zone whose damage ramps the longer you stand in it (a gas that gets worse) | `GroundZoneData` Ramp group: `ramp_per_tick`, `ramp_max`, `ramp_reset_after`, `ramp_key` (zones with the same owner + key share one ramp per target), `ramp_starts_full`; push it from scripts with `ZoneRamp.raise_steps` / `reset` | none |
| a zone that leaves another behind when it ends (a residue, embers) | `GroundZoneData.leaves_zone` | none |
| a lobbed grenade that lands on the cursor, over walls, and leaves a cloud | `ProjectileData.lobbed` + `explode_on_expire` + `explosion_shape` + `explosion_zone` (any zone) | none |
| hold a key to keep a status on yourself (a scope, a guard stance), still free to shoot | `SelfStatusData.hold_to_keep` (released = removed; the status's duration caps the hold) | none |
| a scope: the player's view shifts toward the cursor | `StatusEffect.camera_look_ahead` (px) on a self status; scripts can `ShakeCamera.request_look_ahead(requester, px)` | none |
| a laser sight everyone can see | `effects/feel/aim_laser.tscn` (`AimLaser`) as a status's `attached_vfx` | none |
| a parry: reflect the first projectile / stun the first melee attacker | `StatusEffect.parries` + `parry_melee_status`; react with `actor.combat_hooks.parried(kind, attacker, info)` | none (a small script for rewards) |
| a leap / glide to the cursor over low cover and ledges, optionally steerable | `LaunchData` + `LaunchAbility` (`max_distance`, `air_time`, `steer_speed`); scripts can `actor.retarget_launch(point)` mid-air | none |
| shots that pass through some targets without using up pierce | override `RangedAttackAbility._hit_is_free_pierce(hurtbox)` (`Projectile.free_pierce`) | a small script |
| an ability with charges (two uses stocked, one recharging) | `AbilityData.max_charges`; the HUD shows them as pips | none |
| place a jump pad: press, drag the landing spot, release; allies launch, enemies bounce | `PlacePadData` + `PlacePadAbility` (charge group on for the drag); scripts can `JumpPad.place(...)`. Preview: hook `effects/feel/pad_preview.tscn` to `<id>_charge_start` | none |
| a zone that saves allies who would die (a safety net) | `GroundZoneData` Death intercept group (`intercepts_deaths`, health ratio, move to owner, status); `GroundZone.death_intercepted` | none |
| cast a zone and move on (no channel) | `ZoneAbilityData.instant` | none |
| shots that ricochet off walls | `ProjectileData.wall_bounces` | none |
| shorter knockbacks and pulls on someone | `StatusEffect.DISPLACEMENT_TAKEN` in `stat_multipliers` (0.6 = 40% shorter) | none |
| an animated body from layered art (cutout rig baked to sprite frames) | copy `resources/visuals/rig_template/rig_template.tscn` (`CutoutRig`), bake with `tools/visuals/bake_rig.gd`, set the result as `VisualProfile.sprite_frames` (see docs/VISUALS_AND_AUDIO.md) | none |
| a body that faces the mouse while the legs walk (forward or backpedalling) with the movement keys | `CutoutRig.legs_layer_paths` (baked as `<frames>_legs.tres`) + `VisualProfile.legs_frames`; `bake_rig.gd --profile` fills it in | none |
| an 8-direction body from a per-facing sheet (body faces the mouse, legs strafe/backpedal, arm aims) | `SheetSpec` + `tools/visuals/cut_sheet.gd` to cut parts, a `LiveRig` scene, `VisualProfile.live_rig` | none |
| a whole-body sprite per pose (idle / walk / shoot) instead of cutout parts | a `LiveRig` whose `Upper` sprites carry `walk_textures` (one per step) and `shoot_texture` metadata; a cue with Body Animation `shoot` calls `LiveRig.shoot()` (hold time `RigMotion.shoot_pose_time`). Jose's rig is the example | none |
| a weapon arm that turns toward the aim on a baked body | `CutoutRig.aim_part_path` (exported by the bake) + `VisualProfile` Aim Part group; `bake_rig.gd --profile` fills it in | none |
| a second form: swap a slot to another ability and back (each keeps its own cooldown) | `AbilityController.swap_slot(slot_id, data)` / `restore_slot(slot_id)` / `is_slot_swapped`; the swapped-out ability goes dormant (`Ability.is_dormant()`) | a small script (decides when) |
| hold to raise a shield/cloak on your aim arc that eats projectiles and has its own HP | `BlockerData` + `BlockerAbility` (a `FrontalBlocker`: HP `ScalingValue`, regen, break, slots allowed while raised, raised/lowered statuses) | none |
| lifesteal / a drain | `AbilityData.lifesteal` (share of this ability's damage dealt that heals the caster) | none |
| a status only while dashing (untargetable swarm, barging armor) | `ChargeData.dash_status` | none |
| an ultimate charged by playing in a match (no cooldown there) | nothing: the `ultimate` slot has `SlotDefinition.ultimate_charge`, and `MatchRules` > Ultimate sets the rates. A script that starts the ultimate itself (a passive revive) calls `_spend_cooldown()`, which spends the charge in a match | none |
| heal over time / regen (a buff that restores health each tick) | `StatusEffect.tick_heal_ratio` (share of max HP per `tick_interval`, times stacks) | none |
| read how many Motes someone carries (show a count, scale an effect) | `MoteCarrier.find_on(actor).get_mote_count()` / `get_mote_value()` / `changed` signal | a small script |
| credit for pushing someone into a map hazard (thorns, sleep-fog) | nothing: any enemy push, pull or carry that reports `Actor.displaced` makes the `HazardZone`'s ticks count as yours while they stay in it (`Actor.get_last_displacer`, window `MapPieceData.displacement_credit_time`) | none |
| knock Motes loose (Jostle) | nothing: any enemy status push or pull of at least `MatchRules.jostle_min_distance`, a carry, or an abduction (`MinigameHost.play(game, source)`) already reports `Actor.displaced(source, distance)` | none |
| can't be jostled (Iron Will) | `StatusEffect.DISPLACEMENT_TAKEN` 0 in `stat_multipliers` | none |
| an always-on multiplier that survives death and cleanses (an item's fire rate) | `status_component.set_persistent_multipliers(source_id, {stat: mult})` / `remove_persistent_multipliers(source_id)` | a small script |
| faster (or slower) cooldowns | `StatusEffect.COOLDOWN_RATE` (`cooldown_rate`) in `stat_multipliers`, or persistent (items): 1.2 = 20% faster | none |
| an ability added to a slot at runtime and taken away again | `ability_controller.add_ability(ability, slot_id)` / `remove_ability(ability)` (the active-item slot works this way) | a small script |
| a shop item (stats, fire rate, an active ability) | not hero data: an `ItemData` in `resources/items/`, listed in the `ShopCatalog`. See `docs/ITEMS_AND_SHOPS.md` | none |
| react to Motes going into a Dreamer (a banking buff, a delivery trick) | `Dreamer.deposit_ticked(hero, value, delivered, index)` / `deposit_finished`; find one with `Dreamer.find_for(tree, team)` | a small script |
| a fake Mote that pops when grabbed (a lure) | `MoteDirector.spawn_mote(at)` then `mote.is_decoy = true` | a small script |
| an ally-targeted cast that still goes with no ally (dash anyway) | `AllyTargeting.optional` (`cast_ally` is null) | none |
| a meter on the ability bar (hunger, heat) | override `Ability.get_hud_meter()` (0-1) | a small script |
| a CC-only melee swing (no damage) | `MeleeAttackData` with no `damage` and an `on_hit_status` | none |
| a ring nobody can cross for a while (walking, dashes, launches, teleports, projectiles) | `ContainmentRing.spawn(context, center, radius, duration, members)`; strangers inside are pushed out; ends if a member dies. Area damage centred outside can still reach in | a small script (decides when) |
| a teleport / blink (through walls, but not through rings) | `actor.teleport_to(point)` (returns false if it would cross a `ContainmentRing`) | a small script |
| a skillshot that stops on the first actor of EITHER team (shield a friend, root a foe) | `ProjectileData.affects` BOTH + `ally_hit_status` (allies take no damage); `RangedAttackAbility._on_ally_hit` | none |
| click-target an ally or an enemy near the cursor | `AllyTargeting.accepts` (ALLIES / ENEMIES / BOTH) + `Ability.is_cast_target_ally()` to pick the status | a small script |
| link two actors for a while: a leash (never more than N px apart) and/or a healing share | `ActorLink.spawn(context, a, b, duration, source, leash, share, status)` | a small script (decides who) |
| a minigame that takes over one player's input for a few seconds | a `MinigameInstance` subclass + `MinigameData`, played by `MinigameHost.find_or_create(actor).play(...)`; see the airlock | a script per minigame |
| hard CC that can't be chained forever | automatic: **Resolve** (`GameRules.resolve_duration` / `resolve_cc_multiplier`) halves a stun, root or taunt that lands within 2 s of the last one ending. Carries, self-applied CC, walk-out-able pulls and formations are exempt; `StatusEffect.ignores_resolve` exempts any other | none |
| "can A see B?" (a stalker passive, a sight-gated autofire) | `CombatQueries.has_line_of_sight(from, to)`: walls on `GameRules.sight_mask`, and bushes (can't see in from outside; from inside you see out) | none |
| hide in bushes / reveal someone | bushes and grass patches hide their occupants automatically (`CombatQueries.is_hidden_from`, drawn per viewer by `VisualsComponent`), except from enemies within `GameRules.grass_reveal_radius` and for `grass_fire_reveal_time` after any ability use (`Bush.note_fired`); a `StatusEffect` with `reveals` shows them anyway | none |
| react to knocking someone into a wall (a wall slam, a grab-throw combo) | `target.movement_component.wall_impact(normal, impact_speed, source, wall)`: any knockback, push or pull into a hard wall or crystal at `GameRules.wall_impact_min_speed`+, once per knock (the Ranged Test hero's Charged Shot knocks back to try it); the `wall_impact` cue for the thud | a small script |
| "could my shot reach B?" (crystal: seen but not hittable) | `CombatQueries.shot_clear(from, to)`: nothing on `GameRules.wall_mask` between them | none |
| turn invisible to enemies (a cloak, a stalker's stealth) | a `StatusEffect` with `invisible` (pair it with `body_alpha` so the team sees a ghost): enemies' sight fails and they don't draw it, even in the open; `reveals` beats it. Test hero: Ranged Test (auto)'s Cloak on the item key | none, or a small script to decide when it ends (Pike's Obsession) |
| a timed buff that takes no item slot and ends on death (a shop's temporary item) | `BlackMarketItem` (a `StatusEffect`, or a `TempEffect` script) + `TempItems.ensure_on(hero).grant(item)`; F1 > Match > Map events > **Give temp item** works on Ranged Test | none, or a small `TempEffect` (see `docs/MAP_EVENTS.md`) |
| remove every harmful status from someone (a cleanse) | `hero.status_component.cleanse()` (ends stuns, slows, DoTs, vulnerability; `StatusEffect.cleansable = false` opts a drawback out) | none |
| widen how far loose Motes fly to a hero | `StatusEffect.MOTE_PICKUP_RADIUS` (`mote_pickup_radius`) in `stat_multipliers` (2.0 = twice `MoteData.magnet_radius`) | none |
| a status VFX only some players see (a mark only its target and caster see) | `StatusEffect.vfx_visible_to`: EVERYONE, TARGET_ALLIES, TARGET_ENEMIES, TARGET_AND_APPLIER, or LISTED + `status_component.set_vfx_viewers(id, actors)` | none (LISTED: a small script) |
| a drifty, slippery mover (velocity follows input slowly) | `HeroDefinition.traction` (< 1); `StatusEffect.TRACTION` in `stat_multipliers` for a slippery patch (marbles, ice). Both scale acceleration and friction; nobody else is affected | none |
| a knockback that hurts more into a wall (a wall slam) | `StatusEffect.slam_bonus_ratio` on the push status (0.5 = +50% of the hit at `GameRules.wall_slam_full_speed`, scaled by impact speed; `WallSlam`); `CombatEvents.wall_slammed` and the victim's `wall_slam` cue for VFX/sound | none |
| hits that build a meter on a target and burst when full (Madness) | `StackCounter.add(owner, key, target, max, decay_after, immunity)` returns true on the filling hit; per owner, so a summon keeps its own count | a small script |
| place a turret, a healing post, a drone, anything with health that can be shot | `DeployData` + `DeployAbility` with `deployable_script` = `TurretDeployable`, `AuraDeployable`, `MoteDrone` or your own `Deployable` (owner, health, lifetime, `max_per_owner`, removed on owner death, `cooldown_after_gone`) | none (a small `Deployable` for a new kind) |
| a zone you can blow up (oil) | `GroundZoneData.detonation` (an explosion `ProjectileData`), `GroundZone.detonate()`; `detonated_by_owner_status` sets it off when its owner stands in it with that status; `max_per_owner` caps them | none |
| a wind-up weapon (a minigun): fire rate and accuracy ramp while held | `RangedAttackData` Spin up group (`spin_up_time`, `spin_start_rate`, `spin_cold_spread_degrees`, `spin_down_time`); the bar shows the spin | none |
| a placed shield wall that eats N projectiles | `PlaceBarrierData` + `PlaceBarrierAbility` (a `PlacedBarrier`: charges, recharge, lifetime) | none |
| a turn slow, or a gun that gets more accurate | `StatusEffect.TURN_RATE` (aim turns at `GameRules.limited_turn_rate_degrees` x it) / `StatusEffect.SPREAD` in `stat_multipliers` | none |
| ram enemies you touch while moving fast (a drifting bike) | `StatusEffect` Contact ram group (`contact_radius`, `contact_damage`, `contact_min_speed`, `contact_rehit_time`, `contact_status`) on a self status | none |
| hold a key on a draining meter, optionally leaving a trail | `SelfStatusData.hold_meter_seconds` / `hold_meter_recharge_seconds` / `hold_meter_min`, `hold_trail_zone` + `hold_trail_spacing` (with `hold_to_keep`) | none |
| a leap that slams on landing | `LaunchData.landing_hit_shape` + `damage` + `on_hit_status` | none |
| a status on the shooter every shot (recoil, bailing off a bike) | `RangedAttackData.self_status_on_fire` | none |
| a silence that still lets them shoot | `StatusEffect.silence_spares_primary` (the classic silence blocks the primary too) | none |
| a mark with no effect until later that a cleanse removes (a sticky bomb) | `StatusEffect.harmful` | none |
| steal Motes from a carrier / collect Motes with a non-hero | `MoteCarrier.steal_from(victim, n)` (carry cap applies); `Mote.can_be_taken_by_agent(team)` / `take_by_agent(team)` | a small script (`MoteDrone` does the agent part) |
| an ultimate that charges faster (or slower) | `HeroDefinition.ult_charge_rate` (2 = twice as fast in a match) | none |
| a cone warning on the ground during a windup | `effects/feel/cone_telegraph.tscn` (`ConeTelegraphEffect`) on `<id>_windup`, attached | none |
| something new | extend `Ability` (or `MeleeAttackAbility` / `RangedAttackAbility`) | a small script |

`tools/heroes/ranged_test/` is a test-only hero that uses every ability row
above (pick it with **F1 → Play as → Ranged Test (test)**); the batch-2 rows
(spin-up gun, barrier, deployables, landing slam, hold meter, traction, turn
rate, contact ram, detonatable oil) are on **Ranged Test (gadgets)**, and
`tools/heroes/batch2_infra_test` checks each of them alone. The rules and
queries that aren't abilities (Resolve, line of sight, bushes and grass,
filtered VFX, the map obstacle types, wall slams) are covered by
`tools/heroes/shared_systems_test`. Short recipes follow.

**A gun.** `RangedAttackData`: `projectile` (a `ProjectileData`), `damage`
(per projectile), `fire_mode` AUTO (hold) or SEMI (click; early clicks within
`semi_input_buffer` still fire), `shots_per_second` (scaled by the FIRE_RATE
status multiplier), `projectiles_per_shot` + `spread_degrees` +
`spread_pattern` (RANDOM or EVEN fan), `muzzles` (offsets cycled per shot),
`magazine_size` (0 = infinite), `ammo_per_shot`, `reload_time` /
`reload_per_level`, `reload_style` FULL or PER_ROUND (one round per
`reload_time`, firing interrupts), `auto_reload_when_empty`, and
`falloff_start` / `falloff_end` / `falloff_min_multiplier`. R (`hero_reload`)
reloads the primary gun (or the first gun). Give the gun a short feel preset
(windup 0, small recovery, `ability_cancel_after` 0): each shot is a cast.

```
revolver.tres  fire_mode SEMI, shots_per_second 3, magazine_size 6,
			   reload_style PER_ROUND, reload_time 0.4,
			   muzzles [(50, -14), (50, 14)]      # alternating barrels
```

Other abilities reach the gun through the hero:

```gdscript
func _on_active_start() -> void:          # a dash that reloads on use
	super()
	var gun: RangedAttackAbility = (actor as Hero).get_ranged_ability()
	if gun != null:
		gun.reload_instantly()
```

**Hold to charge.** Tick `charge_enabled` in the ability's Charge group:
`charge_time_max`, `charge_min_to_fire` (+ `charge_below_min`: CANCEL or
FIRE_MINIMUM), `charge_auto_release_at_max`, `charge_move_speed_multiplier`,
`charge_can_cancel` (another key cancels, no cooldown spent),
`charge_perfect_window`. The cast waits in CHARGING until the key is released
(`hero.release_slot()`; AI calls the same). Charged numbers are value pairs:

```
values/damage_full = 120 + 1.4 W     # "damage" is the main damage field
```
```gdscript
var dmg := data.get_charged_value(&"damage", get_stats(), get_charge_ratio())
if was_perfect_release(): ...
```

A `RangedAttackAbility` does this by itself: on a perfect release it
multiplies by `values/perfect_damage_multiplier`, fires `perfect_projectile`
if set (a thicker tracer), and adds a `<id>_perfect` cue. Map
`<id>_charge_start` to `effects/feel/telegraph_line.tscn` (attached to the
actor) for a live aim line that brightens with the charge and strobes in the
perfect window.

**Compel.** A `StatusEffect` with `compel_enabled`,
`compel_speed_multiplier` (of the target's own speed), `compel_stop_distance`
and `compel_overrides_input`. The target walks to the applier's current
position every tick. Stuns and roots stop it, knockbacks play out first, and
it ends if the applier dies. Put it on any `on_hit_status`.

**Stat modifiers + notifications (a mark).** A `StatusEffect` with
`stat_modifiers = [StatModifier(health, percent -0.2)]`,
`stack_per_applier = true` (each applier's copy is separate) and
`attached_vfx = scenes/combat/overhead_marker.tscn` (the overhead marker).
Losing max HP clamps current HP; the debuff ending never hands HP back. The
applier hears about it:

```gdscript
func _ready() -> void:
	super()
	actor.combat_hooks.status_target_died.connect(func(id, _target, _info):
		if id == &"my_mark":
			reset_cooldown())            # also: reduce_cooldown(seconds)
```

**Rhythm.** A `RhythmPhrase` (notes, bpm, lead-in, good/perfect windows,
input action, note pitches) is played by the actor's `RhythmPerformer`:

```gdscript
var performer := RhythmPerformer.find_or_create(actor)
performer.note_graded.connect(_on_note)   # (index, RhythmResults.Grade)
performer.play(data.phrase, ability_id)   # cues <id>_note_perfect/_good/_miss
```

While it plays, the player's presses of `input_action` go to
`press_note()` instead of the slot (AI calls `press_note()` itself). The
ring is drawn on the actor. A stun cancels it (graded notes still count).

**Line of sight and bushes.** `CombatQueries.has_line_of_sight(from, to)`
asks whether `from` can see `to`. Full walls block (`GameRules.sight_mask`;
you see over low cover and ledges). Bushes block one way: nobody outside a
bush sees anyone inside it, while those inside see out and see each other. A
status with `reveals` ignores bushes. The local player's screen follows the
same rule with team-shared vision: an enemy in a bush isn't drawn (body,
health bar, minimap dot) unless you or a teammate shares the bush or it's
revealed. Hidden enemies can still be hit; only drawing and sight-gated
abilities (e.g. Jose's Weapons Free) respect it. A status with `invisible`
hides its actor from every enemy the same way, in the open too, until a
`reveals` status shows it (Pike's Obsession). F1 → Tools → Sight lines
draws the player's lines to nearby enemies.

**Resolve.** After someone else's stun, root or taunt ends on an actor, it
gets `GameRules.resolve_status` for `resolve_duration` (2 s); new hard CC on it
meanwhile lasts `resolve_cc_multiplier` (50%) as long. No hero code is
involved: `StatusEffect.is_hard_cc()` decides what counts.

**Minigames.** A `MinigameInstance` runs on physics ticks for one actor:
`MinigameHost.find_or_create(actor).play(game)` puts the data's
`occupied_status` on the actor (default: silenced only, so a carry or a
cruise can still move the body), routes that
player's WASD to it (PlayerHeroInput; tests and network clients call
`host.set_input(move)`), and opens a `MinigameView` overlay for the local
viewer only, with a live inset of the real map. A tick with no input uses the
game's `bot_input()` (what an AI victim does). `finish(result)` never ends it
before `min_duration`; `max_duration` ends it with `{"timeout": true}`. Key
presses reach `_on_press(action)`, so a rhythm phrase can run inside one
later. The airlock (`AirlockMinigame`, `resources/minigames/airlock.tres`) is
the first: a short maze. Each run picks one of the data's `MazeLayout`s (a
list of wall rects) at random; the player slides along walls and holds in
the door for `door_hold` to get out. A perfect run takes about 1.5 s, the
ship ejects them at 4 s, and `bot_input()` follows the shortest path at
`bot_speed_scale` (75%), so AI victims get out in about 2 s. Add a maze by
adding a `MazeLayout` to the list; `airlock_test` checks every layout is
solvable in 1.4 - 1.7 s. Practise it from F1 → Tools → Airlock practice.

**Shields.** `StatusEffect.shield_amount` (a ScalingValue from the
applier's stats, times the application's strength) soaks damage after
resistances, before health; the status ends when it's used up. The health
bar draws it, and the meter shows "Shielding done" / "Shielded".

**A zone that follows you.** `ZoneAbilityData` with `zone_duration` and a
`GroundZoneData` zone: `shape` ARC, `follow_owner`, `face_aim`, `affects`
(ENEMIES / ALLIES / BOTH; damage only ever hits enemies),
`status_while_inside` (applied on entry and every tick, removed on exit),
`ends_if_owner_dies`, `max_duration`. The zone is owned by the cast: a stun
ends it unless `outlives_cast`. For custom per-target logic, spawn it from
any ability and listen:

```gdscript
var zone := spawn_owned_zone(data.zone)   # ends with this cast
zone.target_entered.connect(_on_enter)    # also target_ticked, target_exited
```

**Ramping zones.** Give a `GroundZoneData` a `ramp_per_tick` and each damage
tick on a target hits `1 + ramp_per_tick x (ticks it already took)` times
harder, up to `ramp_max`, so with 1 s ticks 0.5 is "+50% per second inside".
The ramp belongs to (owner, `ramp_key`, target): every zone of that owner
with the same key shares it, so an aura and the clouds its hero throws feed
one ramp. A target outside all of them for `ramp_reset_after` seconds starts
over. `ramp_starts_full` puts everyone inside at `ramp_max` at once. Scripts
push it directly: `ZoneRamp.raise_steps(owner, key, target, steps)` (a head
start that never lowers it) and `ZoneRamp.reset(...)` (a cleanse).
`draw_z_index` lifts a zone's drawing (and its outline) above other ground
zones, still under characters.

**Avery**, slot by slot:

| Slot | Data | Script |
|---|---|---|
| primary | `sunblade_slash.tres`: 3 `combo_steps` (light, light, finisher) + `swing_projectile` = the crescent | generic `MeleeAttackAbility` |
| ability_1 | `searing_cut.tres` (`SearingCutData`: heal per target, falloff, cap) | `searing_cut_ability.gd`: heals via the `hit_dealt` hook |
| movement | `solar_charge.tres` (`ChargeData` + `trail_zone`) | generic `ChargeAbility` |
| cc | `sunbrand.tres`: one-shot `RangedAttackData` (750 px flare); `on_hit_status` = `avery_sunbrand_status.tres` (40% slow + a true-damage burn) | generic `RangedAttackAbility` |
| ultimate | `phoenix_rebirth.tres` (`PhoenixRebirthData`): the revive, plus `blaze_status` / `blaze_zone` for the alive use | `phoenix_rebirth_ability.gd`: cancels death via `about_to_die`; pressing the key while alive casts the Blaze (speed, regen, a `follow_owner` burning aura) |

Her burn (`avery_burn.tres`) is TRUE damage scaling with Magic, so running away
doesn't shake it. Searing Cut has no knockback, so it never pushes a target out
of her reach. Both uses of the ultimate share one cooldown (or match charge):
Blazing means no revive until it returns.

**Named numbers.** Any extra number a script needs goes in the ability's
`values` dictionary as a `ScalingValue`, and the script reads it with
`data.get_value(&"name", get_stats())`. Rook's lifesteal is `values/lifesteal`.
Named values show up automatically in the debug panel, stat inspector and CSV.

### 4. Write an ability script (only if needed)

The template's `<name>_basic_attack.gd` lists every hook. Rook's is one
function:

```gdscript
extends MeleeAttackAbility

func _on_target_hit(info: DamageInfo, _hurtbox: HurtboxComponent) -> void:
	var share := data.get_value(&"lifesteal", get_stats())
	actor.health_component.heal(info.final_amount * share, actor, &"lifesteal")
```

Hooks available to ability scripts:

* **Cast phases** (from `Ability`): `_activate(target) -> String` (validate;
  return "" or a failure reason), `_on_windup_start`, `_on_active_start`,
  `_on_active_tick(delta)`, `_on_active_end`, `_on_recovery_start`,
  `_on_cast_end(interrupted)`. Timings come from the feel preset; the base
  class handles the attack slow, lunge, cancel windows, buffering and stuns.
* **Melee** (from `MeleeAttackAbility`): `_build_hit(info, hurtbox)` to change
  a hit before it lands, `_on_target_hit(info, hurtbox)` after.
* **Ranged** (from `RangedAttackAbility`): the same two hooks per projectile
  hit, plus `_shot_damage()`, the signals `ammo_changed`, `reload_started`,
  `reload_finished`, `reload_cancelled`, and the calls `get_ammo()`,
  `start_reload()`, `cancel_reload()`, `reload_instantly()`, `add_ammo(n)`.
* **Charge** (any ability with `charge_enabled`): `_on_charge_start()`,
  `_on_charge_released(ratio, perfect)`; `get_charge_ratio()`,
  `was_perfect_release()`, `is_in_perfect_window()`.
* **Cooldowns**: `reset_cooldown()`, `reduce_cooldown(seconds)`.
* **Hero-wide events**: `actor.combat_hooks` → `hit_dealt`, `damage_taken`,
  `kill`, `death`, `level_up`, `about_to_die` (cancellable), `heal_done`,
  and for statuses this hero applied: `status_target_died`,
  `status_expired`, `status_removed(id, target, reason)`.
  Passives live here. Avery's heal-on-hit filters `hit_dealt` to its own
  attack id; her revive calls `event.cancel(hp)` on `about_to_die`.

Rules of thumb:

* No numbers in scripts. If a designer might tweak it, it's a field in the
  data (or a named value).
* Don't use `class_name` in hero scripts that were copied from the template:
  every hero gets its own copy, and names must be unique. (Avery's scripts
  don't need one; her data classes do, so they can be created in the
  inspector.)
* Build every hit as a `DamageInfo` with a `label` (it's what the damage
  meter shows) and hand it to `hurtbox.take_hit()`. Hits go through
  resistances, hooks and the meter automatically.

### 5. Tune the feel

Copy an existing `FeelProfile` (Avery's is a good start for any melee hero)
and adjust the presets. **Simulation** fields change gameplay (windup, active,
recovery, lunge, slow, cancel windows); **Cosmetic** fields only change what
you see and hear (lean, hitstop, shake, nudge, flash, trail, sounds) and are
safe to push hard. Point each ability's `feel_preset` at a preset name.

### 6. Visuals and sound

`visual_profile` / `audio_profile` on the definition map cue names to
effects and sounds (see `docs/VISUALS_AND_AUDIO.md`). Abilities emit
`<id>_windup`, `<id>_active`, `<id>_recovery`, `<id>_hit` and a few
ability-specific cues: guns add `<id>_fire`, `<id>_empty`,
`<id>_reload_start` / `_reload_end`; charges add `<id>_charge_start` /
`_charge_full` / `_charge_release` (full list in VISUALS_AND_AUDIO.md). Swing whoosh, impact and fire layers come from the
FeelProfile, not the cue profiles. Give every hero an `audio_profile` (sounds in
`audio/sfx/<name>/`) and run `tools/heroes/audio_coverage.gd` from its test.

### 7. Test it

* Press **F1 → Hero → "Play as"** to swap the player to your hero in any map.
* **Training Grounds** (F3) has resistance dummies, a pack for multi-target
  abilities, a dummy that fights back, a killable one, and an ally on your
  team (south-west) that patrols and reads out its buffs and shield, for
  ally-targeted abilities like Melody's Wind-Up Key. A dummy becomes an ally
  with `team`, `patrol_offset` and `buff_readout`.
* **F1** edits any number live (Reset restores the .tres), **F2** shows every
  ability number at the current level, **F4** is the damage meter.
* **Tools → Validate Heroes** and **Tools → Export Balance CSV** include your
  hero automatically.

---

## Hero batch 2 (Biker, Horace, Mochi, Computer, Catgirl, Rocco)

Built from `MOTE GARDEN: Hero Batch 2`. The shared pieces they needed are the
rows above from "a drifty, slippery mover" down; `tools/heroes/batch2_infra_test`
covers them alone, Ranged Test (gadgets) plays them, each hero has its own
`<name>_test`, and `tools/ai/batch2_bot_test` has bots play all six.
Placeholder bodies are `sprites/heroes/<name>.svg` (the sprite slot: a
top-down badge that never turns with the aim).

### What the Biker took

A TEMPO (title: The Hellrider). Always on the bike: 640 speed, `traction` 0.5.
Only the ultimate's bail-out needed anything new, and that was data too.

| Slot | Data | Script |
|---|---|---|
| primary | `hellfire_smg.tres`: AUTO 10/s, spin group used for spread only (5° → 12° over 1.5 s) | generic `RangedAttackAbility` |
| ability_1 (RMB) | `burnout.tres`: `SelfStatusData` hold with a 3 s meter (5 s refill), +40% speed status `burnout`, `hold_trail_zone` = a 2 s fire trail (14 burn/s) | generic `SelfStatusAbility` |
| cc (E) | `hellfire_oil.tres`: lobbed flask → `biker_oil_pool` (90 px, 6 s, 35% slow, burn, `max_per_owner` 2, `detonation` = 150 px blast + 3 s hellburn, `detonated_by_owner_status` = `burnout`) | generic `RangedAttackAbility` |
| movement (Shift) | `brake.tres`: `SelfStatusData` hold; the status has `traction` x4 and a contact ram (40 dmg, 1 s per target, slam-capable 180 px knock) | generic `SelfStatusAbility` |
| ultimate | `hellbound.tres`: 0.5 s rev (feel), a lobbed 900 px bike (1.5 s flight, a projectile so nothing can touch it), 220 px blast; `self_status_on_fire` = `biker_bailed` | generic `RangedAttackAbility` |

Judgment call (Hellbound): she bails out at the launch point: 1.6 s at 45%
speed with extra grip, silenced for abilities but free to shoot
(`silence_spares_primary`), then the new bike arrives (the status ends).
Alternative if that feels bad: she rides it (a `LaunchData` leap with the
landing slam, untargetable `self_status`) and lands in the blast.

### What Horace took

A slow gun CARRY (title: The Knight with the Minigun). No scripts at all.

| Slot | Data | Script |
|---|---|---|
| primary | `minigun.tres`: 20/s at full spin, `spin_start_rate` 0.15 (3/s cold), spread 12° → 4° over 2 s | generic `RangedAttackAbility` |
| ability_1 | `shield_wall.tres`: `PlaceBarrierData`, 3 charges, 3 s per charge, 4 s, 10 s cooldown | shared `PlaceBarrierAbility` |
| movement | `steed.tres`: `ChargeData` 700 px ride (no shooting: the dash is a cast), 25 s | generic `ChargeAbility` |
| cc | `overdrive.tres`: `SelfStatusData`, 6 s: damage 1.3, fire_rate 1.25, spread 0.5, turn_rate 0.5 | generic `SelfStatusAbility` |
| ultimate | `dragonfire.tres`: a lobbed breath onto the cursor leaving a 220 px, 5 s fire zone (~40/s + burn) that never moves | generic `RangedAttackAbility` |

### What Mochi took

A burst mage CARRY (title: The Sweet Thing).

| Slot | Data | Script |
|---|---|---|
| primary | `whisper_bolts.tres`: AUTO magic bolts; `values/madness_hits` 5, `madness_decay` 3, `madness_immunity` 1.5, `madness_burst` (40 + 4/lvl + 40% Magic ≈ 120 at L10) | `madness_bolts.gd`: `StackCounter` per shooter, the burst, mirrors to the tentacle |
| ability_1 | `mercy.tres`: 60 magic, `values/missing_health_bonus` 1.0 | `mercy_bolt.gd`: x(1 + bonus x missing health), mirrors to the tentacle |
| movement | `slip.tres`: 350 px roll, 0.3 s i-frames | generic `ChargeAbility` |
| cc | `tentacle.tres`: `DeployData` (8 s, max 1, 12 s) | `tentacle_ability.gd` (place, or swap onto it once) + `tentacle.gd` (a `Deployable` that fires her shots at her cursor with its own counter) |
| ultimate | `cone_stare.tres` (`MochiGazeData`): 300 px 90° cone, 0.6 s telegraphed windup (`cone_telegraph`), 1.5 s stun, `shred_status` -30% Magic Resist 5 s | `cone_stare.gd`: adds the shred |

### What the Computer took

A deployer FLEX (title: The Sentient Beige Box). No scripts at all.

| Slot | Data | Script |
|---|---|---|
| primary | `grenades.tres`: slow grenades, `explode_on_hit` + `explode_on_expire` (1.5 s fuse), 80 px | generic `RangedAttackAbility` |
| ability_1 | `gun_turret.tres`: `TurretDeployable`, 300 HP, 12 s, 4 shots/s in 550 px, 6 s | shared `DeployAbility` |
| cc | `repair_turret.tres`: `AuraDeployable`, 200 HP, 10 s, ~20 heal/s in 200 px, 14 s | shared `DeployAbility` |
| movement | `mote_drone.tres`: `MoteDrone`, 100 HP, `block_while_capped`, `cooldown_after_gone` (20 s after it dies) | shared `DeployAbility` |
| ultimate | `emp.tres`: CC-only 300 px circle, 3 s silence that spares basic fire | generic `MeleeAttackAbility` |

### What Catgirl took

A TEMPO thief (title: The Broke Thief). 620 speed, `ult_charge_rate` 2.

| Slot | Data | Script |
|---|---|---|
| primary | `smg.tres`: 12/s, 14° spread, falloff 250 → 500 px | generic `RangedAttackAbility` |
| movement | `scamper.tres`: 200 px roll, `max_charges` 4, 3 s each | generic `ChargeAbility` |
| ability_1 | `swipe.tres`: 130 px claw, `values/steal_count` 5 | `swipe.gd`: `MoteCarrier.steal_from` |
| cc | `marbles.tres`: lobbed bag → a 100 px, 4 s zone: 40% slow, `traction` 0.4 | generic `RangedAttackAbility` |
| ultimate | `sticky_bomb.tres`: the bomb is a `harmful` 2 s status everyone sees; `values/bomb_damage` (~350 at L10) | `sticky_bomb.gd`: detonates on `status_expired` (a cleanse or death defuses it) |

### What Rocco took

A TEMPO brawler (title: The Heel). No scripts: his passive is that every
knockback status has `slam_bonus_ratio` 0.5.

| Slot | Data | Script |
|---|---|---|
| primary | `jab_combo.tres`: 3 steps of 18, lunging presets, a small slam-capable push | generic `MeleeAttackAbility` |
| ability_1 | `haymaker.tres`: charged `ChargeData` (1.2 s), 150 → 450 px, 120 → 280 damage, 400 px knock | generic `ChargeAbility` |
| movement | `jumping_slam.tres`: `LaunchData` 450 px, `landing_hit_shape` 170 px, 40% slow 1 s | shared `LaunchAbility` |
| cc | `cheap_shot.tres`: 50 damage, 140 px knock, `lifesteal` 0.4 | generic `MeleeAttackAbility` |
| ultimate | `main_event.tres`: 1500 px `ChargeData`, 300 damage, 750 px knock | generic `ChargeAbility` |

## What Sam took

A TEMPO disabler (title: The Visitor). Tools → New Hero from Template →
"Sam", basic attack deleted, then:

| Slot | Data | Script |
|---|---|---|
| primary | `hello.tres`: `RangedAttackData`, AUTO 3/s, magic, 5 + 0.5/lvl + 12% Magic; `sam_hello` projectile with `wall_bounces` 1 | none (`RangedAttackAbility`) |
| ability_1 | `hug.tres`: damage-less one-shot; `sam_hug_hand` projectile (`affects` BOTH, 650 px, `ally_hit_status` = 120 + 50% Magic shield, `vfx/hug_arm.tscn` draws the arm); `on_hit_status` = 1 s root | none (`RangedAttackAbility`) |
| movement | `tractor_beam.tres`: `RangedAttackData`, a wide (48 px) 720 px skillshot (`sam_beam_ray.tres`, `affects` BOTH); enemies get `sam_beam_enemy` (pull `TOWARD_SOURCE` + 0.5 s stun), allies `sam_beam_ally` (pull + untargetable) | generic `RangedAttackAbility` |
| cc | `friendship_bracelet.tres`: damage-less one-shot, `sam_bracelet` (`affects` BOTH); `values/chain_range` 400, `leash_distance` 300, `heal_share` 0.5, `link_duration` 4 | `bracelet_ability.gd`: chains to the nearest teammate of whoever it hit, spawns an `ActorLink` |
| ultimate | `close_encounter.tres` (`SamEncounterData`): `minigame` = the airlock, `abducted_status` (untargetable, `damage_taken` x0, `vfx/ufo.tscn`), `daze_status` 0.3 s; `values/telegraph` 0.4, `beam_radius` 90, `ufo_speed` 350 | `close_encounter_ability.gd`: telegraph, `MinigameHost`, `set_cruise` toward Sam's cursor, `lock_abilities` (primary allowed), the drop |

The UFO (a status `attached_vfx`) is seen by everyone: the ship, its ground
shadow and the victim's name. If Sam dies or is removed, the victim drops at
once. Shared piece changed for him: a `RangedAttackData` may have no
`damage` when its hit applies a status (`on_hit_status` or the projectile's
`ally_hit_status`). `tools/heroes/airlock_test` covers the maze alone and
`tools/heroes/sam_test` covers the kit.

## What Pike took

A TEMPO duelist (title: The Beloved's Shadow). Tools → New Hero from
Template → "Pike", basic attack deleted, then:

| Slot | Data | Script |
|---|---|---|
| passive | `obsession.tres` (`PikeObsessionData`): `unseen_status` (`invisible`, +20% speed, 0.4 alpha), `ambush_status` (0.75 s root), `values/ambush_cooldown` 6, `ambush_damage_multiplier` 2, `restealth_delay` 1.5, `keeps_stealth_slots` [movement] | `obsession.gd`: breaking the Beloved's line of sight (`CombatQueries`) hides her until she attacks or casts; the knife out of hiding is the ambush |
| primary | `juggled_knives.tres`: `RangedAttackData`, AUTO 4/s, 5 rounds, REGEN 0.5 s, 0.4 x Weapon, `values/max_hp_ratio` 0.005, `on_hit_status` = `pike_bleed.tres` (STACK, 8 stacks, 4 s, TRUE damage every 0.5 s: 1 + 8% Weapon per stack) | `juggled_knives.gd`: the max-HP part, the ambush knife; `vfx/knife_orbit.gd` shows the ammo |
| ability_1 | `beloved.tres`: one-shot heart, `on_hit_status` = the Beloved mark (`stack_per_applier`, `ends_if_applier_dies`, `vfx/beloved_heart.tscn`) | `beloved_ability.gd`: one Beloved at a time, `get_beloved()` |
| movement | `there_you_are.tres`: `ChargeData` 300 px (no Beloved), `values/teleport_range` 900, `behind_offset` | `there_you_are_ability.gd`: `teleport_to` behind the Beloved |
| cc | `crazed_devotion.tres`: `ChargeData` bash dash (550 px, 2200 speed, 80 px circle); `values/execute_threshold` 0.15, `execute_per_bleed_stack` 0.02 | `crazed_devotion_ability.gd`: after the cut, executes (TRUE) anyone under the threshold, raised by their Bleeding stacks; a kill resets the cooldown |
| ultimate | `only_us.tres`: `values/ring_radius` 450, `ring_duration` 4, `max_distance` 600 | `only_us_ability.gd`: a `ContainmentRing` around both |

The heart draws big for the Beloved and Pike, small for the Beloved's allies
and not at all for anyone else (`LocalView`); it beats faster as she gets
closer and glows within her teleport range. Shared pieces added for her:
`ContainmentRing` on the new BARRIERS physics layer (every character masks
it; it's in `GameRules.wall_mask`) and `Actor.teleport_to` (map teleporters
and Safety Net's pull use it). `tools/heroes/ranged_infra_test` covers the
ring alone and `tools/heroes/pike_test` covers the kit.

## What Butler took

A two-form TANK (title: The Composed). Tools → New Hero from Template →
"Butler", basic attack deleted, then:

| Slot | Composed (the definition) | Starving (`hunger.tres` `starving_abilities`) |
|---|---|---|
| primary | `cane.tres`: 3-step `MeleeAttackData` combo | `claws.tres`: faster combo, `lifesteal` 0.25 |
| ability_1 | `vampiric_cloak.tres`: `BlockerData`, HP 400 → 1100, -30% speed raised, +20% speed flourish | `bite.tres`: melee lunge, 0.5 s stun, `lifesteal` 1.0, `values/hunger_restored` 35 (`bite_ability.gd` feeds the passive) |
| movement | `at_your_service.tres`: `ChargeData` + optional `AllyTargeting`, shield `on_hit_status` (`at_your_service_ability.gd`: short dash with no ally, shield on arrival) | `pounce.tres`: `ChargeData` (`pounce_ability.gd`: aims at the enemy nearest the cursor) |
| cc | `polite_refusal.tres`: melee sweep, 250 px knockback | `hiss.tres`: CC-only melee cone, 40% slow + 1 s silence |
| ultimate | `dinner_is_served.tres`: 900 px `ChargeData`, untargetable `dash_status`, draining bash (`dinner_is_served_ability.gd` fills Hunger first) | same |
| passive | `hunger.tres` (`ButlerHungerData`) | `hunger.gd`: the meter, `swap_slot` / `restore_slot`, the tie-straightening root and armor |

The Hunger bar over his head (`vfx/hunger_bar.gd`) is cosmetic and drawn for
everyone. Shared pieces added for him: `AbilityController.swap_slot` /
`restore_slot`, `FrontalBlocker` + `BlockerData` / `BlockerAbility`,
`AbilityData.lifesteal`, `ChargeData.dash_status`, `AllyTargeting.optional`,
`Ability.get_hud_meter`, and CC-only melee. `tools/heroes/support_infra_test`
covers them alone and `tools/heroes/butler_test` covers the kit.

## What Tilly took

A movement SUPPORT, role Flex (title: The Crash Test Acrobat). Tools → New
Hero from Template → "Tilly", basic attack deleted, then:

| Slot | Data | Script |
|---|---|---|
| passive | `crumple_zone.tres` (`TillyCrumpleZoneData`): an always-on status with `displacement_taken` 0.6, and a +25% speed status on landing | `crumple_zone.gd` (`PassiveAbility`): keeps the status on, applies the other on `Actor.landed` |
| primary | `bouncy_balls.tres`: `RangedAttackData`, AUTO 2.5/s, big (26 px) long-flying (1100 px) balls, `wall_bounces` 2 | generic `RangedAttackAbility` |
| ability_1 | `trampoline.tres`: `PlacePadData`, 700 px, 10 s / 4 launches, `max_charges` 2, 11 s recharge, enemies get a 250 px bounce back | shared `PlacePadAbility` |
| movement | `cartwheel.tres`: `ChargeData`, 350 px | `cartwheel_ability.gd`: ending on her own pad resets the cooldown (the pad launches her) |
| cc | `all_eyes_on_me.tres`: `SelfStatusData` (40% less damage, 1.25 s), `count_radius` 300, `on_hit_status` = a compel | `all_eyes_ability.gd`: puts the compel on every enemy counted |
| ultimate | `safety_net.tres`: `ZoneAbilityData`, `instant`; a 600 px ALLIES zone with the death intercept (15%, beside her, 1 s untargetable) | generic `ZoneAbility` |

Shared pieces added for her: placed `JumpPad`s (`owner_actor`, `enemy_status`,
`lifetime`, `max_launches`, `wait_for_footing`) with `PlacePadData` /
`PlacePadAbility`, `AbilityData.max_charges`, the `GroundZoneData` death
intercept, `ZoneAbilityData.instant`, `ProjectileData.wall_bounces` and
`StatusEffect.DISPLACEMENT_TAKEN`. `tools/heroes/support_infra_test` covers
the pieces alone and `tools/heroes/tilly_test` covers the kit.

## What Nimbus took

A low-mobility gun CARRY (title: The Gentleman Spy). Tools → New Hero from
Template → "Nimbus", basic attack deleted, then:

| Slot | Data | Script |
|---|---|---|
| passive | `steady_hand.tres`: `values/bonus_per_stack` 0.1, `max_stacks` 4, `still_speed` | `steady_hand.gd` (`PassiveAbility`): a stack per second standing still, pips, `consume()` |
| primary | `umbrella_rifle.tres`: `RangedAttackData`, SEMI, 1.1/s, 5 rounds, 1.6 x Weapon, pierce 1, `values/crit_multiplier` 1.75 | `umbrella_rifle.gd`: Steady Hand bonus, `grant_crit()`, crits + free pierce against his Overcast |
| ability_1 | `scope.tres`: `SelfStatusData` with `hold_to_keep`; the status has -40% speed, `camera_look_ahead` 500 and the `AimLaser` | shared `SelfStatusAbility` |
| movement | `descend.tres`: `LaunchData`, 1100 px, 1.6 s, `steer_speed` 450 | shared `LaunchAbility` |
| cc | `parry.tres`: `SelfStatusData`, a 0.35 s `parries` status whose melee stun is 0.5 s; `values/cooldown_refund` 0.5 | `parry_ability.gd`: refund + next-shot crit on `parried` |
| ultimate | `overcast.tres` (`ZoneAbilityData`, `ability_range` 3600): a 500 px 6 s cloud whose `status_while_inside` reveals and slows 15% | `overcast_ability.gd`: places the cloud on the cursor (instant) |

Crits are Nimbus's own rule (his rifle script), tagged `crit` on the hit.
Shared pieces added for him: `StatusEffect` parry and `camera_look_ahead`,
`SelfStatusData.hold_to_keep` (+ `Ability.is_held` / `release_hold`),
`LaunchData`/`LaunchAbility` and `Actor.retarget_launch`, `AimLaser`, and
`Projectile.free_pierce`. `tools/heroes/ranged_infra_test` covers the pieces
alone and `tools/heroes/nimbus_test` covers the kit.

## What Hazmat took

A slow zone TANK (title: The Contaminant). Tools → New Hero from Template →
"Hazmat", basic attack deleted, then:

| Slot | Data | Script |
|---|---|---|
| passive | `contamination.tres` (`ZoneAbilityData`): `hazmat_aura.tres`, a 220 px `follow_owner` circle, 1 s ticks of 10 + 20% Magic, ramp 0.5 per tick up to x3, reset after 1 s, `ramp_key` contamination | `contamination.gd` (`PassiveAbility`): keeps the aura up, `suspend(seconds)`, `get_ramp_key()` |
| primary | `sprayer.tres`: `RangedAttackData`, AUTO, 5 droplets in a 30° cone, 350 px; `values/ramp_head_start` | `sprayer_ability.gd`: a hit raises the target's Contamination ramp one step |
| ability_1 | `canister.tres`: a one-shot gun firing `hazmat_canister.tres` (`lobbed`, explodes on landing, `explosion_zone` = a 250 px 6 s cloud on the same ramp) | generic `RangedAttackAbility` |
| movement | `seal_suit.tres`: `ChargeData`, 400 px, a shove (`hit_shape` + knockback `on_hit_status`), `self_status` = 30% less damage for 2 s | generic `ChargeAbility` |
| cc | `quarantine.tres`: one-shot gun (500 px) whose `on_hit_status` pulls to him (`TOWARD_SOURCE`) and stuns 0.4 s | generic `RangedAttackAbility` |
| ultimate | `containment_breach.tres` (`ZoneAbilityData`): a 500 px `follow_owner` zone, `ramp_starts_full`, `outlives_cast`, `leaves_zone` = an 8 s residue | `containment_breach_ability.gd`: suspends the aura, spawns the breach (instant, he keeps fighting) |

Shared pieces added for him: the `GroundZoneData` Ramp group and `ZoneRamp`,
`GroundZoneData.leaves_zone` and `draw_z_index`, `ProjectileData.lobbed` and
`explosion_zone`. The Ranged Test hero's cone ramps (+10% per tick up to
x1.5); `tools/heroes/ranged_infra_test` covers the pieces alone and
`tools/heroes/hazmat_test` covers the kit.

## What Cpt. Yellow took

A dive TANK (title: Yellow Army): a small commander riding a swarm of yellow
bugs. Everything is generic; the only hero-specific code is placeholder VFX.

| Slot | Data | Script |
|---|---|---|
| primary | `stinger_volley.tres`: `RangedAttackData`, AUTO, 4 bugs per shot in a 16° cone, short range, no magazine | generic `RangedAttackAbility` |
| ability_1 (RMB) | `swarm_ride.tres` (`RideData`): hold to ride (`ride_speed`, `turn_rate_degrees`, `charge_time_max` 3 s), `landing_telegraph` 0.25 s, landing `hit_shape` + `damage` + knockback `on_hit_status` | shared `RideAbility` |
| movement (Shift) | `rally.tres` (`SelfStatusData`): `yellow_rally_shield.tres` (2 s shield), `strength_per_enemy` 0.4 up to 5 enemies in `count_radius` | shared `SelfStatusAbility` |
| cc (E) | `sting.tres`: one-shot `RangedAttackData`; `on_hit_status` = `yellow_sting_slow.tres` (a latched bug, -40% speed) | generic `RangedAttackAbility` |
| ultimate (Q) | `charge.tres`: `ChargeData`, `telegraph_time` 0.5, a wide LINE bash whose `on_hit_status` stuns and carries (`yellow_wave_carry.tres`), `end_on_hit_status_on_arrival`, `arrival_status` (`yellow_wave_drop.tres`) | generic `ChargeAbility` |

Shared pieces added for him: `MovementComponent.set_cruise` (a steered
drive), `StatusEffect` carry (`carry_enabled`, `carry_max_offset`,
`carry_max_speed`), `RideData`/`RideAbility`, `SelfStatusData`/
`SelfStatusAbility`, `ChargeData.telegraph_time` / arrival release /
`arrival_status`, and `effects/feel/area_telegraph.tscn` (a warning circle
for any area that lands around its caster).
`tools/heroes/cpt_yellow_test` covers the kit.

## What Melody took

A support whose tuba drives everything. Built on the generic support
systems (rhythm, shields, explosions, fades, ally targeting, formations):

| Slot | Data | Script |
|---|---|---|
| passive | `the_key.tres`: max turns, encore threshold, unwind timings, encore bonus | `melody_key.gd` (`PassiveAbility`): turns, the encore rule, unwinding, pips, the key on her back |
| primary | `heavy_notes.tres` (`MelodyHeavyNotesData`): AUTO, no ammo, exploding note; `chord_projectile` splits | `heavy_notes_ability.gd`: fires the Chord on an encore |
| ability_1 | `wind_up_key.tres`: `ally_targeting`, `tether_range`, charge, a fading `on_hit_status` | `wind_up_key_ability.gd`: strength from the charge, Master Key encore |
| movement | `wind_up_dash.tres`: charged `ChargeData` with `min_distance`, bash, boop status | `wind_up_dash_ability.gd`: the Pre-wound ricochet encore only |
| cc | `performance.tres` (`MelodyPerformanceData`): a 4-note `RhythmPhrase`, a shield status | `performance_ability.gd`: winds the key, pulses shields |
| ultimate | `grand_march.tres` (`MelodyGrandMarchData`): 8-note phrase, follow-trail compel, speed and shield statuses | `grand_march_ability.gd`: gathers the line, extends on perfects |

The encore rule lives in one place: each ability asks the passive
`key.consume_encore(self)` when it commits (a cast, or a charge's release)
and gets a strength back, or -1. Encore numbers use `encore_value()`, the
BASE of a named value times that strength, so they don't grow with Magic.
The passive sits in the optional `passive` slot (GameRules), so its numbers
show in F1/F2/CSV like any ability's.

## What Cosmo took

A back-loaded mage CARRY. Tools → New Hero from Template → "Cosmo", basic
attack deleted, then:

| Slot | Data | Script |
|---|---|---|
| passive | `waxing_moon.tres` (`CosmoWaxingMoonData`): `base_moons` 4, `moon_breakpoints` [3,5,7,10] (one more moon each), `regen_interval_by_moons`, orbit radius/speed | `waxing_moon.gd` (`PassiveAbility`): the moon count, `set_max_ammo` / `set_regen_interval` on the gun, the orbit, `moon_waxed` |
| primary | `moonshot.tres`: `RangedAttackData`, SEMI at 10/s, REGEN reload, MAGIC; the moon projectile pierces (`pierce -1`) | `moonshot_ability.gd`: `_get_shot_origin` (a moon launches from its orbit) and `_get_shot_direction` (the volley converges on the cursor) |
| ability_1 | `crescent.tres` (`CosmoCrescentData`): `return_to_caster`, `curve_amount`, `pierce -1`, `moonlit_amp` / `moonlit_amp_full` | `crescent_ability.gd`: applies Moonlit per pass |
| cc | `tide.tres` (`CosmoTideData`): a `statuses_from_zone` pull zone, a detonation template | `tide_ability.gd`: the countdown and `Projectile.explode_at` |
| movement | `new_moon.tres`: `ChargeData` with `stop_at_target` and an untargetable `self_status` | generic `ChargeAbility` |
| ultimate | `starfall.tres` (`CosmoStarfallData`): meteor template, rate by moons, channel/resist statuses, end-on flags | `starfall_ability.gd`: the channel, meteor placement, warnings |

Moonlit is an ordinary status whose `incoming_magic_multiplier` is 2.0,
applied at strength `amp - 1`, so the amp lands in `HealthComponent.mitigate`
for every magic source. Starfall's resist is the same trick with
`incoming_physical_multiplier` 0.0 at strength 0.5. The shared pieces
(per-type damage-taken, boomerangs, REGEN ammo, zone-sourced pulls,
untargetable, `get_hero_metrics`) are in the generic systems;
`tools/heroes/caster_infra_test` covers them and `tools/heroes/cosmo_test`
covers the kit.

## What Jose took

A CARRY with two revolvers. Tools → New Hero from Template → "Jose", then:

| Slot | Data | Script |
|---|---|---|
| primary | `twin_longarms.tres`: `RangedAttackData`, SEMI, 12 rounds, 2 muzzles, FULL reload | generic `RangedAttackAbility` |
| ability_1 | `last_word.tres`: charged, `pierce -1` projectile, `damage_full`, `perfect_damage_multiplier`, `perfect_projectile` | generic `RangedAttackAbility` |
| movement | `flourish.tres`: `ChargeData`, MOVE_INPUT_OR_AIM, `invulnerable_duration` | `flourish_ability.gd`: reloads the gun on use |
| cc | `coin.tres`: a one-shot `RangedAttackData` whose `on_hit_status` is the mark; `values/execute_threshold` | `coin_ability.gd`: the execute (`hit_dealt`) and the reset (`status_target_died`) |
| ultimate | `weapons_free.tres` (`WeaponsFreeData`: a follow-owner circle zone, duration, allowed/quiet slots, `values/weapons_free_fire_rate`) | `weapons_free_ability.gd`: channel, autofire via `fire_extra_shot`, controller lock |

The shared pieces Jose needed were added to the generic systems (spread while
moving, perfect projectile, `fire_extra_shot`, dash direction mode and
immunity window, the controller lock, the live aim line, zone outlines), so
the next ranged hero gets them as data. `tools/heroes/jose_test` covers the
whole kit.

## What Rook took

1. Tools → New Hero from Template → "Rook".
2. In `rook_definition.tres`: title, role Carry, Weapon `growth` 6 with a
   late-spike curve.
3. In `rook_basic_attack.tres`: renamed to Quick Jab, added a `lifesteal`
   named value (0.1).
4. In `rook_basic_attack.gd`: the one `_on_target_hit` function above.

No other files, no engine code. `tools/heroes/balance_tools_test` plays Rook
against a dummy and checks his lifesteal, and the CSV export includes his
late spike.
