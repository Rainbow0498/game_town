extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var world := TownWorld.new()
	# Every destination must be reachable from every other destination, with
	# cardinal-only segments and no step into buildings, trees or the lake.
	for from_id in TownWorld.PLACES:
		for to_id in TownWorld.PLACES:
			var route := world.path(world.center(TownWorld.PLACES[from_id]), TownWorld.PLACES[to_id])
			check(not route.is_empty(), "Missing route %s -> %s" % [from_id, to_id])
			for i in route.size():
				check(world.walkable(world.cell(route[i])), "Route crosses obstacle")
				if i > 0:
					var diff := route[i] - route[i - 1]
					check(is_zero_approx(diff.x) or is_zero_approx(diff.y), "Diagonal route")
	check(world.path(world.center(Vector2i(16, 13)), Vector2i(5, 4)).is_empty(), "Building must block clicks")
	check(world.path(world.center(Vector2i(16, 13)), Vector2i(29, 17)).is_empty(), "Lake must block clicks")
	check(world.path(world.center(Vector2i(16, 13)), Vector2i(-1, 0)).is_empty(), "Out-of-map path")
	# Run two complete days, one simulated minute at a time. This exercises real
	# movement between every schedule transition and across midnight.
	var town_script = load("res://scripts/town.gd")
	for data in town_script.DATA:
		var npc := TownResident.new(data, world)
		var expected: Dictionary = {}
		for entry in data.schedule: expected[entry.place] = true
		for absolute_minute in range(2880):
			var minute: int = absolute_minute % 1440
			var day: int = absolute_minute / 1440 + 1
			npc.sync_schedule(minute, day, world)
			var before := npc.position
			npc.tick(0.5)
			check(world.walkable(world.cell(npc.position)), "%s walked into obstacle" % npc.id)
			check(before.distance_to(npc.position) <= npc.speed * 0.5 + 0.01, "NPC teleported")
		for place in expected:
			check(npc.visits.has(place), "%s never reached %s" % [npc.id, place])
			check(int(npc.visits.get(place, 0)) >= 2, "%s failed daily repeat at %s" % [npc.id, place])
		print("SCHEDULE PASS: %s visited %s over two days" % [npc.id, str(npc.visits)])
	# Exercise actual scene state and UI callbacks, including pause and day wrap.
	var scene = load("res://scenes/town.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	check(scene.residents.size() == 3, "Exactly three residents required")
	scene._walk_to(Vector2i(27, 17))
	for i in range(500): scene._update_player(0.1)
	check(scene.player.distance_to(world.center(Vector2i(27, 17))) < 0.1, "Player failed click-to-walk")
	var old_player: Vector2 = scene.player
	scene._walk_to(Vector2i(29, 17))
	check(scene.player_route.is_empty() and scene.player == old_player, "Invalid destination moved player")
	scene._set_speed(12)
	check(scene.speed_factor == 12, "Speed button failed")
	scene._toggle_pause()
	var old_time: float = scene.minute
	var old_npc: Vector2 = scene.residents[0].position
	scene._process(2)
	check(scene.minute == old_time and scene.residents[0].position == old_npc, "Pause did not stop NPC and clock")
	scene._select(2)
	check(scene.name_label.text == "里奥", "NPC information panel failed")
	scene.minute = 1430
	scene._skip_hour()
	check(scene.day == 2 and scene.minute == 50, "Midnight hour skip failed")
	scene._reset()
	check(scene.day == 1 and scene.minute == 470 and scene.speed_factor == 1 and not scene.paused, "Reset failed")
	check(scene.player_route.is_empty(), "Reset must cancel movement")
	# Real key events test all four directions and wall collision.
	for key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		scene.player = world.center(Vector2i(16, 13))
		scene.player_route.clear()
		var down := InputEventKey.new()
		down.keycode = key
		down.physical_keycode = key
		down.pressed = true
		Input.parse_input_event(down)
		Input.flush_buffered_events()
		scene._update_player(0.1)
		var up := InputEventKey.new()
		up.keycode = key
		up.physical_keycode = key
		up.pressed = false
		Input.parse_input_event(up)
		Input.flush_buffered_events()
		for i in range(4): scene._update_player(0.1)
		var expected_direction: Vector2i = {KEY_W:Vector2i.UP, KEY_A:Vector2i.LEFT, KEY_S:Vector2i.DOWN, KEY_D:Vector2i.RIGHT, KEY_UP:Vector2i.UP, KEY_LEFT:Vector2i.LEFT, KEY_DOWN:Vector2i.DOWN, KEY_RIGHT:Vector2i.RIGHT}[key]
		check(world.cell(scene.player) == Vector2i(16, 13) + expected_direction, "Keyboard direction failed: %s" % key)
	scene.player = world.center(Vector2i(7, 7))
	scene.player_route.clear()
	var wall_key := InputEventKey.new()
	wall_key.physical_keycode = KEY_W
	wall_key.keycode = KEY_W
	wall_key.pressed = true
	Input.parse_input_event(wall_key)
	Input.flush_buffered_events()
	scene._update_player(1)
	check(scene.player == world.center(Vector2i(7, 7)), "Keyboard must not walk into library wall")
	var wall_key_up := InputEventKey.new()
	wall_key_up.physical_keycode = KEY_W
	wall_key_up.keycode = KEY_W
	wall_key_up.pressed = false
	Input.parse_input_event(wall_key_up)
	Input.flush_buffered_events()
	print("TEST RESULTS: %d checks, %d failures" % [checks, failures.size()])
	scene.queue_free()
	quit(0 if failures.is_empty() else 1)
