extends Resource
class_name VisualProfile

# Everything an actor looks like, in one .tres file. Create one per character
# (right-click in FileSystem > New Resource > VisualProfile) and assign it to
# that character's VisualsComponent. See docs/VISUALS_AND_AUDIO.md.

@export_group("Body")
## Animated body. Animations named idle, move, hurt, death are used
## automatically; any other name can be triggered from a VisualCue.
@export var sprite_frames: SpriteFrames
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
