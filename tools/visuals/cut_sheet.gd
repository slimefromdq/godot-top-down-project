extends SceneTree

# Cuts a character reference sheet into part PNGs, one per part and facing.
#
#   godot --headless --script res://tools/visuals/cut_sheet.gd -- <spec.tres>
#
# The spec is a SheetSpec (grid lines, row/column names, output folder). Run
# `godot --headless --import` afterwards so the new PNGs import.
# Exits 0 on success, 1 on failure.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var spec := load(args[0]) as SheetSpec if not args.is_empty() else null
	if spec == null:
		push_error("usage: -- <spec.tres> (a SheetSpec)")
		quit(1)
		return
	var result := SheetCutter.cut(spec)
	for e in result.errors:
		push_error(e)
	print("cut %d parts into %s" % [result.written.size(), spec.out_dir])
	quit(0 if result.errors.is_empty() else 1)
