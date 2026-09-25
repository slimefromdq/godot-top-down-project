@tool
extends Resource
class_name StatScaling

# How one stat grows with level.
#
# Linear (no curve):   value = base + growth * (level - 1)
#
# With a curve, `growth` is still the average gain per level, but the curve
# decides WHEN that growth arrives. The curve's X axis is progress from level 1
# (x = 0) to level 20 (x = 1); its Y axis is the fraction of the total level-20
# growth unlocked so far. So:
#   * a straight diagonal (0,0) -> (1,1) is identical to linear;
#   * a curve that stays low then shoots up = a late-game spike (Cosmo);
#   * a curve that rises fast then flattens = an early-game hero.
# Every shape reaches the same value at level 20, which keeps heroes with
# different power curves comparable in the balance export.

## Formulas are defined over this many levels no matter the match level cap.
const LEVEL_DOMAIN := 20

@export var base: float = 0.0
## Average gain per level.
@export var growth: float = 0.0
## Optional: reshapes when growth arrives. Leave empty for linear.
@export var curve: Curve


static func make(base_value: float, growth_value: float = 0.0) -> StatScaling:
	var scaling := StatScaling.new()
	scaling.base = base_value
	scaling.growth = growth_value
	return scaling


func value_at(level: int) -> float:
	level = clampi(level, 1, LEVEL_DOMAIN)
	var total_growth := growth * (LEVEL_DOMAIN - 1)
	if curve == null:
		return base + growth * (level - 1)
	var progress := float(level - 1) / float(LEVEL_DOMAIN - 1)
	return base + total_growth * curve.sample_baked(progress)
