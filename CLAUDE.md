# CLAUDE.md

Godot 4.7 top-down hero shooter. Read `docs/HOW_TO_ADD_A_HERO.md` before
touching a hero, `docs/VISUALS_AND_AUDIO.md` before touching looks or sound,
and `docs/BALANCE_TOOLS.md` for the debug panel, CSV export and test list.
The current design work is in `Six New Heroes Implementation Plan.md` and
its phase prompts in `Implementation prompts.md`.

## Heroes are data plus small scripts

- Before writing any new ability script, check the "You want / Use" table in
  `docs/HOW_TO_ADD_A_HERO.md` and use a row if one fits. Write a script only
  where no row fits.
- Any new reusable system gets a row in that table and a case in the test
  hero `tools/heroes/ranged_test/` (a data-only hero you can play from
  F1 > Play as), plus a headless check in the matching
  `tools/heroes/*_infra_test.gd` so it can be tested alone.
- Shared systems (`scripts/`) must never reference a specific hero.
- Hero scripts copied from the template don't use `class_name`.

## Numbers, visuals, sound

- All tuning numbers live in `.tres` resources (ability data, statuses,
  `resources/rules/game_rules.tres`), never hard-coded in scripts. A number
  a script needs goes in the ability's `values` dictionary.
- Visuals and sounds go through cues and profiles (`VisualProfile`,
  `AudioProfile`, status `attached_vfx`), never gameplay code.

## Stats

- Stats are authored on the 20-level `StatScaling` range while matches cap
  at level 10 (`GameRules.max_level`).
- Linear growth = (L10 value - L1 value) / 9.
- Check every new hero in the balance CSV against a hero of the same role.

## Tests

- Every hero has `tools/heroes/<name>_test.tscn`, run with
  `godot --headless res://tools/heroes/<name>_test.tscn`. It exits with the
  number of failed checks (0 = all passed).
- Before finishing any task, run every test listed in `docs/BALANCE_TOOLS.md`
  (keep that list complete when you add a test).
- On a fresh clone, run `godot --headless --import` once first.
- If `godot` isn't on PATH (cloud sessions), install the matching build:
  `Godot_v4.7.1-stable_linux.x86_64.zip` from the godotengine/godot GitHub
  releases, copied to `~/.local/bin/godot`.
