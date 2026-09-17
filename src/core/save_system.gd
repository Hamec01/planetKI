extends Node

const SAVE_PATH: String = "user://planetki_save.json"
const SAVE_TEMP_PATH: String = "user://planetki_save.tmp"
const SAVE_BAK_PATH: String = "user://planetki_save.bak"
const CURRENT_SCHEMA_VERSION: int = 2
var last_loaded_version: int = 1

func save_game() -> bool:
	var culture_data = GameManager.culture_memory.serialize() if GameManager.culture_memory else {}
	var ev_mgr_data = GameManager.civilization_event_manager.serialize() if GameManager.civilization_event_manager else {}
	
	var s_serialized = {}
	for s_id in GameManager.settlements:
		var s = GameManager.settlements[s_id]
		if s is SettlementData:
			s_serialized[s_id] = s.serialize()
		else:
			s_serialized[s_id] = s

	var factions_data = {}
	for f_id in GameManager.factions:
		var f = GameManager.factions[f_id]
		if f is FactionData:
			factions_data[f_id] = {
				"id": f.id,
				"name": f.name,
				"leader_name": f.leader_name,
				"color": [f.color.r, f.color.g, f.color.b, f.color.a],
				"is_player": f.is_player,
				"active_laws": f.active_laws.duplicate()
			}

	# Сохранение зданий на плитках и экземпляров BuildingInstance
	var tile_b_serialized = []
	for coord in GameManager.tile_buildings:
		tile_b_serialized.append({
			"coord": [coord.x, coord.y],
			"data": GameManager.tile_buildings[coord]
		})

	var b_inst_serialized = []
	for coord in GameManager.building_instances:
		var inst = GameManager.building_instances[coord]
		if inst and inst.has_method("serialize"):
			b_inst_serialized.append({
				"coord": [coord.x, coord.y],
				"data": inst.serialize()
			})

	var save_dict = {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"version": "0.4.0",
		"world_seed": GameManager.world_seed,
		"current_day": GameManager.current_day,
		"current_month": GameManager.current_month,
		"current_year": GameManager.current_year,
		"total_simulation_days": GameManager.total_simulation_days,
		"current_epoch": GameManager.current_epoch,
		"epoch_name": GameManager.epoch_name,
		"current_hour": GameManager.current_hour,
		"current_time_period": GameManager.current_time_period,
		"tick_accumulator": GameManager.tick_accumulator,
		"sim_time_total": GameManager.sim_time_total,
		"base_tick_interval": GameManager.base_tick_interval,
		"is_game_over": GameManager.is_game_over,
		"game_over_reason": GameManager.game_over_reason,
		"player_faction_id": GameManager.player_faction_id,
		"history_log": GameManager.history_log,
		"factions_data": factions_data,
		"settlements_data": s_serialized,
		"tile_buildings": tile_b_serialized,
		"building_instances": b_inst_serialized,
		"resource_manager": GameManager.resource_manager.serialize() if GameManager.resource_manager else [],
		"wildlife": GameManager.wildlife_manager.serialize() if GameManager.wildlife_manager else {},
		"star_system_data": GameManager.star_system_data,
		"planet_data": GameManager.planet_data,
		"culture_memory": culture_data,
		"civilization_event_manager": ev_mgr_data,
		"task_service": GameManager.task_service.serialize() if GameManager.task_service else {}
	}
	
	# Безопасная запись через временный файл и backup
	var json_string = JSON.stringify(save_dict, "\t")
	var tmp_file = FileAccess.open(SAVE_TEMP_PATH, FileAccess.WRITE)
	if not tmp_file:
		push_error("Не удалось открыть временный файл для сохранения: " + SAVE_TEMP_PATH)
		return false
	tmp_file.store_string(json_string)
	tmp_file.close()

	# Валидация записанного файла
	var verify_check = FileAccess.open(SAVE_TEMP_PATH, FileAccess.READ)
	if not verify_check:
		return false
	var read_back = verify_check.get_as_text()
	verify_check.close()
	if read_back.length() == 0:
		return false

	# Ротация backup
	if FileAccess.file_exists(SAVE_PATH):
		var old_file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if old_file:
			var old_content = old_file.get_as_text()
			old_file.close()
			var bak_file = FileAccess.open(SAVE_BAK_PATH, FileAccess.WRITE)
			if bak_file:
				bak_file.store_string(old_content)
				bak_file.close()

	# Замена основного файла сохранения
	var main_file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not main_file:
		push_error("Не удалось записать в основной файл сохранения: " + SAVE_PATH)
		return false
	main_file.store_string(json_string)
	main_file.close()
	
	print("Игра успешно сохранена в " + SAVE_PATH)
	return true

func load_game() -> bool:
	var target_path = SAVE_PATH
	if not FileAccess.file_exists(target_path):
		if FileAccess.file_exists(SAVE_BAK_PATH):
			target_path = SAVE_BAK_PATH
		else:
			push_warning("Файл сохранения не найден: " + SAVE_PATH)
			return false
		
	var file = FileAccess.open(target_path, FileAccess.READ)
	if not file:
		push_error("Не удалось открыть файл для загрузки: " + target_path)
		return false
		
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(content)
	if parse_result != OK:
		push_error("Ошибка парсинга JSON сохранения: " + json.get_error_message())
		return false
		
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return false
		
	var _schema_ver = data.get("schema_version", 1)
	last_loaded_version = int(_schema_ver)

	# --- ФАЗА 1: ДЕСЕРИАЛИЗАЦИЯ СУЩНОСТЕЙ И СТРУКТУР ---
	GameManager.world_seed = data.get("world_seed", "PLN-7A4F-9231-B")
	GameManager.current_day = data.get("current_day", 1)
	GameManager.current_month = data.get("current_month", 1)
	GameManager.current_year = data.get("current_year", 1)
	GameManager.total_simulation_days = data.get("total_simulation_days", 1)
	GameManager.current_epoch = data.get("current_epoch", 1)
	GameManager.epoch_name = data.get("epoch_name", "Эпоха 1 — Племя")
	GameManager.current_hour = float(data.get("current_hour", 6.0))
	GameManager.current_time_period = data.get("current_time_period", "Утро")
	GameManager.base_tick_interval = float(data.get("base_tick_interval", 900.0))
	GameManager.tick_accumulator = float(data.get("tick_accumulator", 225.0))
	GameManager.sim_time_total = float(data.get("sim_time_total", 0.0))
	GameManager.is_game_over = bool(data.get("is_game_over", false))
	GameManager.game_over_reason = data.get("game_over_reason", "")
	GameManager.player_faction_id = data.get("player_faction_id", "player_tribe")
	
	GameManager.history_log.clear()
	var raw_log = data.get("history_log", [])
	if raw_log is Array:
		for item in raw_log:
			if item is Dictionary:
				GameManager.history_log.append(item)
				
	if data.has("factions_data"):
		var fac_dict = data["factions_data"]
		for f_id in fac_dict:
			var fd = fac_dict[f_id]
			if fd is Dictionary:
				var c_arr = fd.get("color", [1,1,1,1])
				var col = Color(c_arr[0], c_arr[1], c_arr[2], c_arr[3]) if c_arr.size() == 4 else Color.WHITE
				var new_f = FactionData.new(f_id, fd.get("name", ""), fd.get("leader_name", ""), col, fd.get("is_player", false))
				new_f.active_laws.assign(fd.get("active_laws", new_f.active_laws))
				GameManager.factions[f_id] = new_f
				
	GameManager.star_system_data = data.get("star_system_data", {})
	GameManager.planet_data = data.get("planet_data", {})
	GameManager.current_season = GameManager._get_season_for_month(GameManager.current_month)
	
	# Инициализация навигационной сетки и ресурсов БЕЗ повторного спавна стартовых животных/жителей
	if GameManager.planet_data.has("tiles"):
		var w = GameManager.planet_data.get("width", 160)
		var h = GameManager.planet_data.get("height", 160)
		GameManager.nav_grid.initialize_grid(GameManager.planet_data["tiles"], w, h)
		GameManager.resource_manager.initialize_from_tiles(GameManager.planet_data["tiles"], w, h)
	
	if data.has("resource_manager") and GameManager.resource_manager:
		GameManager.resource_manager.deserialize(data["resource_manager"])

	# Восстановление tile_buildings
	GameManager.tile_buildings.clear()
	if data.has("tile_buildings"):
		for tb in data["tile_buildings"]:
			var c_arr = tb.get("coord", [0, 0])
			var c = Vector2i(c_arr[0], c_arr[1])
			GameManager.tile_buildings[c] = tb.get("data", {})

	# Восстановление building_instances
	GameManager.building_instances.clear()
	if data.has("building_instances"):
		for bi in data["building_instances"]:
			var c_arr = bi.get("coord", [0, 0])
			var c = Vector2i(c_arr[0], c_arr[1])
			var b_data = bi.get("data", {})
			var inst = GameManager.BuildingInstanceScript.new(b_data.get("id", ""), b_data.get("type", ""), b_data.get("settlement_id", ""), c)
			inst.deserialize(b_data)
			GameManager.building_instances[c] = inst
	
	if data.has("culture_memory") and GameManager.culture_memory:
		GameManager.culture_memory.deserialize(data["culture_memory"])
		
	if data.has("civilization_event_manager") and GameManager.civilization_event_manager:
		GameManager.civilization_event_manager.deserialize(data["civilization_event_manager"])
		
	if data.has("wildlife") and GameManager.wildlife_manager:
		GameManager.wildlife_manager.deserialize(data["wildlife"])
		
	if data.has("task_service") and GameManager.task_service:
		GameManager.task_service.deserialize(data["task_service"])
		
	if data.has("settlements_data"):
		GameManager.settlements.clear()
		var s_data_dict = data["settlements_data"]
		for s_id in s_data_dict:
			var s_dict = s_data_dict[s_id]
			var new_s = SettlementData.new(s_id, s_dict.get("name", "Поселение"), s_dict.get("faction_id", "player_tribe"), Vector2i(s_dict.get("pos_x", 0), s_dict.get("pos_y", 0)))
			new_s.deserialize(s_dict)
			GameManager.settlements[s_id] = new_s

	# --- ФАЗА 2: ВАЛИДАЦИЯ ССЫЛОК И СИНХРОНИЗАЦИЯ (Two-Phase Resolution) ---
	for s_id in GameManager.settlements:
		var s: SettlementData = GameManager.settlements[s_id]
		# Проверяем привязки домов и рабочих мест жителей к реальным экземплярам зданий
		if s.population:
			for c in s.population.citizens:
				if c.home_id == "" or c.home_id == "elders_house":
					# Привязываем к стабильному instance_id хижины старейшины
					var starter_inst = GameManager.get_or_create_building_instance(s.pos, "elders_house", s.id)
					c.home_id = starter_inst.instance_id
					c.home_coord = s.pos
					c.home_pos = Vector2(s.pos.x * 32.0 + 16.0, s.pos.y * 32.0 + 16.0)
			s.sync_assigned_jobs_from_citizens()

	GameManager.is_game_active = true
	EventBus.game_speed_changed.emit(GameManager.game_speed, GameManager.is_paused)
	return true

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
