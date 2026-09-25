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
  * Global comfort settings: shake intensity, trauma cap, shake speed, hitstop on/off and scale, nudge scale, flash on/off.
  * The hero's FeelProfile, editable live.
* **Tools**: export the balance CSV, validate heroes, reset the meter, show or hide the overlays, switch maps.

## F2 stat inspector

* Current and max HP, and effective HP against physical and magic damage.
* Weapon, Magic, Armor, MR and speed.
* Each ability's cooldown at the current level.
* Every damage or heal number at the current level, with its formula (e.g. `41.5 = 28 +2/lvl +45% M`).

## F4 damage meter

Tracks the local player since the last reset:

* Damage dealt, with DPS over a rolling 5-second window. Shields show as "Shielding done" (absorbed by shields you gave) and "Shielded" (absorbed for you; never counted as damage taken). DPS divides by the time actually spent fighting in that window, so a short burst isn't diluted.
* A **breakdown by source**, using each hit's label: `blade`, `crescent`, `burn`, `fire_trail`, `searing_cut`, `dawnbreaker`, `phoenix_burst` …, with total, share and hit count.
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
| source | `stat`, `derived` (effective HP) or `ability` |
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

## Headless test suites

```
godot --headless res://tools/heroes/infrastructure_test.tscn
godot --headless res://tools/heroes/ranged_infra_test.tscn
godot --headless res://tools/heroes/support_infra_test.tscn
godot --headless res://tools/heroes/avery_test.tscn
godot --headless res://tools/heroes/jose_test.tscn
godot --headless res://tools/heroes/feel_test.tscn
godot --headless res://tools/heroes/balance_tools_test.tscn
godot --headless res://tools/heroes/map_switch_test.tscn
godot --headless res://tools/dream_basin/smoke_test.tscn
```

Each exits with the number of failed checks (0 = all passed).
`tools/heroes/capture_feel.tscn` saves screenshots of a finisher swing
(run under a display or `xvfb-run` with `--rendering-driver opengl3`).
