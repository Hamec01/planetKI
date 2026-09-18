class_name AIController
extends RefCounted

static func process_ai_daily(faction: FactionData, settlement: SettlementData, season: String) -> void:
	if faction.is_player or settlement == null:
		return
		
	# 1. Симуляция поселения
	settlement.sim_daily_tick(season)
	
	# Прогресс исследований
	var sages = settlement.assigned_jobs.get("sage", 0)
	var k_rate = 0.2 + sages * 0.8
	faction.sim_daily_research(k_rate)
	
	# 2. Периодическое принятие решений (раз в 15 дней)
	if GameManager.current_day % 15 == 0:
		_evaluate_ai_decisions(faction, settlement, season)

static func _evaluate_ai_decisions(faction: FactionData, settlement: SettlementData, _season: String) -> void:
	var total_pop = settlement.population.get_total_population()
	var food = settlement.economy.get_resource("food")
	var wood = settlement.economy.get_resource("wood")
	var stone = settlement.economy.get_resource("stone")
	
	# 1. Потребность в жилье
	if total_pop >= settlement.get_housing_capacity() and settlement.construction_queue.is_empty():
		if wood >= 15:
			settlement.start_construction("hut")
			return
			
	# 2. Потребность в еде
	if food < total_pop * 1.5 and settlement.construction_queue.is_empty():
		if wood >= 20 and not settlement.buildings.has("hunting_camp"):
			settlement.start_construction("hunting_camp")
		elif wood >= 10 and not settlement.buildings.has("foraging_post"):
			settlement.start_construction("foraging_post")
			
	# 3. Потребность в обороне при агрессивном соседе
	if faction.personality == "aggressive" or faction.personality == "religious":
		if wood >= 50 and stone >= 10 and not settlement.buildings.has("palisade") and settlement.construction_queue.is_empty():
			settlement.start_construction("palisade")
			
	# 4. Балансировка рабочих
	var idle = settlement.get_idle_workforce()
	if idle > 0:
		if food < 50:
			settlement.assign_worker("hunter", 1)
		elif wood < 30:
			settlement.assign_worker("woodcutter", 1)
		elif stone < 20:
			settlement.assign_worker("quarryman", 1)
		else:
			settlement.assign_worker("builder", 1)
			
	# 5. Выбор следующего исследования если не выбрано
	if faction.current_research_tech == "":
		var available = ["trapping_hunting", "flint_knapping", "food_preservation", "primitive_agriculture", "shamanic_rites"]
		for t in available:
			if not faction.unlocked_techs.has(t):
				faction.current_research_tech = t
				break
