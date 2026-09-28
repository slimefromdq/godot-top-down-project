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

# The map scene's colours were hand-tuned in the editor after the first export.
# Every exporter colour maps to exactly one tuned colour, so the export swaps
# them in and a re-export reproduces the tuned scene. Entries marked
# "plaza:" are the plaza re-dress (Map Liveliness Plan > Plaza direction).
HAND_TUNED = {
    "Color(0.122, 0.122, 0.141, 1.0)": "Color(0.2, 0.5, 0.72, 1.0)",
    "Color(0.796, 0.769, 0.910, 1.0)": "Color(0.855, 0.835, 0.925, 1.0)",  # plaza: basin: pale paving
    "Color(0.851, 0.925, 0.776, 1.0)": "Color(0.800, 0.918, 0.735, 1.0)",  # plaza: wilds: garden lawns
    "Color(0.812, 0.902, 0.847, 1.0)": "Color(0.809, 0.929, 0.855, 1.0)",
    "Color(0.722, 0.875, 0.792, 1.0)": "Color(0.696, 0.901, 0.790, 1.0)",
    "Color(0.624, 0.827, 0.725, 1.0)": "Color(0.580, 0.852, 0.715, 1.0)",
    "Color(0.812, 0.773, 0.694, 1.0)": "Color(0.898, 0.839, 0.722, 1.0)",  # plaza: ruins floor: sandstone
    "Color(0.937, 0.847, 0.804, 1.0)": "Color(0.965, 0.845, 0.787, 1.0)",
    "Color(0.925, 0.773, 0.710, 1.0)": "Color(0.953, 0.749, 0.665, 1.0)",
    "Color(0.890, 0.667, 0.584, 1.0)": "Color(0.917, 0.618, 0.507, 1.0)",
    "Color(0.639, 0.616, 0.565, 1.0)": "Color(0.570, 0.654, 0.731, 1.0)",
    "Color(0.561, 0.769, 0.839, 1.0)": "Color(0.493, 0.791, 0.891, 1.0)",
    "Color(0.722, 0.698, 0.651, 1.0)": "Color(0.800, 0.800, 0.860, 1.0)",  # plaza: low rocks: low stone
    "Color(0.788, 0.651, 0.420, 1.0)": "Color(0.850, 0.651, 0.314, 1.0)",
    "Color(0.184, 0.353, 0.165, 1.0)": "Color(0.178, 0.502, 0.141, 1.0)",
    "Color(0.847, 0.824, 0.769, 1.0)": "Color(0.700, 0.803, 0.898, 1.0)",
    "Color(0.247, 0.420, 0.208, 1.0)": "Color(0.247, 0.556, 0.177, 1.0)",
    "Color(0.478, 0.451, 0.420, 1.0)": "Color(0.690, 0.675, 0.720, 1.0)",  # plaza: rocks: garden boulders
    "Color(0.612, 0.498, 0.384, 1.0)": "Color(0.930, 0.880, 0.800, 1.0)",  # plaza: buildings: pavilions
    "Color(0.553, 0.522, 0.659, 1.0)": "Color(0.900, 0.890, 0.940, 1.0)",  # plaza: pillars: marble columns
    "Color(0.478, 0.416, 0.333, 1.0)": "Color(0.800, 0.720, 0.580, 1.0)",  # plaza: ruin walls: colonnade sandstone
    "Color(0.361, 0.337, 0.314, 1.0)": "Color(0.700, 0.680, 0.740, 1.0)",  # plaza: cliffrock: stone retaining walls
    "Color(0.831, 0.678, 0.310, 1.0)": "Color(0.885, 0.665, 0.136, 1.0)",
    "Color(0.184, 0.561, 0.416, 1.0)": "Color(0.062, 0.669, 0.435, 1.0)",
    "Color(0.416, 0.353, 0.282, 1.0)": "Color(0.553, 0.440, 0.312, 1.0)",
    "Color(0.561, 0.639, 0.831, 1.0)": "Color(0.497, 0.609, 0.885, 1.0)",
    "Color(0.753, 0.353, 0.235, 1.0)": "Color(0.822, 0.233, 0.059, 1.0)",
    "Color(0.169, 0.169, 0.188, 1.0)": "Color(0.090, 0.310, 0.470, 1.0)",
}


def hand_tune(text):
    for plain, tuned in HAND_TUNED.items():
        text = text.replace("color = " + plain + "\n", "color = " + tuned + "\n")
    return text


HAZARD_COLORS = {"sleep_fog": "Color(0.7, 0.6, 1, 0.32)", "thorn_bed": "Color(0.45, 0.6, 0.25, 0.45)"}


def export_pieces(s, m):
    """Map pieces (Map Liveliness Plan): breakable cover, Mote geysers, toggle
    gates, hazards, travelators and launch flowers."""
    scenes = {"breakable": "res://scenes/map/breakable_cover.tscn",
              "geyser": "res://scenes/map/mote_geyser.tscn",
              "gate": "res://scenes/map/toggle_gate.tscn",
              "hazard": "res://scenes/map/hazard_zone.tscn",
              "travelator": "res://scenes/map/travelator.tscn",
              "flower": "res://scenes/map/jump_pad.tscn",
              "waterstairs": "res://scenes/map/water_stairs.tscn"}
    used = {}
    datas = {}
    s.node("MapPieces", ".", "Node2D")
    for pc in m["pieces"]:
        kind = pc["kind"]
        if kind not in used:
            used[kind] = s.res("PackedScene", scenes[kind])
        side = "A" if pc["y"] > 0 or (pc["y"] == 0 and pc["x"] < 0) else "B"
        name = pc["name"].title().replace(" ", "") + side
        props = {"position": v2((pc["x"], pc["y"]))}
        hw, hh = pc["w"] / 2, pc["h"] / 2
        box = pva([(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)])
        if kind == "gate":
            props["color"] = "Color(0.3, 0.32, 0.38, 1)"    # plaza: iron garden gate
            props["cycle_offset"] = f'{pc["offset"]:.1f}'
            if pc["lx"] or pc["ly"]:
                props["lever_offset"] = v2((pc["lx"], pc["ly"]))
        elif kind == "hazard":
            if pc["data"] not in datas:
                datas[pc["data"]] = s.res("Resource", f'res://resources/map/pieces/{pc["data"]}.tres')
            props["data"] = datas[pc["data"]]
            props["cycle_offset"] = f'{pc["offset"]:.1f}'
            props["color"] = HAZARD_COLORS.get(pc["data"], "Color(1, 0.5, 0.5, 0.3)")
        elif kind == "travelator":
            props["rotation"] = f'{pc["rot"]:.6f}'
            props["size"] = v2((pc["w"], pc["h"]))
            props["cycle_offset"] = f'{pc["offset"]:.1f}'
        elif kind == "waterstairs":
            props["rotation"] = f'{pc["rot"]:.6f}'
            props["size"] = v2((pc["w"], pc["h"]))
        elif kind == "flower":
            props["landing_offset"] = v2((pc["tx"] - pc["x"], pc["ty"] - pc["y"]))
            props["sweep_degrees"] = f'{pc["sweep"]:.1f}'
            props["color"] = "Color(0.95, 0.45, 0.7, 1)"
        s.node(name, "MapPieces", instance=used[kind], **props)
        if kind in ("breakable", "gate", "hazard"):
            s.node("Shape", f"MapPieces/{name}", polygon=box)


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
    ("court", None): "a99fd6",
}
COVER = {
    "tree": "3f6b35", "hedge": "2f5a2a", "rock": "7a736b", "cliffrock": "5c5650",
    "pillar": "8d85a8", "wall": "4b4b4b", "ruin": "7a6a55", "cloister": "6a5a48",
    "boundary": "2b2b30", "lowrock": "b8b2a6", "lowwall": "a39d90", "crate": "c9a66b",
    "balustrade": "dcdfe8", "planter": "8fb07a", "hedgebox": "4f8a3f", "bench": "b08a5e", "lamp": "4a4f63",
    "fountain": "8fc4d6", "building": "9c7f62",
    # The obstacle types (CoverBody PIT / CRYSTAL): deep water blue, a dark
    # violet pit, pale see-through crystal.
    "water": "2c5a7a", "pit": "3a2f52", "crystal": "9fe4ff",
    "arcwall": "9a92b8",
}
GRASS_COLOR = "73a842"
TEAM_COVER = {
    "basewall": {"A": "2f8f6a", "B": "c05a3c"},
    "sundial": {"A": "d4ad4f", "B": "8fa3d4"},   # Dawn sun-dial / Dusk moon-dial
    "statue": {"A": "d4ad4f", "B": "8fa3d4", None: "d8d2c4"},
    "fountain": {"A": "8fc4d6", "B": "8fc4d6", None: "8fc4d6"},
}
GROUP = {
    "tree": "Trees", "hedge": "Hedges", "rock": "Rocks", "cliffrock": "Rocks",
    "pillar": "Pillars", "wall": "Walls", "ruin": "Walls", "cloister": "Walls",
    "basewall": "Walls", "sundial": "Landmarks", "statue": "Landmarks",
    "boundary": "Boundary", "lowrock": "LowCover", "lowwall": "LowCover", "crate": "LowCover",
    "balustrade": "Court", "planter": "Furniture", "hedgebox": "Furniture", "bench": "Furniture", "lamp": "Furniture",
    "fountain": "Landmarks", "building": "Buildings",
    "water": "Pits", "pit": "Pits", "crystal": "Crystal", "arcwall": "Arcs",
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
    # Pits first (they're below the floor), then low cover, crystal and full
    # cover (tallest) on top where they overlap. Heights are CoverBody.Height.
    items = [(o, 2) for o in m.get("pits", [])] + [(o, 1) for o in m["low"]] + \
            [(o, 3) for o in m.get("crystals", [])] + [(o, 0) for o in m["full"]] + \
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
        # Fountains are tagged so MapAmbience can ripple their water.
        s.node(name, f"Cover/{group}", "StaticBody2D", position=v2(c), script=cover,
               groups=["fountains"] if kind == "fountain" else None,
               height=str(height), fill_color=col(color))
        s.node("Shape", f"Cover/{group}/{name}", "CollisionPolygon2D",
               polygon=pva([(x - c[0], y - c[1]) for x, y in o["pts"]]))

    s.node("Bushes", ".", "Node2D")
    for i, b in enumerate(m["bushes"]):
        s.node(f"Bush{i + 1}", "Bushes", instance=bush, position=v2((b["x"], b["y"])), radius=f'{b["r"]:.0f}')
    # Tall-grass patches: Bush with a polygon (hides, blocks nothing).
    if m.get("grass"):
        s.node("Grass", ".", "Node2D")
        for i, g in enumerate(m["grass"]):
            c = centroid(g["pts"])
            s.node(f"Grass{i + 1}", "Grass", instance=bush, position=v2(c), color=col(GRASS_COLOR),
                   polygon=pva([(x - c[0], y - c[1]) for x, y in g["pts"]]))

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

    # --- motes: trickle points, dreaming zones, the Dream Mote spot ------------
    zone_script = s.res("Script", "res://scripts/match/dream_zone.gd")
    s.node("Motes", ".", "Node2D")
    for i, mk in enumerate(m["mote_spawns"]):
        s.node(f"MoteSpawn{i + 1}", "Motes", "Marker2D", groups=["mote_spawn"], position=v2((mk["x"], mk["y"])))
    for d in m["dream_point"]:
        s.node("DreamMoteSpawn", "Motes", "Marker2D", groups=["dream_mote_spawn"], position=v2((d["x"], d["y"])))
    dreamer_scene = s.res("PackedScene", "res://scenes/match/dreamer.tscn")
    s.node("Dreamers", ".", "Node2D")
    for d in m["dreamers"]:
        s.node("Dawn" if d["team"] == "A" else "Dusk", "Dreamers", instance=dreamer_scene,
               position=v2((d["x"], d["y"])), team=f'&"{d["team"].lower()}"')
    # --- items and neutral objectives ---------------------------------------------
    shop_script = s.res("Script", "res://scripts/items/shop.gd")
    s.node("Shops", ".", "Node2D")
    for sh in m["shops"]:
        s.node("DawnShop" if sh["team"] == "A" else "DuskShop", "Shops", "Node2D", script=shop_script,
               position=v2((sh["x"], sh["y"])), team=f'&"{sh["team"].lower()}"')
    camp_script = s.res("Script", "res://scripts/match/neutral_camp.gd")
    s.node("NeutralCamps", ".", "Node2D")
    camp_data = {}
    for cp in m["camps"]:
        if cp["kind"] not in camp_data:
            camp_data[cp["kind"]] = s.res("Resource", f'res://resources/match/neutrals/{cp["kind"]}.tres')
        data = camp_data[cp["kind"]]
        side = "" if cp["x"] == 0 and cp["y"] == 0 else ("A" if cp["y"] > 0 or (cp["y"] == 0 and cp["x"] < 0) else "B")
        name = cp["name"].title().replace(" ", "").replace("The", "") + side
        s.node(name, "NeutralCamps", "Node2D", script=camp_script, position=v2((cp["x"], cp["y"])),
               data=data, display_name=f'"{cp["name"]}"')
    export_pieces(s, m)
    s.node("DreamZones", ".", "Node2D")
    seen_pairs = {}
    for z in m["dream_zones"]:
        seen_pairs[z["pair"]] = seen_pairs.get(z["pair"], 0) + 1
        name = f'{z["pair"].capitalize()}{seen_pairs[z["pair"]]}'
        s.node(name, "DreamZones", "Area2D", script=zone_script, pair_id=f'&"{z["pair"]}"',
               display_name=f'"{z["name"]}"', collision_layer="0", collision_mask="0")
        s.node("Shape", f"DreamZones/{name}", "CollisionPolygon2D", polygon=pva(z["pts"]))
        for i, p in enumerate(z["spawns"]):
            s.node(f"Spawn{i + 1}", f"DreamZones/{name}", "Marker2D", position=v2(p))

    # --- overview overlay (shown by MapDebugView) ------------------------------
    # Map ambience (docs/VISUALS_AND_AUDIO.md > Map ambience).
    s.node("Ambience", ".", "Node2D", script=s.res("Script", "res://scripts/map/map_ambience.gd"),
           ambience=s.res("Resource", "res://resources/map/dream_basin_ambience.tres"))
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
    return hand_tune(s.text())


def export_world(m):
    spawn = next(mk for mk in m["markers"] if mk["kind"] == "spawn" and mk["team"] == "A")
    # Training dummies: in the Cradle, and one on each Ridge to test long shots.
    dummies = [(0, Y(-300)), (-420, Y(180)), (420, Y(180)), (3600, Y(1900)), (-3600, Y(-1900))]
    solids = [o["pts"] for o in m["full"] + m["low"] + m.get("pits", []) + m.get("crystals", [])]
    for d in dummies:
        assert min(dist_to_poly(d, p) for p in solids) > 90, f"dummy at {d} overlaps cover"

    s = Scene()
    world = s.res("Script", "res://scripts/world.gd")
    game_map = s.res("PackedScene", "res://scenes/maps/dream_basin.tscn")
    player = s.res("PackedScene", "res://heroes/avery/avery.tscn")
    over = s.res("PackedScene", "res://scenes/game_over_screen.tscn")
    dummy = s.res("PackedScene", "res://scenes/training_dummy.tscn")
    bar = s.res("PackedScene", "res://scenes/hud/ability_bar.tscn")
    minimap = s.res("PackedScene", "res://scenes/hud/minimap.tscn")
    music = s.res("Script", "res://scripts/audio/music_request.gd")
    debug = s.res("Script", "res://scripts/map/map_debug_view.gd")
    match_manager = s.res("Script", "res://scripts/match/match_manager.gd")
    match_hud = s.res("PackedScene", "res://scenes/hud/match_hud.tscn")

    s.node("World", type_="Node", script=world)
    s.node("DreamBasin", ".", instance=game_map)
    s.node("Player", ".", instance=player, position=v2((spawn["x"], spawn["y"])),
           team='&"a"', player_controlled="true")
    for i, d in enumerate(dummies):
        s.node(f"TrainingDummy{i + 1}", ".", instance=dummy, position=v2(d))
    s.node("GameOverScreen", ".", instance=over)
    s.node("AbilityBar", ".", instance=bar, node_paths=["actor"], actor='NodePath("../Player")')
    s.node("Minimap", ".", instance=minimap)
    s.node("LevelMusic", ".", "Node", script=music)
    s.node("MapDebugView", ".", "Node", script=debug)
    # The match ("Wake the Dreamer"): state, economy, respawns. Dream Basin
    # only; Training Grounds stays a sandbox.
    s.node("MatchManager", ".", "Node", script=match_manager)
    s.node("MatchHud", ".", instance=match_hud)
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
