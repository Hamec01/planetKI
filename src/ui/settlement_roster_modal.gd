class_name SettlementRosterModal
extends Control

# ==============================================================================
# PLANETKI — SETTLEMENT CITIZEN ROSTER MODAL (СПИСОК СОПЛЕМЕННИКОВ)
# Отображает полный список всех жителей поселения: кто он, возраст, когорта,
# профессия, жилье, семья, здоровье, бодрость, сытость, верность и статус.
# ==============================================================================

var current_settlement: SettlementData = null
var settlement: SettlementData:
	get: return current_settlement
	set(val): current_settlement = val
var search_query: String = ""
var filter_job: String = "all"
var filter_cohort: String = "all"
var sort_mode: String = "age_desc"

var backdrop_btn: Button
var main_panel: PanelContainer
var title_lbl: Label
var demo_lbl: Label
var stat_total_label: Label:
	get: return demo_lbl
var search_edit: LineEdit
var job_filter_opt: OptionButton
var cohort_filter_opt: OptionButton
var sort_opt: OptionButton
var count_lbl: Label
var citizens_vbox: VBoxContainer
var cards_container: VBoxContainer:
	get: return citizens_vbox
var scroll_container: ScrollContainer

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Полупрозрачный фон
	backdrop_btn = Button.new()
	backdrop_btn.anchors_preset = Control.PRESET_FULL_RECT
	backdrop_btn.flat = true
	var bd_style = StyleBoxFlat.new()
	bd_style.bg_color = Color(0.02, 0.03, 0.05, 0.75)
	backdrop_btn.add_theme_stylebox_override("normal", bd_style)
	backdrop_btn.add_theme_stylebox_override("hover", bd_style)
	backdrop_btn.add_theme_stylebox_override("pressed", bd_style)
	backdrop_btn.pressed.connect(close)
	add_child(backdrop_btn)
	
	# Центральное окно
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)
	
	main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(980, 680)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.09, 0.11, 0.16, 0.98)
	p_style.border_color = Color(0.35, 0.45, 0.65, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(10)
	p_style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	p_style.shadow_size = 16
	p_style.set_content_margin_all(16)
	main_panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(main_panel)
	
	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	main_panel.add_child(root_vbox)
	
	# --- 1. ШАПКА ОКНА ---
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(header_hbox)
	
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_vbox)
	
	title_lbl = Label.new()
	title_lbl.text = "👥 Жители поселения"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	title_vbox.add_child(title_lbl)
	
	demo_lbl = Label.new()
	demo_lbl.text = "Всего соплеменников: 0"
	demo_lbl.add_theme_font_size_override("font_size", 12)
	demo_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	title_vbox.add_child(demo_lbl)
	
	var close_btn = Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close)
	header_hbox.add_child(close_btn)
	
	# --- 2. ПАНЕЛЬ ФИЛЬТРОВ И ПОИСКА ---
	var filter_bar = PanelContainer.new()
	var fb_style = StyleBoxFlat.new()
	fb_style.bg_color = Color(0.12, 0.15, 0.22, 0.9)
	fb_style.border_color = Color(0.25, 0.35, 0.5, 0.5)
	fb_style.set_border_width_all(1)
	fb_style.set_corner_radius_all(6)
	fb_style.set_content_margin_all(8)
	filter_bar.add_theme_stylebox_override("panel", fb_style)
	root_vbox.add_child(filter_bar)
	
	var fb_hbox = HBoxContainer.new()
	fb_hbox.add_theme_constant_override("separation", 10)
	filter_bar.add_child(fb_hbox)
	
	# Поиск по имени
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "🔍 Поиск по имени или профессии..."
	search_edit.custom_minimum_size = Vector2(240, 32)
	search_edit.text_changed.connect(func(new_text):
		search_query = new_text.strip_edges().to_lower()
		_refresh_citizens_list()
	)
	fb_hbox.add_child(search_edit)
	
	# Фильтр профессии
	var job_lbl = Label.new()
	job_lbl.text = "Профессия:"
	job_lbl.add_theme_font_size_override("font_size", 12)
	fb_hbox.add_child(job_lbl)
	
	job_filter_opt = OptionButton.new()
	job_filter_opt.custom_minimum_size = Vector2(140, 32)
	job_filter_opt.add_item("Все профессии", 0)
	job_filter_opt.add_item("🏹 Охотник", 1)
	job_filter_opt.add_item("🪓 Лесоруб", 2)
	job_filter_opt.add_item("🌾 Собиратель", 3)
	job_filter_opt.add_item("🔨 Строитель", 4)
	job_filter_opt.add_item("⛏ Каменотёс/Рудокоп", 5)
	job_filter_opt.add_item("🏺 Ремесленник", 6)
	job_filter_opt.add_item("📜 Старейшина", 7)
	job_filter_opt.add_item("🛡 Страж", 8)
	job_filter_opt.add_item("💤 Свободный", 9)
	job_filter_opt.item_selected.connect(func(idx):
		match idx:
			0: filter_job = "all"
			1: filter_job = "hunter"
			2: filter_job = "woodcutter"
			3: filter_job = "forager"
			4: filter_job = "builder"
			5: filter_job = "miner_group"
			6: filter_job = "craftsman"
			7: filter_job = "elder"
			8: filter_job = "guard"
			9: filter_job = "idle"
		_refresh_citizens_list()
	)
	fb_hbox.add_child(job_filter_opt)
	
	# Фильтр когорты
	var cohort_lbl = Label.new()
	cohort_lbl.text = "Возраст:"
	cohort_lbl.add_theme_font_size_override("font_size", 12)
	fb_hbox.add_child(cohort_lbl)
	
	cohort_filter_opt = OptionButton.new()
	cohort_filter_opt.custom_minimum_size = Vector2(130, 32)
	cohort_filter_opt.add_item("Все возрасты", 0)
	cohort_filter_opt.add_item("👶 Дети (0-13)", 1)
	cohort_filter_opt.add_item("🧒 Молодёжь (14-17)", 2)
	cohort_filter_opt.add_item("🧑 Взрослые (18-45)", 3)
	cohort_filter_opt.add_item("🧓 Старики (46+)", 4)
	cohort_filter_opt.item_selected.connect(func(idx):
		match idx:
			0: filter_cohort = "all"
			1: filter_cohort = "child"
			2: filter_cohort = "youth"
			3: filter_cohort = "adult"
			4: filter_cohort = "elder"
		_refresh_citizens_list()
	)
	fb_hbox.add_child(cohort_filter_opt)
	
	# Сортировка
	var sort_lbl = Label.new()
	sort_lbl.text = "Сортировка:"
	sort_lbl.add_theme_font_size_override("font_size", 12)
	fb_hbox.add_child(sort_lbl)
	
	sort_opt = OptionButton.new()
	sort_opt.custom_minimum_size = Vector2(130, 32)
	sort_opt.add_item("По возрасту ↓", 0)
	sort_opt.add_item("По возрасту ↑", 1)
	sort_opt.add_item("По здоровью ↓", 2)
	sort_opt.add_item("По верности ↓", 3)
	sort_opt.add_item("По имени А-Я", 4)
	sort_opt.item_selected.connect(func(idx):
		match idx:
			0: sort_mode = "age_desc"
			1: sort_mode = "age_asc"
			2: sort_mode = "health_desc"
			3: sort_mode = "loyalty_desc"
			4: sort_mode = "name_asc"
		_refresh_citizens_list()
	)
	fb_hbox.add_child(sort_opt)
	
	count_lbl = Label.new()
	count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	fb_hbox.add_child(count_lbl)
	
	# --- 3. СКРОЛЛИРУЕМЫЙ СПИСОК ГРАЖДАН ---
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll_container)
	
	citizens_vbox = VBoxContainer.new()
	citizens_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	citizens_vbox.add_theme_constant_override("separation", 8)
	scroll_container.add_child(citizens_vbox)

func open(p_settlement: SettlementData = null) -> void:
	if p_settlement != null:
		current_settlement = p_settlement
	elif GameManager and not GameManager.settlements.is_empty():
		current_settlement = GameManager.settlements.get(GameManager.player_faction_id + "_settlement", GameManager.settlements.values()[0])
	visible = true
	_refresh_citizens_list()

func open_roster(p_settlement: SettlementData = null) -> void:
	open(p_settlement)

func close() -> void:
	visible = false

func close_roster() -> void:
	close()

func toggle(p_settlement: SettlementData = null) -> void:
	if visible:
		close()
	else:
		open(p_settlement)

func _refresh_citizens_list() -> void:
	if not current_settlement or not current_settlement.population:
		demo_lbl.text = "Нет данных о поселении"
		count_lbl.text = "0 жителей"
		return
		
	var all_citizens = current_settlement.population.citizens
	
	# Обновление демографической сводки в шапке
	var total_count = 0
	var men_cnt = 0
	var women_cnt = 0
	var children_cnt = 0
	var youth_cnt = 0
	var adults_cnt = 0
	var elders_cnt = 0
	
	for c in all_citizens:
		if not c.is_alive:
			continue
		total_count += 1
		if c.gender == "m": men_cnt += 1
		else: women_cnt += 1
		
		match c.cohort:
			"child": children_cnt += 1
			"youth": youth_cnt += 1
			"adult": adults_cnt += 1
			"elder": elders_cnt += 1
			
	title_lbl.text = "👥 Жители поселения: %s" % current_settlement.name
	demo_lbl.text = "Всего соплеменников: %d (Мужчин: %d, Женщин: %d) · Детей: %d, Молодёжи: %d, Взрослых: %d, Стариков: %d" % [
		total_count, men_cnt, women_cnt, children_cnt, youth_cnt, adults_cnt, elders_cnt
	]
	
	# Очистка старых строк списка
	for ch in citizens_vbox.get_children():
		ch.queue_free()
		
	# Фильтрация
	var filtered: Array[CitizenNPC] = []
	for c in all_citizens:
		if not c.is_alive:
			continue
			
		# Фильтр по поисковой строке
		if search_query != "":
			var matches_name = c.name.to_lower().contains(search_query)
			var matches_job = _get_job_name_ru(c.job_id).to_lower().contains(search_query)
			if not matches_name and not matches_job:
				continue
				
		# Фильтр по профессии
		if filter_job != "all":
			if filter_job == "miner_group":
				if not (c.job_id in ["quarryman", "miner"]):
					continue
			elif filter_job == "idle":
				if not (c.job_id in ["idle", ""]):
					continue
			elif c.job_id != filter_job:
				continue
				
		# Фильтр по возрастной когорте
		if filter_cohort != "all":
			if c.cohort != filter_cohort:
				continue
				
		filtered.append(c)
		
	# Сортировка
	match sort_mode:
		"age_desc":
			filtered.sort_custom(func(a, b): return a.age > b.age)
		"age_asc":
			filtered.sort_custom(func(a, b): return a.age < b.age)
		"health_desc":
			filtered.sort_custom(func(a, b): return a.health > b.health)
		"loyalty_desc":
			filtered.sort_custom(func(a, b): return a.loyalty > b.loyalty)
		"name_asc":
			filtered.sort_custom(func(a, b): return a.name < b.name)
			
	count_lbl.text = "Показано: %d из %d" % [filtered.size(), total_count]
	
	# Заполнение карточек жителей
	for c in filtered:
		var card = _create_citizen_card(c)
		citizens_vbox.add_child(card)

func _create_citizen_card(c: CitizenNPC) -> PanelContainer:
	var card = PanelContainer.new()
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	sbox.border_color = Color(0.28, 0.38, 0.52, 0.7)
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(6)
	sbox.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sbox)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)
	
	# 1. Портрет жителя
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex = c.get_texture()
	if tex:
		portrait.texture = tex
	hbox.add_child(portrait)
	
	# 2. Основная информация (Имя, возраст, когорта, профессия, жильё, семья)
	var mid_vbox = VBoxContainer.new()
	mid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(mid_vbox)
	
	# Верхняя строка: Имя, пол, возраст, профессия
	var top_line = HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 8)
	mid_vbox.add_child(top_line)
	
	var name_lbl = Label.new()
	name_lbl.text = c.name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	top_line.add_child(name_lbl)
	
	var gender_sign = "♂ Мужчина" if c.gender == "m" else "♀ Женщина"
	var info_badge = Label.new()
	info_badge.text = "· %s, %d лет (%s)" % [gender_sign, c.age, _get_cohort_name_ru(c.cohort)]
	info_badge.add_theme_font_size_override("font_size", 12)
	info_badge.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	top_line.add_child(info_badge)
	
	var job_badge = Label.new()
	job_badge.text = "· %s" % _get_job_icon_name_ru(c.job_id)
	job_badge.add_theme_font_size_override("font_size", 12)
	job_badge.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	top_line.add_child(job_badge)
	
	# Средняя строка: Место работы, Жилье, Семейные связи
	var detail_line = HBoxContainer.new()
	detail_line.add_theme_constant_override("separation", 12)
	mid_vbox.add_child(detail_line)
	
	var home_text = "🏠 Хижина" if c.home_id != "" else "🏕 Без крова"
	var home_lbl = Label.new()
	home_lbl.text = home_text
	home_lbl.add_theme_font_size_override("font_size", 11)
	home_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	detail_line.add_child(home_lbl)
	
	var fam_text = ""
	if c.spouse_id != "":
		var sp = current_settlement.population.find_citizen(c.spouse_id)
		var sp_name = sp.name if sp else "Соплеменник"
		fam_text = "💍 В браке с: %s" % sp_name
	elif c.guardian_id != "":
		var gd = current_settlement.population.find_citizen(c.guardian_id)
		var gd_name = gd.name if gd else "Опекун"
		fam_text = "🛡 Под опекой: %s" % gd_name
	else:
		fam_text = "Холост / Свободен"
	var fam_lbl = Label.new()
	fam_lbl.text = fam_text
	fam_lbl.add_theme_font_size_override("font_size", 11)
	fam_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.9))
	detail_line.add_child(fam_lbl)
	
	var arch_name = "Мастеровой"
	match c.get_personality_archetype():
		"leader": arch_name = "Лидер"
		"fighter": arch_name = "Воин"
		"rebel": arch_name = "Бунтарь"
		"keeper": arch_name = "Хранитель"
		"diplomat": arch_name = "Дипломат"
		"caretaker": arch_name = "Опекун"
		"visionary": arch_name = "Мечтатель"
		"loner": arch_name = "Одиночка"
		"worker": arch_name = "Труженик"
	var arch_lbl = Label.new()
	arch_lbl.text = "🎭 %s" % arch_name
	arch_lbl.add_theme_font_size_override("font_size", 11)
	arch_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	detail_line.add_child(arch_lbl)
	
	# Нижняя строка: Текущее занятие / статус
	var act_lbl = Label.new()
	act_lbl.text = "Действие: %s" % (c.last_status_reason if c.last_status_reason != "" else "Занят делами племени")
	act_lbl.add_theme_font_size_override("font_size", 11)
	act_lbl.add_theme_color_override("font_color", Color(0.65, 0.8, 0.7))
	mid_vbox.add_child(act_lbl)
	
	# 3. Показатели жизнедеятельности (Здоровье, Бодрость, Сытость, Верность)
	var vitals_vbox = VBoxContainer.new()
	vitals_vbox.custom_minimum_size = Vector2(170, 0)
	vitals_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vitals_vbox)
	
	vitals_vbox.add_child(_create_vital_row("❤️ Здоровье", c.health, Color(0.85, 0.25, 0.25)))
	vitals_vbox.add_child(_create_vital_row("🍗 Сытость", c.hunger, Color(0.85, 0.55, 0.15)))
	vitals_vbox.add_child(_create_vital_row("⚡ Бодрость", c.energy, Color(0.25, 0.65, 0.85)))
	vitals_vbox.add_child(_create_vital_row("🤝 Верность", c.loyalty, Color(0.45, 0.85, 0.45)))
	
	# 4. Кнопки действий (Найти на карте / Досье)
	var actions_vbox = VBoxContainer.new()
	actions_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	actions_vbox.custom_minimum_size = Vector2(110, 0)
	actions_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(actions_vbox)
	
	var cam_btn = Button.new()
	cam_btn.text = "🔍 На карте"
	cam_btn.add_theme_font_size_override("font_size", 11)
	cam_btn.pressed.connect(func():
		_focus_camera_on_citizen(c)
	)
	actions_vbox.add_child(cam_btn)
	
	var inspect_btn = Button.new()
	inspect_btn.text = "ℹ️ Досье"
	inspect_btn.add_theme_font_size_override("font_size", 11)
	inspect_btn.pressed.connect(func():
		EventBus.citizen_selected.emit(c)
		close()
	)
	actions_vbox.add_child(inspect_btn)
	
	return card

func _create_vital_row(title: String, val: float, bar_color: Color) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	
	var lbl = Label.new()
	lbl.text = title
	lbl.custom_minimum_size = Vector2(75, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	row.add_child(lbl)
	
	var pbar = ProgressBar.new()
	pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pbar.custom_minimum_size = Vector2(60, 8)
	pbar.show_percentage = false
	pbar.min_value = 0.0
	pbar.max_value = 100.0
	pbar.value = val
	
	var fg = StyleBoxFlat.new()
	fg.bg_color = bar_color
	fg.set_corner_radius_all(2)
	pbar.add_theme_stylebox_override("fill", fg)
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.13, 0.8)
	bg.set_corner_radius_all(2)
	pbar.add_theme_stylebox_override("background", bg)
	row.add_child(pbar)
	
	var val_lbl = Label.new()
	val_lbl.text = "%d%%" % int(val)
	val_lbl.custom_minimum_size = Vector2(30, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 10)
	val_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(val_lbl)
	
	return row

func _focus_camera_on_citizen(c: CitizenNPC) -> void:
	if c and is_instance_valid(c):
		EventBus.citizen_selected.emit(c)
		if EventBus.has_signal("camera_focus_requested"):
			EventBus.camera_focus_requested.emit(c.pos)
		close()

func _get_cohort_name_ru(cohort: String) -> String:
	match cohort:
		"child": return "Ребёнок"
		"youth": return "Молодёжь"
		"adult": return "Взрослый"
		"elder": return "Старейшина / Старик"
		_: return "Взрослый"

func _get_job_name_ru(job_id: String) -> String:
	match job_id:
		"hunter": return "Охотник"
		"woodcutter": return "Лесоруб"
		"forager": return "Собиратель"
		"builder": return "Строитель"
		"quarryman": return "Каменотёс"
		"miner": return "Рудокоп"
		"craftsman": return "Ремесленник"
		"elder": return "Старейшина"
		"guard": return "Страж"
		"priest": return "Жрец"
		"sage": return "Мудрец"
		"fisherman": return "Рыбак"
		"farmer": return "Земледелец"
		_: return "Свободный житель"

func _get_job_icon_name_ru(job_id: String) -> String:
	match job_id:
		"hunter": return "🏹 Охотник"
		"woodcutter": return "🪓 Лесоруб"
		"forager": return "🌾 Собиратель"
		"builder": return "🔨 Строитель"
		"quarryman": return "⛏ Каменотёс"
		"miner": return "⛏ Рудокоп"
		"craftsman": return "🏺 Ремесленник"
		"elder": return "📜 Старейшина"
		"guard": return "🛡 Страж"
		"priest": return "🔮 Жрец"
		"sage": return "📖 Мудрец"
		"fisherman": return "🎣 Рыбак"
		"farmer": return "🌱 Земледелец"
		_: return "💤 Свободный"
