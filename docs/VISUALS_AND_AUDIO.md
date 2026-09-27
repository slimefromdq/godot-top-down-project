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

**Check a hero's sounds in its test**: create
`preload("res://tools/heroes/audio_coverage.gd").new(hero)` right after the
hero spawns and report its `checks()` at the end (see `sam_test.gd`). It fails
if a gun primary's `<id>_fire` has no Min Interval, the ultimate is silent, a
sound has no stream, or a profile entry never fires during the test (a
misspelt or dead cue name).

Each hero's own placeholder sounds live in `audio/sfx/<hero>/`, next to the
shared ones in `audio/sfx/`.

## The aero look

The game aims for Frutiger Aero / Flash-game gloss: bright saturated colour,
glassy highlights, rounded shapes, sky-blue surroundings.

- **UI theme**: `resources/ui/aero_theme.tres` (project setting
  `gui/theme/custom`) gives every Control glossy aqua buttons, glass panels
  and bubbly progress bars. It's generated: edit the colours in
  `tools/visuals/build_aero_theme.gd` and run
  `godot --headless --script res://tools/visuals/build_aero_theme.gd`.
- **Custom `_draw()` code** uses `AeroDraw` (`scripts/visuals/aero_draw.gd`):
  `gloss_rect` (glass panel), `gloss_circle` (bubble/orb) and
  `gloss_polygon` (highlight on a shape). HUD slots, team cards, the minimap,
  cover and bushes all go through it, so restyle there first.
- **Keep draw calls down.** Every `draw_circle` and `draw_colored_polygon`
  is its own draw call (only rects and short lines batch), and the glossy
  look stacks several per object. Draw many shapes into a `ShapeBatch`
  (`scripts/visuals/shape_batch.gd`: same calls as a CanvasItem, plus
  `draw_rounded_rect`; `gloss_circle`, `gloss_polygon` and
  `gloss_rect_shapes` accept it) and finish with `batch.draw_on(self)`: one
  draw call. Bushes, cover, the minimap and the team cards do this.
- **Don't redraw what nobody sees.** Animated decorations ask
  `ScreenCull.is_near(self, radius)` before `queue_redraw()`, HUD widgets
  redraw at 15-30 Hz instead of every frame, and short-lived world effects
  (`lifetime` 3 s or less) aren't spawned far off-screen
  (`EffectSpawner`). A carrier's outer orbit rings draw simple Motes.
- **Maps**: sky-blue void and clear colour, a white floor grid, saturated
  floor zones and cover (dark boundary walls are deep navy-teal).
- **Hero badges** carry a radial body gradient and a gloss highlight
  (see below).

## Telling heroes and teams apart

**Placeholder bodies**: each hero's VisualProfile `texture` is
`sprites/heroes/<hero>.svg`, a glossy badge until real art arrives: the
silhouette is the role (tank hexagon, carry circle, tempo diamond, flex
pentagon), the fill colour and the letter are the hero. They set
`flip_to_face_aim = false` so the letter stays readable; replace the texture
(or add SpriteFrames) and turn flipping back on when real art lands.

**Team indicator** (`TeamIndicator`, added to every Hero): a ring on the
ground in the team colour (more saturated than the HUD's, so it reads on the
team's own pastel floor), a pointer on the ring toward the hero's aim, a
nameplate over the health bar, and the health bar fill in the team colour.
The local player's ring is thicker with a white rim and their name reads
"(You)". Tuning is in the node's exports.

**Team bars** (`TeamBar`, in the match HUD either side of the wake meters):
every hero's portrait (its body texture) in a team-coloured frame, greyed with
a respawn count while dead. Only your own team's cards show health and
ultimate charge.

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
| `<id>_empty` | Tried to fire with too little ammo. Never fires on a gun with `auto_reload_when_empty` (the default): its last shot already started the reload | |
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

### Match cues

The match objective isn't an actor, so its cues live in two match-wide
profiles, `MatchRules.cue_visuals` and `cue_audio`
(`resources/match/match_visuals.tres`, `match_audio.tres`), played with
`MatchManager.play_world_cue(from, cue, context)`. A hero cue (`level_up`)
uses the hero's own profile entry instead when it has one. A world cue's
VisualCue `screen_shake` reaches the local camera only when it happened
near the screen (and ShakeCamera applies the shake settings). Its sound
plays once per pitch in `context.chord` if given (a deposit's closing
chord), else at `context.pitch`. The chime pitches (`MatchRules.chime_scale`,
a major pentatonic over two octaves via `chime_pitch(n)`) and the two chords
(`bank_chord`, `deliver_chord`, brighter) are in MatchRules > Cues.

| Cue | When | Context |
|---|---|---|
| `level_up` | A hero gains a level (MatchManager) | level |
| `mote_spawn` / `dream_mote_spawn` | A Mote / the Dream Mote appears | position |
| `dream_mote_warning` | The Dream Mote is coming (ground telegraph) | position, radius, duration |
| `mote_pickup` | A Mote attaches to its carrier | count, pitch (up the pentatonic scale with the stack) |
| `mote_drop` | Jostled Motes pop out (a "boing") | position, count |
| `mote_burst` | A carrier died: every Mote bursts out | count, radius |
| `mote_fade` | A dropped Mote ran out of time | position |
| `mote_decoy_pop` | A decoy was grabbed | source (who grabbed it) |
| `zone_start` | A dreaming zone pair starts | position (one half) |
| `deposit_tick` | One Mote goes into a Dreamer | source (depositor), index (1, 2, 3 ... within the visit), pitch (up the pentatonic scale), delivered, target_position, team |
| `bank_complete` / `deliver_complete` | A visit to your own / the enemy's Dreamer ends having deposited | source, total, chord (bank: resolving; deliver: brighter) |
| `sweet_dreams` | A team earns the Sweet Dreams buff | position (their Dreamer) |
| `wake_quarter` | A wake meter passes 25 / 50 / 75% | mark |
| `stir_start` | A Dreamer starts stirring | duration |
| `lullaby_tick` | Once a second while a Lullaby fills | pct |
| `settle` | A stir ends without a win | how (`lullaby` / `timeout`) |
| `wake` | A Dreamer wakes: the match is won | position |
| `dreamer_mumble` | A sleeping Dreamer mumbles now and then (sound) | position |
| `gold_gain` | The local player's deposit visit ends: floating "+gold" at them | text, color |
| `banner` / `banner_major` | An announcer banner appears (sound only; `banner_major` for a stir) | |

Effect scenes made for these (`effects/match/`, scripts in
`scripts/match/fx/`): `sparkle_ring` (spawn / pickup / deposit / Sweet
Dreams), `bubble_pop` (fades, decoys), `light_pillar` (the Dream Mote
telegraph; context duration, radius). `DreamShimmer` is the full-screen
transition into the victory screen.

**Motes** (`MoteLook`): glossy bubbles with a turning shine and a rim; the
Mote squashes through `get_look_squash()` (a wobbly pop when it spawns or
lands, a stretch when pulled). Dropped ones blink faster and faster, then
pop. **Carried** (`MoteOrbit`): up to three counter-turning rings, soft
sparkle trails, the newest squashes as it arrives, a full stack gets rainbow
rims, and carrying the Dream Mote raises a beam of light over the hero. The
**Dream Mote** has a slow iridescent swirl. **Dreaming zones** (`DreamZone`)
fade in over the warning, then tint the ground, shimmer at the edges and
drift petals; they fade out when they end.

**Dreamers** (`DreamerLook`): breathe (one breath every ~3 s, faster as they
wake), blow Zzz bubbles, and now and then twitch, turn over or mumble. At
25 / 50 / 75% the breath quickens, the eyes flutter, the Zzz thin out and,
past 75%, the ring trembles. Stirring: glowing eyes, rocking, a ground ripple
and a light pulse each second of the countdown. The Lullaby drifts moons and
stars down onto it; settling is a big exhale and closed eyes; waking opens
the eyes wide. Each deposited Mote arcs into its mouth: a gulp and a glow
when banked, a flinch and a burst of the depositor's colour when delivered.
The body fades while a hero stands behind it (the rings never do).

**The win**: when a Dreamer wakes, `world.gd` plays a slow-motion beat
(`wake_slowmo_scale` / `_time`), one hit-stop frame (skipped with hitstop off,
scaled by `hitstop_scale`), then the `DreamShimmer`, then the victory screen.

**Announcer** (`scenes/hud/announcer.gd`, added by the match HUD): glossy
banners that slide in at top centre, queue, and cut each other short by
priority (a stir interrupts a zone). Each plays `banner` / `banner_major`.
It also shows toasts for your own banks and deliveries (with the gold) and
pings the minimap for a stir and a Dream Mote. **FeelSettings.announcer_text**
off hides the text and keeps the sounds.

**Minimap** (448 px wide, `Minimap.width`): a Dream Mote star, Dreamer rings that fill with the wake meter
(sun or moon inside, flashing while stirring), tinted dreaming zones, carrier
pips, and big pulsing pings for a stir or a Dream Mote. Objectives draw
their own icon with `draw_minimap_icon(canvas, point, viewer_team)`; areas
join `minimap_areas` with `get_minimap_polygon()` / `get_presence()`.

**Wake meters** (`WakeMeter`): glossy tubes that ease toward the value, with
a highlight sweeping along the fill; from 75% they glow and crack.

The Mote's body is `MoteData.look_scene` (`scenes/match/mote_look.tscn`) and
the Dreamer's is `DreamerData.look_scene` (`scenes/match/dreamer_look.tscn`):
swap either for a sprite scene and gameplay doesn't change.

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

## A crowded mix (AudioMix)

`resources/audio/audio_mix.tres` (`AudioMix`) keeps a 6 v 6 fight from
clipping. Before `AudioManager.play_sfx` starts a sound it checks:

| Field | Default | Effect |
|---|---|---|
| `max_sfx_voices` | 22 | SFX players at once, over every cue. Past it, other heroes' sounds are dropped; yours steal the oldest voice. |
| `same_stream_window` | 0.05 | The same file started again this soon is skipped (a volley of identical hits plays once). |
| `same_stream_max_voices` | 3 | Copies of one file ringing at once. |
| `cull_distance` | 1900 | Positional sounds farther than this from the screen centre don't play. |
| `max_distance` / `attenuation` | 2200 / 1.8 | Their `AudioStreamPlayer2D` falloff. |
| `other_source_db` | -4 | Sounds made by anyone but the local player are this much quieter. |

Your own sounds (pass `source`; `AudioComponent` and projectiles do) and flat
UI sounds (the announcer) are never thinned. `AudioManager.skipped_sfx`
counts what was dropped. The buses (`default_bus_layout.tres`) add a
compressor on SFX (-16 dB, 4:1) and a hard limiter on Master (-0.5 dB).

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
- **Vfx Visible To**: who sees the Attached Vfx: everyone (default), the
  target's allies, the target's enemies, only the target and its applier,
  or a list an ability sets with `status_component.set_vfx_viewers(id, actors)`.
  Only the local player's screen is filtered (`LocalView`); tint, alpha and
  sound aren't.
- **Camera Look Ahead**: the player's own camera leans this many pixels
  toward the cursor while the status is on them (a scope). Ease speed is
  `ShakeCamera.look_ahead_ease`.
- A laser sight: use `effects/feel/aim_laser.tscn` as the Attached Vfx; it
  draws the actor's aim line (stopped by walls) for as long as the status lasts.

## Bushes

A `Bush` hides whoever stands in it from everyone outside it. For the local
player, `VisualsComponent` stops drawing an enemy (and its health bar and
minimap dot) while it's hidden; you, your teammates and revealed actors
(`StatusEffect.reveals`) are always drawn. See `CombatQueries` for the rule.

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

### Layered (adaptive) music

Alongside the priority requests, `AudioManager` can play a `MusicLayerSet`:
synced stems (`MusicLayer`: a stream, the `tier` it joins at, a volume)
that all start together and loop, faded in and out by volume.

- `AudioManager.play_layers(set)`, `set_music_tier(tier)` (each stem plays
  while tier >= its own; crossfades over the set's `crossfade_time`),
  `play_sting(stream)`, `stop_layers()`.
- The match's `MatchMusic` (a child of the MatchManager) picks the tier:
  CALM, TENSE (a wake meter at 50%+, or a Dream Mote on the map), STIRRING
  (any Dreamer stirring), and on the win fades the stems and plays the
  set's `victory_sting`. It rises at once and falls one tier at a time, at
  most once per `min_seconds_per_drop` (8 s).
- `resources/match/match_music.tres` has six empty stems: with no streams it
  all runs silently. What each stem should be is in `docs/MUSIC_STEMS.md`.

## Accessibility hooks

- Screen shake: `ShakeCamera.shake_strength` (0 turns it off). Every match
  shake and the wake's hit-stop go through the same settings.
- Announcer banners: `FeelSettings.announcer_text` hides the text (sounds
  stay).
- Damage numbers: VisualProfile > Feedback > Show Damage Numbers.
- Volume: the `Music` and `SFX` buses.
