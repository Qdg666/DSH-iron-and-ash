extends RefCounted
class_name Battle

## 战斗的全部规则与状态。界面只负责读取与呈现。
## 回合顺序由"主动值"决定（速度、意志、士气、训练度、负重共同决定）。

signal turn_changed(unit)
signal logged(text: String)
signal finished(winner: int)
signal board_changed()

const TERRAIN := {
	"plain":  {"name": "荒原", "cost": 1.0, "cover": 0, "color": Color("2b2620"), "edge": Color("3a3229")},
	"road":   {"name": "道路", "cost": 0.7, "cover": -2, "color": Color("3a3128"), "edge": Color("4c4033")},
	"forest": {"name": "林子", "cost": 1.9, "cover": 14, "color": Color("1f2a1d"), "edge": Color("2c3a27")},
	"hill":   {"name": "丘陵", "cost": 1.7, "cover": 10, "color": Color("332d24"), "edge": Color("463d30")},
	"marsh":  {"name": "泥沼", "cost": 2.5, "cover": -10, "color": Color("232a26"), "edge": Color("2f3a34")},
	"rock":   {"name": "断壁", "cost": 99.0, "cover": 22, "color": Color("1a1815"), "edge": Color("2a2620"), "block": true},
	"water":  {"name": "浅水", "cost": 2.2, "cover": -4, "color": Color("1b242c"), "edge": Color("2a3842")},
}

var tiles := {}                  # Vector2i -> terrain id
var units: Array = []            # Array[WarUnit]
var order: Array = []            # Array[int] uid
var round_no := 1
var turn_idx := -1
var current: WarUnit = null
var winner := -1                 # -1 未定，0 玩家胜，1 敌胜
var log_lines: Array = []
var by_uid := {}
var seed_value := 0

## 天黑之前必须分出结果：超过这个回合数，按存活的完整度判定。
const MAX_ROUNDS := 24

# 显示用的战场尺寸（轴坐标生成时的行列数）
var cols := 13
var rows := 9

func _init(p_seed: int = 0) -> void:
	seed_value = p_seed

# —— 建立战场 ——

func generate(rng: RandomNumberGenerator) -> void:
	cols = rng.randi_range(11, 14)
	rows = rng.randi_range(8, 10)
	var hexes := Hex.rect_map(cols, rows)
	for h in hexes:
		tiles[h] = "plain"
	# 道路：一条横穿战场的大路
	var mid_row := int(rows / 2.0)
	for c in range(cols):
		var off := int(floor(float(mid_row) / 2.0))
		var h := Vector2i(c - off, mid_row)
		if tiles.has(h):
			tiles[h] = "road"
	# 随机地貌斑块
	var kinds := ["forest", "hill", "marsh", "water", "rock"]
	for i in range(rng.randi_range(5, 8)):
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var center: Vector2i = hexes[rng.randi_range(0, hexes.size() - 1)]
		var radius := rng.randi_range(1, 2)
		for h in Hex.within(center, radius):
			if tiles.has(h) and rng.randf() < 0.6:
				tiles[h] = kind
	# 别让出生点变成死地
	for h in hexes:
		var c := _col_of(h)
		if (c <= 1 or c >= cols - 2) and tiles[h] == "rock":
			tiles[h] = "plain"
	# 地貌可能把大路盖断，把战场切成两半 —— 最后重新铺一遍路，保证双方能碰面
	for c in range(cols):
		var off2 := int(floor(float(mid_row) / 2.0))
		var h2 := Vector2i(c - off2, mid_row)
		if tiles.has(h2):
			tiles[h2] = "road"
	_ensure_path()

## 连通性检查：如果左、右出生区之间走不通，就把断壁全部降成丘陵。
func _ensure_path() -> void:
	var start := Vector2i(-int(floor(float(int(rows / 2.0)) / 2.0)), int(rows / 2.0))
	if not tiles.has(start):
		return
	var seen := _flood(start)
	var ok := false
	for h in tiles.keys():
		if _col_of(h) >= cols - 2 and seen.has(h):
			ok = true
			break
	if ok:
		return
	for h in tiles.keys():
		if tiles[h] == "rock":
			tiles[h] = "hill"

func _flood(start: Vector2i) -> Dictionary:
	var seen := {}
	if not is_passable(start):
		return seen
	seen[start] = true
	var open: Array = [start]
	while not open.is_empty():
		var cur: Vector2i = open.pop_back()
		for n in Hex.neighbors(cur):
			if seen.has(n) or not tiles.has(n) or not is_passable(n):
				continue
			seen[n] = true
			open.append(n)
	return seen

func _col_of(h: Vector2i) -> int:
	return h.x + int(floor(float(h.y) / 2.0))

func terrain_at(h: Vector2i) -> Dictionary:
	return TERRAIN.get(tiles.get(h, "plain"), TERRAIN["plain"])

func is_passable(h: Vector2i) -> bool:
	if not tiles.has(h):
		return false
	return not terrain_at(h).get("block", false)

func unit_at(h: Vector2i) -> WarUnit:
	for u in units:
		if u.is_active() and u.pos == h:
			return u
	return null

func unit_by_uid(id: int) -> WarUnit:
	return by_uid.get(id, null)

# —— 部署 ——

## player_slots：与 player_units 对应的阵形槽（行 0..3 × 列 0 后排 / 1 前排）。
## 没给阵形时按顺序自动排。
func deploy(player_units: Array, enemy_units: Array, player_slots: Array = []) -> void:
	units.clear()
	by_uid.clear()
	var left := _spawn_hexes(true)
	var right := _spawn_hexes(false)
	var back: Array = []
	var front: Array = []
	for h in left:
		if _col_of(h) == 0:
			back.append(h)
		else:
			front.append(h)
	back.sort_custom(func(a, b): return a.y < b.y)
	front.sort_custom(func(a, b): return a.y < b.y)
	var used := {}
	var i := 0
	for u in player_units:
		u.faction = 0
		var slot: int = int(player_slots[i]) if i < player_slots.size() else -1
		u.pos = _slot_pos(slot, i, back, front, left, used)
		_add(u)
		i += 1
	i = 0
	for u in enemy_units:
		u.faction = 1
		u.pos = right[right.size() - 1 - (i % right.size())]
		_add(u)
		i += 1
	_build_order()
	turn_idx = -1
	_advance()

func _slot_pos(slot: int, order: int, back: Array, front: Array, all_left: Array,
		used: Dictionary) -> Vector2i:
	var list: Array = []
	var row := 0
	if slot >= 0:
		row = int(slot / 2)
		list = front if slot % 2 == 1 else back
	else:
		row = order
		list = back + front
	if list.is_empty():
		list = all_left
	for k in range(list.size()):
		var h: Vector2i = list[(row + k) % list.size()]
		if not used.has(h):
			used[h] = true
			return h
	for h in all_left:
		if not used.has(h):
			used[h] = true
			return h
	return Vector2i(9999, 9999)

func _add(u: WarUnit) -> void:
	u.uid = units.size() + 1
	units.append(u)
	by_uid[u.uid] = u

func _spawn_hexes(player_side: bool) -> Array:
	var out := []
	var cols_range := range(0, 2) if player_side else range(cols - 2, cols)
	for h in tiles.keys():
		var c := _col_of(h)
		if cols_range.has(c) and is_passable(h) and unit_at(h) == null:
			out.append(h)
	out.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	if out.size() == 0:
		for h in tiles.keys():
			if is_passable(h) and unit_at(h) == null:
				out.append(h)
	return out

# —— 回合推进 ——

func _build_order() -> void:
	var sorted := units.filter(func(u): return u.is_active())
	sorted.sort_custom(func(a, b): return a.initiative() > b.initiative())
	order.clear()
	for u in sorted:
		order.append(u.uid)

func begin_round() -> void:
	if round_no >= MAX_ROUNDS:
		_end_by_attrition()
		return
	round_no += 1
	for u in units:
		if not u.dead:
			var ev: Dictionary = u.round_start()
			if float(ev.get("status_damage", 0.0)) > 0.0:
				_log("%s 的大出血止不住，又流掉 %.0f 生命。" % [u.unit_name,
					float(ev.get("status_damage", 0.0))])
			for e in ev.get("expired", []):
				_log("%s 的「%s」消退了。" % [u.unit_name, str(e)])
			if ev.bled > 0.0:
				_log("%s 的伤口在流血（-%.0f 整体血量）。" % [u.unit_name, ev.bled])
			if ev.died:
				_log("%s 失血过多，死了。" % u.unit_name)
				_on_death(u)
			elif ev.fled:
				_log("%s 的士气崩溃了，扔下武器往后跑。" % u.unit_name)
				u.adjust_morale(-8.0)
	_update_formations()
	_build_order()

func _update_formations() -> void:
	for u in units:
		u.guard_bonus = 0.0
		if u.training < 1 or not u.is_active():
			continue
		var n := 0
		for other in units:
			if other == u or not other.is_active():
				continue
			if other.faction != u.faction or other.training < 1:
				continue
			if Hex.distance(other.pos, u.pos) == 1:
				n += 1
		u.guard_bonus = minf(6.0, float(n) * 3.0)

func _advance() -> void:
	var guard := 0
	while winner < 0:
		guard += 1
		if guard > 512:
			return
		turn_idx += 1
		if turn_idx >= order.size():
			begin_round()
			_check_over()
			if winner >= 0:
				return
			turn_idx = 0
			if order.size() == 0:
				return
		var u: WarUnit = unit_by_uid(order[turn_idx])
		if u == null or not u.is_active():
			continue
		current = u
		u.reset_turn_flags()
		turn_changed.emit(u)
		return

## 当前单位结束行动
func end_unit_turn() -> void:
	if current != null:
		current.has_acted = true
	_check_over()
	if winner >= 0:
		return
	_advance()
	_check_over()

func _check_over() -> void:
	if winner >= 0:
		return
	var p := 0
	var e := 0
	for u in units:
		if u.is_active():
			if u.faction == 0:
				p += 1
			else:
				e += 1
	if e == 0:
		winner = 0
		_log("最后一名敌人倒下。战场安静下来，只剩苍蝇的声音。")
		finished.emit(winner)
	elif p == 0:
		winner = 1
		_log("你们的人已经跑光了。")
		finished.emit(winner)

## 回合数耗尽：按双方还站着的"完整度"判定，玩家的尸体不会被算进去太多。
func _end_by_attrition() -> void:
	if winner >= 0:
		return
	var ps := side_score(0)
	var es := side_score(1)
	winner = 0 if ps > es + 0.01 else 1
	_log("天完全黑了。血泡软了泥地，谁也看不清谁，双方脱离了接触。")
	finished.emit(winner)

func side_score(f: int) -> float:
	var s := 0.0
	for u in units:
		if u.faction != f or u.dead:
			continue
		s += u.vitals_ratio() * 0.5
		var pr := 0.0
		for p in WarUnit.PARTS:
			pr += u.part_ratio(p)
		s += (pr / 6.0) * 0.5
	return s

# —— 移动 ——

## 返回可到达的格子：hex -> {"cost": float, "prev": Vector2i}
func reachable(u: WarUnit) -> Dictionary:
	var res := {}
	if not u.is_active():
		return res
	res[u.pos] = {"cost": 0.0, "prev": u.pos}
	var budget := u.move_allowance()
	var open: Array = [u.pos]
	while open.size() > 0:
		# 取当前代价最小的节点
		var best_i := 0
		for i in range(1, open.size()):
			if float(res[open[i]].cost) < float(res[open[best_i]].cost):
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		var base: float = res[cur].cost
		for n in Hex.neighbors(cur):
			if not is_passable(n) or not tiles.has(n):
				continue
			var occ := unit_at(n)
			if occ != null and occ != u:
				continue
			var step: float = terrain_at(n).cost
			var nc := base + step
			if nc > budget + 0.001:
				continue
			if not res.has(n) or nc < float(res[n].cost) - 0.001:
				res[n] = {"cost": nc, "prev": cur}
				if not open.has(n):
					open.append(n)
	return res

func path_to(u: WarUnit, dest: Vector2i) -> Array:
	var reach := reachable(u)
	if not reach.has(dest):
		return []
	var out := []
	var cur := dest
	var guard := 0
	while cur != u.pos and guard < 256:
		guard += 1
		out.push_front(cur)
		cur = reach[cur].prev
	return out

func try_move(u: WarUnit, dest: Vector2i) -> bool:
	var p := path_to(u, dest)
	if p.size() == 0:
		return false
	var cost := 0.0
	for h in p:
		cost += float(terrain_at(h).cost)
	u.pos = dest
	u.has_moved = true
	u.consume_stamina(cost * 2.2)
	if float(u.stamina) <= 0.0:
		_log("%s 筋疲力尽，跪在地上喘。" % u.unit_name)
	board_changed.emit()
	return true

# —— 行动 ——

func can_reach_target(attacker: WarUnit, target: WarUnit) -> bool:
	if attacker.weapon() == null:
		return false
	return Hex.distance(attacker.pos, target.pos) <= attacker.weapon().attack_range()

## 命中率：界面瞄准部位时显示，attack() 内部也用它，保证显示与实际一致。
func hit_chance(attacker: WarUnit, defender: WarUnit, part: String) -> int:
	if attacker.weapon() == null:
		return 0
	var wp := attacker.weapon()
	var dist := Hex.distance(attacker.pos, defender.pos)
	if dist > wp.attack_range():
		return 0
	var acc := attacker.base_accuracy() + float(wp.hit_bonus())
	acc += float(WarUnit.PART_HIT_MOD.get(part, 0.0))
	acc -= defender.evasion()
	acc -= float(terrain_at(defender.pos).cover)
	acc -= float(dist - 1) * 5.0
	acc += attacker.guard_bonus * 0.6
	if defender.routing:
		acc += 18.0
	if defender.defending:
		acc -= defender.defense_value() * 0.42
	return int(clampf(acc, 5.0, 95.0))

func attack(attacker: WarUnit, defender: WarUnit, part: String) -> Dictionary:
	var res := {"hit": false, "killed": false, "severed": false, "chance": 0, "damage": 0.0}
	if attacker.weapon() == null or not attacker.can_attack():
		_log("%s 已经无法挥动武器。" % attacker.unit_name)
		return res
	var wp := attacker.weapon()
	var dist := Hex.distance(attacker.pos, defender.pos)
	if dist > wp.attack_range():
		return res
	var acc := float(hit_chance(attacker, defender, part))
	res.chance = int(acc)

	var roll := randf() * 100.0
	var part_name: String = WarUnit.PART_NAMES[part]
	if roll > acc:
		_log("%s 劈向 %s 的%s —— 落空了。" % [attacker.unit_name, defender.unit_name, part_name])
		attacker.consume_stamina(7.0 + wp.weight() * 0.6)
		attacker.has_acted = true
		_resolve_panic(attacker, defender)
		return res

	res.hit = true
	var dmg := wp.damage() * (0.92 + float(attacker.might) * 0.024)
	dmg *= randf_range(0.86, 1.18)
	if attacker.is_severed("arm_l"):
		dmg *= 0.85
	if attacker.fatigue > 0:
		dmg *= 1.0 - 0.06 * float(attacker.fatigue)
	dmg *= attacker.status_damage_mult()
	dmg *= attacker.hand_damage_mult()
	# 被围攻时更容易被击中要害
	var ev: Dictionary = defender.take_hit(part, dmg, wp.damage_type())
	res.damage = float(ev.damage)
	res.killed = bool(ev.died)
	res.severed = bool(ev.severed)

	var verb := _verb_for(wp.pattern_id)
	var type_name := wp.damage_type_name()
	var tail := ""
	if bool(ev.get("blocked", false)):
		tail = "（未破甲！%s护甲 %.0f，只蹭掉 %.0f）" % [type_name, float(ev.armor), float(ev.damage)]
	elif ev.died:
		if part == "head" or part == "torso":
			tail = " —— %s 倒下了。" % defender.unit_name
		else:
			tail = "，%s的%s被斩断，血喷了一地。" % [defender.unit_name, part_name]
			tail += " —— 他倒下前就没气了。"
	elif ev.severed:
		tail = "，%s的%s被斩断！生命 -%.0f。" % [defender.unit_name, part_name,
			float(ev.get("burst", 0.0))]
	else:
		var vt := float(ev.get("vital", 0.0))
		if vt > 0.5:
			tail = "（%s · 护甲 %.0f，实际伤害 %.0f，生命 -%.0f）" % [type_name,
				float(ev.armor), float(ev.damage), vt]
		else:
			tail = "（%s · 护甲 %.0f，实际伤害 %.0f）" % [type_name,
				float(ev.armor), float(ev.damage)]
	_log("%s %s %s 的%s%s" % [attacker.unit_name, verb, defender.unit_name, part_name, tail])

	attacker.consume_stamina(9.0 + wp.weight() * 0.7)
	attacker.has_acted = true
	if ev.died:
		_on_death(defender, attacker)
	else:
		defender.adjust_morale(-4.0)
		if ev.severed:
			_log("%s 闷哼一声，血从断口喷出来，止都止不住。" % defender.unit_name)
			_spread_morale(defender.faction, -6.0, defender)
	_resolve_panic(attacker, defender)
	return res

func _verb_for(pid: String) -> String:
	match pid:
		"w_axe", "w_greatsword":
			return "劈开"
		"w_spear":
			return "刺向"
		"w_bow", "w_crossbow":
			return "射向"
		"w_club", "w_scythe":
			return "砸向"
		_:
			return "斩向"

func _resolve_panic(attacker: WarUnit, defender: WarUnit) -> void:
	if defender.dead or defender.routing:
		return
	if defender.morale <= 18.0 and not defender.morale_check():
		defender.routing = true
		_log("%s 扔下武器，转身就跑。" % defender.unit_name)
		_spread_morale(defender.faction, -5.0, defender)

func do_defend(u: WarUnit) -> void:
	u.defending = true
	u.consume_stamina(4.0)
	u.has_acted = true
	u.adjust_morale(3.0)
	_log("%s 稳住架势，把盾（或是别的什么）挡在身前。" % u.unit_name)
	board_changed.emit()

func do_rest(u: WarUnit) -> void:
	var gain := 40.0 + float(u.con - 10) * 1.2
	u.stamina = minf(u.stamina_max, float(u.stamina) + gain)
	u.adjust_morale(4.0)
	u.will = minf(u.will_max, float(u.will) + 3.0)
	if u.fatigue > 0 and randf() < 0.5:
		u.fatigue -= 1
	u.has_acted = true
	_log("%s 扶着膝盖喘气，恢复体力。" % u.unit_name)
	board_changed.emit()

func do_skip(u: WarUnit) -> void:
	u.skipped = true
	u.has_acted = true
	u.adjust_morale(2.0)
	_log("%s 按住阵脚，没有动作。" % u.unit_name)

func _on_death(u: WarUnit, killer: WarUnit = null) -> void:
	u.dead = true
	u.routing = false
	_log("%s 死了。" % u.unit_name)
	if killer != null:
		killer.adjust_morale(9.0)
		killer.will = minf(killer.will_max, float(killer.will) + 2.0)
	_spread_morale(u.faction, -12.0, u)
	board_changed.emit()

func _spread_morale(faction: int, delta: float, except: WarUnit) -> void:
	for u in units:
		if u == except or not u.is_active() or u.faction != faction:
			continue
		if Hex.distance(u.pos, except.pos) <= 4:
			u.adjust_morale(delta)

# —— 敌方 AI ——

func ai_act(u: WarUnit) -> void:
	if not u.is_active():
		return
	# 溃逃：尽量远离最近的敌人
	if u.routing:
		_flee(u)
		return
	if u.stamina <= 6.0:
		do_rest(u)
		return
	var target := _pick_target(u)
	if target == null:
		do_defend(u)
		return
	var rng := u.weapon().attack_range() if u.weapon() != null else 1
	var dist := Hex.distance(u.pos, target.pos)
	if dist > rng:
		_approach(u, target)
		dist = Hex.distance(u.pos, target.pos)
	if dist <= rng and u.can_attack() and u.stamina > 4.0:
		var part := _pick_part(u, target)
		attack(u, target, part)
	elif u.stamina > 12.0:
		do_defend(u)
	else:
		do_rest(u)

func _pick_target(u: WarUnit) -> WarUnit:
	var best: WarUnit = null
	var best_score := -1e9
	for o in units:
		if o.faction == u.faction or not o.is_active():
			continue
		var d := Hex.distance(u.pos, o.pos)
		var score := -float(d) * 3.0
		score += (1.0 - o.vitals_ratio()) * 22.0
		score += (1.0 - o.morale_ratio()) * 8.0
		if o.is_severed("arm_r") and o.is_severed("arm_l"):
			score += 12.0
		if o.bleeding > 0.0:
			score += 5.0
		if o.faction == 0:
			score += 2.0
		if score > best_score:
			best_score = score
			best = o
	return best

func _pick_part(u: WarUnit, t: WarUnit) -> String:
	var wp := u.weapon()
	var est := wp.damage() * (0.9 + float(u.might) * 0.024)
	var dtype := wp.damage_type()
	# 快死的敌人：直接打躯干
	if t.vitals_ratio() < 0.30:
		return "torso"
	# 能一击断掉的手脚/四肢：挑护甲薄、血少的
	var best := ""
	var best_score := -1e9
	for p in ["hand_r", "hand_l", "arm_r", "arm_l", "foot_l", "foot_r", "leg_l", "leg_r"]:
		if t.is_severed(p):
			continue
		if t.armor_need(p, dtype) > est * 0.95:
			continue
		if est * 0.85 < t.part_hp(p):
			continue
		var score := (1.0 - t.part_ratio(p)) * 20.0 - t.armor_of(p) * 1.2
		if p.begins_with("hand") or p.begins_with("foot"):
			score += 3.0
		if score > best_score:
			best_score = score
			best = p
	if best != "":
		return best
	# 打不动甲，就找身上没甲的地方，或稳打躯干
	var roll := randf()
	if roll < 0.55:
		return "torso"
	elif roll < 0.70:
		return "head"
	elif roll < 0.80:
		return "hand_r"
	elif roll < 0.90:
		return "leg_l"
	else:
		return "hand_l"

func _approach(u: WarUnit, target: WarUnit) -> void:
	var reach := reachable(u)
	# 用距离场而不是直线距离：直线会被湖湾和断壁卡住，距离场会绕路
	var field := _distance_field(target.pos)
	var best := u.pos
	var best_d: int = int(field.get(u.pos, 9999))
	for h in reach.keys():
		var d: int = int(field.get(h, 9999))
		if d < best_d:
			best_d = d
			best = h
	if best != u.pos:
		try_move(u, best)

## 从目标格向外做 BFS，得到全图"到目标的步数"。忽略单位，只看地形通不通。
func _distance_field(goal: Vector2i) -> Dictionary:
	var dist := {}
	if not tiles.has(goal) or not is_passable(goal):
		return dist
	dist[goal] = 0
	var open: Array = [goal]
	while not open.is_empty():
		var cur: Vector2i = open.pop_front()
		for n in Hex.neighbors(cur):
			if dist.has(n) or not tiles.has(n) or not is_passable(n):
				continue
			dist[n] = int(dist[cur]) + 1
			open.append(n)
	return dist

func _flee(u: WarUnit) -> void:
	var threat := _nearest_enemy(u)
	if threat == null:
		return
	var reach := reachable(u)
	var best := u.pos
	var best_d := Hex.distance(u.pos, threat.pos)
	for h in reach.keys():
		var d := Hex.distance(h, threat.pos)
		if d > best_d:
			best_d = d
			best = h
	if best != u.pos:
		try_move(u, best)

func _nearest_enemy(u: WarUnit) -> WarUnit:
	var best: WarUnit = null
	var bd := 999
	for o in units:
		if o.faction == u.faction or not o.is_active():
			continue
		var d := Hex.distance(u.pos, o.pos)
		if d < bd:
			bd = d
			best = o
	return best

# —— 战报 ——

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines.pop_front()
	logged.emit(s)

func log_text(n: int = 8) -> String:
	var start := maxi(0, log_lines.size() - n)
	var out: Array = []
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return "\n".join(out)

# —— 统计 ——

func faction_active(f: int) -> int:
	var n := 0
	for u in units:
		if u.is_active() and u.faction == f:
			n += 1
	return n

func attacker_side() -> Array:
	return units.filter(func(u): return u.faction == 0)

func enemy_side() -> Array:
	return units.filter(func(u): return u.faction == 1)
