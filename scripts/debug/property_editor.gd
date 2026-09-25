extends VBoxContainer
class_name PropertyEditor

# Builds live-edit rows for every exported number/toggle on a Resource,
# recursing into nested resources (combo steps, hit shapes, projectiles,
# statuses, ScalingValues ...). Changing a row writes straight into the
# resource, and because abilities read their data at cast time, the next
# swing uses the new number.
#
# It edits whatever resource you hand it. The debug panel always hands it the
# ability's / hero's PRIVATE runtime copy, never the .tres on disk.

signal value_changed(resource: Resource, property: StringName, value: Variant)

## How deep to follow nested resources.
const MAX_DEPTH := 4
## Resource types never worth editing live (art, sound, scripts).
const SKIP_TYPES: Array[String] = ["Script", "PackedScene", "Texture2D", "SoundCue", "AudioStream",
	"SpriteFrames", "Curve", "Gradient", "VisualProfile", "AudioProfile"]

var _visited: Dictionary = {}


func edit(resource: Resource, title: String = "") -> void:
	for child in get_children():
		child.queue_free()
	_visited.clear()
	if resource == null:
		return
	add_theme_constant_override(&"separation", 2)
	if title != "":
		_add_header(self, title, 0)
	_add_resource(self, resource, 0)


func _add_resource(parent: Control, resource: Resource, depth: int) -> void:
	if resource == null or depth > MAX_DEPTH or _visited.has(resource):
		return
	_visited[resource] = true
	for property in resource.get_property_list():
		var usage: int = property.usage
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if usage & PROPERTY_USAGE_READ_ONLY:
			continue
		var name: StringName = property.name
		var value: Variant = resource.get(name)
		match property.type:
			TYPE_FLOAT:
				_add_number(parent, resource, name, value, false, depth)
			TYPE_INT:
				if property.hint == PROPERTY_HINT_ENUM:
					_add_enum(parent, resource, name, value, property.hint_string, depth)
				elif property.hint != PROPERTY_HINT_LAYERS_2D_PHYSICS:
					_add_number(parent, resource, name, value, true, depth)
			TYPE_BOOL:
				_add_toggle(parent, resource, name, value, depth)
			TYPE_OBJECT:
				if value is Resource and not _skip(value):
					_add_header(parent, str(name).capitalize(), depth + 1)
					_add_resource(parent, value, depth + 1)
			TYPE_ARRAY:
				var i := 0
				for item in value:
					if item is Resource and not _skip(item):
						_add_header(parent, "%s %d" % [str(name).capitalize(), i + 1], depth + 1)
						_add_resource(parent, item, depth + 1)
					i += 1
			TYPE_DICTIONARY:
				for key in value:
					var item: Variant = value[key]
					if item is Resource and not _skip(item):
						_add_header(parent, "%s: %s" % [str(name).capitalize(), key], depth + 1)
						_add_resource(parent, item, depth + 1)


func _skip(resource: Resource) -> bool:
	for type in SKIP_TYPES:
		if resource.is_class(type):
			return true
		var script: Script = resource.get_script()
		if script != null and script.get_global_name() == type:
			return true
	return false


func _row(parent: Control, label_text: String, depth: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "  ".repeat(depth) + label_text
	label.custom_minimum_size.x = 220
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	parent.add_child(row)
	return row


func _add_header(parent: Control, text: String, depth: int) -> void:
	var label := Label.new()
	label.text = "  ".repeat(maxi(depth - 1, 0)) + text
	label.add_theme_color_override(&"font_color", Color(1, 0.85, 0.5))
	parent.add_child(label)


func _add_number(parent: Control, resource: Resource, name: StringName, value: Variant, integer: bool, depth: int) -> void:
	var row := _row(parent, str(name).capitalize(), depth)
	var spin := SpinBox.new()
	spin.step = 1.0 if integer else 0.01
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.min_value = -100000
	spin.max_value = 100000
	spin.custom_minimum_size.x = 110
	spin.value = value
	spin.select_all_on_focus = true
	spin.value_changed.connect(func(v: float):
		var new_value: Variant = int(v) if integer else v
		resource.set(name, new_value)
		value_changed.emit(resource, name, new_value))
	row.add_child(spin)


func _add_toggle(parent: Control, resource: Resource, name: StringName, value: bool, depth: int) -> void:
	var row := _row(parent, str(name).capitalize(), depth)
	var box := CheckBox.new()
	box.button_pressed = value
	box.toggled.connect(func(on: bool):
		resource.set(name, on)
		value_changed.emit(resource, name, on))
	row.add_child(box)


func _add_enum(parent: Control, resource: Resource, name: StringName, value: int, hint: String, depth: int) -> void:
	var row := _row(parent, str(name).capitalize(), depth)
	var option := OptionButton.new()
	var index := 0
	for entry in hint.split(","):
		var parts := entry.split(":")
		var id := int(parts[1]) if parts.size() > 1 else index
		option.add_item(parts[0].strip_edges(), id)
		index += 1
	option.select(option.get_item_index(value))
	option.item_selected.connect(func(i: int):
		var id := option.get_item_id(i)
		resource.set(name, id)
		value_changed.emit(resource, name, id))
	row.add_child(option)
