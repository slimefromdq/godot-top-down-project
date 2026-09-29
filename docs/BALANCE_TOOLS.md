# Balance tools

All of these work on every map and only ever edit runtime copies: no .tres
file is changed by playtesting, and every "Reset" restores the designer's
values.

| Key | Tool |
|---|---|
| **F1** | Debug panel |
| **F2** | Stat inspector overlay |
| **F3** | Next test map (Dream Basin ↔ Training Grounds), keeps your level |
| **F4** | Damage meter |
| **M** | Map overview (existing) |

## F1 debug panel

* **Hero**
  * Set the level (1 to the match cap) with a slider and see the recomputed stats and EHP.
  * Raise the level cap (up to 20) for playtests.
  * Toggle god mode and cooldowns off.
  * Full heal, or take a lethal hit to test the revive.
  * "Play as" swaps the player to any hero. In debug builds the list also
    offers test-only heroes from `tools/heroes/*/`, marked "(test)"
    (e.g. Ranged Test). They never appear in the roster, the CSV or
    Validate Heroes.
  * Edit the base stats live. "Reset stats + feel" restores them.
* **Abilities**: every number of every ability (combo steps, hit shapes, projectiles, statuses, trail zones, named values). Changes apply on the next cast. **Reset** restores the ability from its .tres.
* **Dummies**
  * Set HP, armor, magic resist and level.
  * Choose whether new dummies fight back and whether they can die.
  * Spawn one dummy or a pack of 5 in front of you.
  * "Apply to all" reconfigures every dummy.
  * Remove the ones you spawned.
  * A toggle makes every dummy fight back.
* **Feel**
  * Global comfort settings: shake intensity, trauma cap, shake speed, hitstop on/off and scale, nudge scale, flash on/off, announcer text on/off.
  * The hero's FeelProfile, editable live.
* **Match** (maps with a `MatchManager`: Dream Basin; other maps get a
  "Start a match here" button)
  * The state, the clock and both rosters with each hero's level and gold.
  * **Time**: jump the match clock by -60 / -10 / +10 / +60 s, to any
    second, or to a preset read from the live rules and the map (start, the
    first zone and its warning, the Dream Mote, the Nightmare and its
    warning, the late match). A jump (`MatchManager.jump_clock`) re-syncs
    everything on the clock as if the match had got there: the dreaming-zone
    and Dream Mote schedule, every neutral camp (a due camp spawns fresh,
    one not due yet waits), map pieces (glass whole, geysers ready) and the
    mood tint. Gold, XP and levels are left alone.
  * Give the player gold or XP, and set their level through the match (plays
    the level-up cue).
  * Skip the warmup, end the match for Dawn or Dusk, respawn now, fill
    your ultimate charge.
  * **Play as team** flips the player between Dawn (`a`) and Dusk (`b`) and
    moves them to that team's spawn, so you can test either side solo.
  * **Motes**: a Mote or Dream Mote at the cursor, give the player N Motes,
    force the next dreaming zone, clear every Mote (loose and carried), and
    **Mote spawns on the M map view** (trickle points, zones and their spawn
    points, the Dream Mote spot; press M to see them).
  * **Neutral objectives**: spawn the jungle camps now, the Nightmare now,
    start the Nightmare's 30 s warning now (watch the whole announce), clear
    every neutral, and an **Objectives on** switch.
  * **Map events** (`docs/MAP_EVENTS.md`): open the Black Market now (random
    edge, left or right) or close it, relocate the Island portal, spawn a
    Wanderer, go to the portal / market / Wanderer, give yourself a temp item
    (any hero), type a command (`market left`, `island`, `wanderer`,
    `goto portal`, `motes`), and read the **Mote sources** table (spawned /
    banked / delivered / spent per source, save it as CSV).
  * **Items**: pick any catalog item and **Give free** or **Buy** it (buying
    follows the shop rules), clear your items, open the shop, make every bot
    shop now, and **Shop anywhere** (lifts the in-base rule).
  * **Map pieces**: shatter or restore every dream-glass pane, pop every
    Mote geyser, hold every toggle gate open or closed for a minute, or put
    them back on their cycles.
  * **Dreamers**: for each team, set the wake meter, force a stir, finish
    or fail its Lullaby, grant Sweet Dreams now, and a **Deposit / Lullaby
    rings** overlay.
  * The match's `MatchRules`, editable live (a private copy per match).
* **Tools**: export the balance CSV, validate heroes, reset the meter, show or hide the overlays, switch maps. **Sight lines** draws a line from you to every nearby enemy: green if you can see it, red if a wall or a bush blocks it (`CombatQueries.has_line_of_sight`). **Airlock practice** plays Sam's airlock maze on you.
  **Visuals** switches off purely decorative layers one at a time (region
  drifters, critters, sound beds, the mood tint, the Dreamer glow, fountain
  ripples, bush rustle, dreaming-zone petals, the floor grid), or all at
  once, to see what each costs or to lighten a slow machine. They stay off
  across map switches until the game closes (`VisualToggles`); gameplay
  never reads them.

## F2 stat inspector

* Current and max HP, and effective HP against physical and magic damage.
* Weapon, Magic, Armor, MR and speed.
* Each ability's cooldown at the current level.
* Every damage or heal number at the current level, with its formula (e.g. `41.5 = 28 +2/lvl +45% M`).

## F4 damage meter

Tracks the local player since the last reset:

* Damage dealt, with DPS over a rolling 5-second window. DPS divides by the time actually spent fighting in that window, so a short burst isn't diluted.
* Shields: "Shielding done" (damage your shields absorbed, by status) and "Shielded" (damage absorbed for you, never counted as damage taken).
* A **breakdown by source**, using each hit's label: `blade`, `crescent`, `burn`, `fire_trail`, `searing_cut`, `sunbrand`, `sunbrand_burn`, `blaze_aura`, `phoenix_burst` …, with total, share and hit count.
* **Healing received** by source (`searing_cut_heal`, `phoenix_rebirth` …) and damage taken.

Each dummy also shows its own DPS and its total since it last reset.

## Balance CSV

**Tools → Export Balance CSV** (editor), the button in F1 → Tools, or
headless:

```
godot --headless res://tools/heroes/export_balance.tscn -- balance/balance_export.csv
```

The file is tidy (long) format, with one row per hero × level × metric, at levels 1, 5, 10, 15 and 20:

| column | example |
|---|---|
| hero | `avery` |
| role | `Tank` |
| level | `10` |
| source | `stat`, `derived` (effective HP, plus hero-level numbers an ability reports through `get_hero_metrics`, e.g. Cosmo's `moon_volley` and `burst_combo`) or `ability` |
| slot | `ability_1` (empty for stats) |
| ability | `searing_cut` (empty for stats) |
| metric | `health`, `cooldown`, `range`, `damage`, `heal_per_target`, `combo_steps/3/damage`, `values/lifesteal` …; guns add `shots_per_second`, `magazine_size`, `reload_time` (empty to full), `damage_per_shot`, `burst_dps` and `sustained_dps` (with reloads) |
| value | `63.3` |

```r
library(tidyverse)
bal <- read_csv("balance/balance_export.csv")

# Power curves: Weapon by level, one line per hero
bal |> filter(source == "stat", metric == "weapon") |>
  ggplot(aes(level, value, colour = hero)) + geom_line() + geom_point()

# Every ability number at level 10, wide for a quick table
bal |> filter(source == "ability", level == 10) |>
  select(hero, ability, metric, value) |>
  pivot_wider(names_from = metric, values_from = value)
```

## Validation

A HeroDefinition shows problems in a read-only **Validation** line at the
bottom of its inspector. It checks for:
* missing required slots, and slots GameRules doesn't know;
* abilities with no data or no script;
* negative stats, values, timings or shapes;
* guns (no projectile, zero fire rate, ammo per shot above the magazine, bad falloff range), charge settings (min above max), statuses (compel speed, unknown modifier stats) and zones.

Problems are also printed when you save a definition or ability, and by **Tools → Validate Heroes**. Heroes log a warning when they spawn with problems.

## Performance benches

Not tests (they always exit 0); run them before and after a performance
change.

```
godot --headless --fixed-fps 60 res://tools/perf/match_bench.tscn -- 3600
xvfb-run -a godot --rendering-driver opengl3 res://tools/perf/render_cost.tscn
```

* `match_bench` plays the real Dream Basin world with 12 bots for N frames
  and prints the average wall time per frame (game logic only when headless).
* `render_cost` needs a real renderer. It hides one kind of drawn node at a
  time (by script, or class for plain nodes) and prints the frame time, draw
  calls and primitives each kind costs.

## Headless test suites

```
godot --headless res://tools/heroes/infrastructure_test.tscn
godot --headless res://tools/heroes/ranged_infra_test.tscn
godot --headless res://tools/heroes/support_infra_test.tscn
godot --headless res://tools/heroes/caster_infra_test.tscn
godot --headless res://tools/heroes/shared_systems_test.tscn
godot --headless res://tools/heroes/avery_test.tscn
godot --headless res://tools/heroes/jose_test.tscn
godot --headless res://tools/heroes/melody_test.tscn
godot --headless res://tools/heroes/cosmo_test.tscn
godot --headless res://tools/heroes/cpt_yellow_test.tscn
godot --headless res://tools/heroes/hazmat_test.tscn
godot --headless res://tools/heroes/nimbus_test.tscn
godot --headless res://tools/heroes/tilly_test.tscn
godot --headless res://tools/heroes/butler_test.tscn
godot --headless res://tools/heroes/pike_test.tscn
godot --headless res://tools/heroes/sam_test.tscn
godot --headless res://tools/heroes/batch2_infra_test.tscn
godot --headless res://tools/heroes/biker_test.tscn
godot --headless res://tools/heroes/horace_test.tscn
godot --headless res://tools/heroes/mochi_test.tscn
godot --headless res://tools/heroes/computer_test.tscn
godot --headless res://tools/heroes/catgirl_test.tscn
godot --headless res://tools/heroes/rocco_test.tscn
godot --headless res://tools/heroes/airlock_test.tscn
godot --headless res://tools/heroes/feel_test.tscn
godot --headless res://tools/heroes/balance_tools_test.tscn
godot --headless res://tools/heroes/map_switch_test.tscn
godot --headless res://tools/dream_basin/smoke_test.tscn
godot --headless res://tools/match/match_test.tscn
godot --headless res://tools/match/mote_test.tscn
godot --headless res://tools/match/dreamer_test.tscn
godot --headless res://tools/match/polish_test.tscn
godot --headless res://tools/match/ultimate_test.tscn
godot --headless res://tools/match/items_test.tscn
godot --headless res://tools/match/objectives_test.tscn
godot --headless res://tools/match/map_events_test.tscn
godot --headless res://tools/ai/bot_test.tscn
godot --headless res://tools/ai/bot_nav_test.tscn
godot --headless res://tools/ai/bot_role_test.tscn
godot --headless res://tools/ai/bot_neutral_test.tscn
godot --headless res://tools/ai/bot_match_smoke_test.tscn
godot --headless res://tools/ai/batch2_bot_test.tscn
godot --headless res://tools/visuals/rig_bake_test.tscn
godot --headless res://tools/visuals/live_rig_test.tscn
godot --headless res://tools/map/map_pieces_infra_test.tscn
godot --headless res://tools/flow/flow_test.tscn
```

Each exits with the number of failed checks (0 = all passed).

`tools/heroes/dps_compare.tscn` isn't a test: it prints sustained DPS
(primary only, 8 s) and a scripted 3 s burst for each carry at levels 1, 5
and 10, measured in-engine against a dummy with no resists
(`dps_harness.gd`, also used by `cosmo_test` for her balance targets).
`tools/heroes/capture_feel.tscn` saves screenshots of a finisher swing
(run under a display or `xvfb-run` with `--rendering-driver opengl3`).
`tools/match/capture_match.tscn` does the same for the match HUD, the F1
Match tab, Motes (loose, carried, a dreaming zone, the spawn overlay) and
the Dreamers (asleep with the wake meters, stirring with a Lullaby).
`tools/ai/capture_bots.tscn -- <dir>` (run with `xvfb-run -a -s "-screen 0
1920x1080x24"` so the HUD has its full width) saves a 6 v 6 bot match: the
team rings, nameplates and placeholder bodies in a line-up, the team bars,
and the map after the bots have spread out.
`tools/match/capture_objective.tscn -- <dir> <prefix>` saves the objective's
before/after set: an idle Dreamer, a stirring Dreamer, a full Mote stack,
the Dream Mote telegraph and the HUD during a stir.
