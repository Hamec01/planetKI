class_name BuildingDetailPanel
extends PanelContainer

const BuildingInstanceScript = preload("res://src/simulation/building_instance.gd")
const BuildingSystemScript = preload("res://src/simulation/building_system.gd")
const EquipmentDB = preload("res://src/combat/equipment_db.gd")

signal building_mode_changed(building_inst: RefCounted, new_mode: String)
signal building_upgrade_unlocked(building_inst: RefCounted, upgrade_id: String)
signal worker_assigned(building_inst: RefCounted, citizen_id: String)
signal worker_removed(building_inst: RefCounted, citizen_id: String)

var current_building: RefCounted = null
var current_settlement: RefCounted = null

# Элементы интерфейса
var title_label: Label
var type_badge_label: Label
var icon_rect: TextureRect
var condition_bar: ProgressBar
var tab_container: TabContainer

# Контейнеры вкладок
var overview_vbox: VBoxContainer
var workers_vbox: VBoxContainer
var modes_vbox: VBoxContainer
var upgrades_grid: GridContainer
var orders_vbox: VBoxContainer
var events_vbox: VBoxContainer
var history_vbox: VBoxContainer

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -440.0
	offset_top = -290.0
	offset_right = 440.0
	offset_bottom = 290.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	sbox.border_color = Color(0.85, 0.68, 0.28, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.7)
	sbox.shadow_size = 14
	sbox.shadow_offset = Vector2(0, 6)
	sbox.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sbox)
	
	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)
	
	# --- ВЕРХНИЙ ХЕДЕР ---
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(header_hbox)
	
	icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(50, 50)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header_hbox.add_child(icon_rect)
	
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_hbox.add_child(title_box)
	
	title_label = Label.new()
	title_label.text = "Кузница племени"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	title_box.add_child(title_label)
	
	type_badge_label = Label.new()
	type_badge_label.text = "Активный институт 1-й Эпохи"
	type_badge_label.add_theme_font_size_override("font_size", 10)
	type_badge_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.92))
	title_box.add_child(type_badge_label)
	
	var close_btn = Button.new()
	close_btn.text = "✕ Закрыть"
	close_btn.custom_minimum_size = Vector2(90, 28)
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(func(): close_panel())
	header_hbox.add_child(close_btn)
	
	var sep = HSeparator.new()
	root_vbox.add_child(sep)
	
	# --- 7 ВКЛАДОК ЗДАНИЯ ---
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(tab_container)
	
	_setup_overview_tab()
	_setup_workers_tab()
	_setup_modes_tab()
	_setup_upgrades_tab()
	_setup_orders_tab()
	_setup_events_tab()
	_setup_history_tab()

func _setup_overview_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "📊 Обзор"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	
	overview_vbox = VBoxContainer.new()
	overview_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(overview_vbox)
	
	tab_container.add_child(margin)

func _setup_workers_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "👥 Работники"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	
	workers_vbox = VBoxContainer.new()
	workers_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workers_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(workers_vbox)
	
	tab_container.add_child(margin)

func _setup_modes_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "⚙️ Режимы"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	
	modes_vbox = VBoxContainer.new()
	modes_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(modes_vbox)
	
	tab_container.add_child(margin)

func _setup_upgrades_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "✨ Улучшения"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	
	upgrades_grid = GridContainer.new()
	upgrades_grid.columns = 2
	upgrades_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_grid.add_theme_constant_override("h_separation", 8)
	upgrades_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(upgrades_grid)
	
	tab_container.add_child(margin)

func _setup_orders_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "📦 Заказы"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	
	orders_vbox = VBoxContainer.new()
	orders_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orders_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(orders_vbox)
	
	tab_container.add_child(margin)

func _setup_events_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "⚡ События"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	
	events_vbox = VBoxContainer.new()
	events_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	events_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(events_vbox)
	
	tab_container.add_child(margin)

func _setup_history_tab() -> void:
	var margin = MarginContainer.new()
	margin.name = "📖 Летопись"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	
	history_vbox = VBoxContainer.new()
	history_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(history_vbox)
	
	tab_container.add_child(margin)

# --- ОТКРЫТИЕ И ОБНОВЛЕНИЕ ПАНЕЛИ ---
func open_building(b_inst: RefCounted, settlement: RefCounted) -> void:
	current_building = b_inst
	current_settlement = settlement
	visible = true
	refresh_all_tabs()

func close_panel() -> void:
	visible = false
	current_building = null

func refresh_all_tabs() -> void:
	if current_building == null or current_settlement == null:
		return
		
	var b_info = BuildingDB.get_building(current_building.type)
	title_label.text = "%s (Тайл %d:%d)" % [b_info.get("name", current_building.type), current_building.pos.x, current_building.pos.y]
	icon_rect.texture = BuildingTextureManager.get_texture(current_building.type)
	
	_render_overview()
	_render_workers()
	_render_modes()
	_render_upgrades()
	_render_orders()
	_render_events()
	_render_history()

func _render_overview() -> void:
	for c in overview_vbox.get_children():
		c.queue_free()
		
	var b_info = BuildingDB.get_building(current_building.type)
	
	# Карточка статуса
	var card = PanelContainer.new()
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.12, 0.15, 0.22, 0.9)
	sbox.border_color = Color(0.3, 0.5, 0.7, 0.6)
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(6)
	sbox.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sbox)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	
	var desc_lbl = Label.new()
	desc_lbl.text = b_info.get("description", "Функционирующее здание.")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(desc_lbl)
	
	var mode_name = current_building.active_mode
	for m in BuildingSystemScript.get_modes_for_building(current_building.type):
		if m["id"] == current_building.active_mode:
			mode_name = m["name"]
			break
			
	var manager_name = "Не назначен"
	if current_building.manager_id != "":
		var manager_cit = current_settlement.population.get_citizen_by_id(current_building.manager_id)
		if manager_cit != null:
			var m_loyalty = int(manager_cit.loyalty) if "loyalty" in manager_cit else 80
			var m_age = manager_cit.age if "age" in manager_cit else 25
			manager_name = "%s (%d лет, верность %d%%)" % [manager_cit.name, m_age, m_loyalty]
			
	var stats_lbl = Label.new()
	stats_lbl.text = "👑 Руководитель / Мастер: %s\n⚙️ Текущий режим работы: %s\n👥 Работников: %d чел. • Состояние: %.0f%%" % [
		manager_name, mode_name, current_building.workers.size(), current_building.condition
	]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(stats_lbl)
	
	card.add_child(vbox)
	overview_vbox.add_child(card)

func _render_workers() -> void:
	for c in workers_vbox.get_children():
		c.queue_free()
		
	var pop = current_settlement.population
	var b_def = BuildingDB.get_building(current_building.type)
	var max_workers = b_def.get("max_workers", 4)
	
	var title = Label.new()
	title.text = "Назначенные соплеменники (%d / %d):" % [current_building.workers.size(), max_workers]
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	workers_vbox.add_child(title)
	
	if max_workers <= 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "В этом типе здания нет рабочих мест."
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		workers_vbox.add_child(empty_lbl)
		return
	
	for w_id in current_building.workers:
		var cit = pop.get_citizen_by_id(w_id)
		if cit == null:
			continue
			
		var card = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.14, 0.17, 0.24, 0.9)
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", sbox)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var name_lbl = Label.new()
		var is_master = (current_building.manager_id == w_id)
		var c_age = cit.age if "age" in cit else 25
		name_lbl.text = ("👑 " if is_master else "👤 ") + "%s (%d лет)" % [cit.name, c_age]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		hbox.add_child(name_lbl)
		
		var exp_val = cit.experience.get(current_building.type, 10) if ("experience" in cit and cit.experience is Dictionary) else 10
		var c_loyalty = int(cit.loyalty) if "loyalty" in cit else 80
		var stat_lbl = Label.new()
		stat_lbl.text = "Опыт: %d | Верность: %d%%" % [exp_val, c_loyalty]
		stat_lbl.add_theme_font_size_override("font_size", 10)
		stat_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		hbox.add_child(stat_lbl)
		
		if not is_master:
			var make_master_btn = Button.new()
			make_master_btn.text = "Сделать мастером"
			make_master_btn.add_theme_font_size_override("font_size", 9)
			var cur_w_id = w_id
			var cur_w_name = cit.name
			make_master_btn.pressed.connect(func():
				current_building.assign_manager(cur_w_id, cur_w_name)
				refresh_all_tabs()
			)
			hbox.add_child(make_master_btn)
			
		var unassign_btn = Button.new()
		unassign_btn.text = "✕ Снять"
		unassign_btn.add_theme_font_size_override("font_size", 9)
		var remove_w_id = w_id
		unassign_btn.pressed.connect(func():
			current_building.remove_worker(remove_w_id)
			var w_cit = pop.get_citizen_by_id(remove_w_id)
			if w_cit != null:
				w_cit.set_job("idle")
				w_cit.workplace_id = ""
				w_cit.workplace_coord = Vector2i(-1, -1)
			current_settlement.sync_assigned_jobs_from_citizens()
			EventBus.notification_toast.emit(
				"Работник освобождён",
				"%s снят с должности и теперь свободен." % (w_cit.name if w_cit else remove_w_id),
				"info"
			)
			refresh_all_tabs()
		)
		hbox.add_child(unassign_btn)
		
		card.add_child(hbox)
		workers_vbox.add_child(card)
		
	# Кнопка назначения свободного соплеменника
	var add_hbox = HBoxContainer.new()
	add_hbox.add_theme_constant_override("separation", 6)
	
	var idle_citizens = current_settlement.get_idle_citizens()
	var free_count = idle_citizens.size()
	var is_full = (current_building.workers.size() >= max_workers)
	
	var add_btn = Button.new()
	if is_full:
		add_btn.text = "Штат укомплектован (%d / %d)" % [current_building.workers.size(), max_workers]
		add_btn.disabled = true
	elif free_count <= 0:
		add_btn.text = "Нет свободных жителей (Свободно: 0)"
		add_btn.disabled = true
	else:
		add_btn.text = "➕ Назначить свободного жителя (Свободно: %d)" % free_count
		add_btn.disabled = false
		
	add_btn.add_theme_font_size_override("font_size", 11)
	add_btn.pressed.connect(func():
		var fresh_idles = current_settlement.get_idle_citizens()
		if fresh_idles.is_empty():
			EventBus.notification_toast.emit("Нет свободных жителей", "Все взрослые соплеменники уже заняты на других работах!", "warning")
			refresh_all_tabs()
			return
		if current_building.workers.size() >= max_workers:
			EventBus.notification_toast.emit("Штат полон", "В этом здании достигнут лимит рабочих (%d)!" % max_workers, "warning")
			refresh_all_tabs()
			return
			
		var free_c = fresh_idles[0]
		var job_id = BuildingDB.get_job_id_for_building(current_building.type)
		current_building.add_worker(free_c.citizen_id)
		free_c.set_job(job_id)
		free_c.workplace_id = current_building.id
		free_c.workplace_coord = current_building.pos
		if current_building.manager_id == "":
			current_building.assign_manager(free_c.citizen_id, free_c.name)
		current_settlement.sync_assigned_jobs_from_citizens()
		EventBus.notification_toast.emit(
			"Назначен соплеменник",
			"%s приступил к работе в должности: %s" % [free_c.name, b_def.get("job_name", job_id)],
			"good"
		)
		refresh_all_tabs()
	)
	add_hbox.add_child(add_btn)
	workers_vbox.add_child(add_hbox)

func _render_modes() -> void:
	for c in modes_vbox.get_children():
		c.queue_free()
		
	var modes = BuildingSystemScript.get_modes_for_building(current_building.type)
	for m in modes:
		var card = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		var is_active = (current_building.active_mode == m["id"])
		sbox.bg_color = Color(0.18, 0.24, 0.18, 0.95) if is_active else Color(0.12, 0.14, 0.20, 0.9)
		sbox.border_color = Color(0.4, 0.85, 0.45, 1.0) if is_active else Color(0.3, 0.4, 0.5, 0.5)
		sbox.set_border_width_all(2 if is_active else 1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", sbox)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)
		
		var name_lbl = Label.new()
		name_lbl.text = m["name"] + ("  [АКТИВНО]" if is_active else "")
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45) if is_active else Color.WHITE)
		vbox.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = m["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.95))
		vbox.add_child(desc_lbl)
		
		hbox.add_child(vbox)
		
		var btn = Button.new()
		btn.text = "Выбрано" if is_active else "Включить"
		btn.disabled = is_active
		btn.custom_minimum_size = Vector2(90, 30)
		btn.add_theme_font_size_override("font_size", 10)
		var mode_id = m["id"]
		btn.pressed.connect(func():
			current_building.set_mode(mode_id)
			refresh_all_tabs()
		)
		hbox.add_child(btn)
		
		card.add_child(hbox)
		modes_vbox.add_child(card)

func _render_upgrades() -> void:
	for c in upgrades_grid.get_children():
		c.queue_free()
		
	var upgrades = BuildingSystemScript.get_upgrades_for_building(current_building.type)
	var econ = current_settlement.economy
	
	for u in upgrades:
		var u_id = u["id"]
		var is_unlocked = current_building.is_upgrade_unlocked(u_id)
		var can_afford = econ.can_afford(u["cost"])
		
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(380, 80)
		
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.12, 0.18, 0.14, 0.95) if is_unlocked else Color(0.12, 0.15, 0.21, 0.95)
		sbox.border_color = Color(0.35, 0.85, 0.45, 0.9) if is_unlocked else (Color(0.85, 0.65, 0.25, 0.8) if can_afford else Color(0.5, 0.35, 0.3, 0.5))
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", sbox)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)
		
		var name_lbl = Label.new()
		name_lbl.text = ("✅ " if is_unlocked else "✨ ") + u["name"]
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		vbox.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = u["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_lbl)
		
		var cost_items = []
		for r in u["cost"]:
			cost_items.append("%s %d" % [r, u["cost"][r]])
		var cost_lbl = Label.new()
		cost_lbl.text = "Цена: " + " | ".join(cost_items)
		cost_lbl.add_theme_font_size_override("font_size", 9)
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if can_afford else Color(0.95, 0.4, 0.35))
		vbox.add_child(cost_lbl)
		
		hbox.add_child(vbox)
		
		var buy_btn = Button.new()
		var is_in_progress = current_building.has_pending_upgrade() and current_building.pending_upgrade.get("id", "") == u_id
		buy_btn.text = "Изучено" if is_unlocked else ("Строится..." if is_in_progress else "Исследовать")
		buy_btn.disabled = is_unlocked or is_in_progress
		buy_btn.custom_minimum_size = Vector2(85, 30)
		buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy_btn.add_theme_font_size_override("font_size", 10)
		buy_btn.pressed.connect(func():
			if current_building.start_upgrade(u_id, u.get("cost", {})):
				EventBus.notification_toast.emit("Улучшение начато", "Начато улучшение: %s. Требуется доставка стройматериалов." % u.get("name", u_id), "info")
				refresh_all_tabs()
		)
		hbox.add_child(buy_btn)
		
		card.add_child(hbox)
		upgrades_grid.add_child(card)

func _render_orders() -> void:
	for c in orders_vbox.get_children():
		c.queue_free()
		
	# 1. Очередь активных заказов
	if current_building and not current_building.production_queue.is_empty():
		var q_title = Label.new()
		q_title.text = "Текущая очередь производства (%d заказов):" % current_building.production_queue.size()
		q_title.add_theme_font_size_override("font_size", 11)
		q_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		orders_vbox.add_child(q_title)
		
		for ord_item in current_building.production_queue:
			var q_card = PanelContainer.new()
			var q_sbox = StyleBoxFlat.new()
			q_sbox.bg_color = Color(0.14, 0.18, 0.25, 0.95)
			q_sbox.border_color = Color(0.35, 0.7, 0.95, 0.8)
			q_sbox.set_border_width_all(1)
			q_sbox.set_corner_radius_all(5)
			q_sbox.set_content_margin_all(5)
			q_card.add_theme_stylebox_override("panel", q_sbox)
			
			var q_hbox = HBoxContainer.new()
			q_hbox.add_theme_constant_override("separation", 6)
			
			var q_vbox = VBoxContainer.new()
			q_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var q_name = Label.new()
			var progress_pct = (ord_item.get("work_progress", 0.0) / maxf(ord_item.get("work_required", 1.0), 1.0)) * 100.0
			q_name.text = "⚙️ %s (Прогресс: %d%%)" % [ord_item.get("name", ord_item.get("item_id", "")), int(progress_pct)]
			q_name.add_theme_font_size_override("font_size", 10)
			q_name.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
			q_vbox.add_child(q_name)
			
			var q_bar = ProgressBar.new()
			q_bar.max_value = maxf(ord_item.get("work_required", 1.0), 1.0)
			q_bar.value = ord_item.get("work_progress", 0.0)
			q_bar.show_percentage = false
			q_bar.custom_minimum_size = Vector2(100, 8)
			q_vbox.add_child(q_bar)
			
			q_hbox.add_child(q_vbox)
			
			var cancel_btn = Button.new()
			cancel_btn.text = "❌"
			cancel_btn.tooltip_text = "Отменить заказ и вернуть неиспользованные материалы"
			cancel_btn.custom_minimum_size = Vector2(28, 24)
			var cur_ord_id = ord_item.get("order_id", "")
			cancel_btn.pressed.connect(func():
				if current_building.cancel_production_order(cur_ord_id, current_settlement):
					if EventBus:
						EventBus.notification_toast.emit("Заказ отменён", "Заказ отменён, материалы возвращены.", "info")
					refresh_all_tabs()
			)
			q_hbox.add_child(cancel_btn)
			
			q_card.add_child(q_hbox)
			orders_vbox.add_child(q_card)
			
		var sep = HSeparator.new()
		orders_vbox.add_child(sep)

	var info_lbl = Label.new()
	info_lbl.text = "Доступные рецепты производства (EquipmentDB):"
	info_lbl.add_theme_font_size_override("font_size", 11)
	info_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	orders_vbox.add_child(info_lbl)
	
	var econ = current_settlement.economy if current_settlement else null
	
	# Перебираем все рецепты из EquipmentDB
	for item_id in EquipmentDB.RECIPES:
		var recipe = EquipmentDB.RECIPES[item_id]
		var cost = recipe.get("cost", {})
		var can_afford = econ.can_afford(cost) if econ else false
		var req_upgrade = recipe.get("upgrade_req", "")
		var is_unlocked = true
		if req_upgrade != "" and current_building:
			is_unlocked = current_building.is_upgrade_unlocked(req_upgrade)
			
		var card = PanelContainer.new()
		var sbox = StyleBoxFlat.new()
		sbox.bg_color = Color(0.12, 0.15, 0.22, 0.9) if is_unlocked else Color(0.10, 0.11, 0.15, 0.7)
		sbox.border_color = Color(0.85, 0.65, 0.25, 0.8) if can_afford and is_unlocked else Color(0.4, 0.3, 0.3, 0.5)
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(6)
		sbox.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", sbox)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)
		
		var name_lbl = Label.new()
		name_lbl.text = recipe["name"] + (" (Требует улучшение)" if not is_unlocked else "")
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5) if is_unlocked else Color(0.6, 0.6, 0.6))
		vbox.add_child(name_lbl)
		
		var cost_strs = []
		for r in cost:
			cost_strs.append("%s: %d" % [r, cost[r]])
		var cost_lbl = Label.new()
		cost_lbl.text = "Материалы: " + ", ".join(cost_strs) + " | Труд: %.2f раб. дня" % float(recipe.get("work_days", 1.0))
		cost_lbl.add_theme_font_size_override("font_size", 9)
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if can_afford and is_unlocked else Color(0.9, 0.4, 0.4))
		vbox.add_child(cost_lbl)
		
		hbox.add_child(vbox)
		
		var btn = Button.new()
		btn.text = "🔨 Заказать"
		btn.disabled = not is_unlocked
		btn.custom_minimum_size = Vector2(95, 28)
		btn.add_theme_font_size_override("font_size", 10)
		var target_item_id = item_id
		var item_name = recipe["name"]
		btn.pressed.connect(func():
			if current_building:
				var ord_res = current_building.add_production_order(target_item_id, 1)
				if ord_res.get("success", false):
					if EventBus:
						EventBus.notification_toast.emit("Заказ добавлен", "Заказ на %s добавлен в очередь мастерской." % item_name, "info")
					refresh_all_tabs()
		)
		hbox.add_child(btn)
		
		card.add_child(hbox)
		orders_vbox.add_child(card)

func _render_events() -> void:
	for c in events_vbox.get_children():
		c.queue_free()
	var empty_lbl = Label.new()
	empty_lbl.text = "Событий, связанных с этим зданием, нет. Общие решения и происшествия доступны в журнале событий."
	empty_lbl.add_theme_font_size_override("font_size", 11)
	empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	events_vbox.add_child(empty_lbl)

func _render_history() -> void:
	for c in history_vbox.get_children():
		c.queue_free()
		
	var title = Label.new()
	title.text = "Хроника деяний здания:"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	history_vbox.add_child(title)
	
	if current_building.event_history.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Летопись пока пуста. Здание недавно заложено."
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		history_vbox.add_child(empty_lbl)
		return
		
	for h in current_building.event_history:
		var line = Label.new()
		line.text = "• Год %d: %s" % [h["year"], h["text"]]
		line.add_theme_font_size_override("font_size", 10)
		line.add_theme_color_override("font_color", Color(0.85, 0.9, 0.96))
		history_vbox.add_child(line)
