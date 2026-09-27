extends SceneTree

# Regenerates resources/visuals/rig_template/rig_template.tscn, a CutoutRig with
# placeholder Polygon2D parts and idle / move / hurt / death animations.
# Copy that scene for a new hero and swap each part for a Sprite2D of your art;
# don't edit this script for one hero.
#   godot --headless --script res://tools/visuals/make_rig_template.gd

const OUT := "res://resources/visuals/rig_template/rig_template.tscn"

const ARMOR := Color(0.93, 0.97, 0.96)
const CAPE := Color(0.1, 0.8, 0.8)
const GOLD := Color(0.8, 0.62, 0.2)
const WING := Color(0.75, 0.93, 0.88)
const STEEL := Color(0.3, 0.85, 0.85)


func _init() -> void:
	var rig := CutoutRig.new()
	rig.name = "CutoutRig"
	rig.frame_size = Vector2i(160, 160)

	var hips := _part(rig, rig, "Hips", Vector2(0, 10), [])
	_part(rig, hips, "WingBack", Vector2(-6, -30), _poly([-4, 0, -50, -30, -44, 4, -30, 16]), WING)
	_part(rig, hips, "Cape", Vector2(0, -28), _poly([-10, 0, 10, 0, 4, 50, -30, 44]), CAPE)
	_part(rig, hips, "LegBack", Vector2(6, 0), _poly([-6, 0, 6, 0, 6, 34, -6, 34]), ARMOR.darkened(0.15))
	var torso := _part(rig, hips, "Torso", Vector2(0, 0), _poly([-14, 0, 14, 0, 12, -34, -12, -34]), ARMOR)
	_part(rig, torso, "ArmBack", Vector2(12, -28), _poly([-4, 0, 4, 0, 4, 24, -4, 24]), ARMOR.darkened(0.15))
	_part(rig, hips, "LegFront", Vector2(-6, 0), _poly([-6, 0, 6, 0, 6, 34, -6, 34]), ARMOR)
	_part(rig, torso, "Head", Vector2(0, -36), _circle(18), ARMOR)
	_part(rig, torso, "Visor", Vector2(4, -38), _poly([-8, -8, 14, -8, 14, 8, -8, 8]), GOLD)
	_part(rig, torso, "WingFront", Vector2(-10, -28), _poly([0, 0, -40, -44, -36, -6, -24, 12]), WING)
	var arm := _part(rig, torso, "ArmFront", Vector2(-12, -28), _poly([-4, 0, 4, 0, 4, 24, -4, 24]), ARMOR)
	_part(rig, arm, "Sword", Vector2(0, 24), _poly([-3, 0, 3, 0, 3, 44, 0, 52, -3, 44]), STEEL)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	rig.add_child(player)
	player.owner = rig
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle())
	lib.add_animation(&"move", _move())
	lib.add_animation(&"hurt", _hurt())
	lib.add_animation(&"death", _death())
	player.add_animation_library(&"", lib)

	var scene := PackedScene.new()
	scene.pack(rig)
	var err := ResourceSaver.save(scene, OUT)
	rig.free()
	print("wrote %s (%s)" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _part(rig: Node, parent: Node, part_name: String, pos: Vector2, points: PackedVector2Array,
		color := Color.WHITE) -> Node2D:
	var node: Node2D = Polygon2D.new() if not points.is_empty() else Node2D.new()
	if node is Polygon2D:
		node.polygon = points
		node.color = color
	node.name = part_name
	node.position = pos
	parent.add_child(node)
	node.owner = rig
	return node


func _poly(xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		out.append(Vector2(xy[i], xy[i + 1]))
	return out


func _circle(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 16:
		out.append(Vector2.from_angle(TAU * i / 16.0) * r)
	return out


# One track, keys as [time, value, time, value, ...].
func _track(anim: Animation, path: String, keys: Array) -> void:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath(path))
	for i in range(0, keys.size(), 2):
		anim.track_insert_key(t, keys[i], keys[i + 1])


func _idle() -> Animation:
	var a := Animation.new()
	a.length = 1.0
	a.loop_mode = Animation.LOOP_LINEAR
	_track(a, "Hips/Torso:position", [0.0, Vector2.ZERO, 0.5, Vector2(0, 2), 1.0, Vector2.ZERO])
	_track(a, "Hips/Cape:rotation", [0.0, 0.0, 0.5, 0.08, 1.0, 0.0])
	_track(a, "Hips/WingBack:rotation", [0.0, 0.0, 0.5, -0.1, 1.0, 0.0])
	_track(a, "Hips/Torso/WingFront:rotation", [0.0, 0.0, 0.5, 0.1, 1.0, 0.0])
	return a


func _move() -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	_track(a, "Hips/LegFront:rotation", [0.0, 0.45, 0.25, -0.45, 0.5, 0.45])
	_track(a, "Hips/LegBack:rotation", [0.0, -0.45, 0.25, 0.45, 0.5, -0.45])
	_track(a, "Hips:position", [0.0, Vector2(0, 10), 0.125, Vector2(0, 6), 0.25, Vector2(0, 10),
			0.375, Vector2(0, 6), 0.5, Vector2(0, 10)])
	_track(a, "Hips/Cape:rotation", [0.0, 0.25, 0.25, 0.35, 0.5, 0.25])
	_track(a, "Hips/Torso/ArmFront:rotation", [0.0, -0.3, 0.25, 0.3, 0.5, -0.3])
	return a


func _hurt() -> Animation:
	var a := Animation.new()
	a.length = 0.3
	_track(a, "Hips:rotation", [0.0, 0.0, 0.08, 0.25, 0.3, 0.0])
	_track(a, "Hips:modulate", [0.0, Color(1, 0.5, 0.5), 0.3, Color.WHITE])
	return a


func _death() -> Animation:
	var a := Animation.new()
	a.length = 0.6
	_track(a, "Hips:rotation", [0.0, 0.0, 0.4, 1.5])
	_track(a, "Hips:position", [0.0, Vector2(0, 10), 0.4, Vector2(0, 30)])
	_track(a, "Hips:modulate", [0.0, Color.WHITE, 0.4, Color.WHITE, 0.6, Color(1, 1, 1, 0)])
	return a
