extends Node2D
class_name NeutralCamp

# A spot on the map where a neutral objective lives: a jungle camp or the
# Nightmare's lair (Dream Basin places them from tools/dream_basin). It
# holds no timers of its own: the ObjectiveDirector drives every camp on
# the match clock and spawns its monsters here. This node shows the camp on
# the minimap (a paw for a jungle camp, a big horned skull for an announced
# objective like the Nightmare) and on the ground while it's up, and gives
# announced objectives an off-screen arrow.

const GROUP := &"neutral_camps"
const MONSTER_SCENE := "res://scenes/match/neutral_monster.tscn"

enum CampState {
	WAITING,    ## Not up yet (or respawning).
	WARNING,    ## Announced; spawns at the scheduled time.
	ALIVE,      ## Monsters up.
	GONE,       ## Killed and never coming back (respawn_time 0).
}

@export var data: NeutralData
## Shown in banners ("The Nightmare awakens in the Cradle").
@export var display_name: String = ""

var state: CampState = CampState.WAITING
## Match-clock time of the next spawn (INF = never).
var next_spawn_time: float = INF
var monsters: Array[NeutralMonster] = []
## Minimap objective: not fogged for announced camps.
var minimap_fogged: bool = true
var arrow_color := Color("c084fc")

var _t := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(&"minimap_objectives")


func _ready() -> void:
	z_index = -6
	if data != null:
		minimap_fogged = not data.announce
		arrow_color = data.icon_color
	if display_name == "" and data != null:
		display_name = data.display_name


func get_display_name() -> String:
	return display_name if display_name != "" else (data.display_name if data != null else str(name))


func is_alive() -> bool:
	return state == CampState.ALIVE


func get_living_monsters() -> Array[NeutralMonster]:
	var result: Array[NeutralMonster] = []
	for monster in monsters:
		if is_instance_valid(monster) and not monster.health_component.is_dead():
			result.append(monster)
	return result


## Spawn this camp's monsters at `level`. The director calls it.
func spawn(level: int) -> Array[NeutralMonster]:
	monsters.clear()
	var scene: PackedScene = load(MONSTER_SCENE)
	var count := data.count if data != null else 1
	for i in count:
		var monster: NeutralMonster = scene.instantiate()
		monster.data = data
		monster.level = level
		monster.camp = self
		var offset := Vector2.ZERO if count == 1 \
			else Vector2.from_angle(TAU * i / count - PI / 2.0) * (data.pack_spread if data != null else 90.0)
		monster.home = global_position + offset
		monster.position = global_position + offset
		get_tree().current_scene.add_child(monster)
		monsters.append(monster)
	state = CampState.ALIVE
	if data != null and data.announce:
		add_to_group(&"offscreen_arrows")
	return monsters


## Remove every monster (debug, or a test resetting the map).
func despawn() -> void:
	for monster in monsters:
		if is_instance_valid(monster):
			monster.queue_free()
	monsters.clear()
	if is_in_group(&"offscreen_arrows"):
		remove_from_group(&"offscreen_arrows")


func on_cleared(respawns: bool) -> void:
	monsters.clear()
	state = CampState.WAITING if respawns else CampState.GONE
	if is_in_group(&"offscreen_arrows"):
		remove_from_group(&"offscreen_arrows")


## Only a live camp's arrow shows.
func offscreen_arrow_for(_viewer: Node) -> Dictionary:
	if state != CampState.ALIVE:
		return {}
	return {"color": arrow_color, "scale": 1.3}


func draw_minimap_icon(canvas: CanvasItem, at: Vector2, _viewer_team: StringName) -> void:
	if state != CampState.ALIVE and state != CampState.WARNING:
		return
	var big := data != null and data.announce
	var color := data.icon_color if data != null else Color("c084fc")
	if state == CampState.WARNING:
		color.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
	var r := 8.0 if big else 4.0
	canvas.draw_circle(at, r + 1.5, Color.BLACK)
	canvas.draw_circle(at, r, color)
	if big:
		for side in [-1.0, 1.0]:
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(side * 4.0, -5.0),
				at + Vector2(side * 8.0, -5.0), at + Vector2(side * 10.0, -14.0)]), Color.BLACK)
		canvas.draw_circle(at + Vector2(-3, -1), 1.8, Color.BLACK)
		canvas.draw_circle(at + Vector2(3, -1), 1.8, Color.BLACK)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# A faint ring on the ground where the camp is (brighter while it's up, and
# pulsing while announced).
func _draw() -> void:
	if data == null or state == CampState.GONE:
		return
	var radius := data.size * 0.5 + data.pack_spread * (1.0 if data.count > 1 else 0.0) + 40.0
	var alpha := 0.35 if state == CampState.ALIVE else 0.12
	if state == CampState.WARNING:
		alpha = 0.3 + 0.3 * sin(_t * 6.0)
	draw_circle(Vector2.ZERO, radius, Color(data.color, alpha * 0.25))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(data.color, alpha), 5.0, true)
