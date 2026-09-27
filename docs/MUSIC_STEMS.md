# Music stems for the match

The match music is adaptive: `MatchMusic` (a child of the `MatchManager`)
plays `resources/match/match_music.tres`, a `MusicLayerSet`, through
`AudioManager.play_layers()`. Every stem starts on the same frame and loops,
so they stay locked together; stems fade in and out by volume as the match
changes tier. Until the streams are assigned, it all runs silently.

## Rules every stem shares

- **One tempo, one key, one loop length.** The set's `bpm` (100) and
  `bars_per_loop` (8) say what they should be; change them in the .tres if
  you write at a different tempo. Every file must be exactly the same length
  (a whole number of bars, no tail), or the stems drift apart as they loop.
- **Enable Loop** in each file's Import settings (.ogg recommended). The
  AudioManager restarts a stem that ends anyway, but a seamless import loop
  sounds better.
- **Mix each stem to sit on top of the others:** tier 2 plays every stem at
  once.
- The **Music** bus carries them all (`default_bus_layout.tres`).

## The stems

| Stem (`layer_name`) | Tier | Plays when | What it should be |
|---|---|---|---|
| `calm_bed` | 0 CALM | always | The dreamy base: soft pads, a gentle pulse. It must work alone. |
| `calm_melody` | 0 CALM | always | A light, sleepy melody or arpeggio over the bed. |
| `tense_drive` | 1 TENSE | a wake meter is at 50% or more, or a Dream Mote is on the map (loose or carried) | Percussion and a moving bass: the same song, now with purpose. |
| `tense_counter` | 1 TENSE | same | A counter-melody or rhythmic stabs that raise the energy. |
| `stir_full` | 2 STIRRING | any Dreamer is stirring | Everything louder and busier: a lead, bigger drums. |
| `stir_heartbeat` | 2 STIRRING | same | A heartbeat-style low pulse (about one beat per second feels like the countdown). |

**Victory sting** (`victory_sting`): a short one-shot (2 to 4 s) played when
the match ends, as the stems fade out. It doesn't loop and doesn't need to
match the tempo.

## How the tiers move

- Rising is immediate: a stir starting jumps straight to STIRRING.
- Falling is one tier at a time, at most once per `min_seconds_per_drop` (8
  s), so the music doesn't flicker when a meter hovers near 50%.
- Each change crossfades over `crossfade_time` (1.5 s).

## Adding the files

Put the .ogg files in `audio/music/`, open `resources/match/match_music.tres`,
and drag each onto its layer's `stream`. Each layer's `volume_db` balances
it; the set's `sting_volume_db` balances the sting.
