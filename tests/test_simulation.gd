extends SceneTree

const StarSystemGenerator = preload("res://src/world/star_system.gd")
const BiomeDefinitions = preload("res://src/world/biome_definitions.gd")
const WorldGenerator = preload("res://src/world/world_generator.gd")
const BuildingDB = preload("res://src/simulation/building_db.gd")
const PopulationSim = preload("res://src/simulation/population_sim.gd")
const EconomySim = preload("res://src/simulation/economy_sim.gd")
const SettlementData = preload("res://src/simulation/settlement.gd")
const LawSystem = preload("res://src/simulation/law_system.gd")
const ReligionSystem = preload("res://src/simulation/religion_system.gd")
const TechTree = preload("res://src/simulation/tech_tree.gd")
const ArmyData = preload("res://src/simulation/army_system.gd")
const GeneralGenerator = preload("res://src/combat/general_generator.gd")
const BattleInstance = preload("res://src/combat/battle_instance.gd")
const FactionData = preload("res://src/simulation/faction.gd")
const EventDB = preload("res://src/events/event_db.gd")
const EventManager = preload("res://src/events/event_manager.gd")
const AIController = preload("res://src/ai/ai_controller.gd")

const GameManagerScript = preload("res://src/core/game_manager.gd")
const EventBusScript = preload("res://src/core/event_bus.gd")
const SaveSystemScript = preload("res://src/core/save_system.gd")

func _init() -> void:
	print("========================================")
	print("TEST: STARTING SIMULATION TESTS FOR PLANETKI")
	print("========================================")
	
	# Инициализируем синглтоны для изолированного теста
	var event_bus = EventBusScript.new()
	event_bus.name = "EventBus"
	root.add_child(event_bus)
	
	var game_manager = GameManagerScript.new()
	game_manager.name = "GameManager"
	root.add_child(game_manager)
	
	var save_system = SaveSystemScript.new()
	save_system.name = "SaveSystem"
	root.add_child(save_system)
	
	# 1. Тест звёздной системы
	var test_seed = "PLN-7A4F-9231-B"
	var system = StarSystemGenerator.generate_system(test_seed)
	assert(system.has("star_name"), "Star name missing")
	assert(system["planets"].size() >= 4, "Planets count < 4")
	print("OK 1. Star System Generated: [%s], Planet [%s], Moons: %s" % [
		system["star_name"], system["home_planet_name"], ", ".join(system["moons"])
	])
	
	# 2. Тест генератора мира
	var world = WorldGenerator.generate_world(test_seed)
	assert(world["tiles"].size() == WorldGenerator.MAP_HEIGHT, "Invalid map height")
	assert(world["tiles"][0].size() == WorldGenerator.MAP_WIDTH, "Invalid map width")
	assert(world["spawns"].has("player"), "Missing player spawn")
	assert(world["spawns"]["ai"].size() == 4, "Expected 4 AI tribes")
	print("OK 2. Planet Map (%dx%d) generated. Player spawn: %s" % [
		world["width"], world["height"], world["spawns"]["player"]["pos"]
	])
	
	# 3. Тест симуляции времени и GameManager
	game_manager.start_new_game(test_seed)
	game_manager.star_system_data = system
	game_manager.planet_data = world
	
	var p_spawn = world["spawns"]["player"]
	var player_f = FactionData.new(p_spawn["id"], p_spawn["name"], p_spawn["leader_name"], p_spawn["color"], true)
	game_manager.factions[player_f.id] = player_f
	game_manager.player_faction_id = player_f.id
	
	var player_s = SettlementData.new(p_spawn["id"] + "_settlement", "Стоянка Первого Костра", player_f.id, p_spawn["pos"])
	game_manager.settlements[player_s.id] = player_s
	
	print("OK 3. Initialized game state. Settlement: %s, Pop: %d" % [
		player_s.name, player_s.population.get_total_population()
	])
	
	# 4. Тест экономики и строительства
	assert(player_s.economy.get_resource("food") > 0, "No food")
	var initial_wood = player_s.economy.get_resource("wood")
	var can_build = player_s.start_construction("granary")
	assert(can_build, "Failed to start granary construction")
	assert(player_s.economy.get_resource("wood") < initial_wood, "Wood cost not deducted")
	print("OK 4. Granary construction started. Resources deducted.")
	
	# 5. Тест симуляции 60 дней (2 игровых месяца)
	for day in range(60):
		player_s.sim_daily_tick("Лето")
		player_f.sim_daily_research(1.0)
	player_s.sim_monthly_tick("Лето")
	player_s.population.sim_yearly_aging()
	
	assert(player_f.unlocked_techs.has("trapping_hunting"), "Tech should be researched")
	print("OK 5. Simulation of 60 days complete. Pop: %d, Unlocked techs: %s" % [
		player_s.population.get_total_population(), ", ".join(player_f.unlocked_techs)
	])
	
	# 6. Тест генералов и битвы
	var brock = GeneralGenerator.create_brock()
	var gwen = GeneralGenerator.create_gwen()
	assert(brock["bravery"] == 95, "Brock bravery check failed")
	assert(gwen["cunning"] == 95, "Gwen cunning check failed")
	
	var att_army = ArmyData.new()
	att_army.name = "Дружина Брока"
	att_army.general = brock
	att_army.spearmen = 20
	att_army.archers = 15
	
	var def_army = ArmyData.new()
	def_army.name = "Ополчение Врага"
	def_army.general = gwen
	def_army.spearmen = 15
	def_army.archers = 10
	
	var battle = BattleInstance.new("test_battle", Vector2i(10, 10), att_army, def_army, "Холмистая гряда")
	var battle_res = {}
	for r in range(5):
		battle_res = battle.advance_round()
		if battle_res.get("finished", false):
			break
	print("OK 6. Battle simulation finished. Rounds: %d, Chronicle lines: %d" % [
		battle.current_round, battle.chronicle.size()
	])
	
	# 7. Тест сохранения и загрузки
	var save_ok = save_system.save_game()
	assert(save_ok, "Save failed")
	var load_ok = save_system.load_game()
	assert(load_ok, "Load failed")
	print("OK 7. JSON Save and Load validated successfully.")
	
	print("========================================")
	print("SUCCESS: ALL SIMULATION TESTS PASSED!")
	print("========================================")
	quit(0)
