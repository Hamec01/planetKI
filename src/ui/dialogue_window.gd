class_name DialogueWindow
extends PanelContainer

# ==============================================================================
# ОКНО РАЗГОВОРА ВОЖДЯ С ЖИТЕЛЕМ
# Темы и варианты — из NPCDialogue (живое состояние жителя). Пока окно открыто,
# житель стоит и говорит с вождём; после ответа темы пересобираются.
# ==============================================================================

signal closed
signal attack_requested(npc: CitizenNPC)

var npc: CitizenNPC = null
var name_lbl: Label
var info_lbl: Label
var line_lbl: Label
var options_box: VBoxContainer

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
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -330.0
	offset_right = 330.0
	offset_top = -380.0
	offset_bottom = -64.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.06, 0.97)
	sb.border_color = Color(0.95, 0.75, 0.35, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top = HBoxContainer.new()
	v.add_child(top)
	name_lbl = _label("", 14, Color(1.0, 0.9, 0.5))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	info_lbl = _label("", 10, Color(0.7, 0.78, 0.88))
	v.add_child(info_lbl)
	line_lbl = _label("", 13, Color(0.95, 0.95, 0.9))
	v.add_child(line_lbl)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	options_box = VBoxContainer.new()
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 4)
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
	line_lbl.text = "«%s»" % greet["text"]
	npc.shout(greet["text"], 3.0)
	visible = true
	_rebuild(s, ruler)

func _mood_text(s: SettlementData, ruler: CitizenNPC) -> String:
	var aff = int(npc.get_relationship_affinity(ruler.citizen_id))
	return "%d лет • %s • преданность вождю %d • отношение к вам %+d • сытость %d • здоровье %d/%d\n%s" % [
		npc.age, s._get_job_display_name(npc.job_id), int(npc.loyalty), aff, int(npc.hunger), int(npc.health), int(npc.max_health), NPCPsyche.describe(npc)]

# Сведения о собеседнике живые: голод, здоровье, душа меняются прямо во время разговора
func _process(_delta: float) -> void:
	if not visible or npc == null:
		return
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if s and ruler:
		info_lbl.text = _mood_text(s, ruler)

func _rebuild(s: SettlementData, ruler: CitizenNPC) -> void:
	name_lbl.text = "💬 %s" % npc.name
	info_lbl.text = _mood_text(s, ruler)
	for ch in options_box.get_children():
		ch.queue_free()
	for t in NPCDialogue.get_topics(s, npc, ruler):
		var topic: Dictionary = t
		for o in topic["options"]:
			var opt: Dictionary = o
			var btn = Button.new()
			var prefix = topic["icon"] + " "
			btn.text = prefix + (("«%s» → " % topic["npc_line"]) if topic["npc_line"] != "" else "") + opt["text"]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.add_theme_font_size_override("font_size", 11)
			var tid = topic["id"]
			var oid = opt["id"]
			var npc_line = topic["npc_line"]
			btn.pressed.connect(func(): _choose(tid, oid, npc_line))
			options_box.add_child(btn)
	var bye = Button.new()
	bye.text = "👋 Прощай."
	bye.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bye.add_theme_font_size_override("font_size", 11)
	bye.pressed.connect(close)
	options_box.add_child(bye)

func _choose(topic_id: String, option_id: String, npc_line: String) -> void:
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
	line_lbl.text = ("«%s»\n" % npc_line if npc_line != "" else "") + "— %s" % res["reply"]
	npc.shout(res["reply"], 3.5)
	_rebuild(s, ruler)

func close() -> void:
	if npc and npc.is_alive:
		npc.action_timer = 0.3 # житель заканчивает разговор и возвращается к делам
	var s = _get_settlement()
	var ruler = PlayerHero.get_ruler(s)
	if ruler and ruler.state == CitizenNPC.State.TALKING:
		ruler.state = CitizenNPC.State.IDLE
	npc = null
	visible = false
	closed.emit()
