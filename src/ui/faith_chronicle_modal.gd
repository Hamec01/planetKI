class_name FaithChronicleModal
extends PanelContainer

# ==============================================================================
# PLANETKI — FAITH CHRONICLE MODAL (ЛЕТОПИСЬ ВЕРЫ И СВЯЩЕННЫЕ ОБЫЧАИ)
# Заменяет старый селектор религий: показывает возникшую веру, догматы и святилища
# ==============================================================================

var title_lbl: Label
var faith_title_lbl: Label
var faith_desc_lbl: Label
var details_container: VBoxContainer

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -380.0
	offset_top = -250.0
	offset_right = 380.0
	offset_bottom = 250.0
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
	title_lbl.text = "🔮 ЛЕТОПИСЬ ВЕРЫ И СВЯЩЕННЫХ ОБРЯДОВ"
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
	
	# Карточка веры
	var faith_card = PanelContainer.new()
	var f_sbox = StyleBoxFlat.new()
	f_sbox.bg_color = Color(0.12, 0.15, 0.22, 0.9)
	f_sbox.border_color = Color(0.65, 0.45, 0.85, 0.8)
	f_sbox.set_border_width_all(1)
	f_sbox.set_corner_radius_all(6)
	f_sbox.set_content_margin_all(10)
	faith_card.add_theme_stylebox_override("panel", f_sbox)
	
	var f_vbox = VBoxContainer.new()
	f_vbox.add_theme_constant_override("separation", 4)
	faith_card.add_child(f_vbox)
	
	faith_title_lbl = Label.new()
	faith_title_lbl.text = "🔮 Не оформлено"
	faith_title_lbl.add_theme_font_size_override("font_size", 13)
	faith_title_lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 1.0))
	f_vbox.add_child(faith_title_lbl)
	
	faith_desc_lbl = Label.new()
	faith_desc_lbl.text = "Племя ещё не ответило на фундаментальный вопрос о богах."
	faith_desc_lbl.add_theme_font_size_override("font_size", 11)
	faith_desc_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	faith_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	f_vbox.add_child(faith_desc_lbl)
	
	main_vbox.add_child(faith_card)
	
	var sec_lbl = Label.new()
	sec_lbl.text = "Священные места и догматы:"
	sec_lbl.add_theme_font_size_override("font_size", 11)
	sec_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	main_vbox.add_child(sec_lbl)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	details_container = VBoxContainer.new()
	details_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_container.add_theme_constant_override("separation", 6)
	scroll.add_child(details_container)

func open_chronicle() -> void:
	_refresh()
	visible = true

func _refresh() -> void:
	var culture: CultureMemory = GameManager.culture_memory
	if culture == null:
		return
		
	var r = culture.religion_data
	var is_def = r.get("defined", false)
	
	for ch in details_container.get_children():
		ch.queue_free()
		
	if not is_def:
		faith_title_lbl.text = "🔮 Верования племени ещё не оформлены"
		faith_desc_lbl.text = "Взгляды народа на высшие силы родятся из первого природного знамения или дилеммы жрецов (EVENT-REL-01)."
		return
		
	var r_type = r.get("type", "UNDEFINED")
	var r_name = r.get("name", "Вера")
	var est_year = r.get("established_year", 1)
	
	faith_title_lbl.text = "🔮 %s" % r_name
	
	var desc = ""
	match r_type:
		"ANIMISM":
			desc = "Почитание духов природы, священных рощ, рек и стихий. Обряды проводят шаманы племени."
		"MONOTHEISM":
			var d_name = r.get("deity_name", "Творец Небес")
			desc = "Поклонение Единому Создателю (%s). Единство народа перед высшим началом." % d_name
		"POLYTHEISM":
			var p_name = r.get("pantheon_name", "Великий Пантеон")
			desc = "Почитание сонма богов (%s): покровителей войны, ремёсел, плодородия и неба." % p_name
		"ANCESTOR_WORSHIP":
			desc = "Связь с духами предков. Память ушедших отцов охраняет род от скверны и раздоров."
		"EARLY_RATIONALISM":
			desc = "Отказ от мистических объяснений. Народ познаёт мир через ремёсла, практический опыт и наблюдение."
			
	faith_desc_lbl.text = "%s\n(Установлено в Год %d)" % [desc, est_year]
	
	# Догматы и священные строения
	var buildings_lbl = Label.new()
	buildings_lbl.text = "🏛 Священные постройки: %s" % ("Святилище духов / Алтарь" if culture.is_building_unlocked("shrine") else "Пока нет открытых святилищ")
	buildings_lbl.add_theme_font_size_override("font_size", 11)
	buildings_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	details_container.add_child(buildings_lbl)
