class_name EventRegistryPanel
extends PanelContainer

# ==============================================================================
# PLANETKI — EVENT REGISTRY PANEL (Журнал решений, угроз и летописи)
# Не стопорит игру, хранит события по разделам: Решения, Угрозы, Летопись
# ==============================================================================

signal event_open_requested(event_data: Dictionary)

var tab_container: TabContainer
var decisions_list: VBoxContainer
var incidents_list: VBoxContainer
var chronicle_list: VBoxContainer
var empty_decisions_lbl: Label
var empty_incidents_lbl: Label
var empty_chronicle_lbl: Label
var last_revision: String = ""

func _ready() -> void:
	visible = false
	_build_ui()

func _process(_delta: float) -> void:
	if visible:
		_refresh_if_changed()

func open_tab(tab_idx: int) -> void:
	visible = true
	if tab_container and tab_idx >= 0 and tab_idx < tab_container.get_tab_count():
		tab_container.current_tab = tab_idx
	last_revision = ""
	_refresh_if_changed()

func toggle_tab(tab_idx: int) -> void:
	if visible and tab_container and tab_container.current_tab == tab_idx:
		visible = false
	else:
		open_tab(tab_idx)

func open_registry(tab_idx: int = 0) -> void:
	open_tab(tab_idx)

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -370.0
	offset_top = -270.0
	offset_right = 370.0
	offset_bottom = 270.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.09, 0.14, 0.98)
	sbox.border_color = Color(0.85, 0.70, 0.30, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.7)
	sbox.shadow_size = 18
	sbox.shadow_offset = Vector2(0, 8)
	sbox.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sbox)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# --- ШАПКА ЖУРНАЛА ---
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	header.add_child(title_vbox)

	var title = Label.new()
	title.text = "📜 События и дилеммы племени"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	title_vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Решения правителя, актуальные угрозы и летопись истории рода (игра не останавливается)"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	title_vbox.add_child(subtitle)

	var close_btn = Button.new()
	close_btn.text = " ✕ Закрыть "
	close_btn.custom_minimum_size = Vector2(80, 28)
	close_btn.add_theme_font_size_override("font_size", 11)
	var c_sbox = StyleBoxFlat.new()
	c_sbox.bg_color = Color(0.18, 0.22, 0.30, 0.9)
	c_sbox.border_color = Color(0.6, 0.5, 0.3, 0.7)
	c_sbox.set_border_width_all(1)
	c_sbox.set_corner_radius_all(5)
	c_sbox.set_content_margin_all(4)
	close_btn.add_theme_stylebox_override("normal", c_sbox)
	close_btn.pressed.connect(func(): visible = false)
	header.add_child(close_btn)

	var h_sep = HSeparator.new()
	root.add_child(h_sep)

	# --- ВКЛАДКИ ЖУРНАЛА ---
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tab_container)

	decisions_list = _add_tab("👑 Решения")
	incidents_list = _add_tab("⚠️ Угрозы")
	chronicle_list = _add_tab("📖 Летопись")

func _add_tab(tab_name: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	margin.add_child(list)
	return list

func _refresh_if_changed() -> void:
	var manager: CivilizationEventManager = GameManager.civilization_event_manager
	var revision = str(manager.event_instances) if manager else ""
	if revision == last_revision:
		return
	last_revision = revision

	var decisions = _events_for("decision")
	var incidents = _events_for("incident")
	var chronicle = _events_for("chronicle")

	if tab_container and tab_container.get_tab_count() >= 3:
		tab_container.set_tab_title(0, "👑 Решения (%d)" % decisions.size())
		tab_container.set_tab_title(1, "⚠️ Угрозы (%d)" % incidents.size())
		tab_container.set_tab_title(2, "📖 Летопись (%d)" % chronicle.size())

	_render_list(decisions_list, decisions, "decision", "🕊 В племени царит согласие: нет вопросов, требующих решения правителя.")
	_render_list(incidents_list, incidents, "incident", "🛡 Поселение в безопасности: активных угроз и происшествий нет.")
	_render_list(chronicle_list, chronicle, "chronicle", "📖 Летопись пока пуста. История великого рода только начинается.")

func _events_for(kind: String) -> Array[Dictionary]:
	var manager: CivilizationEventManager = GameManager.civilization_event_manager
	var result: Array[Dictionary] = []
	if manager == null:
		return result
	for event_data in manager.event_instances.values():
		if not event_data is Dictionary:
			continue
		var status = event_data.get("status", "pending")
		var is_incident = (event_data.get("type", "") in ["incident", "threat"]) \
			or (event_data.get("category", "") in ["Происшествия", "Угрозы", "Опасности", "Опасные хищники", "Поиски и спасение", "Война", "Нападение"]) \
			or event_data.get("is_threat", false) \
			or int(event_data.get("threat_level", 0)) > 0

		if kind == "decision" and (status in ["pending", "deferred"]) and not is_incident:
			result.append(event_data)
		elif kind == "incident" and (status in ["pending", "deferred"]) and is_incident:
			result.append(event_data)
		elif kind == "chronicle" and status == "resolved":
			result.append(event_data)
	return result

func _render_list(list: VBoxContainer, events: Array[Dictionary], kind: String, empty_text: String) -> void:
	for child in list.get_children():
		child.queue_free()

	if events.is_empty():
		var empty_panel = PanelContainer.new()
		var ep_sbox = StyleBoxFlat.new()
		ep_sbox.bg_color = Color(0.1, 0.13, 0.18, 0.7)
		ep_sbox.set_corner_radius_all(6)
		ep_sbox.set_content_margin_all(20)
		empty_panel.add_theme_stylebox_override("panel", ep_sbox)

		var empty = Label.new()
		empty.text = empty_text
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		empty_panel.add_child(empty)
		list.add_child(empty_panel)
		return

	for event_data in events:
		var card = _create_event_card(event_data, kind)
		list.add_child(card)

func _create_event_card(ev: Dictionary, kind: String) -> PanelContainer:
	var card = PanelContainer.new()
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.13, 0.19, 0.95)
	
	if kind == "decision":
		sbox.border_color = Color(0.75, 0.62, 0.28, 0.85)
	elif kind == "incident":
		sbox.border_color = Color(0.85, 0.35, 0.35, 0.85)
	else:
		sbox.border_color = Color(0.35, 0.55, 0.75, 0.6)
		
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(8)
	sbox.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sbox)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# 1. Верхняя строка: Категория + Статус/Отложено
	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)

	var cat_lbl = Label.new()
	var cat_str = ev.get("category", "ДИЛЕММА").to_upper()
	cat_lbl.text = "🏛 %s" % cat_str
	cat_lbl.add_theme_font_size_override("font_size", 10)
	if kind == "decision":
		cat_lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	elif kind == "incident":
		cat_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		cat_lbl.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	cat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(cat_lbl)

	if ev.get("status", "") == "deferred":
		var def_badge = Label.new()
		def_badge.text = "⏳ Отложено"
		def_badge.add_theme_font_size_override("font_size", 10)
		def_badge.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		top_row.add_child(def_badge)

	# 2. Заголовок события
	var title_lbl = Label.new()
	title_lbl.text = ev.get("title", "Событие")
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	vbox.add_child(title_lbl)

	# 3. Текст описания
	var desc_lbl = Label.new()
	desc_lbl.text = ev.get("description", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	vbox.add_child(desc_lbl)

	# 4. Контекст (участники / место)
	var actor_names = ev.get("actor_names", [])
	if not actor_names.is_empty():
		var actors_lbl = Label.new()
		actors_lbl.text = "Участники: " + ", ".join(actor_names)
		actors_lbl.add_theme_font_size_override("font_size", 10)
		actors_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		vbox.add_child(actors_lbl)

	# 5. Нижняя панель действий
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	vbox.add_child(action_row)

	if kind in ["decision", "incident"]:
		var status_hint = Label.new()
		status_hint.text = "Ожидает рассмотрения правителем" if kind == "decision" else "Требует внимания правителя"
		status_hint.add_theme_font_size_override("font_size", 10)
		status_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
		status_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_child(status_hint)

		var open_btn = Button.new()
		open_btn.custom_minimum_size = Vector2(160, 30)
		open_btn.add_theme_font_size_override("font_size", 11)

		var btn_sbox = StyleBoxFlat.new()
		if kind == "decision":
			open_btn.text = "📜 Рассмотреть решение"
			btn_sbox.bg_color = Color(0.18, 0.28, 0.22, 0.95)
			btn_sbox.border_color = Color(0.45, 0.85, 0.45, 1.0)
		else:
			open_btn.text = "⚠️ Принять меры"
			btn_sbox.bg_color = Color(0.32, 0.16, 0.16, 0.95)
			btn_sbox.border_color = Color(0.95, 0.45, 0.45, 1.0)
			
		btn_sbox.set_border_width_all(1)
		btn_sbox.set_corner_radius_all(5)
		btn_sbox.set_content_margin_all(5)
		open_btn.add_theme_stylebox_override("normal", btn_sbox)

		open_btn.pressed.connect(func():
			event_open_requested.emit(ev)
		)
		action_row.add_child(open_btn)

	elif kind == "chronicle":
		var res_lbl = Label.new()
		var chosen_title = ev.get("chosen_choice_title", "")
		if chosen_title == "":
			var ch_id = ev.get("chosen_choice_id", "")
			for c in ev.get("choices", []):
				if c.get("id", "") == ch_id:
					chosen_title = c.get("title", "")
					break
		if chosen_title == "":
			chosen_title = "Решение исполнено"
			
		var res_day = ev.get("resolved_day", 1)
		res_lbl.text = "✅ Принято решение: «%s» (День %d)" % [chosen_title, res_day]
		res_lbl.add_theme_font_size_override("font_size", 10)
		res_lbl.add_theme_color_override("font_color", Color(0.65, 0.95, 0.65))
		res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_child(res_lbl)

	return card