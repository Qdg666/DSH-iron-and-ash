extends Node

## 全局游戏状态（自动加载单例）。存档、队伍、钱粮、日期、场景切换都经过这里。

signal scene_requested(kind: String, arg: Dictionary)
signal state_changed
signal notice(text: String)

var rng := RandomNumberGenerator.new()

var gold := 140
var food := 18
var day := 1
var node_id := "camp"
var party_pos := Vector2(-1.0, -1.0)   # 大地图上的自由位置；-1 表示还没初始化
var party: Array = []
var inventory: Array = []          # 团队背包：装备字典（Gear.to_dict）
var formation: Array = []          # 阵形：8 个槽位，存成员 id；行0..3 × 列0后排/1前排
var town_rep: Dictionary = {}      # 各据点好感
var shop_stock: Dictionary = {}    # 各据点市场库存 {week, items}
var flags := {}
var seen_events := {}
var resolve := 0.0        # 队伍累积的意志（影响下一场战斗的初始士气）
var battle_context := {}
var battle_members := {}
var last_result := {}
var run_seed := 0

const MAX_PARTY := 8
const INVENTORY_MAX := 30
const FORMATION_SLOTS := 8
const FOOD_PRICE := 3
const RECRUIT_COST := {"民兵": 45, "逃兵": 65, "弓箭手": 95, "雇佣兵": 130, "弩手": 150}
const RECRUITABLE := ["民兵", "逃兵", "弓箭手", "雇佣兵", "弩手"]

func _ready() -> void:
	rng.randomize()

# —— 新游戏 ——

func new_game(p_seed: int = 0) -> void:
	if p_seed == 0:
		p_seed = randi()
	run_seed = p_seed
	rng.seed = p_seed
	gold = 140
	food = 18
	day = 1
	node_id = "camp"
	party_pos = MapData.world_pos("camp") + Vector2(0, 56)
	flags.clear()
	seen_events.clear()
	resolve = 0.0
	last_result = {}
	party.clear()
	inventory.clear()
	formation.clear()
	town_rep.clear()
	shop_stock.clear()

	var leader := Gen.make_member("雇佣兵", rng, "罗兰·灰袍")
	leader["training"] = 2
	leader["skill"] = int(leader["skill"]) + 2
	leader["will"] = 52.0
	party.append(leader)
	party.append(Gen.make_member("民兵", rng))
	party.append(Gen.make_member("民兵", rng))
	party.append(Gen.make_member("弓箭手", rng))
	party.append(Gen.make_member("逃兵", rng))
	inventory.append(Gear.make("torso_jerkin", "leather", 0.7).to_dict())
	inventory.append(Gear.make("head_hood", "leather", 0.6).to_dict())
	inventory.append(Gear.make("w_spear", "iron", 0.6).to_dict())
	ensure_formation()
	state_changed.emit()

func alive_party() -> Array:
	var out := []
	for m in party:
		if not bool(m.get("dead", false)):
			out.append(m)
	return out

func party_size() -> int:
	return alive_party().size()

# —— 阵形（8 槽：行 0..3 × 列 0 后排 / 1 前排）——

func ensure_formation() -> void:
	var live := {}
	for m in alive_party():
		live[str(m.get("id", ""))] = m
	var out: Array = []
	for i in range(FORMATION_SLOTS):
		out.append("")
	var used := {}
	for i in range(mini(formation.size(), FORMATION_SLOTS)):
		var id := str(formation[i])
		if id != "" and live.has(id) and not used.has(id):
			out[i] = id
			used[id] = true
	for m in alive_party():
		var id := str(m.get("id", ""))
		if id == "" or used.has(id):
			continue
		for i in range(FORMATION_SLOTS):
			if out[i] == "":
				out[i] = id
				used[id] = true
				break
	formation = out

func formation_slot_of(m: Dictionary) -> int:
	ensure_formation()
	var id := str(m.get("id", ""))
	for i in range(formation.size()):
		if str(formation[i]) == id:
			return i
	return -1

func swap_formation(a: int, b: int) -> void:
	ensure_formation()
	if a < 0 or b < 0 or a >= FORMATION_SLOTS or b >= FORMATION_SLOTS or a == b:
		return
	var t = formation[a]
	formation[a] = formation[b]
	formation[b] = t
	state_changed.emit()

func ordered_party() -> Array:
	ensure_formation()
	var out: Array = []
	var ms := alive_party()
	for i in range(FORMATION_SLOTS):
		var id := str(formation[i])
		if id == "":
			continue
		for m in ms:
			if str(m.get("id", "")) == id and not out.has(m):
				out.append(m)
				break
	for m in ms:
		if not out.has(m):
			out.append(m)
	return out

## 与 ordered_party() 一一对应的阵形槽位（-1 表示没排进阵形）
func ordered_slots() -> Array:
	var out: Array = []
	var op := ordered_party()
	for m in op:
		out.append(formation_slot_of(m))
	return out

# —— 团队背包 ——

func add_item(d: Dictionary) -> bool:
	if inventory.size() >= INVENTORY_MAX:
		return false
	inventory.append(d)
	state_changed.emit()
	return true

func member_gear(m: Dictionary, slot: String) -> Dictionary:
	var gd = m.get("gear", {})
	if gd is Dictionary and gd.has(slot) and gd[slot] != null:
		return gd[slot]
	return {}

## 把背包里的装备给某个成员；换下来的旧装备回背包
func equip_item_to(m: Dictionary, item_index: int) -> Dictionary:
	if item_index < 0 or item_index >= inventory.size():
		return {"ok": false, "msg": "背包里没有这件东西。"}
	var d: Dictionary = inventory[item_index]
	var g := Gear.from_dict(d)
	var slot := g.slot()
	var gd = m.get("gear", {})
	if not (gd is Dictionary):
		gd = {}
	var old = gd.get(slot, null)
	gd[slot] = d
	m["gear"] = gd
	inventory.remove_at(item_index)
	if old != null:
		inventory.append(old)
	state_changed.emit()
	return {"ok": true, "slot": slot, "replaced": old != null, "name": g.display_name()}

func unequip_slot(m: Dictionary, slot: String) -> bool:
	var gd = m.get("gear", {})
	if not (gd is Dictionary) or not gd.has(slot) or gd[slot] == null:
		return false
	if inventory.size() >= INVENTORY_MAX:
		return false
	inventory.append(gd[slot])
	gd.erase(slot)
	m["gear"] = gd
	state_changed.emit()
	return true

# —— 城镇与市场 ——

func rep_of(node_id: String) -> int:
	return int(town_rep.get(node_id, 0))

func add_rep(node_id: String, n: int) -> void:
	town_rep[node_id] = clampi(rep_of(node_id) + n, 0, 20)

func shop_discount(node_id: String) -> float:
	return minf(0.15, float(rep_of(node_id)) * 0.01)

func buy_price(node_id: String, d: Dictionary) -> int:
	var g := Gear.from_dict(d)
	return maxi(5, int(round(float(g.value()) * (1.0 - shop_discount(node_id)))))

func sell_price(d: Dictionary) -> int:
	return maxi(3, int(round(float(Gear.from_dict(d).value()) * 0.5)))

func _shop_tier(node_id: String) -> int:
	var t := str(MapData.node(node_id).get("type", ""))
	match t:
		"capital": return 3
		"town", "abbey", "outpost": return 2
		"ford", "village", "lumber", "den": return 1
		_: return 0

## 市场库存：按据点生成，每 7 天换一批
func shop_items(node_id: String) -> Array:
	var week := int(day / 7)
	var s = shop_stock.get(node_id, null)
	if s != null and int(s.get("week", -1)) == week:
		return s.get("items", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s@%d" % [node_id, week])
	var arr: Array = []
	var tier := _shop_tier(node_id)
	for i in range(rng.randi_range(5, 7)):
		arr.append(Gear.random_piece(tier, rng).to_dict())
	var entry := {"week": week, "items": arr}
	shop_stock[node_id] = entry
	return arr

func buy_shop_item(node_id: String, index: int) -> Dictionary:
	var arr := shop_items(node_id)
	if index < 0 or index >= arr.size():
		return {"ok": false, "msg": "货架上没有这件。"}
	if inventory.size() >= INVENTORY_MAX:
		return {"ok": false, "msg": "背包塞满了。"}
	var d: Dictionary = arr[index]
	var price := buy_price(node_id, d)
	if gold < price:
		return {"ok": false, "msg": "钱不够。"}
	gold -= price
	arr.remove_at(index)
	inventory.append(d)
	add_rep(node_id, 1)
	state_changed.emit()
	return {"ok": true, "price": price, "name": Gear.from_dict(d).display_name()}

func sell_inventory_item(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok": false}
	var d: Dictionary = inventory[index]
	var price := sell_price(d)
	inventory.remove_at(index)
	gold += price
	state_changed.emit()
	return {"ok": true, "price": price, "name": Gear.from_dict(d).display_name()}

func power() -> float:
	var p := 0.0
	for m in alive_party():
		p += Gen.member_power(m)
	return p / 12.0

func daily_food() -> int:
	return maxi(1, int(ceil(float(party_size()) / 4.0)))

# —— 时间与补给 ——

func advance_days(n: int) -> Array:
	var notes: Array = []
	for _i in range(n):
		day += 1
		var need := daily_food()
		food -= need
		if food < 0:
			food = 0
			for m in alive_party():
				m["cond"] = clampf(float(m.get("cond", 1.0)) - 0.06, 0.1, 1.0)
			resolve = maxf(0.0, resolve - 2.0)
			notes.append("没有吃的了。有人开始啃皮带。")
		# 缓慢愈合
		for m in alive_party():
			m["cond"] = clampf(float(m.get("cond", 1.0)) + 0.015, 0.1, 1.0)
	# 士气倾向回归
	resolve = clampf(resolve - 0.3 * float(n), 0.0, 40.0)
	state_changed.emit()
	return notes

func heal_all(amount: float) -> void:
	for m in alive_party():
		m["cond"] = clampf(float(m.get("cond", 1.0)) + amount, 0.1, 1.0)
	state_changed.emit()

func rest() -> void:
	advance_days(1)
	heal_all(0.14)
	resolve = clampf(resolve + 1.0, 0.0, 40.0)
	notice.emit("你们休整了一夜。有人守夜，有人梦见家里。")

func spend_gold(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	state_changed.emit()
	return true

func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)
	state_changed.emit()

func buy_food(n: int) -> bool:
	var cost := n * FOOD_PRICE
	if not spend_gold(cost):
		return false
	food += n
	state_changed.emit()
	return true

func recruit(arch: String) -> bool:
	if party_size() >= MAX_PARTY:
		notice.emit("队伍已经太长了。再多的人，你连名字都记不住。")
		return false
	var cost: int = int(RECRUIT_COST.get(arch, 100))
	if not spend_gold(cost):
		notice.emit("钱不够。")
		return false
	party.append(Gen.make_member(arch, rng))
	ensure_formation()
	notice.emit("一个%s加入了队伍。" % arch)
	state_changed.emit()
	return true

# —— 事件 ——

func take_event(id: String) -> Dictionary:
	var ev: Dictionary = EventData.get_event(id)
	if ev.is_empty():
		return {}
	if bool(ev.get("once", false)) and seen_events.has(id):
		return {"blocked": true, "text": "这里已经没有别的了。"}
	seen_events[id] = true
	return ev

func apply_effects(effects: Dictionary) -> String:
	var lines: Array = []
	if effects.has("gold"):
		var g := int(effects["gold"])
		if g >= 0:
			add_gold(g)
			lines.append("金币 +%d" % g)
		else:
			spend_gold(-g)
			lines.append("金币 %d" % g)
	if effects.has("food"):
		var f := int(effects["food"])
		food = maxi(0, food + f)
		lines.append("口粮 %+d" % f)
	if effects.has("morale"):
		resolve = clampf(resolve + float(effects["morale"]), 0.0, 40.0)
		lines.append("士气 %+d" % int(effects["morale"]))
	if effects.has("will"):
		resolve = clampf(resolve + float(effects["will"]) * 0.5, 0.0, 40.0)
	if effects.has("heal"):
		heal_all(float(effects["heal"]))
		lines.append("伤情好转")
	if effects.has("hurt"):
		for m in alive_party():
			m["cond"] = clampf(float(m.get("cond", 1.0)) - float(effects["hurt"]), 0.1, 1.0)
		lines.append("队伍受了伤")
	if effects.has("recruit"):
		var arch := str(effects["recruit"])
		party.append(Gen.make_member(arch, rng))
		ensure_formation()
		lines.append("获得兵员：%s" % arch)
	if effects.has("flag"):
		flags[str(effects["flag"])] = true
	if effects.has("log"):
		lines.append(str(effects["log"]))
	state_changed.emit()
	return "　".join(lines)

# —— 战斗 ——

func start_battle(kind: String, title: String = "", scale: float = 1.0) -> void:
	battle_context = {"kind": kind, "title": title, "scale": scale}
	scene_requested.emit("battle", battle_context)

func build_battle() -> Battle:
	var b := Battle.new(rng.randi())
	b.generate(rng)
	# 测试模式可以限制参战人数（test_size=2 即 2v2）
	var limit: int = int(battle_context.get("test_size", 0))
	ensure_formation()
	var members: Array = ordered_party()
	var slot_ids: Array = ordered_slots()
	if limit > 0:
		members = members.slice(0, mini(limit, members.size()))
		slot_ids = slot_ids.slice(0, mini(limit, slot_ids.size()))
	var punits: Array = []
	battle_members.clear()
	for m in members:
		var u: WarUnit = Gen.from_member(m, 0)
		u.morale = clampf(float(u.morale) + resolve * 0.8, 0.0, float(u.morale_max))
		u.will = clampf(float(u.will) + resolve * 0.6, 0.0, float(u.will_max))
		punits.append(u)
		battle_members[u] = m
	var scale: float = float(battle_context.get("scale", 1.0))
	var eparty := Gen.make_enemy_party(day, power() * scale, rng)
	if limit > 0:
		eparty = eparty.slice(0, mini(limit, eparty.size()))
	b.deploy(punits, eparty, slot_ids)
	return b

## 结算战斗：写回伤势、阵亡、掠夺。
func resolve_battle(b: Battle, winner: int) -> Dictionary:
	var dead_names: Array = []
	var wounded := 0
	for u in b.units:
		if u.faction != 0:
			continue
		var m = battle_members.get(u, null)
		if m == null:
			continue
		Gen.write_back(m, u)
		if u.dead:
			dead_names.append(u.unit_name)
		elif u.vitals_ratio() < 0.6:
			wounded += 1
	# 移除阵亡者
	var kept: Array = []
	for m in party:
		if bool(m.get("dead", false)) and dead_names.has(str(m.get("name", ""))):
			continue
		kept.append(m)
	party = kept
	ensure_formation()

	var loot_gold := 0
	var loot_food := 0
	if winner == 0:
		loot_gold = 25 + int(rng.randi_range(0, 15)) + day * 2
		loot_food = int(rng.randi_range(1, 4))
		gold += loot_gold
		food += loot_food
		resolve = clampf(resolve + 4.0, 0.0, 40.0)
		flags["cleared_%s" % str(battle_context.get("kind", "fight"))] = true
	else:
		resolve = maxf(0.0, resolve - 8.0)

	var res := {
		"winner": winner,
		"dead": dead_names,
		"wounded": wounded,
		"gold": loot_gold,
		"food": loot_food,
	}
	last_result = res
	state_changed.emit()
	return res

# —— 存档 ——

func to_dict() -> Dictionary:
	return {
		"gold": gold, "food": food, "day": day, "node": node_id,
		"pos": [party_pos.x, party_pos.y],
		"party": party, "flags": flags, "seen": seen_events,
		"inventory": inventory, "formation": formation,
		"rep": town_rep, "shop": shop_stock,
		"resolve": resolve, "seed": run_seed,
	}

func from_dict(d: Dictionary) -> void:
	gold = int(d.get("gold", 100))
	food = int(d.get("food", 10))
	day = int(d.get("day", 1))
	node_id = str(d.get("node", "camp"))
	var p: Array = d.get("pos", [])
	if p.size() >= 2:
		party_pos = Vector2(float(p[0]), float(p[1]))
	else:
		party_pos = MapData.world_pos(node_id)
	party = d.get("party", [])
	inventory = d.get("inventory", [])
	formation = d.get("formation", [])
	town_rep = d.get("rep", {})
	shop_stock = d.get("shop", {})
	# 老存档的成员没有 id：补一个，阵形才认得人
	for m in party:
		if not m.has("id"):
			m["id"] = "m%d" % randi()
	flags = d.get("flags", {})
	seen_events = d.get("seen", {})
	resolve = float(d.get("resolve", 0.0))
	run_seed = int(d.get("seed", 0))
	ensure_formation()
	state_changed.emit()

func save_game() -> bool:
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true

func has_save() -> bool:
	return FileAccess.file_exists("user://save.json")

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	from_dict(d)
	return true
