class_name CemeteryMemorialModal
extends Control

# ==============================================================================
# PLANETKI — CEMETERY MEMORIAL MODAL (РОДОВОЙ МОГИЛЬНИК / КНИГА ПАМЯТИ)
# Единый мемориал поселения (кладбище макс 4 клетки).
# Отображает список всех умерших соплеменников и по клику открывает полную сводку:
# когда умер, от чего погиб, возраст, профессию, семью, заслуги и память предков.
# ==============================================================================

var current_settlement: SettlementData = null
var current_building_inst: BuildingInstance = null
var selected_deceased_id: String = ""
var search_query: String = ""
var filter_category: String = "all"
var sort_mode: String = "recent_death"

var backdrop_btn: Button
var main_panel: PanelContainer
var title_lbl: Label
var subtitle_lbl: Label
var search_edit: LineEdit
var filter_opt: OptionButton
var sort_opt: OptionButton
var deceased_list_vbox: VBoxContainer
var list_scroll: ScrollContainer
var count_lbl: Label

# Панель полной сводки (правая колонка)
var dossier_panel: PanelContainer
var dossier_vbox: VBoxContainer

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Полупрозрачный затемняющий фон
	backdrop_btn = Button.new()
	backdrop_btn.anchors_preset = Control.PRESET_FULL_RECT
	backdrop_btn.flat = true
	var bd_style = StyleBoxFlat.new()
	bd_style.bg_color = Color(0.02, 0.03, 0.06, 0.82)
	backdrop_btn.add_theme_stylebox_override("normal", bd_style)
	backdrop_btn.add_theme_stylebox_override("hover", bd_style)
	backdrop_btn.add_theme_stylebox_override("pressed", bd_style)
	backdrop_btn.pressed.connect(close)
	add_child(backdrop_btn)
	
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)
	
	main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(980, 680)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.10, 0.14, 0.98)
	p_style.border_color = Color(0.40, 0.48, 0.58, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(12)
	p_style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	p_style.shadow_size = 20
	p_style.set_content_margin_all(18)
	main_panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(main_panel)
	
	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	main_panel.add_child(root_vbox)
	
	# --- 1. ШАПКА ОКНА ---
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header_hbox)
	
	var header_vbox = VBoxContainer.new()
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_theme_constant_override("separation", 3)
	header_hbox.add_child(header_vbox)
	
	title_lbl = Label.new()
	title_lbl.text = "🪦 Родовой Могильник · Книга Памяти Предков"
	title_lbl.add_theme_font_size_override("font_size", 21)
	title_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	header_vbox.add_child(title_lbl)
	
	subtitle_lbl = Label.new()
	subtitle_lbl.text = "Священное место упокоения всех поколений рода · Площадь могильника: 1 из 4 участков"
	subtitle_lbl.add_theme_font_size_override("font_size", 12)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82))
	header_vbox.add_child(subtitle_lbl)
	
	var tribute_all_btn = Button.new()
	tribute_all_btn.text = "🕯 Почтить всех предков (+3 Веры)"
	tribute_all_btn.add_theme_font_size_override("font_size", 12)
	tribute_all_btn.pressed.connect(_on_tribute_all_pressed)
	header_hbox.add_child(tribute_all_btn)
	
	var close_btn = Button.new()
	close_btn.text = "✕ Закрыть"
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(close)
	header_hbox.add_child(close_btn)
	
	# --- 2. ПАНЕЛЬ ФИЛЬТРОВ И ПОИСКА ---
	var filter_hbox = HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(filter_hbox)
	
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "🔍 Поиск по имени или причине гибели..."
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_changed.connect(func(new_text):
		search_query = new_text.strip_edges().to_lower()
		_refresh_list()
	)
	filter_hbox.add_child(search_edit)
	
	filter_opt = OptionButton.new()
	filter_opt.add_item("Все упокоенные", 0)
	filter_opt.add_item("⚔️ Павшие в бою", 1)
	filter_opt.add_item("👴 Преклонный возраст", 2)
	filter_opt.add_item("🏹 Охотники и воины", 3)
	filter_opt.add_item("👶 Дети и юноши", 4)
	filter_opt.item_selected.connect(func(idx):
		match idx:
			0: filter_category = "all"
			1: filter_category = "battle"
			2: filter_category = "old_age"
			3: filter_category = "hunters"
			4: filter_category = "youth"
		_refresh_list()
	)
	filter_hbox.add_child(filter_opt)
	
	sort_opt = OptionButton.new()
	sort_opt.add_item("Сначала недавние", 0)
	sort_opt.add_item("Сначала древние", 1)
	sort_opt.add_item("По возрасту (старшие)", 2)
	sort_opt.add_item("По имени (А-Я)", 3)
	sort_opt.item_selected.connect(func(idx):
		match idx:
			0: sort_mode = "recent_death"
			1: sort_mode = "oldest_death"
			2: sort_mode = "age_desc"
			3: sort_mode = "name_asc"
		_refresh_list()
	)
	filter_hbox.add_child(sort_opt)
	
	count_lbl = Label.new()
	count_lbl.text = "Упокоено: 0"
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.90))
	filter_hbox.add_child(count_lbl)
	
	# --- 3. ДВУХКОЛОНОЧНЫЙ БЛОК: СПИСОК СЛЕВА + ПОЛНАЯ СВОДКА СПРАВА ---
	var body_hsplit = HSplitContainer.new()
	body_hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hsplit.split_offset = 420
	root_vbox.add_child(body_hsplit)
	
	# Левая колонка: Прокручиваемый список карточек умерших
	var left_panel = PanelContainer.new()
	var l_style = StyleBoxFlat.new()
	l_style.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	l_style.border_color = Color(0.25, 0.32, 0.42, 0.65)
	l_style.set_border_width_all(1)
	l_style.set_corner_radius_all(8)
	l_style.set_content_margin_all(8)
	left_panel.add_theme_stylebox_override("panel", l_style)
	body_hsplit.add_child(left_panel)
	
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(list_scroll)
	
	deceased_list_vbox = VBoxContainer.new()
	deceased_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deceased_list_vbox.add_theme_constant_override("separation", 6)
	list_scroll.add_child(deceased_list_vbox)
	
	# Правая колонка: Панель полного досье предка
	dossier_panel = PanelContainer.new()
	var d_style = StyleBoxFlat.new()
	d_style.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	d_style.border_color = Color(0.35, 0.45, 0.58, 0.75)
	d_style.set_border_width_all(1)
	d_style.set_corner_radius_all(8)
	d_style.set_content_margin_all(14)
	dossier_panel.add_theme_stylebox_override("panel", d_style)
	body_hsplit.add_child(dossier_panel)
	
	var dossier_scroll = ScrollContainer.new()
	dossier_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dossier_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dossier_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dossier_panel.add_child(dossier_scroll)
	
	dossier_vbox = VBoxContainer.new()
	dossier_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dossier_vbox.add_theme_constant_override("separation", 10)
	dossier_scroll.add_child(dossier_vbox)

func open(s: SettlementData = null, b_inst: BuildingInstance = null) -> void:
	current_settlement = s
	if current_settlement == null and GameManager:
		current_settlement = GameManager.get_player_settlement()
	current_building_inst = b_inst
	selected_deceased_id = ""
	visible = true
	_refresh_list()

func close() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _refresh_list() -> void:
	if not visible or current_settlement == null:
		return
		
	for ch in deceased_list_vbox.get_children():
		ch.queue_free()
		
	var all_records = current_settlement.get_deceased_registry()
	var total_count = all_records.size()
	
	var cemetery_plots_count = max(1, current_settlement.cemetery_plots.size())
	subtitle_lbl.text = "Поселение: %s · Всего упокоено: %d соплеменников · Участков кладбища: %d из %d" % [
		current_settlement.name, total_count, cemetery_plots_count, SettlementData.MAX_CEMETERY_PLOTS
	]
	
	if total_count == 0:
		count_lbl.text = "Упокоено: 0"
		var empty_lbl = Label.new()
		empty_lbl.text = "🕊 В этом родовом могильнике пока нет захоронений.\nПусть предки хранят живых соплеменников в мире и здравии!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 0.7))
		deceased_list_vbox.add_child(empty_lbl)
		_render_dossier(null)
		return
		
	# Фильтрация
	var filtered: Array[Dictionary] = []
	for rec in all_records:
		var name_str = rec.get("name", "").to_lower()
		var cause_str = rec.get("death_cause", "").to_lower()
		var job_str = rec.get("job_title", rec.get("job_id", "")).to_lower()
		
		if search_query != "":
			if not name_str.contains(search_query) and not cause_str.contains(search_query) and not job_str.contains(search_query):
				continue
				
		if filter_category != "all":
			match filter_category:
				"battle":
					if not (cause_str.contains("бой") or cause_str.contains("ранен") or cause_str.contains("пал") or cause_str.contains("стрел") or cause_str.contains("клык")):
						continue
				"old_age":
					if not (cause_str.contains("возраст") or cause_str.contains("стар") or cause_str.contains("покой")):
						continue
				"hunters":
					var j_id = rec.get("job_id", "")
					if not (j_id in ["hunter", "warrior", "guard", "scout"]):
						continue
				"youth":
					var c_age = int(rec.get("age", 0))
					if c_age >= 18:
						continue
						
		filtered.append(rec)
		
	# Сортировка
	match sort_mode:
		"recent_death":
			filtered.sort_custom(func(a, b):
				var ya = int(a.get("death_year", 0))
				var yb = int(b.get("death_year", 0))
				if ya != yb: return ya > yb
				return int(a.get("death_day", 0)) > int(b.get("death_day", 0))
			)
		"oldest_death":
			filtered.sort_custom(func(a, b):
				var ya = int(a.get("death_year", 0))
				var yb = int(b.get("death_year", 0))
				if ya != yb: return ya < yb
				return int(a.get("death_day", 0)) < int(b.get("death_day", 0))
			)
		"age_desc":
			filtered.sort_custom(func(a, b): return int(a.get("age", 0)) > int(b.get("age", 0)))
		"name_asc":
			filtered.sort_custom(func(a, b): return a.get("name", "") < b.get("name", ""))
			
	count_lbl.text = "Показано: %d из %d" % [filtered.size(), total_count]
	
	# Если выбранный ранее предок есть в списке — держим его, иначе выбираем первого
	var selected_record = null
	for rec in filtered:
		if rec.get("citizen_id", "") == selected_deceased_id:
			selected_record = rec
			break
	if selected_record == null and not filtered.is_empty():
		selected_record = filtered[0]
		selected_deceased_id = selected_record.get("citizen_id", "")
		
	for rec in filtered:
		var card = _create_deceased_card(rec, rec == selected_record)
		deceased_list_vbox.add_child(card)
		
	_render_dossier(selected_record)

func _create_deceased_card(rec: Dictionary, is_selected: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var style = StyleBoxFlat.new()
	if is_selected:
		style.bg_color = Color(0.18, 0.24, 0.34, 0.98)
		style.border_color = Color(0.85, 0.75, 0.45, 0.95)
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.11, 0.13, 0.18, 0.92)
		style.border_color = Color(0.24, 0.28, 0.36, 0.70)
		style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_child(hbox)
	
	# Иконка / Аватар
	var icon_lbl = Label.new()
	var cause = rec.get("death_cause", "")
	var icon_sym = "🪦"
	if cause.contains("бой") or cause.contains("пал") or cause.contains("ранен"):
		icon_sym = "⚔️"
	elif cause.contains("волк") or cause.contains("медвед") or cause.contains("хищник"):
		icon_sym = "🐺"
	elif cause.contains("возраст") or cause.contains("старост"):
		icon_sym = "👴"
	elif cause.contains("холод") or cause.contains("замерз"):
		icon_sym = "❄️"
	elif cause.contains("голод"):
		icon_sym = "🥣"
	icon_lbl.text = icon_sym
	icon_lbl.add_theme_font_size_override("font_size", 20)
	hbox.add_child(icon_lbl)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "%s (%d лет)" % [rec.get("name", "Безымянный"), int(rec.get("age", 0))]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72) if is_selected else Color(0.90, 0.90, 0.90))
	info_vbox.add_child(name_lbl)
	
	var sub_lbl = Label.new()
	var d_yr = int(rec.get("death_year", 1))
	var d_season = rec.get("death_season", "Лето")
	var d_day = int(rec.get("death_day", 1))
	var j_name = rec.get("job_title", rec.get("job_id", "соплеменник"))
	sub_lbl.text = "† Год %d (%s, день %d) · %s" % [d_yr, d_season, d_day, j_name]
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	info_vbox.add_child(sub_lbl)
	
	btn.pressed.connect(func():
		selected_deceased_id = rec.get("citizen_id", "")
		_refresh_list()
	)
	
	return btn

func _render_dossier(rec) -> void:
	for ch in dossier_vbox.get_children():
		ch.queue_free()
		
	if rec == null:
		var empty_dossier = Label.new()
		empty_dossier.text = "Выберите соплеменника из списка слева, чтобы открыть полную сводку жизни и гибели."
		empty_dossier.add_theme_font_size_override("font_size", 13)
		empty_dossier.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		dossier_vbox.add_child(empty_dossier)
		return
		
	# 1. Шапка досье (Портрет + Имя + Род)
	var header_box = HBoxContainer.new()
	header_box.add_theme_constant_override("separation", 14)
	dossier_vbox.add_child(header_box)
	
	var big_portrait = TextureRect.new()
	big_portrait.custom_minimum_size = Vector2(80, 80)
	big_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sp_path = rec.get("sprite_path", "")
	if sp_path != "" and ResourceLoader.exists(sp_path):
		var t = load(sp_path)
		if t is Texture2D:
			big_portrait.texture = t
	header_box.add_child(big_portrait)
	
	var d_title_vbox = VBoxContainer.new()
	d_title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_title_vbox.add_theme_constant_override("separation", 3)
	header_box.add_child(d_title_vbox)
	
	var dec_name_lbl = Label.new()
	dec_name_lbl.text = rec.get("name", "Безымянный")
	dec_name_lbl.add_theme_font_size_override("font_size", 20)
	dec_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.50))
	d_title_vbox.add_child(dec_name_lbl)
	
	var status_line = Label.new()
	var g_str = "Мужчина рода" if rec.get("gender", "m") == "m" else "Женщина рода"
	var j_title = rec.get("job_title", rec.get("job_id", "соплеменник"))
	status_line.text = "🏛 %s · %s" % [g_str, j_title]
	status_line.add_theme_font_size_override("font_size", 13)
	status_line.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98))
	d_title_vbox.add_child(status_line)
	
	var lifetime_line = Label.new()
	var b_yr = int(rec.get("birth_year", 1))
	var d_yr = int(rec.get("death_year", 1))
	var age = int(rec.get("age", 0))
	lifetime_line.text = "⏳ Годы жизни: Родился в Год %d — Упокоился в Год %d (прожил %d лет)" % [b_yr, d_yr, age]
	lifetime_line.add_theme_font_size_override("font_size", 12)
	lifetime_line.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65))
	d_title_vbox.add_child(lifetime_line)
	
	# Разделитель
	dossier_vbox.add_child(HSeparator.new())
	
	# 2. Обстоятельства гибели
	var death_title = Label.new()
	death_title.text = "☠️ ОБСТОЯТЕЛЬСТВА ГИБЕЛИ И ПОГРЕБЕНИЯ"
	death_title.add_theme_font_size_override("font_size", 13)
	death_title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	dossier_vbox.add_child(death_title)
	
	var death_panel = PanelContainer.new()
	var dp_style = StyleBoxFlat.new()
	dp_style.bg_color = Color(0.12, 0.08, 0.08, 0.90)
	dp_style.border_color = Color(0.55, 0.25, 0.25, 0.70)
	dp_style.set_border_width_all(1)
	dp_style.set_corner_radius_all(6)
	dp_style.set_content_margin_all(10)
	death_panel.add_theme_stylebox_override("panel", dp_style)
	dossier_vbox.add_child(death_panel)
	
	var death_vbox = VBoxContainer.new()
	death_vbox.add_theme_constant_override("separation", 4)
	death_panel.add_child(death_vbox)
	
	var death_time_lbl = Label.new()
	var d_season = rec.get("death_season", "Лето")
	var d_day = int(rec.get("death_day", 1))
	death_time_lbl.text = "📅 Время кончины: Год %d, %s, День %d" % [d_yr, d_season, d_day]
	death_time_lbl.add_theme_font_size_override("font_size", 12)
	death_time_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.85))
	death_vbox.add_child(death_time_lbl)
	
	var death_cause_lbl = Label.new()
	death_cause_lbl.text = "📜 Причина смерти: %s" % rec.get("death_cause", "Угас от старости")
	death_cause_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	death_cause_lbl.add_theme_font_size_override("font_size", 13)
	death_cause_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.92))
	death_vbox.add_child(death_cause_lbl)
	
	var burial_place_lbl = Label.new()
	burial_place_lbl.text = "🕊 Погребён с почестями в священной земле родового могильника."
	burial_place_lbl.add_theme_font_size_override("font_size", 11)
	burial_place_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
	death_vbox.add_child(burial_place_lbl)
	
	# 3. Семья, род и близкие
	var fam_title = Label.new()
	fam_title.text = "👨‍👩‍👧‍👦 РОД И СЕМЕЙНЫЕ СВЯЗИ"
	fam_title.add_theme_font_size_override("font_size", 13)
	fam_title.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	dossier_vbox.add_child(fam_title)
	
	var fam_info_lbl = Label.new()
	var sp_name = rec.get("spouse_name", "Нет / Холост")
	var ch_names: Array = rec.get("children_names", [])
	var ch_str = ", ".join(ch_names) if not ch_names.is_empty() else "Нет прямых потомков"
	fam_info_lbl.text = "💍 Супруг(а): %s\n👶 Дети и потомки: %s" % [sp_name, ch_str]
	fam_info_lbl.add_theme_font_size_override("font_size", 12)
	fam_info_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95))
	dossier_vbox.add_child(fam_info_lbl)
	
	# 4. Прижизненный путь и заслуги
	var deeds_title = Label.new()
	deeds_title.text = "📜 ПРИЖИЗНЕННЫЙ ПУТЬ И ЗАСЛУГИ ПЕРЕД РОДОМ"
	deeds_title.add_theme_font_size_override("font_size", 13)
	deeds_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	dossier_vbox.add_child(deeds_title)
	
	var summary_lbl = Label.new()
	var summary_text = rec.get("lifetime_summary", "")
	if summary_text == "":
		summary_text = "Трудился на благо рода, добывал пропитание и оберегал очаг своего племени. Память о его трудах навсегда сохранена в сердцах соплеменников."
	summary_lbl.text = summary_text
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_lbl.add_theme_font_size_override("font_size", 12)
	summary_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	dossier_vbox.add_child(summary_lbl)
	
	# Черты характера
	var raw_traits = rec.get("traits", null)
	var traits_list: Array[String] = []
	if raw_traits is Array:
		for t in raw_traits:
			traits_list.append(str(t))
	elif raw_traits is Dictionary:
		for k in raw_traits:
			traits_list.append(str(k))
			
	if not traits_list.is_empty():
		var traits_lbl = Label.new()
		traits_lbl.text = "✨ Черты характера: %s" % ", ".join(traits_list)
		traits_lbl.add_theme_font_size_override("font_size", 11)
		traits_lbl.add_theme_color_override("font_color", Color(0.70, 0.95, 0.75))
		dossier_vbox.add_child(traits_lbl)
		
	# 5. Статус осквернения могилы (если было осквернено недругом)
	var is_defiled = rec.get("is_defiled", false)
	var defiled_by = rec.get("defiled_by", "")
	if is_defiled or defiled_by != "":
		var defiled_panel = PanelContainer.new()
		var df_style = StyleBoxFlat.new()
		df_style.bg_color = Color(0.20, 0.05, 0.05, 0.95)
		df_style.border_color = Color(0.95, 0.35, 0.25, 0.90)
		df_style.set_border_width_all(1)
		df_style.set_corner_radius_all(6)
		df_style.set_content_margin_all(8)
		defiled_panel.add_theme_stylebox_override("panel", df_style)
		dossier_vbox.add_child(defiled_panel)
		
		var defiled_lbl = Label.new()
		defiled_lbl.text = "⚡ Могила была осквернена (%s)! Почтите память или возложите дары для освящения святыни." % (defiled_by if defiled_by != "" else "недругом")
		defiled_lbl.add_theme_font_size_override("font_size", 12)
		defiled_lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.60))
		defiled_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		defiled_panel.add_child(defiled_lbl)

	# 6. Кнопки почитания памяти
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 10)
	dossier_vbox.add_child(actions_hbox)
	
	var tribute_btn = Button.new()
	tribute_btn.text = "🕯 Почтить память (%s)" % rec.get("name", "предка")
	tribute_btn.add_theme_font_size_override("font_size", 12)
	tribute_btn.pressed.connect(func():
		var name_val = rec.get("name", "соплеменника")
		if rec.get("is_defiled", false) or rec.get("defiled_by", "") != "":
			rec["is_defiled"] = false
			rec["defiled_by"] = ""
			EventBus.notification_toast.emit("🕊 Память предков", "Вы почтили память %s и очистили осквернённую могилу (+2 Веры, +2 Лояльности)." % name_val, "good")
		else:
			EventBus.notification_toast.emit("🕯 Память предков", "Вы почтили память %s. Память укрепляет дух племени (+2 Веры, +2 Лояльности)." % name_val, "good")
		if current_settlement and current_settlement.economy:
			current_settlement.economy.add_resource("faith", 2.0)
			current_settlement.economy.loyalty = minf(100.0, current_settlement.economy.loyalty + 2.0)
		_refresh_list()
	)
	actions_hbox.add_child(tribute_btn)
	
	var offer_gifts_btn = Button.new()
	offer_gifts_btn.text = "🌸 Возложить дары (-1 Еда → +Благословение)"
	offer_gifts_btn.add_theme_font_size_override("font_size", 12)
	offer_gifts_btn.pressed.connect(func():
		if current_settlement and current_settlement.economy:
			if current_settlement.economy.get_resource("food") >= 1.0:
				current_settlement.economy.add_resource("food", -1.0)
				current_settlement.economy.add_resource("faith", 4.0)
				rec["is_defiled"] = false
				rec["defiled_by"] = ""
				EventBus.notification_toast.emit("🌸 Дары предкам", "Вы возложили дары на родовом могильнике. Духи предков благословляют племя (+4 Веры).", "good")
				_refresh_list()
			else:
				EventBus.notification_toast.emit("⚠️ Недостаточно пищи", "В поселении нет припасов для подношения предкам.", "warning")
	)
	actions_hbox.add_child(offer_gifts_btn)

func _on_tribute_all_pressed() -> void:
	if current_settlement and current_settlement.economy:
		current_settlement.economy.add_resource("faith", 3.0)
		current_settlement.economy.loyalty = minf(100.0, current_settlement.economy.loyalty + 3.0)
		EventBus.notification_toast.emit("🕯 Великое поминовение предков", "Все соплеменники почтили память покоящихся в родовом могильнике (+3 Веры, +3 Лояльности).", "good")
