# Top-Down Ability Shooter Roadmap

## Vision

Build a replayable top-down shooter in which distinct heroes combine weapons and cooldown-based abilities, fight escalating enemy waves, collect stat-changing items, and finish a run with a boss encounter. Gameplay should be readable at a glance and new content should be created mostly by combining reusable components and data resources.

## Current Foundation

The project currently has:

- Player movement with acceleration and friction.
- Reusable movement, health, hurtbox, and weapon components.
- Player and enemy projectile combat.
- Ammo, fire cooldown, and reload behavior.
- A basic ranged enemy that follows and shoots the player.
- Collision layers for the world, characters, hurtboxes, and projectiles.
- A small test world with a player, enemy, wall, training dummies, and camera.
- A first hero kit: rapid-fire rifle, skillshot, dash, buff, and click-cast ability (see `docs/HERO_KIT.md`).
- Status effects (buffs/debuffs) with stat multipliers and visuals.
- Reusable, profile-driven visuals and audio components with a music manager (see `docs/VISUALS_AND_AUDIO.md`).

Before adding large amounts of content, the next milestone should turn this prototype into a stable vertical slice.

## Guiding Architecture

Use scenes for behavior, resources for configuration, and components for reusable runtime systems.

Suggested actor structure:

```text
Actor (CharacterBody2D)
|-- Visuals
|   |-- AnimatedSprite2D or AnimationPlayer
|   `-- Effects
|-- Components
|   |-- StatsComponent
|   |-- HealthComponent
|   |-- MovementComponent
|   |-- AbilityController
|   |   |-- AbilitySlotPrimary
|   |   |-- AbilitySlotSecondary
|   |   `-- AbilitySlotUltimate
|   |-- StatusEffectComponent
|   `-- LootComponent (enemies only)
|-- WeaponPivot
|   `-- WeaponComponent
|-- Hurtbox
`-- NavigationAgent2D (enemies only)
```

Core data resources:

- `ActorStats`: health, speed, acceleration, damage, fire rate, cooldown rate, projectile speed, projectile size, armor, and pickup range.
- `AbilityData`: icon, cooldown, charges, targeting mode, tags, and effect scene.
- `ProjectileData`: texture/animation, speed, lifetime, damage, pierce, bounce, collision behavior, trail, impact effect, and team.
- `EnemyData`: stats, behavior profile, visuals, weapon/ability loadout, drop value, and spawn cost.
- `ItemData`: name, description, rarity, icon, stat modifiers, tags, and optional triggered effect.
- `WaveData`: duration, spawn budget, enemy pool, elite chance, and boss rules.

Important rules:

- Keep player input out of ability logic. Input requests an ability; the component validates and executes it.
- Apply all upgrades through a shared modifier pipeline rather than directly changing unrelated component fields.
- Give damage a source team/faction so friendly fire and collision rules remain predictable.
- Drive animation from actor state and signals rather than embedding gameplay rules inside animations.
- Make enemies and items data-driven so variants rarely require copied scripts.

## Phase 1 — Stable Combat Foundation

Goal: create a reliable, testable combat loop before expanding the content.

- [ ] Add a `StatsComponent` that exposes base, additive, and multiplicative values.
- [ ] Make movement, health, weapons, projectiles, and abilities read final values from shared stats.
- [ ] Add factions/teams to actors, hurtboxes, and projectiles.
- [ ] Replace projectile setup fields with `ProjectileData` resources.
- [ ] Add projectile hit data: damage, knockback, critical hit, source, and tags.
- [x] Add health signals for `health_changed`, `damaged`, `healed`, and `died`.
- [ ] Add invulnerability windows and optional armor/resistance hooks.
- [ ] Add player HUD: health, ammo/reload, ability slots, cooldowns, and wave state.
- [ ] Add pause, restart, victory, and defeat flow.
- [ ] Add lightweight debug tools for damage, spawn testing, and cooldown reset.

Done when:

- The player can fight several enemies for five minutes without collision, ownership, or cleanup errors.
- Stats can be changed at runtime and every dependent system updates correctly.
- The HUD clearly communicates health, ammo, reload state, and cooldowns.

## Phase 2 — Component-Based Ability Framework

Goal: make abilities reusable across heroes, enemies, elites, bosses, and items.

- [x] Create an `AbilityController` with configurable slots and input bindings.
- [ ] Create an `AbilityComponent` base with cooldown, charges, cast time, targeting, cancel, and activation signals.
- [ ] Support targeting modes: self, aimed direction, cursor point, nearest target, and placed area.
- [ ] Add reusable effect components: damage, heal, dash, knockback, shield, spawn projectile, spawn area, and apply status.
- [ ] Add status effects with duration, stacking rules, periodic effects, and visual indicators.
- [ ] Add an ability state flow: ready, targeting, casting, active, cooldown, interrupted.
- [ ] Add ability UI with key prompts, cooldown sweep, charges, and disabled feedback.
- [ ] Ensure AI can request the same abilities through the same public interface as the player.

First ability set:

- [x] Dash: directional movement, brief invulnerability, trail, and impact-safe collision.
- [ ] Grenade: aimed arc or target point, explosion radius, damage, and knockback.
- [ ] Barrier: temporary shield or placed projectile blocker.
- [ ] Ultimate: radial projectile burst or high-impact area strike.

Done when:

- At least four abilities are assembled from reusable effects.
- One ability is shared by a player hero and an enemy without copying its core logic.
- Cooldown rate and ability damage respond correctly to item modifiers.

## Phase 3 — Visual Language and Animation Pass

Goal: make movement, attacks, damage, and danger readable without relying on debug output.

- [ ] Establish a compact art guide: palette, scale, silhouettes, outline rules, faction colors, and effect colors.
- [ ] Replace placeholder player and enemy icons with readable hero/enemy sprites.
- [ ] Create idle, move, attack/cast, reload, hurt, death, and dash animations.
- [ ] Flip or rotate visuals consistently while keeping collision shapes stable.
- [ ] Upgrade projectile visuals by family: bullet, plasma, explosive, beam, homing, and enemy warning shot.
- [ ] Add muzzle flashes, shell/ejection accents where appropriate, trails, impacts, explosions, and hit flashes.
- [ ] Add telegraphs for dangerous attacks, including ground markers and wind-up animation.
- [ ] Add camera shake, hit-stop, damage numbers, and screen feedback with accessibility toggles.
- [ ] Pool frequently spawned projectiles and effects if profiling shows allocation spikes.

Done when:

- Players can distinguish friendly and hostile projectiles immediately.
- Normal, elite, and boss attacks have clearly different danger levels.
- Every major action has anticipation, action, and recovery feedback.

## Phase 4 — Map and Encounter Space

Goal: replace the test room with one complete combat map.

- [ ] Build a tile-based arena with collision, navigation, cover, open combat lanes, and landmarks.
- [ ] Separate map layers for floor, decoration, collision, navigation, spawn zones, and foreground occlusion.
- [ ] Add camera bounds and sensible player spawn/checkpoint positions.
- [ ] Add enemy spawn zones that avoid the camera, blocked areas, and unsafe proximity to the player.
- [ ] Add doors or arena locks for combat encounters.
- [ ] Add environmental hazards such as explosive props, damaging zones, or slowing terrain.
- [ ] Add navigation baking and recovery behavior for stuck enemies.
- [ ] Add ambient animation, lighting, particles, and map audio regions.

Done when:

- The map supports close-, medium-, and long-range builds.
- Enemies can navigate the full playable space without common stuck points.
- Spawn positions are fair and never place enemies directly on the player.

## Phase 5 — Spawners, Waves, and Difficulty Director

Goal: create a complete repeatable session with controlled pacing.

- [ ] Create an `EnemySpawner` that consumes enemy data and validated spawn zones.
- [ ] Create a `WaveDirector` that spends a spawn budget over time.
- [ ] Add warm-up, active wave, reward selection, and boss states.
- [ ] Scale spawn budget, enemy stats, variant weights, and elite chance over time.
- [ ] Cap living enemies and expensive effects to protect performance.
- [ ] Add spawn telegraphs and prevent unavoidable contact damage.
- [ ] Add wave progress UI and short breathing periods.
- [ ] Seed random choices so difficult runs can be reproduced during testing.

Done when:

- A full 10–15 minute run progresses from early enemies to elites and a boss.
- Difficulty rises through encounter composition, not health scaling alone.
- The director respects performance and population limits.

## Phase 6 — Enemy Roster and Variants

Goal: create enemy combinations that ask the player to reposition and prioritize targets.

Base enemy roles:

- [ ] Chaser: closes distance and uses contact or short-range attacks.
- [ ] Shooter: maintains range and fires readable bursts.
- [ ] Flanker: circles or dashes toward exposed angles.
- [ ] Tank: slow, durable, and protects weaker units.
- [ ] Artillery: telegraphs delayed area attacks.
- [ ] Support: heals, shields, buffs, or spawns other enemies.

Variant modifiers:

- [ ] Swift: faster movement and shorter recovery, lower health.
- [ ] Armored: frontal resistance with a vulnerable angle or break state.
- [ ] Volatile: explodes on death after a clear warning.
- [ ] Vampiric: heals from dealt damage and uses a distinct effect color.
- [ ] Splitter: creates smaller enemies on death.
- [ ] Elemental: applies a supported status effect with matching visuals.

Implementation notes:

- Compose behavior from steering, range, targeting, weapon, and ability modules.
- Use `EnemyData` resources for most variants; add scripts only for genuinely new behavior.
- Assign each enemy a spawn cost based on pressure, durability, mobility, and utility.

Done when:

- At least four base roles and three modifiers can combine safely.
- Mixed groups produce different positioning decisions.
- Enemy visuals communicate role and modifier before the enemy attacks.

## Phase 7 — Elite Enemies

Goal: turn familiar enemies into short, high-pressure encounters.

- [ ] Create an elite modifier system with two or three compatible affixes.
- [ ] Increase challenge through new behavior and attack patterns, not only larger stats.
- [ ] Add elite health bars, nameplates, aura/outline, and affix icons.
- [ ] Add affixes such as shielding nearby enemies, orbiting projectiles, teleporting, enraging, or creating hazard zones.
- [ ] Add affix compatibility rules to prevent unfair combinations.
- [ ] Guarantee a meaningful reward from elite kills.

Done when:

- Elites are recognizable on entry and their affixes are readable.
- Each elite changes target priority or movement strategy.
- Elite rewards justify their increased risk.

## Phase 8 — Boss Framework and First Boss

Goal: deliver a multi-phase finale that tests the run’s core skills.

- [ ] Create a boss controller with phase thresholds, pattern scheduling, arena events, and interrupt-safe transitions.
- [ ] Add boss HUD, intro, phase-change feedback, defeat sequence, and rewards.
- [ ] Build attacks from the same projectile, area, status, and ability systems used elsewhere.
- [ ] Add attack selection rules that prevent impossible pattern overlaps.
- [ ] Create one boss with three phases:
  - Phase 1 tests aiming and projectile dodging.
  - Phase 2 adds summons or arena control.
  - Phase 3 increases tempo and combines learned patterns.
- [ ] Add checkpoints or rapid boss restart tools for testing.

Done when:

- Every major boss attack is telegraphed and avoidable.
- Phase transitions are deterministic and cannot soft-lock.
- The boss can be tuned mostly through resources rather than script edits.

## Phase 9 — Stat-Changing Items and Rewards

Goal: make each run develop into a distinct build without breaking component boundaries.

- [ ] Create an item inventory that applies and removes named stat modifiers.
- [ ] Support flat, additive-percent, multiplicative, capped, and conditional modifiers.
- [ ] Define modifier order and expose a breakdown for debugging.
- [ ] Add rarity, tags, stacking rules, and mutually exclusive item groups.
- [ ] Create reward choices after waves/elites and a reroll or skip option.
- [ ] Update item descriptions from real values so tooltips stay accurate.
- [ ] Add item pickup, selection, and acquisition effects.

Starter item pool:

- [ ] Max health and healing improvements.
- [ ] Move speed and acceleration.
- [ ] Damage and critical chance/damage.
- [ ] Fire rate, magazine size, reload speed, and projectile speed/size.
- [ ] Pierce, bounce, multishot, or chain effects.
- [ ] Cooldown reduction, extra ability charge, shield strength, and status duration.
- [ ] Tradeoff items, such as more damage with less maximum health.

Done when:

- At least 20 items support several recognizable builds.
- Recalculating stats never permanently corrupts base values.
- Item combinations have explicit caps and cannot create unbounded recursion.

## Phase 10 — Heroes and Loadouts

Goal: offer distinct play styles built on the shared systems.

- [ ] Create a `HeroData` resource containing stats, visuals, weapon, abilities, and animation set.
- [ ] Add hero selection and a concise loadout preview.
- [ ] Build the first three heroes around different combat ranges and ability rhythms.
- [ ] Give each hero a passive, mobility/defense ability, active damage/utility ability, and ultimate.
- [ ] Add hero-specific audio and effect colors without compromising faction readability.
- [ ] Ensure generic items work across all heroes; use tags for deliberate exceptions.

Suggested initial heroes:

- [ ] Vanguard: automatic weapon, dash, barrier, radial ultimate.
- [ ] Ranger: precision weapon, roll, explosive trap, piercing-line ultimate.
- [ ] Arcanist: energy projectiles, blink, slowing field, meteor ultimate.

Done when:

- Each hero has a complete run-capable kit.
- Items create multiple viable builds per hero.
- Shared components contain the mechanics; hero scripts mainly coordinate presentation and special rules.

## Phase 11 — Polish, Balance, and Release Readiness

- [ ] Add sound and music for weapons, abilities, enemies, items, waves, and bosses.
- [ ] Add control rebinding, gamepad support, aim options, and readable focus navigation.
- [ ] Add accessibility settings for flashes, shake, hit-stop, damage numbers, color cues, and aim assistance.
- [ ] Save settings, unlocks, best runs, and persistent progression if desired.
- [ ] Add object-count and frame-time profiling for peak waves.
- [ ] Test unusual resolutions, pause/focus changes, death during transitions, and simultaneous effects.
- [ ] Balance using recorded run data: damage taken, kill time, item picks, deaths, and boss phase reached.
- [ ] Add a short tutorial/onboarding encounter.
- [ ] Prepare export presets and a release checklist.

## Recommended Milestones

### Milestone A — Combat Sandbox

Phases 1–3. One hero, four abilities, two enemy behaviors, improved visuals, complete HUD, and a polished test arena.

### Milestone B — Vertical Slice

Phases 4–5 plus part of Phase 6. One map, wave director, four enemy roles, reward breaks, and a 10-minute session.

### Milestone C — Complete Run

Phases 7–9. Elites, one boss, item inventory, and at least 20 items.

### Milestone D — Content Alpha

Phase 10. Three heroes, six base enemies, several variants/affixes, tuned progression, and a full run loop.

### Milestone E — Release Candidate

Phase 11. Audio, accessibility, save data, performance work, onboarding, balance, and exports.

## Suggested Next Sprint

Keep the first sprint narrow enough to validate the architecture:

1. Implement shared actor stats and a modifier pipeline.
2. Refactor health, movement, weapons, and projectiles to consume those stats.
3. Add factions and structured hit data.
4. Implement the ability controller plus dash and grenade abilities.
5. Add minimal HUD for health, ammo, and the two ability cooldowns.
6. Replace the placeholder player, enemy, and projectile visuals with a coherent first-pass style.
7. Build a small combat test map and validate the loop with one chaser and one shooter.

Sprint exit test: play a five-minute encounter, collect three test stat modifiers, use both abilities repeatedly, and confirm that damage, cooldowns, death, restarting, and cleanup remain correct.

## Scope Guardrails

Defer these until the complete-run milestone is fun and stable:

- Online multiplayer.
- Procedural map generation.
- Large meta-progression trees.
- Crafting and complex currencies.
- More than one boss or biome.
- Large numbers of heroes, enemies, or items before the data pipeline is proven.

The best next release is a small, polished vertical slice—not a large collection of disconnected systems.
