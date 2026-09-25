extends RefCounted
class_name MapLayers

# Physics layer bits, named once so map code never uses magic numbers.
# Names match Project Settings > Layer Names > 2D Physics.
#
#                      blocks characters   blocks projectiles
#   WORLD      (1)            yes                 yes         walls, rocks, trees
#   LOW_COVER  (6)            yes                 no          low walls, crates
#   LEDGES     (7)     one way (climbing)         no          cliff edges
#
# Characters mask WORLD | CHARACTERS | LOW_COVER | LEDGES.
# Projectiles mask only WORLD (plus hurtboxes), so they fly over the rest.

const WORLD := 1 << 0
const CHARACTERS := 1 << 1
const PLAYER_HURTBOX := 1 << 2
const PROJECTILES := 1 << 3
const ENEMY_HURTBOX := 1 << 4
const LOW_COVER := 1 << 5
const LEDGES := 1 << 6

## Layers an airborne character (jump pad arc) passes over.
const JUMPABLE := LOW_COVER | LEDGES
