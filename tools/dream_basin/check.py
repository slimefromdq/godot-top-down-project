"""Sanity checks for the Dream Basin layout.

    python3 tools/dream_basin/check.py

* Sight lanes must be clear of hard walls and crystal (shots must get
  through), and are reported in screens. Pits, crystal and every other
  obstacle block walking in the flood fills below; grass blocks nothing.
* Every jump-pad launch/landing and teleporter end must be standable.
* Walking: every area is reachable on foot from both spawns and can walk
  back to both, and every jump pad / launch flower is an optional shortcut
  with a walking route both ways (its on-foot distance is reported).
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
* Cradle ring: it has cover on it (the Ruined Arcs), but you can walk all
  the way round (RING_MAX_DETOUR between stops every RING_STEP degrees).
* Base routes: the walk from each Plaza exit (north choke, both side gates)
  to the Sunken Court floor stays within ROUTE_MAX_DETOUR of a straight line.
* Reports (no pass/fail): open space per region, and center-field
  sightlines (average clear shot, long-range exposure: whole field, outside
  the ring, the ring and inside).
"""

import math
from collections import deque

from layout import HX, HY, SCREEN_W, Y, build

BODY = 52      # actor collision circle radius (50) plus a hair
CELL = 25
MOTE_DOOR_CLEARANCE = 1200   # about one screen from any spawn door
DEPOSIT_RADIUS = 300         # MatchRules.deposit_radius
CAMP_CLEARANCE = 160         # a camp's monsters need room to stand and be circled


def walk_blockers(m):
    """Everything a body can't walk through: hard walls, low cover (props),
    pits / water and crystal. Grass blocks nothing."""
    return m["full"] + m["low"] + m.get("pits", []) + m.get("crystals", [])


def shot_blockers(m):
    """Everything a shot can't pass: hard walls and crystal (you see through
    crystal but can't shoot through it; shots fly over pits and low cover)."""
    return m["full"] + m.get("crystals", [])


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
    for o in walk_blockers(m):
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


def flood(m, grid, start, use_pads=True, steps=None):
    """Cells reachable from `start`. Pass a dict as `steps` to also get each
    reached cell's walking distance in grid steps (x CELL = px, 4-connected,
    so a little longer than the real diagonal walk)."""
    blocked, cols, rows = grid
    steps = {} if steps is None else steps
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
    steps[s] = 0
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
            steps[(nr, nc)] = steps[(r, c)] + 1
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
        d = min(dist_to_poly(p, o["pts"]) for o in walk_blockers(m))
        r, c = cell_of(*p)
        if d < CAMP_CLEARANCE:
            print(f"  CAMP TOO CLOSE TO COVER: {cp['name']} at {p} ({d:.0f}px)")
            ok = False
        if not seen[r][c]:
            print(f"  CAMP UNREACHABLE ON FOOT: {cp['name']} at {p}")
            ok = False
    return ok


PIECE_CLEARANCE = 120        # room to walk around a piece and shoot it
STAIR_CLEARANCE = 400        # pads and flowers stay this far from any stairwell


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
    others = [o for o in walk_blockers(m) if o.get("kind") not in ("breakable", "gate")]

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
        elif kind in ("hazard", "travelator", "waterstairs"):
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
    # No pad or flower in a stair mouth: walking up the stairs must never
    # launch you somewhere else.
    pads = [(j["name"], (j["x"], j["y"])) for j in m["jump_pads"]]
    pads += [(pc["name"], (pc["x"], pc["y"])) for pc in pieces if pc["kind"] == "flower"]
    for name, p in pads:
        for st in m["stairs"]:
            d = math.dist(p, (st["x"], st["y"])) - max(st["w"], st["d"]) / 2
            if d < STAIR_CLEARANCE:
                print(f"  PAD IN A STAIR MOUTH: {name} at {p} ({d:.0f}px from the stairs at ({st['x']:.0f}, {st['y']:.0f}))")
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


def check_walking(m, grid, probes):
    """Phase 1 rule: every area is reachable on foot, both ways. No jump pad,
    launch flower or teleporter is ever the only way somewhere: from each
    spawn every probe is reachable without them, and every probe can walk
    back to both spawns. Every pad and flower is an optional shortcut: its
    launch and landing are joined on foot both ways (the walking distance is
    reported next to the flight, to show what the shortcut saves)."""
    print("== Walking (no pads, flowers or teleporters; both ways) ==")
    ok = True
    spawns = {"A spawn": probes["A spawn"], "B spawn": probes["B spawn"]}
    reach_from = {}
    for name, p in spawns.items():
        reach_from[name] = flood(m, grid, p, use_pads=False)
    for name, p in probes.items():
        for sname, (seen, cell_of) in reach_from.items():
            r, c = cell_of(*p)
            if not seen[r][c]:
                print(f"  {sname} CAN'T WALK TO {name}")
                ok = False
        seen, cell_of = flood(m, grid, p, use_pads=False)
        for sname, sp in spawns.items():
            r, c = cell_of(*sp)
            if not seen[r][c]:
                print(f"  {name} CAN'T WALK BACK TO {sname}")
                ok = False
    print(f"  {len(probes)} areas: reachable on foot from both spawns and back" if ok else "")
    shortcuts = [(j["name"], (j["x"], j["y"]), (j["tx"], j["ty"])) for j in m["jump_pads"]]
    shortcuts += [(pc["name"], (pc["x"], pc["y"]), (pc["tx"], pc["ty"]))
                  for pc in m["pieces"] if pc["kind"] == "flower"]
    reported = set()
    for name, a, b in shortcuts:
        for frm, to, way in ((a, b, "there"), (b, a, "back")):
            steps = {}
            _, cell_of = flood(m, grid, frm, use_pads=False, steps=steps)
            walk = steps.get(cell_of(*to))
            if walk is None:
                print(f"  PAD IS NOT OPTIONAL: {name} ({way}) has no walking route")
                ok = False
            elif way == "there" and name not in reported:
                reported.add(name)
                print(f"  {name:<18} flight {math.dist(a, b):5.0f}px, on foot {walk * CELL:5.0f}px")
    return ok


# The Cradle ring has cover on it (the Ruined Arcs) but you can still walk
# all the way round: between points every RING_STEP degrees, the walk stays
# within RING_MAX_DETOUR of the arc between them.
RING_STEP = 30
RING_MAX_DETOUR = 1.6


def check_ring_circuit(m, grid):
    print("== Cradle ring: walkable all the way round ==")
    ring = next(mk for mk in m["markers"] if mk["kind"] == "arena_ring")
    blocked = grid[0]
    ok = True
    stops = []
    for deg in range(0, 360, RING_STEP):
        a = math.radians(deg)
        # The clear spot nearest the centreline across the ring's width.
        for k in (0, -0.15, 0.15, -0.3, 0.3, -0.42, 0.42):
            p = ((ring["rx"] + k * ring["width"]) * math.cos(a), (ring["ry"] + k * ring["width"]) * math.sin(a))
            r, c = int((p[1] + HY) // CELL), int((p[0] + HX) // CELL)
            if not blocked[r][c]:
                stops.append((deg, p))
                break
        else:
            print(f"  BLOCKED all the way across at {deg} degrees")
            ok = False
    worst = 0.0
    for (d0, p), (d1, q) in zip(stops, stops[1:] + stops[:1]):
        walked = walk_distance(m, grid, p, q)
        if walked is None:
            print(f"  NO WALK from {d0} to {d1} degrees")
            ok = False
            continue
        detour = walked / max(math.dist(p, q), 1.0)
        worst = max(worst, detour)
        if detour > RING_MAX_DETOUR:
            print(f"  {d0}->{d1} degrees: x{detour:.2f}  <- TOO FAR ROUND")
            ok = False
    print(f"  {len(stops)} stops every {RING_STEP} degrees; worst detour x{worst:.2f} (max x{RING_MAX_DETOUR})")
    return ok


# Walks from each Plaza's exits to the Sunken Court floor must stay direct:
# the center field gets pockets, not a maze. Detour = walked / straight.
ROUTE_MAX_DETOUR = 1.3


def walk_distance(m, grid, a, b):
    """Shortest walk a -> b (8-connected Dijkstra on the flood grid, one-way
    ledges honoured), in px, or None."""
    import heapq
    blocked, cols, rows = grid

    def cell_of(x, y):
        return int((y + HY) // CELL), int((x + HX) // CELL)

    def centre(r, c):
        return (c * CELL - HX + CELL / 2, r * CELL - HY + CELL / 2)
    s, t = cell_of(*a), cell_of(*b)
    best = {s: 0.0}
    heap = [(0.0, s)]
    while heap:
        d, (r, c) = heapq.heappop(heap)
        if (r, c) == t:
            return d * CELL
        if d > best.get((r, c), 1e18):
            continue
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            nr, nc = r + dr, c + dc
            if not (0 <= nr < rows and 0 <= nc < cols) or blocked[nr][nc]:
                continue
            if dr and dc and (blocked[r][nc] or blocked[nr][c]):
                continue
            if crosses_ledge_upward(m, centre(r, c), centre(nr, nc)):
                continue
            nd = d + (1.4142 if dr and dc else 1.0)
            if nd < best.get((nr, nc), 1e18):
                best[(nr, nc)] = nd
                heapq.heappush(heap, (nd, (nr, nc)))
    return None


def check_base_routes(m, grid):
    print("== Base routes (Plaza exits -> Sunken Court, on foot) ==")
    ok = True
    court = (0, 250)
    for team, sign in (("A", 1), ("B", -1)):
        for name, (x, y) in (("north choke", (0, 2290)), ("west gate", (-1600, 2600)),
                             ("east gate", (1600, 2600))):
            start = (x * sign, Y(y) * sign)
            goal = (court[0] * sign, court[1] * sign)
            walked = walk_distance(m, grid, start, goal)
            straight = math.dist(start, goal)
            if walked is None:
                print(f"  {team} {name}: NO ROUTE")
                ok = False
                continue
            detour = walked / straight
            flag = "" if detour <= ROUTE_MAX_DETOUR else "  <- TOO WINDING"
            print(f"  {team} {name:<12} {walked:5.0f}px walked / {straight:5.0f}px straight = x{detour:.2f}{flag}")
            ok &= detour <= ROUTE_MAX_DETOUR
    return ok


def check_court(m, grid):
    """The Sunken Court: you can walk out of it (by its stairs) from its
    floor, without jump pads, and reach both bases."""
    print("== Sunken Court ==")
    seen, cell_of = flood(m, grid, (0, 250), use_pads=False)
    ok = True
    for name, p in (("A spawn", (-700, Y(3880))), ("B spawn", (700, -Y(3880)))):
        r, c = cell_of(*p)
        if not seen[r][c]:
            print(f"  TRAPPED: the court floor can't reach {name}")
            ok = False
    print(f"  {len(m['stairs'])} stairwells, {len(m['ledges'])} ledges;"
          f" the court floor walks out to both bases" if ok else "")
    return ok


# The biggest clear circle (nothing to hide behind or play around) a region
# may hold before the report calls it out. Report only: it points at where
# the next piece of cover should go, it doesn't fail the check.
OPEN_TARGET = 650


def report_open_space(m):
    print("== Open space (largest clear circle per region; report only) ==")
    structure = [o["pts"] for o in walk_blockers(m)]
    ledge_lines = [(l["a"], l["b"]) for l in m["ledges"]]
    ring = next(mk for mk in m["markers"] if mk["kind"] == "arena_ring")

    def clearance(p):
        d = min(dist_to_poly(p, pts) for pts in structure)
        for a, b in ledge_lines:
            d = min(d, dist_to_poly(p, [a, b]))
        return d

    best = {}
    step = 150
    for y in range(-int(HY) + step, int(HY), step):
        for x in range(-int(HX) + step, int(HX), step):
            p = (x, y)
            if any(point_in_poly(p, pts) for pts in structure):
                continue
            region = None
            for r in m["regions"]:
                if point_in_poly(p, r["pts"]):
                    region = r["kind"]
            if region is None:
                continue
            e = math.hypot(x / ring["rx"], y / ring["ry"])
            on_ring = abs(e - 1) < ring["width"] / 2 / ring["rx"]
            d = clearance(p)
            key = region + (" (ring)" if on_ring else "")
            if d > best.get(key, (0, None))[0]:
                best[key] = (d, p)
    for key in sorted(best):
        d, p = best[key]
        flag = "  <- OPEN" if d > OPEN_TARGET and "(ring)" not in key else ""
        print(f"  {key:<18} {d:5.0f}px at ({p[0]:.0f}, {p[1]:.0f}){flag}")


# Center-field sightlines (report only). The basin between the two Plazas and
# the Wilds' cliffs, minus the Old Colonnades (enclosed side blocks). For
# sample points in the open, how far can a shot travel? Long clear rays are
# what let the longest-range hero win every fight there.
SIGHT_CELL = 25
SIGHT_STEP = 300          # sample spacing
SIGHT_DIRS = 32
SIGHT_CAP = 4000          # px; rays are cut off here
LONG_RANGE = 1500         # px; a pair this far apart is a long-range duel


def shot_raster(m):
    """A SIGHT_CELL grid of cells that stop a shot (hard walls, crystal,
    intact glass) or lie off the map."""
    cols, rows = 2 * HX // SIGHT_CELL, 2 * HY // SIGHT_CELL
    solid = [[False] * cols for _ in range(rows)]
    for o in shot_blockers(m):
        xs = [p[0] for p in o["pts"]]
        ys = [p[1] for p in o["pts"]]
        for r in range(max(0, int((min(ys) + HY) // SIGHT_CELL)), min(rows, int((max(ys) + HY) // SIGHT_CELL) + 1)):
            for c in range(max(0, int((min(xs) + HX) // SIGHT_CELL)), min(cols, int((max(xs) + HX) // SIGHT_CELL) + 1)):
                if not solid[r][c] and point_in_poly((c * SIGHT_CELL - HX + SIGHT_CELL / 2,
                                                      r * SIGHT_CELL - HY + SIGHT_CELL / 2), o["pts"]):
                    solid[r][c] = True
    return solid


def _blocked(solid, x, y):
    r, c = int((y + HY) // SIGHT_CELL), int((x + HX) // SIGHT_CELL)
    return not (0 <= r < len(solid) and 0 <= c < len(solid[0])) or solid[r][c]


def clear_ray(solid, p, a, cap=SIGHT_CAP):
    """How far a shot from p at angle a travels before a blocking cell."""
    dx, dy = math.cos(a), math.sin(a)
    d = 0.0
    while d < cap:
        d += SIGHT_CELL * 0.8
        if _blocked(solid, p[0] + dx * d, p[1] + dy * d):
            return d
    return cap


def clear_shot(solid, p, q):
    n = int(math.dist(p, q) / (SIGHT_CELL * 0.8))
    for i in range(1, n):
        t = i / n
        if _blocked(solid, p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t):
            return False
    return True


def center_field_points(m):
    """Walkable sample points of the center field: the basin between the
    Plazas and the Wilds' cliffs, minus the Old Colonnades (enclosed)."""
    walls = [o["pts"] for o in walk_blockers(m)]
    ruins = [r["pts"] for r in m["regions"] if r["kind"] == "ruins"]
    pts = []
    y_max = Y(2350)
    for y in range(-int(y_max) + SIGHT_STEP // 2, int(y_max), SIGHT_STEP):
        for x in range(-2750 + SIGHT_STEP // 2, 2750, SIGHT_STEP):
            p = (x, y)
            if any(point_in_poly(p, r) for r in ruins) or any(dist_to_poly(p, w) < BODY for w in walls):
                continue
            pts.append(p)
    return pts


def _in_ring(m, p):
    """Inside the Cradle ring's outer edge (the ring band and everything it
    encloses)."""
    ring = next(mk for mk in m["markers"] if mk["kind"] == "arena_ring")
    rx, ry = ring["rx"] + ring["width"] / 2, ring["ry"] + ring["width"] / 2
    return (p[0] / rx) ** 2 + (p[1] / ry) ** 2 <= 1.0


def sightline_stats(m, show_map=False, part=None):
    """(average clear shot px, long-range exposure 0..1, sample count) for
    one part of the center field: None = all of it, "outside" = outside the
    Cradle ring, "ring" = the ring band and everything inside it.
    Average clear shot: how far a shot flies, averaged over the part's
    sample points and every direction. Long-range exposure: for each of the
    part's points, the share of all field points LONG_RANGE or more away
    with a clear shot at it, averaged."""
    solid = shot_raster(m)
    pts = center_field_points(m)
    if part is not None:
        mine = [p for p in pts if _in_ring(m, p) == (part == "ring")]
    else:
        mine = pts
    total = 0.0
    for p in mine:
        total += sum(clear_ray(solid, p, 2 * math.pi * i / SIGHT_DIRS) for i in range(SIGHT_DIRS)) / SIGHT_DIRS
    seen = {p: [0, 0] for p in pts}
    for i, p in enumerate(pts):
        for q in pts[i + 1:]:
            if math.dist(p, q) < LONG_RANGE:
                continue
            clear = clear_shot(solid, p, q)
            for k in (p, q):
                seen[k][0] += clear
                seen[k][1] += 1
    # Each point: the share of far points with a clear shot at it; the
    # exposure is the mean over this part's points.
    shares = [seen[p][0] / seen[p][1] for p in mine if seen[p][1]]
    exposure = sum(shares) / max(len(shares), 1)
    if show_map:
        # Per point: share of far points with a clear shot at it.
        # ' ' none sampled, '.' < 15%, 'o' < 35%, '#' 35%+.
        for y in sorted({p[1] for p in pts}):
            row = ""
            for x in range(-2750 + SIGHT_STEP // 2, 2750, SIGHT_STEP):
                v = seen.get((x, y))
                f = v[0] / v[1] if v and v[1] else None
                row += " " if f is None else ("#" if f >= 0.35 else "o" if f >= 0.15 else ".")
            print(f"  {y:6d} {row}")
    return total / max(len(mine), 1), exposure, len(mine)


def report_sightlines(m):
    print("== Center-field sightlines (report only) ==")
    print(f"  average clear shot = how far a shot flies, over every sample point and direction;")
    print(f"  long-range exposure = for a point, the share of points {LONG_RANGE}px+ away with a clear shot at it")
    for label, part in (("whole field", None), ("outside the ring", "outside"), ("ring + inside", "ring")):
        avg, exposure, n = sightline_stats(m, part=part)
        print(f"  {label:<17} {n:4d} points: average clear shot {avg:5.0f}px, long-range exposure {exposure:.0%}")


def main():
    m = build()
    # Breakable cover counts as intact full cover for every check below, so
    # nothing depends on it being broken.
    m["full"] = m["full"] + [{"pts": piece_rect(pc), "kind": "breakable"}
                             for pc in m["pieces"] if pc["kind"] == "breakable"]
    # Dreamer bodies block walking like low cover.
    m["low"] = m["low"] + [{"pts": _circle(d["x"], d["y"], d["body"]), "kind": "dreamer"} for d in m["dreamers"]]
    ok = True
    solid = [o["pts"] for o in shot_blockers(m)]

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
        d = min(dist_to_poly(p, o["pts"]) for o in walk_blockers(m))
        if d < BODY + 10:
            print(f"  TOO CLOSE: {name} at {p} ({d:.0f}px from cover)")
            ok = False
    print("  checked", len(pts), "points")

    print("== Reachability (100px body, one-way ledges) ==")
    grid = build_grid(m)
    ok &= check_ring_circuit(m, grid)
    probes = {
        "A spawn": (-700, 3880), "B spawn": (700, -3880), "Cradle": (0, 0),
        "A Tangle": (-4000, 2000), "B Tangle": (4000, -2000),
        "Glade L": (-3650, -350), "Glade R": (3650, 350),
        "Ridge L": (-3600, -2000), "Ridge R": (3600, 2000),
        "Ruins A": (-2400, 1700), "Ruins B": (2400, -1700),
        "Cloister A": (-2000, 3650), "Orchard A": (3000, 3400),
        "Driftfield A": (2000, 1200), "Plaza A": (-500, 2600),
        "Hollow A": (-4580, 700), "Hollow B": (4580, -700),
        "Court floor": (0, 208), "Cloister B": (2000, -3650), "Orchard B": (-3000, -3400),
        "Driftfield B": (-2000, -1200), "Plaza B": (500, -2600),
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
    ok &= check_walking(m, grid, probes)
    ok &= check_base_routes(m, grid)
    ok &= check_court(m, grid)
    report_open_space(m)
    report_sightlines(m)

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
