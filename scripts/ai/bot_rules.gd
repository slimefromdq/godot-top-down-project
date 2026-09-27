@tool
extends Resource
class_name BotRules

## Shared bot tuning. The debug Bots tab edits a runtime copy.
@export var team_size: int = 6
@export var spawn_spacing: float = 115.0
@export var navigation_cell_size: float = 150.0
@export var navigation_actor_radius: float = 50.0
@export var navigation_link_cost: float = 250.0
@export var strategy_interval: float = 0.5
@export var perception_interval: float = 0.2
@export var goal_commit_time: float = 1.5
@export var goal_reached_distance: float = 90.0
@export var default_attack_range: float = 450.0
@export var attack_range_fraction: float = 0.85
@export var too_close_range_fraction: float = 0.55
@export var wounded_ally_fraction: float = 0.75
@export var waypoint_reached_fraction: float = 0.6
@export var retreat_health_fraction: float = 0.28
@export var bank_health_fraction: float = 0.4
@export var deliver_min_motes: int = 3
@export var mote_search_radius: float = 2400.0
@export var enemy_search_radius: float = 1700.0
@export var stuck_time: float = 1.0
@export var obstacle_probe_distance: float = 180.0
@export var obstacle_avoid_angle: float = 0.8
@export var aim_lead_seconds: float = 0.18
@export var dodge_scan_radius: float = 900.0
@export var dodge_horizon: float = 0.8
@export var dodge_margin: float = 25.0
@export var dodge_duration: float = 0.35
@export var dodge_memory_seconds: float = 2.0
@export var charge_fraction: float = 0.85
@export var held_duration: float = 0.7
@export var ability_range_fraction: float = 0.9
@export var objective_mote_weight: float = 600.0
@export var objective_dream_mote_bonus: float = 1000.0
@export var objective_distance_weight: float = 0.4
@export var target_distance_weight: float = 0.25
@export var target_low_health_weight: float = 350.0
@export var target_carrier_weight: float = 70.0
@export var strategy_only: bool = false
@export var profile_bots: bool = false

const PATH := "res://resources/ai/bot_rules.tres"
static var runtime: BotRules

static func current() -> BotRules:
	if runtime == null:
		runtime = (load(PATH) as BotRules).duplicate()
	return runtime
