# Bot AI implementation prompts

Copy-ready prompts for building bots smart enough to fill two full teams
(6 v 6) in a real Wake the Dreamer match, so a match can be playtested,
balanced and soak-tested without twelve people. They're written for any
coding model, and assume nothing beyond what's in this repo.

## The idea in one paragraph

Each bot has a **fast brain** and a **slow brain**, sitting on top of the
existing `Hero` control interface (the same one `PlayerHeroInput` drives).
The **slow brain** (strategy, "type 2") thinks every half second or so about
how to win the match: where the Motes are, when to bank or deliver, when to
group, defend a stirring Dreamer or contest the Dream Mote, and whether a
fight is worth taking. It does this per team as well as per bot. The **fast
brain** (tactics, "type 1") runs every tick. It handles the fight in front of
it: who to shoot, where to stand, what to dodge, when to use each ability,
and when to leave. The slow brain sets the goal and how aggressive to be;
the fast brain carries it out, and can overrule it only in an emergency
(about to die, caught in crowd control, a free kill in range).

## How to use these

Run one session and one pull request per phase, and merge each before
starting the next, as with `Implementation prompts.md`. **Every phase is a
plan-first phase:** ask for the plan, read it, then say "go". Paste the
**shared preamble** above every phase prompt.

| Phase | What it adds | You can test it by |
|---|---|---|
| AI0 | Bot controller, perception, navigation, debug overlay | One bot walks the whole Dream Basin, taking jump pads and teleporters, and never gets stuck |
| AI1 | Fast brain: 1 v 1 fighting | A bot of each hero beats a scripted "stand and shoot" opponent, and dodges skillshots |
| AI2 | Slow brain: winning the objective alone | 6 v 6 bots with fights switched off finish a match by waking a Dreamer |
| AI3 | Team fights: fight prediction, focus, peel, engage and retreat | 6 v 6 bots finish matches with realistic kills, and neither side is always stomped |
| AI4 | 6 v 6 fill, difficulty, headless sim and balance CSV | F1 > Match > Fill with bots; batch sims print a per-hero win-rate table |
| AI5 (later) | Item buying | Waits until items exist |

A single-prompt version for models with a long enough context is at the end.

---

## Shared preamble (paste above every phase)

```text
You are working in godot-top-down-project, a Godot 4.7 top-down hero shooter
(GDScript). Read CLAUDE.md first and follow it exactly. Also read:
- docs/HOW_TO_ADD_A_HERO.md (heroes, abilities, the "You want / Use" table)
- docs/OBJECTIVE.md (the match: Wake the Dreamer, Motes, banking/delivering,
  stirring, Lullaby, all MatchRules numbers)
- docs/maps/DREAM_BASIN.md (the map: regions, lanes, jump pads, teleporters,
  one-way ledges, bushes, speed strips)
- docs/BALANCE_TOOLS.md (F1 panel, balance CSV, the full test list)
- "Bot AI Implementation Prompts.md" (this plan: the phases and the rules below)

What already exists and must be reused, not duplicated:
- scripts/heroes/hero.gd: a Hero never reads input. A controller writes
  move_direction, aim_direction and aim_point, and calls
  request_slot(slot, point), release_slot(slot, point), cancel_slot(slot)
  and reload(). scripts/heroes/player_hero_input.gd is the human
  controller; the bot controller is its sibling and must drive the hero only
  through that same interface. No bot may call an ability's internals, move
  the body directly, or skip cooldowns, casts, costs or locks.
- Hero definitions (heroes/<name>/<name>_definition.tres) carry role (TANK,
  CARRY, TEMPO, FLEX), stats, and an AbilityData per slot. AbilityData has
  ability_range, hit_shape, damage, on_hit_status, tags, charge_enabled,
  ally_targeting, tether_range and a values dictionary. Ability exposes
  is_ready(), get_charges(), is_casting(), is_charging(), is_held(),
  get_block_reason(), repeats_while_held(), is_movement_ability().
- scripts/combat/combat_queries.gd: has_line_of_sight() (walls and bushes),
  is_hidden_from(), is_revealed(), team_of(). Bots see only what this says a
  player on their team would see.
- scripts/match/: MatchManager (state, clock, gold, XP, levels, kills,
  respawns, rosters, found with MatchManager.find(tree)), MoteDirector
  (trickle, dreaming zones, Dream Mote), Mote, MoteCarrier (count, value,
  can_deposit, reveal level), Dreamer (wake meter, stir, Lullaby), and their
  signals.
- Special input: Melody's RhythmPerformer (press_note while a phrase plays)
  and Sam's MinigameHost (set_input while a minigame plays). Charge abilities
  need a later release_slot; held abilities repeat while held.

Rules for all bot work:
1. Hero-agnostic core. Nothing under scripts/ai/ may name a specific hero.
   A bot plays a hero by reading its data. Where data can't express how an
   ability should be used, add an optional usage-hint resource to that
   AbilityData. A per-hero script (heroes/<name>/ai/) is the last resort,
   and you must say why in the PR.
2. Fair play. Bots perceive through CombatQueries and the same minimap
   reveal rules players get (MoteCarrier reveal pings, the Dream Mote beam,
   announced zones). No wallhacks, no reading an enemy's cooldowns or
   carried count unless a player could see it, no perfect aim. Reaction
   time, aim error, and how long things are remembered after losing sight
   come from a skill resource.
3. Every number in .tres. Tick rates, weights, thresholds, reaction times and
   aim spread live in resources/ai/*.tres (a BotRules resource plus one
   BotSkill per difficulty), editable live in a new F1 > Bots tab, never
   hard-coded.
4. Two speeds, one owner each. The slow brain (strategy) ticks at
   BotRules.strategy_interval (about 0.5 s, staggered so twelve bots don't
   all think on one frame) and outputs an Intent: a goal (a place, an actor
   or a Dreamer), a stance (AGGRESSIVE, NEUTRAL, AVOID) and a leash. The
   fast brain (tactics) runs every physics tick (with an optional reaction
   delay) and outputs movement, aim and slot presses. The fast brain may
   overrule the Intent only for the emergencies listed in BotRules, and
   must log why in the debug overlay.
5. Decisions are utility scores, not deep if/else trees. Each option adds
   up weighted considerations taken from .tres. Use hysteresis and a minimum
   commit time so bots don't flip between choices. The debug overlay can
   show the top three scores for any bot.
6. Deterministic under a seed. All randomness in bot code goes through one
   RandomNumberGenerator seeded from the match, so a headless sim is
   repeatable.
7. Performance budget. Twelve bots must cost under 2 ms per physics frame
   on average in the headless sim. Spread the expensive queries (paths,
   sight rays, threat scans) over frames and cache results.
8. Tests. Each phase adds a headless test under tools/ai/ (same
   exit-code-is-failure-count pattern as tools/heroes/*_test.tscn), lists it
   in docs/BALANCE_TOOLS.md, and runs the whole list before finishing.
   Scenes, not unit mocks: real heroes, a real map, a real MatchManager,
   with Engine.time_scale raised where that's safe.
9. Docs. Keep a docs/BOT_AI.md: the architecture, how to give a new hero's
   ability usage hints, the BotRules/BotSkill fields (a table like
   OBJECTIVE.md's), and the debug overlay. Add a line to the new-hero
   checklist in HOW_TO_ADD_A_HERO.md: "the bot can play it (AI1 test passes
   for this hero)".
10. Stop and report at the end of the phase: what changed, test results,
    the performance number, and every design question you had to guess at.
    Don't start the next phase.
```

---

## Prompt AI0: controller, perception, navigation

```text
[shared preamble]

Phase AI0: the foundations every later phase stands on. Plan first and wait
for my go-ahead.

1. BotHeroInput (scripts/ai/bot_hero_input.gd): a Node that replaces
   PlayerHeroInput on a Hero and drives it only through the Hero interface.
   Hero gets an exported `bot_controlled` flag (with a BotSkill) next to
   player_controlled; the F1 panel's "Play as" and team swaps must still work
   with bots in the world. The node owns two child brains (empty stubs this
   phase): StrategyBrain and TacticsBrain, plus a Blackboard they share.
   It handles held slots (repeat while held), charge release, reload, and
   routing input to a RhythmPerformer or MinigameHost when one is active,
   so no later phase needs to think about it.

2. Perception (scripts/ai/perception.gd): what this bot's team knows, updated
   on a staggered timer:
   - visible enemies (CombatQueries line of sight from any living teammate:
     vision is shared by team, as for players), with last-seen position,
     velocity and time, forgotten after BotSkill.memory_time;
   - enemies revealed by minimap rules (Mote carrier pings, the Dream Mote
     beam), as a position and a timestamp only;
   - threats in flight: enemy projectiles and ground telegraphs/zones near the
     bot, with predicted impact point and time;
   - objective state anyone can see: loose Motes, active or announced dreaming
     zones, the Dream Mote, both Dreamers' wake meters, stir and Lullaby,
     the match clock;
   - own team state: HP, levels, respawn timers, carried Motes, cooldowns.
   A TeamKnowledge object is shared by all bots on a team, so twelve bots
   don't each cast their own rays.

3. Navigation. There is no navmesh in the project yet. Add a
   NavigationRegion2D baked from the map's collision layers (MapLayers) to
   Dream Basin and Training Grounds, with the actor's radius (50) as agent
   radius. Model the map's special movement as NavigationLink2D (or an
   equivalent graph edge) with a cost: jump pads, teleporters (the one-way
   spawn teleporter included), one-way ledges (down only), stairwells. Speed
   strips lower the cost of an edge. Bushes can be walked through, and the
   bot knows it is hidden in one. Build this from the map's own nodes
   (JumpPad, Teleporter, Ledge, Stairwell, SpeedStrip), not a hand-written
   list, so a new map works without extra work. Add avoidance between
   allies, and stuck recovery (no progress for BotRules.stuck_time: repath,
   then nudge).

4. Debug overlay (F1 > Tools > Bot overlay, and the M map view): per bot,
   the current path, the Intent and stance, the fast brain's current target
   and action, and why it last overruled the Intent. It draws for the local
   view only and never changes gameplay.

5. BotRules (resources/ai/bot_rules.tres) and three BotSkill resources:
   easy, normal, hard (reaction time, aim error, dodge chance, memory,
   ability-timing accuracy). An F1 > Bots tab edits them live.

Tests (tools/ai/bot_nav_test.tscn): a bot in Dream Basin visits every
region's centre in turn, from both spawns, reaching each within a time
limit. At least one route must be cheapest via a jump pad and one via a
teleporter, and the bot must take them. A bot pushed into a corner
recovers. A bot controller swapped onto and off a hero at runtime leaves
no stuck held slot. Record the perception and nav cost for twelve bots.
```

## Prompt AI1: the fast brain (1 v 1)

```text
[shared preamble]

Phase AI1: TacticsBrain, the fast "type 1" layer that wins 1 v 1 engages
and later carries out team fights. Plan first and wait for my go-ahead.

The fast brain takes the Intent's stance and leash as given, and every tick
picks one action: fight, reposition, dodge, disengage, or follow the path.

1. Ability understanding, built from data. Write an AbilityProfiler that
   reads each AbilityData (and the Ability script's class) and derives:
   effective range, hit shape, projectile speed, cast/windup time, damage at
   the hero's level, CC applied (on_hit_status: stun, root, slow,
   displacement), mobility (is_movement_ability, dashes, launches), heals,
   shields, ally targeting, zones, charge behaviour. Where that isn't enough,
   an optional AbilityAIHint resource on AbilityData says what the ability
   is for: DAMAGE, POKE, ENGAGE, ESCAPE, PEEL, HEAL_ALLY, SHIELD, CC, ZONE,
   OBJECTIVE (e.g. jostle a carrier), SELF_BUFF. It also carries simple
   conditions: min/max target distance, "only if target is CC'd", "only
   below X% HP", "hold for combo after slot Y", "save for escape". Give every
   existing hero hints only where the profiler can't work it out. Add the
   AbilityAIHint row to the "You want / Use" table, and a hinted ability to
   the ranged_test hero.

2. Target selection: a utility score over visible enemies: kill potential
   (effective HP left vs our burst), threat to us, distance and
   reachability, whether they carry Motes (weighted by carried value), CC on
   them, and an ally already committed to them.

3. Spacing and movement: keep the distance your kit wants against theirs
   (ranged kites melee, melee closes on ranged), strafe while shooting, use
   cover and bush edges to break line of sight while reloading or on
   cooldown, and don't stand in enemy zones. The Resolve rule
   (CC after CC is shorter) is a reason to delay a follow-up stun.

4. Dodging: when Perception predicts a projectile or telegraph will hit, step
   out of it sideways, with BotSkill.dodge_chance and reaction delay. Spend
   a movement ability to dodge only if the hit is worth it (big damage or
   CC).

5. Aim: lead moving targets using projectile speed, with BotSkill aim error
   that grows with target speed and distance. Charge abilities release at
   a ratio chosen by distance and the skill's accuracy. Perfect-release
   windows are hit with a skill-based chance.

6. Engage and disengage in 1 v 1: estimate a duel (our effective HP and DPS
   over the next few seconds, with cooldowns ready, against theirs) and
   commit, poke or leave. Disengage early enough to get away, using escape
   abilities, bushes and allies. A carrier with a large stack is more
   careful, since dying drops every Mote.

Tests (tools/ai/bot_duel_test.tscn):
- For every hero in the roster (read the list from the hero folders, don't
  hard-code it), a normal bot at level 5 fights a scripted opponent of the
  same role that walks straight in and holds fire, in an open arena. The
  bot must win a clear majority over seeded runs.
- A bot dodges a slow skillshot fired at it from range, most of the time
  on hard, less on easy.
- Ranged vs melee: the ranged bot keeps its preferred distance most of the
  time in a 20 s window.
- A low-HP bot disengages rather than trading to death, when it could
  escape.
- Every ability of every hero gets used at least once across the runs
  (no dead slots), including charged, held, ally-targeted, rhythm and
  minigame abilities.
Print a per-hero win-rate table. A hero that can't pass is a hint problem;
report which.
```

## Prompt AI2: the slow brain (the objective)

```text
[shared preamble]

Phase AI2: StrategyBrain and a TeamStrategist, the slow "type 2" layer that
plays the match to win it. Plan first and wait for my go-ahead.

1. TeamStrategist (one per team, a node under the MatchManager's world)
   ticks at BotRules.team_interval. It reads TeamKnowledge and match state
   and gives every bot a role and a goal:
   - FARM a region (spread bots over trickle points and dreaming zones, near
     enough to help each other; prefer unseen spawn points like the
     MoteDirector does);
   - CARRY/DELIVER: when to take a stack to the enemy Dreamer vs bank at
     home. That depends on stack size vs the reveal steps
     (MatchRules.reveal_values), the enemy's last-seen positions, the
     enemy's wake meter vs yours, the Sweet Dreams threshold, and whether
     escorts are free;
   - ESCORT a carrier and HUNT an enemy carrier (the reveal pings make this
     possible; jostling with a displacement ability counts);
   - CONTEST the Dream Mote (announced early: be there on time, grouped);
   - DEFEND and SING THE LULLABY when our Dreamer stirs (everyone in the
     ring beats heroics elsewhere; respawning defenders go straight back),
     and ATTACK a stirring enemy Dreamer: deliver the final Mote after
     the grace period, and deny their Lullaby by standing in the ring;
   - GROUP UP before a planned move (the Dream Mote, a push, a defence);
   - RETREAT/RESET when outnumbered or low, and wait for respawns.
   Each goal is a utility score from .tres weights. The team plan keeps a
   minimum commit time. Roles take the hero's role into account (TANK
   escorts and defends, CARRY farms and delivers, TEMPO hunts and jostles,
   FLEX fills gaps), but only as weights, never as fixed rules.

2. StrategyBrain (per bot) takes its team goal, adds personal factors (HP,
   carried value, level, cooldowns of its key abilities), turns it into an
   Intent (goal, stance, leash) for the fast brain, and plans the path.
   It decides when to go back to heal, and uses the spawn teleporter when
   that's shorter.

3. Match timing: play the clock. The late match (MatchRules.late_match_time,
   Motes worth double), a stir that is about to time out, and a Lullaby that
   is nearly done all change the scores.

4. Add a "strategy only" BotRules switch that turns fights off (bots don't
   shoot, abilities used only to move), so the macro layer can be tested on
   its own.

Tests (tools/ai/bot_macro_test.tscn), 6 v 6 in Dream Basin, headless, raised
time scale:
- With fights off, a match reaches a woken Dreamer within a time limit. Both
  teams bank and deliver, and neither team leaves Motes lying for long.
- A team whose Dreamer stirs sends at least four living bots to its ring
  within a few seconds, and finishes a Lullaby when uncontested.
- When a Dream Mote is announced, at least three bots from each team reach
  the Cradle before it spawns.
- A bot carrying a big stack with enemies seen between it and the enemy
  Dreamer banks at home instead of running the gauntlet.
- Determinism: the same seed gives the same match result twice.
```

## Prompt AI3: team fights

```text
[shared preamble]

Phase AI3: the two brains together in 3 v 3 to 6 v 6 fights. This is where
type 1 and type 2 meet. Plan first and wait for my go-ahead.

1. FightPredictor (shared by both layers): for a group of allies and a group
   of enemies that could meet within a few seconds, estimate the outcome
   from each side's effective HP (shields and resistances included), DPS
   over the next few seconds at their levels, ready cooldowns (ours known;
   theirs from what we saw them spend), CC and burst, heals, distance to
   join (respawn timers, travel time), and position (choke points, high
   ground, our Dreamer's ring). Output: win probability and expected cost.
   The slow brain uses it to pick fights to take and avoid (stance). The
   fast brain re-runs it cheaply while the fight goes on, to decide when to
   stay and when to get out.

2. Team-fight tactics in the fast brain, coordinated through TeamKnowledge
   (a lightweight "call" board, not telepathy beyond what a voice-chat team
   would have):
   - focus fire: prefer the target an ally is already on, when it's killable;
   - engage: a bot with an ENGAGE ability starts the fight only when the team is
     in range to follow up; others hold abilities for the follow-up and
     chain CC around Resolve;
   - peel: protect the carrier and low-HP allies from divers, save CC and
     shields for that;
   - frontline and backline spacing by role and range; don't bunch against
     area damage;
   - heal and shield allies by need, with ally-targeted abilities;
   - retreat together: when the prediction flips, fall back towards allies
     or our Dreamer, and cover the slowest;
   - chase with limits: don't chase past the leash into the enemy base or
     away from the objective;
   - the objective in a fight: jostle enemy carriers, grab dropped Motes
     once it's safe, don't die with a big stack.

3. Carriers change fights: the team with a carrier in it fights to protect
   the stack, and the team facing a carrier plays for the jostle and the
   kill.

Tests (tools/ai/bot_teamfight_test.tscn):
- 3 v 3 with one side two levels higher: the higher side wins most seeded
  fights, and the lower side, if its AVOID stance lets it, disengages
  instead of dying to a bot.
- A 3 v 3 where one side's TANK engages: the rest follow within
  BotRules.follow_up_window.
- 6 v 6 full matches (fights on), easy vs easy, normal vs normal, hard vs
  hard: every match ends in a result, kills and deaths are in a sane band,
  and neither side wins more than BotRules says is suspicious over the
  seeds.
- Hard beats easy in most full matches.
- The frame-time budget holds with twelve bots in a fight.
```

## Prompt AI4: 6 v 6 fill, difficulty and the sim

```text
[shared preamble]

Phase AI4: make bots a playtest and balance tool. Plan first and wait for my
go-ahead.

1. F1 > Match > "Fill with bots": fill both teams to BotRules.team_size (6)
   around the player, choosing heroes by a composition rule in .tres (e.g.
   at least one TANK per team, no duplicates unless the roster is short),
   with a difficulty per team. Options: "Player is a bot too" (spectate),
   swap any bot's hero or difficulty, kick. Bots respawn and level through
   the MatchManager like players.

2. Headless batch sim: tools/ai/bot_sim.tscn takes arguments (number of
   matches, seed, team comps or "random", difficulties, time scale) and
   writes CSV to balance/sims/: one row per match (seed, comps, winner,
   duration, how it ended) and one row per hero per match (kills, deaths,
   assists, gold, XP, damage, healing, Motes banked and delivered, jostles).
   Add a summary: per-hero win rate, pick-matched by role, and a flag for
   any hero outside a band. Hook it into docs/BALANCE_TOOLS.md next to the
   existing balance CSV.

3. Soak: a long-run mode that runs back-to-back matches and fails on any
   error, warning spam, leaked node or growing memory.

Tests (tools/ai/bot_fill_test.tscn): fill gives 6 v 6 with the composition
rule met; a 10-match batch at a fixed seed writes the CSVs with the right
columns; the soak mode runs 3 matches clean.
```

## Prompt AI5 (later): buying items

Items don't exist yet. When they do, run this after the item phase has
merged.

```text
[shared preamble]

Phase AI5: bots buy items. Read the item docs and data first. Plan first and
wait for my go-ahead.

- A ShopPlanner in the slow brain decides when to shop (next time at base,
  or on death), and what to buy. It reads the bot's gold from MatchManager.
- Builds are data: a BotBuild resource per hero (or per role, as a fallback)
  lists core items and situational swaps, with the conditions for each
  ("enemy team has 2+ healers", "we're behind in kills", "I'm the carrier").
  No build logic in code that names an item or a hero.
- Items change FightPredictor's numbers through the same stat pipeline the
  heroes use, so the fast brain automatically fights better with them.
- The sim CSV gains item columns (build, time of each purchase), so item
  balance can be simmed like hero balance.
Tests: a bot with enough gold buys its core item on its next base visit; a
situational swap triggers when its condition is met; a sim batch with items
completes.
```

---

## Single-prompt version

For a model that can hold the whole job at once. It still works in phases,
but on one branch, stopping after each phase for review.

```text
[shared preamble]

Build bots that can fill a 6 v 6 Wake the Dreamer match well enough for
playtesting and balance sims. Work in the phases below, in order. After
each phase, run every test, commit, and stop to report before starting the
next. Show me your plan for the whole thing first and wait for my go-ahead.

Architecture: each bot has a slow brain (type 2: strategy, about every
0.5 s, per team and per bot) that decides how to win the match and outputs
an Intent (goal, stance AGGRESSIVE/NEUTRAL/AVOID, leash); and a fast brain
(type 1: tactics, every tick) that wins the fight in front of it (targeting,
spacing, dodging, aim, ability timing, engage and disengage), and overrules
the Intent only in listed emergencies. Both score options by utility with
.tres weights, with hysteresis. A FightPredictor shared by both decides
which fights are worth taking. Bots drive heroes only through the Hero
control interface, perceive only what their team could see, and read hero
kits from data (AbilityData plus optional AbilityAIHint resources), never
from hero names.

AI0 controller, perception, navmesh with jump pad/teleporter/ledge links,
    stuck recovery, debug overlay, BotRules and BotSkill resources.
AI1 fast brain: 1 v 1 for every hero; dodge, aim lead, spacing, ability
    use from data, duel prediction. Every slot of every hero gets used.
AI2 slow brain: TeamStrategist roles (farm, carry, deliver or bank,
    escort, hunt carriers, contest the Dream Mote, defend with the Lullaby,
    attack a stirring Dreamer, regroup), per-bot Intents, match-clock
    awareness, a fights-off switch for testing.
AI3 team fights: FightPredictor, focus, engage with follow-up, CC chains
    around Resolve, peel, heals, retreat together, chase leash, carriers.
AI4 F1 "Fill with bots" (6 v 6, comp rule, difficulty per team, spectate),
    headless batch sim writing CSV to balance/sims/ with per-hero win rates,
    and a soak mode.
Leave a ShopPlanner hook in the slow brain (does nothing yet) for item
buying later.

Use the test lists from each phase in "Bot AI Implementation Prompts.md".
```

---

## Notes for you, the design owner

- **Questions you'll probably be asked,** worth answering in `docs/BOT_AI.md`
  once decided: how much bots on a team "talk" (the call board: pings only,
  or full plans?); whether hard bots may time enemy cooldowns they saw spent
  (a good player would); a target win-rate band for the sim to flag; and
  whether bots take the one-way spawn teleporter, which exits in the Hollow.
- **Why data-driven hints and not per-hero AI:** with a dozen heroes plus six
  on the way, a per-hero brain each would be the "six copies of similar
  scripts" problem this repo was built to avoid. A new hero should get a
  playable bot by adding a few AbilityAIHint lines to its `.tres`.
- **Why fairness matters here:** bots are for balance. A bot that sees
  through bushes makes stealth heroes look weak, and perfect aim makes
  skillshot heroes look strong. The skill resource is what keeps the sims
  honest, so check the win-rate table at more than one difficulty before
  trusting it.
