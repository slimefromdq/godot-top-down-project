"""Dream Basin layout: the single source of truth for the test map.

Coordinates are Godot pixels, origin at map centre, +y is DOWN.
Team A (Dawn) spawns at the bottom, Team B (Dusk) at the top.

Only the "authored half" is written by hand:
  * the whole LEFT Wild,
  * the LOWER half of the basin (y >= 0),
  * the bottom band (A base, A plaza, A outskirts).
Everything is then rotated 180 degrees about the origin to make the B side,
so the map is exactly rotationally symmetric.

Authored numbers are in "authored space". Every helper multiplies POSITIONS
by SY (vertical stretch) but never sizes, so rocks stay round and walls keep
their thickness when the map is made taller. Change SY to resize the map.
"""

import math
import random

SCREEN_W, SCREEN_H = 1920, 1080
SY = 1.2                           # vertical stretch: 7.5 -> 9 screens tall
AUTH_HY = 4050                     # authored half-height (before SY)
MAP_W, MAP_H = 9600, round(2 * AUTH_HY * SY)   # 5 x 9 screens
HX, HY = MAP_W // 2, MAP_H // 2    # half extents (real pixels)

LEDGE_X = 2750      # |x| where the Wilds' cliff edge sits
WILD_Y = 2700       # |y| where the Wilds end (north/south cliffs)
BASIN_Y = 2350      # |y| where the basin meets the plazas / back road

# --------------------------------------------------------------------------
# Containers. Each item is a dict; "team" is "A", "B" or None (neutral).
# --------------------------------------------------------------------------
L = {
    "regions": [],      # floor tint polygons: {pts, kind, label}
    "full": [],         # full cover: blocks movement AND shots {pts, kind}
    "low": [],          # low cover: blocks movement only {pts, kind}
    "bushes": [],       # concealment only {x, y, r}
    "ledges": [],       # one-way cliff edges {a, b, drop} drop = unit vec high->low
    "stairs": [],       # {x, y, w, d, up} up = unit vec low->high
    "jump_pads": [],    # {x, y, tx, ty, name}
    "teleporters": [],  # {a:(x,y), b:(x,y), two_way, name}
    "speed_strips": [], # {x, y, w, h, dir}
    "markers": [],      # {x, y, kind, label}
    "lanes": [],        # sight lanes {a, b, label}
    "labels": [],       # {x, y, text, size}
}


def rock(x, y, r, seed, n=9, jitter=0.28, stretch=(1.0, 1.0), rot=0.0):
    """Irregular convex-ish blob, so clusters never look like a grid."""
    y = Y(y)
    rng = random.Random(seed)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.18, 0.18)
        rr = r * (1 + rng.uniform(-jitter, jitter * 0.6))
        px, py = math.cos(a) * rr * stretch[0], math.sin(a) * rr * stretch[1]
        c, s = math.cos(rot), math.sin(rot)
        pts.append((x + px * c - py * s, y + px * s + py * c))
    return pts


def Y(y):
    return y * SY


def rect(x0, y0, x1, y1):
    y0, y1 = Y(y0), Y(y1)
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def seg(ax, ay, bx, by, t):
    """Thick line segment as a rectangle polygon (walls, hedges)."""
    ay, by = Y(ay), Y(by)
    dx, dy = bx - ax, by - ay
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln * t / 2, dx / ln * t / 2
    ex, ey = dx / ln * t / 2, dy / ln * t / 2  # extend ends so corners meet
    return [(ax - ex + nx, ay - ey + ny), (bx + ex + nx, by + ey + ny),
            (bx + ex - nx, by + ey - ny), (ax - ex - nx, ay - ey - ny)]


# Natural pieces are drawn a bit smaller than authored, so they are easy to run
# around. One knob per kind instead of editing every radius.
SHRINK = {"tree": 0.72, "rock": 0.75, "lowrock": 0.8}
BUSH_SHRINK = 0.72


def _shrink(pts, kind):
    k = SHRINK.get(kind, 1.0)
    if k == 1.0:
        return pts
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


def full(pts, kind, team=None):
    L["full"].append({"pts": _shrink(pts, kind), "kind": kind, "team": team})


def low(pts, kind, team=None):
    L["low"].append({"pts": _shrink(pts, kind), "kind": kind, "team": team})


def poly(pts):
    """Polygon from authored points (y stretched)."""
    return [(x, Y(y)) for x, y in pts]


def circle(x, y, r, n=20):
    return [(x + r * math.cos(2 * math.pi * i / n), Y(y) + r * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def fountain(x, y, rim=170, team=None):
    """Round basin (low cover: shoot across the water) with a statue in the
    middle (full cover). Easy to circle, and a readable landmark."""
    low(circle(x, y, rim), "fountain", team)
    full(circle(x, y, 55, 10), "statue", team)


def building(x0, y0, x1, y1, team=None):
    """Small ruined building footprint (full cover)."""
    full(rect(x0, y0, x1, y1), "building", team)


def wall(ax, ay, bx, by, t=80, kind="wall", team=None):
    full(seg(ax, ay, bx, by, t), kind, team)


def hedge(ax, ay, bx, by, t=120):
    full(seg(ax, ay, bx, by, t), "hedge")


def lowwall(ax, ay, bx, by, t=50, kind="lowwall", team=None):
    low(seg(ax, ay, bx, by, t), kind, team)


def bush(x, y, r=110):
    L["bushes"].append({"x": x, "y": Y(y), "r": r * BUSH_SHRINK})


def ledge(ax, ay, bx, by, drop):
    L["ledges"].append({"a": (ax, Y(ay)), "b": (bx, Y(by)), "drop": drop})


def stair(x, y, w, d, up):
    L["stairs"].append({"x": x, "y": Y(y), "w": w, "d": d, "up": up})


def jump_pad(x, y, tx, ty, name):
    L["jump_pads"].append({"x": x, "y": Y(y), "tx": tx, "ty": Y(ty), "name": name})


def marker(x, y, kind, label="", team=None):
    L["markers"].append({"x": x, "y": Y(y), "kind": kind, "label": label, "team": team})


def label(x, y, text, size=150):
    L["labels"].append({"x": x, "y": Y(y), "text": text, "size": size})


def teleporter(a, b, two_way, name):
    L["teleporters"].append({"a": (a[0], Y(a[1])), "b": (b[0], Y(b[1])),
                             "two_way": two_way, "name": name})


def speed_strip(x, y, w, h, direction=(1, 0)):
    L["speed_strips"].append({"x": x, "y": Y(y), "w": w, "h": h, "dir": direction})


def lane(a, b, text):
    L["lanes"].append({"a": (a[0], Y(a[1])), "b": (b[0], Y(b[1])), "label": text})


# ==========================================================================
# REGIONS (floor tints)
# ==========================================================================
L["regions"] += [
    {"pts": rect(-LEDGE_X, 0, LEDGE_X, BASIN_Y), "kind": "basin", "team": "A"},
    {"pts": rect(-HX, -WILD_Y, -LEDGE_X, WILD_Y), "kind": "wild", "team": None},
    {"pts": rect(-HX, WILD_Y, HX, AUTH_HY), "kind": "outskirts", "team": "A"},
    {"pts": rect(-LEDGE_X, BASIN_Y, LEDGE_X, WILD_Y), "kind": "outskirts", "team": "A"},
    {"pts": rect(-1600, 2420, 1600, 3300), "kind": "plaza", "team": "A"},
    {"pts": rect(-1400, 3300, 1400, AUTH_HY), "kind": "base", "team": "A"},
    {"pts": poly([(-LEDGE_X, 850), (-1750, 850), (-1350, 1350), (-1350, BASIN_Y),
                  (-LEDGE_X, BASIN_Y)]), "kind": "ruins", "team": "A"},
]

# ==========================================================================
# LEFT WILD (authored whole; rotation makes the right Wild)
#   south third  = THE TANGLE   (overgrown hedge maze, CQC)
#   middle third = THE GLADE    (mid-range meadow)
#   THE HOLLOW   = secluded hedge pocket on the outer wall between Tangle and
#                  Glade: where your one-way spawn teleporter drops you.
#   north third  = STILT RIDGE  (open high ground, sniper perch)
# ==========================================================================

# --- Cliff edges (one-way ledges) ---------------------------------------
# Inner cliff facing the basin, broken by the basin stairwell (y -1200..-850).
ledge(-LEDGE_X, -WILD_Y, -LEDGE_X, -1200, (1, 0))
ledge(-LEDGE_X, -850, -LEDGE_X, WILD_Y, (1, 0))
# South cliff (Tangle -> Cloister yard), stairwell x -3900..-3500.
ledge(-HX, WILD_Y, -3900, WILD_Y, (0, 1))
ledge(-3500, WILD_Y, -LEDGE_X, WILD_Y, (0, 1))
# North cliff (Ridge -> B outskirts), stairwell x -3900..-3500.
ledge(-HX, -WILD_Y, -3900, -WILD_Y, (0, -1))
ledge(-3500, -WILD_Y, -LEDGE_X, -WILD_Y, (0, -1))

stair(-LEDGE_X + 160, -1025, 350, 320, (-1, 0))   # basin -> Ridge flank
stair(-3700, WILD_Y + 160, 400, 320, (0, -1))      # Cloister -> Tangle
stair(-3700, -WILD_Y - 160, 400, 320, (0, 1))      # B outskirts -> Ridge
# Rails that funnel the basin stairwell into a proper choke.
lowwall(-LEDGE_X + 20, -1220, -LEDGE_X + 380, -1220)
lowwall(-LEDGE_X + 20, -830, -LEDGE_X + 380, -830)

# --- The Tangle (y 900..2700): a walled hedge garden ---------------------
# Protection comes from the perimeter hedges (they block shots, so you have to
# come in to fight whoever is inside), not from tight corridors. The inside is
# a few loose rooms around a fountain, with 450+ px lanes between hedges.
hedge(-4800, 900, -3900, 900)      # north wall (also the Hollow's floor)
hedge(-3350, 900, -2950, 900)      # gap -3900..-3350 = main north entrance
hedge(-3420, 2700, -3420, 2350)    # screens the south stair from the east
hedge(-4400, 1250, -4400, 1650)    # west room divider
hedge(-3100, 1200, -3100, 1500)    # east screen (drop-off side)
hedge(-4300, 2250, -3850, 2250)    # south-west room
fountain(-3750, 1750)
full(rock(-4550, 2050, 100, 11), "tree")
full(rock(-3450, 1300, 100, 12), "tree")
full(rock(-3000, 2450, 90, 14), "tree")
full(rock(-4600, 1150, 90, 15), "tree")
for (bx, by) in [(-3650, 2300), (-4550, 1500), (-3000, 1850), (-4100, 1300), (-3350, 2050)]:
    bush(bx, by, 120)

# --- The Hollow: pocket at x -4800..-4300, y 520..900 --------------------
# Tangle hedge below, inner hedge to the east, outer map wall to the west, a
# tree and bush screen its mouth. Arrivals are hidden from the Glade, but the
# exit telegraph still shows to anyone who looks in.
hedge(-4300, 900, -4300, 560)
full(rock(-4600, 330, 100, 16), "tree")
bush(-4200, 420, 120)

# --- The Glade (y -750..750) --------------------------------------------
full(rock(-3350, -150, 150, 22, stretch=(1.2, 0.9)), "rock")
full(rock(-4150, -420, 120, 23), "tree")
full(rock(-3200, 560, 110, 24), "tree")
low(rock(-3850, 80, 120, 25, stretch=(1.5, 0.6)), "lowrock")
low(rock(-3000, -500, 100, 26, stretch=(0.6, 1.4)), "lowrock")
bush(-4600, -150, 140)
bush(-3600, 450, 110)
bush(-3050, 150, 100)

# --- Stilt Ridge (y -2650..-750) ----------------------------------------
# Crenellated low rocks along the lip: shoot between them, can't walk through.
for i, y in enumerate([-2450, -2050, -1650, -1400]):
    low(rock(-2880, y, 95, 31 + i, stretch=(0.6, 1.6)), "lowrock")
# Sniper nest: a stilt hut to hide behind while reloading.
building(-3380, -1950, -3140, -1760)
# Back path of trees along the outer wall = the flank that counters the nest.
for i, (tx, ty) in enumerate([(-4500, -950), (-4300, -1350), (-4550, -1700),
                              (-4250, -2100), (-4500, -2450)]):
    full(rock(tx, ty, 110, 40 + i), "tree")
for (bx, by) in [(-4100, -1100), (-4000, -1900), (-4150, -2400), (-3700, -1450)]:
    bush(bx, by, 120)
low(rock(-3650, -2250, 110, 47, stretch=(1.6, 0.7)), "lowrock")

# Jump pads onto the left Wild (both fire from the A half of the basin).
jump_pad(-2530, 300, -3450, 300, "Glade Spring")         # basin -> glade
jump_pad(-2400, 1950, -3250, 1850, "Ruins Updraft")     # ruins courtyard -> Tangle

# ==========================================================================
# LOWER BASIN (y >= 0): THE CRADLE, the A-side LULLABY RUINS, the DRIFTFIELD
# ==========================================================================
# The Cradle's open ring: a wide oval kept free of collision so the future
# objective (whatever it becomes) has room to move, and fights can circle.
L["markers"].append({"x": 0, "y": 0, "kind": "arena_ring",
                     "rx": 1600, "ry": Y(1300), "width": 600, "label": "", "team": None})

# Broken pillar ring inside the circuit. Angles avoid the Moon Aisle diagonal.
for i, deg in enumerate([15, 72, 102, 172]):
    a = math.radians(deg)
    full(rock(850 * math.cos(a), 850 * math.sin(a), 105, 60 + i, n=8, jitter=0.12),
         "pillar")
# Low toppled-column pieces near pillars: bash-and-slam fodder for Melody.
low(rock(560, 380, 90, 70, stretch=(1.7, 0.6), rot=0.6), "lowrock")
low(rock(-620, 470, 80, 71, stretch=(1.6, 0.6), rot=-0.5), "lowrock")
bush(250, 620, 110)
bush(-1000, 150, 100)

# --- Cradle Steps: the terraces between circuit and plaza choke ---------
lowwall(-1050, 1950, -600, 2010)
lowwall(600, 1990, 1150, 1900)
low(rock(0, 1780, 90, 72, stretch=(1.8, 0.7)), "lowrock")
full(rock(1300, 1950, 130, 74), "rock")
bush(-850, 2150, 100)
bush(850, 2150, 100)

# --- Lullaby Ruins (A): x -2750..-1350, y 850..2350, NE corner collapsed ----
# A roofless chapel. Four ways in: north door, the collapsed north-east breach
# (faces the Cradle), east door, south door; plus dropping in off the Tangle
# cliff. Inside is roomy: a pillar colonnade, an open courtyard with the
# updraft, and a side chapel holding the Dream Rift.
RW = "ruin"
wall(-2750, 850, -2350, 850, kind=RW)          # north wall, door -2350..-1950
wall(-1950, 850, -1750, 850, kind=RW)
wall(-1750, 850, -1660, 960, kind=RW)          # collapsed NE corner: breach
wall(-1440, 1240, -1350, 1350, kind=RW)
wall(-1350, 1350, -1350, 1750, kind=RW)        # east wall, door 1750..2100
wall(-1350, 2100, -1350, 2350, kind=RW)
wall(-2750, 2350, -2250, 2350, kind=RW)        # south wall, door -2250..-1850
wall(-1850, 2350, -1350, 2350, kind=RW)
# Colonnade across the nave: cover without corridors.
for i, x in enumerate([-2500, -2200, -1900]):
    full(rock(x, 1250, 55, 80 + i, n=8, jitter=0.08), "pillar")
# Side chapel (south-east) around the Dream Rift.
wall(-1850, 1850, -1600, 1850, kind=RW)
wall(-1850, 1850, -1850, 2050, kind=RW)
low(rect(-2200, 1580, -1980, 1660), "crate")   # altar: shoot over it
low(rock(-2550, 2150, 70, 83), "crate")
full(rock(-2000, 2150, 60, 84, n=7, jitter=0.1), "pillar")
bush(-2600, 1550, 100)
teleporter((-1580, 2150), (1580, -2150), True, "Dream Rift")

# --- Driftfield (A): open field under the A Ridge, x 1100..2750 ----------
for i, (x, y, r) in enumerate([(1900, 750, 130), (2350, 450, 110), (1250, 2150, 100)]):
    full(rock(x, y, r, 90 + i, stretch=(1.2, 0.9)), "rock")
fountain(1900, 1450)                    # the Driftfield's landmark
building(2250, 1480, 2480, 1650)        # ruined gatehouse under the Ridge
low(rock(2150, 1150, 100, 96, stretch=(1.6, 0.6), rot=0.4), "lowrock")
low(rock(1650, 1900, 90, 97, stretch=(1.5, 0.6), rot=-0.3), "lowrock")
low(rect(2380, 350, 2520, 470), "crate")
low(rect(2520, 420, 2640, 540), "crate")
for (bx, by) in [(2000, 1000), (1300, 1500), (2550, 1300), (1750, 2250)]:
    bush(bx, by, 120)

# ==========================================================================
# BOTTOM BAND: A base, Dawn Plaza, Cloister (west), Orchard (east)
# ==========================================================================
# Plaza north edge: two rock masses leave the Cradle Steps choke (x -320..320).
full(rock(-840, 2290, 500, 100, n=12, jitter=0.12, stretch=(1.0, 0.28)), "cliffrock")
full(rock(980, 2290, 640, 101, n=12, jitter=0.12, stretch=(1.0, 0.22)), "cliffrock")
# Driftfield/back-road gate (east) and Ruins south door (west) are the other
# two ways out of the plaza. Rocks between them keep those routes distinct.
full(rock(2330, 2330, 200, 102, stretch=(1.2, 0.5)), "cliffrock")
# The Sundial: plaza landmark that blocks line of sight into the spawn door.
full(rock(0, 2900, 190, 103, n=12, jitter=0.05), "sundial", "A")
# Broken plaza walls: full cover, and they cut the diagonals into the spawn door.
wall(-950, 2720, -600, 2960, kind="ruin", team="A")
wall(600, 2960, 950, 2720, kind="ruin", team="A")
bush(-1300, 3100, 110)
bush(1300, 3100, 110)
# Gate lanterns by the plaza's side gates (they also cut the long diagonal
# from the Ruins' south door into the spawn door).
for x in (-1250, 1250):
    full(circle(x, 2680, 60, 8), "statue", "A")

# Plaza side walls with gates to the back road at y 2450..2750
wall(-1600, 2750, -1600, 3300, kind="basewall", team="A")
wall(1600, 2750, 1600, 3300, kind="basewall", team="A")

# Lamplight Road speed strips (bidirectional), both sides of the plaza.
speed_strip(-2150, 2560, 900, 170)
speed_strip(2150, 2600, 900, 170)

# --- A base / spawn room: three exits + one-way comeback teleporter -------
wall(-1400, 3300, -300, 3300, kind="basewall", team="A")
wall(300, 3300, 1400, 3300, kind="basewall", team="A")
wall(-1400, 3300, -1400, 3500, kind="basewall", team="A")
wall(-1400, 3800, -1400, AUTH_HY, kind="basewall", team="A")
wall(1400, 3300, 1400, 3500, kind="basewall", team="A")
wall(1400, 3800, 1400, AUTH_HY, kind="basewall", team="A")
# Dawn Statue: breaks every straight line between the three spawn doors, so
# no one outside can see through the spawn room.
full(rock(0, 3640, 140, 104, n=12, jitter=0.05), "statue", "A")
for x in (-1080, 1080):
    full(rock(x, 3470, 85, 105 + (x > 0), n=8, jitter=0.08), "statue", "A")
for x in (-950, -700, -450, 450, 700, 950):
    marker(x, 3880, "spawn", "", "A")
teleporter((-1000, 3700), (-4580, 700), False, "Dawn Door")

# --- Cloister (west outskirts): spawn W door -> tight tunnel -> colonnade ---
# East half is a solid-walled tunnel (~320 px clear: pure CQC). West half is
# an open colonnade: pillars you can shoot and slip between.
wall(-1400, 3470, -1950, 3470, kind="cloister", team="A")
wall(-1400, 3830, -3050, 3830, kind="cloister", team="A")
full(rect(-3050, 3870, -1400, AUTH_HY), "cloister", "A")   # solid fill behind
# Side door out of the tunnel to the back road (x -2250..-1950 is the gap).
for i, x in enumerate([-2400, -2650, -2900]):
    full(rock(x, 3470, 65, 110 + i, n=7, jitter=0.08), "pillar", "A")
low(rect(-1850, 3610, -1740, 3700), "crate", "A")
# Cloister yard in front of the Tangle stair.
full(rock(-4400, 3300, 150, 112), "tree")
full(rock(-3300, 3150, 110, 113), "tree")
full(rock(-3400, 3650, 120, 114), "rock")   # plugs the tunnel line into spawn
bush(-4600, 2950, 110)
bush(-3500, 3700, 110)
full(rock(-2250, 2950, 130, 115), "rock")
bush(-2750, 3100, 100)
bush(-1900, 3150, 90)

# --- Orchard (east outskirts): open, scattered trees ---------------------
for i, (x, y, r) in enumerate([(2050, 3150, 110), (2450, 3550, 120), (3100, 3050, 130),
                               (3700, 3500, 110), (4350, 3100, 120), (2900, 3850, 100),
                               (4200, 3850, 100)]):
    full(rock(x, y, r, 120 + i), "tree")
for (bx, by) in [(2250, 2950), (3400, 3350), (4000, 3000), (2000, 3700)]:
    bush(bx, by, 110)
low(rock(3450, 2900, 100, 130, stretch=(1.6, 0.6)), "lowrock")

# ==========================================================================
# SIGHT LANES (validated by check.py: must be clear of full cover)
# ==========================================================================
lane((-1550, 1100), (1550, -1100), "Moon Aisle")
lane((3150, 2050), (-500, 1250), "Ridge Line (A)")
lane((3000, 2550), (3000, -800), "Wild Rail (A)")

# Region labels (authored half only; rotated copies get B names below)
label(-3750, 1450, "THE TANGLE", 150)
label(-3750, 0, "THE GLADE", 130)
label(-3750, -1600, "STILT RIDGE", 150)
label(0, 350, "THE CRADLE", 170)
label(-2050, 1450, "LULLABY RUINS", 110)
label(1950, 1650, "DRIFTFIELD", 130)
label(0, 3150, "DAWN PLAZA", 120)
label(0, 3950, "A SPAWN", 110)
label(-3900, 3450, "CLOISTER", 120)
label(3300, 3600, "ORCHARD", 130)


# ==========================================================================
# 180-degree rotation -> B side
# ==========================================================================
def _rot(p):
    return (-p[0], -p[1])


def _swap(team):
    return {"A": "B", "B": "A"}.get(team, team)


def build():
    out = {k: list(v) for k, v in L.items()}
    for r in L["regions"]:
        out["regions"].append({**r, "pts": [_rot(p) for p in r["pts"]], "team": _swap(r["team"])})
    for key in ("full", "low"):
        for o in L[key]:
            out[key].append({**o, "pts": [_rot(p) for p in o["pts"]], "team": _swap(o["team"])})
    for b in L["bushes"]:
        out["bushes"].append({**b, "x": -b["x"], "y": -b["y"]})
    for l in L["ledges"]:
        out["ledges"].append({"a": _rot(l["a"]), "b": _rot(l["b"]), "drop": _rot(l["drop"])})
    for s in L["stairs"]:
        out["stairs"].append({**s, "x": -s["x"], "y": -s["y"], "up": _rot(s["up"])})
    for j in L["jump_pads"]:
        out["jump_pads"].append({**j, "x": -j["x"], "y": -j["y"], "tx": -j["tx"], "ty": -j["ty"]})
    for t in L["teleporters"]:
        if t["name"] == "Dream Rift":
            continue  # already self-symmetric
        out["teleporters"].append({**t, "a": _rot(t["a"]), "b": _rot(t["b"]),
                                   "name": t["name"].replace("Dawn", "Dusk")})
    for s in L["speed_strips"]:
        out["speed_strips"].append({**s, "x": -s["x"], "y": -s["y"]})
    for m in L["markers"]:
        if m["kind"] == "arena_ring":
            continue
        out["markers"].append({**m, "x": -m["x"], "y": -m["y"], "team": _swap(m["team"]),
                               "label": m["label"]})
    for ln in L["lanes"]:
        if ln["label"] in ("Moon Aisle",):
            continue
        out["lanes"].append({"a": _rot(ln["a"]), "b": _rot(ln["b"]),
                             "label": ln["label"].replace("(A)", "(B)")})
    rename = {"DAWN PLAZA": "DUSK PLAZA", "A SPAWN": "B SPAWN", "THE TANGLE": "THE TANGLE",
              "THE CRADLE": None}
    for lb in L["labels"]:
        new = rename.get(lb["text"], lb["text"])
        if new is None:
            continue
        out["labels"].append({**lb, "x": -lb["x"], "y": -lb["y"], "text": new})
    return out
