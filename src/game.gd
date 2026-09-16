class_name Game
extends Node2D

@onready var map_view: WorldMapView = $MapView
@onready var map_camera: MapCamera = $MapCamera
@onready var main_hud: MainHUD = $MainHUD
@onready var settlement_panel: SettlementPanel = $UI/SettlementPanel
@onready var faction_view: FactionView = $UI/FactionView
@onready var events_dialog: EventsDialog = $UI/EventsDialog
@onready var battle_modal: BattleModal = $UI/BattleModal

func _ready() -> void:
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.month_passed.connect(_on_month_passed)
	EventBus.year_passed.connect(_on_year_passed)
	EventBus.battle_started.connect(_on_battle_started)
	
	main_hud.tab_opened.connect(_on_tab_opened)
	
	if not GameManager.is_game_active:
		start_game(GameManager.world_seed)

func start_game(seed_str: String) -> void:
	GameManager.start_new_game(seed_str)
	
	# 1. Генерация звездной системы
	var star_system = StarSystemGenerator.generate_system(GameManager.world_seed)
	GameManager.star_system_data = star_system
	
	# 2. Генерация карты мира
	var world_data = WorldGenerator.generate_world(GameManager.world_seed)
	GameManager.planet_data = world_data
	
	# 3. Создание фракции и поселения игрока
	var p_spawn = world_data["spawns"]["player"]
	var player_f = FactionData.new(p_spawn["id"], p_spawn["name"], p_spawn["leader_name"], p_spawn["color"], true)
	player_f.culture = p_spawn["culture"]
	player_f.religion_id = "ancestor_spirits"
	GameManager.factions[player_f.id] = player_f
	GameManager.player_faction_id = player_f.id
	
	var player_settlement = SettlementData.new(
		p_spawn["id"] + "_settlement",
		"Стоянка Первого Костра",
		player_f.id,
		p_spawn["pos"]
	)
	GameManager.settlements[player_settlement.id] = player_settlement
	player_settlement.init_starter_buildings_on_map()
	
	# Изначально у игрока 10 мирных жителей, 0 генералов и 0 армий
	player_f.generals.clear()
	player_f.armies.clear()
	
	# 4. Создание ИИ-фракций и поселений
	for ai_spawn in world_data["spawns"]["ai"]:
		var ai_f = FactionData.new(ai_spawn["id"], ai_spawn["name"], ai_spawn["leader_name"], ai_spawn["color"], false)
		ai_f.culture = ai_spawn["culture"]
		ai_f.religion_id = "world_spirits"
		ai_f.personality = ai_spawn["personality"]
		ai_f.generals.clear()
		ai_f.armies.clear()
		GameManager.factions[ai_f.id] = ai_f
		
		var ai_s = SettlementData.new(
			ai_spawn["id"] + "_settlement",
			"Стоянка " + ai_spawn["name"],
			ai_f.id,
			ai_spawn["pos"]
		)
		GameManager.settlements[ai_s.id] = ai_s
		ai_s.init_starter_buildings_on_map()
		
	# 5. Оповещаем карту и центрируем камеру на стартовой стоянке игрока
	EventBus.world_generated.emit(world_data)
	map_camera.focus_on_tile(player_settlement.pos, WorldMapView.TILE_SIZE)
	
	_setup_army_command_panel()

const ArmyCommandPanelScript = preload("res://src/ui/army_command_panel.gd")
var army_command_panel: Control = null

func _setup_army_command_panel() -> void:
	if army_command_panel == null:
		army_command_panel = ArmyCommandPanelScript.new()
		army_command_panel.name = "ArmyCommandPanel"
		$UI.add_child(army_command_panel)

func _on_day_passed(_day: int, _month: int, _year: int) -> void:
	var season = GameManager.current_season
	
	# Обновление поселения игрока
	var player_s = GameManager.settlements.get("player_tribe_settlement", null)
	if player_s:
		player_s.sim_daily_tick(season)
		var player_f = GameManager.factions.get(GameManager.player_faction_id, null)
		if player_f:
			var sages = player_s.assigned_jobs.get("sage", 0)
			player_f.sim_daily_research(0.2 + sages * 0.8)
			
	# Обновление ИИ-фракций
	for f_id in GameManager.factions:
		if f_id != GameManager.player_faction_id:
			var ai_f = GameManager.factions[f_id]
			var ai_s = GameManager.settlements.get(f_id + "_settlement", null)
			AIController.process_ai_daily(ai_f, ai_s, season)
			
	# Проверка триггеров событий
	EventManager.check_triggers()

func _on_month_passed(_month: int, _year: int) -> void:
	var season = GameManager.current_season
	for s_id in GameManager.settlements:
		var s = GameManager.settlements[s_id]
		s.sim_monthly_tick(season)

func _on_year_passed(_year: int) -> void:
	for s_id in GameManager.settlements:
		var s = GameManager.settlements[s_id]
		s.population.sim_yearly_aging()

func _on_battle_started(_battle_data: Dictionary) -> void:
	# Бои теперь идут прямо в реальном времени на карте (RTS), без модального окна!
	pass

func _on_tab_opened(tab_name: String, extra_data: Variant = null) -> void:
	if tab_name == "settlement":
		settlement_panel.open_for_player(0)
	elif tab_name == "settlement_buildings" or tab_name == "buildings":
		var build_coord = extra_data if (extra_data is Vector2i) else Vector2i(-1, -1)
		settlement_panel.open_for_player(1, build_coord)
	elif tab_name == "army":
		var player_f = GameManager.factions.get(GameManager.player_faction_id, null)
		if player_f and not player_f.armies.is_empty():
			EventBus.army_selected.emit(player_f.armies[0])
			map_camera.focus_on_tile(player_f.armies[0].pos, WorldMapView.TILE_SIZE)
		else:
			faction_view.open_tab("army")
	elif tab_name == "menu":
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
	else:
		faction_view.open_tab(tab_name)


