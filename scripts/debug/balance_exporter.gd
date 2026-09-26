@tool
extends RefCounted
class_name BalanceExporter

# Writes every hero's stats and ability numbers at chosen levels to a CSV in
# TIDY (long) format: one row per hero x level x metric. That shape loads
# straight into R / the tidyverse:
#
#   library(tidyverse)
#   bal <- read_csv("balance_export.csv")
#   bal |> filter(source == "stat", metric == "health") |>
#     ggplot(aes(level, value, colour = hero)) + geom_line()
#
# Columns:
#   hero     hero_id                     (avery)
#   role     Tank / Carry / Tempo / Flex
#   level    1, 5, 10, 15, 20
#   source   stat | derived | ability
#   slot     ability slot, "" for stats  (primary, cc ...)
#   ability  ability id, "" for stats    (sunblade_slash)
#   metric   what the number is          (health, cooldown, damage,
#                                         combo_steps/3/damage, heal_per_target,
#                                         guns: magazine_size, shots_per_second,
#                                         reload_time, burst_dps, sustained_dps ...)
#   value    the number
#
# Everything is computed from the resources alone (no scene needed), so the
# export runs in the editor, headless, or in game.

const LEVELS: Array[int] = [1, 5, 10, 15, 20]
const HEADER := ["hero", "role", "level", "source", "slot", "ability", "metric", "value"]


# Returns rows (each an Array matching HEADER) for the given heroes.
static func build_rows(definitions: Array[HeroDefinition], levels: Array[int] = LEVELS) -> Array[Array]:
	var rows: Array[Array] = []
	var rules := GameRules.current()
	for definition in definitions:
		var hero := str(definition.hero_id)
		var role := definition.get_role_name()
		for level in levels:
			var stats := {}
			for stat in StatBlock.ALL:
				stats[stat] = definition.stats.value_at(stat, level)
				rows.append([hero, role, level, "stat", "", "", str(stat), stats[stat]])
			rows.append([hero, role, level, "stat", "", "", "move_speed", definition.move_speed])
			# Effective HP: raw damage needed to kill through resistances.
			rows.append([hero, role, level, "derived", "", "", "effective_hp_physical",
				stats[StatBlock.HEALTH] / rules.resistance_multiplier(stats[StatBlock.ARMOR])])
			rows.append([hero, role, level, "derived", "", "", "effective_hp_magic",
				stats[StatBlock.HEALTH] / rules.resistance_multiplier(stats[StatBlock.MAGIC_RESIST])])

			for slot in rules.get_slot_ids():
				var data := definition.get_ability(slot)
				if data == null:
					continue
				var ability := str(data.id)
				rows.append([hero, role, level, "ability", str(slot), ability, "cooldown", data.get_cooldown(level)])
				if data.get_range() > 0.0:
					rows.append([hero, role, level, "ability", str(slot), ability, "range", data.get_range()])
				var derived := data.get_hero_metrics(definition, level)
				for metric in derived:
					rows.append([hero, role, level, "derived", str(slot), ability, str(metric), derived[metric]])
				var metrics := data.get_balance_metrics(level, stats[StatBlock.WEAPON], stats[StatBlock.MAGIC])
				for metric in metrics:
					rows.append([hero, role, level, "ability", str(slot), ability, str(metric), metrics[metric]])
				var values := data.get_scaling_values()
				for path in values:
					var value: ScalingValue = values[path]
					if value == null:
						continue
					rows.append([hero, role, level, "ability", str(slot), ability, str(path),
						value.evaluate_at(level, stats[StatBlock.WEAPON], stats[StatBlock.MAGIC])])
	return rows


static func to_csv(rows: Array[Array]) -> String:
	var lines := PackedStringArray([",".join(HEADER)])
	for row in rows:
		var cells := PackedStringArray()
		for cell in row:
			cells.append(_cell(cell))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


# Export every hero under heroes/ (except the template) to `path`.
# Returns "" on success or an error message.
static func export_all(path: String) -> String:
	var definitions: Array[HeroDefinition] = []
	for definition in HeroScaffold.find_definitions():
		if not definition.resource_path.begins_with(HeroScaffold.TEMPLATE_DIR):
			definitions.append(definition)
	if definitions.is_empty():
		return "No hero definitions found under %s" % HeroScaffold.HEROES_DIR
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(to_csv(build_rows(definitions)))
	file.close()
	return ""


# Numbers rounded to 3 decimals; text quoted only when it needs it.
static func _cell(value: Variant) -> String:
	if value is float:
		return str(snappedf(value, 0.001))
	var text := str(value)
	if text.contains(",") or text.contains("\"") or text.contains("\n"):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text
