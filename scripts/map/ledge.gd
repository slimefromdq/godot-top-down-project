@tool
extends StaticBody2D
class_name Ledge

# A one-way cliff edge between high ground and low ground.
#
# Local frame (rotate the node to place it):
#   * the edge runs along +X, from 0 to `length`;
#   * LOW ground is on the -Y side (the chevrons point that way);
#   * HIGH ground is on the +Y side.
#
# How it works: the collision shape is a thin strip on layer 7 (Ledges) with
# Godot's `one_way_collision` on. A one-way shape only stops bodies moving
# along its local +Y, i.e. from low ground toward high ground, so climbing is
# blocked and dropping down passes straight through. Projectiles don't mask
# layer 7, so shots always cross. A jump pad clears the Ledges bit from the
# character's mask while it is airborne, which is how pads get you up.

@export var length: float = 1000.0:
	set(value):
		length = maxf(value, 10.0)
		_rebuild()
## Height of the cliff face drawn on the low side. Low-ground players stop at
## its foot.
@export var face_depth: float = 44.0:
	set(value):
		face_depth = value
		_rebuild()
@export var face_color := Color("56663c")
@export var lip_color := Color("eef5dc")

const STRIP_THICKNESS := 20.0
const CHEVRON_SPACING := 320.0

var _shape_node: CollisionShape2D


func _ready() -> void:
	collision_layer = MapLayers.LEDGES
	collision_mask = 0
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		# Built in code (no owner), so it never gets saved into the scene.
		_shape_node = CollisionShape2D.new()
		_shape_node.one_way_collision = true
		_shape_node.one_way_collision_margin = 8.0
		add_child(_shape_node)
	var strip := RectangleShape2D.new()
	strip.size = Vector2(length, STRIP_THICKNESS)
	_shape_node.shape = strip
	# The blocking surface is the strip's -Y edge, placed at the foot of the face.
	_shape_node.position = Vector2(length / 2.0, -face_depth + STRIP_THICKNESS / 2.0)
	queue_redraw()


func _draw() -> void:
	# Cliff face: a dark band on the low side, darkest at the foot.
	var steps := 4
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var color := face_color.darkened(0.35 * t1)
		draw_rect(Rect2(0, -face_depth * t1, length, face_depth * (t1 - t0)), color)
	# Bright lip on the high side: "this edge is the top".
	draw_rect(Rect2(0, 0, length, 7), lip_color)
	draw_line(Vector2(0, 0), Vector2(length, 0), face_color.darkened(0.6), 3.0)
	# Chevrons pointing down the drop.
	var count := maxi(1, int(length / CHEVRON_SPACING))
	for i in count:
		var x := length * (i + 0.5) / count
		var tip := Vector2(x, -face_depth + 8)
		var arm := face_depth * 0.55
		draw_polyline(PackedVector2Array([tip + Vector2(-arm, arm * 0.9), tip, tip + Vector2(arm, arm * 0.9)]),
			lip_color, 4.0, true)
