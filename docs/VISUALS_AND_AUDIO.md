# Adding Visuals and Audio

Every character's look and sound is kept out of gameplay code. Gameplay only
announces **cues**, named moments like `fire`, `hurt`, `death` or `phase_dash`.
Two reusable components listen for those names and decide what to show and
play:

| Component | Profile resource | Per-cue entry |
|---|---|---|
| `VisualsComponent` (Node2D) | `VisualProfile` (.tres) | `VisualCue` |
| `AudioComponent` (Node) | `AudioProfile` (.tres) | `SoundCue` |

Both work the same way. To change how something looks or sounds, edit its
profile. You rarely need to touch a script.

```
gameplay ──trigger_cue("phase_dash")──►  cue_triggered signal
                                              │
                         ┌────────────────────┴────────────────────┐
                 VisualsComponent                           AudioComponent
          profile.cues["phase_dash"] ─► VisualCue    profile.cues["phase_dash"] ─► SoundCue
          (spawn effect, flash, anim, shake)         (random variation, pitch, anti-spam)
```

## Quick recipes

**Give a character a new sprite**
1. Open its visual profile (`resources/visuals/player_visuals.tres` etc.).
2. For a still image, drag a texture into **Body > Texture**. For animation,
   create a `SpriteFrames` in **Body > Sprite Frames** with animations named
   `idle`, `move`, `hurt` and `death`. They play automatically. Missing ones are skipped.
3. Adjust **Body Scale / Body Offset**. Set **Body Tint** alpha to 0 if your
   art already has its colours.

**Change a kill/death effect**
- *Death effect* (what this actor looks like dying): profile > Cues > `death`
  > Effect Scene.
- *Kill effect* (a cosmetic that plays on anything **this** actor kills,
  e.g. the player's gold sparkle): profile > Death > Kill Effect.
  The audio twin is AudioProfile > Kill Sound.

**Add VFX to an ability**
1. Build the effect as a scene (see *Making effect scenes* below).
2. In the caster's VisualProfile > Cues, add a key equal to the ability's
   `ability_id` (e.g. `overdrive`) and a new `VisualCue` whose Effect Scene is
   your scene.

**Add a sound**
1. Drop `.wav`/`.ogg` files anywhere under `audio/`.
2. In the AudioProfile > Cues, add the cue name and a new `SoundCue`. Put
   several files in **Streams** for random variation.

**Make anything use these components** (enemy, dummy, neutral monster, crate)
1. Add a `HealthComponent` if it doesn't have one.
2. Add a `Node2D` with `visuals_component.gd` and put a `Sprite2D` or
   `AnimatedSprite2D` under it, or let the profile create one.
3. Add a `Node` with `audio_component.gd`.
4. Assign profiles. Health-based cues (`hurt`, `heal`, `death`, `spawn`)
   work immediately. For custom cues, give the root script a
   `signal cue_triggered(cue: StringName, context: Dictionary)` and emit it
   (see `scripts/training_dummy.gd`). Anything built from `actor.tscn`
   already has this.

**Find out which cue names fire**: tick **Print Cues** on either component
and watch the Output panel while you play.

## Built-in cues

| Cue | When | Useful context keys |
|---|---|---|
| `spawn` | Component enters the tree / dummy respawns | position |
| `hurt` | Took damage | source, text (amount) |
| `heal` | Healed | text (amount) |
| `death` | Health hit 0 | source (killer) |
| `fire` | Weapon fired (legacy WeaponComponent) | position (muzzle), direction |
| `reload` / `reload_done` | Reload started / finished (legacy) | |
| `dry_fire` | Tried to fire with an empty magazine (legacy) | |
| `<id>_fire` | A RangedAttackAbility shot | position (muzzle), direction, muzzle_index, ammo, max_ammo, charge_ratio, perfect, extra (fired by another ability via fire_extra_shot) |
| `<id>_perfect` | A perfect charged release fired | same as `<id>_fire` |
| `<id>_hit` | One of its projectiles hit | position, target, damage |
| `<id>_empty` | Tried to fire with too little ammo | |
| `<id>_reload_start` / `_reload_round` / `_reload_end` / `_reload_cancel` | Gun reload started / one round loaded (PER_ROUND) / full / stopped early | duration (start), ammo (round) |
| `<id>_charge_start` / `_charge_full` / `_charge_release` / `_charge_cancel` | Hold-to-charge phases | charge_ratio, perfect |
| `<id>_zone_start` / `_zone_end` | ZoneAbility channel began / ended | zone_duration |
| `<id>_charge_start` (live aim line) | Map to `effects/feel/telegraph_line.tscn`, attached: it follows the charging ability | charge_ability, range |
| Jose: `flourish_reload`, `coin_execute`, `coin_reset`, `weapons_free_start` / `_shot` / `_end` | Flip reload; execute (at the victim); coin back in hand; ultimate channel | target, target_position, interrupted (end) |
| `<id>_drop` | ChargeAbility arrival released a bashed target (end_on_hit_status_on_arrival / arrival_status) | position, target |
| RideAbility: `<id>_charge_start` / `_charge_release` / `_windup` / `_active` | Ride begins (context.charge_ability) / ends / landing telegraph / burst | radius, duration (windup) |
| `<id>_applied` | SelfStatusAbility put its status on the caster | enemies, strength, radius, duration |
| `ability_failed` | A cast was rejected | text ("No target", "Out of range", "Blocked") |
| `<ability_id>` | Ability cast (e.g. `piercing_lance`, `phase_dash`, `overdrive`, `arc_zap`) | direction, duration, target, target_position |
| `phase_dash_end` | Dash finished | position (landing spot) |
| `arc_zap_hit` | Click-cast landed | position (target), target |

Every cue also gets `position`, `direction`, `source` and `visuals` filled in
automatically. Custom scripts can trigger anything with
`actor.trigger_cue(&"my_cue", {...})`.

## VisualCue fields

| Field | Effect |
|---|---|
| Effect Scene | Scene to spawn. Receives the context if its root has `setup_cue(context)`. |
| Attach To Actor | Follow the actor (auras, trails) instead of staying in the world (impacts). |
| Attached Duration | Remove an attached effect after N seconds (0 = use the cue's `duration`). |
| Align To Direction | Rotate to face the cue direction. |
| Offset / Scale / Tint | Placement and colour tweaks without editing the scene. |
| Body Animation | Play this animation on the body (SpriteFrames or AnimationPlayer). |
| Flash Color / Duration | Hit-flash the body. Alpha = strength. |
| Screen Shake | 0 to 1 trauma added to a `ShakeCamera`. |

## SoundCue fields

| Field | Effect |
|---|---|
| Streams | One is picked at random each play. |
| Volume / Pitch Min / Pitch Max | Pitch is randomised within the range. |
| Bus | `SFX` or `Music` (defined in `default_bus_layout.tres`). |
| Positional | World-space sound (fades with distance) vs. flat UI-style sound. |
| Min Interval | Rate limit, which keeps rapid-fire weapons from turning into noise. |
| Max Voices | Cap on overlapping copies; the oldest is cut. |

## Making effect scenes

`effects/` holds the placeholder effects. Duplicate one as a starting point.

- Use `scripts/visuals/one_shot_effect.gd` as the root script. It restarts
  every particle system, plays every `AnimatedSprite2D` and the
  `AnimationPlayer`'s `default` animation, then frees itself after
  **Lifetime**. Set Lifetime to 0 for attached effects that the component
  removes (auras). They fade out instead of popping.
- Inside, use anything: `GPUParticles2D`/`CPUParticles2D`, a flipbook
  `AnimatedSprite2D`, a `Sprite2D` with an `AnimationPlayer`, lights.
- Want data from the cue? Add `func setup_cue(context: Dictionary)` to the
  root script. See `beam_effect.gd` (uses `target_position`),
  `floating_text.gd` (uses `text`) and `afterimage_trail.gd` (uses
  `visuals` to copy the body sprite).

## Status effects

Buffs and debuffs (`resources/status/*.tres`) carry their own presentation,
so they look the same on every target:

- **Attached Vfx**: shown for as long as the status lasts.
- **Body Tint**: colour blended over the body.
- **Apply Sound**: played once on application.

## Projectiles

Projectiles are plain scenes (`scenes/bullet.tscn`,
`scenes/skillshot_projectile.tscn`). Edit the sprite and trail directly in the
scene. Impact look and sound are exports on the root: **Hit Effect**,
**Wall Effect**, **Hit Sound**, **Wall Sound**. The victim's own `hurt` cue
still plays, so leave Hit Sound empty unless you want an extra layer.

## Music

`AudioManager` (autoload) keeps a priority list of music requests and
crossfades to the highest one:

- **Level music**: set the stream on the `LevelMusic` node in `world.tscn`
  (a `MusicRequest`, priority 0).
- **Character or boss themes**: AudioProfile > Music > Theme Music. It plays
  while that actor is alive and fades back when it dies. A boss at priority
  10 overrides level music automatically.
- **Code**: `AudioManager.request_music(self, stream, priority)` /
  `AudioManager.release_music(self)`.

Music keeps playing while the game is paused. Put music files in
`audio/music/` and enable **Loop** in the file's Import settings. The manager
also restarts tracks that end.

## Accessibility hooks

- Screen shake: `ShakeCamera.shake_strength` (0 turns it off).
- Damage numbers: VisualProfile > Feedback > Show Damage Numbers.
- Volume: the `Music` and `SFX` buses.
