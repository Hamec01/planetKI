class_name CivilizationEventModal
extends PanelContainer

# ==============================================================================
# PLANETKI — CIVILIZATION EVENT MODAL (Dilemmas of Civilization)
# Интерактивное модальное окно цивилизационных выборов и дилемм
# ==============================================================================

var current_event: Dictionary = {}
var selected_choice_id: String = ""

# UI элементы
var category_badge: Label
var title_label: Label
var story_desc: Label
var choices_container: VBoxContainer
var confirm_btn: Button
var extra_input_container: HBoxContainer
var extra_input_edit: LineEdit
var extra_input_lbl: Label

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
	offset_top = -280.0
	offset_right = 380.0
	offset_bottom = 280.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	sbox.border_color = Color(0.85, 0.68, 0.28, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.75)
	sbox.shadow_size = 16
	sbox.shadow_offset = Vector2(0, 8)
	sbox.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sbox)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	add_child(main_vbox)
	
	# Шапка: Категория + Заголовок
	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	main_vbox.add_child(header_vbox)
	
	category_badge = Label.new()
	category_badge.text = "🏛 СУДЬБА ЦИВИЛИЗАЦИИ"
	category_badge.add_theme_font_size_override("font_size", 11)
	category_badge.add_theme_color_override("font_color", Color(0.85, 0.70, 0.35))
	header_vbox.add_child(category_badge)
	
	title_label = Label.new()
	title_label.text = "Заголовок события"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	header_vbox.add_child(title_label)
	
	var sep = HSeparator.new()
	main_vbox.add_child(sep)
	
	# Описание истории
	var story_panel = PanelContainer.new()
	var story_sbox = StyleBoxFlat.new()
	story_sbox.bg_color = Color(0.12, 0.15, 0.20, 0.8)
	story_sbox.set_corner_radius_all(6)
	story_sbox.set_content_margin_all(10)
	story_panel.add_theme_stylebox_override("panel", story_sbox)
	
	story_desc = Label.new()
	story_desc.text = "Художественное описание дилеммы..."
	story_desc.add_theme_font_size_override("font_size", 12)
	story_desc.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96))
	story_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_panel.add_child(story_desc)
	main_vbox.add_child(story_panel)
	
	# Дополнительное поле ввода (например, имя бога или пантеона)
	extra_input_container = HBoxContainer.new()
	extra_input_container.add_theme_constant_override("separation", 8)
	extra_input_container.visible = false
	main_vbox.add_child(extra_input_container)
	
	extra_input_lbl = Label.new()
	extra_input_lbl.text = "Имя Создателя / Пантеона:"
	extra_input_lbl.add_theme_font_size_override("font_size", 12)
	extra_input_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	extra_input_container.add_child(extra_input_lbl)
	
	extra_input_edit = LineEdit.new()
	extra_input_edit.placeholder_text = "Введите имя..."
	extra_input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	extra_input_container.add_child(extra_input_edit)
	
	# Контейнер для вариантов выбора со скроллом
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	main_vbox.add_child(scroll)
	
	choices_container = VBoxContainer.new()
	choices_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_container.add_theme_constant_override("separation", 6)
	scroll.add_child(choices_container)
	
	# Нижняя кнопка подтверждения
	confirm_btn = Button.new()
	confirm_btn.text = "🏛 Утвердить решение народа"
	confirm_btn.custom_minimum_size = Vector2(0, 36)
	confirm_btn.add_theme_font_size_override("font_size", 13)
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(_on_confirm_pressed)
	
	var conf_sbox = StyleBoxFlat.new()
	conf_sbox.bg_color = Color(0.18, 0.28, 0.20, 0.95)
	conf_sbox.border_color = Color(0.45, 0.85, 0.45, 1.0)
	conf_sbox.set_border_width_all(1)
	conf_sbox.set_corner_radius_all(6)
	confirm_btn.add_theme_stylebox_override("normal", conf_sbox)
	main_vbox.add_child(confirm_btn)
	var passive_actions = HBoxContainer.new()
	main_vbox.add_child(passive_actions)
	var defer_button = Button.new()
	defer_button.text = "Отложить"
	defer_button.pressed.connect(_on_defer_pressed)
	passive_actions.add_child(defer_button)
	var ignore_button = Button.new()
	ignore_button.text = "Не вмешиваться"
	ignore_button.pressed.connect(_on_ignore_pressed)
	passive_actions.add_child(ignore_button)

func open_event(ev: Dictionary) -> void:
	current_event = ev
	selected_choice_id = ""
	confirm_btn.disabled = true
	extra_input_container.visible = false
	
	category_badge.text = "🏛 %s" % ev.get("category", "СУДЬБА ЦИВИЛИЗАЦИИ").to_upper()
	title_label.text = ev.get("title", "Историческое решение")
	story_desc.text = ev.get("description", "")
	
	# Очищаем старые кнопки
	for ch in choices_container.get_children():
		ch.queue_free()
		
	var choices = ev.get("choices", [])
	for c in choices:
		var btn = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var c_id = c["id"]
		var c_title = c.get("title", "")
		var c_desc = c.get("desc", "")
		var c_effects = c.get("effects_desc", "")
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var top_lbl = Label.new()
		top_lbl.text = "%s. %s" % [c_id, c_title]
		top_lbl.add_theme_font_size_override("font_size", 12)
		top_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(top_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = "%s\n%s" % [c_desc, c_effects]
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_lbl)
		
		btn.add_child(vbox)
		btn.pressed.connect(func(): _select_choice(c_id))
		choices_container.add_child(btn)
		
	if not visible:
		visible = true
		GameManager.push_modal_pause()

func _select_choice(choice_id: String) -> void:
	selected_choice_id = choice_id
	confirm_btn.disabled = false
	
	# Подсветка выбранной кнопки
	for btn in choices_container.get_children():
		btn.modulate = Color(0.8, 0.8, 0.8)
		
	var idx = 0
	for c in current_event.get("choices", []):
		if c["id"] == choice_id:
			if idx < choices_container.get_child_count():
				choices_container.get_child(idx).modulate = Color(1.3, 1.3, 1.0)
				
			# Если выбран монотеизм/политеизм — покажем поле ввода имени
			var g_val = c.get("group_value", "")
			if g_val == "MONOTHEISM":
				extra_input_container.visible = true
				extra_input_lbl.text = "Имя Единого Бога:"
				extra_input_edit.text = "Творец Небес"
			elif g_val == "POLYTHEISM":
				extra_input_container.visible = true
				extra_input_lbl.text = "Имя Пантеона:"
				extra_input_edit.text = "Великий Пантеон"
			else:
				extra_input_container.visible = false
			break
		idx += 1

func _on_confirm_pressed() -> void:
	if current_event.is_empty() or selected_choice_id == "":
		return
		
	var extra_data: Dictionary = {}
	if extra_input_container.visible:
		var txt = extra_input_edit.text.strip_edges()
		if txt != "":
			extra_data["deity_name"] = txt
			extra_data["pantheon_name"] = txt
			
	var instance_id = current_event.get("instance_id", "")
	GameManager.civilization_event_manager.apply_choice(instance_id, selected_choice_id, extra_data)
	
	if visible:
		visible = false
		GameManager.pop_modal_pause()

func _on_defer_pressed() -> void:
	var instance_id = current_event.get("instance_id", "")
	GameManager.civilization_event_manager.defer_event(instance_id)
	if visible:
		visible = false
		GameManager.pop_modal_pause()

func _on_ignore_pressed() -> void:
	var instance_id = current_event.get("instance_id", "")
	GameManager.civilization_event_manager.resolve_without_intervention(instance_id)
	if visible:
		visible = false
		GameManager.pop_modal_pause()
