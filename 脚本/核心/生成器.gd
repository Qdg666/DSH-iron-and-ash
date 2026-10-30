extends RefCounted
class_name Gen

## 人物与队伍的随机生成。名字、兵种、装备都是程序化的。

const FIRST_NAMES := [
	"奥托", "格里高", "汉斯", "洛尔", "巴托", "塞维尔", "库尔特", "雅各布",
	"雷纳德", "厄本", "狄特", "马库斯", "奥兰", "维特", "约斯特", "戈弗雷",
	"埃克", "西蒙", "鲁道夫", "提奥", "梅尔", "约根", "阿尔文", "康拉德",
]
const SURNAMES := [
	"铁匠之子", "无姓者", "黑水人", "瘸子", "独眼", "灰袍", "石匠",
	"牧羊人", "流浪者", "绞索下活下来的", "烧炭人", "挖坟的", "面包师",
]
const EPITHETS := ["", "", "", "老", "瞎", "哑", "秃", "红脸"]

const ARCH := {
	"农奴": {
		"training": 0, "might": 10, "skill": 7, "spd": 10, "con": 10,
		"will": 26.0, "tier": 0, "weapon": "w_scythe",
		"desc": "被人从田里拖出来，手里塞了把镰刀。",
	},
	"民兵": {
		"training": 0, "might": 11, "skill": 9, "spd": 10, "con": 11,
		"will": 30.0, "tier": 0, "weapon": "w_spear",
		"desc": "领主征召的农户，操练过三个下午。",
	},
	"逃兵": {
		"training": 1, "might": 11, "skill": 12, "spd": 11, "con": 11,
		"will": 36.0, "tier": 1, "weapon": "w_spear",
		"desc": "从某场败仗里跑出来的，活到今天全靠跑得快。",
	},
	"雇佣兵": {
		"training": 1, "might": 12, "skill": 14, "spd": 11, "con": 12,
		"will": 42.0, "tier": 2, "weapon": "w_sword",
		"desc": "为钱卖命的人。钱给够，命就是你的。",
	},
	"弓箭手": {
		"training": 1, "might": 10, "skill": 15, "spd": 12, "con": 10,
		"will": 38.0, "tier": 1, "weapon": "w_bow",
		"desc": "林子里的猎人，杀人比杀鹿更顺手。",
	},
	"弩手": {
		"training": 1, "might": 11, "skill": 14, "spd": 10, "con": 11,
		"will": 40.0, "tier": 2, "weapon": "w_crossbow",
		"desc": "教会曾禁止弩，因为它是农夫杀骑士的器具。",
	},
	"劫掠者": {
		"training": 0, "might": 13, "skill": 10, "spd": 12, "con": 11,
		"will": 24.0, "tier": 1, "weapon": "w_axe",
		"desc": "在废墟里翻找食物的人，抢和杀是一回事。",
	},
	"重装步兵": {
		"training": 2, "might": 13, "skill": 14, "spd": 9, "con": 14,
		"will": 54.0, "tier": 3, "weapon": "w_spear",
		"desc": "领主养着的职业军人。他们不跑，因为跑不掉。",
	},
	"教团骑士": {
		"training": 2, "might": 14, "skill": 16, "spd": 10, "con": 14,
		"will": 62.0, "tier": 4, "weapon": "w_greatsword",
		"desc": "披着铁皮的布道者。他们说这是仁慈。",
	},
	"土匪": {
		"training": 0, "might": 12, "skill": 9, "spd": 11, "con": 10,
		"will": 22.0, "tier": 1, "weapon": "w_club",
		"desc": "去年还是农民。今年已经不问理由了。",
	},
}

static func random_name(rng: RandomNumberGenerator, unique_set: Array = []) -> String:
	for _i in range(40):
		var n: String = FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)]
		if n == "奥托" and rng.randf() < 0.5:
			n = "老奥托"
		var ep: String = EPITHETS[rng.randi_range(0, EPITHETS.size() - 1)]
		if ep != "":
			n = ep + n
		var s: String = SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)]
		var full := "%s·%s" % [n, s] if rng.randf() < 0.55 else n
		if not unique_set.has(full):
			unique_set.append(full)
			return full
	return "无名者"

static func make_unit(arch_name: String, faction: int, rng: RandomNumberGenerator,
		rname: String = "") -> WarUnit:
	var a: Dictionary = ARCH.get(arch_name, ARCH["民兵"])
	var u := WarUnit.new()
	var nm := rname if rname != "" else random_name(rng)
	var t: int = int(a.training)
	var might: int = int(a.might) + rng.randi_range(-1, 1)
	var skl: int = int(a.skill) + rng.randi_range(-1, 1)
	var spd: int = int(a.spd) + rng.randi_range(-1, 1)
	var cns: int = int(a.con) + rng.randi_range(-1, 1)
	var wl: float = float(a.will) + rng.randf_range(-4.0, 4.0)
	u.setup(nm, t, faction, might, skl, spd, cns, wl)
	var loadout := Gear.random_loadout(int(a.tier), rng)
	loadout["weapon"] = Gear.make(str(a.weapon), _mat_for_tier(int(a.tier), rng),
		rng.randf_range(0.35, 0.95))
	if not loadout.has("hands"):
		loadout["hands"] = Gear.make("hands_cloth", "hemp", 0.5)
	if not loadout.has("feet"):
		loadout["feet"] = Gear.make("feet_cloth", "hemp", 0.5)
	u.equip_all(loadout)
	u.epithet = arch_name
	return u

static func _mat_for_tier(tier: int, rng: RandomNumberGenerator) -> String:
	var pool := ["hemp", "leather", "leather", "iron", "iron", "bronze", "steel"]
	var t: int = clampi(tier, 0, 4)
	var idx: int = clampi(t + rng.randi_range(-1, 1), 0, pool.size() - 1)
	return str(pool[idx])

## 生成一个"队伍成员"数据块（会写进存档）
static func make_member(arch_name: String, rng: RandomNumberGenerator,
		rname: String = "") -> Dictionary:
	var a: Dictionary = ARCH.get(arch_name, ARCH["民兵"])
	var loadout := Gear.random_loadout(int(a.tier), rng)
	loadout["weapon"] = Gear.make(str(a.weapon), _mat_for_tier(int(a.tier), rng),
		rng.randf_range(0.35, 0.95))
	var gear_data := {}
	for k in loadout.keys():
		gear_data[k] = loadout[k].to_dict()
	return {
		"id": "m%d_%d" % [Time.get_ticks_usec(), randi()],
		"name": rname if rname != "" else random_name(rng),
		"arch": arch_name,
		"training": int(a.training),
		"might": int(a.might) + rng.randi_range(-1, 1),
		"skill": int(a.skill) + rng.randi_range(-1, 1),
		"spd": int(a.spd) + rng.randi_range(-1, 1),
		"con": int(a.con) + rng.randi_range(-1, 1),
		"will": float(a.will) + rng.randf_range(-4.0, 4.0),
		"gear": gear_data,
		"cond": 1.0,
		"severed": [],
		"dead": false,
		"exp": 0,
	}

## 由成员数据造出战斗单位；cond 表示旧伤，severed 是永久残废。
static func from_member(m: Dictionary, faction: int) -> WarUnit:
	var u := WarUnit.new()
	u.setup(str(m.get("name", "无名者")), int(m.get("training", 0)), faction,
		int(m.get("might", 10)), int(m.get("skill", 10)),
		int(m.get("spd", 10)), int(m.get("con", 10)),
		float(m.get("will", 30.0)))
	var gd: Dictionary = m.get("gear", {})
	var loadout := {}
	for k in gd.keys():
		loadout[k] = Gear.from_dict(gd[k])
	# 老存档没有手/脚装备：补最基础的，免得光脚空手
	if not loadout.has("hands"):
		loadout["hands"] = Gear.make("hands_cloth", "hemp", 0.5)
	if not loadout.has("feet"):
		loadout["feet"] = Gear.make("feet_cloth", "hemp", 0.5)
	u.equip_all(loadout)
	u.epithet = str(m.get("arch", ""))
	var cond := float(m.get("cond", 1.0))
	cond = clampf(cond, 0.05, 1.0)
	u.vitals = u.vitals_max * cond
	for p in WarUnit.PARTS:
		u.parts[p].hp = float(u.parts[p]["max"]) * cond
	for p in m.get("severed", []):
		if u.parts.has(p) and not u.severed_parts.has(p):
			u.severed_parts.append(p)
			u.parts[p].hp = 0.0
	u.morale = u.morale_max * clampf(0.55 + cond * 0.4, 0.3, 1.0)
	u.bleeding = 0.0
	return u

## 战斗结束后把单位状态写回成员数据
static func write_back(m: Dictionary, u: WarUnit) -> void:
	if u.dead:
		m["dead"] = true
		m["cond"] = 0.0
		return
	var vals := [u.vitals_ratio()]
	for p in WarUnit.PARTS:
		vals.append(u.part_ratio(p))
	var sum := 0.0
	for v in vals:
		sum += float(v)
	m["cond"] = clampf(sum / float(vals.size()), 0.05, 1.0)
	m["severed"] = u.severed_parts.duplicate()

## 生成一支敌人队伍，规模随天数增长
static func make_enemy_party(day: int, power: float, rng: RandomNumberGenerator) -> Array:
	var count := clampi(int(round(2.0 + power + float(day) * 0.06)), 2, 7)
	var pool := ["土匪", "劫掠者", "土匪", "民兵", "逃兵"]
	if day > 6:
		pool.append_array(["雇佣兵", "弓箭手"])
	if day > 12:
		pool.append_array(["重装步兵", "弩手"])
	var out := []
	for i in range(count):
		var arch: String = pool[rng.randi_range(0, pool.size() - 1)]
		out.append(make_unit(arch, 1, rng))
	return out

static func arch_desc(arch_name: String) -> String:
	return str(ARCH.get(arch_name, {}).get("desc", ""))

static func member_power(m: Dictionary) -> float:
	var p := 0.0
	p += float(m.get("might", 10)) * 0.4
	p += float(m.get("skill", 10)) * 0.6
	p += float(m.get("con", 10)) * 0.3
	p += float(m.get("training", 0)) * 4.0
	p *= clampf(float(m.get("cond", 1.0)), 0.2, 1.0)
	return p
