extends RefCounted
class_name MapClock

# The time map pieces run their cycles on: the match clock while a match is
# playing (so a debug clock jump moves every cycle with it, and both teams
# see the same schedule), else seconds since the scene started (Training
# Grounds, tests).
#
# phase(now, on, off, offset) -> [is_on, seconds_until_change] for a cycle
# that is `on` for `on` seconds then off for `off` seconds, repeating.


## Tests: when >= 0, used instead of every other clock.
static var override_time: float = -1.0


static func now(node: Node) -> float:
	if override_time >= 0.0:
		return override_time
	if node == null or not node.is_inside_tree():
		return 0.0
	var manager := MatchManager.find(node.get_tree())
	if manager != null and manager.is_playing():
		return manager.clock
	return Time.get_ticks_msec() / 1000.0


static func phase(t: float, on_time: float, off_time: float, offset: float = 0.0) -> Array:
	if off_time <= 0.0:
		return [true, INF]
	if on_time <= 0.0:
		return [false, INF]
	var period := on_time + off_time
	var p := fposmod(t + offset, period)
	return [true, on_time - p] if p < on_time else [false, period - p]
