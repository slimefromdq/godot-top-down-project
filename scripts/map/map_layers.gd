extends RefCounted
class_name MapLayers

# Physics layer bits, named once so map code never uses magic numbers.
# Names match Project Settings > Layer Names > 2D Physics.
#
#                      blocks characters   blocks projectiles  blocks sight
#   WORLD      (1)            yes                 yes             yes    hard walls, rocks, trees
#   LOW_COVER  (6)            yes                 no              no     props: low walls, crates
#   LEDGES     (7)     one way (climbing)         no              no     cliff edges
#   BARRIERS   (8)            yes                 yes             no     ability walls (ContainmentRing):
#                                                                        no jumping over them
#   PITS       (9)            yes                 no              no     pits and water: shoot across,
#                                                                        walk around (jump pads fly over)
#   CRYSTAL    (10)           yes                 yes             no     crystal/glass: see through,
#                                                                        can't shoot through
#
# Characters mask WORLD | CHARACTERS | LOW_COVER | LEDGES, plus BARRIERS,
# PITS and CRYSTAL (added in code by Actor / TrainingDummy / NeutralMonster:
# CHARACTER_EXTRA). Projectiles stop at GameRules.wall_mask (WORLD, BARRIERS,
# CRYSTAL) and sight at GameRules.sight_mask (WORLD); grass (Bush) hides by
# its own rule, not by layer. The four map obstacle types are WORLD (hard
# wall), PITS, CRYSTAL and grass; see scripts/map/cover_body.gd and bush.gd.

const WORLD := 1 << 0
const CHARACTERS := 1 << 1
const PLAYER_HURTBOX := 1 << 2
const PROJECTILES := 1 << 3
const ENEMY_HURTBOX := 1 << 4
const LOW_COVER := 1 << 5
const LEDGES := 1 << 6
const BARRIERS := 1 << 7
const PITS := 1 << 8
const CRYSTAL := 1 << 9

## Map obstacle layers every walking body adds to its mask in code.
const CHARACTER_EXTRA := BARRIERS | PITS | CRYSTAL
## Everything a walking body can't walk through (for pathing and probes).
const WALK_BLOCKERS := WORLD | LOW_COVER | LEDGES | PITS | CRYSTAL

## Layers an airborne character (jump pad arc) passes over.
const JUMPABLE := LOW_COVER | LEDGES | PITS
