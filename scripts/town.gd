extends Node2D

const ORIGIN := Vector2(24, 118)
const MAP_SCALE := 2.0
const INK := Color("e6e4d4")
const MUTED := Color("93a69a")
const GOLD := Color("dbbd83")
const DATA := [
	{"id":"mia", "name":"米娅", "role":"图书管理员", "color":"d59a83", "home":"home_mia", "bio":"喜欢旧书、手写信和清晨的阳光。\n正在整理小镇的口述历史。", "schedule":[
		{"time":0,"place":"home_mia","activity":"在家读书"}, {"time":480,"place":"library","activity":"整理书架"},
		{"time":660,"place":"cafe","activity":"喝一杯拿铁"}, {"time":780,"place":"library","activity":"修复旧书"},
		{"time":1020,"place":"park","activity":"公园散步"}, {"time":1140,"place":"home_mia","activity":"回家读书"}]},
	{"id":"oliver", "name":"奥利弗", "role":"咖啡师", "color":"96b9b6", "home":"home_oliver", "bio":"用一杯热咖啡记住每个人的故事。\n午后常到湖边寻找新菜单的灵感。", "schedule":[
		{"time":0,"place":"home_oliver","activity":"在家休息"}, {"time":480,"place":"cafe","activity":"准备开店"},
		{"time":720,"place":"square","activity":"午间休息"}, {"time":780,"place":"cafe","activity":"烘焙咖啡豆"},
		{"time":1020,"place":"lake","activity":"湖边放空"}, {"time":1140,"place":"home_oliver","activity":"收工回家"}]},
	{"id":"leo", "name":"里奥", "role":"艺术系学生", "color":"c2c591", "home":"studio", "bio":"随身带着画本，收集小镇的颜色。\n梦想为每一位居民画一幅肖像。", "schedule":[
		{"time":0,"place":"studio","activity":"整理画具"}, {"time":480,"place":"school","activity":"参加绘画课"},
		{"time":660,"place":"park","activity":"树下写生"}, {"time":780,"place":"cafe","activity":"与朋友碰面"},
		{"time":900,"place":"studio","activity":"创作新作品"}, {"time":1080,"place":"lake","activity":"记录落日"},
		{"time":1200,"place":"studio","activity":"回工作室休息"}]}
]

var world := TownWorld.new()
var residents: Array[TownResident] = []
var town_texture: Texture2D = preload("res://assets/town.png")
var player_texture: Texture2D = preload("res://assets/player.png")
var font: SystemFont
var serif: SystemFont
var player := Vector2(264, 216)
var player_route := PackedVector2Array()
var player_facing := 0
var player_anim := 0.0
var player_moving := false
var minute := 470.0
var day := 1
var speed_factor := 1.0
var paused := false
var show_routes := true
var selected := 0
var elapsed := 0.0
var hover_cell := Vector2i(-1, -1)
var feedback := "欢迎来到橡树镇。去认识一位新邻居吧。"
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

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "serif"])
	for data in DATA: residents.append(TownResident.new(data, world))
	_build_ui()
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
	_label(root, "●  自由探索 · 校园小镇", Vector2(413, 35), 12, Color("bac998"))
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
	_label(root, "✦  你   ·   3 位居民   ·   9 处地点", Vector2(55, 811), 11, Color("e2dabe"))
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
	follow_button = _button(root, "寻找米娅  →", Rect2(1156, 775, 240, 34), _go_to_selected)
	_label(root, "点击居民查看信息 · E 与附近居民交谈", Vector2(1156, 823), 10, MUTED)
	# Footer: controls and speed stay visible for quick acceptance testing.
	_label(root, "W A S D / 方向键", Vector2(25, 873), 12, GOLD)
	_label(root, "移动", Vector2(156, 873), 12, MUTED)
	_label(root, "鼠标左键", Vector2(205, 873), 12, GOLD)
	_label(root, "寻路 / 查看居民", Vector2(278, 873), 12, MUTED)
	status_label = _label(root, "", Vector2(424, 873), 11, MUTED)
	pause_button = _button(root, "Ⅱ", Rect2(954, 865, 38, 28), _toggle_pause)
	for i in range(3):
		var value: float = [1.0, 4.0, 12.0][i]
		speed_buttons.append(_button(root, "%d×" % value, Rect2(1000 + i * 48, 865, 42, 28), _set_speed.bind(value)))
	_button(root, "+1h", Rect2(1146, 865, 55, 28), _skip_hour)
	route_button = _button(root, "路线 · 开", Rect2(1210, 865, 91, 28), _toggle_routes)
	_button(root, "重置", Rect2(1310, 865, 106, 28), _reset)

func _process(delta: float) -> void:
	elapsed += delta
	feedback_timer = maxf(0, feedback_timer - delta)
	if not paused:
		minute += delta * 2.0 * speed_factor
		while minute >= 1440:
			minute -= 1440
			day += 1
		for npc in residents:
			npc.sync_schedule(minute, day, world)
			npc.tick(delta * speed_factor)
	_update_player(delta)
	hover_cell = world.cell((get_global_mouse_position() - ORIGIN) / MAP_SCALE)
	ui_timer += delta
	if ui_timer >= 0.12:
		ui_timer = 0
		_update_ui()
	queue_redraw()

func _update_player(delta: float) -> void:
	player_anim += delta
	var direction := Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction = Vector2i.LEFT
	elif Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction = Vector2i.RIGHT
	elif Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction = Vector2i.UP
	elif Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction = Vector2i.DOWN
	if direction != Vector2i.ZERO:
		if player_route.size() > 1: player_route.resize(1)
		if player_route.is_empty():
			var next := world.cell(player) + direction
			player_facing = 1 if direction.x < 0 else (2 if direction.x > 0 else (3 if direction.y < 0 else 0))
			if world.walkable(next): player_route.append(world.center(next))
	player_moving = not player_route.is_empty()
	var budget := delta * 65.0
	while budget > 0 and not player_route.is_empty():
		var difference := player_route[0] - player
		if difference.length() > 0.1:
			if abs(difference.x) > abs(difference.y): player_facing = 2 if difference.x > 0 else 1
			else: player_facing = 0 if difference.y > 0 else 3
		var distance := difference.length()
		if distance <= budget:
			player = player_route[0]
			player_route.remove_at(0)
			budget -= distance
		else:
			player += difference.normalized() * budget
			budget = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := (get_global_mouse_position() - ORIGIN) / MAP_SCALE
		if not Rect2(Vector2.ZERO, Vector2(TownWorld.SIZE * 16)).has_point(local): return
		for i in residents.size():
			if local.distance_to(residents[i].position - Vector2(0, 7)) < 13:
				_select(i)
				return
		_walk_to(world.cell(local))
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: _toggle_pause()
			KEY_TAB: _select((selected + 1) % residents.size())
			KEY_E: _interact()
			KEY_ESCAPE: player_route.clear()
			KEY_R: _toggle_routes()

func _walk_to(destination: Vector2i) -> void:
	if not world.walkable(destination):
		_notify("这里无法通行，请点击道路或草地。")
		return
	var route := world.path(player, destination)
	if route.is_empty():
		_notify("无法到达这里。")
		return
	player_route = route
	if player.distance_to(player_route[0]) < 0.1: player_route.remove_at(0)
	_notify("正在前往标记地点 · Esc 取消")

func _select(index: int) -> void:
	selected = index
	_update_ui()

func _go_to_selected() -> void:
	_walk_to(world.cell(residents[selected].position))
	_notify("前往%s当前所在的位置。" % residents[selected].display_name)

func _interact() -> void:
	var nearest := -1
	var distance := 36.0
	for i in residents.size():
		var test_distance := player.distance_to(residents[i].position)
		if test_distance < distance:
			distance = test_distance
			nearest = i
	if nearest >= 0:
		_select(nearest)
		_notify(["米娅：早安！图书馆总有一个位置留给你。", "奥利弗：想喝点什么？今天的咖啡豆很香。", "里奥：你看，今天的树影像不像一幅画？"][nearest])
	else: _notify("靠近居民后按 E，就可以打个招呼。")

func _toggle_pause() -> void:
	paused = not paused
	_update_ui()

func _set_speed(value: float) -> void:
	speed_factor = value
	_update_ui()

func _skip_hour() -> void:
	minute += 60
	if minute >= 1440:
		minute -= 1440
		day += 1
	for npc in residents: npc.sync_schedule(minute, day, world)
	_notify("已快进 1 小时，居民正按日程前往下一站。")
	_update_ui()

func _toggle_routes() -> void:
	show_routes = not show_routes
	_update_ui()

func _reset() -> void:
	minute = 470
	day = 1
	paused = false
	speed_factor = 1
	player = world.center(Vector2i(16, 13))
	player_route.clear()
	residents.clear()
	for data in DATA: residents.append(TownResident.new(data, world))
	_notify("新的一天开始了。早安，橡树镇。")
	_update_ui()

func _show_help() -> void:
	if not is_instance_valid(help_dialog):
		help_dialog = AcceptDialog.new()
		help_dialog.title = "欢迎来到橡树镇 · 操作说明"
		help_dialog.dialog_text = "WASD / 方向键    四方向移动，遇到障碍会停下\n\n鼠标左键    点击道路或草地，自动寻路\n点击居民 / Tab    查看或切换居民信息\nE    与附近的居民打招呼\nEsc    取消玩家当前的行走路线\n\n空格    暂停 / 继续小镇时间，玩家仍可探索\n1× / 4× / 12×    调整时间与居民行走速度\n+1h    快进一小时，观察日程变化\nR    显示 / 隐藏居民路线\n\n居民每天按固定日程活动，跨日后自动循环。\n本阶段建筑采用剖面展示，活动地点位于建筑门前。"
		help_dialog.add_theme_font_override("font", font)
		help_dialog.add_theme_font_size_override("font_size", 16)
		help_dialog.ok_button_text = "开始散步"
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
	period_label.text = "已暂停 · 玩家仍可探索" if paused else ("清晨 · 小镇正在醒来" if minute < 660 else ("白昼 · 各自忙碌的日常" if minute < 1020 else "傍晚 · 慢慢走回家"))
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
	follow_button.text = "寻找%s  →" % npc.display_name
	pause_button.text = "▶" if paused else "Ⅱ"
	for i in speed_buttons.size(): speed_buttons[i].add_theme_color_override("font_color", GOLD if speed_factor == [1, 4, 12][i] else MUTED)
	route_button.text = "路线 · " + ("开" if show_routes else "关")
	status_label.text = feedback if feedback_timer > 0 else "日常在继续，故事正发生。"
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
	if player_route.size() > 0:
		var points := PackedVector2Array([player])
		points.append_array(player_route)
		if points.size() > 1: draw_polyline(points, Color("f6e1ac"), 1.0, false)
		var goal := player_route[-1]
		draw_arc(goal, 5 + sin(elapsed * 4), 0, TAU, 16, GOLD, 1.0)
	if world.walkable(hover_cell):
		draw_rect(Rect2(Vector2(hover_cell * 16) + Vector2(1, 1), Vector2(14, 14)), Color(1, 0.95, 0.7, 0.25), false, 1)
	# Sort actors by their feet for correct overlap.
	var actors: Array[Dictionary] = []
	actors.append({"pos":player, "texture":player_texture, "facing":player_facing, "anim":player_anim, "moving":player_moving, "index":-1})
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
		var title := "你" if actor.index == -1 else residents[actor.index].display_name
		var color := GOLD if actor.index == -1 else residents[actor.index].color
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
	minute = 510
	for npc in residents:
		npc.sync_schedule(minute, day, world)
		npc.tick(5)
	_walk_to(Vector2i(17, 12))
	_update_ui()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	get_viewport().get_texture().get_image().save_png("res://test-output/town-preview.png")
	print("SMOKE PASS: rendered town and UI to test-output/town-preview.png")
	get_tree().quit()
