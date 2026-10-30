extends Control

## 主菜单：一幅会呼吸的夜景，加上三个按钮。
## 所有画面都是程序化绘制的 —— 没有贴图，只有墨、烟和铁锈。

var _t := 0.0
var _btn_new: Button
var _btn_cont: Button
var _btn_quit: Button
var _hint: Label
var _glow: ImageTexture

func setup(_arg: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_btn_new = Ui.button("新 的 开 始", 21)
	_btn_new.pressed.connect(_on_new)
	add_child(_btn_new)

	_btn_cont = Ui.button("继 续 旅 程", 21)
	_btn_cont.pressed.connect(_on_continue)
	_btn_cont.disabled = not Game.has_save()
	add_child(_btn_cont)

	_btn_quit = Ui.button("离 开", 21)
	_btn_quit.pressed.connect(func(): get_tree().quit())
	add_child(_btn_quit)

	_hint = Ui.label("", 14, Ui.PARCH_LOW)
	add_child(_hint)
	if Game.has_save():
		_hint.text = "旧档还在。路上的人不一定还在。"
	else:
		_hint.text = "没有旧档。上一次，你也是这么开始的。"

	resized.connect(_layout)
	_layout()
	_glow = _make_glow()
	set_process(true)

# —— 柔光贴图：径向渐变，用来做月亮光晕与地面火光，避免一圈圈的硬边 ——

func _make_glow() -> ImageTexture:
	var n := 160
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n) * 0.5
	for y in range(n):
		for x in range(n):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.4)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _layout() -> void:
	var w := size.x
	var h := size.y
	var x := maxf(84.0, w * 0.085)
	var y := h * 0.585
	var arr := [_btn_new, _btn_cont, _btn_quit]
	for i in range(arr.size()):
		var b: Button = arr[i]
		b.position = Vector2(x, y + float(i) * 58.0)
		b.size = Vector2(276, 46)
	_hint.position = Vector2(x + 2, y + 3.0 * 58.0 + 10.0)
	_hint.size = Vector2(420, 24)

func _on_new() -> void:
	Game.new_game()
	Game.scene_requested.emit("map", {})

func _on_continue() -> void:
	if Game.load_game():
		Game.scene_requested.emit("map", {})

# —— 绘制 ——

func _draw() -> void:
	var w := size.x
	var h := size.y
	_sky(w, h)
	_moon(w, h)
	_clouds(w, h)
	_ridge(w, h, h * 0.60, 62.0, Color("171108"), 0.0)
	_ridge(w, h, h * 0.675, 38.0, Color("100c08"), 1.7)
	_ground(w, h)
	_warband(w, h)
	_crows(w, h)
	_fog(w, h)
	_title(w, h)

func _sky(w: float, h: float) -> void:
	var top := Color("0a0807")
	var horizon := Color("2a1a10")
	var bands := 44
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var c := top.lerp(horizon, pow(t, 1.8))
		draw_rect(Rect2(0, h * 0.76 * t, w, h * 0.76 / float(bands) + 1.5), c, true)
	# 极远处一点将熄的火光
	draw_circle(Vector2(w * 0.83, h * 0.635), 130.0, Color(0.30, 0.12, 0.05, 0.10))
	draw_circle(Vector2(w * 0.83, h * 0.635), 62.0, Color(0.42, 0.18, 0.07, 0.10))

func _moon(w: float, h: float) -> void:
	var c := Vector2(w * 0.735, h * 0.235)
	var r := 76.0
	if _glow != null:
		var gr := r * 4.4
		draw_texture_rect(_glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false,
			Color(0.80, 0.72, 0.55, 0.34))
	draw_circle(c, r, Color(0.72, 0.66, 0.52))
	draw_circle(c + Vector2(-18, -14), r * 0.92, Color(0.78, 0.72, 0.58))
	# 月海
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 911
	for i in range(14):
		var a := rnd.randf() * TAU
		var d := rnd.randf() * r * 0.78
		draw_circle(c + Vector2(cos(a), sin(a)) * d, rnd.randf_range(3.0, 11.0),
			Color(0.60, 0.55, 0.44, 0.28))

func _clouds(w: float, h: float) -> void:
	for i in range(5):
		var y := h * (0.14 + float(i) * 0.055)
		var off := fmod(_t * (5.0 + float(i) * 2.0), w + 520.0) - 260.0
		var pts := PackedVector2Array([
			Vector2(off - 200, y), Vector2(off + 120, y - 9),
			Vector2(off + 420, y + 4), Vector2(off + 300, y + 15),
			Vector2(off - 60, y + 13),
		])
		draw_colored_polygon(pts, Color(0.03, 0.025, 0.02, 0.35 + float(i) * 0.05))

func _ridge(w: float, h: float, base: float, amp: float, col: Color, phase: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, h))
	var steps := 34
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := t * w
		var y := base - amp * (0.5 + 0.5 * sin(t * 8.0 + phase)) - amp * 0.25 * sin(t * 27.0 + phase * 2.0)
		pts.append(Vector2(x, y))
	pts.append(Vector2(w, h))
	draw_colored_polygon(pts, col)
	# 山脊上稀疏的枯树
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 100 + int(phase * 10.0)
	for i in range(12):
		var x := w * (0.05 + 0.9 * float(i) / 11.0 + rnd.randf_range(-0.02, 0.02))
		var t2 := x / maxf(1.0, w)
		var y := base - amp * (0.5 + 0.5 * sin(t2 * 8.0 + phase)) - amp * 0.25 * sin(t2 * 27.0 + phase * 2.0)
		if rnd.randf() < 0.45:
			continue
		var th := rnd.randf_range(14.0, 34.0)
		draw_line(Vector2(x, y + 4), Vector2(x + rnd.randf_range(-3, 3), y - th),
			Color(0.02, 0.018, 0.014, 0.9), 1.6)
		draw_line(Vector2(x, y - th * 0.6), Vector2(x - 7, y - th * 1.05),
			Color(0.02, 0.018, 0.014, 0.8), 1.1)
		draw_line(Vector2(x, y - th * 0.75), Vector2(x + 8, y - th * 1.15),
			Color(0.02, 0.018, 0.014, 0.8), 1.1)

func _ground(w: float, h: float) -> void:
	draw_rect(Rect2(0, h * 0.755, w, h * 0.245), Color("0b0907"), true)
	draw_rect(Rect2(0, h * 0.765, w, 2), Color(0.16, 0.12, 0.08, 0.55), true)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 4242
	for i in range(160):
		var x := rnd.randf() * w
		var y := h * (0.77 + rnd.randf() * 0.23)
		draw_rect(Rect2(x, y, rnd.randf_range(2, 16), 1), Color(0.14, 0.11, 0.08, 0.25))
	# 远处将熄的火堆 —— 队伍在那里
	if _glow != null:
		var fc := Vector2(w * 0.815, h * 0.756)
		var fr := 130.0
		draw_texture_rect(_glow, Rect2(fc - Vector2(fr, fr), Vector2(fr, fr) * 2.0), false,
			Color(0.95, 0.42, 0.14, 0.30))
		draw_circle(fc, 3.5, Color(0.95, 0.62, 0.24, 0.95))
		draw_circle(fc + Vector2(-14, 1), 2.0, Color(0.85, 0.40, 0.12, 0.8))

func _warband(w: float, h: float) -> void:
	# 一排站在地平线上的剪影：长枪、旗、驼背的人
	var y := h * 0.756
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 20251026
	var n := 9
	for i in range(n):
		var t := float(i) / float(n - 1)
		var x := w * (0.505 + t * 0.40)
		y = h * 0.756 - 6.0 + sin(t * 5.0) * 4.0
		var k := 0.85 + rnd.randf() * 0.35
		var col := Color(0.018, 0.015, 0.012, 0.96)
		# 身体
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 9 * k, y), Vector2(x - 6 * k, y - 26 * k),
			Vector2(x + 6 * k, y - 26 * k), Vector2(x + 9 * k, y),
		]), col)
		# 头
		draw_circle(Vector2(x, y - 32 * k), 6.0 * k, col)
		# 长枪
		if i % 3 != 2:
			var hx := x + 8.0 * k
			draw_line(Vector2(hx, y + 4), Vector2(hx + 2, y - 62 * k), Color(0.018, 0.015, 0.012, 0.96), 1.8)
			draw_line(Vector2(hx + 2, y - 62 * k), Vector2(hx - 2, y - 53 * k), col, 1.6)
		# 偶尔一面旗
		if i == 3 or i == 7:
			var bx := x + 13.0 * k
			draw_line(Vector2(bx, y + 4), Vector2(bx, y - 74 * k), col, 2.2)
			draw_colored_polygon(PackedVector2Array([
				Vector2(bx, y - 74 * k), Vector2(bx + 22 * k, y - 68 * k),
				Vector2(bx + 18 * k, y - 52 * k), Vector2(bx, y - 46 * k),
			]), Color(0.20, 0.05, 0.04, 0.92))
	# 一个跛行落在后面的人
	var lx := w * 0.462
	var ly := h * 0.756
	draw_colored_polygon(PackedVector2Array([
		Vector2(lx - 6, ly), Vector2(lx - 5, ly - 20),
		Vector2(lx + 5, ly - 20), Vector2(lx + 7, ly),
	]), Color(0.018, 0.015, 0.012, 0.9))
	draw_circle(Vector2(lx, ly - 25), 5.0, Color(0.018, 0.015, 0.012, 0.9))
	draw_line(Vector2(lx + 1, ly - 16), Vector2(lx + 15, ly - 2), Color(0.02, 0.017, 0.013, 0.9), 2.0)

func _crows(w: float, h: float) -> void:
	for i in range(6):
		var t := fmod(_t * 0.06 + float(i) * 0.17, 1.0)
		var x := -80.0 + t * (w + 160.0)
		var y := h * (0.18 + float(i) * 0.033) + sin(_t * 0.8 + float(i)) * 12.0
		var s := 5.0 + float(i % 3)
		draw_line(Vector2(x - s, y), Vector2(x, y - s * 0.55), Color(0.02, 0.02, 0.02, 0.75), 1.4)
		draw_line(Vector2(x, y - s * 0.55), Vector2(x + s, y), Color(0.02, 0.02, 0.02, 0.75), 1.4)

func _fog(w: float, h: float) -> void:
	for i in range(4):
		var y := h * (0.70 + float(i) * 0.045)
		var off := fmod(_t * (7.0 + float(i) * 3.0) + float(i) * 180.0, w + 700.0) - 350.0
		var pts := PackedVector2Array([
			Vector2(off - 300, y), Vector2(off + 260, y - 12),
			Vector2(off + 620, y + 6), Vector2(off + 340, y + 26),
			Vector2(off - 150, y + 22),
		])
		draw_colored_polygon(pts, Color(0.55, 0.52, 0.46, 0.030 + float(i) * 0.008))

func _title(w: float, h: float) -> void:
	var x := maxf(84.0, w * 0.085)
	var y := h * 0.315
	Ui.text(self, Vector2(x + 4, y + 5), "铁 与 灰", 78, Color(0, 0, 0, 0.65))
	Ui.text(self, Vector2(x + 2, y + 2), "铁 与 灰", 78, Color(0.06, 0.04, 0.03, 0.9))
	Ui.text(self, Vector2(x, y), "铁 与 灰", 78, Ui.PARCH)
	# 金色细线
	draw_rect(Rect2(x + 2, y + 20, 300, 2), Ui.GOLD, true)
	draw_rect(Rect2(x + 2, y + 24, 180, 1), Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.4), true)
	Ui.text(self, Vector2(x + 4, y + 56), "I R O N   &   A S H", 13, Ui.GOLD)
	Ui.text(self, Vector2(x + 4, y + 84), "十部位血肉 · 断肢 · 分类型护甲 · 天命", 16, Ui.PARCH_DIM)
	var body := "刀剑有罪，饥荒是罚，忍耐是德。\n—— 圣安德烈修道院，第七次钟声"
	draw_multiline_string(Ui.font, Vector2(x + 4, y + 138), body,
		HORIZONTAL_ALIGNMENT_LEFT, 520, 15, 3, Ui.PARCH_LOW)
	# 底部署名
	Ui.text(self, Vector2(x + 4, h - 28), "Godot 4.7 · 程序化生成 · 没有一张贴图", 12,
		Color(Ui.PARCH_LOW.r, Ui.PARCH_LOW.g, Ui.PARCH_LOW.b, 0.55))
