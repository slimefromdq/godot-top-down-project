extends TempEffect
class_name MoteMagnetEffect

# Pulls loose Motes within values.pull_radius toward the hero at
# values.pull_speed px/s while it lasts. The bigger pickup radius is the item's
# status (MOTE_PICKUP_RADIUS multiplier), read by Mote. Only Motes this hero
# could take are pulled (not claimed against them, not their own lockout), and
# a full stack pulls nothing.


func _on_tick(delta: float) -> void:
	var carrier := MoteCarrier.find_on(hero)
	if carrier == null or not carrier.can_pick_up():
		return
	var radius := item.value_of(&"pull_radius", 700.0)
	var step := item.value_of(&"pull_speed", 900.0) * delta
	for node in hero.get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote == null or mote.is_queued_for_deletion() or mote.state != Mote.State.IDLE:
			continue
		var to_hero := hero.global_position - mote.global_position
		if to_hero.length() > radius or not mote.can_be_taken_by(hero):
			continue
		mote.global_position += to_hero.limit_length(step)
