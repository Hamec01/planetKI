class_name GameOverModal
extends PanelContainer

# ==============================================================================
# PLANETKI — GAME OVER MODAL (Окно завершения партии при гибели вождя)
# ==============================================================================

var overlay_dim: ColorRect
var title_lbl: Label
var reason_lbl: Label
var stats_lbl: Label
var btn_quick_load: Button
var btn_restart: Button
var btn_menu: Button

func _ready() -> void:
	visible = false
	_build_ui()
	EventBus.game_over.connect(_on_game_over)

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -320.0
	offset_top = -220.0
	offset_right = 320.0
	offset_bottom = 220.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	z_index = 100
	
	# Полупрозрачная подложка на весь экран
	overlay_dim = ColorRect.new()
	overlay_dim.name = "DimOverlay"
	overlay_dim.color = Color(0.02, 0.02, 0.04, 0.85)
	overlay_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_dim)
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.08, 0.12, 0.98)
	sbox.border_color = Color(0.9, 0.25, 0.25, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0.4, 0.05, 0.05, 0.6)
	sbox.shadow_size = 24
	sbox.shadow_offset = Vector2(0, 8)
	sbox.set_content_margin_all(20)
	add_theme_stylebox_override("panel", sbox)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)
	
	# Заголовок
	var header_box = VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	vbox.add_child(header_box)
	
	var badge = Label.new()
	badge.text = "💀 СУДЬБА ЦИВИЛИЗАЦИИ ОПРЕДЕЛЕНА"
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(badge)
	
	title_lbl = Label.new()
	title_lbl.text = "ПАДЕНИЕ ВОЖДЯ — ПАРТИЯ ОКОНЧЕНА"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(title_lbl)
	
	# Разделитель
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)
	
	# Причина
	reason_lbl = Label.new()
	reason_lbl.text = "Вождь племени пал в диких землях. Без мудрого предводителя племя рассеялось."
	reason_lbl.add_theme_font_size_override("font_size", 13)
	reason_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.85))
	reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(reason_lbl)
	
	# Статистика правления
	var stat_panel = PanelContainer.new()
	var stat_sbox = StyleBoxFlat.new()
	stat_sbox.bg_color = Color(0.05, 0.05, 0.07, 0.7)
	stat_sbox.set_corner_radius_all(6)
	stat_sbox.set_content_margin_all(10)
	stat_panel.add_theme_stylebox_override("panel", stat_sbox)
	
	stats_lbl = Label.new()
	stats_lbl.text = "Племя просуществовало: 10 суток"
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_panel.add_child(stats_lbl)
	vbox.add_child(stat_panel)
	
	# Кнопки действий
	var btn_vbox = VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_vbox)
	
	btn_quick_load = Button.new()
	btn_quick_load.text = "💾 Загрузить последнее сохранение (F9)"
	btn_quick_load.custom_minimum_size = Vector2(0, 36)
	btn_quick_load.pressed.connect(_on_quick_load_pressed)
	btn_vbox.add_child(btn_quick_load)
	
	btn_restart = Button.new()
	btn_restart.text = "🔄 Начать заново (Новый мир)"
	btn_restart.custom_minimum_size = Vector2(0, 34)
	btn_restart.pressed.connect(_on_restart_pressed)
	btn_vbox.add_child(btn_restart)
	
	btn_menu = Button.new()
	btn_menu.text = "🚪 Выйти в главное меню"
	btn_menu.custom_minimum_size = Vector2(0, 32)
	btn_menu.pressed.connect(_on_menu_pressed)
	btn_vbox.add_child(btn_menu)

func _on_game_over(reason: String) -> void:
	show_game_over(reason)

func show_game_over(reason: String) -> void:
	reason_lbl.text = reason
	
	var total_days = GameManager.total_simulation_days
	var cur_day = GameManager.current_day
	var cur_month = GameManager.current_month
	var cur_year = GameManager.current_year
	
	var s: RefCounted = GameManager.settlements.get("player_tribe_settlement", null)
	var pop_count = s.population.get_total_population() if (s and "population" in s) else 10
	var food_count = int(s.economy.get_resource("food")) if (s and "economy" in s) else 0
	var wood_count = int(s.economy.get_resource("wood")) if (s and "economy" in s) else 0
	
	stats_lbl.text = "⏳ Прожито в симуляции: %d дней (Сутки %d, Месяц %d, Год %d)\n👥 Население: %d чел.  |  🥩 Пища: %d  |  🪵 Древесина: %d" % [
		total_days, cur_day, cur_month, cur_year, pop_count, food_count, wood_count
	]
	
	visible = true
	GameManager.push_modal_pause()

func _on_quick_load_pressed() -> void:
	if SaveSystem.has_save("quicksave"):
		SaveSystem.quick_load()
		visible = false
		GameManager.pop_modal_pause()
	elif SaveSystem.has_save("manual_save_1"):
		SaveSystem.load_game("manual_save_1")
		visible = false
		GameManager.pop_modal_pause()
	else:
		EventBus.notification_toast.emit("Нет сохранений", "Файл автосохранения не найден.", "warning")

func _on_restart_pressed() -> void:
	visible = false
	GameManager.pop_modal_pause()
	GameManager.start_new_game()
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	visible = false
	GameManager.pop_modal_pause()
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
