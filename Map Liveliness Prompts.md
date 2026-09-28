# Map Liveliness Prompts

Copy-ready Claude Code prompts for each phase of `Map Liveliness Plan.md`.
Use one session and one PR per phase, and merge each before starting the
next. Every prompt ends by running every test in `docs/BALANCE_TOOLS.md`.

## Prompt 1: ambient life

```text
Read CLAUDE.md, Map Liveliness Plan.md (Phase 1), docs/VISUALS_AND_AUDIO.md
and docs/maps/DREAM_BASIN.md first.

Build Phase 1 of the plan: region ambience, reactive props, match mood and
base reactions. Looks and sound only: no gameplay code may change behaviour.
- Region shapes come from the exported Dream Basin data; never hard-code a
  region name in a script.
- Every look and sound goes through VisualProfile / AudioProfile cues; the
  mood keyframes live in a new MapMoodProfile .tres.
- Reactive props listen to existing combat and movement signals; combat
  code must not call them.
- Add a headless check in tools/map/map_pieces_infra_test.gd (new) that the
  mood profile samples correctly across match time and that ambience nodes
  exist for every region. List the test in docs/BALANCE_TOOLS.md.
- Update docs/VISUALS_AND_AUDIO.md with the new profiles and cues.
Run every test in docs/BALANCE_TOOLS.md, then check tools/perf for a
frame-time regression. Stop and report.
```

## Prompt 2: breakable cover and Mote geysers

```text
Read CLAUDE.md, Map Liveliness Plan.md (Phase 2), docs/ITEMS_AND_SHOPS.md
(neutral objectives) and docs/OBJECTIVE.md. Plan first; wait for "go".

Build the MapPieceData resource and two pieces: breakable cover and the
Mote geyser, as scenes in scenes/map/ with scripts in scripts/map/.
- Both take damage through the normal hurtbox / HealthComponent path on a
  neutral team, so no hero code changes.
- Cover regrows after regrow_time with a warning, and waits if a body is in
  the way. Geyser Motes are free for anyone.
- Place mirrored pairs through tools/dream_basin/layout.py and extend
  check.py so they're verified.
- Add headless checks to tools/map/map_pieces_infra_test.gd, a Training
  Grounds spot for each piece, and a "You want / Use" row plus a
  tools/heroes/ranged_test/ case if heroes can target them specially.
Run every test in docs/BALANCE_TOOLS.md. Stop and report.
```

## Prompt 3: gates, hazards, platforms, launch flowers

```text
Read CLAUDE.md, Map Liveliness Plan.md (Phase 3) and docs/maps/DREAM_BASIN.md.
Plan first; wait for "go". If the plan touches more than about 15 files,
split it into part 1 (gates + hazards) and part 2 (platforms + flowers).

- Toggle gate: gate clock, shootable lever, or event control. It never crushes;
  bodies in the doorway are pushed out. Gates update navigation for bots.
- Hazard zone: telegraphed status area. Displacement into it credits the
  displacer. Add a "You want / Use" row and a ranged_test case for that.
- Drifting platform on a Path2D that carries bodies (reuse ledge rules).
- Launch flower: jump_pad.gd with a sweeping angle, not a new script.
- check.py: no gate state cuts a base off from the Cradle or opens a sight
  lane onto a spawn door.
Headless checks in tools/map/map_pieces_infra_test.gd; Training Grounds
spots. Run every test in docs/BALANCE_TOOLS.md. Stop and report.
```

## Prompt 4: claimable shrines

```text
Read CLAUDE.md, Map Liveliness Plan.md (Phase 4) and docs/OBJECTIVE.md.
Plan first; wait for "go".

Build the shrine: the only team-owned map piece. Capture bar (more allies
fill it faster, frozen while contested), taking an enemy shrine drains then
refills, team_status for the owner, periodic claim_income, and drift back
to neutral after neutral_after seconds unattended. Owner colour on the map
and minimap; cues shrine_contested / shrine_claimed_<team> / shrine_lost.
Every number lives in a ShrineData .tres. Place two mirrored pairs via
layout.py. Headless checks cover capture, contest, steal, decay and income.
Add shrine values to the balance CSV. Update docs/OBJECTIVE.md.
Run every test in docs/BALANCE_TOOLS.md. Stop and report.
```

## Prompt 5: MapEventDirector

```text
Read CLAUDE.md, Map Liveliness Plan.md (Phase 5), scripts/match/mote_director.gd
(dreaming zones) and scripts/match/objective_director.gd. Plan first; wait
for "go".

Add MapEventDirector (child of MatchManager) that runs MapEventData
resources on the match clock: announce, run for duration, revert. Implement
Moonfall, Sleepstorm, Stampede, Bloom and Shatter using the Phase 2–3
pieces; events never overlap an active dreaming zone's region pair, and
never repeat twice in a row. Timing lives in match_rules.tres. Add an
F1 > Match "fire event" button. Headless checks: scheduling, revert
restores every piece, no overlap with dreaming zones.
Run every test in docs/BALANCE_TOOLS.md. Stop and report.
```

## Prompt 6: bots, docs, balance

```text
Read CLAUDE.md, docs/BOT_AI.md and Map Liveliness Plan.md (Phase 6).

Teach bots to pop geysers, claim and contest shrines (as a role-plan goal),
avoid hazards and path around closed gates. Update docs/maps/DREAM_BASIN.md,
docs/OBJECTIVE.md and docs/VISUALS_AND_AUDIO.md. Run bot matches with
tools/ai before and after and report Mote totals, shrine hold time and match
length. Run every test in docs/BALANCE_TOOLS.md. Stop and report.
```
