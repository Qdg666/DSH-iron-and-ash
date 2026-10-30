extends SceneTree

## 无界面逻辑自检：让双方都由 AI 代打，跑到分出胜负，检查规则是否有崩溃或死循环。
## 另外检查：头/躯干归零即死、断肢爆发与大出血状态、状态衰减。
## 运行：godot --headless --path . --script res://测试/逻辑自检.gd

func _init() -> void:
	print("=== 逻辑自检开始 ===")
	seed(20251026)   # 固定全局随机，保证每次跑的战场一致
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251026
	var failures := 0

	for trial in range(3):
		var b := Battle.new(trial + 1)
		b.generate(rng)
		var p: Array = []
		for i in range(2):
			p.append(Gen.make_unit(["雇佣兵", "弓箭手"][i], 0, rng, "测试%d" % i))
		var e := Gen.make_enemy_party(2 + trial * 4, 1.0 + float(trial) * 0.4, rng)
		e = e.slice(0, 2)
		b.deploy(p, e)
		var guard := 0
		while b.winner < 0 and guard < 600:
			guard += 1
			var u: WarUnit = b.current
			if u == null:
				break
			b.ai_act(u)
			b.end_unit_turn()
		var dead := 0
		for u in b.units:
			if u.dead:
				dead += 1
		print("[%d] 胜负=%d 回合=%d 循环=%d 战报=%d 阵亡=%d" % [
			trial, b.winner, b.round_no, guard, b.log_lines.size(), dead])
		if b.winner < 0:
			failures += 1
			print("  !! 战斗没有结束（可能是死循环）")
		# 抽样打印几条战报
		var n := mini(8, b.log_lines.size())
		for i in range(n):
			print("  · ", b.log_lines[b.log_lines.size() - n + i])

	# 六边形数学自检
	var a := Vector2i(0, 0)
	var bb := Vector2i(5, 0)
	assert(Hex.distance(a, bb) == 5)
	assert(Hex.distance(a, Vector2i(0, 4)) == 4)
	assert(Hex.distance(Vector2i(1, 0), Vector2i(0, 1)) == 1)
	var px := Hex.to_pixel(Vector2i(3, 2))
	var back := Hex.from_pixel(px)
	print("像素往返：", Vector2i(3, 2), " -> ", px, " -> ", back)
	assert(back == Vector2i(3, 2))
	var path := Hex.line(Vector2i(0, 0), Vector2i(4, -2))
	print("直线格子数：", path.size())

	# 装备自检
	var g := Gear.make("torso_plate", "steel", 0.9)
	print("装备：", g.display_name(), " 护甲=", g.armor(), " 重量=", g.weight(), " 颜色=", g.color())
	var w := Gear.make("w_greatsword", "meteor", 0.8)
	print("武器：", w.display_name(), " 伤害=", w.damage(), " 命中=", w.hit_bonus(), " 射程=", w.attack_range())

	# 成员往返
	var m := Gen.make_member("雇佣兵", rng)
	var u2 := Gen.from_member(m, 0)
	print("成员→单位：", u2.unit_name, " 训练=", u2.training_name(), " 整体血量=", u2.vitals)
	Gen.write_back(m, u2)
	print("写回 cond=", m["cond"])

	# —— 部位致死规则 ——
	var r2 := RandomNumberGenerator.new()
	r2.seed = 777

	var torso_u := Gen.make_unit("雇佣兵", 0, r2, "躯干试刀")
	torso_u.take_hit("torso", 60.0)
	print("躯干归零：dead=", torso_u.dead, " 躯干=", torso_u.part_hp("torso"))
	if not torso_u.dead:
		failures += 1
		print("  !! 躯干归零没有致死")

	var head_u := Gen.make_unit("民兵", 0, r2, "头部试刀")
	head_u.take_hit("head", 60.0)
	print("头部归零：dead=", head_u.dead, " 头部=", head_u.part_hp("head"))
	if not head_u.dead:
		failures += 1
		print("  !! 头部归零没有致死")

	# —— 断肢：立即掉 20% 生命 + 大出血/剧痛状态 ——
	var sev_u := Gen.make_unit("雇佣兵", 0, r2, "断臂试刀")
	sev_u.parts["arm_l"].hp = 5.0
	var v0: float = sev_u.vitals
	var acc0: float = sev_u.base_accuracy()
	var ev := sev_u.take_hit("arm_l", 24.0)
	var burst: float = v0 - sev_u.vitals
	print("断肢：severed=%s 爆发掉血=%.1f (上限 %.1f 的 20%% = %.1f)" % [
		str(sev_u.is_severed("arm_l")), burst, sev_u.vitals_max, sev_u.vitals_max * 0.2])
	print("  状态=", sev_u.status_names(), " 命中 %.1f -> %.1f" % [acc0, sev_u.base_accuracy()])
	if not sev_u.is_severed("arm_l"):
		failures += 1
		print("  !! 手臂没有被斩断")
	if not sev_u.has_status("bleed_heavy"):
		failures += 1
		print("  !! 断肢没有挂上大出血")
	if absf(burst - sev_u.vitals_max * 0.2) > 1.0:
		failures += 1
		print("  !! 断肢爆发伤害不是 20%% 上限")
	if sev_u.base_accuracy() >= acc0:
		failures += 1
		print("  !! 大出血没有降低命中")

	# —— 状态每回合掉血与过期 ——
	var v1: float = sev_u.vitals
	var st: Dictionary = sev_u.tick_statuses()
	print("状态结算：掉血=%.1f 剩 %d 个状态，生命 %.0f -> %.0f" % [
		float(st.get("damage", 0.0)), sev_u.statuses.size(), v1, sev_u.vitals])
	if sev_u.vitals >= v1:
		failures += 1
		print("  !! 大出血没有每回合掉血")
	for _i in range(8):
		sev_u.tick_statuses()
	print("八回合后状态：", sev_u.statuses.size(), " 个")
	if not sev_u.statuses.is_empty():
		failures += 1
		print("  !! 状态没有过期")

	# —— 十部位：各部位护甲不同 ——
	var ap := Gen.make_unit("雇佣兵", 0, r2, "护甲试验")
	ap.gear["head"] = Gear.make("head_helm", "iron", 1.0)
	ap.gear["torso"] = Gear.make("torso_hauberk", "iron", 1.0)
	ap.gear["arms"] = Gear.make("arms_iron", "iron", 1.0)
	ap.gear["hands"] = Gear.make("hands_leather", "leather", 1.0)
	ap.gear["legs"] = Gear.make("legs_iron", "iron", 1.0)
	ap.gear["feet"] = Gear.make("feet_boots", "leather", 1.0)
	print("部位护甲：头 %.1f / 躯 %.1f / 臂 %.1f / 手 %.1f / 腿 %.1f / 脚 %.1f" % [
		ap.armor_of("head"), ap.armor_of("torso"), ap.armor_of("arm_r"),
		ap.armor_of("hand_r"), ap.armor_of("leg_r"), ap.armor_of("foot_r")])
	if ap.armor_of("hand_r") >= ap.armor_of("arm_r"):
		failures += 1
		print("  !! 手的护甲没有低于手臂")
	if ap.armor_of("foot_r") >= ap.armor_of("leg_r"):
		failures += 1
		print("  !! 脚的护甲没有低于腿")

	# —— 分类型护甲：斩 / 刺 / 钝 ——
	var tank_s := Gen.make_unit("重装步兵", 0, r2, "甲斩")
	var tank_p := Gen.make_unit("重装步兵", 0, r2, "甲刺")
	var tank_b := Gen.make_unit("重装步兵", 0, r2, "甲钝")
	for tank in [tank_s, tank_p, tank_b]:
		tank.gear["torso"] = Gear.make("torso_plate", "steel", 1.0)
	var e_s: Dictionary = tank_s.take_hit("torso", 30.0, "slash")
	var e_p: Dictionary = tank_p.take_hit("torso", 30.0, "pierce")
	var e_b: Dictionary = tank_b.take_hit("torso", 30.0, "blunt")
	print("板甲吃 30 点伤害：斩=%.1f 刺=%.1f 钝=%.1f（护甲 %.1f）" % [
		float(e_s["damage"]), float(e_p["damage"]), float(e_b["damage"]),
		tank_s.armor_of("torso")])
	if not (float(e_s["damage"]) < float(e_p["damage"]) and float(e_p["damage"]) < float(e_b["damage"])):
		failures += 1
		print("  !! 三种伤害类型的护甲减免没有拉开差距")

	# —— 破甲门槛：6 点斩击打板甲应当破不了甲 ——
	var weak := Gen.make_unit("重装步兵", 0, r2, "轻击试验")
	weak.gear["torso"] = Gear.make("torso_plate", "steel", 1.0)
	var wv: Dictionary = weak.take_hit("torso", 6.0, "slash")
	print("6 点斩击打板甲：blocked=%s 伤害=%.1f 需要=%.1f" % [
		str(wv["blocked"]), float(wv["damage"]), weak.armor_need("torso", "slash")])
	if not bool(wv["blocked"]):
		failures += 1
		print("  !! 轻伤害没有被重甲挡住")

	# —— 手伤降命中/攻击力，脚伤降移动 ——
	var lim := Gen.make_unit("雇佣兵", 0, r2, "手脚试验")
	var acc_full: float = lim.base_accuracy()
	var dmgm_full: float = lim.hand_damage_mult()
	var mv_full: float = lim.move_allowance()
	lim.parts["hand_r"].hp = float(lim.parts["hand_r"]["max"]) * 0.20
	lim.parts["foot_l"].hp = float(lim.parts["foot_l"]["max"]) * 0.20
	var acc_hurt: float = lim.base_accuracy()
	print("手伤：命中 %.1f -> %.1f，伤害倍率 %.2f -> %.2f" % [
		acc_full, acc_hurt, dmgm_full, lim.hand_damage_mult()])
	print("脚伤：移动 %.2f -> %.2f，闪避受牵连" % [mv_full, lim.move_allowance()])
	if acc_hurt >= acc_full:
		failures += 1
		print("  !! 手伤没有降低命中")
	if lim.hand_damage_mult() >= dmgm_full:
		failures += 1
		print("  !! 手伤没有降低攻击力")
	if lim.move_allowance() >= mv_full:
		failures += 1
		print("  !! 脚伤没有降低移动")

	# —— 背包 / 交易 / 阵形 ——
	var GameScript = load("res://脚本/核心/游戏.gd")
	var gm = GameScript.new()
	gm.new_game(4242)
	gm.gold = 500
	print("开局背包：", gm.inventory.size(), " 件，阵形槽：", gm.formation.size())
	if gm.inventory.size() < 1:
		failures += 1
		print("  !! 开局背包是空的")
	var man: Dictionary = gm.alive_party()[0]
	var bag_before: int = gm.inventory.size()
	var res_eq: Dictionary = gm.equip_item_to(man, 0)
	print("装备背包第 0 件：ok=%s 部位=%s 背包 %d -> %d" % [
		str(res_eq.get("ok", false)), str(res_eq.get("slot", "")), bag_before, gm.inventory.size()])
	var slot_used := str(res_eq.get("slot", ""))
	if not bool(res_eq.get("ok", false)) or gm.member_gear(man, slot_used).is_empty():
		failures += 1
		print("  !! 从背包装备没有生效")
	if not gm.unequip_slot(man, slot_used):
		failures += 1
		print("  !! 卸下装备失败")

	var inv_before: int = gm.inventory.size()
	var stock: Array = gm.shop_items("town")
	if stock.is_empty():
		failures += 1
		print("  !! 市场没有库存")
	var gold_before: int = gm.gold
	var price: int = gm.buy_price("town", stock[0])
	var res_buy: Dictionary = gm.buy_shop_item("town", 0)
	print("市场买入：%s 价格 %d 金币 %d -> %d 背包 %d -> %d" % [
		str(res_buy.get("name", "")), price, gold_before, gm.gold, inv_before, gm.inventory.size()])
	if not bool(res_buy.get("ok", false)) or gm.gold != gold_before - price:
		failures += 1
		print("  !! 买入金币结算不对")
	var gold2: int = gm.gold
	var res_sell: Dictionary = gm.sell_inventory_item(gm.inventory.size() - 1)
	if not bool(res_sell.get("ok", false)) or gm.gold <= gold2:
		failures += 1
		print("  !! 卖出没有给钱")
	print("市场好感：", gm.rep_of("town"), " 折扣 ", gm.shop_discount("town"))

	var op: Array = gm.ordered_party()
	var slots: Array = gm.ordered_slots()
	print("阵形：", gm.formation, " 出场顺序槽位 ", slots)
	if op.size() != gm.alive_party().size() or slots.size() != op.size():
		failures += 1
		print("  !! 阵形出场顺序数量不对")
	var id0 := str(gm.formation[0])
	var id1 := str(gm.formation[1])
	gm.swap_formation(0, 1)
	if str(gm.formation[0]) != id1 or str(gm.formation[1]) != id0:
		failures += 1
		print("  !! 阵形换位失败")

	# 阵形是否真的影响战斗初始站位：槽 0 后排、槽 1 前排
	gm.battle_context = {"kind": "bandit", "scale": 1.0, "test_size": 2}
	var bt: Battle = gm.build_battle()
	var pu: Array = bt.attacker_side()
	if pu.size() >= 2:
		var col0: int = bt._col_of(pu[0].pos)
		var col1: int = bt._col_of(pu[1].pos)
		print("阵形部署：%s 列=%d，%s 列=%d（0 后排 / 1 前排）" % [
			pu[0].unit_name, col0, pu[1].unit_name, col1])
		if col0 != 0 or col1 != 1:
			failures += 1
			print("  !! 阵形没有映射到战斗初始列")
	else:
		failures += 1
		print("  !! 阵形部署人数不对")

	# —— 大地图几何 ——
	var camp: Vector2 = MapData.world_pos("camp")
	var town: Vector2 = MapData.world_pos("town")
	print("大地图：营地=", camp, " 铁砧镇=", town, " 世界尺寸=", MapData.WORLD_SIZE)
	if MapData.nearest_node(camp, 30.0) != "camp":
		failures += 1
		print("  !! 营地附近找不到营地")
	if MapData.nearest_node(Vector2(100, 100), 60.0) != "":
		failures += 1
		print("  !! 荒野处误报据点")
	var road_d: float = MapData.distance_to_road((camp + town) * 0.5)
	print("营地与镇之间中点离道路：", road_d)
	if road_d > 40.0:
		failures += 1
		print("  !! 道路距离计算异常")
	var cw: Vector2 = MapData.clamp_world(Vector2(-50, 99999))
	if cw.x != 24.0:
		failures += 1
		print("  !! 世界边界钳制异常")

	print("=== 自检结束，失败项：%d ===" % failures)
	quit(1 if failures > 0 else 0)
