@tool
extends Resource
class_name BotRolePlan

## How a bot plays its hero's role (HeroDefinition.role). BotRules holds one
## per role; the bot's strategy tick reads it. Weights, never fixed scripts:
## every bot still defends a stirring Dreamer, collects Motes it passes and
## fights back when attacked.

enum Job {
	## Roam the Mote spawns and dreaming zones, collect, and bank at home to
	## level up. Fights only what comes close.
	FARM,
	## Stay with the team's most valuable carrier and take stacks to the
	## enemy Dreamer. Contests the Dream Mote.
	ESCORT,
	## Hunt enemy carriers, join fights near teammates, scout the enemy half.
	PLAYMAKER,
}

@export var job: Job = Job.FARM

@export_group("Fighting")
## Visible enemies closer than this become a target (the bot turns to
## fight). Farther ones are ignored unless the job hunts them.
@export var engage_radius: float = 700.0
## A target that gets this far away is dropped (no chasing across the map).
@export var chase_radius: float = 1000.0
## Below this share of health, with an enemy in sight, go home.
@export_range(0.0, 1.0, 0.01) var retreat_health_fraction: float = 0.3

@export_group("Motes")
## Carried value at which the bot heads for a Dreamer.
@export var deposit_value: int = 10
## Bank at home (XP and gold for the team) instead of delivering, unless the
## enemy's wake meter is at least deliver_when_enemy_wake.
@export var prefers_bank: bool = false
@export_range(0.0, 1.0, 0.05) var deliver_when_enemy_wake: float = 0.6
## ...or once the hero reaches this level: farm until strong, then push.
@export var deliver_from_level: int = 8
## A big stack with this many enemies seen near the way to their Dreamer is
## banked instead.
@export var gauntlet_enemies: int = 2

@export_group("Roaming")
## Roam point score bonus for points on the enemy half of the map (scouting
## and intercepting); negative keeps the bot on its own half.
@export var enemy_half_bias: float = 0.0
## Roam point score bonus per second since the team last saw that point.
@export var unseen_weight: float = 12.0
## Roam point score penalty per pixel of travel.
@export var distance_weight: float = 0.35
## Roam points closer than this to another bot's roam goal are avoided, which
## keeps the team spread out.
@export var spread_radius: float = 1300.0
@export var spread_penalty: float = 900.0

@export_group("Items")
## What the bot buys, in purchase order (components before their upgrades).
## It buys whenever it can shop (in base, or dead), stops at the first item
## it can't afford and saves for it. Items that can never fit (a second
## active) are skipped.
@export var item_build: Array[ItemData] = []
## Walk home to shop once holding this much gold (and the next item is
## affordable, no Motes carried, no fight). 0 = only shop when passing
## through base or while dead.
@export var shop_trip_gold: float = 0.0

@export_group("Team play")
## ESCORT: follow carriers holding at least this value.
@export var escort_min_value: int = 4
## Leash while escorting: stay within this of the carrier.
@export var escort_distance: float = 260.0
## PLAYMAKER: go help a teammate fighting within this distance.
@export var assist_radius: float = 2600.0
## PLAYMAKER: hunt known enemy carriers within this distance.
@export var hunt_radius: float = 3500.0
## Only enemy carriers holding at least this value are worth a hunt.
@export var hunt_min_value: int = 5
## Most teammates hunting the same enemy.
@export var max_hunters: int = 2
## Head for the Dream Mote (warning or loose) from within this distance.
@export var dream_mote_radius: float = 5000.0
