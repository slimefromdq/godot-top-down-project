extends RefCounted
class_name DeathEvent

# Sent with HealthComponent.about_to_die, BEFORE the death happens.
#
# Signals in Godot call every listener immediately, one after another, before
# emit() returns. So HealthComponent can emit about_to_die, let any listener
# flip `cancelled` on this shared object, and then check it. That's how a
# revive ultimate cancels a death without the health code knowing it exists.

## The hit that would have killed. May be null for scripted deaths.
var info: DamageInfo
var cancelled: bool = false
## Health to set when cancelled. Clamped to at least 1.
var restore_health: float = 1.0
## Who cancelled it (for debugging and the damage log).
var cancelled_by: Object = null


func cancel(health_after: float, by: Object = null) -> void:
	# First canceller wins; a second revive shouldn't also fire and burn its
	# cooldown on the same death.
	if cancelled:
		return
	cancelled = true
	restore_health = health_after
	cancelled_by = by
