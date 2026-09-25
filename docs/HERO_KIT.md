# Hero Kit: Abilities

> This page describes the original rifle hero (`scenes/player.tscn`,
> `scenes/world.tscn`). Heroes are now built from data: see
> [HOW_TO_ADD_A_HERO.md](HOW_TO_ADD_A_HERO.md) (Avery is the worked example)
> and [BALANCE_TOOLS.md](BALANCE_TOOLS.md).
>
> **`WeaponComponent` is legacy and superseded for heroes.** A hero's gun is
> a `RangedAttackData` + `RangedAttackAbility` in any slot: it goes through
> the ability controller, feel presets, `DamageInfo` labels, the HUD, the
> debug panel and the balance CSV like every other ability, and adds SEMI/AUTO
> fire, muzzles, spread, falloff and FULL/PER_ROUND reloads. Keep
> `WeaponComponent` only for the old rifle player and `scenes/enemy.tscn`
> until they're rebuilt; don't extend it.

The first hero covers one of each common ability archetype, so later heroes
and enemies can be assembled from the same parts.

| Key | Ability | Archetype | Script | What it covers |
|---|---|---|---|---|
| LMB (hold) | Rapid-fire rifle | Primary weapon | `WeaponComponent` | 12 shots/s, 45-round magazine, slight spread, reload |
| Q | Piercing Lance | **Skillshot** | `SkillshotAbility` | Aimed projectile that can miss; pierce, knockback, optional on-hit status |
| Shift | Phase Dash | **Movement** | `DashAbility` | Forced movement, invulnerability window, direction from input or cursor |
| E | Overdrive | **Buff** | `BuffAbility` | Timed self status with stat multipliers (+75% fire rate, +25% speed), instant reload |
| F | Arc Zap | **Instant click-cast** | `TargetedAbility` | Target under cursor validated (exists, in range, line of sight), hit lands instantly, applies Shocked debuff |

The enemy under the cursor is highlighted while Arc Zap is ready. A cast with
no valid target fails with a message, and the cooldown isn't spent.

## How it fits together

```
Player (Actor)
└── Components
    ├── AbilityController         ← player input / AI calls try_activate()
    │   ├── SkillshotAbility
    │   ├── DashAbility
    │   ├── BuffAbility
    │   └── TargetedAbility
    ├── StatusComponent           ← buffs/debuffs; others read multipliers
    ├── HealthComponent           ← damage_taken multiplier, invulnerability
    ├── MovementComponent         ← move_speed multiplier, forced moves, knockback
    └── AudioComponent
```

- **Input is outside abilities.** `player.gd` maps input events to abilities
  through each ability's `input_action`. An AI can call
  `ability_controller.try_activate_id(&"phase_dash", point)` to use the same
  ability.
- **Hits are structured.** `DamageInfo` carries damage, type, source, tags, knockback and
  status. `HurtboxComponent.take_hit()` routes each part to the right component.
- **Stats go through statuses.** Abilities never edit a component's fields
  directly, so an effect expiring always restores the original values.

## Tuning

All numbers are exports on the ability nodes in `scenes/player.tscn`
(cooldown, damage, range, distance, ...) or on the status resources in
`resources/status/`. Key bindings are in Project Settings > Input Map
(`ability_skillshot`, `ability_dash`, `ability_buff`, `ability_target`).

## Adding a new ability

1. Extend `Ability` and override `_activate(target_position) -> String`.
   Return `""` on success or a short reason to fail (no cooldown is spent).
2. Call `actor.trigger_cue(ability_id, {...})` for presentation.
3. Add the node under an `AbilityController`, set `ability_id`,
   `input_action` and `cooldown`.
4. Map the `ability_id` cue in the actor's Visual/Audio profiles
   (see `VISUALS_AND_AUDIO.md`).

## Training dummies

`scenes/training_dummy.tscn` shows a DPS readout, regenerates after 3 s
without damage, and (with **Can Die**) dies and respawns so you can preview
death and kill effects. The world has one killable and one unkillable dummy
on the left.
