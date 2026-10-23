extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := TownWorld.new()
	for origin in TownWorld.PLACES:
		for destination in TownWorld.PLACES:
			var path := world.path(world.center(TownWorld.PLACES[origin]), TownWorld.PLACES[destination])
			check(not path.is_empty(), "Unreachable destination")
			for i in path.size():
				check(world.walkable(world.cell(path[i])), "Path crosses solid tile")
				if i > 0:
					var delta := path[i] - path[i-1]
					check(is_zero_approx(delta.x) or is_zero_approx(delta.y), "Diagonal path")
	var scene = load("res://scenes/town.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	check(scene.residents.size() == 3, "Three NPCs required")
	for property in scene.get_property_list():
		check(not str(property.name).begins_with("player"), "Player state must be removed")
	check(not scene.has_method("_update_player"), "Player controls must be removed")
	scene._select(2)
	check(scene.name_label.text == scene.residents[2].display_name, "NPC panel failed")
	scene._show_selected_log()
	check(scene.journal_filter == "leo" and scene.journal_visible, "Selected NPC log failed")
	scene._cycle_log_filter()
	check(scene.journal_filter == "", "All NPC log filter failed")
	scene._toggle_journal()
	check(not scene.journal_panel.visible, "Log toggle failed")
	var previous_minute: float = scene.minute
	scene._skip_hour()
	check(scene.minute == previous_minute, "View must not advance its own clock")
	scene._save()
	check(scene.api_queue[-1].path == "/save", "Save must use shared API")
	scene._restore_latest()
	check(scene.api_queue[-1].path == "/snapshots", "Restore must use shared database")
	print("GODOT VIEW TESTS: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	quit(0 if failures == 0 else 1)
