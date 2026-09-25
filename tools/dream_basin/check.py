"""Sanity checks for the Dream Basin layout.

    python3 tools/dream_basin/check.py

* Sight lanes must be clear of full cover, and are reported in screens.
* Every jump-pad launch/landing and teleporter end must be standable.
* Grid flood-fill (with a 128 px body, one-way ledges honoured) from A spawn
  must reach every region; from the basin floor the Wilds must only be
  reachable through a stairwell or jump pad.
* Spawn doors: longest clear line of sight into each door from outside.
"""

import math
from collections import deque

from layout import HX, HY, LEDGE_X, SCREEN_W, build

BODY = 66      # half-size of the 129x127 actor collision box, plus a hair
CELL = 25


def seg_hits_poly(a, b, pts):
    n = len(pts)
    for i in range(n):
        if _seg_x(a, b, pts[i], pts[(i + 1) % n]):
            return True
    return point_in_poly(a, pts) or point_in_poly(b, pts)


def _seg_x(p1, p2, p3, p4):
    def cr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    d1, d2 = cr(p3, p4, p1), cr(p3, p4, p2)
    d3, d4 = cr(p1, p2, p3), cr(p1, p2, p4)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0)


def point_in_poly(p, pts):
    x, y = p
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def dist_to_poly(p, pts):
    if point_in_poly(p, pts):
        return 0.0
    best = 1e9
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy))
    return best


def build_grid(m):
    cols, rows = 2 * HX // CELL, 2 * HY // CELL
    blocked = [[False] * cols for _ in range(rows)]
    for o in m["full"] + m["low"]:
        xs = [p[0] for p in o["pts"]]
        ys = [p[1] for p in o["pts"]]
        c0 = max(0, int((min(xs) - BODY + HX) // CELL))
        c1 = min(cols - 1, int((max(xs) + BODY + HX) // CELL))
        r0 = max(0, int((min(ys) - BODY + HY) // CELL))
        r1 = min(rows - 1, int((max(ys) + BODY + HY) // CELL))
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                if blocked[r][c]:
                    continue
                p = (c * CELL - HX + CELL / 2, r * CELL - HY + CELL / 2)
                if dist_to_poly(p, o["pts"]) < BODY:
                    blocked[r][c] = True
    for r in range(rows):
        for c in range(cols):
            x, y = c * CELL - HX + CELL / 2, r * CELL - HY + CELL / 2
            if abs(x) > HX - BODY or abs(y) > HY - BODY:
                blocked[r][c] = True
    return blocked, cols, rows


def crosses_ledge_upward(m, p, q):
    """True if moving p->q climbs a ledge (i.e. moves against its drop dir)."""
    for l in m["ledges"]:
        if _seg_x(p, q, l["a"], l["b"]):
            mv = (q[0] - p[0], q[1] - p[1])
            if mv[0] * l["drop"][0] + mv[1] * l["drop"][1] < 0:
                return True
    return False


def flood(m, grid, start, use_pads=True):
    blocked, cols, rows = grid
    # Ledge crossings are only possible between cells straddling a ledge line,
    # so precompute those cells to keep the flood fast.
    def cell_of(x, y):
        return int((y + HY) // CELL), int((x + HX) // CELL)

    def centre(r, c):
        return (c * CELL - HX + CELL / 2, r * CELL - HY + CELL / 2)

    pads = {}
    if use_pads:
        for j in m["jump_pads"]:
            pads.setdefault(cell_of(j["x"], j["y"]), []).append(cell_of(j["tx"], j["ty"]))
        for t in m["teleporters"]:
            pads.setdefault(cell_of(*t["a"]), []).append(cell_of(*t["b"]))
            if t["two_way"]:
                pads.setdefault(cell_of(*t["b"]), []).append(cell_of(*t["a"]))

    seen = [[False] * cols for _ in range(rows)]
    s = cell_of(*start)
    seen[s[0]][s[1]] = True
    dq = deque([s])
    while dq:
        r, c = dq.popleft()
        p = centre(r, c)
        nbrs = [(r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)]
        if (r, c) in pads:
            nbrs += pads[(r, c)]
        for nr, nc in nbrs:
            if not (0 <= nr < rows and 0 <= nc < cols) or seen[nr][nc] or blocked[nr][nc]:
                continue
            q = centre(nr, nc)
            if abs(nr - r) + abs(nc - c) == 1 and crosses_ledge_upward(m, p, q):
                continue
            seen[nr][nc] = True
            dq.append((nr, nc))
    return seen, cell_of


def main():
    m = build()
    ok = True
    solid = [o["pts"] for o in m["full"]]

    print("== Sight lanes ==")
    for ln in m["lanes"]:
        hit = any(seg_hits_poly(ln["a"], ln["b"], pts) for pts in solid)
        L = math.dist(ln["a"], ln["b"])
        print(f"  {ln['label']:<18} {L:6.0f}px = {L / SCREEN_W:.2f} screen-widths  "
              f"{'BLOCKED' if hit else 'clear'}")
        ok &= not hit

    print("== Standable points ==")
    pts = []
    for j in m["jump_pads"]:
        pts += [(j["name"] + " launch", (j["x"], j["y"])), (j["name"] + " land", (j["tx"], j["ty"]))]
    for t in m["teleporters"]:
        pts += [(t["name"] + " a", t["a"]), (t["name"] + " b", t["b"])]
    for mk in m["markers"]:
        if mk["kind"] in ("spawn", "bell_gate", "bell_wild", "sleepwalker"):
            pts.append((mk["kind"], (mk["x"], mk["y"])))
    for name, p in pts:
        d = min(dist_to_poly(p, o["pts"]) for o in m["full"] + m["low"])
        if d < BODY + 10:
            print(f"  TOO CLOSE: {name} at {p} ({d:.0f}px from cover)")
            ok = False
    print("  checked", len(pts), "points")

    print("== Sleepwalker circuit clear of collision ==")
    circ = next(mk for mk in m["markers"] if mk["kind"] == "sleepwalker_circuit")
    bad = 0
    for i in range(180):
        a = 2 * math.pi * i / 180
        for k in (-0.5, 0, 0.5):
            rx, ry = circ["rx"] + k * circ["width"], circ["ry"] + k * circ["width"]
            p = (rx * math.cos(a), ry * math.sin(a))
            if any(point_in_poly(p, o["pts"]) for o in m["full"] + m["low"]):
                bad += 1
    print(f"  {bad} blocked samples")
    ok &= bad == 0

    print("== Reachability (128px body, one-way ledges) ==")
    grid = build_grid(m)
    probes = {
        "A spawn": (-700, 3880), "B spawn": (700, -3880), "Cradle": (0, 0),
        "A Tangle": (-3700, 1700), "B Tangle": (3700, -1700),
        "Glade L": (-3650, -350), "Glade R": (3650, 350),
        "Ridge L": (-3600, -2000), "Ridge R": (3600, 2000),
        "Ruins A": (-2300, 1300), "Ruins B": (2300, -1300),
        "Cloister A": (-2000, 3650), "Orchard A": (3000, 3400),
        "Driftfield A": (2000, 1200), "Plaza A": (-500, 2600),
    }
    seen, cell_of = flood(m, grid, (-700, 3880))
    for name, p in probes.items():
        r, c = cell_of(*p)
        reach = seen[r][c]
        print(f"  from A spawn -> {name:<13} {'ok' if reach else 'UNREACHABLE'}")
        ok &= reach
    # Without pads/teleporters, from the Cradle, the only way up is stairs.
    # Block the stairwells too and the Wilds must become unreachable.
    blocked = grid[0]
    for s in m["stairs"]:
        r, c = cell_of(s["x"], s["y"])
        for dr in range(-12, 13):
            for dc in range(-12, 13):
                if 0 <= r + dr < len(blocked) and 0 <= c + dc < len(blocked[0]):
                    blocked[r + dr][c + dc] = True
    seen2, _ = flood(m, grid, (0, 0), use_pads=False)
    leaks = [n for n in ("Glade L", "Glade R", "Ridge L", "Ridge R", "A Tangle", "B Tangle")
             if seen2[cell_of(*probes[n])[0]][cell_of(*probes[n])[1]]]
    print("  wilds reachable from basin without stairs/pads:", leaks or "none (good)")
    ok &= not leaks

    print("== Spawn door exposure (longest clear ray from a door, outside base) ==")
    for team, sign in (("A", 1), ("B", -1)):
        for name, door in (("north", (0, 3300)), ("west", (-1400, 3650)), ("east", (1400, 3650))):
            d = (door[0] * sign, door[1] * sign)
            best, best_a = 0, 0
            for i in range(144):
                a = 2 * math.pi * i / 144
                far = (d[0] + math.cos(a) * 9000, d[1] + math.sin(a) * 9000)
                lo, hi = 0.0, 1.0
                # binary search the first solid hit along the ray
                for _ in range(14):
                    mid = (lo + hi) / 2
                    q = (d[0] + (far[0] - d[0]) * mid, d[1] + (far[1] - d[1]) * mid)
                    if abs(q[0]) > HX or abs(q[1]) > HY or \
                            any(seg_hits_poly((d[0] + math.cos(a) * 60, d[1] + math.sin(a) * 60), q, pts)
                                for pts in solid):
                        hi = mid
                    else:
                        lo = mid
                if lo * 9000 > best:
                    best, best_a = lo * 9000, math.degrees(a)
            print(f"  {team} {name:<5} door: {best:5.0f}px = {best / SCREEN_W:.2f} screens (at {best_a:.0f} deg)")
    print("\nALL CHECKS PASSED" if ok else "\nSOME CHECKS FAILED")


if __name__ == "__main__":
    main()
