extends Resource
class_name MapPieceData

# Tuning for a neutral map piece (Map Liveliness Plan). One class for every
# piece; each uses only its own group. Anyone can hit a piece (it has no team),
# and hits come through the normal HurtboxComponent / HealthComponent path, so
# no hero code knows about pieces. Cues play through the match profiles
# (MatchManager.play_world_cue): each piece names its own below.

@export var display_name: String = ""

@export_group("Health")
@export var max_health: float = 600.0

@export_group("Breakable")
## Seconds from shattering until it starts regrowing (breakable cover).
@export var regrow_time: float = 25.0
## Seconds of warning shimmer before it's solid again.
@export var regrow_warning: float = 3.0
## While a body stands where it would regrow, it waits and retries this often.
@export var regrow_retry: float = 0.25

@export_group("Geyser")
## The geyser's mound: low cover of this radius (walk around it, shoot over).
@export var body_radius: float = 46.0
## Hits (not damage) that pop it (Mote geyser).
@export var hits_to_pop: int = 6
## Hits fade away if nobody hits it for this long.
@export var hit_decay_time: float = 4.0
@export var mote_count: int = 3
## Mote value before the late-match multiplier.
@export var mote_value: int = 1
@export var mote_burst_radius: float = 140.0
## Dormant seconds after popping.
@export var cooldown: float = 45.0
## Uses the small Mote when empty.
@export var mote_data: MoteData

@export_group("Gate")
## Gate cycle on the match clock: open for gate_open_time, then closed for
## gate_closed_time, repeating. A gate's own cycle_offset shifts it.
@export var gate_open_time: float = 20.0
@export var gate_closed_time: float = 12.0
## Seconds of flashing before the gate changes.
@export var gate_warning: float = 2.5
## A hit on the gate's lever flips it for this long, then it rejoins its cycle.
@export var lever_hold_time: float = 8.0
## After a lever flip, the lever can't be flipped again for this long.
@export var lever_cooldown: float = 3.0
## Closed gates block shots too (full cover); off = low cover (shoot over).
@export var gate_blocks_shots: bool = true
## Bodies in the doorway when it closes are pushed this far past its edge.
@export var gate_push_margin: float = 40.0

@export_group("Hazard")
## Put on everyone inside every hazard_tick seconds (e.g. a slow).
@export var hazard_status: StatusEffect
@export var hazard_tick: float = 0.5
## Damage per tick (true damage: armour doesn't help against the map).
@export var hazard_damage: float = 0.0
## Hazard cycle on the match clock: active for hazard_active_time, then off
## for hazard_dormant_time (0 = always active). It shows hazard_telegraph
## seconds of warning before it turns on.
@export var hazard_active_time: float = 0.0
@export var hazard_dormant_time: float = 0.0
@export var hazard_telegraph: float = 2.0
## Pushed, pulled or carried into the hazard by an enemy within this many
## seconds: the hazard's damage and statuses count as that enemy's (kill
## credit, damage meters).
@export var displacement_credit_time: float = 3.0

@export_group("Travelator")
## Belt speed, px/s, along the belt's local X. Bodies standing on it are
## carried at this speed and walk on top of it.
@export var belt_speed: float = 260.0
## Seconds between direction flips (0 = never flips). The belt slows to a
## stop and back up over belt_flip_time.
@export var belt_reverse_period: float = 0.0
@export var belt_flip_time: float = 1.5

@export_group("Water Stairs")
## Walking down the cascade (along local +X): speed along it x this.
@export var stairs_down_multiplier: float = 1.45
## Climbing it (against local +X): speed along it x this.
@export var stairs_up_multiplier: float = 0.6

@export_group("Cues")
## Match cue names (MatchRules.cue_visuals / cue_audio).
@export var hit_cue: StringName = &"piece_hit"
@export var break_cue: StringName = &""
@export var warning_cue: StringName = &""
@export var restore_cue: StringName = &""
## Gates: opening / closing; hazards: turning on.
@export var open_cue: StringName = &""
@export var close_cue: StringName = &""
