extends RefCounted
class_name MapLayers

# Physics layer bits, named once so map code never uses magic numbers.
# Names match Project Settings > Layer Names > 2D Physics.
#
#                      blocks characters   blocks projectiles
#   WORLD      (1)            yes                 yes         walls, rocks, trees
#   LOW_COVER  (6)            yes                 no          low walls, crates
#   LEDGES     (7)     one way (climbing)         no          cliff edges
#   BARRIERS   (8)            yes                 yes         ability walls (ContainmentRing):
#                                                             no jumping over them, no sight blocked
#
# Characters mask WORLD | CHARACTERS | LOW_COVER | LEDGES, plus BARRIERS
# (added in code by Actor / TrainingDummy).
# Projectiles mask only WORLD (plus hurtboxes), so they fly over the rest.

const WORLD := 1 << 0
const CHARACTERS := 1 << 1
const PLAYER_HURTBOX := 1 << 2
const PROJECTILES := 1 << 3
const ENEMY_HURTBOX := 1 << 4
const LOW_COVER := 1 << 5
const LEDGES := 1 << 6
const BARRIERS := 1 << 7

## Layers an airborne character (jump pad arc) passes over.
const JUMPABLE := LOW_COVER | LEDGES
