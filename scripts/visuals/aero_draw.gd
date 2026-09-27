class_name AeroDraw

# Glossy "Frutiger Aero" drawing helpers for _draw() code: a soft body, a
# bright glassy highlight over the top half and a thin light rim. Every
# custom-drawn surface (HUD slots, cover, bushes...) uses these so the whole
# game shares one look. Colours come from the caller; nothing here is tuning.
#
# gloss_circle and gloss_polygon also draw into a ShapeBatch (pass it as the
# canvas): each circle is otherwise a draw call of its own.


# A rounded, glass-like panel. `base` is the body colour (its alpha is kept).
static func gloss_rect(canvas: CanvasItem, rect: Rect2, base: Color, radius: float = 10.0, rim := Color(1, 1, 1, 0.55)) -> void:
	var body := StyleBoxFlat.new()
	body.bg_color = base
	body.set_corner_radius_all(int(radius))
	body.border_color = base.darkened(0.45)
	body.set_border_width_all(2)
	body.anti_aliasing = true
	canvas.draw_style_box(body, rect)
	# Highlight: the top ~45%, whiter at the top edge.
	var shine := StyleBoxFlat.new()
	shine.bg_color = Color(1, 1, 1, 0.28 * base.a)
	shine.corner_radius_top_left = int(radius)
	shine.corner_radius_top_right = int(radius)
	shine.corner_radius_bottom_left = int(radius * 1.6)
	shine.corner_radius_bottom_right = int(radius * 1.6)
	shine.anti_aliasing = true
	var top := Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, rect.size.y * 0.45))
	canvas.draw_style_box(shine, top)
	canvas.draw_line(top.position + Vector2(radius * 0.6, 1), Vector2(top.end.x - radius * 0.6, top.position.y + 1), rim, 1.5, true)


# gloss_rect's look drawn into a ShapeBatch (no StyleBoxes): the rounded
# body with its darker border, the highlight and the rim line. Lets a HUD
# draw many panels in one draw call.
static func gloss_rect_shapes(batch: ShapeBatch, rect: Rect2, base: Color, radius: float = 10.0,
		rim := Color(1, 1, 1, 0.55)) -> void:
	batch.draw_rounded_rect(rect, base.darkened(0.45), radius)
	batch.draw_rounded_rect(rect.grow(-2.0), base, maxf(radius - 2.0, 0.0))
	var top := Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, rect.size.y * 0.45))
	batch.draw_rounded_rect(top, Color(1, 1, 1, 0.28 * base.a), radius, radius * 1.6)
	batch.draw_line(top.position + Vector2(radius * 0.6, 1), Vector2(top.end.x - radius * 0.6, top.position.y + 1), rim, 1.5)


# A glossy bubble/orb: darker rim, lighter core and a crescent highlight.
static func gloss_circle(canvas: Object, center: Vector2, radius: float, base: Color) -> void:
	canvas.draw_circle(center, radius, base.darkened(0.25))
	canvas.draw_circle(center + Vector2(0, -radius * 0.06), radius * 0.9, base)
	canvas.draw_circle(center + Vector2(-radius * 0.12, -radius * 0.2), radius * 0.6, base.lightened(0.18))
	var shine := Color(1, 1, 1, 0.5 * base.a)
	canvas.draw_set_transform(center + Vector2(-radius * 0.1, -radius * 0.48), 0.0, Vector2(1.0, 0.5))
	canvas.draw_circle(Vector2.ZERO, radius * 0.55, shine)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Soft highlight inside an arbitrary polygon (cover tops): a lighter copy of
# the shape shrunk toward its top edge.
static func gloss_polygon(canvas: Object, polygon: PackedVector2Array, base: Color) -> void:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		box = box.expand(p)
	var anchor := Vector2(box.get_center().x, box.position.y)
	var inner := PackedVector2Array()
	for p in polygon:
		inner.append(anchor + (p - anchor) * Vector2(0.86, 0.5) + Vector2(0, box.size.y * 0.06))
	canvas.draw_colored_polygon(inner, Color(base.lightened(0.35), 0.55 * base.a))
