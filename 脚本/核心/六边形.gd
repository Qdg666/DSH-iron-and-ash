extends RefCounted
class_name Hex

## 尖顶（pointy-top）六边形，使用轴坐标 (q, r)。
## 像素坐标：x = size * √3 * (q + r/2)，y = size * 1.5 * r

const SIZE := 46.0
const DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func to_pixel(h: Vector2i, size: float = SIZE) -> Vector2:
	return Vector2(size * sqrt(3.0) * (float(h.x) + float(h.y) * 0.5), size * 1.5 * float(h.y))

static func from_pixel(p: Vector2, size: float = SIZE) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return _cube_round(q, -q - r, r)

## 立方坐标取整 -> 轴坐标
static func _cube_round(cx: float, cy: float, cz: float) -> Vector2i:
	var rx := roundi(cx)
	var ry := roundi(cy)
	var rz := roundi(cz)
	var dx := absf(float(rx) - cx)
	var dy := absf(float(ry) - cy)
	var dz := absf(float(rz) - cz)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)

static func corners(center: Vector2, size: float = SIZE) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * float(i) + 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * size)
	return pts

static func corners_scaled(center: Vector2, size: float, k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * float(i) + 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * size * k)
	return pts

static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

static func neighbors(h: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		out.append(h + d)
	return out

static func within(h: Vector2i, radius: int) -> Array:
	var out := []
	for r in range(-radius, radius + 1):
		var q_min := maxi(-radius, -r - radius)
		var q_max := mini(radius, -r + radius)
		for q in range(q_min, q_max + 1):
			out.append(h + Vector2i(q, r))
	return out

## 矩形形状的地图（轴坐标），切掉四个尖角，让它看起来不像一张表格。
static func rect_map(cols: int, rows: int) -> Array:
	var out := []
	for r in range(rows):
		var off := int(floor(float(r) / 2.0))
		for c in range(cols):
			var corner_bad := (r == 0 or r == rows - 1) and (c == 0 or c == cols - 1)
			if corner_bad:
				continue
			out.append(Vector2i(c - off, r))
	return out

static func line(a: Vector2i, b: Vector2i) -> Array:
	var n := distance(a, b)
	if n == 0:
		return [a]
	var out := []
	var ax := float(a.x)
	var az := float(a.y)
	var ay := -ax - az
	var bx := float(b.x)
	var bz := float(b.y)
	var by := -bx - bz
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(_cube_round(
			lerpf(ax, bx, t) + 1e-6,
			lerpf(ay, by, t) + 2e-6,
			lerpf(az, bz, t) - 3e-6))
	return out
