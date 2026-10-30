extends RefCounted
class_name Doll

## 纸娃娃：角色只露出上半身，由装备拼成。
## 颜色直接取自装备的材质 —— 材质越好，饱和度越高，看着越"活"。

static func slot_color(u: WarUnit, slot: String, fallback: Color) -> Color:
	var g = u.gear.get(slot, null)
	if g == null:
		return fallback
	return g.color()

static func draw_bust(c: CanvasItem, center: Vector2, h: float, u: WarUnit,
		alpha: float = 1.0, flip: bool = false) -> void:
	var k := h / 100.0
	var skin := Color("9c7d61")
	var body := Color("2a231c")
	var x := 1.0
	if flip:
		x = -1.0

	var torso_col := slot_color(u, "torso", Color("3b3227"))
	var arm_col := slot_color(u, "arms", torso_col.darkened(0.15))
	var head_col := slot_color(u, "head", skin)

	# —— 影子/背光 ——
	c.draw_colored_polygon(_poly(center, k, [
		Vector2(-24, 8), Vector2(24, 8), Vector2(30, 50), Vector2(-30, 50),
	]), Color(0, 0, 0, 0.28 * alpha))

	# —— 手臂（先画，藏在躯干后面）——
	var arm_l_ok := not u.is_severed("arm_l")
	var arm_r_ok := not u.is_severed("arm_r")
	if arm_l_ok:
		c.draw_colored_polygon(_poly(center, k, [
			Vector2(-26, -2), Vector2(-16, -4), Vector2(-15, 40), Vector2(-25, 42),
		]), Color(arm_col.r, arm_col.g, arm_col.b, alpha))
	if arm_r_ok:
		c.draw_colored_polygon(_poly(center, k, [
			Vector2(16, -4), Vector2(26, -2), Vector2(25, 42), Vector2(15, 40),
		]), Color(arm_col.r, arm_col.g, arm_col.b, alpha))

	# —— 断口 ——
	if not arm_l_ok:
		c.draw_circle(center + Vector2(-20, 6) * k, 5.0 * k, Color(0.42, 0.08, 0.08, alpha))
		c.draw_line(center + Vector2(-24, -2) * k, center + Vector2(-16, 12) * k,
			Color(0.75, 0.25, 0.2, alpha), maxf(1.0, 1.6 * k))
	if not arm_r_ok:
		c.draw_circle(center + Vector2(20, 6) * k, 5.0 * k, Color(0.42, 0.08, 0.08, alpha))
		c.draw_line(center + Vector2(16, -2) * k, center + Vector2(24, 12) * k,
			Color(0.75, 0.25, 0.2, alpha), maxf(1.0, 1.6 * k))

	# —— 躯干 ——
	c.draw_colored_polygon(_poly(center, k, [
		Vector2(-19, -8), Vector2(19, -8), Vector2(24, 48), Vector2(-24, 48),
	]), Color(torso_col.r, torso_col.g, torso_col.b, alpha))
	# 甲片分割线
	c.draw_line(center + Vector2(-19, 4) * k, center + Vector2(19, 4) * k,
		Color(0, 0, 0, 0.32 * alpha), maxf(1.0, 1.0 * k))
	c.draw_line(center + Vector2(-20, 22) * k, center + Vector2(20, 22) * k,
		Color(0, 0, 0, 0.28 * alpha), maxf(1.0, 1.0 * k))
	# 腰带
	c.draw_rect(Rect2(center + Vector2(-23, 40) * k, Vector2(46, 5) * k),
		Color(0.22, 0.15, 0.09, alpha))

	# —— 脖子 ——
	c.draw_rect(Rect2(center + Vector2(-6, -18) * k, Vector2(12, 12) * k),
		Color(skin.r * 0.8, skin.g * 0.8, skin.b * 0.8, alpha))

	# —— 头 ——
	var head_c := center + Vector2(0, -30) * k
	c.draw_circle(head_c, 13.0 * k, Color(skin.r, skin.g, skin.b, alpha))
	# 头盔（有头盔就盖住上半张脸）
	if u.gear.has("head"):
		var hc := Color(head_col.r, head_col.g, head_col.b, alpha)
		c.draw_colored_polygon(_poly(head_c, k, [
			Vector2(-13, 0), Vector2(-13, -4), Vector2(-9, -12), Vector2(0, -14),
			Vector2(9, -12), Vector2(13, -4), Vector2(13, 0), Vector2(0, 2),
		]), hc)
		# 护鼻
		c.draw_rect(Rect2(head_c + Vector2(-1.5, -2) * k, Vector2(3, 10) * k),
			hc.darkened(0.35))
		# 眼缝
		c.draw_rect(Rect2(head_c + Vector2(-8, 1) * k, Vector2(16, 2.4) * k),
			Color(0.03, 0.02, 0.02, alpha))
	else:
		c.draw_circle(head_c + Vector2(-4.5, 0) * k, 1.6 * k, Color(0.1, 0.08, 0.06, alpha))
		c.draw_circle(head_c + Vector2(4.5, 0) * k, 1.6 * k, Color(0.1, 0.08, 0.06, alpha))

	# —— 伤：头部/躯干受损就糊一片血 ——
	var head_r := u.part_ratio("head")
	if head_r < 0.6:
		c.draw_circle(head_c + Vector2(6, 6) * k, (2.0 + (0.6 - head_r) * 9.0) * k,
			Color(0.5, 0.06, 0.05, alpha * 0.55))
	var torso_r := u.part_ratio("torso")
	if torso_r < 0.7:
		c.draw_colored_polygon(_poly(center, k, [
			Vector2(-14, 6), Vector2(6, 10), Vector2(10, 34), Vector2(-8, 30),
		]), Color(0.45, 0.05, 0.04, alpha * (0.7 - torso_r) * 0.9))

	# —— 武器 ——
	_draw_weapon(c, center, k, u, alpha, x)

static func _draw_weapon(c: CanvasItem, center: Vector2, k: float, u: WarUnit,
		alpha: float, x: float) -> void:
	var w = u.weapon()
	var col := Color(0.55, 0.57, 0.6, alpha)
	if w != null:
		col = w.color()
		col.a = alpha
	var hand := center + Vector2(26 * x, 26) * k
	var pid: String = "" if w == null else w.pattern_id
	match pid:
		"w_spear":
			c.draw_line(hand + Vector2(0, 26) * k, hand + Vector2(0, -52) * k, col, maxf(1.5, 2.2 * k))
			c.draw_colored_polygon(PackedVector2Array([
				hand + Vector2(0, -52) * k, hand + Vector2(-6, -42) * k,
				hand + Vector2(6, -42) * k,
			]), col)
		"w_bow":
			var pts := PackedVector2Array()
			for i in range(9):
				var t := float(i) / 8.0
				var ang := lerpf(-1.0, 1.0, t) * 1.15
				pts.append(hand + Vector2(cos(ang) * 16.0 * x, sin(ang) * 26.0) * k)
			for i in range(pts.size() - 1):
				c.draw_line(pts[i], pts[i + 1], col, maxf(1.5, 2.0 * k))
		"w_crossbow", "w_greatsword":
			c.draw_line(hand + Vector2(-6, 18) * k, hand + Vector2(6, -34) * k, col, maxf(2.0, 3.2 * k))
			c.draw_line(hand + Vector2(-12, 4) * k, hand + Vector2(10, -2) * k, col.darkened(0.2), maxf(2.0, 2.4 * k))
		"w_axe":
			c.draw_line(hand + Vector2(-4, 20) * k, hand + Vector2(-2, -22) * k, Color(0.32, 0.24, 0.16, alpha), maxf(2.0, 2.6 * k))
			c.draw_colored_polygon(PackedVector2Array([
				hand + Vector2(-2, -22) * k, hand + Vector2(14, -26) * k,
				hand + Vector2(12, -4) * k, hand + Vector2(-2, -2) * k,
			]), col)
		"w_club", "w_scythe":
			c.draw_line(hand + Vector2(-2, 20) * k, hand + Vector2(2, -20) * k, Color(0.30, 0.22, 0.14, alpha), maxf(2.0, 2.4 * k))
		_:
			c.draw_line(hand + Vector2(-2, 16) * k, hand + Vector2(2, -30) * k, col, maxf(1.5, 2.2 * k))
			c.draw_line(hand + Vector2(-8, 6) * k, hand + Vector2(8, 4) * k, col.darkened(0.25), maxf(1.5, 2.0 * k))

static func _poly(center: Vector2, k: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(center + Vector2(p.x, p.y) * k)
	return out
