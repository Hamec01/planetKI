class_name MainHUD
extends CanvasLayer

@onready var date_label: Label = $TopBar/MarginContainer/HBoxContainer/DateLabel
@onready var epoch_label: Label = $TopBar/MarginContainer/HBoxContainer/EpochLabel
@onready var food_label: Label = $TopBar/MarginContainer/HBoxContainer/ResContainer/FoodLabel
@onready var wood_label: Label = $TopBar/MarginContainer/HBoxContainer/ResContainer/WoodLabel
@onready var stone_label: Label = $TopBar/MarginContainer/HBoxContainer/ResContainer/StoneLabel
@onready var metal_label: Label = $TopBar/MarginContainer/HBoxContainer/ResContainer/MetalLabel
@onready var kubriki_label: Label = $TopBar/MarginContainer/HBoxContainer/ResContainer/KubrikiLabel
@onready var knowledge_label: Label = $TopBar/MarginContainer/HBoxContainer/ResContainer/KnowledgeLabel
@onready var pop_label: Label = $TopBar/MarginContainer/HBoxContainer/PopContainer/PopLabel
@onready var loyalty_label: Label = $TopBar/MarginContainer/HBoxContainer/StatsContainer/LoyaltyLabel
@onready var stability_label: Label = $TopBar/MarginContainer/HBoxContainer/StatsContainer/StabilityLabel

@onready var pause_btn: Button = $TopBar/MarginContainer/HBoxContainer/SpeedContainer/PauseBtn
@onready var speed1_btn: Button = $TopBar/MarginContainer/HBoxContainer/SpeedContainer/Speed1Btn
@onready var speed2_btn: Button = $TopBar/MarginContainer/HBoxContainer/SpeedContainer/Speed2Btn
@onready var speed4_btn: Button = $TopBar/MarginContainer/HBoxContainer/SpeedContainer/Speed4Btn

@onready var tile_info_panel: PanelContainer = $TileInfoPanel
@onready var tile_title_label: Label = $TileInfoPanel/MarginContainer/VBox/Title
@onready var tile_details_label: Label = $TileInfoPanel/MarginContainer/VBox/Details

# Горизонтальная нижняя панель RTS (Control Dock Bar)
var bottom_dock_bar: PanelContainer
var map_mode_panel: PanelContainer
var active_menu_item: String = ""
var dock_buttons: Dictionary = {}

# Контейнер всплывающих тост-уведомлений
var toast_container: VBoxContainer

# Всплывающее контекстное меню у курсора (ПКМ / Клик по клетке/объекту)
var cursor_context_menu: PanelContainer
var ctx_icon_rect: TextureRect
var ctx_title_lbl: Label
var ctx_coords_lbl: Label
var ctx_desc_lbl: Label
var ctx_progress_bar: ProgressBar
var ctx_action_btn: Button
var ctx_secondary_btn: Button
var current_ctx_coord: Vector2i = Vector2i(-1, -1)
var current_ctx_tile_data: Dictionary = {}
var active_inspected_nature_coord: Vector2i = Vector2i(-1, -1)

signal tab_opened(tab_name: String, extra_data: Variant)

func _ready() -> void:
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.resources_updated.connect(_on_resources_updated)
	EventBus.game_speed_changed.connect(_on_speed_changed)
	EventBus.tile_selected.connect(_on_tile_selected)
	EventBus.tile_right_clicked.connect(_on_tile_right_clicked)
	EventBus.nature_object_selected.connect(_on_nature_object_selected)
	EventBus.animal_selected.connect(_on_animal_selected)
	EventBus.selection_cleared.connect(_on_selection_cleared)
	EventBus.time_period_changed.connect(func(_p): _update_ui())
	EventBus.settlement_selected.connect(_on_settlement_context_selected)
	EventBus.notification_toast.connect(_on_notification_toast)
	
	pause_btn.pressed.connect(func(): GameManager.toggle_pause())
	speed1_btn.pressed.connect(func(): GameManager.set_speed(1.0))
	speed2_btn.pressed.connect(func(): GameManager.set_speed(2.0))
	speed4_btn.pressed.connect(func(): GameManager.set_speed(4.0))
	
	# Скрываем старый BottomBar если он есть в дереве
	if has_node("BottomBar"):
		$BottomBar.visible = false
	if has_node("TileInfoPanel"):
		$TileInfoPanel.visible = false
	
	_setup_top_bar_icons()
	_setup_bottom_rts_dock_bar()
	_setup_toast_system()
	_setup_map_mode_selector()
	_setup_cursor_context_menu()
	_setup_placement_mode_banner()
	_setup_rts_build_menu()
	_update_ui()
	
	EventBus.start_building_placement.connect(_on_placement_started)
	EventBus.cancel_building_placement.connect(_on_placement_cancelled)
	EventBus.building_placed_on_map.connect(func(_id, _coord): _on_placement_cancelled())

const RTSBuildMenuScript = preload("res://src/ui/rts_build_menu.gd")
const BuildingDetailPanelScript = preload("res://src/ui/building_detail_panel.gd")
const CivilizationEventModalScript = preload("res://src/ui/civilization_event_modal.gd")
const EventRegistryPanelScript = preload("res://src/ui/event_registry_panel.gd")
const TraditionsRegistryModalScript = preload("res://src/ui/traditions_registry_modal.gd")
const FaithChronicleModalScript = preload("res://src/ui/faith_chronicle_modal.gd")
const DevEventInspectorScript = preload("res://src/ui/dev_event_inspector.gd")

var rts_build_menu: Control = null
var building_detail_panel: Control = null
var civilization_event_modal: Control = null
var event_registry_panel: Control = null
var traditions_modal: Control = null
var faith_modal: Control = null
var dev_inspector: Control = null

func _setup_rts_build_menu() -> void:
	if rts_build_menu == null:
		rts_build_menu = RTSBuildMenuScript.new()
		rts_build_menu.name = "RTSBuildMenu"
		add_child(rts_build_menu)
		
	if building_detail_panel == null:
		building_detail_panel = BuildingDetailPanelScript.new()
		building_detail_panel.name = "BuildingDetailPanel"
		add_child(building_detail_panel)
		
	if civilization_event_modal == null:
		civilization_event_modal = CivilizationEventModalScript.new()
		civilization_event_modal.name = "CivilizationEventModal"
		add_child(civilization_event_modal)
		EventBus.civilization_event_triggered.connect(func(ev):
			civilization_event_modal.open_event(ev)
		)
	if event_registry_panel == null:
		event_registry_panel = EventRegistryPanelScript.new()
		event_registry_panel.name = "EventRegistryPanel"
		add_child(event_registry_panel)
		event_registry_panel.event_open_requested.connect(func(ev):
			civilization_event_modal.open_event(ev)
		)
			
	if traditions_modal == null:
		traditions_modal = TraditionsRegistryModalScript.new()
		traditions_modal.name = "TraditionsRegistryModal"
		add_child(traditions_modal)
		
	if faith_modal == null:
		faith_modal = FaithChronicleModalScript.new()
		faith_modal.name = "FaithChronicleModal"
		add_child(faith_modal)
		
	if dev_inspector == null:
		dev_inspector = DevEventInspectorScript.new()
		dev_inspector.name = "DevEventInspector"
		add_child(dev_inspector)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var focused = get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return
			
		match event.keycode:
			KEY_SPACE:
				GameManager.toggle_pause()
			KEY_1:
				GameManager.set_speed(1.0)
			KEY_2:
				GameManager.set_speed(2.0)
			KEY_3, KEY_4:
				GameManager.set_speed(4.0)
			KEY_B:
				if rts_build_menu:
					rts_build_menu.toggle_menu()
			KEY_L:
				if traditions_modal:
					traditions_modal.open_registry()
			KEY_R:
				if faith_modal:
					faith_modal.open_chronicle()
			KEY_A:
				tab_opened.emit("army", null)
			KEY_M:
				map_mode_panel.visible = not map_mode_panel.visible
			KEY_E:
				tab_opened.emit("history", null)
			KEY_F12:
				if dev_inspector:
					dev_inspector.toggle_inspector()
			KEY_ESCAPE:
				if civilization_event_modal and civilization_event_modal.visible:
					pass
				if dev_inspector and dev_inspector.visible:
					dev_inspector.visible = false
				if traditions_modal and traditions_modal.visible:
					traditions_modal.visible = false
				if faith_modal and faith_modal.visible:
					faith_modal.visible = false
				if building_detail_panel and building_detail_panel.visible:
					building_detail_panel.close_panel()
				if rts_build_menu and rts_build_menu.visible:
					rts_build_menu.close_menu()
				if cursor_context_menu and cursor_context_menu.visible:
					cursor_context_menu.visible = false
				if map_mode_panel.visible:
					map_mode_panel.visible = false

func _setup_top_bar_icons() -> void:
	_attach_icon(food_label, "food")
	_attach_icon(wood_label, "wood")
	_attach_icon(stone_label, "stone")
	_attach_icon(metal_label, "metal")
	_attach_icon(kubriki_label, "kubriki")
	_attach_icon(knowledge_label, "knowledge")
	_attach_icon(pop_label, "pop")
	_attach_icon(loyalty_label, "loyalty")
	_attach_icon(stability_label, "backpack")

func _attach_icon(lbl: Label, icon_key: String) -> void:
	if lbl == null:
		return
	var tex = ItemTextureManager.get_icon(icon_key)
	if tex:
		var parent = lbl.get_parent()
		if parent is HBoxContainer:
			var idx = lbl.get_index()
			var icon_rect = TextureRect.new()
			icon_rect.texture = tex
			icon_rect.custom_minimum_size = Vector2(22, 22)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			parent.add_child(icon_rect)
			parent.move_child(icon_rect, idx)

# --- ГОРИЗОНТАЛЬНАЯ НИЖНЯЯ ПАНЕЛЬ УПРАВЛЕНИЯ RTS (ПОСТОЯННЫЙ БОРДЕР ВНИЗУ) ---
func _setup_bottom_rts_dock_bar() -> void:
	if has_node("BottomDockBar"):
		bottom_dock_bar = $BottomDockBar
	else:
		bottom_dock_bar = PanelContainer.new()
		bottom_dock_bar.name = "BottomDockBar"
		add_child(bottom_dock_bar)
		
	bottom_dock_bar.custom_minimum_size = Vector2(0, 52)
	bottom_dock_bar.anchors_preset = Control.PRESET_BOTTOM_WIDE
	bottom_dock_bar.anchor_left = 0.0
	bottom_dock_bar.anchor_right = 1.0
	bottom_dock_bar.anchor_top = 1.0
	bottom_dock_bar.anchor_bottom = 1.0
	bottom_dock_bar.offset_left = 0.0
	bottom_dock_bar.offset_top = -52.0
	bottom_dock_bar.offset_right = 0.0
	bottom_dock_bar.offset_bottom = 0.0
	bottom_dock_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_dock_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_dock_bar.visible = true
	
	# Стиль: темный гранитный RTS-бордер с золотым верхним кантом
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	sbox.border_color = Color(0.85, 0.68, 0.28, 1.0) # Золотая окантовка
	sbox.border_width_top = 2
	sbox.border_width_left = 0
	sbox.border_width_right = 0
	sbox.border_width_bottom = 0
	sbox.shadow_color = Color(0, 0, 0, 0.65)
	sbox.shadow_size = 10
	sbox.shadow_offset = Vector2(0, -3)
	sbox.set_content_margin_all(6)
	sbox.content_margin_left = 14
	sbox.content_margin_right = 14
	bottom_dock_bar.add_theme_stylebox_override("panel", sbox)
	
	for c in bottom_dock_bar.get_children():
		c.queue_free()
		
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	bottom_dock_bar.add_child(hbox)
	
	var menu_items = [
		{"id": "settlement", "name": "🏛 Поселение", "icon": "backpack_LVL_01"},
		{"id": "buildings", "name": "🔨 Постройки [B]", "icon": "shovel_01"},
		{"id": "laws", "name": "📜 Законы [L]", "icon": "tome_01"},
		{"id": "relig", "name": "🔮 Религия [R]", "icon": "crystal_01"},
		{"id": "army", "name": "⚔️ Армия [A]", "icon": "short_sword_01"},
		{"id": "map_modes", "name": "🗺 Карта [M]", "icon": "apple_red_01"},
		{"id": "events", "name": "⚡ События", "icon": "book_01"},
		{"id": "history", "name": "📖 Хроника [E]", "icon": "book_01"},
		{"id": "inspector", "name": "⚙️ Инспектор [F12]", "icon": "gold_01"}
	]
	
	for item in menu_items:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(110, 36)
		btn.text = item["name"]
		btn.add_theme_font_size_override("font_size", 12)
		
		var icon_tex = ItemTextureManager.get_icon(item["icon"])
		if icon_tex:
			btn.icon = icon_tex
			btn.expand_icon = true
		
		var btn_normal = StyleBoxFlat.new()
		btn_normal.bg_color = Color(0.13, 0.16, 0.23, 0.9)
		btn_normal.border_color = Color(0.4, 0.5, 0.65, 0.8)
		btn_normal.set_border_width_all(1)
		btn_normal.set_corner_radius_all(5)
		btn_normal.set_content_margin_all(5)
		btn.add_theme_stylebox_override("normal", btn_normal)
		
		var btn_hover = StyleBoxFlat.new()
		btn_hover.bg_color = Color(0.22, 0.28, 0.38, 1.0)
		btn_hover.border_color = Color(1.0, 0.85, 0.4, 1.0)
		btn_hover.set_border_width_all(1)
		btn_hover.set_corner_radius_all(5)
		btn_hover.set_content_margin_all(5)
		btn.add_theme_stylebox_override("hover", btn_hover)
		
		var item_id = item["id"]
		btn.pressed.connect(func(): _on_menu_item_clicked(item_id))
		
		hbox.add_child(btn)
		dock_buttons[item_id] = btn

func _on_menu_item_clicked(item_id: String) -> void:
	if item_id == "map_modes":
		map_mode_panel.visible = not map_mode_panel.visible
		return
	elif map_mode_panel.visible:
		map_mode_panel.visible = false
		
	if item_id == "buildings":
		if rts_build_menu:
			rts_build_menu.toggle_menu()
		else:
			tab_opened.emit("settlement_buildings", null)
	elif item_id == "laws":
		if traditions_modal:
			traditions_modal.open_registry()
	elif item_id == "relig":
		if faith_modal:
			faith_modal.open_chronicle()
	elif item_id == "inspector":
		if dev_inspector:
			dev_inspector.toggle_inspector()
	elif item_id == "events":
		if event_registry_panel:
			event_registry_panel.open_registry()
	else:
		tab_opened.emit(item_id, null)
		
	_highlight_menu_btn(item_id)

func _highlight_menu_btn(active_id: String) -> void:
	active_menu_item = active_id
	for id in dock_buttons:
		var btn = dock_buttons[id]
		if id == active_id:
			btn.modulate = Color(1.3, 1.2, 0.85)
		else:
			btn.modulate = Color.WHITE

# --- ВЫПАДАЮЩАЯ ПАНЕЛЬ РЕЖИМОВ КАРТЫ (НАД НИЖНЕЙ ПАНЕЛЬЮ) ---
func _setup_map_mode_selector() -> void:
	map_mode_panel = PanelContainer.new()
	map_mode_panel.name = "MapModePanel"
	map_mode_panel.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	map_mode_panel.anchor_left = 1.0
	map_mode_panel.anchor_right = 1.0
	map_mode_panel.anchor_top = 1.0
	map_mode_panel.anchor_bottom = 1.0
	map_mode_panel.offset_left = -230.0
	map_mode_panel.offset_top = -235.0
	map_mode_panel.offset_right = -20.0
	map_mode_panel.offset_bottom = -54.0
	map_mode_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_mode_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_mode_panel.visible = false
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.11, 0.14, 0.20, 0.98)
	sbox.border_color = Color(0.85, 0.7, 0.3, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(8)
	sbox.shadow_color = Color(0, 0, 0, 0.6)
	sbox.shadow_size = 8
	sbox.set_content_margin_all(8)
	map_mode_panel.add_theme_stylebox_override("panel", sbox)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	
	var title = Label.new()
	title.text = "🗺 Режимы карты"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	vbox.add_child(title)
	
	var modes = [
		{"id": "normal", "name": "🌍 Обычный мир"},
		{"id": "political", "name": "👑 Границы племён"},
		{"id": "fertility", "name": "🌾 Плодородие почв"},
		{"id": "resources", "name": "⛏ Залежи ресурсов"},
		{"id": "religion", "name": "🔮 Влияние культов"}
	]
	
	for m in modes:
		var btn = Button.new()
		btn.text = m["name"]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		
		var m_id = m["id"]
		btn.pressed.connect(func():
			EventBus.map_mode_changed.emit(m_id)
			map_mode_panel.visible = false
		)
		vbox.add_child(btn)
		
	map_mode_panel.add_child(vbox)
	add_child(map_mode_panel)

# --- СИСТЕМА ТОСТ-УВЕДОМЛЕНИЙ ---
func _setup_toast_system() -> void:
	toast_container = VBoxContainer.new()
	toast_container.name = "ToastContainer"
	toast_container.anchors_preset = Control.PRESET_TOP_RIGHT
	toast_container.anchor_left = 1.0
	toast_container.anchor_right = 1.0
	toast_container.anchor_top = 0.0
	toast_container.offset_left = -340.0
	toast_container.offset_top = 68.0
	toast_container.offset_right = -16.0
	toast_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toast_container.add_theme_constant_override("separation", 6)
	add_child(toast_container)

func _on_notification_toast(title_text: String, message_text: String, toast_type: String = "info") -> void:
	var toast = PanelContainer.new()
	var sbox = StyleBoxFlat.new()
	
	var border_c = Color(0.4, 0.7, 1.0)
	var bg_c = Color(0.1, 0.14, 0.22, 0.95)
	if toast_type == "good":
		border_c = Color(0.3, 0.9, 0.4)
		bg_c = Color(0.08, 0.18, 0.12, 0.95)
	elif toast_type == "bad":
		border_c = Color(1.0, 0.35, 0.3)
		bg_c = Color(0.22, 0.08, 0.08, 0.95)
		
	sbox.bg_color = bg_c
	sbox.border_color = border_c
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(6)
	sbox.shadow_color = Color(0, 0, 0, 0.4)
	sbox.shadow_size = 4
	sbox.set_content_margin_all(8)
	toast.add_theme_stylebox_override("panel", sbox)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var title_lbl = Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", border_c)
	vbox.add_child(title_lbl)
	
	var msg_lbl = Label.new()
	msg_lbl.text = message_text
	msg_lbl.add_theme_font_size_override("font_size", 10)
	msg_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)
	
	toast.add_child(vbox)
	toast_container.add_child(toast)
	
	var tween = create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.3).from(0.0)
	tween.tween_interval(3.5)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): if is_instance_valid(toast): toast.queue_free())

var _clock_refresh_timer: float = 0.0

func _process(delta: float) -> void:
	_clock_refresh_timer += delta
	if _clock_refresh_timer >= 0.25:
		_clock_refresh_timer = 0.0
		if is_instance_valid(date_label):
			date_label.text = GameManager.get_formatted_date()
	if cursor_context_menu and cursor_context_menu.visible and active_inspected_nature_coord != Vector2i(-1, -1):
		_refresh_nature_context_live()

func _on_day_passed(_day: int, _month: int, _year: int) -> void:
	_update_ui()

func _on_resources_updated(_f_id: String, _res: Dictionary) -> void:
	_update_ui()

func _on_speed_changed(new_speed: float, is_paused: bool) -> void:
	pause_btn.modulate = Color(1.4, 0.6, 0.6) if is_paused else Color.WHITE
	speed1_btn.modulate = Color(1.3, 1.2, 0.8) if (new_speed == 1.0 and not is_paused) else Color.WHITE
	speed2_btn.modulate = Color(1.3, 1.2, 0.8) if (new_speed == 2.0 and not is_paused) else Color.WHITE
	speed4_btn.modulate = Color(1.3, 1.2, 0.8) if (new_speed >= 4.0 and not is_paused) else Color.WHITE

func _update_ui() -> void:
	date_label.text = GameManager.get_formatted_date()
	epoch_label.text = GameManager.epoch_name
	
	var s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	if s:
		var econ = s.economy
		var season = GameManager.current_season
		var ledger = s.get_detailed_ledger(season)
		var inc: Dictionary = ledger.get("income", {})
		var exp: Dictionary = ledger.get("expenses", ledger.get("expense", {}))
		
		var food_inc = float(inc.get("food", 0.0))
		var food_exp = float(exp.get("food", 0.0))
		food_label.text = "🍗 %d" % int(econ.get_resource("food"))
		food_label.tooltip_text = _format_tooltip("Пища", econ.get_resource("food"), food_inc - food_exp, {"Добыча": food_inc, "Потребление": -food_exp})
		
		var wood_inc = float(inc.get("wood", 0.0))
		var wood_exp = float(exp.get("wood", 0.0))
		wood_label.text = "🪵 %d" % int(econ.get_resource("wood"))
		wood_label.tooltip_text = _format_tooltip("Древесина", econ.get_resource("wood"), wood_inc - wood_exp, {"Добыча": wood_inc, "Расход": -wood_exp})
		
		var stone_inc = float(inc.get("stone", 0.0))
		stone_label.text = "🪨 %d" % int(econ.get_resource("stone"))
		stone_label.tooltip_text = _format_tooltip("Камень", econ.get_resource("stone"), stone_inc, {"Добыча": stone_inc})
		
		var metal_inc = float(inc.get("metal", 0.0))
		metal_label.text = "⛏ %d" % int(econ.get_resource("metal"))
		metal_label.tooltip_text = _format_tooltip("Металл", econ.get_resource("metal"), metal_inc, {"Добыча": metal_inc})
		
		var kub_inc = float(inc.get("kubriki", 0.0))
		kubriki_label.text = "🪙 %d" % int(econ.get_resource("kubriki"))
		kubriki_label.tooltip_text = _format_tooltip("Кубрики", econ.get_resource("kubriki"), kub_inc, {"Ремесло": kub_inc})
		
		var know_inc = float(inc.get("knowledge", 0.0))
		knowledge_label.text = "📜 %d" % int(econ.get_resource("knowledge"))
		knowledge_label.tooltip_text = _format_tooltip("Знания", econ.get_resource("knowledge"), know_inc, {"Мудрецы": know_inc})
		
		var pop = s.population
		var total_pop = pop.get_total_population()
		var housing_cap = s.get_housing_capacity()
		var unassigned = s.get_idle_workforce()
		
		pop_label.text = "👥 %d/%d (Своб: %d)" % [total_pop, housing_cap, unassigned]
		if total_pop > housing_cap:
			pop_label.tooltip_text = "⚠️ ПЕРЕНАСЕЛЕНИЕ! Не хватает жилья на %d чел.\nПостройте новые хижины." % [total_pop - housing_cap]
			pop_label.modulate = Color(1.0, 0.4, 0.4)
		else:
			pop_label.tooltip_text = "Дети: %d, Юноши: %d, Взрослые: %d, Старейшины: %d" % [pop.children, pop.youth, pop.adults_m + pop.adults_f, pop.elders]
			pop_label.modulate = Color.WHITE
			
		loyalty_label.text = "Лояльность: %d%%" % int(econ.loyalty)
		stability_label.text = "Порядок: %d%%" % int(econ.stability)

func _format_tooltip(res_name: String, total: float, net: float, sources: Dictionary) -> String:
	var lines = ["📊 %s (Запас: %d):" % [res_name, int(total)]]
	for s_name in sources:
		var val = sources[s_name]
		var sign_str = "+" if val > 0 else ""
		lines.append(" • %s: %s%.1f / дн" % [s_name, sign_str, val])
	lines.append("─────────────────────")
	var net_sign = "+" if net >= 0 else ""
	lines.append("Итоговое сальдо: %s%.1f / день" % [net_sign, net])
	return "\n".join(lines)

# --- ВСплывающее КОНТЕКСТНОЕ МЕНЮ КУРСОРА (ПОСТРОИТЬ ЗДЕСЬ / ДЕЙСТВИЕ НАД ОБЪЕКТОМ) ---
func _setup_cursor_context_menu() -> void:
	cursor_context_menu = PanelContainer.new()
	cursor_context_menu.name = "CursorContextMenu"
	cursor_context_menu.top_level = true
	cursor_context_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cursor_context_menu.anchor_left = 0.0
	cursor_context_menu.anchor_top = 0.0
	cursor_context_menu.anchor_right = 0.0
	cursor_context_menu.anchor_bottom = 0.0
	cursor_context_menu.grow_horizontal = Control.GROW_DIRECTION_END
	cursor_context_menu.grow_vertical = Control.GROW_DIRECTION_END
	cursor_context_menu.custom_minimum_size = Vector2(260, 0)
	cursor_context_menu.size = Vector2(260, 0)
	cursor_context_menu.visible = false
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.12, 0.18, 0.98)
	sbox.border_color = Color(0.88, 0.72, 0.32, 1.0) # Золотая окантовка
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(8)
	sbox.shadow_color = Color(0, 0, 0, 0.65)
	sbox.shadow_size = 12
	sbox.shadow_offset = Vector2(2, 4)
	sbox.set_content_margin_all(8)
	cursor_context_menu.add_theme_stylebox_override("panel", sbox)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cursor_context_menu.add_child(vbox)
	
	# Верхняя строка: Иконка + Заголовок + Закрыть
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(header_hbox)
	
	ctx_icon_rect = TextureRect.new()
	ctx_icon_rect.custom_minimum_size = Vector2(28, 28)
	ctx_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ctx_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header_hbox.add_child(ctx_icon_rect)
	
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	header_hbox.add_child(title_box)
	
	ctx_title_lbl = Label.new()
	ctx_title_lbl.text = "Клетка мира"
	ctx_title_lbl.add_theme_font_size_override("font_size", 12)
	ctx_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	title_box.add_child(ctx_title_lbl)
	
	ctx_coords_lbl = Label.new()
	ctx_coords_lbl.text = "X: 0, Y: 0"
	ctx_coords_lbl.add_theme_font_size_override("font_size", 10)
	ctx_coords_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	title_box.add_child(ctx_coords_lbl)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(22, 22)
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(func(): cursor_context_menu.visible = false)
	header_hbox.add_child(close_btn)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	ctx_desc_lbl = Label.new()
	ctx_desc_lbl.add_theme_font_size_override("font_size", 10)
	ctx_desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98))
	ctx_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(ctx_desc_lbl)
	
	ctx_progress_bar = ProgressBar.new()
	ctx_progress_bar.custom_minimum_size = Vector2(0, 12)
	ctx_progress_bar.visible = false
	vbox.add_child(ctx_progress_bar)
	
	# Главная кнопка действия (Построить здесь... / Войти в здание)
	ctx_action_btn = Button.new()
	ctx_action_btn.custom_minimum_size = Vector2(0, 30)
	ctx_action_btn.text = "🔨 Построить здесь... [B]"
	ctx_action_btn.add_theme_font_size_override("font_size", 12)
	
	var act_sbox = StyleBoxFlat.new()
	act_sbox.bg_color = Color(0.18, 0.26, 0.18, 0.98)
	act_sbox.border_color = Color(0.45, 0.9, 0.5, 1.0)
	act_sbox.set_border_width_all(1)
	act_sbox.set_corner_radius_all(6)
	act_sbox.set_content_margin_all(4)
	ctx_action_btn.add_theme_stylebox_override("normal", act_sbox)
	
	var act_hover = StyleBoxFlat.new()
	act_hover.bg_color = Color(0.25, 0.38, 0.25, 1.0)
	act_hover.border_color = Color(0.7, 1.0, 0.7, 1.0)
	act_hover.set_border_width_all(1)
	act_hover.set_corner_radius_all(6)
	act_hover.set_content_margin_all(4)
	ctx_action_btn.add_theme_stylebox_override("hover", act_hover)
	
	vbox.add_child(ctx_action_btn)
	add_child(cursor_context_menu)

func _on_tile_right_clicked(coord: Vector2i, tile_data: Dictionary, screen_pos: Vector2) -> void:
	_open_cursor_context_menu(coord, tile_data, screen_pos)

func _on_tile_selected(coord: Vector2i, tile_data: Dictionary) -> void:
	# Открываем меню только если это здание или центр поселения (не пустая клетка!)
	if GameManager.tile_buildings.has(coord) or tile_data.get("settlement_id", "") != "":
		var mouse_pos = get_viewport().get_mouse_position()
		_open_cursor_context_menu(coord, tile_data, mouse_pos)
	else:
		cursor_context_menu.visible = false

func _on_selection_cleared() -> void:
	cursor_context_menu.visible = false
	active_inspected_nature_coord = Vector2i(-1, -1)

func _refresh_nature_context_live() -> void:
	if not GameManager.resource_manager or not GameManager.resource_manager.nodes.has(active_inspected_nature_coord):
		return
	var node = GameManager.resource_manager.nodes[active_inspected_nature_coord]
	var res_amt = float(node.get("amount", 0.0))
	var max_amt = float(node.get("max_amount", 100.0))
	var is_depleted = node.get("depleted", false) or res_amt <= 0.0
	var res_type = node.get("type", "wood")
	var unit_name = "дров" if res_type == "wood" else ("ед. пищи" if res_type in ["berries", "mushrooms"] else "камня")
	
	ctx_progress_bar.max_value = max_amt
	ctx_progress_bar.value = res_amt
	
	if is_depleted:
		ctx_desc_lbl.text = "Ресурс полностью выработан.\nДерево срублено под корень." if res_type == "wood" else "Ресурс полностью собран."
		ctx_action_btn.visible = false
		ctx_progress_bar.value = 0
	else:
		var status_text = "Готово к заготовке"
		var res_by = node.get("reserved_by", "")
		if res_by != "":
			var worker_name = res_by
			var pl_s = GameManager.settlements.get("player_tribe_settlement", null)
			if pl_s and pl_s.population:
				for c in pl_s.population.citizens:
					if c.citizen_id == res_by:
						worker_name = c.name + " (" + c.job_id + ")"
						break
			status_text = "Добывается: " + worker_name
		ctx_desc_lbl.text = "Запас ресурса: %d / %d %s\nСтатус: %s" % [int(res_amt), int(max_amt), unit_name, status_text]

func _on_nature_object_selected(info: Dictionary, screen_pos: Vector2) -> void:
	var coord: Vector2i = info.get("coord", Vector2i(-1, -1))
	active_inspected_nature_coord = coord
	var n_data: Dictionary = info.get("n_data", {})
	var sprite_name = n_data.get("name", "")
	var cat = n_data.get("category", "")
	
	# Сброс старых подключений кнопки
	for conn in ctx_action_btn.pressed.get_connections():
		ctx_action_btn.pressed.disconnect(conn["callable"])
		
	# Получаем или ищем ресурсный узел
	var node: Dictionary = {}
	if GameManager.resource_manager and GameManager.resource_manager.nodes.has(coord):
		node = GameManager.resource_manager.nodes[coord]
	elif MapResourceManager.RESOURCE_NATURE_CONFIG.has(sprite_name):
		var cfg = MapResourceManager.RESOURCE_NATURE_CONFIG[sprite_name]
		node = {
			"type": cfg["type"],
			"category": cfg["category"],
			"name": cfg["name"],
			"amount": cfg["amount"],
			"max_amount": cfg["amount"],
			"reserved_by": "",
			"depleted": false
		}
		
	var has_res = not node.is_empty() and not node.get("depleted", false)
	var res_type = node.get("type", "wood") if has_res else ""
	var res_amt = float(node.get("amount", 0.0))
	var max_amt = float(node.get("max_amount", 100.0))
	var res_name = node.get("name", n_data.get("name", "Природный объект"))
	
	# 1. Иконка ресурса
	if has_res:
		ctx_icon_rect.texture = ItemTextureManager.get_icon(res_type)
	else:
		ctx_icon_rect.texture = n_data.get("tex", null)
		
	# 2. Название
	var prefix = "🌲 " if cat == "tree" else ("🍄 " if res_type == "mushrooms" else ("🍓 " if res_type == "berries" else ("🪨 " if cat == "rock" else "🌿 ")))
	ctx_title_lbl.text = prefix + res_name
	
	# 3. Подзаголовок
	if has_res:
		var cat_names = {
			"wood": "Лесной ресурс • 100 дров в дереве",
			"food": "Сбор пищи • Ягоды и грибы",
			"stone": "Каменная порода • Каменоломня",
			"metal": "Металлическая руда"
		}
		ctx_coords_lbl.text = cat_names.get(node.get("category", "wood"), "Природный ресурс")
	else:
		ctx_coords_lbl.text = "Растительность и декорации"
		
	# 4. Шкала запаса и описание
	if has_res:
		ctx_progress_bar.visible = true
		ctx_progress_bar.max_value = max_amt
		ctx_progress_bar.value = res_amt
		
		var unit_name = "дров" if res_type == "wood" else ("ед. пищи" if res_type in ["berries", "mushrooms"] else "камня")
		var status_text = "Готово к заготовке"
		var res_by = node.get("reserved_by", "")
		if res_by != "":
			var worker_name = res_by
			var pl_s = GameManager.settlements.get("player_tribe_settlement", null)
			if pl_s and pl_s.population:
				for c in pl_s.population.citizens:
					if c.citizen_id == res_by:
						worker_name = c.name + " (" + c.job_id + ")"
						break
			status_text = "Добывается: " + worker_name
			
		var desc = "Запас ресурса: %d / %d %s\nСтатус: %s" % [int(res_amt), int(max_amt), unit_name, status_text]
		if sprite_name in ["tree_young", "tree_spruce_young"]:
			desc += "\n🌱 Молодой саженец. Растет во взрослое дерево (100 дров)."
		ctx_desc_lbl.text = desc
		
		# Кнопка действия
		ctx_action_btn.visible = true
		ctx_action_btn.disabled = false
		if cat == "tree":
			ctx_action_btn.text = "🪓 Вырубить дерево (Приоритет)"
			ctx_action_btn.pressed.connect(func():
				EventBus.order_harvest_resource.emit(coord, "wood")
			)
		elif res_type in ["berries", "mushrooms"]:
			ctx_action_btn.text = "🧺 Собрать урожай (Приоритет)"
			ctx_action_btn.pressed.connect(func():
				EventBus.order_harvest_resource.emit(coord, "food")
			)
		elif cat == "rock":
			ctx_action_btn.text = "⛏ Добыть камень (Приоритет)"
			ctx_action_btn.pressed.connect(func():
				EventBus.order_harvest_resource.emit(coord, "stone")
			)
		else:
			ctx_action_btn.visible = false
	else:
		ctx_progress_bar.visible = false
		ctx_desc_lbl.text = "Природный элемент ландшафта."
		ctx_action_btn.visible = false
		
	_position_cursor_menu(screen_pos)

func _on_animal_selected(animal: RefCounted, screen_pos: Vector2) -> void:
	active_inspected_nature_coord = Vector2i(-1, -1)
	if animal == null or not animal.is_alive():
		cursor_context_menu.visible = false
		return
		
	# Сброс старых подключений кнопки
	for conn in ctx_action_btn.pressed.get_connections():
		ctx_action_btn.pressed.disconnect(conn["callable"])
		
	var cfg = WildAnimal.SPECIES_CONFIG.get(animal.type_id, {})
	var species_names = {
		"wolf_grey": "Серый волк", "wolf_dark": "Тёмный волк", "wolf_pup": "Волчонок",
		"hare_brown": "Бурый заяц", "hare_white": "Белый заяц", "hare_leveret": "Зайчонок",
		"deer_stag": "Благородный олень", "deer_doe": "Олениха", "deer_fawn": "Оленёнок",
		"moose_bull": "Сохатый лось", "moose_cow": "Лосиха", "moose_calf": "Лосёнок",
		"bear_brown": "Бурый медведь", "bear_dark": "Тёмный медведь", "bear_cub": "Медвежонок",
		"boar_male": "Секач (кабан)", "boar_female": "Кабаниха", "boar_piglet": "Поросёнок",
		"fox_adult": "Рыжая лиса", "fox_kit": "Лисёнок",
		"lynx_adult": "Лесная рысь",
		"badger_adult": "Барсук",
		"duck_drake": "Селезень", "duck_female": "Дикая утка", "duck_duckling": "Утёнок"
	}
	var display_name = species_names.get(animal.type_id, animal.species.capitalize())
	
	ctx_icon_rect.texture = animal.get_texture()
	var prefix = "🐺 " if animal.species == "wolf" else ("🐻 " if animal.species == "bear" else ("🦌 " if animal.species in ["deer", "moose"] else ("🐗 " if animal.species == "boar" else ("🦆 " if animal.species == "duck" else "🐾 "))))
	ctx_title_lbl.text = prefix + display_name
	
	var behavior_desc = "Дикая фауна"
	var bh = cfg.get("behavior", "")
	if bh in ["predator", "territorial", "stealth_predator"]:
		behavior_desc = "⚠️ Опасный хищник! Нападает на людей."
	elif bh in ["defensive", "mother_aggressive"]:
		behavior_desc = "🛡 Защищает потомство и территорию."
	elif bh == "waterfowl":
		behavior_desc = "🌊 Водоплавающая птица. Спасается на воде."
	else:
		behavior_desc = "🌿 Пугливое травоядное животное."
	ctx_coords_lbl.text = behavior_desc
	
	ctx_progress_bar.visible = true
	ctx_progress_bar.max_value = animal.max_health
	ctx_progress_bar.value = animal.health
	
	var mat_name = "Шкура" if animal.extra_material == "hide" else ("Мех" if animal.extra_material == "fur" else ("Перья" if animal.extra_material == "feathers" else "Мелкая шкурка"))
	var drops = "Мясо x%d, %s x%d" % [int(animal.meat_yield), mat_name, animal.extra_material_count] if animal.extra_material_count > 0 else "Мясо x%d" % int(animal.meat_yield)
	
	var state_text = "Пасётся"
	match animal.state:
		WildAnimal.State.FLEEING: state_text = "Убегает от опасности"
		WildAnimal.State.DEFENDING: state_text = "Атакует в ближнем бою!"
		WildAnimal.State.SWIMMING: state_text = "Плавает по воде"
		WildAnimal.State.FOLLOWING: state_text = "Следует за матерью"
		WildAnimal.State.RESTING: state_text = "Отдыхает"
		
	ctx_desc_lbl.text = "Здоровье: %d / %d HP\nСостояние: %s\nДобыча при охоте: %s" % [
		int(animal.health), int(animal.max_health), state_text, drops
	]
	
	ctx_action_btn.visible = true
	ctx_action_btn.disabled = false
	ctx_action_btn.text = "🏹 Направить охотников"
	ctx_action_btn.pressed.connect(func():
		EventBus.notification_toast.emit("Охота", "Охотники поселения выследят эту цель.", "good")
	)
	
	_position_cursor_menu(screen_pos)

func _open_cursor_context_menu(coord: Vector2i, tile_data: Dictionary, screen_pos: Vector2) -> void:
	current_ctx_coord = coord
	current_ctx_tile_data = tile_data
	
	if ctx_action_btn.pressed.is_connected(_open_settlement_panel):
		ctx_action_btn.pressed.disconnect(_open_settlement_panel)
	
	ctx_progress_bar.visible = false
	ctx_action_btn.disabled = false
	
	# Проверяем, есть ли поселение
	if tile_data.get("settlement_id", "") != "":
		var s = GameManager.settlements.get(tile_data["settlement_id"], null)
		if s:
			var is_player = (s.id == "player_tribe_settlement")
			ctx_icon_rect.texture = BuildingTextureManager.get_texture("great_lodge")
			ctx_title_lbl.text = "🏛 %s" % s.name
			ctx_coords_lbl.text = "Столица племени (%d:%d)" % [coord.x, coord.y] if is_player else "Соседнее племя (%d:%d)" % [coord.x, coord.y]
			ctx_desc_lbl.text = "👥 Жители: %d (свободно: %d)\n🛡 Оборона: %.1f" % [
				s.population.get_total_population(), s.get_idle_workforce(), s.get_defense_rating()
			]
			ctx_action_btn.text = "🏛 Управление поселением"
			ctx_action_btn.pressed.connect(_open_settlement_panel)
			_position_cursor_menu(screen_pos)
			return
			
	# Проверяем здание на клетке
	if GameManager.tile_buildings.has(coord):
		var b_data = GameManager.tile_buildings[coord]
		var b_id = b_data.get("id", "")
		var b_info = BuildingDB.get_building(b_id)
		var b_name = b_info.get("name", b_id)
		var status = b_data.get("status", "active")
		
		ctx_icon_rect.texture = BuildingTextureManager.get_texture(b_id)
		
		if status == "constructing":
			ctx_title_lbl.text = "🔨 %s" % b_name
			ctx_coords_lbl.text = "Стройка (%d:%d)" % [coord.x, coord.y]
			var days_left = float(b_data.get("days_left", 1.0))
			var total_days = float(b_data.get("total_days", max(1, b_info.get("build_days", 10))))
			ctx_desc_lbl.text = "Осталось дней: %.1f из %d" % [days_left, int(total_days)]
			ctx_progress_bar.visible = true
			ctx_progress_bar.max_value = total_days
			ctx_progress_bar.value = total_days - days_left
			ctx_action_btn.text = "🔨 Идет возведение..."
			ctx_action_btn.disabled = true
		else:
			ctx_title_lbl.text = "🏠 %s" % b_name
			ctx_coords_lbl.text = "Институт (%d:%d)" % [coord.x, coord.y]
			ctx_desc_lbl.text = "%s" % b_info.get("description", "Действующее здание.")
			var s_id = b_data.get("settlement_id", "player_tribe_settlement")
			var b_inst = GameManager.get_or_create_building_instance(coord, b_id, s_id)
			var s = GameManager.settlements.get(s_id, null)
			ctx_action_btn.text = "🏛 Войти в здание"
			ctx_action_btn.pressed.connect(func():
				cursor_context_menu.visible = false
				if building_detail_panel and s:
					building_detail_panel.open_building(b_inst, s)
			)
			
		_position_cursor_menu(screen_pos)
		return
		
	# Пустая земля / ресурс / вода
	var biome_info = BiomeDefinitions.get_biome_info(tile_data.get("biome", 0))
	ctx_title_lbl.text = "🗺 %s" % biome_info["name"]
	ctx_coords_lbl.text = "Клетка мира (X:%d, Y:%d)" % [coord.x, coord.y]
	
	var desc = "🏔 Высота: %d%% | 💧 Влажн: %d%% | 🌡 Темп: %d%%" % [
		int(tile_data.get("elevation", 0.5) * 100),
		int(tile_data.get("moisture", 0.5) * 100),
		int(tile_data.get("temperature", 0.5) * 100)
	]
	
	if tile_data.get("is_water", false):
		ctx_icon_rect.texture = null
		desc += "\n🌊 Водоём. Строительство невозможно."
		ctx_action_btn.text = "🌊 Водоём"
		ctx_action_btn.disabled = true
	elif tile_data.get("resource", null):
		var res = tile_data["resource"]
		desc += "\n✨ Залежи: %s (+%d)" % [res.get("name", "Ресурс"), res.get("yield", 1)]
		ctx_icon_rect.texture = ItemTextureManager.get_icon(res.get("type", "wood"))
		ctx_action_btn.text = "🔨 Построить здесь... [B]"
		ctx_action_btn.pressed.connect(func():
			cursor_context_menu.visible = false
			if rts_build_menu:
				rts_build_menu.open_menu(coord)
		)
	else:
		ctx_icon_rect.texture = null
		desc += "\n🌱 Свободная земля для возведения зданий."
		ctx_action_btn.text = "🔨 Построить здесь... [B]"
		ctx_action_btn.pressed.connect(func():
			cursor_context_menu.visible = false
			if rts_build_menu:
				rts_build_menu.open_menu(coord)
		)
		
	ctx_desc_lbl.text = desc
	_position_cursor_menu(screen_pos)

func _position_cursor_menu(screen_pos: Vector2) -> void:
	var vp_size = get_viewport().get_visible_rect().size
	cursor_context_menu.reset_size()
	var menu_min = cursor_context_menu.get_combined_minimum_size()
	var menu_w = maxf(260.0, menu_min.x)
	var menu_h = maxf(120.0, menu_min.y)
	var target_x = clampf(screen_pos.x + 10.0, 10.0, vp_size.x - menu_w - 10.0)
	var target_y = clampf(screen_pos.y + 10.0, 64.0, vp_size.y - 70.0 - menu_h - 10.0)
	cursor_context_menu.position = Vector2(target_x, target_y)
	cursor_context_menu.size = Vector2(menu_w, menu_h)
	cursor_context_menu.reset_size()
	cursor_context_menu.visible = true
	cursor_context_menu.move_to_front()

func _on_settlement_context_selected(s: SettlementData) -> void:
	if s == null:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	_open_cursor_context_menu(s.pos, {"settlement_id": s.id}, mouse_pos)

func _open_settlement_panel() -> void:
	if cursor_context_menu:
		cursor_context_menu.visible = false
	tab_opened.emit("settlement", null)

var placement_mode_banner: PanelContainer
var placement_mode_label: Label

func _setup_placement_mode_banner() -> void:
	placement_mode_banner = PanelContainer.new()
	placement_mode_banner.name = "PlacementModeBanner"
	placement_mode_banner.anchors_preset = Control.PRESET_TOP_WIDE
	placement_mode_banner.anchor_top = 0.0
	placement_mode_banner.anchor_bottom = 0.0
	placement_mode_banner.offset_left = 320.0
	placement_mode_banner.offset_top = 68.0
	placement_mode_banner.offset_right = -320.0
	placement_mode_banner.offset_bottom = 104.0
	
	var b_sbox = StyleBoxFlat.new()
	b_sbox.bg_color = Color(0.12, 0.16, 0.24, 0.95)
	b_sbox.border_color = Color(0.35, 0.85, 0.45, 1.0)
	b_sbox.set_border_width_all(2)
	b_sbox.set_corner_radius_all(8)
	b_sbox.set_content_margin_all(6)
	placement_mode_banner.add_theme_stylebox_override("panel", b_sbox)
	
	var b_hbox = HBoxContainer.new()
	b_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	b_hbox.add_theme_constant_override("separation", 14)
	
	placement_mode_label = Label.new()
	placement_mode_label.text = "🔨 РЕЖИМ СТРОИТЕЛЬСТВА: Выберите клетку на карте. ЛКМ — Разместить | ПКМ / ESC — Отмена"
	placement_mode_label.add_theme_font_size_override("font_size", 12)
	placement_mode_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	b_hbox.add_child(placement_mode_label)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "✕ Отмена"
	cancel_btn.custom_minimum_size = Vector2(80, 24)
	cancel_btn.add_theme_font_size_override("font_size", 11)
	cancel_btn.pressed.connect(func():
		EventBus.cancel_building_placement.emit()
	)
	b_hbox.add_child(cancel_btn)
	
	placement_mode_banner.add_child(b_hbox)
	placement_mode_banner.visible = false
	add_child(placement_mode_banner)

func _on_placement_started(building_id: String) -> void:
	var b_info = BuildingDB.get_building(building_id)
	var b_name = b_info.get("name", building_id)
	placement_mode_label.text = "🔨 СТРОИТЕЛЬСТВО [%s]: Кликните ЛКМ по зеленой клетке для закладки | ПКМ / ESC — Отмена" % b_name
	placement_mode_banner.visible = true
	if cursor_context_menu:
		cursor_context_menu.visible = false

func _on_placement_cancelled() -> void:
	placement_mode_banner.visible = false
