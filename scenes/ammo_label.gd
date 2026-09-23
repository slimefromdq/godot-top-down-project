extends Label
class_name AmmoLabel

@export var weapon_component: WeaponComponent

func _ready() -> void:
	weapon_component.ammo_changed.connect(_on_ammo_changed)
	text = "%d/%d" % [weapon_component.current_ammo, weapon_component.mag_capacity]
	
func _on_ammo_changed(current: int, maximum: int ) -> void:
	text = "%d/%d" % [current, maximum]
