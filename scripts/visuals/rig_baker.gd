extends RefCounted
class_name RigBaker

const AIM_OFFSETS_META := &"aim_pivot_offsets"

# Renders a CutoutRig into one sprite sheet (a row per animation) and a
# SpriteFrames that uses it. Needs a real renderer: under --headless every
# frame comes back empty, so run the bake tool through xvfb-run in a cloud
# session (see tools/visuals/bake_rig.gd).
#
#   var result := await RigBaker.bake(rig, host_node)
#   result.sheet   Image with every frame
#   result.frames  SpriteFrames whose AtlasTextures point at `sheet_texture`
#
# Each frame also records how far the aim part's pivot has moved from its rest
# pose (SpriteFrames metadata, see aim_pivot_offset()), so a live aim arm rides
# the baked idle bob, walk cycle and hurt recoil.
#
# pack() and build_frames() are pure, so tests can check them headless.


## True when this process can render (not --headless).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Renders every frame. `host` is any node in the tree to hang the viewport
## on. The rig is moved into the viewport for the bake and put back after.
## Returns {errors, frames_by_anim: {name: Array[Image]},
## aim_offsets: {name: PackedVector2Array}} (empty without an aim part).
static func render(rig: CutoutRig, host: Node) -> Dictionary:
	var errors := rig.validate()
	if not can_render():
		errors.append("no renderer: run without --headless (xvfb-run in a cloud session)")
	if not errors.is_empty():
		return {"errors": errors, "frames_by_anim": {}, "aim_offsets": {}}

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
	var aim := rig.get_aim_part()
	if aim != null and aim.visible:
		aim.visible = false
		hidden.append(aim)
	for node in rig.get_tree().get_nodes_in_group(CutoutRig.HIDDEN_GROUP):
		if node is CanvasItem and rig.is_ancestor_of(node) and node.visible:
			node.visible = false
			hidden.append(node)

	var player := rig.get_animation_player()
	var rest_pivot := rig.get_aim_pivot()
	var frames_by_anim := {}
	var aim_offsets := {}
	for anim_name in rig.get_bake_list():
		var images: Array[Image] = []
		var offsets := PackedVector2Array()
		player.play(anim_name)
		player.pause()
		for t in rig.get_sample_times(anim_name):
			player.seek(t, true)
			await RenderingServer.frame_post_draw
			var img := viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			images.append(img)
			offsets.append(rig.get_aim_pivot() - rest_pivot)
		frames_by_anim[anim_name] = images
		if aim != null:
			aim_offsets[anim_name] = offsets
	player.stop()

	for node in hidden:
		node.visible = true
	viewport.remove_child(rig)
	rig.transform = old_transform
	if old_parent != null:
		old_parent.add_child(rig)
	viewport.queue_free()
	return {"errors": errors, "frames_by_anim": frames_by_anim, "aim_offsets": aim_offsets}


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
		fps: float, looping: Dictionary, aim_offsets: Dictionary = {}) -> SpriteFrames:
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
	if not aim_offsets.is_empty():
		frames.set_meta(AIM_OFFSETS_META, aim_offsets)
	return frames


## How far the aim part's pivot has moved from rest on this frame (Vector2.ZERO
## for frames baked without an aim part, or any other SpriteFrames).
static func aim_pivot_offset(frames: SpriteFrames, anim_name: StringName, frame: int) -> Vector2:
	if frames == null or not frames.has_meta(AIM_OFFSETS_META):
		return Vector2.ZERO
	var offsets: PackedVector2Array = frames.get_meta(AIM_OFFSETS_META).get(anim_name, PackedVector2Array())
	return offsets[frame] if frame >= 0 and frame < offsets.size() else Vector2.ZERO


## Renders, packs, and builds. `sheet_path` (a .png) is where the sheet will
## live; the SpriteFrames references it by that path. Returns {errors, sheet,
## frames}. Saving is the caller's job (see save()).
static func bake(rig: CutoutRig, host: Node, sheet_path: String) -> Dictionary:
	# Rest pose, before render() plays anything.
	var aim_scene: PackedScene = null
	var aim_pivot := rig.get_aim_pivot()
	var aim_copy := rig.make_aim_part_copy()
	if aim_copy != null:
		aim_scene = PackedScene.new()
		aim_scene.pack(aim_copy)
		aim_copy.free()
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
	var frames := build_frames(texture, packed.cells, order, rig.fps, looping, rendered.aim_offsets)
	return {"errors": PackedStringArray(), "sheet": packed.sheet, "frames": frames,
			"aim_scene": aim_scene, "aim_pivot": aim_pivot, "aim_rest_angle": rig.aim_part_rest_angle}


## Writes the sheet PNG, the SpriteFrames .tres (which points at the PNG)
## and, if the rig has an aim part, <frames>_aim.tscn.
static func save(result: Dictionary, sheet_path: String, frames_path: String) -> Error:
	var err := (result.sheet as Image).save_png(ProjectSettings.globalize_path(sheet_path))
	if err != OK:
		return err
	err = ResourceSaver.save(result.frames, frames_path)
	if err != OK or result.get("aim_scene") == null:
		return err
	return ResourceSaver.save(result.aim_scene, aim_scene_path(frames_path))


static func aim_scene_path(frames_path: String) -> String:
	return frames_path.get_basename() + "_aim.tscn"


## Points a VisualProfile at a bake: sprite frames, and the aim part fields
## when the rig had one. Body Scale / Offset are left alone.
static func apply_to_profile(result: Dictionary, frames_path: String, profile: VisualProfile) -> void:
	profile.sprite_frames = load(frames_path)
	if result.get("aim_scene") != null:
		profile.aim_part = load(aim_scene_path(frames_path))
		profile.aim_part_pivot = result.aim_pivot
		profile.aim_part_rest_angle = result.aim_rest_angle
