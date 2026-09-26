@tool
extends Resource
class_name MazeLayout

# One airlock maze: the inner walls (room pixels). The outer walls are the
# room's edges.

@export var walls: Array[Rect2] = []
