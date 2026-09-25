"""Dream Basin layout: the single source of truth for the test map.

Coordinates are Godot pixels, origin at map centre, +y is DOWN.
Team A (Dawn) spawns at the bottom, Team B (Dusk) at the top.

Only the "authored half" is written by hand:
  * the whole LEFT Wild,
  * the LOWER half of the basin (y >= 0),
  * the bottom band (A base, A plaza, A outskirts).
Everything is then rotated 180 degrees about the origin to make the B side,
so the map is exactly rotationally symmetric.
"""

import math
import random

SCREEN_W, SCREEN_H = 1920, 1080
MAP_W, MAP_H = 9600, 8100          # 5 x 7.5 screens
HX, HY = MAP_W // 2, MAP_H // 2    # half extents

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
    rng = random.Random(seed)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.18, 0.18)
        rr = r * (1 + rng.uniform(-jitter, jitter * 0.6))
        px, py = math.cos(a) * rr * stretch[0], math.sin(a) * rr * stretch[1]
        c, s = math.cos(rot), math.sin(rot)
        pts.append((x + px * c - py * s, y + px * s + py * c))
    return pts


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def seg(ax, ay, bx, by, t):
    """Thick line segment as a rectangle polygon (walls, hedges)."""
    dx, dy = bx - ax, by - ay
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln * t / 2, dx / ln * t / 2
    ex, ey = dx / ln * t / 2, dy / ln * t / 2  # extend ends so corners meet
    return [(ax - ex + nx, ay - ey + ny), (bx + ex + nx, by + ey + ny),
            (bx + ex - nx, by + ey - ny), (ax - ex - nx, ay - ey - ny)]


def full(pts, kind, team=None):
    L["full"].append({"pts": pts, "kind": kind, "team": team})


def low(pts, kind, team=None):
    L["low"].append({"pts": pts, "kind": kind, "team": team})


def wall(ax, ay, bx, by, t=80, kind="wall", team=None):
    full(seg(ax, ay, bx, by, t), kind, team)


def hedge(ax, ay, bx, by, t=120):
    full(seg(ax, ay, bx, by, t), "hedge")


def lowwall(ax, ay, bx, by, t=50, kind="lowwall", team=None):
    low(seg(ax, ay, bx, by, t), kind, team)


def bush(x, y, r=110):
    L["bushes"].append({"x": x, "y": y, "r": r})


def ledge(ax, ay, bx, by, drop):
    L["ledges"].append({"a": (ax, ay), "b": (bx, by), "drop": drop})


def stair(x, y, w, d, up):
    L["stairs"].append({"x": x, "y": y, "w": w, "d": d, "up": up})


def jump_pad(x, y, tx, ty, name):
    L["jump_pads"].append({"x": x, "y": y, "tx": tx, "ty": ty, "name": name})


def marker(x, y, kind, label="", team=None):
    L["markers"].append({"x": x, "y": y, "kind": kind, "label": label, "team": team})


def label(x, y, text, size=150):
    L["labels"].append({"x": x, "y": y, "text": text, "size": size})


# ==========================================================================
# REGIONS (floor tints)
# ==========================================================================
L["regions"] += [
    {"pts": rect(-LEDGE_X, 0, LEDGE_X, BASIN_Y), "kind": "basin", "team": "A"},
    {"pts": rect(-HX, -WILD_Y, -LEDGE_X, WILD_Y), "kind": "wild", "team": None},
    {"pts": rect(-HX, WILD_Y, HX, HY), "kind": "outskirts", "team": "A"},
    {"pts": rect(-LEDGE_X, BASIN_Y, LEDGE_X, WILD_Y), "kind": "outskirts", "team": "A"},
    {"pts": rect(-1600, 2420, 1600, 3300), "kind": "plaza", "team": "A"},
    {"pts": rect(-1400, 3300, 1400, HY), "kind": "base", "team": "A"},
    {"pts": rect(-LEDGE_X, 1100, -1500, BASIN_Y), "kind": "ruins", "team": "A"},
]

# ==========================================================================
# LEFT WILD (authored whole; rotation makes the right Wild)
#   south third  = THE TANGLE   (overgrown hedge maze, CQC)
#   middle third = THE GLADE    (mid-range meadow, wild bells)
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

# --- The Tangle (y 750..2650) -------------------------------------------
# Hedges are full cover: they block shots, so snipers can't see in.
hedge(-4800, 2280, -4250, 2280)
hedge(-4250, 2280, -4250, 1880)
hedge(-3420, 2700, -3420, 2300)
hedge(-3420, 2300, -3020, 2300)
hedge(-3950, 1900, -3350, 1900)
hedge(-4550, 1480, -3720, 1480)
hedge(-3720, 1480, -3720, 1120)
hedge(-3300, 1560, -3300, 1150)
hedge(-3300, 1150, -2950, 1150)
hedge(-4300, 1080, -4300, 780)
hedge(-3950, 820, -3500, 820)
full(rock(-4520, 1850, 110, 11), "tree")
full(rock(-3020, 1850, 120, 12), "tree")
full(rock(-4050, 2520, 100, 13), "tree")
full(rock(-3000, 2500, 90, 14), "tree")
full(rock(-4050, 1250, 105, 15), "tree")
for (bx, by) in [(-3700, 2150), (-4550, 1250), (-3050, 1350), (-4000, 1700),
                 (-3500, 1050), (-4600, 950), (-3150, 2150)]:
    bush(bx, by, 120)
marker(-3550, 1010, "bell_wild", "A wild bell", "A")

# --- The Glade (y -750..750) --------------------------------------------
full(rock(-4450, 350, 140, 21), "tree")
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
# Sniper nest: a boulder to hide behind while reloading.
full(rock(-3250, -1850, 150, 36, stretch=(1.0, 1.3)), "rock")
# Back path of trees along the outer wall = the flank that counters the nest.
for i, (tx, ty) in enumerate([(-4500, -950), (-4300, -1350), (-4550, -1700),
                              (-4250, -2100), (-4500, -2450)]):
    full(rock(tx, ty, 110, 40 + i), "tree")
for (bx, by) in [(-4100, -1100), (-4000, -1900), (-4150, -2400), (-3700, -1450)]:
    bush(bx, by, 120)
low(rock(-3650, -2250, 110, 47, stretch=(1.6, 0.7)), "lowrock")
marker(-3600, -1250, "bell_wild", "B wild bell", "B")

# Jump pads onto the left Wild (both fire from the A half of the basin).
jump_pad(-2530, 300, -3450, 300, "Glade Spring")         # basin -> glade
jump_pad(-2250, 1750, -3150, 1700, "Ruins Updraft")     # ruins courtyard -> Tangle

# ==========================================================================
# LOWER BASIN (y >= 0): THE CRADLE, the A-side LULLABY RUINS, the DRIFTFIELD
# ==========================================================================
marker(0, 0, "sleepwalker", "Sleepwalker start")
L["markers"].append({"x": 0, "y": 0, "kind": "sleepwalker_circuit",
                     "rx": 1600, "ry": 1300, "width": 600, "label": "", "team": None})

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
lowwall(-1150, 1900, -600, 1990)
lowwall(600, 1990, 1150, 1900)
low(rock(0, 1780, 90, 72, stretch=(1.8, 0.7)), "lowrock")
full(rock(-1300, 1680, 120, 73), "rock")
full(rock(1300, 1950, 130, 74), "rock")
bush(-850, 2150, 100)
bush(850, 2150, 100)

# --- Lullaby Ruins (A): x -2750..-1500, y 1100..2350 ---------------------
# A collapsed chapel. Doors: north (basin), east (Cradle), south (back road),
# west is the Tangle cliff (drop-in only).
RW = "ruin"
wall(-2750, 1100, -2350, 1100, kind=RW)        # north wall, door -2350..-2050
wall(-2050, 1100, -1500, 1100, kind=RW)
wall(-1500, 1100, -1500, 1450, kind=RW)        # east wall, door 1450..1750
wall(-1500, 1750, -1500, 2350, kind=RW)
wall(-2750, 2350, -2250, 2350, kind=RW)        # south wall, door -2250..-1950
wall(-1950, 2350, -1500, 2350, kind=RW)
# Interior: nave (north), side chapel (south-east), open courtyard (south-west)
wall(-2750, 1500, -2450, 1500, kind=RW)
wall(-2150, 1500, -1850, 1500, kind=RW)        # gaps = doorways
wall(-1950, 1850, -1950, 2100, kind=RW)
wall(-1950, 1850, -1700, 1850, kind=RW)
full(rock(-2000, 1300, 70, 80, n=7, jitter=0.1), "pillar")
full(rock(-1750, 1300, 70, 81, n=7, jitter=0.1), "pillar")
low(rock(-2550, 1300, 90, 82, stretch=(1.5, 0.7)), "crate")
low(rock(-2450, 2150, 80, 83), "crate")
low(rect(-1860, 1940, -1760, 2040), "crate")
bush(-2600, 1850, 100)
L["teleporters"].append({"a": (-1680, 2170), "b": (1680, -2170), "two_way": True,
                         "name": "Dream Rift"})

# --- Driftfield (A): open field under the A Ridge, x 1100..2750 ----------
for i, (x, y, r) in enumerate([(1900, 750, 130), (2350, 450, 110), (1900, 1450, 150),
                               (2450, 1800, 120), (1250, 2150, 100)]):
    full(rock(x, y, r, 90 + i, stretch=(1.2, 0.9)), "rock")
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
full(rock(-980, 2290, 640, 100, n=12, jitter=0.12, stretch=(1.0, 0.22)), "cliffrock")
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
marker(-1250, 2620, "bell_gate", "A gate bell", "A")
marker(1250, 2620, "bell_gate", "A gate bell", "A")

# Plaza side walls with gates to the back road at y 2450..2750
wall(-1600, 2750, -1600, 3300, kind="basewall", team="A")
wall(1600, 2750, 1600, 3300, kind="basewall", team="A")

# Lamplight Road speed strips (bidirectional), both sides of the plaza.
L["speed_strips"].append({"x": -2150, "y": 2560, "w": 900, "h": 170, "dir": (1, 0)})
L["speed_strips"].append({"x": 2150, "y": 2600, "w": 900, "h": 170, "dir": (1, 0)})

# --- A base / spawn room: three exits + one-way comeback teleporter -------
wall(-1400, 3300, -300, 3300, kind="basewall", team="A")
wall(300, 3300, 1400, 3300, kind="basewall", team="A")
wall(-1400, 3300, -1400, 3500, kind="basewall", team="A")
wall(-1400, 3800, -1400, HY, kind="basewall", team="A")
wall(1400, 3300, 1400, 3500, kind="basewall", team="A")
wall(1400, 3800, 1400, HY, kind="basewall", team="A")
# Dawn Statue: breaks every straight line between the three spawn doors, so
# no one outside can see through the spawn room.
full(rock(0, 3640, 140, 104, n=12, jitter=0.05), "statue", "A")
for x in (-1080, 1080):
    full(rock(x, 3470, 85, 105 + (x > 0), n=8, jitter=0.08), "statue", "A")
for x in (-950, -700, -450, 450, 700, 950):
    marker(x, 3880, "spawn", "", "A")
L["teleporters"].append({"a": (-1000, 3700), "b": (-4050, 380), "two_way": False,
                         "name": "Dawn Door"})

# --- Cloister (west outskirts): spawn W door -> tight tunnel -> colonnade ---
# East half is a solid-walled tunnel (~320 px clear: pure CQC). West half is
# an open colonnade: pillars you can shoot and slip between.
wall(-1400, 3470, -1950, 3470, kind="cloister", team="A")
wall(-1400, 3830, -3050, 3830, kind="cloister", team="A")
full(rect(-3050, 3870, -1400, HY), "cloister", "A")   # solid fill behind
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
for i, (x, y, r) in enumerate([(2050, 3220, 110), (2450, 3550, 120), (3100, 3050, 130),
                               (3700, 3500, 110), (4350, 3100, 120), (2900, 3850, 100),
                               (4200, 3850, 100)]):
    full(rock(x, y, r, 120 + i), "tree")
for (bx, by) in [(2250, 2950), (3400, 3350), (4000, 3000), (2000, 3700)]:
    bush(bx, by, 110)
low(rock(3450, 2900, 100, 130, stretch=(1.6, 0.6)), "lowrock")

# ==========================================================================
# SIGHT LANES (validated by check.py: must be clear of full cover)
# ==========================================================================
L["lanes"] += [
    {"a": (-1450, 1600), "b": (1450, -1600), "label": "Moon Aisle"},
    {"a": (3150, 2050), "b": (-500, 1250), "label": "Ridge Line (A)"},
    {"a": (3000, 2550), "b": (3000, -800), "label": "Wild Rail (A)"},
]

# Region labels (authored half only; rotated copies get B names below)
label(-3750, 1650, "THE TANGLE", 150)
label(-3750, 0, "THE GLADE", 130)
label(-3750, -1600, "STILT RIDGE", 150)
label(0, 350, "THE CRADLE", 170)
label(-2150, 1400, "LULLABY RUINS", 95)
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
        if m["kind"] in ("sleepwalker", "sleepwalker_circuit"):
            continue
        out["markers"].append({**m, "x": -m["x"], "y": -m["y"], "team": _swap(m["team"]),
                               "label": m["label"].replace("A ", "#").replace("B ", "A ").replace("#", "B ")})
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
