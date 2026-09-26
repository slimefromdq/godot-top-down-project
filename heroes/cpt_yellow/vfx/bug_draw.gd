extends RefCounted

# Placeholder art for Cpt. Yellow's army: one bug drawn with primitives,
# shared by every effect so the swarm reads as one thing.

const BODY := Color(1.0, 0.82, 0.1)
const STRIPE := Color(0.18, 0.13, 0.02)
const WING := Color(1.0, 1.0, 0.9, 0.55)


# A bug at `at`, facing `facing`, `size` px long. `flap` 0..1 animates wings.
static func draw_bug(canvas: CanvasItem, at: Vector2, facing: Vector2, size: float,
		alpha: float = 1.0, flap: float = 0.0) -> void:
	var f := facing.normalized() if facing != Vector2.ZERO else Vector2.RIGHT
	var side := f.orthogonal()
	var wing := WING
	wing.a *= alpha
	var spread := lerpf(0.35, 0.9, flap)
	canvas.draw_circle(at + (side * spread - f * 0.1) * size * 0.45, size * 0.28, wing)
	canvas.draw_circle(at + (-side * spread - f * 0.1) * size * 0.45, size * 0.28, wing)
	var body := BODY
	body.a *= alpha
	canvas.draw_circle(at, size * 0.32, body)
	canvas.draw_circle(at + f * size * 0.3, size * 0.2, body)
	var stripe := STRIPE
	stripe.a *= alpha
	canvas.draw_line(at + side * size * 0.28 - f * size * 0.06, at - side * size * 0.28 - f * size * 0.06,
		stripe, maxf(size * 0.08, 1.0))
	canvas.draw_circle(at + f * size * 0.42, size * 0.07, stripe)
