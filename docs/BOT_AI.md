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
notes. The minigame host's own bot control handles an occupied hero. Enemy
perception uses `CombatQueries` from living teammates; an enemy that leaves
sight is remembered only for `BotSkill.memory_time`. Projectiles and enemy
ground zones trigger dodges when seen. Random choices use a seeded
`RandomNumberGenerator` per bot.

### Roles

The hero's `HeroDefinition.role` picks a `BotRolePlan` from `BotRules`
(`resources/ai/roles/*.tres`). Plans are weights, not scripts: every bot
still defends a stirring Dreamer, grabs Motes it passes and fights back.

| Role | Job | Plays like |
| --- | --- | --- |
| Tank | ESCORT | Stays with the teammate carrying the most Motes (one tank per carrier), contests the Dream Mote, delivers its own stacks to the enemy Dreamer. With no carrier to guard it hunts big enemy stacks nearby, then roams. |
| Carry | FARM | Roams the Mote spawns on its own half, fights only what comes close (small `engage_radius`), and banks at home for XP and gold. Delivers instead once it reaches `deliver_from_level` or the enemy's wake meter passes `deliver_when_enemy_wake`. |
| Tempo, Flex | PLAYMAKER | Hunts revealed enemy carriers (at most `max_hunters` per carrier), joins teammates' fights within `assist_radius`, escorts carriers, scouts the enemy half. Delivers its stacks. |

### Strategy tick

Every `strategy_interval`, in order: defend a stirring home Dreamer; deliver
the winning Mote to a stirring enemy Dreamer after its grace (or stand in its
ring to pause the Lullaby); retreat when below the plan's health threshold
with an enemy in sight, to the team's healing spawn area, and stay there
until `retreat_until_fraction` health; bank when hurt (if home is nearer than the enemy
Dreamer); take a stack of `deposit_value` to a Dreamer (bank or deliver by
the plan, banking instead when `gauntlet_enemies` wait at theirs); the role's
job; the Dream Mote (at the Cradle for the warning, chased while loose); the
nearest visible Mote; and otherwise **roam**: go to the Mote spawn the team
has gone longest without seeing (`unseen_weight`), on the plan's side of the
map (`enemy_half_bias`), away from teammates' roam goals (`spread_radius`).
There is no idle or "wait in the middle" state.

Bots on a team share claims through `BotHeroInput.goal_key` (`mote:<id>`,
`roam:<index>`, `escort:<id>`, `hunt:<id>`), so two bots don't chase the same
Mote or scout the same spawn. Known enemy carriers are those in sight plus
revealed ones (`MatchRules.reveal_values`), updated at their minimap ping
rate.

### Fighting

A visible enemy becomes the target only inside the plan's `engage_radius`;
the bot keeps it until it passes `chase_radius`. Whoever hit the bot in the
last `self_defence_time` seconds, a hunted carrier, and attackers near a
defended Dreamer are always fair game. Travelling bots (deliver, bank,
retreat) shoot on the move instead of turning to chase and keep their
movement abilities for travel; an escort turns to fight only near its
carrier. This keeps fights local instead of every bot converging on the
nearest brawl.

### Ultimates

In a match every hero starts with no ultimate and charges it by playing (see
[OBJECTIVE.md](OBJECTIVE.md#ultimate-charge)). A bot tries its ultimate like
any other slot once it is charged.

### Fill

F1 > Bots fills each team to `team_size` following `BotRules.team_composition`
(by default tank, carry, tempo, flex, carry, tank), keeping the local player
in the roster. Dusk picks from the other end of the hero list so mirror
matches differ.

`BotNavigation` shares one obstacle graph per map. It samples map collision
with a 50 pixel actor radius and adds directed edges from the map's `JumpPad`
and `Teleporter` nodes. Bots follow graph waypoints and steer around dynamic
obstacles. The graph is rebuilt when a new map is loaded.

| Resource | Key fields | Purpose |
| --- | --- | --- |
| `resources/ai/bot_rules.tres` | intervals, ranges, health thresholds, Mote and target weights, navigation size and link cost, ability timing, dodge thresholds, roaming, team composition, the four role plans | Shared live tuning |
| `resources/ai/roles/tank.tres`, `carry.tres`, `tempo.tres`, `flex.tres` (`BotRolePlan`) | job, engage and chase radius, retreat health, deposit value and bank/deliver choice, roaming bias and spread, escort, assist and hunt settings | Per-role behaviour |
| `resources/ai/easy.tres`, `normal.tres`, `hard.tres` | reaction time, aim error, memory, dodge chance, ability timing accuracy | Per-bot difficulty |

## Tests and limits

Run the four scenes in `tools/ai/`: `bot_test.tscn` checks control,
perception, projectile dodge, fill, and overlay; `bot_role_test.tscn` checks
engage radii per role, the strategy decisions (roam, escort, bank or deliver,
hunt with a hunter cap, Mote claims, defend) and that twelve bots with fights
off spread out over the map; `bot_nav_test.tscn` checks
Dream Basin routes including jump pad and teleporter edges;
`bot_match_smoke_test.tscn` runs twelve bots on Dream Basin and prints
controller time. Ledges are currently treated as blocking in both directions
by the graph; bots route around them or take a jump pad. The controller does
not yet plan team fights (grouping for a push) or produce balance simulation
CSVs, so match win rates should not be used for hero balance decisions.
`tools/ai/capture_bots.tscn` (under `xvfb-run`, see BALANCE_TOOLS.md) saves
screenshots of a bot match and prints every bot's intent after 25 seconds.
