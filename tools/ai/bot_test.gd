extends Node2D

const HERO := preload("res://scenes/heroes/hero_base.tscn")
const JOSE := preload("res://heroes/jose/jose_definition.tres")

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	var bot: Hero = HERO.instantiate()
	bot.definition = JOSE
	bot.team = &"a"
	bot.bot_controlled = true
	bot.position = Vector2.ZERO
	add_child(bot)
	var enemy: Hero = HERO.instantiate()
	enemy.definition = JOSE
	enemy.team = &"b"
	enemy.position = Vector2(350, 0)
	add_child(enemy)
	await _frames(5)
	var input := bot.get_node_or_null(^"BotHeroInput") as BotHeroInput
	_check("bot controller attached", input != null)
	_check("roster contains both heroes", manager.get_roster().size() == 2)
	await _frames(20)
	_check("bot sees visible enemy", input.target == enemy)
	_check("bot aims toward enemy", bot.aim_direction.x > 0.5)
	var wall := StaticBody2D.new()
	wall.collision_layer = MapLayers.WORLD
	wall.collision_mask = 0
	wall.position = Vector2(175, 0)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30, 300)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)
	await _frames(20)
	_check("wall blocks enemy perception", input.target == null)
	bot.set_bot_controlled(false)
	_check("controller can be removed", bot.get_node_or_null(^"BotHeroInput") == null and bot.move_direction == Vector2.ZERO)
	bot.set_bot_controlled(true)
	_check("controller can be restored", bot.get_node_or_null(^"BotHeroInput") != null)
	wall.queue_free()
	await _frames(2)
	input = bot.get_node(^"BotHeroInput") as BotHeroInput
	input.skill = input.skill.duplicate()
	input.skill.dodge_chance = 1.0
	input.skill.reaction_time = 0.0
	var projectile_data := ProjectileData.new()
	projectile_data.speed = 150.0
	projectile_data.lifetime = 2.0
	projectile_data.radius = 40.0
	var projectile := Projectile.fire(self, projectile_data, bot.global_position + Vector2(130, 0),
		Vector2.LEFT, DamageInfo.create(0.0, enemy))
	var dodged := false
	for frame in 30:
		await get_tree().physics_frame
		if input.action == &"dodge":
			dodged = true
			break
	_check("bot sidesteps an approaching projectile", dodged)
	if is_instance_valid(projectile):
		projectile.queue_free()
	projectile = null
	projectile_data = null
	var filled := DebugTools.fill_with_bots(1)
	await _frames(3)
	_check("fill creates two teams of six", filled == 10 and manager.get_roster(&"a").size() == 6
		and manager.get_roster(&"b").size() == 6)
	var tanks := 0
	for member in manager.get_roster():
		if member.definition.role == HeroDefinition.Role.TANK:
			tanks += 1
	_check("fill includes tanks", tanks >= 2)
	DebugTools.set_bot_overlay_enabled(true)
	_check("bot overlay can be enabled", is_instance_valid(DebugTools._bot_overlay))
	await _frames(2)
	DebugTools.set_bot_overlay_enabled(false)
	DebugTools.clear_bots()
	await _frames(2)
	bot.queue_free()
	enemy.queue_free()
	manager.queue_free()
	await _frames(2)
	print("BOT TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
