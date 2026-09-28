extends RefCounted
class_name VisualToggles

# Debug switches for purely decorative visuals and sounds (F1 > Tools >
# Visuals), to see what each costs or to make a slow machine playable. Every
# layer is on by default; the settings last until the game closes (they
# survive map switches). Gameplay never reads these: turning a layer off only
# stops drawing (and, where it has any, its per-frame work).
#
# Each decorative system checks is_on(<its layer>). Add a layer to LAYERS
# when you add a decoration, and check it where the decoration draws.

const LAYERS := {
	&"drifters": "Region drifters (pollen, fog, dust)",
	&"critters": "Region critters (birds, fireflies)",
	&"sound_beds": "Region sound beds",
	&"mood": "Match mood tint",
	&"dreamer_glow": "Dreamer glow",
	&"fountain_ripples": "Fountain ripples",
	&"bush_rustle": "Bush rustle",
	&"zone_petals": "Dreaming-zone petals",
	&"floor_grid": "Floor grid",
}

static var _off: Dictionary = {}


static func is_on(layer: StringName) -> bool:
	return not _off.has(layer)


static func set_on(layer: StringName, on: bool, tree: SceneTree = null) -> void:
	if on:
		_off.erase(layer)
	else:
		_off[layer] = true
	if tree != null:
		tree.call_group(GROUP, &"on_visual_toggles_changed")


static func set_all(on: bool, tree: SceneTree = null) -> void:
	for layer in LAYERS:
		set_on(layer, on, null)
	if tree != null:
		tree.call_group(GROUP, &"on_visual_toggles_changed")


## Nodes in this group get on_visual_toggles_changed() after a change.
const GROUP := &"visual_toggle_listeners"
