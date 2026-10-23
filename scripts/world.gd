class_name TownWorld
extends RefCounted

const TILE := 16
const SIZE := Vector2i(34, 23)
const BUILDINGS := [
	{"id": "library", "name": "橡树图书馆", "rect": Rect2i(3, 2, 8, 5), "door": Vector2i(7, 7)},
	{"id": "cafe", "name": "余烬咖啡馆", "rect": Rect2i(14, 2, 7, 5), "door": Vector2i(17, 7)},
	{"id": "school", "name": "青藤学堂", "rect": Rect2i(24, 2, 7, 5), "door": Vector2i(27, 7)},
	{"id": "home_mia", "name": "米娅的小屋", "rect": Rect2i(3, 15, 5, 4), "door": Vector2i(5, 19)},
	{"id": "home_oliver", "name": "奥利弗的小屋", "rect": Rect2i(11, 15, 5, 4), "door": Vector2i(13, 19)},
	{"id": "studio", "name": "林间工作室", "rect": Rect2i(19, 15, 5, 4), "door": Vector2i(21, 19)},
]
const PLACES := {
	"library": Vector2i(7, 7), "cafe": Vector2i(17, 7), "school": Vector2i(27, 7),
	"park": Vector2i(8, 11), "square": Vector2i(17, 12), "lake": Vector2i(27, 17),
	"home_mia": Vector2i(5, 19), "home_oliver": Vector2i(13, 19), "studio": Vector2i(21, 19)
}
const PLACE_NAMES := {
	"library": "橡树图书馆", "cafe": "余烬咖啡馆", "school": "青藤学堂", "park": "橡树公园",
	"square": "中央广场", "lake": "月牙湖畔", "home_mia": "米娅的小屋", "home_oliver": "奥利弗的小屋", "studio": "林间工作室"
}
const TREE_CELLS := [Vector2i(1, 1), Vector2i(12, 2), Vector2i(22, 2), Vector2i(32, 2), Vector2i(1, 5), Vector2i(32, 6), Vector2i(2, 9), Vector2i(11, 9), Vector2i(22, 9), Vector2i(31, 10), Vector2i(3, 12), Vector2i(11, 12), Vector2i(23, 12), Vector2i(1, 16), Vector2i(9, 16), Vector2i(17, 16), Vector2i(25, 20), Vector2i(2, 21), Vector2i(9, 21), Vector2i(17, 21), Vector2i(23, 21), Vector2i(31, 21)]

var grid := AStarGrid2D.new()
var blocked: Dictionary = {}

func _init() -> void:
	grid.region = Rect2i(Vector2i.ZERO, SIZE)
	grid.cell_size = Vector2(TILE, TILE)
	grid.offset = Vector2(TILE / 2.0, TILE / 2.0)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			var solid := x == 0 or y == 0 or x == SIZE.x - 1 or y == SIZE.y - 1
			for b in BUILDINGS:
				if b.rect.has_point(c): solid = true
			if (x >= 28 and x <= 31 and y >= 15 and y <= 19): solid = true
			if c in TREE_CELLS: solid = true
			# Fountain and benches are solid objects too.
			if c in [Vector2i(17, 10), Vector2i(18, 10), Vector2i(17, 11), Vector2i(18, 11), Vector2i(6, 10), Vector2i(7, 10), Vector2i(20, 10), Vector2i(21, 10)]: solid = true
			if solid:
				blocked[c] = true
				grid.set_point_solid(c)

func walkable(c: Vector2i) -> bool:
	return grid.is_in_boundsv(c) and not grid.is_point_solid(c)

func cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))

func center(c: Vector2i) -> Vector2:
	return Vector2(c * TILE) + Vector2(8, 8)

func path(from: Vector2, to: Vector2i) -> PackedVector2Array:
	var start := cell(from)
	if not walkable(start) or not walkable(to): return PackedVector2Array()
	return grid.get_point_path(start, to)
