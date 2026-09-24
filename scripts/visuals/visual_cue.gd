extends Resource
class_name VisualCue

# What to show when a cue fires. Every field is optional: a cue can spawn an
# effect, play a body animation, flash the body, shake the camera, or any mix.

## Effect scene to spawn (particles, AnimatedSprite2D, anything). If its root
## has a setup_cue(context: Dictionary) method it receives the cue context.
@export var effect_scene: PackedScene
## Parent the effect to the actor so it follows them (auras, trails).
## Otherwise it is left in the world where the cue happened (impacts, deaths).
@export var attach_to_actor: bool = false
## Free an attached effect after this many seconds. 0 = use context.duration
## if the cue provides one, else the effect frees itself.
@export var attached_duration: float = 0.0
## Rotate the effect to face the cue's direction (muzzle flashes, slashes).
@export var align_to_direction: bool = true
@export var offset: Vector2 = Vector2.ZERO
@export var scale: float = 1.0
## Multiplied into the effect's modulate. White keeps the scene's own colours.
@export var tint: Color = Color.WHITE

@export_group("Body")
## Animation to play on the body (AnimatedSprite2D or AnimationPlayer). Skipped
## if the animation doesn't exist.
@export var body_animation: StringName
## Flash the body with this colour. Alpha 0 = no flash.
@export var flash_color: Color = Color(1, 1, 1, 0)
@export var flash_duration: float = 0.1

@export_group("Screen")
## Camera shake strength, 0 to 1.
@export_range(0.0, 1.0, 0.05) var screen_shake: float = 0.0
