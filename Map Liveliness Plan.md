# Map Liveliness Plan

Sep 28, 2026 · @Lucy

## Overview

Dream Basin has good static pieces (jump pads, teleporters, bushes, speed
strips, ledges, stairwells) and timed objectives (dreaming zones, the Dream
Mote, jungle camps, the Nightmare). What it lacks is a map that **changes
during the match** and **reacts to the people in it**. This plan adds both.

Design decisions (settled):

- **The map noticeably changes mid-match.** Gates open and close, cover
  breaks and regrows, and map events reshape whole wings for a while.
- **New pieces are neutral.** Anyone can break, trigger or use them.
- **Exception: shrines are claimed by a team.** A claimed shrine is that
  team's until the other team takes it.
- **Everything is mirrored.** Every piece and every event comes in 180°
  pairs, so neither team gets an edge. `check.py` enforces it.

Phase prompts are in `Map Liveliness Prompts.md`.

## Rules every phase follows

- **Shared systems.** Map pieces live in `scenes/map/` + `scripts/map/`, and
  events in `scripts/match/`. They never reference a specific hero or
  region by name. Regions come from exported data (`pair_id`, groups).
- **Numbers in `.tres`.** Each piece reads a `MapPieceData` resource
  (`resources/map/pieces/*.tres`). Event timing lives in
  `resources/rules/match_rules.tres`, next to the dreaming-zone values.
- **Looks and sound through cues/profiles.** Every piece has a
  `VisualProfile` / `AudioProfile`, and gameplay code only fires cues.
- **Tests.** Every piece gets a headless check in
  `tools/map/map_pieces_infra_test.gd` (new) and a playable spot in
  Training Grounds. `docs/BALANCE_TOOLS.md` lists the new test.
- **Placement.** Pieces are placed by `tools/dream_basin/layout.py` and
  verified by `check.py` (mirrored, reachable, clear of cover, sight lanes).
- **Hero interaction.** A piece heroes can affect with abilities (e.g.
  knock someone into a hazard, shoot a lever) gets a row in the "You want /
  Use" table in `docs/HOW_TO_ADD_A_HERO.md` and a case in
  `tools/heroes/ranged_test/`.

## Phase 1: ambient life (looks and sound only)

This phase makes no gameplay changes, so there's no balance risk. It also
covers the unchecked ROADMAP Phase 4 item "ambient animation, lighting,
particles, and map audio regions".

- **Region ambience.** A `RegionAmbience` node per region (reusing the
  exported region polygons) with a `VisualProfile` + `AudioProfile`:
  pollen in the Glade, fog wisps in the Tangle, wind and grass sway on Stilt
  Ridge, chimes and dust motes in the Lullaby Ruins, fountain burble in
  Driftfield. Audio crossfades as the listener moves between regions.
- **Reactive props.** Grass and bushes part as bodies pass. Fireflies or
  birds scatter from nearby shots and explosions (listens to combat
  signals, never called by them). Fountains ripple.
- **Match mood.** A slow global tint driven by match time: dusk deepens
  toward 10:00, flares for the Nightmare, and shifts again at 15:00
  (double Motes). All keyframes are in a `MapMoodProfile` `.tres`.
- **Base reactions.** Each Plaza glows with its Dreamer's wake meter. The
  whole base shimmers while its Dreamer stirs.

Done when: Dream Basin looks and sounds alive with nobody fighting, and the
perf tool (`tools/perf`) shows no frame-time regression.

## Phase 2: neutral map pieces, part 1 (breakables and geysers)

| Piece | Behaviour | Data |
|---|---|---|
| **Breakable cover** | Dream-glass or crates with HP. They block shots and movement like `cover_block`, shatter when broken (cue), and regrow after `regrow_time` with a warning shimmer. Won't regrow on top of a body; waits instead. | hp, regrow_time, regrow_warning |
| **Mote geyser** | Hit it `hits_to_pop` times and it pops `mote_count` Motes (anyone may grab them), then goes dormant for `cooldown`. | hits_to_pop, mote_count, mote_value, cooldown |

Heroes can damage both through the normal hurtbox path (they're
`HealthComponent` targets on a neutral team), so no hero code changes.

## Phase 3: neutral map pieces, part 2 (gates, hazards, platforms)

| Piece | Behaviour | Data |
|---|---|---|
| **Toggle gate** | Hedge or ruin door. Driven by a shared **gate clock** (`open_time` / `closed_time`), by a **lever** that anyone can shoot, or by a map event. Closing never crushes: bodies in the doorway are pushed out to the nearer side. | open_time, closed_time, lever_hold_time, warning |
| **Hazard zone** | Sleep-fog (slows) or thorn hedge (small tick damage). Always telegraphed. Being pushed, pulled or carried into one counts as a hit from the displacer, so displacement heroes get credit. | status, tick, telegraph_time |
| **Drifting platform** | Moves on a `Path2D` loop and carries bodies standing on it (reuses ledge height rules). | speed, pause_time |
| **Launch flower** | A jump pad whose launch angle sweeps back and forth on a loop. Reuses `jump_pad.gd`. | sweep_angle, sweep_period |

`check.py` gains rules: no gate state may cut off a base from the Cradle,
and no gate state may open a sight lane onto a spawn door.

## Phase 4: claimable shrines

The only team-owned piece.

- **Claiming.** Stand in the ring to fill a capture bar (`capture_time`).
  More allies fill it faster, and it's contested (frozen) while an enemy is
  inside. Taking an enemy shrine first drains their claim, then fills yours.
- **While claimed.** The owner's team gets the shrine's `team_status` (each
  shrine offers a different one: vision pulse, move speed, Mote magnet
  range). The shrine shows the owner's colour on the map and minimap, and
  pulses a `claim_income` of gold/XP to its team every `income_interval`.
- **Decay.** A claim lasts until taken, but `neutral_after` seconds with no
  owner nearby lets it slowly drift back to neutral. That stops one early
  capture from lasting the whole match.
- **Placement.** Four shrines in mirrored pairs, outside both Plazas and
  away from the Cradle. Each team has a "near" pair and a "far" pair.
- **Cues:** `shrine_contested`, `shrine_claimed_<team>`, `shrine_lost`.
  Announced to both teams.

## Phase 5: MapEventDirector (the map changes mid-match)

This grows out of `MoteDirector`'s dreaming-zone scheduler. A new
`MapEventDirector` (a child of `MatchManager`, like `ObjectiveDirector`)
picks events from a data pool of `MapEventData` resources on the match clock.
Each event is announced (banner, minimap ping, region tint), runs for
`duration`, then reverts. Events and dreaming zones never overlap in the same
region pair.

| Event | What changes |
|---|---|
| **Moonfall** | One pair of wings throws its gates open and opens a normally sealed shortcut for the duration. |
| **Sleepstorm** | Fog rolls across a pair of Wilds: vision shrinks, bushes spread, hazard fog appears. |
| **Stampede** | A herd of harmless dream-beasts crosses a lane on a path. They block bodies and jostle Mote carriers (reuses the jostle rule). |
| **Bloom** | Broken cover in a region regrows as Mote geysers until the event ends. |
| **Shatter** | All breakable cover in the Cradle shatters at once and stays down for the duration, so the arena opens up. |

Scheduling: first event at `map_event_first_time`, then every
`map_event_interval`, weighted so the same event doesn't repeat twice in a
row. Later events (after 15:00) can pick two at once. F1 > Match gets a
"fire event" button for testing.

## Phase 6: bots, docs and balance

- **Bots** (`docs/BOT_AI.md`): pop geysers when nearby and safe, contest and
  claim shrines as a role-plan goal, avoid hazards, and route around closed
  gates (rebake navigation, or give gates nav obstacles).
- **Docs:** `docs/maps/DREAM_BASIN.md` (piece and shrine tables, updated
  blockout), `docs/OBJECTIVE.md` (shrines and events for players), and
  `docs/VISUALS_AND_AUDIO.md` (new cues).
- **Balance:** shrine income and event frequency in the balance CSV. Run
  bot matches (`tools/ai`) and compare Mote totals and match length before
  and after.

## Build order

1. Ambient life
2. Breakable cover + Mote geysers
3. Gates, hazards, platforms, launch flowers
4. Shrines
5. MapEventDirector + events
6. Bots, docs, balance pass

Each phase is one PR. Phases 2–5 are infrastructure, so ask for the plan
first, read it, then say "go".

## Open questions

- Should shrine buffs stack if one team holds both of a pair?
- Should the Nightmare (10:00) suppress map events while it's up, or can an
  event land during it?
- Should breakable cover drop anything (a single Mote?) or stay purely
  positional?
