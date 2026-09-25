@tool
extends EditorPlugin

# Editor helpers for hero work, under Project > Tools:
#   * New Hero from Template...   copies heroes/_template to heroes/<name>/
#   * Validate Heroes             checks every HeroDefinition, prints problems
#
# Definitions are also validated automatically every time one is saved, so a
# missing slot or a negative number shows up in the Output panel right away.

const MENU_NEW := "New Hero from Template..."
const MENU_VALIDATE := "Validate Heroes"

var _dialog: ConfirmationDialog
var _name_edit: LineEdit


func _enter_tree() -> void:
	add_tool_menu_item(MENU_NEW, _open_new_hero_dialog)
	add_tool_menu_item(MENU_VALIDATE, validate_all)
	resource_saved.connect(_on_resource_saved)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NEW)
	remove_tool_menu_item(MENU_VALIDATE)
	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)
	if _dialog != null:
		_dialog.queue_free()


func validate_all() -> void:
	var definitions := HeroScaffold.find_definitions()
	var bad := 0
	for definition in definitions:
		bad += 1 if _report(definition) else 0
	print("Validate Heroes: %d checked, %d with problems." % [definitions.size(), bad])


func _on_resource_saved(resource: Resource) -> void:
	if resource is HeroDefinition:
		_report(resource)
	elif resource is AbilityData:
		for problem in resource.validate():
			push_warning("%s: %s" % [resource.resource_path, problem])


# Returns true if it found problems.
func _report(definition: HeroDefinition) -> bool:
	var problems := definition.validate()
	if problems.is_empty():
		print("  OK  %s" % definition.resource_path)
		return false
	push_warning("HeroDefinition %s:\n- %s" % [definition.resource_path, "\n- ".join(problems)])
	return true


func _open_new_hero_dialog() -> void:
	if _dialog == null:
		_dialog = ConfirmationDialog.new()
		_dialog.title = "New Hero from Template"
		var box := VBoxContainer.new()
		var label := Label.new()
		label.text = "Hero name (e.g. Cosmo). Creates heroes/<name>/."
		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = "Cosmo"
		box.add_child(label)
		box.add_child(_name_edit)
		_dialog.add_child(box)
		_dialog.confirmed.connect(_create_hero)
		_name_edit.text_submitted.connect(func(_t): _dialog.hide(); _create_hero())
		EditorInterface.get_base_control().add_child(_dialog)
	_name_edit.text = ""
	_dialog.popup_centered(Vector2i(420, 120))
	_name_edit.grab_focus()


func _create_hero() -> void:
	var hero_name := _name_edit.text
	var error := HeroScaffold.create(hero_name)
	if error != "":
		push_error("New hero: " + error)
		return
	EditorInterface.get_resource_filesystem().scan()
	print("Created %s. Open it, set the definition's stats and fill the slots." % HeroScaffold.scene_path(hero_name))
	# Give the file system a moment to register the new files, then open.
	await get_tree().create_timer(0.5).timeout
	EditorInterface.open_scene_from_path(HeroScaffold.scene_path(hero_name))
