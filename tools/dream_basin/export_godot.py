"""Export the Dream Basin layout to Godot scenes.

    python3 tools/dream_basin/export_godot.py

Writes:
  scenes/maps/dream_basin.tscn     the map (floors, cover, ledges, mobility)
  scenes/dream_basin_world.tscn    playable test scene (map + player + HUD)

The map scene is plain nodes, so it can be edited in the Godot editor. Re-running
this script OVERWRITES it: once you start hand-editing the scene, either keep
making changes here instead, or stop re-exporting.
"""

import math
import os

from check import dist_to_poly
from layout import HX, HY, Y, build

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
MAP_OUT = os.path.join(ROOT, "scenes", "maps", "dream_basin.tscn")
WORLD_OUT = os.path.join(ROOT, "scenes", "dream_basin_world.tscn")

FLOOR = {
    ("basin", "A"): "cbc4e8", ("basin", "B"): "cbc4e8",
    ("wild", None): "d9ecc6",
    ("outskirts", "A"): "cfe6d8", ("outskirts", "B"): "efd8cd",
    ("plaza", "A"): "b8dfca", ("plaza", "B"): "ecc5b5",
    ("base", "A"): "9fd3b9", ("base", "B"): "e3aa95",
    ("ruins", "A"): "cfc5b1", ("ruins", "B"): "cfc5b1",
}
COVER = {
    "tree": "3f6b35", "hedge": "2f5a2a", "rock": "7a736b", "cliffrock": "5c5650",
    "pillar": "8d85a8", "wall": "4b4b4b", "ruin": "7a6a55", "cloister": "6a5a48",
    "boundary": "2b2b30", "lowrock": "b8b2a6", "lowwall": "a39d90", "crate": "c9a66b",
}
TEAM_COVER = {
    "basewall": {"A": "2f8f6a", "B": "c05a3c"},
    "sundial": {"A": "d4ad4f", "B": "8fa3d4"},   # Dawn sun-dial / Dusk moon-dial
    "statue": {"A": "d4ad4f", "B": "8fa3d4"},
}
GROUP = {
    "tree": "Trees", "hedge": "Hedges", "rock": "Rocks", "cliffrock": "Rocks",
    "pillar": "Pillars", "wall": "Walls", "ruin": "Walls", "cloister": "Walls",
    "basewall": "Walls", "sundial": "Landmarks", "statue": "Landmarks",
    "boundary": "Boundary", "lowrock": "LowCover", "lowwall": "LowCover", "crate": "LowCover",
}


def col(hex6, a=1.0):
    r, g, b = (int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"Color({r:.3f}, {g:.3f}, {b:.3f}, {a})"


def v2(p):
    return f"Vector2({p[0]:.0f}, {p[1]:.0f})"


def pva(pts):
    return "PackedVector2Array(" + ", ".join(f"{x:.0f}, {y:.0f}" for x, y in pts) + ")"


class Scene:
    def __init__(self):
        self.ext = []
        self.nodes = []

    def res(self, kind, path):
        rid = f"{len(self.ext) + 1}_{os.path.basename(path).split('.')[0]}"
        self.ext.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
        return f'ExtResource("{rid}")'

    def node(self, name, parent=None, type_=None, instance=None, groups=None, node_paths=None, **props):
        head = f'[node name="{name}"'
        if type_:
            head += f' type="{type_}"'
        if parent is not None:
            head += f' parent="{parent}"'
        if node_paths:
            head += " node_paths=PackedStringArray(" + ", ".join(f'"{n}"' for n in node_paths) + ")"
        if groups:
            head += " groups=[" + ", ".join(f'"{g}"' for g in groups) + "]"
        if instance:
            head += f" instance={instance}"
        lines = [head + "]"] + [f"{k} = {v}" for k, v in props.items()]
        self.nodes.append("\n".join(lines))

    def text(self):
        return "[gd_scene format=3]\n\n" + "\n".join(self.ext) + "\n\n" + "\n\n".join(self.nodes) + "\n"


def centroid(pts):
    return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)


def export_map(m):
    s = Scene()
    game_map = s.res("Script", "res://scripts/map/game_map.gd")
    grid = s.res("Script", "res://scripts/map/floor_grid.gd")
    cover = s.res("Script", "res://scripts/map/cover_body.gd")
    ledge = s.res("PackedScene", "res://scenes/map/ledge.tscn")
    stair = s.res("PackedScene", "res://scenes/map/stairwell.tscn")
    pad = s.res("PackedScene", "res://scenes/map/jump_pad.tscn")
    tele = s.res("PackedScene", "res://scenes/map/teleporter.tscn")
    strip = s.res("PackedScene", "res://scenes/map/speed_strip.tscn")
    bush = s.res("PackedScene", "res://scenes/map/bush.tscn")

    bounds = f"Rect2({-HX}, {-HY}, {2 * HX}, {2 * HY})"
    s.node("DreamBasin", type_="Node2D", script=game_map, bounds=bounds)

    # --- floor --------------------------------------------------------------
    s.node("Floor", ".", "Node2D", z_index=-20)
    s.node("Void", "Floor", "Polygon2D", color=col("1f1f24"),
           polygon=pva([(-HX - 600, -HY - 600), (HX + 600, -HY - 600), (HX + 600, HY + 600), (-HX - 600, HY + 600)]))
    counts = {}
    for r in m["regions"]:
        key = f'{r["kind"].capitalize()}{r["team"] or ""}'
        counts[key] = counts.get(key, 0) + 1
        s.node(f"{key}_{counts[key]}", "Floor", "Polygon2D",
               color=col(FLOOR[(r["kind"], r["team"])]), polygon=pva(r["pts"]))
    s.node("Grid", "Floor", "Node2D", script=grid, bounds=bounds)

    # --- stairwells + ledges -------------------------------------------------
    s.node("Stairwells", ".", "Node2D", z_index=-14)
    for i, st in enumerate(m["stairs"]):
        s.node(f"Stairwell{i + 1}", "Stairwells", instance=stair, position=v2((st["x"], st["y"])),
               rotation=f'{math.atan2(st["up"][1], st["up"][0]):.6f}', width=f'{st["w"]:.0f}',
               depth=f'{st["d"]:.0f}')

    s.node("Ledges", ".", "Node2D", z_index=-12)
    for i, l in enumerate(m["ledges"]):
        dx, dy = l["drop"]
        theta = math.atan2(dx, -dy)            # local +Y = climb direction = -drop
        ax_dir = (-dy, dx)                     # local +X
        a, b = l["a"], l["b"]
        if (b[0] - a[0]) * ax_dir[0] + (b[1] - a[1]) * ax_dir[1] < 0:
            a, b = b, a
        s.node(f"Ledge{i + 1}", "Ledges", instance=ledge, position=v2(a),
               rotation=f"{theta:.6f}", length=f"{math.dist(a, b):.0f}")

    # --- mobility -------------------------------------------------------------
    s.node("Mobility", ".", "Node2D")
    s.node("SpeedStrips", "Mobility", "Node2D")
    for i, sp in enumerate(m["speed_strips"]):
        s.node(f"LamplightRoad{i + 1}", "Mobility/SpeedStrips", instance=strip,
               position=v2((sp["x"], sp["y"])), size=v2((sp["w"], sp["h"])))
    s.node("JumpPads", "Mobility", "Node2D")
    seen = {}
    for j in m["jump_pads"]:
        base = j["name"].replace(" ", "")
        seen[base] = seen.get(base, 0) + 1
        name = base + ("A" if seen[base] == 1 else "B")
        s.node(name, "Mobility/JumpPads", instance=pad, position=v2((j["x"], j["y"])),
               landing_offset=v2((j["tx"] - j["x"], j["ty"] - j["y"])))
    s.node("Teleporters", "Mobility", "Node2D")
    for i, t in enumerate(m["teleporters"]):
        base = t["name"].replace(" ", "")
        if t["two_way"]:
            ends = [(f"{base}_A", t["a"], 0), (f"{base}_B", t["b"], 0)]
            extra = {"channel_time": "0.75", "cooldown": "4.0"}
        else:
            ends = [(f"{base}_Entrance", t["a"], 1), (f"{base}_Exit", t["b"], 2)]
            extra = {"channel_time": "0.35", "cooldown": "0.0"}
        for k, (name, p, mode) in enumerate(ends):
            partner = ends[1 - k][0]
            s.node(name, "Mobility/Teleporters", instance=tele, node_paths=["partner"],
                   position=v2(p), partner=f'NodePath("../{partner}")', mode=str(mode), **extra)

    # --- cover ----------------------------------------------------------------
    s.node("Cover", ".", "Node2D")
    groups_made = set()
    counts = {}
    edge = 400
    boundary = [
        [(-HX - edge, -HY - edge), (HX + edge, -HY - edge), (HX + edge, -HY), (-HX - edge, -HY)],
        [(-HX - edge, HY), (HX + edge, HY), (HX + edge, HY + edge), (-HX - edge, HY + edge)],
        [(-HX - edge, -HY), (-HX, -HY), (-HX, HY), (-HX - edge, HY)],
        [(HX, -HY), (HX + edge, -HY), (HX + edge, HY), (HX, HY)],
    ]
    items = [(o, 0) for o in m["full"]] + [(o, 1) for o in m["low"]] + \
            [({"pts": p, "kind": "boundary", "team": None}, 0) for p in boundary]
    for o, height in items:
        kind = o["kind"]
        group = GROUP[kind]
        if group not in groups_made:
            s.node(group, "Cover", "Node2D")
            groups_made.add(group)
        color = TEAM_COVER[kind][o["team"]] if kind in TEAM_COVER else COVER[kind]
        counts[kind] = counts.get(kind, 0) + 1
        name = f"{kind.capitalize()}{counts[kind]}"
        c = centroid(o["pts"])
        s.node(name, f"Cover/{group}", "StaticBody2D", position=v2(c), script=cover,
               height=str(height), fill_color=col(color))
        s.node("Shape", f"Cover/{group}/{name}", "CollisionPolygon2D",
               polygon=pva([(x - c[0], y - c[1]) for x, y in o["pts"]]))

    s.node("Bushes", ".", "Node2D")
    for i, b in enumerate(m["bushes"]):
        s.node(f"Bush{i + 1}", "Bushes", instance=bush, position=v2((b["x"], b["y"])), radius=f'{b["r"]:.0f}')

    # --- spawns ---------------------------------------------------------------
    s.node("SpawnPoints", ".", "Node2D")
    counts = {}
    for mk in m["markers"]:
        if mk["kind"] != "spawn":
            continue
        team = mk["team"].lower()
        counts[team] = counts.get(team, 0) + 1
        s.node(f"Team{mk['team']}_{counts[team]}", "SpawnPoints", "Marker2D", groups=[f"spawn_{team}"],
               position=v2((mk["x"], mk["y"])))

    # --- overview overlay (shown by MapDebugView) ------------------------------
    s.node("Overview", ".", "Node2D", groups=["map_overview"], visible="false", z_index=100)
    for i, ln in enumerate(m["lanes"]):
        s.node(f"Lane{i + 1}", "Overview", "Line2D", points=pva([ln["a"], ln["b"]]), width="28.0",
               default_color=col("dc2626", 0.7))
    for i, lb in enumerate(m["labels"] + [{"x": 0, "y": -HY - 260, "size": 200,
                                          "text": "OVERVIEW  -  M to return, right-click to move the player"}]):
        size = int(lb["size"] * 1.35)
        w = len(lb["text"]) * size * 0.7
        s.node(f"Label{i + 1}", "Overview", "Label",
               offset_left=f"{lb['x'] - w / 2:.0f}", offset_top=f"{lb['y'] - size:.0f}",
               offset_right=f"{lb['x'] + w / 2:.0f}", offset_bottom=f"{lb['y'] + size:.0f}",
               horizontal_alignment="1", vertical_alignment="1", text=f'"{lb["text"]}"',
               **{"theme_override_colors/font_color": col("ffffff"),
                  "theme_override_colors/font_outline_color": col("111111"),
                  "theme_override_constants/outline_size": str(size // 4),
                  "theme_override_font_sizes/font_size": str(size)})
    return s.text()


def export_world(m):
    spawn = next(mk for mk in m["markers"] if mk["kind"] == "spawn" and mk["team"] == "A")
    # Training dummies: in the Cradle, and one on each Ridge to test long shots.
    dummies = [(0, Y(-300)), (-420, Y(180)), (420, Y(180)), (3600, Y(1900)), (-3600, Y(-1900))]
    solids = [o["pts"] for o in m["full"] + m["low"]]
    for d in dummies:
        assert min(dist_to_poly(d, p) for p in solids) > 90, f"dummy at {d} overlaps cover"

    s = Scene()
    world = s.res("Script", "res://scripts/world.gd")
    game_map = s.res("PackedScene", "res://scenes/maps/dream_basin.tscn")
    player = s.res("PackedScene", "res://scenes/player.tscn")
    over = s.res("PackedScene", "res://scenes/game_over_screen.tscn")
    dummy = s.res("PackedScene", "res://scenes/training_dummy.tscn")
    bar = s.res("PackedScene", "res://scenes/hud/ability_bar.tscn")
    music = s.res("Script", "res://scripts/audio/music_request.gd")
    debug = s.res("Script", "res://scripts/map/map_debug_view.gd")

    s.node("World", type_="Node", script=world)
    s.node("DreamBasin", ".", instance=game_map)
    s.node("Player", ".", instance=player, position=v2((spawn["x"], spawn["y"])))
    for i, d in enumerate(dummies):
        s.node(f"TrainingDummy{i + 1}", ".", instance=dummy, position=v2(d))
    s.node("GameOverScreen", ".", instance=over)
    s.node("AbilityBar", ".", instance=bar, node_paths=["actor"], actor='NodePath("../Player")')
    s.node("LevelMusic", ".", "Node", script=music)
    s.node("MapDebugView", ".", "Node", script=debug)
    return s.text()


if __name__ == "__main__":
    m = build()
    os.makedirs(os.path.dirname(MAP_OUT), exist_ok=True)
    with open(MAP_OUT, "w") as f:
        f.write(export_map(m))
    with open(WORLD_OUT, "w") as f:
        f.write(export_world(m))
    print("wrote", os.path.normpath(MAP_OUT))
    print("wrote", os.path.normpath(WORLD_OUT))
