class_name TownWorld
extends RefCounted

const TILE := 16
const SIZE := Vector2i(34, 23)
static var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town.json"))
static var BUILDINGS: Array = _buildings()
static var PLACES: Dictionary = _places()
static var PLACE_NAMES: Dictionary = _names()

static func _buildings() -> Array:
	var result: Array = []
	for b in definition.buildings:
		result.append({"id": b.id, "name": b.name, "rect": Rect2i(b.rect[0], b.rect[1], b.rect[2], b.rect[3]), "door": Vector2i(b.door[0], b.door[1])})
	return result

static func _places() -> Dictionary:
	var result: Dictionary = {}
	for key in definition.places:
		var point: Array = definition.places[key].cell
		result[key] = Vector2i(point[0], point[1])
	return result

static func _names() -> Dictionary:
	var result: Dictionary = {}
	for key in definition.places: result[key] = definition.places[key].name
	return result

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
			for r in definition.solid_rects:
				if Rect2i(r[0], r[1], r[2], r[3]).has_point(c): solid = true
			for tree in definition.trees:
				if c == Vector2i(tree[0], tree[1]): solid = true
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
