extends Resource
class_name RigMotion

# How a LiveRig moves: all the numbers behind its idle bob, walk bounce, sway,
# hurt tilt and death. One per hero (or share the default).

@export_group("Facing")
## Degrees past a direction boundary before the rig turns (stops flicker).
@export_range(0.0, 22.0) var direction_hysteresis_deg: float = 10.0
## Speed (px/s) above which the legs walk.
@export var move_threshold: float = 20.0
## How fast idle and walk blend into each other (per second).
@export var blend_speed: float = 8.0

@export_group("Idle")
@export var idle_bob_px: float = 2.0
@export var idle_bob_hz: float = 0.8

@export_group("Walk")
## Steps per second at full walk; each step bounces once and swaps the stride.
@export var steps_per_second: float = 4.0
@export var walk_bounce_px: float = 4.0

@export_group("Sway")
## Swing (degrees) of parts tagged with "sway" metadata, times their tag value.
@export var idle_sway_deg: float = 3.0
@export var walk_sway_deg: float = 8.0
@export var sway_hz: float = 0.8

@export_group("Hurt")
@export var hurt_tilt_deg: float = 12.0
@export var hurt_time: float = 0.3

@export_group("Death")
@export var death_tip_deg: float = 80.0
@export var death_time: float = 0.45
@export var death_drop_px: float = 30.0
## Fade after the tip, in seconds.
@export var death_fade_time: float = 0.3
