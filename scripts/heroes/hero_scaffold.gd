@tool
extends RefCounted
class_name HeroScaffold

# Copies heroes/_template into heroes/<id>/ with every "template" name and
# path rewritten, giving a new hero that runs immediately with a basic attack.
# The editor plugin (Project > Tools > New Hero from Template) calls this; it
# works headless too, which is how it's tested.
#
# Why rewrite text instead of duplicating resources through the API? The
# template's files reference each other by path (the definition points at the
# basic attack, which points at its script). A plain copy would leave the new
# hero pointing back into _template, so every edit would change both heroes.

const TEMPLATE_DIR := "res://heroes/_template/"
const HEROES_DIR := "res://heroes/"
const TEMPLATE_TOKEN := "template"


# Returns "" on success, or an error message.
static func create(hero_name: String) -> String:
	var id := hero_name.strip_edges().to_snake_case()
	if id.is_empty() or not id.is_valid_ascii_identifier():
		return "'%s' isn't a usable name (letters, digits, underscores)." % hero_name
	var target := HEROES_DIR + id + "/"
	if DirAccess.dir_exists_absolute(target):
		return "%s already exists." % target
	var error := DirAccess.make_dir_recursive_absolute(target)
	if error != OK:
		return "Couldn't create %s (%s)." % [target, error_string(error)]

	var pascal := id.to_pascal_case()
	var display := id.capitalize()
	for file in DirAccess.get_files_at(TEMPLATE_DIR):
		if file.ends_with(".uid") or file.ends_with(".import"):
			continue
		var text := FileAccess.get_file_as_string(TEMPLATE_DIR + file)
		text = _rewrite(text, id, pascal, display)
		var new_name := file.replace(TEMPLATE_TOKEN, id)
		var out := FileAccess.open(target + new_name, FileAccess.WRITE)
		if out == null:
			return "Couldn't write %s." % (target + new_name)
		out.store_string(text)
		out.close()
	return ""


# Path to the new hero's scene, for opening it after creation.
static func scene_path(hero_name: String) -> String:
	var id := hero_name.strip_edges().to_snake_case()
	return HEROES_DIR + id + "/" + id + "_hero.tscn"


static func _rewrite(text: String, id: String, pascal: String, display: String) -> String:
	# Unique ids must not be copied, or Godot sees two files claiming one uid.
	var uid_attr := RegEx.create_from_string(" uid=\"uid://[a-z0-9]+\"")
	text = uid_attr.sub(text, "", true)
	text = text.replace(TEMPLATE_DIR, HEROES_DIR + id + "/")
	text = text.replace("template_", id + "_")
	text = text.replace("hero_id = &\"template\"", "hero_id = &\"%s\"" % id)
	text = text.replace("display_name = \"Template\"", "display_name = \"%s\"" % display)
	text = text.replace("title = \"the Placeholder\"", "title = \"\"")
	text = text.replace("TemplateHero", pascal + "Hero")
	text = text.replace("Starting point for new heroes. Copy with Project > Tools > New Hero from Template.", "")
	return text


# Every HeroDefinition under heroes/, for validation and balance export.
static func find_definitions() -> Array[HeroDefinition]:
	var result: Array[HeroDefinition] = []
	for dir in DirAccess.get_directories_at(HEROES_DIR):
		for file in DirAccess.get_files_at(HEROES_DIR + dir):
			if not file.ends_with(".tres"):
				continue
			var path := HEROES_DIR + dir + "/" + file
			# Cheap text check first, so we don't load every ability resource.
			if not FileAccess.get_file_as_string(path).contains("script_class=\"HeroDefinition\""):
				continue
			var definition := load(path) as HeroDefinition
			if definition != null:
				result.append(definition)
	return result
