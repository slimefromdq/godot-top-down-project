extends Node

# Headless check that F3 map switching cycles the test maps and keeps the
# player's level.   godot --headless res://tools/heroes/map_switch_test.tscn

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# This node starts as the current scene, and changing scenes frees the
	# current scene. Hand that role to a throwaway node so the test survives.
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	var maps := GameRules.current().test_maps
	get_tree().change_scene_to_file(maps[0])
	await _frames(3)
	var player := get_tree().get_first_node_in_group(&"player") as Hero
	_check("first map has Avery as the player", player != null and player.definition.hero_id == &"avery", "")
	player.stats_component.set_level(6)
	await MapSwitcher.next_map()
	await _frames(2)
	_check("switched to the next map", get_tree().current_scene.scene_file_path == maps[1],
		get_tree().current_scene.scene_file_path)
	player = get_tree().get_first_node_in_group(&"player") as Hero
	_check("level carried across", player != null and player.stats_component.level == 6,
		str(player.stats_component.level) if player else "no player")
	await MapSwitcher.next_map()
	await _frames(2)
	_check("wraps back to the first map", get_tree().current_scene.scene_file_path == maps[0], "")
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
