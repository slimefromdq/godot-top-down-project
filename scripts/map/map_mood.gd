extends CanvasModulate
class_name MapMood

# Tints the whole world (not the HUD, which sits on CanvasLayers) with a
# MapMoodProfile sampled on the match clock. Made by MapAmbience.
# Presentation only. With no MatchManager it holds the profile's first colour.

var profile: MapMoodProfile
var _manager: MatchManager


func _ready() -> void:
	add_to_group(MatchManager.CLOCK_LISTENERS)
	color = profile.sample(0.0) if profile else Color.WHITE


## Debug clock jump: show the new time's mood at once, no easing.
func on_clock_jumped(_from: float, _to: float) -> void:
	color = get_target_color()


func get_target_color() -> Color:
	if profile == null or not VisualToggles.is_on(&"mood"):
		return Color.WHITE
	if _manager == null or not is_instance_valid(_manager):
		_manager = MatchManager.find(get_tree())
	return profile.sample(_manager.clock if _manager else 0.0)


func _process(delta: float) -> void:
	var target := get_target_color()
	var k := 1.0 if profile.smoothing <= 0.0 else clampf(delta / profile.smoothing, 0.0, 1.0)
	color = color.lerp(target, k)
