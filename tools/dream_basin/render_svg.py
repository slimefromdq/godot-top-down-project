"""Render the Dream Basin layout to a top-down SVG blockout.

    python3 tools/dream_basin/render_svg.py docs/maps/dream_basin_blockout.svg
"""

import math
import sys

from layout import HX, HY, SCREEN_W, SCREEN_H, build

S = 0.1  # svg units per game pixel
PAD = 40
LEGEND_W = 520

FLOOR = {
    ("basin", "A"): "#e7e3f7", ("basin", "B"): "#e7e3f7",
    ("wild", None): "#cfe3c4",
    ("outskirts", "A"): "#dcefe6", ("outskirts", "B"): "#f5e1da",
    ("plaza", "A"): "#c6e8d8", ("plaza", "B"): "#f2cdbf",
    ("base", "A"): "#a9dcc4", ("base", "B"): "#eab6a3",
    ("ruins", "A"): "#d9d2c4", ("ruins", "B"): "#d9d2c4",
}
TEAM_INK = {"A": "#2f8f6a", "B": "#c05a3c", None: "#555"}


def P(x, y):
    return (x + HX) * S + PAD, (y + HY) * S + PAD


def poly(pts, **attrs):
    d = " ".join(f"{P(*p)[0]:.1f},{P(*p)[1]:.1f}" for p in pts)
    a = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<polygon points="{d}" {a}/>'


def line(a, b, **attrs):
    (x1, y1), (x2, y2) = P(*a), P(*b)
    at = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" {at}/>'


def text(x, y, s, size, **attrs):
    px, py = P(x, y)
    at = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return (f'<text x="{px:.1f}" y="{py:.1f}" font-size="{size * S:.1f}" '
            f'text-anchor="middle" dominant-baseline="middle" {at}>{s}</text>')


def render(m):
    w = MAP_PX_W = 2 * HX * S + 2 * PAD
    h = 2 * HY * S + 2 * PAD
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w + LEGEND_W:.0f} {h:.0f}" '
         f'width="{w + LEGEND_W:.0f}" height="{h:.0f}" font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="100%" height="100%" fill="#fbfaf7"/>',
         '<defs><marker id="arr" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" '
         'markerHeight="5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#d97706"/>'
         '</marker><marker id="arrp" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" '
         'markerHeight="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#7c3aed"/></marker>'
         '<pattern id="stairs" width="6" height="6" patternUnits="userSpaceOnUse">'
         '<rect width="6" height="6" fill="#f4e7c5"/><rect width="6" height="2" fill="#b89b5e"/></pattern>'
         '</defs>']

    # floors
    for r in m["regions"]:
        o.append(poly(r["pts"], fill=FLOOR[(r["kind"], r["team"])]))
    # screen grid
    for i in range(1, 5):
        x = -HX + i * SCREEN_W
        o.append(line((x, -HY), (x, HY), stroke="#000", stroke_opacity="0.08", stroke_dasharray="4 6"))
    y = -HY + SCREEN_H
    while y < HY:
        o.append(line((-HX, y), (HX, y), stroke="#000", stroke_opacity="0.08", stroke_dasharray="4 6"))
        y += SCREEN_H

    # sleepwalker circuit
    for mk in m["markers"]:
        if mk["kind"] == "sleepwalker_circuit":
            cx, cy = P(mk["x"], mk["y"])
            o.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{mk["rx"] * S}" ry="{mk["ry"] * S}" '
                     f'fill="none" stroke="#a79be6" stroke-opacity="0.35" '
                     f'stroke-width="{mk["width"] * S}"/>')
            o.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{mk["rx"] * S}" ry="{mk["ry"] * S}" '
                     f'fill="none" stroke="#7c6fd0" stroke-dasharray="6 5" stroke-width="1.2"/>')

    # speed strips
    for s in m["speed_strips"]:
        x0, y0 = s["x"] - s["w"] / 2, s["y"] - s["h"] / 2
        o.append(poly([(x0, y0), (x0 + s["w"], y0), (x0 + s["w"], y0 + s["h"]), (x0, y0 + s["h"])],
                      fill="#fde68a", stroke="#d97706", stroke_width="1"))
        for k in range(4):
            cx = x0 + s["w"] * (k + 0.5) / 4
            o.append(text(cx, s["y"], "&#x2194;", 140, fill="#b45309"))

    # stairs
    for s in m["stairs"]:
        ux, uy = s["up"]
        if ux == 0:
            pts = [(s["x"] - s["w"] / 2, s["y"] - s["d"] / 2), (s["x"] + s["w"] / 2, s["y"] + s["d"] / 2)]
        else:
            pts = [(s["x"] - s["d"] / 2, s["y"] - s["w"] / 2), (s["x"] + s["d"] / 2, s["y"] + s["w"] / 2)]
        (ax, ay), (bx, by) = pts
        o.append(poly([(ax, ay), (bx, ay), (bx, by), (ax, by)], fill="url(#stairs)",
                      stroke="#8a6d2f", stroke_width="1"))
        o.append(line((s["x"] - ux * s["d"] * 0.35, s["y"] - uy * s["d"] * 0.35),
                      (s["x"] + ux * s["d"] * 0.45, s["y"] + uy * s["d"] * 0.45),
                      stroke="#8a6d2f", stroke_width="2", marker_end="url(#arr)"))

    # bushes (under cover so rocks read on top)
    for b in m["bushes"]:
        cx, cy = P(b["x"], b["y"])
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{b["r"] * S:.1f}" fill="#6fae5a" '
                 f'fill-opacity="0.45" stroke="#4d8a3c" stroke-dasharray="2 2"/>')

    # ledges: thick lip on the high side, chevrons pointing the drop direction
    for l in m["ledges"]:
        (ax, ay), (bx, by) = l["a"], l["b"]
        dx, dy = l["drop"]
        lip = 70
        o.append(poly([(ax, ay), (bx, by), (bx - dx * lip, by - dy * lip), (ax - dx * lip, ay - dy * lip)],
                      fill="#6b7f4a"))
        o.append(line((ax, ay), (bx, by), stroke="#3b4a26", stroke_width="2.2"))
        ln = math.hypot(bx - ax, by - ay)
        n = max(1, int(ln // 450))
        for k in range(n):
            t = (k + 0.5) / n
            cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
            o.append(line((cx - dx * 60, cy - dy * 60), (cx + dx * 110, cy + dy * 110),
                          stroke="#3b4a26", stroke_width="1.3", marker_end="url(#arr)"))

    # cover
    FULLC = {"tree": "#3f6b35", "hedge": "#2f5a2a", "rock": "#6b6560", "cliffrock": "#5c5650",
             "pillar": "#8d85a8", "wall": "#4b4b4b", "ruin": "#7a6a55", "basewall": "#3d3d3d",
             "cloister": "#6a5a48", "sundial": "#b99a4a", "statue": "#b99a4a"}
    for c in m["full"]:
        fill = FULLC.get(c["kind"], "#555")
        if c["kind"] == "basewall":
            fill = TEAM_INK[c["team"]]
        o.append(poly(c["pts"], fill=fill, stroke="#222", stroke_width="0.6"))
    for c in m["low"]:
        o.append(poly(c["pts"], fill="#c9b88f" if c["kind"] == "crate" else "#b8b2a6",
                      stroke="#5a5347", stroke_width="1.2", stroke_dasharray="3 1.5"))

    # sight lanes
    for ln in m["lanes"]:
        o.append(line(ln["a"], ln["b"], stroke="#dc2626", stroke_width="2.2", stroke_opacity="0.75",
                      stroke_dasharray="10 5"))
        mx, my = ln["a"][0] * 0.7 + ln["b"][0] * 0.3, ln["a"][1] * 0.7 + ln["b"][1] * 0.3
        o.append(text(mx, my - 90, ln["label"], 85, fill="#b91c1c", font_style="italic",
                      stroke="#fbfaf7", stroke_width="3", paint_order="stroke"))

    # jump pads
    for j in m["jump_pads"]:
        cx, cy = P(j["x"], j["y"])
        tx, ty = P(j["tx"], j["ty"])
        mx, my = (cx + tx) / 2, (cy + ty) / 2
        nx, ny = -(ty - cy), (tx - cx)
        ln = math.hypot(nx, ny) or 1
        qx, qy = mx + nx / ln * 25, my + ny / ln * 25
        o.append(f'<path d="M{cx:.1f},{cy:.1f} Q{qx:.1f},{qy:.1f} {tx:.1f},{ty:.1f}" fill="none" '
                 f'stroke="#d97706" stroke-width="2" stroke-dasharray="5 3" marker-end="url(#arr)"/>')
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="9" fill="#fbbf24" stroke="#b45309" stroke-width="2"/>')
        o.append(f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="5" fill="none" stroke="#b45309" stroke-width="1.5"/>')

    # teleporters
    for t in m["teleporters"]:
        (ax, ay), (bx, by) = P(*t["a"]), P(*t["b"])
        o.append(f'<line x1="{ax:.1f}" y1="{ay:.1f}" x2="{bx:.1f}" y2="{by:.1f}" stroke="#7c3aed" '
                 f'stroke-opacity="0.35" stroke-width="1.5" stroke-dasharray="2 5" ' +
                 ('' if t["two_way"] else 'marker-end="url(#arrp)"') + '/>')
        for (x, y) in ((ax, ay), (bx, by)):
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="10" fill="#c4b5fd" stroke="#7c3aed" stroke-width="2.5"/>')
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="#7c3aed"/>')

    # markers
    for mk in m["markers"]:
        cx, cy = P(mk["x"], mk["y"])
        if mk["kind"] == "spawn":
            o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="5" fill="{TEAM_INK[mk["team"]]}"/>')
        elif mk["kind"] == "bell_gate":
            o.append(f'<rect x="{cx - 9:.1f}" y="{cy - 9:.1f}" width="18" height="18" rx="3" '
                     f'fill="none" stroke="{TEAM_INK[mk["team"]]}" stroke-width="2" stroke-dasharray="3 2"/>')
        elif mk["kind"] == "bell_wild":
            o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="10" fill="none" '
                     f'stroke="{TEAM_INK[mk["team"]]}" stroke-width="2" stroke-dasharray="3 2"/>')
        elif mk["kind"] == "sleepwalker":
            o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="14" fill="#efe9e0" stroke="#8a7f70" stroke-width="2"/>')

    # labels
    for lb in m["labels"]:
        o.append(text(lb["x"], lb["y"], lb["text"], lb["size"], fill="#1f2937", font_weight="700",
                      fill_opacity="0.72", letter_spacing="1", stroke="#fbfaf7", stroke_width="2.5",
                      paint_order="stroke"))

    # border
    o.append(poly([(-HX, -HY), (HX, -HY), (HX, HY), (-HX, HY)], fill="none", stroke="#222", stroke_width="3"))
    o.append(_legend(MAP_PX_W))
    o.append('</svg>')
    return "\n".join(o)


def _legend(x0):
    x = x0 + 20
    rows = [
        ("rect", "#cfe3c4", "Wilds (high ground)"),
        ("rect", "#e7e3f7", "Central Basin (low ground)"),
        ("rect", "#c6e8d8", "Team A (Dawn) plaza / base"),
        ("rect", "#f2cdbf", "Team B (Dusk) plaza / base"),
        ("rect", "#d9d2c4", "Lullaby Ruins floor"),
        ("ledge", "", "One-way ledge (drop toward arrow)"),
        ("stairs", "", "Stairwell (climb in arrow direction)"),
        ("rect", "#5c5650", "Full cover: blocks move + shots"),
        ("dash", "#b8b2a6", "Low cover: blocks move, not shots"),
        ("bush", "", "Bush: hides you, blocks nothing"),
        ("pad", "", "Jump pad (arc to landing ring)"),
        ("tp", "", "Teleporter (arrow = one-way)"),
        ("strip", "", "Speed strip (both directions)"),
        ("lane", "", "Long sight lane"),
        ("ring", "", "Sleepwalker circuit (kept clear)"),
        ("bellg", "", "Gate bell site (reserved)"),
        ("bellw", "", "Wild bell site (reserved)"),
    ]
    o = [f'<text x="{x}" y="70" font-size="30" font-weight="700" fill="#111">DREAM BASIN</text>',
         f'<text x="{x}" y="100" font-size="15" fill="#555">5 x 7.5 screens (9600 x 8100 px)</text>',
         f'<text x="{x}" y="120" font-size="15" fill="#555">1 grid cell = 1 screen (1920 x 1080)</text>',
         f'<text x="{x}" y="140" font-size="15" fill="#555">180-degree rotational symmetry</text>']
    y = 180
    for kind, col, lab in rows:
        cy = y
        if kind == "rect":
            o.append(f'<rect x="{x}" y="{cy - 10}" width="30" height="20" fill="{col}" stroke="#888"/>')
        elif kind == "dash":
            o.append(f'<rect x="{x}" y="{cy - 10}" width="30" height="20" fill="{col}" stroke="#5a5347" stroke-dasharray="3 1.5"/>')
        elif kind == "ledge":
            o.append(f'<rect x="{x}" y="{cy - 10}" width="30" height="8" fill="#6b7f4a"/>'
                     f'<line x1="{x}" y1="{cy - 2}" x2="{x + 30}" y2="{cy - 2}" stroke="#3b4a26" stroke-width="2"/>'
                     f'<line x1="{x + 15}" y1="{cy - 6}" x2="{x + 15}" y2="{cy + 10}" stroke="#3b4a26" marker-end="url(#arr)"/>')
        elif kind == "stairs":
            o.append(f'<rect x="{x}" y="{cy - 10}" width="30" height="20" fill="url(#stairs)" stroke="#8a6d2f"/>')
        elif kind == "bush":
            o.append(f'<circle cx="{x + 15}" cy="{cy}" r="10" fill="#6fae5a" fill-opacity="0.45" stroke="#4d8a3c" stroke-dasharray="2 2"/>')
        elif kind == "pad":
            o.append(f'<circle cx="{x + 15}" cy="{cy}" r="9" fill="#fbbf24" stroke="#b45309" stroke-width="2"/>')
        elif kind == "tp":
            o.append(f'<circle cx="{x + 15}" cy="{cy}" r="10" fill="#c4b5fd" stroke="#7c3aed" stroke-width="2.5"/>')
        elif kind == "strip":
            o.append(f'<rect x="{x}" y="{cy - 8}" width="30" height="16" fill="#fde68a" stroke="#d97706"/>')
        elif kind == "lane":
            o.append(f'<line x1="{x}" y1="{cy}" x2="{x + 30}" y2="{cy}" stroke="#dc2626" stroke-width="2.2" stroke-dasharray="6 3"/>')
        elif kind == "ring":
            o.append(f'<rect x="{x}" y="{cy - 8}" width="30" height="16" fill="#a79be6" fill-opacity="0.35" stroke="#7c6fd0" stroke-dasharray="4 3"/>')
        elif kind == "bellg":
            o.append(f'<rect x="{x + 6}" y="{cy - 9}" width="18" height="18" rx="3" fill="none" stroke="#2f8f6a" stroke-width="2" stroke-dasharray="3 2"/>')
        elif kind == "bellw":
            o.append(f'<circle cx="{x + 15}" cy="{cy}" r="10" fill="none" stroke="#2f8f6a" stroke-width="2" stroke-dasharray="3 2"/>')
        o.append(f'<text x="{x + 42}" y="{cy + 5}" font-size="16" fill="#222">{lab}</text>')
        y += 34
    return "\n".join(o)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "dream_basin_blockout.svg"
    with open(out, "w") as f:
        f.write(render(build()))
    print("wrote", out)
