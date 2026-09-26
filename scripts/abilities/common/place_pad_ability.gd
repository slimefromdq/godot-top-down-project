extends Ability
class_name PlacePadAbility

# Generic "place a jump pad" driven by PlacePadData. The press picks the spot
# (the cursor, clamped to place_range); with charge_enabled the key is held
# while the cursor is dragged, and the release point is the landing spot
# (clamped to max_offset; a short drag lands min_offset along the aim).
#
# Cues: <id>_charge_start (context.position = pad spot, for a preview),
# <id>_placed (context.position, target_position = landing).

## Pads this ability put down that are still out.
var pads: Array[JumpPad] = []
var _place_at := Vector2.ZERO


func get_pad_data() -> PlacePadData:
	return data as PlacePadData


func _activate(_target_position: Vector2) -> String:
	var pad_data := get_pad_data()
	_place_at = actor.global_position + (cast_target - actor.global_position).limit_length(pad_data.place_range)
	return ""


func _on_charge_start() -> void:
	actor.trigger_cue(StringName(str(ability_id) + "_charge_start"), {"position": _place_at, "charge_ability": self})


# Where a release at `release_point` would land.
func landing_for(release_point: Vector2) -> Vector2:
	var pad_data := get_pad_data()
	var offset := release_point - _place_at
	if offset.length() < pad_data.min_offset:
		var aim := cast_direction if cast_direction != Vector2.ZERO else Vector2.RIGHT
		offset = aim * pad_data.min_offset
	return _place_at + offset.limit_length(pad_data.max_offset)


func get_place_point() -> Vector2:
	return _place_at


func _on_active_start() -> void:
	var pad_data := get_pad_data()
	var landing := landing_for(cast_target)
	var pad := JumpPad.place(actor, _place_at, landing, actor, pad_data.pad_radius, pad_data.air_time,
		pad_data.arc_height, pad_data.lifetime, pad_data.max_launches, pad_data.enemy_status, pad_data.pad_color)
	pads.append(pad)
	pad.expired.connect(func(): pads.erase(pad))
	actor.trigger_cue(StringName(str(ability_id) + "_placed"), {"position": _place_at, "target_position": landing})
