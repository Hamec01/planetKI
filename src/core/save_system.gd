extends Node

const SAVE_PATH: String = "user://planetki_save.json"

func save_game() -> bool:
	var culture_data = GameManager.culture_memory.serialize() if GameManager.culture_memory else {}
	var ev_mgr_data = {
		"triggered_events": GameManager.civilization_event_manager.triggered_events if GameManager.civilization_event_manager else [],
		"chain_cooldowns": GameManager.civilization_event_manager.chain_cooldowns if GameManager.civilization_event_manager else {}
	}
	
	var save_dict = {
		"version": "0.2.0",
		"world_seed": GameManager.world_seed,
		"current_day": GameManager.current_day,
		"current_month": GameManager.current_month,
		"current_year": GameManager.current_year,
		"total_simulation_days": GameManager.total_simulation_days,
		"current_epoch": GameManager.current_epoch,
		"epoch_name": GameManager.epoch_name,
		"player_faction_id": GameManager.player_faction_id,
		"history_log": GameManager.history_log,
		"factions": GameManager.factions,
		"settlements": GameManager.settlements,
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
	GameManager.player_faction_id = data.get("player_faction_id", "player_tribe")
	GameManager.history_log = data.get("history_log", [])
	GameManager.factions = data.get("factions", {})
	GameManager.settlements = data.get("settlements", {})
	GameManager.star_system_data = data.get("star_system_data", {})
	GameManager.planet_data = data.get("planet_data", {})
	GameManager.current_season = GameManager._get_season_for_month(GameManager.current_month)
	
	if data.has("culture_memory") and GameManager.culture_memory:
		GameManager.culture_memory.deserialize(data["culture_memory"])
		
	if data.has("civilization_event_manager") and GameManager.civilization_event_manager:
		var ev_data = data["civilization_event_manager"]
		GameManager.civilization_event_manager.triggered_events = Array(ev_data.get("triggered_events", []))
		GameManager.civilization_event_manager.chain_cooldowns = ev_data.get("chain_cooldowns", {})
		
	GameManager.is_game_active = true
	
	EventBus.world_generated.emit(GameManager.planet_data)
	return true

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
