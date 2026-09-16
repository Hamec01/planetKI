class_name RTSBuildMenu
extends PanelContainer

var current_category: String = "food"
var target_build_coord: Vector2i = Vector2i(-1, -1)

var category_buttons: Dictionary = {}
var cards_grid: GridContainer
var title_label: Label
var category_desc_label: Label

const CATEGORIES = [
	{"id": "food", "name": "🌾 Промыслы", "desc": "Охота, собирательство, рыболовство и земледелие"},
	{"id": "production", "name": "🪵 Ресурсы", "desc": "Заготовка древесины, камня, руды и ремесленное дело"},
	{"id": "housing", "name": "🏠 Поселение", "desc": "Жилые хижины, дома рода и амбары-хранилища"},
	{"id": "military", "name": "⚔️ Оборона", "desc": "Дозорные вышки, частоколы и площадки воинов"},
	{"id": "society", "name": "🔮 Культура", "desc": "Костровые площади, святилища духов и дома старейшин"}
]

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -340.0
	offset_top = -220.0
	offset_right = 340.0
	offset_bottom = 220.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# Стиль панели в духе классической RTS (темный металл/камень с золоченой окантовкой)
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.11, 0.16, 0.98)
	sbox.border_color = Color(0.85, 0.68, 0.28, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(10)
	sbox.shadow_color = Color(0, 0, 0, 0.65)
	sbox.shadow_size = 12
	sbox.shadow_offset = Vector2(0, 5)
	sbox.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sbox)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)
	
	# Верхняя плашка: Заголовок + Подсказка + Крестик закрытия
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(top_hbox)
	
	title_label = Label.new()
	title_label.text = "🏛 ПРОЕКТЫ И СТРОИТЕЛЬСТВО (Эпоха 1 — Племя)"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title_label)
	
	var tip_lbl = Label.new()
	tip_lbl.text = "[Горячая клавиша: B]"
	tip_lbl.add_theme_font_size_override("font_size", 11)
	tip_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	top_hbox.add_child(tip_lbl)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 26)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func(): close_menu())
	top_hbox.add_child(close_btn)
	
	# Вкладки категорий в стиле RTS
	var cat_hbox = HBoxContainer.new()
	cat_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(cat_hbox)
	
	for cat in CATEGORIES:
		var btn = Button.new()
		btn.text = cat["name"]
		btn.tooltip_text = cat["desc"]
		btn.custom_minimum_size = Vector2(120, 32)
		btn.add_theme_font_size_override("font_size", 11)
		
		var cat_id = cat["id"]
		btn.pressed.connect(func():
			_select_category(cat_id)
		)
		cat_hbox.add_child(btn)
		category_buttons[cat_id] = btn
		
	category_desc_label = Label.new()
	category_desc_label.text = CATEGORIES[0]["desc"]
	category_desc_label.add_theme_font_size_override("font_size", 11)
	category_desc_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	main_vbox.add_child(category_desc_label)
	
	var sep = HSeparator.new()
	main_vbox.add_child(sep)
	
	# Скроллируемая область карточек зданий
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	cards_grid = GridContainer.new()
	cards_grid.columns = 2
	cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_grid.add_theme_constant_override("h_separation", 10)
	cards_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(cards_grid)

func open_menu(at_coord: Vector2i = Vector2i(-1, -1)) -> void:
	target_build_coord = at_coord
	visible = true
	_select_category(current_category)

func close_menu() -> void:
	visible = false
	target_build_coord = Vector2i(-1, -1)

func toggle_menu() -> void:
	if visible:
		close_menu()
	else:
		open_menu()

func _select_category(cat_id: String) -> void:
	current_category = cat_id
	for id in category_buttons:
		var btn: Button = category_buttons[id]
		if id == cat_id:
			btn.modulate = Color(1.35, 1.25, 0.8)
		else:
			btn.modulate = Color(0.85, 0.85, 0.85)
			
	for cat in CATEGORIES:
		if cat["id"] == cat_id:
			category_desc_label.text = cat["desc"]
			break
			
	_refresh_cards()

func _refresh_cards() -> void:
	for child in cards_grid.get_children():
		child.queue_free()
		
	var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	var economy = player_s.economy if player_s else null
	
	for b_id in BuildingDB.BUILDINGS:
		var b_info = BuildingDB.get_building(b_id)
		var b_cat = b_info.get("category", "")
		
		var match_cat = false
		if current_category == "food" and (b_cat == "food"):
			match_cat = true
		elif current_category == "production" and (b_cat == "production"):
			match_cat = true
		elif current_category == "housing" and (b_cat in ["housing", "storage"]):
			match_cat = true
		elif current_category == "military" and (b_cat in ["defense", "military"]):
			match_cat = true
		elif current_category == "society" and (b_cat in ["society", "culture", "religion"]):
			match_cat = true
			
		if not match_cat:
			continue
			
		var card = _create_building_card(b_id, b_info, economy)
		cards_grid.add_child(card)

func _create_building_card(b_id: String, b_info: Dictionary, economy: RefCounted) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(310, 84)
	
	var is_unlocked = true
	if GameManager.culture_memory:
		is_unlocked = GameManager.culture_memory.is_building_unlocked(b_id)
		
	var can_afford = (economy.can_afford(b_info["cost"]) if economy else false) and is_unlocked
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.13, 0.16, 0.22, 0.95)
	if not is_unlocked:
		sbox.border_color = Color(0.4, 0.35, 0.5, 0.6)
	elif can_afford:
		sbox.border_color = Color(0.35, 0.75, 0.45, 0.8)
	else:
		sbox.border_color = Color(0.6, 0.35, 0.3, 0.6)
		
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(8)
	sbox.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sbox)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)
	
	# Иконка постройки
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = BuildingTextureManager.get_texture(b_id)
	if not is_unlocked:
		icon.modulate = Color(0.6, 0.6, 0.7, 0.7)
	hbox.add_child(icon)
	
	# Описание
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = b_info["name"]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5) if is_unlocked else Color(0.7, 0.7, 0.8))
	vbox.add_child(name_lbl)
	
	var desc_lbl = Label.new()
	if not is_unlocked:
		desc_lbl.text = "🔒 Требует решения народа / исторического события."
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.6, 0.9))
	else:
		desc_lbl.text = b_info.get("description", "")
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94))
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)
	
	# Стоимость с пиктограммами
	var cost_items = []
	var res_icons = {"wood": "🪵", "stone": "🪨", "food": "🍗", "metal": "⛏", "kubriki": "🪙", "knowledge": "📜"}
	for r in b_info["cost"]:
		var ic = res_icons.get(r, r)
		cost_items.append("%s %d" % [ic, b_info["cost"][r]])
	cost_items.append("⏳ %d дн." % b_info["build_days"])
	
	var cost_lbl = Label.new()
	cost_lbl.text = " | ".join(cost_items)
	cost_lbl.add_theme_font_size_override("font_size", 10)
	cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.45) if can_afford else Color(1.0, 0.45, 0.4))
	vbox.add_child(cost_lbl)
	
	# Кнопка строительства
	var place_btn = Button.new()
	place_btn.text = "🔨 На карту" if is_unlocked else "🔒 Закрыто"
	place_btn.custom_minimum_size = Vector2(85, 36)
	place_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place_btn.disabled = not can_afford
	place_btn.add_theme_font_size_override("font_size", 10)
	
	if is_unlocked:
		place_btn.pressed.connect(func():
			close_menu()
			EventBus.start_building_placement.emit(b_id)
		)
	hbox.add_child(place_btn)
	
	return card

