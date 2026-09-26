# Implementation prompts

Copy-ready Claude Code prompts for each phase of the build order, written against the current repo (`godot-top-down-project`).

## Strategy

Run one Claude Code session and one pull request per phase, and merge each before starting the next. Every prompt follows the same shape: read the docs, plan, build shared systems before the hero, prove it with a headless test, then stop and report.

**Why this shape fits your repo:**

- **The repo already documents itself.** `docs/HOW_TO_ADD_A_HERO.md` has a "You want / Use" table that maps mechanics to existing data types. Every prompt tells Claude Code to use a row from that table before writing new code, and to add a row for anything new. That table is what stops six heroes from turning into six copies of similar scripts.
- **Tests are already headless.** Each existing hero has `tools/heroes/<name>_test.tscn`, which exits with the number of failed checks. Each new hero gets the same, so "done" is a number, not a feeling.
- **Numbers live in `.tres` files.** Prompts ask for all tuning values in resources, so you can adjust them live in the F1 panel instead of asking for code changes.

**Working rules:**

1. **Plan first on infrastructure phases** (0, 4, 5 and 6). Ask for a plan, read it, then say "go". For hero-only work, skip straight to building.
2. **Stats match the current roster.** Stats stay on the 20-level range; each new hero's L10 values come from the design doc, and linear growth = (L10 − L1) ÷ 9.
3. **Run every existing test at the end of each phase,** not just the new one. The shared systems touch combat code all five current heroes rely on.
4. **Keep a PR small enough to review.** If a phase's plan touches more than about 15 files, split the prompt at its "part 1 / part 2" line.
5. **You're the design owner.** When Claude Code asks a design question the prompt doesn't answer, answer it in the design doc too, so the next session sees it.

## Prompt 0: conventions and shared systems

Phase 0 adds a `CLAUDE.md` so every later session starts with the repo's rules, then builds the three systems all six heroes lean on. Ask for the plan first.

```text
Read ROADMAP.md, docs/HOW_TO_ADD_A_HERO.md, docs/BALANCE_TOOLS.md and
docs/VISUALS_AND_AUDIO.md before doing anything.

Part 1: create CLAUDE.md at the repo root. Keep it under 60 lines. Include:
- A hero is data plus small scripts. Before writing any new ability script,
  check the "You want / Use" table in HOW_TO_ADD_A_HERO.md and use a row if
  one fits.
- Any new reusable system gets a row in that table and a case in
  tools/heroes/ranged_test so it can be tested alone.
- Shared systems must never reference a specific hero.
- All tuning numbers live in .tres resources, never hard-coded in scripts.
- Visuals and sounds go through cues and profiles, never gameplay code.
- Every hero has tools/heroes/<name>_test.tscn, run with
  `godot --headless res://tools/heroes/<name>_test.tscn`; it exits with the
  number of failed checks.
- Stats are authored on the 20-level StatScaling range while matches cap at
  level 10 (GameRules.max_level). Linear growth = (L10 value - L1 value) / 9.
- Before finishing any task, run every test listed in BALANCE_TOOLS.md.

Part 2: plan, then build, three shared systems. Show me the plan first and
wait for my go-ahead.

1. Resolve (global CC rule). After a stun, root or compel ends on an actor,
   they get a Resolve status for 2 s. While Resolved, new stuns, roots and
   compels last 50% as long. Both numbers live in game_rules.tres.

2. Line-of-sight query. A static CombatQueries.has_line_of_sight(from_actor,
   to_actor) using a raycast against world and cover layers. Bushes also
   block sight between an actor outside the bush and an actor inside it.
   Add a debug overlay toggle (F1 > Tools) that draws sight lines from the
   player to nearby enemies, green when clear and red when blocked.

3. Viewer-filtered visuals. Attached status VFX get a visibility rule:
   everyone, allies of the target, enemies of the target, or an explicit
   list of actors. Only the local player's view is filtered; gameplay is
   unaffected.

Write tools/heroes/shared_systems_test.tscn covering:
- a dummy stunned twice in a row gets a second stun half as long
- line of sight is blocked by a wall and by a bush, and clear in the open
- a VFX limited to "target and applier" is hidden for a third actor

Add the new systems to HOW_TO_ADD_A_HERO.md, run every test, and report
what you changed.
```

## Prompt 1: Hazmat

Hazmat is almost all existing parts, so this is the phase that shows whether the pattern works. No plan step needed.

```text
Read CLAUDE.md and docs/HOW_TO_ADD_A_HERO.md.

Part 1: add a reusable "ramping zone damage" option. A zone's damage per
tick is multiplied by a per-target ramp that grows the longer that target
stays inside and resets after it has been outside for a set time. All
numbers are on the zone data. Add a row to the How-To table and a case to
ranged_test.

Part 2: create Hazmat with Tools > New Hero from Template.
Name: Hazmat. Title: The Contaminant. Role: TANK.
Stats (L1 -> L10, linear): Health 950 -> 1850, Weapon 35 -> 70,
Magic 30 -> 80, Armor 40 -> 75, Magic Resist 30 -> 55.
Movement speed must be lower than Cpt. Yellow's.

Kit:
- passive, Contamination: an aura that follows him (ZoneAbilityData,
  follow_owner). 220 px radius. Magic damage 10 + 20% Magic per second,
  ramping +50% per second inside, capped at 3x, resetting 1 s after the
  target leaves.
- primary, Sprayer: auto-fire short cone of small projectiles, 350 px
  range. Enemies hit start their Contamination ramp one step higher.
- ability_1, Canister: lobbed projectile that explodes into a 250 px
  lingering gas ground zone for 6 s. 12 s cooldown.
- movement, Seal Suit: 400 px forward shove with 30% damage reduction for
  2 s. 12 s cooldown.
- cc, Quarantine: 500 px hose hook skillshot; pulls the first enemy hit to
  him and stuns 0.4 s. 11 s cooldown.
- ultimate, Containment Breach: aura grows to 500 px and applies full ramp
  instantly for 6 s; when it ends it leaves an 8 s residue ground zone at
  that spot. 90 s cooldown.

Visual placeholder: glossy yellow body, chartreuse aura with a crisp edge
ring drawn above other ground effects.

Write tools/heroes/hazmat_test.tscn checking:
- a dummy standing in the aura for 4 s takes 3x the first second's damage
- stepping out for 1 s resets the ramp
- Quarantine pulls and stuns, and the second stun within 2 s is halved
  (Resolve)
- Breach leaves a residue zone behind
Run every test, export the balance CSV, and report Hazmat's L10 stats
next to Avery's and Cpt. Yellow's.
```

## Prompt 2: Nimbus

Nimbus adds two small systems, camera look-ahead and a parry window, plus a steerable glide.

```text
Read CLAUDE.md and docs/HOW_TO_ADD_A_HERO.md.

Part 1: two reusable systems.
1. Camera look-ahead: while an ability requests it, the local player's
   camera shifts toward the cursor by a set distance, easing in and out.
2. Parry window: a self status that, for its duration, reflects the first
   enemy projectile that hits the actor (the projectile flips team and
   direction), or stuns the first melee attacker. It emits a signal on
   success so the ability can react.
Add How-To rows and ranged_test cases for both.

Part 2: create Nimbus. Title: The Gentleman Spy. Role: CARRY.
Stats (L1 -> L10, linear): Health 500 -> 950, Weapon 50 -> 110,
Magic 10 -> 18, Armor 14 -> 30, Magic Resist 14 -> 24.
Lowest movement speed of any Carry.

Kit:
- passive, Steady Hand: each second standing still adds +10% damage to
  his next shot, up to +40%. Show it as pips.
- primary, Umbrella Rifle: RangedAttackData, SEMI, 1.1 shots/s,
  magazine 5, fast projectile, pierce 1, 1.6 x Weapon.
- ability_1, Scope: hold. Camera look-ahead 500 px, -40% move speed, and a
  thin aim laser visible to all players while held.
- movement, Descend: opens the umbrella and launches him (Actor.launch)
  up to 1100 px over walls and ledges, 1.6 s air time. While airborne his
  move input steers the landing point. 22 s cooldown.
- cc, Parry: 0.35 s parry window. On success, refund half the cooldown
  and make his next shot a guaranteed crit. 10 s cooldown.
- ultimate, Overcast: a 500 px raincloud ground zone anywhere within two
  screens for 6 s. Enemies inside are revealed (including in bushes) and
  slowed 15%. His shots against targets inside always crit (1.75x) and
  pierce everyone. 70 s cooldown.

Write tools/heroes/nimbus_test.tscn checking:
- a dummy's bolt reflected by Parry damages that dummy
- Descend clears a ledge and the landing point moves with steering input
- Steady Hand reaches +40% after 4 s still and resets on moving
- shots into Overcast crit and pierce
Run every test and report Nimbus's L10 stats next to Jose's.
```

## Prompt 3: Tilly

Tilly turns the map's `JumpPad` into something a hero can place, and adds a death-intercept zone built on the same hook as Avery's Phoenix Rebirth.

```text
Read CLAUDE.md, docs/HOW_TO_ADD_A_HERO.md, scripts/map/jump_pad.gd and
heroes/avery/abilities/phoenix_rebirth_ability.gd.

Part 1: two reusable systems.
1. Placeable jump pad: an ability can spawn a JumpPad at runtime with a
   team filter, a lifetime, a launch-count limit and a landing offset set
   by dragging from the placement point (hold to place, drag, release).
   Enemies of the owner get an optional displacement status instead of a
   launch. Keep the existing map JumpPad working unchanged.
2. Death-intercept zone: a zone that subscribes to CombatHooks.about_to_die
   on allies inside it and can cancel the death, set health, move the ally
   and apply a status. Once per ally per zone.
Add How-To rows and ranged_test cases for both.

Part 2: create Tilly. Title: The Crash Test Acrobat. Role: FLEX.
Stats (L1 -> L10, linear): Health 580 -> 1120, Weapon 30 -> 60,
Magic 40 -> 100, Armor 20 -> 38, Magic Resist 22 -> 40.

Kit:
- passive, Crumple Zone: displacements on her are 40% shorter; after any
  launch she lands with +25% move speed for 1.5 s.
- primary, Bouncy Balls: 2.5 shots/s, projectiles bounce off walls twice.
  No healing.
- ability_1, Trampoline: placeable jump pad, 700 px max landing offset,
  lasts 10 s or 4 launches, 2 charges, 16 s recharge. Enemies stepping on
  it are bounced back the way they came.
- movement, Cartwheel: 350 px dash, 8 s cooldown. If it ends on one of her
  trampolines, she launches with it and the cooldown resets.
- cc, All Eyes on Me: 300 px spin; enemies are compelled toward her for
  1.25 s (compel_overrides_input) while she takes 40% less damage.
  12 s cooldown.
- ultimate, Safety Net: 600 px death-intercept zone around her for 6 s.
  An ally who would die is set to 15% health, moved beside Tilly and made
  untargetable for 1 s. 100 s cooldown.

Write tools/heroes/tilly_test.tscn checking:
- an ally stepping on a trampoline lands on the dragged spot
- a trampoline expires after 4 launches
- Cartwheel onto her own trampoline launches her and resets the cooldown
- a lethal hit on an ally inside Safety Net leaves them at 15% beside her,
  and a second lethal hit on the same ally is not intercepted
- Avery's revive test still passes
Run every test and report Tilly's L10 stats next to Melody's.
```

## Prompt 4: Butler

Butler's form swap touches the `AbilityController`, which every hero uses, so ask for the plan first and read it carefully.

```text
Read CLAUDE.md, docs/HOW_TO_ADD_A_HERO.md and
scripts/abilities/ability_controller.gd. Plan first and wait for my go.

Part 1: two reusable systems.
1. Slot swapping: AbilityController.swap_slot(slot_id, ability_data) and
   restore_slot(slot_id). Each form keeps its own cooldowns, so swapping
   back and forth never resets or skips a cooldown. The HUD updates icons
   and cooldowns on swap. Existing heroes must be unaffected.
2. Frontal blocker: while held, a hitbox on the hero's aim arc absorbs
   enemy projectiles. It has its own HP (a ScalingValue), regenerates while
   lowered, and breaks when emptied. It emits signals for raised, lowered,
   absorbed and broken.
Add How-To rows and ranged_test cases for both.

Part 2: create Butler. Title: The Composed. Role: TANK.
Stats (L1 -> L10, linear): Health 900 -> 1750, Weapon 38 -> 78,
Magic 20 -> 45, Armor 38 -> 70, Magic Resist 30 -> 52.

Passive, Hunger (0-100), shown as a bar visible to both teams:
+1 per 1% of max HP lost, +1 per second while in combat. At 100 he swaps
every slot to its Starving version for up to 8 s. Each Bite lowers Hunger
by 35; at 0 he restores the Composed slots, is rooted for 0.6 s (a
tie-straightening cue), then gains bonus armor for 3 s.

Composed kit:
- primary, Cane: three-hit melee combo.
- ability_1, Vampiric Cloak: frontal blocker, HP 400 at L1 scaling to
  1100 at L10. Lowering it gives +20% move speed for 1 s.
- movement, At Your Service: dash to an ally near the cursor and shield
  them for 150 + 60% Magic. Short dash with no ally. 10 s cooldown.
- cc, Polite Refusal: cane sweep, 250 px knockback. 9 s cooldown.
Starving kit:
- primary, Claws: faster melee swipes with 25% lifesteal.
- ability_1, Bite: lunge-grab, 0.5 s stun, drains health, lowers Hunger
  by 35. 3 s cooldown.
- movement, Pounce: dash to the enemy nearest the cursor. 6 s cooldown.
- cc, Hiss: short cone, 40% slow and 1 s silence. 9 s cooldown.
Both forms:
- ultimate, Dinner Is Served: set Hunger to 100 and enter Starving with a
  full 8 s, then fly 900 px as a bat swarm, untargetable, draining every
  enemy passed through. 80 s cooldown.

Write tools/heroes/butler_test.tscn checking:
- losing 100% of max HP in damage triggers Starving
- cooldowns survive a swap to Starving and back
- two Bites bring Hunger from 100 to 30, and three return him to Composed
- the cloak absorbs exactly its HP and then breaks
- Dinner Is Served leaves him Starving with a full 8 s
Run every test and report Butler's L10 stats next to Avery's and
Cpt. Yellow's.
```

## Prompt 5: Pike

Pike needs the containment ring, the biggest new piece of physics so far, because it has to stop movement, dashes, teleports and projectiles in both directions. Plan first.

```text
Read CLAUDE.md, docs/HOW_TO_ADD_A_HERO.md and
heroes/jose/abilities/coin_ability.gd (the existing single-target mark).
Plan first and wait for my go.

Part 1: containment ring (reusable). A ring zone with a listed set of
actors inside. For its duration nothing crosses its edge in either
direction: walking, dashes, charges, launches, teleports and projectiles
are all stopped. Actors not on the list are pushed out when it forms.
It ends early if a listed actor dies. Add a How-To row and a ranged_test
case.

Part 2: create Pike. Title: The Beloved's Shadow. Role: TEMPO.
Stats (L1 -> L10, linear): Health 560 -> 1050, Weapon 40 -> 95,
Magic 10 -> 18, Armor 18 -> 34, Magic Resist 16 -> 28.

Beloved is a status Pike applies to one enemy at a time
(stack_per_applier, ends_if_applier_dies). Applying it to a new enemy
removes it from the old one. The Beloved sees a pink heart over their head
that beats faster as Pike gets closer and glows when she is within
teleport range; their allies see a smaller heart (use viewer-filtered
VFX).

Kit:
- passive, Obsession: while her Beloved has no line of sight to her
  (CombatQueries.has_line_of_sight), +20% move speed and body_alpha 0.4.
  Her first knife after they regain sight deals double damage and roots
  0.75 s, at most once per 6 s.
- primary, Juggled Knives: RangedAttackData, 4 shots/s, magazine 5,
  reload_style REGEN at 1 knife per 0.5 s. Damage 0.4 x Weapon plus 0.5%
  of the target's max HP. Five knives orbit her as the ammo display.
- ability_1, Beloved: heart skillshot; the enemy hit becomes her Beloved.
  4 s cooldown.
- movement, There You Are: blink to just behind her Beloved if within
  900 px. No line of sight needed. With no Beloved, a short dash.
  10 s cooldown.
- cc, Don't Go: knife skillshot that roots the first enemy hit for 1 s,
  1.5 s if it is her Beloved. 12 s cooldown.
- ultimate, Only Us: containment ring, 450 px radius, 4 s, around Pike
  and her Beloved; requires the Beloved within 600 px. 90 s cooldown.

Write tools/heroes/pike_test.tscn checking:
- marking a second enemy clears Beloved from the first
- There You Are works behind a wall and fails beyond 900 px
- Obsession's bonus is on only while a wall blocks the Beloved's sight
- nothing crosses the ring: a dash, a projectile and a teleport all fail
- the ring ends early if the Beloved dies
Run every test and report Pike's L10 stats next to Jose's and Melody's.
```

## Prompt 6: Sam, in two parts

Sam is split into two sessions and two PRs: the minigame instance is new territory, and it's worth playing the airlock alone before wiring it to the UFO.

**6a: systems and the airlock.** Plan first.

```text
Read CLAUDE.md, docs/HOW_TO_ADD_A_HERO.md, scripts/abilities/ally_targeting.gd
and the rhythm system in scripts/rhythm. Plan first and wait for my go.

Build three reusable systems:
1. Either-team targeting: a skillshot or targeted ability can hit the
   first actor of either team and apply different statuses depending on
   whether it's an ally or an enemy.
2. Two-target link: a status linking two actors for a duration. Options:
   a leash (they can't move more than N px apart; the one moving away is
   pulled back) and healing share (X% of healing on one also heals the
   other).
3. Minigame instance: a per-player overlay that takes over one hero's
   input for a while and reports a result. It has a minimum and maximum
   duration, shows a small inset of the real map, and is only rendered for
   that player. Design it so a rhythm phrase could later run inside it.

Then build the airlock as the first minigame, playable alone from F1 >
Tools:
- a small top-down room played with normal WASD movement
- the player starts on the left; the airlock door is on the right and
  opens after standing in it for 0.3 s
- obstacles: slow heart projectiles in simple patterns, "HI!!" speech
  bubbles sweeping across, and a wobbly hug-arm that reaches for the
  player's position
- each hit pushes the player back 60 px
- room length tuned so a perfect run takes about 1.5 s; forced exit at 4 s
- every number in a .tres

Add How-To rows and ranged_test cases for all three systems. Write
tools/heroes/airlock_test.tscn checking that a scripted perfect run
finishes in 1.4-1.7 s and a run that stands still exits at 4 s.
```

**6b: Sam himself.** Only start after you've played the airlock and like how it feels.

```text
Read CLAUDE.md and docs/HOW_TO_ADD_A_HERO.md.

Create Sam. Title: The Visitor. Role: TEMPO.
Stats (L1 -> L10, linear): Health 620 -> 1150, Weapon 25 -> 45,
Magic 40 -> 110, Armor 20 -> 38, Magic Resist 22 -> 40.

Kit:
- primary, Hello!: 3 shots/s, magic damage orbs that bounce off walls once.
- ability_1, Hug: 650 px either-team skillshot drawn as his arms
  stretching out. Enemy: root 1 s. Ally: shield 120 + 50% Magic.
  9 s cooldown.
- movement, Tractor Beam: lifts and carries a target 400 px
  (carry_enabled). Enemy: stunned while carried. Ally: untargetable while
  carried. With no target, a short hover-dash. 14 s cooldown.
- cc, Friendship Bracelet: a projectile that hits one target and chains
  to the nearest same-team actor within 400 px. Enemies: 300 px leash.
  Allies: 50% healing share. 4 s, 12 s cooldown.
- ultimate, Close Encounter: target an enemy within 700 px; 0.4 s beam
  telegraph they can dodge. On hit: the victim becomes untargetable and
  can't be damaged, is carried under a UFO, and plays the airlock
  minigame. The UFO flies toward Sam's cursor at 350 px/s using
  movement_component.set_cruise; Sam can move and shoot but not cast
  other abilities. When the victim escapes or the minigame ends, they
  drop at the UFO's position with a 0.3 s daze. Everyone sees the UFO's
  ground shadow and a portrait of who's inside. 80 s cooldown.

Write tools/heroes/sam_test.tscn checking:
- Hug roots an enemy and shields an ally
- Tractor Beam moves an ally 400 px and they take no damage meanwhile
- two leashed enemies can't get more than 300 px apart
- a Close Encounter victim can't be damaged and lands where the UFO was
- Resolve halves a stun applied right after the landing daze
Run every test and report Sam's L10 stats next to Pike's.
```

## After every phase

Before merging a phase's PR, spend ten minutes on these checks. Most bugs in a shared-systems change show up in heroes that weren't the focus.

- [ ] Every headless test exits 0, the old ones included.
- [ ] Validate Heroes (F1 > Tools) shows no new problems.
- [ ] The balance CSV's L10 row for the new hero sits within about 15% of its role peers' health and damage.
- [ ] The How-To table has a row for each new system, and `ranged_test` can use it.
- [ ] Play the new hero in Training Grounds for five minutes against fighting dummies, then two minutes each as Avery and Jose to check nothing broke.
- [ ] Tune numbers in the F1 panel, then copy the values you like into the `.tres` files (the panel never saves).
- [ ] Write anything you changed about the design back into the main tab, so the next session's prompt matches.

If a phase goes badly, don't patch it across sessions. Close the PR, adjust the prompt here, and rerun it from a clean branch.
