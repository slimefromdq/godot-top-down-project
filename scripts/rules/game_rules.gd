@tool
extends Resource
class_name GameRules

# Match-wide numbers that aren't owned by any single hero: the level cap, the
# resistance formula, the ability slot layout and input buffering defaults.
#
# There is one shared instance (resources/rules/game_rules.tres). Code reads it
# through GameRules.current() instead of a hard-coded path, so a playtest can
# swap rules (e.g. a level-20 test mode) by pointing DEFAULT_PATH elsewhere or
# calling GameRules.override(). The debug panel edits the live copy.

const DEFAULT_PATH := "res://resources/rules/game_rules.tres"

## Highest level a hero can reach in a match. Stat formulas are defined for
## levels 1-20 regardless, so the cap can be raised for playtests without
## touching any hero data.
@export_range(1, 20) var max_level: int = 10

@export_group("Resistances")
## Damage multiplier = K / (K + resistance). With K = 100, 100 armor halves
## physical damage and 300 armor quarters it. Every point of resistance is
## worth the same amount of effective HP, which keeps tank stacking linear.
@export var resistance_constant: float = 100.0

@export_group("Crowd control")
## Resolve: after a stun, root or taunt (StatusEffect.is_hard_cc) ends on an
## actor, they carry resolve_status for this many seconds. 0 turns the rule off.
@export var resolve_duration: float = 2.0
## While Resolved, new hard CC lasts this fraction of its duration.
@export_range(0.0, 1.0, 0.05) var resolve_cc_multiplier: float = 0.5
## The status that marks a Resolved actor (its look and HUD name). Its own
## duration is ignored: resolve_duration is used.
@export var resolve_status: StatusEffect

@export_group("Ability slots")
## Every slot a hero can have, in HUD order.
@export var slots: Array[SlotDefinition] = []

@export_group("Input")
## Default seconds an early ability press is remembered while another cast is
## still busy. A hero's FeelProfile can override it. It must be long enough to
## bridge a press made early in a windup to that swing's cancel window, or
## early presses get dropped.
@export var default_input_buffer: float = 0.3

@export_group("Test maps")
## Maps the F3 switcher cycles through, in order.
@export_file("*.tscn") var test_maps: PackedStringArray = []

@export_group("Collision")
## Physics layers a Hitbox or Projectile searches for hurtboxes. Team checks
## then decide who can actually be hit. (Layers 3 and 5 are the legacy
## "Player Hurtbox" / "Enemy Hurtbox" layers.)
@export_flags_2d_physics var hurtbox_mask: int = 4 | 16
## Layers that stop projectiles and dashes. Low cover and ledges are left out on
## purpose: projectiles fly over them.
@export_flags_2d_physics var wall_mask: int = 1
## Layers that block line of sight (CombatQueries.has_line_of_sight). Full
## cover only by default: you can see over low cover and ledges. Bushes block
## sight by their own rule, not by layer.
@export_flags_2d_physics var sight_mask: int = 1


static var _current: GameRules


static func current() -> GameRules:
	if _current == null:
		if ResourceLoader.exists(DEFAULT_PATH):
			_current = load(DEFAULT_PATH)
		else:
			_current = GameRules.new()
	return _current


# Swap the active rules (tests, alternative playtest modes).
static func override(rules: GameRules) -> void:
	_current = rules


func get_slot(slot_id: StringName) -> SlotDefinition:
	for slot in slots:
		if slot.id == slot_id:
			return slot
	return null


func get_slot_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for slot in slots:
		ids.append(slot.id)
	return ids


# How much of a hit gets through a resistance value. Negative resistance
# (from future shred items) amplifies damage symmetrically.
func resistance_multiplier(resistance: float) -> float:
	if resistance >= 0.0:
		return resistance_constant / (resistance_constant + resistance)
	return 2.0 - resistance_constant / (resistance_constant - resistance)
