class_name SettlementData
extends RefCounted

const PopulationSim = preload("res://src/simulation/population_sim.gd")
const EconomySim = preload("res://src/simulation/economy_sim.gd")
const BuildingDB = preload("res://src/simulation/building_db.gd")

var id: String = ""
var name: String = "Стоянка Первого Костра"
var faction_id: String = ""
var pos: Vector2i = Vector2i.ZERO

var population: RefCounted = PopulationSim.new()
var economy: RefCounted = EconomySim.new()

# Построенные здания: 1 стартовое здание — Хижина Старейшины
var buildings: Array[String] = ["elders_house"]

# Строящиеся здания: Array of Dictionaries
var construction_queue: Array[Dictionary] = []

# Назначенные рабочие для стартовых 10 поселенцев: 2 собирателя, 2 лесоруба, 1 охотник, 1 строитель (4 свободных)
var assigned_jobs: Dictionary = {
	"hunter": 1,
	"forager": 2,
	"woodcutter": 2,
	"quarryman": 0,
	"miner": 0,
	"farmer": 0,
	"craftsman": 0,
	"sage": 0,
	"priest": 0,
	"builder": 1,
	"warrior": 0
}

func _init(p_id: String = "", p_name: String = "", p_faction: String = "", p_pos: Vector2i = Vector2i.ZERO) -> void:
	id = p_id
	name = p_name
	faction_id = p_faction
	pos = p_pos
	
	# Ровно 1 стартовое здание
	buildings = ["elders_house"]

func get_housing_capacity() -> int:
	var cap = 15 # Базовый навес под открытым небом
	for b_id in buildings:
		var b_info = BuildingDB.get_building(b_id)
		cap += b_info.get("housing", 0)
	return cap

func get_defense_rating() -> float:
	var def = 5.0
	for b_id in buildings:
		var b_info = BuildingDB.get_building(b_id)
		def += b_info.get("defense_bonus", 0.0)
	return def

func get_granary_spoilage_factor() -> float:
	var factor = 1.0
	for b_id in buildings:
		var b_info = BuildingDB.get_building(b_id)
		if b_info.has("food_spoilage_reduction"):
			factor *= b_info["food_spoilage_reduction"]
	return factor

func get_total_assigned_workers() -> int:
	var total = 0
	for j in assigned_jobs:
		total += assigned_jobs[j]
	return total

func get_idle_workforce() -> int:
	return max(0, population.get_workforce_total() - get_total_assigned_workers())

func can_assign_worker(job_id: String) -> bool:
	return get_idle_workforce() > 0

func assign_worker(job_id: String, delta: int) -> bool:
	if delta > 0 and get_idle_workforce() < delta:
		return false
	if delta < 0 and assigned_jobs.get(job_id, 0) + delta < 0:
		return false
	assigned_jobs[job_id] = assigned_jobs.get(job_id, 0) + delta
	return true

func find_available_tile_for_building() -> Vector2i:
	if not GameManager.planet_data.has("tiles"):
		return Vector2i(-1, -1)
	var tiles = GameManager.planet_data["tiles"]
	
	# Поиск по расширяющимся кольцам суши вокруг стоянки
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(abs(dx), abs(dy)) != r:
					continue
				var c = pos + Vector2i(dx, dy)
				if c.y >= 0 and c.y < tiles.size() and c.x >= 0 and c.x < tiles[0].size():
					var t = tiles[c.y][c.x]
					if not t.get("is_water", false) and not GameManager.tile_buildings.has(c) and c != pos:
						return c
	return Vector2i(-1, -1)

func init_starter_buildings_on_map() -> void:
	# На карту выставляется ровно 1 стартовое здание — Хижина Старейшины
	GameManager.tile_buildings[pos] = {
		"id": "elders_house",
		"status": "active",
		"settlement_id": id
	}

func start_construction(building_id: String, target_coord: Vector2i = Vector2i(-1, -1)) -> bool:
	var b_info = BuildingDB.get_building(building_id)
	if b_info.is_empty():
		return false
	if not economy.deduct_cost(b_info["cost"]):
		return false
		
	if target_coord == Vector2i(-1, -1):
		target_coord = find_available_tile_for_building()
		
	construction_queue.append({
		"id": building_id,
		"coord": target_coord,
		"days_left": b_info["build_days"],
		"total_days": b_info["build_days"],
		"name": b_info["name"]
	})
	
	GameManager.tile_buildings[target_coord] = {
		"id": building_id,
		"status": "constructing",
		"days_left": float(b_info["build_days"]),
		"total_days": int(b_info["build_days"]),
		"settlement_id": id
	}
	return true

func move_queue_item(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= construction_queue.size():
		return
	if to_idx < 0 or to_idx >= construction_queue.size():
		return
	var item = construction_queue.pop_at(from_idx)
	construction_queue.insert(to_idx, item)

func cancel_queue_item(idx: int) -> void:
	if idx < 0 or idx >= construction_queue.size():
		return
	var item = construction_queue[idx]
	var b_info = BuildingDB.get_building(item["id"])
	if not b_info.is_empty():
		# Возврат 75% стоимости
		for res in b_info.get("cost", {}):
			economy.add_resource(res, b_info["cost"][res] * 0.75)
			
	var coord = item.get("coord", Vector2i(-1, -1))
	if coord != Vector2i(-1, -1):
		GameManager.tile_buildings.erase(coord)
		
	construction_queue.remove_at(idx)


func toggle_pause_queue_item(idx: int) -> void:
	if idx < 0 or idx >= construction_queue.size():
		return
	var item = construction_queue[idx]
	item["is_paused"] = not item.get("is_paused", false)

func get_detailed_ledger(season: String) -> Dictionary:
	var hunters = assigned_jobs.get("hunter", 0)
	var hunt_prod = hunters * 1.4 * (0.7 if season == "Зима" else 1.0)
	
	var foragers = assigned_jobs.get("forager", 0)
	var for_prod = foragers * 1.1 * (0.2 if season == "Зима" else (1.4 if season == "Лето" or season == "Осень" else 1.0))
	
	var farmers = assigned_jobs.get("farmer", 0)
	var farm_prod = 0.0
	if season == "Осень":
		farm_prod = farmers * 3.5
	elif season == "Лето":
		farm_prod = farmers * 1.2
	elif season == "Весна":
		farm_prod = farmers * 0.4
		
	var woodcutters = assigned_jobs.get("woodcutter", 0)
	var wood_prod = woodcutters * 1.2
	
	var quarrymen = assigned_jobs.get("quarryman", 0)
	var stone_prod = quarrymen * 1.0
	
	var miners = assigned_jobs.get("miner", 0)
	var metal_prod = miners * 0.5
	
	var craftsmen = assigned_jobs.get("craftsman", 0)
	var kubriki_prod = craftsmen * 0.8
	var craft_know_prod = craftsmen * 0.2
	
	var sages = assigned_jobs.get("sage", 0)
	var sage_know_prod = sages * 0.8
	
	var priests = assigned_jobs.get("priest", 0)
	var faith_prod = priests * 0.5
	
	var pop_count = population.get_total_population()
	var pop_food_expense = pop_count * EconomySim.FOOD_CONSUMPTION_PER_POP_DAILY
	
	var total_food_income = hunt_prod + for_prod + farm_prod
	var net_food = total_food_income - pop_food_expense
	var total_know_income = craft_know_prod + sage_know_prod
	
	var expense_dict = {
			"food": pop_food_expense,
			"wood": 0.0,
			"stone": 0.0,
			"metal": 0.0,
			"kubriki": 0.0,
			"knowledge": 0.0,
			"faith": 0.0
		}
	return {
		"income": {
			"food": total_food_income,
			"wood": wood_prod,
			"stone": stone_prod,
			"metal": metal_prod,
			"kubriki": kubriki_prod,
			"knowledge": total_know_income,
			"faith": faith_prod
		},
		"expense": expense_dict,
		"expenses": expense_dict,
		"net": {
			"food": net_food,
			"wood": wood_prod,
			"stone": stone_prod,
			"metal": metal_prod,
			"kubriki": kubriki_prod,
			"knowledge": total_know_income,
			"faith": faith_prod
		},
		"breakdown": {
			"food": {
				"Охота": hunt_prod,
				"Собирательство": for_prod,
				"Поля/Фермы": farm_prod,
				"Расход населения": -pop_food_expense
			},
			"wood": {
				"Лесорубы": wood_prod
			},
			"stone": {
				"Каменоломни": stone_prod
			},
			"metal": {
				"Рудники": metal_prod
			},
			"kubriki": {
				"Ремесленники и рынок": kubriki_prod
			},
			"knowledge": {
				"Мудрецы": sage_know_prod,
				"Ремесленники": craft_know_prod
			}
		}
	}

func calculate_daily_production(season: String) -> Dictionary:
	var prod: Dictionary = {}
	
	# Охотники
	var hunters = assigned_jobs.get("hunter", 0)
	var hunt_prod = hunters * 1.4 * (0.7 if season == "Зима" else 1.0)
	prod["food"] = prod.get("food", 0.0) + hunt_prod
	
	# Собиратели
	var foragers = assigned_jobs.get("forager", 0)
	var for_prod = foragers * 1.1 * (0.2 if season == "Зима" else (1.4 if season == "Лето" or season == "Осень" else 1.0))
	prod["food"] = prod.get("food", 0.0) + for_prod
	
	# Земледельцы
	var farmers = assigned_jobs.get("farmer", 0)
	var farm_prod = 0.0
	if season == "Осень":
		farm_prod = farmers * 3.5 # Сезон сбора урожая
	elif season == "Лето":
		farm_prod = farmers * 1.2
	elif season == "Весна":
		farm_prod = farmers * 0.4
	prod["food"] = prod.get("food", 0.0) + farm_prod
	
	# Лесорубы
	var woodcutters = assigned_jobs.get("woodcutter", 0)
	prod["wood"] = prod.get("wood", 0.0) + woodcutters * 1.2
	
	# Каменотёсы
	var quarrymen = assigned_jobs.get("quarryman", 0)
	prod["stone"] = prod.get("stone", 0.0) + quarrymen * 1.0
	
	# Рудокопы
	var miners = assigned_jobs.get("miner", 0)
	prod["metal"] = prod.get("metal", 0.0) + miners * 0.5
	
	# Ремесленники
	var craftsmen = assigned_jobs.get("craftsman", 0)
	prod["kubriki"] = prod.get("kubriki", 0.0) + craftsmen * 0.8
	prod["knowledge"] = prod.get("knowledge", 0.0) + craftsmen * 0.2
	
	# Мудрецы
	var sages = assigned_jobs.get("sage", 0)
	prod["knowledge"] = prod.get("knowledge", 0.0) + sages * 0.8
	
	# Жрецы
	var priests = assigned_jobs.get("priest", 0)
	prod["faith"] = prod.get("faith", 0.0) + priests * 0.5
	prod["loyalty"] = prod.get("loyalty", 0.0) + priests * 0.1
	
	return prod

func sim_daily_tick(season: String) -> void:
	# 1. Прогресс строительства
	var builders = assigned_jobs.get("builder", 0)
	var build_speed = 1.0 + builders * 0.5
	var completed = []
	for i in range(construction_queue.size()):
		var item = construction_queue[i]
		if item.get("is_paused", false):
			continue
		item["days_left"] -= build_speed
		if item["days_left"] <= 0:
			completed.append(i)
			buildings.append(item["id"])
			var coord = item.get("coord", Vector2i(-1, -1))
			if coord != Vector2i(-1, -1):
				GameManager.tile_buildings[coord] = {
					"id": item["id"],
					"status": "active",
					"settlement_id": id
				}
			var b_info = BuildingDB.get_building(item["id"])
			GameManager.add_history_entry(GameManager.current_year, "Постройка завершена", "В поселении %s возведено новое здание: %s." % [name, b_info["name"]], "Строительство")
			EventBus.building_constructed.emit(id, b_info)
			break # Строим по очереди (первое активное)
		else:
			var coord = item.get("coord", Vector2i(-1, -1))
			if coord != Vector2i(-1, -1) and GameManager.tile_buildings.has(coord):
				GameManager.tile_buildings[coord]["days_left"] = item["days_left"]

			
	# Удаляем завершенные из очереди
	for i in range(completed.size() - 1, -1, -1):
		construction_queue.remove_at(completed[i])
		
	# 2. Производство и потребление
	var prod = calculate_daily_production(season)
	var spoilage_factor = get_granary_spoilage_factor()
	var econ_result = economy.sim_daily_tick(population.get_total_population(), prod, spoilage_factor)
	
	if faction_id == GameManager.player_faction_id:
		EventBus.resources_updated.emit(faction_id, economy.resources)

func sim_monthly_tick(season: String) -> void:
	var food_ratio = 1.0
	var pop_res = population.sim_monthly_tick(food_ratio, get_housing_capacity(), season)
	if pop_res["births"] > 0:
		EventBus.person_born.emit(id)
	if pop_res["deaths"] > 0:
		EventBus.person_died.emit(id, ", ".join(pop_res["reasons"]))
	EventBus.population_changed.emit(faction_id, pop_res["total"], pop_res["births"] - pop_res["deaths"], "Естественный прирост")

