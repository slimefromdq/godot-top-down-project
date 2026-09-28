extends RefCounted
class_name SheetCutter

# Cuts a character sheet (SheetSpec) into one transparent PNG per part and
# facing: flood-fills the flat background in from each cell's border, drops
# small stray pieces, and trims to the art. Works headless.
#
#   var result := SheetCutter.cut(spec)    # {errors, written: [paths]}
#
# cut_cell() is pure, so tests can feed it a made-up image.


static func cut(spec: SheetSpec) -> Dictionary:
	var errors := spec.validate()
	var sheet: Image = null
	if errors.is_empty():
		var path := ProjectSettings.globalize_path(spec.source_path)
		sheet = Image.load_from_file(path)
		if sheet == null or sheet.is_empty():
			errors.append("can't read %s" % spec.source_path)
	if not errors.is_empty():
		return {"errors": errors, "written": PackedStringArray()}
	sheet.convert(Image.FORMAT_RGBA8)
	var written := PackedStringArray()
	for row in spec.row_names.size():
		var part: String = spec.row_names[row]
		var restore := spec.restore_enclosed_rows.has(part)
		var dir := spec.out_dir.path_join(part)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for column in spec.column_names.size():
			var facing: String = spec.column_names[column]
			if not spec.export_columns.is_empty() and not spec.export_columns.has(facing):
				continue
			var image := cut_cell(sheet, spec.cell_rect(row, column), spec, restore)
			var out := dir.path_join(facing + ".png")
			var err := image.save_png(ProjectSettings.globalize_path(out))
			if err != OK:
				errors.append("saving %s: %s" % [out, error_string(err)])
			else:
				written.append(out)
	return {"errors": errors, "written": written}


## One cell of `sheet`, background removed and trimmed to the art.
static func cut_cell(sheet: Image, rect: Rect2i, spec: SheetSpec, restore_enclosed := false) -> Image:
	var source := sheet.get_region(rect)
	source.convert(Image.FORMAT_RGBA8)
	var part := source.duplicate() as Image
	_key_background(part, spec)
	_drop_small_pieces(part, spec.min_piece_ratio)
	if restore_enclosed:
		_restore_enclosed(part, source, spec.restored_alpha)
	var used := part.get_used_rect()
	return part.get_region(used) if used.size != Vector2i.ZERO else part


static func _is_background(c: Color, spec: SheetSpec) -> bool:
	return c.a < 0.01 or (c.v >= spec.background_min_value and c.s <= spec.background_max_saturation)


# Flood fill from the border through background-coloured pixels.
static func _key_background(part: Image, spec: SheetSpec) -> void:
	var w := part.get_width()
	var h := part.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or seen[p.y * w + p.x] == 1:
			continue
		seen[p.y * w + p.x] = 1
		if not _is_background(part.get_pixelv(p), spec):
			continue
		part.set_pixelv(p, Color(0, 0, 0, 0))
		stack.append(p + Vector2i.RIGHT)
		stack.append(p + Vector2i.LEFT)
		stack.append(p + Vector2i.UP)
		stack.append(p + Vector2i.DOWN)


# Label connected opaque pieces; clear the ones much smaller than the biggest.
static func _drop_small_pieces(part: Image, min_ratio: float) -> void:
	var w := part.get_width()
	var h := part.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	var sizes: Array[int] = [0]
	for y in h:
		for x in w:
			if label[y * w + x] != 0 or part.get_pixel(x, y).a == 0.0:
				continue
			var id := sizes.size()
			var count := 0
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or label[q.y * w + q.x] != 0 \
						or part.get_pixelv(q).a == 0.0:
					continue
				label[q.y * w + q.x] = id
				count += 1
				stack.append(q + Vector2i.RIGHT)
				stack.append(q + Vector2i.LEFT)
				stack.append(q + Vector2i.UP)
				stack.append(q + Vector2i.DOWN)
			sizes.append(count)
	var biggest: int = sizes.max()
	for y in h:
		for x in w:
			var l := label[y * w + x]
			if l != 0 and sizes[l] < biggest * min_ratio:
				part.set_pixel(x, y, Color(0, 0, 0, 0))


# Keyed pixels with art on all four sides were inside the part: put them back.
static func _restore_enclosed(part: Image, source: Image, alpha: float) -> void:
	var w := part.get_width()
	var h := part.get_height()
	var first_x := PackedInt32Array()
	var last_x := PackedInt32Array()
	var first_y := PackedInt32Array()
	var last_y := PackedInt32Array()
	first_x.resize(h)
	last_x.resize(h)
	first_y.resize(w)
	last_y.resize(w)
	first_x.fill(w)
	last_x.fill(-1)
	first_y.fill(h)
	last_y.fill(-1)
	for y in h:
		for x in w:
			if part.get_pixel(x, y).a > 0.0:
				first_x[y] = mini(first_x[y], x)
				last_x[y] = maxi(last_x[y], x)
				first_y[x] = mini(first_y[x], y)
				last_y[x] = maxi(last_y[x], y)
	for y in h:
		for x in w:
			if part.get_pixel(x, y).a > 0.0:
				continue
			if x > first_x[y] and x < last_x[y] and y > first_y[x] and y < last_y[x]:
				var c := source.get_pixel(x, y)
				c.a = alpha
				part.set_pixel(x, y, c)
