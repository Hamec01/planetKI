extends Node

const SAVE_PATH: String = "user://planetki_save.json"

func save_game() -> bool:
	var culture_data = GameManager.culture_memory.serialize() if GameManager.culture_memory else {}
	var ev_mgr_data = {
		"triggered_events": GameManager.civilization_event_manager.triggered_events if GameManager.civilization_event_manager else [],
		"chain_cooldowns": GameManager.civilization_event_manager.chain_cooldowns if GameManager.civilization_event_manager else {}
	}
	
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
				"is_player": f.is_player
			}

	var save_dict = {
		"version": "0.3.0",
		"world_seed": GameManager.world_seed,
		"current_day": GameManager.current_day,
		"current_month": GameManager.current_month,
		"current_year": GameManager.current_year,
		"total_simulation_days": GameManager.total_simulation_days,
		"current_epoch": GameManager.current_epoch,
		"epoch_name": GameManager.epoch_name,
		"current_hour": GameManager.current_hour,
		"current_time_period": GameManager.current_time_period,
		"player_faction_id": GameManager.player_faction_id,
		"history_log": GameManager.history_log,
		"factions_data": factions_data,
		"settlements_data": s_serialized,
		"wildlife": GameManager.wildlife_manager.serialize() if GameManager.wildlife_manager else {},
		"star_system_data": GameManager.star_system_data,
		"planet_data": GameManager.planet_data,
		"culture_memory": culture_data,
		"civilization_event_manager": ev_mgr_data
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("Не удалось открыть файл для сохранения: " + SAVE_PATH)
		return false
		
	var json_string = JSON.stringify(save_dict, "\t")
	file.store_string(json_string)
	file.close()
	print("Игра успешно сохранена в " + SAVE_PATH)
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("Файл сохранения не найден: " + SAVE_PATH)
		return false
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("Не удалось открыть файл для загрузки: " + SAVE_PATH)
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
		
	GameManager.world_seed = data.get("world_seed", "PLN-7A4F-9231-B")
	GameManager.current_day = data.get("current_day", 1)
	GameManager.current_month = data.get("current_month", 1)
	GameManager.current_year = data.get("current_year", 1)
	GameManager.total_simulation_days = data.get("total_simulation_days", 1)
	GameManager.current_epoch = data.get("current_epoch", 1)
	GameManager.epoch_name = data.get("epoch_name", "Эпоха 1 — Племя")
	GameManager.current_hour = float(data.get("current_hour", 8.0))
	GameManager.current_time_period = data.get("current_time_period", "Утро")
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
				GameManager.factions[f_id] = new_f
				
	GameManager.star_system_data = data.get("star_system_data", {})
	GameManager.planet_data = data.get("planet_data", {})
	GameManager.current_season = GameManager._get_season_for_month(GameManager.current_month)
	
	# Инициализируем карту и сетку навигации ПЕРЕД восстановлением сущностей
	EventBus.world_generated.emit(GameManager.planet_data)
	
	if data.has("culture_memory") and GameManager.culture_memory:
		GameManager.culture_memory.deserialize(data["culture_memory"])
		
	if data.has("civilization_event_manager") and GameManager.civilization_event_manager:
		var ev_data = data["civilization_event_manager"]
		GameManager.civilization_event_manager.triggered_events.assign(ev_data.get("triggered_events", []))
		GameManager.civilization_event_manager.chain_cooldowns = ev_data.get("chain_cooldowns", {})
		
	if data.has("wildlife") and GameManager.wildlife_manager:
		GameManager.wildlife_manager.deserialize(data["wildlife"])
		
	if data.has("settlements_data"):
		GameManager.settlements.clear()
		var s_data_dict = data["settlements_data"]
		for s_id in s_data_dict:
			var s_dict = s_data_dict[s_id]
			var new_s = SettlementData.new(s_id, s_dict.get("name", "Поселение"), s_dict.get("faction_id", "player_tribe"), Vector2i(s_dict.get("pos_x", 0), s_dict.get("pos_y", 0)))
			new_s.deserialize(s_dict)
			GameManager.settlements[s_id] = new_s

	GameManager.is_game_active = true
	return true

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
