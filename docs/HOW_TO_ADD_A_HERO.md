# How to add a hero

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
| `StatusEffect` | slow, stun, root, silence, knockback/pull, burn, compel, stat modifiers; stacking rules | `data/avery_stun.tres`, `data/avery_burn.tres` |
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
| hard CC that can't be chained forever | automatic: **Resolve** (`GameRules.resolve_duration` / `resolve_cc_multiplier`) halves a stun, root or taunt that lands within 2 s of the last one ending. Carries, self-applied CC, walk-out-able pulls and formations are exempt; `StatusEffect.ignores_resolve` exempts any other | none |
| "can A see B?" (a stalker passive, a sight-gated autofire) | `CombatQueries.has_line_of_sight(from, to)`: walls on `GameRules.sight_mask`, and bushes (can't see in from outside; from inside you see out) | none |
| hide in bushes / reveal someone | bushes hide their occupants automatically (`CombatQueries.is_hidden_from`, drawn per viewer by `VisualsComponent`); a `StatusEffect` with `reveals` shows them anyway | none |
| a status VFX only some players see (a mark only its target and caster see) | `StatusEffect.vfx_visible_to`: EVERYONE, TARGET_ALLIES, TARGET_ENEMIES, TARGET_AND_APPLIER, or LISTED + `status_component.set_vfx_viewers(id, actors)` | none (LISTED: a small script) |
| something new | extend `Ability` (or `MeleeAttackAbility` / `RangedAttackAbility`) | a small script |

`tools/heroes/ranged_test/` is a test-only hero that uses every ability row
above (pick it with **F1 → Play as → Ranged Test (test)**). The rules and
queries that aren't abilities (Resolve, line of sight, bushes, filtered VFX)
are covered by `tools/heroes/shared_systems_test`. Short recipes follow.

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
abilities (e.g. Jose's Weapons Free) respect it. F1 → Tools → Sight lines
draws the player's lines to nearby enemies.

**Resolve.** After someone else's stun, root or taunt ends on an actor, it
gets `GameRules.resolve_status` for `resolve_duration` (2 s); new hard CC on it
meanwhile lasts `resolve_cc_multiplier` (50%) as long. No hero code is
involved: `StatusEffect.is_hard_cc()` decides what counts.

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

**Avery**, slot by slot:

| Slot | Data | Script |
|---|---|---|
| primary | `sunblade_slash.tres`: 3 `combo_steps` (light, light, finisher) + `swing_projectile` = the crescent | generic `MeleeAttackAbility` |
| ability_1 | `searing_cut.tres` (`SearingCutData`: heal per target, falloff, cap) | `searing_cut_ability.gd`: heals via the `hit_dealt` hook |
| movement | `solar_charge.tres` (`ChargeData` + `trail_zone`) | generic `ChargeAbility` |
| cc | `dawnbreaker.tres` with `on_hit_status = avery_stun.tres` | generic `MeleeAttackAbility` |
| ultimate | `phoenix_rebirth.tres` (`PhoenixRebirthData`) | `phoenix_rebirth_ability.gd`: cancels death via `about_to_die` |

To swap Dawnbreaker's stun for a knockback or pull, point its
`on_hit_status` at `avery_cc_knockback.tres` or `avery_cc_pull.tres`. No
code.

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
FeelProfile, not the cue profiles.

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
for any area that lands around its caster). His body-is-the-army look is
`vfx/bug_army.gd` (cosmetic, spawned by the `spawn` cue).
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
