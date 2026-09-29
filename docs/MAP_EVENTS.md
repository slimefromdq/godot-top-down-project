# Map events: the Black Market, the Mote Island, the Wanderer

Three side systems that give the match places and moments to fight over
without touching the main objective. They add **no** change to the Mote
trickle, the dreaming zones, the Dream Mote or the banking rules: every Mote
they make is tagged with its source and counted by the **Mote ledger**, so you
can check they stay a side dish.

Everything is data. **All tunables are in one resource,
`resources/rules/map_events.tres`** (`MapEventRules`, referenced by
`MatchRules.map_events`), including the market's stock and the Wanderer's
body. The names mirror the design spec (`BLACKMARKET_OPEN_TIME` is
`blackmarket_open_time`). Each match works on a private copy, so F1 edits
never touch the file. To get the shipped defaults back, run
`godot --headless res://tools/events/build_map_events.tscn`.

Tests: `tools/match/map_events_test.tscn` (everything here) and the temp-item
checks in `tools/heroes/infrastructure_test.tscn`.

## Structure

`MatchManager` adds a **`MapEvents`** node (like the Mote and Objective
directors). Under it: `BlackMarketDirector`, `IslandDirector`,
`WandererDirector`, `MoteLedger`. All state lives in the directors; the HUD
(`MapEventsHud`, `BlackMarketPanel`), the drawn nodes and the cues only read it
and call `purchase()`, `request_enter()`, `request_leave()`. There is no
networking in the project yet, so this is "server-authoritative shaped": the
schedules are pure functions of the match clock and the **match seed**
(`MatchManager.match_seed`, `make_rng()`, `seeded_int()`), so a server can own
the directors and clients mirror them, and a clock jump lands on the right
state. Set `match_seed` (before `_ready`) to replay a match's events.

The map supplies the places as `Marker2D`s in groups (Dream Basin gets them
from `tools/dream_basin/layout.py`, checked by `check.py`):

| Group | What |
|---|---|
| `blackmarket_spawn` | Where the stall can open. Left or right of the map's centre decides the edge. Dream Basin: one per edge, mirrored. |
| `island_portal_spawn` | Hidden nooks for the Island portal (10 on Dream Basin, mirrored). |
| `mote_spawn` (or `wanderer_spawn`) | Where the Wanderer can appear (the trickle's open, reachable points). |

A map without markers simply runs without that event.

## Black Market

Opens at 5:00 (`blackmarket_first_spawn_time`) on the far left or right edge
(seeded per window, may repeat), stays `blackmarket_open_time` (90 s), is gone
`blackmarket_closed_time` (60 s), and comes back. Everyone gets a banner and
an off-screen arrow and a minimap icon while it is open, and a pill under the
clock with the despawn countdown (also drawn over the stall).

**Shopping.** Stand within `blackmarket_interact_radius` and press the interact
key (**X**, `map_interact`). Items cost **carried Motes and gold**. The Motes
come out of your stack (least valuable first, never a Dream Mote), so they are
not banked. Refused if you lack either. Each hero buys each item at most
`blackmarket_max_per_item` (1) times per open window. Taking damage closes the
window (`blackmarket_close_on_damage`), as does walking away, dying, or the
market closing.

**Temporary items** take no item slot and end on death or their timer
(`blackmarket_item_duration` 60 s unless the item sets its own). They are
`BlackMarketItem`s: a `StatusEffect` for numbers and, for what a status can't
do, a small `TempEffect` script whose numbers are in the item's `values`.

| Item | Cost (Motes + gold) | Does | Built from |
|---|---|---|---|
| Overclock | 3 + 350 | +40% fire rate, +20% move speed | status only |
| Glass Cannon | 4 + 400 | +50% weapon/magic damage, -30% max HP | status only (`cleansable = false`) |
| Phase Cloak | 3 + 300 | invulnerable dash, then 5 s unseen by enemies | `PhaseCloakEffect` + status (`invisible`, `body_alpha`) |
| Mote Magnet | 2 + 250 | loose Motes pulled to you, pickup radius x2 | `MoteMagnetEffect` + status (`mote_pickup_radius`) |
| Second Wind | 3 + 300 | instant heal 60% max HP and cleanse | `SecondWindEffect` |

(The prices are placeholders to playtest.) "Fire rate" speeds up guns; melee
swings aren't timed by it (see `ITEMS_AND_SHOPS.md`).

Adding an item: add a `BlackMarketItem` to `blackmarket_items` in the .tres (or
duplicate one in the builder script); reuse a status; write a `TempEffect`
only if no status does it (`start`, `tick`, `stop`, `is_instant`).

**Bots** (`BotHeroInput._choose_market`): they go only when the stall is open,
they are healthy (`bot_market_min_health`), not in a fight, within
`bot_market_max_distance` and able to arrive before it closes, and can afford
an item in **both** Motes and gold. At the stall they buy by `bot_priority`.
After shopping they wait `bot_market_retry_time`.

## Mote Island

Every match one **secret portal** sits at a spot drawn from the
`island_portal_spawn` markers (seeded, so it differs every game). It is not on
the minimap and has no arrow. The local player sees a faint shimmer (and hears a
soft hum) within `island_shimmer_tiles` (10 tiles), the portal itself within
`island_visible_tiles` (3), and can use it within `island_interact_tiles`
(1.5). A tile is `tile_size` (160 px, the floor grid).

Stepping through teleports only that hero to the **Island**: a small walled
room far off the map (`island_origin`) with a **cache** of `island_cache_motes`
(8) Motes (normal pickup rules: the carry cap stays, excess Motes stay on the
floor). It is an open room: everyone who found the portal is inside together and
can fight. Visitors leave through the exit portal (interact key) or are sent
home after `island_stay_time` (12 s), to the spot they left from. Dying on the
Island just respawns you at your base. While inside, a hero is off every
minimap.

Every `island_relocate_time` (180 s) the portal despawns and reappears at a new
spot (never the same twice in a row), anyone inside is sent home, the cache
refills, and the HUD gives a faint chime and a soft glow at the screen edges:
"it moved", with no place in it. Bots ignore the Island
(`IslandDirector.bot_can_use_island()` is the TODO hook).

## The Wanderer

A neutral mote-runner (a `NeutralMonster` with its own brain, `Wanderer`,
`scenes/match/wanderer.tscn`; body, size and stats from the embedded
`wanderer_data`). First at `wanderer_first_spawn` (2:00), then
`wanderer_respawn` (120 s) after it dies or escapes. It meanders quietly and
never attacks.

Each hit that hurts (at least `wanderer_min_hit_damage`, at most one per
`wanderer_hit_drop_cooldown`, from a hero) **drops `wanderer_motes_per_hit`
loose Motes** (for anyone; nothing is banked for a team), up to
`wanderer_max_motes` (6) in all, and it **flees** at `wanderer_flee_speed` (above
every hero's base speed) until `wanderer_calm_time` (6 s) pass without damage.
Killing it drops whatever it still holds and pays the killer
`wanderer_gold_reward`. It escapes if it lives `wanderer_max_lifetime` or
survives `wanderer_escape_time` after its first hit.

Where it runs: every `wanderer_repath_interval` it samples
`wanderer_flee_candidates` destinations, gets a route to each from the bots'
navigation graph (`BotNavigation`), and scores them by distance from every
hero, **openness** of the ground (graph points within
`wanderer_openness_hops`), and detour. A destination with fewer than
`wanderer_dead_end_cells` open cells is a dead end and only chosen if nothing
else is left. Cornered, it slows to `wanderer_cornered_speed_mult`. Its health
is about 7 typical hits (`wanderer_data.stats.health`, level scaled).

## Mote ledger

Every Mote is tagged at birth (`Mote.source`): `trickle`, `zone`, `dream`,
`neutral` (slain camps), `geyser`, `island`, `wanderer`. The tag rides along
while carried and dropped. `MoteLedger` counts per source: **spawned** (count and
value), **banked**, **delivered** (value into the Dreamers), and **spent** (at
the Black Market). It is printed at match end (`log_ledger_on_match_end`), shown
live in F1 > Match > Map events, and saved with **Save CSV**
(`user://mote_sources.csv`). `event_share()` is the share of deposited value
that came from the Island and the Wanderer.

One base-code touch to know about: the Island's cache is excluded from the
`max_loose_motes` count, so eight sealed-off Motes can't throttle the trickle.

## Debug

F1 > Match > **Map events**: open the market (random edge, left, right) or close
it; relocate the Island; spawn a Wanderer; **Go to** the portal, market or
Wanderer; **Give temp item** (any hero, Ranged Test included); a command box
(`market left`, `market close`, `island`, `wanderer`, `goto portal`, `motes`);
and the live Mote-source table. The same functions are methods on the
`DebugTools` autoload (`force_spawn_market`, `force_relocate_island`,
`force_spawn_wanderer`, `run_command`, `mote_ledger_report`).
