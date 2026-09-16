class_name DevEventInspector
extends PanelContainer

# ==============================================================================
# PLANETKI — DEV / DEBUG EVENT & CIVILIZATION INSPECTOR
# Источник правды: STAGE1_CIVILIZATION_EVENTS_v3_SOURCE_OF_TRUTH.md (Секция 102)
# ==============================================================================

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
	offset_left = -460.0
	offset_top = -320.0
	offset_right = 460.0
	offset_bottom = 320.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	sbox.border_color = Color(0.9, 0.3, 0.3, 1.0) # Отличительный дебаг-бордер
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.8)
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
	t_lbl.text = "🛠️ DEV CIVILIZATION & EVENT INSPECTOR (F12)"
	t_lbl.add_theme_font_size_override("font_size", 13)
	t_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(t_lbl)
	
	var refresh_btn = Button.new()
	refresh_btn.text = "🔄 Обновить"
	refresh_btn.pressed.connect(_refresh)
	top_hbox.add_child(refresh_btn)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): visible = false)
	top_hbox.add_child(close_btn)
	
	var split = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	main_vbox.add_child(split)
	
	# Левая колонка: Текущее состояние цивилизации
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left_vbox)
	
	var left_lbl = Label.new()
	left_lbl.text = "📊 Authoritative Civilization State:"
	left_lbl.add_theme_font_size_override("font_size", 11)
	left_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	left_vbox.add_child(left_lbl)
	
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(info_text)
	
	# Правая колонка: Запуск любого события вручную
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(320, 0)
	split.add_child(right_vbox)
	
	var right_lbl = Label.new()
	right_lbl.text = "⚡ Принудительный запуск события:"
	right_lbl.add_theme_font_size_override("font_size", 11)
	right_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	right_vbox.add_child(right_lbl)
	
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

func _refresh() -> void:
	var culture: CultureMemory = GameManager.culture_memory
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
	
	var ev_mgr: CivilizationEventManager = GameManager.civilization_event_manager
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
			if GameManager.civilization_event_manager:
				GameManager.civilization_event_manager.trigger_event(ev)
		)
		event_buttons_container.add_child(btn)
