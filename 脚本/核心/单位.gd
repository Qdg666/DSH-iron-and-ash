extends RefCounted
class_name WarUnit

## 一个战士。血量按六个部位分别计算，另有一个"整体血量"（失血与内伤）。
## 能不能继续战斗，取决于：各部位血量、整体血量、意志、士气。

const PARTS := ["head", "torso", "arm_l", "arm_r", "hand_l", "hand_r",
	"leg_l", "leg_r", "foot_l", "foot_r"]
const PART_NAMES := {
	"head": "头部", "torso": "躯干", "arm_l": "左臂", "arm_r": "右臂",
	"hand_l": "左手", "hand_r": "右手", "leg_l": "左腿", "leg_r": "右腿",
	"foot_l": "左脚", "foot_r": "右脚",
}
const PART_SHORT := {
	"head": "头", "torso": "躯", "arm_l": "左臂", "arm_r": "右臂",
	"hand_l": "左手", "hand_r": "右手", "leg_l": "左腿", "leg_r": "右腿",
	"foot_l": "左脚", "foot_r": "右脚",
}
const PART_BASE := {
	"head": 16.0, "torso": 36.0, "arm_l": 20.0, "arm_r": 20.0,
	"hand_l": 10.0, "hand_r": 10.0, "leg_l": 22.0, "leg_r": 22.0,
	"foot_l": 12.0, "foot_r": 12.0,
}
const PART_HIT_MOD := {
	"head": -26.0, "torso": 0.0, "arm_l": -8.0, "arm_r": -8.0,
	"hand_l": -18.0, "hand_r": -18.0, "leg_l": -10.0, "leg_r": -10.0,
	"foot_l": -14.0, "foot_r": -14.0,
}

## 命中部位时，这一击有多少比例会牵动整体血量（失血、内伤）。
## 头/躯干几乎全额计入 —— 打中要害，人很快就不行了。
## 四肢与手脚本身不牵动整体血量，但一旦被斩断，会立刻爆发性失血（见 SEVER_BURST）。
const VITAL_SHARE := {
	"head": 1.0, "torso": 0.9,
	"arm_l": 0.0, "arm_r": 0.0, "hand_l": 0.0, "hand_r": 0.0,
	"leg_l": 0.0, "leg_r": 0.0, "foot_l": 0.0, "foot_r": 0.0,
}
## 肢体被斩断的瞬间，整体血量立刻损失上限的这个比例。
const SEVER_BURST := 0.20

## 护甲对三种伤害的等效转换：斩击怕甲，钝击破甲。
const ARMOR_VS := {"slash": 0.62, "pierce": 0.46, "blunt": 0.30}
## 等效护甲达到这个值后，攻击必须达到"破甲门槛"才能造成有效伤害。
const ARMOR_THRESHOLD := 8.0
## 破甲所需的伤害 = 等效护甲 × 这个系数（钝击最容易破甲）
const PEN_REQ := {"slash": 0.62, "pierce": 0.48, "blunt": 0.34}

const TRAIN_NAMES := ["民兵", "常备", "精锐"]
const TRAIN_MORALE_MAX := [68.0, 88.0, 100.0]

var uid := 0
var unit_name := "无名者"
var epithet := ""          # 称号，例如"断手的"
var faction := 0           # 0 = 玩家一方，1 = 敌方
var training := 0          # 训练度 0 民兵 / 1 常备 / 2 精锐

# 基础属性（10 为凡人基准）
var might := 10            # 力量
var skill := 10            # 技巧
var spd := 10              # 速度
var con := 10              # 体质
var will_max := 40.0       # 意志上限

# 资源
var parts := {}
var vitals_max := 100.0
var vitals := 100.0
var stamina_max := 100.0
var stamina := 100.0
var morale := 70.0
var morale_max := 88.0
var will := 40.0

var gear := {}
var pos := Vector2i.ZERO

# 状态
var defending := false
var routing := false
var dead := false
var bleeding := 0.0
var severed_parts: Array = []
var statuses: Array = []    # [{id, stacks, turns}]，见 状态.gd
var fatigue := 0
var has_acted := false
var has_moved := false
var skipped := false
var guard_bonus := 0.0     # 阵型加成的防御

signal damaged(unit, ev)

# —— 初始化 ——

func setup(p_name: String, p_training: int, p_faction: int,
		p_might: int, p_skill: int, p_spd: int, p_con: int, p_will: float) -> void:
	unit_name = p_name
	training = clampi(p_training, 0, 2)
	faction = p_faction
	might = p_might
	skill = p_skill
	spd = p_spd
	con = p_con
	will_max = p_will
	will = p_will
	morale_max = TRAIN_MORALE_MAX[training]
	morale = morale_max * 0.85
	stamina_max = 80.0 + float(con - 10) * 3.0 + float(training) * 6.0
	stamina = stamina_max
	vitals_max = 60.0 + float(con - 10) * 3.5
	vitals = vitals_max
	_init_parts()

func _init_parts() -> void:
	parts.clear()
	var scale := 1.0 + float(con - 10) * 0.045
	for p in PARTS:
		var mx: float = PART_BASE[p] * scale
		parts[p] = {"max": mx, "hp": mx}

func equip_all(loadout: Dictionary) -> void:
	gear = loadout

# —— 部位查询 ——

func part_hp(p: String) -> float:
	return float(parts[p].hp)

func part_max(p: String) -> float:
	return float(parts[p]["max"])

func part_ratio(p: String) -> float:
	var mx := part_max(p)
	if mx <= 0.0:
		return 0.0
	return clampf(part_hp(p) / mx, 0.0, 1.0)

func is_severed(p: String) -> bool:
	return severed_parts.has(p)

func _armor_slot(s: String) -> float:
	if gear.has(s) and gear[s] != null:
		return gear[s].armor()
	return 0.0

## 每个部位有各自的护甲值：手、脚、护臂、护腿分开算。
func armor_of(p: String) -> float:
	var a := 0.0
	match p:
		"head":
			a = _armor_slot("head")
		"torso":
			a = _armor_slot("torso")
		"arm_l", "arm_r":
			a = _armor_slot("arms") + _armor_slot("torso") * 0.15
		"hand_l", "hand_r":
			a = _armor_slot("hands") + _armor_slot("arms") * 0.30
		"leg_l", "leg_r":
			a = _armor_slot("legs") + _armor_slot("torso") * 0.10
		"foot_l", "foot_r":
			a = _armor_slot("feet") + _armor_slot("legs") * 0.30
	return a

## 护甲对某类伤害的等效值：斩击最吃甲，钝击几乎无视一半。
func armor_vs(p: String, dmg_type: String) -> float:
	return armor_of(p) * float(ARMOR_VS.get(dmg_type, 0.5))

## 破甲所需的攻击力（低于它就只能蹭掉一点血）。轻甲没有这个门槛。
func armor_need(p: String, dmg_type: String) -> float:
	var eff := armor_vs(p, dmg_type)
	if eff < ARMOR_THRESHOLD:
		return 0.0
	return eff * float(PEN_REQ.get(dmg_type, 0.5))

## 训练度带来的护甲利用率
func skill_armor_factor() -> float:
	return [0.0, 0.08, 0.16][training]

func weapon() -> Gear:
	return gear.get("weapon", null)

func total_weight() -> float:
	var w := 0.0
	for k in gear.keys():
		if gear[k] != null:
			w += gear[k].weight()
	return w

# —— 状态 ——

func add_status(id: String, stacks: int = 1) -> void:
	var d := Status.def(id)
	if d.is_empty():
		return
	for s in statuses:
		if str(s["id"]) == id:
			s["stacks"] = mini(int(d.get("stack_max", 1)), int(s["stacks"]) + stacks)
			s["turns"] = int(d.get("dur", 1))
			return
	statuses.append(Status.make(id, stacks))

func status_stacks(id: String) -> int:
	for s in statuses:
		if str(s["id"]) == id:
			return int(s["stacks"])
	return 0

func has_status(id: String) -> bool:
	return status_stacks(id) > 0

## 状态带来的属性修正（负数为减益）
func status_mod(key: String) -> float:
	var v := 0.0
	for s in statuses:
		var d := Status.def(str(s["id"]))
		var mods: Dictionary = d.get("mods", {})
		if mods.has(key):
			v += float(mods[key]) * float(s["stacks"])
	return v

func status_damage_mult() -> float:
	return clampf(1.0 + status_mod("dmg"), 0.30, 1.0)

func status_names() -> String:
	var out: Array = []
	for s in statuses:
		var d := Status.def(str(s["id"]))
		var nm := str(d.get("name", ""))
		if int(s["stacks"]) > 1:
			nm += "×%d" % int(s["stacks"])
		if int(s["turns"]) > 0:
			nm += "(%d)" % int(s["turns"])
		out.append(nm)
	return "、".join(out)

func status_color() -> Color:
	for s in statuses:
		var d := Status.def(str(s["id"]))
		if not d.is_empty():
			return d.get("color", Color("c06a55"))
	return Color("c06a55")

## 每回合开始结算状态：掉血、减持续、过期清除。返回事件供战报记录。
func tick_statuses() -> Dictionary:
	var ev := {"damage": 0.0, "expired": [], "died": false}
	if dead:
		statuses.clear()
		return ev
	var keep: Array = []
	for s in statuses:
		var d := Status.def(str(s["id"]))
		var pct := float(d.get("vital_pct", 0.0))
		if pct > 0.0:
			var loss := vitals_max * pct * float(s["stacks"])
			vitals = maxf(0.0, vitals - loss)
			ev.damage += loss
		s["turns"] = int(s["turns"]) - 1
		if int(s["turns"]) > 0:
			keep.append(s)
		else:
			ev.expired.append(str(d.get("name", "")))
	statuses = keep
	if vitals <= 0.0 and not dead:
		dead = true
		ev.died = true
	return ev

# —— 派生数值 ——

func is_active() -> bool:
	return not dead and not routing

func can_attack() -> bool:
	if dead or routing:
		return false
	if weapon() == null:
		return false
	if is_severed("arm_l") and is_severed("arm_r"):
		return false
	if is_severed("hand_l") and is_severed("hand_r"):
		return false
	if is_severed("arm_r") and weapon().attack_range() < 2:
		return false
	# 持械手没了：长杆/弓弩这类需要双手的武器就用不了了
	if is_severed("hand_r") and weapon().attack_range() >= 2:
		return false
	return true

func vitals_ratio() -> float:
	return clampf(vitals / maxf(1.0, vitals_max), 0.0, 1.0)

func stamina_ratio() -> float:
	return clampf(stamina / maxf(1.0, stamina_max), 0.0, 1.0)

func morale_ratio() -> float:
	return clampf(morale / maxf(1.0, morale_max), 0.0, 1.0)

func will_ratio() -> float:
	return clampf(will / maxf(1.0, will_max), 0.0, 1.0)

func arm_penalty() -> float:
	var p := 0.0
	if is_severed("arm_r"):
		p -= 26.0
	if is_severed("arm_l"):
		p -= 9.0
	return p

func leg_penalty() -> float:
	var p := 0.0
	if is_severed("leg_l"):
		p -= 1.6
	if is_severed("leg_r"):
		p -= 1.6
	return p

func head_penalty() -> float:
	if part_ratio("head") < 0.35:
		return -12.0
	return 0.0

## 手伤：右手是持械手，越伤越握不住刀 —— 命中与伤害一起掉。
func hand_penalty() -> float:
	var p := 0.0
	p -= (1.0 - part_ratio("hand_r")) * 22.0
	p -= (1.0 - part_ratio("hand_l")) * 8.0
	if is_severed("hand_r"):
		p -= 12.0
	if is_severed("hand_l"):
		p -= 4.0
	return p

func hand_damage_mult() -> float:
	var m := 1.0
	m -= (1.0 - part_ratio("hand_r")) * 0.28
	if is_severed("hand_r"):
		m *= 0.70
	if is_severed("hand_l"):
		m *= 0.92
	return clampf(m, 0.35, 1.0)

## 脚伤：走不快、站不稳、出手也慢。
func foot_penalty() -> float:
	var p := 0.0
	for f in ["foot_l", "foot_r"]:
		p -= (1.0 - part_ratio(f)) * 1.4
		if is_severed(f):
			p -= 0.5
	return p

func foot_evasion_penalty() -> float:
	var p := 0.0
	for f in ["foot_l", "foot_r"]:
		p -= (1.0 - part_ratio(f)) * 5.0
	return p

func move_allowance() -> float:
	var v := 3.6 + float(spd - 10) * 0.13 - total_weight() * 0.16
	v += leg_penalty() + foot_penalty() + stamina_ratio() * 0.8
	v += [0.0, 0.2, 0.4][training]
	v += status_mod("move")
	return maxf(1.0, v)

func base_accuracy() -> float:
	var a := 46.0 + float(skill) * 1.7 + float(training) * 5.0
	a += (morale - 50.0) * 0.10
	a += will_ratio() * 6.0
	a += (stamina_ratio() - 0.5) * 8.0
	a += arm_penalty() + head_penalty() + hand_penalty()
	a -= total_weight() * 0.28
	a += status_mod("acc")
	return a

func evasion() -> float:
	var e := 6.0 + float(spd) * 0.95 - total_weight() * 0.32
	e += (stamina_ratio() - 0.5) * 10.0
	e += leg_penalty() * 4.0 + foot_evasion_penalty()
	if defending:
		e += 6.0
	e += status_mod("eva")
	return e

func defense_value() -> float:
	var d := 4.0 + float(training) * 4.0 + skill_armor_factor() * 60.0
	d += guard_bonus
	if defending:
		d += 12.0
	if is_severed("leg_l") and is_severed("leg_r"):
		d -= 8.0
	d += status_mod("def")
	return d

func initiative() -> float:
	var i := 12.0 + float(spd) * 1.15 + will_ratio() * 12.0
	i += morale_ratio() * 7.0 + float(training) * 2.5
	i -= total_weight() * 0.35
	i += stamina_ratio() * 4.0
	if has_acted:
		i -= 3.0
	if skipped:
		i += 5.0
	if routing:
		i += 8.0
	i += foot_penalty() * 2.0
	i += status_mod("init")
	return i

func injury_penalty_text() -> String:
	var out: Array = []
	if is_severed("arm_l"):
		out.append("左臂断")
	if is_severed("arm_r"):
		out.append("右臂断")
	if is_severed("hand_l"):
		out.append("左手断")
	if is_severed("hand_r"):
		out.append("右手断")
	if is_severed("leg_l"):
		out.append("左腿断")
	if is_severed("leg_r"):
		out.append("右腿断")
	if is_severed("foot_l"):
		out.append("左脚断")
	if is_severed("foot_r"):
		out.append("右脚断")
	if part_ratio("hand_r") < 0.75:
		out.append("右手伤")
	if part_ratio("hand_l") < 0.75:
		out.append("左手伤")
	if part_ratio("foot_l") < 0.7 or part_ratio("foot_r") < 0.7:
		out.append("跛行")
	if part_ratio("head") < 0.35:
		out.append("头破血流")
	if part_ratio("torso") < 0.35:
		out.append("内脏出血")
	if bleeding > 0.0:
		out.append("流血")
	if fatigue > 0:
		out.append("力竭×%d" % fatigue)
	if defending:
		out.append("架势")
	if routing:
		out.append("溃逃")
	return "，".join(out)

func is_flank_broken() -> bool:
	return severed_parts.size() >= 2

# —— 战斗结算 ——

## 承受一次命中。dmg_type 为斩击/刺击/钝击，护甲按类型分别减免。
## 返回事件字典，供战报使用（blocked=true 表示没破甲）。
func take_hit(part: String, raw_damage: float, dmg_type: String = "slash") -> Dictionary:
	var ev := {"severed": false, "died": false, "armor": 0.0, "damage": 0.0,
		"vital": 0.0, "burst": 0.0, "blocked": false}
	if dead:
		return ev
	var armor: float = armor_vs(part, dmg_type) * (1.0 - float(training) * 0.04)
	var need: float = armor_need(part, dmg_type) * (1.0 - float(training) * 0.04)
	ev.armor = armor
	var pd: Dictionary = parts[part]
	# —— 重甲门槛：伤害不够就破不了甲，只能蹭掉一点 ——
	if need > 0.0 and raw_damage < need:
		var chip: float = maxf(1.0, raw_damage * 0.12)
		# 破不了甲就只能蹭，最多把部位蹭到残血，不会直接打废
		pd.hp = maxf(1.0, float(pd.hp) - chip)
		var vd_chip: float = chip * float(VITAL_SHARE.get(part, 0.0))
		vitals = maxf(0.0, vitals - vd_chip)
		ev.blocked = true
		ev.damage = chip
		ev.vital = vd_chip
		damaged.emit(self, ev)
		return ev
	# 护甲按类型吃掉一部分；破甲之后才谈得上伤害
	var reduction: float = minf(raw_damage * 0.72, armor * 0.55)
	var dmg: float = maxf(1.0, raw_damage - reduction)
	ev.damage = dmg
	pd.hp = maxf(0.0, float(pd.hp) - dmg)
	# 部位受创牵动整体：头/躯干几乎全额计入，四肢只是皮肉
	var vital_share: float = float(VITAL_SHARE.get(part, 0.0))
	var vd := dmg * vital_share
	vitals = maxf(0.0, vitals - vd)
	ev.vital = vd

	if pd.hp <= 0.0 and not is_severed(part):
		if part == "head" or part == "torso":
			# 头或躯干被破坏 —— 当场死亡
			dead = true
			ev.died = true
		else:
			# 断肢：立刻失去 20% 整体血量，并挂上大出血 + 断肢剧痛
			severed_parts.append(part)
			var burst := vitals_max * SEVER_BURST
			vitals = maxf(0.0, vitals - burst)
			ev.burst = burst
			ev.vital += burst
			bleeding += 2.4
			morale -= 16.0
			will = maxf(0.0, will - 8.0)
			ev.severed = true
			add_status("bleed_heavy", 1)
			add_status("shock", 1)
	if vitals <= 0.0 and not dead:
		dead = true
		ev.died = true
	if dead:
		routing = false
		morale = minf(morale, 10.0)
	damaged.emit(self, ev)
	return ev

## 每回合开始：状态结算、流血、疲劳恢复、意志回稳
func round_start() -> Dictionary:
	var ev := {"bled": 0.0, "died": false, "fled": false, "status_damage": 0.0,
		"expired": [], "status_died": false}
	if dead:
		return ev
	var st := tick_statuses()
	ev.status_damage = float(st.get("damage", 0.0))
	ev.expired = st.get("expired", [])
	if bool(st.get("died", false)):
		dead = true
		ev.status_died = true
		ev.died = true
	if dead:
		return ev
	if bleeding > 0.0 and vitals > 0.0:
		var b := bleeding
		vitals = maxf(0.0, vitals - b)
		ev.bled = b
		if vitals <= 0.0:
			dead = true
			ev.died = true
	# 喘息
	stamina = minf(stamina_max, stamina + 14.0 + float(con - 10) * 0.7)
	will = minf(will_max, will + 2.5)
	if not dead and not routing:
		# 士气回升：训练度高的部队更稳
		var rec := 2.0 + float(training) * 2.4
		if guard_bonus > 0.0:
			rec += 2.0
		morale = minf(morale_max, morale + rec)
		# 士气崩溃 + 意志检定
		if morale <= 18.0 and not ev.died:
			if not morale_check():
				routing = true
				ev.fled = true
	# 疲劳随体力恢复而消退
	if stamina >= stamina_max * 0.85 and fatigue > 0:
		fatigue = maxi(0, fatigue - 1)
	return ev

## 意志检定：士气低于阈值时，用意志对抗恐惧。
func morale_check() -> bool:
	var target := will_ratio() * 0.5 + 0.22
	return randf() < target

func adjust_morale(delta: float, _reason: String = "") -> void:
	if dead:
		return
	morale = clampf(morale + delta, 0.0, morale_max)

func consume_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	if stamina <= 0.0:
		fatigue += 1

func reset_turn_flags() -> void:
	has_acted = false
	has_moved = false
	skipped = false
	defending = false

func clone_snapshot() -> Dictionary:
	var p := {}
	for k in PARTS:
		p[k] = float(parts[k].hp)
	return {
		"name": unit_name, "vitals": vitals, "parts": p,
		"morale": morale, "will": will, "training": training,
		"dead": dead, "severed": severed_parts.duplicate(),
	}

func training_name() -> String:
	return TRAIN_NAMES[training]

func short_status() -> String:
	if dead:
		return "阵亡"
	if routing:
		return "溃逃"
	if is_severed("arm_r") and is_severed("arm_l"):
		return "双臂尽断"
	if is_severed("hand_r") and is_severed("hand_l"):
		return "双手尽断"
	if is_severed("foot_l") and is_severed("foot_r"):
		return "双足尽断"
	return training_name()
