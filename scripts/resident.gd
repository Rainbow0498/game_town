class_name TownResident
extends RefCounted

var id: String
var display_name: String
var role: String
var bio: String
var color: Color
var schedule: Array
var position: Vector2
var route := PackedVector2Array()
var facing := 0
var moving := false
var animation_time := 0.0
var current_entry := -1
var arrived := true
var texture: Texture2D
var current_activity := "等待世界状态"
var destination := ""

func _init(data: Dictionary, world: TownWorld) -> void:
	id = data.id
	display_name = data.name
	role = data.role
	bio = data.bio
	color = Color(data.color)
	schedule = data.schedule
	texture = load("res://assets/" + id + ".png")
	position = world.center(TownWorld.PLACES[data.home])

func apply_state(data: Dictionary) -> void:
	position = Vector2(data.position[0], data.position[1])
	route.clear()
	for point in data.route: route.append(Vector2(point[0], point[1]))
	facing = int(data.facing)
	moving = data.moving
	animation_time = data.animation_time
	current_entry = int(data.current_entry)
	arrived = data.arrived
	current_activity = data.activity
	destination = data.destination_name

func activity() -> String:
	return current_activity

func destination_name() -> String:
	return destination
