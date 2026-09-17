extends Node

const SEASONS: Array[String] = ["Весна", "Лето", "Осень", "Зима"]
const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12

# Временные масштабы симуляции (PlanetKI Living Settlement TZ v2)
const DAY_CYCLE_DURATION: float = 900.0   # 15 реальных минут на 1 сутки при 1x
const NPC_YEAR_DURATION: float = 1800.0    # 30 реальных минут на 1 биографический год при 1x (2 суток = 1 год)

# Текущее время симуляции
var current_day: int = 1
var current_month: int = 1 # 1 - 12 (для совместимости)
var current_year: int = 1
var current_season: String = "Весна"

# Суточное время симуляции
var current_hour: float = 6.0 # 0.0 .. 24.0 (06:00 утра старт)
var current_time_period: String = "Утро" # "Утро", "День", "Вечер", "Ночь"

# Скорость времени и централизованная пауза
var is_paused: bool = false
var user_paused: bool = false
var modal_pause_count: int = 0
var game_speed: float = 1.0 # 1.0, 2.0, 4.0, 8.0
var base_tick_interval: float = 900.0 # 900 секунд реального времени на 1 игровой день при 1x
var tick_accumulator: float = 225.0 # Смещение на 06:00 (225 / 900 = 0.25 дня)
var sim_time_total: float = 0.0 # Общее симуляционное время в секундах

# Глобальное состояние игры
var world_seed: String = "PLN-7A4F-9231-B"
var current_epoch: int = 1 # 1: Племя, 2: Укрепленный город, 3: Королевство, 4: Индустриализация, 5: Космос
var epoch_name: String = "Эпоха 1 — Племя"

const BuildingInstanceScript = preload("res://src/simulation/building_instance.gd")
const CultureMemoryScript = preload("res://src/simulation/culture_memory.gd")
const CivilizationEventManagerScript = preload("res://src/events/civilization_event_manager.gd")
const NPCNavigationScript = preload("res://src/simulation/npc_navigation.gd")
const MapResourceManagerScript = preload("res://src/simulation/map_resource_manager.gd")
const WildlifeManagerScript = preload("res://src/simulation/wildlife_manager.gd")
const TaskServiceScript = preload("res://src/simulation/task_service.gd")

var nav_grid = NPCNavigationScript.new()
var resource_manager = MapResourceManagerScript.new()
var wildlife_manager = WildlifeManagerScript.new()
var task_service = TaskServiceScript.new()

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
var is_game_over: bool = false
var game_over_reason: String = ""

func trigger_game_over(reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over_reason = reason
	is_paused = true
	add_history_entry(current_year, "Падение вождя (Конец игры)", reason, "Кризис")
	EventBus.game_over.emit(reason)
	EventBus.notification_toast.emit("ПАРТИЯ ОКОНЧЕНА", reason, "danger")

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
	EventBus.world_generated.connect(_on_world_generated_init_nav)

func _on_world_generated_init_nav(data: Dictionary) -> void:
	if data.has("tiles"):
		var w = data.get("width", 160)
		var h = data.get("height", 160)
		nav_grid.initialize_grid(data["tiles"], w, h)
		resource_manager.initialize_from_tiles(data["tiles"], w, h)
		wildlife_manager.init_wildlife(data, nav_grid)

func get_time_period_for_hour(hour_val: float) -> String:
	if hour_val >= 6.0 and hour_val < 9.0:
		return "Утро"
	elif hour_val >= 9.0 and hour_val < 18.0:
		return "День"
	elif hour_val >= 18.0 and hour_val < 22.0:
		return "Вечер"
	else:
		return "Ночь"

func get_formatted_time() -> String:
	var h = int(floor(current_hour))
	var m = int(floor((current_hour - h) * 60.0))
	return "%02d:%02d · %s" % [h, m, current_time_period]

func _process(delta: float) -> void:
	if not is_game_active or is_paused or is_game_over:
		return
	
	var sim_delta: float = delta * game_speed
	sim_time_total += sim_delta
	
	# 1. Восстановление природных ресурсов карты
	resource_manager.update_regrowth(sim_delta)
	
	# 2. Авторитетная симуляция жителей и поселений (независимо от камеры/WorldMapView)
	var threat_positions: Array = []
	for s_id in settlements:
		var s: SettlementData = settlements[s_id]
		s.update_citizens(sim_delta)
		if s.population:
			for c in s.population.citizens:
				if c.health > 0:
					threat_positions.append({"pos": c.pos, "citizen": c})
				if not c.is_ruler:
					c.sim_aging(sim_delta)
					
	# 3. Авторитетная симуляция фауны
	if wildlife_manager:
		wildlife_manager.update(sim_delta, nav_grid, threat_positions)
		
	# 4. Перемещение и обновление таймеров армий
	_process_armies_simulation(sim_delta)
	
	# 5. Продвижение времени суток и календарного дня
	tick_accumulator += sim_delta
	var step: float = base_tick_interval
	
	current_hour = (tick_accumulator / step) * 24.0
	var new_period = get_time_period_for_hour(current_hour)
	if new_period != current_time_period:
		current_time_period = new_period
		EventBus.time_period_changed.emit(current_time_period)
		
	while tick_accumulator >= step:
		tick_accumulator -= step
		current_hour = (tick_accumulator / step) * 24.0
		_advance_day()

func _process_armies_simulation(sim_delta: float) -> void:
	for f_id in factions:
		var f: FactionData = factions[f_id]
		for a in f.armies:
			if a.speech_timer > 0.0:
				a.speech_timer -= sim_delta
				if a.speech_timer <= 0.0:
					a.speech_bubble = ""
					
			if a.is_moving:
				var dest = Vector2(a.target_pos.x * 32.0 + 16.0, a.target_pos.y * 32.0 + 16.0)
				var to_dest = dest - a.world_pos
				var dist = to_dest.length()
				if dist <= a.move_speed * sim_delta or dist < 2.0:
					a.world_pos = dest
					a.pos = a.target_pos
					a.is_moving = false
				else:
					a.world_pos += to_dest.normalized() * a.move_speed * sim_delta
					a.pos = Vector2i(int(floor(a.world_pos.x / 32.0)), int(floor(a.world_pos.y / 32.0)))

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
	current_season = "Весна"
	user_paused = false
	modal_pause_count = 0
	is_paused = false
	is_game_over = false
	game_over_reason = ""
	game_speed = 1.0
	base_tick_interval = DAY_CYCLE_DURATION
	tick_accumulator = 225.0 # 06:00 утра старт
	sim_time_total = 0.0
	total_simulation_days = 1
	factions.clear()
	settlements.clear()
	history_log.clear()
	building_instances.clear()
	tile_buildings.clear()
	if task_service:
		task_service.tasks.clear()
	
	culture_memory = CultureMemoryScript.new()
	if civilization_event_manager:
		civilization_event_manager.reset()
	else:
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

func push_modal_pause() -> void:
	modal_pause_count += 1
	_apply_pause_state()

func pop_modal_pause() -> void:
	modal_pause_count = maxi(0, modal_pause_count - 1)
	_apply_pause_state()

func toggle_pause() -> void:
	user_paused = !user_paused
	_apply_pause_state()

func set_paused(paused: bool) -> void:
	user_paused = paused
	_apply_pause_state()

func set_speed(speed: float) -> void:
	game_speed = speed
	if modal_pause_count == 0:
		user_paused = false
	_apply_pause_state()

func _apply_pause_state() -> void:
	var prev_paused = is_paused
	is_paused = (modal_pause_count > 0) or user_paused
	if is_paused != prev_paused:
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
	return "Сутки %d · %s" % [total_simulation_days, get_formatted_time()]

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
