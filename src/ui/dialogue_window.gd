class_name DialogueWindow
extends PanelContainer

# ==============================================================================
# РАЗГОВОР ВОЖДЯ С ЖИТЕЛЕМ — как в «Ведьмаке»
# ------------------------------------------------------------------------------
# 1) Вождь выбирает, о чём заговорить: список его реплик (темы NPCDialogue из
#    живого состояния жителя). Важные темы подсвечены, угрозы — красным.
# 2) Житель отвечает (субтитры), и вождь выбирает один из ответов.
# 3) Ответ реально меняет мир (NPCDialogue.respond), житель реагирует, и список
#    тем пересобирается — отвеченное на время уходит.
# Клавиши 1–9 выбирают реплику, Esc — уйти. Сведения о жителе обновляются вживую.
# ==============================================================================

signal closed
signal attack_requested(npc: CitizenNPC)

const COL_TOPIC := Color(0.92, 0.9, 0.84)
const COL_URGENT := Color(1.0, 0.82, 0.35)
const COL_HOSTILE := Color(1.0, 0.45, 0.4)
const COL_HOVER := Color(1.0, 0.95, 0.6)
const COL_BACK := Color(0.65, 0.65, 0.62)
const COL_PLAYER_LINE := Color(0.72, 0.78, 0.86)

var npc: CitizenNPC = null
var name_lbl: Label
var info_lbl: Label
var player_line_lbl: Label
var npc_line_lbl: RichTextLabel
var options_box: VBoxContainer
var _stage: String = "topics" # "topics" | "answers"
var _topic: Dictionary = {}
var _option_actions: Array[Callable] = []

func _ready() -> void:
	visible = false
	_build_ui()

func _get_settlement() -> SettlementData:
	var s = GameManager.get_player_settlement() if GameManager else null
	return s if s is SettlementData else null

func _label(text: String, size: int, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _build_ui() -> void:
	# Широкая кинематографичная полоса внизу экрана
	anchor_left = 0.12
	anchor_right = 0.88
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -330.0
	offset_bottom = -58.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.03, 0.82)
	sb.border_color = Color(0.55, 0.42, 0.22, 0.9)
	sb.border_width_top = 2
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top = HBoxContainer.new()
	v.add_child(top)
	name_lbl = _label("", 15, Color(1.0, 0.86, 0.5))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	info_lbl = _label("", 10, Color(0.62, 0.68, 0.76))
	v.add_child(info_lbl)
	# Субтитры: реплика вождя и ответ жителя
	player_line_lbl = _label("", 12, COL_PLAYER_LINE)
	v.add_child(player_line_lbl)
	npc_line_lbl = RichTextLabel.new()
	npc_line_lbl.bbcode_enabled = true
	npc_line_lbl.fit_content = true
	npc_line_lbl.scroll_active = false
	npc_line_lbl.add_theme_font_size_override("normal_font_size", 14)
	npc_line_lbl.add_theme_color_override("default_color", Color(0.97, 0.96, 0.92))
	v.add_child(npc_line_lbl)
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	v.add_child(sep)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	options_box = VBoxContainer.new()
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 2)
	scroll.add_child(options_box)

func open_with(p_npc: CitizenNPC) -> void:
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if s == null or ruler == null or p_npc == null:
		return
	npc = p_npc
	# Житель останавливается и поворачивается к вождю
	npc.state = CitizenNPC.State.TALKING
	npc.talk_partner_id = ruler.citizen_id
	npc.action_timer = 9999.0
	npc.facing_dir = (ruler.pos - npc.pos).normalized()
	ruler.state = CitizenNPC.State.TALKING
	ruler.facing_dir = (npc.pos - ruler.pos).normalized()
	HeroAnimations.play(ruler, "talk")
	var greet = NPCDialogue.get_greeting(npc, ruler)
	player_line_lbl.text = ""
	_set_npc_line(greet["text"])
	npc.shout(greet["text"], 3.0)
	visible = true
	_show_topics(s, ruler)

func _set_npc_line(text: String) -> void:
	npc_line_lbl.text = "[color=#f5d98a]%s:[/color] %s" % [npc.name, text]

func _set_player_line(text: String) -> void:
	player_line_lbl.text = "Вы: %s" % text if text != "" else ""

func _mood_text(s: SettlementData, ruler: CitizenNPC) -> String:
	var aff = int(npc.get_relationship_affinity(ruler.citizen_id))
	return "%d лет • %s • преданность вождю %d • отношение к вам %+d • сытость %d • здоровье %d/%d • %s" % [
		npc.age, s._get_job_display_name(npc.job_id), int(npc.loyalty), aff, int(npc.hunger), int(npc.health), int(npc.max_health), NPCPsyche.describe(npc)]

# Сведения о собеседнике живые: голод, здоровье, душа меняются прямо во время разговора
func _process(_delta: float) -> void:
	if not visible or npc == null:
		return
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if s and ruler:
		info_lbl.text = _mood_text(s, ruler)

func _clear_options() -> void:
	for ch in options_box.get_children():
		ch.queue_free()
	_option_actions.clear()

func _add_option(text: String, color: Color, action: Callable) -> void:
	_option_actions.append(action)
	var n = _option_actions.size()
	var btn = Button.new()
	btn.flat = true
	btn.text = "%d. %s" % [n, text] if n <= 9 else text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", COL_HOVER)
	btn.add_theme_color_override("font_focus_color", COL_HOVER)
	btn.add_theme_color_override("font_pressed_color", COL_HOVER)
	btn.pressed.connect(action)
	options_box.add_child(btn)

# Шаг 1: о чём заговорить
func _show_topics(s: SettlementData, ruler: CitizenNPC) -> void:
	_stage = "topics"
	_topic = {}
	name_lbl.text = "💬 %s" % npc.name
	info_lbl.text = _mood_text(s, ruler)
	_clear_options()
	for t in NPCDialogue.get_topics(s, npc, ruler):
		var topic: Dictionary = t
		var tid = String(topic["id"])
		var color = COL_HOSTILE if tid in NPCDialogue.HOSTILE_TOPICS else (COL_URGENT if tid in NPCDialogue.URGENT_TOPICS else COL_TOPIC)
		var prompt = NPCDialogue.get_prompt(topic)
		if tid == "flowers" or tid == "deed":
			prompt = "(%s)" % topic["options"][0]["text"]
		_add_option(prompt, color, func(): _pick_topic(topic))
	_add_option("Прощай.", COL_BACK, close)

# Шаг 2: житель отвечает на выбранную тему, вождь выбирает ответ
func _pick_topic(topic: Dictionary) -> void:
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if s == null or ruler == null or npc == null or not npc.is_alive:
		close()
		return
	_set_player_line(NPCDialogue.get_prompt(topic) if not String(topic["id"]) in ["flowers", "deed"] else String(topic["options"][0]["text"]))
	var options: Array = topic["options"]
	# Поступок без слов (подарок, нападение) или простой вопрос с единственным ответом — сразу
	if String(topic["npc_line"]) == "" and options.size() == 1:
		_choose(String(topic["id"]), String(options[0]["id"]), "")
		return
	_stage = "answers"
	_topic = topic
	_set_npc_line(String(topic["npc_line"]))
	npc.shout(String(topic["npc_line"]), 3.0)
	_clear_options()
	for o in options:
		var opt: Dictionary = o
		var tid = String(topic["id"])
		var oid = String(opt["id"])
		var color = COL_HOSTILE if oid in ["attack", "threaten", "rebuke", "scold", "arrest", "guard"] else COL_TOPIC
		_add_option(String(opt["text"]), color, func(): _choose(tid, oid, String(opt["text"])))
	_add_option("…Поговорим о другом.", COL_BACK, func(): _show_topics(s, ruler))

func _choose(topic_id: String, option_id: String, option_text: String) -> void:
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if s == null or ruler == null or npc == null or not npc.is_alive:
		close()
		return
	var res = NPCDialogue.respond(s, npc, ruler, topic_id, option_id)
	if res.get("attack", false):
		var victim = npc
		close()
		attack_requested.emit(victim)
		return
	if option_text != "":
		_set_player_line(option_text)
	_set_npc_line(String(res["reply"]))
	npc.shout(String(res["reply"]), 3.5)
	_show_topics(s, ruler)

# Клавиши 1–9 — выбор реплики
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			var i = int(k - KEY_1)
			if i < _option_actions.size():
				get_viewport().set_input_as_handled()
				_option_actions[i].call()

func close() -> void:
	if npc and npc.is_alive:
		npc.action_timer = 0.3 # житель заканчивает разговор и возвращается к делам
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if ruler and ruler.state == CitizenNPC.State.TALKING:
		ruler.state = CitizenNPC.State.IDLE
	npc = null
	_stage = "topics"
	_option_actions.clear()
	visible = false
	closed.emit()
