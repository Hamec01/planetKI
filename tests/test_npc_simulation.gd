extends SceneTree

const PopulationSim = preload("res://src/simulation/population_sim.gd")
const CitizenNPC = preload("res://src/simulation/citizen_npc.gd")
const NPCNavigation = preload("res://src/simulation/npc_navigation.gd")
const SettlementData = preload("res://src/simulation/settlement.gd")
const WorldGenerator = preload("res://src/world/world_generator.gd")

const GameManagerScript = preload("res://src/core/game_manager.gd")
const EventBusScript = preload("res://src/core/event_bus.gd")
const SaveSystemScript = preload("res://src/core/save_system.gd")

func _init() -> void:
	print("========================================")
	print("TEST: RUNNING NPC SIMULATION TESTS (STAGE A)")
	print("========================================")
	
	# Синглтоны
	var event_bus = EventBusScript.new()
	event_bus.name = "EventBus"
	root.add_child(event_bus)
	
	var game_manager = GameManagerScript.new()
	game_manager.name = "GameManager"
	root.add_child(game_manager)
	
	var save_system = SaveSystemScript.new()
	save_system.name = "SaveSystem"
	root.add_child(save_system)
	
	# 1. Тест PopulationSim и CitizenNPC (1 гражданин = 1 NPC)
	var pop = PopulationSim.new()
	assert(pop.get_total_population() == 10, "Expected 10 starter citizens")
	assert(pop.citizens.size() == 10, "citizens array size must match total population")
	
	var cit1 = pop.get_citizen_by_id("cit_1")
	assert(cit1 != null, "Missing cit_1")
	assert(cit1.name == "Старейшина Мирослав", "cit_1 name mismatch")
	assert(cit1.cohort == "elder", "cit_1 cohort must be elder")
	assert(cit1.job_id == "idle", "cit_1 starter job must be idle")
	
	# Проверка стабильной идентичности при смене профессии
	cit1.set_job("woodcutter")
	assert(cit1.job_id == "woodcutter", "Job change failed")
	assert(cit1.name == "Старейшина Мирослав", "Job change must not alter citizen name")
	assert(cit1.gender == "m", "Job change must not alter citizen gender")
	
	# Проверка сериализации/десериализации
	var serialized = cit1.serialize()
	assert(serialized["citizen_id"] == "cit_1", "Serialization ID mismatch")
	var dummy = CitizenNPC.new()
	dummy.deserialize(serialized)
	assert(dummy.name == cit1.name and dummy.age == cit1.age and dummy.job_id == "woodcutter", "Deserialization mismatch")
	print("OK 1. CitizenNPC & PopulationSim: 1:1 Identity and Serialization passed.")
	
	# 2. Тест добавления новорожденного и удаления умершего
	var newborn = pop.add_newborn("player_settlement", Vector2(100, 100))
	assert(pop.get_total_population() == 11, "Population must be 11 after birth")
	assert(newborn.cohort == "child", "Newborn cohort must be child")
	assert(pop.children == 1, "Demographic children count must be 1")
	
	var removed = pop.remove_citizen(newborn.citizen_id)
	assert(removed != null, "Failed to remove citizen")
	assert(pop.get_total_population() == 10, "Population must be 10 after removal")
	assert(pop.children == 0, "Demographic children count must be 0")
	print("OK 2. Dynamic Birth & Death 1:1 Cohort Synchronization passed.")
	
	# 3. Тест навигации AStarGrid2D (NPCNavigation)
	var world = WorldGenerator.generate_world("PLN-TEST-STAGE-A")
	game_manager.planet_data = world
	var nav = NPCNavigation.new()
	nav.initialize_grid(world["tiles"], world["width"], world["height"])
	game_manager.nav_grid = nav
	
	var player_spawn = world["spawns"]["player"]["pos"]
	var spawn_center = nav.tile_to_world_center(player_spawn)
	var nearby_walkable = nav.find_random_walkable_nearby(player_spawn, 3)
	var nearby_center = nav.tile_to_world_center(nearby_walkable)
	
	var nav_path = nav.find_path(spawn_center, nearby_center)
	assert(not nav_path.is_empty(), "Path between neighboring land tiles must not be empty")
	print("OK 3. AStarGrid2D Navigation initialized, found path of %d points." % nav_path.size())
	
	# 4. Тест SettlementData с живой симуляцией жителей
	var s = SettlementData.new("test_s", "Стоянка Первого Костра", "player_tribe", player_spawn)
	s.init_starter_buildings_on_map()
	s.init_citizens_on_map()
	assert(s.population.citizens.size() == 10, "Settlement must have 10 citizens initialized")
	
	# Проверка привязки назначенных профессий к гражданам
	var woodcutter_count = 0
	for c in s.population.citizens:
		if c.job_id == "woodcutter":
			woodcutter_count += 1
	assert(woodcutter_count == 2, "Expected exactly 2 woodcutters assigned")
	
	# Проверка переназначения профессии
	var assigned = s.assign_worker("forager", 1)
	assert(assigned, "Failed to assign forager worker")
	var forager_count = 0
	for c in s.population.citizens:
		if c.job_id == "forager":
			forager_count += 1
	assert(forager_count == 3, "Expected 3 foragers after assignment")
	print("OK 4. Settlement Worker Assignment directly modifies CitizenNPC instances.")
	
	# 5. Тест шага симуляции (update_citizens)
	game_manager.current_hour = 12.0 # День
	s.update_citizens(0.5)
	
	# Проверка, что жители получают действия и двигаются
	var has_action = false
	for c in s.population.citizens:
		if c.last_status_reason != "":
			has_action = true
			break
	assert(has_action, "Citizens must have status reasons")
	
	# Проверка ночного сна
	game_manager.current_hour = 23.5 # Глубокая ночь
	s.update_citizens(1.0)
	var night_actions = 0
	for c in s.population.citizens:
		if c.state in [CitizenNPC.State.GOING_HOME, CitizenNPC.State.SLEEPING]:
			night_actions += 1
	assert(night_actions > 0, "At least some citizens must head home or sleep at night")
	print("OK 5. Daytime Work and Nighttime Sleep cycles verified successfully.")
	
	print("========================================")
	print("ALL STAGE A NPC TESTS PASSED SUCCESSFULLY!")
	print("========================================")
	quit(0)
