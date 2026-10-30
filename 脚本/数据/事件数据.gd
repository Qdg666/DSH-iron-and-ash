extends RefCounted
class_name EventData

## 事件：一段文字，加几个选项。选项的效果用字典描述，由 游戏.gd 统一结算。
## effects 支持的键：gold / food / morale / heal / hurt / recruit / flag / battle / log

const EVENTS := {
	"ashes": {
		"title": "灰烬里的两个人",
		"text": "村口的灰堆里有两个人形。一个还在动，另一个不动了。\n动着的那只手举起来，掌心朝上，像是在讨，又像是在指给你看什么。",
		"once": true,
		"choices": [
			{
				"label": "把口粮分给他们。",
				"effects": {"food": -3, "morale": 8, "heal": 0.05, "log": "队伍里没人说话，但脚步比刚才齐了一点。"},
				"result": "孩子们吃得很慢，先把面包掰成两半，一半塞进死人的嘴里。\n你队伍里的人看了很久。有人转过脸去。",
			},
			{
				"label": "问他们知不知道匪巢的路。",
				"effects": {"gold": 5, "flag": "knows_den", "morale": -3, "log": "你记下了匪巢附近的水源和哨位。"},
				"result": "他们知道。他们原来就住在那儿——在匪徒来之前，那里叫「下磨坊」。",
			},
			{
				"label": "走开。",
				"effects": {"morale": -6, "will": -3, "log": "身后那只手举了很久，然后放下了。"},
				"result": "你们踩着灰走过去。灰是热的，底下还有火。",
			},
		],
	},
	"bounty": {
		"title": "悬赏",
		"text": "镇公所的墙上钉着一张纸。上面画的不是匪首，是一个断手的人。\n赏金三百，落款是教会的印章。\n\n旁边有个抱孩子的女人在看，看了一会儿，把纸撕下来揣进怀里。",
		"once": true,
		"choices": [
			{
				"label": "揭下悬赏，去领赏钱。",
				"require": {"gold": 0},
				"effects": {"gold": 60, "morale": -10, "flag": "bounty_taken", "log": "你领了赏钱。队伍里没人问你人是怎么断的手。"},
				"result": "领赏的窗口后面坐着个文书，他数钱数得很慢，每一枚都在桌上敲一下。\n走出镇公所的时候，你的手在抖。",
			},
			{
				"label": "把悬赏换成给匪巢的假情报。",
				"require": {"gold": 20},
				"effects": {"gold": -20, "flag": "fake_intel", "morale": 4, "log": "匪巢的哨位换到了西侧，你记住了。"},
				"result": "你花钱买通了一个信差。三天后，匪徒会在西边的林子里白等一夜。",
			},
			{
				"label": "什么也不做。",
				"effects": {"morale": 2},
				"result": "你们在镇上吃了一顿热的东西。汤里有一小块肉，没人问那是什么肉。",
			},
		],
	},
	"forest": {
		"title": "林子里的东西",
		"text": "伐木工说林子深处有钟声。\n他们说这一带没有教堂。他们说钟是从地底下响的。\n\n天黑以后，你们听见了。",
		"once": true,
		"choices": [
			{
				"label": "派人去看。",
				"effects": {"hurt": 0.15, "gold": 40, "morale": -5, "log": "你们从土里挖出一口钟，和半截还挂在绳上的手。"},
				"result": "钟是好的，铜的，能在镇上换四十枚银币。\n绳子上的那只手，手指头全都朝里弯着，像在抓什么。",
			},
			{
				"label": "烧掉伐木场的棚屋，天亮就走。",
				"effects": {"food": -2, "morale": 5, "log": "火光烧了一夜，钟声停了。"},
				"result": "钟声停了。伐木工看着火光，谁也没拦你们。\n有个老工人说：这林子早该烧了。",
			},
		],
	},
	"ferry": {
		"title": "不收钱的摆渡人",
		"text": "老头没有拦你们。他只是伸手指了指桥，然后说：\n\n「过去的人，回来的时候少一个。这是规矩。」",
		"once": true,
		"choices": [
			{
				"label": "问他这规矩是谁定的。",
				"effects": {"gold": -15, "will": 6, "morale": 4, "log": "老头收下钱，说了句：「定的那个人，早就过去了。」"},
				"result": "他收了钱，把桥板一块一块摸过去，像是在数。\n「定的那个人，早就过去了。」他说。「他也没回来。」",
			},
			{
				"label": "什么也不问，直接过桥。",
				"effects": {"morale": -4, "log": "过桥的时候，桥板底下有东西跟着走了很久。"},
				"result": "桥下传来水声，水声里夹着脚步声。等你们上了岸，脚步声才停。",
			},
		],
	},
	"sermon": {
		"title": "第七次钟声",
		"text": "修道院里很冷。修士们跪在长凳上，没有人抬头。\n布道的内容是：刀剑有罪，饥荒是罚，忍耐是德。\n\n布道结束，管事修士走过来，问你们要不要捐一笔钱，为死者赎罪。",
		"once": false,
		"choices": [
			{
				"label": "捐钱。",
				"require": {"gold": 25},
				"effects": {"gold": -25, "morale": 6, "will": 4, "log": "钟声里，你觉得肩上轻了一点。"},
				"result": "修士在你的额头上抹了一点油。油是凉的，带着一股旧羊毛的味道。",
			},
			{
				"label": "问他们墙下新翻的土埋的是谁。",
				"effects": {"morale": -8, "will": 8, "flag": "abbey_doubt", "log": "没有人回答。但那天晚上，有两个修士跑了。"},
				"result": "管事修士笑了。他说：都是兄弟。\n当天夜里，修道院少了两个人。院门是从里面打开的。",
			},
			{
				"label": "离开。",
				"effects": {},
				"result": "你们走出院门。钟还在响，第七次，或者是第八次。",
			},
		],
	},
	"levy": {
		"title": "征召令",
		"text": "哨长把一张纸拍在桌上，酒气喷到你脸上。\n\n「上面要人。你们既然在这里，就算你们了。」\n他顿了顿，又补了一句：「当然，也可以谈谈。」",
		"once": true,
		"choices": [
			{
				"label": "谈。给钱，让我们走。",
				"require": {"gold": 50},
				"effects": {"gold": -50, "log": "哨长收了钱，把名单上的名字划掉了两个。"},
				"result": "他划名字的时候手很稳，像是做过很多次。",
			},
			{
				"label": "答应替他清剿匪巢。",
				"effects": {"flag": "levy_oath", "morale": 5, "gold": 30, "log": "哨长先付了一半的钱。他说另一半等你们回来。"},
				"result": "他数出三十枚银币，推到你面前。「回来再给另一半。」\n他没有说如果回不来。",
			},
			{
				"label": "拔出武器。",
				"effects": {"morale": -5, "will": -4, "flag": "outpost_hostile", "log": "你们走的时候，哨所里没有人抬头。"},
				"result": "哨长举起手，示意手下别动。\n「随你。」他说。「反正都是要死的人。」",
			},
		],
	},
	"mandate": {
		"title": "天命",
		"text": "王庭的使者坐在阴影里，从头到尾没有看你的脸。\n\n「天子有命：凡愿往野地开荒者，赐粮五十石，钱二百，并授「拓荒之权」。」\n他终于抬起头：「你们这样的人，最合适。」",
		"once": true,
		"choices": [
			{
				"label": "接下委任状。",
				"effects": {"gold": 120, "food": 12, "flag": "mandate_taken", "morale": 8, "log": "你成了天子的刀。刀不知道自己什么时候会钝。"},
				"result": "委任状上的字很好，纸很旧。你注意到印章的一角是缺的——\n像是从别的文书上借来的。",
			},
			{
				"label": "问他要兵。",
				"require": {"gold": 0},
				"effects": {"recruit": "民兵", "gold": -40, "flag": "mandate_taken", "log": "他给了你两个名字，都是已死之人的名字。"},
				"result": "他念了两个名字，让人去营里调人。\n名册上这两个名字旁边，早就画好了勾。",
			},
			{
				"label": "「我不替任何人开荒。」",
				"effects": {"will": 10, "morale": 5, "flag": "refused_mandate", "log": "走出王庭的时候，你的影子比来的时候长。"},
				"result": "使者的表情没有变。他只是把委任状收回去，叠好，放进袖子。\n「你会回来的。」他说。" },
		],
	},
}

static func get_event(id: String) -> Dictionary:
	return EVENTS.get(id, {})

static func all_ids() -> Array:
	return EVENTS.keys()
