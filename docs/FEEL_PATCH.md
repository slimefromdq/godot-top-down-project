# The "feel" patch

One patch that makes the game snappier, faster and easier to read. Every
number is data (a `.tres` or an `@export` default); nothing here is hard-coded
in gameplay code.

| Area | What changed | Where |
|---|---|---|
| **Latency** | Mouse and pad events are handled as they arrive (no merged event per frame). Hitstop 1.0 -> 0.6 and camera nudge 1.0 -> 0.8 by default, so impacts stall the sprites less. Performance changes are listed under "Performance" below. | `game_feel.gd`, `feel_settings.gd` |
| **Overperformers** | Hazmat: health 855 +90/lvl -> 810 +84, magic growth 5.56 -> 5.0, armor 40 +3.9 -> 38 +3.5. Pike: health 504 +49 -> 480 +46, weapon growth 6.11 -> 5.6, armor growth 1.78 -> 1.6. Avery: health 648 +64.8 -> 612 +60.8, weapon growth 4.0 -> 3.6, magic growth 5.0 -> 4.5. | `heroes/<hero>/<hero>_definition.tres` |
| **Gold** | Kill 150 -> 300, assist 60 -> 120, passive 2 -> 2.5 per second. | `MatchRules` > Economy |
| **Mote Island** | Found from 14 tiles (was 10), fully visible from 6 (3), usable from 2.5 (1.5); visitors stay 18 s (12); the cache holds 12 Motes (8); the portal moves every 150 s (180). | `MapEventRules` > Mote Island |
| **Wanderer** | 2 Motes per hit (1), up to 12 (6), drop cooldown 0.15 s (0.25), appears at 1:30 (2:00) and every 100 s (120), flees at 480 (540). | `MapEventRules` > Wanderer |
| **Bots and Motes** | Every role deposits a smaller stack (6 to 7 Motes, was 8 to 10). The carry (Farm) plan delivers to the enemy Dreamer once it is 25% awake (60%) or from level 4 (7). Bots run the gauntlet past up to 3 guards before falling back to banking (was 1 to 2). | `resources/ai/roles/*.tres` |
| **No ammo** | `GameRules.ammo_enabled` is off: guns ignore `magazine_size`, so nothing reloads, there is no dry click and the HUD shows no count. REGEN guns (Cosmo's moons, Pike's knives) keep their regenerating charges: those are the heroes' own mechanic and never reload. The ammo code stays for modes that turn it back on. | `game_rules.tres`, `RangedAttackAbility.get_max_ammo()` |
| **Gun balance** | Jose and Nimbus were the only heroes whose guns reloaded, so with no ammo their sustained damage would have nearly doubled (Jose 151 -> 287, Nimbus 134 -> 209 at level 10). Their primaries were trimmed to land at about +30% / +25% (Jose 16.2 + 40.5% Weapon per round, was 22 + 55%; Nimbus 1.38 x Weapon per round, was 1.6). The balance CSV's `sustained_dps` now equals `burst_dps` for magazine guns. | `twin_longarms.tres`, `umbrella_rifle.tres`, `RangedAttackData.get_balance_metrics` |
| **Cast skillshots** | Rocco, Jose, Nimbus, Mochi, Catgirl, Computer and Horace: projectile radius x1.35, range (lifetime) x1.15, melee and area hit shapes x1.12 to x1.2, damage x1.08, gun falloff ranges x1.15, Haymaker's dash 450 -> 495 px, Dragonfire's reach 900 -> 1100 px. | `heroes/<hero>/data/*.tres`, `abilities/*.tres` |
| **New visuals** | A glowing comet trail on Nimbus's, Mochi's, Catgirl's, Computer's and Horace's projectiles (`CometTrail`, one small scene each); Rocco's punches, slams and Main Event fire a ring burst with a bit of shake. | `scripts/visuals/comet_trail.gd`, `heroes/<hero>/vfx/comet_*.tscn`, `rocco_visuals.tres` |
| **Gaps** | Dream Basin has no slit narrower than a hero's body (104 px) that isn't shut: `tools/dream_basin/gaps.py` finds them, `layout.py` shuts them with a short wall of the same kind (40 bridges), the Glasshouse's back pane is widened to meet its sides, and `check.py` fails while any are left. | `tools/dream_basin/` |
| **Shop** | A new layout: header with a status chip, the catalog, a details card, and your slots. See `ITEMS_AND_SHOPS.md`. | `scenes/hud/shop_panel.gd` |
| **Kill feedback** | A sharp chime (pitch climbs with your streak) and a crosshair marker with the victim's name and gold, DOUBLE / TRIPLE / QUADRA / PENTA KILL callouts, and a smaller marker for assists. See `VISUALS_AND_AUDIO.md`. | `scenes/hud/kill_feedback.gd`, `kill_confirm.tres` |
| **MVP screen** | After the match: the MVP (best score on the winning team) and the ACE (best on the losing team), a full scoreboard, Play again. The screen now shows for every match with a `MatchManager`, not only launched ones. Score weights are `MatchRules` > MVP. | `end_match_screen.gd`, `match_rules.gd` |

Test: `godot --headless res://tools/match/feel_patch_test.tscn` covers ammo,
the economy and event defaults, the bot plans, the kill marker, the MVP stats
and screen, and the shop window. The gap check is
`python3 tools/dream_basin/gaps.py` (also part of `check.py`).
