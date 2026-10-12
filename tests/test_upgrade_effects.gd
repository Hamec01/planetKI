extends Node

# Проверка, что улучшения зданий, исследования и решения событий реально меняют мир,
# а постройки не залезают друг на друга.

func _ready() -> void:
	print("========================================")
	print("TEST: UPGRADE EFFECTS, RESEARCH, EVENT CONSEQUENCES, BUILDING OVERLAP")
	print("========================================")
	var faction = FactionData.new("fx_test", "Племя проверки", "Вождь", Color.WHITE, false)
	GameManager.factions[faction.id] = faction
	var s = SettlementData.new("fx_test_settlement", "Стоянка проверки", faction.id, Vector2i(200, 200))
	GameManager.settlements[s.id] = s

	# 1. Улучшение мастерской даёт реальный бонус к рубке, а следующее требует предыдущего
	var ws = BuildingInstance.new("fx_ws", "craft_workshop", s.id, Vector2i(205, 205))
	GameManager.building_instances[ws.pos] = ws
	assert(is_equal_approx(s.get_bonus("woodcutting_speed"), 0.0), "No bonus before upgrades")
	assert(not ws.start_upgrade("forge_reinforced_pickaxes"), "Upgrade with unmet prerequisite must be refused")
	ws.unlock_upgrade("forge_copper_axes")
	assert(is_equal_approx(s.get_bonus("woodcutting_speed"), 0.15), "Copper axes give +15%% woodcutting (got %.2f)" % s.get_bonus("woodcutting_speed"))
	assert(ws.start_upgrade("forge_reinforced_pickaxes"), "Upgrade allowed once prerequisite is built")
	ws.unlock_upgrade("forge_reinforced_pickaxes")
	assert(is_equal_approx(s.get_bonus("stone_speed"), 0.15), "Reinforced pickaxes give +15% stone")
	assert(BuildingSystem.get_upgrades_for_building("craft_workshop").size() >= 12, "Workshop exposes forge and carpentry branches")
	print("OK 1. Building upgrades apply real bonuses and respect prerequisites.")

	# 2. Амбар реально снижает порчу пищи
	var granary = BuildingInstance.new("fx_gr", "granary", s.id, Vector2i(207, 205))
	GameManager.building_instances[granary.pos] = granary
	var spoil_before = s.get_granary_spoilage_factor()
	granary.unlock_upgrade("granary_dry_decking")
	assert(s.get_granary_spoilage_factor() < spoil_before, "Dry decking lowers spoilage factor")
	print("OK 2. Granary upgrade lowers real food spoilage.")

	# 3. Исследование: соблюдение порядка открытий, прогресс не теряется, эффект входит в бонусы
	assert(not faction.can_research("food_preservation"), "Tech with unmet prerequisite is locked")
	assert(faction.set_research("flint_knapping"), "Root tech can be researched")
	faction.sim_daily_research(10.0)
	assert(faction.set_research("trapping_hunting"), "Switching research works")
	assert(is_equal_approx(float(faction.research_saved.get("flint_knapping", 0.0)), 10.0), "Progress of the previous topic is kept")
	faction.set_research("flint_knapping")
	assert(is_equal_approx(faction.research_progress, 10.0), "Returning restores saved progress")
	faction.sim_daily_research(25.0)
	assert(faction.unlocked_techs.has("flint_knapping"), "Tech unlocks when cost is reached")
	assert(is_equal_approx(s.get_bonus("woodcutting_speed"), 0.35), "Tech wood bonus adds to upgrade bonus (got %.2f)" % s.get_bonus("woodcutting_speed"))
	assert(faction.can_research("food_preservation") == false and faction.can_research("primitive_agriculture"), "Unlocked tech opens its children")
	print("OK 3. Research respects prerequisites, keeps progress and applies effects.")

	# 4. Последствия решения события меняют ресурсы, веру и дают долговременный бонус
	s.economy.resources["wood"] = 50.0
	var faith_before = s.economy.get_resource("faith")
	GameManager.civilization_event_manager._apply_generic_consequences({}, {"title": "Проверка"}, {"wood_cost": 10.0, "spiritual_zeal": 8.0, "hunt_damage_boost": 0.15, "nature_respect": true}, s, s.population, GameManager.culture_memory)
	assert(is_equal_approx(s.economy.get_resource("wood"), 40.0), "wood_cost takes wood from storage")
	assert(s.economy.get_resource("faith") > faith_before, "spiritual_zeal adds faith")
	assert(is_equal_approx(s.get_bonus("hunter_damage"), 0.15), "hunt_damage_boost becomes a settlement bonus")
	assert(GameManager.culture_memory.discovered_practices.has("nature_respect"), "Flag consequence becomes a cultural practice")
	var saved = s.serialize()
	var s2 = SettlementData.new("fx_test_settlement_2", "Копия", faction.id, Vector2i(10, 10))
	s2.deserialize(saved)
	assert(is_equal_approx(float(s2.event_bonuses.get("hunter_damage", 0.0)), 0.15), "Event bonuses survive save/load")
	print("OK 4. Event decisions have real, persistent consequences.")

	# 5. Постройки не перекрывают друг друга: большой Дом рода занимает больше одной клетки
	GameManager.tile_buildings[Vector2i(220, 220)] = {"id": "great_lodge", "status": "active"}
	if ComposerBuildings.has_building("great_lodge"):
		assert(BuildingSystem.overlaps_existing(Vector2i(221, 220), "hut"), "Hut right next to a big lodge overlaps it")
		assert(BuildingSystem.get_covered_tiles(Vector2i(220, 220), "great_lodge").size() > 1, "Big lodge covers several ground tiles")
	assert(not BuildingSystem.overlaps_existing(Vector2i(226, 220), "hut"), "Hut far enough away is allowed")
	assert(BuildingSystem.overlaps_existing(Vector2i(220, 220), "hut"), "Occupied tile is always an overlap")
	GameManager.tile_buildings.erase(Vector2i(220, 220))
	print("OK 5. Building footprints prevent overlapping sprites.")

	# 6. Воин на тренировке реально растит телесный опыт
	var w = CitizenNPC.new("fx_warrior", "Воин проверки", "m", 25, "adult")
	var str_before = w.strength_xp
	w.add_work_xp("combat_training", 0.35)
	assert(w.strength_xp > str_before, "Combat training grows strength experience")
	print("OK 6. Warrior drills grow real experience.")

	GameManager.building_instances.erase(ws.pos)
	GameManager.building_instances.erase(granary.pos)
	GameManager.settlements.erase(s.id)
	GameManager.factions.erase(faction.id)
	print("ALL UPGRADE EFFECT TESTS: PASS")
	get_tree().quit()
