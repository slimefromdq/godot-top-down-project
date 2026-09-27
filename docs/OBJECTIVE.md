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
  - every couple of minutes a pair of mirrored regions (both Glades, both
    Orchards ...) starts **dreaming**: it's announced a few seconds early,
    the ground tints and petals drift, and Motes pour in there for a while;
  - the big **Dream Mote** (worth 5) appears in the Cradle every few
    minutes, announced with a pillar of light. Whoever carries it is shown
    to everyone, with a beam of light over them.
  - After 15 minutes, new Motes are worth double.
- **Carrying:** you can hold up to 25; they circle you. The more you carry,
  the more the enemy sees of you on their minimap (pings, then always).
- **Losing them:** when you die they all burst out for anyone to grab. An
  enemy push, pull, carry or abduction **jostles** a fifth of them loose.
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
| `respawn_base` | 5.0 | Seconds a dead hero waits before respawning: base + per_level x level. |
| `respawn_per_level` | 0.8 | As above. |

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
| `xp_level_base` | 300.0 | XP needed to go from level L to L+1 = base + growth x (L - 1). With 300 / 100, level 10 takes 6300 XP in total. |
| `xp_level_growth` | 100.0 | As above. |

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
