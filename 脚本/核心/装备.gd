extends RefCounted
class_name Gear

## 装备由两根轴构成：**版型**（形状，决定覆盖部位与基础性能）与**材质**（品质倍率与颜色）。
## 例：锻钢 · 札甲 = 札甲版型 × 锻钢材质。

const SLOTS := ["head", "torso", "arms", "hands", "legs", "feet", "weapon"]
const SLOT_NAMES := {
	"head": "头部", "torso": "躯干", "arms": "手臂", "hands": "手",
	"legs": "腿部", "feet": "脚", "weapon": "武器",
}

## 伤害类型：斩击 / 刺击 / 钝击。护甲对三者的减免完全不同。
const TYPE_NAMES := {"slash": "斩击", "pierce": "刺击", "blunt": "钝击"}

# 版型：slot 决定穿戴位置；armor 为基础护甲；dmg/hit/range/type 仅武器使用。
const PATTERNS := {
	# —— 头 ——
	"head_cloth":  {"name": "布巾",   "slot": "head", "armor": 1.5, "weight": 0.5, "tier": 0},
	"head_hood":   {"name": "皮兜帽", "slot": "head", "armor": 4.0, "weight": 1.5, "tier": 1},
	"head_helm":   {"name": "铁盔",   "slot": "head", "armor": 8.0, "weight": 3.5, "tier": 2},
	"head_great":  {"name": "全盔",   "slot": "head", "armor": 12.0, "weight": 5.5, "tier": 3},
	# —— 躯干 ——
	"torso_tunic":  {"name": "布衣",   "slot": "torso", "armor": 2.0, "weight": 1.0, "tier": 0},
	"torso_jerkin": {"name": "皮甲",   "slot": "torso", "armor": 5.0, "weight": 3.0, "tier": 1},
	"torso_hauberk":{"name": "锁甲",   "slot": "torso", "armor": 9.0, "weight": 7.0, "tier": 2},
	"torso_lamel":  {"name": "札甲",   "slot": "torso", "armor": 13.0, "weight": 9.5, "tier": 3},
	"torso_plate":  {"name": "板甲",   "slot": "torso", "armor": 18.0, "weight": 14.0, "tier": 4},
	# —— 手臂 ——
	"arms_cloth":  {"name": "布袖",   "slot": "arms", "armor": 1.0, "weight": 0.3, "tier": 0},
	"arms_leather":{"name": "皮护臂", "slot": "arms", "armor": 3.0, "weight": 1.0, "tier": 1},
	"arms_iron":   {"name": "铁护臂", "slot": "arms", "armor": 6.0, "weight": 2.5, "tier": 2},
	# —— 手 ——
	"hands_cloth":  {"name": "裹手布", "slot": "hands", "armor": 0.8, "weight": 0.2, "tier": 0},
	"hands_leather":{"name": "皮手套", "slot": "hands", "armor": 2.0, "weight": 0.5, "tier": 1},
	"hands_mail":   {"name": "铁护手", "slot": "hands", "armor": 4.5, "weight": 1.5, "tier": 2},
	# —— 腿 ——
	"legs_cloth":  {"name": "布裤",   "slot": "legs", "armor": 1.0, "weight": 0.4, "tier": 0},
	"legs_leather":{"name": "皮护腿", "slot": "legs", "armor": 3.0, "weight": 1.2, "tier": 1},
	"legs_iron":   {"name": "铁护腿", "slot": "legs", "armor": 6.5, "weight": 3.0, "tier": 2},
	# —— 脚 ——
	"feet_cloth":  {"name": "布鞋",   "slot": "feet", "armor": 0.8, "weight": 0.3, "tier": 0},
	"feet_boots":  {"name": "皮靴",   "slot": "feet", "armor": 2.2, "weight": 0.8, "tier": 1},
	"feet_greaves":{"name": "铁护胫", "slot": "feet", "armor": 5.0, "weight": 2.0, "tier": 2},
	# —— 武器 ——
	"w_club":     {"name": "木棍",   "slot": "weapon", "dmg": 8.0,  "hit": 0,  "range": 1, "weight": 2.0, "tier": 0, "type": "blunt"},
	"w_scythe":   {"name": "镰刀",   "slot": "weapon", "dmg": 12.0, "hit": 1,  "range": 1, "weight": 2.5, "tier": 0, "type": "slash"},
	"w_spear":    {"name": "长枪",   "slot": "weapon", "dmg": 14.0, "hit": 2,  "range": 2, "weight": 3.5, "tier": 1, "type": "pierce"},
	"w_sword":    {"name": "长剑",   "slot": "weapon", "dmg": 13.0, "hit": 9,  "range": 1, "weight": 2.5, "tier": 2, "type": "slash"},
	"w_axe":      {"name": "战斧",   "slot": "weapon", "dmg": 19.0, "hit": -3, "range": 1, "weight": 4.0, "tier": 2, "type": "slash"},
	"w_bow":      {"name": "猎弓",   "slot": "weapon", "dmg": 10.0, "hit": 7,  "range": 3, "weight": 1.5, "tier": 1, "type": "pierce"},
	"w_crossbow": {"name": "弩",     "slot": "weapon", "dmg": 17.0, "hit": 11, "range": 3, "weight": 4.5, "tier": 2, "type": "pierce"},
	"w_greatsword":{"name": "双手剑","slot": "weapon", "dmg": 22.0, "hit": 5,  "range": 1, "weight": 6.0, "tier": 3, "type": "slash"},
}

# 材质：mult 为性能倍率，hue/sat/val 决定颜色 —— 数值越好，饱和度越高。
const MATERIALS := {
	"hemp":    {"name": "麻",   "mult": 0.75, "tier": 0, "hue": 0.11, "sat": 0.14, "val": 0.50, "weight": 0.8},
	"leather": {"name": "皮革", "mult": 1.00, "tier": 1, "hue": 0.07, "sat": 0.34, "val": 0.40, "weight": 1.0},
	"bronze":  {"name": "青铜", "mult": 1.15, "tier": 2, "hue": 0.10, "sat": 0.45, "val": 0.55, "weight": 1.2},
	"iron":    {"name": "铁",   "mult": 1.30, "tier": 2, "hue": 0.58, "sat": 0.10, "val": 0.56, "weight": 1.15},
	"steel":   {"name": "锻钢", "mult": 1.60, "tier": 3, "hue": 0.57, "sat": 0.24, "val": 0.72, "weight": 1.1},
	"meteor":  {"name": "陨铁", "mult": 2.00, "tier": 4, "hue": 0.76, "sat": 0.38, "val": 0.64, "weight": 1.25},
}

var pattern_id := "torso_tunic"
var material_id := "hemp"
var quality := 0.5        # 0..1，粗糙/精良
var durability := 1.0     # 0..1 只剩残片

func _init(p_pattern: String = "torso_tunic", p_material: String = "hemp",
		p_quality: float = 0.5) -> void:
	pattern_id = p_pattern
	material_id = p_material
	quality = p_quality

static func make(p_pattern: String, p_material: String, p_quality: float = 0.5) -> Gear:
	return Gear.new(p_pattern, p_material, p_quality)

func pat() -> Dictionary:
	return PATTERNS.get(pattern_id, PATTERNS["torso_tunic"])

func mat() -> Dictionary:
	return MATERIALS.get(material_id, MATERIALS["hemp"])

func slot() -> String:
	return pat().get("slot", "torso")

func is_weapon() -> bool:
	return slot() == "weapon"

func display_name() -> String:
	return "%s · %s" % [mat().name, pat().name]

static func slot_name(s: String) -> String:
	return SLOT_NAMES.get(s, s)

# —— 数值 ——

func armor() -> float:
	if is_weapon():
		return 0.0
	return pat().armor * mat().mult * (0.7 + 0.3 * quality) * (0.6 + 0.4 * durability)

func damage() -> float:
	if not is_weapon():
		return 0.0
	return pat().dmg * mat().mult * (0.85 + 0.3 * quality) * (0.55 + 0.45 * durability)

func hit_bonus() -> int:
	if not is_weapon():
		return 0
	return int(pat().hit) + int(round((quality - 0.5) * 6.0))

func attack_range() -> int:
	return int(pat().get("range", 1))

## 武器伤害类型：斩击 / 刺击 / 钝击
func damage_type() -> String:
	return str(pat().get("type", "slash"))

func damage_type_name() -> String:
	return str(TYPE_NAMES.get(damage_type(), "斩击"))

func weight() -> float:
	return pat().weight * mat().weight

## 数值越好，饱和度越高 —— 界面上装备的颜色随之更"活"。
func color() -> Color:
	var m := mat()
	var sat: float = m.sat * (0.55 + 0.45 * quality) * (0.5 + 0.5 * durability)
	var val: float = m.val * (0.85 + 0.2 * quality)
	return Color.from_hsv(m.hue, sat, val)

func tier() -> int:
	return int(mat().tier) * 2 + int(pat().get("tier", 0))

## 大致市价：阶级、品质、耐久
func value() -> int:
	var t := tier()
	var v := 8.0 + float(t) * 7.0
	v *= 0.70 + 0.60 * quality
	v *= 0.55 + 0.45 * durability
	return maxi(4, int(round(v)))

func describe() -> String:
	if is_weapon():
		return "%s\n伤害 %.0f（%s）   命中 %+d   射程 %d\n重量 %.1f" % [
			display_name(), damage(), damage_type_name(), hit_bonus(), attack_range(), weight()]
	return "%s\n护甲 %.0f\n重量 %.1f   品质 %d%%" % [
		display_name(), armor(), weight(), int(quality * 100.0)]

# —— 序列化 ——

func to_dict() -> Dictionary:
	return {"p": pattern_id, "m": material_id, "q": quality, "d": durability}

static func from_dict(d: Dictionary) -> Gear:
	var g := Gear.new(str(d.get("p", "torso_tunic")), str(d.get("m", "hemp")),
		float(d.get("q", 0.5)))
	g.durability = float(d.get("d", 1.0))
	return g

# —— 预设 ——

const SLOT_PATTERNS := {
	"head": ["head_cloth", "head_hood", "head_helm", "head_great"],
	"torso": ["torso_tunic", "torso_jerkin", "torso_hauberk", "torso_lamel", "torso_plate"],
	"arms": ["arms_cloth", "arms_leather", "arms_iron"],
	"hands": ["hands_cloth", "hands_leather", "hands_mail"],
	"legs": ["legs_cloth", "legs_leather", "legs_iron"],
	"feet": ["feet_cloth", "feet_boots", "feet_greaves"],
	"weapon": ["w_club", "w_scythe", "w_spear", "w_sword", "w_axe", "w_bow", "w_crossbow", "w_greatsword"],
}

## 单件随机装备：城镇市场用
static func random_piece(tier: int, rng: RandomNumberGenerator) -> Gear:
	var slots := ["head", "torso", "arms", "hands", "legs", "feet", "weapon", "weapon", "torso"]
	var slot: String = slots[rng.randi_range(0, slots.size() - 1)]
	var pool: Array = SLOT_PATTERNS[slot]
	var idx: int = clampi(tier + rng.randi_range(-1, 1), 0, pool.size() - 1)
	var mats := {
		0: ["hemp", "hemp", "leather"],
		1: ["leather", "leather", "iron"],
		2: ["iron", "iron", "bronze", "steel"],
		3: ["steel", "steel", "iron", "meteor"],
	}
	var mp: Array = mats[clampi(tier, 0, 3)]
	var mat: String = mp[rng.randi_range(0, mp.size() - 1)]
	return Gear.make(str(pool[idx]), mat, rng.randf_range(0.3, 0.95))

const PRESETS := {
	"农奴": "w_scythe",
	"逃兵": "w_spear",
	"雇佣兵": "w_sword",
	"弓箭手": "w_bow",
	"弩手": "w_crossbow",
	"劫掠者": "w_axe",
	"重装步兵": "w_spear",
}

## 按"阶级"生成一整套装备：tier 越高越精良。
static func random_loadout(tier: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var out := {}
	var mats_by_tier := {
		0: ["hemp", "hemp", "leather"],
		1: ["leather", "leather", "iron"],
		2: ["iron", "iron", "bronze", "steel"],
		3: ["steel", "steel", "iron", "meteor"],
	}
	var t: int = clampi(tier, 0, 3)
	var pool: Array = mats_by_tier[t]
	# 头
	if r.randf() < 0.85:
		var hp: Array = ["head_cloth", "head_hood", "head_helm", "head_great"]
		out["head"] = Gear.make(_pick(hp, t, r), _pick(pool, 0, r), r.randf_range(0.3, 0.95))
	# 躯干
	var tp: Array = ["torso_tunic", "torso_jerkin", "torso_hauberk", "torso_lamel", "torso_plate"]
	out["torso"] = Gear.make(_pick(tp, t, r), _pick(pool, 0, r), r.randf_range(0.3, 0.95))
	# 手臂 / 腿部
	if r.randf() < 0.8:
		out["arms"] = Gear.make(_pick(["arms_cloth", "arms_leather", "arms_iron"], t, r),
			_pick(pool, 0, r), r.randf_range(0.3, 0.9))
	if r.randf() < 0.7:
		out["hands"] = Gear.make(_pick(["hands_cloth", "hands_leather", "hands_mail"], t, r),
			_pick(pool, 0, r), r.randf_range(0.3, 0.9))
	if r.randf() < 0.8:
		out["legs"] = Gear.make(_pick(["legs_cloth", "legs_leather", "legs_iron"], t, r),
			_pick(pool, 0, r), r.randf_range(0.3, 0.9))
	if r.randf() < 0.7:
		out["feet"] = Gear.make(_pick(["feet_cloth", "feet_boots", "feet_greaves"], t, r),
			_pick(pool, 0, r), r.randf_range(0.3, 0.9))
	# 武器
	var wp: Array = ["w_club", "w_scythe", "w_spear", "w_sword", "w_axe", "w_bow", "w_crossbow", "w_greatsword"]
	out["weapon"] = Gear.make(_pick(wp, t, r), _pick(pool, 0, r), r.randf_range(0.3, 0.95))
	return out

## 从版型表中按阶级取一件（越靠后越高级），带少量随机偏移。
static func _pick(pool: Array, tier: int, r: RandomNumberGenerator) -> String:
	var idx: int = clampi(tier + r.randi_range(-1, 1), 0, pool.size() - 1)
	return str(pool[idx])
