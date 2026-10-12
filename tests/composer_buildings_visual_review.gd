extends Node2D

const ComposerBuildings = preload("res://src/core/composer_buildings.gd")
const ComposerAssets = preload("res://src/core/composer_assets.gd")
const NPCGenerator = preload("res://src/simulation/npc_generator.gd")

var _npc_showcase_list: Array = []

func _ready() -> void:
	ComposerBuildings.ready_pack()
	ComposerAssets.ready_pack()
	_init_npc_showcase()
	queue_redraw()
	# Подождём 3 кадра для полной отрисовки
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_save_screenshot()

func _init_npc_showcase() -> void:
	var npc_samples = [
		{"name": "Ратибор", "gender": "m", "cohort": "adult", "job_id": "woodcutter", "desc": "Лесоруб (борода, топор)"},
		{"name": "Велена", "gender": "f", "cohort": "adult", "job_id": "forager", "desc": "Травница (косы, веснушки)"},
		{"name": "Ярополк", "gender": "m", "cohort": "youth", "job_id": "hunter", "desc": "Охотник (лук, андеркат)"},
		{"name": "Мирослав", "gender": "m", "cohort": "elder", "job_id": "elder", "desc": "Старец (седая борода)"},
		{"name": "Берегиня", "gender": "f", "cohort": "elder", "job_id": "elder", "desc": "Матриарх (корона кос)"},
		{"name": "Доброгнева", "gender": "f", "cohort": "adult", "job_id": "guard", "desc": "Воительница (шрам, меч)"},
		{"name": "Горыня", "gender": "m", "cohort": "adult", "job_id": "guard", "desc": "Богатырь (доспех, шлем)"},
		{"name": "Светозар", "gender": "m", "cohort": "adult", "job_id": "miner", "desc": "Рудокоп (кирка, эспаньолка)"},
		{"name": "Богдан", "gender": "m", "cohort": "child", "job_id": "idle", "desc": "Мальчик (кудри, 8 лет)"},
		{"name": "Злата", "gender": "f", "cohort": "child", "job_id": "idle", "desc": "Девочка (хвостики, 6 лет)"}
	]
	var npc_row_y = 960.0
	var npc_spacing = 145.0
	var npc_start_x = 90.0
	for n_idx in range(npc_samples.size()):
		var data = npc_samples[n_idx]
		var nx = npc_start_x + float(n_idx) * npc_spacing
		var npc_pos = Vector2(nx, npc_row_y + 15)
		var npc_obj = NPCGenerator.generate_citizen({
			"id": "demo_showcase_%d" % n_idx,
			"name": data["name"],
			"gender": data["gender"],
			"cohort": data["cohort"],
			"job_id": data["job_id"]
		})
		npc_obj.pos = npc_pos
		npc_obj.facing_dir = Vector2(1, 0) if (n_idx % 2 == 0) else Vector2(-1, 0)
		if data["job_id"] == "guard":
			if data["gender"] == "f":
				npc_obj.equipment["weapon"] = "short_sword"
				npc_obj.equipment["body_armor"] = "leather_armor"
				npc_obj.equipment["shield"] = "weapons_6"
				npc_obj.custom_data.get("composer_slots", {})["token_scar"] = "face_extra_24"
			else:
				npc_obj.equipment["weapon"] = "short_sword"
				npc_obj.equipment["body_armor"] = "chainmail"
				npc_obj.equipment["helmet"] = "iron_helmet"
				npc_obj.equipment["shield"] = "weapons_6"
		var tex = npc_obj.get_texture()
		_npc_showcase_list.append({
			"npc": npc_obj,
			"tex": tex,
			"data": data,
			"nx": nx,
			"npc_pos": npc_pos
		})

func _save_screenshot() -> void:
	var vp = get_viewport()
	var img = vp.get_texture().get_image()
	if img:
		var dir = DirAccess.open("res://")
		if not dir.dir_exists("scratch"):
			dir.make_dir("scratch")
		var save_path = "res://scratch/composer-buildings-visual-review.png"
		var err = img.save_png(save_path)
		print("VISUAL REVIEW SCREENSHOT SAVED: %s (err: %d, size: %dx%d)" % [save_path, err, img.get_width(), img.get_height()])
	get_tree().quit(0)

func _draw() -> void:
	var font = ThemeDB.fallback_font
	
	# Фон демонстрационной сцены (тёмно-землистый цвет игрового биома)
	draw_rect(Rect2(0, 0, 1600, 1080), Color(0.12, 0.14, 0.16))
	
	# 1. ЗАГОЛОВОК
	var title = "PLANETKI x ASSET COMPOSER: ПОЛНЫЙ КАТАЛОГ ЗДАНИЙ, СОСТОЯНИЙ И ПРЕДМЕТОВ"
	draw_string(font, Vector2(40, 36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.90, 0.70))
	var subtitle = "Единый коэффициент K = 0.04 (Взрослый чиби = 8.96 px) • 7 Зданий x 5 Состояний = 35 состояний • 36 Улучшений и орудий"
	draw_string(font, Vector2(40, 58), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.85, 0.95))
	
	# =========================================================================
	# СЕКЦИЯ 1: БОЛЬШОЙ ДОМ РОДА (GREAT LODGE) — ВСЕ 5 ДИСКРЕТНЫХ СОСТОЯНИЙ
	# =========================================================================
	draw_line(Vector2(40, 75), Vector2(1560, 75), Color(0.3, 0.4, 0.5, 0.5), 1.0)
	draw_string(font, Vector2(40, 95), "1. БОЛЬШОЙ ДОМ РОДА (GREAT LODGE) — 5 ДИСКРЕТНЫХ СОСТОЯНИЙ И ВЗРОСЛЫЙ ЧИБИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	
	var states = ["foundation", "half_built", "complete", "damaged", "ruined"]
	var state_labels = ["1. Свайный фундамент", "2. Возведение стен/стропил", "3. Завершённый дом", "4. Повреждения крыши", "5. Руины / Пепелище"]
	
	var start_x = 110.0
	var lodge_y = 260.0
	var col_spacing = 250.0
	
	for i in range(states.size()):
		var st = states[i]
		var px = start_x + float(i) * col_spacing
		var ground_pos = Vector2(px, lodge_y)
		
		# Мягкая тень на земле
		draw_circle(ground_pos + Vector2(0, -2), 38.0, Color(0.08, 0.10, 0.08, 0.65))
		
		# Отрисовка через ComposerBuildings.draw_building
		ComposerBuildings.draw_building(self, "great_lodge", st, ground_pos)
		
		# Подпись состояния
		draw_string(font, Vector2(px - 90, lodge_y + 22), state_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.92, 1.0))
		draw_string(font, Vector2(px - 90, lodge_y + 36), "state = \"%s\"" % st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.70, 0.85))
	
	# Взрослые токены чиби рядом с готовым Большим домом (для строгой сверки масштаба)
	var complete_x = start_x + 2.0 * col_spacing
	var citizen_left_pos = Vector2(complete_x - 65.0, lodge_y)
	var citizen_right_pos = Vector2(complete_x + 65.0, lodge_y)
	
	# Тень под токенами чиби
	draw_circle(citizen_left_pos + Vector2(0, 1), 5.0, Color(0, 0, 0, 0.45))
	draw_circle(citizen_right_pos + Vector2(0, 1), 5.0, Color(0, 0, 0, 0.45))
	
	# Создаем токен чиби через прокси ComposerAssets
	var proxy_left = ComposerAssets.proxy("cit_demo_1", "woodcutter")
	var proxy_right = ComposerAssets.proxy("cit_demo_2", "hunter")
	proxy_left.pos = citizen_left_pos
	proxy_right.pos = citizen_right_pos
	proxy_left.facing_dir = Vector2(-1, 0) # Смотрит влево
	proxy_right.facing_dir = Vector2(1, 0)  # Смотрит вправо
	
	ComposerAssets.draw_citizen(self, proxy_left, 1.0, "idle")
	ComposerAssets.draw_citizen(self, proxy_right, 1.0, "idle")
	
	# Подпись для масштаба чиби
	draw_string(font, Vector2(complete_x - 85, lodge_y - 105), "▲ Чиби взрослого (H = 8.96 px)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 1.0, 0.6))
	
	# =========================================================================
	# СЕКЦИЯ 2: ОСТАЛЬНЫЕ 6 ЗДАНИЙ ПОСЕЛЕНИЯ В ГОТОВОМ СОСТОЯНИИ (COMPLETE)
	# =========================================================================
	var sec2_y = 330.0
	draw_line(Vector2(40, sec2_y), Vector2(1560, sec2_y), Color(0.3, 0.4, 0.5, 0.5), 1.0)
	draw_string(font, Vector2(40, sec2_y + 20), "2. ОСТАЛЬНЫЕ 6 ЗДАНИЙ ПОСЕЛЕНИЯ (ПОЛНЫЙ КАТАЛОГ ИЗ MANIFEST.JSON, СОСТОЯНИЕ COMPLETE)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	
	var other_buildings = ["hunting_camp", "foraging_post", "seed_store", "quern_house", "bakery", "tannery"]
	var other_labels = ["Лагерь охотников", "Стоянка собирателей", "Амбар семян", "Дом жерновов", "Пекарня", "Кожевня"]
	var other_scales = ["s=4.0", "s=3.0", "s=4.0", "s=3.0", "s=3.0", "s=4.0"]
	
	var row2_y = 510.0
	var col2_spacing = 240.0
	var start2_x = 110.0
	
	for j in range(other_buildings.size()):
		var b_id = other_buildings[j]
		var px = start2_x + float(j) * col2_spacing
		var ground_pos = Vector2(px, row2_y)
		
		draw_circle(ground_pos + Vector2(0, -2), 34.0, Color(0.08, 0.10, 0.08, 0.65))
		ComposerBuildings.draw_building(self, b_id, "complete", ground_pos)
		
		# Рядом ставим токен жителя для сверки масштаба пропорций каждого здания
		var cit_pos = Vector2(px + 45.0, row2_y)
		draw_circle(cit_pos + Vector2(0, 1), 4.5, Color(0, 0, 0, 0.4))
		var c_token = ComposerAssets.proxy("cit_prop_%d" % j, "gatherer")
		c_token.pos = cit_pos
		c_token.facing_dir = Vector2(-1, 0)
		ComposerAssets.draw_citizen(self, c_token, 0.5, "idle")
		
		draw_string(font, Vector2(px - 70, row2_y + 20), other_labels[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.92, 1.0))
		draw_string(font, Vector2(px - 70, row2_y + 34), "%s (%s)" % [b_id, other_scales[j]], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.70, 0.85))
	
	# =========================================================================
	# СЕКЦИЯ 3: 36 УЛУЧШЕНИЙ И ПРЕДМЕТОВ (ДВОРОВЫЕ, ОРУДИЯ, ИНТЕРЬЕР)
	# =========================================================================
	var sec3_y = 580.0
	draw_line(Vector2(40, sec3_y), Vector2(1560, sec3_y), Color(0.3, 0.4, 0.5, 0.5), 1.0)
	draw_string(font, Vector2(40, sec3_y + 20), "3. УЛУЧШЕНИЯ И ПРЕДМЕТЫ (ДВОРОВЫЕ ОБЪЕКТЫ, С/Х ОРУДИЯ И ПРЕДПРОСМОТР ИНТЕРЬЕРА)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	
	# 3.1 Дворовые улучшения (Yard Objects)
	var yard_title = "Дворовые объекты (размещение во дворе с собственной тенью и Y-сортировкой):"
	draw_string(font, Vector2(40, sec3_y + 44), yard_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.9, 0.6))
	
	var yard_samples = [
		{"id": "clan_totems", "name": "Родовые тотемы"},
		{"id": "knowledge_circle", "name": "Круг знаний"},
		{"id": "hunt_campfire", "name": "Костёр охотников"},
		{"id": "hunt_butchering_area", "name": "Стол разделки"},
		{"id": "hunt_dogs", "name": "Охотничьи псы"},
		{"id": "forage_drying_racks", "name": "Сушилка трав"},
		{"id": "forage_sorting_table", "name": "Стол травника"},
		{"id": "forage_baskets", "name": "Корзины сбора"},
		{"id": "forage_storage_pit", "name": "Яма припасов"}
	]
	
	var yard_row_y = 690.0
	var yard_spacing = 90.0
	for k in range(yard_samples.size()):
		var sample = yard_samples[k]
		var yx = 70.0 + float(k) * yard_spacing
		var g_pos = Vector2(yx, yard_row_y)
		draw_circle(g_pos + Vector2(0, -1), 6.0, Color(0.08, 0.10, 0.08, 0.5))
		ComposerBuildings.draw_upgrade(self, sample["id"], g_pos)
		draw_string(font, Vector2(yx - 36, yard_row_y + 16), sample["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.9, 0.85))
	
	# 3.2 Сельскохозяйственные орудия (8 предметов из каталога agriculture)
	var tools_title = "Сельскохозяйственные орудия (8 предметов, включая отдельный flint_sickle 1254x1254):"
	draw_string(font, Vector2(920, sec3_y + 44), tools_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.75, 0.35))
	
	var tools_samples = [
		{"id": "flint_sickle", "name": "Серп (1254x1254)"},
		{"id": "digging_stick", "name": "Палка-копалка"},
		{"id": "stone_hoe", "name": "Кам. мотыга"},
		{"id": "wooden_hoe", "name": "Дер. мотыга"},
		{"id": "threshing_flail", "name": "Цеп"},
		{"id": "winnowing_sieve", "name": "Сито"},
		{"id": "wooden_ard", "name": "Рало"},
		{"id": "ox_yoke", "name": "Ярмо вола"}
	]
	
	var tool_row_y = 690.0
	var tool_spacing = 76.0
	for t in range(tools_samples.size()):
		var ts = tools_samples[t]
		var tx = 950.0 + float(t) * tool_spacing
		var g_pos = Vector2(tx, tool_row_y)
		draw_circle(g_pos + Vector2(0, -1), 5.0, Color(0.08, 0.10, 0.08, 0.5))
		ComposerBuildings.draw_upgrade(self, ts["id"], g_pos)
		draw_string(font, Vector2(tx - 32, tool_row_y + 16), ts["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.9, 0.7))
	
	# 3.3 Карточка предпросмотра интерьерных улучшений (компактный вид)
	var card_rect = Rect2(40, 720, 1520, 110)
	draw_rect(card_rect, Color(0.06, 0.12, 0.20, 0.95))
	draw_rect(card_rect, Color(0.25, 0.65, 0.95, 0.85), false, 1.5)
	
	var card_header = "[ИНТЕРЬЕР: РЕЖИМ ПРЕДПРОСМОТРА · СЛОИ КРЫШИ И ПОЛА В РАЗРАБОТКЕ]"
	draw_string(font, Vector2(60, 740), card_header, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.9, 1.0))
	var card_info = "Интерьерные модули (очаг, люльки, закрома) не выбрасываются во двор, а отображаются в карточке здания:"
	draw_string(font, Vector2(60, 755), card_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.92, 0.98))
	
	var interior_samples = [
		{"id": "great_hearth", "name": "Очаг"},
		{"id": "nursery_corner", "name": "Люлька"},
		{"id": "caretaker_quarters", "name": "Опекун"},
		{"id": "communal_store", "name": "Закрома"},
		{"id": "drying_beams", "name": "Балки"},
		{"id": "forage_indoor_drying", "name": "Сушилка"},
		{"id": "hunt_smoke_corner", "name": "Коптильня"},
		{"id": "hunt_salt_trough", "name": "Корыто"},
		{"id": "hunt_trophy_hearth", "name": "Трофеи"},
		{"id": "partitions", "name": "Стенка"}
	]
	
	var int_row_y = 800.0
	var int_spacing = 145.0
	for m in range(interior_samples.size()):
		var mod = interior_samples[m]
		var mx = 90.0 + float(m) * int_spacing
		var g_pos = Vector2(mx, int_row_y)
		draw_circle(g_pos + Vector2(0, -1), 7.0, Color(0.04, 0.08, 0.12, 0.6))
		ComposerBuildings.draw_upgrade(self, mod["id"], g_pos)
		draw_string(font, Vector2(mx - 32, int_row_y + 16), mod["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.85, 0.4))

	# =========================================================================
	# СЕКЦИЯ 4: ПРОЦЕДУРНАЯ ГЕНЕРАЦИЯ УНИКАЛЬНЫХ NPC ПО ТРЕБОВАНИЮ (265 МОДУЛЕЙ CHIBI)
	# =========================================================================
	var sec4_y = 840.0
	draw_line(Vector2(40, sec4_y), Vector2(1560, sec4_y), Color(0.3, 0.4, 0.5, 0.5), 1.0)
	draw_string(font, Vector2(40, sec4_y + 18), "4. ПРОЦЕДУРНАЯ ГЕНЕРАЦИЯ УНИКАЛЬНЫХ NPC ПО ТРЕБОВАНИЮ (ON-DEMAND NPC GENERATOR — 265 МОДУЛЕЙ CHIBI)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	var sec4_sub = "Каждый житель генерируется с индивидуальным набором: 24 причёски, 14 бород, 25 типов глаз, 16 бровей, 10 носов, 18 ртов, шрамы, веснушки, экипировка"
	draw_string(font, Vector2(40, sec4_y + 34), sec4_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.85, 0.95))
	
	var npc_row_y = 960.0
	for item in _npc_showcase_list:
		var nx: float = item["nx"]
		var npc_pos: Vector2 = item["npc_pos"]
		var npc_obj = item["npc"]
		var data: Dictionary = item["data"]
		var portrait_tex = item["tex"]
		
		# Мягкая тень под чиби
		draw_circle(npc_pos + Vector2(0, 1), 5.5, Color(0, 0, 0, 0.45))
		
		# 1. Детальный портрет лица крупным планом (52x54) с аккуратной рамкой
		var p_rect = Rect2(nx - 26, npc_row_y - 68, 52, 54)
		draw_rect(p_rect, Color(0.18, 0.20, 0.24, 0.9))
		draw_rect(p_rect, Color(0.35, 0.45, 0.55, 0.8), false, 1.0)
		if portrait_tex:
			draw_texture_rect(portrait_tex, p_rect, false)
			
		# 2. Игровой токен в масштабе K=0.04 (с оружием и инструментами)
		ComposerAssets.draw_citizen(self, npc_obj, 0.0, "idle")
		
		# 3. Подписи
		draw_string(font, Vector2(nx - 45, npc_row_y + 30), data["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.95, 0.8))
		draw_string(font, Vector2(nx - 55, npc_row_y + 42), data["desc"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.85, 0.95))
