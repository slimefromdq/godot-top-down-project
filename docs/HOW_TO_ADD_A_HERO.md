# How to add a hero

A hero is **data plus a few small scripts**. The systems (health, damage,
hitboxes, projectiles, statuses, the cast state machine, movement, game feel,
HUD, debug tools, balance export) are shared and never need editing for a new
hero.

Avery (`heroes/avery/`) is the worked example throughout. Rook
(`heroes/rook/`) was made by following exactly these steps, with nothing but
a definition and one ability script.

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
| `StatusEffect` | slow, stun, root, silence, knockback/pull, burn; stacking rules | `data/avery_stun.tres`, `data/avery_burn.tres` |
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
| a melee CC (stun, knockback, pull) | `MeleeAttackData` with `on_hit_status` | none |
| something new | extend `Ability` (or `MeleeAttackAbility`) | a small script |

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
* **Hero-wide events**: `actor.combat_hooks` → `hit_dealt`, `damage_taken`,
  `kill`, `death`, `level_up`, `about_to_die` (cancellable), `heal_done`.
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
ability-specific cues. Swing whoosh, impact and fire layers come from the
FeelProfile, not the cue profiles.

### 7. Test it

* Press **F1 → Hero → "Play as"** to swap the player to your hero in any map.
* **Training Grounds** (F3) has resistance dummies, a pack for multi-target
  abilities, a dummy that fights back, and a killable one.
* **F1** edits any number live (Reset restores the .tres), **F2** shows every
  ability number at the current level, **F4** is the damage meter.
* **Tools → Validate Heroes** and **Tools → Export Balance CSV** include your
  hero automatically.

---

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
