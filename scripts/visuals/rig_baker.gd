extends RefCounted
class_name RigBaker

# Renders a CutoutRig into one sprite sheet (a row per animation) and a
# SpriteFrames that uses it. Needs a real renderer: under --headless every
# frame comes back empty, so run the bake tool through xvfb-run in a cloud
# session (see tools/visuals/bake_rig.gd).
#
#   var result := await RigBaker.bake(rig, host_node)
#   result.sheet   Image with every frame
#   result.frames  SpriteFrames whose AtlasTextures point at `sheet_texture`
#
# pack() and build_frames() are pure, so tests can check them headless.


## True when this process can render (not --headless).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Renders every frame. `host` is any node in the tree to hang the viewport
## on. The rig is moved into the viewport for the bake and put back after.
## Returns {errors, frames_by_anim: {name: Array[Image]}} .
static func render(rig: CutoutRig, host: Node) -> Dictionary:
	var errors := rig.validate()
	if not can_render():
		errors.append("no renderer: run without --headless (xvfb-run in a cloud session)")
	if not errors.is_empty():
		return {"errors": errors, "frames_by_anim": {}}

	var viewport := SubViewport.new()
	viewport.size = rig.frame_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	host.add_child(viewport)

	var old_parent := rig.get_parent()
	var old_transform := rig.transform
	if old_parent != null:
		old_parent.remove_child(rig)
	viewport.add_child(rig)
	rig.position = Vector2(rig.frame_size) * 0.5
	rig.scale = Vector2.ONE * rig.bake_scale
	rig.rotation = 0.0

	var hidden: Array[CanvasItem] = []
	for node in rig.get_tree().get_nodes_in_group(CutoutRig.HIDDEN_GROUP):
		if node is CanvasItem and rig.is_ancestor_of(node) and node.visible:
			node.visible = false
			hidden.append(node)

	var player := rig.get_animation_player()
	var frames_by_anim := {}
	for anim_name in rig.get_bake_list():
		var images: Array[Image] = []
		player.play(anim_name)
		player.pause()
		for t in rig.get_sample_times(anim_name):
			player.seek(t, true)
			await RenderingServer.frame_post_draw
			var img := viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			images.append(img)
		frames_by_anim[anim_name] = images
	player.stop()

	for node in hidden:
		node.visible = true
	viewport.remove_child(rig)
	rig.transform = old_transform
	if old_parent != null:
		old_parent.add_child(rig)
	viewport.queue_free()
	return {"errors": errors, "frames_by_anim": frames_by_anim}


## Lays frames out one animation per row, left to right.
## Returns {sheet: Image, cells: {name: Array[Rect2i]}}.
static func pack(frames_by_anim: Dictionary, order: Array[StringName], frame_size: Vector2i) -> Dictionary:
	var columns := 1
	for anim_name in order:
		columns = maxi(columns, frames_by_anim[anim_name].size())
	var sheet := Image.create_empty(frame_size.x * columns, frame_size.y * maxi(1, order.size()),
			false, Image.FORMAT_RGBA8)
	var cells := {}
	for row in order.size():
		var anim_name: StringName = order[row]
		var rects: Array[Rect2i] = []
		var images: Array = frames_by_anim[anim_name]
		for col in images.size():
			var at := Vector2i(col * frame_size.x, row * frame_size.y)
			var img: Image = images[col]
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, frame_size), at)
			rects.append(Rect2i(at, frame_size))
		cells[anim_name] = rects
	return {"sheet": sheet, "cells": cells}


## SpriteFrames over `sheet_texture` using the rects from pack().
static func build_frames(sheet_texture: Texture2D, cells: Dictionary, order: Array[StringName],
		fps: float, looping: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim_name in order:
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, looping.get(anim_name, true))
		for rect: Rect2i in cells[anim_name]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet_texture
			atlas.region = Rect2(rect)
			frames.add_frame(anim_name, atlas)
	return frames


## Renders, packs, and builds. `sheet_path` (a .png) is where the sheet will
## live; the SpriteFrames references it by that path. Returns {errors, sheet,
## frames}. Saving is the caller's job (see save()).
static func bake(rig: CutoutRig, host: Node, sheet_path: String) -> Dictionary:
	var rendered: Dictionary = await render(rig, host)
	if not rendered.errors.is_empty():
		return {"errors": rendered.errors, "sheet": null, "frames": null}
	var order := rig.get_bake_list()
	var looping := {}
	for anim_name in order:
		looping[anim_name] = rig.is_looping(anim_name)
	var packed := pack(rendered.frames_by_anim, order, rig.frame_size)
	var texture := ImageTexture.create_from_image(packed.sheet)
	texture.take_over_path(sheet_path)
	var frames := build_frames(texture, packed.cells, order, rig.fps, looping)
	return {"errors": PackedStringArray(), "sheet": packed.sheet, "frames": frames}


## Writes the sheet PNG and the SpriteFrames .tres (which points at the PNG).
static func save(result: Dictionary, sheet_path: String, frames_path: String) -> Error:
	var err := (result.sheet as Image).save_png(ProjectSettings.globalize_path(sheet_path))
	if err != OK:
		return err
	return ResourceSaver.save(result.frames, frames_path)
