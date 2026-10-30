extends RefCounted
class_name Status

## 状态系统：战斗中挂在单位身上的临时异常。
## 每个状态有持续回合、可叠层数、每回合掉血比例，以及一组属性修正。
## 属性键：acc 命中 / eva 闪避 / init 主动 / dmg 伤害倍率 / move 移动 / def 防御

const DEFS := {
	"bleed_heavy": {
		"name": "大出血",
		"short": "血",
		"desc": "断肢处的血止不住：每回合流失生命，命中、闪避、主动、伤害全面下降。",
		"dur": 6,
		"stack_max": 3,
		"vital_pct": 0.045,
		"mods": {"acc": -13.0, "eva": -8.0, "init": -7.0, "dmg": -0.16, "move": -0.7, "def": -5.0},
		"color": Color("c0392b"),
	},
	"shock": {
		"name": "断肢剧痛",
		"short": "痛",
		"desc": "刚失去肢体，眼前发白，短时间内所有动作都变形。",
		"dur": 3,
		"stack_max": 2,
		"vital_pct": 0.0,
		"mods": {"acc": -9.0, "eva": -5.0, "init": -5.0, "dmg": -0.10},
		"color": Color("c06a55"),
	},
	"winded": {
		"name": "力竭",
		"short": "竭",
		"desc": "喘不上气，手脚发软。",
		"dur": 2,
		"stack_max": 2,
		"vital_pct": 0.0,
		"mods": {"acc": -7.0, "eva": -5.0, "init": -4.0, "dmg": -0.08, "move": -0.5},
		"color": Color("b8a24e"),
	},
}

static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func make(id: String, stacks: int = 1) -> Dictionary:
	var d := def(id)
	return {
		"id": id,
		"stacks": maxi(1, mini(int(d.get("stack_max", 1)), stacks)),
		"turns": int(d.get("dur", 1)),
	}
