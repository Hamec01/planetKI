class_name MapEditor
extends Control

const TILE_SIZE: float = 32.0
const BiomeType = BiomeDefinitions.BiomeType

var map_data: Dictionary = {}
var cur_mode: String = "biome" # "biome", "nature", "spawns"

# Настройки кисти
var cur_biome: int = BiomeType.PLAINS
var brush_size: int = 1 # 1, 3, 99 (заливка)
var cur_nature_obj: String = "tree_oak"
var nature_erase_mode: bool = false
var cur_spawn_target: String = "player" # "player", "ai_1", "ai_2"

# Камера редактора
var cam_pos: Vector2 = Vector2.ZERO
var cam_zoom: float = 1.0
var is_dragging_cam: bool = false
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_start_cam: Vector2 = Vector2.ZERO

var hovered_tile: Vector2i = Vector2i(-1, -1)
var is_painting: bool = false

# UI элементы
var map_name_input: LineEdit
var status_label: Label
var canvas: Node2D
var nature_grid: GridContainer
var biome_container: VBoxContainer
var nature_scroll: ScrollContainer

func _ready() -> void:
	TileTextureManager.load_all_textures()
	map_data = CustomMapManager.create_blank_map(48, 48, BiomeType.PLAINS)
	cam_pos = Vector2(48 * TILE_SIZE * 0.5, 48 * TILE_SIZE * 0.5)
	_build_editor_ui()
	_update_nature_palette("all")

func _build_editor_ui() -> void:
	# Фоновый Canvas для отрисовки карты
	canvas = Node2D.new()
	canvas.name = "MapCanvas"
	canvas.draw.connect(_on_canvas_draw)
	add_child(canvas)
	
	# Главный контейнер интерфейса
	var ui_root = Control.new()
	ui_root.name = "UI"
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root)
	
	# Верхняя панель (TopBar)
	var top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 44)
	ui_root.add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(top_hbox)
	
	var title_lbl = Label.new()
	title_lbl.text = " 🗺️ РЕДАКТОР КАРТ"
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	top_hbox.add_child(title_lbl)
	
	map_name_input = LineEdit.new()
	map_name_input.text = "Моя_Карта_01"
	map_name_input.custom_minimum_size = Vector2(160, 28)
	top_hbox.add_child(map_name_input)
	
	var btn_save = Button.new()
	btn_save.text = "💾 Сохранить"
	btn_save.pressed.connect(_on_save_map)
	top_hbox.add_child(btn_save)
	
	var btn_load = Button.new()
	btn_load.text = "📂 Загрузить"
	btn_load.pressed.connect(_on_open_load_dialog)
	top_hbox.add_child(btn_load)
	
	var btn_clear = Button.new()
	btn_clear.text = "🧹 Очистить (Вода)"
	btn_clear.pressed.connect(func(): _clear_map_to(BiomeType.DEEP_OCEAN))
	top_hbox.add_child(btn_clear)
	
	var btn_clear_plains = Button.new()
	btn_clear_plains.text = "🌱 Очистить (Суша)"
	btn_clear_plains.pressed.connect(func(): _clear_map_to(BiomeType.PLAINS))
	top_hbox.add_child(btn_clear_plains)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)
	
	var btn_play = Button.new()
	btn_play.text = "▶️ ИГРАТЬ НА ЭТОЙ КАРТЕ"
	btn_play.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	btn_play.pressed.connect(_on_play_custom_map)
	top_hbox.add_child(btn_play)
	
	var btn_exit = Button.new()
	btn_exit.text = "⬅️ Главное меню"
	btn_exit.pressed.connect(func(): get_tree().change_scene_to_file("res://src/ui/main_menu.tscn"))
	top_hbox.add_child(btn_exit)
	
	# Боковая панель инструментов (Sidebar)
	var sidebar = PanelContainer.new()
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_top = 48
	sidebar.offset_bottom = -28
	sidebar.custom_minimum_size = Vector2(260, 0)
	ui_root.add_child(sidebar)
	
	var side_vbox = VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 8)
	sidebar.add_child(side_vbox)
	
	# Переключатель режимов: [🎨 Биомы] [🌲 Природа] [⛺ Спавны]
	var mode_tabs = HBoxContainer.new()
	side_vbox.add_child(mode_tabs)
	
	var btn_m_biome = Button.new()
	btn_m_biome.text = "🎨 Биомы"
	btn_m_biome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_m_biome.pressed.connect(func(): _set_mode("biome"))
	mode_tabs.add_child(btn_m_biome)
	
	var btn_m_nature = Button.new()
	btn_m_nature.text = "🌲 Природа"
	btn_m_nature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_m_nature.pressed.connect(func(): _set_mode("nature"))
	mode_tabs.add_child(btn_m_nature)
	
	var btn_m_spawns = Button.new()
	btn_m_spawns.text = "⛺ Спавны"
	btn_m_spawns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_m_spawns.pressed.connect(func(): _set_mode("spawns"))
	mode_tabs.add_child(btn_m_spawns)
	
	# 1. КОНТРОЛЫ РЕЖИМА БИОМОВ
	biome_container = VBoxContainer.new()
	side_vbox.add_child(biome_container)
	
	var brush_hbox = HBoxContainer.new()
	brush_hbox.add_child(Label.new())
	brush_hbox.get_child(0).text = "Размер кисти:"
	
	for bs in [1, 3]:
		var b_btn = Button.new()
		b_btn.text = "%dx%d" % [bs, bs]
		b_btn.pressed.connect(func(sz = bs): brush_size = sz)
		brush_hbox.add_child(b_btn)
		
	var b_fill = Button.new()
	b_fill.text = "Заливка"
	b_fill.pressed.connect(func(): brush_size = 99)
	brush_hbox.add_child(b_fill)
	biome_container.add_child(brush_hbox)
	
	# Список биомов с кнопками
	var biome_scroll = ScrollContainer.new()
	biome_scroll.custom_minimum_size = Vector2(0, 450)
	biome_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	biome_container.add_child(biome_scroll)
	
	var b_list = VBoxContainer.new()
	biome_scroll.add_child(b_list)
	
	var biomes_info = [
		{"id": BiomeType.DEEP_OCEAN, "name": "🌊 Глубокий океан"},
		{"id": BiomeType.SHALLOW_COAST, "name": "🏖️ Мелководье / Берег"},
		{"id": BiomeType.PLAINS, "name": "🌱 Равнины"},
		{"id": BiomeType.MEADOW, "name": "🌸 Цветущий луг"},
		{"id": BiomeType.DECIDUOUS_FOREST, "name": "🌳 Лиственный лес"},
		{"id": BiomeType.PINE_TAIGA, "name": "🌲 Хвойная тайга"},
		{"id": BiomeType.JUNGLE, "name": "🌴 Джунгли"},
		{"id": BiomeType.SAVANNA, "name": "🌾 Саванна"},
		{"id": BiomeType.DESERT, "name": "🏜️ Пустыня"},
		{"id": BiomeType.SWAMP, "name": "🐸 Болото"},
		{"id": BiomeType.HILLS, "name": "⛰️ Холмы"},
		{"id": BiomeType.MOUNTAINS, "name": "🏔️ Скалистые горы"},
		{"id": BiomeType.SNOW_PEAKS, "name": "❄️ Снежные пики"},
		{"id": BiomeType.TUNDRA, "name": "🌨️ Тундра"}
	]
	
	for b_def in biomes_info:
		var btn = Button.new()
		btn.text = b_def["name"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func(b_id = b_def["id"]):
			cur_biome = b_id
		)
		b_list.add_child(btn)
		
	# 2. КОНТРОЛЫ РЕЖИМА ПРИРОДЫ
	nature_scroll = ScrollContainer.new()
	nature_scroll.custom_minimum_size = Vector2(0, 500)
	nature_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nature_scroll.visible = false
	side_vbox.add_child(nature_scroll)
	
	var n_vbox = VBoxContainer.new()
	n_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nature_scroll.add_child(n_vbox)
	
	var n_tools = HBoxContainer.new()
	n_vbox.add_child(n_tools)
	
	var btn_erase = Button.new()
	btn_erase.text = "🗑️ Стереть объект"
	btn_erase.pressed.connect(func(): nature_erase_mode = true)
	n_tools.add_child(btn_erase)
	
	var btn_auto_nature = Button.new()
	btn_auto_nature.text = "✨ Засеять карту"
	btn_auto_nature.pressed.connect(_on_auto_populate_nature)
	n_tools.add_child(btn_auto_nature)
	
	# Фильтр категорий
	var cat_opt = OptionButton.new()
	cat_opt.add_item("Все объекты", 0)
	cat_opt.add_item("Деревья", 1)
	cat_opt.add_item("Кустарники", 2)
	cat_opt.add_item("Скалы и камни", 3)
	cat_opt.add_item("Цветы и грибы", 4)
	cat_opt.add_item("Пустыня и болото", 5)
	cat_opt.add_item("Пни и детали", 6)
	cat_opt.item_selected.connect(func(idx):
		var cats = ["all", "tree", "bush", "rock", "flower_mushroom", "marsh_desert", "detail"]
		_update_nature_palette(cats[idx])
	)
	n_vbox.add_child(cat_opt)
	
	nature_grid = GridContainer.new()
	nature_grid.columns = 4
	nature_grid.add_theme_constant_override("h_separation", 4)
	nature_grid.add_theme_constant_override("v_separation", 4)
	n_vbox.add_child(nature_grid)
	
	# 3. КОНТРОЛЫ СПАВНОВ
	# (будут активироваться по вкладке Спавны)
	
	# Нижняя строка статуса
	var bottom_bar = PanelContainer.new()
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.custom_minimum_size = Vector2(0, 26)
	ui_root.add_child(bottom_bar)
	
	status_label = Label.new()
	status_label.text = " [X: 0, Y: 0] | ЛКМ: Рисовать | ПКМ: Панорама камеры | Колесо мыши: Зум"
	status_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	bottom_bar.add_child(status_label)

func _set_mode(new_mode: String) -> void:
	cur_mode = new_mode
	biome_container.visible = (cur_mode == "biome")
	nature_scroll.visible = (cur_mode == "nature")
	nature_erase_mode = false
	canvas.queue_redraw()

func _update_nature_palette(filter_cat: String) -> void:
	for child in nature_grid.get_children():
		child.queue_free()
		
	var sprites = TileTextureManager.nature_sprites
	var meta = TileTextureManager.nature_meta
	
	for s_name in sprites:
		var item_meta = meta.get(s_name, {})
		var cat = item_meta.get("category", "")
		if filter_cat != "all" and cat != filter_cat:
			continue
			
		var tex = sprites[s_name]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(52, 52)
		btn.icon = tex
		btn.expand_icon = true
		btn.tooltip_text = s_name
		btn.pressed.connect(func(n = s_name):
			cur_nature_obj = n
			nature_erase_mode = false
		)
		nature_grid.add_child(btn)

func _clear_map_to(biome_id: int) -> void:
	var width = map_data["width"]
	var height = map_data["height"]
	var is_water = (biome_id == BiomeType.DEEP_OCEAN or biome_id == BiomeType.SHALLOW_COAST)
	for y in range(height):
		for x in range(width):
			var t = map_data["tiles"][y][x]
			t["biome"] = biome_id
			t["is_water"] = is_water
			t["nature_object"] = ""
	canvas.queue_redraw()

func _on_auto_populate_nature() -> void:
	var width = map_data["width"]
	var height = map_data["height"]
	for y in range(height):
		for x in range(width):
			var t = map_data["tiles"][y][x]
			if not t["is_water"]:
				var auto_data = TileTextureManager.get_nature_data(t["biome"], Vector2i(x, y))
				t["nature_object"] = auto_data.get("name", "")
	canvas.queue_redraw()

func _on_save_map() -> void:
	var map_name = map_name_input.text.strip_edges()
	if CustomMapManager.save_map(map_data, map_name):
		status_label.text = " ✅ Карта успешно сохранена как '%s'!" % map_name
	else:
		status_label.text = " ❌ Ошибка сохранения карты"

func _on_open_load_dialog() -> void:
	var maps = CustomMapManager.get_saved_maps_list()
	if maps.is_empty():
		status_label.text = " ℹ️ Нет сохраненных карт для загрузки"
		return
		
	# Загружаем последнюю или первую из списка
	var chosen = maps[0]
	var loaded = CustomMapManager.load_map(chosen)
	if not loaded.is_empty():
		map_data = loaded
		map_name_input.text = chosen
		status_label.text = " ✅ Карта '%s' загружена!" % chosen
		canvas.queue_redraw()

func _on_play_custom_map() -> void:
	_on_save_map()
	GameManager.custom_map_to_play = map_data
	get_tree().change_scene_to_file("res://src/game.tscn")

# ==============================================================================
# ОБРАБОТКА ВВОДА: РИСОВАНИЕ, КАМЕРА, ЗУМ
# ==============================================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging_cam = mb.pressed
			if is_dragging_cam:
				drag_start_mouse = mb.position
				drag_start_cam = cam_pos
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			is_painting = mb.pressed
			if is_painting:
				_apply_current_tool(hovered_tile)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = clampf(cam_zoom * 1.15, 0.4, 3.5)
			canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = clampf(cam_zoom / 1.15, 0.4, 3.5)
			canvas.queue_redraw()
			
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if is_dragging_cam:
			cam_pos = drag_start_cam - (mm.position - drag_start_mouse) / cam_zoom
			canvas.queue_redraw()
			
		# Расчет тайла под курсором
		var screen_center = size * 0.5
		var world_pos = cam_pos + (mm.position - screen_center) / cam_zoom
		var tx = int(floor(world_pos.x / TILE_SIZE))
		var ty = int(floor(world_pos.y / TILE_SIZE))
		
		if tx >= 0 and tx < map_data["width"] and ty >= 0 and ty < map_data["height"]:
			hovered_tile = Vector2i(tx, ty)
			var cur_b = map_data["tiles"][ty][tx]["biome"]
			var b_name = BiomeDefinitions.get_biome_info(cur_b)["name"]
			var nat_name = map_data["tiles"][ty][tx].get("nature_object", "—")
			status_label.text = " [X: %d, Y: %d] | Биом: %s | Объект: %s | Зум: %.1fx" % [tx, ty, b_name, nat_name, cam_zoom]
		else:
			hovered_tile = Vector2i(-1, -1)
			
		if is_painting and hovered_tile != Vector2i(-1, -1):
			_apply_current_tool(hovered_tile)
			
		canvas.queue_redraw()

func _apply_current_tool(coord: Vector2i) -> void:
	if coord == Vector2i(-1, -1):
		return
	var width = map_data["width"]
	var height = map_data["height"]
	var tiles = map_data["tiles"]
	
	if cur_mode == "biome":
		var is_water = (cur_biome == BiomeType.DEEP_OCEAN or cur_biome == BiomeType.SHALLOW_COAST)
		if brush_size == 99:
			# Заливка
			var target_b = tiles[coord.y][coord.x]["biome"]
			if target_b != cur_biome:
				_flood_fill_biome(coord, target_b, cur_biome)
		else:
			var rad = int(brush_size * 0.5)
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var nx = coord.x + dx
					var ny = coord.y + dy
					if nx >= 0 and nx < width and ny >= 0 and ny < height:
						tiles[ny][nx]["biome"] = cur_biome
						tiles[ny][nx]["is_water"] = is_water
						
	elif cur_mode == "nature":
		if nature_erase_mode:
			tiles[coord.y][coord.x]["nature_object"] = ""
		else:
			tiles[coord.y][coord.x]["nature_object"] = cur_nature_obj
			
	elif cur_mode == "spawns":
		if cur_spawn_target == "player":
			map_data["spawns"]["player"]["pos"] = coord
		elif cur_spawn_target == "ai_1":
			_set_or_add_ai_spawn(0, coord)
		elif cur_spawn_target == "ai_2":
			_set_or_add_ai_spawn(1, coord)
			
	canvas.queue_redraw()

func _set_or_add_ai_spawn(idx: int, coord: Vector2i) -> void:
	var ai_list: Array = map_data["spawns"].get("ai", [])
	while ai_list.size() <= idx:
		ai_list.append({"pos": coord, "name": "ИИ-племя %d" % (ai_list.size() + 1)})
	ai_list[idx]["pos"] = coord
	map_data["spawns"]["ai"] = ai_list

func _flood_fill_biome(start: Vector2i, target_b: int, fill_b: int) -> void:
	var width = map_data["width"]
	var height = map_data["height"]
	var tiles = map_data["tiles"]
	var is_water = (fill_b == BiomeType.DEEP_OCEAN or fill_b == BiomeType.SHALLOW_COAST)
	
	var q: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	visited[start] = true
	
	while not q.is_empty():
		var cur = q.pop_back()
		tiles[cur.y][cur.x]["biome"] = fill_b
		tiles[cur.y][cur.x]["is_water"] = is_water
		
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = cur + off
			if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height and not visited.has(n):
				if tiles[n.y][n.x]["biome"] == target_b:
					visited[n] = true
					q.append(n)

# ==============================================================================
# ОТРИСОВКА КАРТЫ В РЕДАКТОРЕ
# ==============================================================================
func _on_canvas_draw() -> void:
	if not map_data.has("tiles") or map_data["tiles"].is_empty():
		return
		
	var width = map_data["width"]
	var height = map_data["height"]
	var tiles = map_data["tiles"]
	
	var screen_center = size * 0.5
	# Матрица трансформации камеры
	canvas.draw_set_transform(screen_center - cam_pos * cam_zoom, 0.0, Vector2(cam_zoom, cam_zoom))
	
	# 1. Базовые тайлы и переходы
	for y in range(height):
		for x in range(width):
			var tile = tiles[y][x]
			var rect = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			
			var tex = TileTextureManager.get_tile_texture(tile["biome"], tile["coord"])
			if tex:
				canvas.draw_texture_rect(tex, rect, false)
			else:
				var b_info = BiomeDefinitions.get_biome_info(tile["biome"])
				canvas.draw_rect(rect, b_info["color"])
				
			# Бесшовные переходы между биомами
			var overlays = TerrainResolver.get_transition_overlays(tiles, x, y, width, height)
			for ov in overlays:
				var ov_tex = TileTextureManager.get_overlay_texture(ov["biome_folder"], ov["mask"])
				if ov_tex:
					canvas.draw_texture_rect(ov_tex, rect, false)
					
			# Природные объекты (деревья, скалы, кусты, грибы)
			var nat_obj = tile.get("nature_object", "")
			if nat_obj != "":
				var n_data = TileTextureManager.get_nature_data(tile["biome"], tile["coord"], null, nat_obj)
				if not n_data.is_empty() and n_data.get("tex", null) != null:
					var c = rect.get_center()
					var n_tex: Texture2D = n_data["tex"]
					var aspect = n_tex.get_size().x / maxf(1.0, n_tex.get_size().y)
					var target_h: float = n_data.get("scale_h", 20.0)
					var target_w: float = target_h * aspect
					var foot_y = c.y + 11.0
					var n_rect = Rect2(c.x - target_w * 0.5, foot_y - target_h, target_w, target_h)
					
					canvas.draw_circle(Vector2(c.x, foot_y - 1.0), target_w * 0.30, Color(0, 0, 0, 0.22))
					canvas.draw_texture_rect(n_tex, n_rect, false)
					
			# Сетка карты
			canvas.draw_rect(rect, Color(1, 1, 1, 0.08), false, 1.0)
			
	# 2. Спавны
	var p_spawn = map_data["spawns"]["player"]["pos"]
	var p_rect = Rect2(p_spawn.x * TILE_SIZE, p_spawn.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	canvas.draw_circle(p_rect.get_center(), 14.0, Color(0.2, 0.8, 1.0, 0.4))
	canvas.draw_circle(p_rect.get_center(), 14.0, Color(0.2, 0.8, 1.0, 0.9), false, 2.0)
	
	for ai_s in map_data["spawns"].get("ai", []):
		var ai_pos = ai_s["pos"]
		var ai_rect = Rect2(ai_pos.x * TILE_SIZE, ai_pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		canvas.draw_circle(ai_rect.get_center(), 14.0, Color(0.9, 0.3, 0.3, 0.4))
		canvas.draw_circle(ai_rect.get_center(), 14.0, Color(0.9, 0.3, 0.3, 0.9), false, 2.0)
		
	# 3. Подсветка курсора и кисти
	if hovered_tile != Vector2i(-1, -1):
		var h_rect = Rect2(hovered_tile.x * TILE_SIZE, hovered_tile.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		if cur_mode == "biome" and brush_size > 1 and brush_size != 99:
			var rad = int(brush_size * 0.5)
			var b_area = Rect2((hovered_tile.x - rad) * TILE_SIZE, (hovered_tile.y - rad) * TILE_SIZE, brush_size * TILE_SIZE, brush_size * TILE_SIZE)
			canvas.draw_rect(b_area, Color(1, 0.9, 0.2, 0.25))
			canvas.draw_rect(b_area, Color(1, 0.9, 0.2, 0.8), false, 2.0)
		else:
			canvas.draw_rect(h_rect, Color(1, 1, 1, 0.3))
			canvas.draw_rect(h_rect, Color(1, 0.9, 0.2, 0.9), false, 2.0)
			
		# Призрак объекта природы под курсором
		if cur_mode == "nature" and not nature_erase_mode:
			var n_tex = TileTextureManager.nature_sprites.get(cur_nature_obj, null)
			if n_tex:
				var c = h_rect.get_center()
				var aspect = n_tex.get_size().x / maxf(1.0, n_tex.get_size().y)
				var meta = TileTextureManager.nature_meta.get(cur_nature_obj, {})
				var target_h: float = meta.get("scale_h", 20.0)
				var target_w: float = target_h * aspect
				var foot_y = c.y + 11.0
				var ghost_rect = Rect2(c.x - target_w * 0.5, foot_y - target_h, target_w, target_h)
				canvas.draw_texture_rect(n_tex, ghost_rect, false, Color(1, 1, 1, 0.6))
