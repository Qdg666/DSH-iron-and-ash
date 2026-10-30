extends RefCounted
class_name Ui

## 全局视觉与主题。所有界面共用一套血、铁、羊皮纸的调色板。
## 背景随数值提高饱和度 —— 参见：数值越好，颜色越鲜艳。

# —— 调色板 ——
const BG         := Color("0e0c0a")
const BG_ALT     := Color("15110e")
const PANEL      := Color("1a1512")
const PANEL_HI   := Color("241d17")
const BORDER     := Color("463525")
const BORDER_HI  := Color("8a6b38")
const PARCH      := Color("cdbf9f")
const PARCH_DIM  := Color("8b8272")
const PARCH_LOW  := Color("5e574a")
const IRON       := Color("6f6f6c")
const BLOOD      := Color("8d2023")
const BLOOD_HI   := Color("c4392f")
const GOLD       := Color("b8913f")
const STEEL      := Color("96a0aa")
const GREEN      := Color("6b8f52")
const BLUE       := Color("3f6f9e")
const ENEMY      := Color("a4402f")
const SKIN       := Color("b08b6a")

static var font: Font
static var theme: Theme

static func setup(root: Window) -> void:
	_build_font()
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16

	t.set_color("font_color", "Label", PARCH)
	t.set_stylebox("panel", "Panel", box(PANEL, BORDER, 1, 10))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 1, 10))
	t.set_stylebox("panel", "PopupPanel", box(PANEL, BORDER_HI, 1, 8))

	t.set_color("font_color", "Button", PARCH)
	t.set_color("font_hover_color", "Button", Color("f0e2bd"))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", PARCH_LOW)
	t.set_stylebox("normal", "Button", box(Color("211a15"), Color("453526"), 1, 8))
	t.set_stylebox("hover", "Button", box(Color("2e2419"), BORDER_HI, 1, 8))
	t.set_stylebox("pressed", "Button", box(Color("120e0b"), BORDER_HI, 1, 8))
	t.set_stylebox("disabled", "Button", box(Color("171310"), Color("2c2419"), 1, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), BORDER_HI, 1, 8))

	t.set_color("font_color", "RichTextLabel", PARCH)
	t.set_color("default_color", "RichTextLabel", PARCH)
	t.set_constant("line_separation", "RichTextLabel", 5)

	root.theme = t
	theme = t

static func _build_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "Microsoft YaHei UI",
		"SimHei", "Noto Sans CJK SC", "Source Han Sans SC",
		"PingFang SC", "sans-serif",
	])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font = f

# —— 构建工具 ——

static func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 1,
		margin: float = 8.0, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if bw > 0 and border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb

static func label(text: String, size: int = 16, color: Color = PARCH) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func panel(bg: Color = PANEL, border: Color = BORDER) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 1, 10))
	return p

static func hline(color: Color = BORDER, h: int = 1) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_rect(r, col, true)

## 画一个角上有装饰刻痕的框，用于自制面板。
static func frame(c: CanvasItem, r: Rect2, fill: Color, border: Color, tick: float = 7.0) -> void:
	c.draw_rect(r, fill, true)
	c.draw_rect(r, border, false, 1.0)
	# 四角刻痕
	var o := 3.0
	c.draw_line(r.position + Vector2(o, o + tick), r.position + Vector2(o, o), border, 2.0)
	c.draw_line(r.position + Vector2(o, o), r.position + Vector2(o + tick, o), border, 2.0)
	c.draw_line(r.position + Vector2(r.size.x - o - tick, o), r.position + Vector2(r.size.x - o, o), border, 2.0)
	c.draw_line(r.position + Vector2(r.size.x - o, o), r.position + Vector2(r.size.x - o, o + tick), border, 2.0)
	c.draw_line(r.position + Vector2(o, r.size.y - o - tick), r.position + Vector2(o, r.size.y - o), border, 2.0)
	c.draw_line(r.position + Vector2(o, r.size.y - o), r.position + Vector2(o + tick, r.size.y - o), border, 2.0)
	c.draw_line(r.position + Vector2(r.size.x - o - tick, r.size.y - o), r.position + Vector2(r.size.x - o, r.size.y - o), border, 2.0)
	c.draw_line(r.position + Vector2(r.size.x - o, r.size.y - o - tick), r.position + Vector2(r.size.x - o, r.size.y - o), border, 2.0)

## 通用进度条
static func bar(c: CanvasItem, r: Rect2, ratio: float, color: Color, back: Color = Color("221a14")) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	c.draw_rect(r, back, true)
	if ratio > 0.0:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), color, true)
	c.draw_rect(r, Color(border_of(back), 0.9), false, 1.0)

static func border_of(c: Color) -> Color:
	return Color(c.r * 1.9 + 0.06, c.g * 1.9 + 0.06, c.b * 1.9 + 0.06, 1.0)

## 血量比例 -> 颜色（从铁灰的病态到饱和的血红）
static func hp_color(ratio: float) -> Color:
	if ratio > 0.66:
		return Color("7d9a5e")
	elif ratio > 0.33:
		return Color("b5913a")
	else:
		return Color("a8322a")

static func text(c: CanvasItem, pos: Vector2, s: String, size: int = 16,
		color: Color = PARCH, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0) -> void:
	var f: Font = font if font != null else ThemeDB.fallback_font
	c.draw_string(f, pos, s, align, width, size, color)

static func text_c(c: CanvasItem, center: Vector2, s: String, size: int = 16,
		color: Color = PARCH) -> void:
	var f: Font = font if font != null else ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(f, center - Vector2(w * 0.5, -size * 0.35), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func text_width(s: String, size: int = 16) -> float:
	var f: Font = font if font != null else ThemeDB.fallback_font
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
