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
var current_day := -1
var arrived := true
var visits: Dictionary = {}
var texture: Texture2D
var last_place := ""
var speed := 23.0

func _init(data: Dictionary, world: TownWorld) -> void:
	id = data.id
	display_name = data.name
	role = data.role
	bio = data.bio
	color = Color(data.color)
	schedule = data.schedule
	texture = load("res://assets/" + id + ".png")
	position = world.center(TownWorld.PLACES[data.home])

func sync_schedule(minute: float, day: int, world: TownWorld) -> void:
	var active := 0
	for i in schedule.size():
		if minute >= schedule[i].time: active = i
	if active == current_entry and day == current_day: return
	current_entry = active
	current_day = day
	var destination: Vector2i = TownWorld.PLACES[schedule[active].place]
	route = world.path(position, destination)
	# Finish the current grid segment first when the schedule changes mid-walk.
	if route.size() > 1:
		var anchor := route[0]
		if position.distance_to(anchor) < 0.1: route.remove_at(0)
	arrived = false

func tick(delta: float) -> void:
	animation_time += delta
	var remaining := speed * delta
	moving = not route.is_empty()
	while remaining > 0 and not route.is_empty():
		var diff := route[0] - position
		var distance := diff.length()
		if distance > 0.01:
			if abs(diff.x) > abs(diff.y): facing = 2 if diff.x > 0 else 1
			else: facing = 0 if diff.y > 0 else 3
		if distance <= remaining:
			position = route[0]
			route.remove_at(0)
			remaining -= distance
		else:
			position += diff.normalized() * remaining
			remaining = 0
	if route.is_empty() and not arrived and current_entry >= 0:
		arrived = true
		last_place = schedule[current_entry].place
		visits[last_place] = int(visits.get(last_place, 0)) + 1

func activity() -> String:
	if current_entry < 0: return "准备开始新的一天"
	return schedule[current_entry].activity

func destination_name() -> String:
	if current_entry < 0: return "家"
	return TownWorld.PLACE_NAMES[schedule[current_entry].place]
