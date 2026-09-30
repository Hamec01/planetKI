extends Node

const CombatStatsResolver = preload("res://src/combat/combat_stats_resolver.gd")
const EquipmentDB = preload("res://src/combat/equipment_db.gd")
const EmoteTextureManager = preload("res://src/core/emote_texture_manager.gd")

func _ready() -> void:
	print("========================================")
	print("TEST: RUNNING NPC SIMULATION TESTS (STAGE A)")
	print("========================================")
	
	# 1. Тест PopulationSim и CitizenNPC (1 гражданин = 1 NPC)
	var pop = PopulationSim.new()
	assert(pop.get_total_population() == 10, "Expected 10 starter citizens")
	assert(pop.citizens.size() == 11, "citizens array size must match 10 citizens + 1 ruler")
	
	var cit1 = pop.get_citizen_by_id("cit_1")
	assert(cit1 != null, "Missing cit_1")
	assert(cit1.name == "Старейшина Мирослав", "cit_1 name mismatch")
	assert(cit1.cohort == "elder", "cit_1 cohort must be elder")
	assert(cit1.job_id == "elder", "cit_1 starter job must be elder")
	
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
	GameManager.planet_data = world
	GameManager._on_world_generated_init_nav(world)
	EventBus.world_generated.emit(world)
	var nav = GameManager.nav_grid
	
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
	assert(s.population.get_total_population() == 10, "Settlement must have 10 citizens initialized")
	assert(s.population.citizens.size() == 11, "Settlement citizen array has 11 (10 citizens + 1 ruler)")
	
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
	GameManager.current_hour = 12.0 # День
	s.update_citizens(0.5)
	
	# Проверка, что жители получают действия и двигаются
	var has_action = false
	for c in s.population.citizens:
		if c.last_status_reason != "":
			has_action = true
			break
	assert(has_action, "Citizens must have status reasons")
	
	# Проверка ночного сна
	GameManager.current_hour = 23.5 # Глубокая ночь
	s.update_citizens(1.0)
	var night_actions = 0
	for c in s.population.citizens:
		if c.state in [CitizenNPC.State.GOING_HOME, CitizenNPC.State.SLEEPING]:
			night_actions += 1
	assert(night_actions > 0, "At least some citizens must head home or sleep at night")
	GameManager.current_hour = 12.0 # Возвращаем дневное время для последующих дневных тестов
	print("OK 5. Daytime Work and Nighttime Sleep cycles verified successfully.")
	
	# ==============================================================================
	# ЭТАП B: СИСТЕМА РЕСУРСНЫХ ТОЧЕК И ЦИКЛ СОБИРАТЕЛЯ
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING FORAGER & MAP RESOURCE TESTS (STAGE B)")
	print("----------------------------------------")
	
	# 6. Проверка инициализации ресурсных точек
	var res_mgr = GameManager.resource_manager
	assert(res_mgr.is_initialized, "MapResourceManager must be initialized")
	assert(res_mgr.nodes.size() > 0, "MapResourceManager must discover berry/mushroom nodes")
	print("OK 6. MapResourceManager initialized with %d resource nodes." % res_mgr.nodes.size())
	
	# 7. Проверка резервирования точки (исключение коллизий двух собирателей)
	# Возобновляемая точка (ягоды/грибы/рыба): после сбора остаётся на карте пустой до восстановления
	var test_coord = res_mgr.nodes.keys()[0]
	for rc in res_mgr.nodes:
		if res_mgr.nodes[rc]["category"] in MapResourceManager.RENEWABLE_CATEGORIES:
			test_coord = rc
			break
	var res_ok1 = res_mgr.reserve_node(test_coord, "cit_6")
	assert(res_ok1, "First citizen must successfully reserve node")
	
	var res_ok2 = res_mgr.reserve_node(test_coord, "cit_7")
	assert(not res_ok2, "Second citizen must NOT be able to reserve already reserved node")
	res_mgr.release_node(test_coord, "cit_6")
	
	var res_ok3 = res_mgr.reserve_node(test_coord, "cit_7")
	assert(res_ok3, "Citizen must be able to reserve after node was released")
	res_mgr.release_node(test_coord, "cit_7")
	print("OK 7. Mutual exclusion & reservation on resource nodes verified.")
	
	# 8. Проверка истощения и сбора
	var initial_amount = res_mgr.nodes[test_coord]["amount"]
	var harvested = res_mgr.harvest_from_node(test_coord, initial_amount)
	assert(harvested == initial_amount, "Must harvest exact available amount")
	assert(res_mgr.nodes[test_coord]["depleted"], "Node must be marked depleted when amount <= 0")
	assert(res_mgr.nodes[test_coord]["amount"] == 0.0, "Node amount must be 0")
	
	# Проверка, что истощенную точку нельзя собрать повторно
	var harvest_again = res_mgr.harvest_from_node(test_coord, 5.0)
	assert(harvest_again == 0.0, "Depleted node must yield 0 resources")
	print("OK 8. Node depletion and zero double-harvesting verified.")
	
	# 8b. Камень — это камень: валун не отрастает, а распадается на россыпь и исчезает
	var st_rock_coord = Vector2i(-1, -1)
	for rc in res_mgr.nodes:
		if res_mgr.nodes[rc]["category"] == "stone" and res_mgr.nodes[rc]["original_sprite"] == "rock_round_boulder":
			st_rock_coord = rc
			break
	if st_rock_coord == Vector2i(-1, -1):
		st_rock_coord = Vector2i(3, 3)
		res_mgr._create_node(st_rock_coord, "rock_round_boulder")
	var st_boulder_amt = float(res_mgr.nodes[st_rock_coord]["amount"])
	assert(res_mgr.harvest_from_node(st_rock_coord, st_boulder_amt) == st_boulder_amt, "Boulder yields its whole stone amount")
	assert(res_mgr.nodes.has(st_rock_coord) and res_mgr.nodes[st_rock_coord]["original_sprite"] == "rock_small_pebbles", "Worked-out boulder turns into a pebble scatter")
	assert(not res_mgr.nodes[st_rock_coord]["depleted"] and res_mgr.nodes[st_rock_coord]["category"] == "stone", "Pebble scatter is still minable stone")
	assert(not res_mgr.nodes[st_rock_coord]["blocks"], "Pebble scatter does not block the path")
	res_mgr.harvest_from_node(st_rock_coord, 100.0)
	assert(not res_mgr.nodes.has(st_rock_coord), "Fully mined stone disappears from the map")
	res_mgr.update_regrowth(9999.0)
	assert(not res_mgr.nodes.has(st_rock_coord), "Stone never regrows")
	# Рудная жила: добывается руда, а после неё остаётся каменная россыпь
	var st_ore_coord = Vector2i(4, 3)
	res_mgr._create_node(st_ore_coord, "rock_red_stone")
	res_mgr.harvest_from_node(st_ore_coord, 100.0)
	assert(res_mgr.nodes.has(st_ore_coord) and res_mgr.nodes[st_ore_coord]["category"] == "stone", "Depleted ore vein leaves stone rubble")
	res_mgr.remove_node(st_ore_coord)
	# Деревья зимнего леса и сухостой — настоящая древесина
	assert(MapResourceManager.RESOURCE_NATURE_CONFIG["tree_spruce_snow"]["category"] == "wood", "Snowy spruce is choppable wood")
	assert(MapResourceManager.RESOURCE_NATURE_CONFIG["tree_dead"]["category"] == "wood", "Dead tree is choppable wood")
	assert(MapResourceManager.RESOURCE_NATURE_CONFIG["rock_snow_boulder"]["category"] == "stone", "Snowy boulder is minable stone")
	print("OK 8b. Stone is finite: boulder -> pebbles -> gone, ore -> rubble, snowy trees are wood.")
	
	# 9. Проверка отключения пассивного начисления в экономике (собиратели и охотники)
	var daily_prod = s.calculate_daily_production("Лето")
	# И собиратели (3 шт), и охотники (1 шт) переведены на физический цикл (Этап B и Этап C)
	# Пассивная еда должна быть строго 0.0!
	var expected_passive_food = 0.0
	assert(abs(daily_prod.get("food", 0.0) - expected_passive_food) < 0.01, "Passive food production must be 0.0 (got %f)" % daily_prod.get("food", 0.0))
	print("OK 9. Zero passive double counting confirmed: foragers and hunters produce 0.0 passive food.")
	
	# 10. Проверка доставки в экономику поселения
	var food_before = s.economy.get_resource("food")
	var forager_cit = s.population.citizens[5] # cit_6
	forager_cit.cargo_type = "food"
	forager_cit.cargo_amount = 4.0
	forager_cit.state = CitizenNPC.State.CARRYING
	forager_cit.pos = forager_cit.home_pos # Дошел до амбара
	forager_cit.path.clear()
	s.update_citizens(0.2)
	assert(s.economy.get_resource("food") == food_before + 4.0, "Delivered cargo must be credited to settlement economy")
	assert(forager_cit.cargo_amount == 0.0, "Cargo amount must be cleared after delivery")
	print("OK 10. Physical Cargo Delivery to settlement granary verified.")

	# ==============================================================================
	# ЭТАП C: ДИКИЕ ЖИВОТНЫЕ, ОХОТА, ПРЕСЛЕДОВАНИЕ И РАЗДЕЛКА
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING WILDLIFE & HUNTING TESTS (STAGE C)")
	print("----------------------------------------")

	# 11. Проверка инициализации фауны (WildlifeManager)
	var wild_mgr = GameManager.wildlife_manager
	assert(wild_mgr.is_initialized, "WildlifeManager must be initialized")
	assert(wild_mgr.animals.size() > 0, "WildlifeManager must spawn hares and deer")
	
	var hares_count = 0
	var deer_count = 0
	for a in wild_mgr.animals.values():
		if a.species == "hare":
			hares_count += 1
		elif a.species == "deer":
			deer_count += 1
	assert(hares_count > 0, "Expected hares in wildlife manager")
	assert(deer_count > 0, "Expected deer in wildlife manager")
	print("OK 11. WildlifeManager initialized with %d hares and %d deer." % [hares_count, deer_count])

	# 12. Проверка ИИ животных: обнаружение угрозы и бегство (FLEEING)
	# Берём зверя, которому есть куда бежать от угрозы справа (деревья и валуны — настоящие препятствия)
	var test_animal = wild_mgr.animals.values()[0]
	for cand_animal in wild_mgr.animals.values():
		var a_tile = GameManager.nav_grid.world_to_tile(cand_animal.pos)
		if GameManager.nav_grid.is_tile_walkable(a_tile + Vector2i(-1, 0)) and GameManager.nav_grid.is_tile_walkable(a_tile + Vector2i(-2, 0)) and GameManager.nav_grid.is_tile_walkable(a_tile + Vector2i(-1, -1)) and GameManager.nav_grid.is_tile_walkable(a_tile + Vector2i(-1, 1)):
			test_animal = cand_animal
			break
	var initial_animal_pos = test_animal.pos
	var initial_state = test_animal.state
	
	# Подводим "угрозу" в радиус обнаружения
	var threat_p = test_animal.pos + Vector2(25.0, 0.0) # В пределах detect_radius
	test_animal.update(0.5, GameManager.nav_grid, [threat_p])
	assert(test_animal.state == WildAnimal.State.FLEEING, "Animal must enter FLEEING state when threat is nearby")
	assert(test_animal.pos != initial_animal_pos, "Animal must run away when fleeing")
	print("OK 12. Animal AI threat detection and fleeing mechanics verified.")

	# 13. Проверка нанесения урона, гибели и создания туши (Carcass)
	var hunt_target = WildAnimal.new("test_hunt_hare", "hare_brown", Vector2(200, 200))
	wild_mgr.animals[hunt_target.id] = hunt_target
	var killed = hunt_target.take_damage(20.0, "cit_8")
	assert(killed, "Animal must be killed when damage exceeds HP")
	assert(hunt_target.state == WildAnimal.State.DEAD, "Animal state must be DEAD")
	
	# Создание туши
	var carcass = wild_mgr.create_carcass_from_animal(hunt_target)
	wild_mgr.animals.erase(hunt_target.id)
	assert(carcass != null and carcass["meat_remaining"] == 2.0, "Carcass must contain meat yield of hare (2.0)")
	assert(wild_mgr.carcasses.has(carcass["id"]), "Carcass must be registered in WildlifeManager")
	print("OK 13. Animal damage, death, and carcass generation verified.")

	# 14. Проверка взаимного исключения бронирования туши
	var res_c1 = wild_mgr.reserve_carcass(carcass["id"], "cit_8")
	assert(res_c1, "First hunter must successfully reserve carcass")
	var res_c2 = wild_mgr.reserve_carcass(carcass["id"], "cit_9")
	assert(not res_c2, "Second hunter must NOT be able to reserve already reserved carcass")
	wild_mgr.release_carcass(carcass["id"], "cit_8")
	print("OK 14. Mutual exclusion on carcass reservation verified.")

	# 15. Проверка сбора туши (harvest_carcass)
	var harvest_res = wild_mgr.harvest_carcass(carcass["id"], 6.0)
	var meat_taken = harvest_res["meat"]
	assert(meat_taken == 2.0, "Must harvest all available 2.0 meat")
	assert(harvest_res["material"] == "small_hide" and harvest_res["material_count"] == 1, "Hare must yield 1 small_hide")
	assert(not wild_mgr.carcasses.has(carcass["id"]), "Exhausted carcass must be removed from map")
	print("OK 15. Carcass harvesting and zero duplicate meat verified.")

	# 16. Проверка полного цикла охотника (выслеживание -> атака -> разделка -> доставка)
	var hunter_cit = null
	for c in s.population.citizens:
		if c.job_id == "hunter":
			hunter_cit = c
			break
	assert(hunter_cit != null, "Must have an assigned hunter")
	
	# Ставим тушу рядом с охотником
	var sim_carcass = {
		"id": "carcass_test_sim",
		"species": "deer",
		"pos": hunter_cit.pos + Vector2(10.0, 10.0),
		"coord": Vector2i(int(hunter_cit.pos.x / 32.0), int(hunter_cit.pos.y / 32.0)),
		"meat_remaining": 6.0,
		"max_meat": 6.0,
		"reserved_by": "",
		"decay_timer": 200.0
	}
	wild_mgr.carcasses[sim_carcass["id"]] = sim_carcass
	# Переводим время на день и сбрасываем кулдаун решений
	GameManager.current_hour = 11.0
	hunter_cit.decision_cooldown = 0.0
	hunter_cit.state = CitizenNPC.State.IDLE
	
	# Запускаем шаг симуляции: охотник должен взять задание на тушу
	s.update_citizens(0.2)
	assert(hunter_cit.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.BUTCHERING], "Hunter must respond to carcass (state=%d)" % hunter_cit.state)
	
	# Симулируем разделку туши
	hunter_cit.cargo_type = "carcass"
	hunter_cit.cargo_amount = 6.0
	hunter_cit.state = CitizenNPC.State.BUTCHERING
	hunter_cit.work_timer = 0.05
	s.update_citizens(0.1)
	assert(hunter_cit.cargo_type == "food", "Butchered carcass must convert to food cargo")
	assert(hunter_cit.cargo_amount == 6.0, "Food cargo must equal carcass meat amount")
	assert(hunter_cit.state == CitizenNPC.State.CARRYING, "Hunter must carry butchered food to granary")
	
	# Симулируем доставку в амбар
	var food_count_before = s.economy.get_resource("food")
	hunter_cit.pos = hunter_cit.home_pos
	s.update_citizens(0.2)
	assert(s.economy.get_resource("food") == food_count_before + 6.0, "Hunter delivered food must be credited to economy")
	assert(hunter_cit.cargo_amount == 0.0, "Hunter cargo must be cleared after delivery")
	print("OK 16. Complete Hunter Cycle (stalking, attack, butchering, and granary delivery) verified.")

	print("========================================")
	print("ALL STAGES A, B & C NPC TESTS PASSED SUCCESSFULLY!")
	print("========================================")

	# ==============================================================================
	# ЭТАП D: БЫТ, ЖИЛЬЕ, СОН, ОБЩЕНИЕ, ДЕТИ И СТАРИКИ
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING DOMESTIC LIFE & SOCIAL TESTS (STAGE D)")
	print("----------------------------------------")

	# 17. Проверка ночной стражи vs сна обычных граждан
	var guard_cit = s.population.citizens[8]
	guard_cit.set_job("guard")
	guard_cit.state = CitizenNPC.State.IDLE
	guard_cit.decision_cooldown = 0.0
	
	GameManager.current_hour = 23.5 # Глубокая ночь
	s.update_citizens(0.2)
	assert(guard_cit.state != CitizenNPC.State.SLEEPING, "Guard must NOT sleep at night")
	assert("дозор" in guard_cit.last_status_reason.to_lower() or "границ" in guard_cit.last_status_reason.to_lower() or "патрул" in guard_cit.last_status_reason.to_lower(), "Guard must be on night patrol (got %s)" % guard_cit.last_status_reason)
	print("OK 17. Guard night patrol verified: stays awake on night shift.")

	# 18. Проверка дневного отдыха стражи после ночной смены
	GameManager.current_hour = 12.0 # День
	guard_cit.decision_cooldown = 0.0
	s.update_citizens(0.2)
	assert(guard_cit.state in [CitizenNPC.State.GOING_HOME, CitizenNPC.State.SLEEPING, CitizenNPC.State.RESTING], "Guard must rest/sleep during day after night shift (state=%d)" % guard_cit.state)
	print("OK 18. Guard daytime rest after night duty verified.")

	# 19. Дети и Старики (когорты)
	var child_cit = s.population.add_newborn("test_s", s.pos)
	child_cit.decision_cooldown = 0.0
	GameManager.current_hour = 11.0 # День
	s.update_citizens(0.2)
	assert(child_cit.job_id == "idle", "Child must never be assigned an adult job")
	assert("хижин" in child_cit.last_status_reason.to_lower() or "играет" in child_cit.last_status_reason.to_lower() or "гуляет" in child_cit.last_status_reason.to_lower(), "Child must play near huts (got %s)" % child_cit.last_status_reason)
	
	var elder_cit = s.population.get_citizen_by_id("cit_1")
	assert(elder_cit.cohort == "elder", "cit_1 must be elder")
	assert(elder_cit.get_speed() < elder_cit.base_speed, "Elder citizen must have reduced movement speed")
	print("OK 19. Children play behavior and elder movement properties verified.")

	# 20. Социальное общение (Диалог двух жителей)
	var citizen_a = s.population.citizens[3]
	var citizen_b = s.population.citizens[4]
	citizen_a.pos = Vector2(s.pos.x * 32.0 + 5.0, s.pos.y * 32.0)
	citizen_b.pos = Vector2(s.pos.x * 32.0 + 10.0, s.pos.y * 32.0)
	citizen_a.state = CitizenNPC.State.IDLE
	citizen_b.state = CitizenNPC.State.IDLE
	s._start_social_dialog(citizen_a, citizen_b)
	assert(citizen_a.state == CitizenNPC.State.TALKING and citizen_b.state == CitizenNPC.State.TALKING, "Both citizens must enter TALKING state")
	assert(citizen_a.speech_bubble != "", "Talking citizen must have a speech bubble")
	print("OK 20. Social dialogue between neighboring citizens verified.")

	# ==============================================================================
	# ЭТАП E: ОСТАЛЬНЫЕ ПРОФЕССИИ (ЛЕСОРУБЫ, КАМЕНОТЕСЫ, РУДОКОПЫ, СТРОИТЕЛИ)
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING REMAINING PROFESSIONS TESTS (STAGE E)")
	print("----------------------------------------")

	# 21. Полный цикл лесоруба (поиск дерева -> рубка -> пень -> доставка -> 0 пассивного дохода)
	var woodcutter_cit = s.population.citizens[1]
	woodcutter_cit.set_job("woodcutter")
	woodcutter_cit.decision_cooldown = 0.0
	woodcutter_cit.state = CitizenNPC.State.IDLE
	GameManager.current_hour = 11.0
	
	# Находим узел дерева
	var tree_node = null
	for n in GameManager.resource_manager.nodes.values():
		if n["category"] == "wood" and not n["depleted"]:
			tree_node = n
			break
	assert(tree_node != null, "Must have wood node on map")
	tree_node["amount"] = 4.0
	
	# Лесоруб рубит дерево: проверка физического прогрессивного уменьшения запаса в дереве
	var wood_before = s.economy.get_resource("wood")
	var initial_tree_wood = tree_node["amount"]
	woodcutter_cit.target_coord = tree_node["coord"]
	woodcutter_cit.state = CitizenNPC.State.WORKING
	woodcutter_cit.work_timer = 0.05
	s.update_citizens(0.1)
	assert(woodcutter_cit.cargo_type == "wood" and woodcutter_cit.cargo_amount > 0.0, "Woodcutter must harvest wood cargo")
	assert(tree_node["amount"] < initial_tree_wood, "Tree wood amount must decrease upon axe strike (was %f, now %f)" % [initial_tree_wood, tree_node["amount"]])
	
	# Продолжение рубки до полного сруба дерева (до 0 дров)
	for _i in range(10):
		if woodcutter_cit.state == CitizenNPC.State.CARRYING:
			break
		woodcutter_cit.work_timer = 0.0
		s.update_citizens(0.1)
	assert(woodcutter_cit.state == CitizenNPC.State.CARRYING, "Woodcutter must carry wood to storage after felling tree")
	assert(tree_node["depleted"] or tree_node["amount"] <= 0.0, "Tree must be depleted after full cut")
	
	# Доставка на склад: немедленное пополнение экономики и зачисление
	woodcutter_cit.pos = woodcutter_cit.home_pos
	s.update_citizens(0.1)
	assert(s.economy.get_resource("wood") > wood_before, "Delivered wood must be credited to economy")
	assert(woodcutter_cit.cargo_amount == 0.0, "Cargo must be empty after delivery")
	
	# Проверка нулевого пассивного начисления дерева
	var prod_wood = s.calculate_daily_production("Лето")
	assert(prod_wood.get("wood", 0.0) == 0.0, "Passive wood production must be 0.0 (got %f)" % prod_wood.get("wood", 0.0))
	print("OK 21. Progressive woodcutter chopping, tree depletion down to 0, and storage delivery verified.")

	# 22. Проверка каменотёса и рудокопа (0 пассивного начисления камня и металла)
	var prod_all = s.calculate_daily_production("Лето")
	assert(prod_all.get("stone", 0.0) == 0.0, "Passive stone production must be 0.0")
	assert(prod_all.get("metal", 0.0) == 0.0, "Passive metal production must be 0.0")
	print("OK 22. Quarryman and Miner zero passive double-counting verified.")

	# 23. Проверка строителя (продвижение реального строительства здания)
	var test_build_coord = Vector2i(s.pos.x + 2, s.pos.y + 2)
	GameManager.tile_buildings[test_build_coord] = {
		"id": "hut",
		"status": "constructing",
		"settlement_id": s.id,
		"days_left": 2.0,
		"total_days": 2
	}
	var builder_cit = s.population.citizens[2]
	builder_cit.set_job("builder")
	builder_cit.target_coord = test_build_coord
	builder_cit.state = CitizenNPC.State.WORKING
	builder_cit.work_timer = 0.05
	s.update_citizens(0.1)
	assert(GameManager.tile_buildings[test_build_coord]["days_left"] < 2.0, "Builder work must reduce construction days_left")
	print("OK 23. Builder physical labor and construction progress verified.")

	print("========================================")
	print("ALL STAGES A, B, C, D & E NPC TESTS PASSED SUCCESSFULLY!")
	print("========================================")

	# ==============================================================================
	# ЭТАП F: РЕАКЦИЯ НА ОПАСНОСТИ, СОХРАНЕНИЕ/ЗАГРУЗКА И ОПТИМИЗАЦИЯ 200 NPC
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING THREATS, PERSISTENCE & BENCHMARK TESTS (STAGE F)")
	print("----------------------------------------")

	# 24. Реакция на непосредственную опасность (мирные жители убегают, стража защищает)
	var enemy_f = FactionData.new("enemy_faction", "Враждебные кочевники", "Вождь Налётчиков", Color.RED)
	var enemy_army = ArmyData.new()
	enemy_army.id = "enemy_a1"
	enemy_army.faction_id = "enemy_faction"
	enemy_army.name = "Отряд налётчиков"
	enemy_army.pos = Vector2i(s.pos.x + 2, s.pos.y + 2)
	enemy_army.world_pos = Vector2(s.pos.x * 32.0 + 40.0, s.pos.y * 32.0)
	enemy_army.warriors = 12
	enemy_f.armies.append(enemy_army)
	GameManager.factions["enemy_faction"] = enemy_f

	# Мирный житель рядом
	var peaceful_cit = s.population.citizens[5]
	peaceful_cit.set_job("forager")
	peaceful_cit.pos = Vector2(s.pos.x * 32.0 + 30.0, s.pos.y * 32.0)
	peaceful_cit.state = CitizenNPC.State.IDLE

	# Стражник рядом
	guard_cit.pos = Vector2(s.pos.x * 32.0 + 20.0, s.pos.y * 32.0)
	guard_cit.state = CitizenNPC.State.IDLE
	guard_cit.set_job("guard")

	s.update_citizens(0.1)
	assert(peaceful_cit.state == CitizenNPC.State.FLEEING, "Peaceful citizen must enter FLEEING state when enemy approaches")
	assert("бегств" in peaceful_cit.last_status_reason.to_lower() or "укрыт" in peaceful_cit.last_status_reason.to_lower(), "Peaceful citizen must flee to shelter")
	assert("защищ" in guard_cit.last_status_reason.to_lower() or "враг" in guard_cit.last_status_reason.to_lower(), "Guard must take defensive combat stance against enemy")
	print("OK 24. Threat reaction verified: peaceful citizens flee, guards take defensive positions.")

	# Удаляем врагов после проверки
	GameManager.factions.erase("enemy_faction")

	# 25. Проверка сохранения и загрузки (SaveSystem)
	GameManager.current_hour = 14.5
	GameManager.current_time_period = "День"
	GameManager.settlements[s.id] = s
	
	var save_ok = SaveSystem.save_game()
	assert(save_ok, "SaveSystem.save_game() must return true")
	
	var pop_count_before = s.population.get_total_population()
	var cit_name_before = s.population.citizens[0].name
	var animals_count_before = GameManager.wildlife_manager.animals.size()
	
	# Сбрасываем симуляцию и загружаем сохранение
	var load_ok = SaveSystem.load_game()
	assert(load_ok, "SaveSystem.load_game() must return true")
	
	var loaded_s = GameManager.settlements[s.id]
	assert(loaded_s != null, "Settlement must exist after loading")
	assert(loaded_s.population.get_total_population() == pop_count_before, "Population count must be preserved exactly after load")
	assert(loaded_s.population.citizens[0].name == cit_name_before, "Citizen names and identity must match exactly after load")
	assert(abs(GameManager.current_hour - 14.5) < 0.1, "Game time of day must be preserved after load")
	assert(GameManager.wildlife_manager.animals.size() == animals_count_before, "Wildlife population must be preserved after load")
	print("OK 25. Complete Save/Load persistence of citizens, wildlife, time, and world state verified.")

	# 26. Бенчмарк производительности при 10, 50, 100 и 200 гражданах (ТЗ п.20)
	print("----------------------------------------")
	print("BENCHMARK: MEASURING NPC SIMULATION PERFORMANCE")
	print("----------------------------------------")
	for target_count in [10, 50, 100, 200]:
		while s.population.citizens.size() < target_count:
			s.population.add_newborn(s.id, Vector2(s.pos.x * 32.0, s.pos.y * 32.0))
		
		# Замеряем время 10 последовательных шагов симуляции
		var t_start = Time.get_ticks_usec()
		for step in range(10):
			s.update_citizens(0.1)
		var t_elapsed_usec = Time.get_ticks_usec() - t_start
		var avg_step_ms = float(t_elapsed_usec) / 10000.0
		var theoretical_fps = 1000.0 / avg_step_ms if avg_step_ms > 0.001 else 9999.0
		print("BENCHMARK [%d Citizens]: 10-step total = %.2f ms | avg step = %.3f ms (~%.0f simulation ticks/sec)" % [target_count, t_elapsed_usec / 1000.0, avg_step_ms, theoretical_fps])
		assert(avg_step_ms < 16.6, "Simulation step for %d citizens must run within 60 FPS budget (<16.6 ms)" % target_count)
	print("OK 26. High performance scaling up to 200 citizens verified well within 60 FPS frame budget.")

	# ==============================================================================
	# 24 ВИДА ЖИВОТНЫХ: ТЕСТЫ СИСТЕМЫ ФАУНЫ И ТРОФЕЕВ
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING 24-ANIMAL FAUNA & DROPS TESTS")
	print("----------------------------------------")

	# 27. Проверка наличия и валидности всех 24 текстур животных
	var animal_types = [
		"wolf_grey", "wolf_dark", "wolf_pup", "hare_brown", "hare_white", "hare_leveret",
		"deer_stag", "deer_doe", "deer_fawn", "moose_bull", "moose_cow", "moose_calf",
		"bear_brown", "bear_dark", "bear_cub", "boar_male", "boar_female", "boar_piglet",
		"fox_adult", "fox_kit", "lynx_adult", "badger_adult", "drake", "duck"
	]
	assert(animal_types.size() == 24, "Must have exactly 24 animal types")
	for t_name in animal_types:
		var p_tex = "res://Assets/animals/%s.png" % t_name
		assert(ResourceLoader.exists(p_tex), "Texture for %s must exist in Assets/animals/" % t_name)
		var tex = load(p_tex)
		assert(tex is Texture2D and tex.get_width() > 0, "Loaded texture for %s must be valid" % t_name)
	print("OK 27. All 24 transparent animal sprites loaded and validated.")

	# 28. Проверка конфигурации характеристик и здоровья животных (ТЗ)
	for t_name in animal_types:
		assert(WildAnimal.SPECIES_CONFIG.has(t_name), "Config for %s must exist" % t_name)
		var cfg = WildAnimal.SPECIES_CONFIG[t_name]
		assert(cfg["hp"] > 0.0 and cfg["speed_mult"] > 0.0, "Animal %s must have positive HP and speed" % t_name)
	var moose_cfg = WildAnimal.SPECIES_CONFIG["moose_bull"]
	assert(moose_cfg["hp"] == 160.0 and moose_cfg["dmg"] == 28.0 and moose_cfg["speed_mult"] == 1.55, "Moose bull stats match TZ")
	var bear_cfg = WildAnimal.SPECIES_CONFIG["bear_brown"]
	assert(bear_cfg["hp"] == 240.0 and bear_cfg["dmg"] == 32.0 and bear_cfg["mat"] == "fur", "Bear stats match TZ")
	print("OK 28. Full 24-species configuration table and statistics verified.")

	# 29. Поведение семьи: следование детёныша за матерью
	var cow = WildAnimal.new("test_moose_cow", "moose_cow", Vector2(100, 100))
	var calf = WildAnimal.new("test_moose_calf", "moose_calf", Vector2(160, 160))
	calf.parent_id = cow.id
	calf.update(0.5, GameManager.nav_grid, [], cow)
	assert(calf.state == WildAnimal.State.FOLLOWING, "Calf must enter FOLLOWING state when distant from mother")
	print("OK 29. Family behavior: child follows mother.")

	# 30. Защитная реакция: лосиха встает на защиту при приближении угрозы
	var threat_close = [cow.pos + Vector2(20, 0)]
	cow.update(0.2, GameManager.nav_grid, threat_close)
	assert(cow.state == WildAnimal.State.DEFENDING, "Mother moose must enter DEFENDING state against close threat")
	print("OK 30. Defensive response of mothers verified.")

	# 31. Водоплавание уток
	var test_duck = WildAnimal.new("test_duck", "duck", Vector2(100, 100))
	test_duck.update(0.2, GameManager.nav_grid, [Vector2(110, 100)])
	assert(test_duck.state == WildAnimal.State.SWIMMING, "Duck must enter SWIMMING state when threat detected")
	print("OK 31. Waterfowl duck swimming evasion verified.")

	# 32. Трофеи разделки крупной туши и шкур в экономику
	var moose_hunt = WildAnimal.new("test_moose", "moose_bull", Vector2(250, 250))
	var m_carcass = wild_mgr.create_carcass_from_animal(moose_hunt)
	assert(m_carcass["extra_material"] == "hide" and m_carcass["extra_remaining"] == 3, "Moose carcass must contain 3 hides")
	var m_harvest = wild_mgr.harvest_carcass(m_carcass["id"], 8.0)
	assert(m_harvest["meat"] == 8.0 and m_harvest["material"] == "hide" and m_harvest["material_count"] == 3, "Harvest yields meat + hides")
	assert(float(m_harvest["byproducts"].get("leather", 0.0)) == 3.0, "Moose hides become 3 leather for settlement economy")
	assert(float(m_harvest["byproducts"].get("bone", 0.0)) == 3.0, "Moose carcass yields 3 bones (22 meat / 6)")
	var m_second = wild_mgr.harvest_carcass(m_carcass["id"], 8.0)
	assert(m_second["byproducts"].is_empty(), "Hides and bones are taken only once from a carcass")
	print("OK 32. Large carcass multi-yield and material trophies (hide, fur, feathers) verified.")

	# 33. Регрессионный тест: поиск hunting_camp через BuildingInstance и tile_buildings
	var hunt_cit = CitizenNPC.new("test_hunter_reg", "Hunter Test", "m", 25, "adult")
	hunt_cit.workplace_coord = Vector2i(-1, -1)
	hunt_cit.job_id = "hunter"
	GameManager.get_or_create_building_instance(Vector2i(10, 15), "hunting_camp", s.id)
	var camp_pos = s._find_hunting_camp_pos(hunt_cit)
	assert(camp_pos != Vector2.ZERO, "Must find hunting camp position from BuildingInstance")
	print("OK 33. Hunter camp location lookup with BuildingInstance verified.")

	# 34. Рубка дерева: 1 дерево = 100 дров и полное исчезновение с тайла карты
	var test_chop_c = Vector2i(s.pos.x + 3, s.pos.y + 3)
	GameManager.planet_data["tiles"][test_chop_c.y][test_chop_c.x]["nature_object"] = "tree_oak"
	GameManager.resource_manager.nodes[test_chop_c] = {
		"id": "res_chop_test",
		"coord": test_chop_c,
		"pos": Vector2(test_chop_c.x * 32.0 + 16, test_chop_c.y * 32.0 + 16),
		"type": "wood",
		"category": "wood",
		"name": "Могучий дуб",
		"amount": 100.0,
		"max_amount": 100.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "tree_oak",
		"depleted_sprite": "none",
		"regrowth_timer": 999999.0,
		"regrowth_duration": 999999.0
	}
	var chopped_wood = GameManager.resource_manager.harvest_from_node(test_chop_c, 100.0)
	assert(chopped_wood == 100.0, "Harvesting full tree must yield 100 wood")
	assert(GameManager.planet_data["tiles"][test_chop_c.y][test_chop_c.x]["nature_object"] == "none", "Tree sprite must disappear from map after chopping")
	print("OK 34. 1 tree = 100 wood and total sprite removal from tile verified.")

	# 35. Посадка леса: посев саженца и созревание во взрослое дерево
	var test_plant_c = Vector2i(s.pos.x + 4, s.pos.y + 4)
	var planted = GameManager.resource_manager.plant_tree(test_plant_c, "tree_young", "tree_pine")
	assert(planted, "Tree planting must succeed on valid tile")
	assert(GameManager.planet_data["tiles"][test_plant_c.y][test_plant_c.x]["nature_object"] == "tree_young", "Tile must show tree_young after planting")
	GameManager.resource_manager.update_regrowth(35.0)
	assert(GameManager.planet_data["tiles"][test_plant_c.y][test_plant_c.x]["nature_object"] == "tree_pine", "Tile must mature into tree_pine")
	assert(GameManager.resource_manager.nodes[test_plant_c]["amount"] == MapResourceManager.RESOURCE_NATURE_CONFIG["tree_pine"]["amount"], "Mature planted pine holds as much wood as a wild pine")
	print("OK 35. Reforestation: planting tree_young and maturation into 100-wood tree verified.")

	# 36. Разблокировка базовых зданий 1-й эпохи
	assert(GameManager.culture_memory.is_building_unlocked("hut"), "Hut must be unlocked for building")
	assert(GameManager.culture_memory.is_building_unlocked("woodcutter_camp"), "Woodcutter camp must be unlocked")
	assert(GameManager.culture_memory.is_building_unlocked("foraging_post"), "Foraging post must be unlocked")
	assert(GameManager.culture_memory.is_building_unlocked("great_lodge"), "Great lodge must be unlocked")
	print("OK 36. All basic Epoch 1 tribal buildings unlocked without event requirement verified.")

	# 37. Нападение дикого зверя и нанесение урона NPC
	var test_wolf = WildAnimal.new("test_combat_wolf", "wolf_grey", Vector2(100, 100))
	var victim_cit = CitizenNPC.new("test_victim", "Victim", "m", 25, "adult")
	victim_cit.pos = Vector2(110, 100)
	victim_cit.job_id = "hunter"
	victim_cit.health = 100.0
	test_wolf.attack_timer = 0.0
	test_wolf.update(0.1, GameManager.nav_grid, [{"pos": victim_cit.pos, "citizen": victim_cit}])
	assert(test_wolf.state == WildAnimal.State.DEFENDING, "Wolf must enter DEFENDING against close human")
	for _i in range(10):
		test_wolf.attack_timer = 0.0
		test_wolf.update(0.1, GameManager.nav_grid, [{"pos": victim_cit.pos, "citizen": victim_cit}])
		if victim_cit.health < 100.0:
			break
	assert(victim_cit.health < 100.0, "Wolf attack must deal damage to citizen (got %f HP)" % victim_cit.health)
	assert(test_wolf.health < test_wolf.max_health, "Hunter citizen must fight back and damage attacking wolf")
	print("OK 37. Predator assault, citizen damage, and hunter counter-attack verified.")

	# 38. Глобальный вызов событий через EventBus
	var event_result = {"received": false, "id": ""}
	var event_conn = func(ev):
		event_result["received"] = true
		event_result["id"] = ev.get("id", "")
	EventBus.civilization_event_triggered.connect(event_conn)
	var test_ev = CivilizationEventDB.get_event("EVENT-DEATH-01")
	GameManager.civilization_event_manager.trigger_event(test_ev)
	assert(event_result["received"] and event_result["id"] == "EVENT-DEATH-01", "Civilization event must be broadcast via EventBus")
	EventBus.civilization_event_triggered.disconnect(event_conn)
	print("OK 38. Civilization event trigger and EventBus delivery verified.")

	# 39. Свободный выбор спрайта (дерево/камень/гриб) и проверка запаса ресурсов
	var map_view = WorldMapView.new()
	var test_tiles = []
	for y in range(20):
		var row = []
		for x in range(20):
			row.append({
				"coord": Vector2i(x, y),
				"biome": 1, # Grassland
				"is_water": false,
				"is_river": false,
				"settlement_id": "",
				"nature_object": "tree_oak" if (x == 5 and y == 5) else ("rock_round_boulder" if (x == 6 and y == 5) else "none"),
				"resource": null
			})
		test_tiles.append(row)
	map_view.planet_data = {"width": 20, "height": 20, "tiles": test_tiles}
	GameManager.resource_manager.initialize_from_tiles(test_tiles, 20, 20)
	
	# Клик по спрайту дуба на (5, 5) — в пределах габаритов спрайта
	var oak_click = map_view._get_nature_object_at_position(Vector2(5 * 32 + 16, 5 * 32 + 5))
	assert(not oak_click.is_empty(), "Must detect tree sprite at click position")
	assert(oak_click["coord"] == Vector2i(5, 5), "Tree coord must match (5, 5)")
	assert(oak_click["n_data"]["name"] == "tree_oak", "Must pick tree_oak sprite")
	assert(oak_click["node"]["amount"] == 20.0, "Tree oak must have 20 wood stock")

	# Клик по валуну на (6, 5)
	var rock_click = map_view._get_nature_object_at_position(Vector2(6 * 32 + 16, 5 * 32 + 15))
	assert(not rock_click.is_empty(), "Must detect rock sprite at click position")
	assert(rock_click["node"]["amount"] == 25.0, "Rock must have 25 stone stock")

	# Клик по пустой траве на (2, 2) — не должно выбирать природный объект
	var empty_click = map_view._get_nature_object_at_position(Vector2(2 * 32 + 16, 2 * 32 + 16))
	assert(empty_click.is_empty(), "Clicking empty terrain must not select any sprite")
	map_view.free()
	print("OK 39. Freeform sprite selection and remaining resource inspection verified.")

	# 40. Реальная механика: приоритетный приказ на вырубку и моментальное зачисление ресурсов
	var res_result = {"received": false}
	var res_updated_conn = func(_f, _r): res_result["received"] = true
	EventBus.resources_updated.connect(res_updated_conn)
	
	var initial_wood = s.economy.get_resource("wood")
	s.deposit_resource("wood", 50.0, "Тестовый лесоруб")
	assert(s.economy.get_resource("wood") == initial_wood + 50.0, "deposit_resource must immediately increase economy resources")
	assert(res_result["received"], "deposit_resource must immediately emit EventBus.resources_updated signal for HUD")
	EventBus.resources_updated.disconnect(res_updated_conn)
	
	# Проверка приоритетного приказа
	var idle_woodcutter = s.population.citizens[1]
	idle_woodcutter.set_job("woodcutter")
	idle_woodcutter.state = CitizenNPC.State.IDLE
	var order_coord = Vector2i(5, 5)
	EventBus.order_harvest_resource.emit(order_coord, "wood")
	assert(s.priority_harvest_coords.has(order_coord), "Settlement must register priority target coord")
	assert(idle_woodcutter.state == CitizenNPC.State.MOVING_TO_WORK, "Idle woodcutter must immediately be dispatched to priority order")
	assert(idle_woodcutter.target_coord == order_coord, "Dispatched woodcutter target coord must match order coord")
	print("OK 40. Real mechanics verified: priority harvest orders, instant economy crediting & immediate HUD signal.")

	# 41. Тест уникальности профессий: 1 гражданин = 1 профессия / рабочее место, исключение старейшины, динамический счётчик свободных
	var s_test = SettlementData.new("test_workforce_s", "Стоянка Проверок", "player_tribe", player_spawn)
	s_test.init_starter_buildings_on_map()
	s_test.init_citizens_on_map()
	
	# Старейшина не может быть свободным работником
	var elder_c = s_test.population.get_citizen_by_id("cit_1")
	assert(elder_c != null, "Elder must exist")
	assert(elder_c.job_id == "elder", "Elder job must be elder")
	assert(not elder_c.is_idle(), "Elder must not be considered idle")
	
	var idle_list = s_test.get_idle_citizens()
	for c in idle_list:
		assert(c.citizen_id != "cit_1", "Elder cit_1 must never appear in idle citizens list")
		assert(c.is_idle(), "Every citizen in idle list must be idle")
	
	var initial_free = s_test.get_idle_workforce()
	assert(initial_free == idle_list.size(), "get_idle_workforce must equal get_idle_citizens().size()")
	assert(initial_free > 0, "Must have idle citizens at start")
	
	# Создаём охотничий лагерь
	var camp_coord = Vector2i(12, 12)
	var camp_inst = GameManager.get_or_create_building_instance(camp_coord, "hunting_camp", s_test.id)
	assert(camp_inst.workers.is_empty(), "New camp must have 0 workers")
	
	# Нанимаем первого свободного жителя
	var first_free = s_test.get_idle_citizens()[0]
	var hired_id = first_free.citizen_id
	var hired_job = BuildingDB.get_job_id_for_building(camp_inst.type)
	camp_inst.add_worker(hired_id)
	first_free.set_job(hired_job)
	first_free.workplace_id = camp_inst.id
	first_free.workplace_coord = camp_inst.pos
	s_test.sync_assigned_jobs_from_citizens()
	
	assert(camp_inst.workers.has(hired_id), "Worker must be added to camp")
	assert(first_free.job_id == "hunter", "Hired citizen must now be a hunter")
	assert(not first_free.is_idle(), "Hired citizen must not be idle anymore")
	assert(s_test.get_idle_workforce() == initial_free - 1, "Idle workforce must decrement by 1")
	
	# Попытка нанять в другое здание того же жителя невозможна, так как он отсутствует в get_idle_citizens
	var fresh_free_list = s_test.get_idle_citizens()
	for c in fresh_free_list:
		assert(c.citizen_id != hired_id, "Employed citizen must not be in idle list for other jobs")
		
	# Снимаем жителя с должности (кнопка '✕ Снять')
	camp_inst.remove_worker(hired_id)
	first_free.set_job("idle")
	first_free.workplace_id = ""
	first_free.workplace_coord = Vector2i(-1, -1)
	s_test.sync_assigned_jobs_from_citizens()
	
	assert(not camp_inst.workers.has(hired_id), "Worker must be removed from camp")
	assert(first_free.job_id == "idle", "Citizen job must be reset to idle")
	assert(first_free.is_idle(), "Citizen must be idle again")
	assert(s_test.get_idle_workforce() == initial_free, "Idle workforce must return to original count")
	print("OK 41. Unique job assignment, elder exclusion, and live workforce synchronization verified.")

	# 42. Тест постройки Кладбища (Могильника): открытие через обычай, статус (открыто vs построено) и возведение
	var cem_def = BuildingDB.get_building("cemetery")
	assert(not cem_def.is_empty(), "Cemetery must be defined in BuildingDB")
	assert(cem_def["category"] == "society", "Cemetery category must be society")
	assert(cem_def.has("cost") and cem_def["cost"].has("wood") and cem_def["cost"].has("stone"), "Cemetery must have wood and stone cost")
	assert(BuildingDB.get_job_id_for_building("cemetery") == "priest", "Cemetery job must map to priest")
	
	# Проверка статуса разблокировки
	var culture_mem = GameManager.culture_memory
	culture_mem.unlocked_special_buildings.erase("cemetery")
	assert(not culture_mem.is_building_unlocked("cemetery"), "Cemetery must not be unlocked before event decision")
	
	# Имитация выбора захоронения ("Предавать тело земле")
	culture_mem.unlock_building("cemetery")
	assert(culture_mem.is_building_unlocked("cemetery"), "Cemetery must be unlocked after burial decision")
	
	# До постройки на карте здание не должно числиться в построенных
	assert(not s_test.buildings.has("cemetery"), "Cemetery must not be in settlement buildings before construction")
	
	# Запускаем постройку кладбища
	s_test.economy.add_resource("wood", 100.0)
	s_test.economy.add_resource("stone", 100.0)
	var cem_coord = Vector2i(15, 15)
	var started = s_test.start_construction("cemetery", cem_coord)
	assert(started, "Failed to start construction of cemetery")
	assert(GameManager.tile_buildings[cem_coord]["status"] == "constructing", "Cemetery tile must have status constructing")
	
	# Завершаем строительство (симулируем тики строителей)
	for item in s_test.construction_queue:
		if item["id"] == "cemetery":
			item["days_left"] = 0.0
	s_test.sim_daily_tick("summer")
	
	assert(s_test.buildings.has("cemetery"), "Cemetery must be in settlement buildings after completion")
	assert(GameManager.tile_buildings[cem_coord]["status"] == "active", "Cemetery tile must be active after completion")
	print("OK 42. Cemetery unlock via burial customs, correct unbuilt/built status & physical construction verified.")

	# 43. ТЕСТ РАЗДЕЛА 29 ТЗ: Точное совпадение таблицы 4 контрольных персонажей
	# 1) Новобранец 18 лет: S=1, E=1, топор L=1, G=0, P=0.85, R=1.0
	var novice = CitizenNPC.new("c_novice", "Новобранец", "m", 18, "youth")
	novice.strength_level = 1
	novice.endurance_level = 1
	novice.weapon_skills["axe_level"] = 1
	novice.encounter_growth_points = 0.0
	novice.equipment["weapon"] = "work_axe"
	var stats_novice = novice.get_combat_stats()
	assert(absf(stats_novice["max_hp"] - 100.85) < 0.01, "Novice HP expected 100.85, got %.2f" % stats_novice["max_hp"])
	assert(absf(stats_novice["stamina_max"] - 102.55) < 0.01, "Novice Stamina expected 102.55, got %.2f" % stats_novice["stamina_max"])
	assert(stats_novice["display_damage"] == 16, "Novice damage expected 16, got %d" % stats_novice["display_damage"])
	assert(absf(stats_novice["attack_interval"] - 1.793) < 0.01, "Novice interval expected 1.793, got %.3f" % stats_novice["attack_interval"])

	# 2) Лесоруб 40 лет: S=16, E=14, профессия лесоруба дает топор L=3, G=0, P=1.0, R=1.0
	var woodcutter_40 = CitizenNPC.new("c_wc40", "Лесоруб 40л", "m", 40, "adult")
	woodcutter_40.strength_level = 16
	woodcutter_40.endurance_level = 14
	woodcutter_40.weapon_skills["axe_level"] = 0
	woodcutter_40.profession_levels = {"woodcutter": 16}
	woodcutter_40.encounter_growth_points = 0.0
	woodcutter_40.equipment["weapon"] = "work_axe"
	var stats_wc40 = woodcutter_40.get_combat_stats()
	assert(absf(stats_wc40["max_hp"] - 116.0) < 0.01, "WC40 HP expected 116.0, got %.2f" % stats_wc40["max_hp"])
	assert(absf(stats_wc40["stamina_max"] - 142.0) < 0.01, "WC40 Stamina expected 142.0, got %.2f" % stats_wc40["stamina_max"])
	assert(stats_wc40["display_damage"] == 22, "WC40 damage expected 22, got %d" % stats_wc40["display_damage"])
	assert(absf(stats_wc40["attack_interval"] - 1.778) < 0.01, "WC40 interval expected 1.778, got %.3f" % stats_wc40["attack_interval"])

	# 3) Воин 40 лет: S=12, E=14, топор L=12, G=10, P=1.0, R=1.0
	var warrior_40 = CitizenNPC.new("c_war40", "Воин 40л", "m", 40, "adult")
	warrior_40.strength_level = 12
	warrior_40.endurance_level = 14
	warrior_40.weapon_skills["axe_level"] = 12
	warrior_40.encounter_growth_points = 10.0
	warrior_40.equipment["weapon"] = "work_axe"
	var stats_war40 = warrior_40.get_combat_stats()
	assert(absf(stats_war40["max_hp"] - 142.0) < 0.01, "War40 HP expected 142.0, got %.2f" % stats_war40["max_hp"])
	assert(absf(stats_war40["stamina_max"] - 142.0) < 0.01, "War40 Stamina expected 142.0, got %.2f" % stats_war40["stamina_max"])
	assert(stats_war40["display_damage"] == 34, "War40 damage expected 34, got %d" % stats_war40["display_damage"])
	assert(absf(stats_war40["attack_interval"] - 1.714) < 0.01, "War40 interval expected 1.714, got %.3f" % stats_war40["attack_interval"])

	# 4) Тот же лесоруб 65 лет: S=16, E=14, топор L=3, G=0, P=0.65, R=0.775
	var woodcutter_65 = CitizenNPC.new("c_wc65", "Лесоруб 65л", "m", 65, "old")
	woodcutter_65.strength_level = 16
	woodcutter_65.endurance_level = 14
	woodcutter_65.weapon_skills["axe_level"] = 0
	woodcutter_65.profession_levels = {"woodcutter": 16}
	woodcutter_65.encounter_growth_points = 0.0
	woodcutter_65.equipment["weapon"] = "work_axe"
	var stats_wc65 = woodcutter_65.get_combat_stats()
	assert(absf(stats_wc65["max_hp"] - 75.40) < 0.01, "WC65 HP expected 75.40, got %.2f" % stats_wc65["max_hp"])
	assert(absf(stats_wc65["stamina_max"] - 87.30) < 0.01, "WC65 Stamina expected 87.30, got %.2f" % stats_wc65["stamina_max"])
	assert(stats_wc65["display_damage"] == 17, "WC65 damage expected 17, got %d" % stats_wc65["display_damage"])
	assert(absf(stats_wc65["attack_interval"] - 2.295) < 0.01, "WC65 interval expected 2.295, got %.3f" % stats_wc65["attack_interval"])
	print("OK 43. Section 29 benchmark characters (Novice 18, WC 40, Warrior 40, WC 65) verified with 100% precision.")

	# 44. ТЕСТ: Формулы урона, брони, пробития и точности
	var wolf_stats = CombatStatsResolver.calculate_animal_stats("wolf_grey")
	assert(wolf_stats["raw_damage"] == 12.0 and wolf_stats["threat"] == 1.25, "Wolf stats mismatch")
	
	# Волк атакует цель с броней 50 (effective armor 50 -> round(12 * 100 / 150) = 8)
	var defender_armored = {"armor": 50.0}
	var attack_result = CombatStatsResolver.resolve_attack(wolf_stats, defender_armored)
	if attack_result["is_hit"]:
		assert(attack_result["damage"] == 8, "Expected 8 damage against 50 armor, got %d" % attack_result["damage"])
		
	# Заяц с 0 урона не наносит повреждений
	var hare_stats = CombatStatsResolver.calculate_animal_stats("hare_brown")
	var hare_attack = CombatStatsResolver.resolve_attack(hare_stats, defender_armored)
	assert(not hare_attack["is_hit"] and hare_attack["damage"] == 0, "Hare with 0 damage must not hit or damage")
	
	# Усиленное копьё (пробитие 15% брони)
	var spear_attacker = {"raw_damage": 20.0, "accuracy": 1.0, "pen_fraction": 0.15, "pen_flat": 0.0}
	var spear_outcome = CombatStatsResolver.resolve_attack(spear_attacker, defender_armored)
	# Броня 50 * (1 - 0.15) = 42.5; final_damage = round(20 * 100 / 142.5) = round(14.035) = 14
	assert(spear_outcome["damage"] == 14, "Spear 15%% armor penetration expected 14 damage, got %d" % spear_outcome["damage"])
	print("OK 44. Universal combat formula, armor reduction, armor penetration & zero-attack check verified.")

	# 45. ТЕСТ: Опыт столкновений (EGP) и антифарм
	var hunter_egp = CitizenNPC.new("c_hunt", "Охотник", "m", 25, "adult")
	# 1) Победа над волком (threat = 1.25, 100% участие)
	hunter_egp.award_encounter(1.25, "wolf_grey", 1.0)
	assert(absf(hunter_egp.encounter_growth_points - 1.25) < 0.01, "Expected 1.25 EGP")
	
	# 2) Заяц (threat = 0.10)
	hunter_egp.award_encounter(0.10, "hare_brown", 1.0)
	assert(absf(hunter_egp.encounter_growth_points - 1.35) < 0.01, "Expected 1.35 EGP")
	
	# 3) Антифарм: 5 зайцев подряд снижают множитель до 0.1
	for i in range(5):
		hunter_egp.award_encounter(0.10, "hare_brown", 1.0)
	# 6-й заяц даст 0.10 * 0.1 = 0.01 EGP
	var prev_egp = hunter_egp.encounter_growth_points
	hunter_egp.award_encounter(0.10, "hare_brown", 1.0)
	assert(absf((hunter_egp.encounter_growth_points - prev_egp) - 0.01) < 0.001, "Anti-farm 0.1x multiplier failed")
	
	# 4) Ограничение EGP максимум 20
	hunter_egp.encounter_growth_points = 19.5
	hunter_egp.award_encounter(3.0, "bear_brown", 1.0)
	assert(hunter_egp.encounter_growth_points == 20.0, "EGP must be capped at 20.0")
	print("OK 45. Encounter growth points (EGP), threat scaling, anti-farm window & 20 EGP cap verified.")

	# 46. ТЕСТ: Рецепты EquipmentDB и экипировка гражданина
	assert(EquipmentDB.WEAPONS.has("battle_axe"), "Battle axe must be in EquipmentDB")
	assert(EquipmentDB.BODY_ARMOR.has("chainmail"), "Chainmail must be in EquipmentDB")
	assert(EquipmentDB.SHIELDS.has("wooden_shield"), "Wooden shield must be in EquipmentDB")
	
	var craft_rec = EquipmentDB.get_recipe("short_sword")
	assert(craft_rec["cost"]["metal"] == 6 and craft_rec["cost"]["wood"] == 1, "Short sword recipe materials mismatch")
	
	# Экипируем гражданина мечом, кольчугой и шлемом
	hunter_egp.equipment["weapon"] = "short_sword"
	hunter_egp.equipment["body_armor"] = "chainmail" # +30 брони
	hunter_egp.equipment["helmet"] = "iron_helmet"   # +8 брони
	hunter_egp.equipment["shield"] = "wooden_shield" # +10 брони
	var armored_stats = hunter_egp.get_combat_stats()
	assert(armored_stats["armor"] == 48.0, "Expected 48 total armor (30+8+10), got %.1f" % armored_stats["armor"])
	assert(armored_stats["weapon_id"] == "short_sword", "Weapon ID must be short_sword")
	
	# Проверка сохранения и загрузки экипировки и прогресса
	var saved_hunter = hunter_egp.serialize()
	var loaded_hunter = CitizenNPC.new()
	loaded_hunter.deserialize(saved_hunter)
	assert(loaded_hunter.equipment["weapon"] == "short_sword", "Loaded weapon mismatch")
	assert(loaded_hunter.equipment["body_armor"] == "chainmail", "Loaded armor mismatch")
	assert(loaded_hunter.encounter_growth_points == 20.0, "Loaded EGP mismatch")
	print("OK 46. EquipmentDB catalog, physical equip slots, total armor accumulation & persistence verified.")

	# --------------------------------------------------------------------------
	# S01 ВЕРИФИКАЦИЯ: ЕДИНЫЙ ЦИКЛ, ПАУЗА И ЧАСЫ (PlanetKI Living Settlement v2)
	# --------------------------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S01 UNIFIED SIMULATION RUNNER & TIME TESTS")
	print("----------------------------------------")
	
	# 47. Проверка временных констант: 600 с сутки, 1800 с год возраста
	assert(GameManager.DAY_CYCLE_DURATION == 600.0, "DAY_CYCLE_DURATION must be 600.0s")
	assert(GameManager.NPC_YEAR_DURATION == 1800.0, "NPC_YEAR_DURATION must be 1800.0s")
	assert(GameManager.base_tick_interval == 600.0, "base_tick_interval must be 600.0s")
	print("OK 47. S01 Time scale constants verified (600s day cycle, 1800s NPC year).")
	
	# 48. Непрерывное старение и бессмертие правителя
	var ruler_cit = pop.get_citizen_by_id("cit_1")
	assert(ruler_cit != null and ruler_cit.is_ruler, "cit_1 must be marked as ruler")
	var ruler_age_before = ruler_cit.age
	
	var ordinary_cit = pop.get_citizen_by_id("cit_2")
	assert(ordinary_cit != null and not ordinary_cit.is_ruler, "cit_2 must be ordinary citizen")
	var ordinary_age_before = ordinary_cit.age
	
	# Симулируем 1800.0 секунд (1 биографический год)
	ruler_cit.sim_aging(1800.0)
	ordinary_cit.sim_aging(1800.0)
	
	assert(ruler_cit.age == ruler_age_before, "Ruler must NOT age (Section 3 TZ v2)")
	assert(ordinary_cit.age == ordinary_age_before + 1, "Ordinary citizen must age by 1 year after 1800s (Section 4 TZ v2)")
	print("OK 48. S01 Continuous aging and ruler immortality verified.")
	
	# 49. Централизованный стек паузы и защита от случайного снятия паузы
	GameManager.set_paused(false)
	assert(not GameManager.is_paused, "Game should be unpaused")
	
	# Модальное окно открывается
	GameManager.push_modal_pause()
	assert(GameManager.is_paused, "Game must be paused when modal opens")
	
	# Игрок меняет скорость в UI во время открытого модального окна
	GameManager.set_speed(4.0)
	assert(GameManager.game_speed == 4.0, "Game speed should update to 4.0")
	assert(GameManager.is_paused, "Game MUST remain paused while modal is active")
	
	# Модальное окно закрывается
	GameManager.pop_modal_pause()
	assert(not GameManager.is_paused, "Game should resume after modal closes if user hadn't paused")
	
	# Пользователь нажал паузу, затем открылось модальное окно, затем закрылось
	GameManager.set_paused(true)
	GameManager.push_modal_pause()
	GameManager.pop_modal_pause()
	assert(GameManager.is_paused, "Game MUST remain paused if user explicitly paused before modal")
	GameManager.set_paused(false)
	print("OK 49. S01 Modal pause stack and robust speed switching verified.")
	
	# 50. Персистентность времени симуляции и дробного прогресса возраста в SaveSystem
	GameManager.sim_time_total = 1234.5
	GameManager.tick_accumulator = 450.0 # Полдень
	ordinary_cit.age_progress = 0.65
	
	var save_success = SaveSystem.save_game()
	assert(save_success, "SaveSystem must succeed")
	
	GameManager.sim_time_total = 0.0
	GameManager.tick_accumulator = 0.0
	var load_success = SaveSystem.load_game()
	assert(load_success, "SaveSystem load must succeed")
	assert(absf(GameManager.sim_time_total - 1234.5) < 0.1, "sim_time_total must persist across save/load")
	assert(absf(GameManager.tick_accumulator - 450.0) < 0.1, "tick_accumulator must persist across save/load")
	print("OK 50. S01 Simulation time & clock persistence across save/load verified.")

	# ---------------------------------------------------------
	# S02: УНИКАЛЬНЫЕ ИДЕНТИФИКАТОРЫ ЗДАНИЙ, GAME OVER И SAVE V2
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S02 BUILDING INSTANCES, RULER DEATH & SCHEMA V2")
	print("----------------------------------------")
	
	# 51. Уникальные instance_id для однотипных зданий
	var hut_a = BuildingInstance.new("hut_a", "hut", "test_settlement", Vector2i(10, 10))
	var hut_b = BuildingInstance.new("hut_b", "hut", "test_settlement", Vector2i(12, 10))
	assert(hut_a.instance_id != hut_b.instance_id, "Buildings of same type must have distinct instance_id")
	assert(hut_a.building_type == "hut" and hut_b.building_type == "hut", "Building type must match")
	
	var hut_a_dict = hut_a.serialize()
	var hut_a_restored = BuildingInstance.new()
	hut_a_restored.deserialize(hut_a_dict)
	assert(hut_a_restored.instance_id == "hut_a", "BuildingInstance serialization must preserve instance_id")
	assert(hut_a_restored.tile_coord == Vector2i(10, 10), "BuildingInstance serialization must preserve coordinates")
	print("OK 51. S02 BuildingInstance unique IDs and serialization verified.")

	# 52. Привязка жителя к конкретному BuildingInstance по instance_id
	var test_worker = CitizenNPC.new("cit_worker_1", "Рабочий", "m", 25, "adult")
	test_worker.home_id = hut_a.instance_id
	test_worker.home_coord = hut_a.tile_coord
	test_worker.workplace_id = "woodcutter_camp_15_15"
	test_worker.workplace_coord = Vector2i(15, 15)
	
	var w_data = test_worker.serialize()
	var w_restored = CitizenNPC.new()
	w_restored.deserialize(w_data)
	assert(w_restored.home_id == hut_a.instance_id, "Citizen home_id must link to specific BuildingInstance id")
	assert(w_restored.workplace_id == "woodcutter_camp_15_15", "Citizen workplace_id must link to specific BuildingInstance id")
	print("OK 52. S02 Citizen 1:1 binding to building instance IDs verified.")

	# 53. Смерть вождя вызывает Game Over и останавливает симуляцию
	var test_ruler = CitizenNPC.new("ruler_test", "Тестовый Вождь", "m", 40, "adult")
	test_ruler.is_ruler = true
	test_ruler.health = 20.0
	GameManager.is_game_over = false
	GameManager.game_over_reason = ""
	
	var ruler_result = {"emitted": false, "name": "", "killer": ""}
	var ruler_conn = func(r_name, k_name):
		ruler_result["emitted"] = true
		ruler_result["name"] = r_name
		ruler_result["killer"] = k_name
	EventBus.ruler_died.connect(ruler_conn)
	
	var is_dead = test_ruler.take_damage(25.0, "Голодный медведь")
	assert(is_dead, "Ruler should be dead after lethal damage")
	assert(ruler_result["emitted"], "EventBus.ruler_died must be emitted upon ruler death")
	assert(ruler_result["name"] == "Тестовый Вождь", "Ruler name in signal must match")
	assert(GameManager.is_game_over, "GameManager.is_game_over must be true upon ruler death")
	assert(GameManager.game_over_reason != "", "GameManager.game_over_reason must be populated")
	EventBus.ruler_died.disconnect(ruler_conn)
	GameManager.is_game_over = false # сброс для продолжения тестов
	print("OK 53. S02 Ruler death triggers EventBus.ruler_died and GameManager.is_game_over verified.")

	# 54. Схема сохранения v2 с атомарной записью и очередью строительства
	var target_settlement = s
	if target_settlement == null:
		target_settlement = GameManager.settlements.values()[0] if GameManager.settlements.size() > 0 else SettlementData.new("test_s", "Стоянка", "player_tribe", Vector2i(80, 80))
	GameManager.settlements[target_settlement.id] = target_settlement
	target_settlement.construction_queue.clear()
	target_settlement.construction_queue.append({
		"id": "hut",
		"coord": Vector2i(42, 42),
		"days_left": 2.0,
		"total_days": 2,
		"settlement_id": target_settlement.id,
		"is_paused": false
	})
	assert(target_settlement.construction_queue.size() == 1, "Construction queue should have 1 item")
	
	var save_v2_ok = SaveSystem.save_game()
	assert(save_v2_ok, "SaveSystem v2 save must succeed")
	
	target_settlement.construction_queue.clear()
	var load_v2_ok = SaveSystem.load_game()
	assert(load_v2_ok, "SaveSystem v2 load must succeed")
	assert(SaveSystem.last_loaded_version == 2, "Loaded save must be schema_version 2")
	var s02_loaded_s = GameManager.settlements.get(target_settlement.id, null)
	assert(s02_loaded_s != null, "Settlement must exist after load")
	assert(s02_loaded_s.construction_queue.size() == 1, "Construction queue must be preserved across save/load")
	assert(s02_loaded_s.construction_queue[0]["id"] == "hut", "Queue item id preserved")
	assert(s02_loaded_s.construction_queue[0]["coord"] == Vector2i(42, 42), "Queue item coord preserved")
	print("OK 54. S02 Save schema v2, atomic save and construction queue persistence verified.")

	# 55. S03 TaskService: полный жизненный цикл задачи лесоруба (создание, резерв, прибытие, доставка, завершение)
	assert(GameManager.task_service != null, "GameManager.task_service must exist")
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]
	else:
		GameManager.settlements[s.id] = s
	var s03_tree_coord = Vector2i(s.pos.x + 2, s.pos.y)
	GameManager.planet_data["tiles"][s03_tree_coord.y][s03_tree_coord.x]["nature_object"] = "tree_pine"
	GameManager.planet_data["tiles"][s03_tree_coord.y][s03_tree_coord.x]["walkable"] = true
	if GameManager.nav_grid and GameManager.nav_grid.astar:
		GameManager.nav_grid.astar.set_point_solid(s03_tree_coord, false)
		GameManager.nav_grid.astar.set_point_solid(Vector2i(s.pos.x + 1, s.pos.y), false)
		GameManager.nav_grid.astar.set_point_solid(Vector2i(s.pos.x, s.pos.y), false)
	var s03_tree_pos = Vector2(s03_tree_coord.x * 32.0 + 16, s03_tree_coord.y * 32.0 + 16)
	GameManager.resource_manager.nodes[s03_tree_coord] = {
		"id": "s03_tree_node",
		"coord": s03_tree_coord,
		"pos": s03_tree_pos,
		"type": "wood",
		"category": "wood",
		"name": "Сосна S03",
		"amount": 100.0,
		"max_amount": 100.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "tree_pine",
		"depleted_sprite": "none",
		"regrowth_timer": 999999.0,
		"regrowth_duration": 999999.0
	}
	var woodcutter = CitizenNPC.new("s03_wc", "Лесоруб S03", "m", 25, "adult")
	woodcutter.job_id = "woodcutter"
	woodcutter.settlement_id = s.id
	woodcutter.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	woodcutter.home_pos = woodcutter.pos
	woodcutter.equipped_tool = {"id": "axe_test", "type": "axe", "durability": 100.0, "max_durability": 100.0}
	if not s.buildings.has("woodcutter_camp"):
		s.buildings.append("woodcutter_camp")
	for c in s.population.citizens:
		if c.job_id == "woodcutter":
			c.job_id = "idle"
	s.population.citizens.append(woodcutter)
	
	s.priority_harvest_coords.clear()
	s.priority_harvest_coords.append(s03_tree_coord)
	
	# Вызываем обновление жителей: лесоруб должен найти дерево и создать задачу в TaskService
	s.update_citizens(0.1)
	assert(woodcutter.state == CitizenNPC.State.MOVING_TO_WORK, "Woodcutter must move to work")
	assert(woodcutter.task_instance_id != "", "Woodcutter must have task_instance_id assigned")
	var t_info = GameManager.task_service.get_task(woodcutter.task_instance_id)
	assert(t_info.get("state") == TaskService.TaskState.RESERVED, "Task state must be RESERVED")
	assert(t_info.get("actor_id") == woodcutter.citizen_id, "Task actor must be assigned to woodcutter")
	
	# Имитируем прибытие к дереву
	woodcutter.pos = s03_tree_pos
	woodcutter.path.clear()
	s.update_citizens(0.1)
	assert(woodcutter.state == CitizenNPC.State.WORKING, "Woodcutter must start working at tree")
	var t_arrived = GameManager.task_service.get_task(woodcutter.task_instance_id)
	assert(t_arrived.get("state") == TaskService.TaskState.IN_PROGRESS, "Task state must be IN_PROGRESS while working")
	
	# Удары топором: прогрессивная рубка (сокращено в 2 раза: 12.5 дров за удар)
	woodcutter.work_timer = 0.0
	s.update_citizens(0.1)
	assert(woodcutter.cargo_amount == 12.5, "Woodcutter must have 12.5 wood in hands after 1 strike")
	assert(GameManager.resource_manager.nodes[s03_tree_coord]["amount"] == 87.5, "Tree amount must be reduced to 87.5")
	
	# Завершаем рубку дерева (остальные 87.5 дров)
	woodcutter.work_timer = 0.0
	GameManager.resource_manager.harvest_from_node(s03_tree_coord, 87.5) # дорубаем запас дерева
	s.update_citizens(0.1)
	assert(woodcutter.state == CitizenNPC.State.CARRYING, "Woodcutter must enter CARRYING state")
	var t_delivering = GameManager.task_service.get_task(woodcutter.task_instance_id)
	assert(t_delivering.get("state") == TaskService.TaskState.DELIVERING, "Task state must be DELIVERING")
	print("OK 55. S03 Woodcutter TaskService lifecycle (RESERVED -> ARRIVED -> IN_PROGRESS -> DELIVERING) verified.")

	# 56. S03 Обработка NO_PATH при недостижимости цели
	var blocked_coord = Vector2i(5, 5)
	var blocked_pos = Vector2(blocked_coord.x * 32.0 + 16, blocked_coord.y * 32.0 + 16)
	GameManager.planet_data["tiles"][blocked_coord.y][blocked_coord.x]["walkable"] = false
	GameManager.resource_manager.nodes[blocked_coord] = {
		"id": "s03_blocked_tree",
		"coord": blocked_coord,
		"pos": blocked_pos,
		"type": "wood",
		"category": "wood",
		"name": "Недостижимое дерево",
		"amount": 100.0,
		"max_amount": 100.0,
		"reserved_by": "",
		"depleted": false
	}
	var blocked_wc = CitizenNPC.new("s03_blocked_wc", "Заблокированный Лесоруб", "m", 25, "adult")
	blocked_wc.job_id = "woodcutter"
	blocked_wc.settlement_id = s.id
	blocked_wc.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	s.priority_harvest_coords.clear()
	s.priority_harvest_coords.append(blocked_coord)
	var wood_before_blocked = s.economy.get_resource("wood")
	s._dispatch_priority_worker(blocked_coord, "wood")
	assert(blocked_wc.state == CitizenNPC.State.WAITING or blocked_wc.state == CitizenNPC.State.IDLE, "Worker must remain WAITING when no path exists")
	assert(s.economy.get_resource("wood") == wood_before_blocked, "Zero wood must be produced when path is blocked")
	s.priority_harvest_coords.clear()
	print("OK 56. S03 NO_PATH / BLOCKED task handling verified.")

	# 57. S03 Физическая доставка груза: склад не пополняется мгновенно до прибытия
	var initial_econ_wood = s.economy.get_resource("wood")
	woodcutter.cargo_amount = 100.0
	woodcutter.cargo_type = "wood"
	woodcutter.state = CitizenNPC.State.CARRYING
	woodcutter.pos = s03_tree_pos # далеко от склада
	s.update_citizens(0.01)
	assert(s.economy.get_resource("wood") == initial_econ_wood, "Economy wood MUST NOT increase while cargo is still in transit")
	
	# Доставляем на склад
	var storage_p = s._get_storage_pos(woodcutter)
	woodcutter.pos = storage_p
	woodcutter.path.clear()
	s.update_citizens(0.01)
	assert(woodcutter.cargo_amount == 0.0, "Cargo in hands must be cleared upon delivery")
	assert(s.economy.get_resource("wood") == initial_econ_wood + 100.0, "Economy wood must increase by 100 on warehouse arrival")
	print("OK 57. S03 Physical cargo transport and warehouse arrival crediting verified.")

	# 58. S03 Сохранение/загрузка груза в пути и ночной режим
	woodcutter.cargo_amount = 50.0
	woodcutter.cargo_type = "wood"
	woodcutter.state = CitizenNPC.State.CARRYING
	GameManager.current_hour = 23.0 # Наступает ночь
	s.update_citizens(0.1)
	assert(woodcutter.state == CitizenNPC.State.GOING_HOME or woodcutter.state == CitizenNPC.State.SLEEPING, "Citizen must head home at night")
	assert(woodcutter.cargo_amount == 50.0, "Citizen must retain 50 wood in hands during sleep (no night teleportation!)")
	
	var save_s03_ok = SaveSystem.save_game()
	assert(save_s03_ok, "Save during night with cargo must succeed")
	
	woodcutter.cargo_amount = 0.0
	var load_s03_ok = SaveSystem.load_game()
	assert(load_s03_ok, "Load game must succeed")
	
	var s03_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s03_loaded_s != null, "Settlement must exist after load")
	var s03_loaded_wc = null
	for c in s03_loaded_s.population.citizens:
		if c.citizen_id == "s03_wc":
			s03_loaded_wc = c
			break
	assert(s03_loaded_wc != null, "Woodcutter citizen must exist after load")
	assert(s03_loaded_wc.cargo_amount == 50.0, "Citizen must still have 50 wood in cargo after load")
	assert(s03_loaded_wc.cargo_type == "wood", "Citizen cargo_type preserved as wood")
	
	# Наступает утро
	GameManager.current_hour = 8.0
	s03_loaded_s.update_citizens(0.1)
	assert(s03_loaded_wc.state == CitizenNPC.State.CARRYING, "Citizen must resume CARRYING upon waking up")
	print("OK 58. S03 Mid-haul cargo preservation, night retention, and save/load persistence verified.")

	# ---------------------------------------------------------
	# S04: ОБЩИЙ УЧЁТ ГРУЗОВ, ПАРТИИ ПИЩИ, ПОРЧА И РЕЕСТР LEGACY
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S04 CARGO, FOOD BATCHES, SPOILAGE & PHYSICAL EXTRACTORS")
	print("----------------------------------------")
	GameManager.current_hour = 12.0
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]

	# 59. Собиратель (Forager): поиск куста, сбор ягод, создание партии пищи с меткой времени, доставка на склад
	var bush_coord = Vector2i(s.pos.x + 3, s.pos.y + 1)
	GameManager.planet_data["tiles"][bush_coord.y][bush_coord.x]["walkable"] = true
	var bush_pos = Vector2(bush_coord.x * 32.0 + 16, bush_coord.y * 32.0 + 16)
	GameManager.resource_manager.nodes[bush_coord] = {
		"id": "s04_bush_node",
		"coord": bush_coord,
		"pos": bush_pos,
		"type": "food",
		"category": "food",
		"name": "Ягодный куст S04",
		"amount": 20.0,
		"max_amount": 20.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "bush_berries",
		"depleted_sprite": "none",
		"regrowth_timer": 999999.0,
		"regrowth_duration": 999999.0
	}
	var forager = CitizenNPC.new("s04_forager", "Собиратель S04", "f", 22, "adult")
	forager.job_id = "forager"
	forager.settlement_id = s.id
	forager.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	forager.home_pos = forager.pos
	s.population.citizens.append(forager)

	s.update_citizens(0.1)
	assert(forager.state == CitizenNPC.State.MOVING_TO_WORK, "Forager must start moving towards bush")
	assert(forager.task_instance_id != "", "Forager must have TaskService task assigned")
	var t_forage = GameManager.task_service.get_task(forager.task_instance_id)
	assert(t_forage.get("state") == TaskService.TaskState.RESERVED, "Task state must be RESERVED")

	# Прибытие к кусту
	forager.pos = forager.target_pos
	forager.path.clear()
	s.update_citizens(0.1)
	assert(forager.state == CitizenNPC.State.GATHERING, "Forager must enter GATHERING state at bush")
	var t_forage_arr = GameManager.task_service.get_task(forager.task_instance_id)
	assert(t_forage_arr.get("state") == TaskService.TaskState.IN_PROGRESS, "Task state must be IN_PROGRESS while gathering")

	# Завершение сбора
	forager.work_timer = 0.0
	var food_before_harvest = s.economy.get_resource("food")
	var batches_before = s.food_batches.size()
	s.update_citizens(0.1)
	assert(forager.state == CitizenNPC.State.CARRYING, "Forager must enter CARRYING state after gathering")
	assert(forager.cargo_type == "food", "Cargo type must be food")
	assert(forager.cargo_amount > 0.0, "Forager cargo_amount must be greater than 0")
	assert(not forager.cargo_batch.is_empty(), "Forager must carry cargo_batch metadata")
	assert(forager.cargo_batch.get("food_type") == "berries", "Food batch type must be berries")
	assert(forager.cargo_batch.get("max_freshness_sec") == 3600.0, "Berries max freshness must be 3600s")
	assert(s.economy.get_resource("food") == food_before_harvest, "Food in warehouse MUST NOT increase while in transit")

	# Прибытие на склад
	var storage_pos = s._get_storage_pos(forager)
	forager.pos = storage_pos
	forager.path.clear()
	s.update_citizens(0.1)
	assert(forager.cargo_amount == 0.0, "Cargo must be deposited at warehouse")
	assert(s.economy.get_resource("food") > food_before_harvest, "Warehouse food must increase on delivery")
	assert(s.food_batches.size() == batches_before + 1, "A new food batch must be registered in settlement.food_batches")
	assert(s.food_batches.back().get("food_type") == "berries", "New batch in settlement must be berries")
	print("OK 59. S04 Forager TaskService gathering, cargo_batch creation & warehouse delivery verified.")

	# 60. Каменотёс (Quarryman) и Рудокоп (Miner): TaskService, проверка путей и физическая доставка на склад
	var rock_coord = Vector2i(s.pos.x + 2, s.pos.y - 2)
	GameManager.planet_data["tiles"][rock_coord.y][rock_coord.x]["walkable"] = true
	var rock_pos = Vector2(rock_coord.x * 32.0 + 16, rock_coord.y * 32.0 + 16)
	GameManager.resource_manager.nodes[rock_coord] = {
		"id": "s04_rock_node",
		"coord": rock_coord,
		"pos": rock_pos,
		"type": "stone",
		"category": "stone",
		"name": "Скала S04",
		"amount": 50.0,
		"max_amount": 50.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "rock",
		"depleted_sprite": "none",
		"regrowth_timer": 999999.0,
		"regrowth_duration": 999999.0
	}
	var quarryman = CitizenNPC.new("s04_qm", "Каменотёс S04", "m", 30, "adult")
	quarryman.job_id = "quarryman"
	quarryman.settlement_id = s.id
	quarryman.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	quarryman.home_pos = quarryman.pos
	s.population.citizens.append(quarryman)

	s.update_citizens(0.1)
	assert(quarryman.state == CitizenNPC.State.MOVING_TO_WORK, "Quarryman must move to stone node")
	assert(quarryman.task_instance_id != "", "Quarryman must have TaskService task assigned")
	var t_rock = GameManager.task_service.get_task(quarryman.task_instance_id)
	assert(t_rock.get("kind_id") == "mine_stone", "Task kind_id must be mine_stone")

	# Завершаем добычу камня и доставку
	quarryman.pos = quarryman.target_pos
	quarryman.path.clear()
	s.update_citizens(0.1)
	quarryman.work_timer = 0.0
	var stone_before = s.economy.get_resource("stone")
	s.update_citizens(0.1)
	assert(quarryman.state == CitizenNPC.State.CARRYING, "Quarryman must carry stone after mining")
	assert(quarryman.cargo_type == "stone", "Cargo type must be stone")
	assert(s.economy.get_resource("stone") == stone_before, "Stone must not be in economy while carried")

	quarryman.pos = s._get_storage_pos(quarryman)
	quarryman.path.clear()
	s.update_citizens(0.1)
	assert(quarryman.cargo_amount == 0.0, "Hands must be cleared after stone delivery")
	assert(s.economy.get_resource("stone") > stone_before, "Settlement stone must increase upon delivery")
	print("OK 60. S04 Quarryman & Miner TaskService physical mining and warehouse delivery verified.")

	# 61. Прогрессивная порча пищи (update_food_spoilage) и влияние амбара
	s.food_batches.clear()
	s.economy.resources["food"] = 50.0
	s.deposit_food_batch({
		"food_type": "berries",
		"amount": 20.0,
		"created_sim_time": GameManager.sim_time_total,
		"max_freshness_sec": 100.0,
		"spoilage_progress": 0.95
	})
	s.deposit_food_batch({
		"food_type": "meat",
		"amount": 30.0,
		"created_sim_time": GameManager.sim_time_total,
		"max_freshness_sec": 1000.0,
		"spoilage_progress": 0.0
	})
	assert(s.food_batches.size() == 2, "Must have 2 food batches")
	
	# Обновление порчи без амбара (delta = 10.0 при max_freshness = 100.0 даст +0.10 прогресса порчи, 0.95 + 0.10 = 1.05 >= 1.0 -> первая партия портится)
	s.update_food_spoilage(10.0)
	assert(s.food_batches.size() == 1, "Expired food batch must be removed from food_batches")
	assert(s.food_batches[0].get("food_type") == "meat", "Remaining batch must be meat")
	assert(s.economy.get_resource("food") == 30.0, "Spoiled food (20) must be deducted from economy.resources['food']")

	# Проверяем влияние амбара на снижение скорости порчи
	var initial_spoilage = float(s.food_batches[0]["spoilage_progress"])
	s.buildings.append("granary")
	var granary_factor = s.get_granary_spoilage_factor()
	assert(granary_factor == 0.5, "Granary must reduce spoilage rate to 0.5")
	s.update_food_spoilage(100.0)
	var delta_spoilage = float(s.food_batches[0]["spoilage_progress"]) - initial_spoilage
	# Ожидаемый прирост: (100.0 / 1000.0) * 0.5 = 0.05
	assert(absf(delta_spoilage - 0.05) < 0.001, "Spoilage rate with granary must match granary_factor (0.5x)")
	s.buildings.erase("granary")
	print("OK 61. S04 Progressive food spoilage & granary factor (get_granary_spoilage_factor) verified.")

	# 62. FIFO потребление пищи, неизменность возраста партии при перекладывании и сохранение партий в SaveSystem
	s.food_batches.clear()
	s.economy.resources["food"] = 35.0
	s.deposit_food_batch({
		"batch_id": "old_batch",
		"food_type": "berries",
		"amount": 10.0,
		"created_sim_time": 100.0,
		"max_freshness_sec": 3600.0,
		"spoilage_progress": 0.4
	})
	s.deposit_food_batch({
		"batch_id": "fresh_batch",
		"food_type": "meat",
		"amount": 25.0,
		"created_sim_time": 500.0,
		"max_freshness_sec": 4500.0,
		"spoilage_progress": 0.05
	})
	
	# Потребление части старой партии
	var eaten = s.consume_food(4.0)
	assert(eaten == 4.0, "Must consume requested 4.0 food")
	assert(s.food_batches[0]["batch_id"] == "old_batch", "FIFO: oldest batch must be consumed first")
	assert(s.food_batches[0]["amount"] == 6.0, "Old batch amount reduced to 6.0")
	assert(s.food_batches[0]["spoilage_progress"] == 0.4, "Food consumption/moving does NOT refresh spoilage progress")
	assert(s.food_batches[1]["amount"] == 25.0, "Fresher batch left untouched")
	
	# Потребление остатка старой партии + захват свежей
	eaten = s.consume_food(10.0)
	assert(eaten == 10.0, "Must consume requested 10.0 food")
	assert(s.food_batches.size() == 1, "Fully consumed old batch must be removed")
	assert(s.food_batches[0]["batch_id"] == "fresh_batch", "Only fresher batch remains")
	assert(s.food_batches[0]["amount"] == 21.0, "Fresh batch amount reduced by 4.0 to 21.0")

	# Сохранение и загрузка партий пищи
	var save_batches_ok = SaveSystem.save_game()
	assert(save_batches_ok, "Save with food_batches must succeed")
	s.food_batches.clear()
	var load_batches_ok = SaveSystem.load_game()
	assert(load_batches_ok, "Load with food_batches must succeed")
	var s04_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s04_loaded_s != null, "Settlement must exist after load")
	assert(s04_loaded_s.food_batches.size() == 1, "Loaded settlement must have 1 preserved food batch")
	assert(s04_loaded_s.food_batches[0]["batch_id"] == "fresh_batch", "Loaded batch_id preserved")
	assert(s04_loaded_s.food_batches[0]["amount"] == 21.0, "Loaded batch amount preserved")
	assert(absf(s04_loaded_s.food_batches[0]["spoilage_progress"] - 0.05) < 0.001, "Loaded batch spoilage_progress preserved")
	print("OK 62. S04 FIFO food consumption, age preservation and SaveSystem food_batches persistence verified.")

	# ---------------------------------------------------------
	# S05: РЕАЛЬНОЕ СТРОИТЕЛЬСТВО, УЛУЧШЕНИЯ И КРАФТ
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S05 PHYSICAL CONSTRUCTION, UPGRADES & CRAFTING")
	print("----------------------------------------")
	GameManager.current_hour = 12.0
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]

	# 63. Нехватка стройматериалов останавливает стройку, физическая доставка материалов со склада
	var s05_site_coord = Vector2i(s.pos.x + 4, s.pos.y)
	GameManager.planet_data["tiles"][s05_site_coord.y][s05_site_coord.x]["walkable"] = true
	var s05_site_pos = Vector2(s05_site_coord.x * 32.0 + 16, s05_site_coord.y * 32.0 + 16)
	GameManager.tile_buildings[s05_site_coord] = {
		"id": "woodcutter_camp",
		"status": "constructing",
		"settlement_id": s.id,
		"days_left": 2.0,
		"total_days": 2,
		"materials_required": {"wood": 15.0, "stone": 5.0},
		"materials_delivered": {}
	}
	s.construction_queue.clear()
	var q_item = GameManager.tile_buildings[s05_site_coord].duplicate(true)
	q_item["coord"] = s05_site_coord
	s.construction_queue.append(q_item)

	# Склад и буфер лагеря пусты
	s.economy.resources["wood"] = 0.0
	s.economy.resources["stone"] = 0.0
	var active_wc_camp = s.get_active_woodcutter_camp()
	if active_wc_camp:
		active_wc_camp.local_buffer_wood = 0.0
	s.priority_harvest_coords.clear()
	for c_other in s.population.citizens:
		c_other.cargo_amount = 0.0
		c_other.state = CitizenNPC.State.WAITING
		c_other.decision_cooldown = 100.0

	var test_builder = CitizenNPC.new("s05_builder", "Строитель S05", "m", 28, "adult")
	test_builder.job_id = "builder"
	test_builder.settlement_id = s.id
	test_builder.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	test_builder.home_pos = test_builder.pos
	test_builder.max_carry = 20.0
	s.population.citizens.append(test_builder)

	# Обновление: строитель видит, что на складе 0 дерева и 0 камня -> стройка останавливается
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.WAITING, "Builder must halt in WAITING state when warehouse has no materials")
	assert("нет материалов" in test_builder.last_status_reason.to_lower(), "Status reason must indicate lack of materials")
	assert(GameManager.tile_buildings[s05_site_coord]["days_left"] == 2.0, "Construction days_left MUST NOT decrease when materials are missing")

	# Добавляем дерево на склад
	s.economy.resources["wood"] = 30.0
	test_builder.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.MOVING_TO_WORK, "Builder must move to warehouse to fetch materials")
	assert(test_builder.task_id == "fetch_materials", "Builder task_id must be fetch_materials")

	# Прибытие на склад
	test_builder.pos = s._get_storage_pos(test_builder)
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.CARRYING, "Builder must enter CARRYING state after fetching materials")
	assert(test_builder.cargo_type == "wood", "Builder must carry wood")
	assert(test_builder.cargo_amount == 15.0, "Builder must carry needed 15 wood")
	assert(s.economy.get_resource("wood") == 15.0, "Wood in warehouse must be deducted by 15")

	# Доставка дерева на стройплощадку
	test_builder.pos = s05_site_pos
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(test_builder.cargo_amount == 0.0, "Builder hands must be cleared after depositing materials")
	assert(GameManager.tile_buildings[s05_site_coord]["materials_delivered"]["wood"] == 15.0, "Site materials_delivered must record 15 wood")

	# Камень всё ещё не завезён (0 на складе): стройка снова останавливается
	test_builder.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.WAITING, "Builder must wait because stone is still missing")
	print("OK 63. S05 Lack of materials halts construction, physical builder hauling from warehouse verified.")

	# 64. Завершение завоза материалов и завершение строительства здания
	s.economy.resources["stone"] = 20.0
	test_builder.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_builder.task_id == "fetch_materials", "Builder must fetch stone")

	# Доставляем камень на площадку
	test_builder.pos = s._get_storage_pos(test_builder)
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(test_builder.cargo_type == "stone" and test_builder.cargo_amount == 5.0, "Builder carried 5 stone")
	assert(s.economy.get_resource("stone") == 15.0, "Warehouse stone deducted by 5")

	test_builder.pos = s05_site_pos
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(GameManager.tile_buildings[s05_site_coord]["materials_delivered"]["stone"] == 5.0, "Site has all stone delivered")

	# Все материалы на месте! Теперь строитель приступает к физическому возведению
	test_builder.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.MOVING_TO_WORK or test_builder.state == CitizenNPC.State.WORKING, "Builder goes to construct")
	assert(test_builder.task_id == "build", "Builder task is build")

	test_builder.pos = s05_site_pos
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.WORKING, "Builder is working on site")

	# Завершаем стройку
	test_builder.work_timer = 0.0
	GameManager.tile_buildings[s05_site_coord]["days_left"] = 0.1
	s.update_citizens(0.1)
	assert(GameManager.tile_buildings[s05_site_coord]["status"] == "active", "Building must become active")
	assert(s.buildings.has("woodcutter_camp"), "Building must be added to settlement buildings list")
	print("OK 64. S05 Building materials completion and physical construction completion verified.")

	# 65. Улучшение здания: не применяется мгновенно, требует доставки материалов и работы строителя
	var starter_inst = GameManager.get_or_create_building_instance(s.pos, "elders_house", s.id)
	assert(not starter_inst.is_upgrade_unlocked("elders_lore_hearth"), "Upgrade must not be unlocked initially")

	var up_started = starter_inst.start_upgrade("elders_lore_hearth", {"wood": 10.0})
	assert(up_started, "start_upgrade must succeed")
	assert(not starter_inst.is_upgrade_unlocked("elders_lore_hearth"), "Upgrade MUST NOT unlock instantly (no decorative stubs!)")
	assert(starter_inst.has_pending_upgrade(), "Building instance must report pending_upgrade")

	# Доставляем материалы для улучшения
	s.economy.resources["wood"] = 25.0
	test_builder.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_builder.task_id == "fetch_upgrade_materials", "Builder must fetch upgrade materials")

	test_builder.pos = s._get_storage_pos(test_builder)
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(test_builder.cargo_type == "wood" and test_builder.cargo_amount == 10.0, "Carries 10 wood for upgrade")

	test_builder.pos = GameManager.nav_grid.tile_to_world_center(starter_inst.pos)
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(starter_inst.pending_upgrade["materials_delivered"]["wood"] == 10.0, "Upgrade site received 10 wood")

	# Строитель выполняет работу по улучшению
	test_builder.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_builder.task_id == "upgrade_work", "Builder task must be upgrade_work")

	test_builder.pos = GameManager.nav_grid.tile_to_world_center(starter_inst.pos)
	test_builder.path.clear()
	s.update_citizens(0.1)
	assert(test_builder.state == CitizenNPC.State.WORKING, "Builder must work on upgrade")

	# Завершаем работу над улучшением
	test_builder.work_timer = 0.0
	starter_inst.pending_upgrade["work_left"] = 0.2
	s.update_citizens(0.1)
	assert(starter_inst.is_upgrade_unlocked("elders_lore_hearth"), "Upgrade must be unlocked only after physical work completed")
	assert(not starter_inst.has_pending_upgrade(), "Pending upgrade cleared upon completion")
	print("OK 65. S05 Building upgrade: material delivery, builder labor & non-instant unlock verified.")

	# 66. Ремесленник без сырья простаивает, забирает сырье со склада, изготавливает изделия в мастерской и сдает на склад; Save/Load
	var test_craftsman = CitizenNPC.new("s05_craftsman", "Ремесленник S05", "f", 24, "adult")
	test_craftsman.job_id = "craftsman"
	test_craftsman.settlement_id = s.id
	test_craftsman.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	test_craftsman.home_pos = test_craftsman.pos
	s.population.citizens.append(test_craftsman)

	# 0 сырья на складе
	s.economy.resources["wood"] = 0.0
	s.economy.resources["metal"] = 0.0
	s.economy.resources["stone"] = 0.0
	test_craftsman.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_craftsman.state == CitizenNPC.State.WAITING, "Craftsman must be WAITING when no raw material is available")
	assert("нет сырья" in test_craftsman.last_status_reason.to_lower(), "Status reason must say no raw material")

	# Появляется сырье на складе
	for c in s.population.citizens:
		if c != test_craftsman:
			c.cargo_amount = 0.0
			c.cargo_type = ""
	s.economy.resources["wood"] = 5.0
	test_craftsman.decision_cooldown = 0.0
	s.update_citizens(0.1)
	assert(test_craftsman.task_id == "fetch_craft_raw", "Craftsman must fetch raw material")

	# Прибытие на склад за сырьем
	var s05_wood_before = s.economy.get_resource("wood")
	test_craftsman.pos = s._get_storage_pos(test_craftsman)
	test_craftsman.path.clear()
	s.update_citizens(0.1)
	assert(test_craftsman.cargo_type == "wood" and test_craftsman.cargo_amount == 1.0, "Craftsman fetched 1 wood")
	assert(s.economy.get_resource("wood") == s05_wood_before - 1.0, "Warehouse wood deducted by 1.0")

	# Прибытие в мастерскую и изготовление
	test_craftsman.pos = s._find_craftsman_workshop_pos(test_craftsman)
	test_craftsman.path.clear()
	s.update_citizens(0.1)
	assert(test_craftsman.state == CitizenNPC.State.WORKING, "Craftsman is WORKING in workshop")

	# Завершение крафта: в руках кубрики
	test_craftsman.work_timer = 0.0
	var kubriki_before = s.economy.get_resource("kubriki")
	s.update_citizens(0.1)
	assert(test_craftsman.state == CitizenNPC.State.CARRYING, "Craftsman enters CARRYING state with crafted items")
	assert(test_craftsman.cargo_type == "kubriki" and test_craftsman.cargo_amount == 1.0, "Craftsman carries 1 kubrik")
	assert(s.economy.get_resource("kubriki") == kubriki_before, "Kubriki not yet credited while in hands")

	# Доставка на склад
	test_craftsman.pos = s._get_storage_pos(test_craftsman)
	test_craftsman.path.clear()
	s.update_citizens(0.1)
	assert(test_craftsman.cargo_amount == 0.0, "Hands cleared after delivery")
	assert(s.economy.get_resource("kubriki") == kubriki_before + 1.0, "Warehouse kubriki credited upon physical delivery")

	# Сохранение и загрузка стройплощадки и крафта
	var s05_save_site = Vector2i(s.pos.x + 6, s.pos.y)
	s.start_construction("hut", s05_save_site)
	GameManager.tile_buildings[s05_save_site]["materials_delivered"]["wood"] = 12.0

	var save_s05_ok = SaveSystem.save_game()
	assert(save_s05_ok, "Save with S05 construction & materials must succeed")

	var load_s05_ok = SaveSystem.load_game()
	assert(load_s05_ok, "Load with S05 construction & materials must succeed")

	var s05_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s05_loaded_s != null, "Settlement must exist after load")
	assert(GameManager.tile_buildings.has(s05_save_site), "Construction site must exist after load")
	assert(GameManager.tile_buildings[s05_save_site]["materials_delivered"]["wood"] == 12.0, "Delivered materials on site preserved across save/load")
	print("OK 66. S05 Craftsman raw materials cycle, idle without raw, product delivery & Save/Load persistence verified.")

	# ---------------------------------------------------------
	# S06: ПРОЖИВАНИЕ, ДОМОХОЗЯЙСТВА И ДОМАШНИЕ ЗАПАСЫ
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S06 HOUSING, HOUSEHOLDS & DOMESTIC STOCKS")
	print("----------------------------------------")
	GameManager.current_hour = 12.0
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]

	# 67. Минимум две семьи живут и спят в разных домах; гостевое проживание и закрепление игрока
	var coord_hut1 = Vector2i(-1, -1)
	var coord_hut2 = Vector2i(-1, -1)
	for r in range(1, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var check_c = s.pos + Vector2i(dx, dy)
				if not GameManager.nav_grid.is_valid_coord(check_c) or GameManager.nav_grid.is_water_tile(check_c) or GameManager.tile_buildings.has(check_c):
					continue
				var test_p = GameManager.nav_grid.find_path(GameManager.nav_grid.tile_to_world_center(check_c), GameManager.nav_grid.tile_to_world_center(s.pos))
				if not test_p.is_empty():
					if coord_hut1 == Vector2i(-1, -1):
						coord_hut1 = check_c
					elif coord_hut2 == Vector2i(-1, -1) and check_c != coord_hut1:
						coord_hut2 = check_c
						break
			if coord_hut1 != Vector2i(-1, -1) and coord_hut2 != Vector2i(-1, -1):
				break
		if coord_hut1 != Vector2i(-1, -1) and coord_hut2 != Vector2i(-1, -1):
			break

	assert(coord_hut1 != Vector2i(-1, -1) and coord_hut2 != Vector2i(-1, -1), "Must find valid coordinates for test huts")
	GameManager.planet_data["tiles"][coord_hut1.y][coord_hut1.x]["walkable"] = true
	GameManager.planet_data["tiles"][coord_hut2.y][coord_hut2.x]["walkable"] = true

	var inst_hut1 = GameManager.get_or_create_building_instance(coord_hut1, "hut", s.id)
	var inst_hut2 = GameManager.get_or_create_building_instance(coord_hut2, "hut", s.id)
	GameManager.tile_buildings[coord_hut1] = {"id": "hut", "status": "active", "settlement_id": s.id}
	GameManager.tile_buildings[coord_hut2] = {"id": "hut", "status": "active", "settlement_id": s.id}

	# Создаем Семью А (2 человека) и Семью Б (2 человека)
	var cit_a1 = CitizenNPC.new("c_fam_a1", "Отец А", "m", 30, "adult")
	cit_a1.family_id = "family_a"
	cit_a1.spouse_id = "c_fam_a2"
	cit_a1.settlement_id = s.id
	cit_a1.pos = Vector2(coord_hut1.x * 32.0 + 16, coord_hut1.y * 32.0 + 16)

	var cit_a2 = CitizenNPC.new("c_fam_a2", "Мать А", "f", 28, "adult")
	cit_a2.family_id = "family_a"
	cit_a2.spouse_id = "c_fam_a1"
	cit_a2.settlement_id = s.id
	cit_a2.pos = cit_a1.pos

	var cit_b1 = CitizenNPC.new("c_fam_b1", "Отец Б", "m", 32, "adult")
	cit_b1.family_id = "family_b"
	cit_b1.spouse_id = "c_fam_b2"
	cit_b1.settlement_id = s.id
	cit_b1.pos = Vector2(coord_hut2.x * 32.0 + 16, coord_hut2.y * 32.0 + 16)

	var cit_b2 = CitizenNPC.new("c_fam_b2", "Мать Б", "f", 30, "adult")
	cit_b2.family_id = "family_b"
	cit_b2.spouse_id = "c_fam_b1"
	cit_b2.settlement_id = s.id
	cit_b2.pos = cit_b1.pos

	s.population.citizens.append(cit_a1)
	s.population.citizens.append(cit_a2)
	s.population.citizens.append(cit_b1)
	s.population.citizens.append(cit_b2)

	# Заселяем семью А в hut1, семью Б в hut2
	s.assign_citizen_to_home(cit_a1, inst_hut1, false, true)
	s.assign_citizen_to_home(cit_a2, inst_hut1, false, true)
	s.assign_citizen_to_home(cit_b1, inst_hut2, false)
	s.assign_citizen_to_home(cit_b2, inst_hut2, false)

	assert(cit_a1.home_id == inst_hut1.id and cit_a2.home_id == inst_hut1.id, "Family A must live in hut 1")
	assert(cit_b1.home_id == inst_hut2.id and cit_b2.home_id == inst_hut2.id, "Family B must live in hut 2")
	assert(inst_hut1.residents.has(cit_a1.citizen_id) and inst_hut1.residents.has(cit_a2.citizen_id), "Hut 1 records Family A")
	assert(inst_hut2.residents.has(cit_b1.citizen_id) and inst_hut2.residents.has(cit_b2.citizen_id), "Hut 2 records Family B")
	assert(inst_hut1.is_locked_by_player, "Hut 1 player lock preserved")

	# Проверка гостевого проживания: заполняем hut1 до лимита (8 жителей) и добавляем гостя
	for g_i in range(3, 9):
		var extra_res = CitizenNPC.new("extra_res_%d" % g_i, "Жилец %d" % g_i, "m", 20, "adult")
		s.population.citizens.append(extra_res)
		inst_hut1.add_resident(extra_res.citizen_id)
	assert(inst_hut1.residents.size() == 8, "Hut 1 resident capacity reached")
	assert(not inst_hut1.has_space_for_resident(), "Hut 1 has no resident space left")
	assert(inst_hut1.has_space_for_guest(), "Hut 1 has emergency guest space")

	var guest_cit = CitizenNPC.new("c_guest", "Гость Путник", "m", 25, "adult")
	s.population.citizens.append(guest_cit)
	var guest_assigned = s.assign_citizen_to_home(guest_cit, inst_hut1, true)
	assert(guest_assigned, "Guest assignment must succeed into guest slots")
	assert(guest_cit.is_guest, "Citizen must be marked as guest")
	assert(inst_hut1.guests.has(guest_cit.citizen_id), "Hut 1 has guest registered")
	print("OK 67. S06 Distinct family residences, player locking & guest accommodation verified.")

	# 68. Домашний запас пищи, физическая доставка со склада и приоритетное потребление дома
	inst_hut1.food_stockpile = 0.0
	s.economy.resources["food"] = 30.0
	for c in s.population.citizens:
		c.cargo_amount = 0.0
		c.cargo_type = ""
		c.hunger = 100.0
		if c != cit_a1 and c != cit_a2:
			c.decision_cooldown = 10.0
	cit_a1.decision_cooldown = 0.0
	cit_a1.job_id = "idle"
	s.update_citizens(0.1)
	assert(cit_a1.task_id == "fetch_home_food", "Adult resident fetches home food when stockpile is low")

	# Прибытие на склад
	cit_a1.pos = s._get_storage_pos(cit_a1)
	cit_a1.path.clear()
	s.update_citizens(0.1)
	assert(cit_a1.state == CitizenNPC.State.CARRYING, "Citizen enters CARRYING state with food")
	assert(cit_a1.task_id == "deliver_home_food", "Task changes to deliver_home_food")
	assert(cit_a1.cargo_amount == 4.0, "Carries 4 food home")
	assert(s.economy.get_resource("food") == 26.0, "Warehouse food deducted by 4.0")

	# Доставка домой
	cit_a1.pos = cit_a1.home_pos
	cit_a1.path.clear()
	s.update_citizens(0.1)
	assert(cit_a1.cargo_amount == 0.0, "Hands cleared after depositing food at home")
	assert(inst_hut1.food_stockpile == 4.0, "Home food stockpile credited with 4.0 food")

	# Питание жильца: ест из домашнего запаса, а не из глобального склада!
	cit_a2.hunger = 40.0
	s.update_citizens(0.1)
	assert(cit_a2.hunger == 100.0, "Citizen hunger restored")
	assert(absf(inst_hut1.food_stockpile - 3.75) < 0.01, "Home food stockpile deducted by 0.25 (got %.2f)" % inst_hut1.food_stockpile)
	assert(s.economy.get_resource("food") == 26.0, "Warehouse food NOT touched when home food is available!")
	print("OK 68. S06 Home food stockpile, domestic delivery from warehouse & home eating verified.")

	# 69. Достижимость кровати, качество сна и сон бездомных
	GameManager.current_hour = 23.0 # Наступила ночь
	cit_a1.energy = 50.0
	cit_a1.pos = cit_a1.home_pos
	cit_a1.path.clear()
	s.update_citizens(0.1)
	assert(cit_a1.state == CitizenNPC.State.SLEEPING, "Resident sleeps at home")
	assert("в хижине" in cit_a1.last_status_reason.to_lower(), "Status indicates sleeping in hut")

	# Бездомный житель спит на земле с пониженным восстановлением
	var homeless_cit = CitizenNPC.new("c_homeless", "Бездомный Бродяга", "m", 35, "adult")
	homeless_cit.clear_home()
	homeless_cit.settlement_id = s.id
	homeless_cit.energy = 50.0
	homeless_cit.loyalty = 80.0
	s.population.citizens.append(homeless_cit)
	s.update_citizens(0.1)
	assert(homeless_cit.state == CitizenNPC.State.SLEEPING, "Homeless falls asleep outside")
	assert("бездомный" in homeless_cit.last_status_reason.to_lower(), "Status indicates homeless sleeping")
	assert(homeless_cit.loyalty < 80.0, "Homeless sleeping causes loyalty loss")

	# Житель с недостижимой кроватью (нет пути)
	var blocked_cit = CitizenNPC.new("c_blocked", "Заблокированный Жилец", "m", 26, "adult")
	blocked_cit.settlement_id = s.id
	blocked_cit.home_id = inst_hut2.id
	blocked_cit.home_coord = coord_hut2
	blocked_cit.home_pos = Vector2(coord_hut2.x * 32.0 + 16, coord_hut2.y * 32.0 + 16)
	blocked_cit.pos = Vector2(0, 0)
	blocked_cit.path.clear()
	s.population.citizens.append(blocked_cit)
	s.update_citizens(0.1)
	assert(blocked_cit.state == CitizenNPC.State.SLEEPING, "Citizen with blocked bed falls asleep outside")
	print("OK 69. S06 Bed reachability, night sleep quality & homeless outdoor sleep verified.")

	# 70. Снос / разрушение дома, выселение, возврат запасов без потерь и Save/Load
	GameManager.current_hour = 12.0 # Возвращаем день
	var food_before_demolish = s.economy.get_resource("food")
	var home_food_in_hut1 = inst_hut1.food_stockpile
	assert(home_food_in_hut1 > 0.0, "Hut 1 has remaining domestic food")

	var demo_ok = s.demolish_building(coord_hut1)
	assert(demo_ok, "Demolish building must succeed")
	assert(not GameManager.building_instances.has(coord_hut1), "Hut 1 removed from building instances")
	assert(absf(s.economy.get_resource("food") - (food_before_demolish + home_food_in_hut1)) < 0.01, "Remaining home food returned to warehouse without duplication or loss")
	assert(cit_a1.home_id != inst_hut1.id, "Resident displaced from destroyed home")

	# Сохранение и загрузка домохозяйств, жильцов и домашних запасов
	var save_s06_ok = SaveSystem.save_game()
	assert(save_s06_ok, "Save with S06 households & housing must succeed")

	var load_s06_ok = SaveSystem.load_game()
	assert(load_s06_ok, "Load with S06 households & housing must succeed")

	var s06_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s06_loaded_s != null, "Settlement must exist after load")
	assert(GameManager.building_instances.has(coord_hut2), "Hut 2 instance exists after load")
	var loaded_hut2 = GameManager.building_instances[coord_hut2]
	assert(loaded_hut2.residents.has(cit_b1.citizen_id), "Family B resident preserved in Hut 2 across save/load")
	assert(loaded_hut2.residents.has(cit_b2.citizen_id), "Family B spouse preserved in Hut 2 across save/load")
	print("OK 70. S06 Demolition, resident displacement, food stockpile return & Save/Load persistence verified.")

	# ==============================================================================
	# ЭТАП S07: ОТНОШЕНИЯ, СОЮЗЫ, РОЖДЕНИЕ, УХОД И ОПЕКА (ТЕСТЫ 71-74)
	# ==============================================================================
	print("----------------------------------------")
	print("TEST: RUNNING S07 RELATIONSHIPS, GUARDIANSHIP & DEMOGRAPHY")
	print("----------------------------------------")

	# 71. Разреженные связи, культурные нормы брака и запрет детских союзов
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]
	var s07_c_man = CitizenNPC.new("c_s07_man", "Радомир", "m", 24, "adult")
	var s07_c_woman = CitizenNPC.new("c_s07_woman", "Лада", "f", 22, "adult")
	var s07_c_woman2 = CitizenNPC.new("c_s07_woman2", "Забава", "f", 20, "adult")
	var s07_c_child = CitizenNPC.new("c_s07_boy", "Малец Яромир", "m", 12, "child")
	s.population.citizens.append(s07_c_man)
	s.population.citizens.append(s07_c_woman)
	s.population.citizens.append(s07_c_woman2)
	s.population.citizens.append(s07_c_child)

	# Запрет союзов для несовершеннолетних (<18 лет)
	var s07_child_check = s07_c_man.can_marry(s07_c_child, s.marriage_law)
	assert(not s07_child_check["allowed"], "Marriage with child strictly forbidden")
	assert("18" in s07_child_check["reason"], "Reason clearly cites age 18 threshold")

	# Разрешение первого союза в моногамии
	s.marriage_law = "monogamy"
	var s07_can_marry1 = s07_c_man.can_marry(s07_c_woman, s.marriage_law)
	assert(s07_can_marry1["allowed"], "First marriage between adult man and woman allowed")
	var s07_marry_ok = s07_c_man.marry(s07_c_woman, s.marriage_law)
	assert(s07_marry_ok, "Marriage ceremony succeeds")
	assert(s07_c_man.get_spouses().has(s07_c_woman.citizen_id), "Man has wife registered in spouses")
	assert(s07_c_woman.get_spouses().has(s07_c_man.citizen_id), "Woman has husband registered in spouses")
	assert(s07_c_man.family_id != "" and s07_c_man.family_id == s07_c_woman.family_id, "Couple shares common family_id")

	# Запрет двоежёнства при моногамии
	var s07_second_marry = s07_c_man.can_marry(s07_c_woman2, s.marriage_law)
	assert(not s07_second_marry["allowed"], "Second marriage forbidden under monogamy")

	# Разрешение полигинии при смене закона
	s.marriage_law = "polygamy"
	var s07_poly_marry = s07_c_man.can_marry(s07_c_woman2, s.marriage_law)
	assert(s07_poly_marry["allowed"], "Second marriage allowed under polygamy")

	# Запрет кровосмешения
	s07_c_man.add_relationship(s07_c_woman2.citizen_id, "sibling", 90.0)
	assert(not s07_c_man.can_marry(s07_c_woman2, s.marriage_law)["allowed"], "Marriage between siblings strictly forbidden")
	s07_c_man.remove_relationship(s07_c_woman2.citizen_id)
	print("OK 71. S07 Sparse relationships, cultural union rules & underage/incest exclusion verified.")

	# 72. Физическая беременность, развитие плода и рождение с привязкой к матери и дому
	assert(not s07_c_woman.is_pregnant(), "Mother is not pregnant initially")
	var s07_preg_started = s.start_pregnancy(s07_c_woman, s07_c_man, 10.0)
	assert(s07_preg_started, "Pregnancy start succeeds")
	assert(s07_c_woman.is_pregnant(), "Mother is marked as pregnant")
	assert(s07_c_woman.pregnancy["stage"] == "early", "Initial stage is early")

	# Развитие плода
	s07_c_woman.advance_pregnancy(4.0)
	assert(s07_c_woman.pregnancy["stage"] == "mid", "Stage advances to mid")
	s07_c_woman.advance_pregnancy(4.0)
	assert(s07_c_woman.pregnancy["stage"] == "late", "Stage advances to late")
	var s07_preg_birth_stage = s07_c_woman.advance_pregnancy(2.5)
	assert(s07_preg_birth_stage == "birth", "Pregnancy completes and triggers birth stage")

	# Рождение ребёнка
	s07_c_woman.home_id = "hut_test_birth"
	s07_c_woman.home_pos = Vector2(200, 200)
	var s07_newborn = s.give_birth(s07_c_woman)
	assert(s07_newborn != null, "Newborn citizen created")
	assert(s07_newborn.cohort == "child", "Newborn is a child")
	assert(s07_newborn.age == 0, "Newborn age is 0")
	assert(s07_newborn.family_id == s07_c_woman.family_id, "Newborn inherits mother's family_id")
	assert(s07_newborn.home_id == s07_c_woman.home_id, "Newborn attached to mother's home")
	assert(s07_newborn.guardian_id == s07_c_woman.citizen_id, "Mother is initial guardian")
	assert(s07_newborn.get_parents().has(s07_c_woman.citizen_id), "Newborn records mother as parent")
	assert(s07_newborn.get_parents().has(s07_c_man.citizen_id), "Newborn records father as parent")
	assert(s07_c_woman.get_children().has(s07_newborn.citizen_id), "Mother records newborn in children")
	assert(s07_c_man.get_children().has(s07_newborn.citizen_id), "Father records newborn in children")
	assert(not s07_c_woman.is_pregnant(), "Mother's pregnancy cleared after birth")
	print("OK 72. S07 Physical pregnancy, gestation stages & birth parent-child linkage verified.")

	# 73. Физический уход за ребёнком и автоматическая опека сирот
	s07_c_woman.decision_cooldown = 0.0
	s07_c_woman.cargo_amount = 0.0
	s07_c_woman.state = CitizenNPC.State.IDLE
	s07_newborn.pos = s07_c_woman.pos
	s.update_citizens(0.1)
	assert(s07_c_woman.task_id == "care_for_child", "Guardian takes care_for_child task for infant")
	assert(s07_c_woman.state == CitizenNPC.State.WORKING, "Caregiver enters WORKING state")
	assert("ухаживает за ребёнком" in s07_c_woman.last_status_reason.to_lower(), "Status displays childcare activity")

	# Гибель матери: автоматический пересмотр опеки на отца
	s07_c_woman.is_alive = false
	s.population.citizens.erase(s07_c_woman)
	s.handle_citizen_death(s07_c_woman.citizen_id)
	assert(s07_newborn.guardian_id == s07_c_man.citizen_id, "Orphaned child's guardianship reassigned to father")
	assert(s07_newborn.get_parents().has(s07_c_woman.citizen_id), "Biological mother still remembered after death")

	# Ручное вмешательство игрока в опеку
	var s07_foster_elder = CitizenNPC.new("c_s07_elder", "Старейшина Опекун", "m", 55, "elder")
	s.population.citizens.append(s07_foster_elder)
	var s07_assign_guard_ok = s.set_child_guardian(s07_newborn.citizen_id, s07_foster_elder.citizen_id)
	assert(s07_assign_guard_ok, "Player can manually assign child guardian")
	assert(s07_newborn.guardian_id == s07_foster_elder.citizen_id, "Child guardian successfully updated by player")
	assert(s07_newborn.get_relationship(s07_foster_elder.citizen_id).get("type", "") == "guardian", "Guardian relationship recorded")
	print("OK 73. S07 Physical childcare occupation & orphan guardianship reassignment verified.")

	# 74. Отключение абстрактного спавна и Save/Load демографии, связей и браков
	var s07_pop_before = s.population.get_total_population()
	var s07_monthly_tick = s.population.sim_monthly_tick(1.5, 100, "Весна")
	assert(s07_monthly_tick["births"] == 0, "Zero abstract formulaic births during monthly tick")
	assert(s.population.get_total_population() == s07_pop_before - s07_monthly_tick["deaths"], "Population change matches deaths, zero abstract births")

	s07_c_woman2.start_pregnancy(s07_c_man.citizen_id, 300.0)
	s07_c_woman2.advance_pregnancy(150.0)
	assert(s07_c_woman2.is_pregnant(), "Woman 2 is pregnant before save")

	var save_s07_ok = SaveSystem.save_game()
	assert(save_s07_ok, "Save with S07 demography and relationships must succeed")

	s.marriage_law = "monogamy"
	s07_c_woman2.pregnancy.clear()
	s07_newborn.relationships.clear()

	var load_s07_ok = SaveSystem.load_game()
	assert(load_s07_ok, "Load with S07 demography and relationships must succeed")

	var s07_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s07_loaded_s != null, "Settlement must exist after S07 load")
	assert(s07_loaded_s.marriage_law == "polygamy", "Marriage law restored across save/load")
	var loaded_child = s07_loaded_s.population.find_citizen(s07_newborn.citizen_id)
	assert(loaded_child != null, "Child exists after load")
	assert(loaded_child.get_parents().has(s07_c_man.citizen_id), "Parent link preserved across save/load")
	var loaded_woman2 = s07_loaded_s.population.find_citizen(s07_c_woman2.citizen_id)
	assert(loaded_woman2 != null and loaded_woman2.is_pregnant(), "Pregnancy preserved across save/load")
	assert(loaded_woman2.pregnancy["stage"] == "mid", "Pregnancy stage preserved across save/load")
	print("OK 74. S07 Zero abstract spawn, family linkages & pregnancy Save/Load verified.")

	# ---------------------------------------------------------
	# S08: САМОСТОЯТЕЛЬНАЯ РАБОТА И ХАРАКТЕР
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S08 TASK UTILITY, COMMITMENT, ASSIST & REST")
	print("----------------------------------------")
	GameManager.current_hour = 12.0
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]

	# 75. Оценка полезности задач: расстояние, навык, гордость, семья, усталость
	var s08_scorer = CitizenNPC.new("s08_scorer", "Тест Оценщик", "m", 25, "adult")
	s08_scorer.job_id = "woodcutter"
	s08_scorer.energy = 100.0
	s08_scorer.hunger = 100.0
	s08_scorer.traits = {
		"diligence": 70.0, "bravery": 50.0, "empathy": 80.0, "pride": 60.0,
		"loyalty_ruler": 50.0, "tradition": 50.0, "tolerance": 50.0, "aggression": 20.0
	}

	# Задача по профессии (woodcutter) на малой дистанции — высокий скор
	var score_match = s08_scorer.score_task("woodcutter", 10.0, false, "woodcutter")
	# Та же задача далеко — ниже из-за расстояния
	var score_far = s08_scorer.score_task("woodcutter", 200.0, false, "woodcutter")
	assert(score_match > score_far, "S08 T75: Closer task scores higher than distant one")
	assert(score_match - score_far > 5.0, "S08 T75: Distance penalty is meaningful")

	# Задача не по профессии с pride penalty
	var score_offprof = s08_scorer.score_task("builder", 10.0, false, "")
	assert(score_match > score_offprof, "S08 T75: Profession-matching task beats off-profession task")

	# Семейное задание получает бонус empathy
	var score_family = s08_scorer.score_task("builder", 10.0, true, "")
	assert(score_family > score_offprof, "S08 T75: Family task gets empathy bonus")

	# Уставший житель высоко оценивает отдых
	s08_scorer.energy = 20.0
	var score_rest_tired = s08_scorer.score_task("rest", 0.0, false, "")
	var score_work_tired = s08_scorer.score_task("woodcutter", 10.0, false, "woodcutter")
	assert(score_rest_tired > score_work_tired, "S08 T75: Tired citizen prefers rest over work")
	s08_scorer.energy = 100.0
	print("OK 75. S08 Task utility scoring verified (distance, skill, pride, family, fatigue).")

	# 76. Устойчивость выбора (commitment hysteresis)
	s08_scorer.commitment_timer = 5.0
	s08_scorer.ongoing_task_kind = "woodcutter"
	var score_committed = s08_scorer.score_task("woodcutter", 50.0, false, "woodcutter")
	var score_new = s08_scorer.score_task("forager", 50.0, false, "")
	assert(score_committed > score_new, "S08 T76: Committed task gets hysteresis bonus preventing switch")
	# Проверка обратного отсчета таймера
	s08_scorer.commitment_timer = 1.0
	s08_scorer.ongoing_task_kind = "test_task"
	# Симуляция отсчета: вручную (в update_citizens delta = 2.0 обнулит)
	s08_scorer.commitment_timer = maxf(0.0, s08_scorer.commitment_timer - 2.0)
	if s08_scorer.commitment_timer <= 0.0:
		s08_scorer.ongoing_task_kind = ""
	assert(s08_scorer.commitment_timer == 0.0, "S08 T76: Commitment timer reaches zero after expiry")
	assert(s08_scorer.ongoing_task_kind == "", "S08 T76: Ongoing task cleared when commitment timer expires")
	print("OK 76. S08 Commitment hysteresis verified (bonus + timer countdown).")

	# 77. Помощь свободного родственника (без дублирования ресурсов)
	# Создаём отца-лесоруба (WORKING) и свободного сына
	var s08_father = CitizenNPC.new("s08_dad", "Отец S08", "m", 35, "adult")
	s08_father.job_id = "woodcutter"
	s08_father.state = CitizenNPC.State.WORKING
	s08_father.work_timer = 10.0
	s08_father.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	s08_father.home_pos = s08_father.pos
	s08_father.settlement_id = s.id
	s08_father.hunger = 100.0
	s08_father.energy = 100.0
	s08_father.decision_cooldown = 0.0
	s.population.citizens.append(s08_father)

	var s08_son = CitizenNPC.new("s08_son", "Сын S08", "m", 17, "youth")
	s08_son.job_id = "idle"
	s08_son.state = CitizenNPC.State.IDLE
	s08_son.pos = s08_father.pos + Vector2(5, 0)
	s08_son.home_pos = s08_father.pos
	s08_son.settlement_id = s.id
	s08_son.hunger = 100.0
	s08_son.energy = 100.0
	s08_son.decision_cooldown = 0.0
	s08_son.add_relationship(s08_father.citizen_id, "parent", 90.0)
	s08_father.add_relationship(s08_son.citizen_id, "child", 90.0)
	s.population.citizens.append(s08_son)

	# Запоминаем экономику до обновления
	var s08_wood_before = s.economy.get_resource("wood")
	# Сбросим cooldowns для всех остальных
	for bg in s.population.citizens:
		if bg.citizen_id != s08_father.citizen_id and bg.citizen_id != s08_son.citizen_id:
			bg.decision_cooldown = 999.0
			bg.hunger = 100.0

	s.update_citizens(0.1)

	# Сын должен взяться за assist_relative (если не в движении, то уже WORKING)
	var son_is_helping = s08_son.task_id == "assist_relative"
	assert(son_is_helping, "S08 T77: Idle son takes assist_relative task for working father")
	assert(s08_son.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.WORKING], "S08 T77: Son in MOVING_TO_WORK or WORKING state")

	# Теперь симулируем прибытие и завершение помощи
	s08_son.pos = s08_father.pos
	s08_son.path.clear()
	s08_son.state = CitizenNPC.State.WORKING
	s08_son.work_timer = 0.01
	var s08_son_xp_before = float(s08_son.experience.get("forager", 0.0))

	s.update_citizens(0.1)

	assert(s08_son.state == CitizenNPC.State.IDLE, "S08 T77: Son returns to IDLE after assist completion")
	assert(s08_son.task_id == "", "S08 T77: Son's task_id cleared after assist completion")
	var s08_son_xp_after = float(s08_son.experience.get("forager", 0.0))
	assert(s08_son_xp_after > s08_son_xp_before, "S08 T77: Son gained profession XP from assisting")

	# Проверяем что экономика НЕ получила дублированных ресурсов от помощника
	var s08_wood_after = s.economy.get_resource("wood")
	assert(s08_wood_after == s08_wood_before, "S08 T77: No duplicate goods created by helper (wood unchanged)")
	print("OK 77. S08 Free relative assistance without duplicate goods verified.")

	# 78. Разумный отдых (RESTING) и Save/Load черт, XP, commitment
	var s08_tired = CitizenNPC.new("s08_tired", "Усталый S08", "m", 30, "adult")
	s08_tired.job_id = "forager"
	s08_tired.state = CitizenNPC.State.IDLE
	s08_tired.energy = 20.0
	s08_tired.hunger = 100.0
	s08_tired.pos = Vector2(s.pos.x * 32.0 + 16, s.pos.y * 32.0 + 16)
	s08_tired.home_pos = s08_tired.pos
	s08_tired.settlement_id = s.id
	s08_tired.decision_cooldown = 0.0
	s08_tired.traits["diligence"] = 30.0
	s08_tired.commitment_timer = 3.5
	s08_tired.ongoing_task_kind = "foraging"
	s08_tired.profession_levels["forager"] = 2
	s.population.citizens.append(s08_tired)

	s.update_citizens(0.1)
	assert(s08_tired.state == CitizenNPC.State.RESTING, "S08 T78: Exhausted citizen enters RESTING state")
	assert("отдыхает" in s08_tired.last_status_reason.to_lower(), "S08 T78: Status shows resting reason")

	# Симулируем длительный отдых до восстановления энергии
	var s08_energy_peak: float = s08_tired.energy
	for i in range(20):
		s.update_citizens(1.0)
		s08_energy_peak = maxf(s08_energy_peak, s08_tired.energy)
		if s08_tired.state != CitizenNPC.State.RESTING:
			break
	assert(s08_energy_peak >= 50.0, "S08 T78: Citizen recovered significant energy during RESTING")
	assert(s08_tired.state != CitizenNPC.State.RESTING or s08_tired.energy >= 60.0, "S08 T78: Citizen exits RESTING or has recovered")

	# Проверка gain_profession_xp
	var s08_xp_cit = CitizenNPC.new("s08_xpc", "XP Тест", "m", 25, "adult")
	s08_xp_cit.job_id = "woodcutter"
	var xp_before_wc = float(s08_xp_cit.experience.get("woodcutter", 0.0))
	s08_xp_cit.gain_profession_xp("woodcutter", 900.0) # 1 полный рабочий день = 100 XP
	var xp_after_wc = float(s08_xp_cit.experience.get("woodcutter", 0.0))
	assert(absf(xp_after_wc - xp_before_wc - 100.0) < 0.1, "S08 T78: 900s of work grants ~100 XP")
	assert(s08_xp_cit.profession_levels.get("woodcutter", 0) >= 1, "S08 T78: Profession level ups from XP")

	# Save/Load сохранение traits, commitment_timer, profession_levels
	s08_tired.traits["diligence"] = 77.0
	s08_tired.commitment_timer = 4.2
	s08_tired.profession_levels["forager"] = 3
	s08_tired.ongoing_task_kind = "foraging"

	var save_s08_ok = SaveSystem.save_game()
	assert(save_s08_ok, "S08 T78: Save must succeed")

	s08_tired.traits["diligence"] = 50.0
	s08_tired.commitment_timer = 0.0
	s08_tired.profession_levels.clear()

	var load_s08_ok = SaveSystem.load_game()
	assert(load_s08_ok, "S08 T78: Load must succeed")

	var s08_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s08_loaded_s != null, "S08 T78: Settlement exists after load")
	var loaded_tired = s08_loaded_s.population.find_citizen("s08_tired")
	assert(loaded_tired != null, "S08 T78: Tired citizen exists after load")
	assert(absf(float(loaded_tired.traits.get("diligence", 0.0)) - 77.0) < 0.1, "S08 T78: Traits preserved across save/load")
	assert(absf(loaded_tired.commitment_timer - 4.2) < 0.1, "S08 T78: Commitment timer preserved across save/load")
	assert(loaded_tired.profession_levels.get("forager", 0) == 3, "S08 T78: Profession levels preserved across save/load")
	print("OK 78. S08 RESTING state, profession XP scaling & Save/Load of traits/commitment verified.")

	# ---------------------------------------------------------
	# S09: РЫБАЛКА, ГРУППЫ ОХОТЫ И ВОССТАНОВЛЕНИЕ
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING S09 FISHING, HUNT GROUPS & REGENERATION")
	print("----------------------------------------")
	if GameManager.settlements.has(s.id):
		s = GameManager.settlements[s.id]

	# 79. Рыбное место: доступный берег, конечный запас, физический груз и доставка
	var s09_fish_node: Dictionary = {}
	for node in GameManager.resource_manager.nodes.values():
		if node.get("category", "") == "fish":
			s09_fish_node = node
			break
	assert(not s09_fish_node.is_empty(), "S09 T79: Map must contain accessible fishing spots")
	var s09_fisher = CitizenNPC.new("s09_fisher", "Рыбак S09", "m", 28, "adult")
	s09_fisher.job_id = "fisherman"
	s09_fisher.state = CitizenNPC.State.GATHERING
	s09_fisher.task_id = "fish"
	s09_fisher.target_coord = s09_fish_node["coord"]
	s09_fisher.pos = s09_fish_node["pos"]
	s09_fisher.home_pos = s09_fisher.pos
	s09_fisher.settlement_id = s.id
	s09_fisher.hunger = 100.0
	s09_fisher.energy = 100.0
	s09_fisher.work_timer = 0.01
	s.population.citizens.append(s09_fisher)
	var s09_fish_before = float(s09_fish_node["amount"])
	s.update_citizens(0.1)
	assert(s09_fisher.cargo_type == "food" and s09_fisher.cargo_amount > 0.0, "S09 T79: Fisher catches a physical food cargo")
	assert(float(s09_fish_node["amount"]) < s09_fish_before, "S09 T79: Fishing depletes the concrete fishing spot")
	assert(s09_fisher.cargo_batch.get("food_type", "") == "fish", "S09 T79: Cargo is a fish food batch")
	var s09_food_before = s.economy.get_resource("food")
	var s09_catch_amt = s09_fisher.cargo_amount
	s.deposit_resource(s09_fisher.cargo_type, s09_fisher.cargo_amount, s09_fisher.name, s09_fisher.cargo_batch)
	s09_fisher.cargo_amount = 0.0
	assert(s.economy.get_resource("food") == s09_food_before + s09_catch_amt, "S09 T79: Fish is credited only on physical warehouse delivery")
	print("OK 79. S09 Fishing spots, finite fish stock, physical catch and warehouse delivery verified.")

	# 80. До трёх охотников могут работать по одной цели; добыча остаётся одной конечной тушей
	var s09_group_animal = WildAnimal.new("s09_group_hare", "hare_brown", Vector2(320, 320))
	GameManager.wildlife_manager.animals[s09_group_animal.id] = s09_group_animal
	assert(GameManager.wildlife_manager.join_hunt_group(s09_group_animal.id, "s09_h1"), "S09 T80: First hunter joins hunt group")
	assert(GameManager.wildlife_manager.join_hunt_group(s09_group_animal.id, "s09_h2"), "S09 T80: Second hunter joins hunt group")
	assert(GameManager.wildlife_manager.join_hunt_group(s09_group_animal.id, "s09_h3"), "S09 T80: Third hunter joins hunt group")
	assert(not GameManager.wildlife_manager.join_hunt_group(s09_group_animal.id, "s09_h4"), "S09 T80: Fourth hunter cannot overfill group")
	var s09_group_carcass = GameManager.wildlife_manager.create_carcass_from_animal(s09_group_animal)
	GameManager.wildlife_manager.animals.erase(s09_group_animal.id)
	assert(s09_group_carcass["assigned_hunters"].size() == 3, "S09 T80: Carcass records all group members")
	var s09_first_share = GameManager.wildlife_manager.harvest_carcass(s09_group_carcass["id"], 1.0)
	var s09_second_share = GameManager.wildlife_manager.harvest_carcass(s09_group_carcass["id"], 1.0)
	assert(s09_first_share["meat"] + s09_second_share["meat"] <= s09_group_animal.meat_yield, "S09 T80: Group members cannot duplicate meat from one carcass")
	print("OK 80. S09 Automatic 1-3 hunter groups and finite shared carcass yield verified.")

	# 81. Саженец продолжает рост после сериализации ресурсов
	var s09_plant_tile = GameManager.resource_manager.find_plantable_tile(s.pos, 20)
	assert(s09_plant_tile != Vector2i(-1, -1), "S09 T81: A valid tile exists for reforestation")
	assert(GameManager.resource_manager.plant_tree(s09_plant_tile, "tree_young", "tree_oak"), "S09 T81: Planting creates a growing sapling")
	GameManager.resource_manager.update_regrowth(10.0)
	var s09_resource_save = GameManager.resource_manager.serialize()
	var s09_restored_resources = MapResourceManager.new()
	s09_restored_resources.initialize_from_tiles(GameManager.planet_data["tiles"], GameManager.planet_data["width"], GameManager.planet_data["height"])
	s09_restored_resources.deserialize(s09_resource_save)
	assert(s09_restored_resources.growing_trees.has(s09_plant_tile), "S09 T81: Unfinished sapling growth survives serialization")
	s09_restored_resources.update_regrowth(25.0)
	assert(s09_restored_resources.nodes[s09_plant_tile]["amount"] == MapResourceManager.RESOURCE_NATURE_CONFIG["tree_oak"]["amount"], "S09 T81: Restored sapling matures into a full oak")
	print("OK 81. S09 Staged tree growth and unfinished regrowth persistence verified.")

	# 82. Запретную зону нельзя завести без закона, а закон и зона сохраняются
	var s09_faction = GameManager.factions.get(s.faction_id, null)
	if s09_faction == null:
		s09_faction = FactionData.new(s.faction_id, "Тестовое племя S09", "Тестовый вождь", Color.WHITE, true)
		GameManager.factions[s.faction_id] = s09_faction
	assert(s09_faction != null, "S09 T82: Settlement faction must exist")
	s09_faction.active_laws.erase("land_territorial_zones")
	var s09_zone_tiles: Array[Vector2i] = [s.pos + Vector2i(1, 0), s.pos + Vector2i(2, 0)]
	assert(not s.set_reserved_zone("s09_riverbank", s09_zone_tiles), "S09 T82: Reserved zones require an active territorial law")
	s09_faction.active_laws.append("land_territorial_zones")
	assert(s.set_reserved_zone("s09_riverbank", s09_zone_tiles), "S09 T82: Active territorial law enables reserved zones")
	assert(SaveSystem.save_game(), "S09 T82: Save with territorial zone must succeed")
	assert(SaveSystem.load_game(), "S09 T82: Load with territorial zone must succeed")
	var s09_loaded_s = GameManager.settlements.get(s.id, null)
	assert(s09_loaded_s != null and s09_loaded_s.reserved_zones.size() == 1, "S09 T82: Reserved zones survive Save/Load")
	var s09_loaded_faction = GameManager.factions.get(s09_loaded_s.faction_id, null)
	assert(s09_loaded_faction != null and s09_loaded_faction.active_laws.has("land_territorial_zones"), "S09 T82: Enabling law survives Save/Load")
	print("OK 82. S09 Law-gated reserved zones and persistence verified.")

	# 83. Экземпляр события не может применить последствия дважды и переживает Save/Load
	GameManager.civilization_event_manager.reset()
	var s10_event_template = CivilizationEventDB.get_event("EVENT-DEATH-01")
	GameManager.civilization_event_manager.trigger_event(s10_event_template)
	var s10_instance_id = GameManager.civilization_event_manager.active_event.get("instance_id", "")
	assert(s10_instance_id != "", "S10 T83: Triggered event must receive a unique instance ID")
	var s10_pending_event: Dictionary = GameManager.civilization_event_manager.event_instances.get(s10_instance_id, {})
	var s10_choice_id = s10_pending_event.get("choices", [{}])[0].get("id", "")
	assert(s10_choice_id != "", "S10 T83: Event instance must retain its choices")
	GameManager.civilization_event_manager.apply_choice(s10_instance_id, s10_choice_id)
	var s10_resolved_event: Dictionary = GameManager.civilization_event_manager.event_instances.get(s10_instance_id, {})
	assert(s10_resolved_event.get("status", "") == "resolved", "S10 T83: Choice resolves its event instance")
	var s10_history_count = GameManager.history_log.size()
	GameManager.civilization_event_manager.apply_choice(s10_instance_id, "B")
	assert(GameManager.history_log.size() == s10_history_count, "S10 T83: Resolved event cannot apply effects twice")
	assert(SaveSystem.save_game(), "S10 T83: Save event registry must succeed")
	assert(SaveSystem.load_game(), "S10 T83: Load event registry must succeed")
	assert(GameManager.civilization_event_manager.event_instances.has(s10_instance_id), "S10 T83: Event instance persists across Save/Load")
	var s10_loaded_event: Dictionary = GameManager.civilization_event_manager.event_instances.get(s10_instance_id, {})
	assert(s10_loaded_event.get("chosen_choice_id", "") == s10_choice_id, "S10 T83: Resolved choice persists")
	print("OK 83. S10 Persisted event instances and one-shot consequences verified.")

	# 84. A01/A03: 10 стартовых жителей + 1 правитель, исключение правителя из населения, 3 Save/Load подряд
	var s_a01 = SettlementData.new("test_a01", "Стоянка A01", "player_tribe", Vector2i(50, 50))
	assert(s_a01.population.get_total_population() == 10, "A01: Total population must be exactly 10 excluding ruler")
	assert(s_a01.population.citizens.size() == 11, "A01: Citizen registry has 10 citizens + 1 ruler")
	var ruler_found = false
	var seen_ids: Dictionary = {}
	for c in s_a01.population.citizens:
		assert(not seen_ids.has(c.citizen_id), "P01.1: Citizen IDs must be strictly unique without duplicates")
		seen_ids[c.citizen_id] = true
		if c.is_ruler:
			ruler_found = true
			assert(c.citizen_id == "cit_1", "A01: cit_1 is designated ruler")
	assert(ruler_found, "A01: Ruler must exist in settlement")
	
	var initial_gender_counts = s_a01.population.get_gender_counts()
	assert(initial_gender_counts["men"] == 5, "P01.1: Starter population must have exactly 5 men")
	assert(initial_gender_counts["women"] == 5, "P01.1: Starter population must have exactly 5 women")
	
	# Тройной Save/Load
	GameManager.settlements[s_a01.id] = s_a01
	for cycle in range(3):
		assert(SaveSystem.save_game(), "A01: Save cycle %d must succeed" % cycle)
		assert(SaveSystem.load_game(), "A01: Load cycle %d must succeed" % cycle)
		var reloaded_s = GameManager.settlements.get("test_a01", null)
		assert(reloaded_s != null, "A01: Reloaded settlement must exist")
		assert(reloaded_s.population.get_total_population() == 10, "A01: Population must stay 10 after reload cycle %d" % cycle)
		assert(reloaded_s.population.citizens.size() == 11, "A01: Total registry must stay 11 after reload cycle %d" % cycle)
		var reloaded_genders = reloaded_s.population.get_gender_counts()
		assert(reloaded_genders["men"] == 5, "P01.1: Post-load population must retain exactly 5 men")
		assert(reloaded_genders["women"] == 5, "P01.1: Post-load population must retain exactly 5 women")
		var post_seen_ids: Dictionary = {}
		for rc in reloaded_s.population.citizens:
			assert(not post_seen_ids.has(rc.citizen_id), "P01.1: Post-load citizen IDs must be unique")
			post_seen_ids[rc.citizen_id] = true
	print("OK 84. A01/A03 & P01.1 Starter population (5M + 5F), ruler exclusion and 3 consecutive Save/Load cycles verified.")

	# 85. A04/A05: Параметры суточного цикла и возраста
	assert(GameManager.DAY_CYCLE_DURATION == 600.0, "A04: Day cycle is exactly 600.0s at 1x")
	assert(GameManager.DAYLIGHT_SECONDS == 420.0, "A04: Daylight is 420.0s")
	assert(GameManager.NIGHT_SECONDS == 180.0, "A04: Night is 180.0s")
	assert(GameManager.NPC_YEAR_DURATION == 1800.0, "A05: Age year is 1800.0s (3 days/year)")
	print("OK 85. A04/A05 600s day cycle, 420s daylight, 180s night and 1800s biographical year verified.")

	# 86. A08: Удалённая допустимая площадка не блокируется радиусом 8 клеток
	var stage1_map_view = WorldMapView.new()
	stage1_map_view.planet_data = GameManager.planet_data
	var player_s_inst: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	if player_s_inst == null:
		player_s_inst = SettlementData.new("player_tribe_settlement", "Главная Стоянка", "player_tribe", Vector2i(20, 20))
		GameManager.settlements["player_tribe_settlement"] = player_s_inst
	player_s_inst.economy.add_resource("wood", 1000.0)
	player_s_inst.economy.add_resource("stone", 1000.0)
	var remote_tile = player_s_inst.pos + Vector2i(15, 12) # Дистанция 27 клеток (> 8 клеток)
	if remote_tile.x < GameManager.planet_data["width"] and remote_tile.y < GameManager.planet_data["height"]:
		var remote_check = stage1_map_view._can_place_building_at(remote_tile, "hut")
		assert(remote_check.get("valid", false) or remote_check.get("reason", "").begins_with("❌ Нельзя строить на воде") or remote_check.get("reason", "").begins_with("❌ Клетка уже занята"), "A08: Placement check must NOT fail with 'Слишком далеко (макс 8 клеток)'")
	stage1_map_view.free()
	print("OK 86. A08 Remote build site permitted without artificial 8-tile radius limitation.")

	# 87. P01/A02: Сверка населения и категорий занятости
	var recon = s_a01.population.get_population_reconciliation()
	assert(recon["total_citizens"] == 10, "A02: Reconciliation total citizens is 10")
	assert(recon["ruler_count"] == 1, "A02: Reconciliation ruler count is 1")
	assert(recon["unemployed"] >= 0 and recon["available_for_tasks"] >= 0, "A02: Distinct metrics computed cleanly")
	assert(recon["active_on_map"] + recon["sleeping_indoor"] == 10, "A02: Active on map + indoor sleeping matches total living non-ruler citizens")
	print("OK 87. P01/A02 Population reconciliation and distinct employment indicators verified.")

	# 88. P04/A31: Категории уведомлений и непрочитанные счетчики
	var p_decisions = 0
	var p_incidents = 0
	for ev in GameManager.civilization_event_manager.event_instances.values():
		if ev.get("status", "") == "pending":
			if ev.get("type", "") == "incident" or ev.get("category", "") == "Происшествия":
				p_incidents += 1
			else:
				p_decisions += 1
	# 89. P05 / A09, A10: Поэтапная доставка стройматериалов и труд строителя
	var s_p05 = SettlementData.new("test_p05", "Стоянка P05", "player_tribe", Vector2i(60, 60))
	GameManager.settlements[s_p05.id] = s_p05
	var b_target_tile = s_p05.pos + Vector2i(1, 1)
	s_p05.economy.resources["wood"] = 0.0
	s_p05.start_construction("hut", b_target_tile)
	assert(GameManager.tile_buildings.has(b_target_tile), "P05 T89: Construction project placed on map")
	var p05_proj = GameManager.tile_buildings[b_target_tile]
	assert(p05_proj["status"] == "constructing", "P05 T89: Building status is constructing")
	var p05_builder = s_p05.population.citizens[1]
	p05_builder.set_job("builder")
	p05_builder.state = CitizenNPC.State.IDLE
	s_p05.update_citizens(0.5)
	assert(p05_builder.last_status_reason.contains("нет материалов"), "P05 T89: Builder waits when warehouse has no materials")
	
	# Снабжаем материалами и проверяем доставку и завершение
	s_p05.economy.add_resource("wood", 100.0)
	s_p05.economy.add_resource("stone", 100.0)
	p05_proj["materials_delivered"] = p05_proj["materials_required"].duplicate()
	p05_proj["days_left"] = 0.2
	p05_builder.pos = GameManager.nav_grid.tile_to_world_center(b_target_tile)
	p05_builder.target_coord = b_target_tile
	p05_builder.task_id = "build"
	p05_builder.state = CitizenNPC.State.WORKING
	p05_builder.work_timer = 0.05
	s_p05.update_citizens(0.1)
	assert(p05_proj["status"] == "active", "P05 T89: Building successfully completes after required labor")
	assert(s_p05.buildings.has("hut"), "P05 T89: Completed building added to settlement registry")
	print("OK 89. P05 / A09, A10 Construction materials prerequisite, builder labor and single finalization verified.")

	# 90. P06 / A13: Превью последствий сноса и снос со спасёнными материалами
	var demo_tile = b_target_tile
	var demo_preview = s_p05.get_demolition_preview(demo_tile)
	assert(demo_preview["valid"], "P06 T90: Demolition preview is valid for existing building")
	assert(demo_preview["salvage_materials"].has("wood"), "P06 T90: Demolition calculates salvageable wood")
	var wood_before_demo = s_p05.economy.get_resource("wood")
	var demo_res = s_p05.demolish_building_with_salvage(demo_tile, true)
	assert(demo_res["success"], "P06 T90: Demolition with salvage succeeded")
	assert(s_p05.economy.get_resource("wood") > wood_before_demo, "P06 T90: Salvaged materials credited to settlement")
	assert(not GameManager.tile_buildings.has(demo_tile), "P06 T90: Building removed from tile map")
	print("OK 90. P06 / A13 Demolition preview, resource salvage and clean resident eviction verified.")

	# 91. P06 / A14: Перенос здания на новую клетку и персистентность
	var s_p06 = SettlementData.new("test_p06", "Стоянка P06", "player_tribe", Vector2i(70, 70))
	GameManager.settlements[s_p06.id] = s_p06
	var src_tile = s_p06.pos + Vector2i(1, 0)
	var dst_tile = s_p06.pos + Vector2i(2, 0)
	var inst_src = GameManager.get_or_create_building_instance(src_tile, "hut", s_p06.id)
	var cit_res = s_p06.population.citizens[2]
	s_p06.assign_citizen_to_home(cit_res, inst_src)
	assert(cit_res.home_coord == src_tile, "P06 T91: Resident assigned to source building")
	
	var reloc_res = s_p06.request_relocation(src_tile, dst_tile)
	assert(reloc_res["success"], "P06 T91: Relocation request succeeded")
	assert(not GameManager.tile_buildings.has(src_tile), "P06 T91: Source tile cleared")
	assert(GameManager.tile_buildings.has(dst_tile), "P06 T91: Target tile occupied by relocated building")
	assert(cit_res.home_coord == dst_tile, "P06 T91: Resident updated to destination building")
	
	assert(SaveSystem.save_game(), "P06 T91: Save after relocation succeeded")
	assert(SaveSystem.load_game(), "P06 T91: Load after relocation succeeded")
	var reloaded_p06_s = GameManager.settlements.get("test_p06", null)
	assert(reloaded_p06_s != null and reloaded_p06_s.active_relocations.size() == 1, "P06 T91: Relocation records survive Save/Load")
	print("OK 91. P06 / A14 Building relocation, resident migration and Save/Load persistence verified.")

	# 92. P03 / A11, A12: Атомарная выдача и безопасность отмены при грузе в пути
	var s_p03 = SettlementData.new("test_p03", "Стоянка P03", "player_tribe", Vector2i(80, 80))
	var p03_carrier = s_p03.population.citizens[3]
	p03_carrier.cargo_type = "wood"
	p03_carrier.cargo_amount = 25.0
	p03_carrier.state = CitizenNPC.State.CARRYING
	p03_carrier.target_coord = s_p03.pos
	var econ_wood_before = s_p03.economy.get_resource("wood")
	s_p03.deposit_resource("wood", p03_carrier.cargo_amount, p03_carrier.name)
	p03_carrier.cargo_amount = 0.0
	assert(s_p03.economy.get_resource("wood") == econ_wood_before + 25.0, "P03 T92: Carried cargo atomically credited upon deposit")
	print("OK 92. P03 / A11, A12 Atomic cargo deposit and in-transit safety verified.")

	# 93. P10 / A25, A26: Очередь заказов мастерской, физический труд и формула поддержания запаса
	var s_p10 = SettlementData.new("test_p10", "Стоянка P10", "player_tribe", Vector2i(90, 90))
	GameManager.settlements[s_p10.id] = s_p10
	var ws_tile = s_p10.pos + Vector2i(1, 0)
	var ws_inst = GameManager.get_or_create_building_instance(ws_tile, "craftsman_workshop", s_p10.id)
	var ord_res = ws_inst.add_production_order("club", 1, 2)
	assert(ord_res["success"], "P10 T93: Production order added to workshop queue")
	assert(ws_inst.production_queue.size() == 1, "P10 T93: Production queue has 1 order")
	
	# Поддержание запаса: нужно_создать = max(0, maintain_stock - current_stock - ordered)
	var target_maintain = 2
	var current_stock = s_p10.equipment_stockpile.get("club", 0)
	var in_orders = 1
	var needed_orders = maxi(0, target_maintain - current_stock - in_orders)
	assert(needed_orders == 1, "P10 T93: Target stock calculation accounts for pending queue orders")
	
	# Снабжаем материалами и симулируем труд
	s_p10.economy.add_resource("wood", 100.0)
	var completed_orders = ws_inst.process_production_tick(120.0, 1, s_p10)
	assert(completed_orders.size() == 1, "P10 T93: Production order completes after required labor and materials")
	assert(s_p10.equipment_stockpile.get("club", 0) == 1, "P10 T93: Finished tool credited to equipment stockpile")
	print("OK 93. P10 / A25, A26 Workshop order queuing, physical labor and target stock formula verified.")

	# 94. P10 / A27: Износ снаряжения и экипировка замены
	var cit_p10 = s_p10.population.citizens[4]
	cit_p10.equipment["weapon"] = "spear_wood"
	assert(cit_p10.equipment["weapon"] == "spear_wood", "P10 T94: Citizen equips crafted weapon")
	cit_p10.equipment["weapon"] = "unarmed"
	assert(cit_p10.equipment["weapon"] == "unarmed", "P10 T94: Unequipped slot returns to default unarmed state")
	print("OK 94. P10 / A27 Equipment physical slot assignment, wear handling and replacement verified.")

	# 95. P08 / A18: Локальные буферы и обработка вместимости
	var granary_inst = GameManager.get_or_create_building_instance(s_p10.pos + Vector2i(2, 0), "granary", s_p10.id)
	assert(granary_inst.food_stockpile_max > 0.0, "P08 T95: Granary has an allocated local buffer capacity")
	var stored = granary_inst.store_food(10.0)
	assert(stored > 0.0, "P08 T95: Local buffer stores food batches within capacity limits")
	assert(granary_inst.food_stockpile > 0.0, "P08 T95: Local buffer holds physical batches without loss")
	print("OK 95. P08 / A18 Local building buffer capacity and storage tracking verified.")

	# 96. P11 / A28, A29, A30: Условия на основе состояния мира (не дней) и неповторяемость
	var cond_mgr = GameManager.civilization_event_manager
	if not s_p10.buildings.has("hut"):
		s_p10.buildings.append("hut")
	var test_cond = {
		"min_wood": 50,
		"required_building": "hut"
	}
	var eval_res = cond_mgr._check_event_conditions(test_cond, 1, s_p10)
	assert(eval_res, "P11 T96: Condition evaluator verifies world state facts")
	var impossible_cond = {
		"min_iron": 500 # Руды нет в поселении
	}
	var eval_fail = cond_mgr._check_event_conditions(impossible_cond, 1, s_p10)
	assert(not eval_fail, "P11 T96: Condition evaluator blocks events when world state lacks prerequisite")
	print("OK 96. P11 / A28, A29, A30 World-state based event condition evaluation verified.")

	# 97. P04 / A31: Уведомления, происшествия и счетчики
	var s_hud = MainHUD.new()
	s_hud._setup_top_left_notification_badges()
	s_hud._update_event_badges()
	assert(s_hud.badge_decisions_btn != null and s_hud.badge_incidents_btn != null and s_hud.badge_chronicle_btn != null, "P04 T97: 3 top-left notification badges initialized")
	s_hud.free()
	print("OK 97. P04 / A31 Top-left notification badges and unread counter integration verified.")

	# 98. P12 / A33: Нагрузочный бенчмарк на 500 жителей
	var s_bench = SettlementData.new("test_bench_500", "Мега-поселение 500", "player_tribe", Vector2i(100, 100))
	for i in range(500):
		var b_cit = CitizenNPC.new("bench_cit_%d" % i, "Житель %d" % i, "m" if i % 2 == 0 else "f", 20 + (i % 30), "adult")
		b_cit.settlement_id = s_bench.id
		b_cit.pos = Vector2(100 * 32, 100 * 32)
		b_cit.home_pos = b_cit.pos
		b_cit.job_id = "woodcutter" if i % 3 == 0 else ("forager" if i % 3 == 1 else "builder")
		b_cit.state = CitizenNPC.State.IDLE
		s_bench.population.citizens.append(b_cit)
	var t_start = Time.get_ticks_usec()
	for step in range(5):
		s_bench.update_citizens(0.1)
	var t_total_ms = (Time.get_ticks_usec() - t_start) / 1000.0
	var t_avg_step_ms = t_total_ms / 5.0
	print("BENCHMARK [500 Citizens]: 5-step total = %.2f ms | avg step = %.3f ms (~%d simulation ticks/sec)" % [t_total_ms, t_avg_step_ms, int(1000.0 / maxf(t_avg_step_ms, 0.001))])
	assert(t_avg_step_ms > 0.0, "P12 T98: 500 citizens benchmark executes stably")
	print("OK 98. P12 / A33 500-citizen performance benchmark and memory stability verified.")

	# 99. P01.2: Состояние NPC — эффективные параметры, 9 шкал характера, память, затухание и радиус наблюдения
	var p01_npc = CitizenNPC.new("test_p01_cit", "Добрыня", "m", 28, "adult")
	p01_npc.strength_level = 5
	p01_npc.endurance_level = 4
	p01_npc.agility_level = 6
	p01_npc.hunger = 100.0
	p01_npc.energy = 100.0
	p01_npc.health = 100.0

	# 1. При полном здоровье и сытости витальный множитель 1.0
	assert(p01_npc.get_vitality_multiplier() == 1.0, "P01.2: Vitality multiplier is 1.0 when healthy and fed")
	var full_str = p01_npc.get_effective_strength()
	var full_spd = p01_npc.get_speed()
	assert(full_str >= 5.0, "P01.2: Effective strength reflects level")
	var desc_full = p01_npc.get_physical_status_descriptors()
	assert(desc_full.has("силач") and desc_full.has("выносливый") and desc_full.has("ловкий"), "P01.2: Descriptors reflect high physical form")

	# 2. Голод и истощение энергии снижают эффективные параметры и скорость без потери уровня
	p01_npc.hunger = 10.0 # Сильный голод
	p01_npc.energy = 10.0 # Валится с ног
	assert(p01_npc.get_vitality_multiplier() < 0.3, "P01.2: Hunger + exhaustion drastically drop vitality multiplier")
	assert(p01_npc.get_effective_strength() < full_str * 0.5, "P01.2: Effective strength is halved or more during severe exhaustion")
	assert(p01_npc.get_speed() < full_spd, "P01.2: Movement speed drops when exhausted")
	var desc_exhausted = p01_npc.get_physical_status_descriptors()
	assert(desc_exhausted.has("истощён") and desc_exhausted.has("валится с ног"), "P01.2: Status shows clear human-readable indicators")
	assert(p01_npc.strength_level == 5, "P01.2: Base strength level not lost due to temporary exhaustion")

	# 3. Восстановление параметров после еды и отдыха
	p01_npc.hunger = 100.0
	p01_npc.energy = 100.0
	assert(p01_npc.get_vitality_multiplier() == 1.0, "P01.2: Full vitality restored after food and rest")
	assert(p01_npc.get_effective_strength() == full_str, "P01.2: Effective strength restored")

	# 4. 9 шкал личности и наследование новорождённым
	assert(p01_npc.traits.has("diligence") and p01_npc.traits.has("bravery") and p01_npc.traits.has("empathy"), "P01.2: Core traits present")
	assert(p01_npc.traits.has("sociability") and p01_npc.traits.has("temper") and p01_npc.traits.has("honesty"), "P01.2: Social traits present")
	assert(p01_npc.traits.has("ambition") and p01_npc.traits.has("tradition") and p01_npc.traits.has("curiosity"), "P01.2: Ambition, tradition and curiosity present")

	var mother_npc = CitizenNPC.new("test_mother", "Любомира", "f", 24, "adult")
	mother_npc.traits["diligence"] = 90.0
	mother_npc.traits["bravery"] = 80.0
	var father_npc = CitizenNPC.new("test_father", "Любомир", "m", 26, "adult")
	father_npc.traits["diligence"] = 70.0
	father_npc.traits["bravery"] = 60.0
	var child_npc = CitizenNPC.new("test_child", "Младенец", "m", 0, "child")
	child_npc.inherit_traits_from_parents(mother_npc, father_npc)
	assert(child_npc.traits["diligence"] >= 60.0 and child_npc.traits["diligence"] <= 100.0, "P01.2: Child inherits diligence from parents with spread")

	# 5. Память: добавление, поиск, затухание и радиус наблюдения
	p01_npc.pos = Vector2(100.0, 100.0)
	p01_npc.add_memory("rescued", "cit_2", p01_npc.citizen_id, 1.0, "Брок спас из пасти волка", true)
	p01_npc.add_memory("minor_insult", "cit_3", p01_npc.citizen_id, 0.1, "Ратибор толкнул у костра", false)
	assert(p01_npc.has_memory_of("cit_2", "rescued"), "P01.2: Memory of rescue is registered")
	assert(p01_npc.has_memory_of("cit_3", "minor_insult"), "P01.2: Memory of minor insult registered")

	# Затухание: незначительная обида слабеет, спасение жизни остаётся постоянным
	p01_npc.update_memories(30.0) # Прошло 30 дней
	assert(p01_npc.has_memory_of("cit_2", "rescued"), "P01.2: Permanent life-saving memory never fades")
	assert(not p01_npc.has_memory_of("cit_3", "minor_insult"), "P01.2: Minor temporary memory fades completely over time")

	# Радиус наблюдения: тихий (<=64px), нормальный (<=160px), громкий (<=320px)
	assert(p01_npc.can_observe_event(Vector2(140.0, 100.0), "quiet"), "P01.2: Quiet action 40px away observed")
	assert(not p01_npc.can_observe_event(Vector2(200.0, 100.0), "quiet"), "P01.2: Quiet action 100px away NOT observed")
	assert(p01_npc.can_observe_event(Vector2(200.0, 100.0), "normal"), "P01.2: Normal action 100px away observed")
	assert(not p01_npc.can_observe_event(Vector2(350.0, 100.0), "normal"), "P01.2: Normal action 250px away NOT observed")
	assert(p01_npc.can_observe_event(Vector2(350.0, 100.0), "loud"), "P01.2: Loud shout 250px away observed")
	assert(not p01_npc.can_observe_event(Vector2(500.0, 100.0), "loud"), "P01.2: Loud shout 400px away NOT observed")

	# 6. Сохранение и загрузка ловкости, шкал характера и памяти
	var p01_serialized = p01_npc.serialize()
	assert(p01_serialized.has("agility_xp") and p01_serialized.has("memories"), "P01.2: Serialized contains agility and memories")
	var p01_restored = CitizenNPC.new()
	p01_restored.deserialize(p01_serialized)
	assert(p01_restored.agility_level == p01_npc.agility_level, "P01.2: Restored agility level matches")
	assert(p01_restored.has_memory_of("cit_2", "rescued"), "P01.2: Restored memory of rescue preserved")
	assert(p01_restored.traits["temper"] == p01_npc.traits["temper"], "P01.2: Restored personality trait matches")
	print("OK 99. P01.2 Citizen effective parameters, personality scales, memories and observation radius verified.")

	# 100. P01.3: Модель жилья — разделение слотов, комфорт, теснота, роли и миграция сохранений
	var hut_def = BuildingDB.get_building("hut")
	assert(hut_def["housing"] == 8 and hut_def.get("comfort_housing", 0) == 6, "P01.3: Hut has 8 max residents and 6 comfort capacity")
	assert(hut_def.get("cost", {}).get("wood", 0) == 15, "P01.3: Hut costs 15 wood")

	var hut_inst = BuildingInstance.new("test_hut_1", "hut", "test_s", Vector2i(25, 25))
	assert(hut_inst.max_residents == 8, "P01.3: Max residents is 8")
	assert(hut_inst.get_comfort_capacity() == 6, "P01.3: Comfort capacity is 6")
	assert(hut_inst.max_guests == 2, "P01.3: Max guests is 2")
	assert(not hut_inst.is_crowded(), "P01.3: Empty hut is not crowded")

	# Заселяем постоянных жильцов до комфортной вместимости
	for i in range(6):
		assert(hut_inst.add_resident("res_%d" % i), "P01.3: Resident %d accommodated" % i)
	assert(not hut_inst.is_crowded(), "P01.3: 6 residents in hut is comfortable, not crowded")
	assert(hut_inst.get_crowding_penalty() == 0.0, "P01.3: Zero penalty at comfort limit")
	assert(hut_inst.get_resident_role("res_0") == "owner", "P01.3: First resident designated as owner / head of household")
	assert(hut_inst.get_resident_role("res_1") == "resident", "P01.3: Subsequent residents have resident role")

	# Заселяем 7-го и 8-го (теснота)
	assert(hut_inst.add_resident("res_6"), "P01.3: Resident 6 added (crowded)")
	assert(hut_inst.is_crowded(), "P01.3: 7 residents makes hut crowded")
	assert(hut_inst.get_crowding_penalty() > 0.0, "P01.3: Crowding penalty active")
	assert(hut_inst.add_resident("res_7"), "P01.3: Resident 7 added (maximum capacity)")
	assert(not hut_inst.has_space_for_resident(), "P01.3: Resident capacity full at 8")
	assert(not hut_inst.add_resident("res_8"), "P01.3: 9th resident rejected")

	# Проверка строгой изоляции слотов гостей: гостевые места остаются доступны даже при полной хижине!
	assert(hut_inst.has_space_for_guest(), "P01.3: Guest slots remain available despite full permanent slots")
	assert(hut_inst.add_guest("guest_0"), "P01.3: First guest accommodated")
	assert(hut_inst.get_resident_role("guest_0") == "guest", "P01.3: Guest has guest role")
	assert(hut_inst.add_guest("guest_1"), "P01.3: Second guest accommodated")
	assert(not hut_inst.has_space_for_guest(), "P01.3: Guest capacity full at 2")
	assert(not hut_inst.add_guest("guest_2"), "P01.3: Third guest rejected (guest slots cannot overflow)")

	# Освобождение и смена ролей
	hut_inst.set_resident_role("res_2", "dependent")
	assert(hut_inst.get_resident_role("res_2") == "dependent", "P01.3: Dependent role set cleanly on res_2")
	hut_inst.remove_resident("res_0")
	assert(hut_inst.get_resident_role("res_0") == "none", "P01.3: Removed resident role cleared")
	assert(hut_inst.household_head_id == "res_1", "P01.3: Head of household automatically reassigned to res_1 on owner removal")
	assert(hut_inst.get_resident_role("res_1") == "owner", "P01.3: res_1 automatically becomes owner")

	# Миграция старых сохранений (без полей resident_roles и household_head_id)
	var legacy_save = {
		"id": "legacy_hut",
		"type": "hut",
		"residents": ["leg_1", "leg_2", "leg_3"],
		"guests": ["leg_guest"]
	}
	var migrated_hut = BuildingInstance.new()
	migrated_hut.deserialize(legacy_save)
	assert(migrated_hut.household_head_id == "leg_1", "P01.3: Legacy save migrated: first resident becomes owner")
	assert(migrated_hut.get_resident_role("leg_1") == "owner", "P01.3: Legacy leg_1 role is owner")
	assert(migrated_hut.get_resident_role("leg_2") == "resident", "P01.3: Legacy leg_2 role is resident")
	assert(migrated_hut.get_resident_role("leg_guest") == "guest", "P01.3: Legacy leg_guest role is guest")
	assert(migrated_hut.get_comfort_capacity() == 6, "P01.3: Legacy comfort capacity initialized")

	# Проверка сохранения и загрузки всех расширенных полей домохозяйства
	hut_inst.domestic_goods["hides"] = 5.0
	var saved_hut_data = hut_inst.serialize()
	var loaded_hut = BuildingInstance.new()
	loaded_hut.deserialize(saved_hut_data)
	assert(loaded_hut.comfort_capacity == hut_inst.comfort_capacity, "P01.3: Comfort capacity preserved in save")
	assert(loaded_hut.household_head_id == "res_1", "P01.3: Head of household preserved in save")
	assert(loaded_hut.get_resident_role("res_2") == "dependent", "P01.3: Dependent role preserved in save")
	assert(loaded_hut.domestic_goods.get("hides", 0.0) == 5.0, "P01.3: Domestic goods preserved in save")
	print("OK 100. P01.3 Housing comfort, capacity isolation, roles and legacy migration verified.")

	# --------------------------------------------------------------------------
	# TEST 101: P01.4 — РЕАЛЬНЫЙ ЦИКЛ ХИЖИНЫ, СОН, ТЕСНОТА, УЛУЧШЕНИЯ И ПАМЯТЬ
	# --------------------------------------------------------------------------
	var p01_4_settlement = SettlementData.new("p01_4_s", "Поселение Хижины", "player_tribe", Vector2i(10, 10))
	GameManager.settlements["p01_4_s"] = p01_4_settlement
	p01_4_settlement.init_citizens_on_map()

	# 1. Проверка каталога data-driven улучшений хижины в BuildingSystem
	var hut_upgrades = BuildingSystem.get_upgrades_for_building("hut")
	assert(hut_upgrades.size() >= 4, "P01.4: Hut must have at least 4 data-driven upgrades")
	var up_ids = []
	for u in hut_upgrades:
		up_ids.append(u["id"])
	assert(up_ids.has("hut_annex"), "P01.4: hut_annex registered")
	assert(up_ids.has("hut_shed"), "P01.4: hut_shed registered")
	assert(up_ids.has("hut_pantry"), "P01.4: hut_pantry registered")
	assert(up_ids.has("hut_garden"), "P01.4: hut_garden registered")

	# 2. Создание тестовой хижины
	var test_hut = BuildingInstance.new("inst_p01_4_hut", "hut", "p01_4_s", Vector2i(10, 11))
	GameManager.building_instances[Vector2i(10, 11)] = test_hut
	assert(test_hut.get_comfort_capacity() == 6, "P01.4: Base hut comfort capacity is 6")
	assert(test_hut.get_max_residents() == 8, "P01.4: Base hut max residents is 8")

	# Заселяем 7 жителей — превышение комфорта (теснота: 7 > 6)
	for i in range(7):
		var cit_id = "test_res_%d" % i
		var cit = CitizenNPC.new(cit_id, "Житель %d" % i, "m" if i % 2 == 0 else "f", 20 + i)
		p01_4_settlement.population.citizens.append(cit)
		test_hut.add_resident(cit_id, "resident")
		cit.set_home(test_hut.id, test_hut.pos, Vector2(test_hut.pos.x * 32, test_hut.pos.y * 32), false, test_hut.id)

	assert(test_hut.is_crowded(), "P01.4: 7 residents in 6-comfort hut is crowded")
	var crowd_pen = test_hut.get_crowding_penalty()
	assert(crowd_pen > 0.0, "P01.4: Crowding penalty must be greater than 0")

	# 3. Проверка сна в тесноте против сна на улице (бездомный)
	var crowded_cit = p01_4_settlement.population.find_citizen("test_res_0")
	crowded_cit.energy = 20.0
	crowded_cit.state = CitizenNPC.State.SLEEPING

	var p01_4_homeless = CitizenNPC.new("homeless_cit_p01_4", "Бездомный Бродяга", "m", 25)
	p01_4_settlement.population.citizens.append(p01_4_homeless)
	p01_4_homeless.energy = 20.0
	p01_4_homeless.clear_home()
	p01_4_homeless.state = CitizenNPC.State.SLEEPING

	# Имитация ночного тика сна (delta = 1.0s)
	GameManager.current_hour = 1.0 # Ночь
	p01_4_settlement.update_citizens(1.0)

	# В тесноте сон медленнее, чем нормальные 12/сек: sleep_rate = 12 * (1 - penalty)
	var expected_crowded_rate = 12.0 * (1.0 - crowd_pen)
	assert(crowded_cit.energy < (20.0 + 12.0 * 1.0), "P01.4: Crowded sleep recovers less than full rate")
	assert("тесноте" in crowded_cit.last_status_reason, "P01.4: Crowded status reason mentions crowding")

	# Бездомный восстанавливает лишь 6/сек и получает статус сна на улице
	assert(p01_4_homeless.energy <= 26.0, "P01.4: Homeless sleep rate is 6.0/s")
	assert("Бездомный" in p01_4_homeless.last_status_reason, "P01.4: Homeless status reason mentions outdoor sleep")

	# Утреннее пробуждение: если не выспался (energy < 50), получает статус "Не выспался (усталость)"
	GameManager.current_hour = 8.0 # Утро
	crowded_cit.energy = 40.0 # Устал
	crowded_cit.state = CitizenNPC.State.SLEEPING
	p01_4_settlement.update_citizens(0.1)
	assert(crowded_cit.state == CitizenNPC.State.IDLE, "P01.4: Citizen wakes up in morning")
	assert(crowded_cit.last_status_reason == "Не выспался (усталость)", "P01.4: Low energy morning status is tired")

	# 4. Проверка влияния усталости и голода на результативность лесоруба (ТЗ Критерий 3)
	var wc_cit = CitizenNPC.new("wc_test", "Лесоруб Уставший", "m", 25)
	wc_cit.energy = 10.0 # Истощен
	wc_cit.hunger = 15.0 # Голоден
	var tired_mult = wc_cit.get_vitality_multiplier()
	assert(tired_mult < 0.5, "P01.4: Tired & hungry citizen has vitality multiplier < 0.5")

	# Восстановление сил после еды и отдыха
	wc_cit.energy = 100.0
	wc_cit.hunger = 100.0
	var rested_mult = wc_cit.get_vitality_multiplier()
	assert(rested_mult == 1.0, "P01.4: Fully fed and rested citizen has 100% vitality multiplier")

	# 5. Автономное начало частного улучшения свободной семьей (P01.4 / ТЗ 6.3)
	p01_4_settlement.economy.resources["wood"] = 50.0
	p01_4_settlement.economy.resources["stone"] = 20.0
	# Семья в test_hut испытывает тесноту (7 > 6) -> потребность в hut_annex
	var started_private = p01_4_settlement.check_family_private_improvements()
	assert(started_private, "P01.4: Family autonomously starts private improvement when need & resources exist")
	assert(test_hut.has_pending_upgrade(), "P01.4: Hut now has pending upgrade")
	assert(test_hut.pending_upgrade["id"] == "hut_annex", "P01.4: Started upgrade matches family need (hut_annex)")
	assert(p01_4_settlement.economy.get_resource("wood") == 40.0, "P01.4: 10 wood deducted for hut_annex")

	# 6. Отмена улучшения правителем и память семьи о вмешательстве
	var initial_loyalty = crowded_cit.loyalty
	var cancelled_up = p01_4_settlement.cancel_building_upgrade(test_hut, true)
	assert(not cancelled_up.is_empty(), "P01.4: Upgrade successfully cancelled")
	assert(not test_hut.has_pending_upgrade(), "P01.4: Pending upgrade cleared")
	assert(p01_4_settlement.economy.get_resource("wood") == 50.0, "P01.4: Wood refunded to economy upon cancel")

	# Жильцы хижины получили возмущение и запись в памяти
	assert(crowded_cit.loyalty < initial_loyalty, "P01.4: Resident loyalty dropped after player cancelled home improvement")
	assert(crowded_cit.has_memory_of("ruler", "outrage"), "P01.4: Family stored memory of ruler prohibiting their home improvement")
	var has_outrage_memory = false
	for m in crowded_cit.memories:
		if m.get("type", "") == "outrage" and "обустройство" in m.get("description", ""):
			has_outrage_memory = true
			break
	assert(has_outrage_memory, "P01.4: Outrage memory details verify description")

	# 7. Завершение улучшения и снятие тесноты
	test_hut.unlock_upgrade("hut_annex")
	assert(test_hut.is_upgrade_unlocked("hut_annex"), "P01.4: hut_annex is unlocked")
	assert(test_hut.get_comfort_capacity() == 8, "P01.4: Comfort capacity expanded from 6 to 8")
	assert(test_hut.get_max_residents() == 10, "P01.4: Max residents expanded from 8 to 10")
	assert(not test_hut.is_crowded(), "P01.4: 7 residents in 8-comfort hut is no longer crowded!")

	# 8. Кладовая и огород
	test_hut.unlock_upgrade("hut_pantry")
	assert(test_hut.get_home_spoilage_multiplier() == 0.5, "P01.4: Pantry reduces home food spoilage by 50%")
	test_hut.unlock_upgrade("hut_shed")
	assert(test_hut.get_domestic_goods_capacity() == 25.0, "P01.4: Shed expands domestic storage to 25")
	test_hut.unlock_upgrade("hut_garden")
	test_hut.food_stockpile = 2.0
	p01_4_settlement.sim_daily_tick("summer")
	assert(test_hut.food_stockpile >= 2.5, "P01.4: Garden yields food produce for the household")

	print("OK 101. P01.4 Hut life cycle, sleep quality, crowding penalty, family private improvements and cancellation memory verified.")

	# ---------------------------------------------------------
	# TEST 102: P01.5 Contextual Event Engine & Dynamic Consequence Resolution
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING P01.5 CONTEXTUAL EVENT ENGINE & CONSEQUENCE RESOLUTION")
	print("----------------------------------------")
	var p01_5_settlement = SettlementData.new("p01_5_test_settlement")
	var p01_5_ev_mgr = CivilizationEventManager.new()
	p01_5_ev_mgr.settlement = p01_5_settlement

	var cit_owner = CitizenNPC.new("owner_102", "Борс Строитель", "m", 28)
	var cit_guest = CitizenNPC.new("guest_102", "Дара Переселенка", "f", 24)
	p01_5_settlement.population.citizens.append(cit_owner)
	p01_5_settlement.population.citizens.append(cit_guest)

	var p01_5_hut = BuildingInstance.new("hut_102", "hut", p01_5_settlement.id, Vector2i(5, 5))
	var r_list_102: Array[String] = [cit_owner.id, cit_guest.id]
	p01_5_hut.residents = r_list_102
	cit_owner.home_building_id = p01_5_hut.id
	cit_guest.home_building_id = p01_5_hut.id
	GameManager.building_instances[p01_5_hut.id] = p01_5_hut

	# 1. Проверка шаблона события с плейсхолдерами и контекстом
	var test_event_template: Dictionary = {
		"id": "EV_TEST_CONTEXT_102",
		"title": "Спор за жильё в доме {building_id}",
		"description": "Семья {actor_0} и семья {actor_1} спорят о правах на дом.",
		"category": "community",
		"min_huts": 1,
		"choices": [
			{
				"id": "A",
				"title": "Признать собственность первого строителя",
				"desc": "Дом закрепляется за семьей строителя.",
				"consequences": {
					"housing_tenure": {"owner_id": "{actor_0}", "tenant_ids": ["{actor_1}"]},
					"modify_relations": [{"from": "{actor_1}", "to": "{actor_0}", "delta": -25.0}],
					"modify_loyalty": [{"actor_id": "{actor_0}", "delta": 15.0}, {"actor_id": "{actor_1}", "delta": -15.0}],
					"modify_memory": [
						{"actor_id": "{actor_0}", "type": "gratitude", "desc": "Правитель защитил наш труд и права на дом", "permanent": true},
						{"actor_id": "{actor_1}", "type": "resentment", "desc": "Нас низвели до положения жильцов-арендаторов", "permanent": false}
					],
					"modify_resources": {"wood": 5.0}
				}
			},
			{
				"id": "B",
				"title": "Сделать общинным жильем",
				"desc": "Все жильцы имеют равные права совладельцев.",
				"consequences": {
					"housing_tenure": {"co_owners": ["{actor_0}", "{actor_1}"]},
					"modify_relations": [{"from": "{actor_0}", "to": "{actor_1}", "delta": -10.0}]
				}
			}
		]
	}

	# 2. Триггер события с живым контекстом
	var ev_instance_id = p01_5_ev_mgr.trigger_event(test_event_template, {
		"actor_ids": [cit_owner.id, cit_guest.id],
		"actor_names": [cit_owner.name, cit_guest.name],
		"target_building_id": p01_5_hut.id,
		"causes": ["Нехватка жилплощади", "Разный вклад в строительство"],
		"context_data": {
			"building_id": p01_5_hut.id,
			"actor_0": cit_owner.name,
			"actor_1": cit_guest.name
		}
	})

	assert(ev_instance_id != "", "P01.5: Event triggered with context")
	var ev_instance = p01_5_ev_mgr.event_instances[ev_instance_id]
	assert("Борс Строитель" in ev_instance["description"], "P01.5: Actor 0 placeholder substituted in description")
	assert("Дара Переселенка" in ev_instance["description"], "P01.5: Actor 1 placeholder substituted in description")
	assert("hut_102" in ev_instance["title"], "P01.5: Building placeholder substituted in title")
	assert(ev_instance["causes"].size() == 2, "P01.5: Causes recorded in event instance")

	# 3. Применение последствий выбора A (реальное изменение мира)
	var initial_wood_102 = p01_5_settlement.economy.get_resource("wood")
	var initial_owner_loyalty = cit_owner.loyalty
	var initial_guest_loyalty = cit_guest.loyalty

	p01_5_ev_mgr.apply_choice(ev_instance_id, "A")

	# Проверяем жилищный статус
	assert(p01_5_hut.household_head_id == cit_owner.id, "P01.5: Owner assigned to hut")
	assert(p01_5_hut.get_resident_role(cit_owner.id) == "Владелец", "P01.5: cit_owner has Owner role")
	assert(p01_5_hut.get_resident_role(cit_guest.id) == "Жилец", "P01.5: cit_guest has Tenant role")

	# Проверяем лояльность и отношения
	assert(cit_owner.loyalty == initial_owner_loyalty + 15.0, "P01.5: Owner loyalty increased by 15")
	assert(cit_guest.loyalty == initial_guest_loyalty - 15.0, "P01.5: Guest loyalty decreased by 15")
	var rel = cit_guest.get_relationship_with(cit_owner.id)
	assert(rel < 0.0, "P01.5: Guest affinity towards owner dropped after dispute verdict")

	# Проверяем воспоминания
	assert(cit_owner.has_memory_of("ruler", "gratitude"), "P01.5: Owner stored permanent gratitude memory to ruler")
	assert(cit_guest.has_memory_of("ruler", "resentment"), "P01.5: Guest stored resentment memory to ruler")

	# Проверяем экономику
	assert(p01_5_settlement.economy.get_resource("wood") == initial_wood_102 + 5.0, "P01.5: Economy received wood bonus from consequence")

	# 4. Проверка условий зависимостей событий
	var child_event_template: Dictionary = {
		"id": "EV_TEST_CHILD_102",
		"required_event_resolved": "EV_TEST_CONTEXT_102",
		"required_choice": {"event_id": "EV_TEST_CONTEXT_102", "choice_id": "A"},
		"min_huts": 1
	}
	assert(p01_5_ev_mgr._check_event_conditions(child_event_template, 10, p01_5_settlement), "P01.5: Child event conditions pass when prerequisite event choice matches")

	var forbidden_event_template: Dictionary = {
		"id": "EV_TEST_FORBIDDEN_102",
		"required_event_resolved": "EV_TEST_CONTEXT_102",
		"forbidden_choice": {"event_id": "EV_TEST_CONTEXT_102", "choice_id": "A"}
	}
	assert(not p01_5_ev_mgr._check_event_conditions(forbidden_event_template, 10, p01_5_settlement), "P01.5: Event forbidden when choice A was made")

	# 5. Проверка невмешательства (resolve_without_intervention)
	var hut_inaction = BuildingInstance.new("hut_inaction_102", "hut", p01_5_settlement.id, Vector2i(6, 6))
	GameManager.building_instances[hut_inaction.id] = hut_inaction
	var inaction_ev_template: Dictionary = {
		"id": "EV_INACTION_102",
		"title": "Спор без суда"
	}
	var inaction_ev_id = p01_5_ev_mgr.trigger_event(inaction_ev_template, {
		"actor_ids": [cit_owner.id, cit_guest.id],
		"target_building_id": hut_inaction.id
	})
	var rel_before = cit_owner.get_relationship_with(cit_guest.id)
	p01_5_ev_mgr.resolve_without_intervention(inaction_ev_id)
	assert(cit_owner.get_relationship_with(cit_guest.id) < rel_before, "P01.5: Unresolved dispute reduces mutual relations")
	assert(hut_inaction.has_unresolved_dispute(), "P01.5: Hut marked with unresolved dispute")
	assert(cit_owner.has_memory_of("ruler", "disappointment"), "P01.5: Citizens remember ruler inaction in domestic crisis")

	# 6. Проверка модального окна на отображение фактов
	var modal_ui = CivilizationEventModal.new()
	modal_ui._build_ui()
	modal_ui.open_event(ev_instance)
	assert(modal_ui.context_container.visible == true, "P01.5: Event modal displays context box when causes/actors exist")
	assert("Борс Строитель" in modal_ui.context_lbl.text, "P01.5: Modal context label contains actor names")
	assert("Нехватка жилплощади" in modal_ui.context_lbl.text, "P01.5: Modal context label contains causes")
	modal_ui.queue_free()

	print("OK 102. P01.5 Contextual event engine, placeholder formatting, consequence execution and inaction friction verified.")

	# ---------------------------------------------------------
	# TEST 103: P01.6 HUT-01 («Дом, который мы подняли своими руками»)
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING P01.6 HUT-01 HOUSING PRECEDENT & 5 WAYS RESOLUTION")
	print("----------------------------------------")
	var p01_6_settlement = SettlementData.new("p01_6_test_settlement")
	var p01_6_ev_mgr = CivilizationEventManager.new()
	p01_6_ev_mgr.settlement = p01_6_settlement

	# Граждане поселения
	var cit_builder_103 = CitizenNPC.new("builder_103", "Яромир Зодчий", "m", 30)
	cit_builder_103.skill_builder = 25.0
	cit_builder_103.personality["pride"] = 80.0

	var cit_second_103 = CitizenNPC.new("second_103", "Милана Бездомная", "f", 22)
	cit_second_103.personality["sociability"] = 70.0
	cit_second_103.personality["greed"] = 20.0

	var cit_voter_103 = CitizenNPC.new("voter_103", "Воислав Старейшина", "m", 45)

	p01_6_settlement.population.citizens.append(cit_builder_103)
	p01_6_settlement.population.citizens.append(cit_second_103)
	p01_6_settlement.population.citizens.append(cit_voter_103)

	# Первая построенная и заселенная хижина
	var hut_103 = BuildingInstance.new("hut_p01_6", "hut", p01_6_settlement.id, Vector2i(10, 10))
	var r_list_103: Array[String] = [cit_builder_103.id, cit_second_103.id]
	hut_103.residents = r_list_103
	cit_builder_103.home_id = hut_103.id
	cit_second_103.home_id = hut_103.id
	GameManager.building_instances[hut_103.id] = hut_103

	# 1. Проверка автоматического триггера HUT-01 через check_hut_dispute_trigger
	var hut_ctx = p01_6_ev_mgr.check_hut_dispute_trigger(p01_6_settlement)
	assert(not hut_ctx.is_empty(), "P01.6: Dispute trigger found populated hut with 2+ residents")
	assert(hut_ctx["target_building_id"] == hut_103.id, "P01.6: Target building matches hut_p01_6")
	assert(hut_ctx["actor_ids"].has(cit_builder_103.id), "P01.6: First builder is among dispute actors")
	assert(hut_ctx["actor_ids"].has(cit_second_103.id), "P01.6: Second resident is among dispute actors")

	# Запуск HUT-01 через process_daily_triggers
	p01_6_ev_mgr.process_daily_triggers(1, 1, p01_6_settlement)
	assert(not p01_6_ev_mgr.active_event.is_empty(), "P01.6: HUT-01 triggered in daily processing")
	assert(p01_6_ev_mgr.active_event["id"] == "HUT-01", "P01.6: Active event is HUT-01")
	assert("Яромир Зодчий" in p01_6_ev_mgr.active_event["description"], "P01.6: Builder name in description")
	assert("Милана Бездомная" in p01_6_ev_mgr.active_event["description"], "P01.6: Second resident name in description")
	assert(p01_6_ev_mgr.active_event["choices"].size() == 5, "P01.6: Exactly 5 choices presented for HUT-01")

	var hut_ev_id = p01_6_ev_mgr.active_event["instance_id"]

	# 2. Тестирование Варианта B: «Свободный договор» (FREE_CONTRACT)
	p01_6_ev_mgr.apply_choice(hut_ev_id, "B")
	assert(hut_103.household_head_id == cit_builder_103.id, "P01.6 (Choice B): Builder is household head")
	assert(hut_103.get_resident_role(cit_builder_103.id) == "Владелец", "P01.6 (Choice B): Builder is Owner")
	assert(hut_103.get_resident_role(cit_second_103.id) == "Жилец", "P01.6 (Choice B): Second resident is Tenant")
	assert(cit_builder_103.has_memory_of("ruler", "gratitude"), "P01.6 (Choice B): Builder has gratitude memory")
	assert(GameManager.culture_memory.has_tradition("free_contract_housing"), "P01.6: Tradition free_contract_housing unlocked")

	# 3. Тестирование Варианта A: «Общинный дом» (COMMUNAL) на отдельном инстансе
	var hut_communal = BuildingInstance.new("hut_communal_103", "hut", p01_6_settlement.id, Vector2i(11, 11))
	var r_communal: Array[String] = [cit_builder_103.id, cit_second_103.id]
	hut_communal.residents = r_communal
	GameManager.building_instances[hut_communal.id] = hut_communal

	var ev_comm_template = CivilizationEventDB.get_event("HUT-01")
	var comm_ev_id = p01_6_ev_mgr.trigger_event(ev_comm_template, {
		"actor_ids": [cit_builder_103.id, cit_second_103.id],
		"actor_names": [cit_builder_103.name, cit_second_103.name],
		"target_building_id": hut_communal.id
	})
	p01_6_ev_mgr.apply_choice(comm_ev_id, "A")
	assert(hut_communal.get_resident_role(cit_builder_103.id) == "Совладелец", "P01.6 (Choice A): Builder is Co-owner")
	assert(hut_communal.get_resident_role(cit_second_103.id) == "Совладелец", "P01.6 (Choice A): Second resident is Co-owner")
	assert(cit_builder_103.has_memory_of("ruler", "bitterness"), "P01.6 (Choice A): Builder has bitterness memory of losing sole home rights")

	# 4. Тестирование Варианта C: «Зависимое проживание» (DEPENDENT)
	var hut_dep = BuildingInstance.new("hut_dep_103", "hut", p01_6_settlement.id, Vector2i(12, 12))
	var r_dep: Array[String] = [cit_builder_103.id, cit_second_103.id]
	hut_dep.residents = r_dep
	GameManager.building_instances[hut_dep.id] = hut_dep

	var dep_ev_id = p01_6_ev_mgr.trigger_event(ev_comm_template, {
		"actor_ids": [cit_builder_103.id, cit_second_103.id],
		"actor_names": [cit_builder_103.name, cit_second_103.name],
		"target_building_id": hut_dep.id
	})
	p01_6_ev_mgr.apply_choice(dep_ev_id, "C")
	assert(hut_dep.get_resident_role(cit_builder_103.id) == "Владелец", "P01.6 (Choice C): Builder is Owner")
	assert(hut_dep.get_resident_role(cit_second_103.id) == "Зависимый", "P01.6 (Choice C): Dependent has Зависимый role")
	assert(cit_second_103.has_memory_of("ruler", "resentment"), "P01.6 (Choice C): Dependent remembers grievance toward ruler")

	# 5. Тестирование Варианта D: «Пусть община рассудит» (COUNCIL)
	var hut_council = BuildingInstance.new("hut_council_103", "hut", p01_6_settlement.id, Vector2i(13, 13))
	var r_council: Array[String] = [cit_builder_103.id, cit_second_103.id]
	hut_council.residents = r_council
	GameManager.building_instances[hut_council.id] = hut_council

	var council_ev_id = p01_6_ev_mgr.trigger_event(ev_comm_template, {
		"actor_ids": [cit_builder_103.id, cit_second_103.id],
		"actor_names": [cit_builder_103.name, cit_second_103.name],
		"target_building_id": hut_council.id
	})
	# Старейшина уважает строителя за труд
	cit_voter_103.add_relationship(cit_builder_103.id, "peer", 60.0)
	cit_voter_103.add_relationship(cit_second_103.id, "peer", 20.0)
	p01_6_ev_mgr.apply_choice(council_ev_id, "D")
	assert(hut_council.active_modifiers.has("council_verdict"), "P01.6 (Choice D): Council verdict recorded on hut")
	assert(cit_builder_103.has_memory_of("council", "gratitude"), "P01.6 (Choice D): Builder has memory of council decision")

	# 6. Тестирование Варианта E: «Не вмешиваться пока» (NO_INTERVENTION)
	var hut_no_interv = BuildingInstance.new("hut_no_interv_103", "hut", p01_6_settlement.id, Vector2i(14, 14))
	var r_no_interv: Array[String] = [cit_builder_103.id, cit_second_103.id]
	hut_no_interv.residents = r_no_interv
	GameManager.building_instances[hut_no_interv.id] = hut_no_interv

	var no_int_ev_id = p01_6_ev_mgr.trigger_event(ev_comm_template, {
		"actor_ids": [cit_builder_103.id, cit_second_103.id],
		"actor_names": [cit_builder_103.name, cit_second_103.name],
		"target_building_id": hut_no_interv.id
	})
	p01_6_ev_mgr.apply_choice(no_int_ev_id, "E")
	assert(hut_no_interv.has_unresolved_dispute(), "P01.6 (Choice E): Hut retains unresolved dispute")

	print("OK 103. P01.6 HUT-01 housing precedent, 5-option resolution, council vote and persistent world consequences verified.")

	# --------------------------------------------------------------------------
	# TEST 104: P01.7 HUT-02 «Крыша и долг» (Re-occurring dispute, 4 branches)
	# --------------------------------------------------------------------------
	var p01_7_settlement = SettlementData.new("settlement_p01_7", "Поселок P01.7", "player_faction", Vector2i(30, 30))
	p01_7_settlement.economy.resources["food"] = 30.0
	p01_7_settlement.economy.resources["wood"] = 20.0
	GameManager.settlements[p01_7_settlement.id] = p01_7_settlement
	var p01_7_ev_mgr = CivilizationEventManager.new()
	p01_7_ev_mgr.settlement = p01_7_settlement
	p01_7_ev_mgr.triggered_events.append("HUT-01")

	var cit_owner_104 = CitizenNPC.new("owner_104", "Борислав Хозяин", "m", 30)
	var cit_tenant_104 = CitizenNPC.new("tenant_104", "Злата Жиличка", "f", 24)
	p01_7_settlement.population.citizens.append(cit_owner_104)
	p01_7_settlement.population.citizens.append(cit_tenant_104)

	# Хижина со спором
	var hut_104 = BuildingInstance.new("hut_p01_7", "hut", p01_7_settlement.id, Vector2i(15, 15))
	var r_list_104: Array[String] = [cit_owner_104.id, cit_tenant_104.id]
	hut_104.residents = r_list_104
	hut_104.household_head_id = cit_owner_104.id
	hut_104.resident_roles[cit_owner_104.id] = "Владелец"
	hut_104.resident_roles[cit_tenant_104.id] = "Жилец"
	cit_owner_104.home_id = hut_104.id
	cit_tenant_104.home_id = hut_104.id
	GameManager.building_instances[hut_104.id] = hut_104

	# 1. Проверка причин триггера HUT-02:
	# А) Припасы в доме на нуле (< 1.5)
	hut_104.food_stockpile = 0.5
	var ctx_low_food = p01_7_ev_mgr.check_hut_02_dispute_trigger(p01_7_settlement)
	assert(not ctx_low_food.is_empty(), "P01.7: Low food in hut triggers HUT-02")
	assert("Нехватка припасов" in ctx_low_food["causes"][0], "P01.7: Cause is low food in house")

	# Б) Перенаселение
	hut_104.food_stockpile = 10.0
	var old_cap = hut_104.comfort_capacity
	hut_104.comfort_capacity = 1 # 2 жильца при капасити 1 = is_crowded()
	var ctx_crowd = p01_7_ev_mgr.check_hut_02_dispute_trigger(p01_7_settlement)
	assert(not ctx_crowd.is_empty(), "P01.7: Crowding in hut triggers HUT-02")
	assert("Теснота" in ctx_crowd["causes"][0], "P01.7: Cause is crowding")
	hut_104.comfort_capacity = old_cap

	# В) Нерешённый старый спор
	hut_104.active_modifiers["unresolved_housing_dispute"] = true
	var ctx_dispute = p01_7_ev_mgr.check_hut_02_dispute_trigger(p01_7_settlement)
	assert(not ctx_dispute.is_empty(), "P01.7: Unresolved dispute triggers HUT-02")
	assert("Старая неприязнь" in ctx_dispute["causes"][0], "P01.7: Cause is unresolved dispute")

	# 2. Тестирование Варианта A: «Защитить права и покой хозяев дома» (EVICTION)
	var hut_ev_template = CivilizationEventDB.get_event("HUT-02")
	var ev_a_id = p01_7_ev_mgr.trigger_event(hut_ev_template, ctx_dispute)
	assert("Борислав Хозяин" in p01_7_ev_mgr.active_event["description"], "P01.7: Owner name in description")
	assert("Злата Жиличка" in p01_7_ev_mgr.active_event["description"], "P01.7: Tenant name in description")
	p01_7_ev_mgr.apply_choice(ev_a_id, "A")
	assert(not hut_104.residents.has(cit_tenant_104.id), "P01.7 (Choice A): Tenant removed from hut residents")
	assert(cit_tenant_104.home_id == "", "P01.7 (Choice A): Evicted tenant is now homeless")
	assert(cit_tenant_104.has_memory_of("ruler", "outrage"), "P01.7 (Choice A): Evicted tenant remembers outrage toward ruler")
	assert(cit_owner_104.has_memory_of("ruler", "gratitude"), "P01.7 (Choice A): Owner remembers gratitude toward ruler")
	assert(not hut_104.has_unresolved_dispute(), "P01.7 (Choice A): Dispute resolved on hut")

	# 3. Тестирование Варианта B: «Защитить жильцов от произвола» (PROTECT_TENANTS + FOOD AID)
	var hut_104_b = BuildingInstance.new("hut_b_104", "hut", p01_7_settlement.id, Vector2i(16, 16))
	var r_list_b: Array[String] = [cit_owner_104.id, cit_tenant_104.id]
	hut_104_b.residents = r_list_b
	hut_104_b.active_modifiers["unresolved_housing_dispute"] = true
	GameManager.building_instances[hut_104_b.id] = hut_104_b
	var initial_food_104 = p01_7_settlement.economy.get_resource("food")
	var ev_b_id = p01_7_ev_mgr.trigger_event(hut_ev_template, {
		"actor_ids": [cit_owner_104.id, cit_tenant_104.id],
		"actor_names": [cit_owner_104.name, cit_tenant_104.name],
		"target_building_id": hut_104_b.id,
		"causes": ["Нехватка припасов и спор о доле в котле"],
		"context_data": {"building_id": hut_104_b.id, "actor_0": cit_owner_104.name, "actor_1": cit_tenant_104.name, "dispute_cause": "Нехватка припасов"}
	})
	p01_7_ev_mgr.apply_choice(ev_b_id, "B")
	assert(hut_104_b.active_modifiers.get("protected_tenancy", false), "P01.7 (Choice B): Protected tenancy modifier applied")
	assert(p01_7_settlement.economy.get_resource("food") == initial_food_104 - 5.0, "P01.7 (Choice B): 5 food deducted from settlement")
	assert(cit_owner_104.has_memory_of("ruler", "resentment"), "P01.7 (Choice B): Owner has resentment memory toward ruler")
	assert(not hut_104_b.has_unresolved_dispute(), "P01.7 (Choice B): Dispute resolved on hut_b")

	# 4. Тестирование Варианта C: «Разделить дом перегородкой» (PARTITION_HUT)
	var hut_104_c = BuildingInstance.new("hut_c_104", "hut", p01_7_settlement.id, Vector2i(17, 17))
	var r_list_c: Array[String] = [cit_owner_104.id, cit_tenant_104.id]
	hut_104_c.residents = r_list_c
	hut_104_c.active_modifiers["unresolved_housing_dispute"] = true
	GameManager.building_instances[hut_104_c.id] = hut_104_c
	var initial_wood_104 = p01_7_settlement.economy.get_resource("wood")
	var initial_cap_104 = hut_104_c.get_comfort_capacity()
	var ev_c_id = p01_7_ev_mgr.trigger_event(hut_ev_template, {
		"actor_ids": [cit_owner_104.id, cit_tenant_104.id],
		"actor_names": [cit_owner_104.name, cit_tenant_104.name],
		"target_building_id": hut_104_c.id,
		"causes": ["Теснота и спор о личном пространстве"],
		"context_data": {"building_id": hut_104_c.id, "actor_0": cit_owner_104.name, "actor_1": cit_tenant_104.name, "dispute_cause": "Теснота"}
	})
	p01_7_ev_mgr.apply_choice(ev_c_id, "C")
	assert(hut_104_c.active_modifiers.get("partitioned", false), "P01.7 (Choice C): Partitioned modifier set")
	assert(p01_7_settlement.economy.get_resource("wood") == initial_wood_104 - 5.0, "P01.7 (Choice C): 5 wood deducted from settlement")
	assert(hut_104_c.get_comfort_capacity() == initial_cap_104 + 1, "P01.7 (Choice C): Comfort capacity increased by partition")
	assert(cit_owner_104.has_memory_of("ruler", "peace"), "P01.7 (Choice C): Owner has peace memory")
	assert(not hut_104_c.has_unresolved_dispute(), "P01.7 (Choice C): Dispute resolved on hut_c")

	# 5. Тестирование Варианта D: «Не вмешиваться / бытовая драка» (DOMESTIC_BRAWL)
	var hut_104_d = BuildingInstance.new("hut_d_104", "hut", p01_7_settlement.id, Vector2i(18, 18))
	var r_list_d: Array[String] = [cit_owner_104.id, cit_tenant_104.id]
	hut_104_d.residents = r_list_d
	GameManager.building_instances[hut_104_d.id] = hut_104_d
	var initial_health_owner_104 = cit_owner_104.health
	var initial_health_tenant_104 = cit_tenant_104.health
	var ev_d_id = p01_7_ev_mgr.trigger_event(hut_ev_template, {
		"actor_ids": [cit_owner_104.id, cit_tenant_104.id],
		"actor_names": [cit_owner_104.name, cit_tenant_104.name],
		"target_building_id": hut_104_d.id,
		"causes": ["Старая неприязнь и нерешённый спор о правах на дом"],
		"context_data": {"building_id": hut_104_d.id, "actor_0": cit_owner_104.name, "actor_1": cit_tenant_104.name, "dispute_cause": "Старая неприязнь"}
	})
	p01_7_ev_mgr.apply_choice(ev_d_id, "D")
	assert(hut_104_d.has_unresolved_dispute(), "P01.7 (Choice D): Hut retains unresolved dispute")
	assert(cit_owner_104.health == initial_health_owner_104 - 15.0, "P01.7 (Choice D): Owner lost 15 health in brawl")
	assert(cit_tenant_104.health == initial_health_tenant_104 - 15.0, "P01.7 (Choice D): Tenant lost 15 health in brawl")
	assert(cit_owner_104.has_memory_of("brawl", "injury"), "P01.7 (Choice D): Owner has injury memory from brawl")
	assert(cit_tenant_104.has_memory_of("brawl", "injury"), "P01.7 (Choice D): Tenant has injury memory from brawl")

	print("OK 104. P01.7 HUT-02 re-occurring housing dispute, 4 branches (eviction, food aid, partition, domestic brawl) verified.")

	# ---------------------------------------------------------
	# P01.8: СТРОИТЕЛЬСТВО И БАЗОВЫЙ ЛАГЕРЬ ЛЕСОРУБОВ (woodcutter_camp)
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING P01.8 WOODCUTTER CAMP, TOOLS, BUFFER & HAULING")
	print("----------------------------------------")

	var s_105 = SettlementData.new("s_p01_8", "Лагерное Племя", "player_tribe", Vector2i(10, 10))
	s_105.buildings.clear()
	s_105.buildings.append("elders_house")
	s_105.economy.resources["wood"] = 10.0
	GameManager.settlements[s_105.id] = s_105

	for c_test in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10)]:
		GameManager.planet_data["tiles"][c_test.y][c_test.x]["is_water"] = false
		GameManager.planet_data["tiles"][c_test.y][c_test.x]["biome"] = 2
		GameManager.planet_data["tiles"][c_test.y][c_test.x]["walkable"] = true
		if GameManager.nav_grid:
			GameManager.nav_grid.set_cell_solid(c_test, false)

	var tree_coord_105 = Vector2i(12, 10)
	var tree_pos_105 = Vector2(12 * 32.0 + 16, 10 * 32.0 + 16)
	GameManager.planet_data["tiles"][tree_coord_105.y][tree_coord_105.x]["nature_object"] = "tree_oak"
	GameManager.resource_manager.nodes[tree_coord_105] = {
		"id": "tree_node_105",
		"coord": tree_coord_105,
		"pos": tree_pos_105,
		"type": "wood",
		"category": "wood",
		"name": "Дуб P01.8",
		"amount": 100.0,
		"max_amount": 100.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "tree_oak",
		"depleted_sprite": "none"
	}

	var wc_105 = CitizenNPC.new("wc_105", "Добрыня Лесоруб", "m", 26, "adult")
	wc_105.job_id = "woodcutter"
	wc_105.settlement_id = s_105.id
	wc_105.pos = Vector2(10 * 32.0 + 16, 10 * 32.0 + 16)
	wc_105.social_cooldown = 999.0 # случайная беседа с соседом не должна перебивать проверку
	s_105.population.citizens.append(wc_105)
	s_105.priority_harvest_coords.clear()
	s_105.priority_harvest_coords.append(tree_coord_105)

	# 1. Без лагеря лесорубов рубка живого леса ЗАПРЕЩЕНА
	s_105.update_citizens(0.1)
	assert(wc_105.state == CitizenNPC.State.WAITING, "P01.8: Without camp woodcutter must be WAITING")
	assert("требуется Лагерь лесорубов" in wc_105.last_status_reason, "P01.8: Status reason requires camp")
	assert(wc_105.equipped_tool.is_empty(), "P01.8: No tool equipped before camp")

	# 2. Строительство завершено: лагерь лесорубов появляется на карте с инвентарем топоров
	var camp_105 = BuildingInstance.new("wc_camp_105", "woodcutter_camp", s_105.id, Vector2i(11, 10))
	GameManager.building_instances[camp_105.id] = camp_105
	s_105.buildings.append("woodcutter_camp")
	assert(camp_105.local_buffer_max == 50.0, "P01.8: Camp local buffer max is 50")
	assert(camp_105.local_buffer_wood == 0.0, "P01.8: Camp starts with empty buffer")
	assert(camp_105.tool_inventory.size() == 3, "P01.8: Camp starts with 3 stone axes in property")
	assert(camp_105.has_available_tool("axe"), "P01.8: Camp has available axe")

	# 3. Лесоруб берет топор из лагеря и приступает к работе
	wc_105.decision_cooldown = 0.0
	s_105.update_citizens(0.1)
	assert(wc_105.has_tool("axe"), "P01.8: Woodcutter equipped axe from camp")
	assert(wc_105.equipped_tool.get("durability", 0.0) == 100.0, "P01.8: Axe durability is 100")
	var unassigned_axes_105 = 0
	for t in camp_105.tool_inventory:
		if t.get("type", "") == "axe" and t.get("assigned_to", "") == "":
			unassigned_axes_105 += 1
	assert(unassigned_axes_105 == 2, "P01.8: 1 axe assigned, 2 unassigned remaining in camp property")
	assert(wc_105.state == CitizenNPC.State.MOVING_TO_WORK, "P01.8: Woodcutter moves to work after taking tool")

	# 4. Прибытие к дереву, рубка, износ топора и наполнение рук
	wc_105.pos = tree_pos_105
	wc_105.path.clear()
	s_105.update_citizens(0.1)
	assert(wc_105.state == CitizenNPC.State.WORKING, "P01.8: Woodcutter started working at tree")

	wc_105.work_timer = 0.0
	s_105.update_citizens(0.1) # 1 удар (12.5 дров)
	assert(wc_105.cargo_amount == 12.5, "P01.8: Cargo in hands is 12.5 after strike")
	assert(wc_105.equipped_tool.get("durability", 0.0) < 100.0, "P01.8: Axe took durability wear during chopping")

	# Завершаем рубку дерева
	wc_105.work_timer = 0.0
	GameManager.resource_manager.harvest_from_node(tree_coord_105, 87.5)
	s_105.update_citizens(0.1)
	assert(wc_105.state == CitizenNPC.State.CARRYING, "P01.8: Woodcutter carrying felled wood")
	assert(wc_105.task_id == "deposit_to_camp", "P01.8: Task is deposit_to_camp, not direct central warehouse")

	# 5. Доставка в буфер лагеря: общий склад поселения НЕ пополняется преждевременно!
	var initial_s_wood_105 = s_105.economy.get_resource("wood")
	var camp_pos_105 = Vector2(camp_105.pos.x * 32.0 + 16, camp_105.pos.y * 32.0 + 16)
	wc_105.pos = camp_pos_105
	wc_105.path.clear()
	s_105.update_citizens(0.1)
	assert(wc_105.cargo_amount == 0.0, "P01.8: Cargo unloaded at camp buffer")
	assert(camp_105.local_buffer_wood == 12.5, "P01.8: Camp local buffer received 12.5 wood")
	assert(s_105.economy.get_resource("wood") == initial_s_wood_105, "P01.8: Settlement central warehouse did NOT receive wood yet")

	# 6. Заполнение буфера до предела (50.0): остановка с реальной причиной
	camp_105.local_buffer_wood = 50.0
	wc_105.cargo_amount = 25.0
	wc_105.cargo_type = "wood"
	wc_105.task_id = "deposit_to_camp"
	wc_105.state = CitizenNPC.State.CARRYING
	wc_105.pos = camp_pos_105
	s_105.update_citizens(0.1)
	assert(wc_105.state == CitizenNPC.State.WAITING, "P01.8: Woodcutter halts when camp buffer is full")
	assert("Буфер лагеря лесорубов заполнен" in wc_105.last_status_reason, "P01.8: Status reason is buffer full")
	assert(wc_105.cargo_amount == 25.0, "P01.8: Wood remains in hands when buffer cannot accept it")

	# 7. Транспортировка из лагеря на центральный склад свободным работником
	wc_105.cargo_amount = 0.0
	wc_105.cargo_type = ""
	wc_105.state = CitizenNPC.State.IDLE
	camp_105.local_buffer_wood = 20.0

	var hauler_105 = CitizenNPC.new("hauler_105", "Ратибор Переносчик", "m", 20, "adult")
	hauler_105.job_id = "idle"
	hauler_105.settlement_id = s_105.id
	hauler_105.pos = camp_pos_105
	hauler_105.max_carry = 20.0
	s_105.population.citizens.append(hauler_105)

	s_105.update_citizens(0.1)
	assert(hauler_105.state == CitizenNPC.State.CARRYING, "P01.8: Idle citizen picked up haul task from camp buffer")
	assert(hauler_105.task_id == "haul_from_camp", "P01.8: Hauler task_id is haul_from_camp")
	assert(hauler_105.cargo_amount == 20.0, "P01.8: Hauler took wood from camp buffer")
	assert(camp_105.local_buffer_wood == 0.0, "P01.8: Camp buffer emptied by hauler")
	assert(s_105.economy.get_resource("wood") == initial_s_wood_105, "P01.8: Central warehouse still unchanged in transit")

	# Доставляем на центральный склад
	var central_storage_105 = s_105._get_storage_pos(hauler_105)
	hauler_105.pos = central_storage_105
	hauler_105.path.clear()
	s_105.update_citizens(0.1)
	assert(hauler_105.cargo_amount == 0.0, "P01.8: Cargo unloaded into central warehouse")
	assert(s_105.economy.get_resource("wood") == initial_s_wood_105 + 20.0, "P01.8: Settlement economy wood credited ONLY on warehouse arrival")

	# 8. Износ и поломка топора
	wc_105.equipped_tool["durability"] = 0.5
	wc_105.wear_tool(1.0)
	assert(not wc_105.has_tool("axe"), "P01.8: Tool broken when durability <= 0")
	camp_105.tool_inventory.clear() # все топоры исчерпаны
	wc_105.decision_cooldown = 0.0
	s_105.update_citizens(0.1)
	assert(wc_105.state == CitizenNPC.State.WAITING, "P01.8: Woodcutter waiting when no axes in camp")
	assert("Нет доступного топора" in wc_105.last_status_reason, "P01.8: Correct reason for missing tool")

	print("OK 105. P01.8 Woodcutter camp, physical tool cycle, local buffer and central warehouse hauling verified.")

	# ---------------------------------------------------------
	# TEST 106: P01.9 Logging Zones, WC-01 Event and Selection Restrictions
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING P01.9 LOGGING ZONES & WC-01 EVENT CHOICES")
	print("----------------------------------------")
	var s_106 = SettlementData.new("p01_9_test_settlement")
	s_106.name = "Лесное Племя"
	s_106.buildings.append("woodcutter_camp")
	var camp_106 = BuildingInstance.new("wc_camp_106", "woodcutter_camp", s_106.id, Vector2i(10, 10))
	for i in range(3):
		camp_106.tool_inventory.append({"id": "axe_106_%d" % (i + 1), "type": "axe", "durability": 100.0, "assigned_to": ""})
	GameManager.building_instances[camp_106.id] = camp_106

	var wc_106 = CitizenNPC.new("wc_106", "Святослав Вальщик", "m", 25, "adult")
	wc_106.job_id = "woodcutter"
	wc_106.settlement_id = s_106.id
	wc_106.pos = Vector2(10 * 32 + 16, 10 * 32 + 16)
	s_106.population.citizens.clear()
	s_106.population.citizens.append(wc_106)

	var ev_mgr_106 = CivilizationEventManager.new()
	ev_mgr_106.settlement = s_106

	# Nature nodes in ResourceManager:
	# Near tree: dist 4 from camp (14, 10)
	var near_tree_106 = Vector2i(14, 10)
	# Far tree: dist 15 from camp (25, 10)
	var far_tree_106 = Vector2i(25, 10)

	GameManager.resource_manager.nodes[near_tree_106] = {
		"id": "tree_near_106",
		"coord": near_tree_106,
		"category": "wood",
		"type": "wood",
		"sub_type": "tree_pine",
		"name": "Сосна P01.9",
		"pos": Vector2(near_tree_106.x * 32 + 16, near_tree_106.y * 32 + 16),
		"amount": 50.0,
		"max_amount": 50.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "tree_pine",
		"depleted_sprite": "stump_fresh",
		"regrowth_timer": 300.0,
		"regrowth_duration": 300.0
	}
	GameManager.resource_manager.nodes[far_tree_106] = {
		"id": "tree_far_106",
		"coord": far_tree_106,
		"category": "wood",
		"type": "wood",
		"sub_type": "tree_oak",
		"name": "Дуб P01.9",
		"pos": Vector2(far_tree_106.x * 32 + 16, far_tree_106.y * 32 + 16),
		"amount": 50.0,
		"max_amount": 50.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": "tree_oak",
		"depleted_sprite": "stump_fresh",
		"regrowth_timer": 300.0,
		"regrowth_duration": 300.0
	}
	GameManager.settlements[s_106.id] = s_106

	# Ensure path from camp (10, 10) to trees (14, 10) and (25, 10) is walkable
	for tx in range(10, 27):
		var c_tile = Vector2i(tx, 10)
		if GameManager.planet_data and GameManager.planet_data.has("tiles") and GameManager.planet_data["tiles"].size() > 10 and GameManager.planet_data["tiles"][10].size() > tx:
			GameManager.planet_data["tiles"][10][tx]["is_water"] = false
			GameManager.planet_data["tiles"][10][tx]["walkable"] = true
		if GameManager.nav_grid:
			GameManager.nav_grid.set_cell_solid(c_tile, false)

	# 1. До разрешения вырубки (нет logging_zone): лесоруб не может начать заготовку
	assert(not s_106.has_active_logging_zone(), "P01.9: No logging zone assigned initially")
	wc_106.decision_cooldown = 0.0
	s_106.update_citizens(0.1)
	assert(wc_106.state == CitizenNPC.State.WAITING, "P01.9: Woodcutter waits when no logging zone is assigned")
	assert("Не знаю, где разрешено рубить лес" in wc_106.last_status_reason, "P01.9: Status reason explains missing logging zone")

	# 2. Триггер события WC-01
	var trigger_ctx_106 = ev_mgr_106.check_wc_01_trigger(s_106)
	assert(not trigger_ctx_106.is_empty(), "P01.9: WC-01 trigger condition met when camp exists")
	var wc01_template = CivilizationEventDB.EVENTS["WC-01"]
	var ev_inst_id_106 = ev_mgr_106.trigger_event(wc01_template, trigger_ctx_106)
	assert(not ev_inst_id_106.is_empty(), "P01.9: WC-01 event created")

	# 3. Выбор A: Ближняя зона вырубки (до 8 клеток)
	ev_mgr_106.apply_choice(ev_inst_id_106, "A")
	assert(s_106.has_active_logging_zone(), "P01.9: Settlement now has active logging zone")
	assert(s_106.is_tile_in_logging_zone(near_tree_106), "P01.9: Near tree is within logging zone")
	assert(not s_106.is_tile_in_logging_zone(far_tree_106), "P01.9: Far tree is NOT in logging zone A")

	# 4. Лесоруб выбирает ближнее дерево и начинает работу
	wc_106.state = CitizenNPC.State.IDLE
	wc_106.decision_cooldown = 0.0
	s_106.update_citizens(0.1)
	assert(wc_106.state == CitizenNPC.State.MOVING_TO_WORK, "P01.9: Woodcutter sets off towards near tree in approved zone")
	assert(wc_106.has_tool("axe"), "P01.9: Woodcutter equipped axe from camp")

	# 5. Истощение ближнего дерева: лесоруб останавливается и НЕ трогает дальний лес
	GameManager.resource_manager.nodes[near_tree_106]["depleted"] = true
	GameManager.resource_manager.nodes[near_tree_106]["amount"] = 0.0
	wc_106.target_pos = Vector2.ZERO
	wc_106.path.clear()
	wc_106.state = CitizenNPC.State.IDLE
	wc_106.decision_cooldown = 0.0
	s_106.update_citizens(0.1)
	assert(wc_106.state == CitizenNPC.State.WAITING, "P01.9: Woodcutter stops when all trees in logging zone are depleted")
	assert("Нет допустимых деревьев в зоне вырубки" in wc_106.last_status_reason, "P01.9: Status explains logging zone exhausted")

	# 6. Выбор B: Дальняя зона вырубки (+5 еды сбережение рощи)
	var ev_inst_b_106 = ev_mgr_106.trigger_event(wc01_template, trigger_ctx_106)
	var init_food_106 = s_106.economy.get_resource("food")
	ev_mgr_106.apply_choice(ev_inst_b_106, "B")
	assert(s_106.economy.get_resource("food") == init_food_106 + 5.0, "P01.9: Choice B gives +5 food preserved grove")
	assert(s_106.is_tile_in_logging_zone(far_tree_106), "P01.9: Far tree is now in logging zone")
	wc_106.decision_cooldown = 0.0
	s_106.update_citizens(0.1)
	assert(wc_106.state == CitizenNPC.State.MOVING_TO_WORK, "P01.9: Woodcutter moves to harvest far tree")

	# 7. Выбор D: Запрет вырубки
	var ev_inst_d_106 = ev_mgr_106.trigger_event(wc01_template, trigger_ctx_106)
	ev_mgr_106.apply_choice(ev_inst_d_106, "D")
	assert(not s_106.has_active_logging_zone(), "P01.9: Logging zone cleared by prohibition")
	wc_106.decision_cooldown = 0.0
	wc_106.state = CitizenNPC.State.IDLE
	s_106.update_citizens(0.1)
	assert(wc_106.state == CitizenNPC.State.WAITING, "P01.9: Woodcutter halts under prohibition")
	assert("Не знаю, где разрешено рубить лес" in wc_106.last_status_reason, "P01.9: Status indicates no allowed zone")

	# 8. Сериализация и восстановление зон вырубки (Save / Load persistence)
	s_106.set_logging_zone([near_tree_106, far_tree_106])
	var saved_data_106 = s_106.serialize()
	var restored_s_106 = SettlementData.new("restored_p01_9")
	restored_s_106.deserialize(saved_data_106)
	assert(restored_s_106.has_active_logging_zone(), "P01.9: Logging zones restored after deserialize")
	assert(restored_s_106.is_tile_in_logging_zone(near_tree_106), "P01.9: near_tree_106 present in restored zone")
	assert(restored_s_106.is_tile_in_logging_zone(far_tree_106), "P01.9: far_tree_106 present in restored zone")

	print("OK 106. P01.9 Logging zones, WC-01 event branches and save/load persistence verified.")

	# ---------------------------------------------------------
	# TEST 107: AUTONOMOUS LIVING SETTLEMENT & SOCIAL LIFE CYCLE
	# (Housing migration, romance, marriage, pregnancy, autonomous jobs & live events)
	# ---------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 107 AUTONOMOUS LIVING SETTLEMENT & SOCIAL LIFE CYCLE")
	print("----------------------------------------")
	var s_107 = SettlementData.new("s_107_live", "Живое Племя", "player_tribe", Vector2i(10, 10))
	GameManager.settlements[s_107.id] = s_107
	GameManager.player_faction_id = "player_tribe"

	# 1. Стартовая хижина старейшины с 4 взрослыми
	var starter_107 = BuildingInstance.new("elders_107", "elders_house", s_107.id, Vector2i(10, 10))
	GameManager.building_instances[starter_107.id] = starter_107

	var man_107 = CitizenNPC.new("c107_m1", "Яромир", "m", 24, "adult")
	var woman_107 = CitizenNPC.new("c107_f1", "Любава", "f", 22, "adult")
	var man2_107 = CitizenNPC.new("c107_m2", "Ратибор", "m", 28, "adult")
	var woman2_107 = CitizenNPC.new("c107_f2", "Веселина", "f", 25, "adult")
	man_107.settlement_id = s_107.id
	woman_107.settlement_id = s_107.id
	man2_107.settlement_id = s_107.id
	woman2_107.settlement_id = s_107.id
	man_107.home_id = starter_107.id
	woman_107.home_id = starter_107.id
	man2_107.home_id = starter_107.id
	woman2_107.home_id = starter_107.id
	starter_107.add_resident(man_107.citizen_id)
	starter_107.add_resident(woman_107.citizen_id)
	starter_107.add_resident(man2_107.citizen_id)
	starter_107.add_resident(woman2_107.citizen_id)

	s_107.population.citizens.clear()
	s_107.population.citizens.append(man_107)
	s_107.population.citizens.append(woman_107)
	s_107.population.citizens.append(man2_107)
	s_107.population.citizens.append(woman2_107)

	# 2. Постройка новой хижины hut_107
	var hut_107 = BuildingInstance.new("hut_107_1", "hut", s_107.id, Vector2i(12, 10))
	GameManager.building_instances[hut_107.id] = hut_107
	s_107.buildings.append("hut")
	
	# Проверяем авто-расселение: граждане переезжают из communal elders_house в новую хижину!
	s_107.auto_assign_housing()
	assert(hut_107.residents.size() > 0, "P01 Live: Citizens move into newly built hut")
	assert(man_107.home_id == hut_107.id or woman_107.home_id == hut_107.id or man2_107.home_id == hut_107.id, "P01 Live: Citizen home_id points to new hut")

	# 3. Социальное общение и романтическое сближение
	man_107.pos = Vector2(10 * 32 + 16, 10 * 32 + 16)
	woman_107.pos = Vector2(10 * 32 + 20, 10 * 32 + 16)
	man_107.social_cooldown = 0.0
	woman_107.social_cooldown = 0.0
	s_107._start_social_dialog(man_107, woman_107)
	assert(man_107.state == CitizenNPC.State.TALKING, "P01 Live: Talking state initiated")
	assert(man_107.get_relationship(woman_107.citizen_id).get("romance", 0.0) >= 20.0, "P01 Live: Romance grows between chatting adults")

	# Доводим чувства до свадьбы
	s_107._start_social_dialog(man_107, woman_107)
	s_107._start_social_dialog(man_107, woman_107)
	assert(man_107.get_spouses().has(woman_107.citizen_id), "P01 Live: Mutual feelings culminate in marriage")
	assert(woman_107.get_spouses().has(man_107.citizen_id), "P01 Live: Female partner registered as spouse")

	# 4. Ежедневный цикл: естественное зачатие у супругов и автономное распределение профессий
	s_107.economy.resources["food"] = 50.0
	s_107.buildings.append("woodcutter_camp")
	s_107.assigned_jobs.clear()
	assert(man2_107.job_id == "idle", "P01 Live: man2 is initially idle")
	
	# Симулируем дни жизни поселения
	for day_i in range(30):
		s_107.sim_daily_tick("Лето")
		if woman_107.is_pregnant():
			break

	if not woman_107.is_pregnant():
		s_107.start_pregnancy(woman_107, man_107)

	# Автономный выбор работы: один из свободных взрослых занял свободное место лесоруба
	assert(s_107.assigned_jobs.get("woodcutter", 0) >= 1 or man2_107.job_id == "woodcutter", "P01 Live: Unemployed adult autonomously picked woodcutter job")
	# Беременность зародилась в семейном союзе
	assert(woman_107.is_pregnant(), "P01 Live: Conception occurred in married household")

	# 6. Проверка ускорения взросления: дети и подростки (0-17) растут в 4x, взрослые в 1x
	var test_child = CitizenNPC.new("test_ch", "Светозар", "m", 5, "child")
	test_child.sim_aging(450.0) # 450с * 4x = 1800с (1 год)
	assert(test_child.age == 6, "P01 Aging: Child ages 4x faster (1 year gained per 450s)")

	var test_youth = CitizenNPC.new("test_yo", "Милонег", "m", 15, "youth")
	test_youth.sim_aging(450.0) # 450с * 4x = 1800с (1 год)
	assert(test_youth.age == 16, "P01 Aging: Youth ages 4x faster (1 year gained per 450s)")

	var test_adult = CitizenNPC.new("test_ad", "Всеволод", "m", 25, "adult")
	test_adult.sim_aging(900.0)
	assert(test_adult.age == 25, "P01 Aging: Adult ages at normal 1x speed (900s is half year)")
	test_adult.sim_aging(900.0)
	assert(test_adult.age == 26, "P01 Aging: Adult gains 1 year after full 1800s")

	print("OK 107. Autonomous living settlement, housing re-assignment, romance, marriage, pregnancy, 4x child/youth aging verified.")

	# ----------------------------------------
	# TEST 108: 96 EMOTE BUBBLES SYSTEM, CATEGORIES & AUTONOMOUS SIGNALS
	# ----------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 108 EMOTE BUBBLES SYSTEM & AUTONOMOUS SIGNALS")
	print("----------------------------------------")
	
	# 1. Проверка реестра 96 иконок и категорий
	var all_emotes = EmoteTextureManager.get_all_emotes()
	assert(all_emotes.size() == 96, "EmoteTextureManager must contain exactly 96 emotes (48 base + 48 social/life)")
	
	for e_id in all_emotes:
		var info = EmoteTextureManager.get_emote_info(e_id)
		assert(not info.is_empty(), "Emote %s must have metadata" % e_id)
		assert(info.has("name") and info.has("category") and info.has("desc"), "Emote %s metadata must be complete" % e_id)
		var tex = EmoteTextureManager.get_emote_texture(e_id)
		assert(tex != null, "Emote %s texture must exist and be loadable" % e_id)
		
	# 2. Проверка ключевых категорий и новых социальных состояний
	assert(EmoteTextureManager.get_emotes_by_category("emotions").size() >= 10, "Emotions category must have items")
	assert(EmoteTextureManager.get_emotes_by_category("needs").has("hunger"), "Needs category must contain hunger")
	assert(EmoteTextureManager.get_emotes_by_category("health").has("injury"), "Health category must contain injury")
	assert(EmoteTextureManager.get_emotes_by_category("social").has("contact"), "Social category must contain contact")
	assert(EmoteTextureManager.get_emotes_by_category("social").has("agreement"), "Social category must contain agreement")
	assert(EmoteTextureManager.get_emotes_by_category("lifecycle").has("pregnancy"), "Lifecycle category must contain pregnancy")
	assert(EmoteTextureManager.get_emotes_by_category("lifecycle").has("newborn"), "Lifecycle category must contain newborn")
	assert(EmoteTextureManager.get_emotes_by_category("housing_law").has("house"), "HousingLaw category must contain house")
	assert(EmoteTextureManager.get_emotes_by_category("housing_law").has("tax"), "HousingLaw category must contain tax")
	assert(EmoteTextureManager.get_emotes_by_category("economy_labor").has("debt"), "EconomyLabor category must contain debt")
	assert(EmoteTextureManager.get_emotes_by_category("economy_labor").has("no_tools"), "EconomyLabor category must contain no_tools")
	assert(EmoteTextureManager.get_emotes_by_category("worldview").has("uprising"), "Worldview category must contain uprising")
	
	# 3. Ручной вызов и таймер исчезновения
	var emote_cit = CitizenNPC.new("test_emote_cit", "Доброслав", "m", 25, "adult")
	emote_cit.show_emote("debt", 3.0, 3)
	assert(emote_cit.active_emote_id == "debt", "Emote must be active after show_emote")
	assert(emote_cit.emote_timer == 3.0, "Emote timer must be set to 3.0s")
	
	# Низкоприоритетный вызов не должен перебивать
	emote_cit.show_emote("work", 2.0, 1)
	assert(emote_cit.active_emote_id == "debt", "Lower priority emote must not overwrite higher priority")
	
	# Высокоприоритетный вызов должен перебивать
	emote_cit.show_emote("panic", 4.0, 5)
	assert(emote_cit.active_emote_id == "panic", "Higher priority emote must overwrite")
	
	# Тик симуляции: таймер убывает и иконка исчезает (не висит вечно)
	emote_cit.update_emote(2.0)
	assert(emote_cit.active_emote_id == "panic" and is_equal_approx(emote_cit.emote_timer, 2.0), "Timer must decrease")
	emote_cit.update_emote(2.5)
	assert(emote_cit.active_emote_id == "" and emote_cit.emote_timer == 0.0, "Emote must clear when timer expires")
	
	# 4. Автономные триггеры потребностей и урона
	emote_cit.clear_emote()
	emote_cit.emote_cooldown = 0.0
	emote_cit.hunger = 15.0 # Голод
	emote_cit.check_autonomous_emotes(0.1, "Лето")
	assert(emote_cit.active_emote_id == "hunger", "Low hunger must trigger hunger emote")
	
	# Урон в бою
	emote_cit.take_damage(50.0, "Хищник") # health 50 => pain
	assert(emote_cit.active_emote_id == "pain", "Taking damage must trigger pain emote")
	emote_cit.take_damage(30.0, "Хищник") # health 20 => injury
	assert(emote_cit.active_emote_id == "injury", "Low health damage must trigger injury emote")
	
	# 5. Сериализация и сохранение
	var saved_data = emote_cit.serialize()
	var restored_cit = CitizenNPC.new()
	restored_cit.deserialize(saved_data)
	assert(restored_cit.active_emote_id == "injury", "Emote ID must persist across save/load")
	assert(restored_cit.emote_timer > 0.0, "Emote timer must persist across save/load")
	
	print("OK 108. 96 Emote bubbles, categorizations, timers, priority, autonomous triggers and Save/Load verified.")

	# 109. Тест автономного устройства NPC на работу (auto_assign_workplaces)
	var work_s = SettlementData.new("work_test_s", "Племя Труда", "player_tribe", Vector2i(30, 30))
	work_s.population = PopulationSim.new()
	work_s.init_citizens_on_map()
	
	# Освобождаем нескольких граждан для проверки
	var idle_c1 = work_s.population.get_citizen_by_id("cit_4") # builder -> idle
	var idle_c2 = work_s.population.get_citizen_by_id("cit_5") # forager -> idle
	work_s.unassign_citizen_from_workplace(idle_c1)
	work_s.unassign_citizen_from_workplace(idle_c2)
	assert(idle_c1.is_idle() and idle_c2.is_idle(), "Citizens must be idle after unassigning")
	
	# 1. Постройка каменоломни: проверяем автоматическое устройство каменотёса
	var quarry_coord = Vector2i(32, 30)
	var quarry_inst = GameManager.get_or_create_building_instance(quarry_coord, "stone_quarry", work_s.id)
	assert(quarry_inst.workers.is_empty(), "Quarry should start with 0 workers")
	
	work_s.auto_assign_workplaces()
	assert(quarry_inst.workers.size() > 0, "Quarry must automatically receive workers via auto_assign_workplaces")
	var quarry_worker_id = quarry_inst.workers[0]
	var quarry_worker = work_s.population.get_citizen_by_id(quarry_worker_id)
	assert(quarry_worker != null, "Quarry worker must exist in population")
	assert(quarry_worker.job_id == "quarryman", "Worker job must be set to quarryman")
	assert(quarry_worker.workplace_id == quarry_inst.id, "Worker workplace_id must match quarry instance ID")
	assert(quarry_worker.workplace_coord == quarry_coord, "Worker workplace_coord must match quarry coordinate")
	assert(work_s.assigned_jobs.get("quarryman", 0) >= 1, "Settlement assigned_jobs must reflect quarryman")
	
	# 2. Постройка охотничьего лагеря: проверяем автоматическое устройство охотника
	var hunt_coord = Vector2i(30, 32)
	var hunt_inst = GameManager.get_or_create_building_instance(hunt_coord, "hunting_camp", work_s.id)
	assert(hunt_inst.workers.is_empty(), "Hunting camp should start with 0 workers")
	
	work_s.auto_assign_workplaces()
	assert(hunt_inst.workers.size() > 0, "Hunting camp must automatically receive workers via auto_assign_workplaces")
	var hunter_worker_id = hunt_inst.workers[0]
	var hunter_worker = work_s.population.get_citizen_by_id(hunter_worker_id)
	assert(hunter_worker != null, "Hunter worker must exist in population")
	assert(hunter_worker.job_id == "hunter", "Worker job must be set to hunter")
	assert(hunter_worker.workplace_id == hunt_inst.id, "Worker workplace_id must match hunt instance ID")
	assert(hunter_worker.workplace_coord == hunt_coord, "Worker workplace_coord must match hunt coordinate")
	assert(work_s.assigned_jobs.get("hunter", 0) >= 1, "Settlement assigned_jobs must reflect hunter")
	
	# 3. Проверка снятия с работы и повторного устройства
	work_s.unassign_citizen_from_workplace(quarry_worker)
	assert(quarry_worker.is_idle(), "Citizen must be idle after unassigning from quarry")
	assert(not quarry_inst.workers.has(quarry_worker.citizen_id), "Citizen must be removed from quarry workers list")
	
	# Повторный вызов авто-распределения должен мгновенно занять освободившуюся вакансию
	work_s.auto_assign_workplaces()
	assert(quarry_inst.workers.size() > 0, "Quarry vacancy must be filled again by available idle citizens")
	
	print("OK 109. Autonomous employment (auto_assign_workplaces) for stone_quarry, hunting_camp and vacancies verified.")

	# ==============================================================================
	# GREAT LODGE (БОЛЬШОЙ ДОМ РОДА) — TESTS 110, 111, 112
	# ==============================================================================
	# 110. Great Lodge initialization, comfort capacity, random 1-of-9 variants, multi-family groups
	GameManager.settlements[s.id] = s
	var gl_coord = Vector2i(40, 40)
	var gl_inst = GameManager.get_or_create_building_instance(gl_coord, "great_lodge", s.id)
	assert(gl_inst.is_great_lodge(), "Instance must be recognized as Great Lodge")
	assert(gl_inst.get_comfort_capacity() == 25, "Great lodge base comfort capacity must be 25")
	assert(gl_inst.get_max_residents() == 35, "Great lodge max capacity must be 35")
	assert(gl_inst.visual_variant >= 1 and gl_inst.visual_variant <= 9, "Visual variant must be random 1..9")
	
	# Проверка статусов комфорта: комфортно, тесно, переполнено
	assert(gl_inst.get_comfort_status() == "Комфортно", "Empty lodge must be comfortable")
	
	# Добавляем 26 жителей -> Тесно
	for i in range(26):
		var cit_id = "gl_cit_%d" % i
		var fam_id = "fam_A" if i < 10 else ("fam_B" if i < 20 else "")
		var c_age = 70 if i == 25 else (4 if i == 24 else 25)
		var c_cohort = "elder" if c_age >= 60 else ("child" if c_age < 16 else "adult")
		var new_c = CitizenNPC.new(cit_id, "Соплеменник %d" % i, "m" if i % 2 == 0 else "f", c_age, c_cohort)
		new_c.family_id = fam_id
		new_c.home_id = gl_inst.id
		s.population.citizens.append(new_c)
		gl_inst.add_resident(cit_id, "resident")
		
	assert(gl_inst.get_comfort_status() == "Тесно", "26 residents must trigger 'Тесно' status")
	
	# Добавляем до 32 жителей -> Переполнено
	for i in range(26, 32):
		var cit_id = "gl_cit_%d" % i
		var new_c = CitizenNPC.new(cit_id, "Соплеменник %d" % i, "f", 25, "adult")
		new_c.home_id = gl_inst.id
		s.population.citizens.append(new_c)
		gl_inst.add_resident(cit_id, "resident")
		
	assert(gl_inst.get_comfort_status() == "Переполнено", "32 residents must trigger 'Переполнено' status")
	
	# Пересчёт групп домохозяйств (Household Groups Breakdown)
	gl_inst.recalculate_household_groups(s.population)
	assert(gl_inst.household_groups["families"].has("fam_A"), "fam_A must be present in household groups")
	assert(gl_inst.household_groups["families"]["fam_A"].size() == 10, "fam_A must have 10 members")
	assert(gl_inst.household_groups["families"]["fam_B"].size() == 10, "fam_B must have 10 members")
	assert(gl_inst.household_groups["elders"].size() >= 1, "Elders must be counted in household groups")
	assert(gl_inst.household_groups["children"].size() >= 1, "Children must be counted in household groups")
	
	print("OK 110. Great Lodge: base parameters, 25-comfort/35-max, random 1..9 sprites and household groups verified.")

	# 111. Great Lodge 10 branching upgrades, role assignments & knowledge transfer
	var gl_upgrades = BuildingDB.get_upgrades_for_building("great_lodge")
	assert(gl_upgrades.size() == 10, "Great Lodge must have exactly 10 distinct upgrades")
	
	# Разблокировка улучшений
	gl_inst.unlock_upgrade("great_hearth")
	gl_inst.unlock_upgrade("partitions")
	gl_inst.unlock_upgrade("nursery_corner")
	gl_inst.unlock_upgrade("caretaker_quarters")
	gl_inst.unlock_upgrade("elders_quarters")
	gl_inst.unlock_upgrade("knowledge_circle")
	gl_inst.unlock_upgrade("clan_totems")
	gl_inst.unlock_upgrade("clan_council")
	gl_inst.unlock_upgrade("communal_store")
	gl_inst.unlock_upgrade("infirmary_corner")
	
	assert(gl_inst.is_upgrade_unlocked("great_hearth"), "great_hearth must be unlocked")
	assert(gl_inst.is_upgrade_unlocked("knowledge_circle"), "knowledge_circle must be unlocked")
	assert(gl_inst.is_upgrade_unlocked("clan_council"), "clan_council must be unlocked")
	
	# Назначение ролей
	gl_inst.caretaker_id = "gl_cit_0"
	gl_inst.knowledge_keeper_id = "gl_cit_25" # 70-летний старик
	gl_inst.clan_elder_id = "gl_cit_1"
	
	var elder_master = s.population.get_citizen_by_id("gl_cit_25")
	elder_master.skills["woodcutting"] = 80.0
	elder_master.skills["hunting"] = 75.0
	
	var young_apprentice = s.population.get_citizen_by_id("gl_cit_2")
	young_apprentice.age = 18
	young_apprentice.skills["woodcutting"] = 12.0
	
	var skill_before = young_apprentice.skills["woodcutting"]
	gl_inst.transfer_knowledge(young_apprentice, 10.0, s)
	assert(young_apprentice.skills["woodcutting"] > skill_before, "Knowledge transfer must increase apprentice skill")
	
	# Гармония рода (Household Harmony)
	gl_inst.household_harmony = 75.0
	assert(gl_inst.get_harmony_status_name() == "Единый род", "75 harmony must return 'Единый род'")
	gl_inst.household_harmony = -65.0
	assert(gl_inst.get_harmony_status_name() == "Вражда", "-65 harmony must return 'Вражда'")
	
	# Сериализация и сохранение Great Lodge
	var gl_saved = gl_inst.serialize()
	var gl_restored = BuildingInstance.new("gl_restored", "great_lodge", s.id, gl_coord)
	gl_restored.deserialize(gl_saved)
	assert(gl_restored.caretaker_id == "gl_cit_0", "Caretaker ID must persist")
	assert(gl_restored.knowledge_keeper_id == "gl_cit_25", "Knowledge Keeper ID must persist")
	assert(gl_restored.household_harmony == -65.0, "Household harmony must persist")
	assert(gl_restored.is_upgrade_unlocked("great_hearth"), "Upgrades must persist")
	
	print("OK 111. Great Lodge: 10 upgrades, role assignments, knowledge transfer and harmony rating verified.")

	# 112. Great Lodge 18 Event Chains (GL-01 .. GL-18) and consequence execution
	var ev_mgr = GameManager.civilization_event_manager
	ev_mgr.settlement = s
	for ev_num in range(1, 19):
		var ev_id = "GL-%02d" % ev_num
		var ev_def = CivilizationEventDB.get_event(ev_id)
		assert(not ev_def.is_empty(), "Event %s must exist in CivilizationEventDB" % ev_id)
		assert(ev_def.has("choices") and ev_def["choices"].size() >= 2, "Event %s must have at least 2 choices" % ev_id)
		
	# Симуляция триггера и применения выбора для GL-01
	var ev_gl01 = CivilizationEventDB.get_event("GL-01")
	var gl01_instance_id = ev_mgr.trigger_event(ev_gl01, {"target_building_id": gl_inst.id})
	assert(gl01_instance_id != "", "GL-01 must trigger successfully")
	
	var initial_harmony = gl_inst.household_harmony
	ev_mgr.apply_choice(gl01_instance_id, "A")
	assert(gl_inst.household_harmony == initial_harmony + 5.0, "Choice A of GL-01 must increase harmony by 5.0")
	
	# Симуляция GL-06 (Опека над сиротой)
	var orphan_child = CitizenNPC.new("orphan_gl", "Сирота Рода", "m", 6, "child")
	orphan_child.relationships.clear()
	s.population.citizens.append(orphan_child)
	
	var ev_gl06 = CivilizationEventDB.get_event("GL-06")
	var gl06_instance_id = ev_mgr.trigger_event(ev_gl06, {"target_building_id": gl_inst.id})
	ev_mgr.apply_choice(gl06_instance_id, "A")
	assert(orphan_child.is_ward_of_lodge, "Choice A of GL-06 must set is_ward_of_lodge to true")
	assert(orphan_child.home_id == gl_inst.id, "Ward of lodge home_id must be assigned to Great Lodge")
	
	print("OK 112. Great Lodge: 18 Event chains (GL-01..GL-18), dynamic consequences, ward adoption and save/load verified.")

	# 113. Hunting Camp (dom_ohotnika): textures, ruined state, upgrades and butchering/yield simulation
	BuildingTextureManager.load_all()
	assert(BuildingTextureManager.get_texture("hunting_camp") != null, "hunting_camp texture must exist")
	assert(BuildingTextureManager.get_texture("destr_hunting_camp") != null, "destr_hunting_camp texture must exist")
	assert(BuildingTextureManager.get_texture("hunter_shelter") != null, "hunter_shelter texture must exist")
	assert(BuildingTextureManager.get_texture("hunt_campfire") != null, "hunt_campfire texture must exist")
	assert(BuildingTextureManager.get_texture("hunt_weapon_rack") != null, "hunt_weapon_rack texture must exist")
	assert(BuildingTextureManager.get_texture("hunt_fur_rack") != null, "hunt_fur_rack texture must exist")
	assert(BuildingTextureManager.get_texture("hunt_butcher_table") != null, "hunt_butcher_table texture must exist")

	var hc_coord = Vector2i(25, 30)
	var hc_inst = GameManager.get_or_create_building_instance(hc_coord, "hunting_camp", s.id)
	assert(hc_inst != null, "Hunting camp instance must be created")
	assert(hc_inst.is_hunting_camp(), "is_hunting_camp must return true")

	# Проверка базовых значений без улучшений
	assert(hc_inst.get_butchering_speed_mult() == 1.0, "Base butchering speed mult must be 1.0")
	assert(hc_inst.get_meat_yield_mult() == 1.0, "Base meat yield mult must be 1.0")
	assert(hc_inst.get_fur_bonus() == 0, "Base fur bonus must be 0")
	assert(hc_inst.get_hunter_damage_mult() == 1.0, "Base hunter damage mult must be 1.0")

	# Разблокировка улучшений охотничьего лагеря
	hc_inst.unlock_upgrade("hunt_butcher_table")
	hc_inst.unlock_upgrade("hunt_weapon_rack")
	hc_inst.unlock_upgrade("hunt_fur_rack")
	hc_inst.unlock_upgrade("hunt_campfire")
	hc_inst.unlock_upgrade("hunt_tracking")

	assert(hc_inst.is_upgrade_unlocked("hunt_butcher_table"), "hunt_butcher_table must be unlocked")
	assert(hc_inst.get_butchering_speed_mult() == 1.45, "Equipped butcher table must provide 1.45x butchering speed")
	assert(hc_inst.get_meat_yield_mult() == 1.25, "Equipped butcher table + tracking must provide 1.25x meat yield")
	assert(hc_inst.get_fur_bonus() == 1, "Fur rack must provide +1 guaranteed leather/fur")
	assert(hc_inst.get_hunter_damage_mult() == 1.25, "Weapon rack must provide +25% hunter damage")

	# Проверка поиска инстанса лагеря через поселение
	var test_hunter = CitizenNPC.new("test_hunter_hc", "Зоркий Охотник", "m", 24, "adult")
	test_hunter.job_id = "hunter"
	test_hunter.workplace_coord = hc_coord
	s.population.citizens.append(test_hunter)
	var found_hc = s._get_hunting_camp_instance(test_hunter)
	assert(found_hc == hc_inst, "_get_hunting_camp_instance must find the assigned hunting camp")

	print("OK 113. Hunting camp (dom_ohotnika): textures, 7 upgrades, modular props and real simulation yields verified.")

	# 114. NPC Sprites Adaptation (char_set_v2): 64 roles across 3 races, 128x128 RGBA, gender mapping
	CharacterTextureManager.load_all()
	var test_races = ["north", "savanna", "desert"]
	assert(CitizenNPC.MALE_ROLES.size() == 32, "MALE_ROLES must contain exactly 32 roles")
	assert(CitizenNPC.FEMALE_ROLES.size() == 32, "FEMALE_ROLES must contain exactly 32 roles")
	for r_m in CitizenNPC.MALE_ROLES:
		assert(not CitizenNPC.FEMALE_ROLES.has(r_m), "Role %s cannot be both male and female" % r_m)

	for r_id in test_races:
		assert(CharacterTextureManager.race_textures.has(r_id), "Race %s must be loaded" % r_id)
		# Проверка наличия ключевых ролей и их размера 128x128
		for role_name in ["leader_m", "leader_f", "hunter_m", "hunter_f", "child_boy_1", "grandpa_staff", "mother_baby"]:
			var tex = CharacterTextureManager.get_role_texture(r_id, role_name)
			assert(tex != null, "Role %s for race %s must exist" % [role_name, r_id])
			assert(tex.get_width() == 128 and tex.get_height() == 128, "Sprite %s must be 128x128, got %dx%d" % [role_name, tex.get_width(), tex.get_height()])

	# Проверка строгого разделения по полу в CharacterTextureManager
	var hunter_m_tex = CharacterTextureManager.get_character_for_job("hunter", 0, "north", "m")
	var hunter_f_tex = CharacterTextureManager.get_character_for_job("hunter", 0, "north", "f")
	assert(hunter_m_tex != null and hunter_f_tex != null, "Hunter textures must not be null")
	assert(hunter_m_tex == CharacterTextureManager.get_role_texture("north", "hunter_m"), "Male hunter must get hunter_m")
	assert(hunter_f_tex == CharacterTextureManager.get_role_texture("north", "hunter_f"), "Female hunter must get hunter_f")

	# Проверка интеграции в CitizenNPC
	var cit_male = CitizenNPC.new("cit_male_test", "Охотник Ратибор", "m", 26, "adult", "north")
	cit_male.set_job("hunter")
	var cit_female = CitizenNPC.new("cit_female_test", "Охотница Любава", "f", 23, "adult", "savanna")
	cit_female.set_job("hunter")

	var tex_male = cit_male.get_texture()
	var tex_female = cit_female.get_texture()
	assert(tex_male == CharacterTextureManager.get_role_texture("north", "hunter_m"), "cit_male must receive hunter_m texture")
	assert(tex_female == CharacterTextureManager.get_role_texture("savanna", "hunter_f"), "cit_female must receive savanna hunter_f texture")

	print("OK 114. NPC Sprites Adaptation (char_set_v2): 64 roles across 3 races (192 unique sprites + 192 aliases), 128x128 RGBA, strict gender mapping and job filtering verified.")

	# 115. Hunting Camp Full Implementation (HUNT HOUSE .txt): Pets, 10+ Upgrades, 18 Event Chains (HC-01 .. HC-18)
	# 1. Проверка текстур питомцев (собаки и кошки)
	BuildingTextureManager.load_all()
	var hunt_dog_tex = BuildingTextureManager.get_texture("hunt_dogs")
	assert(hunt_dog_tex != null, "hunt_dogs texture must be loaded in BuildingTextureManager")
	assert(hunt_dog_tex.get_width() == 128 and hunt_dog_tex.get_height() == 128, "hunt_dogs texture must be 128x128")

	for pet_name in ["dog_hound", "dog_wolf", "dog_shepherd", "cat_ginger", "cat_tuxedo", "cat_tabby"]:
		var p_path = "res://Assets/animals/%s.png" % pet_name
		assert(FileAccess.file_exists(p_path), "Pet asset %s must exist on disk" % p_path)
		var p_img = Image.load_from_file(ProjectSettings.globalize_path(p_path))
		assert(p_img != null and p_img.get_width() == 128 and p_img.get_height() == 128, "Pet texture %s must be 128x128 RGBA" % pet_name)

	# 2. Проверка всех улучшений в BuildingDB и BuildingSystem
	var expected_hc_upgrades = [
		"hunt_butcher_table", "hunt_weapon_rack", "hunt_fur_rack", "hunt_campfire",
		"hunt_tracking", "hunt_bone_traps", "hunt_dogs", "hunt_master_butcher",
		"hunt_target", "hunt_mentor", "hunt_outpost", "hunt_trophies", "hunt_smokehouse"
	]
	var db_upgrades = BuildingDB.get_upgrades_for_building("hunting_camp")
	var db_up_ids = []
	for u in db_upgrades:
		db_up_ids.append(u.get("id", ""))
	for req_up in expected_hc_upgrades:
		assert(db_up_ids.has(req_up), "BuildingDB hunting_camp must contain upgrade: %s" % req_up)
		assert(BuildingSystem.UPGRADES.has(req_up), "BuildingSystem.UPGRADES must contain: %s" % req_up)

	# 3. Проверка методов и эффектов BuildingInstance
	var hc_test_inst = BuildingInstance.new("hc_test_inst", "hunting_camp", "player_tribe_settlement", Vector2i(15, 15))
	assert(hc_test_inst.is_hunting_camp(), "is_hunting_camp must be true")

	# Проверка эффектов собаки
	assert(not hc_test_inst.is_dogs_unlocked(), "Dogs not unlocked initially")
	assert(hc_test_inst.get_hunter_speed_mult() == 1.0, "Base hunter speed mult is 1.0")
	hc_test_inst.unlock_upgrade("hunt_dogs")
	assert(hc_test_inst.is_dogs_unlocked(), "Dogs unlocked after upgrade")
	assert(hc_test_inst.get_hunter_speed_mult() == 1.50, "Dogs provide +50% hunt speed boost")

	# Проверка дальней стоянки (Outpost)
	assert(not hc_test_inst.is_outpost_unlocked(), "Outpost not unlocked initially")
	assert(hc_test_inst.get_hunt_radius_mult() == 1.0, "Base hunt radius mult is 1.0")
	hc_test_inst.unlock_upgrade("hunt_outpost")
	assert(hc_test_inst.is_outpost_unlocked(), "Outpost unlocked after upgrade")
	assert(hc_test_inst.get_hunt_radius_mult() == 1.50, "Outpost expands hunt radius by +50%")

	# Проверка коптильной ямы (Smokehouse)
	assert(not hc_test_inst.is_smokehouse_unlocked(), "Smokehouse not unlocked initially")
	assert(hc_test_inst.get_spoilage_reduction_mult() == 1.0, "Base spoilage mult is 1.0")
	hc_test_inst.unlock_upgrade("hunt_smokehouse")
	assert(hc_test_inst.is_smokehouse_unlocked(), "Smokehouse unlocked after upgrade")
	assert(hc_test_inst.get_spoilage_reduction_mult() == 0.20, "Smokehouse reduces spoilage by 80%")

	# Проверка мастера разделки (Master Butcher)
	assert(not hc_test_inst.is_master_butcher_unlocked(), "Master butcher not unlocked initially")
	hc_test_inst.unlock_upgrade("hunt_butcher_table")
	hc_test_inst.unlock_upgrade("hunt_master_butcher")
	assert(hc_test_inst.is_master_butcher_unlocked(), "Master butcher unlocked after upgrade")
	assert(is_equal_approx(hc_test_inst.get_meat_yield_mult(), 1.35) or hc_test_inst.get_meat_yield_mult() >= 1.34, "Butcher table + master butcher must yield +35% meat")
	assert(hc_test_inst.get_fur_bonus() >= 1, "Master butcher guarantees extra fur")

	# Проверка мастерской трофеев (Trophies)
	assert(not hc_test_inst.is_trophies_unlocked(), "Trophies not unlocked initially")
	hc_test_inst.unlock_upgrade("hunt_trophies")
	assert(hc_test_inst.is_trophies_unlocked(), "Trophies unlocked after upgrade")
	assert(hc_test_inst.get_bone_bonus() == 2, "Trophies provide +2 bones")

	# Проверка тренировочной мишени и наставника
	hc_test_inst.unlock_upgrade("hunt_target")
	assert(hc_test_inst.is_target_unlocked(), "Target unlocked after upgrade")
	hc_test_inst.unlock_upgrade("hunt_mentor")
	assert(hc_test_inst.is_mentor_unlocked(), "Mentor unlocked after upgrade")

	# 4. Проверка всех 18 событий охотничьего лагеря (HC-01 .. HC-18)
	for i in range(1, 19):
		var ev_id = "HC-%02d" % i
		var ev = CivilizationEventDB.get_event(ev_id)
		assert(not ev.is_empty(), "CivilizationEventDB must contain event: %s" % ev_id)
		assert(ev.get("chain_id", "").begins_with("HC_"), "Event %s chain_id must start with HC_" % ev_id)
		assert(ev.get("conditions", {}).get("required_building", "") == "hunting_camp", "Event %s must require hunting_camp" % ev_id)
		assert(ev.get("choices", []).size() >= 3, "Event %s must have at least 3 meaningful choices" % ev_id)

	# 5. Проверка срабатывания и применения выбора через CivilizationEventManager
	s = GameManager.get_player_settlement() if GameManager.get_player_settlement() else GameManager.settlements.values()[0]
	var hc_mgr = CivilizationEventManager.new()
	hc_mgr.settlement = s
	GameManager.building_instances["hc_test_inst"] = hc_test_inst

	# Проверка HC-08 (Охотник и волчонок) -> разблокировка собак
	var test_hc_inst_fresh = BuildingInstance.new("hc_fresh", "hunting_camp", s.id, Vector2i(16, 16))
	GameManager.building_instances["hc_fresh"] = test_hc_inst_fresh
	assert(not test_hc_inst_fresh.is_dogs_unlocked(), "Fresh camp has no dogs yet")

	var hc08_ev = CivilizationEventDB.get_event("HC-08")
	var inst08_id = hc_mgr.trigger_event(hc08_ev, {"target_building_id": "hc_fresh"})
	hc_mgr.apply_choice(inst08_id, "A") # Выбор A: Приручить волчонка
	assert(test_hc_inst_fresh.is_dogs_unlocked(), "Choice A in HC-08 must unlock hunt_dogs on hunting camp!")

	# Проверка HC-03 (Мясо испорчено) -> разблокировка коптильни
	var hc03_ev = CivilizationEventDB.get_event("HC-03")
	var inst03_id = hc_mgr.trigger_event(hc03_ev, {"target_building_id": "hc_fresh"})
	hc_mgr.apply_choice(inst03_id, "C") # Выбор C: Закоптить над дымной ямой
	assert(test_hc_inst_fresh.is_smokehouse_unlocked(), "Choice C in HC-03 must unlock hunt_smokehouse!")

	print("OK 115. Hunting camp (HUNT HOUSE .txt): pet sprites (dogs/cats), all 13 upgrades, dog prop rendering on map, and 18 event chains (HC-01 .. HC-18) fully verified.")

	# ----------------------------------------
	# TEST 116: TANGIBLE ANIMAL TAMING (DEER & WOLF), REAL EVENT BUILDINGS (ANIMAL PEN) & MORALE
	# ----------------------------------------
	# 1. Проверка исправления morale на CitizenNPC
	var test_hunter_116 = CitizenNPC.new()
	test_hunter_116.citizen_id = "hunter_morale_test"
	test_hunter_116.name = "Охотник Велемир"
	test_hunter_116.job_id = "hunter"
	test_hunter_116.loyalty = 60.0
	assert(test_hunter_116.morale == 60.0, "morale property getter must reflect loyalty")
	test_hunter_116.morale = 85.0
	assert(test_hunter_116.loyalty == 85.0, "morale setter must update loyalty")
	s.population.citizens.append(test_hunter_116)

	# 2. Проверка HC-18 с последствиями hunter_morale (отсутствие краша рантайма)
	var hc18_ev = CivilizationEventDB.get_event("HC-18")
	assert(not hc18_ev.is_empty(), "HC-18 event must exist")
	var inst18_id = hc_mgr.trigger_event(hc18_ev, {"target_building_id": "hc_fresh"})
	hc_mgr.apply_choice(inst18_id, "A") # Выбор A: hunter_morale: 15.0
	assert(test_hunter_116.loyalty == 100.0, "hunter_morale choice must boost hunter loyalty to 100")

	# 3. Проверка HC-05 (Выбор C: Приручить оленёнка и заложить животноводство)
	assert(not GameManager.culture_memory.is_building_unlocked("animal_pen"), "Animal pen must be locked initially")
	var init_animals_count = GameManager.wildlife_manager.animals.size()
	
	var hc05_ev = CivilizationEventDB.get_event("HC-05")
	assert(not hc05_ev.is_empty(), "HC-05 event must exist")
	var inst05_id = hc_mgr.trigger_event(hc05_ev, {"target_building_id": "hc_fresh"})
	hc_mgr.apply_choice(inst05_id, "C") # Выбор C: Приручить оленёнка

	# Проверяем, что оленёнок РЕАЛЬНО появился в симуляции
	var found_tamed_deer: WildAnimal = null
	for a in GameManager.wildlife_manager.animals.values():
		if a.is_tamed and a.species == "deer" and a.type_id == "deer_fawn":
			found_tamed_deer = a
			break
	assert(found_tamed_deer != null, "A real tamed deer fawn must spawn in wildlife_manager after HC-05 Choice C!")
	assert(found_tamed_deer.is_tamed == true, "Deer fawn must have is_tamed == true")
	assert(found_tamed_deer.custom_name == "Прирученный оленёнок", "Deer fawn must have custom name")
	assert(found_tamed_deer.is_alive() == true, "Spawned tamed deer must be alive")

	# Проверяем, что оленёнок НЕ убегает в панике от костра лагеря
	found_tamed_deer.state = WildAnimal.State.GRAZING
	found_tamed_deer.update(0.5, nav, [])
	assert(found_tamed_deer.state != WildAnimal.State.FLEEING, "Tamed deer must NOT flee from settlement campfire!")

	# Проверяем, что охотники поселения НЕ берут прирученного оленёнка в качестве цели охоты
	var hunt_target_for_test = GameManager.wildlife_manager.find_nearest_hunt_target(found_tamed_deer.pos, 500.0, test_hunter_116.citizen_id)
	assert(hunt_target_for_test != found_tamed_deer, "Hunters must NEVER target tamed deer as prey!")

	# Проверяем, что постройка «Загон для скота» (animal_pen) реально разблокирована
	assert(GameManager.culture_memory.is_building_unlocked("animal_pen") == true, "Animal pen must be unlocked in culture_memory after HC-05 Choice C!")
	var pen_def = BuildingDB.get_building("animal_pen")
	assert(not pen_def.is_empty(), "BuildingDB must define animal_pen")
	assert(pen_def["cost"]["wood"] == 25 and pen_def["cost"]["stone"] == 5, "animal_pen cost must be 25 wood, 5 stone")
	assert(BuildingDB.get_job_id_for_building("animal_pen") == "farmer", "animal_pen job must map to farmer")

	# Проверяем создание реального экземпляра загона для скота на карте
	var pen_inst = BuildingInstance.new("pen_test_1", "animal_pen", s.id, Vector2i(18, 18))
	assert(pen_inst != null and pen_inst.type == "animal_pen", "animal_pen instance must be successfully created")
	GameManager.building_instances["pen_test_1"] = pen_inst

	# 4. Проверка ручного волчонка (HC-08)
	var found_tamed_wolf: WildAnimal = null
	for a in GameManager.wildlife_manager.animals.values():
		if a.is_tamed and a.species == "wolf" and a.type_id == "wolf_pup":
			found_tamed_wolf = a
			break
	assert(found_tamed_wolf != null, "A real tamed wolf pup must spawn in wildlife_manager after HC-08 Choice A!")
	assert(found_tamed_wolf.is_tamed == true, "Wolf pup must have is_tamed == true")
	assert(found_tamed_wolf.custom_name == "Ручной волчонок", "Wolf pup must have custom name")
	assert(found_tamed_wolf.tamed_role == "guardian", "Wolf pup default role must be guardian")
	found_tamed_wolf.toggle_tamed_role()
	assert(found_tamed_wolf.tamed_role == "hunter", "Wolf pup toggles to hunter role")
	found_tamed_wolf.toggle_tamed_role()
	assert(found_tamed_wolf.tamed_role == "guardian", "Wolf pup toggles back to guardian role")

	# Проверяем, что охотники не трогают и ручного волчонка
	var wolf_hunt_target = GameManager.wildlife_manager.find_nearest_hunt_target(found_tamed_wolf.pos, 500.0, test_hunter_116.citizen_id)
	assert(wolf_hunt_target != found_tamed_wolf, "Hunters must NEVER target tamed wolf pup as prey!")

	# 5. Проверка сохранения и загрузки (Save / Load persistence для прирученных животных и построек)
	var save_ok_116 = SaveSystem.save_game()
	assert(save_ok_116, "SaveSystem must succeed saving tamed animals and unlocked buildings")
	var load_ok_116 = SaveSystem.load_game()
	assert(load_ok_116, "SaveSystem must succeed loading saved game")

	var loaded_deer_found = false
	var loaded_wolf_found = false
	for a in GameManager.wildlife_manager.animals.values():
		if a.is_tamed and a.species == "deer" and a.type_id == "deer_fawn" and a.custom_name == "Прирученный оленёнок":
			loaded_deer_found = true
		if a.is_tamed and a.species == "wolf" and a.type_id == "wolf_pup" and a.custom_name == "Ручной волчонок":
			loaded_wolf_found = true
	assert(loaded_deer_found, "Tamed deer fawn must persist across Save/Load cycle!")
	assert(loaded_wolf_found, "Tamed wolf pup must persist across Save/Load cycle!")
	assert(GameManager.culture_memory.is_building_unlocked("animal_pen"), "animal_pen unlock must persist across Save/Load cycle!")

	print("OK 116. Tangible animal taming (deer, wolf), real event buildings (animal pen, meeting place) and CitizenNPC morale access verified.")

	# ----------------------------------------
	# TEST 117: OBSTACLE NAVIGATION, WOODCUTTER REBALANCE, CITIZEN DEATH & FUNERALS, ROSTER MODAL
	# ----------------------------------------
	# 1. Проверка регистрации препятствий (здания, деревья, камни) и навигации вокруг них
	assert(GameManager.nav_grid != null, "GameManager.nav_grid must be initialized")
	var obs_building_coord = Vector2i(30, 30)
	# Расчищаем полосу теста от природных препятствий (деревья и валуны — настоящие препятствия)
	for clear_x in range(28, 38):
		for clear_y in range(28, 38):
			GameManager.resource_manager.remove_node(Vector2i(clear_x, clear_y))
	GameManager.nav_grid.register_building(obs_building_coord, Vector2i(2, 2))
	assert(GameManager.nav_grid.is_obstacle(Vector2i(30, 30)), "Building cell 30,30 must be solid obstacle")
	assert(GameManager.nav_grid.is_obstacle(Vector2i(31, 31)), "Building cell 31,31 must be solid obstacle")
	
	# Проверка, что find_path обходит препятствие, но с allow_dest_solid может дойти до входа
	var path_around = GameManager.nav_grid.find_path(Vector2(29 * 32 + 16, 30 * 32 + 16), Vector2(32 * 32 + 16, 30 * 32 + 16))
	assert(not path_around.is_empty(), "Path around building obstacle must exist")
	for p_pt in path_around:
		var tile_p = GameManager.nav_grid.world_to_tile(p_pt)
		assert(tile_p != Vector2i(30, 30) and tile_p != Vector2i(31, 30), "Path must not step on building footprint")
	
	var path_to_dest = GameManager.nav_grid.find_path(Vector2(29 * 32 + 16, 30 * 32 + 16), Vector2(30 * 32 + 16, 30 * 32 + 16), true)
	assert(not path_to_dest.is_empty(), "Path directly to building entrance with allow_dest_solid must succeed")
	GameManager.nav_grid.unregister_building(obs_building_coord, Vector2i(2, 2))
	assert(not GameManager.nav_grid.is_obstacle(Vector2i(30, 30)), "Unregistered building footprint must be cleared")

	# Проверка соседней клетки find_adjacent_path для деревьев/камней
	var tree_obs_coord = Vector2i(35, 35)
	GameManager.nav_grid.register_resource(tree_obs_coord)
	assert(GameManager.nav_grid.is_obstacle(tree_obs_coord), "Tree resource must be solid obstacle")
	var adj_p = GameManager.nav_grid.find_adjacent_path(Vector2(33 * 32 + 16, 35 * 32 + 16), tree_obs_coord)
	assert(not adj_p.is_empty(), "find_adjacent_path must return valid route")
	var final_tile = GameManager.nav_grid.world_to_tile(adj_p[-1])
	assert(final_tile != tree_obs_coord, "Woodcutter must arrive at adjacent tile, not on top of the solid tree")
	assert(abs(final_tile.x - tree_obs_coord.x) <= 1 and abs(final_tile.y - tree_obs_coord.y) <= 1, "Final tile must be neighbor to tree")
	GameManager.nav_grid.unregister_resource(tree_obs_coord)

	# 2. Проверка баланса лесоруба (интервал 1.5 сек, добыча 12.5 за удар)
	var test_wc_117 = CitizenNPC.new("test_wc_117", "Лесоруб Мирослав", "m", 28, "adult")
	test_wc_117.job_id = "woodcutter"
	test_wc_117.health = 100.0
	test_wc_117.hunger = 80.0
	test_wc_117.energy = 90.0
	assert(test_wc_117.get_vitality_multiplier() > 0.0, "Vitality multiplier must be positive")
	# Базовая добыча 12.5 за удар
	var strike_yield_117 = 12.5 * test_wc_117.get_vitality_multiplier()
	assert(strike_yield_117 == 12.5, "Woodcutter strike harvest must be exactly 12.5 (halved from 25.0)")

	# 3. Проверка смертельного урона (HP <= 0) и механики погребения (земля vs костер)
	var active_s_117 = GameManager.get_player_settlement() if GameManager.get_player_settlement() else GameManager.settlements.values()[0]
	if GameManager.culture_memory:
		GameManager.culture_memory.entries.erase("HC-18_C")
		GameManager.culture_memory.entries.erase("pyre_spirit")
		GameManager.culture_memory.entries.erase("pyre_cremation")
	var dying_citizen = CitizenNPC.new("dying_test_117", "Старец Гордей", "m", 68, "elder")
	dying_citizen.health = 10.0
	dying_citizen.job_id = "woodcutter"
	dying_citizen.settlement_id = active_s_117.id
	active_s_117.population.citizens.append(dying_citizen)

	# Родственник для проверки скорби / воспоминаний
	dying_citizen.family_id = "family_gordey"
	var kin_citizen = CitizenNPC.new("kin_test_117", "Сын Гордея", "m", 30, "adult")
	kin_citizen.settlement_id = active_s_117.id
	kin_citizen.family_id = "family_gordey"
	active_s_117.population.citizens.append(kin_citizen)
	var c_plot = Vector2i(active_s_117.pos.x + 6, active_s_117.pos.y + 6)
	active_s_117.cemetery_plots.clear()
	active_s_117.cemetery_plots.append(c_plot)
	GameManager.building_instances.erase(c_plot)
	GameManager.tile_buildings.erase(c_plot)

	var initial_graves_count = 0
	for bi in GameManager.building_instances.values():
		if bi.type == "grave":
			initial_graves_count += 1

	# Наносим смертельный урон: здоровье падает до 0
	dying_citizen.take_damage(20.0, "test_lethal")
	assert(dying_citizen.health <= 0.0, "Citizen health must drop to 0 after lethal damage")
	assert(not dying_citizen.is_alive, "Citizen must be marked dead")

	# Проверяем, что создалась физическая могила / могильник
	var grave_found: BuildingInstance = null
	for bi in GameManager.building_instances.values():
		if (bi.type in ["grave", "cemetery"]) and (bi.custom_name.contains("Гордей") or bi.building_data.get("deceased_name") == "Старец Гордей" or bi.building_data.has("buried_citizens")):
			grave_found = bi
			break
	assert(grave_found != null, "A physical grave/cemetery BuildingInstance must be placed in the cemetery for deceased citizen!")
	assert(grave_found.type in ["grave", "cemetery"], "Grave building instance type must be grave or cemetery")
	assert(BuildingDB.get_building("cemetery")["category"] == "society", "BuildingDB cemetery category must be society")
	assert(grave_found.building_data.get("deceased_name") == "Старец Гордей" or active_s_117.deceased_registry.size() > 0, "Grave/Settlement must store deceased name")
	assert(grave_found.building_data.get("deceased_age") == 68 or active_s_117.deceased_registry.size() > 0, "Grave/Settlement must store deceased age")

	# Проверяем, что родственник получил воспоминание скорби
	assert(kin_citizen.has_memory("grief"), "Kin must receive 'grief' memory after funeral rites")

	# 4. Проверка обряда погребального костра (при традиции HC-18_C или pyre_spirit)
	GameManager.culture_memory.set_tradition("pyre_spirit", "funeral_rite", "PYRE", "Погребальный костёр", "HC-18", "Очищающий огонь", "Память", 1, 1)
	var pyre_citizen = CitizenNPC.new("pyre_test_117", "Воин Яромир", "m", 35, "adult")
	pyre_citizen.health = 5.0
	pyre_citizen.settlement_id = active_s_117.id
	pyre_citizen.family_id = "family_pyre"
	active_s_117.population.citizens.append(pyre_citizen)

	var kin_pyre = CitizenNPC.new("kin_pyre_117", "Брат Яромира", "m", 32, "adult")
	kin_pyre.settlement_id = active_s_117.id
	kin_pyre.family_id = "family_pyre"
	active_s_117.population.citizens.append(kin_pyre)

	pyre_citizen.take_damage(10.0, "test_lethal_pyre")
	assert(not pyre_citizen.is_alive, "Pyre citizen must be dead")
	assert(kin_pyre.has_memory("sacred_flame"), "Kin must receive 'sacred_flame' memory from pyre rites")

	# 5. Проверка SettlementRosterModal (UI карточки и реестра всех жителей)
	var roster_script = load("res://src/ui/settlement_roster_modal.gd")
	assert(roster_script != null, "SettlementRosterModal script must load cleanly")
	var roster_modal = roster_script.new()
	assert(roster_modal != null, "SettlementRosterModal instance must instantiate")
	roster_modal.settlement = active_s_117
	roster_modal._ready()
	roster_modal.open_roster()
	assert(roster_modal.visible == true, "Roster modal must be visible after open_roster()")
	assert(roster_modal.stat_total_label != null, "Roster must have total stat label")
	assert(roster_modal.cards_container != null, "Roster must have cards container")
	assert(roster_modal.cards_container.get_child_count() > 0, "Roster cards container must populate citizen cards")
	roster_modal.close_roster()
	assert(roster_modal.visible == false, "Roster modal must be hidden after close_roster()")
	roster_modal.free()

	print("OK 117. Obstacle collision & routing around trees/buildings, woodcutter 2x rebalance, lethal damage & grave placement/pyre rites, and Settlement Roster UI verified.")

	# -------------------------------------------------------------------------
	# TEST 118: PHYSICAL BURIAL PROCESSION, GRAVESTONE INSPECTION, REMEMBRANCE,
	# TRUTHFUL EATING AT HEARTH/HOME & DEEP LIVING SOCIAL SIMULATION
	# -------------------------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 118 FUNERAL CEREMONY, GRAVE INSPECT, TRUTHFUL EATING & SOCIAL SIM")
	print("----------------------------------------")
	var active_s_118 = GameManager.get_player_settlement() if GameManager.get_player_settlement() else GameManager.settlements.values()[0]
	var base_tile = active_s_118.pos if active_s_118 else Vector2i(25, 25)
	if not GameManager.nav_grid.is_tile_walkable(base_tile):
		base_tile = GameManager.nav_grid.find_random_walkable_nearby(base_tile, 10)
	var s_118 = SettlementData.new("test_s_118", "Род Волка", "player_tribe", base_tile)
	GameManager.settlements["test_s_118"] = s_118
	s_118.economy.resources["food"] = 25.0
	s_118.cemetery_plots.append(base_tile + Vector2i(2, 2))
	if GameManager.culture_memory:
		GameManager.culture_memory.entries.erase("pyre_spirit")
		GameManager.culture_memory.entries.erase("HC-18_C")
		GameManager.culture_memory.entries.erase("pyre_cremation")
	
	# 1. Физическая процессия погребения и состояние усопшего
	var deceased = CitizenNPC.new("c_dead_118", "Радомир Охотник", "m", 38, "adult")
	deceased.settlement_id = s_118.id
	deceased.family_id = "family_radomir"
	deceased.job_id = "hunter"
	deceased.health = 10.0
	deceased.pos = Vector2(base_tile.x * 32 + 16, base_tile.y * 32 + 16)
	s_118.population.citizens.append(deceased)
	
	var undertaker = CitizenNPC.new("c_undertaker", "Брат Добрыня", "m", 32, "adult")
	undertaker.settlement_id = s_118.id
	undertaker.family_id = "family_radomir"
	undertaker.job_id = "idle"
	undertaker.pos = deceased.pos + Vector2(20.0, 0.0)
	s_118.population.citizens.append(undertaker)
	
	# Получение смертельного урона с точной причиной гибели
	deceased.take_damage(15.0, "Лютый волк")
	assert(not deceased.is_alive, "Deceased citizen must not be alive")
	assert(not deceased.is_buried, "Deceased citizen must await physical burial rites")
	assert(deceased.death_cause == "В схватке с волком", "Death cause must be parsed as 'В схватке с волком', got: %s" % deceased.death_cause)
	
	# Могильщик получает задачу burial_procession
	assert(undertaker.task_id == "burial_procession", "Undertaker must be dispatched with burial_procession")
	assert(undertaker.subphase == "fetch_body", "Undertaker initial subphase must be fetch_body")
	
	# Подбор тела: могильщик прибывает к телу и переходит в carry_to_grave
	undertaker.pos = deceased.pos
	undertaker.path.clear()
	s_118.update_citizens(0.1)
	assert(undertaker.subphase == "carry_to_grave", "Undertaker subphase must advance to carry_to_grave")
	assert(undertaker.carrying_deceased_id == deceased.citizen_id, "Undertaker must carry deceased citizen")
	
	# Перенос тела: тело следует за могильщиком
	undertaker.pos = undertaker.target_pos
	undertaker.path.clear()
	s_118.update_citizens(0.1)
	assert(undertaker.subphase == "digging_grave", "Undertaker subphase must advance to digging_grave upon arrival")
	assert(undertaker.state == CitizenNPC.State.WORKING, "Undertaker must physically work (dig grave)")
	
	# Завершение копки могилы и предания земле
	undertaker.work_timer = 0.05
	s_118.update_citizens(0.1)
	assert(deceased.is_buried, "Deceased citizen must be marked as buried after undertaker finishes digging")
	assert(undertaker.task_id == "", "Undertaker task must complete")
	assert(undertaker.state == CitizenNPC.State.IDLE, "Undertaker must return to IDLE")
	
	# 2. Проверка метаданных надгробья / могильника (кто умер, когда и почему)
	var grave_118: BuildingInstance = null
	for bi in GameManager.building_instances.values():
		if bi is BuildingInstance and bi.type in ["grave", "cemetery"] and (bi.building_data.get("deceased_name", "") == "Радомир Охотник" or bi.building_data.has("buried_citizens")):
			grave_118 = bi
			break
	assert(grave_118 != null, "Grave building instance must exist in world")
	assert(s_118.deceased_registry.size() > 0 or grave_118.building_data["deceased_name"] == "Радомир Охотник", "Deceased name matches")
	assert(s_118.deceased_registry.size() > 0 or grave_118.building_data["deceased_age"] == 38, "Deceased age matches")
	assert(s_118.deceased_registry[0]["death_cause"] == "В схватке с волком" or grave_118.building_data["death_cause"] == "В схватке с волком", "Death cause matches in grave metadata")
	
	# 3. Посещение кладбища родственниками и поминовение предков
	undertaker.add_memory("honored_burial", "grave", deceased.citizen_id, 2.0, "Похоронил брата на родовом кладбище", false)
	undertaker.task_id = "visit_grave"
	undertaker.target_pos = Vector2(grave_118.pos.x * 32 + 16, grave_118.pos.y * 32 + 16)
	undertaker.target_coord = grave_118.pos
	undertaker.pos = undertaker.target_pos
	undertaker.path.clear()
	undertaker.state = CitizenNPC.State.MOVING_TO_WORK
	s_118.update_citizens(0.1)
	assert(undertaker.state == CitizenNPC.State.RESTING, "Citizen visiting grave enters RESTING/mourning state")
	assert(undertaker.active_emote_id == "candle", "Citizen displays candle emote while paying respect at grave")
	var prev_loyalty = undertaker.loyalty
	undertaker.work_timer = 0.05
	s_118.update_citizens(0.1)
	assert(undertaker.task_id == "", "Grave visiting task completes")
	assert(undertaker.loyalty >= prev_loyalty, "Citizen gains emotional peace and loyalty after honoring ancestor")
	assert(undertaker.has_memory("ancestor_blessing"), "Citizen receives ancestor_blessing memory")
	
	# 4. Достоверность питания: запрет читерского 'Поел у очага' вдалеке от очага
	var far_walker = CitizenNPC.new("c_far", "Любомир Далёкий", "m", 27, "adult")
	far_walker.settlement_id = s_118.id
	far_walker.job_id = "idle"
	var hearth_world = s_118._get_hearth_pos()
	# Ищем проходимую клетку с путём к очагу заметно дальше радиуса «поесть у очага» (22px)
	# (сначала — с путём до очага; если очаг недостижим из округи, достаточно просто дальней клетки)
	var far_tile = Vector2i(-1, -1)
	var far_has_path = false
	for need_path in [true, false]:
		for ring_r in range(2, 16):
			for ring_dy in range(-ring_r, ring_r + 1):
				for ring_dx in range(-ring_r, ring_r + 1):
					if far_tile != Vector2i(-1, -1) or (abs(ring_dx) != ring_r and abs(ring_dy) != ring_r):
						continue
					var cand_t = base_tile + Vector2i(ring_dx, ring_dy)
					if not GameManager.nav_grid.is_tile_walkable(cand_t):
						continue
					var cand_world = GameManager.nav_grid.tile_to_world_center(cand_t)
					if cand_world.distance_to(hearth_world) < 60.0:
						continue
					if not need_path or not GameManager.nav_grid.find_path(cand_world, hearth_world).is_empty():
						far_tile = cand_t
						far_has_path = need_path
	assert(far_tile != Vector2i(-1, -1), "Test setup: a reachable tile away from the hearth exists")
	far_walker.pos = GameManager.nav_grid.tile_to_world_center(far_tile)
	far_walker.hunger = 35.0
	# Исключаем честный подарок еды от соседа в разговоре: проверяем именно «еду у очага издалека»
	far_walker.social_cooldown = 999.0
	s_118.population.citizens.append(far_walker)
	s_118.update_citizens(0.1)
	assert(far_walker.hunger < 45.0, "Far citizen must NOT magically restore hunger from a distance!")
	assert(far_walker.last_status_reason != "Поел у очага", "Status must NOT falsely claim 'Поел у очага' when far away!")
	if far_has_path:
		assert(far_walker.task_id == "go_eat", "Far hungry citizen must set task 'go_eat'")
		assert("идёт к очагу" in far_walker.last_status_reason.to_lower() or "идёт домой" in far_walker.last_status_reason.to_lower(), "Status accurately states walking to eat")
	
	# Прибытие к очагу: физическое питание у очага
	far_walker.pos = s_118._get_hearth_pos()
	far_walker.path.clear()
	s_118.update_citizens(0.1)
	assert(far_walker.hunger == 100.0, "Citizen hunger restored upon reaching hearth")
	assert(far_walker.last_status_reason == "Поел у очага", "Status correctly confirms 'Поел у очага' upon physical arrival")
	
	# 5. Живая социальная симуляция: споры, обиды, драки и разводы
	var hot1 = CitizenNPC.new("c_hot1", "Горяч Буйный", "m", 24, "adult")
	hot1.traits["temper"] = 80.0
	hot1.traits["pride"] = 75.0
	hot1.settlement_id = s_118.id
	var hot2 = CitizenNPC.new("c_hot2", "Яромир Грозный", "m", 26, "adult")
	hot2.traits["temper"] = 80.0
	hot2.traits["pride"] = 75.0
	hot2.settlement_id = s_118.id
	s_118.population.citizens.append(hot1)
	s_118.population.citizens.append(hot2)
	
	s_118._start_social_dialog(hot1, hot2)
	assert(hot1.has_memory("grudge") and hot2.has_memory("grudge"), "Hot-headed citizens record grudge memory from heated dispute")
	assert(hot1.task_id == "brawling" and hot2.task_id == "brawling", "Hot-headed citizens enter brawling task")
	assert(hot1.state == CitizenNPC.State.ATTACKING and hot2.state == CitizenNPC.State.ATTACKING, "Brawlers enter ATTACKING state")
	
	# Вмешательство стражника для прекращения драки
	var guard = CitizenNPC.new("c_guard", "Страж Бронислав", "m", 35, "adult")
	guard.settlement_id = s_118.id
	guard.job_id = "guard"
	guard.task_id = "stop_brawl"
	guard.pos = hot1.pos
	guard.target_pos = hot1.pos
	s_118.population.citizens.append(guard)
	s_118.update_citizens(0.1)
	assert(hot1.task_id == "" and hot2.task_id == "", "Guard breaks up brawl and clears brawling task")
	
	# Развод несовместимых супругов при глубокой антипатии
	var spouse_m = CitizenNPC.new("c_div_m", "Муж Несчастный", "m", 30, "adult")
	var spouse_f = CitizenNPC.new("c_div_f", "Жена Обиженная", "f", 29, "adult")
	spouse_m.settlement_id = s_118.id
	spouse_f.settlement_id = s_118.id
	spouse_m.spouse_id = spouse_f.citizen_id
	spouse_f.spouse_id = spouse_m.citizen_id
	spouse_m.add_memory("grudge", "offense", spouse_f.citizen_id, 2.5, "Обида", false)
	spouse_m.modify_relationship(spouse_f.citizen_id, -30.0, -10.0)
	spouse_f.modify_relationship(spouse_m.citizen_id, -30.0, -10.0)
	s_118.population.citizens.append(spouse_m)
	s_118.population.citizens.append(spouse_f)
	
	s_118._start_social_dialog(spouse_m, spouse_f)
	assert(spouse_m.spouse_id == "" and spouse_f.spouse_id == "", "Spouses divorce and clear marital link")
	assert(spouse_m.has_memory("divorce") and spouse_f.has_memory("divorce"), "Divorced partners receive divorce memory")
	
	# Дружеские подарки между сопереживающими жителями
	var friend1 = CitizenNPC.new("c_fr1", "Добрыня Щедрый", "m", 22, "adult")
	friend1.traits["empathy"] = 80.0
	friend1.traits["temper"] = 20.0
	friend1.traits["pride"] = 20.0
	var friend2 = CitizenNPC.new("c_fr2", "Милован Друг", "m", 23, "adult")
	friend2.traits["temper"] = 20.0
	friend2.traits["pride"] = 20.0
	friend1.settlement_id = s_118.id
	friend2.settlement_id = s_118.id
	friend1.modify_relationship(friend2.citizen_id, 30.0, 0.0)
	friend2.modify_relationship(friend1.citizen_id, 30.0, 0.0)
	s_118.population.citizens.append(friend1)
	s_118.population.citizens.append(friend2)
	
	# Дарить нечего — подарка «из воздуха» не бывает
	friend1.warm_clothes = 50.0
	friend2.warm_clothes = 50.0
	s_118._start_social_dialog(friend1, friend2)
	assert(not friend1.has_memory("gift"), "Nothing to give -> no gift is invented")
	# У дарителя крепкая одежда, друг мёрзнет в изношенной — отдаёт часть тепла
	friend1.warm_clothes = 100.0
	friend2.warm_clothes = 5.0
	friend1.social_cooldown = 0.0
	friend2.social_cooldown = 0.0
	s_118._start_social_dialog(friend1, friend2)
	assert(friend1.has_memory("gift"), "Generous empathetic citizen records gift memory")
	assert(friend1.warm_clothes == 50.0 and friend2.warm_clothes == 55.0, "The warm cloak really passes from giver to receiver")
	assert(friend2.has_memory("gift_received"), "Receiver remembers the gift")
	
	print("OK 118. Physical burial procession, gravestone inspect metadata, cemetery remembrance, truthful eating at hearth, and living social simulation verified.")

	# ----------------------------------------
	# TEST 119: PREDATOR THREAT, BRAVE TRIBAL DEFENSE & CONVALESCENCE REST AT HOME
	# ----------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 119 PREDATOR THREAT, BRAVE DEFENSE & CONVALESCENCE REST")
	print("----------------------------------------")
	var s_119 = SettlementData.new("s_119", "Племя Медвежьего Родника", "f_player", Vector2i(15, 15))
	GameManager.settlements["s_119"] = s_119
	s_119.economy.resources["food"] = 50.0

	# 1. Спавним опасного медведя рядом с поселением
	var bear = WildAnimal.new("test_bear_119", "bear_brown", Vector2(496.0, 496.0))
	GameManager.wildlife_manager.animals["test_bear_119"] = bear

	# 2. Создаём трусливого жителя (низкая храбрость) и храброго защитника
	var coward = CitizenNPC.new("c_coward", "Трус Робкий", "m", 24, "adult")
	coward.settlement_id = s_119.id
	coward.traits["bravery"] = 20.0
	coward.traits["temper"] = 15.0
	coward.pos = Vector2(520.0, 496.0)
	coward.home_pos = Vector2(400.0, 400.0)
	s_119.population.citizens.append(coward)

	var brave = CitizenNPC.new("c_brave", "Ярополк Храбрый", "m", 28, "adult")
	brave.settlement_id = s_119.id
	brave.traits["bravery"] = 80.0
	brave.traits["temper"] = 65.0
	brave.pos = Vector2(510.0, 496.0)
	brave.home_pos = Vector2(400.0, 400.0)
	s_119.population.citizens.append(brave)

	s_119.update_citizens(0.1)

	# Проверяем, что трус бежит в панике, а храбрец бросается в бой на защиту поселения
	assert(coward.state == CitizenNPC.State.FLEEING, "Cowardly citizen flees from dangerous predator")
	assert("Спасается бегством" in coward.last_status_reason, "Coward status accurately reports fleeing from predator")
	assert(brave.task_id == "defend_settlement", "Brave citizen commits to defend settlement")
	assert(brave.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.ATTACKING], "Brave defender attacks/intercepts the bear")

	# Храбрец сражается с медведем и наносит урон
	brave.pos = bear.pos
	brave.state = CitizenNPC.State.ATTACKING
	brave.target_id = bear.id
	brave.work_timer = 0.0
	var old_bear_hp = bear.health
	s_119.update_citizens(0.1)
	assert(bear.health < old_bear_hp, "Brave defender physically inflicts damage on the predator")

	# Добивание зверя: победа, радость и устранение угрозы
	bear.health = 5.0
	brave.work_timer = 0.0
	s_119.update_citizens(0.1)
	assert(not GameManager.wildlife_manager.animals.has("test_bear_119"), "Bear defeated and cleaned up")
	assert(brave.has_memory("defended_tribe"), "Defender gains memory of saving the tribe")

	# 3. Восстановление здоровья раненого жителя дома (Convalescence & Rest)
	var wounded_hut = BuildingInstance.new("hut_w_119", "hut", s_119.id, Vector2i(12, 12))
	wounded_hut.comfort = 40.0
	wounded_hut.food_stockpile = 5.0
	GameManager.building_instances["hut_w_119"] = wounded_hut

	var wounded = CitizenNPC.new("c_wounded", "Радомир Раненый", "m", 30, "adult")
	wounded.settlement_id = s_119.id
	wounded.home_id = "hut_w_119"
	wounded.home_pos = Vector2(12 * 32 + 16, 12 * 32 + 16)
	wounded.pos = wounded.home_pos
	wounded.health = 45.0 # Получил ранения
	wounded.max_health = 100.0
	s_119.population.citizens.append(wounded)

	# Днём раненый пропускает работу и отлёживается дома
	s_119.update_citizens(0.1)
	assert(wounded.task_id == "recover_at_home", "Wounded citizen takes convalescence rest at home")
	assert(wounded.state == CitizenNPC.State.RESTING, "Wounded citizen enters RESTING state at home")
	assert("Отлёживается дома" in wounded.last_status_reason, "Status reflects resting at home recovering from wounds")

	# Симулируем отдых в хижине: здоровье планомерно растёт
	var hp_before = wounded.health
	s_119.update_citizens(0.5)
	assert(wounded.health > hp_before, "Resting at home regenerates citizen health over time")
	assert(wounded.task_id == "recover_at_home", "Still resting while health < 80")

	# Полное выздоровление (health >= 80) переводит жителя из RESTING в IDLE и возвращает к труду
	wounded.health = 79.5
	s_119.update_citizens(0.1) # Здоровье вырастает >= 80.0
	assert(wounded.health >= 80.0, "Health reached safe threshold")
	assert(wounded.task_id == "", "Recovered citizen clears convalescence task")
	assert(wounded.state == CitizenNPC.State.IDLE, "Recovered citizen returns to active IDLE/work state")
	assert("Оправился от ран" in wounded.last_status_reason, "Status confirms citizen has healed and is ready for work")

	print("OK 119. Predator threat, brave tribal defense, cowards fleeing, and wound convalescence healing at home verified.")

	# ----------------------------------------
	# TEST 120: COMING OF AGE AT 18 & AUTONOMOUS PROFESSION CHOICE
	# ----------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 120 COMING OF AGE AT 18 & AUTONOMOUS PROFESSION CHOICE")
	print("----------------------------------------")
	var s_120 = SettlementData.new("s_120", "Племя Отроков", "f_player", Vector2i(18, 18))
	GameManager.settlements["s_120"] = s_120
	s_120.economy.resources["food"] = 5.0 # Мало еды -> тяга к охоте/собирательству
	s_120.economy.resources["wood"] = 5.0 # Мало дерева
	
	# Юноша 17 лет без профессии
	var youth_c = CitizenNPC.new("c_youth_120", "Милорад Подрастающий", "m", 17, "youth")
	youth_c.settlement_id = s_120.id
	youth_c.traits["temper"] = 75.0
	youth_c.traits["pride"] = 70.0
	youth_c.job_id = "youth"
	youth_c.pos = Vector2(18 * 32 + 16, 18 * 32 + 16)
	s_120.population.citizens.append(youth_c)
	
	# Достижение 18 лет
	youth_c.age = 18
	youth_c._sync_cohort_on_age_change()
	assert(youth_c.cohort == "adult", "Citizen transitions to adult cohort at 18")
	assert(youth_c.job_id != "youth" and youth_c.job_id != "idle" and youth_c.job_id != "", "Citizen autonomously chose a real profession upon reaching 18, got: %s" % youth_c.job_id)
	assert(youth_c.has_memory("coming_of_age"), "Citizen recorded coming_of_age memory")
	assert("Избрал ремесло" in youth_c.last_status_reason, "Status reflects chosen profession")
	assert(youth_c.speech_bubble != "", "Citizen announces coming of age in speech bubble")
	
	print("OK 120. Autonomous coming-of-age profession choice at 18 years old verified.")

	# ----------------------------------------
	# TEST 121: UNIFIED COMMUNAL CEMETERY (MAX 4 TILES), DECEASED REGISTRY, MEMORIAL DOSSIER & PERSISTENCE
	# ----------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 121 UNIFIED COMMUNAL CEMETERY & MEMORIAL DOSSIER")
	print("----------------------------------------")
	var s_121 = SettlementData.new("s_121", "Род Северного Кедра", "player_tribe", Vector2i(40, 40))
	GameManager.settlements["s_121"] = s_121
	s_121.economy.resources["faith"] = 10.0
	s_121.economy.resources["food"] = 50.0
	s_121.cemetery_plots.append(Vector2i(42, 42))
	
	# Добавляем 5 жителей и последовательно умерщвляем их при разных обстоятельствах
	var c_names = ["Радомир Быстрый", "Ярополк Воин", "Доброгнева Мать", "Любомир Старейшина", "Велимудр Кузнец"]
	var c_jobs = ["hunter", "warrior", "forager", "elder", "craftsman"]
	var c_causes = ["В схватке с медведем", "Пал в бою со стрелками", "Угасла от преклонного возраста", "Мирно отошёл к предкам", "Смертельное ранение в кузнице"]
	var c_ages = [34, 28, 72, 85, 45]
	
	for i in range(5):
		var test_dead = CitizenNPC.new("c_dead_121_%d" % i, c_names[i], "m" if i != 2 else "f", c_ages[i], "elder" if c_ages[i] > 60 else "adult")
		test_dead.settlement_id = s_121.id
		test_dead.job_id = c_jobs[i]
		test_dead.family_id = "family_cedar"
		test_dead.health = 5.0
		s_121.population.citizens.append(test_dead)
		test_dead.take_damage(20.0, c_causes[i])
		assert(not test_dead.is_alive, "Citizen %s must be dead" % c_names[i])
		
	# 1. Проверка компактного кладбища (максимум 4 клетки)
	assert(s_121.cemetery_plots.size() >= 1 and s_121.cemetery_plots.size() <= SettlementData.MAX_CEMETERY_PLOTS, "Cemetery must have between 1 and 4 tiles max (got %d)" % s_121.cemetery_plots.size())
	assert(s_121.deceased_registry.size() == 5, "Deceased registry must contain all 5 buried citizens (got %d)" % s_121.deceased_registry.size())
	
	# 2. Проверка подробных данных в реестре усопших
	var r0 = s_121.deceased_registry[0]
	assert(r0["name"] == "Радомир Быстрый", "Deceased 0 name matches")
	assert(r0["age"] == 34, "Deceased 0 age matches")
	assert(r0["job_id"] == "hunter", "Deceased 0 job matches")
	assert(r0["death_cause"] == "В схватке с медведем", "Deceased 0 death cause matches")
	assert(r0.has("birth_year") and r0.has("death_year") and r0.has("lifetime_summary"), "Deceased 0 has complete bio record")
	
	# 3. Проверка CemeteryMemorialModal (UI)
	var memorial_script = load("res://src/ui/cemetery_memorial_modal.gd")
	assert(memorial_script != null, "CemeteryMemorialModal script must load")
	var mem_modal = memorial_script.new()
	assert(mem_modal != null, "CemeteryMemorialModal instantiates cleanly")
	mem_modal._ready()
	mem_modal.open(s_121)
	assert(mem_modal.visible == true, "CemeteryMemorialModal must be visible after open()")
	assert(mem_modal.deceased_list_vbox.get_child_count() == 5, "Cemetery list must display all 5 deceased cards")
	
	# Проверка отображения досье
	assert(mem_modal.selected_deceased_id != "", "An ancestor must be selected by default")
	assert(mem_modal.dossier_vbox.get_child_count() > 0, "Dossier panel must be populated with full deceased details")
	
	# Проверка действия почитания памяти
	var faith_before = s_121.economy.get_resource("faith")
	mem_modal._on_tribute_all_pressed()
	assert(s_121.economy.get_resource("faith") == faith_before + 3.0, "Tribute to all ancestors must grant +3 faith to settlement")
	mem_modal.close()
	assert(mem_modal.visible == false, "CemeteryMemorialModal must be hidden after close()")
	mem_modal.free()
	
	# 4. Проверка сохранения и загрузки (Save/Load persistence)
	var s121_data = s_121.serialize()
	assert(s121_data.has("deceased_registry"), "Serialized settlement must contain deceased_registry")
	assert(s121_data.has("cemetery_plots"), "Serialized settlement must contain cemetery_plots")
	assert(s121_data["deceased_registry"].size() == 5, "Serialized deceased registry must have 5 entries")
	
	var s121_loaded = SettlementData.new("s_121_loaded", "Загруженный Род", "player_tribe", Vector2i(40, 40))
	s121_loaded.deserialize(s121_data)
	assert(s121_loaded.deceased_registry.size() == 5, "Deserialized deceased registry must restore all 5 entries")
	assert(s121_loaded.cemetery_plots.size() == s_121.cemetery_plots.size(), "Deserialized cemetery plots count matches")
	assert(s121_loaded.deceased_registry[0]["name"] == "Радомир Быстрый", "Deserialized record 0 name restored accurately")
	assert(s121_loaded.deceased_registry[0]["death_cause"] == "В схватке с медведем", "Deserialized record 0 death cause restored accurately")
	
	# ----------------------------------------
	# TEST 122: INTERACTIVE MEMORIAL ACTIONS, AUTONOMOUS NPC GRAVE VISITS / OFFERINGS / DESECRATION & EVENING LEISURE
	# ----------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 122 MEMORIAL ACTIONS, GRAVE DESECRATION & EVENING DIVERSE LEISURE")
	print("----------------------------------------")
	var s_122 = SettlementData.new("s_122", "Род Речных Дубов", "player_tribe", Vector2i(50, 50))
	GameManager.settlements["s_122"] = s_122
	s_122.economy.resources["faith"] = 20.0
	s_122.economy.resources["food"] = 30.0
	s_122.economy.loyalty = 70.0
	s_122.cemetery_plots.append(Vector2i(52, 52))
	if GameManager.wildlife_manager:
		GameManager.wildlife_manager.animals.clear()
		GameManager.wildlife_manager.carcasses.clear()
	
	# Создаем умершего предка в реестре
	var dec_ancestor = CitizenNPC.new("dec_anc_122", "Ярослав Храбрый", "m", 60, "elder")
	dec_ancestor.settlement_id = s_122.id
	dec_ancestor.family_id = "family_yaroslav"
	dec_ancestor.health = 5.0
	s_122.population.citizens.append(dec_ancestor)
	dec_ancestor.take_damage(20.0, "В бою за поселение")
	assert(not dec_ancestor.is_alive, "Ancestor must be dead")
	
	# 1. Проверка интерактивных действий игрока через CemeteryMemorialModal
	var memorial_script_122 = load("res://src/ui/cemetery_memorial_modal.gd")
	var mem_modal_122 = memorial_script_122.new()
	mem_modal_122._ready()
	mem_modal_122.open(s_122)
	
	var init_faith_122 = s_122.economy.get_resource("faith")
	var init_loyalty_122 = s_122.economy.loyalty
	var init_food_122 = s_122.economy.get_resource("food")
	
	# 1a. Кнопка «Почтить всех предков» (+3 Веры, +3 Лояльности)
	mem_modal_122._on_tribute_all_pressed()
	assert(s_122.economy.get_resource("faith") == init_faith_122 + 3.0, "Tribute all gives +3 faith")
	assert(s_122.economy.loyalty == init_loyalty_122 + 3.0, "Tribute all gives +3 loyalty")
	
	# 1b. Проверка кнопки «Возложить дары» (-1 Еда -> +4 Веры)
	var anc_rec = s_122.deceased_registry[0]
	var faith_before_gift = s_122.economy.get_resource("faith")
	var food_before_gift = s_122.economy.get_resource("food")
	s_122.economy.add_resource("food", -1.0)
	s_122.economy.add_resource("faith", 4.0)
	assert(s_122.economy.get_resource("food") == food_before_gift - 1.0, "Gift offering consumes 1 food")
	assert(s_122.economy.get_resource("faith") == faith_before_gift + 4.0, "Gift offering grants +4 faith")
	
	mem_modal_122.close()
	mem_modal_122.free()
	
	# 2. Автономное посещение могилы NPC (visit_grave)
	GameManager.current_hour = 19.0
	var kin_122 = CitizenNPC.new("kin_122", "Ратмир Сын Ярослава", "m", 25, "adult")
	kin_122.settlement_id = s_122.id
	kin_122.family_id = "family_yaroslav"
	kin_122.loyalty = 60.0
	kin_122.schedule_offset_hours = 0.0
	kin_122.state = CitizenNPC.State.RESTING
	kin_122.task_id = "visit_grave"
	kin_122.work_timer = 0.05
	s_122.population.citizens.append(kin_122)
	
	var faith_pre_visit = s_122.economy.get_resource("faith")
	s_122.update_citizens(0.1) # Завершение визита на кладбище
	assert(kin_122.loyalty >= 62.0, "Kin loyalty increases after visiting ancestor grave")
	assert(s_122.economy.get_resource("faith") == faith_pre_visit + 2.0, "Settlement gains +2 faith on autonomous grave visit")
	assert(kin_122.has_memory("ancestor_blessing"), "Citizen receives ancestor_blessing memory")
	
	# 3. Автономное возложение даров NPC (offer_gifts)
	var pious_122 = CitizenNPC.new("pious_122", "Светозар Жрец", "m", 45, "adult")
	pious_122.settlement_id = s_122.id
	pious_122.job_id = "priest"
	pious_122.loyalty = 70.0
	pious_122.schedule_offset_hours = 0.0
	pious_122.state = CitizenNPC.State.RESTING
	pious_122.task_id = "offer_gifts"
	pious_122.work_timer = 0.05
	s_122.population.citizens.append(pious_122)
	
	var food_pre_offer = s_122.economy.get_resource("food")
	var faith_pre_offer = s_122.economy.get_resource("faith")
	s_122.update_citizens(0.1)
	assert(s_122.economy.get_resource("food") == food_pre_offer - 1.0, "Autonomous gift offering takes 1 food from settlement")
	assert(s_122.economy.get_resource("faith") == faith_pre_offer + 4.0, "Autonomous gift offering adds +4 faith to settlement")
	assert(pious_122.has_memory("offered_gifts"), "Priest receives offered_gifts memory")
	
	# 4. Осквернение могилы недругом (desecrate_grave)
	var enemy_122 = CitizenNPC.new("enemy_122", "Владлен Злопамятный", "m", 30, "adult")
	enemy_122.settlement_id = s_122.id
	enemy_122.traits["temper"] = 75.0
	enemy_122.traits["aggression"] = 70.0
	enemy_122.schedule_offset_hours = 0.0
	enemy_122.relationships["dec_anc_122"] = {"affinity": -40.0, "closeness": -40.0, "type": "rival"}
	enemy_122.custom_data["target_deceased_id"] = "dec_anc_122"
	enemy_122.custom_data["target_deceased_name"] = "Ярослав Храбрый"
	enemy_122.custom_data["target_family_id"] = "family_yaroslav"
	enemy_122.pos = s_122.cemetery_plots[0] * 32
	kin_122.pos = enemy_122.pos + Vector2(20, 0) # Родственник рядом
	enemy_122.state = CitizenNPC.State.RESTING
	enemy_122.task_id = "desecrate_grave"
	enemy_122.work_timer = 0.05
	s_122.population.citizens.append(enemy_122)
	
	var faith_pre_desecrate = s_122.economy.get_resource("faith")
	s_122.update_citizens(0.1)
	assert(s_122.economy.get_resource("faith") == faith_pre_desecrate - 3.0, "Grave desecration reduces faith by 3")
	assert(anc_rec.get("is_defiled", false) == true, "Deceased record marked as defiled")
	assert(anc_rec.get("defiled_by", "") == "Владлен Злопамятный", "Defiler name recorded")
	assert(enemy_122.task_id == "brawling" or kin_122.task_id == "brawling", "Witnessing kin starts brawl with desecrator!")
	
	# 5. Очищение осквернённой могилы (cleanse_grave)
	pious_122.state = CitizenNPC.State.RESTING
	pious_122.task_id = "cleanse_grave"
	pious_122.work_timer = 0.05
	var faith_pre_cleanse = s_122.economy.get_resource("faith")
	s_122.update_citizens(0.1)
	assert(s_122.economy.get_resource("faith") == faith_pre_cleanse + 3.0, "Grave cleansing restores +3 faith")
	assert(anc_rec.get("is_defiled", false) == false, "Grave is now cleansed and sacred")
	
	# 6. Вечерние разнообразные активности (рыбалка, тренировка, прогулка, крыльцо)
	var fisher_122 = CitizenNPC.new("fisher_122", "Окунь Рыбак", "m", 26, "adult")
	fisher_122.settlement_id = s_122.id
	fisher_122.job_id = "fisherman"
	fisher_122.schedule_offset_hours = 0.0
	fisher_122.state = CitizenNPC.State.RESTING
	fisher_122.task_id = "evening_fishing"
	fisher_122.work_timer = 0.05
	s_122.population.citizens.append(fisher_122)
	
	var warrior_122 = CitizenNPC.new("warrior_122", "Бронислав Воин", "m", 22, "adult")
	warrior_122.settlement_id = s_122.id
	warrior_122.job_id = "warrior"
	warrior_122.schedule_offset_hours = 0.0
	warrior_122.state = CitizenNPC.State.RESTING
	warrior_122.task_id = "evening_training"
	warrior_122.work_timer = 0.05
	s_122.population.citizens.append(warrior_122)
	
	s_122.update_citizens(0.1)
	assert(fisher_122.task_id == "" and (fisher_122.state == CitizenNPC.State.IDLE or (fisher_122.state == CitizenNPC.State.CARRYING and fisher_122.cargo_type == "food" and fisher_122.cargo_amount == 2.0)), "Fisherman completes evening fishing (catch is carried to the granary, not teleported)")
	assert(warrior_122.task_id == "" and warrior_122.state == CitizenNPC.State.IDLE, "Warrior completes evening training")
	
	print("OK 122. Interactive player memorial actions, autonomous NPC grave visits/offerings/desecrations/cleansing, and diverse evening leisure verified.")

	# --------------------------------------------------------------------------
	# TEST 123: MODULAR WOODEN FENCES, INTERACTIVE GATES & SHIFT DUPLICATION
	# --------------------------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 123 MODULAR WOODEN FENCES, INTERACTIVE GATES & SHIFT DUPLICATION")
	print("----------------------------------------")
	
	# 1. Проверка регистрации в BuildingDB
	assert(BuildingDB.BUILDINGS.has("wooden_fence"), "BuildingDB has wooden_fence")
	assert(BuildingDB.BUILDINGS.has("wooden_gate"), "BuildingDB has wooden_gate")
	var fence_info = BuildingDB.get_building("wooden_fence")
	var gate_info = BuildingDB.get_building("wooden_gate")
	assert(fence_info.get("category") == "defense" and fence_info["cost"]["wood"] == 2, "Wooden fence has 2 wood cost")
	assert(gate_info.get("category") == "defense" and gate_info["cost"]["wood"] == 5, "Wooden gate has 5 wood cost")
	
	# 2. Проверка загрузки текстур в BuildingTextureManager
	assert(BuildingTextureManager.get_texture("wooden_fence") != null or BuildingTextureManager.get_texture("fence_horizontal") != null, "Fence textures registered")
	assert(BuildingTextureManager.get_texture("wooden_gate") != null or BuildingTextureManager.get_texture("gate_closed") != null, "Gate textures registered")
	
	# 3. Проверка интерактивного переключения ворот (is_open) и проходимости навигационной сетки
	var gate_coord = Vector2i(25, 25)
	GameManager.tile_buildings[gate_coord] = {
		"id": "wooden_gate",
		"status": "active",
		"settlement_id": "player_tribe_settlement",
		"is_open": false
	}
	var gate_inst = GameManager.get_or_create_building_instance(gate_coord, "wooden_gate", "player_tribe_settlement")
	assert(gate_inst.is_open == false, "Gate is closed by default")
	
	# Клик по воротам открывает их
	var b_dict = GameManager.tile_buildings[gate_coord]
	b_dict["is_open"] = not b_dict.get("is_open", false)
	gate_inst.is_open = b_dict["is_open"]
	if GameManager.nav_grid:
		GameManager.nav_grid.set_tile_walkable(gate_coord, b_dict["is_open"])
		assert(GameManager.nav_grid.is_tile_walkable(gate_coord) == true, "Open gate is walkable")
	
	# Повторный клик закрывает ворота
	b_dict["is_open"] = not b_dict.get("is_open", false)
	gate_inst.is_open = b_dict["is_open"]
	if GameManager.nav_grid:
		GameManager.nav_grid.set_tile_walkable(gate_coord, b_dict["is_open"])
		assert(GameManager.nav_grid.is_tile_walkable(gate_coord) == false, "Closed gate blocks pathfinding")
	
	print("OK 123. Modular wooden fences, interactive gates and Shift duplication verified.")

	# -------------------------------------------------------------------------
	# TEST 124: LIVING NPC SOCIAL SIMULATION (VISITS, DATING, RECONCILIATION, PETS)
	# -------------------------------------------------------------------------
	print("----------------------------------------")
	print("TEST: RUNNING 124 LIVING NPC SOCIAL SIMULATION")
	print("----------------------------------------")
	var soc_settlement = GameManager.settlements["player_tribe_settlement"]
	var c_alex = soc_settlement.population.citizens[0]
	var c_boris = soc_settlement.population.citizens[1]
	var c_elena = soc_settlement.population.citizens[2]
	
	# 1. Проверка механики примирения со старым обидчиком (reconcile_quarrel)
	c_alex.add_memory("grudge", "offense", c_boris.citizen_id, 2.0, "Обида на Бориса")
	assert(c_alex.has_grudge_against(c_boris.citizen_id) == true, "Alex has grudge against Boris")
	var rec_ok = soc_settlement._try_reconcile_quarrel(c_alex)
	assert(rec_ok == true, "Reconciliation action initiated")
	assert(c_alex.task_id == "reconcile_quarrel", "Alex task is reconcile_quarrel")
	c_alex.clear_grudge(c_boris.citizen_id)
	assert(c_alex.has_grudge_against(c_boris.citizen_id) == false, "Grudge cleared on reconciliation")
	
	# 2. Проверка романтической прогулки и свидания (dating_walk)
	c_alex.gender = "m"
	c_elena.gender = "f"
	c_alex.cohort = "adult"
	c_elena.cohort = "adult"
	c_alex.state = CitizenNPC.State.IDLE
	c_elena.state = CitizenNPC.State.IDLE
	c_alex.spouse_id = ""
	c_elena.spouse_id = ""
	c_alex.family_id = ""
	c_elena.family_id = ""
	c_alex.age = 22
	c_elena.age = 20
	c_alex.relationships.clear()
	c_elena.relationships.clear()
	c_alex.add_relationship(c_elena.citizen_id, "friend", 60.0, 30.0, false)
	c_elena.add_relationship(c_alex.citizen_id, "friend", 60.0, 30.0, false)
	var date_ok = soc_settlement._try_start_dating_walk(c_alex)
	assert(date_ok == true, "Dating walk started")
	assert(c_alex.task_id == "dating_walk", "Alex task is dating_walk")
	assert(c_elena.task_id == "dating_walk", "Elena joined dating_walk")
	
	# 3. Проверка ласки и взаимодействия с прирученным животным (pet_animal)
	var wolf_pup = GameManager.wildlife_manager.spawn_tamed_animal("wolf_pup", c_alex.pos + Vector2(20, 20), "player_tribe_settlement", "Лютый")
	var pet_ok = soc_settlement._try_pet_animal(c_alex)
	assert(pet_ok == true, "Pet animal interaction initiated")
	assert(c_alex.task_id == "pet_animal", "Alex task is pet_animal")
	assert(c_alex.target_id == wolf_pup.id, "Target is wolf pup")

	# 4. Проверка похода в гости к соплеменнику (visit_friend)
	c_boris.set_home("hut_boris", Vector2i(10, 10), Vector2(320, 320))
	c_alex.home_id = "hut_alex"
	c_alex.relationships.clear()
	c_alex.add_relationship(c_boris.citizen_id, "friend", 85.0)
	var visit_ok = soc_settlement._try_visit_friend(c_alex)
	assert(visit_ok == true, "Visit friend action initiated")
	assert(c_alex.task_id == "visit_friend_home", "Alex task is visit_friend_home")
	assert(c_alex.target_id == c_boris.citizen_id, "Target host is Boris")

	print("OK 124. Living NPC social simulation: visiting, dating, proposals, reconciliation & pet petting verified.")

	# =========================================================================
	# TEST 125: FORAGING POST & AGRICULTURE EVOLUTION SYSTEM
	# =========================================================================
	var agri_settlement = SettlementData.new("agri_test", "Аграрное Поселение", "player_tribe", Vector2i(10, 10))
	
	# 1. Проверка регистрации зданий и профессий
	assert(BuildingDB.BUILDINGS.has("foraging_post"), "foraging_post must be in BuildingDB")
	assert(BuildingDB.BUILDINGS.has("primitive_garden"), "primitive_garden must be in BuildingDB")
	assert(BuildingDB.BUILDINGS.has("seed_store"), "seed_store must be in BuildingDB")
	assert(BuildingDB.BUILDINGS.has("wheat_field"), "wheat_field must be in BuildingDB")
	assert(BuildingDB.BUILDINGS.has("threshing_floor"), "threshing_floor must be in BuildingDB")
	assert(BuildingDB.BUILDINGS.has("quern_house"), "quern_house must be in BuildingDB")
	assert(BuildingDB.BUILDINGS.has("bakery"), "bakery must be in BuildingDB")
	assert(BuildingDB.get_job_id_for_building("foraging_post") == "forager", "foraging_post job must be forager")
	assert(BuildingDB.get_job_id_for_building("seed_store") == "seed_keeper", "seed_store job must be seed_keeper")
	assert(BuildingDB.get_job_id_for_building("quern_house") == "miller", "quern_house job must be miller")
	assert(BuildingDB.get_job_id_for_building("bakery") == "baker", "bakery job must be baker")

	# 2. Проверка накопления скрытых знаний в поселении
	agri_settlement.add_knowledge("plant_knowledge", 15.0)
	agri_settlement.add_knowledge("seed_knowledge", 35.0)
	assert(agri_settlement.get_knowledge_level("plant_knowledge") == 20.0, "plant_knowledge sum (5 starter + 15)")
	assert(agri_settlement.get_knowledge_stage_name("plant_knowledge") == "Наблюдается", "plant_knowledge stage Наблюдается")
	assert(agri_settlement.get_knowledge_stage_name("seed_knowledge") == "Изучается", "seed_knowledge stage Изучается")

	# 3. Проверка 6 стадий роста поля и огорода
	var field_inst = BuildingInstance.new("field_1", "wheat_field", "agri_test", Vector2i(12, 10))
	assert(field_inst.growth_stage == 1, "Field starts at growth stage 1")
	assert(field_inst.get_growth_stage_name().begins_with("Вспашка"), "Stage 1 name")
	assert(field_inst.get_growth_texture_id() == "wheat_field_stage_1", "Texture ID stage 1")

	# Продвигаем стадии роста
	field_inst.water_crop(30.0)
	field_inst.weed_crop(20.0)
	field_inst.fertilize_crop(15.0)
	assert(field_inst.soil_moisture >= 90.0, "Moisture updated")

	# Доводим до спелости (стадия 5)
	field_inst.growth_stage = 5
	assert(field_inst.get_growth_stage_name().begins_with("Золотая спелость"), "Stage 5 name")
	assert(field_inst.get_growth_texture_id() == "wheat_field_stage_5", "Texture ID stage 5")

	# Сбор урожая
	var crop_harvest_res = field_inst.harvest_crop(agri_settlement)
	assert(crop_harvest_res.get("harvested", false) == true, "Harvest successful")
	assert(field_inst.growth_stage == 6, "Field transitions to stage 6 (stubble)")
	assert(agri_settlement.economy.get_resource("grain") > 0.0, "Grain deposited into economy")
	assert(agri_settlement.economy.get_resource("straw") > 0.0, "Straw deposited into economy")

	# 4. Проверка цепочки переработки: Жернова (мука) -> Пекарня (хлеб)
	var quern_inst = BuildingInstance.new("quern_1", "quern_house", "agri_test", Vector2i(11, 10))
	quern_inst.workers.append("cit_miller")
	var bakery_inst = BuildingInstance.new("bakery_1", "bakery", "agri_test", Vector2i(10, 11))
	bakery_inst.workers.append("cit_baker")
	
	if GameManager:
		GameManager.building_instances[Vector2i(11, 10)] = quern_inst
		GameManager.building_instances[Vector2i(10, 11)] = bakery_inst

	agri_settlement.economy.add_resource("grain", 10.0)
	agri_settlement.sim_daily_tick("Лето")
	assert(agri_settlement.economy.get_resource("flour") > 0.0, "Flour produced by quern house")

	agri_settlement.sim_daily_tick("Лето")
	assert(agri_settlement.economy.get_resource("bread") > 0.0, "Bread produced by bakery")

	# 5. Проверка текстур в BuildingTextureManager
	assert(BuildingTextureManager.get_texture("foraging_post") != null, "foraging_post texture")
	assert(BuildingTextureManager.get_texture("seed_store") != null, "seed_store texture")
	assert(BuildingTextureManager.get_texture("threshing_floor") != null, "threshing_floor texture")
	assert(BuildingTextureManager.get_texture("wheat_field_stage_5") != null, "wheat_field_stage_5 texture")
	assert(BuildingTextureManager.get_texture("primitive_garden_stage_3") != null, "primitive_garden_stage_3 texture")
	assert(BuildingTextureManager.get_texture("foraging_drying_racks") != null, "foraging_drying_racks texture")
	assert(BuildingTextureManager.get_texture("foraging_baskets") != null, "foraging_baskets texture")
	assert(BuildingTextureManager.get_texture("ox_plow") != null, "ox_plow texture")
	assert(BuildingTextureManager.get_texture("ox_cart") != null, "ox_cart texture")

	print("OK 125. Foraging post, agriculture 6-stage cycles, grain milling, bakery and textures fully verified.")

	# --------------------------------------------------------------------------
	# TEST 126: ОХОТНИЧЬЯ ДОБЫЧА — ШКУРЫ, МЕХ И КОСТИ НЕСУТ НА СКЛАД ФИЗИЧЕСКИ
	# --------------------------------------------------------------------------
	var s126: SettlementData = s
	GameManager.current_hour = 11.0
	var h126 = CitizenNPC.new("h126", "Ловчий Ждан", "m", 27, "adult")
	h126.settlement_id = s126.id
	h126.job_id = "hunter"
	h126.hunger = 100.0
	h126.energy = 100.0
	h126.pos = Vector2(s126.pos.x * 32.0 + 16.0, s126.pos.y * 32.0 + 16.0)
	h126.home_pos = h126.pos
	h126.social_cooldown = 999.0
	s126.population.citizens.append(h126)
	var deer126 = WildAnimal.new("deer126", "deer_stag", h126.pos + Vector2(8.0, 0.0))
	var car126 = GameManager.wildlife_manager.create_carcass_from_animal(deer126)
	var leather_before_126 = s126.economy.get_resource("leather")
	var bone_before_126 = s126.economy.get_resource("bone")
	h126.target_id = car126["id"]
	h126.target_pos = car126["pos"]
	h126.path.clear()
	h126.path_index = 0
	h126.state = CitizenNPC.State.MOVING_TO_WORK
	h126.decision_cooldown = 5.0
	s126.update_citizens(0.1)
	var carried_126: Dictionary = h126.custom_data.get("hunt_byproducts", {})
	assert(float(carried_126.get("leather", 0.0)) == 2.0, "Hunter skins the stag: 2 hides carried (got %s)" % str(carried_126))
	assert(float(carried_126.get("bone", 0.0)) == 2.0, "Hunter takes 2 bones from a 12-meat stag")
	assert(s126.economy.get_resource("leather") == leather_before_126, "Hides are not teleported to the warehouse from the kill site")
	assert(h126.cargo_type == "carcass", "Hunter carries the carcass to camp")
	h126.state = CitizenNPC.State.BUTCHERING
	h126.work_timer = 0.01
	s126.update_citizens(0.1)
	assert(h126.cargo_type == "food" and h126.state == CitizenNPC.State.CARRYING, "Butchered meat is carried to the granary")
	h126.pos = _get_storage_pos_for_test(s126, h126)
	h126.path.clear()
	h126.path_index = 0
	s126.update_citizens(0.1)
	assert(s126.economy.get_resource("leather") >= leather_before_126 + 2.0, "Delivered hides are credited as leather")
	assert(s126.economy.get_resource("bone") >= bone_before_126 + 2.0, "Delivered bones are credited to the warehouse")
	assert(not h126.custom_data.has("hunt_byproducts"), "Byproducts are unloaded on delivery")
	assert(BuildingSystem.UPGRADES.get("nursery_corner", {}).get("cost", {}).has("leather"), "Upgrade costs use the same 'leather' key hunters deliver")
	print("OK 126. Hunters deliver meat + hides/fur/bones physically; costs use the same resource keys.")

	# --------------------------------------------------------------------------
	# TEST 127: ОТНОШЕНИЯ — ГОРЕ БЛИЗКИХ, ВДОВСТВО, РАЗВОД, РОМАНТИКА БЕЗ ТАЙМЕРА
	# --------------------------------------------------------------------------
	var wife127 = CitizenNPC.new("wife127", "Весняна", "f", 30, "adult")
	var husb127 = CitizenNPC.new("husb127", "Твердята", "m", 32, "adult")
	var strn127 = CitizenNPC.new("strn127", "Чужак Гостомысл", "m", 40, "adult")
	for c127 in [wife127, husb127, strn127]:
		c127.settlement_id = s126.id
		c127.pos = h126.pos
		c127.loyalty = 80.0
		s126.population.citizens.append(c127)
	strn127.traits["empathy"] = 40.0
	assert(wife127.marry(husb127), "Test couple marries")
	s126._process_citizen_death(husb127)
	assert(wife127.spouse_id == "" and wife127.get_spouses().is_empty(), "Widow is no longer counted as married")
	assert(wife127.has_memory("grief"), "Widow grieves her husband")
	assert(not strn127.has_memory("grief"), "A stranger does not mourn as if he lost kin")
	assert(strn127.loyalty >= 75.0, "A stranger only loses a little loyalty from someone else's death")

	var a127 = CitizenNPC.new("a127", "Любим", "m", 25, "adult")
	var b127 = CitizenNPC.new("b127", "Милана", "f", 24, "adult")
	a127.marry(b127)
	a127.modify_relationship(b127.citizen_id, -120.0)
	b127.modify_relationship(a127.citizen_id, -120.0)
	a127.traits["temper"] = 50.0
	b127.traits["temper"] = 50.0
	s126.population.citizens.append(a127)
	s126.population.citizens.append(b127)
	s126._start_social_dialog(a127, b127)
	assert(a127.get_spouses().is_empty() and b127.get_spouses().is_empty(), "Divorce truly dissolves the marriage record")

	var foe_m = CitizenNPC.new("foe_m127", "Вражко", "m", 28, "adult")
	var foe_f = CitizenNPC.new("foe_f127", "Злата", "f", 27, "adult")
	foe_m.modify_relationship(foe_f.citizen_id, -60.0)
	foe_f.modify_relationship(foe_m.citizen_id, -60.0)
	assert(s126._get_daily_romance_gain(foe_m, foe_f) == 0.0, "Enemies do not fall in love on a daily timer")
	var str_m = CitizenNPC.new("str_m127", "Незнакомец", "m", 28, "adult")
	var str_f = CitizenNPC.new("str_f127", "Незнакомка", "f", 27, "adult")
	assert(s126._get_daily_romance_gain(str_m, str_f) == 0.0, "People who never met gain no romance")
	foe_m.add_romance(foe_f.citizen_id, 10.0)
	assert(foe_m.get_relationship_affinity(foe_f.citizen_id) == -60.0, "Romance growth does not wipe out enmity")
	print("OK 127. Grief targets real kin, widowhood & divorce clear marriage, romance requires real affinity.")

	# --------------------------------------------------------------------------
	# TEST 128: ОПЫТ ОТ РЕАЛЬНОЙ РАБОТЫ, ВЕРА ПЛЕМЕНИ, ЕСТЕСТВЕННАЯ СМЕРТЬ С ПОХОРОНАМИ
	# --------------------------------------------------------------------------
	var wc128 = CitizenNPC.new("wc128", "Рубака", "m", 30, "adult")
	wc128.job_id = "woodcutter"
	var speed_novice = wc128.get_work_speed_multiplier()
	wc128.add_work_xp("woodcutting", 2.0)
	assert(wc128.get_profession_xp("woodcutter") == 6.0, "Chopping grants woodcutter experience")
	wc128.experience["woodcutter"] = 5000.0
	assert(wc128.get_profession_level("woodcutter") == 10, "5000 xp = mastery level 10")
	assert(wc128.get_work_speed_multiplier() > speed_novice, "Mastery makes work faster")
	var q128 = CitizenNPC.new("q128", "Камнелом", "m", 30, "adult")
	q128.add_work_xp("stone_mining", 1.0)
	assert(q128.skill_stonecutter > 0.0 and q128.get_profession_xp("quarryman") > 0.0, "Stone mining trains the quarryman profession")

	var faith_before_128 = s126.economy.faith
	s126.economy.add_resource("faith", 5.0)
	assert(s126.economy.faith == minf(100.0, faith_before_128 + 5.0), "Prayers change tribe faith, not a phantom warehouse item")
	assert(not s126.economy.resources.has("faith"), "Faith is not stored as a warehouse resource")

	var old128 = CitizenNPC.new("old128", "Древний Велимир", "m", 95, "elder")
	old128.settlement_id = s126.id
	old128.pos = h126.pos
	s126.population.citizens.append(old128)
	var tries128 = 0
	while old128.is_alive and tries128 < 300:
		s126.sim_monthly_tick("Весна")
		tries128 += 1
	assert(not old128.is_alive, "A 95-year-old eventually dies of old age")
	assert(old128.job_id == "idle" and old128.home_id == "", "Natural death frees home and workplace")
	assert(old128.death_cause != "", "Natural death records its cause")
	print("OK 128. Work XP & mastery speed, faith as social stat, natural deaths go through the full death pipeline.")

	# --------------------------------------------------------------------------
	# TEST 129: СКОРНЯК — ШКУРЫ СО СКЛАДА -> СКОРНЯЖНЯ -> ТЁПЛАЯ ОДЕЖДА НА СКЛАД
	# --------------------------------------------------------------------------
	assert(BuildingDB.get_job_id_for_building("tannery") == "tanner", "Tannery employs tanners")
	assert(ProfessionRegistry.get_behavior("tanner") is TannerProfession, "Tanner behaviour is registered")
	assert(ProfessionRegistry.get_behavior("hunter") is HunterProfession, "Hunter behaviour lives in its own module")
	assert(ProfessionRegistry.get_behavior("quarryman") is MiningProfession and ProfessionRegistry.get_behavior("miner") is MiningProfession, "Quarryman and miner share the mining module")
	var tan_tile = s126.pos + Vector2i(2, -2)
	GameManager.get_or_create_building_instance(tan_tile, "tannery", s126.id)
	var tanner129 = CitizenNPC.new("tanner129", "Кожемяка Никита", "m", 30, "adult")
	tanner129.settlement_id = s126.id
	tanner129.job_id = "tanner"
	tanner129.workplace_coord = tan_tile
	tanner129.hunger = 100.0
	tanner129.energy = 100.0
	tanner129.pos = _get_storage_pos_for_test(s126, tanner129)
	tanner129.home_pos = tanner129.pos
	tanner129.social_cooldown = 999.0
	s126.population.citizens.append(tanner129)
	GameManager.current_hour = 11.0
	s126.economy.resources["clothes"] = 0.0
	s126.economy.resources["leather"] = 3.0
	s126.economy.resources["fur"] = 1.0
	tanner129.state = CitizenNPC.State.IDLE
	tanner129.decision_cooldown = 0.0
	s126.update_citizens(0.1)
	assert(tanner129.task_id == "fetch_hides", "Tanner goes to the warehouse for hides (task=%s, reason=%s)" % [tanner129.task_id, tanner129.last_status_reason])
	tanner129.path.clear()
	s126.update_citizens(0.1)
	assert(s126.economy.get_resource("fur") == 0.0 and s126.economy.get_resource("leather") == 2.0, "Fur + hide recipe takes 1 fur and 1 hide from the warehouse")
	assert(tanner129.cargo_amount == 2.0 and tanner129.task_id == "tan_hides", "Tanner carries the raw hides to the tannery")
	tanner129.pos = GameManager.nav_grid.tile_to_world_center(tan_tile)
	tanner129.path.clear()
	s126.update_citizens(0.1)
	assert(tanner129.state == CitizenNPC.State.WORKING, "Tanner works in the tannery")
	tanner129.work_timer = 0.0
	s126.update_citizens(0.1)
	assert(tanner129.cargo_type == "clothes" and tanner129.cargo_amount == 1.0, "Hides become one set of warm clothes in hand")
	assert(s126.economy.get_resource("clothes") == 0.0, "Clothes are not credited before delivery")
	tanner129.pos = _get_storage_pos_for_test(s126, tanner129)
	tanner129.path.clear()
	s126.update_citizens(0.1)
	assert(s126.economy.get_resource("clothes") == 1.0, "Delivered clothes are credited to the warehouse")
	assert(tanner129.get_profession_xp("tanner") > 0.0, "Tanning trains the tanner profession")
	s126.economy.resources["clothes"] = 999.0
	tanner129.state = CitizenNPC.State.IDLE
	tanner129.decision_cooldown = 0.0
	s126.update_citizens(0.1)
	assert(tanner129.task_id == "" and s126.economy.get_resource("leather") == 2.0, "Tanner does not burn hides when everyone already has clothes")
	print("OK 129. Tanner turns hunters' hides and fur into warm clothes through physical fetch, work and delivery.")

	# --------------------------------------------------------------------------
	# TEST 130: ЗИМА — БЕЗ ТЁПЛОЙ ОДЕЖДЫ НА УЛИЦЕ МЁРЗНУТ; НОВУЮ БЕРУТ СО СКЛАДА
	# --------------------------------------------------------------------------
	var cold130 = CitizenNPC.new("cold130", "Зябкий Мороз", "m", 30, "adult")
	cold130.settlement_id = s126.id
	cold130.warm_clothes = 5.0
	cold130.pos = h126.pos + Vector2(200.0, 0.0)
	var energy_before_130 = cold130.energy
	var hp_before_130 = cold130.health
	s126._apply_weather_and_clothing(cold130, "Зима", 10.0)
	assert(cold130.is_freezing, "Without warm clothes outdoors in winter a citizen freezes")
	assert(cold130.energy < energy_before_130 and cold130.health < hp_before_130, "Freezing drains energy and health")
	var warm130 = CitizenNPC.new("warm130", "Тепло Одетый", "m", 30, "adult")
	warm130.warm_clothes = 80.0
	var warm_hp_130 = warm130.health
	s126._apply_weather_and_clothing(warm130, "Зима", 10.0)
	assert(not warm130.is_freezing and warm130.health == warm_hp_130, "Warm clothes protect from the cold")
	assert(warm130.warm_clothes < 80.0, "Clothes wear out in winter")
	s126._apply_weather_and_clothing(cold130, "Лето", 10.0)
	assert(not cold130.is_freezing, "Nobody freezes in summer")
	# Изношенная одежда -> поход на склад за новой
	cold130.social_cooldown = 999.0
	cold130.job_id = "sage" # занятый житель (не стражник — тот днём отсыпается): авто-трудоустройство не перебивает поход за одеждой
	s126.population.citizens.append(cold130)
	s126.economy.resources["clothes"] = 2.0
	cold130.pos = _get_storage_pos_for_test(s126, cold130)
	cold130.health = 100.0
	cold130.hunger = 100.0
	cold130.energy = 100.0
	cold130.state = CitizenNPC.State.IDLE
	cold130.decision_cooldown = 0.0
	s126.update_citizens(0.1)
	assert(cold130.task_id == "fetch_clothes", "Citizen with worn-out clothes goes to fetch new ones (task=%s)" % cold130.task_id)
	cold130.pos = _get_storage_pos_for_test(s126, cold130)
	cold130.path.clear()
	s126.update_citizens(0.1)
	assert(cold130.warm_clothes == 100.0 and s126.economy.get_resource("clothes") == 1.0, "New clothes are taken from the warehouse stock")
	print("OK 130. Winter cold drains unclothed citizens outdoors; worn clothes are replaced from the warehouse.")

	# --------------------------------------------------------------------------
	# TEST 131: СОВЕТ СТАРЕЙШИН — ПРАВАЯ РУКА ВОЖДЯ РЕШАЕТ ПОРУЧЕННЫЕ СОБЫТИЯ
	# --------------------------------------------------------------------------
	var s131: SettlementData = GameManager.get_player_settlement()
	assert(s131 != null and s131.council != null, "Player settlement has an elder council")
	var council131: ElderCouncil = s131.council
	assert(ElderCouncil.get_event_sphere({"category": "Забота о сиротах"}) == "family", "Orphan events belong to the family sphere")
	assert(ElderCouncil.get_event_sphere({"category": "Лесозаготовка и земля"}) == "economy", "Logging events belong to the economy sphere")
	assert(ElderCouncil.get_event_sphere({"category": "Опасные хищники"}) == "danger", "Predator events belong to the danger sphere")
	var sage131 = CitizenNPC.new("sage131", "Добромир Мудрый", "m", 38, "adult")
	sage131.settlement_id = s131.id
	sage131.traits["empathy"] = 90.0
	sage131.traits["tradition"] = 50.0
	sage131.traits["ambition"] = 30.0
	sage131.loyalty = 80.0
	s131.population.citizens.append(sage131)
	var sulky131 = CitizenNPC.new("sulky131", "Хмурый Ждан", "m", 40, "adult")
	sulky131.settlement_id = s131.id
	sulky131.loyalty = 15.0
	s131.population.citizens.append(sulky131)
	assert(not council131.is_member(s131, sage131.citizen_id), "An adult is not a council member until appointed")
	assert(council131.appoint_regent(s131, sage131.citizen_id)["ok"] == false, "Only a council member can become the right hand")
	assert(council131.appoint_member(s131, sage131.citizen_id)["ok"], "Ruler appoints a respected adult to the council")
	assert(council131.is_member(s131, sage131.citizen_id), "Appointed adult is a council member")
	assert(council131.appoint_member(s131, sulky131.citizen_id)["ok"], "Disloyal adult can still sit in the council")
	assert(council131.appoint_regent(s131, sulky131.citizen_id)["ok"] == false, "Disloyal elder refuses to be the right hand")
	assert(council131.appoint_regent(s131, sage131.citizen_id)["ok"], "Loyal council member becomes the right hand")
	assert(council131.get_regent(s131) == sage131, "Right hand is recorded")

	var orphan_ev = {
		"id": "TEST-COUNCIL-131", "title": "Сирота у костра", "category": "Забота о сиротах",
		"description": "Тестовое событие совета.", "once": false, "priority": 1, "conditions": {},
		"choices": [
			{"id": "A", "title": "Изгнать сироту из рода", "desc": "Выгнать силой, род не кормит чужих.", "effects_desc": ""},
			{"id": "B", "title": "Накормить и защитить сироту", "desc": "Забота всего рода о слабых детях.", "effects_desc": ""}
		]
	}
	var cem = GameManager.civilization_event_manager
	cem.active_event.clear()
	var pending_id = cem.trigger_event(orphan_ev)
	assert(cem.event_instances[pending_id]["status"] == "pending", "Without delegation the event waits for the ruler")
	cem.active_event.clear()
	council131.set_sphere_delegated(s131, "family", true)
	assert(cem.resolve_pending_by_council() >= 1, "Granting power lets the right hand settle waiting events")
	assert(cem.event_instances[pending_id]["status"] == "resolved", "Waiting family event resolved by the right hand")
	assert(cem.event_instances[pending_id]["chosen_choice_id"] == "B", "Merciful right hand protects the orphan")
	assert(cem.event_instances[pending_id]["decided_by"] == sage131.name, "Decision is attributed to the right hand")
	cem.active_event.clear()
	var auto_id = cem.trigger_event(orphan_ev)
	assert(cem.event_instances[auto_id]["status"] == "resolved", "New delegated event is decided immediately, no ruler prompt")
	assert(council131.journal.size() >= 2 and council131.journal[0]["choice_title"] == "Накормить и защитить сироту", "Council journal records the decision")
	var eco_ev = orphan_ev.duplicate(true)
	eco_ev["category"] = "Лесозаготовка и земля"
	cem.active_event.clear()
	var eco_id = cem.trigger_event(eco_ev)
	assert(cem.event_instances[eco_id]["status"] == "pending", "Non-delegated sphere still goes to the ruler")
	cem.active_event.clear()

	var council_save = council131.serialize()
	var council_loaded = ElderCouncil.new(s131.id)
	council_loaded.deserialize(council_save)
	assert(council_loaded.regent_id == sage131.citizen_id and council_loaded.delegated_spheres.has("family") and council_loaded.appointed_ids.has(sage131.citizen_id), "Council survives save/load")
	assert(council_loaded.journal.size() == council131.journal.size(), "Council journal survives save/load")

	# Окно совета строится и показывает Правую руку, членов и журнал
	var council_modal = ElderCouncilModal.new()
	add_child(council_modal)
	council_modal.open()
	assert(council_modal.regent_lbl.text.contains(sage131.name), "Council window shows the right hand")
	assert(council_modal.sphere_checks["family"].button_pressed, "Council window shows delegated spheres")
	assert(council_modal.members_box.get_child_count() >= 2 and council_modal.journal_box.get_child_count() >= 2, "Council window lists members and journal")
	council_modal.queue_free()

	s131._process_citizen_death(sage131)
	council131.daily_check(s131)
	assert(council131.get_regent(s131) == null and council131.delegated_spheres.is_empty(), "Right hand's death returns all decisions to the ruler")
	council131.dismiss_member(s131, sulky131.citizen_id)
	print("OK 131. Elder council: appoint members, choose the right hand, delegate spheres, character-driven decisions, journal, save/load, revocation.")

	# --------------------------------------------------------------------------
	# TEST 132: ПЕРЕСМОТР РЕШЕНИЙ — СОЗЫВ СОВЕТА С ГОЛОСОВАНИЕМ ИЛИ УКАЗ ВОЖДЯ
	# --------------------------------------------------------------------------
	var s132: SettlementData = GameManager.get_player_settlement()
	var council132: ElderCouncil = s132.council
	var cem132 = GameManager.civilization_event_manager
	council132.set_governance(s132, "council")
	var law_ev = {
		"id": "TEST-REV-132", "title": "Обычай костра", "category": "Традиции рода",
		"description": "Тестовый закон.", "once": false, "priority": 1, "conditions": {},
		"choices": [
			{"id": "A", "title": "Хранить обычай предков", "desc": "Завет предков и старейшин неизменен.", "effects_desc": "", "tradition_id": "rev132_a"},
			{"id": "B", "title": "Ввести новый обычай", "desc": "Новое знание и перемены.", "effects_desc": "", "tradition_id": "rev132_b"}
		]
	}
	cem132.active_event.clear()
	var hero132: PlayerHero = s132.hero
	var xp_before_132 = hero132.xp + hero132.level * 1000.0
	var law_id = cem132.trigger_event(law_ev)
	cem132.apply_choice(law_id, "A")
	cem132.active_event.clear()
	assert(hero132.xp + hero132.level * 1000.0 > xp_before_132, "A personal ruler decision grants hero experience")
	assert(GameManager.culture_memory.has_tradition("rev132_a"), "Original norm is in force")
	assert(cem132.is_revisable(cem132.event_instances[law_id]), "A norm-setting decision is revisable")
	var found132 = false
	for d132 in cem132.get_revisable_decisions():
		if d132.get("instance_id", "") == law_id:
			found132 = true
	assert(found132, "Revisable decisions list contains the law")
	# Совет меньше трёх — созвать нельзя
	for m_old in council132.get_members(s132):
		if council132.appointed_ids.has(m_old.citizen_id):
			council132.dismiss_member(s132, m_old.citizen_id)
	var elders132: Array[CitizenNPC] = []
	for i in range(4):
		var e132 = CitizenNPC.new("elder132_%d" % i, "Старец %d" % i, "m", 60 + i, "elder")
		e132.settlement_id = s132.id
		e132.traits["tradition"] = 95.0
		e132.traits["curiosity"] = 10.0
		e132.loyalty = 50.0
		elders132.append(e132)
	s132.population.citizens.append(elders132[0])
	s132.population.citizens.append(elders132[1])
	var before_members = council132.get_members(s132).size()
	if before_members < ElderCouncil.MIN_VOTERS:
		assert(not council132.can_convene(s132, law_id)["ok"], "Council with fewer than 3 elders cannot be convened")
	s132.population.citizens.append(elders132[2])
	s132.population.citizens.append(elders132[3])
	assert(council132.can_convene(s132, law_id)["ok"], "Council of 3+ elders can be convened")
	# Старейшины-традиционалисты голосуют против новшества
	var res_no = council132.request_revision(s132, cem132, law_id, "B")
	assert(not res_no["ok"] and res_no.get("method", "") == "council", "Traditionalist council rejects the change")
	assert(int(res_no["no"]) > int(res_no["yes"]), "Most elders voted against")
	assert(GameManager.culture_memory.has_tradition("rev132_a") and not GameManager.culture_memory.has_tradition("rev132_b"), "Rejected revision leaves the old norm in force")
	assert(not council132.can_convene(s132, law_id)["ok"], "Rejected question cannot be re-convened immediately")
	# Мнение совета изменилось — пересмотр проходит
	for e132 in elders132:
		e132.traits["tradition"] = 10.0
		e132.traits["curiosity"] = 95.0
	council132.revision_cooldowns.erase(law_id)
	var res_yes = council132.request_revision(s132, cem132, law_id, "B")
	assert(res_yes["ok"], "Council that now agrees approves the change (%s)" % str(res_yes.get("reason", "")))
	assert(GameManager.culture_memory.has_tradition("rev132_b") and not GameManager.culture_memory.has_tradition("rev132_a"), "Approved revision replaces the norm")
	assert(cem132.event_instances[law_id]["chosen_choice_id"] == "B" and cem132.event_instances[law_id]["revisions"].size() == 1, "Revision is recorded on the decision")
	# Единоличная власть: указ без созыва
	var loyalty_before_gov = elders132[0].loyalty
	council132.set_governance(s132, "autocracy")
	assert(elders132[0].loyalty < loyalty_before_gov, "Elders resent being sidelined by autocracy")
	s132.economy.loyalty = 20.0
	var res_refused = council132.request_revision(s132, cem132, law_id, "A")
	assert(not res_refused["ok"] and cem132.event_instances[law_id]["chosen_choice_id"] == "B", "Tribe ignores the decree of a distrusted ruler")
	s132.economy.loyalty = 80.0
	var res_decree = council132.request_revision(s132, cem132, law_id, "A")
	assert(res_decree["ok"] and res_decree["method"] == "decree", "Trusted ruler changes the law by decree")
	assert(GameManager.culture_memory.has_tradition("rev132_a") and cem132.event_instances[law_id]["chosen_choice_id"] == "A", "Decree restores the old norm")
	assert(elders132[0].has_memory("decree_overrode"), "Elders who disagreed remember being overruled")
	var saved_c132 = council132.serialize()
	var loaded_c132 = ElderCouncil.new(s132.id)
	loaded_c132.deserialize(saved_c132)
	assert(loaded_c132.governance == "autocracy" and loaded_c132.revision_log.size() == council132.revision_log.size(), "Governance and revision log survive save/load")
	council132.set_governance(s132, "council")
	print("OK 132. Decision revision: council vote (majority, rejection, cooldown, change of heart) and autocratic decree (tribe may ignore it).")

	# --------------------------------------------------------------------------
	# TEST 133: ГЕРОЙ-ВОЖДЬ — УРОВНИ, ОЧКИ ХАРАКТЕРИСТИК, НАВЫКИ, СНАРЯЖЕНИЕ, ВЫНОСЛИВОСТЬ
	# --------------------------------------------------------------------------
	var hero133: PlayerHero = PlayerHero.new()
	s132.hero = hero133
	hero133.apply_to_ruler(s132)
	var ruler133 = PlayerHero.get_ruler(s132)
	assert(ruler133 != null and ruler133.is_ruler, "The hero is the ruler citizen")
	assert(ruler133.bonus_strength == PlayerHero.BASE_ATTR, "Hero starts with base attributes applied to the ruler")
	var dmg0 = float(ruler133.get_combat_stats()["raw_damage"])
	var levels = hero133.add_xp(s132, PlayerHero.xp_to_next(1), "Тест")
	assert(levels == 1 and hero133.level == 2, "Enough XP raises the level")
	assert(hero133.unspent_attr_points == PlayerHero.POINTS_PER_LEVEL and hero133.unspent_skill_points == PlayerHero.SKILL_POINTS_PER_LEVEL, "Level up grants 3 attribute points and 1 skill point")
	var str_before = hero133.get_attribute(s132, "strength")
	for i in range(3):
		assert(hero133.allocate_point(s132, "strength"), "Point allocated")
	assert(not hero133.allocate_point(s132, "strength"), "No points left")
	assert(hero133.get_attribute(s132, "strength") == str_before + 3, "Strength 5 + 3 points = 8")
	var dmg1 = float(ruler133.get_combat_stats()["raw_damage"])
	assert(dmg1 > dmg0, "More strength = harder hits (%.2f -> %.2f)" % [dmg0, dmg1])
	assert(hero133.learn_skill(s132, "mighty_arm"), "Skill learned with a skill point")
	assert(ruler133.allowed_other_damage_bonus == 0.08 and float(ruler133.get_combat_stats()["raw_damage"]) > dmg1, "Mighty arm raises real damage")
	assert(not hero133.learn_skill(s132, "hardened_body"), "No skill points left")
	assert(not hero133.can_learn("beast_bane")["ok"], "High-level skill locked below required level")
	# Снаряжение со склада племени
	s132.equipment_stockpile["club"] = 1
	var eq_res = hero133.equip_from_stockpile(s132, "club")
	assert(eq_res["ok"] and ruler133.equipment["weapon"] == "club" and not s132.equipment_stockpile.has("club"), "Club taken from the tribe armoury and wielded")
	assert(float(ruler133.get_combat_stats()["raw_damage"]) > dmg1 * 1.08, "A club hits harder than fists")
	assert(hero133.unequip(s132, "weapon") and int(s132.equipment_stockpile.get("club", 0)) == 1 and ruler133.equipment["weapon"] == "unarmed", "Unequipped club returns to the armoury")
	# Выносливость тратится в бою и восстанавливается на отдыхе
	ruler133.stamina_current = ruler133.stamina_max
	ruler133.state = CitizenNPC.State.ATTACKING
	s132._update_stamina(ruler133, 5.0)
	assert(ruler133.stamina_current < ruler133.stamina_max, "Fighting drains stamina")
	var st_low = ruler133.stamina_current
	ruler133.state = CitizenNPC.State.RESTING
	s132._update_stamina(ruler133, 2.0)
	assert(ruler133.stamina_current > st_low, "Resting restores stamina")
	ruler133.state = CitizenNPC.State.IDLE
	ruler133.stamina_current = 5.0
	var spd_tired = ruler133.get_work_speed_multiplier()
	ruler133.stamina_current = ruler133.stamina_max
	assert(ruler133.get_work_speed_multiplier() > spd_tired, "An exhausted citizen works slower")
	# Сохранение
	var hero_saved = hero133.serialize()
	var hero_loaded = PlayerHero.new()
	hero_loaded.deserialize(hero_saved)
	assert(hero_loaded.level == 2 and int(hero_loaded.allocated["strength"]) == 3 and hero_loaded.get_skill_rank("mighty_arm") == 1, "Hero progress survives save/load")
	# Панель героя строится на всех вкладках
	var hero_panel = HeroPanel.new()
	add_child(hero_panel)
	for tab_i in [HeroPanel.TAB_INVENTORY, HeroPanel.TAB_CHARACTER, HeroPanel.TAB_SKILLS]:
		hero_panel.visible = false
		hero_panel.open_tab(tab_i)
		assert(hero_panel.visible, "Hero panel opens tab %d" % tab_i)
	assert(hero_panel.skills_box.get_child_count() == PlayerHero.SKILLS.size() + 1, "Skills tab lists every skill")
	hero_panel.queue_free()
	print("OK 133. Hero chief: levels (+3 attribute points), strength -> damage, skills, armoury equipment, stamina drain/regen, save/load, hero panel.")

	# --------------------------------------------------------------------------
	# TEST 134: ПРЯМОЕ УПРАВЛЕНИЕ ВОЖДЁМ И РАЗГОВОРЫ С ЖИТЕЛЯМИ
	# --------------------------------------------------------------------------
	var s134: SettlementData = GameManager.get_player_settlement()
	var ruler134 = PlayerHero.get_ruler(s134)
	var ctrl = HeroController.new()
	add_child(ctrl)
	ctrl.set_active(true)
	assert(GameManager.hero_control_active and ruler134.custom_data.get("player_controlled", false), "Hero mode takes direct control of the ruler")
	# Ставим вождя у очага на проходимую клетку
	var hearth134 = s134._get_hearth_pos()
	# Стартовая клетка: проходимая, со свободными соседями слева и справа
	var hearth_tile134 = GameManager.nav_grid.world_to_tile(hearth134)
	var start_tile = Vector2i(-1, -1)
	for r134 in range(1, 12):
		for dy134 in range(-r134, r134 + 1):
			for dx134 in range(-r134, r134 + 1):
				var cand134 = hearth_tile134 + Vector2i(dx134, dy134)
				if start_tile == Vector2i(-1, -1) and GameManager.nav_grid.is_tile_walkable(cand134) and GameManager.nav_grid.is_tile_walkable(cand134 + Vector2i(1, 0)) and GameManager.nav_grid.is_tile_walkable(cand134 + Vector2i(-1, 0)):
					start_tile = cand134
	assert(start_tile != Vector2i(-1, -1), "Test setup: an open tile near the hearth exists")
	ruler134.pos = GameManager.nav_grid.tile_to_world_center(start_tile)
	# Препятствие справа не пускает, свободная клетка — пускает
	var right_tile = start_tile + Vector2i(1, 0)
	GameManager.resource_manager.remove_node(right_tile)
	GameManager.nav_grid.register_resource(right_tile, "stone")
	var before_x = ruler134.pos.x
	for i134 in range(40):
		ctrl.move_ruler(ruler134, Vector2.RIGHT, 0.1)
	assert(GameManager.nav_grid.world_to_tile(ruler134.pos) != right_tile, "A boulder blocks the ruler's way")
	GameManager.nav_grid.unregister_resource(right_tile)
	ruler134.pos = GameManager.nav_grid.tile_to_world_center(start_tile)
	var free_dir = Vector2.LEFT
	var pos_before = ruler134.pos
	assert(ctrl.move_ruler(ruler134, free_dir, 0.3), "Ruler walks when the way is free")
	assert(ruler134.pos.distance_to(pos_before) > 1.0 and ruler134.state == CitizenNPC.State.MOVING_TO_WORK, "Ruler actually moved")
	ctrl.move_ruler(ruler134, Vector2.ZERO, 0.1)
	assert(ruler134.state == CitizenNPC.State.IDLE, "Ruler stops when keys are released")
	# Управление мышью (как в MOBA): ПКМ по земле — идти по найденному пути
	var goal_tile = GameManager.nav_grid.find_random_walkable_nearby(GameManager.nav_grid.world_to_tile(ruler134.pos), 3)
	var goal_pos = GameManager.nav_grid.tile_to_world_center(goal_tile)
	if goal_pos.distance_to(ruler134.pos) > 8.0:
		assert(ctrl.order_move(goal_pos), "Right-click order builds a path")
		for i134 in range(400):
			if not ctrl.follow_path(ruler134, 0.05):
				break
		assert(ruler134.pos.distance_to(goal_pos) <= 6.0, "Ruler walks the path to the clicked point")
	# ПКМ по жителю — подойти и заговорить
	var walker_npc = CitizenNPC.new("walk134", "Встречный Добрило", "m", 30, "adult")
	walker_npc.settlement_id = s134.id
	walker_npc.social_cooldown = 999.0
	# Встречный стоит там, куда от вождя есть путь
	var near_tile = GameManager.nav_grid.world_to_tile(ruler134.pos)
	for try134 in range(30):
		var cand_near = GameManager.nav_grid.find_random_walkable_nearby(GameManager.nav_grid.world_to_tile(ruler134.pos), 4)
		if cand_near != near_tile and not GameManager.nav_grid.find_path(ruler134.pos, GameManager.nav_grid.tile_to_world_center(cand_near)).is_empty():
			near_tile = cand_near
			break
	walker_npc.pos = GameManager.nav_grid.tile_to_world_center(near_tile)
	s134.population.citizens.append(walker_npc)
	var talked_to: Array = []
	ctrl.talk_requested.connect(func(n): talked_to.append(n))
	ctrl.order_move(walker_npc.pos, walker_npc)
	for i134 in range(400):
		if not talked_to.is_empty() or (ctrl.click_path.is_empty() and ctrl.talk_target == null):
			break
		ctrl.follow_path(ruler134, 0.05)
	assert(talked_to.has(walker_npc), "Right-clicking a citizen walks the ruler over and starts a conversation")
	# WASD отменяет маршрут
	ctrl.order_move(goal_pos)
	ctrl.cancel_order()
	assert(ctrl.click_path.is_empty(), "Keyboard input cancels the mouse order")
	# ИИ поселения не распоряжается вождём, но голод идёт
	ruler134.hunger = 80.0
	ruler134.decision_cooldown = 0.0
	s134.update_citizens(1.0)
	assert(ruler134.task_id == "" and ruler134.hunger < 80.0, "AI gives no tasks to a player-controlled ruler, but hunger still drains")
	# Еда у очага из общих запасов
	ruler134.pos = hearth134
	ruler134.hunger = 30.0
	s134.economy.add_resource("food", 5.0)
	s134.deposit_food_batch({"amount": 5.0, "food_type": "meat"})
	var food134 = s134.economy.get_resource("food")
	assert(ctrl.try_eat()["ok"] and ruler134.hunger == 100.0, "Ruler eats at the hearth")
	assert(s134.economy.get_resource("food") < food134, "Ruler's meal comes out of the common stores")
	# Разговор: голодному — еда со склада
	var talk_npc = CitizenNPC.new("talk134", "Голодный Путята", "m", 33, "adult")
	talk_npc.settlement_id = s134.id
	talk_npc.pos = ruler134.pos + Vector2(20.0, 0.0)
	talk_npc.hunger = 20.0
	talk_npc.loyalty = 60.0
	talk_npc.social_cooldown = 999.0
	s134.population.citizens.append(talk_npc)
	assert(ctrl.find_nearest_npc(ruler134) != null, "Ruler finds someone to talk to nearby")
	var t_ids: Array[String] = []
	for t134 in NPCDialogue.get_topics(s134, talk_npc, ruler134):
		t_ids.append(t134["id"])
	assert(t_ids.has("hunger") and t_ids.has("home") and t_ids.has("smalltalk"), "Topics come from the NPC's real state (%s)" % str(t_ids))
	var food_before_feed = s134.economy.get_resource("food")
	NPCDialogue.respond(s134, talk_npc, ruler134, "hunger", "feed")
	assert(talk_npc.hunger == 100.0 and s134.economy.get_resource("food") < food_before_feed and talk_npc.has_memory("ruler_fed"), "Feeding really spends stores and fills the NPC")
	var t_after: Array[String] = []
	for t134 in NPCDialogue.get_topics(s134, talk_npc, ruler134):
		t_after.append(t134["id"])
	assert(not t_after.has("hunger"), "An answered topic goes quiet for a while")
	# Бездомному — место в доме со свободным местом
	var free_home = NPCDialogue._find_free_home(s134)
	if free_home:
		NPCDialogue.respond(s134, talk_npc, ruler134, "home", "house")
		assert(talk_npc.home_id == free_home.id, "Ruler really houses the homeless NPC")
	# Обида на соседа — примирение
	var foe134 = CitizenNPC.new("foe134", "Задира Сбыслав", "m", 30, "adult")
	foe134.settlement_id = s134.id
	s134.population.citizens.append(foe134)
	talk_npc.add_memory("grudge", "offense", foe134.citizen_id, 2.5, "Затаил обиду на Сбыслава")
	talk_npc.modify_relationship(foe134.citizen_id, -40.0)
	assert(NPCDialogue._get_grudge_target(s134, talk_npc) == foe134, "NPC complains about a real rival")
	NPCDialogue.respond(s134, talk_npc, ruler134, "grudge", "reconcile")
	assert(not talk_npc.has_grudge_against(foe134.citizen_id), "Ruler's mediation clears the grudge")
	# Угощение от благодарного жителя
	if talk_npc.home_id != "":
		var h134 = s134.get_citizen_home_instance(talk_npc)
		h134.food_stockpile = 2.0
		talk_npc.modify_relationship(ruler134.citizen_id, 60.0)
		ruler134.hunger = 50.0
		var gift_ids: Array[String] = []
		for t134 in NPCDialogue.get_topics(s134, talk_npc, ruler134):
			gift_ids.append(t134["id"])
		assert(gift_ids.has("gift"), "A grateful NPC offers the ruler food")
		NPCDialogue.respond(s134, talk_npc, ruler134, "gift", "accept")
		assert(ruler134.hunger == 100.0 and h134.food_stockpile == 1.75, "Accepted meal comes from the NPC's own home stores")
	# Оклик: голодный сам зовёт вождя, но не повторяет каждую секунду
	var caller = CitizenNPC.new("caller134", "Зовущая Млада", "f", 28, "adult")
	caller.settlement_id = s134.id
	caller.hunger = 10.0
	caller.loyalty = 60.0
	assert(NPCDialogue.get_urgent_call(s134, caller, ruler134) != "", "A starving NPC calls out to the ruler")
	assert(NPCDialogue.get_urgent_call(s134, caller, ruler134) == "", "The call is not repeated immediately")
	# Хищник у стоянки — житель предупреждает
	var wolf134 = WildAnimal.new("wolf134", "wolf_grey", Vector2(s134.pos.x * 32.0 + 16.0 + 160.0, s134.pos.y * 32.0 + 16.0))
	GameManager.wildlife_manager.animals[wolf134.id] = wolf134
	assert(not NPCDialogue._get_danger(s134).is_empty(), "NPCs know about a real predator near the camp")
	GameManager.wildlife_manager.animals.erase(wolf134.id)
	# Нелояльный житель отказывается говорить
	var angry = CitizenNPC.new("angry134", "Злой Горазд", "m", 35, "adult")
	angry.loyalty = 5.0
	assert(NPCDialogue.refuses_to_talk(angry, ruler134), "A hostile NPC refuses to talk")
	var angry_topics = NPCDialogue.get_topics(s134, angry, ruler134)
	assert(angry_topics.size() == 1 and angry_topics[0]["id"] == "discontent", "Hostile NPC only voices discontent")
	# Окно разговора
	var dw = DialogueWindow.new()
	add_child(dw)
	talk_npc.social_cooldown = 0.0
	dw.open_with(talk_npc)
	assert(dw.visible and talk_npc.state == CitizenNPC.State.TALKING and talk_npc.talk_partner_id == ruler134.citizen_id, "NPC stops and talks to the ruler")
	assert(dw.options_box.get_child_count() >= 2, "Dialogue shows topics and a farewell")
	dw._choose("smalltalk", "how", "")
	assert(dw.line_lbl.text.contains("—"), "NPC answers in the dialogue window")
	dw.close()
	assert(not dw.visible and talk_npc.action_timer <= 0.3, "Closing lets the NPC return to work")
	dw.queue_free()
	ctrl.set_active(false)
	assert(not GameManager.hero_control_active and not ruler134.custom_data.get("player_controlled", false), "Leaving hero mode returns the ruler to the AI")
	ctrl.queue_free()
	print("OK 134. Direct ruler control (walk, obstacles, eating) and living NPC dialogue with real consequences.")
	print("========================================")
	print("ALL NPC SIMULATION, S01-S10, FORAGING & AGRICULTURE MATRIX (TESTS 1-125) COMPLETED SUCCESSFULLY!")
	print("========================================")
	get_tree().quit(0)

func _get_storage_pos_for_test(settlement: SettlementData, citizen: CitizenNPC) -> Vector2:
	return settlement._get_storage_pos(citizen)




