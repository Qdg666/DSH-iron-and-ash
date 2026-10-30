extends RefCounted
class_name MapData

## 大地图：一张骑砍式的道路图。节点是城镇与据点，边是路，走一次要几天。

const NODES := {
	"camp": {
		"name": "灰沼营地",
		"type": "camp",
		"pos": [235, 700],
		"desc": "一片烂泥地里支起的帐篷。烟熏黑了半片天，被雨浇熄又点起来。\n你们管这里叫家。",
		"actions": ["rest", "tavern"],
	},
	"village": {
		"name": "焦土村",
		"type": "village",
		"pos": [465, 565],
		"desc": "去年烧过一次，现在只剩半边村子。还活着的人在灰烬里翻来翻去，\n像在找去年埋下的什么东西。",
		"actions": ["rest", "event:ashes"],
	},
	"town": {
		"name": "铁砧镇",
		"type": "town",
		"pos": [745, 645],
		"desc": "铁匠铺的锤声日夜不停。镇公所墙上钉着一张新的悬赏，\n墨迹还没干，画的像是你。",
		"actions": ["rest", "market", "tavern", "event:bounty"],
	},
	"lumber": {
		"name": "林间伐木场",
		"type": "lumber",
		"pos": [520, 375],
		"desc": "伐木工的棚屋。树被砍倒后拖进河里，顺水漂到镇上去。\n林子深处有东西在看着他们。",
		"actions": ["rest", "event:forest"],
	},
	"ford": {
		"name": "黑水渡口",
		"type": "ford",
		"pos": [895, 425],
		"desc": "一条木栈桥卡在两块石头之间。桥头坐着收过路费的老头，\n他眼睛是白的，却从不数错钱。",
		"actions": ["rest", "market", "event:ferry"],
	},
	"abbey": {
		"name": "圣安德烈修道院",
		"type": "abbey",
		"pos": [1115, 245],
		"desc": "钟声一天响七次。院墙上刻着「仁慈」，墙下有新翻的土。\n修士们的沉默比钟声更响。",
		"actions": ["rest", "heal", "event:sermon"],
	},
	"outpost": {
		"name": "边境哨所",
		"type": "outpost",
		"pos": [1165, 625],
		"desc": "十几个烂醉的兵，一根褪色的旗杆。哨长在墙上刻日子，\n刻到一半就忘了自己刻到第几天。",
		"actions": ["rest", "tavern", "battle:bandit", "event:levy"],
	},
	"capital": {
		"name": "旧王庭",
		"type": "capital",
		"pos": [1360, 435],
		"desc": "天命所在。城墙有三十年没修过，因为没人相信它还会被攻打。\n使者从这里出发，去分封那些迟早会反的家族。",
		"actions": ["rest", "market", "event:mandate"],
	},
	"den": {
		"name": "匪巢",
		"type": "den",
		"pos": [875, 795],
		"desc": "死人挂在树上，风一吹就转。他们不是在等你投降，\n只是在清点你身上能拿走的东西。",
		"actions": ["battle:bandit", "leave"],
	},
}

const EDGES := [
	["camp", "village", 2],
	["camp", "town", 3],
	["village", "town", 2],
	["village", "lumber", 2],
	["town", "lumber", 2],
	["lumber", "ford", 3],
	["town", "ford", 2],
	["town", "outpost", 3],
	["town", "den", 2],
	["ford", "abbey", 2],
	["ford", "outpost", 2],
	["outpost", "den", 2],
	["outpost", "capital", 2],
	["abbey", "capital", 3],
]

static func node(id: String) -> Dictionary:
	return NODES.get(id, {})

static func node_pos(id: String) -> Vector2:
	var n: Dictionary = NODES.get(id, {})
	var p: Array = n.get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))

static func node_name(id: String) -> String:
	return str(NODES.get(id, {}).get("name", "荒野"))

## 返回 [目标id, 天数] 的列表
static func routes_from(id: String) -> Array:
	var out := []
	for e in EDGES:
		if e[0] == id:
			out.append([e[1], int(e[2])])
		elif e[1] == id:
			out.append([e[0], int(e[2])])
	return out

static func travel_days(a: String, b: String) -> int:
	for e in EDGES:
		if (e[0] == a and e[1] == b) or (e[1] == a and e[0] == b):
			return int(e[2])
	return -1

static func all_ids() -> Array:
	return NODES.keys()

# —— 自由行军用的世界坐标 ——
# 节点表里的坐标是按 1600×900 画的，放大成一张 2400×1500 的可行走地图。

const WORLD_SCALE := 1.6
const WORLD_SIZE := Vector2(2400, 1500)

static func world_pos(id: String) -> Vector2:
	return node_pos(id) * WORLD_SCALE

## 地图边缘留出一点荒野，免得队伍贴着世界边界走
static func clamp_world(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 24.0, WORLD_SIZE.x - 24.0), clampf(p.y, 24.0, WORLD_SIZE.y - 24.0))

## 离某个世界坐标最近的据点（返回 id；超过 max_dist 返回空串）
static func nearest_node(p: Vector2, max_dist: float = 90.0) -> String:
	var best := ""
	var bd := max_dist
	for id in NODES.keys():
		var d := world_pos(str(id)).distance_to(p)
		if d < bd:
			bd = d
			best = str(id)
	return best

## 最近的道路距离（用于"走大路有加成、走野地会吃亏"）
static func distance_to_road(p: Vector2) -> float:
	var best := 1e9
	for e in EDGES:
		var a := world_pos(str(e[0]))
		var b := world_pos(str(e[1]))
		best = minf(best, _dist_to_segment(p, a, b))
	return best

static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
