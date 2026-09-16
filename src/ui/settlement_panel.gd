class_name SettlementPanel
extends Control

@onready var settlement_name_label: Label = $CenterContainer/Panel/Margin/VBox/Header/Title
@onready var close_btn: Button = $CenterContainer/Panel/Margin/VBox/Header/CloseBtn
@onready var backdrop_btn: Button = $Backdrop

var tab_container: TabContainer
var settlement: SettlementData = null
var target_build_coord: Vector2i = Vector2i(-1, -1)

# Вкладка 1: Жители и Профессии
var pop_cohorts_label: Label
var housing_label: Label
var idle_workers_label: Label
var jobs_container: VBoxContainer

# Вкладка 2: Строительство и Очередь
var queue_vbox: VBoxContainer
var catalog_vbox: VBoxContainer

# Вкладка 3: Построенные здания
var built_list_vbox: VBoxContainer

# Вкладка 4: Экономика
var economy_text: RichTextLabel

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(func(): visible = false)
	backdrop_btn.pressed.connect(func(): visible = false)
	EventBus.day_passed.connect(_on_tick)
	EventBus.settlement_selected.connect(_on_settlement_selected)
	
	_setup_tabbed_interface()

func _setup_tabbed_interface() -> void:
	var root_vbox = $CenterContainer/Panel/Margin/VBox
	
	# Скрываем старые ноды если они есть
	if root_vbox.has_node("PopBox"):
		root_vbox.get_node("PopBox").visible = false
	if root_vbox.has_node("ContentSplit"):
		root_vbox.get_node("ContentSplit").visible = false
		
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.custom_minimum_size = Vector2(860, 520)
	
	# --- ВКЛАДКА 1: НАСЕЛЕНИЕ И ПРОФЕССИИ ---
	var tab1 = MarginContainer.new()
	tab1.name = "👥 Жители и Профессии"
	tab1.add_theme_constant_override("margin_left", 12)
	tab1.add_theme_constant_override("margin_right", 12)
	tab1.add_theme_constant_override("margin_top", 12)
	tab1.add_theme_constant_override("margin_bottom", 12)
	
	var tab1_vbox = VBoxContainer.new()
	tab1_vbox.add_theme_constant_override("separation", 10)
	
	# Демография
	var demo_card = PanelContainer.new()
	var sbox_demo = StyleBoxFlat.new()
	sbox_demo.bg_color = Color(0.1, 0.13, 0.19, 0.95)
	sbox_demo.border_color = Color(0.25, 0.35, 0.5, 0.7)
	sbox_demo.set_border_width_all(1)
	sbox_demo.set_corner_radius_all(8)
	sbox_demo.set_content_margin_all(10)
	demo_card.add_theme_stylebox_override("panel", sbox_demo)
	
	var demo_vbox = VBoxContainer.new()
	var demo_title = Label.new()
	demo_title.text = "📊 Демографический состав и жильё"
	demo_title.add_theme_font_size_override("font_size", 14)
	demo_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	demo_vbox.add_child(demo_title)
	
	pop_cohorts_label = Label.new()
	pop_cohorts_label.add_theme_font_size_override("font_size", 12)
	demo_vbox.add_child(pop_cohorts_label)
	
	housing_label = Label.new()
	housing_label.add_theme_font_size_override("font_size", 12)
	demo_vbox.add_child(housing_label)
	
	idle_workers_label = Label.new()
	idle_workers_label.add_theme_font_size_override("font_size", 12)
	idle_workers_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	demo_vbox.add_child(idle_workers_label)
	
	demo_card.add_child(demo_vbox)
	tab1_vbox.add_child(demo_card)
	
	# Профессии (Скролл)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jobs_container = VBoxContainer.new()
	jobs_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jobs_container.add_theme_constant_override("separation", 6)
	scroll.add_child(jobs_container)
	tab1_vbox.add_child(scroll)
	
	tab1.add_child(tab1_vbox)
	tab_container.add_child(tab1)
	
	# --- ВКЛАДКА 2: СТРОИТЕЛЬСТВО И ОЧЕРЕДЬ ---
	var tab2 = MarginContainer.new()
	tab2.name = "🔨 Строительство"
	tab2.add_theme_constant_override("margin_left", 12)
	tab2.add_theme_constant_override("margin_right", 12)
	tab2.add_theme_constant_override("margin_top", 12)
	tab2.add_theme_constant_override("margin_bottom", 12)
	
	var hsplit = HBoxContainer.new()
	hsplit.add_theme_constant_override("separation", 14)
	
	# Левая колонка: Очередь
	var left_box = VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.size_flags_stretch_ratio = 0.45
	var q_title = Label.new()
	q_title.text = "🏗 Текущая очередь стройки"
	q_title.add_theme_font_size_override("font_size", 14)
	q_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	left_box.add_child(q_title)
	
	var q_scroll = ScrollContainer.new()
	q_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_vbox = VBoxContainer.new()
	queue_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_vbox.add_theme_constant_override("separation", 6)
	q_scroll.add_child(queue_vbox)
	left_box.add_child(q_scroll)
	hsplit.add_child(left_box)
	
	# Правая колонка: Каталог доступных проектов
	var right_box = VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_stretch_ratio = 0.55
	var cat_title = Label.new()
	cat_title.text = "📜 Доступные проекты эпохи"
	cat_title.add_theme_font_size_override("font_size", 14)
	cat_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	right_box.add_child(cat_title)
	
	var cat_scroll = ScrollContainer.new()
	cat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_vbox = VBoxContainer.new()
	catalog_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_vbox.add_theme_constant_override("separation", 6)
	cat_scroll.add_child(catalog_vbox)
	right_box.add_child(cat_scroll)
	hsplit.add_child(right_box)
	
	tab2.add_child(hsplit)
	tab_container.add_child(tab2)
	
	# --- ВКЛАДКА 3: ПОСТРОЕННЫЕ ЗДАНИЯ ---
	var tab3 = MarginContainer.new()
	tab3.name = "🏛 Построенные объекты"
	tab3.add_theme_constant_override("margin_left", 12)
	tab3.add_theme_constant_override("margin_right", 12)
	tab3.add_theme_constant_override("margin_top", 12)
	tab3.add_theme_constant_override("margin_bottom", 12)
	
	var tab3_scroll = ScrollContainer.new()
	tab3_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab3_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	built_list_vbox = VBoxContainer.new()
	built_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	built_list_vbox.add_theme_constant_override("separation", 6)
	tab3_scroll.add_child(built_list_vbox)
	tab3.add_child(tab3_scroll)
	tab_container.add_child(tab3)
	
	# --- ВКЛАДКА 4: СВОДНЫЙ БЮДЖЕТ И ДОХОДЫ ---
	var tab4 = MarginContainer.new()
	tab4.name = "📈 Экономика и Баланс"
	tab4.add_theme_constant_override("margin_left", 12)
	tab4.add_theme_constant_override("margin_right", 12)
	tab4.add_theme_constant_override("margin_top", 12)
	tab4.add_theme_constant_override("margin_bottom", 12)
	
	economy_text = RichTextLabel.new()
	economy_text.bbcode_enabled = true
	economy_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	economy_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab4.add_child(economy_text)
	tab_container.add_child(tab4)
	
	root_vbox.add_child(tab_container)

func _on_settlement_selected(s: SettlementData) -> void:
	if s == null:
		return
	settlement = s
	visible = true
	_refresh_ui()

func _on_tick(_d: int, _m: int, _y: int) -> void:
	if visible and settlement != null:
		_refresh_ui()

func open_for_player(tab_index: int = 0, build_coord: Vector2i = Vector2i(-1, -1)) -> void:
	settlement = GameManager.settlements.get("player_tribe_settlement", null)
	target_build_coord = build_coord
	visible = true
	if tab_container and tab_index >= 0 and tab_index < tab_container.get_tab_count():
		tab_container.current_tab = tab_index
	_refresh_ui()

func _refresh_ui() -> void:
	if settlement == null:
		return
		
	settlement_name_label.text = "🏛 %s (Эпоха 1 — Племя)" % settlement.name
	var pop = settlement.population
	pop_cohorts_label.text = "👶 Дети: %d  |  🧒 Юноши: %d  |  🧑 Взрослые (М/Ж): %d / %d  |  🧓 Старейшины: %d  |  👴 Старики: %d" % [
		pop.children, pop.youth, pop.adults_m, pop.adults_f, pop.elders, pop.old_folk
	]
	housing_label.text = "🏠 Жилой фонд: %d / %d мест   •   🛡 Обороноспособность: %.1f" % [
		pop.get_total_population(), settlement.get_housing_capacity(), settlement.get_defense_rating()
	]
	
	idle_workers_label.text = "⚡ Свободные рабочие руки: %d (Всего способных трудиться: %d)" % [
		settlement.get_idle_workforce(), pop.get_workforce_total()
	]
	
	_populate_jobs()
	_populate_queue()
	_populate_catalog()
	_populate_built_buildings()
	_populate_economy_ledger()

func _populate_jobs() -> void:
	for child in jobs_container.get_children():
		child.queue_free()
		
	var job_configs = [
		{"id": "hunter", "name": "Охотники", "prod": "+1.4 🍗/дн", "icon_key": "hunter", "fallback": "🏹"},
		{"id": "forager", "name": "Собиратели", "prod": "+1.1 🍗/дн", "icon_key": "forager", "fallback": "🧺"},
		{"id": "farmer", "name": "Земледельцы", "prod": "+1.8 🍗/дн (осенью)", "icon_key": "farmer", "fallback": "🌾"},
		{"id": "woodcutter", "name": "Лесорубы", "prod": "+1.2 🪵/дн", "icon_key": "woodcutter", "fallback": "🪓"},
		{"id": "quarryman", "name": "Каменотёсы", "prod": "+1.0 🪨/дн", "icon_key": "quarryman", "fallback": "⛏"},
		{"id": "miner", "name": "Рудокопы", "prod": "+0.5 ⚒/дн", "icon_key": "miner", "fallback": "⛏"},
		{"id": "craftsman", "name": "Ремесленники", "prod": "+0.8 🪙/дн", "icon_key": "craftsman", "fallback": "🏺"},
		{"id": "sage", "name": "Мудрецы", "prod": "+0.8 📜/дн", "icon_key": "sage", "fallback": "📜"},
		{"id": "priest", "name": "Жрецы", "prod": "+0.5 🕯/дн", "icon_key": "priest", "fallback": "🕯"},
		{"id": "builder", "name": "Строители", "prod": "+0.5 к скорости", "icon_key": "builder", "fallback": "🔨"}
	]
	
	for job in job_configs:
		var panel = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.12, 0.15, 0.21, 0.95)
		sbox.border_color = Color(0.25, 0.32, 0.44, 0.7)
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", sbox)
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		
		# Портрет персонажа данной профессии
		var char_tex = CharacterTextureManager.get_character_for_job(job["id"])
		if char_tex:
			var char_rect = TextureRect.new()
			char_rect.texture = char_tex
			char_rect.custom_minimum_size = Vector2(34, 34)
			char_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			char_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(char_rect)
			
		var icon_tex = ItemTextureManager.get_icon(job["icon_key"])
		if icon_tex:
			var icon_tr = TextureRect.new()
			icon_tr.texture = icon_tex
			icon_tr.custom_minimum_size = Vector2(24, 24)
			icon_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon_tr)
		else:
			var icon_lbl = Label.new()
			icon_lbl.text = job["fallback"]
			icon_lbl.custom_minimum_size = Vector2(24, 0)
			row.add_child(icon_lbl)
		
		var info_box = VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl = Label.new()
		name_lbl.text = job["name"]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
		info_box.add_child(name_lbl)
		
		var prod_lbl = Label.new()
		prod_lbl.text = job["prod"]
		prod_lbl.add_theme_font_size_override("font_size", 11)
		prod_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		info_box.add_child(prod_lbl)
		
		row.add_child(info_box)
		
		var count_badge = Label.new()
		var count = settlement.assigned_jobs.get(job["id"], 0)
		count_badge.text = " %d " % count
		count_badge.custom_minimum_size = Vector2(32, 0)
		count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_badge.add_theme_font_size_override("font_size", 16)
		count_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		row.add_child(count_badge)
		
		var minus_btn = Button.new()
		minus_btn.text = " - "
		minus_btn.custom_minimum_size = Vector2(36, 32)
		minus_btn.disabled = (count <= 0)
		minus_btn.pressed.connect(func():
			if settlement.assign_worker(job["id"], -1):
				_refresh_ui()
		)
		row.add_child(minus_btn)
		
		var plus_btn = Button.new()
		plus_btn.text = " + "
		plus_btn.custom_minimum_size = Vector2(36, 32)
		plus_btn.disabled = (settlement.get_idle_workforce() <= 0)
		plus_btn.pressed.connect(func():
			if settlement.assign_worker(job["id"], 1):
				_refresh_ui()
		)
		row.add_child(plus_btn)
		
		panel.add_child(row)
		jobs_container.add_child(panel)

func _populate_queue() -> void:
	for child in queue_vbox.get_children():
		child.queue_free()
		
	if settlement.construction_queue.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Очередь пуста.\nВыберите здание в каталоге справа для начала работ."
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		queue_vbox.add_child(empty_lbl)
		return
		
	for i in range(settlement.construction_queue.size()):
		var item = settlement.construction_queue[i]
		var panel = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.14, 0.18, 0.25, 0.95) if i == 0 else Color(0.1, 0.13, 0.18, 0.9)
		sbox.border_color = Color(1.0, 0.85, 0.3, 0.8) if i == 0 else Color(0.25, 0.35, 0.45, 0.7)
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel", sbox)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		
		var top_row = HBoxContainer.new()
		var title_lbl = Label.new()
		title_lbl.text = "#%d: %s (%s%.1f из %d дн.)" % [i + 1, item["name"], "[ПАУЗА] " if item.get("is_paused", false) else "", item["days_left"], item["total_days"]]
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.add_theme_font_size_override("font_size", 13)
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5) if i == 0 else Color(0.9, 0.9, 0.9))
		top_row.add_child(title_lbl)
		
		# Кнопки управления очередью: ▲, ▼, ⏸, ✖
		var q_idx = i
		if i > 0:
			var up_btn = Button.new()
			up_btn.text = "▲"
			up_btn.custom_minimum_size = Vector2(28, 24)
			up_btn.pressed.connect(func(): settlement.move_queue_item(q_idx, q_idx - 1); _refresh_ui())
			top_row.add_child(up_btn)
			
		if i < settlement.construction_queue.size() - 1:
			var dn_btn = Button.new()
			dn_btn.text = "▼"
			dn_btn.custom_minimum_size = Vector2(28, 24)
			dn_btn.pressed.connect(func(): settlement.move_queue_item(q_idx, q_idx + 1); _refresh_ui())
			top_row.add_child(dn_btn)
			
		var pause_btn = Button.new()
		pause_btn.text = "▶" if item.get("is_paused", false) else "⏸"
		pause_btn.custom_minimum_size = Vector2(28, 24)
		pause_btn.pressed.connect(func(): settlement.toggle_pause_queue_item(q_idx); _refresh_ui())
		top_row.add_child(pause_btn)
		
		var cancel_btn = Button.new()
		cancel_btn.text = "✖"
		cancel_btn.custom_minimum_size = Vector2(28, 24)
		cancel_btn.pressed.connect(func(): settlement.cancel_queue_item(q_idx); _refresh_ui())
		top_row.add_child(cancel_btn)
		
		vbox.add_child(top_row)
		
		var pbar = ProgressBar.new()
		pbar.max_value = item["total_days"]
		pbar.value = item["total_days"] - item["days_left"]
		pbar.custom_minimum_size = Vector2(0, 10)
		pbar.show_percentage = false
		vbox.add_child(pbar)
		
		panel.add_child(vbox)
		queue_vbox.add_child(panel)

func _populate_catalog() -> void:
	for child in catalog_vbox.get_children():
		child.queue_free()
		
	for b_id in BuildingDB.BUILDINGS:
		var b_info = BuildingDB.get_building(b_id)
		var panel = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.12, 0.15, 0.21, 0.95)
		sbox.border_color = Color(0.25, 0.32, 0.44, 0.7)
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", sbox)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var tex = BuildingTextureManager.get_texture(b_id)
		if tex:
			var icon = TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(42, 42)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(icon)
			
		var info_box = VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var title_row = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = b_info["name"]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		title_row.add_child(name_lbl)
		
		var built_count = settlement.buildings.count(b_id)
		if built_count > 0:
			var built_lbl = Label.new()
			built_lbl.text = " [Построено: %d]" % built_count
			built_lbl.add_theme_font_size_override("font_size", 11)
			built_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
			title_row.add_child(built_lbl)
		info_box.add_child(title_row)
		
		var cost_lbl = Label.new()
		var cost_str = "Цена: "
		for res in b_info["cost"]:
			cost_str += "%s %d  " % [res, b_info["cost"][res]]
		cost_str += " | Срок: %d дн." % b_info["build_days"]
		cost_lbl.text = cost_str
		cost_lbl.add_theme_font_size_override("font_size", 11)
		cost_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
		info_box.add_child(cost_lbl)
		
		hbox.add_child(info_box)
		
		var btn_box = VBoxContainer.new()
		btn_box.add_theme_constant_override("separation", 4)
		btn_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		var can_afford = settlement.economy.can_afford(b_info["cost"])
		
		var place_on_map_btn = Button.new()
		place_on_map_btn.text = "📍 На карту"
		place_on_map_btn.custom_minimum_size = Vector2(105, 26)
		place_on_map_btn.disabled = not can_afford
		place_on_map_btn.pressed.connect(func():
			visible = false
			EventBus.start_building_placement.emit(b_id)
		)
		btn_box.add_child(place_on_map_btn)
		
		var build_btn = Button.new()
		build_btn.text = "🔨 В очередь"
		build_btn.custom_minimum_size = Vector2(105, 26)
		build_btn.disabled = not can_afford
		build_btn.pressed.connect(func():
			var build_coord = target_build_coord
			if settlement.start_construction(b_id, build_coord):
				if build_coord != Vector2i(-1, -1):
					EventBus.notification_toast.emit("Строительство", "Заложено здание: %s на тайле (%d:%d)" % [b_info["name"], build_coord.x, build_coord.y], "good")
					target_build_coord = Vector2i(-1, -1)
				else:
					EventBus.notification_toast.emit("Строительство", "Заложено здание: %s" % b_info["name"], "good")
				_refresh_ui()
		)
		btn_box.add_child(build_btn)
		
		hbox.add_child(btn_box)
		
		panel.add_child(hbox)
		catalog_vbox.add_child(panel)

func _populate_built_buildings() -> void:
	for child in built_list_vbox.get_children():
		child.queue_free()
		
	var counts: Dictionary = {}
	for b_id in settlement.buildings:
		counts[b_id] = counts.get(b_id, 0) + 1
		
	for b_id in counts:
		var b_info = BuildingDB.get_building(b_id)
		var panel = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.11, 0.14, 0.20, 0.95)
		sbox.border_color = Color(0.3, 0.4, 0.55, 0.7)
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel", sbox)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		var tex = BuildingTextureManager.get_texture(b_id)
		if tex:
			var icon = TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(44, 44)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(icon)
			
		var info_box = VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl = Label.new()
		name_lbl.text = "%s (Количество: %d)" % [b_info.get("name", b_id), counts[b_id]]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
		info_box.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = b_info.get("description", "Функционирующее здание.")
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		info_box.add_child(desc_lbl)
		
		hbox.add_child(info_box)
		
		# Кнопка «Показать на карте»
		var focus_btn = Button.new()
		focus_btn.text = "🔍 На карте"
		focus_btn.custom_minimum_size = Vector2(90, 32)
		focus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		focus_btn.pressed.connect(func():
			visible = false
			var cam = get_tree().root.find_child("MapCamera", true, false)
			if cam:
				cam.focus_on(Vector2(settlement.pos.x * 32.0 + 16, settlement.pos.y * 32.0 + 16), 1.6)
		)
		hbox.add_child(focus_btn)
		
		panel.add_child(hbox)
		built_list_vbox.add_child(panel)

func _populate_economy_ledger() -> void:
	if economy_text == null or settlement == null:
		return
		
	var season = GameManager.get_season()
	var ledger = settlement.get_detailed_ledger(season)
	var inc = ledger["income"]
	var expenses = ledger["expense"]
	var net = ledger["net"]
	
	var bb = "[b][color=#ffd700]Сводный экономический баланс поселения (%s):[/color][/b]\n\n" % season
	bb += "[table=4]"
	bb += "[cell][b]Ресурс[/b][/cell][cell][b]Добыча/дн[/b][/cell][cell][b]Расход/дн[/b][/cell][cell][b]Чистое сальдо[/b][/cell]"
	
	var res_names = ["food", "wood", "stone", "metal", "kubriki", "knowledge", "faith"]
	var labels = {"food": "🍗 Еда", "wood": "🪵 Дерево", "stone": "🪨 Камень", "metal": "⛏ Металл", "kubriki": "🪙 Кубрики", "knowledge": "📜 Знания", "faith": "🕯 Вера"}
	
	for r in res_names:
		var net_val = net.get(r, 0.0)
		var col = "#55ff55" if net_val >= 0 else "#ff5555"
		bb += "[cell]%s[/cell][cell]+%.1f[/cell][cell]-%.1f[/cell][cell][color=%s]%s%.1f[/color][/cell]" % [
			labels.get(r, r), inc.get(r, 0.0), expenses.get(r, 0.0), col, "+" if net_val >= 0 else "", net_val
		]
	bb += "[/table]\n\n"
	bb += "[b]Продовольственная безопасность:[/b] "
	var food_stock = settlement.economy.get_resource("food")
	var daily_burn = expenses.get("food", 1.0)
	var days_left = (food_stock / daily_burn) if daily_burn > 0 else 999.0
	bb += "Запасов еды хватит на [color=#ffd700]%.0f дней[/color] автономного существования." % days_left
	
	economy_text.text = bb
