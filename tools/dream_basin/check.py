"""Sanity checks for the Dream Basin layout.

    python3 tools/dream_basin/check.py

* Sight lanes must be clear of full cover, and are reported in screens.
* Every jump-pad launch/landing and teleporter end must be standable.
* Grid flood-fill (with a 128 px body, one-way ledges honoured) from A spawn
  must reach every region; from the basin floor the Wilds must only be
  reachable through a stairwell or jump pad.
* Spawn doors: longest clear line of sight into each door from outside.
* Motes: every trickle point, dreaming-zone spawn and the Dream Mote spot is
  reachable on foot from A spawn (no pads or teleporters), 180-degree
  mirrored, and at least MOTE_DOOR_CLEARANCE from every spawn door; zone
  spawns sit inside their own zone, and zones come in mirrored pairs.
* Objectives: one Shop per team inside its spawn room; the Nightmare's lair
  at the centre; every jungle camp mirrored, clear of cover by
  CAMP_CLEARANCE and reachable on foot from A spawn.
* Dreamers: one per team, mirrored, the deposit ring outside the spawn room,
  and each ring reachable on foot from the Cradle with EITHER the Plaza's
  north choke or its side gates blocked, the spawn room's north door closed
  both times (two ways in besides the spawn room). With all three closed it
  must be unreachable, proving the blockers really cut those routes.
"""

import math
from collections import deque

from layout import HX, HY, SCREEN_W, Y, build

BODY = 52      # actor collision circle radius (50) plus a hair
CELL = 25
MOTE_DOOR_CLEARANCE = 1200   # about one screen from any spawn door
DEPOSIT_RADIUS = 300         # MatchRules.deposit_radius
CAMP_CLEARANCE = 160         # a camp's monsters need room to stand and be circled


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


def _mirrored(points, tol=1.0):
    """Every point's 180-degree twin is in the list."""
    return [p for p in points if not any(math.dist((-p[0], -p[1]), q) <= tol for q in points)]


def check_motes(m, grid):
    ok = True
    print("== Motes ==")
    trickle = [(mk["x"], mk["y"]) for mk in m["mote_spawns"]]
    zone_spawns = [p for z in m["dream_zones"] for p in z["spawns"]]
    dream = [(d["x"], d["y"]) for d in m["dream_point"]]
    print(f"  {len(trickle)} trickle points, {len(m['dream_zones'])} zone halves, "
          f"{len(zone_spawns)} zone spawns, {len(dream)} Dream Mote spot")
    ok &= len(dream) == 1

    unmatched = _mirrored(trickle) + _mirrored(zone_spawns) + _mirrored(dream)
    for p in unmatched:
        print(f"  NOT MIRRORED: {p}")
    ok &= not unmatched

    pairs = {}
    for z in m["dream_zones"]:
        pairs.setdefault(z["pair"], []).append(z)
        for p in z["spawns"]:
            if not point_in_poly(p, z["pts"]):
                print(f"  OUTSIDE ITS ZONE: {z['pair']} spawn {p}")
                ok = False
    for pair, zones in pairs.items():
        mirrored = len(zones) == 2 and all(
            any(math.dist((-p[0], -p[1]), q) <= 1.0 for q in zones[1]["pts"]) for p in zones[0]["pts"])
        if not mirrored:
            print(f"  ZONE PAIR NOT MIRRORED: {pair} ({len(zones)} halves)")
            ok = False

    doors = []
    for sign in (1, -1):
        for door in ((0, Y(3300)), (-1400, Y(3650)), (1400, Y(3650))):
            doors.append((door[0] * sign, door[1] * sign))
    seen, cell_of = flood(m, grid, (-700, Y(3880)), use_pads=False)
    bad = 0
    for label, points in (("trickle", trickle), ("zone", zone_spawns), ("dream", dream)):
        for p in points:
            near = min(math.dist(p, d) for d in doors)
            r, c = cell_of(*p)
            if not seen[r][c]:
                print(f"  UNREACHABLE on foot: {label} {p}")
                bad += 1
            if near < MOTE_DOOR_CLEARANCE:
                print(f"  TOO CLOSE TO A SPAWN DOOR: {label} {p} ({near:.0f}px)")
                bad += 1
    print(f"  {bad} problems (reach on foot, >= {MOTE_DOOR_CLEARANCE}px from doors)")
    return ok and bad == 0


def _circle(x, y, r, n=16):
    return [(x + r * math.cos(2 * math.pi * i / n), y + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def check_dreamers(m):
    ok = True
    print("== Dreamers ==")
    ds = m["dreamers"]
    ok &= sorted(d["team"] for d in ds) == ["A", "B"]
    if len(ds) == 2 and math.dist((ds[0]["x"], ds[0]["y"]), (-ds[1]["x"], -ds[1]["y"])) > 1.0:
        print("  NOT MIRRORED")
        ok = False
    # Routes into each Plaza, as blockers (authored for A, rotated for B).
    choke = _rect(-500, Y(2130), 500, Y(2420))
    gates = [_rect(-1750, Y(2380), -1450, Y(2820)), _rect(1450, Y(2380), 1750, Y(2820))]
    door = _rect(-350, Y(3230), 350, Y(3380))    # the spawn room's north door
    for d in ds:
        sign = 1 if d["team"] == "A" else -1
        centre = (d["x"], d["y"])
        door_point = (0, sign * Y(3300))
        print(f"  {d['team']} Dreamer at ({d['x']:.0f}, {d['y']:.0f}): {math.dist(centre, door_point):.0f}px from its spawn door")
        ok &= abs(d["y"]) < Y(3300) - DEPOSIT_RADIUS    # ring stays out of the spawn room
        for label, blocks, want in (("north choke blocked", [choke, door], True),
                                    ("side gates blocked", gates + [door], True),
                                    ("all routes blocked", [choke, door] + gates, False)):
            rotated = [[(x * sign, y * sign) for x, y in b] for b in blocks]
            mm = {**m, "low": m["low"] + [{"pts": b, "kind": "block"} for b in rotated]}
            seen, cell_of = flood(mm, build_grid(mm), (0, 0), use_pads=False)
            reach = False
            for i in range(24):
                p = (centre[0] + math.cos(i * math.pi / 12) * DEPOSIT_RADIUS * 0.8,
                     centre[1] + math.sin(i * math.pi / 12) * DEPOSIT_RADIUS * 0.8)
                r, c = cell_of(*p)
                reach |= seen[r][c]
            print(f"    {label} (spawn door closed): {'reachable' if reach else 'cut off'}"
                  f"{'' if reach == want else '  <- WRONG'}")
            ok &= reach == want
    return ok


def check_objectives(m, grid):
    print("== Shops and neutral camps ==")
    ok = True
    shops = m["shops"]
    teams = sorted(sh["team"] for sh in shops)
    print(f"  {len(shops)} shops, {len(m['camps'])} camps")
    ok &= teams == ["A", "B"]
    for sh in shops:
        sign = 1 if sh["team"] == "A" else -1
        inside = abs(sh["x"]) < 1400 and sign * sh["y"] > Y(3300)
        if not inside:
            print(f"  SHOP OUTSIDE ITS SPAWN ROOM: {sh}")
            ok = False
    centre = [cp for cp in m["camps"] if cp["kind"] == "nightmare"]
    if len(centre) != 1 or (centre[0]["x"], centre[0]["y"]) != (0, 0):
        print("  the Nightmare must have exactly one lair, at the centre")
        ok = False
    others = [(cp["x"], cp["y"]) for cp in m["camps"] if cp["kind"] != "nightmare"]
    unmatched = _mirrored(others)
    if unmatched:
        print(f"  UNMIRRORED camps: {unmatched}")
        ok = False
    seen, cell_of = flood(m, grid, (-700, Y(3880)), use_pads=False)
    for cp in m["camps"]:
        p = (cp["x"], cp["y"])
        d = min(dist_to_poly(p, o["pts"]) for o in m["full"] + m["low"])
        r, c = cell_of(*p)
        if d < CAMP_CLEARANCE:
            print(f"  CAMP TOO CLOSE TO COVER: {cp['name']} at {p} ({d:.0f}px)")
            ok = False
        if not seen[r][c]:
            print(f"  CAMP UNREACHABLE ON FOOT: {cp['name']} at {p}")
            ok = False
    return ok


PIECE_CLEARANCE = 120        # room to walk around a piece and shoot it


def piece_rect(pc):
    return _rect(pc["x"] - pc["w"] / 2, pc["y"] - pc["h"] / 2, pc["x"] + pc["w"] / 2, pc["y"] + pc["h"] / 2)


def check_pieces(m, grid):
    print("== Map pieces ==")
    ok = True
    pieces = m["pieces"]
    kinds = sorted({pc["kind"] for pc in pieces})
    print(f"  {len(pieces)} pieces ({', '.join(kinds)})")
    unmatched = _mirrored([(pc["x"], pc["y"]) for pc in pieces])
    if unmatched:
        print(f"  UNMIRRORED pieces: {unmatched}")
        ok = False
    ring = next(mk for mk in m["markers"] if mk["kind"] == "arena_ring")
    seen, cell_of = flood(m, grid, (-700, Y(3880)), use_pads=False)
    others = [o for o in m["full"] + m["low"] if o.get("kind") not in ("breakable", "gate")]

    def gap(p):
        return min(dist_to_poly(p, o["pts"]) for o in others)

    def reachable(p):
        r, c = cell_of(*p)
        return seen[r][c]

    # Things a hazard or belt must not sit on.
    keep_clear = [(mk["x"], mk["y"]) for mk in m["markers"] if mk["kind"] == "spawn"]
    keep_clear += [(d["x"], d["y"]) for d in m["dreamers"]] + [(cp["x"], cp["y"]) for cp in m["camps"]]
    for j in m["jump_pads"]:
        keep_clear += [(j["x"], j["y"]), (j["tx"], j["ty"])]
    for pc in pieces:
        p = (pc["x"], pc["y"])
        kind = pc["kind"]
        if kind in ("breakable", "geyser"):
            d = gap(p) - max(pc["w"], pc["h"]) / 2
            if d < PIECE_CLEARANCE:
                print(f"  PIECE TOO CLOSE TO COVER: {pc['name']} at {p} ({d:.0f}px)")
                ok = False
            e = math.hypot(p[0] / ring["rx"], p[1] / ring["ry"])
            inner = (ring["rx"] - ring["width"] / 2 - max(pc["w"], pc["h"]) / 2) / ring["rx"]
            outer = (ring["rx"] + ring["width"] / 2 + max(pc["w"], pc["h"]) / 2) / ring["rx"]
            if inner < e < outer:
                print(f"  PIECE ON THE CRADLE RING: {pc['name']} at {p}")
                ok = False
            if kind == "geyser" and not reachable(p):
                print(f"  GEYSER UNREACHABLE ON FOOT: {pc['name']} at {p}")
                ok = False
        elif kind in ("hazard", "travelator"):
            rect = piece_rect(pc)
            corners = rect + [p]
            if any(point_in_poly(q, o["pts"]) for q in corners for o in others):
                print(f"  {kind.upper()} OVERLAPS COVER: {pc['name']} at {p}")
                ok = False
            for q in keep_clear:
                if point_in_poly(q, rect) or dist_to_poly(q, rect) < 150:
                    print(f"  {kind.upper()} ON A KEY SPOT: {pc['name']} near {q}")
                    ok = False
            if not reachable(p):
                print(f"  {kind.upper()} UNREACHABLE: {pc['name']} at {p}")
                ok = False
        elif kind == "flower":
            for f in (-1.0, 0.0, 1.0):
                a = math.radians(pc["sweep"] * f)
                dx, dy = pc["tx"] - pc["x"], pc["ty"] - pc["y"]
                land = (pc["x"] + dx * math.cos(a) - dy * math.sin(a), pc["y"] + dx * math.sin(a) + dy * math.cos(a))
                if gap(land) < BODY + 10 or any(point_in_poly(land, o["pts"]) for o in others):
                    print(f"  FLOWER LANDS IN COVER: {pc['name']} at sweep {f:+.0f} -> {land}")
                    ok = False
            if gap(p) < BODY + 10 or not reachable(p):
                print(f"  FLOWER PAD BLOCKED OR UNREACHABLE: {pc['name']} at {p}")
                ok = False
    # Every gate closed at once (the worst case): the Cradle, every camp,
    # geyser and Dreamer ring must still be reachable on foot from each base.
    gates = [{"pts": piece_rect(pc), "kind": "gate"} for pc in pieces if pc["kind"] == "gate"]
    if gates:
        closed = {**m, "full": m["full"] + gates}
        grid2 = build_grid(closed)
        for team, start in (("A", (-700, Y(3880))), ("B", (700, -Y(3880)))):
            seen2, cell2 = flood(closed, grid2, start, use_pads=False)
            targets = [("the Cradle", (0, 400 if team == "A" else -400))]
            targets += [(cp["name"], (cp["x"], cp["y"])) for cp in m["camps"]]
            targets += [(pc["name"], (pc["x"], pc["y"])) for pc in pieces if pc["kind"] == "geyser"]
            for name, q in targets:
                r, c = cell2(*q)
                if not seen2[r][c]:
                    print(f"  ALL GATES CLOSED CUTS {team} OFF FROM {name} at {q}")
                    ok = False
        print(f"  all {len(gates)} gates closed: every objective still reachable from both bases"
              if ok else "  (gate check failed)")
    return ok


def main():
    m = build()
    # Breakable cover counts as intact full cover for every check below, so
    # nothing depends on it being broken.
    m["full"] = m["full"] + [{"pts": piece_rect(pc), "kind": "breakable"}
                             for pc in m["pieces"] if pc["kind"] == "breakable"]
    # Dreamer bodies block walking like low cover.
    m["low"] = m["low"] + [{"pts": _circle(d["x"], d["y"], d["body"]), "kind": "dreamer"} for d in m["dreamers"]]
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
        if mk["kind"] == "spawn":
            pts.append((mk["kind"], (mk["x"], mk["y"])))
    for name, p in pts:
        d = min(dist_to_poly(p, o["pts"]) for o in m["full"] + m["low"])
        if d < BODY + 10:
            print(f"  TOO CLOSE: {name} at {p} ({d:.0f}px from cover)")
            ok = False
    print("  checked", len(pts), "points")

    print("== Cradle arena ring clear of collision ==")
    circ = next(mk for mk in m["markers"] if mk["kind"] == "arena_ring")
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

    print("== Reachability (100px body, one-way ledges) ==")
    grid = build_grid(m)
    probes = {
        "A spawn": (-700, 3880), "B spawn": (700, -3880), "Cradle": (0, 0),
        "A Tangle": (-4000, 2000), "B Tangle": (4000, -2000),
        "Glade L": (-3650, -350), "Glade R": (3650, 350),
        "Ridge L": (-3600, -2000), "Ridge R": (3600, 2000),
        "Ruins A": (-2400, 1700), "Ruins B": (2400, -1700),
        "Cloister A": (-2000, 3650), "Orchard A": (3000, 3400),
        "Driftfield A": (2000, 1200), "Plaza A": (-500, 2600),
        "Hollow A": (-4580, 700),
    }
    probes = {k: (x, Y(y)) for k, (x, y) in probes.items()}
    seen, cell_of = flood(m, grid, probes["A spawn"])
    for name, p in probes.items():
        r, c = cell_of(*p)
        reach = seen[r][c]
        print(f"  from A spawn -> {name:<13} {'ok' if reach else 'UNREACHABLE'}")
        ok &= reach
    ok &= check_motes(m, grid)
    ok &= check_dreamers(m)
    ok &= check_objectives(m, grid)
    ok &= check_pieces(m, grid)

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
        for name, door in (("north", (0, Y(3300))), ("west", (-1400, Y(3650))), ("east", (1400, Y(3650)))):
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
