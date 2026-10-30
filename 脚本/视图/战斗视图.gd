extends Control
class_name BattleBoard

## 六边形战场：只负责画和收输入，规则全在 Battle 里。

signal hex_clicked(h: Vector2i)

var battle: Battle = null
var hover := Vector2i(9999, 9999)
var selected: WarUnit = null
var move_set := {}
var attack_set := {}
var target_hex := Vector2i(9999, 9999)
var target_part := ""

var S := 42.0
var ox := 0.0
var oy := 0.0
var _t := 0.0
var _flash: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func attach(b: Battle) -> void:
	battle = b
	relayout()
	queue_redraw()

func relayout() -> void:
	if battle == null or battle.tiles.is_empty():
		return
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for h in battle.tiles.keys():
		var p := Hex.to_pixel(h, 1.0)
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.y)
	var span := mx - mn
	var avail := size
	if avail.x < 10.0:
		avail = Vector2(1220, 760)
	var base := 1.0
	var try_s := minf(
		(avail.x * 0.94) / maxf(1.0, (span.x + 1.8) * 1.0),
		(avail.y * 0.88) / maxf(1.0, (span.y + 2.2) * 1.0))
	S = clampf(try_s, 26.0, 52.0)
	var px_span := span * S
	ox = (avail.x - px_span.x) * 0.5 - mn.x * S
	oy = (avail.y - px_span.y) * 0.5 - mn.y * S + S * 0.15

func to_screen(h: Vector2i) -> Vector2:
	return Hex.to_pixel(h, S) + Vector2(ox, oy)

func hex_at(pos: Vector2) -> Vector2i:
	return Hex.from_pixel(pos - Vector2(ox, oy), S)

func set_highlights(move: Dictionary, atk: Dictionary) -> void:
	move_set = move
	attack_set = atk
	queue_redraw()

func add_flash(pos: Vector2i, text: String, color: Color) -> void:
	_flash.append({"h": pos, "text": text, "color": color, "life": 1.0})

func _process(delta: float) -> void:
	_t += delta
	if battle != null:
		queue_redraw()
	var keep: Array = []
	for f in _flash:
		f.life -= delta * 0.85
		if f.life > 0.0:
			keep.append(f)
	_flash = keep

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := hex_at(event.position)
		if h != hover:
			hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			hex_clicked.emit(hex_at(event.position))

# —— 绘制 ——

func _draw() -> void:
	if battle == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	# 背景
	draw_rect(r, Color("0b0908"), true)
	# 远处的地平线雾气
	for i in range(14):
		var y := r.size.y * (0.15 + 0.06 * float(i))
		draw_rect(Rect2(0, y, r.size.x, 3), Color(0.09, 0.08, 0.07, 0.35 - float(i) * 0.02), true)

	for h in battle.tiles.keys():
		_draw_tile(h)

	for h in battle.tiles.keys():
		_draw_overlay(h)

	# 单位（按行排序，让下面的人挡住上面的）
	var sorted := battle.units.duplicate()
	sorted.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for u in sorted:
		_draw_unit(u)

	_draw_flash()
	_draw_tooltip()

func _draw_tile(h: Vector2i) -> void:
	var c := to_screen(h)
	var pts := Hex.corners(c, S * 0.97)
	var ter := battle.terrain_at(h)
	var col: Color = ter.color
	draw_colored_polygon(pts, col)
	# 边框
	var edge: Color = ter.edge
	draw_polyline(_closed(pts), edge, 1.0, true)
	# 地面碎屑
	var seed_v := float(absi(h.x * 73856093 ^ h.y * 19349663) % 1000) / 1000.0
	var rnd := RandomNumberGenerator.new()
	rnd.seed = int(absi(h.x * 73856093 + h.y * 19349663))
	for i in range(3):
		var p := c + Vector2(rnd.randf_range(-0.5, 0.5), rnd.randf_range(-0.5, 0.5)) * S
		draw_circle(p, 1.2 + seed_v, Color(col.r + 0.04, col.g + 0.04, col.b + 0.03, 0.5))
	if ter.get("block", false):
		# 断壁：画几块石头
		for i in range(3):
			var off := Vector2(rnd.randf_range(-0.45, 0.45), rnd.randf_range(-0.4, 0.3)) * S
			var sz := S * rnd.randf_range(0.14, 0.26)
			draw_rect(Rect2(c + off - Vector2(sz, sz) * 0.5, Vector2(sz, sz * 0.8)),
				Color(0.22, 0.2, 0.17), true)
	elif ter.name == "浅水":
		draw_line(c + Vector2(-S * 0.4, -S * 0.1), c + Vector2(S * 0.35, -S * 0.28),
			Color(0.3, 0.4, 0.45, 0.35), 1.5)

func _draw_overlay(h: Vector2i) -> void:
	var c := to_screen(h)
	if attack_set.has(h):
		draw_colored_polygon(Hex.corners(c, S * 0.94), Color(0.55, 0.1, 0.08, 0.26))
	if move_set.has(h):
		draw_colored_polygon(Hex.corners(c, S * 0.94), Color(0.35, 0.5, 0.62, 0.18))
		draw_polyline(_closed(Hex.corners(c, S * 0.94)), Color(0.45, 0.62, 0.72, 0.5), 1.0, true)
	if h == target_hex:
		draw_polyline(_closed(Hex.corners(c, S * 0.92)), Ui.BLOOD_HI, 2.5, true)
	if h == hover:
		draw_polyline(_closed(Hex.corners(c, S * 0.95)), Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.85), 1.6, true)

func _draw_unit(u: WarUnit) -> void:
	var c := to_screen(u.pos)
	var faction_col := Ui.BLUE if u.faction == 0 else Ui.ENEMY
	if not u.is_active():
		# 尸体
		draw_colored_polygon(Hex.corners(c, S * 0.7), Color(0.12, 0.08, 0.07, 0.55))
		var rr := RandomNumberGenerator.new()
		rr.seed = u.uid * 7919
		draw_line(c + Vector2(-S * 0.3, -S * 0.1), c + Vector2(S * 0.32, S * 0.16),
			Color(0.28, 0.09, 0.08), 3.0 + rr.randf() * 2.0)
		draw_line(c + Vector2(-S * 0.2, S * 0.2), c + Vector2(S * 0.1, -S * 0.25),
			Color(0.24, 0.16, 0.1), 2.5)
		Ui.text_c(self, c + Vector2(0, S * 0.55), "尸", 12, Color(0.55, 0.5, 0.42))
		return

	# 站位底盘
	draw_colored_polygon(Hex.corners(c, S * 0.86), Color(faction_col.r, faction_col.g,
		faction_col.b, 0.22))
	# 当前行动者：金色脉冲
	if battle.current == u:
		var pulse := 0.55 + 0.45 * sin(_t * 4.0)
		draw_polyline(_closed(Hex.corners(c, S * 0.9)),
			Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, pulse), 2.5, true)
	elif u.defending:
		draw_arc(c, S * 0.72, -2.6, -0.5, 14, Color(0.6, 0.68, 0.8, 0.75), 3.0)

	if selected == u:
		draw_polyline(_closed(Hex.corners(c, S * 0.93)), Color(0.95, 0.85, 0.55), 2.0, true)

	# 立绘
	Doll.draw_bust(self, c + Vector2(0, -S * 0.10), S * 1.02, u, 1.0, u.faction == 1)

	# 溃逃标记
	if u.routing:
		Ui.text_c(self, c + Vector2(0, -S * 0.95), "溃", 15, Ui.BLOOD_HI)

	# 整体血量条
	var bw := S * 1.25
	var bx := c.x - bw * 0.5
	var by := c.y + S * 0.52
	draw_rect(Rect2(bx - 1, by - 1, bw + 2, S * 0.15 + 2), Color(0, 0, 0, 0.75), true)
	var vr := u.vitals_ratio()
	draw_rect(Rect2(bx, by, bw * vr, S * 0.15), Ui.hp_color(vr), true)
	# 体力细条
	draw_rect(Rect2(bx, by + S * 0.17, bw * u.stamina_ratio(), S * 0.06),
		Color(0.72, 0.66, 0.4), true)

	# 名字：只标出当前行动者与鼠标下的单位，免得一堆名字糊在一起
	var hovered := battle.unit_at(hover)
	if u == battle.current or u == hovered or u == selected:
		var nm := u.unit_name
		if nm.length() > 6:
			nm = nm.substr(0, 6)
		draw_rect(Rect2(c.x - 34, c.y + S * 0.72, 68, 16), Color(0, 0, 0, 0.45), true)
		Ui.text_c(self, c + Vector2(0, S * 0.86), nm, 11,
			Color(0.9, 0.86, 0.75) if u.faction == 0 else Color(0.92, 0.74, 0.68))
	# 残废标记
	if u.severed_parts.size() > 0:
		Ui.text_c(self, c + Vector2(S * 0.55, -S * 0.62), "断", 11, Color(0.9, 0.45, 0.38))
	# 大出血标记
	if u.has_status("bleed_heavy") and not u.dead:
		Ui.text_c(self, c + Vector2(-S * 0.55, -S * 0.62), "血", 12, Color(0.92, 0.3, 0.24))

func _draw_flash() -> void:
	for f in _flash:
		var p := to_screen(f.h) + Vector2(0, -S * (1.0 + (1.0 - f.life) * 0.9))
		var col: Color = f.color
		col.a = clampf(f.life, 0.0, 1.0)
		Ui.text_c(self, p, f.text, 18, col)

func _draw_tooltip() -> void:
	if battle == null or not battle.tiles.has(hover):
		return
	var ter := battle.terrain_at(hover)
	var u := battle.unit_at(hover)
	var lines: Array = ["%s  移动%.1f  掩护+%d" % [ter.name, ter.cost, int(ter.cover)]]
	if u != null:
		lines.append("%s · %s" % [u.unit_name, u.short_status()])
		lines.append("整体 %d/%d   体力 %d%%" % [int(u.vitals), int(u.vitals_max), int(u.stamina_ratio() * 100.0)])
		var ns := u.armor_need("torso", "slash")
		var np := u.armor_need("torso", "pierce")
		var nb := u.armor_need("torso", "blunt")
		lines.append("躯干甲 %.0f   破甲线 斩%s / 刺%s / 钝%s" % [
			u.armor_of("torso"),
			"%.0f" % ns if ns > 0.0 else "—",
			"%.0f" % np if np > 0.0 else "—",
			"%.0f" % nb if nb > 0.0 else "—"])
		if not u.statuses.is_empty():
			lines.append("状态：" + u.status_names())
	var w := 0.0
	for l in lines:
		w = maxf(w, Ui.text_width(str(l), 13))
	var box := Rect2(hover_pos() + Vector2(16, 14), Vector2(w + 18, 12.0 * lines.size() + 14.0))
	var r := Rect2(Vector2.ZERO, size)
	if box.position.x + box.size.x > r.size.x - 4:
		box.position.x = hover_pos().x - box.size.x - 14
	if box.position.y + box.size.y > r.size.y - 4:
		box.position.y = hover_pos().y - box.size.y - 10
	Ui.frame(self, box, Color(0.06, 0.05, 0.045, 0.94), Ui.BORDER, 5.0)
	for i in range(lines.size()):
		Ui.text(self, box.position + Vector2(9, 16 + 12 * i), str(lines[i]), 13,
			Ui.PARCH if i == 0 else Ui.PARCH_DIM)

var _mouse := Vector2.ZERO

func hover_pos() -> Vector2:
	return _mouse

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_visible_in_tree():
		_mouse = get_local_mouse_position()

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
