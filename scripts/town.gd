extends Node2D

const ORIGIN := Vector2(24, 118)
const MAP_SCALE := 2.0
const INK := Color("e6e4d4")
const MUTED := Color("93a69a")
const GOLD := Color("dbbd83")
var DATA: Array = TownWorld.definition.residents

var world := TownWorld.new()
var residents: Array[TownResident] = []
var town_texture: Texture2D = preload("res://assets/town.png")
var font: SystemFont
var serif: SystemFont
var minute := 470.0
var day := 1
var speed_factor := 1.0
var paused := false
var show_routes := true
var selected := 0
var elapsed := 0.0
var feedback := "观察居民的日常，按 J 查看全部角色日志。"
var feedback_timer := 6.0
var clock_label: Label
var period_label: Label
var day_label: Label
var status_label: Label
var name_label: Label
var role_label: Label
var bio_label: Label
var activity_label: Label
var location_label: Label
var schedule_labels: Array[Label] = []
var schedule_times: Array[Label] = []
var resident_buttons: Array[Button] = []
var pause_button: Button
var speed_buttons: Array[Button] = []
var route_button: Button
var portrait: TextureRect
var follow_button: Button
var ui_timer := 0.0
var toast: Panel
var toast_label: Label
var help_dialog: AcceptDialog
var request: HTTPRequest
var api_queue: Array[Dictionary] = []
var active_request: Dictionary = {}
var api_busy := false
var connected := false
var poll_timer := 0.0
var backend_pid := -1
var auto_start_attempted := false
var journal_label: Label
var journal_panel: Panel
var journal_visible := true
var journal_filter := ""
var latest_snapshot := 0
var world_revision := 0
var world_period := "清晨"
var journal_filter_button: Button
const API := "http://127.0.0.1:8765"

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "serif"])
	for data in DATA: residents.append(TownResident.new(data, world))
	_build_ui()
	request = HTTPRequest.new()
	request.timeout = 3.0
	add_child(request)
	request.request_completed.connect(_on_response)
	_enqueue("/world")
	_update_ui()
	if "--smoke-test" in OS.get_cmdline_user_args(): _run_smoke_test.call_deferred()

func _panel(parent: Node, box: Rect2, color: Color, border: Color = Color("3a4d41"), radius: int = 10) -> Panel:
	var panel := Panel.new()
	panel.position = box.position
	panel.size = box.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Node, text: String, pos: Vector2, size_px: int = 16, color: Color = INK, width: float = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0: label.custom_minimum_size.x = width
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, box: Rect2, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = box.position
	b.size = box.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", GOLD)
	for type in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("344b3d") if type in ["hover", "pressed"] else Color("263a30")
		style.border_color = Color("bba679") if type == "focus" else Color("4a5c49")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		b.add_theme_stylebox_override(type, style)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	_panel(root, Rect2(0, 0, 1440, 98), Color("192b24"), Color("354639"), 0)
	_panel(root, Rect2(24, 22, 48, 48), Color("344c39"), Color("6a7b52"), 8)
	_label(root, "♧", Vector2(34, 22), 34, GOLD)
	var title := _label(root, "Oak & Ember", Vector2(88, 12), 32, Color("eadcc1"))
	title.add_theme_font_override("font", serif)
	_label(root, "橡 树 镇   /   A LITTLE LIFE, WELL LIVED", Vector2(90, 55), 12, MUTED)
	_panel(root, Rect2(399, 27, 154, 35), Color("293c30"), Color("4b6045"), 18)
	_label(root, "●  居民观察 · 校园小镇", Vector2(413, 35), 12, Color("bac998"))
	_label(root, "晴  /  22°C", Vector2(602, 24), 20, GOLD)
	_label(root, "微风经过橡树的午后", Vector2(603, 55), 12, MUTED)
	day_label = _label(root, "春 01 日 · 星期一", Vector2(832, 27), 15, INK)
	period_label = _label(root, "清晨 · 小镇正在醒来", Vector2(832, 53), 12, MUTED)
	clock_label = _label(root, "07:50", Vector2(1024, 22), 35, GOLD)
	_label(root, "TOWN TIME", Vector2(1032, 64), 9, MUTED)
	_button(root, "?  操作说明", Rect2(1283, 30, 133, 36), _show_help)
	_panel(root, Rect2(20, 114, 1096, 744), Color("00000000"), Color("899771"), 4)
	# Map labels occupy their own topmost layer, without intercepting clicks.
	for b in TownWorld.BUILDINGS:
		var p: Vector2 = ORIGIN + Vector2(b.rect.position * 16) * MAP_SCALE
		var w: float = b.rect.size.x * 32.0
		var tag := _panel(root, Rect2(p.x + w / 2 - 53, p.y - 22, 106, 25), Color("f0dfb7"), Color("ad956e"), 3)
		var l := _label(tag, b.name, Vector2(0, 2), 12, Color("514d3b"), 106)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var park_tag := _label(root, "O A K   G R O V E", ORIGIN + Vector2(66, 189) * 2, 10, Color("435b3c"))
	park_tag.modulate.a = 0.85
	_label(root, "月 牙 湖", ORIGIN + Vector2(466, 320) * 2, 12, Color("405e50"))
	_panel(root, Rect2(42, 136, 164, 31), Color("263b30d9"), Color("657b52"), 5)
	_label(root, "●  OAK & EMBER / 镇区", Vector2(53, 144), 10, Color("dedec0"))
	_panel(root, Rect2(42, 803, 225, 32), Color("263b30e8"), Color("647653"), 5)
	_label(root, "●  观察模式 · 3 位居民 · 9 处地点", Vector2(55, 811), 11, Color("e2dabe"))
	toast = _panel(root, Rect2(291, 795, 801, 41), Color("263b30eb"), Color("647653"), 5)
	toast_label = _label(toast, "", Vector2(13, 4), 12, Color("e2dabe"))
	toast_label.size = Vector2(775, 33)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panel(root, Rect2(1136, 118, 280, 736), Color("1d3027"))
	_label(root, "T O W N S F O L K", Vector2(1156, 137), 11, GOLD)
	_label(root, "遇见你的邻居", Vector2(1156, 158), 22, INK)
	_label(root, "每个人，都有自己的小小日常。", Vector2(1156, 194), 12, MUTED)
	for i in residents.size():
		var npc := residents[i]
		var b := _button(root, npc.display_name, Rect2(1156 + i * 84, 226, 76, 36), _select.bind(i))
		resident_buttons.append(b)
	_panel(root, Rect2(1156, 280, 58, 68), Color("435341"), Color("64734f"), 6)
	portrait = TextureRect.new()
	portrait.position = Vector2(1161, 280)
	portrait.size = Vector2(48, 66)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(portrait)
	name_label = _label(root, "米娅", Vector2(1228, 280), 22)
	role_label = _label(root, "图书管理员", Vector2(1228, 316), 12, MUTED)
	bio_label = _label(root, "", Vector2(1156, 362), 12, MUTED)
	_panel(root, Rect2(1156, 413, 240, 71), Color("2a4032"), Color("4b5e42"), 6)
	activity_label = _label(root, "", Vector2(1170, 423), 15, GOLD)
	location_label = _label(root, "", Vector2(1170, 453), 11, MUTED)
	_label(root, "今 日 日 程", Vector2(1156, 505), 12, INK)
	_label(root, "固定日程 / 每日循环", Vector2(1287, 507), 10, MUTED)
	for i in range(7):
		var yy := 537 + i * 30
		schedule_times.append(_label(root, "", Vector2(1157, yy), 12, MUTED))
		schedule_labels.append(_label(root, "", Vector2(1220, yy), 12, MUTED))
	follow_button = _button(root, "查看米娅的日常  →", Rect2(1156, 775, 240, 34), _show_selected_log)
	_label(root, "点击居民查看信息 · Tab 切换观察对象", Vector2(1156, 823), 10, MUTED)
	journal_panel = _panel(root, Rect2(42, 585, 640, 202), Color("1d3027f5"), Color("6a7954"), 8)
	journal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(journal_panel, "小 镇 日 志", Vector2(16, 11), 15, GOLD)
	journal_filter_button = _button(journal_panel, "全部居民", Rect2(434, 9, 93, 27), _cycle_log_filter)
	_button(journal_panel, "收起", Rect2(537, 9, 85, 27), _toggle_journal)
	journal_label = _label(journal_panel, "正在连接小镇世界……", Vector2(16, 48), 12, INK)
	journal_label.size = Vector2(608, 145)
	journal_label.clip_text = true
	_label(root, "点击居民 / Tab 观察", Vector2(25, 873), 12, GOLD)
	_button(root, "日志 J", Rect2(196, 865, 77, 28), _toggle_journal)
	_button(root, "保存", Rect2(281, 865, 64, 28), _save)
	_button(root, "恢复", Rect2(353, 865, 64, 28), _restore_latest)
	status_label = _label(root, "", Vector2(436, 873), 11, MUTED)
	pause_button = _button(root, "Ⅱ", Rect2(954, 865, 38, 28), _toggle_pause)
	for i in range(3):
		var value: float = [1.0, 4.0, 12.0][i]
		speed_buttons.append(_button(root, "%d×" % value, Rect2(1000 + i * 48, 865, 42, 28), _set_speed.bind(value)))
	_button(root, "+1h", Rect2(1146, 865, 55, 28), _skip_hour)
	route_button = _button(root, "路线 · 开", Rect2(1210, 865, 91, 28), _toggle_routes)
	_button(root, "新世界", Rect2(1310, 865, 106, 28), _reset)

func _process(delta: float) -> void:
	elapsed += delta
	feedback_timer = maxf(0, feedback_timer - delta)
	poll_timer += delta
	if poll_timer >= 0.25 and not api_busy and api_queue.is_empty():
		poll_timer = 0
		_enqueue("/world")
	if not api_busy and not api_queue.is_empty(): _send_next()
	ui_timer += delta
	if ui_timer >= 0.12:
		ui_timer = 0
		_update_ui()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := (get_global_mouse_position() - ORIGIN) / MAP_SCALE
		for i in residents.size():
			if local.distance_to(residents[i].position - Vector2(0, 7)) < 13:
				_select(i)
				return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: _toggle_pause()
			KEY_TAB: _select((selected + 1) % residents.size())
			KEY_R: _toggle_routes()
			KEY_J: _toggle_journal()

func _select(index: int) -> void:
	selected = index
	_update_ui()

func _toggle_pause() -> void:
	_enqueue("/clock", {"paused": not paused}, true)

func _set_speed(value: float) -> void:
	_enqueue("/clock", {"speed": int(value)}, true)

func _skip_hour() -> void:
	_enqueue("/advance", {"minutes": 60}, true)

func _toggle_routes() -> void:
	show_routes = not show_routes
	_update_ui()

func _reset() -> void:
	_enqueue("/reset", {"start_minute": 470}, true)

func _save() -> void:
	_enqueue("/save", {"name": "第%d天 %s 手动存档" % [day, _time(minute)]}, true)

func _restore_latest() -> void:
	_enqueue("/snapshots")

func _toggle_journal() -> void:
	journal_visible = not journal_visible
	journal_panel.visible = journal_visible

func _show_selected_log() -> void:
	journal_filter = residents[selected].id
	journal_visible = true
	journal_panel.visible = true
	_fetch_events()

func _cycle_log_filter() -> void:
	var ids: Array = ["", "mia", "oliver", "leo"]
	journal_filter = ids[(ids.find(journal_filter) + 1) % ids.size()]
	_fetch_events()

func _fetch_events() -> void:
	_enqueue("/events?latest=true&limit=6" + ("&npc=" + journal_filter if journal_filter != "" else ""))

func _enqueue(path: String, body: Dictionary = {}, post: bool = false) -> void:
	api_queue.append({"path": path, "body": body, "post": post})

func _send_next() -> void:
	active_request = api_queue.pop_front()
	api_busy = true
	var method := HTTPClient.METHOD_POST if active_request.post else HTTPClient.METHOD_GET
	var error := request.request(API + active_request.path, PackedStringArray(["Content-Type: application/json"]), method, JSON.stringify(active_request.body) if active_request.post else "")
	if error != OK:
		api_busy = false
		connected = false

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	api_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		connected = false
		if not auto_start_attempted:
			auto_start_attempted = true
			var python := OS.get_environment("TOWN_PYTHON")
			if python.is_empty(): python = "D:/Anaconda3/python.exe" if FileAccess.file_exists("D:/Anaconda3/python.exe") else "python"
			var args := PackedStringArray([ProjectSettings.globalize_path("res://backend/server.py")])
			if not OS.get_environment("TOWN_DB_PATH").is_empty(): args.append_array(PackedStringArray(["--db", OS.get_environment("TOWN_DB_PATH")]))
			backend_pid = OS.create_process(python, args, false)
		_notify("正在启动本地世界服务，现有存档会自动载入。")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if code != 200:
		_notify("操作失败：" + str(data.get("error", code)) if data is Dictionary else "世界服务返回错误")
		return
	if not connected: _notify("世界已连接，居民日常会自动记录；按 J 查看日志。")
	connected = true
	if active_request.path == "/snapshots":
		if data.is_empty(): _notify("还没有存档，请先保存。")
		else: _enqueue("/restore", {"snapshot_id": int(data[0].id)}, true)
		return
	if str(active_request.path).begins_with("/events"):
		_display_events(data.events)
		return
	if data.has("snapshot_id"):
		latest_snapshot = int(data.snapshot_id)
		_notify("存档 #%d 已保存到本地数据库。" % latest_snapshot)
		data = data.state
	if data.has("npcs"):
		minute = float(data.minute)
		day = int(data.day)
		paused = data.paused
		speed_factor = float(data.speed)
		world_revision = int(data.revision)
		world_period = data.period
		for i in residents.size(): residents[i].apply_state(data.npcs[i])
		if journal_filter == "": _display_events(data.recent_events)
		elif api_queue.is_empty(): _fetch_events()
	if active_request.path == "/restore": _notify("已恢复存档：时间、位置、路线、日程和日志已同步。")
	_update_ui()

func _display_events(events: Array) -> void:
	var lines := PackedStringArray()
	for event in events:
		lines.append("第%d天  %s   %s" % [int(event.day), _time(float(event.minute)), event.message])
	journal_label.text = "\n".join(lines) if not lines.is_empty() else "该角色暂无日志。"
	journal_filter_button.text = "全部居民" if journal_filter == "" else str(DATA[["mia", "oliver", "leo"].find(journal_filter)].name)

func _exit_tree() -> void:
	if backend_pid > 0: OS.kill(backend_pid)

func _show_help() -> void:
	if not is_instance_valid(help_dialog):
		help_dialog = AcceptDialog.new()
		help_dialog.title = "欢迎来到橡树镇 · 操作说明"
		help_dialog.dialog_text = "小镇现在只有 NPC，你以观察者身份查看他们的生活。\n\n点击居民 / Tab    查看或切换居民信息\nJ    显示 / 隐藏日常日志，支持按角色筛选\n空格    暂停 / 继续统一游戏时间\n1× / 4× / 12×    调整模拟速度\n+1h    完整模拟一小时，不跳过任何活动\nR    显示 / 隐藏居民路线\n\n保存    将完整世界状态与事件记录写入 SQLite\n恢复    载入最新手动存档，并从保存的路线继续行走\n\n窗口与无界面模式共用本地世界服务。\n若无法连接，请先运行 backend/server.py。"
		help_dialog.add_theme_font_override("font", font)
		help_dialog.add_theme_font_size_override("font_size", 16)
		help_dialog.ok_button_text = "开始观察"
		add_child(help_dialog)
	help_dialog.popup_centered(Vector2i(580, 520))

func _notify(message: String) -> void:
	feedback = message
	feedback_timer = 7

func _time(value: float) -> String:
	return "%02d:%02d" % [int(value) / 60, int(value) % 60]

func _update_ui() -> void:
	if not is_instance_valid(clock_label): return
	clock_label.text = _time(minute)
	day_label.text = "春 %02d 日 · 星期%s" % [day, ["一", "二", "三", "四", "五", "六", "日"][(day - 1) % 7]]
	period_label.text = "世界服务未连接" if not connected else ("已暂停 · 世界状态已保存" if paused else world_period + " · 居民各自忙碌")
	var npc := residents[selected]
	name_label.text = npc.display_name
	name_label.add_theme_color_override("font_color", npc.color)
	role_label.text = npc.role
	bio_label.text = npc.bio
	activity_label.text = ("●  " if npc.arrived else "↗  ") + npc.activity()
	location_label.text = ("所在地点  /  " if npc.arrived else "正在前往  /  ") + npc.destination_name()
	var atlas := AtlasTexture.new()
	atlas.atlas = npc.texture
	atlas.region = Rect2(0, 0, 16, 24)
	portrait.texture = atlas
	for i in range(7):
		var visible_row := i < npc.schedule.size()
		schedule_labels[i].visible = visible_row
		schedule_times[i].visible = visible_row
		if not visible_row: continue
		var entry: Dictionary = npc.schedule[i]
		schedule_times[i].text = _time(entry.time)
		schedule_labels[i].text = ("● " if i == npc.current_entry else "·  ") + entry.activity
		var col := GOLD if i == npc.current_entry else MUTED
		schedule_labels[i].add_theme_color_override("font_color", col)
		schedule_times[i].add_theme_color_override("font_color", col)
	for i in resident_buttons.size():
		resident_buttons[i].add_theme_color_override("font_color", residents[i].color if i == selected else MUTED)
		resident_buttons[i].text = ("● " if i == selected else "") + residents[i].display_name
	follow_button.text = "查看%s的日常  →" % npc.display_name
	pause_button.text = "▶" if paused else "Ⅱ"
	for i in speed_buttons.size(): speed_buttons[i].add_theme_color_override("font_color", GOLD if speed_factor == [1, 4, 12][i] else MUTED)
	route_button.text = "路线 · " + ("开" if show_routes else "关")
	status_label.text = "世界已连接 · 状态 #%d · SQLite 持久化" % world_revision if connected else "等待本地世界服务……"
	toast.visible = feedback_timer > 0
	toast_label.text = feedback
	# Keep long hints within the footer's available width.
	status_label.size.x = 514
	status_label.clip_text = true

func _draw() -> void:
	draw_set_transform(ORIGIN, 0, Vector2(MAP_SCALE, MAP_SCALE))
	draw_texture(town_texture, Vector2.ZERO)
	if show_routes:
		for npc in residents:
			if npc.route.size() > 0:
				var points := PackedVector2Array([npc.position])
				points.append_array(npc.route)
				if points.size() > 1: draw_polyline(points, Color(npc.color, 0.50), 1.0, false)
	# Only NPCs are rendered; no player or controllable actor exists.
	var actors: Array[Dictionary] = []
	for i in residents.size():
		var npc := residents[i]
		actors.append({"pos":npc.position, "texture":npc.texture, "facing":npc.facing, "anim":npc.animation_time, "moving":npc.moving, "index":i})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	for actor in actors:
		var pos: Vector2 = actor.pos.round()
		draw_ellipse_shadow(pos)
		if actor.index == selected: draw_arc(pos + Vector2(0, 1), 6, 0, TAU, 16, residents[selected].color, 1)
		var frame := int(actor.anim * 8) % 3 if actor.moving else 0
		draw_texture_rect_region(actor.texture, Rect2(pos - Vector2(8, 20), Vector2(16, 24)), Rect2(frame * 16, actor.facing * 24, 16, 24))
		var title: String = residents[actor.index].display_name
		var color: Color = residents[actor.index].color
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 8
		draw_style_box(_tag_style(), Rect2(pos.x - width / 2, pos.y - 32, width, 11))
		draw_string(font, pos + Vector2(-width / 2 + 4, -24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, color)
	# Subtle dusk tint follows the simulation clock.
	var dusk := clampf((minute - 1050) / 250.0, 0, 0.24)
	if minute < 360: dusk = 0.24
	draw_rect(Rect2(Vector2.ZERO, Vector2(544, 368)), Color(0.15, 0.20, 0.31, dusk))
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow(pos: Vector2) -> void:
	draw_set_transform(ORIGIN + pos * MAP_SCALE, 0, Vector2(2, 0.7))
	draw_circle(Vector2(0, 4), 5, Color(0.15, 0.23, 0.13, 0.30))
	draw_set_transform(ORIGIN, 0, Vector2(MAP_SCALE, MAP_SCALE))

func _tag_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("243a2ee6")
	style.set_corner_radius_all(2)
	return style

func _run_smoke_test() -> void:
	# A real rendered frame catches missing imports, broken UI and drawing errors.
	await get_tree().process_frame
	await get_tree().process_frame
	for attempt in range(100):
		if connected: break
		await get_tree().create_timer(0.1).timeout
	if not connected:
		push_error("SMOKE FAILED: world API did not connect")
		get_tree().quit(1)
		return
	_enqueue("/clock", {"paused": true}, true)
	_enqueue("/advance", {"minutes": 50}, true)
	while api_busy or not api_queue.is_empty(): await get_tree().process_frame
	_update_ui()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	get_viewport().get_texture().get_image().save_png("res://test-output/town-preview.png")
	print("SMOKE PASS: rendered town and UI to test-output/town-preview.png")
	get_tree().quit()
