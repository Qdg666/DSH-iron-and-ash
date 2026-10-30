extends Control

## 主场景：负责全局主题、视图切换与开发期的截图自检。

const VIEW_MENU := preload("res://脚本/视图/主菜单.gd")
const VIEW_MAP := preload("res://脚本/视图/大地图.gd")
const VIEW_BATTLE := preload("res://脚本/视图/战斗场景.gd")

var 当前视图: Node = null

func _ready() -> void:
	Ui.setup(get_tree().root)
	Game.scene_requested.connect(_on_scene_requested)
	_show_menu()
	_try_screenshot_mode()

# —— 视图切换 ——

func _switch(script: Script, arg: Dictionary = {}) -> void:
	if 当前视图 != null:
		remove_child(当前视图)
		当前视图.queue_free()
		当前视图 = null
	var v: Node = script.new()
	if v is Control:
		(v as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	当前视图 = v
	if v.has_method("setup"):
		v.call("setup", arg)

func _show_menu() -> void:
	_switch(VIEW_MENU)

func _show_map(arg: Dictionary = {}) -> void:
	_switch(VIEW_MAP, arg)

func _show_battle(ctx: Dictionary) -> void:
	_switch(VIEW_BATTLE, ctx)

func _on_scene_requested(kind: String, arg: Dictionary) -> void:
	match kind:
		"menu":
			_show_menu()
		"map":
			_show_map(arg)
		"battle":
			_show_battle(arg)

# —— 截图自检（开发用）——
# 用法：godot --path . -- --shot=menu|map|battle [--shotdir=D:/dir]

func _try_screenshot_mode() -> void:
	var target := ""
	var dir := ""
	var wait := 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			target = a.substr(7)
		elif a.begins_with("--shotdir="):
			dir = a.substr(10)
		elif a.begins_with("--shotwait="):
			wait = float(a.substr(11))
	if target == "":
		return
	if dir == "":
		dir = "user://"
	if not dir.ends_with("/"):
		dir += "/"
	match target:
		"map":
			Game.new_game(20251026)
			_on_scene_requested("map", {})
		"battle":
			Game.new_game(20251026)
			Game.battle_context = {"kind": "bandit", "title": "匪巢", "scale": 1.0}
			_on_scene_requested("battle", Game.battle_context)
		"battletest":
			# 开发用：2v2 自动打完整场，验证移动/攻击/AI/结算
			print("BATTLETEST_START")
			Game.new_game(20251026)
			Game.battle_context = {"kind": "bandit", "title": "匪巢", "scale": 1.0, "test_size": 2}
			_on_scene_requested("battle", Game.battle_context)
			return
		"town":
			Game.new_game(20251026)
			Game.node_id = "town"
			_on_scene_requested("map", {})
		_:
			pass
	for _i in range(4):
		await get_tree().process_frame
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir + "shot_%s.png" % target
	var err := img.save_png(path)
	print("SHOT_SAVED:", path, " err=", err)
	get_tree().quit()
