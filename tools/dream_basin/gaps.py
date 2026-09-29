"""Awkward-gap finder for the Dream Basin layout.

    python3 tools/dream_basin/gaps.py

A gap is awkward when two things that block a body (hard walls, low cover,
pits and water, crystal, the map edge) sit closer than a hero's body is wide
(2 x actor radius, plus a margin) but not touching: it looks like a way
through and the hero gets stuck on it. Every gap must be either shut (the
things touch or overlap) or wide enough to walk through.

`find_gaps(m)` returns [(distance, point, name_a, name_b)]; check.py calls it
and fails while any are left.
"""

import math

ACTOR_RADIUS = 50.0        # scenes/actor.tscn CollisionShape2D
MARGIN = 4.0               # check.py's body is a hair bigger (BODY = 52)
MIN_GAP = 2 * ACTOR_RADIUS + MARGIN
BRIDGE_WIDTH = 50.0        # how thick a wall shutting a gap is
BRIDGE_OVERLAP = 8.0       # how far it reaches into the walls it joins
TOUCH = 1.5                # closer than this = the two are joined


def blockers(m):
    return m["full"] + m["low"] + m.get("pits", []) + m.get("crystals", [])


def _bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _seg_seg(a, b, c, d):
    """(distance, point on ab, point on cd) between two segments."""
    def closest(p, q, r):
        dx, dy = q[0] - p[0], q[1] - p[1]
        l2 = dx * dx + dy * dy
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((r[0] - p[0]) * dx + (r[1] - p[1]) * dy) / l2))
        return (p[0] + t * dx, p[1] + t * dy)
    if _cross(a, b, c, d):
        return 0.0, a, c
    best = (1e18, a, c)
    for p, q, r, is_ab in ((a, b, c, False), (a, b, d, False), (c, d, a, True), (c, d, b, True)):
        cp = closest(p, q, r)
        dist = math.dist(cp, r)
        if dist < best[0]:
            best = (dist, r, cp) if is_ab else (dist, cp, r)
    return best


def _cross(a, b, c, d):
    def cr(o, p, q):
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    return (cr(c, d, a) > 0) != (cr(c, d, b) > 0) and (cr(a, b, c) > 0) != (cr(a, b, d) > 0)


def poly_gap(p, q):
    """Closest approach of two polygons: (distance, point on p, point on q)."""
    best = (1e18, None, None)
    for i in range(len(p)):
        a, b = p[i], p[(i + 1) % len(p)]
        for j in range(len(q)):
            c, d = q[j], q[(j + 1) % len(q)]
            r = _seg_seg(a, b, c, d)
            if r[0] < best[0]:
                best = r
                if r[0] == 0.0:
                    return best
    return best


def _inside(pt, poly):
    x, y = pt
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _covered(pa, pb, shapes, i, j):
    """The slit's middle is already inside another shape (a wall shutting it),
    or one closest point is inside the other shape (they overlap)."""
    mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
    if _inside(pa, shapes[j]["pts"]) or _inside(pb, shapes[i]["pts"]):
        return True
    for k, o in enumerate(shapes):
        if k != i and k != j and _inside(mid, o["pts"]):
            return True
    return False


def _label(o, i):
    return str(o.get("name") or o.get("id") or o.get("kind") or "shape%d" % i)


def find_gaps(m, hx=4800, hy=4860):
    shapes = blockers(m)
    boxes = [_bbox(o["pts"]) for o in shapes]
    found = []
    for i in range(len(shapes)):
        x0, y0, x1, y1 = boxes[i]
        for j in range(i + 1, len(shapes)):
            a0, b0, a1, b1 = boxes[j]
            if a0 > x1 + MIN_GAP or a1 < x0 - MIN_GAP or b0 > y1 + MIN_GAP or b1 < y0 - MIN_GAP:
                continue
            p, q = shapes[i]["pts"], shapes[j]["pts"]
            dist, pa, pb = poly_gap(p, q)
            if dist < TOUCH or dist >= MIN_GAP:
                continue
            if _covered(pa, pb, shapes, i, j):
                continue
            found.append((dist, ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2), _label(shapes[i], i), _label(shapes[j], j)))
    # The map edge is a wall too.
    for i, o in enumerate(shapes):
        x0, y0, x1, y1 = boxes[i]
        for name, dist, at in (("west edge", x0 + hx, (-hx, (y0 + y1) / 2)), ("east edge", hx - x1, (hx, (y0 + y1) / 2)),
                               ("north edge", y0 + hy, ((x0 + x1) / 2, -hy)), ("south edge", hy - y1, ((x0 + x1) / 2, hy))):
            if TOUCH < dist < MIN_GAP:
                found.append((dist, at, name, _label(o, i)))
    found.sort(key=lambda g: g[0])
    return found


def seal(m, hx, hy, extra=()):
    """Shut every awkward gap between two shapes with a short wall of the
    same kind (the layout calls this last, so the exported scene never has a
    slit a hero can't squeeze through). Returns how many were shut."""
    shapes = [("full", o) for o in m["full"]] + [("low", o) for o in m["low"]] \
        + [("pits", o) for o in m.get("pits", [])] + [("crystals", o) for o in m.get("crystals", [])]
    shapes += [("extra", o) for o in extra]    # bodies that aren't walls but still fill space
    boxes = [_bbox(o["pts"]) for _, o in shapes]
    all_shapes = [o for _, o in shapes]
    shut = 0
    for i in range(len(shapes)):
        x0, y0, x1, y1 = boxes[i]
        for j in range(i + 1, len(shapes)):
            a0, b0, a1, b1 = boxes[j]
            if a0 > x1 + MIN_GAP or a1 < x0 - MIN_GAP or b0 > y1 + MIN_GAP or b1 < y0 - MIN_GAP:
                continue
            p, q = shapes[i][1]["pts"], shapes[j][1]["pts"]
            dist, pa, pb = poly_gap(p, q)
            if dist < TOUCH or dist >= MIN_GAP or _covered(pa, pb, all_shapes, i, j):
                continue
            ux, uy = (pb[0] - pa[0]) / dist, (pb[1] - pa[1]) / dist
            a = (pa[0] - ux * BRIDGE_OVERLAP, pa[1] - uy * BRIDGE_OVERLAP)
            b = (pb[0] + ux * BRIDGE_OVERLAP, pb[1] + uy * BRIDGE_OVERLAP)
            nx, ny = -uy * BRIDGE_WIDTH / 2, ux * BRIDGE_WIDTH / 2
            quad = [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]
            # Low cover keeps shots flying over it; otherwise the first shape's kind.
            if shapes[i][0] == "extra" and shapes[j][0] == "extra":
                continue
            key, model = shapes[j] if shapes[j][0] == "low" or shapes[i][0] == "extra" else shapes[i]
            if key == "extra":
                continue
            bridge = {**model, "pts": quad}
            m[key].append(bridge)
            all_shapes.append(bridge)
            shut += 1
    return shut


def main() -> int:
    from layout import HX, HY, build
    gaps = find_gaps(build(), HX, HY)
    print(f"== Awkward gaps (closer than {MIN_GAP:.0f}px but not touching) ==")
    for dist, at, a, b in gaps:
        print(f"  {dist:5.1f}px at ({at[0]:.0f}, {at[1]:.0f}): {a} / {b}")
    print(f"  {len(gaps)} found")
    return 1 if gaps else 0


if __name__ == "__main__":
    raise SystemExit(main())
