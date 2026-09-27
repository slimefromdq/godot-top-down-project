# Bot AI

`Hero.bot_controlled` attaches `BotHeroInput` to any hero, and
`set_bot_controlled()` can swap control at runtime. The bot writes
`move_direction`, `aim_direction`, and `aim_point`, then uses `request_slot`,
`release_slot`, and `reload`. Abilities still enforce their normal casts,
cooldowns, costs, and locks.

F1 > Bots fills each team to six, keeps the local player in the roster, selects
a tank for each team where the roster allows it, sets Easy/Normal/Hard, and
edits `BotRules` and the selected `BotSkill` live. F1 > Tools > Bot overlay draws goals, paths, targets,
intents, and actions in the world and the M map view.

## Decisions

Every physics tick the bot follows its current goal, positions for its
primary range, aims with skill-dependent error, uses abilities whose data
allows the target, reloads, releases charged or held slots, and plays rhythm
notes. The minigame host's own bot control handles an occupied hero. A
slower strategy tick chooses visible Motes, delivery, banking, Dreamer
defence, retreat, a visible enemy, or patrol. Enemy perception uses
`CombatQueries` from living teammates; an enemy that leaves sight is
remembered only for `BotSkill.memory_time`. Projectiles and enemy ground
zones trigger dodges when seen. Random choices use a seeded
`RandomNumberGenerator` per bot.

`BotNavigation` shares one obstacle graph per map. It samples map collision
with a 50 pixel actor radius and adds directed edges from the map's `JumpPad`
and `Teleporter` nodes. Bots follow graph waypoints and steer around dynamic
obstacles. The graph is rebuilt when a new map is loaded.

| Resource | Key fields | Purpose |
| --- | --- | --- |
| `resources/ai/bot_rules.tres` | intervals, ranges, health thresholds, goal and target weights, navigation size and link cost, ability timing, dodge thresholds | Shared live tuning |
| `resources/ai/easy.tres`, `normal.tres`, `hard.tres` | reaction time, aim error, memory, dodge chance, ability timing accuracy | Per-bot difficulty |

## Tests and limits

Run the three scenes in `tools/ai/`: `bot_test.tscn` checks control,
perception, projectile dodge, fill, and overlay; `bot_nav_test.tscn` checks
Dream Basin routes including jump pad and teleporter edges;
`bot_match_smoke_test.tscn` runs twelve bots on Dream Basin and prints
controller time. Ledges are currently treated as blocking in both directions
by the graph; bots route around them or take a jump pad. The controller does
not yet coordinate team fights or produce balance simulation CSVs, so match
win rates should not be used for hero balance decisions.
