extends RefCounted
class_name BotDraft

# Which heroes bots play, and putting a bot into the world. Shared by the
# hero select screen (bots pick while you choose), the match setup
# (GameState spawns the picked roster) and the debug panel's "Fill with bots".
#
#   playable_definitions()   every valid hero under heroes/, by hero_id
#   pick(pool, have, used)   the next bot's hero: the first role in
#                            BotRules.team_composition the team is short of,
#                            else any hero not taken yet
#   spawn_bot(...)           a bot Hero added to the current scene

const HERO_BASE := "res://scenes/heroes/hero_base.tscn"
const SKILL_PATHS := ["res://resources/ai/easy.tres", "res://resources/ai/normal.tres",
	"res://resources/ai/hard.tres"]


static func playable_definitions() -> Array[HeroDefinition]:
	var definitions := HeroScaffold.find_definitions()
	definitions = definitions.filter(func(definition: HeroDefinition):
		return definition.hero_id != &"template" and definition.validate().is_empty())
	definitions.sort_custom(func(a: HeroDefinition, b: HeroDefinition):
		return str(a.hero_id) < str(b.hero_id))
	return definitions


static func find_definition(hero_id: StringName) -> HeroDefinition:
	for definition in playable_definitions():
		if definition.hero_id == hero_id:
			return definition
	return null


## `have`: the definitions already on the team. `used`: hero_ids not to pick.
static func pick(pool: Array, have: Array, used: Array) -> HeroDefinition:
	var role_count := {}
	for definition in have:
		if definition != null:
			role_count[definition.role] = int(role_count.get(definition.role, 0)) + 1
	var wanted := {}
	for role in BotRules.current().team_composition:
		wanted[role] = int(wanted.get(role, 0)) + 1
		if int(role_count.get(role, 0)) >= int(wanted[role]):
			continue
		for definition in pool:
			if definition.role == role and definition.hero_id not in used:
				return definition
	for definition in pool:
		if definition.hero_id not in used:
			return definition
	return null


static func skill_for(difficulty: int) -> BotSkill:
	return load(SKILL_PATHS[clampi(difficulty, 0, SKILL_PATHS.size() - 1)])


## A bot of `definition` on `team`, placed around the team's spawn point
## (`index` spreads them out). Added to the current scene.
static func spawn_bot(tree: SceneTree, definition: HeroDefinition, team: StringName, skill: BotSkill,
		bot_seed: int, index: int, group: StringName = &"") -> Hero:
	var scene: PackedScene = definition.scene_override if definition.scene_override != null else load(HERO_BASE)
	var bot: Hero = scene.instantiate()
	bot.definition = definition
	bot.team = team
	bot.bot_controlled = true
	bot.bot_skill = skill
	bot.bot_seed = bot_seed
	bot.name = "Bot_%s_%d" % [team, index + 1]
	if group != &"":
		bot.add_to_group(group)
	tree.current_scene.add_child(bot)
	var rules := BotRules.current()
	var angle := TAU * float(index) / maxf(rules.team_size, 1)
	var map := tree.get_first_node_in_group(&"game_map") as GameMap
	var spawn := Vector2.ZERO
	if map != null:
		var points := map.get_spawn_points(team)
		if not points.is_empty():
			spawn = points[index % points.size()].global_position
	bot.global_position = spawn + Vector2.RIGHT.rotated(angle) * rules.spawn_spacing
	return bot
