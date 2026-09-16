class_name TraditionsRegistryModal
extends PanelContainer

# ==============================================================================
# PLANETKI — TRADITIONS & LAWS REGISTRY (РЕЕСТР ОБЫЧАЕВ И ИНСТИТУТОВ)
# Заменяет старый Law Shop: показывает возникшие нормы, традиции и форму власти
# ==============================================================================

var title_lbl: Label
var gov_title_lbl: Label
var gov_desc_lbl: Label
var gov_stats_lbl: Label
var traditions_container: VBoxContainer

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -400.0
	offset_top = -270.0
	offset_right = 400.0
	offset_bottom = 270.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	sbox.border_color = Color(0.85, 0.68, 0.28, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.7)
	sbox.shadow_size = 16
	sbox.shadow_offset = Vector2(0, 8)
	sbox.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sbox)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)
	
	# Верхняя плашка: Заголовок + Закрыть
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(top_hbox)
	
	title_lbl = Label.new()
	title_lbl.text = "📜 РЕЕСТР ОБЫЧАЕВ И ФОРМА ПРАВЛЕНИЯ"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title_lbl)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(func(): visible = false)
	top_hbox.add_child(close_btn)
	
	# Карточка производной формы правления (Derived Government)
	var gov_card = PanelContainer.new()
	var g_sbox = StyleBoxFlat.new()
	g_sbox.bg_color = Color(0.12, 0.16, 0.22, 0.9)
	g_sbox.border_color = Color(0.35, 0.55, 0.75, 0.8)
	g_sbox.set_border_width_all(1)
	g_sbox.set_corner_radius_all(6)
	g_sbox.set_content_margin_all(8)
	gov_card.add_theme_stylebox_override("panel", g_sbox)
	
	var g_vbox = VBoxContainer.new()
	g_vbox.add_theme_constant_override("separation", 3)
	gov_card.add_child(g_vbox)
	
	gov_title_lbl = Label.new()
	gov_title_lbl.text = "🏛 Родовое вождество"
	gov_title_lbl.add_theme_font_size_override("font_size", 13)
	gov_title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	g_vbox.add_child(gov_title_lbl)
	
	gov_desc_lbl = Label.new()
	gov_desc_lbl.text = "Формируется на основе принятых в обществе законов и решений старейшин."
	gov_desc_lbl.add_theme_font_size_override("font_size", 10)
	gov_desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	gov_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g_vbox.add_child(gov_desc_lbl)
	
	gov_stats_lbl = Label.new()
	gov_stats_lbl.text = "Власть вождя: Умеренная | Сила Совета: Высокая"
	gov_stats_lbl.add_theme_font_size_override("font_size", 10)
	gov_stats_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	g_vbox.add_child(gov_stats_lbl)
	
	main_vbox.add_child(gov_card)
	
	var sec_title = Label.new()
	sec_title.text = "Укоренившиеся обычаи и законы племени (CultureMemory):"
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	main_vbox.add_child(sec_title)
	
	# Скролл со списком принятых традиций
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	traditions_container = VBoxContainer.new()
	traditions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	traditions_container.add_theme_constant_override("separation", 6)
	scroll.add_child(traditions_container)

func open_registry() -> void:
	_refresh()
	visible = true

func _refresh() -> void:
	var culture: CultureMemory = GameManager.culture_memory
	if culture == null:
		return
		
	# Обновление формы правления
	var gov = culture.get_derived_government()
	gov_title_lbl.text = "🏛 %s" % gov.get("title", "Родовое вождество")
	gov_desc_lbl.text = gov.get("description", "")
	gov_stats_lbl.text = "Власть правителя: %s | Власть Совета: %s" % [
		gov.get("ruler_power", "Умеренная"),
		gov.get("council_power", "Высокая")
	]
	
	# Очистка и заполнение традиций
	for ch in traditions_container.get_children():
		ch.queue_free()
		
	if culture.entries.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Племя ещё не столкнулось с первыми дилеммами.\nТрадиции родятся из событий и выборов соплеменников."
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		traditions_container.add_child(empty_lbl)
		return
		
	for k in culture.entries:
		var entry = culture.entries[k]
		var card = PanelContainer.new()
		var csbox = StyleBoxFlat.new()
		csbox.bg_color = Color(0.12, 0.14, 0.18, 0.8)
		csbox.border_color = Color(0.45, 0.40, 0.30, 0.7)
		csbox.set_border_width_all(1)
		csbox.set_corner_radius_all(5)
		csbox.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", csbox)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		
		var top_hbox = HBoxContainer.new()
		var t_lbl = Label.new()
		t_lbl.text = "⚖️ %s" % entry.source_choice_title
		t_lbl.add_theme_font_size_override("font_size", 11)
		t_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_hbox.add_child(t_lbl)
		
		var year_lbl = Label.new()
		year_lbl.text = "Год %d · Сила нормы: %d%%" % [entry.established_year, int(entry.strength)]
		year_lbl.add_theme_font_size_override("font_size", 10)
		year_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		top_hbox.add_child(year_lbl)
		vbox.add_child(top_hbox)
		
		var cat_lbl = Label.new()
		cat_lbl.text = "Категория: %s | Источник: %s" % [entry.category, entry.source_event_id]
		cat_lbl.add_theme_font_size_override("font_size", 9)
		cat_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		vbox.add_child(cat_lbl)
		
		card.add_child(vbox)
		traditions_container.add_child(card)
