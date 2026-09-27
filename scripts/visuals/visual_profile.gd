extends Resource
class_name VisualProfile

# Everything an actor looks like, in one .tres file. Create one per character
# (right-click in FileSystem > New Resource > VisualProfile) and assign it to
# that character's VisualsComponent. See docs/VISUALS_AND_AUDIO.md.

@export_group("Body")
## An 8-direction LiveRig scene drawn live as the body (see
## docs/VISUALS_AND_AUDIO.md). Takes the place of Sprite Frames / Texture.
@export var live_rig: PackedScene
## Animated body. Animations named idle, move, hurt, death are used
## automatically; any other name can be triggered from a VisualCue.
@export var sprite_frames: SpriteFrames
## Optional lower-body layer baked from a CutoutRig's legs_layer_paths. It's
## drawn behind the body, faces the aim with it, and plays its walk backwards
## while moving away from the aim. Same animation names and frame counts as
## sprite_frames.
@export var legs_frames: SpriteFrames
## Static body sprite, used when sprite_frames is empty.
@export var texture: Texture2D
@export var body_scale: Vector2 = Vector2.ONE
@export var body_offset: Vector2 = Vector2.ZERO
## Multiplied into the body's colours (darkens only). Good for subtle shading.
@export var body_modulate: Color = Color.WHITE
## Blended over the body; alpha is the strength. Good for faction/team colour
## on placeholder or shared art. Statuses and target highlight override it.
@export var body_tint: Color = Color(1, 1, 1, 0)
## Mirror the body horizontally when aiming left.
@export var flip_to_face_aim: bool = true
## Speed above which the "move" animation plays instead of "idle".
@export var move_animation_threshold: float = 20.0

@export_group("Aim Part")
## A live part (an arm holding the weapon) that rotates toward the aim every
## frame. Its scene origin is the pivot (the shoulder). Left out of a cutout
## rig's bake and exported by tools/visuals/bake_rig.gd.
@export var aim_part: PackedScene
## Pivot position relative to the body, facing right, before Body Scale.
## Bodies baked from a CutoutRig add each frame's pivot movement on top.
@export var aim_part_pivot: Vector2 = Vector2.ZERO
## Which way the part's art points at rotation 0 (90 = hanging down).
@export_range(-180.0, 180.0, 1.0, "degrees") var aim_part_rest_angle: float = 0.0
## Draw the part behind the body instead of in front.
@export var aim_part_behind_body: bool = false
## Also draw it behind the body while aiming up (away from the camera).
@export var aim_part_behind_when_aiming_up: bool = true
## How far up counts as "aiming up": the aim's upward component, 0 = level,
## 1 = straight up (0.5 = 30 degrees above level).
@export_range(0.0, 1.0, 0.05) var aim_part_up_threshold: float = 0.5

@export_group("Cues")
## Cue name -> what to show. Built-in names: hurt, heal, death, spawn, fire,
## reload, reload_done, dry_fire, ability_failed, plus each ability's
## ability_id (and <id>_end / <id>_hit where the ability documents them).
@export var cues: Dictionary[StringName, VisualCue] = {}

@export_group("Death")
## Extra effect played on anything THIS actor kills: a cosmetic kill effect.
@export var kill_effect: VisualCue
## Keep the actor around this long after death (e.g. for a death animation).
## The "death" animation's length is used automatically if it is longer.
@export var death_linger_time: float = 0.0

@export_group("Feedback")
@export var show_damage_numbers: bool = true
@export var damage_number_color: Color = Color(1, 0.95, 0.6)
@export var damage_number_scene: PackedScene = preload("res://effects/floating_text.tscn")
## Highlight colour when this actor is under the cursor as a valid target.
@export var target_highlight_color: Color = Color(1, 0.9, 0.3, 0.45)
