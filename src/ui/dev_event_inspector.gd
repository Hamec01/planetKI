class_name DevEventInspector
extends PanelContainer

# ==============================================================================
# PLANETKI — DEV / DEBUG SIMULATION, NPC & EVENT INSPECTOR (F3 / F12)
# ==============================================================================

var tab_container: TabContainer
var npc_diag_text: RichTextLabel
var burial_diag_text: RichTextLabel
var construction_diag_text: RichTextLabel
var log_diag_text: RichTextLabel
var info_text: RichTextLabel
var event_buttons_container: VBoxContainer

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -520.0
	offset_top = -340.0
	offset_right = 520.0
	offset_bottom = 340.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	sbox.border_color = Color(0.3, 0.7, 0.9, 1.0) # Отличительный дебаг-бордер
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.85)
	sbox.shadow_size = 20
	sbox.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sbox)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)
	
	# Верхняя плашка
	var top_hbox = HBoxContainer.new()
	main_vbox.add_child(top_hbox)
	
	var t_lbl = Label.new()
	t_lbl.text = "🛠️ ДИАГНОСТИКА СИМУЛЯЦИИ И ДЕБАГ-ЛОГ (F3 / F12)"
	t_lbl.add_theme_font_size_override("font_size", 14)
	t_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(t_lbl)
	
	var log_btn = Button.new()
	log_btn.text = "📁 Открыть папку логов"
	log_btn.pressed.connect(func():
		var global_p = ProjectSettings.globalize_path("user://")
		OS.shell_open(global_p)
	)
	top_hbox.add_child(log_btn)

	var refresh_btn = Button.new()
	refresh_btn.text = "🔄 Обновить"
	refresh_btn.pressed.connect(_refresh)
	top_hbox.add_child(refresh_btn)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): visible = false)
	top_hbox.add_child(close_btn)
	
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)
	
	# --- TAB 1: Диагностика NPC и Задач ---
	var tab_npc = VBoxContainer.new()
	tab_npc.name = "👥 Жители & Задачи"
	tab_container.add_child(tab_npc)
	
	npc_diag_text = RichTextLabel.new()
	npc_diag_text.bbcode_enabled = true
	npc_diag_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_npc.add_child(npc_diag_text)
	
	# --- TAB 2: Погребение и Тела ---
	var tab_burial = VBoxContainer.new()
	tab_burial.name = "⚰️ Погребение & Тела"
	tab_container.add_child(tab_burial)
	
	burial_diag_text = RichTextLabel.new()
	burial_diag_text.bbcode_enabled = true
	burial_diag_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_burial.add_child(burial_diag_text)
	
	# --- TAB 3: Лесозаготовка и Стройка ---
	var tab_build = VBoxContainer.new()
	tab_build.name = "🪓 Лес & Стройка"
	tab_container.add_child(tab_build)
	
	construction_diag_text = RichTextLabel.new()
	construction_diag_text.bbcode_enabled = true
	construction_diag_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_build.add_child(construction_diag_text)

	# --- TAB 4: Живой лог событий ---
	var tab_log = VBoxContainer.new()
	tab_log.name = "📜 Живой лог (user://planetki_debug.log)"
	tab_container.add_child(tab_log)
	
	log_diag_text = RichTextLabel.new()
	log_diag_text.bbcode_enabled = true
	log_diag_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_log.add_child(log_diag_text)
	
	# --- TAB 5: События цивилизации ---
	var tab_events = HBoxContainer.new()
	tab_events.name = "⚡ События Цивилизации"
	tab_events.add_theme_constant_override("separation", 10)
	tab_container.add_child(tab_events)
	
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_events.add_child(left_vbox)
	
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(info_text)
	
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(340, 0)
	tab_events.add_child(right_vbox)
	
	var r_scroll = ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(r_scroll)
	
	event_buttons_container = VBoxContainer.new()
	event_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_buttons_container.add_theme_constant_override("separation", 4)
	r_scroll.add_child(event_buttons_container)

func toggle_inspector() -> void:
	visible = not visible
	if visible:
		_refresh()

func _process(_delta: float) -> void:
	if visible:
		# Периодическое мягкое обновление открытого окна дебага
		_refresh_active_tab()

func _refresh_active_tab() -> void:
	if not visible:
		return
	var cur_tab = tab_container.current_tab
	if cur_tab == 0:
		_refresh_npc_diag()
	elif cur_tab == 1:
		_refresh_burial_diag()
	elif cur_tab == 2:
		_refresh_build_diag()
	elif cur_tab == 3:
		_refresh_log_diag()
	elif cur_tab == 4:
		_refresh_events_diag()

func _refresh() -> void:
	_refresh_npc_diag()
	_refresh_burial_diag()
	_refresh_build_diag()
	_refresh_log_diag()
	_refresh_events_diag()

func _refresh_npc_diag() -> void:
	var s = GameManager.get_player_settlement() if GameManager else null
	if s == null or s.population == null:
		npc_diag_text.text = "[color=gray]Нет данных поселения игрока[/color]"
		return
		
	var lines: Array[String] = []
	lines.append("[b][color=gold]👥 ДИАГНОСТИКА ЖИТЕЛЕЙ ПОСЕЛЕНИЯ (Всего: %d)[/color][/b]" % s.population.citizens.size())
	lines.append("────────────────────────────────────────────────────────────────────────────────────────────")
	lines.append("[b]Имя[/b] | [b]Профессия[/b] | [b]Состояние[/b] | [b]Задача[/b] | [b]HP / Сытость / Энергия[/b] | [b]Статус (Причина)[/b]")
	lines.append("────────────────────────────────────────────────────────────────────────────────────────────")
	
	for c in s.population.citizens:
		var state_str = CitizenNPC.State.keys()[c.state] if c.state < CitizenNPC.State.size() else str(c.state)
		var state_color = "lime" if c.state == CitizenNPC.State.WORKING else ("yellow" if c.state == CitizenNPC.State.MOVING_TO_WORK else ("orange" if c.state == CitizenNPC.State.WAITING else ("gray" if not c.is_alive else "white")))
		var alive_icon = "🟢" if c.is_alive else "⚰️"
		var task_str = c.task_id if c.task_id != "" else "—"
		var tool_str = " (🪓 %s)" % c.equipped_tool.get("type", "") if not c.equipped_tool.is_empty() else ""
		
		lines.append("%s [b]%s[/b] | [color=cyan]%s%s[/color] | [color=%s]%s[/color] | [color=lightgreen]%s[/color] | %d HP / %d сыт / %d бодр | [color=lightgray]%s[/color]" % [
			alive_icon,
			c.name,
			c.job_id,
			tool_str,
			state_color,
			state_str,
			task_str,
			int(c.health),
			int(c.hunger),
			int(c.energy),
			c.last_status_reason
		])
	npc_diag_text.text = "\n".join(lines)

func _refresh_burial_diag() -> void:
	var s = GameManager.get_player_settlement() if GameManager else null
	if s == null or s.population == null:
		burial_diag_text.text = "[color=gray]Нет данных поселения[/color]"
		return
		
	var lines: Array[String] = []
	lines.append("[b][color=gold]⚰️ ДИАГНОСТИКА ПОГРЕБЕНИЙ И ТЕЛ УСОПШИХ[/color][/b]")
	lines.append("Участков кладбища: %d | Реестр усопших: %d" % [s.cemetery_plots.size(), s.deceased_registry.size()])
	lines.append("────────────────────────────────────────────────────────────────────────────────────────────")
	
	var dead_unburied = []
	for c in s.population.citizens:
		if not c.is_alive and not c.is_buried:
			dead_unburied.append(c)
			
	if dead_unburied.is_empty():
		lines.append("[color=lime]✅ Все усопшие соплеменники преданы земле с почестями. Неупокоенных тел нет.[/color]")
	else:
		lines.append("[color=salmon]⚠️ Обнаружено неупокоенных тел: %d[/color]" % dead_unburied.size())
		for d in dead_unburied:
			var undertaker_name = "НЕ НАЗНАЧЕН (ожидает)"
			for cit in s.population.citizens:
				if cit.is_alive and cit.task_id == "burial_procession" and (cit.target_id == d.citizen_id or cit.carrying_deceased_id == d.citizen_id):
					undertaker_name = "%s (Фаза: %s)" % [cit.name, cit.subphase]
					break
			lines.append(" • [b]%s[/b] (Позиция: %s) -> Могильщик: [color=yellow]%s[/color]" % [d.name, str(d.pos), undertaker_name])
			
	lines.append("\n[b]Могильники и Кладбища:[/b]")
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == s.id and b.type in ["cemetery", "grave"]:
				var buried_cnt = b.building_data.get("buried_citizens", []).size()
				lines.append(" • Участок %s: захоронено %d/4 соплеменников" % [str(b.pos), buried_cnt])
				
	burial_diag_text.text = "\n".join(lines)

func _refresh_build_diag() -> void:
	var s = GameManager.get_player_settlement() if GameManager else null
	if s == null:
		construction_diag_text.text = "[color=gray]Нет данных поселения[/color]"
		return
		
	var lines: Array[String] = []
	lines.append("[b][color=gold]🪓 ЛЕСОЗАГОТОВКА И СТРОИТЕЛЬНАЯ ОЧЕРЕДЬ[/color][/b]")
	lines.append("Запас дерева на складе: [color=yellow]%.1f[/color] | Буфер лагеря: [color=yellow]%.1f[/color]" % [
		s.economy.get_resource("wood") if s.economy else 0.0,
		s.get_active_woodcutter_camp().local_buffer_wood if s.get_active_woodcutter_camp() else 0.0
	])
	lines.append("────────────────────────────────────────────────────────────────────────────────────────────")
	
	lines.append("[b]🏗 Очередь строительства (Объектов: %d):[/b]" % s.construction_queue.size())
	if s.construction_queue.is_empty():
		lines.append("[color=gray]Очередь стройки пуста.[/color]")
	else:
		for item in s.construction_queue:
			var coord = item.get("coord", Vector2i(-1, -1))
			if GameManager and GameManager.tile_buildings.has(coord):
				var b = GameManager.tile_buildings[coord]
				var req = b.get("materials_required", {})
				var deliv = b.get("materials_delivered", {})
				var days_left = float(b.get("days_left", 1.0))
				var mat_str = []
				for r in req:
					mat_str.append("%s: %.0f/%.0f" % [r, float(deliv.get(r, 0.0)), float(req[r])])
				lines.append(" • [b]%s[/b] на %s: Статус [color=cyan]%s[/color] | Материалы: [%s] | Осталось работы: %.1f дн." % [
					b.get("id", "building"),
					str(coord),
					b.get("status", ""),
					", ".join(mat_str),
					days_left
				])
				
	lines.append("\n[b]🪓 Лесорубы племени:[/b]")
	if s.population:
		var w_cnt = 0
		for c in s.population.citizens:
			if c.is_alive and c.job_id == "woodcutter":
				w_cnt += 1
				var tool_str = "есть топор (прочность %.0f)" % float(c.equipped_tool.get("durability", 0.0)) if not c.equipped_tool.is_empty() else "[color=salmon]НЕТ ТОПОРА[/color]"
				lines.append(" • [b]%s[/b]: Состояние [color=yellow]%s[/color] | Задача: %s | Инструмент: %s | Статус: [color=gray]%s[/color]" % [
					c.name,
					CitizenNPC.State.keys()[c.state],
					c.task_id if c.task_id != "" else "—",
					tool_str,
					c.last_status_reason
				])
		if w_cnt == 0:
			lines.append("[color=salmon]⚠️ В поселении нет назначенных лесорубов! Назначьте жителей лесорубами в окне населения (U).[/color]")
			
	construction_diag_text.text = "\n".join(lines)

func _refresh_log_diag() -> void:
	var logs = DebugLogger.get_recent_logs()
	var lines: Array[String] = []
	lines.append("[b][color=gold]📜 ПОСЛЕДНИЕ СОБЫТИЯ СИМУЛЯЦИИ (user://planetki_debug.log)[/color][/b]")
	lines.append("────────────────────────────────────────────────────────────────────────────────────────────")
	for entry in logs:
		var color = "white"
		if entry["level"] == "WARN": color = "salmon"
		elif entry["level"] == "ERROR": color = "red"
		elif entry["category"] == "Burial": color = "violet"
		elif entry["category"] == "Woodcutter": color = "lightgreen"
		elif entry["category"] == "Builder": color = "gold"
		
		lines.append("[%s][%s] [b][color=%s]%s[/color][/b]: %s" % [
			entry["time"],
			entry["day_hour"],
			color,
			entry["category"],
			entry["message"]
		])
	log_diag_text.text = "\n".join(lines)

func _refresh_events_diag() -> void:
	var culture: CultureMemory = GameManager.culture_memory if GameManager else null
	if culture == null:
		info_text.text = "[color=red]CultureMemory не инициализирована![/color]"
		return
		
	var gov = culture.get_derived_government()
	var lines = []
	lines.append("[b][color=gold]🏛 Форма правления:[/color][/b] " + gov.get("title", ""))
	lines.append("[color=gray]" + gov.get("description", "") + "[/color]")
	lines.append("Власть вождя: [color=cyan]" + gov.get("ruler_power", "") + "[/color] | Власть Совета: [color=cyan]" + gov.get("council_power", "") + "[/color]")
	lines.append("─────────────────────────────────────")
	
	lines.append("[b][color=yellow]🔮 Религия:[/color][/b] " + str(culture.religion_data.get("name", "Не оформлено")))
	lines.append("Базис: [color=lime]" + str(culture.religion_data.get("type", "UNDEFINED")) + "[/color]")
	lines.append("─────────────────────────────────────")
	
	lines.append("[b][color=orange]⚖️ Взаимоисключающие группы (Exclusive Groups):[/color][/b]")
	for g in culture.exclusive_groups:
		lines.append(" • [b]%s[/b]: [color=yellow]%s[/color]" % [g, culture.exclusive_groups[g]])
	lines.append("─────────────────────────────────────")
	
	lines.append("[b][color=lightgreen]🏛 Открытые спец. постройки:[/color][/b] " + str(culture.unlocked_special_buildings))
	lines.append("[b][color=lightblue]📜 Открытые практики:[/color][/b] " + str(culture.discovered_practices))
	lines.append("─────────────────────────────────────")
	
	var ev_mgr: CivilizationEventManager = GameManager.civilization_event_manager if GameManager else null
	if ev_mgr:
		lines.append("[b][color=salmon]⏳ Кулдауны цепочек событий:[/color][/b] " + str(ev_mgr.chain_cooldowns))
		lines.append("[b][color=salmon]🚩 Завершённые события:[/color][/b] " + str(ev_mgr.triggered_events))
		
	info_text.text = "\n".join(lines)
	
	# Заполнение кнопок запуска событий
	for ch in event_buttons_container.get_children():
		ch.queue_free()
		
	for ev in CivilizationEventDB.get_all_events():
		var btn = Button.new()
		var ev_id = ev["id"]
		var ev_title = ev.get("title", "")
		btn.text = "%s: %s" % [ev_id, ev_title]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func():
			visible = false
			if GameManager and GameManager.civilization_event_manager:
				GameManager.civilization_event_manager.trigger_event(ev)
		)
		event_buttons_container.add_child(btn)
