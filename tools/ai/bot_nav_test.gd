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
	print("BOT NAV TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


func _uses_link(route: PackedVector2Array, entry: Vector2, exit: Vector2) -> bool:
	for index in range(route.size() - 1):
		if route[index].distance_to(entry) < 1.0 and route[index + 1].distance_to(exit) < 1.0:
			return true
	return false


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
