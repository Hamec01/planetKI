class_name ElderCouncilModal
extends PanelContainer

# ==============================================================================
# ОКНО «СОВЕТ СТАРЕЙШИН»
# Вождь видит совет, призывает уважаемых соплеменников, назначает Правую руку
# и поручает ему решать события по сферам. Данные обновляются каждую секунду.
# ==============================================================================

var regent_lbl: Label
var regent_style_lbl: Label
var sphere_checks: Dictionary = {} # sphere -> CheckButton
var delegate_all_btn: Button
var revoke_btn: Button
var members_box: VBoxContainer
var candidates_box: VBoxContainer
var journal_box: VBoxContainer
var status_lbl: Label
var tabs: TabContainer
var governance_opt: OptionButton
var governance_hint_lbl: Label
var decisions_box: VBoxContainer
var revision_log_box: VBoxContainer
var _decisions_signature: String = ""
var _selected_alternatives: Dictionary = {} # instance_id -> выбранный вариант
var _refresh_timer: float = 0.0
var _updating: bool = false
var _lists_signature: String = ""

func _ready() -> void:
	visible = false
	_build_ui()

func _get_settlement() -> SettlementData:
	var s = GameManager.get_player_settlement() if GameManager else null
	return s if s is SettlementData else null

func open() -> void:
	visible = true
	refresh()

func toggle() -> void:
	if visible:
		visible = false
	else:
		open()

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 1.0
		refresh()

# --- ПОСТРОЕНИЕ ---

func _make_panel_style(bg: Color, border: Color, width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb

func _label(text: String, size: int, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _small_button(text: String, tip: String = "") -> Button:
	var b = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(0, 24)
	return b

func _scroll_list(min_height: float) -> Array:
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, min_height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	return [scroll, box]

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -440.0
	offset_top = -300.0
	offset_right = 440.0
	offset_bottom = 300.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var sbox = _make_panel_style(Color(0.08, 0.10, 0.15, 0.98), Color(0.85, 0.68, 0.28, 1.0), 2, 10)
	sbox.shadow_color = Color(0, 0, 0, 0.7)
	sbox.shadow_size = 16
	sbox.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sbox)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	var top = HBoxContainer.new()
	main_vbox.add_child(top)
	var title = _label("🏛 СОВЕТ СТАРЕЙШИН", 14, Color(1.0, 0.90, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(func(): visible = false)
	top.add_child(close_btn)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs)
	var council_tab = VBoxContainer.new()
	council_tab.name = "🏛 Совет"
	council_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(council_tab)

	# Карточка Правой руки и поручения
	var regent_card = PanelContainer.new()
	regent_card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.14, 0.12, 0.08, 0.95), Color(0.85, 0.68, 0.28, 0.9)))
	council_tab.add_child(regent_card)
	var rc_vbox = VBoxContainer.new()
	rc_vbox.add_theme_constant_override("separation", 4)
	regent_card.add_child(rc_vbox)
	regent_lbl = _label("👑 Правая рука не назначена", 13, Color(1.0, 0.88, 0.5))
	rc_vbox.add_child(regent_lbl)
	regent_style_lbl = _label("", 10, Color(0.85, 0.85, 0.8))
	rc_vbox.add_child(regent_style_lbl)
	rc_vbox.add_child(_label("Поручить Правой руке решать события (игра примет решение сама, по характеру старейшины):", 10, Color(0.7, 0.8, 0.9)))
	var spheres_row = HFlowContainer.new()
	spheres_row.add_theme_constant_override("h_separation", 10)
	rc_vbox.add_child(spheres_row)
	for sp in ElderCouncil.SPHERES:
		var cb = CheckButton.new()
		cb.text = ElderCouncil.SPHERES[sp]["name"]
		cb.add_theme_font_size_override("font_size", 10)
		var sphere_id = sp
		cb.toggled.connect(func(on): _on_sphere_toggled(sphere_id, on))
		spheres_row.add_child(cb)
		sphere_checks[sp] = cb
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	rc_vbox.add_child(btn_row)
	delegate_all_btn = _small_button("🤝 Доверить все решения", "Правая рука будет решать все события рода")
	delegate_all_btn.pressed.connect(func(): _on_delegate_all(true))
	btn_row.add_child(delegate_all_btn)
	var take_back_btn = _small_button("✋ Решать самому", "Забрать все поручения — события снова ждут решения вождя")
	take_back_btn.pressed.connect(func(): _on_delegate_all(false))
	btn_row.add_child(take_back_btn)
	revoke_btn = _small_button("⛔ Снять Правую руку", "Лишить старейшину поста")
	revoke_btn.pressed.connect(_on_revoke)
	btn_row.add_child(revoke_btn)

	# Члены совета | кандидаты
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	council_tab.add_child(cols)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(_label("Члены совета:", 11, Color(0.7, 0.85, 1.0)))
	var m = _scroll_list(170)
	left.add_child(m[0])
	members_box = m[1]
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_label("Можно призвать в совет (%d+ лет, по авторитету):" % ElderCouncil.MIN_APPOINT_AGE, 11, Color(0.7, 0.85, 1.0)))
	var c = _scroll_list(170)
	right.add_child(c[0])
	candidates_box = c[1]

	# Журнал решений Правой руки
	council_tab.add_child(_label("📜 Решения Правой руки:", 11, Color(0.7, 0.85, 1.0)))
	var j = _scroll_list(110)
	council_tab.add_child(j[0])
	journal_box = j[1]

	_build_revision_tab()

	status_lbl = _label("", 10, Color(1.0, 0.7, 0.5))
	main_vbox.add_child(status_lbl)

func _build_revision_tab() -> void:
	var rev_tab = VBoxContainer.new()
	rev_tab.name = "📜 Пересмотр решений"
	rev_tab.add_theme_constant_override("separation", 6)
	tabs.add_child(rev_tab)
	var gov_row = HBoxContainer.new()
	gov_row.add_theme_constant_override("separation", 8)
	rev_tab.add_child(gov_row)
	gov_row.add_child(_label("Как вождь меняет прежние решения:", 11, Color(0.8, 0.88, 1.0)))
	governance_opt = OptionButton.new()
	governance_opt.add_theme_font_size_override("font_size", 10)
	var idx = 0
	for mode in ElderCouncil.GOVERNANCE_NAMES:
		governance_opt.add_item(ElderCouncil.GOVERNANCE_NAMES[mode], idx)
		governance_opt.set_item_metadata(idx, mode)
		idx += 1
	governance_opt.item_selected.connect(_on_governance_selected)
	gov_row.add_child(governance_opt)
	governance_hint_lbl = _label("", 10, Color(0.8, 0.8, 0.75))
	rev_tab.add_child(governance_hint_lbl)
	rev_tab.add_child(_label("Действующие решения (обычаи, законы, устройство промысла):", 11, Color(0.7, 0.85, 1.0)))
	var d = _scroll_list(220)
	rev_tab.add_child(d[0])
	decisions_box = d[1]
	rev_tab.add_child(_label("🗳 Созывы совета и указы:", 11, Color(0.7, 0.85, 1.0)))
	var l = _scroll_list(110)
	rev_tab.add_child(l[0])
	revision_log_box = l[1]

func _refresh_revision_tab(s: SettlementData, council: ElderCouncil) -> void:
	var cem = GameManager.civilization_event_manager
	if cem == null:
		return
	for i in range(governance_opt.item_count):
		if governance_opt.get_item_metadata(i) == council.governance:
			governance_opt.select(i)
	var n_members = council.get_members(s).size()
	if council.governance == "council":
		governance_hint_lbl.text = "Изменение проходит, если «за» больше половины совета. В совете %d (нужно не меньше %d). Отказ совета — решение остаётся, повторный созыв через %d дн." % [n_members, ElderCouncil.MIN_VOTERS, ElderCouncil.REVOTE_COOLDOWN_DAYS]
	else:
		var hero: PlayerHero = s.hero
		var threshold = ElderCouncil.DECREE_MIN_TRIBE_LOYALTY - (hero.get_decree_threshold_relief() if hero else 0.0)
		governance_hint_lbl.text = "Указ действует сразу, но несогласные теряют лояльность, а старейшины помнят обиду. Племя признаёт указ, если его лояльность не ниже %d (сейчас %d)." % [int(threshold), int(s.economy.loyalty)]
	var decisions = cem.get_revisable_decisions()
	var sig_parts: Array[String] = [council.governance, str(n_members), str(council.revision_log.size())]
	for ev in decisions:
		sig_parts.append("%s:%s" % [ev.get("instance_id", ""), ev.get("chosen_choice_id", "")])
	var sig = "|".join(sig_parts)
	if sig == _decisions_signature:
		return
	_decisions_signature = sig
	for ch in decisions_box.get_children():
		ch.queue_free()
	if decisions.is_empty():
		decisions_box.add_child(_label("Пока нет принятых законов и обычаев, которые можно пересмотреть.", 10, Color(0.75, 0.75, 0.75)))
	for ev in decisions:
		_add_decision_row(s, council, cem, ev)
	for ch in revision_log_box.get_children():
		ch.queue_free()
	if council.revision_log.is_empty():
		revision_log_box.add_child(_label("Решения ещё не пересматривались.", 10, Color(0.75, 0.75, 0.75)))
	for e in council.revision_log:
		revision_log_box.add_child(_label(_format_revision_entry(e), 10, Color(0.88, 0.86, 0.78)))

func _add_decision_row(s: SettlementData, council: ElderCouncil, cem: CivilizationEventManager, ev: Dictionary) -> void:
	var inst_id: String = ev.get("instance_id", "")
	var cur_id: String = ev.get("chosen_choice_id", "")
	var cur_ch = cem.get_choice(ev, cur_id)
	var r = _row_container(false)
	var v: VBoxContainer = r[1]
	var who = ""
	var revs: Array = ev.get("revisions", [])
	if not revs.is_empty():
		who = " (изменено: %s)" % ("советом" if revs.back().get("method", "") == "council" else "указом")
	elif ev.get("decided_by", "") != "":
		who = " (решил(а) %s)" % ev["decided_by"]
	v.add_child(_label("%s • %s" % [ev.get("title", ""), ev.get("category", "")], 11, Color(0.95, 0.9, 0.75)))
	v.add_child(_label("Действует: «%s»%s" % [cur_ch.get("title", cur_id), who], 10, Color(0.7, 0.9, 0.7)))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var alt_opt = OptionButton.new()
	alt_opt.add_theme_font_size_override("font_size", 10)
	alt_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var i = 0
	var preselect = -1
	for ch in ev.get("choices", []):
		if ch.get("id", "") == cur_id:
			continue
		alt_opt.add_item(ch.get("title", ch.get("id", "")), i)
		alt_opt.set_item_metadata(i, ch.get("id", ""))
		if _selected_alternatives.get(inst_id, "") == ch.get("id", ""):
			preselect = i
		i += 1
	if preselect >= 0:
		alt_opt.select(preselect)
	alt_opt.item_selected.connect(func(sel): _selected_alternatives[inst_id] = alt_opt.get_item_metadata(sel))
	row.add_child(alt_opt)
	var act_btn = _small_button("🏛 Созвать совет" if council.governance == "council" else "👑 Объявить указ")
	if council.governance == "council":
		var conv = council.can_convene(s, inst_id)
		act_btn.disabled = not conv["ok"]
		act_btn.tooltip_text = conv["reason"]
	act_btn.pressed.connect(func():
		var chosen_alt = String(alt_opt.get_item_metadata(alt_opt.selected)) if alt_opt.selected >= 0 else ""
		_on_request_revision(inst_id, chosen_alt)
	)
	row.add_child(act_btn)
	decisions_box.add_child(r[0])

func _format_revision_entry(e: Dictionary) -> String:
	var head = "Год %d • «%s»: «%s» → «%s»" % [int(e.get("year", 0)), e.get("title", ""), e.get("from_title", ""), e.get("to_title", "")]
	if e.get("method", "") == "council":
		var votes: Array[String] = []
		for b in e.get("ballots", []):
			votes.append("%s %s (%s)" % [b.get("name", ""), "за" if b.get("yes", false) else "против", b.get("reason", "")])
		return "%s — совет: %s (%d за / %d против). %s" % [head, "ПРИНЯТО" if e.get("passed", false) else "ОТВЕРГНУТО", int(e.get("yes", 0)), int(e.get("no", 0)), "; ".join(votes)]
	if e.get("refused", false):
		return "%s — указ НЕ ПРИЗНАН племенем" % head
	return "%s — указ вождя, недовольных: %d" % [head, int(e.get("angered", 0))]

func _on_governance_selected(idx: int) -> void:
	if _updating:
		return
	var s = _get_settlement()
	if s:
		s.council.set_governance(s, String(governance_opt.get_item_metadata(idx)))
		_decisions_signature = ""
		refresh()

func _on_request_revision(inst_id: String, new_choice_id: String) -> void:
	var s = _get_settlement()
	if s == null or new_choice_id == "":
		return
	var res = s.council.request_revision(s, GameManager.civilization_event_manager, inst_id, new_choice_id)
	_selected_alternatives.erase(inst_id)
	_decisions_signature = ""
	if res.get("ok", false):
		status_lbl.text = "✅ Решение изменено" + ((" советом: %d за / %d против" % [int(res.get("yes", 0)), int(res.get("no", 0))]) if res.get("method", "") == "council" else " указом вождя")
	else:
		status_lbl.text = "⚠ " + String(res.get("reason", ""))
	refresh()

# --- ОБНОВЛЕНИЕ ---

func refresh() -> void:
	var s = _get_settlement()
	if s == null or s.council == null:
		return
	_updating = true
	var council: ElderCouncil = s.council
	var regent = council.get_regent(s)
	if regent:
		regent_lbl.text = "👑 Правая рука: %s, %d лет — авторитет %d, преданность вождю %d" % [regent.name, regent.age, int(council.get_authority(s, regent)), int(regent.loyalty)]
		regent_style_lbl.text = "Как решает: %s." % council.describe_style(regent)
	else:
		regent_lbl.text = "👑 Правая рука не назначена"
		regent_style_lbl.text = "Выберите члена совета и нажмите «Сделать Правой рукой». Пока её нет, все события решает вождь."
	for sp in sphere_checks:
		var cb: CheckButton = sphere_checks[sp]
		cb.disabled = regent == null
		cb.set_pressed_no_signal(council.delegated_spheres.has(sp))
	delegate_all_btn.disabled = regent == null
	revoke_btn.disabled = regent == null
	# Списки пересобираются только при изменении данных, чтобы кнопки не пропадали посреди клика
	var sig = _make_signature(s, council)
	if sig != _lists_signature:
		_lists_signature = sig
		_fill_members(s, council, regent)
		_fill_candidates(s, council)
		_fill_journal(council)
	_refresh_revision_tab(s, council)
	_updating = false

func _make_signature(s: SettlementData, council: ElderCouncil) -> String:
	var parts: Array[String] = [council.regent_id, str(council.journal.size()), str(council.appointed_ids)]
	for mbr in council.get_members(s):
		parts.append("%s:%d:%d:%d" % [mbr.citizen_id, mbr.age, int(mbr.loyalty), int(council.get_authority(s, mbr))])
	for cand in council.get_candidates(s):
		parts.append("c%s:%d:%d" % [cand.citizen_id, int(cand.loyalty), int(council.get_authority(s, cand))])
	return "|".join(parts)

func _row_container(highlight: bool) -> Array:
	var row_panel = PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.20, 0.16, 0.08, 0.95) if highlight else Color(0.12, 0.15, 0.21, 0.9),
		Color(0.85, 0.68, 0.28, 0.9) if highlight else Color(0.3, 0.4, 0.55, 0.6)))
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	row_panel.add_child(v)
	return [row_panel, v]

func _fill_members(s: SettlementData, council: ElderCouncil, regent: CitizenNPC) -> void:
	for ch in members_box.get_children():
		ch.queue_free()
	var members = council.get_members(s)
	if members.is_empty():
		members_box.add_child(_label("В совете пока никого. Призовите уважаемых соплеменников справа.", 10, Color(0.75, 0.75, 0.75)))
		return
	for mbr in members:
		var is_regent = regent != null and mbr == regent
		var r = _row_container(is_regent)
		var v: VBoxContainer = r[1]
		var kind = "старейшина" if council.is_natural_elder(mbr) else "призван вождём"
		v.add_child(_label("%s%s, %d лет (%s)" % ["👑 " if is_regent else "", mbr.name, mbr.age, kind], 11, Color(0.95, 0.92, 0.8)))
		v.add_child(_label("Авторитет %d • Преданность %d • %s" % [int(council.get_authority(s, mbr)), int(mbr.loyalty), council.describe_style(mbr)], 9, Color(0.75, 0.82, 0.9)))
		var btns = HBoxContainer.new()
		btns.add_theme_constant_override("separation", 6)
		v.add_child(btns)
		if not is_regent:
			var appoint = _small_button("👑 Сделать Правой рукой")
			var mid = mbr.citizen_id
			appoint.pressed.connect(func(): _on_appoint_regent(mid))
			btns.add_child(appoint)
		if council.appointed_ids.has(mbr.citizen_id):
			var dismiss = _small_button("Отпустить из совета")
			var did = mbr.citizen_id
			dismiss.pressed.connect(func(): _on_dismiss(did))
			btns.add_child(dismiss)
		members_box.add_child(r[0])

func _fill_candidates(s: SettlementData, council: ElderCouncil) -> void:
	for ch in candidates_box.get_children():
		ch.queue_free()
	var full = council.appointed_ids.size() >= ElderCouncil.MAX_APPOINTED
	var shown = 0
	for cand in council.get_candidates(s):
		if shown >= 12:
			break
		shown += 1
		var r = _row_container(false)
		var v: VBoxContainer = r[1]
		v.add_child(_label("%s, %d лет — %s" % [cand.name, cand.age, s._get_job_display_name(cand.job_id)], 11, Color(0.9, 0.9, 0.9)))
		v.add_child(_label("Авторитет %d • Преданность %d • %s" % [int(council.get_authority(s, cand)), int(cand.loyalty), council.describe_style(cand)], 9, Color(0.75, 0.82, 0.9)))
		var btn = _small_button("➕ Призвать в совет", "Совет полон (%d призванных)" % ElderCouncil.MAX_APPOINTED if full else "")
		btn.disabled = full
		var cid = cand.citizen_id
		btn.pressed.connect(func(): _on_appoint_member(cid))
		v.add_child(btn)
		candidates_box.add_child(r[0])
	if shown == 0:
		candidates_box.add_child(_label("Нет подходящих взрослых соплеменников.", 10, Color(0.75, 0.75, 0.75)))

func _fill_journal(council: ElderCouncil) -> void:
	for ch in journal_box.get_children():
		ch.queue_free()
	if council.journal.is_empty():
		journal_box.add_child(_label("Правая рука ещё не принимал решений.", 10, Color(0.75, 0.75, 0.75)))
		return
	for e in council.journal:
		var sphere_name = ElderCouncil.SPHERES.get(e.get("sphere", ""), {}).get("name", "")
		var txt = "Год %d • %s • «%s» → %s решил(а): «%s» — %s. Одобрили: %d, недовольны: %d" % [
			int(e.get("year", 0)), sphere_name, e.get("title", ""), e.get("regent_name", ""),
			e.get("choice_title", ""), e.get("reason", ""), int(e.get("approve", 0)), int(e.get("oppose", 0))]
		journal_box.add_child(_label(txt, 10, Color(0.88, 0.86, 0.78)))

# --- ДЕЙСТВИЯ ИГРОКА ---

func _show_result(res: Dictionary) -> void:
	status_lbl.text = "" if res.get("ok", false) else "⚠ " + String(res.get("reason", ""))
	refresh()

func _on_appoint_member(cid: String) -> void:
	var s = _get_settlement()
	if s:
		_show_result(s.council.appoint_member(s, cid))

func _on_dismiss(cid: String) -> void:
	var s = _get_settlement()
	if s:
		_show_result(s.council.dismiss_member(s, cid))

func _on_appoint_regent(cid: String) -> void:
	var s = _get_settlement()
	if s:
		_show_result(s.council.appoint_regent(s, cid))

func _on_revoke() -> void:
	var s = _get_settlement()
	if s:
		s.council.revoke_regent(s, "снят вождём")
		_show_result({"ok": true})

func _on_sphere_toggled(sphere: String, on: bool) -> void:
	if _updating:
		return
	var s = _get_settlement()
	if s == null:
		return
	s.council.set_sphere_delegated(s, sphere, on)
	_resolve_waiting(s)
	refresh()

func _on_delegate_all(on: bool) -> void:
	var s = _get_settlement()
	if s == null:
		return
	s.council.delegate_all(s, on)
	_resolve_waiting(s)
	refresh()

# Уже ожидающие события в поручённых сферах Правая рука решает сразу
func _resolve_waiting(s: SettlementData) -> void:
	if GameManager.civilization_event_manager == null or s.council.delegated_spheres.is_empty():
		return
	var n = GameManager.civilization_event_manager.resolve_pending_by_council()
	status_lbl.text = ("Правая рука разобрал(а) ожидавшие решения: %d" % n) if n > 0 else ""
