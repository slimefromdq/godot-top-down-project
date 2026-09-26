extends Node

# Prints sustained DPS and 3 s burst for every carry at levels 1, 5, 10
# (the match cap), measured in-engine by dps_harness.gd.
#
#   godot --headless res://tools/heroes/dps_compare.tscn

const HARNESS := preload("res://tools/heroes/dps_harness.gd")
const HEROES := {
	"avery": "res://heroes/avery/avery.tscn",
	"jose": "res://heroes/jose/jose_hero.tscn",
	"melody": "res://heroes/melody/melody_hero.tscn",
	"cosmo": "res://heroes/cosmo/cosmo_hero.tscn",
}
const LEVELS := [1, 5, 10]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var harness: Node = HARNESS.new()
	add_child(harness)
	print("hero     level  sustained_dps  burst_3s")
	for hero in HEROES:
		for level in LEVELS:
			var dps: float = await harness.sustained(HEROES[hero], level)
			var burst: float = await harness.burst(HEROES[hero], level)
			print("%-8s %5d  %13.1f  %8.0f" % [hero, level, dps, burst])
	get_tree().quit()
