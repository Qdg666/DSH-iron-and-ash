extends Control

## 大地图：像骑马与砍杀那样，队伍在一张开放地图上自由行走。
## 走大路快、走野地慢且容易遇敌；靠近城镇/据点按 E 进入；接敌后切入六边形战棋。

const SPEED := 170.0          # 基础速度（像素/秒）
const DAY_DIST := 700.0       # 走这么远算过了一天
const ON_ROAD_SPEED := 1.35
const OFF_ROAD_SPEED := 0.82
const ROAD_HALF_WIDTH := 20.0
const ENTER_RADIUS := 64.0

var _t := 0.0
var _cam := Vector2.ZERO
var _dest := Vector2(-1, -1)
var _day_accum := 0.0
var _paused := false
var _near := ""
var _roamers: Array = []
var _last_spawn_day := 1
var _hint_life := 0.0
var _game_over_shown := false
var _party: Control = null
var _party_sel_id := ""
var _party_pick := -1

var _tex: Texture2D
var _top: Panel
var _lbl_day: Label
var _lbl_gold: Label
var _lbl_food: Label
var _lbl_res: Label
var _roster: PartyList
var _hint: Label
var _modal: Control = null

# 世界装饰（一次性生成）
var _grass: Array = []
var _trees: Array = []
var _hills: Array = []
var _rocks: Array = []

const TITLE_TEXT := "铁 与 灰"

# —— 队伍名册（自绘、可点） ——

class PartyList extends Control:
	signal member_clicked(m: Dictionary)
	var _hover := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		Ui.frame(self, Rect2(Vector2.ZERO, size), Color(0.055, 0.045, 0.038, 0.90), Ui.BORDER, 10.0)
		Ui.text(self, Vector2(14, 27), "队 伍", 18, Ui.GOLD)
		var ms: Array = Game.alive_party()
		Ui.text(self, Vector2(size.x - 66, 27), "%d / %d" % [ms.size(), Game.MAX_PARTY], 13, Ui.PARCH_LOW)
		if ms.is_empty():
			Ui.text(self, Vector2(14, 62), "没有人了。", 15, Ui.PARCH_LOW)
			return
		for i in range(ms.size()):
			var m: Dictionary = ms[i]
			var y := 44.0 + float(i) * 58.0
			if i == _hover:
				draw_rect(Rect2(6, y - 6, size.x - 12, 54), Color(1, 1, 1, 0.035), true)
				draw_rect(Rect2(6, y - 6, 2, 54), Ui.GOLD, true)
			var cond := float(m.get("cond", 1.0))
			Ui.text(self, Vector2(14, y + 12), str(m.get("name", "无名者")), 15,
				Ui.PARCH if cond > 0.5 else Color("b98a72"))
			var tr := clampi(int(m.get("training", 0)), 0, 2)
			Ui.text(self, Vector2(14, y + 31), "%s · %s" % [str(m.get("arch", "")), WarUnit.TRAIN_NAMES[tr]],
				12, Ui.PARCH_LOW)
			Ui.bar(self, Rect2(size.x - 106, y + 7, 88, 7), cond, Ui.hp_color(cond))
			var marks: Array = []
			for p in m.get("severed", []):
				marks.append(WarUnit.PART_SHORT.get(str(p), "断"))
			var tail := ""
			if not marks.is_empty():
				tail = "断：" + "、".join(marks)
			elif cond < 0.45:
				tail = "重伤"
			if tail != "":
				Ui.text(self, Vector2(size.x - 106, y + 34), tail, 11, Color("c06a55"))
		Ui.text(self, Vector2(14, size.y - 14), "点击查看装备与伤势", 11,
			Color(Ui.PARCH_LOW.r, Ui.PARCH_LOW.g, Ui.PARCH_LOW.b, 0.7))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var idx := int(floor((event.position.y - 38.0) / 58.0))
			if event.position.y < 38.0:
				idx = -1
			if idx < 0 or idx >= Game.alive_party().size():
				idx = -1
			if idx != _hover:
				_hover = idx
				queue_redraw()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var idx := int(floor((event.position.y - 38.0) / 58.0))
			if idx >= 0 and idx < Game.alive_party().size():
				member_clicked.emit(Game.alive_party()[idx])

class MemberBust extends Control:
	var unit: WarUnit = null

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("120e0b"), true)
		draw_rect(Rect2(Vector2.ZERO, size), Ui.BORDER, false, 1.0)
		if unit == null:
			return
		Doll.draw_bust(self, Vector2(size.x * 0.5, size.y * 0.58), 210.0, unit, 1.0, false)

# —— 初始化 ——

func setup(arg: Dictionary = {}) -> void:
	if Game.party.is_empty():
		Game.new_game()
	if Game.party_pos.x < 0.0:
		Game.party_pos = MapData.world_pos("camp")
	_tex = load("res://图标.svg")
	_gen_world()
	_build()
	Game.notice.connect(_toast)
	Game.state_changed.connect(_refresh)
	_spawn_roamers()
	_last_spawn_day = Game.day
	_cam = _clamp_cam(Game.party_pos - _view_size() * 0.5)
	_refresh()
	_toast("WASD 或点击地面行军。走大路快，走野地会遇到人。")
	if "--autowalk" in OS.get_cmdline_user_args():
		_dest = MapData.clamp_world(Game.party_pos + Vector2(820, -260))
	# 开发用：直接打开队伍/市场，方便截图检查界面
	if "--openparty" in OS.get_cmdline_user_args():
		_open_party()
	elif "--openmarket" in OS.get_cmdline_user_args():
		Game.node_id = "town"
		_open_market()
	elif "--opentavern" in OS.get_cmdline_user_args():
		Game.node_id = "town"
		_open_tavern()
	elif "--partytest" in OS.get_cmdline_user_args():
		_dev_party_test()
	elif "--slotpicker" in OS.get_cmdline_user_args():
		_open_party()
		if not Game.alive_party().is_empty():
			_open_slot_picker(Game.alive_party()[0], "torso")
	if arg.has("result"):
		Game.last_result = {}
		_show_battle_result(arg["result"])
	elif not Game.last_result.is_empty():
		var r: Dictionary = Game.last_result
		Game.last_result = {}
		_show_battle_result(r)

func _build() -> void:
	_top = Panel.new()
	_top.add_theme_stylebox_override("panel", Ui.box(Color("0f0c09"), Ui.BORDER, 1, 0))
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_bottom = 58

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	_top.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	row.add_child(Ui.label(TITLE_TEXT, 21, Ui.GOLD))
	_lbl_day = Ui.label("", 16, Ui.PARCH)
	row.add_child(_lbl_day)
	_lbl_gold = Ui.label("", 15, Color("c8b06a"))
	row.add_child(_lbl_gold)
	_lbl_food = Ui.label("", 15, Color("a9b184"))
	row.add_child(_lbl_food)
	_lbl_res = Ui.label("", 15, Color("b08f8a"))
	row.add_child(_lbl_res)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var b_party := Ui.button("队 伍", 14)
	b_party.custom_minimum_size = Vector2(78, 30)
	b_party.pressed.connect(_open_party)
	row.add_child(b_party)
	var b_save := Ui.button("存 档", 14)
	b_save.custom_minimum_size = Vector2(78, 30)
	b_save.pressed.connect(_on_save)
	row.add_child(b_save)
	var b_menu := Ui.button("主菜单", 14)
	b_menu.custom_minimum_size = Vector2(78, 30)
	b_menu.pressed.connect(_on_menu)
	row.add_child(b_menu)

	_roster = PartyList.new()
	_roster.member_clicked.connect(_show_member)
	add_child(_roster)

	_hint = Ui.label("", 14, Ui.PARCH_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	_layout()
	resized.connect(_layout)
	set_process(true)

func _layout() -> void:
	_roster.position = Vector2(16, 74)
	_roster.size = Vector2(286, 58.0 + float(maxi(1, Game.alive_party().size())) * 58.0 + 26.0)
	_hint.position = Vector2(0, size.y - 34)
	_hint.size = Vector2(size.x, 24)
	_cam = _clamp_cam(_cam)

func _view_size() -> Vector2:
	return Vector2(size.x, maxf(120.0, size.y - 58.0))

func _clamp_cam(c: Vector2) -> Vector2:
	var v := _view_size()
	return Vector2(
		clampf(c.x, 0.0, maxf(0.0, MapData.WORLD_SIZE.x - v.x)),
		clampf(c.y, 0.0, maxf(0.0, MapData.WORLD_SIZE.y - v.y)))

func sp(p: Vector2) -> Vector2:
	return p - _cam + Vector2(0, 58)

func _vis(p: Vector2, margin: float = 90.0) -> bool:
	var s := sp(p)
	return s.x > -margin and s.x < size.x + margin and s.y > 58.0 - margin and s.y < size.y + margin

# —— 每帧 ——

func _process(delta: float) -> void:
	_t += delta
	if _modal == null and _party == null and not _paused and not Game.alive_party().is_empty():
		_tick(delta)
	_update_camera(delta)
	_update_near()
	_update_hint(delta)
	queue_redraw()

func _tick(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir.length_squared() > 0.01:
		_dest = Vector2(-1, -1)
	elif _dest.x >= 0.0:
		var to_dest := _dest - Game.party_pos
		if to_dest.length() < 12.0:
			_dest = Vector2(-1, -1)
		else:
			dir = to_dest.normalized()
	if dir.length_squared() <= 0.01:
		return
	dir = dir.normalized()
	var on_road := MapData.distance_to_road(Game.party_pos) < ROAD_HALF_WIDTH
	var spd := SPEED * (ON_ROAD_SPEED if on_road else OFF_ROAD_SPEED)
	var step := spd * delta
	Game.party_pos = MapData.clamp_world(Game.party_pos + dir * step)
	_day_accum += step
	while _day_accum >= DAY_DIST:
		_day_accum -= DAY_DIST
		var notes: Array = Game.advance_days(1)
		if not notes.is_empty():
			_toast(str(notes[0]))
	# 走野地：可能撞上人
	if not on_road and _near == "" and randf() < 0.012 * delta:
		_start_battle("road", "野地", 0.8)
		return
	_tick_roamers(delta)

func _tick_roamers(delta: float) -> void:
	for r in _roamers.duplicate():
		var p: Vector2 = r["pos"]
		var to_p := Game.party_pos - p
		if to_p.length() < 440.0:
			r["pos"] = p + to_p.normalized() * float(r["speed"]) * delta
		else:
			var ph := float(r["phase"])
			r["pos"] = p + Vector2(cos(_t * 0.6 + ph), sin(_t * 0.45 + ph)) * float(r["speed"]) * 0.3 * delta
		r["pos"] = MapData.clamp_world(r["pos"])
		if Vector2(r["pos"]).distance_to(Game.party_pos) < 34.0:
			_roamers.erase(r)
			_start_battle("bandit", str(r["name"]), float(r["scale"]))
			return

func _update_camera(delta: float) -> void:
	var target := _clamp_cam(Game.party_pos - _view_size() * 0.5)
	_cam = _cam.lerp(target, 1.0 - exp(-7.0 * delta))

func _update_near() -> void:
	var id := MapData.nearest_node(Game.party_pos, ENTER_RADIUS)
	if id != _near:
		_near = id
		if id != "":
			Game.node_id = id

func _update_hint(delta: float) -> void:
	if _hint_life > 0.0:
		_hint_life -= delta
		if _hint_life < 0.9:
			_hint.modulate.a = clampf(_hint_life / 0.9, 0.0, 1.0)
		return
	_hint.modulate.a = 0.85
	if Game.food <= 0:
		_hint.text = "没有口粮了。人开始走不动，队伍在掉血。"
	elif _paused:
		_hint.text = "已暂停（空格继续）"
	elif _near != "":
		_hint.text = "按 E 进入 · %s" % MapData.node_name(_near)
	elif _dest.x >= 0.0:
		_hint.text = "正在前往…  （WASD 可随时接管）"
	else:
		_hint.text = "WASD / 点击地面 行军 · 靠城镇按 E 进入 · 空格 暂停"

func _spawn_roamers() -> void:
	_roamers.clear()
	var spots := [
		["den", "铁钩的匪帮", 1.05],
		["outpost", "溃兵", 0.85],
		["lumber", "林中劫掠者", 0.95],
	]
	for i in range(spots.size()):
		var base: Vector2 = MapData.world_pos(str(spots[i][0]))
		base += Vector2(randf_range(-200, 200), randf_range(-140, 140))
		_roamers.append({
			"name": str(spots[i][1]),
			"pos": MapData.clamp_world(base),
			"speed": 92.0 + float(i) * 9.0,
			"scale": float(spots[i][2]),
			"phase": randf() * TAU,
		})

# —— 进入城镇 ——

func _open_city(id: String) -> void:
	var n := MapData.node(id)
	if n.is_empty():
		return
	Game.node_id = id
	var type_names := {
		"camp": "营地", "village": "村子", "town": "镇子", "lumber": "伐木场",
		"ford": "渡口", "abbey": "修道院", "outpost": "哨所", "capital": "王庭", "den": "匪巢",
	}
	var box := _modal_open(str(n.get("name", "荒野")))
	box.add_child(Ui.label(str(type_names.get(str(n.get("type", "")), "荒野")), 13, Ui.GOLD))
	box.add_child(Ui.label("好感 %d · 买入折扣 %d%%" % [Game.rep_of(id),
		int(Game.shop_discount(id) * 100.0)], 11, Ui.PARCH_LOW))
	var body := Ui.label(str(n.get("desc", "")), 15, Ui.PARCH_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(620, 0)
	box.add_child(body)
	box.add_child(Ui.hline(Ui.BORDER))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	var count := 0
	for a in n.get("actions", []):
		var s := str(a)
		var label := ""
		var cb: Callable = Callable()
		if s == "rest":
			label = "休整一夜"
			cb = func(): _on_rest()
		elif s == "market":
			label = "市场"
			cb = func(): _open_market()
		elif s == "tavern":
			label = "酒馆"
			cb = func(): _open_tavern()
		elif s == "heal":
			label = "祈祷疗伤（20 金）"
			cb = func(): _on_heal()
		elif s.begins_with("event:"):
			var eid := s.substr(6)
			var ev := EventData.get_event(eid)
			if ev.is_empty():
				continue
			label = "「%s」" % str(ev.get("title", "事件"))
			cb = func(): _open_event(eid)
		elif s.begins_with("battle:"):
			var kind := s.substr(7)
			label = "拔刀（战斗）"
			cb = func(): _start_battle(kind, "匪徒", 1.0)
		elif s == "leave":
			continue
		if label == "":
			continue
		var b := Ui.button(label, 15)
		b.custom_minimum_size = Vector2(300, 38)
		b.pressed.connect(cb)
		grid.add_child(b)
		count += 1
	if count == 0:
		grid.add_child(Ui.label("这里没什么可做的。", 13, Ui.PARCH_LOW))

	var close := Ui.button("离开", 15)
	close.custom_minimum_size = Vector2(160, 36)
	close.pressed.connect(func(): _modal_close())
	box.add_child(close)

func _on_rest() -> void:
	Game.rest()
	_toast("你们休整了一天。有人守夜，有人梦见家里。")

func _on_heal() -> void:
	if Game.gold < 20:
		_toast("钱不够。修士看着你，没有笑。")
		return
	Game.spend_gold(20)
	Game.heal_all(0.4)
	Game.resolve = clampf(Game.resolve + 3.0, 0.0, 40.0)
	_toast("修士替你处理了伤口。他说：疼是好事。")

func _on_save() -> void:
	if Game.save_game():
		_toast("已存档。")
	else:
		_toast("存档失败。")

func _on_menu() -> void:
	_modal_choices("离开这张地图？", "没存档的进度会消失。", [
		{"label": "存档并回主菜单", "cb": func():
			Game.save_game()
			_modal_close()
			Game.scene_requested.emit("menu", {})},
		{"label": "不存了", "cb": func():
			_modal_close()
			Game.scene_requested.emit("menu", {})},
		{"label": "继续走", "cb": func(): _modal_close()},
	])

func _start_battle(kind: String, title: String, scale: float = 1.0) -> void:
	_modal_close()
	Game.start_battle(kind, title, scale)

# —— 输入 ——

func _gui_input(event: InputEvent) -> void:
	if _modal != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var world: Vector2 = mb.position - Vector2(0, 58) + _cam
			var id := MapData.nearest_node(world, 30.0)
			if id != "":
				_dest = MapData.world_pos(id)
			else:
				_dest = world
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dest = Vector2(-1, -1)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_ESCAPE:
		if _party != null:
			_close_party()
		elif _modal != null:
			_modal_close()
		else:
			_dest = Vector2(-1, -1)
	elif key.keycode == KEY_SPACE and _modal == null:
		_paused = not _paused
	elif (key.keycode == KEY_E or key.keycode == KEY_ENTER) and _modal == null and _near != "":
		_open_city(_near)

func _refresh() -> void:
	if _lbl_gold == null:
		return
	_lbl_day.text = "第 %d 日" % Game.day
	_lbl_gold.text = "金币 %d" % Game.gold
	_lbl_food.text = "口粮 %d（日耗 %d）" % [Game.food, Game.daily_food()]
	_lbl_res.text = "意志 %d" % int(Game.resolve)
	_roster.queue_redraw()
	_roster.size = Vector2(286, 58.0 + float(maxi(1, Game.alive_party().size())) * 58.0 + 26.0)
	_check_game_over()

func _check_game_over() -> void:
	if _game_over_shown or Game.alive_party().is_empty() == false:
		return
	_game_over_shown = true
	_modal_choices("队伍没了", "最后一个人也倒下了。\n名字会被记在镇公所的某张纸上，和别的名字一起。", [
		{"label": "回到主菜单", "cb": func():
			_modal_close()
			Game.scene_requested.emit("menu", {})},
	])

func _toast(text: String) -> void:
	if _hint == null:
		return
	_hint.text = text
	_hint.modulate.a = 1.0
	_hint_life = 4.0

# —— 队伍 / 背包 / 阵形 ——

func _member_by_id(id: String) -> Dictionary:
	for m in Game.alive_party():
		if str(m.get("id", "")) == id:
			return m
	return {}

## 开发用：模拟"选人 → 换位 → 从背包装备"的点击流程
func _dev_party_test() -> void:
	_open_party()
	await get_tree().create_timer(0.15).timeout
	print("PT_BEFORE ", Game.formation)
	_on_form_click(0)
	_on_form_click(0)
	_on_form_click(2)
	await get_tree().create_timer(0.15).timeout
	print("PT_AFTER ", Game.formation)
	if Game.inventory.size() > 0:
		_equip_from_bag(0)
	await get_tree().create_timer(0.2).timeout
	var m := _member_by_id(_party_sel_id)
	print("PT_SELECTED ", str(m.get("name", "")), " 背包=", Game.inventory.size())
	print("PT_GEAR ", Game.member_gear(m, "torso"))

func _party_close() -> void:
	if _party != null:
		_party.queue_free()
		_party = null

func _close_party() -> void:
	_party_pick = -1
	_party_close()

func _open_party() -> void:
	_modal_close()
	_party_close()
	Game.ensure_formation()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_party = layer
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.030, 0.025, 0.985)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var w := size.x
	var h := size.y
	layer.add_child(_at(Ui.label("队伍 · 背包 · 阵形", 25, Ui.GOLD), Vector2(28, 16)))
	layer.add_child(_at(Ui.label("金币 %d    背包 %d / %d" % [Game.gold, Game.inventory.size(),
		Game.INVENTORY_MAX], 14, Ui.PARCH_DIM), Vector2(300, 24)))
	var close := Ui.button("关闭（Esc）", 14)
	close.position = Vector2(w - 150, 16)
	close.size = Vector2(120, 34)
	close.pressed.connect(_close_party)
	layer.add_child(close)

	# —— 左：个人装备栏 ——
	var sel := _member_by_id(_party_sel_id)
	if sel.is_empty() and not Game.alive_party().is_empty():
		sel = Game.alive_party()[0]
		_party_sel_id = str(sel.get("id", ""))

	var left := Panel.new()
	left.position = Vector2(24, 70)
	left.size = Vector2(382, 476)
	left.add_theme_stylebox_override("panel", Ui.box(Color("12100d"), Ui.BORDER, 1, 0, 4))
	layer.add_child(left)
	var lm := MarginContainer.new()
	lm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lm.add_theme_constant_override("margin_left", 16)
	lm.add_theme_constant_override("margin_right", 16)
	lm.add_theme_constant_override("margin_top", 12)
	lm.add_theme_constant_override("margin_bottom", 12)
	left.add_child(lm)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 5)
	lm.add_child(lv)

	if sel.is_empty():
		lv.add_child(Ui.label("队伍里没有人。", 16, Ui.PARCH_LOW))
	else:
		lv.add_child(Ui.label(str(sel.get("name", "无名者")), 20, Ui.PARCH))
		var tr := clampi(int(sel.get("training", 0)), 0, 2)
		lv.add_child(Ui.label("%s · %s" % [str(sel.get("arch", "")), WarUnit.TRAIN_NAMES[tr]], 12, Ui.GOLD))
		lv.add_child(Ui.label("力量 %d  技巧 %d  速度 %d  体质 %d" % [
			int(sel.get("might", 10)), int(sel.get("skill", 10)),
			int(sel.get("spd", 10)), int(sel.get("con", 10))], 11, Ui.PARCH_DIM))
		var cond := float(sel.get("cond", 1.0))
		lv.add_child(Ui.label("状况 %d%%" % int(cond * 100.0), 11, Ui.hp_color(cond)))
		var sev: Array = []
		for p in sel.get("severed", []):
			sev.append(WarUnit.PART_NAMES.get(str(p), "断"))
		if not sev.is_empty():
			lv.add_child(Ui.label("残废：" + "、".join(sev), 11, Color("c06a55")))
		lv.add_child(Ui.hline(Ui.BORDER))
		lv.add_child(Ui.label("装备栏（点击更换）", 13, Ui.GOLD))
		for slot in Gear.SLOTS:
			var gd := Game.member_gear(sel, slot)
			var txt := Gear.slot_name(slot) + "　"
			if gd.is_empty():
				txt += "（空）"
			else:
				var g := Gear.from_dict(gd)
				txt += g.display_name() + "　" + _gear_stat_text(g)
			var b := Ui.button(txt, 12)
			b.custom_minimum_size = Vector2(340, 34)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			var s2: String = slot
			b.pressed.connect(func(): _open_slot_picker(sel, s2))
			lv.add_child(b)
		lv.add_child(Ui.label("要点：先在上面的部位换装；下方阵形点人可选中。", 10, Ui.PARCH_LOW))

	# —— 右上：团队背包 ——
	var bag := Panel.new()
	bag.position = Vector2(420, 70)
	bag.size = Vector2(w - 444, 476)
	bag.add_theme_stylebox_override("panel", Ui.box(Color("12100d"), Ui.BORDER, 1, 0, 4))
	layer.add_child(bag)
	var bm := MarginContainer.new()
	bm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bm.add_theme_constant_override("margin_left", 14)
	bm.add_theme_constant_override("margin_right", 14)
	bm.add_theme_constant_override("margin_top", 12)
	bm.add_theme_constant_override("margin_bottom", 12)
	bag.add_child(bm)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	bm.add_child(bv)
	bv.add_child(Ui.label("团队背包（点击物品，装给左侧选中角色）", 14, Ui.PARCH))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	if Game.inventory.is_empty():
		grid.add_child(Ui.label("背包里空空如也。", 13, Ui.PARCH_LOW))
	for i in range(Game.inventory.size()):
		var d: Dictionary = Game.inventory[i]
		var g := Gear.from_dict(d)
		var txt := "%s　%s　%d金" % [g.display_name(), _gear_stat_text(g), g.value()]
		var card := Ui.button(txt, 12)
		card.custom_minimum_size = Vector2(330, 52)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.clip_text = true
		var idx := i
		card.pressed.connect(func(): _equip_from_bag(idx))
		grid.add_child(card)

	# —— 下：阵形 ——
	var form := Panel.new()
	form.position = Vector2(24, 562)
	form.size = Vector2(w - 48, h - 578)
	form.add_theme_stylebox_override("panel", Ui.box(Color("12100d"), Ui.BORDER, 1, 0, 4))
	layer.add_child(form)
	form.add_child(_at(Ui.label("阵形 · 战斗初始站位", 16, Ui.PARCH), Vector2(18, 10)))
	var fhint := "点人选中并换装；再点同一人进入换位，再点另一格完成交换。"
	if _party_pick >= 0:
		fhint = "换位中：再点一个格子，把人与它交换。"
	form.add_child(_at(Ui.label(fhint, 12, Ui.GOLD if _party_pick >= 0 else Ui.PARCH_LOW),
		Vector2(250, 12)))
	form.add_child(_at(Ui.label("后排（远离中线）", 12, Ui.PARCH_DIM), Vector2(110, 40)))
	form.add_child(_at(Ui.label("前排（靠近中线）", 12, Ui.PARCH_DIM), Vector2(480, 40)))
	for row in range(4):
		for col in range(2):
			var slot := row * 2 + col
			var id := str(Game.formation[slot]) if slot < Game.formation.size() else ""
			var m := _member_by_id(id)
			var txt := "（空）"
			if not m.is_empty():
				txt = "%s · %s　%d%%" % [str(m.get("name", "")), str(m.get("arch", "")),
					int(float(m.get("cond", 1.0)) * 100.0)]
				if id == _party_sel_id:
					txt = "▶ " + txt
				if slot == _party_pick:
					txt = "⇄ " + txt
			var fb := Ui.button(txt, 13)
			fb.position = Vector2(110 + col * 370, 58 + row * 52)
			fb.size = Vector2(330, 42)
			fb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			fb.clip_text = true
			var s3 := slot
			fb.pressed.connect(func(): _on_form_click(s3))
			form.add_child(fb)
	form.add_child(_at(Ui.label("战斗中，前排更靠近敌人，后排更安全。", 11, Ui.PARCH_LOW),
		Vector2(880, 40)))

func _at(c: Control, p: Vector2) -> Control:
	c.position = p
	return c

func _gear_stat_text(g: Gear) -> String:
	if g.is_weapon():
		return "伤%.0f·%s·射程%d" % [g.damage(), g.damage_type_name(), g.attack_range()]
	return "甲%.0f" % g.armor()

func _equip_from_bag(idx: int) -> void:
	if idx < 0 or idx >= Game.inventory.size():
		return
	var m := _member_by_id(_party_sel_id)
	if m.is_empty():
		_toast("先在阵形里点一个人。")
		return
	var res: Dictionary = Game.equip_item_to(m, idx)
	_open_party()
	if bool(res.get("ok", false)):
		_toast("已装备：%s" % str(res.get("name", "")))
	else:
		_toast(str(res.get("msg", "装备失败。")))

func _on_form_click(slot: int) -> void:
	if slot < 0 or slot >= Game.FORMATION_SLOTS:
		return
	var id := str(Game.formation[slot]) if slot < Game.formation.size() else ""
	if id != "":
		if _party_pick >= 0 and _party_pick != slot:
			Game.swap_formation(_party_pick, slot)
			_party_pick = -1
		elif _party_sel_id == id:
			# 再点一次已选中的人：进入换位
			_party_pick = slot
		else:
			_party_sel_id = id
			_party_pick = -1
	else:
		if _party_pick >= 0:
			Game.swap_formation(_party_pick, slot)
			_party_pick = -1
	_open_party()

func _open_slot_picker(m: Dictionary, slot: String) -> void:
	var cur := Game.member_gear(m, slot)
	var box := _modal_open("更换 · %s" % Gear.slot_name(slot))
	var cur_txt := "当前：空"
	if not cur.is_empty():
		var cg := Gear.from_dict(cur)
		cur_txt = "当前：%s（%s）" % [cg.display_name(), _gear_stat_text(cg)]
	box.add_child(Ui.label(cur_txt, 14, Ui.PARCH_DIM))
	var found := 0
	for i in range(Game.inventory.size()):
		var d: Dictionary = Game.inventory[i]
		var g := Gear.from_dict(d)
		if g.slot() != slot:
			continue
		var b := Ui.button("%s　%s　%d 金" % [g.display_name(), _gear_stat_text(g), g.value()], 13)
		b.custom_minimum_size = Vector2(640, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		var m2 := m
		b.pressed.connect(func(): _do_equip(m2, idx))
		box.add_child(b)
		found += 1
	if found == 0:
		box.add_child(Ui.label("背包里没有能装在这个部位的装备。", 13, Ui.PARCH_LOW))
	if not cur.is_empty():
		var un := Ui.button("卸下当前装备", 14)
		un.custom_minimum_size = Vector2(200, 34)
		un.pressed.connect(func(): _do_unequip(m, slot))
		box.add_child(un)
	var cancel := Ui.button("取消", 14)
	cancel.custom_minimum_size = Vector2(120, 34)
	cancel.pressed.connect(func(): _modal_close())
	box.add_child(cancel)

func _do_equip(m: Dictionary, idx: int) -> void:
	var res: Dictionary = Game.equip_item_to(m, idx)
	_modal_close()
	_party_sel_id = str(m.get("id", ""))
	_open_party()
	if bool(res.get("ok", false)):
		_toast("已装备：%s" % str(res.get("name", "")))

func _do_unequip(m: Dictionary, slot: String) -> void:
	if Game.unequip_slot(m, slot):
		_modal_close()
		_party_sel_id = str(m.get("id", ""))
		_open_party()
		_toast("已卸下。")
	else:
		_toast("背包满了，卸不下来。")

# —— 市场 ——

func _open_market() -> void:
	var node := Game.node_id
	var box := _modal_open("市场 · %s" % MapData.node_name(node))
	box.add_child(Ui.label("金币 %d　好感 %d　买入折扣 %d%%" % [Game.gold, Game.rep_of(node),
		int(Game.shop_discount(node) * 100.0)], 13, Ui.PARCH_DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)

	inner.add_child(Ui.label("买入 · 装备", 16, Ui.GOLD))
	var items := Game.shop_items(node)
	if items.is_empty():
		inner.add_child(Ui.label("货架空了。过几天会补货。", 12, Ui.PARCH_LOW))
	for i in range(items.size()):
		var d: Dictionary = items[i]
		var g := Gear.from_dict(d)
		var price := Game.buy_price(node, d)
		var idx := i
		_market_row(inner, "%s　%s" % [g.display_name(), _gear_stat_text(g)],
			"%d 金" % price, "买 入",
			Game.gold >= price and Game.inventory.size() < Game.INVENTORY_MAX,
			func():
				var res: Dictionary = Game.buy_shop_item(node, idx)
				if bool(res.get("ok", false)):
					_toast("买下：%s（%d 金）" % [str(res.get("name", "")), int(res.get("price", 0))])
				else:
					_toast(str(res.get("msg", "买不了。")))
				_open_market())

	inner.add_child(Ui.hline(Ui.BORDER))
	inner.add_child(Ui.label("卖出 · 背包", 16, Ui.GOLD))
	if Game.inventory.is_empty():
		inner.add_child(Ui.label("背包里没有东西可卖。", 12, Ui.PARCH_LOW))
	for i in range(Game.inventory.size()):
		var d2: Dictionary = Game.inventory[i]
		var g2 := Gear.from_dict(d2)
		var price2 := Game.sell_price(d2)
		var idx2 := i
		_market_row(inner, "%s　%s" % [g2.display_name(), _gear_stat_text(g2)],
			"%d 金" % price2, "卖 出", true,
			func():
				var res: Dictionary = Game.sell_inventory_item(idx2)
				if bool(res.get("ok", false)):
					_toast("卖出：%s（%d 金）" % [str(res.get("name", "")), int(res.get("price", 0))])
				_open_market())

	inner.add_child(Ui.hline(Ui.BORDER))
	inner.add_child(Ui.label("口粮", 16, Ui.GOLD))
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	inner.add_child(row1)
	var b1 := Ui.button("买 1 份（3 金）", 13)
	b1.pressed.connect(func():
		if Game.buy_food(1):
			_toast("买了一份口粮。")
		else:
			_toast("钱不够。")
		_open_market())
	row1.add_child(b1)
	var b5 := Ui.button("买 5 份（15 金）", 13)
	b5.pressed.connect(func():
		if Game.buy_food(5):
			_toast("买了五份口粮。")
		else:
			_toast("钱不够。")
		_open_market())
	row1.add_child(b5)
	row1.add_child(Ui.label("现有口粮 %d（日耗 %d）" % [Game.food, Game.daily_food()], 12, Ui.PARCH_LOW))

	var close := Ui.button("离开市场", 15)
	close.custom_minimum_size = Vector2(160, 36)
	close.pressed.connect(func(): _modal_close())
	box.add_child(close)

func _market_row(parent: VBoxContainer, name: String, price: String, btn_text: String,
		enabled: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Ui.label(name, 12, Ui.PARCH)
	l.custom_minimum_size = Vector2(440, 0)
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var p := Ui.label(price, 12, Color("c8b06a"))
	p.custom_minimum_size = Vector2(80, 0)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(p)
	var b := Ui.button(btn_text, 12)
	b.custom_minimum_size = Vector2(72, 28)
	b.disabled = not enabled
	b.pressed.connect(cb)
	row.add_child(b)

# —— 酒馆 ——

const RUMORS := [
	"「铁砧镇的悬赏换人了。上一个被吊在门口，风干了三天。」",
	"「匪巢里有个断手的人。他们管他叫『铁钩』，说他一晚上能杀七个。」",
	"「修道院的新坟比去年多了两倍。修士说都是病死的，可病怎么会断手。」",
	"「王庭的使者又在路上了。每次来，税就多一成，人少一成。」",
	"「黑水渡口的老头不收钱。他说他收的是别的。没人敢问他收什么。」",
	"「边境哨所的哨长在墙上刻日子。刻到一半就忘了自己刻到第几天。」",
	"「林子深处有钟声。伐木工说，是从地底下响的。」",
]

func _open_tavern() -> void:
	var box := _modal_open("酒馆")
	var body := Ui.label("屋里很闷。有人趴在桌上，有人在角落里数硬币。\n墙上钉着一张旧地图，边角被撕掉了。", 14, Ui.PARCH_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(620, 0)
	box.add_child(body)
	box.add_child(Ui.hline(Ui.BORDER))
	box.add_child(Ui.label("招募　队伍 %d / %d" % [Game.party_size(), Game.MAX_PARTY], 14, Ui.GOLD))
	for arch in Game.RECRUITABLE:
		var a2: String = str(arch)
		var cost := int(Game.RECRUIT_COST[a2])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var l := Ui.label("%s　%d 金" % [a2, cost], 13, Ui.PARCH)
		l.custom_minimum_size = Vector2(140, 0)
		row.add_child(l)
		var d := Ui.label(Gen.arch_desc(a2), 11, Ui.PARCH_LOW)
		d.custom_minimum_size = Vector2(330, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(d)
		var b := Ui.button("雇佣", 12)
		b.custom_minimum_size = Vector2(66, 28)
		b.disabled = Game.gold < cost or Game.party_size() >= Game.MAX_PARTY
		b.pressed.connect(func():
			if Game.recruit(a2):
				_toast("一个%s加入了队伍。" % a2)
			_open_tavern())
		row.add_child(b)
	box.add_child(Ui.hline(Ui.BORDER))

	var b1 := Ui.button("打听消息（5 金）", 15)
	b1.pressed.connect(func():
		if not Game.spend_gold(5):
			_toast("你摸了摸口袋，又把手拿出来。")
			return
		var line: String = RUMORS[randi() % RUMORS.size()]
		Game.flags["heard_rumor"] = true
		_modal_choices("酒馆", line, [{"label": "记下了", "cb": func(): _modal_close()}]))
	box.add_child(b1)

	var b2 := Ui.button("喝一杯（3 金）", 15)
	b2.pressed.connect(func():
		if not Game.spend_gold(3):
			_toast("你只能看着别人的杯子。")
			return
		Game.apply_effects({"morale": 3, "heal": 0.03})
		_toast("酒是酸的，但胃里暖起来。"))
	box.add_child(b2)

	var b3 := Ui.button("回到大路", 15)
	b3.pressed.connect(func(): _modal_close())
	box.add_child(b3)

# —— 事件 ——

func _open_event(id: String) -> void:
	var ev := Game.take_event(id)
	if ev.is_empty():
		return
	if ev.has("blocked"):
		_modal_choices("这里", str(ev.get("text", "什么也没有。")), [
			{"label": "走开", "cb": func(): _modal_close()},
		])
		return
	_show_event_page(ev)

func _show_event_page(ev: Dictionary) -> void:
	var box := _modal_open(str(ev.get("title", "事件")))
	var body := Ui.label(str(ev.get("text", "")), 15, Ui.PARCH_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(640, 0)
	box.add_child(body)
	box.add_child(Ui.hline(Ui.BORDER))
	for c in ev.get("choices", []):
		var ch: Dictionary = c
		var req: Dictionary = ch.get("require", {})
		var ok := true
		var why := ""
		if req.has("gold") and Game.gold < int(req["gold"]):
			ok = false
			why = "（金币不足）"
		var b := Ui.button(str(ch.get("label", "…")) + why, 15)
		b.custom_minimum_size = Vector2(640, 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not ok
		var ch2: Dictionary = ch
		b.pressed.connect(func(): _choose(ch2))
		box.add_child(b)

func _choose(ch: Dictionary) -> void:
	var result := str(ch.get("result", ""))
	var line := Game.apply_effects(ch.get("effects", {}))
	var text := result
	if line != "":
		text += "\n\n" + line
	_modal_choices("", text, [{"label": "继续", "cb": func():
		_modal_close()
		_refresh()}])

func _show_battle_result(res: Dictionary) -> void:
	var win := int(res.get("winner", 1)) == 0
	var title := "战斗结束" if win else "你们败了"
	var lines: Array = []
	if win:
		lines.append("战场安静下来。苍蝇先回来。")
		lines.append("缴获 %d 金币，%d 份口粮。" % [int(res.get("gold", 0)), int(res.get("food", 0))])
	else:
		lines.append("你们拖着还能走的人离开了。有人没能走。")
	var dead: Array = res.get("dead", [])
	if not dead.is_empty():
		lines.append("死了：%s" % "、".join(dead))
	if int(res.get("wounded", 0)) > 0:
		lines.append("重伤 %d 人。" % int(res.get("wounded", 0)))
	_modal_choices(title, "\n".join(lines), [
		{"label": "回到地图", "cb": func():
			_modal_close()
			_refresh()},
	])

# —— 角色详情 ——

func _show_member(m: Dictionary) -> void:
	var box := _modal_open(str(m.get("name", "无名者")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)

	var bust := MemberBust.new()
	bust.unit = Gen.from_member(m, 0)
	bust.custom_minimum_size = Vector2(220, 240)
	row.add_child(bust)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	var tr := clampi(int(m.get("training", 0)), 0, 2)
	info.add_child(Ui.label("%s · %s" % [str(m.get("arch", "")), WarUnit.TRAIN_NAMES[tr]], 14, Ui.GOLD))
	info.add_child(Ui.label("力量 %d   技巧 %d   速度 %d   体质 %d   意志 %d" % [
		int(m.get("might", 10)), int(m.get("skill", 10)), int(m.get("spd", 10)),
		int(m.get("con", 10)), int(m.get("will", 30))], 13, Ui.PARCH))
	var cond := float(m.get("cond", 1.0))
	info.add_child(Ui.label("状况 %d%%" % int(cond * 100.0), 13, Ui.hp_color(cond)))
	var sev: Array = []
	for p in m.get("severed", []):
		sev.append(WarUnit.PART_NAMES.get(str(p), "断"))
	if not sev.is_empty():
		info.add_child(Ui.label("残废：" + "、".join(sev), 13, Color("c06a55")))
	info.add_child(Ui.hline(Ui.BORDER))
	info.add_child(Ui.label("装备", 15, Ui.GOLD))
	var gd: Dictionary = m.get("gear", {})
	for slot in Gear.SLOTS:
		if not gd.has(slot):
			continue
		var g := Gear.from_dict(gd[slot])
		info.add_child(Ui.label("%s：%s" % [Gear.slot_name(slot), g.display_name()], 13, Ui.PARCH_DIM))
		var sub := ""
		if g.is_weapon():
			sub = "伤害 %.0f · 命中 %+d · 射程 %d · 重 %.1f" % [g.damage(), g.hit_bonus(), g.attack_range(), g.weight()]
		else:
			sub = "护甲 %.0f · 重 %.1f" % [g.armor(), g.weight()]
		info.add_child(Ui.label("　　" + sub, 12, Ui.PARCH_LOW))

	var to_party := Ui.button("队伍与背包（换装 / 阵形）", 14)
	to_party.custom_minimum_size = Vector2(260, 34)
	to_party.pressed.connect(func():
		_modal_close()
		_party_sel_id = str(m.get("id", ""))
		_open_party())
	box.add_child(to_party)

	var close := Ui.button("合上名册", 15)
	close.custom_minimum_size = Vector2(160, 34)
	close.pressed.connect(func(): _modal_close())
	box.add_child(close)

# —— 通用弹窗 ——

func _modal_open(title: String) -> VBoxContainer:
	_modal_close()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal = dim

	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(Color("15110d"), Ui.BORDER_HI, 1, 0, 4))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(700, 0)
	margin.add_child(box)

	if title != "":
		box.add_child(Ui.label(title, 24, Ui.PARCH))
		box.add_child(Ui.hline(Ui.GOLD, 1))
	return box

func _modal_choices(title: String, body: String, choices: Array) -> void:
	var box := _modal_open(title)
	var l := Ui.label(body, 15, Ui.PARCH_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(640, 0)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	for c in choices:
		var ch: Dictionary = c
		var b := Ui.button(str(ch.get("label", "好")), 15)
		b.custom_minimum_size = Vector2(150, 36)
		b.pressed.connect(ch.get("cb", func(): _modal_close()))
		row.add_child(b)

func _modal_close() -> void:
	if _modal != null:
		_modal.queue_free()
		_modal = null

# —— 绘制 ——

func _gen_world() -> void:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 88231
	_grass.clear()
	_trees.clear()
	_hills.clear()
	_rocks.clear()
	var w := MapData.WORLD_SIZE
	for i in range(2600):
		_grass.append(Vector2(rnd.randf() * w.x, rnd.randf() * w.y))
	for i in range(120):
		var c := Vector2(rnd.randf() * w.x, rnd.randf() * w.y)
		for j in range(rnd.randi_range(3, 8)):
			_trees.append({
				"p": c + Vector2(rnd.randf_range(-34, 34), rnd.randf_range(-26, 26)),
				"s": rnd.randf_range(5.0, 9.0),
			})
	for i in range(110):
		_hills.append({
			"p": Vector2(rnd.randf() * w.x, rnd.randf() * w.y),
			"s": rnd.randf_range(10.0, 22.0),
		})
	for i in range(90):
		_rocks.append({
			"p": Vector2(rnd.randf() * w.x, rnd.randf() * w.y),
			"s": rnd.randf_range(2.0, 5.0),
		})

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b0907"), true)
	var map_rect := Rect2(0, 58, size.x, size.y - 58)
	draw_rect(map_rect, Color("13100b"), true)
	_draw_ground()
	_draw_terrain()
	_draw_roads()
	_draw_destination()
	_draw_cities()
	_draw_roamers()
	_draw_party()
	_draw_frame()

func _draw_ground() -> void:
	# 几块大的地貌色斑，让地面不只是一块纯色
	var blobs := [
		[MapData.world_pos("lumber"), 420.0, Color(0.055, 0.075, 0.05, 0.55)],
		[MapData.world_pos("abbey"), 360.0, Color(0.09, 0.085, 0.07, 0.35)],
		[MapData.world_pos("den"), 380.0, Color(0.10, 0.055, 0.045, 0.40)],
		[MapData.world_pos("ford"), 330.0, Color(0.05, 0.07, 0.09, 0.40)],
		[MapData.world_pos("camp"), 380.0, Color(0.095, 0.075, 0.05, 0.35)],
	]
	for b in blobs:
		var c := sp(b[0])
		draw_circle(c, float(b[1]), b[2])
	# 地面暗角
	draw_rect(Rect2(0, 58, size.x, 120), Color(0, 0, 0, 0.25), true)

func _draw_terrain() -> void:
	for p in _grass:
		if not _vis(p):
			continue
		var s := sp(p)
		var ox := fmod(p.x * 13.7, 5.0) - 2.5
		draw_line(s, s + Vector2(ox, -3.0), Color(0.22, 0.20, 0.14, 0.35), 1.0)
	for h in _hills:
		if not _vis(h["p"], 40.0):
			continue
		var s := sp(h["p"])
		var k: float = h["s"]
		var col := Color(0.26, 0.22, 0.16, 0.55)
		draw_polyline(PackedVector2Array([
			s + Vector2(-k, 0), s + Vector2(0, -k * 0.8), s + Vector2(k, 0),
		]), col, 1.4, true)
		draw_line(s + Vector2(-k * 0.2, -k * 0.4), s + Vector2(-k * 0.55, 0), col, 1.0)
	for r in _rocks:
		if not _vis(r["p"], 20.0):
			continue
		draw_circle(sp(r["p"]), float(r["s"]), Color(0.20, 0.18, 0.15, 0.5))
	for t in _trees:
		if not _vis(t["p"], 30.0):
			continue
		var s := sp(t["p"])
		var k: float = t["s"]
		draw_line(s, s + Vector2(0, k), Color(0.12, 0.09, 0.06, 0.55), 1.0)
		draw_colored_polygon(PackedVector2Array([
			s + Vector2(-k * 0.75, k * 0.15), s + Vector2(0, -k * 1.3),
			s + Vector2(k * 0.75, k * 0.15),
		]), Color(0.14, 0.18, 0.12, 0.65))

func _draw_roads() -> void:
	for e in MapData.EDGES:
		var a := sp(MapData.world_pos(str(e[0])))
		var b := sp(MapData.world_pos(str(e[1])))
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * 28.0
		var pts := PackedVector2Array()
		for i in range(17):
			var t := float(i) / 16.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		draw_polyline(pts, Color(0.045, 0.038, 0.03, 0.9), 15.0, true)
		draw_polyline(pts, Color(0.24, 0.195, 0.135, 0.95), 11.0, true)
		draw_polyline(pts, Color(0.33, 0.27, 0.18, 0.45), 2.0, true)

func _draw_destination() -> void:
	if _dest.x < 0.0:
		return
	var a := sp(Game.party_pos)
	var b := sp(_dest)
	var col := Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.55)
	var steps := 16
	for i in range(steps):
		if i % 2 == 0:
			continue
		var p1 := a.lerp(b, float(i) / float(steps))
		var p2 := a.lerp(b, float(i + 1) / float(steps))
		draw_line(p1, p2, col, 1.2)
	draw_arc(b, 9.0, 0, TAU, 24, col, 1.6, true)
	draw_line(b + Vector2(-13, 0), b + Vector2(13, 0), col, 1.0)
	draw_line(b + Vector2(0, -13), b + Vector2(0, 13), col, 1.0)

func _draw_cities() -> void:
	for id in MapData.NODES.keys():
		var nid := str(id)
		var n: Dictionary = MapData.NODES[id]
		var p := MapData.world_pos(nid)
		if not _vis(p, 120.0):
			continue
		var c := sp(p)
		var t := str(n.get("type", ""))
		var col := _type_color(t)
		var r := 19.0
		draw_circle(c + Vector2(2, 3), r + 8.0, Color(0, 0, 0, 0.5))
		draw_circle(c, r + 6.0, Color(0.055, 0.045, 0.035, 0.95))
		draw_circle(c, r, Color(col.r * 0.20, col.g * 0.20, col.b * 0.20, 0.95))
		draw_arc(c, r + 1.0, 0, TAU, 32, Color(col.r, col.g, col.b, 0.85), 1.5, true)
		_draw_icon(c, t, col, r)
		if _near == nid:
			var pulse := 0.5 + 0.5 * sin(_t * 3.4)
			draw_arc(c, r + 9.0 + pulse * 4.0, 0, TAU, 40,
				Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.45 + 0.4 * pulse), 2.2, true)
			# 名字挪到上方，免得被站在城门口的队伍挡住
			Ui.text_c(self, c + Vector2(1, -r - 11), str(n.get("name", "荒野")), 14, Color(0, 0, 0, 0.7))
			Ui.text_c(self, c + Vector2(0, -r - 12), str(n.get("name", "荒野")), 14, Ui.PARCH)
			Ui.text(self, c + Vector2(r + 10, 4), "E", 14, Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.9))
		else:
			Ui.text_c(self, c + Vector2(1, r + 21), str(n.get("name", "荒野")), 14, Color(0, 0, 0, 0.7))
			Ui.text_c(self, c + Vector2(0, r + 20), str(n.get("name", "荒野")), 14, Ui.PARCH)

func _draw_roamers() -> void:
	for r in _roamers:
		var p: Vector2 = r["pos"]
		if not _vis(p, 80.0):
			continue
		var c := sp(p)
		var chase := p.distance_to(Game.party_pos) < 440.0
		draw_circle(c + Vector2(0, 22), 14.0, Color(0, 0, 0, 0.45))
		if _tex != null:
			draw_texture_rect(_tex, Rect2(c - Vector2(19, 19), Vector2(38, 38)), false,
				Color(1.0, 0.55, 0.48, 1.0))
		if chase:
			draw_arc(c, 26.0, 0, TAU, 28, Color(0.75, 0.2, 0.15, 0.75), 1.8, true)
		Ui.text_c(self, c + Vector2(0, -26), str(r["name"]), 12, Color(0.85, 0.6, 0.55))

func _draw_party() -> void:
	var c := sp(Game.party_pos)
	draw_circle(c + Vector2(0, 24), 18.0, Color(0, 0, 0, 0.5))
	var pulse := 0.5 + 0.5 * sin(_t * 2.6)
	draw_arc(c, 27.0 + pulse * 2.0, 0, TAU, 32,
		Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.3 + 0.25 * pulse), 1.6, true)
	if _tex != null:
		draw_texture_rect(_tex, Rect2(c - Vector2(23, 23), Vector2(46, 46)), false, Color(1, 1, 1, 1))
	if _near == "":
		Ui.text_c(self, c + Vector2(0, -30), "你的队伍", 12, Ui.PARCH)
	else:
		Ui.text(self, c + Vector2(28, 4), "队伍", 11, Color(Ui.PARCH_DIM.r, Ui.PARCH_DIM.g, Ui.PARCH_DIM.b, 0.85))
	# 暂停标记
	if _paused:
		Ui.text_c(self, c + Vector2(0, 40), "暂停", 12, Ui.GOLD)

func _draw_frame() -> void:
	# 天数的进度条，贴在顶栏下面
	var ratio := clampf(_day_accum / DAY_DIST, 0.0, 1.0)
	draw_rect(Rect2(0, 58, size.x, 2), Color(0, 0, 0, 0.5), true)
	draw_rect(Rect2(0, 58, size.x * ratio, 2), Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.45), true)
	# 四边压暗
	for i in range(10):
		var a := 0.05 + float(i) * 0.012
		draw_rect(Rect2(0, 58.0 + float(i) * 7.0, size.x, 2), Color(0, 0, 0, a), true)
		draw_rect(Rect2(0, size.y - float(i) * 7.0 - 2, size.x, 2), Color(0, 0, 0, a), true)

func _type_color(t: String) -> Color:
	match t:
		"camp": return Color("b8913f")
		"town": return Color("a08a63")
		"capital": return Color("c9a860")
		"village": return Color("8d7a5c")
		"lumber": return Color("7f8a5e")
		"ford": return Color("6f8f9e")
		"abbey": return Color("9aa6b2")
		"outpost": return Color("8a7a5a")
		"den": return Color("a4402f")
		_: return Color("8d7a5c")

func _draw_icon(c: Vector2, t: String, col: Color, r: float) -> void:
	var ic := Color(minf(1.0, col.r * 1.35 + 0.1), minf(1.0, col.g * 1.35 + 0.1),
		minf(1.0, col.b * 1.35 + 0.1))
	var k := r / 17.0
	match t:
		"camp":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -11) * k, c + Vector2(-12, 8) * k, c + Vector2(12, 8) * k,
			]), ic)
			draw_line(c + Vector2(0, -11) * k, c + Vector2(0, -15) * k, ic, 1.5 * k)
		"village", "town":
			var houses := 2 if t == "village" else 3
			for i in range(houses):
				var ox := (float(i) - float(houses - 1) * 0.5) * 9.0 * k
				draw_rect(Rect2(c + Vector2(ox - 3.2, -1) * k, Vector2(6.4 * k, 7.0 * k)), ic, true)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(ox - 4.6, -1) * k, c + Vector2(ox, -6.5) * k,
					c + Vector2(ox + 4.6, -1) * k,
				]), ic)
		"capital":
			draw_rect(Rect2(c + Vector2(-7, -4) * k, Vector2(14, 13) * k), ic, true)
			for i in range(3):
				draw_rect(Rect2(c + Vector2(-7 + float(i) * 5.0, -7) * k, Vector2(2.6, 3.4) * k), ic, true)
			draw_line(c + Vector2(0, -7) * k, c + Vector2(0, -15) * k, ic, 1.6 * k)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -15) * k, c + Vector2(9, -12) * k, c + Vector2(0, -9) * k,
			]), Color(0.6, 0.16, 0.12))
		"abbey":
			draw_rect(Rect2(c + Vector2(-2, -12) * k, Vector2(4, 22) * k), ic, true)
			draw_rect(Rect2(c + Vector2(-8, -6) * k, Vector2(16, 4) * k), ic, true)
			draw_arc(c + Vector2(0, 10) * k, 5.0 * k, PI, TAU, 12, ic, 2.0 * k, true)
		"ford":
			draw_line(c + Vector2(-11, 1) * k, c + Vector2(11, 1) * k, ic, 2.4 * k)
			for i in range(3):
				draw_arc(c + Vector2(-7 + float(i) * 7.0, 4) * k, 3.4 * k, 0, PI, 10, ic, 1.4 * k, true)
			draw_line(c + Vector2(-9, 6) * k, c + Vector2(9, 6) * k, Color(0.35, 0.5, 0.58), 1.0 * k)
		"lumber":
			draw_line(c + Vector2(-8, 9) * k, c + Vector2(2, -9) * k, ic, 2.4 * k)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -9) * k, c + Vector2(11, -11) * k, c + Vector2(9, -2) * k,
				c + Vector2(0, -4) * k,
			]), ic)
		"outpost":
			draw_line(c + Vector2(-6, 10) * k, c + Vector2(-6, -11) * k, ic, 1.8 * k)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-6, -11) * k, c + Vector2(7, -8) * k, c + Vector2(-6, -4) * k,
			]), Color(0.55, 0.14, 0.11))
		"den":
			draw_circle(c + Vector2(0, -3) * k, 7.6 * k, ic)
			draw_rect(Rect2(c + Vector2(-4, 2) * k, Vector2(8, 6) * k), ic, true)
			draw_circle(c + Vector2(-3, -3) * k, 2.2 * k, Color(0.05, 0.03, 0.03))
			draw_circle(c + Vector2(3, -3) * k, 2.2 * k, Color(0.05, 0.03, 0.03))
			draw_line(c + Vector2(-2, 5) * k, c + Vector2(-2, 8) * k, Color(0.05, 0.03, 0.03), 1.4 * k)
			draw_line(c + Vector2(2, 5) * k, c + Vector2(2, 8) * k, Color(0.05, 0.03, 0.03), 1.4 * k)
