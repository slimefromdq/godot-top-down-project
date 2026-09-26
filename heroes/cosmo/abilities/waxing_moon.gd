extends PassiveAbility

# Waxing Moon: Cosmo's passive, in the "passive" slot. Owns her moon count
# and drives her primary: moons ARE its magazine.
#
#   * On spawn and every level change: count = moons reached in
#     moon_breakpoints -> gun.set_max_ammo(count, fill_new = true) (a new
#     moon arrives loaded) and gun.set_regen_interval() from
#     regen_interval_by_moons, if set.
#   * moon_waxed(count) + the wax cue on each new moon.
#   * The orbit: orbit_angle turns on physics time; get_moon_offset() is
#     where moon i sits, used both by the orbit visual and by her primary
#     (Moonshot launches the moon from its place in the orbit).
#   * Pips on the bar: moons ready / moons.

signal moon_waxed(count: int)

const ORBIT := preload("res://heroes/cosmo/vfx/moon_orbit.gd")

var moons: int = 0
var orbit_angle: float = 0.0


func get_wax_data() -> CosmoWaxingMoonData:
	return data as CosmoWaxingMoonData


func _ready() -> void:
	super()
	if actor == null:
		return
	var stats := get_stats()
	if stats != null:
		stats.level_changed.connect(func(_level: int): update_moons(true))
	var orbit: Node2D = ORBIT.new()
	orbit.passive = self
	actor.get_node(^"Visuals").add_child(orbit)    # fades with her (New Moon)
	# The gun is built before the passive (slot order), so this finds it.
	update_moons(false)


func get_gun() -> RangedAttackAbility:
	var hero := actor as Hero
	return hero.get_ranged_ability(get_wax_data().gun_slot) if hero != null else null


# Recount from her level; grows (or shrinks) the gun's magazine.
func update_moons(announce: bool) -> void:
	var count := get_wax_data().get_moon_count(get_level())
	var gun := get_gun()
	if count == moons or gun == null:
		return
	var gained := count > moons
	moons = count
	gun.set_max_ammo(count, true)
	var regen := get_wax_data().get_regen_interval(count)
	if regen > 0.0:
		gun.set_regen_interval(regen)
	if gained and announce:
		moon_waxed.emit(count)
		actor.trigger_cue(get_wax_data().wax_cue, {"moons": count})


# Where moon `index` of `count` sits relative to her, right now.
func get_moon_offset(index: int, count: int) -> Vector2:
	var radius := data.get_value(&"orbit_radius", get_stats())
	return Vector2.from_angle(orbit_angle + TAU * index / maxi(count, 1)) * radius


func get_hud_pips() -> Vector2i:
	var gun := get_gun()
	return Vector2i(gun.get_ammo() if gun != null else 0, moons)


func _physics_process(delta: float) -> void:
	super(delta)
	orbit_angle = fposmod(orbit_angle + data.get_value(&"orbit_speed", get_stats()) * delta, TAU)


static func find_on(actor: Node) -> Ability:
	var hero := actor as Hero
	if hero == null:
		return null
	var passive := hero.get_ability(&"passive")
	return passive if passive != null and passive.has_method(&"get_moon_offset") else null
