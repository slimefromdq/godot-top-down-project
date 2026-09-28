extends Resource
class_name MapMoodProfile

# The map's slow colour mood over a match: a CanvasModulate colour sampled
# from keyframes on the match clock (seconds of PLAYING). Keyframes are
# interpolated linearly; before the first / after the last, they hold.

@export var times := PackedFloat32Array([0.0])
@export var colors := PackedColorArray([Color.WHITE])
## Seconds to ease between the sampled colour and the shown one (smooths
## clock jumps from the debug panel).
@export var smoothing: float = 1.5


func sample(t: float) -> Color:
	var n := mini(times.size(), colors.size())
	if n == 0:
		return Color.WHITE
	if t <= times[0]:
		return colors[0]
	for i in range(1, n):
		if t <= times[i]:
			var span := times[i] - times[i - 1]
			var w := 1.0 if span <= 0.0 else (t - times[i - 1]) / span
			return colors[i - 1].lerp(colors[i], w)
	return colors[n - 1]
