# Wake the Dreamer

The match objective, for players. Every number here is a `MatchRules` value
(`resources/rules/match_rules.tres`); the table at the end lists them all.
F1 > Match edits them live.

## The goal

Each team has a **Dreamer** sleeping in its Plaza: Dawn (mint, a little sun
on its head) at the bottom, Dusk (coral, a crescent moon) at the top. **Wake
the enemy's Dreamer** by feeding it Motes, and keep yours asleep.

## Motes

Motes are little dream-bugs, the young of Cpt. Yellow's species. Walk near
one and it flies to you.

- **Where they come from:**
  - small Motes (worth 1) keep appearing all over the map;
  - every couple of minutes a pair of mirrored regions (both Lawns, both
    Promenades ...) starts **dreaming**: it's announced a few seconds early,
    the ground tints and petals drift, and Motes pour in there for a while;
  - the big **Dream Mote** (worth 10) appears in the Sunken Court every few
    minutes, announced with a pillar of light. Whoever carries it is shown
    to everyone, with a beam of light over them.
  - slain **neutral objectives** burst into Motes that only the killing
    team can grab for a few seconds: a couple from a jungle camp, a big
    pile from the Nightmare (see below).
  - After 15 minutes, new Motes are worth double.
- **Carrying:** you can hold up to 25; they circle you. The more you carry,
  the more the enemy sees of you on their minimap (pings, then always).
- **Losing them:** when you die they all burst out for anyone to grab. An
  enemy push, pull, carry or abduction **jostles** a fifth of them loose.
  Every hit **shakes** some loose too, in proportion to the damage (a hit
  for a quarter of your max HP shakes out a quarter of your stack; small
  hits add up). You can't grab your own shaken Motes back for a moment.
  Dropped Motes fade after 20 seconds. Carried Motes make jump pads and
  trampolines a little floatier.
- **In transit you can't deposit:** not while airborne, abducted or inside a
  containment ring.

## Depositing

Stand in a Dreamer's ring: your Motes go in one at a time (getting faster),
most valuable first. Leaving, dying or being jostled stops it.

- **Bank** at your own Dreamer: gold and XP for your whole team (you get a
  bonus), and every 25 banked earns your team **Sweet Dreams**: a little
  faster and slowly healing for 30 seconds.
- **Deliver** to the enemy's Dreamer: more gold and XP, and it fills their
  **wake meter** (100). The meter never drains on its own.

## Stirring and the Lullaby

A full wake meter makes that Dreamer **stir** for 30 seconds.

- For the first 5 seconds it takes nothing at all.
- After that, **one more delivered Mote wakes it: the attackers win.**
- The defenders sing a **Lullaby** by standing near their Dreamer (more
  defenders sing faster; it stops while an attacker is close) and by banking
  there. A finished Lullaby puts it back to sleep at 60%.
- If time runs out with no final Mote, it settles at 80%: defending actively
  pays off more than stalling. Defenders respawn faster during a stir.

## Neutral objectives

Neutral monsters live around the map. They leave you alone until someone
hits them, then fight whoever hit them last; walk them out of their leash
(or stop hitting them for a few seconds) and they go home and heal to full.
Every number is in the camp's `NeutralData`
(`resources/match/neutrals/*.tres`); the full rules are in
`docs/ITEMS_AND_SHOPS.md`.

- **Jungle camps** (8 on Dream Basin, in mirrored pairs): a
  **Sleepwalker** in each Lawn and on each Upper Terrace, a pack of three
  **Dream Wisps** in each Garden Court and Fountain Court. They come back a minute or
  so after they're cleared, and pay a little: gold and XP for the killer and
  their team, a pinch of ultimate charge, and a Mote or two.
- **The Nightmare** wakes once per match, at 10:00, in the middle of the
  Sunken Court. Everyone is warned 30 seconds early (banner, minimap ping, an
  off-screen arrow while it's up). It's tough and fights back with volleys
  and a ring of bolts. The team that slays it gets a big gold and XP
  payout, ultimate charge, **12 Motes worth 5 each** (theirs alone for 12
  seconds), and **Nightmare's Bane** for 2 minutes: +15% damage, 10% less
  damage taken, a little faster (teammates who are dead at the time get
  the rest of it when they respawn).

## Map pieces

- **Dream-glass** (6 on Dream Basin): full cover that both teams can shoot
  down. It cracks as it takes damage and shatters at 0; about 25 seconds
  later it shimmers for 3 seconds and grows back (never on top of anyone:
  it waits for them to move).
- **Mote geysers** (4): anyone can hit one. Six hits pop 3 Motes around it
  for anyone to grab, then it rests for 45 seconds. Hits fade if nobody
  keeps hitting it.
- **Gates** (4): the Old Colonnade' north door and the Garden Court's main
  entrance open for 20 seconds and close for 12, the two alternating. They
  flash before they change. Shoot the lever post beside one to flip it for
  8 seconds. A closing gate pushes anyone in the doorway out; it never
  traps you.
- **Hazards**: sleep-fog rolls over each Upper Terrace for 15 seconds at a
  time (30% slower while you're in it; it blinks for 3 seconds first), and
  a thorn bed in each Promenade nicks whoever stands in it. Push an enemy into
  one and its damage counts as yours.
- **The Plaza Express** (a travelator along each Plaza front) carries
  whoever stands on it and flips direction every 30 seconds.
- **Water stairs** (a stepped cascade in each Fountain Court, running down
  toward the Sunken Court): quicker going down, slower climbing up.
- **Launch flowers** (one past each Fountain Court) are jump pads whose landing
  sweeps back and forth: time your jump.

Every number is in `resources/map/pieces/*.tres`.

## Shops

Each base has a shop stall in its spawn room. Press **B** to open the shop:
you can buy and sell anywhere in your base (near the stall or in your spawn
area), or from anywhere while you wait to respawn. You hold up to 6 items
plus one **active item**, whose ability goes on **G**. See
`docs/ITEMS_AND_SHOPS.md`.

## Spawn areas

Each team's spawn area (tinted in its colour, around the spawn markers) heals
its own heroes fast: 30% of max health a second. Camping the enemy's spawn
doesn't pay, and anyone can walk home to reset. Enemies get nothing there.

## Ultimate charge

In a match nobody starts with their ultimate. It fills from 0 to
`ult_charge_max` by playing, and casting it spends all of it (there is no
cooldown on it in a match):

- a trickle every second you're alive;
- damage you deal to enemy heroes, and damage you take from them;
- healing you do to teammates (a little for healing yourself);
- kills and assists;
- every Mote you deposit, banked or delivered.

The ultimate's button fills with gold and shows the percentage; your team's
cards in the top bar show each teammate's charge. On the training maps (no
match) ultimates keep their cooldowns so they can be practised.

## MatchRules

### Match

| Value | Default | What it does |
|---|---|---|
| `warmup_time` | 10.0 | Countdown before the match starts. Heroes can move, nobody earns anything. |
| `respawn_base` | 5.0 | Seconds a dead hero waits before respawning: base + per_level x level + the match-time growth. |
| `respawn_per_level` | 0.8 | As above. |
| `respawn_growth_max` | 4.0 | Respawns grow by up to this many seconds as the match goes on... |
| `respawn_growth_time` | 1200.0 | ...rising linearly over this many seconds of play (full at 20 minutes). |

### Spawn

| Value | Default | What it does |
|---|---|---|
| `spawn_area_margin` | 450.0 | A team's spawn area is the box around its spawn markers grown by this (kept inside the map). |
| `spawn_heal_pct_per_second` | 0.3 | Share of max health healed per second for the team's own living heroes in it... |
| `spawn_heal_interval` | 0.5 | ...paid in chunks this many seconds apart (label `spawn_heal`, gives no ultimate charge). |

### Economy

| Value | Default | What it does |
|---|---|---|
| `passive_gold_per_second` | 2.0 | Paid to every hero on a team (alive or dead) while the match is PLAYING. |
| `passive_xp_per_second` | 4.0 | As above. |
| `passive_tick_interval` | 1.0 | Passive income is paid in chunks this many seconds apart. |
| `kill_gold` | 150.0 | Paid to the hero who lands the killing blow on an enemy hero. |
| `kill_xp` | 200.0 | As above. |
| `assist_gold` | 60.0 | Paid to each other enemy hero who damaged the victim recently. |
| `assist_xp` | 100.0 | As above. |
| `assist_window` | 10.0 | How recent that damage must be, in seconds. |

### Leveling

| Value | Default | What it does |
|---|---|---|
| `xp_level_base` | 300.0 | XP needed to go from level L to L+1 = base + growth x (L - 1) + accel x (L - 1)². With 300 / 70 / 12, level 10 takes 7668 XP in total and level 13 (the cap) 14292. |
| `xp_level_growth` | 70.0 | As above. |
| `xp_level_accel` | 12.0 | As above: makes each level cost more than the last. |

### Ultimate

| Value | Default | What it does |
|---|---|---|
| `ultimate_charge_enabled` | true | Ultimates (slots with `SlotDefinition.ultimate_charge`) run on charge instead of their cooldown. Off = cooldowns, as on the training maps. |
| `ult_charge_max` | 100.0 | Charge that fills the ultimate. Every hero starts at 0. |
| `ult_charge_per_second` | 0.35 | Earned by every living hero each second while PLAYING. |
| `ult_charge_per_damage` | 0.03 | Per point of damage dealt to enemy heroes (after resistances). |
| `ult_charge_per_damage_taken` | 0.015 | Per point of damage taken from enemy heroes, shields included. |
| `ult_charge_per_heal` | 0.04 | Per point of healing done to a teammate... |
| `ult_charge_self_heal_mult` | 0.25 | ...times this for healing yourself. |
| `ult_charge_kill` | 12.0 | Flat charge for a kill. |
| `ult_charge_assist` | 6.0 | Flat charge for an assist. |
| `ult_charge_per_mote_value` | 1.5 | Per Mote value the depositor puts into either Dreamer. |

### Motes

| Value | Default | What it does |
|---|---|---|
| `max_carried` | 25 | Most Motes one hero can carry (a Dream Mote takes one slot). |
| `reveal_values` | [8, 15, 22] | Enemy minimap reveal steps by carried VALUE: at reveal_values[i] or more, the carrier pings the enemy minimap every reveal_ping_intervals[i] seconds (0 = shown all the time). Ascending. |
| `reveal_ping_intervals` | [6.0, 3.0, 0.0] | As above. |
| `jostle_displacements_required` | 1 | Enemy displacements (pushes, pulls, carries, abductions) needed to jostle Motes loose. Pushes shorter than jostle_min_distance don't count. |
| `jostle_min_distance` | 100.0 | As above. |
| `jostle_window` | 4.0 | For jostle_displacements_required > 1: displacements this far apart start the count again. |
| `jostle_drop_fraction` | 0.2 | A jostle knocks loose this share of the stack (rounded up), at least one. 0.2 = a full stack of 25 loses 5. |
| `heavy_pockets_air_time` | 0.04 | Heavy pockets: seconds of extra air time per carried Mote on jump pads and trampolines. |
| `burst_radius` | 170.0 | Death burst: Motes scatter this far from the body. |
| `jostle_drop_distance` | 120.0 | Jostled Motes land about this far from the carrier. |
| `mote_shake_factor` | 1.0 | Damage shake: every hit knocks loose carried * (damage / max HP) * this. The fraction left over carries to the next hit. 0 = off. |
| `shake_repickup_delay` | 0.75 | The shaken carrier can't grab their own shaken Motes back for this long. |
| `shake_drop_distance` | 110.0 | Shaken Motes land about this far from the carrier. |

### Spawning

| Value | Default | What it does |
|---|---|---|
| `trickle_interval` | 4.0 | Trickle: one small Mote every interval at a free mote_spawn point, while fewer than max_loose_motes lie on the map. |
| `max_loose_motes` | 16 | As above. |
| `spawn_sight_range` | 1300.0 | A trickle point is "seen" if a hero is within this range with line of sight. Unseen points are preferred. |
| `zone_first_time` | 90.0 | Dreaming zones: first one at zone_first_time, then every zone_interval (counted from the previous zone's start). Announced zone_warning early. |
| `zone_interval` | 120.0 | As above. |
| `zone_warning` | 10.0 | As above. |
| `zone_duration` | 40.0 | As above. |
| `zone_spawn_interval` | 1.5 | While dreaming, each half spawns a Mote this often, up to zone_max_per_half loose Motes in that half. |
| `zone_max_per_half` | 6 | As above. |
| `dream_mote_first_time` | 240.0 | Dream Mote: first at dream_mote_first_time, then dream_mote_interval after the previous one is picked up for good (banked, or faded). |
| `dream_mote_interval` | 180.0 | As above. |
| `dream_mote_warning` | 15.0 | As above. |

### Dreamers

| Value | Default | What it does |
|---|---|---|
| `deposit_radius` | 300.0 | A carrier standing within this of a Dreamer deposits (the deposit ring). |
| `deposit_tick` | 0.2 | Seconds before the first Mote of a visit goes in; each next gap is deposit_tick_speedup times the last, down to deposit_tick_min. |
| `deposit_tick_speedup` | 0.9 | As above. |
| `deposit_tick_min` | 0.06 | As above. |
| `bank_gold_per_value` | 15.0 | Banking at your own Dreamer: paid per Mote value, split across the team. |
| `bank_xp_per_value` | 50.0 | As above. |
| `deliver_gold_per_value` | 25.0 | Delivering to the enemy Dreamer: paid per value, split across the team. |
| `deliver_xp_per_value` | 80.0 | As above. |
| `depositor_bonus_pct` | 0.25 | The depositor also gets this share of each tick's team payment. |

### Wake

| Value | Default | What it does |
|---|---|---|
| `wake_meter_max` | 100.0 | Delivered value that fills a Dreamer's wake meter. It never drains on its own. |
| `stir_duration` | 30.0 | A full meter stirs the Dreamer for this long. |
| `stir_grace` | 5.0 | The first seconds of a stir refuse deposits (the filling deposit stops too), so the defenders always get their final fight. |
| `lullaby_radius` | 600.0 | Defenders in this ring fill the Lullaby (larger than the deposit ring). |
| `lullaby_rate_per_defender` | 0.04 | Lullaby progress (0..1) per second per living defender in the ring. It pauses while any living attacker is inside. |
| `lullaby_per_banked_value` | 0.02 | Lullaby progress per value banked at your own stirring Dreamer. |
| `lullaby_reset_pct` | 0.6 | A finished Lullaby settles the Dreamer at this share of the wake meter... |
| `timeout_reset_pct` | 0.8 | ...and a stir that runs out with no final Mote settles it at this. |
| `stir_defender_respawn_mult` | 0.75 | Defenders of a stirring Dreamer respawn this much faster. |

### Buffs

| Value | Default | What it does |
|---|---|---|
| `sweet_dreams_threshold` | 25.0 | Every this much banked value gives the whole team the Sweet Dreams buff. |
| `sweet_dreams_status` | (resource | The buff; its own duration is replaced by sweet_dreams_duration. |
| `sweet_dreams_duration` | 30.0 | As above. |

### Objectives

| Value | Default | What it does |
|---|---|---|
| `objectives_enabled` | true | Neutral camps (jungle camps and the Nightmare) spawn on the match clock. Their own numbers live in each camp's NeutralData. |
| `objective_motes_use_late_mult` | true | Motes dropped by a slain neutral get the late-match multiplier too. |

### Shop

| Value | Default | What it does |
|---|---|---|
| `shop_catalog` | (resource) | What the shop sells (`resources/items/shop_catalog.tres`). |
| `item_slots` | 6 | Passive items a hero can hold. |
| `max_active_items` | 1 | Active items a hero can hold. |
| `active_item_slot` | item | The GameRules slot an active item's ability fills (key G). |
| `sell_refund_pct` | 0.6 | Selling refunds this share of the item's full cost. |
| `shop_radius` | 700.0 | Heroes within this of their own Shop, or anywhere in their spawn area, are in base and can shop. |
| `shop_while_dead` | true | Dead heroes can shop from anywhere. |

### Late match

| Value | Default | What it does |
|---|---|---|
| `late_match_time` | 900.0 | After late_match_time, new Motes spawn worth late_match_value_mult times as much. This keeps matches from running forever. |
| `late_match_value_mult` | 2.0 | As above. |

### Cues

| Value | Default | What it does |
|---|---|---|
| `cue_visuals` | (resource | Match-wide looks and sounds (level_up ...). A hero whose own profile has the same cue name plays its own instead. |
| `cue_audio` | (resource | As above. |
| `chime_scale` | [1.0, 1.125, 1.25, 1.5, 1.667] | Cosmetic pitch steps (a major pentatonic): Mote pickups and deposit ticks climb it, an octave higher on the second pass. |
| `bank_chord` | [1.0, 1.25, 1.5] | Pitches played together when a deposit visit ends: a resolving chord for banking, a brighter one for a delivery. |
| `deliver_chord` | [1.5, 1.875, 2.25, 3.0] | As above. |
