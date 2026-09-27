extends Resource
class_name DreamerData

# The Dreamer itself (resources/match/dreamer.tres). Every number the match
# plays by (rings, ticks, wake, Lullaby) is in MatchRules; this is the body.

## The body blocks movement (low-cover layer: shots and sight pass).
@export var body_radius: float = 130.0
## The look. Its root gets setup_dreamer(dreamer) if it has that method.
## Gameplay never reads it; a sprite scene can replace it.
@export var look_scene: PackedScene
