@tool
extends Resource
class_name HitShape

# The area an attack covers, relative to the attacker and the aim direction.
#
#   ARC     a pie slice: `radius` long, `arc_degrees` wide (a sword swing)
#   CIRCLE  a disc of `radius`, pushed `forward_offset` along the aim
#           (a ground slam, a burst around yourself with offset 0)
#   LINE    a rectangle `length` long and `width` wide starting at the
#           attacker (a thrust, a beam)

enum Kind { ARC, CIRCLE, LINE }

@export var kind: Kind = Kind.ARC
@export var radius: float = 160.0
@export_range(1.0, 360.0) var arc_degrees: float = 120.0
@export var length: float = 300.0
@export var width: float = 60.0
## Moves the shape's origin forward along the aim direction.
@export var forward_offset: float = 0.0


static func arc(reach: float, degrees: float) -> HitShape:
	var shape := HitShape.new()
	shape.kind = Kind.ARC
	shape.radius = reach
	shape.arc_degrees = degrees
	return shape


static func circle(reach: float, offset: float = 0.0) -> HitShape:
	var shape := HitShape.new()
	shape.kind = Kind.CIRCLE
	shape.radius = reach
	shape.forward_offset = offset
	return shape


static func line(line_length: float, line_width: float) -> HitShape:
	var shape := HitShape.new()
	shape.kind = Kind.LINE
	shape.length = line_length
	shape.width = line_width
	return shape


# The farthest point the shape reaches, for AI range checks and tooltips.
func get_reach() -> float:
	match kind:
		Kind.LINE:
			return forward_offset + length
	return forward_offset + radius


func has_negative() -> bool:
	return radius < 0.0 or length < 0.0 or width < 0.0 or arc_degrees < 0.0
