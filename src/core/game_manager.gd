extends Node

const SEASONS: Array[String] = ["Весна", "Лето", "Осень", "Зима"]
const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12

# Текущее время симуляции
var current_day: int = 1
var current_month: int = 1 # 1 - 12
var current_year: int = 1
var current_season: String = "Весна"

# Скорость времени
var is_paused: bool = false
var game_speed: float = 1.0 # 1.0, 2.0, 4.0, 8.0
var base_tick_interval: float = 0.8 # секунд реального времени на 1 игровой день при 1x
var tick_accumulator: float = 0.0

# Глобальное состояние игры
var world_seed: String = "PLN-7A4F-9231-B"
var current_epoch: int = 1 # 1: Племя, 2: Укрепленный город, 3: Королевство, 4: Индустриализация, 5: Космос
var epoch_name: String = "Эпоха 1 — Племя"

const BuildingInstanceScript = preload("res://src/simulation/building_instance.gd")
const CultureMemoryScript = preload("res://src/simulation/culture_memory.gd")
const CivilizationEventManagerScript = preload("res://src/events/civilization_event_manager.gd")

var player_faction_id: String = "player_tribe"
var player_race: String = "north" # "desert", "savanna", "north"
var faction_races: Dictionary = {} # faction_id -> race_id
var factions: Dictionary = {} # id -> FactionData
var settlements: Dictionary = {} # id -> SettlementData
var tile_buildings: Dictionary = {} # Vector2i -> Dictionary {"id": "hut", "status": "active"|"constructing", "settlement_id": String, "days_left": float, "total_days": int}
var building_instances: Dictionary = {} # Vector2i -> RefCounted
var planet_data: Dictionary = {}
var custom_map_to_play: Dictionary = {}
var star_system_data: Dictionary = {}
var history_log: Array[Dictionary] = []

var culture_memory: RefCounted = null
var civilization_event_manager: RefCounted = null
var total_simulation_days: int = 1

var is_game_active: bool = false

func get_or_create_building_instance(coord: Vector2i, b_id: String, s_id: String) -> RefCounted:
	if building_instances.has(coord):
		return building_instances[coord]
	var inst = BuildingInstanceScript.new(b_id + "_" + str(coord.x) + "_" + str(coord.y), b_id, s_id, coord)
	building_instances[coord] = inst
	return inst

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	culture_memory = CultureMemoryScript.new()
	civilization_event_manager = CivilizationEventManagerScript.new()

func _process(delta: float) -> void:
	if not is_game_active or is_paused:
		return
	
	tick_accumulator += delta * game_speed
	var step: float = base_tick_interval
	while tick_accumulator >= step:
		tick_accumulator -= step
		_advance_day()

func start_new_game(p_seed: String = "") -> void:
	if p_seed.strip_edges() != "":
		world_seed = p_seed.strip_edges()
	else:
		world_seed = _generate_random_seed()
		
	current_day = 1
	current_month = 1
	current_year = 1
	current_epoch = 1
	epoch_name = "Эпоха 1 — Племя"
	current_season = _get_season_for_month(current_month)
	is_paused = false
	game_speed = 1.0
	tick_accumulator = 0.0
	total_simulation_days = 1
	factions.clear()
	settlements.clear()
	history_log.clear()
	building_instances.clear()
	tile_buildings.clear()
	
	culture_memory = CultureMemoryScript.new()
	civilization_event_manager = CivilizationEventManagerScript.new()
	EventManager.reset()
	
	# Добавляем стартовую запись в историю
	add_history_entry(current_year, "Рождение племени", "Малая община людей зажгла первый костёр и основала стоянку в неизведанных землях.", "Начало")
	
	is_game_active = true
	EventBus.game_speed_changed.emit(game_speed, is_paused)

func _advance_day() -> void:
	current_day += 1
	total_simulation_days += 1
	if current_day > DAYS_PER_MONTH:
		current_day = 1
		current_month += 1
		var old_season = current_season
		current_season = _get_season_for_month(current_month)
		if old_season != current_season:
			EventBus.season_changed.emit(current_season)
			
		if current_month > MONTHS_PER_YEAR:
			current_month = 1
			current_year += 1
			EventBus.year_passed.emit(current_year)
			
		EventBus.month_passed.emit(current_month, current_year)
		
	# Проверка фундаментальных событий цивилизации
	var s = settlements.get("player_tribe_settlement", null)
	if civilization_event_manager and is_instance_valid(civilization_event_manager):
		civilization_event_manager.process_daily_triggers(current_day, total_simulation_days, s)
		
	EventBus.day_passed.emit(current_day, current_month, current_year)

func toggle_pause() -> void:
	is_paused = !is_paused
	EventBus.game_speed_changed.emit(game_speed, is_paused)

func set_paused(paused: bool) -> void:
	is_paused = paused
	EventBus.game_speed_changed.emit(game_speed, is_paused)

func set_speed(speed: float) -> void:
	game_speed = speed
	is_paused = false
	EventBus.game_speed_changed.emit(game_speed, is_paused)

func _get_season_for_month(month: int) -> String:
	match month:
		1, 2, 12:
			return "Зима"
		3, 4, 5:
			return "Весна"
		6, 7, 8:
			return "Лето"
		9, 10, 11:
			return "Осень"
		_:
			return "Весна"

func get_season() -> String:
	return current_season

func get_formatted_date() -> String:
	return "День %d · Месяц %d · Год %d" % [current_day, current_month, current_year]

func add_history_entry(year: int, title: String, description: String, category: String = "Общее") -> void:
	var entry = {
		"year": year,
		"day": current_day,
		"month": current_month,
		"title": title,
		"description": description,
		"category": category
	}
	history_log.append(entry)
	EventBus.history_entry_added.emit(year, title, description, category)

func _generate_random_seed() -> String:
	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var res = "PLN-"
	for i in range(4):
		res += chars[randi() % chars.length()]
	res += "-"
	for i in range(4):
		res += chars[randi() % chars.length()]
	return res
