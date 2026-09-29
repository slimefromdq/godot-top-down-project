# Menus and match flow

The game starts on the main menu (`scenes/ui/main_menu.tscn`). Every scene
change between menus and matches goes through one autoload, **GameState**
(`scripts/flow/game_state.gd`).

```
Main menu ─ Play ──> Match setup ──> Hero select ──> Match ──> End screen ─┐
          ├ Practice ─────────────> Hero select ──> Training grounds       │
          ├ Settings (overlay)                                             │
          └ Quit                  <────────── Back to menu / Leave match ──┘
```

## The pieces

| What | Where | Notes |
|---|---|---|
| Scene flow | `scripts/flow/game_state.gd` (autoload `GameState`) | `goto_*()`, `launch()`, `leave_match()`, `finish_match()` |
| Match settings | `scripts/flow/match_config.gd`, defaults in `resources/match/default_match_config.tres` | mode, team size (6), bot fill, bot difficulty, map list, hero select timer (30 s), bot pick interval, start delay |
| Match setup | `scenes/ui/match_setup.tscn` | Online lobby is listed but disabled (stub) |
| Hero select | `scenes/ui/hero_select.tscn` (screen), `scripts/flow/hero_draft.gd` (rules) | grid, details, Lock In, timer, both teams' picks |
| Bot picks and spawning | `scripts/ai/bot_draft.gd` | shared with the F1 Bots tab's "Fill with bots" |
| Settings | `scripts/flow/settings_panel.gd`, `scripts/flow/user_settings.gd` | volumes (Master, Music, SFX buses) and fullscreen, saved to `user://settings.cfg` |
| Pause (Esc) | `scripts/flow/pause_menu.gd` | Resume, Settings, Leave match; added by `world.gd` |
| End of match | `scripts/flow/end_match_screen.gd` | Victory/Defeat, the **MVP** (best score on the winning team) and the **ACE** (best on the losing team) in spotlight cards, a scoreboard of both teams (K/D/A, damage dealt and taken, healing, Motes banked/delivered, gold), Play again, Back to menu. Scores are `MatchRules.mvp_score` (weights in `MatchRules` > MVP); the stats come from `MatchManager.Record`. |

## How a match is launched

`GameState.launch()` instances the map's world scene, sets the `Player`
node's `definition` to your pick **before** the scene enters the tree (a Hero
applies its definition in `_enter_tree`), switches to it, then spawns the
picked bots with `BotDraft.spawn_bot()`. Worlds opened directly (F5, the
headless tests, F3 map switching) are untouched: `GameState.in_launched_game`
is false, and the old "DAWN VICTORY" screen still shows.

## Hero select rules (HeroDraft)

- You are slot 1 of Dawn. Bots lock in one at a time
  (`bot_pick_interval`), enemy and ally in turn, using the role mix in
  `BotRules.team_composition`.
- No hero twice on one team. An ally bot avoids the hero you're looking at;
  if you lock a hero a bot already has, that bot picks again. Teams may
  mirror each other.
- When the timer runs out you're locked into the hero you're looking at (a
  random free one if none), and any bots still waiting lock in at once.
- With bot fill off, the other slots stay empty.

## Hooks for later

- **Stats and progression:** `GameState.match_finished(result)` fires when a
  launched match ends; `GameState.last_result` keeps it. `result` has
  `winner`, `player_team`, `won`, `duration` and `heroes` (one row per hero:
  `hero_id`, `name`, `team`, `is_player`, `kills`, `deaths`, `assists`,
  `motes_banked`, `motes_delivered`, `gold`).
- **Motes banked/delivered** are counted per hero in `MatchManager.Record`
  (from each Dreamer's `deposit_finished`), in Mote value.
- **Online lobby:** `MatchConfig.Mode.LOBBY` exists and is disabled in the
  setup screen.
- **More maps:** add a name and world scene to `map_names` / `map_scenes` in
  the default config.

Test: `godot --headless res://tools/flow/flow_test.tscn`.
