extends Node2D

const MAP := preload("res://scenes/maps/dream_basin.tscn")
const HERO := preload("res://scenes/heroes/hero_base.tscn")
const JOSE := preload("res://heroes/jose/jose_definition.tres")

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var map: GameMap = MAP.instantiate()
	add_child(map)
	var bot: Hero = HERO.instantiate()
	bot.definition = JOSE
	bot.team = &"a"
	add_child(bot)
	bot.global_position = map.get_spawn_points(&"a")[0].global_position
	await get_tree().physics_frame
	var started := Time.get_ticks_usec()
	var navigation := BotNavigation.for_actor(bot)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	_check("Dream Basin navigation graph builds", navigation != null and navigation.graph.get_point_count() > 0)
	var route := navigation.path(bot.global_position, Vector2.ZERO)
	_check("spawn has route toward Cradle", route.size() > 2)
	var jump_found := false
	for node in get_tree().get_nodes_in_group(JumpPad.GROUP):
		if not map.is_ancestor_of(node):
			continue
		var pad := node as JumpPad
		var jump_route := navigation.path(pad.global_position, pad.get_landing_position())
		if _uses_link(jump_route, pad.global_position, pad.get_landing_position()):
			jump_found = true
			break
	_check("jump pad is a directed route", jump_found)
	var portal_found := false
	var chosen_portal: Teleporter
	for node in map.find_children("*", "Area2D", true, false):
		if node is Teleporter and node.can_send():
			var portal := node as Teleporter
			var portal_route := navigation.path(portal.global_position, portal.partner.global_position)
			if _uses_link(portal_route, portal.global_position, portal.partner.global_position):
				portal_found = true
				if chosen_portal == null or portal.global_position.distance_to(portal.partner.global_position) \
						> chosen_portal.global_position.distance_to(chosen_portal.partner.global_position):
					chosen_portal = portal
	_check("teleporter is a directed route", portal_found)
	if chosen_portal != null:
		bot.global_position = chosen_portal.global_position
		bot.set_bot_controlled(true)
		var input := bot.get_node(^"BotHeroInput") as BotHeroInput
		input.goal = chosen_portal.partner.global_position
		input.intent = &"travel"
		input._strategy_left = INF
		var arrived := false
		for frame in 180:
			await get_tree().physics_frame
			if bot.global_position.distance_to(chosen_portal.partner.global_position) < chosen_portal.radius:
				arrived = true
				break
		_check("bot waits for teleporter channel and arrives", arrived)
	print("Navigation build: %.1f ms, %d points" % [build_ms, navigation.graph.get_point_count()])
	await _check_walking_only(map, bot)
	print("BOT NAV TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


# Every area of Dream Basin is reachable on foot: with every jump pad and
# teleporter removed, bots still find a path from each spawn to every area
# (both bases, the Cradle, the Sunken Court floor, every Wild block, Ruins,
# Hollow, outskirts) and back.
func _check_walking_only(old_map: GameMap, bot: Hero) -> void:
	bot.set_bot_controlled(false)
	old_map.queue_free()
	await get_tree().process_frame
	var map: GameMap = MAP.instantiate()
	for node in map.find_children("*", "Area2D", true, false):
		if node is JumpPad or node is Teleporter:
			node.get_parent().remove_child(node)
			node.free()
	add_child(map)
	bot.global_position = map.get_spawn_points(&"a")[0].global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var navigation := BotNavigation.for_actor(bot)
	_check("walking-only graph has no links", navigation != null and navigation.teleport_entries.is_empty()
		and navigation._links.is_empty())
	var spawns := [map.get_spawn_points(&"a")[0].global_position, map.get_spawn_points(&"b")[0].global_position]
	var areas := {
		"Cradle": Vector2(0, 1320), "Court floor": Vector2(0, 250),
		"A Garden Court": Vector2(-4000, 2400), "B Garden Court": Vector2(4000, -2400),
		"Lawn L": Vector2(-3650, -420), "Lawn R": Vector2(3650, 420),
		"Terrace L": Vector2(-3600, -2400), "Terrace R": Vector2(3600, 2400),
		"Colonnade A": Vector2(-2400, 2040), "Colonnade B": Vector2(2400, -2040),
		"Hollow A": Vector2(-4580, 840), "Hollow B": Vector2(4580, -840),
		"Fountain Court A": Vector2(2000, 1440), "Fountain Court B": Vector2(-2000, -1440),
		"Cloister A": Vector2(-2000, 4380), "Promenade A": Vector2(3000, 4080),
		# Center-field pockets (geometry pass, phase 3).
		"Pool gate A": Vector2(305, 2060), "Pool gate B": Vector2(-305, -2060),
		"Ring inner track": Vector2(1072, 877), "Ring outer track": Vector2(1340, 1099),
		"Behind the flank kiosk": Vector2(2550, 760), "Flank screen, cliff side": Vector2(-2500, 0),
	}
	var bad := []
	for area in areas:
		for spawn in spawns:
			if navigation.path(spawn, areas[area]).size() < 2 or navigation.path(areas[area], spawn).size() < 2:
				bad.append(area)
				break
	_check("bots walk from both spawns to every area and back, no pads (%s)" % ", ".join(bad), bad.is_empty())


func _uses_link(route: PackedVector2Array, entry: Vector2, exit: Vector2) -> bool:
	for index in range(route.size() - 1):
		if route[index].distance_to(entry) < 1.0 and route[index + 1].distance_to(exit) < 1.0:
			return true
	return false


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
