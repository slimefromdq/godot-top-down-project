@tool
extends Resource
class_name HeroDefinition

# Everything that makes a hero THAT hero, in one resource: identity, stats,
# abilities per slot, feel, visuals and sound. The Hero scene reads it and
# assembles itself, so a new hero is mostly a new .tres (see
# docs/HOW_TO_ADD_A_HERO.md).
#
# Deliberately one-way: a hero scene points at its definition, never the other
# way round. (If both pointed at each other, Godot would have to load each
# before the other: a cyclic load.)

enum Role { TANK, CARRY, TEMPO, FLEX }

@export var hero_id: StringName = &"hero"
@export var display_name: String = "Hero"
## Epithet, e.g. "the Sunblade".
@export var title: String = ""
@export var role: Role = Role.FLEX
@export_multiline var description: String = ""
@export var portrait: Texture2D
@export var icon: Texture2D

@export_group("Stats")
@export var stats: StatBlock
@export var move_speed: float = 540.0
@export var acceleration: float = 2600.0
@export var friction: float = 2800.0

@export_group("Abilities")
## Slot id -> ability. Slot ids come from GameRules (primary, ability_1,
## ability_2, movement, cc, ultimate). Optional slots may be left out.
@export var abilities: Dictionary[StringName, AbilityData] = {}

@export_group("Presentation")
@export var feel_profile: FeelProfile
@export var visual_profile: VisualProfile
@export var audio_profile: AudioProfile
## Optional replacement for the shared hero_base.tscn, for heroes that need
## extra nodes. Most heroes leave this empty.
@export var scene_override: PackedScene


func get_ability(slot_id: StringName) -> AbilityData:
	return abilities.get(slot_id)


func get_role_name() -> String:
	return Role.keys()[role].capitalize()


# Problems a designer should fix; empty = valid. Shown in the inspector (the
# read-only "Validation" field below) and by Tools > Validate Heroes.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var rules := GameRules.current()
	if hero_id == &"":
		problems.append("hero_id is empty")
	if stats == null:
		problems.append("no StatBlock")
	else:
		for stat in StatBlock.ALL:
			var scaling := stats.get_scaling(stat)
			if scaling == null:
				problems.append("stat %s has no scaling" % stat)
			elif scaling.base < 0.0 or scaling.growth < 0.0:
				problems.append("stat %s has a negative base or growth" % stat)
		if stats.health != null and stats.health.base <= 0.0:
			problems.append("health base must be above 0")
	if move_speed <= 0.0 or acceleration < 0.0 or friction < 0.0:
		problems.append("movement values must be positive")
	for slot in rules.slots:
		if slot.required and not abilities.has(slot.id):
			problems.append("missing required slot '%s'" % slot.id)
	for slot_id in abilities:
		if rules.get_slot(slot_id) == null:
			problems.append("slot '%s' isn't defined in GameRules" % slot_id)
		var ability := abilities[slot_id]
		if ability == null:
			problems.append("slot '%s' has no AbilityData" % slot_id)
			continue
		for problem in ability.validate():
			problems.append("slot '%s': %s" % [slot_id, problem])
	return problems


# A read-only "Validation" line at the bottom of the inspector.
func _get_property_list() -> Array[Dictionary]:
	return [{
		"name": "validation",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_MULTILINE_TEXT,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
	}]


func _get(property: StringName) -> Variant:
	if property == &"validation":
		var problems := validate()
		return "OK" if problems.is_empty() else "WARNING:\n- " + "\n- ".join(problems)
	return null
