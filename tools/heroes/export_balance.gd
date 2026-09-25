extends Node

# Headless balance export (same data as Tools > Export Balance CSV):
#
#   godot --headless res://tools/heroes/export_balance.tscn -- [output.csv]
#
# Default output: res://balance/balance_export.csv. Exits non-zero on error.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "res://balance/balance_export.csv"
	var error := BalanceExporter.export_all(path)
	if error != "":
		printerr(error)
	else:
		print("Wrote ", ProjectSettings.globalize_path(path))
	get_tree().quit(1 if error != "" else 0)
