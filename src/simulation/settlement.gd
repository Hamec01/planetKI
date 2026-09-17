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
	"elder": 1,
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

var priority_harvest_coords: Array[Vector2i] = []

func deposit_resource(res_name: String, amount: float, source_name: String = "") -> void:
	if amount <= 0.0 or res_name == "":
		return
	economy.add_resource(res_name, amount)
	var is_player = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "player_tribe_settlement" or id == "test_s")
	if is_player:
		EventBus.resources_updated.emit(faction_id, economy.resources)
		var res_names_ru = {
			"wood": "древесины",
			"food": "пищи",
			"stone": "камня",
			"metal": "металла",
			"leather": "кожи",
			"bones": "костей",
			"fur": "меха"
		}
		var name_ru = res_names_ru.get(res_name, res_name)
		var total_amt = int(economy.get_resource(res_name))
		var msg = "+%d %s на склад поселения (Всего: %d)" % [int(amount), name_ru, total_amt]
		if source_name != "":
			msg = "%s доставил +%d %s (Всего: %d)" % [source_name, int(amount), name_ru, total_amt]
		EventBus.notification_toast.emit("Поступление ресурсов", msg, "good")

func _on_order_harvest_resource(target_coord: Vector2i, category: String) -> void:
	var is_player = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "player_tribe_settlement" or id == "test_s")
	if not is_player:
		return
	if not priority_harvest_coords.has(target_coord):
		priority_harvest_coords.append(target_coord)
	_dispatch_priority_worker(target_coord, category)

func _dispatch_priority_worker(target_coord: Vector2i, category: String) -> void:
	if not population or population.citizens.is_empty():
		return
	var target_job = "woodcutter" if category == "wood" else ("forager" if category == "food" else "quarryman")
	for c in population.citizens:
		if c.job_id == target_job and c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
			if GameManager.resource_manager and GameManager.resource_manager.reserve_node(target_coord, c.citizen_id):
				c.task_id = "chop_tree" if category == "wood" else "gather"
				c.target_coord = target_coord
				var node = GameManager.resource_manager.nodes.get(target_coord, {})
				c.target_pos = node.get("pos", GameManager.nav_grid.tile_to_world_center(target_coord))
				c.target_id = node.get("id", "")
				c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
				c.path_index = 0
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Идёт на первоочередную вырубку дерева" if category == "wood" else "Идёт на первоочередной сбор"
				EventBus.notification_toast.emit(
					"Приказ выполнен",
					"%s направлен на первоочередную задачу (%s)" % [c.name, node.get("name", "Ресурс")],
					"info"
				)
				return

func _init(p_id: String = "", p_name: String = "", p_faction: String = "", p_pos: Vector2i = Vector2i.ZERO) -> void:
	id = p_id
	name = p_name
	faction_id = p_faction
	pos = p_pos
	
	# Ровно 1 стартовое здание
	buildings = ["elders_house"]
	
	if not EventBus.order_harvest_resource.is_connected(_on_order_harvest_resource):
		EventBus.order_harvest_resource.connect(_on_order_harvest_resource)

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

func get_idle_citizens() -> Array[CitizenNPC]:
	var result: Array[CitizenNPC] = []
	if not population:
		return result
	for c in population.citizens:
		if c.is_idle():
			result.append(c)
	return result

func get_idle_workforce() -> int:
	return get_idle_citizens().size()

func get_total_assigned_workers() -> int:
	var total = 0
	if population:
		for c in population.citizens:
			if not c.is_idle() and c.cohort in ["adult", "youth", "elder"]:
				total += 1
	return total

func can_assign_worker(_job_id: String) -> bool:
	return get_idle_workforce() > 0

func sync_assigned_jobs_from_citizens() -> void:
	if not population:
		return
	for j in assigned_jobs:
		assigned_jobs[j] = 0
	for c in population.citizens:
		if c.job_id != "idle":
			assigned_jobs[c.job_id] = assigned_jobs.get(c.job_id, 0) + 1

func assign_worker(job_id: String, delta: int) -> bool:
	if delta > 0 and get_idle_workforce() < delta:
		return false
	if delta < 0 and assigned_jobs.get(job_id, 0) + delta < 0:
		return false
		
	if delta > 0:
		var remaining = delta
		for c in get_idle_citizens():
			c.set_job(job_id)
			remaining -= 1
			if remaining <= 0:
				break
	elif delta < 0:
		var remaining = -delta
		for c in population.citizens:
			if c.job_id == job_id:
				if c.workplace_id != "" and GameManager and GameManager.building_instances:
					for b_inst in GameManager.building_instances.values():
						if b_inst and "id" in b_inst and b_inst.id == c.workplace_id:
							b_inst.remove_worker(c.citizen_id)
				c.set_job("idle")
				c.workplace_id = ""
				c.workplace_coord = Vector2i(-1, -1)
				remaining -= 1
				if remaining <= 0:
					break
	sync_assigned_jobs_from_citizens()
	return true

func init_citizens_on_map() -> void:
	var center_pixel = Vector2(pos.x * 32.0 + 16.0, pos.y * 32.0 + 16.0)
	for c in population.citizens:
		c.settlement_id = id
		c.home_id = "elders_house"
		c.home_coord = pos
		c.home_pos = center_pixel
		c.pos = center_pixel + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		if c.job_id == "elder":
			c.workplace_id = "elders_house"
			c.workplace_coord = pos

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
	# Охотники: физический цикл NPC (Этап C)
	var hunt_prod = 0.0
	
	# Собиратели: физический цикл NPC (Этап B)
	var for_prod = 0.0
	
	var farmers = assigned_jobs.get("farmer", 0)
	var farm_prod = 0.0
	if season == "Осень":
		farm_prod = farmers * 3.5
	elif season == "Лето":
		farm_prod = farmers * 1.2
	elif season == "Весна":
		farm_prod = farmers * 0.4
		
	# Лесорубы: физический цикл NPC (Этап E)
	var wood_prod = 0.0
	
	# Каменотёсы: физический цикл NPC (Этап E)
	var stone_prod = 0.0
	
	# Рудокопы: физический цикл NPC (Этап E)
	var metal_prod = 0.0
	
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
	
	# Охотники: физический цикл NPC (Этап C)
	# Пассивное начисление ОТКЛЮЧЕНО для исключения двойного учета (ТЗ п.10)
	var hunt_prod = 0.0
	prod["food"] = prod.get("food", 0.0) + hunt_prod
	
	# Собиратели: физический цикл NPC (Этап B)
	# Пассивное начисление ОТКЛЮЧЕНО для исключения двойного учета (ТЗ п.10)
	var for_prod = 0.0
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
	
	# Лесорубы: физический цикл NPC (Этап E)
	var wood_prod = 0.0
	prod["wood"] = prod.get("wood", 0.0) + wood_prod
	
	# Каменотёсы: физический цикл NPC (Этап E)
	var stone_prod = 0.0
	prod["stone"] = prod.get("stone", 0.0) + stone_prod
	
	# Рудокопы: физический цикл NPC (Этап E)
	var metal_prod = 0.0
	prod["metal"] = prod.get("metal", 0.0) + metal_prod
	
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

# ==============================================================================
# ЖИВАЯ СИМУЛЯЦИЯ ГРАЖДАН (1 ГРАЖДАНИН = 1 NPC)
# ==============================================================================
func update_citizens(delta: float) -> void:
	if not population or population.citizens.is_empty():
		return
		
	var cur_hour = GameManager.current_hour
	var center_pixel = Vector2(pos.x * 32.0 + 16.0, pos.y * 32.0 + 16.0)
	
	for c in population.citizens:
		# 1. Индивидуальное суточное время
		var indiv_hour = cur_hour + c.schedule_offset_hours
		if indiv_hour >= 24.0: indiv_hour -= 24.0
		elif indiv_hour < 0.0: indiv_hour += 24.0
		var is_night = (indiv_hour >= 22.0 or indiv_hour < 6.0)
		
		# 2. Обновление речевого облачка
		if c.speech_timer > 0.0:
			c.speech_timer -= delta
			if c.speech_timer <= 0.0:
				c.speech_bubble = ""

		# Реакция на непосредственную опасность (ТЗ п.5, 14, 21 Этап F)
		var threat_nearby = false
		var nearest_threat_pos = Vector2.ZERO
		for f_id in GameManager.factions:
			if f_id != faction_id:
				var f = GameManager.factions[f_id]
				for a in f.armies:
					if a.get_total_soldiers() > 0:
						var d = c.pos.distance_to(a.world_pos)
						if d < 180.0:
							threat_nearby = true
							nearest_threat_pos = a.world_pos
							break
			if threat_nearby:
				break
				
		if threat_nearby:
			if c.job_id in ["guard", "warrior"]:
				c.facing_dir = (nearest_threat_pos - c.pos).normalized()
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Защищает поселение от врагов!"
				continue
			else:
				if c.state != CitizenNPC.State.FLEEING:
					c.state = CitizenNPC.State.FLEEING
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.last_status_reason = "Спасается бегством в укрытие!"
					c.shout("Тревога! Враги близко!", 3.0)
					continue
				
		# 3. Ночной режим: Сон в хижине (стража не спит ночью — выходит в ночной дозор)
		if is_night and c.job_id != "guard":
			if c.state == CitizenNPC.State.SLEEPING:
				c.energy = minf(100.0, c.energy + 12.0 * delta)
				c.last_status_reason = "Спит в хижине" if c.home_id != "" else "Спит под звёздами"
				continue
			elif c.state == CitizenNPC.State.GOING_HOME:
				var reached = c.update_movement(delta)
				if reached or c.pos.distance_to(c.home_pos) < 6.0:
					c.state = CitizenNPC.State.SLEEPING
					c.last_status_reason = "Спит в хижине" if c.home_id != "" else "Спит под звёздами"
			else:
				# Если нёс груз — сдаем перед сном
				if c.cargo_type != "" and c.cargo_amount > 0:
					deposit_resource(c.cargo_type, c.cargo_amount, c.name)
					c.cargo_type = ""
					c.cargo_amount = 0.0
				c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
				c.path_index = 0
				c.state = CitizenNPC.State.GOING_HOME
				c.last_status_reason = "Возвращается домой ко сну"
			continue
			
		# Дневной отдых для ночной стражи (с 10:00 до 16:00)
		if not is_night and c.job_id == "guard" and GameManager.current_hour >= 10.0 and GameManager.current_hour < 16.0:
			if c.state != CitizenNPC.State.SLEEPING and c.state != CitizenNPC.State.GOING_HOME:
				c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
				c.path_index = 0
				c.state = CitizenNPC.State.GOING_HOME
				c.last_status_reason = "Идёт на дневной отдых после ночного дозора"
			elif c.state == CitizenNPC.State.GOING_HOME:
				var reached = c.update_movement(delta)
				if reached or c.pos.distance_to(c.home_pos) < 6.0:
					c.state = CitizenNPC.State.SLEEPING
					c.last_status_reason = "Спит после ночного дозора"
			elif c.state == CitizenNPC.State.SLEEPING:
				c.energy = minf(100.0, c.energy + 12.0 * delta)
				c.last_status_reason = "Спит после ночного дозора"
			continue
			
		# 4. Дневной режим: Работа, Быт, Общение
		if c.state == CitizenNPC.State.SLEEPING:
			c.state = CitizenNPC.State.IDLE
			c.last_status_reason = "Пробуждение"
			c.decision_cooldown = randf_range(0.5, 2.0)
			
		# Снижение бодрости и сытости
		c.energy = maxf(0.0, c.energy - 0.4 * delta)
		c.hunger = maxf(0.0, c.hunger - 0.5 * delta)
		
		# Питание при сильном голоде
		if c.hunger < 45.0 and economy.get_resource("food") >= 0.5:
			economy.resources["food"] -= 0.5
			c.hunger = 100.0
			c.last_status_reason = "Поел у очага"
			
		# Общение двух свободных жителей
		if c.state == CitizenNPC.State.TALKING:
			c.action_timer -= delta
			if c.action_timer <= 0.0:
				c.state = CitizenNPC.State.IDLE
				c.talk_partner_id = ""
				c.last_status_reason = "Закончил разговор"
			continue
			
		# Движение к цели
		if c.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.GOING_HOME]:
			# Особая обработка охотника на ходу (преследование и дистанция атаки)
			if c.job_id == "hunter" and c.state == CitizenNPC.State.MOVING_TO_WORK:
				if c.target_id.begins_with("carcass_"):
					var arrived_carcass = c.update_movement(delta)
					var reached_carcass = arrived_carcass
					if GameManager.wildlife_manager.carcasses.has(c.target_id):
						if c.pos.distance_to(GameManager.wildlife_manager.carcasses[c.target_id]["pos"]) <= 24.0:
							reached_carcass = true
					if reached_carcass:
						var h_res = GameManager.wildlife_manager.harvest_carcass(c.target_id, c.max_carry)
						GameManager.wildlife_manager.release_carcass(c.target_id, c.citizen_id)
						c.target_id = ""
						var meat = h_res.get("meat", 0.0) if h_res is Dictionary else float(h_res)
						if h_res is Dictionary:
							var mat = h_res.get("material", "")
							var mat_cnt = h_res.get("material_count", 0)
							if mat != "" and mat_cnt > 0:
								deposit_resource(mat, float(mat_cnt), c.name)
						if meat > 0.0:
							c.cargo_type = "carcass"
							c.cargo_amount = meat
							var camp_p = _find_hunting_camp_pos(c)
							c.path = GameManager.nav_grid.find_path(c.pos, camp_p)
							c.path_index = 0
							c.state = CitizenNPC.State.CARRYING
							c.last_status_reason = "Несёт тушу в охотничий лагерь"
						else:
							c.state = CitizenNPC.State.IDLE
							c.decision_cooldown = 1.0
					continue
				elif c.target_id != "":
					if not GameManager.wildlife_manager.animals.has(c.target_id):
						c.target_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 1.0
						continue
					var animal = GameManager.wildlife_manager.animals[c.target_id]
					c.action_timer += delta
					
					# Проверка лимитов погони (ТЗ: не преследовать бесконечно через всю карту)
					var dist_from_camp = c.pos.distance_to(_find_hunting_camp_pos(c))
					if c.action_timer > 18.0 or dist_from_camp > 1000.0 or animal.state == WildAnimal.State.SWIMMING:
						GameManager.wildlife_manager.release_animal(c.target_id, c.citizen_id)
						c.target_id = ""
						c.action_timer = 0.0
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 2.0
						c.last_status_reason = "Потерял добычу из виду" if animal.state != WildAnimal.State.SWIMMING else "Добыча спаслась на воде"
						continue
						
					var dist_to_animal = c.pos.distance_to(animal.pos)
					if dist_to_animal <= 70.0:
						c.path.clear()
						c.facing_dir = (animal.pos - c.pos).normalized()
						c.state = CitizenNPC.State.ATTACKING
						c.work_timer = 1.2
						c.last_status_reason = "Атакует %s" % _get_animal_display_name(animal.type_id)
						continue
					else:
						if animal.pos.distance_to(c.target_pos) > 40.0:
							c.target_pos = animal.pos
							c.path = GameManager.nav_grid.find_path(c.pos, animal.pos)
							c.path_index = 0
						var arrived = c.update_movement(delta)
						if arrived and dist_to_animal > 70.0:
							c.target_pos = animal.pos
							c.path = GameManager.nav_grid.find_path(c.pos, animal.pos)
							c.path_index = 0
						continue

			var arrived = c.update_movement(delta)
			if arrived:
				if c.state == CitizenNPC.State.MOVING_TO_WORK:
					if c.job_id == "forager":
						c.state = CitizenNPC.State.GATHERING
						c.work_timer = randf_range(2.0, 3.5)
						c.last_status_reason = "Собирает ягоды"
					elif c.job_id == "woodcutter":
						c.state = CitizenNPC.State.WORKING
						if c.task_id == "plant_tree":
							c.work_timer = 2.5
							c.last_status_reason = "Сажает саженец дерева"
						else:
							c.work_timer = 0.75
							c.last_status_reason = "Рубит дерево топором"
					else:
						c.state = CitizenNPC.State.WORKING
						c.work_timer = randf_range(3.0, 5.5)
						c.last_status_reason = _get_job_action_name(c.job_id)
				elif c.state == CitizenNPC.State.CARRYING or c.state == CitizenNPC.State.GOING_HOME:
					if c.cargo_type == "carcass":
						c.state = CitizenNPC.State.BUTCHERING
						c.work_timer = 2.5
						c.last_status_reason = "Разделывает добычу в лагере"
						continue
					elif c.cargo_type != "" and c.cargo_amount > 0:
						deposit_resource(c.cargo_type, c.cargo_amount, c.name)
						c.last_status_reason = "Сдал %d %s в амбар" % [int(c.cargo_amount), c.cargo_type]
						c.cargo_type = ""
						c.cargo_amount = 0.0
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = randf_range(1.5, 3.0)
			continue
			
		# Сбор ягод и растений (GATHERING)
		if c.state == CitizenNPC.State.GATHERING:
			c.work_timer -= delta
			if c.work_timer <= 0.0:
				var harvested = 0.0
				if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
					harvested = GameManager.resource_manager.harvest_from_node(c.target_coord, 4.0)
					GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
				if harvested > 0.0:
					c.cargo_type = "food"
					c.cargo_amount += harvested
				c.target_coord = Vector2i(-1, -1)
				c.state = CitizenNPC.State.CARRYING
				c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
				c.path_index = 0
				c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
			continue
			
		# Атака зверя охотником (ATTACKING)
		if c.state == CitizenNPC.State.ATTACKING:
			c.work_timer -= delta
			if not GameManager.wildlife_manager.animals.has(c.target_id):
				c.target_id = ""
				c.state = CitizenNPC.State.IDLE
				c.decision_cooldown = 1.0
				continue
			var animal = GameManager.wildlife_manager.animals[c.target_id]
			c.facing_dir = (animal.pos - c.pos).normalized()
			if c.work_timer <= 0.0:
				var killed = animal.take_damage(20.0, c.citizen_id)
				if killed:
					var carcass = GameManager.wildlife_manager.create_carcass_from_animal(animal)
					GameManager.wildlife_manager.animals.erase(c.target_id)
					c.target_id = carcass["id"]
					c.target_pos = carcass["pos"]
					c.path = GameManager.nav_grid.find_path(c.pos, carcass["pos"])
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Добыл зверя, идёт к туше"
				else:
					c.target_pos = animal.pos
					c.path = GameManager.nav_grid.find_path(c.pos, animal.pos)
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Преследует раненого зверя"
			continue

		# Разделка добычи в охотничьем лагере (BUTCHERING)
		if c.state == CitizenNPC.State.BUTCHERING:
			c.work_timer -= delta
			if c.work_timer <= 0.0:
				c.cargo_type = "food"
				c.state = CitizenNPC.State.CARRYING
				c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
				c.path_index = 0
				c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
			continue

		# Выполнение работы на месте
		if c.state == CitizenNPC.State.WORKING:
			c.work_timer -= delta
			if c.work_timer <= 0.0:
				if c.job_id == "woodcutter":
					if c.task_id == "plant_tree":
						if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
							GameManager.resource_manager.plant_tree(c.target_coord, "tree_young", "tree_pine" if randf() > 0.5 else "tree_oak")
						c.target_coord = Vector2i(-1, -1)
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = randf_range(1.5, 3.0)
						c.last_status_reason = "Посадил молодой саженец"
						EventBus.notification_toast.emit("Посадка леса", "Лесорубы посеяли молодое дерево", "good")
					else:
						# УДАР ТОПОРОМ: прогрессивное снятие порции древесины (25 дров за удар)
						var strike_harvest = 25.0
						var h_amount = 0.0
						if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
							h_amount = GameManager.resource_manager.harvest_from_node(c.target_coord, strike_harvest)
						
						if h_amount > 0.0:
							c.cargo_type = "wood"
							c.cargo_amount += h_amount
							
						# Проверяем оставшийся запас в дереве
						var node = GameManager.resource_manager.nodes.get(c.target_coord, {}) if GameManager.resource_manager else {}
						var rem_wood = float(node.get("amount", 0.0)) if not node.is_empty() else 0.0
						var is_done = node.get("depleted", false) or rem_wood <= 0.0 or h_amount <= 0.0
						
						if is_done or c.cargo_amount >= 100.0:
							# Дерево срублено полностью (или достигнут лимит 100 дров)
							if GameManager.resource_manager:
								GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
							if priority_harvest_coords.has(c.target_coord):
								priority_harvest_coords.erase(c.target_coord)
								
							if c.cargo_amount > 0.0:
								c.state = CitizenNPC.State.CARRYING
								c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
								c.path_index = 0
								c.last_status_reason = "Срубил дерево, несёт %d дров на склад" % int(c.cargo_amount)
							else:
								c.state = CitizenNPC.State.IDLE
								c.decision_cooldown = 1.0
							c.target_coord = Vector2i(-1, -1)
							c.task_id = ""
						else:
							# Следующий удар топором через 0.75 сек
							c.work_timer = 0.75
							c.last_status_reason = "Рубит дерево (осталось %d дров)" % int(rem_wood)
				elif c.job_id in ["quarryman", "miner"]:
					var res_cat = "stone" if c.job_id == "quarryman" else "metal"
					var h_amount = 0.0
					if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
						h_amount = GameManager.resource_manager.harvest_from_node(c.target_coord, 4.0)
						GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
					if h_amount > 0.0:
						c.cargo_type = res_cat
						c.cargo_amount = h_amount
					c.target_coord = Vector2i(-1, -1)
					c.state = CitizenNPC.State.CARRYING
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.last_status_reason = "Несёт %d %s на склад" % [int(c.cargo_amount), c.cargo_type]
				elif c.job_id == "builder":
					if GameManager.tile_buildings.has(c.target_coord):
						var b = GameManager.tile_buildings[c.target_coord]
						if b.get("status", "") == "constructing":
							b["days_left"] = maxf(0.0, b.get("days_left", 1.0) - 0.25)
							if b["days_left"] <= 0.0:
								b["status"] = "active"
								if not buildings.has(b["id"]):
									buildings.append(b["id"])
								c.last_status_reason = "Завершил строительство здания"
								var b_name = BuildingDB.get_building(b["id"]).get("name", b["id"])
								EventBus.notification_toast.emit("Стройка завершена", "Построено: %s" % b_name, "good")
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = 1.5
				elif c.job_id == "sage":
					economy.add_resource("knowledge", 0.5)
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = randf_range(2.0, 4.0)
					c.last_status_reason = "Записал предание в свитки"
				elif c.job_id == "priest":
					economy.add_resource("faith", 0.4)
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = randf_range(2.0, 4.0)
					c.last_status_reason = "Вознёс молитву духам"
				elif c.job_id == "guard":
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = randf_range(2.0, 5.0)
					c.last_status_reason = "Патрулирует периметр"
				else:
					var res_type = _get_cargo_for_job(c.job_id)
					if res_type != "":
						c.cargo_type = res_type
						c.cargo_amount = randi_range(2, 4)
						c.state = CitizenNPC.State.CARRYING
						c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
						c.path_index = 0
						c.last_status_reason = "Несёт %d %s в поселение" % [int(c.cargo_amount), c.cargo_type]
					else:
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = randf_range(2.0, 4.0)
			continue
			
		# Свободный выбор нового действия (IDLE или WAITING)
		if c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
			c.decision_cooldown -= delta
			if c.decision_cooldown > 0.0:
				continue
				
			# 1. Особая логика для Собирателя (Этап B)
			if c.job_id == "forager" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount >= c.max_carry:
					c.state = CitizenNPC.State.CARRYING
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
					continue
					
				var f_node = GameManager.resource_manager.find_available_node(pos, "food", 14, c.citizen_id)
				if not f_node.is_empty():
					GameManager.resource_manager.reserve_node(f_node["coord"], c.citizen_id)
					c.target_coord = f_node["coord"]
					c.target_pos = f_node["pos"]
					c.target_id = f_node["id"]
					c.path = GameManager.nav_grid.find_path(c.pos, f_node["pos"])
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт к: %s" % f_node["name"]
					c.decision_cooldown = 0.8
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступных ягодных кустов"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue
				
			# 2. Особая логика для Охотника (Этап C)
			if c.job_id == "hunter" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_type == "carcass":
					var camp_p = _find_hunting_camp_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, camp_p)
					c.path_index = 0
					c.state = CitizenNPC.State.CARRYING
					c.last_status_reason = "Несёт тушу в охотничий лагерь"
					continue
				elif c.cargo_type == "food" and c.cargo_amount > 0:
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.state = CitizenNPC.State.CARRYING
					c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
					continue
					
				var carcass = GameManager.wildlife_manager.find_nearest_carcass(c.pos, 500.0, c.citizen_id)
				if not carcass.is_empty():
					GameManager.wildlife_manager.reserve_carcass(carcass["id"], c.citizen_id)
					c.target_id = carcass["id"]
					c.target_pos = carcass["pos"]
					c.path = GameManager.nav_grid.find_path(c.pos, carcass["pos"])
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт забирать тушу (%s)" % _get_animal_display_name(carcass.get("type_id", carcass["species"]))
					c.decision_cooldown = 0.8
					continue
					
				var target_animal = GameManager.wildlife_manager.find_nearest_hunt_target(c.pos, 1000.0, c.citizen_id)
				if target_animal != null:
					GameManager.wildlife_manager.reserve_animal(target_animal.id, c.citizen_id)
					c.target_id = target_animal.id
					c.target_pos = target_animal.pos
					c.path = GameManager.nav_grid.find_path(c.pos, target_animal.pos)
					c.path_index = 0
					c.action_timer = 0.0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Выслеживает %s" % _get_animal_display_name(target_animal.type_id)
					c.decision_cooldown = 0.8
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступной добычи"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue

			# 3. Особая логика для Лесоруба (Рубка 1 дерево = 100 дров + Посадка леса)
			if c.job_id == "woodcutter" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount > 0.0:
					c.state = CitizenNPC.State.CARRYING
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.last_status_reason = "Несёт %d дров на склад" % int(c.cargo_amount)
					continue
					
				# Проверяем наличие Лагеря лесорубов и улучшения на посадку леса
				var can_plant = false
				var plant_mode = false
				for b_coord in GameManager.building_instances:
					var b_inst = GameManager.building_instances[b_coord]
					if b_inst and "type" in b_inst and b_inst.type == "woodcutter_camp":
						if b_inst.is_upgrade_unlocked("woodcutter_forestry"):
							can_plant = true
						if b_inst.active_mode == "reforestation":
							plant_mode = true
							can_plant = true
							
				# Если включен режим лесопосадки или есть улучшение (шанс посеять саженец)
				if can_plant and (plant_mode or randf() < 0.35):
					var plant_tile = GameManager.resource_manager.find_plantable_tile(pos, 12)
					if plant_tile != Vector2i(-1, -1):
						c.task_id = "plant_tree"
						c.target_coord = plant_tile
						c.target_pos = GameManager.nav_grid.tile_to_world_center(plant_tile)
						c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
						c.path_index = 0
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.last_status_reason = "Идёт сажать саженец дерева"
						c.decision_cooldown = 0.8
						continue
						
				# 1. Проверяем первоочередные цели игрока
				var chosen_tree: Dictionary = {}
				for p_coord in priority_harvest_coords:
					var p_node = GameManager.resource_manager.nodes.get(p_coord, {}) if GameManager.resource_manager else {}
					if not p_node.is_empty() and p_node.get("category", "") == "wood" and not p_node.get("depleted", false) and p_node.get("amount", 0.0) > 0.0:
						if p_node.get("reserved_by", "") == "" or p_node.get("reserved_by", "") == c.citizen_id:
							chosen_tree = p_node
							break
				
				# 2. Обычная заготовка: поиск зрелого дерева если нет приоритетных
				var tree = chosen_tree
				if tree.is_empty() and GameManager.resource_manager:
					tree = GameManager.resource_manager.find_available_node(pos, "wood", 24, c.citizen_id)
				if not tree.is_empty():
					GameManager.resource_manager.reserve_node(tree["coord"], c.citizen_id)
					c.task_id = "chop_tree"
					c.target_coord = tree["coord"]
					c.target_pos = tree["pos"]
					c.target_id = tree["id"]
					c.path = GameManager.nav_grid.find_path(c.pos, tree["pos"])
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт рубить: %s" % tree["name"]
					c.decision_cooldown = 0.8
				else:
					if can_plant:
						var plant_tile = GameManager.resource_manager.find_plantable_tile(pos, 14)
						if plant_tile != Vector2i(-1, -1):
							c.task_id = "plant_tree"
							c.target_coord = plant_tile
							c.target_pos = GameManager.nav_grid.tile_to_world_center(plant_tile)
							c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.last_status_reason = "Восстанавливает вырубку: сажает дерево"
							c.decision_cooldown = 0.8
							continue
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступных деревьев"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue

			# 4. Особая логика для Каменотёса (Этап E)
			if c.job_id == "quarryman" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount >= c.max_carry:
					c.state = CitizenNPC.State.CARRYING
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.last_status_reason = "Несёт %d камня на склад" % int(c.cargo_amount)
					continue
				var rock = GameManager.resource_manager.find_available_node(pos, "stone", 16, c.citizen_id)
				if not rock.is_empty():
					GameManager.resource_manager.reserve_node(rock["coord"], c.citizen_id)
					c.target_coord = rock["coord"]
					c.target_pos = rock["pos"]
					c.target_id = rock["id"]
					c.path = GameManager.nav_grid.find_path(c.pos, rock["pos"])
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт добывать: %s" % rock["name"]
					c.decision_cooldown = 0.8
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступного камня"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue

			# 5. Особая логика для Рудокопа (Этап E)
			if c.job_id == "miner" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount >= c.max_carry:
					c.state = CitizenNPC.State.CARRYING
					c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					c.path_index = 0
					c.last_status_reason = "Несёт %d руды на склад" % int(c.cargo_amount)
					continue
				var ore = GameManager.resource_manager.find_available_node(pos, "metal", 20, c.citizen_id)
				if not ore.is_empty():
					GameManager.resource_manager.reserve_node(ore["coord"], c.citizen_id)
					c.target_coord = ore["coord"]
					c.target_pos = ore["pos"]
					c.target_id = ore["id"]
					c.path = GameManager.nav_grid.find_path(c.pos, ore["pos"])
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт к: %s" % ore["name"]
					c.decision_cooldown = 0.8
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступных жил руды"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue

			# 6. Особая логика для Строителя (Этап E)
			if c.job_id == "builder" and c.cohort in ["youth", "adult", "elder"]:
				var constr_coord = Vector2i(-1, -1)
				for b_coord in GameManager.tile_buildings:
					var b = GameManager.tile_buildings[b_coord]
					if b.get("status", "") == "constructing":
						constr_coord = b_coord
						break
				if constr_coord != Vector2i(-1, -1):
					c.target_coord = constr_coord
					c.target_pos = GameManager.nav_grid.tile_to_world_center(constr_coord)
					c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт на стройплощадку"
					c.decision_cooldown = 1.0
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет активных строек"
					c.decision_cooldown = randf_range(4.0, 7.0)
				continue

			# 7. Особая логика для Стражника (Этап E)
			if c.job_id == "guard" and c.cohort in ["youth", "adult", "elder"]:
				var patrol_tile = GameManager.nav_grid.find_random_walkable_nearby(pos, 4)
				var patrol_pos = GameManager.nav_grid.tile_to_world_center(patrol_tile)
				c.path = GameManager.nav_grid.find_path(c.pos, patrol_pos)
				c.path_index = 0
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Патрулирует границу стоянки"
				c.decision_cooldown = randf_range(5.0, 8.0)
				continue
				
			# 8. Мудрецы и Жрецы
			if c.job_id in ["sage", "priest"] and c.cohort in ["youth", "adult", "elder"]:
				var target_p = _find_job_work_target(c)
				c.target_pos = target_p
				c.path = GameManager.nav_grid.find_path(c.pos, target_p)
				c.path_index = 0
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Идёт к месту служения (%s)" % _get_job_display_name(c.job_id)
				c.decision_cooldown = 1.0
				continue

			# 9. Если есть другая назначенная работа и житель трудоспособен
			if c.job_id != "idle" and c.cohort in ["youth", "adult", "elder"]:
				var target_p = _find_job_work_target(c)
				c.target_pos = target_p
				c.path = GameManager.nav_grid.find_path(c.pos, target_p)
				c.path_index = 0
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Идёт к месту работы (%s)" % _get_job_display_name(c.job_id)
				c.decision_cooldown = 1.0
			else:
				# 10. Свободные жители, дети и старики (Этап D)
				var partner = _find_chat_partner(c)
				if partner != null and randf() < 0.40:
					_start_social_dialog(c, partner)
					continue
					
				var dest_tile = GameManager.nav_grid.find_random_walkable_nearby(pos, 3)
				var dest_pos = GameManager.nav_grid.tile_to_world_center(dest_tile) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
				c.path = GameManager.nav_grid.find_path(c.pos, dest_pos)
				c.path_index = 0
				c.state = CitizenNPC.State.GOING_HOME
				if c.cohort == "child":
					c.last_status_reason = "Гуляет и играет у хижины"
				elif c.cohort == "elder":
					c.last_status_reason = "Отдыхает у костра"
				else:
					c.last_status_reason = "Отдыхает в свободное время"
				c.decision_cooldown = randf_range(6.0, 12.0)

func _get_job_display_name(job: String) -> String:
	match job:
		"hunter": return "Охота"
		"forager": return "Собирательство"
		"woodcutter": return "Лесозаготовка"
		"quarryman": return "Каменоломня"
		"miner": return "Рудник"
		"builder": return "Стройка"
		"farmer": return "Поле"
		"craftsman": return "Мастерская"
		"sage": return "Совет старейшин"
		"priest": return "Святилище"
		"guard": return "Дозор"
		"warrior": return "Тренировка"
		_: return "Свободный"

func _get_job_action_name(job: String) -> String:
	match job:
		"hunter": return "Выслеживает добычу"
		"forager": return "Собирает ягоды и травы"
		"woodcutter": return "Рубит дерево"
		"quarryman": return "Обтёсывает камень"
		"miner": return "Добывает руду"
		"builder": return "Работает на стройке"
		"farmer": return "Ухаживает за посевами"
		"craftsman": return "Изготавливает изделия"
		"sage": return "Размышляет в совете"
		"priest": return "Творит священный обряд"
		"guard": return "Охраняет поселение"
		"warrior": return "Отрабатывает удары"
		_: return "Занят делом"

func _get_cargo_for_job(job: String) -> String:
	match job:
		"woodcutter": return "wood"
		"quarryman": return "stone"
		"miner": return "metal"
		"hunter", "forager", "farmer": return "food"
		"craftsman": return "kubriki"
		"builder": return ""
		_: return ""

func _find_chat_partner(citizen: CitizenNPC) -> CitizenNPC:
	for other in population.citizens:
		if other != citizen and other.state == CitizenNPC.State.IDLE and other.pos.distance_to(citizen.pos) < 28.0:
			return other
	return null

func _start_social_dialog(c1: CitizenNPC, c2: CitizenNPC) -> void:
	c1.facing_dir = (c2.pos - c1.pos).normalized()
	c2.facing_dir = (c1.pos - c2.pos).normalized()
	c1.state = CitizenNPC.State.TALKING
	c2.state = CitizenNPC.State.TALKING
	c1.action_timer = 3.0
	c2.action_timer = 3.0
	c1.talk_partner_id = c2.citizen_id
	c2.talk_partner_id = c1.citizen_id
	
	var phrases = [
		"Славная погода сегодня!",
		"В лесу полно дичи и ягод.",
		"Запасы племени растут!",
		"Огонь очага греет душу.",
		"Предки хранят наше племя."
	]
	var ph = phrases[randi() % phrases.size()]
	c1.shout(ph, 3.0)
	c1.last_status_reason = "Беседует с " + c2.name
	c2.last_status_reason = "Слушает " + c1.name

func _find_job_work_target(c: CitizenNPC) -> Vector2:
	var tiles = GameManager.planet_data.get("tiles", [])
	if tiles.is_empty():
		return c.home_pos + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		
	# Строители бегут к реальной стройплощадке
	if c.job_id == "builder":
		for coord in GameManager.tile_buildings:
			var b = GameManager.tile_buildings[coord]
			if b.get("status", "") == "constructing":
				return GameManager.nav_grid.tile_to_world_center(coord)
				
	# Лесорубы идут к лесным биомам
	if c.job_id == "woodcutter":
		var candidates: Array[Vector2i] = []
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var check_c = pos + Vector2i(dx, dy)
				if GameManager.nav_grid.is_tile_walkable(check_c):
					var t = tiles[check_c.y][check_c.x]
					if t["biome"] in [BiomeDefinitions.BiomeType.DECIDUOUS_FOREST, BiomeDefinitions.BiomeType.PINE_TAIGA, BiomeDefinitions.BiomeType.JUNGLE]:
						candidates.append(check_c)
		if not candidates.is_empty():
			return GameManager.nav_grid.tile_to_world_center(candidates[randi() % candidates.size()])
			
	# Каменотёсы к холмам и горам
	if c.job_id in ["quarryman", "miner"]:
		var candidates: Array[Vector2i] = []
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var check_c = pos + Vector2i(dx, dy)
				if GameManager.nav_grid.is_tile_walkable(check_c):
					var t = tiles[check_c.y][check_c.x]
					if t["biome"] in [BiomeDefinitions.BiomeType.HILLS, BiomeDefinitions.BiomeType.MOUNTAINS]:
						candidates.append(check_c)
		if not candidates.is_empty():
			return GameManager.nav_grid.tile_to_world_center(candidates[randi() % candidates.size()])
			
	# По умолчанию: случайная проходимая сухая клетка в радиусе 3-4 клеток
	var t_rand = GameManager.nav_grid.find_random_walkable_nearby(pos, 3)
	return GameManager.nav_grid.tile_to_world_center(t_rand)

func _find_hunting_camp_pos(c: CitizenNPC) -> Vector2:
	if c.workplace_coord != Vector2i(-1, -1) and GameManager.nav_grid:
		return GameManager.nav_grid.tile_to_world_center(c.workplace_coord)
	if GameManager.tile_buildings:
		for coord in GameManager.tile_buildings.keys():
			var b = GameManager.tile_buildings[coord]
			if b is Dictionary and b.get("id", "") == "hunting_camp":
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(coord)
	if GameManager.building_instances:
		for coord in GameManager.building_instances.keys():
			var b = GameManager.building_instances[coord]
			if b and "type" in b and b.type == "hunting_camp":
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(coord)
	return c.home_pos

func _get_animal_display_name(type_id: String) -> String:
	match type_id:
		"wolf_grey", "wolf_dark": return "волка"
		"wolf_pup": return "волчонка"
		"hare_brown", "hare_white": return "зайца"
		"hare_leveret": return "зайчонка"
		"deer_stag", "deer_doe": return "оленя"
		"deer_fawn": return "оленёнка"
		"moose_bull", "moose_cow": return "лося"
		"moose_calf": return "лосёнка"
		"bear_brown", "bear_dark": return "медведя"
		"bear_cub": return "медвежонка"
		"boar_male", "boar_female": return "кабана"
		"boar_piglet": return "поросёнка"
		"fox_adult": return "лису"
		"fox_kit": return "лисёнка"
		"lynx_adult": return "рысь"
		"badger_adult": return "барсука"
		"drake", "duck": return "утку"
		_: return "дичь"

func serialize() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"faction_id": faction_id,
		"pos_x": pos.x,
		"pos_y": pos.y,
		"buildings": buildings.duplicate(),
		"assigned_jobs": assigned_jobs.duplicate(),
		"economy": economy.resources.duplicate(),
		"population": population.serialize() if population else {}
	}

func deserialize(data: Dictionary) -> void:
	id = data.get("id", id)
	name = data.get("name", name)
	faction_id = data.get("faction_id", faction_id)
	pos = Vector2i(data.get("pos_x", pos.x), data.get("pos_y", pos.y))
	buildings.assign(data.get("buildings", []))
	assigned_jobs = data.get("assigned_jobs", {})
	if data.has("economy"):
		economy.resources = data["economy"].duplicate()
	if data.has("population") and population:
		population.deserialize(data["population"])
