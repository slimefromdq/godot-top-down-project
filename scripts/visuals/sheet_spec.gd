extends Resource
class_name SheetSpec

# Describes a character reference sheet laid out as a grid: one row per part
# (head, torso, legs, ...), one column per facing (down, down-right, ...).
# SheetCutter cuts each cell out of its flat background into
# <out_dir>/<row>/<column>.png. See docs/VISUALS_AND_AUDIO.md.

## The sheet image (res:// or an absolute path).
@export var source_path: String
## Pixel x of every vertical grid line, left to right (columns + 1 values).
@export var column_edges: PackedInt32Array = []
## Pixel y of every horizontal grid line, top to bottom (rows + 1 values).
@export var row_edges: PackedInt32Array = []
## One name per column, e.g. down, down_left, left, ...
@export var column_names: PackedStringArray = []
## One name per row (the part), e.g. head, torso, legs, ...
@export var row_names: PackedStringArray = []
## Columns to write. Empty = all. A mirrored rig only needs down, down_right,
## right, up_right and up.
@export var export_columns: PackedStringArray = []
## Folder the parts go in (res://...).
@export var out_dir: String
## Pixels trimmed off each side of a cell (skips the grid lines themselves).
@export var inset: int = 2

@export_group("Background keying")
## Pixels at least this bright and at most this saturated count as background
## when they're connected to the cell's border. The art's dark outline stops
## the fill, so white highlights inside a part survive.
@export_range(0.0, 1.0) var background_min_value: float = 0.78
@export_range(0.0, 1.0) var background_max_saturation: float = 0.09
## Pieces smaller than this share of the biggest piece are dropped (slivers of
## neighbouring cells).
@export_range(0.0, 1.0) var min_piece_ratio: float = 0.15
## Rows whose pale insides leak into the background (a white flame) get holes
## enclosed on all four sides restored from the sheet.
@export var restore_enclosed_rows: PackedStringArray = []
## Alpha given to restored pixels.
@export_range(0.0, 1.0) var restored_alpha: float = 0.9


## Problems that would stop a cut. Empty = ready.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if column_edges.size() != column_names.size() + 1:
		errors.append("column_edges needs one more value than column_names")
	if row_edges.size() != row_names.size() + 1:
		errors.append("row_edges needs one more value than row_names")
	for name in export_columns:
		if not column_names.has(name):
			errors.append("export column %s isn't in column_names" % name)
	if out_dir.is_empty():
		errors.append("out_dir is empty")
	return errors


## The pixel rect of one cell, inset.
func cell_rect(row: int, column: int) -> Rect2i:
	return Rect2i(column_edges[column] + inset, row_edges[row] + inset,
			column_edges[column + 1] - column_edges[column] - inset * 2,
			row_edges[row + 1] - row_edges[row] - inset * 2)
