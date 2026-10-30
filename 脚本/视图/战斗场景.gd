extends Control

## 战斗场景：左边是六边形战场，右边是出手顺序 / 十部位 / 战报。
## 玩家点击格子移动、点敌人选部位；敌人回合由 AI 走，动画结束后自动轮转。

const PART_ORDER := ["head", "torso", "arm_l", "arm_r", "hand_l", "hand_r",
	"leg_l", "leg_r", "foot_l", "foot_r"]
const PART_HINT := {"head": "头", "torso": "躯干", "arm_l": "左臂", "arm_r": "右臂",
	"hand_l": "左手", "hand_r": "右手", "leg_l": "左腿", "leg_r": "右腿",
	"foot_l": "左脚", "foot_r": "右脚"}

var b: Battle = null
var board: BattleBoard = null
var hud: Hud = null
var acting: WarUnit = null
var target: WarUnit = null
var busy := false
var moved := false
var finished := false

var _bottom: Panel
var _hint: Label
var _action_row: HBoxContainer
var _part_row: HBoxContainer
var _part_buttons := {}
var _btn_def: Button
var _btn_rest: Button
var _btn_skip: Button
var _btn_end: Button

# —— 右侧面板（自绘） ——

class Hud extends Control:
	var battle: Battle
	var acting: WarUnit
	var target: WarUnit

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if battle == null:
			return
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color("0d0a08"), true)
		draw_line(Vector2(0, 0), Vector2(0, h), Ui.BORDER, 1.0)
		var x := 14.0
		var y := 26.0
		Ui.text(self, Vector2(x, y), "第 %d 回合" % battle.round_no, 19, Ui.GOLD)
		var np := 0
		var ne := 0
		for u in battle.units:
			if u.is_active():
				if u.faction == 0:
					np += 1
				else:
					ne += 1
		Ui.text(self, Vector2(w - 128, y), "我 %d · 敌 %d" % [np, ne], 13, Ui.PARCH_DIM)
		draw_line(Vector2(x, y + 10), Vector2(w - 14, y + 10), Ui.BORDER, 1.0)

		# —— 出手顺序 ——
		y += 32
		Ui.text(self, Vector2(x, y), "出 手 顺 序", 13, Ui.PARCH_LOW)
		var q: Array = []
		for u in battle.units:
			if u.is_active():
				q.append(u)
		q.sort_custom(func(a, c): return a.initiative() > c.initiative())
		var shown: int = mini(q.size(), 9)
		for i in range(shown):
			var u: WarUnit = q[i]
			var ry := y + 14.0 + float(i) * 21.0
			if u == battle.current:
				draw_rect(Rect2(x - 4, ry - 13, w - 20, 20), Color(0.5, 0.4, 0.2, 0.10), true)
				draw_rect(Rect2(x - 4, ry - 13, 2, 20), Ui.GOLD, true)
			draw_rect(Rect2(x + 2, ry - 10, 3, 12), Ui.BLUE if u.faction == 0 else Ui.ENEMY, true)
			var nm := u.unit_name
			if nm.length() > 7:
				nm = nm.substr(0, 7)
			Ui.text(self, Vector2(x + 12, ry), nm, 13,
				Ui.PARCH if u.faction == 0 else Color("c89a8e"))
			var vr := u.vitals_ratio()
			Ui.bar(self, Rect2(w - 90, ry - 9, 52, 7), vr, Ui.hp_color(vr))
			Ui.text(self, Vector2(w - 32, ry), "%d" % int(vr * 100), 11, Ui.PARCH_LOW)
		y += 14.0 + float(shown) * 21.0 + 8.0
		if q.size() > shown:
			Ui.text(self, Vector2(x + 12, y), "…还有 %d 人" % (q.size() - shown), 11, Ui.PARCH_LOW)
			y += 14.0
		draw_line(Vector2(x, y), Vector2(w - 14, y), Ui.BORDER, 1.0)

		# —— 当前单位 ——
		var u2: WarUnit = battle.current
		y += 24
		if u2 == null:
			return
		Ui.text(self, Vector2(x, y), u2.unit_name, 19, Ui.PARCH)
		Ui.text(self, Vector2(w - 58, y), "敌人" if u2.faction == 1 else "你", 12,
			Ui.ENEMY if u2.faction == 1 else Ui.BLUE)
		y += 18
		var wname := "空手"
		if u2.weapon() != null:
			wname = "%s（%s）" % [u2.weapon().display_name(), u2.weapon().damage_type_name()]
		var arch := u2.epithet if u2.epithet != "" else "无名"
		Ui.text(self, Vector2(x, y), "%s · %s · %s" % [arch, u2.training_name(), wname], 12, Ui.PARCH_LOW)
		y += 16

		# —— 十部位（两列五行，带各自的护甲值）——
		var py := y + 4
		for i in range(PART_ORDER.size()):
			var p: String = PART_ORDER[i]
			var cx := x + float(i % 2) * 172.0
			var ry := py + float(i / 2) * 22.0
			var sev := u2.is_severed(p)
			Ui.text(self, Vector2(cx, ry), PART_HINT[p], 12,
				Color("c06a55") if sev else Ui.PARCH_DIM)
			if sev:
				Ui.text(self, Vector2(cx + 34, ry), "断", 12, Color("c06a55"))
			else:
				var rr := u2.part_ratio(p)
				Ui.bar(self, Rect2(cx + 34, ry - 9, 82, 8), rr, Ui.hp_color(rr))
				Ui.text(self, Vector2(cx + 120, ry), "%d" % int(u2.part_hp(p)), 11, Ui.PARCH_LOW)
				Ui.text(self, Vector2(cx + 146, ry), "甲%d" % int(u2.armor_of(p)), 10,
					Color(0.55, 0.60, 0.66))
		y = py + 5.0 * 22.0 + 10.0

		# —— 资源 ——
		y = _bar_row("整体", u2.vitals_ratio(), "%d/%d" % [int(u2.vitals), int(u2.vitals_max)],
			x, y, Ui.hp_color(u2.vitals_ratio()))
		y = _bar_row("体力", u2.stamina_ratio(), "%d%%" % int(u2.stamina_ratio() * 100.0),
			x, y, Color("b8a24e"))
		y = _bar_row("士气", u2.morale_ratio(), "%d" % int(u2.morale),
			x, y, Color("6f8fb0"))
		y = _bar_row("意志", u2.will_ratio(), "%d" % int(u2.will),
			x, y, Color("9a7fb0"))
		y += 4

		var inj: String = u2.injury_penalty_text()
		if inj != "":
			draw_multiline_string(Ui.font, Vector2(x, y), inj, HORIZONTAL_ALIGNMENT_LEFT,
				w - 28, 12, 2, Color("c06a55"))
			y += 18

		if not u2.statuses.is_empty():
			Ui.text(self, Vector2(x, y), "状态：" + u2.status_names(), 12, u2.status_color())
			y += 18

		if target != null and u2.faction == 0:
			Ui.text(self, Vector2(x, y), "瞄准：%s（躯干命中 %d%%）" % [target.unit_name,
				battle.hit_chance(u2, target, "torso")], 12, Ui.GOLD)
			y += 18

		draw_line(Vector2(x, y), Vector2(w - 14, y), Ui.BORDER, 1.0)
		y += 18
		Ui.text(self, Vector2(x, y), "战 报", 12, Ui.PARCH_LOW)
		y += 10
		var avail := h - y - 12.0
		var max_lines := int(avail / 16.0)
		if max_lines < 2:
			return
		var start: int = maxi(0, battle.log_lines.size() - max_lines)
		var tail: Array = battle.log_lines.slice(start)
		draw_multiline_string(Ui.font, Vector2(x, y + 4), "\n".join(tail),
			HORIZONTAL_ALIGNMENT_LEFT, w - 26, 11, max_lines, Color(0.62, 0.58, 0.5, 0.92))

	func _bar_row(label: String, ratio: float, text: String, x: float, y: float, col: Color) -> float:
		Ui.text(self, Vector2(x, y), label, 12, Ui.PARCH_DIM)
		Ui.bar(self, Rect2(x + 36, y - 9, 180, 8), ratio, col)
		Ui.text(self, Vector2(x + 224, y), text, 11, Ui.PARCH_LOW)
		return y + 20.0

# —— 初始化 ——

func setup(_arg: Dictionary = {}) -> void:
	if Game.battle_context.is_empty():
		Game.battle_context = {"kind": "bandit", "title": "遭遇", "scale": 1.0}
	b = Game.build_battle()
	board = BattleBoard.new()
	add_child(board)
	board.hex_clicked.connect(_on_hex)
	board.attach(b)

	_build_ui()
	_layout()
	resized.connect(_layout)
	_refresh()
	_begin_turn()
	if "--autoplay" in OS.get_cmdline_user_args():
		_autoplay()

# —— 开发用自动对战：把玩家回合也交给简单脚本，验证整条链路 ——

func _nearest_enemy(u: WarUnit) -> WarUnit:
	var best: WarUnit = null
	var bd := 999
	for o in b.units:
		if o.faction == u.faction or not o.is_active():
			continue
		var d := Hex.distance(u.pos, o.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _autoplay() -> void:
	_dlog("AUTOPLAY_START")
	await get_tree().create_timer(0.4).timeout
	_dlog("AUTOPLAY_TICK inside=%s winner=%d" % [str(is_inside_tree()), b.winner])
	var guard := 0
	while is_inside_tree() and b.winner < 0 and guard < 240:
		guard += 1
		await get_tree().create_timer(0.25).timeout
		if not is_inside_tree() or b.winner >= 0 or finished:
			_dlog("loop break g=%d inside=%s winner=%d finished=%s" % [guard, str(is_inside_tree()), b.winner, str(finished)])
			break
		if busy or acting == null or acting.faction != 0:
			continue
		var foe := _nearest_enemy(acting)
		_dlog("player turn g=%d unit=%s foe=%s busy=%s" % [guard, acting.unit_name, str(foe), str(busy)])
		if foe == null:
			_end_turn()
			await get_tree().create_timer(0.7).timeout
			continue
		if not b.can_reach_target(acting, foe):
			var best := acting.pos
			var bd := Hex.distance(acting.pos, foe.pos)
			var reach: Dictionary = b.reachable(acting)
			for h in reach.keys():
				var d := Hex.distance(h, foe.pos)
				if d < bd:
					bd = d
					best = h
			if best != acting.pos:
				_on_hex(best)
		if b.can_reach_target(acting, foe):
			_on_hex(foe.pos)
			_attack("torso")
			await get_tree().create_timer(1.1).timeout
		else:
			_end_turn()
			await get_tree().create_timer(0.8).timeout
	await get_tree().create_timer(1.2).timeout
	_dlog("AUTOPLAY_END winner=%d rounds=%d log=%d" % [b.winner, b.round_no, b.log_lines.size()])
	var n: int = mini(10, b.log_lines.size())
	for i in range(n):
		_dlog("  · %s" % b.log_lines[b.log_lines.size() - n + i])
	get_tree().quit()

func _dlog(s: String) -> void:
	var f := FileAccess.open("user://autoplay.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://autoplay.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(s)
	f.close()

func _build_ui() -> void:
	hud = Hud.new()
	hud.battle = b
	add_child(hud)

	_bottom = Panel.new()
	_bottom.add_theme_stylebox_override("panel", Ui.box(Color("0b0908"), Ui.BORDER, 1, 0, 3))
	add_child(_bottom)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_bottom.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vb)

	_hint = Ui.label("", 14, Ui.PARCH)
	vb.add_child(_hint)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	vb.add_child(_action_row)
	_btn_def = Ui.button("防 御", 16)
	_btn_def.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_def.custom_minimum_size = Vector2(0, 36)
	_btn_def.pressed.connect(_do_defend)
	_action_row.add_child(_btn_def)
	_btn_rest = Ui.button("恢复体力", 16)
	_btn_rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_rest.custom_minimum_size = Vector2(0, 36)
	_btn_rest.pressed.connect(_do_rest)
	_action_row.add_child(_btn_rest)
	_btn_skip = Ui.button("跳 过", 16)
	_btn_skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_skip.custom_minimum_size = Vector2(0, 36)
	_btn_skip.pressed.connect(_do_skip)
	_action_row.add_child(_btn_skip)
	_btn_end = Ui.button("结束回合", 16)
	_btn_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_end.custom_minimum_size = Vector2(0, 36)
	_btn_end.pressed.connect(_end_turn)
	_action_row.add_child(_btn_end)

	_part_row = HBoxContainer.new()
	_part_row.add_theme_constant_override("separation", 6)
	_part_row.visible = false
	vb.add_child(_part_row)
	for p in PART_ORDER:
		var btn := Ui.button("", 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 34)
		var key: String = p
		btn.pressed.connect(func(): _attack(key))
		_part_row.add_child(btn)
		_part_buttons[p] = btn
	var cancel := Ui.button("取消", 12)
	cancel.custom_minimum_size = Vector2(58, 34)
	cancel.pressed.connect(func():
		target = null
		board.target_hex = Vector2i(9999, 9999)
		_refresh())
	_part_row.add_child(cancel)

func _layout() -> void:
	var w := size.x
	var h := size.y
	var hud_w := 372.0
	board.position = Vector2(12, 12)
	board.size = Vector2(maxf(400.0, w - hud_w - 24.0), maxf(300.0, h - 170.0))
	board.relayout()
	hud.position = Vector2(w - hud_w, 12)
	hud.size = Vector2(hud_w - 12.0, h - 24.0)
	_bottom.position = Vector2(12, h - 146)
	_bottom.size = Vector2(maxf(400.0, w - hud_w - 24.0), 134)

# —— 回合流程 ——

func _begin_turn() -> void:
	if finished:
		return
	target = null
	moved = false
	busy = false
	acting = b.current
	if board != null:
		board.target_hex = Vector2i(9999, 9999)
		board.selected = null
	_refresh()
	if acting == null or b.winner >= 0:
		return
	if acting.faction == 1:
		busy = true
		_refresh()
		_run_ai()
	else:
		_update_highlights()

func _update_highlights() -> void:
	if board == null or acting == null or acting.faction != 0 or b.winner >= 0:
		if board != null:
			board.set_highlights({}, {})
		return
	var move := {}
	if not moved:
		var reach: Dictionary = b.reachable(acting)
		for h in reach.keys():
			if h != acting.pos:
				move[h] = true
	var atk := {}
	for u in b.units:
		if u.faction != 0 and u.is_active() and b.can_reach_target(acting, u):
			atk[u.pos] = true
	board.selected = acting
	board.set_highlights(move, atk)
	board.queue_redraw()

func _on_hex(h: Vector2i) -> void:
	if busy or finished or b.winner >= 0:
		return
	if acting == null or acting.faction != 0:
		return
	var u := b.unit_at(h)
	if u != null and u.faction == 1:
		if b.can_reach_target(acting, u):
			target = u
			board.target_hex = h
			board.selected = acting
			_update_part_row()
			_refresh()
		else:
			board.add_flash(h, "太远", Ui.PARCH_LOW)
		return
	if u != null and u == acting:
		target = null
		board.target_hex = Vector2i(9999, 9999)
		_refresh()
		return
	if u != null:
		return
	if moved:
		board.add_flash(h, "已经移动过", Ui.PARCH_LOW)
		return
	var reach: Dictionary = b.reachable(acting)
	if reach.has(h):
		if b.try_move(acting, h):
			moved = true
			target = null
			board.target_hex = Vector2i(9999, 9999)
			_update_highlights()
			_refresh()

func _attack(part: String) -> void:
	if busy or finished or target == null or acting == null:
		return
	if acting.faction != 0:
		return
	busy = true
	var res: Dictionary = b.attack(acting, target, part)
	if bool(res.get("hit", false)):
		board.add_flash(target.pos, "-%d" % int(res.get("damage", 0.0)), Ui.BLOOD_HI)
	else:
		board.add_flash(target.pos, "落空", Ui.PARCH_LOW)
	target = null
	board.target_hex = Vector2i(9999, 9999)
	_refresh()
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree():
		return
	if b.winner >= 0:
		_show_result()
		return
	_after_action()

func _do_defend() -> void:
	if busy or finished or acting == null or acting.faction != 0:
		return
	b.do_defend(acting)
	board.add_flash(acting.pos, "架势", Color("9ab0c8"))
	_after_action()

func _do_rest() -> void:
	if busy or finished or acting == null or acting.faction != 0:
		return
	b.do_rest(acting)
	board.add_flash(acting.pos, "喘息", Color("b8a24e"))
	_after_action()

func _do_skip() -> void:
	if busy or finished or acting == null or acting.faction != 0:
		return
	b.do_skip(acting)
	_after_action()

func _end_turn() -> void:
	if busy or finished or acting == null or acting.faction != 0:
		return
	_after_action()

func _after_action() -> void:
	busy = true
	_refresh()
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		return
	_advance_turn()

func _advance_turn() -> void:
	b.end_unit_turn()
	_refresh()
	if b.winner >= 0:
		_show_result()
		return
	_begin_turn()

func _run_ai() -> void:
	var guard := 0
	while is_inside_tree() and b.winner < 0 and b.current != null and b.current.faction == 1:
		guard += 1
		if guard > 240:
			break
		await get_tree().create_timer(0.42).timeout
		if not is_inside_tree() or b.winner >= 0:
			break
		var u: WarUnit = b.current
		if u == null or not u.is_active():
			b.end_unit_turn()
			continue
		b.ai_act(u)
		_refresh()
		if board != null:
			board.queue_redraw()
		if b.winner >= 0:
			break
		await get_tree().create_timer(0.22).timeout
		if not is_inside_tree():
			return
		b.end_unit_turn()
		_refresh()
	if not is_inside_tree():
		return
	if b.winner >= 0:
		_show_result()
	else:
		_begin_turn()

# —— 界面刷新 ——

func _refresh() -> void:
	if hud != null:
		hud.battle = b
		hud.acting = acting
		hud.target = target
		hud.queue_redraw()
	if board != null:
		board.queue_redraw()
	_update_buttons()
	_update_part_row()
	_update_hint()

func _update_buttons() -> void:
	var can := (not busy) and (not finished) and acting != null and acting.faction == 0 and b.winner < 0
	if _btn_def != null:
		_btn_def.disabled = not can
		_btn_rest.disabled = not can
		_btn_skip.disabled = not can
		_btn_end.disabled = not can

func _update_part_row() -> void:
	if _part_row == null:
		return
	var show := target != null and acting != null and acting.faction == 0 and not busy and not finished
	_part_row.visible = show
	_action_row.visible = not show
	if not show:
		return
	for p in PART_ORDER:
		var chance := b.hit_chance(acting, target, p)
		var btn: Button = _part_buttons[p]
		btn.text = "%s %d%%" % [PART_HINT[p], chance]
		btn.disabled = false

func _update_hint() -> void:
	if _hint == null:
		return
	if finished:
		_hint.text = "战斗结束。"
		return
	if acting == null:
		_hint.text = ""
		return
	if acting.faction == 1:
		_hint.text = "敌人行动中…（%s）" % acting.unit_name
		return
	if target != null:
		_hint.text = "瞄准 %s —— 选择部位出手，或取消。" % target.unit_name
	elif moved:
		_hint.text = "已经移动。可以攻击身边的敌人，或结束回合。"
	else:
		_hint.text = "你的回合（%s）：点击格子移动，点击敌人选择部位。" % acting.unit_name

# —— 结算 ——

func _show_result() -> void:
	if finished:
		return
	finished = true
	busy = true
	if board != null:
		board.set_highlights({}, {})
	var res: Dictionary = Game.resolve_battle(b, b.winner)
	var win := b.winner == 0
	var title := "你们赢了" if win else "你们败了"
	var lines: Array = []
	if win:
		lines.append("最后一名敌人倒下。战场安静下来，只剩苍蝇的声音。")
		lines.append("缴获 %d 金币、%d 份口粮。" % [int(res.get("gold", 0)), int(res.get("food", 0))])
	else:
		lines.append("你们的人已经跑光了。能走的都走了。")
	var dead: Array = res.get("dead", [])
	if not dead.is_empty():
		lines.append("死了：%s" % "、".join(dead))
	if int(res.get("wounded", 0)) > 0:
		lines.append("重伤 %d 人。" % int(res.get("wounded", 0)))

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.78)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(Color("15110d"), Ui.BORDER_HI, 1, 0, 4))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(560, 0)
	margin.add_child(vb)
	vb.add_child(Ui.label(title, 26, Ui.GOLD if win else Color("c06a55")))
	vb.add_child(Ui.hline(Ui.BORDER))
	var body := Ui.label("\n".join(lines), 15, Ui.PARCH_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(540, 0)
	vb.add_child(body)
	var btn := Ui.button("回到大地图", 16)
	btn.custom_minimum_size = Vector2(200, 40)
	btn.pressed.connect(func():
		Game.scene_requested.emit("map", {"result": res}))
	vb.add_child(btn)
