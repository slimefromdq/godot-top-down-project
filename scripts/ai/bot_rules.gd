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
@export var bank_health_fraction: float = 0.4
## A retreating bot stays in its spawn area until healed to this share.
@export var retreat_until_fraction: float = 0.9
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
@export var mote_weight: float = 600.0
@export var dream_mote_bonus: float = 1000.0
@export var mote_distance_weight: float = 0.4
@export var target_distance_weight: float = 0.25
@export var target_low_health_weight: float = 350.0
@export var target_carrier_weight: float = 70.0
@export var strategy_only: bool = false
@export var profile_bots: bool = false

@export_group("Roles")
## Roles F1 > Bots fills a team with, in order (HeroDefinition.Role values:
## 0 tank, 1 carry, 2 tempo, 3 flex).
@export var team_composition: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 1, 0])
## How each HeroDefinition.Role plays (see BotRolePlan).
@export var tank_plan: BotRolePlan
@export var carry_plan: BotRolePlan
@export var tempo_plan: BotRolePlan
@export var flex_plan: BotRolePlan

@export_group("Roaming")
## A roam point counts as scouted when a bot comes this close to it.
@export var roam_seen_distance: float = 650.0
## Roam points closer than this to the bot aren't picked (it just saw them).
@export var roam_min_distance: float = 500.0
## A bot that was hit by an enemy fights back for this long, whatever its job.
@export var self_defence_time: float = 3.0
## A teammate counts as "fighting" (for PLAYMAKER assists) while its target
## is within this.
@export var ally_fight_radius: float = 1200.0

const PATH := "res://resources/ai/bot_rules.tres"
static var runtime: BotRules

static func current() -> BotRules:
	if runtime == null:
		runtime = (load(PATH) as BotRules).duplicate()
	return runtime


func plan_for(role: HeroDefinition.Role) -> BotRolePlan:
	var plan: BotRolePlan
	match role:
		HeroDefinition.Role.TANK: plan = tank_plan
		HeroDefinition.Role.CARRY: plan = carry_plan
		HeroDefinition.Role.TEMPO: plan = tempo_plan
		_: plan = flex_plan
	return plan if plan != null else BotRolePlan.new()
