class_name SettlementData
extends RefCounted


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
	"fisherman": 0,
	"woodcutter": 2,
	"quarryman": 0,
	"miner": 0,
	"farmer": 0,
	"seed_keeper": 0,
	"miller": 0,
	"baker": 0,
	"craftsman": 0,
	"tanner": 0,
	"sage": 0,
	"priest": 0,
	"guard": 0,
	"builder": 1,
	"warrior": 0
}

# Скрытые направления аграрных знаний (ТЗ Foraging & Agriculture)
var knowledge: Dictionary = {
	"plant_knowledge": 5.0,
	"rain_knowledge": 0.0,
	"seed_knowledge": 0.0,
	"soil_knowledge": 0.0,
	"storage_knowledge": 0.0,
	"grain_knowledge": 0.0,
	"cultivation_knowledge": 0.0,
	"food_processing_knowledge": 0.0,
	"water_management_knowledge": 0.0
}

func add_knowledge(key: String, amount: float) -> void:
	knowledge[key] = maxf(0.0, float(knowledge.get(key, 0.0)) + amount)
	if economy:
		economy.add_resource("knowledge", amount * 0.25)

func get_knowledge_level(key: String) -> float:
	return float(knowledge.get(key, 0.0))

func get_knowledge_stage_name(key: String) -> String:
	var val = get_knowledge_level(key)
	if val < 10.0:
		return "Неизвестно"
	elif val < 30.0:
		return "Наблюдается"
	elif val < 65.0:
		return "Изучается"
	elif val < 120.0:
		return "Практикуется"
	else:
		return "Освоено"

var priority_harvest_coords: Array[Vector2i] = []
var food_batches: Array[Dictionary] = []
var _next_batch_id: int = 1
var marriage_law: String = "monogamy" # "monogamy", "polygamy", "free_union"
var reserved_zones: Array[Dictionary] = []
var active_relocations: Dictionary = {}
var equipment_stockpile: Dictionary = {}


# Родовой могильник / Кладбище предков (максимум 4 клетки)
const MAX_CEMETERY_PLOTS: int = 4
var cemetery_plots: Array[Vector2i] = []
var deceased_registry: Array[Dictionary] = []

# Система живых NPC и социальных связей (ТЗ NPC_ALIVE_SYSTEM_TZ.md)
var event_reactor: NPCEventReactor = null
var relationship_graph: NPCRelationshipGraph = null
var citizens: Array:
	get: return population.citizens if population else []

func get_deceased_registry() -> Array[Dictionary]:
	return deceased_registry

func can_manage_reserved_zones() -> bool:
	var faction = GameManager.factions.get(faction_id, null) if GameManager else null
	return faction != null and faction.active_laws.has("land_territorial_zones")

func set_reserved_zone(zone_id: String, tile_coords: Array[Vector2i]) -> bool:
	if zone_id == "" or tile_coords.is_empty() or not can_manage_reserved_zones():
		return false
	var serialized_tiles: Array[Array] = []
	for coord in tile_coords:
		serialized_tiles.append([coord.x, coord.y])
	for zone in reserved_zones:
		if zone.get("id", "") == zone_id:
			zone["tiles"] = serialized_tiles
			return true
	reserved_zones.append({"id": zone_id, "tiles": serialized_tiles})
	return true

# --- ЗОНЫ ВЫРУБКИ ЛЕСА ПОСЕЛЕНИЯ (P01.9: WC-01) ---
var logging_zones: Array[Vector2i] = []

func has_active_logging_zone() -> bool:
	return not logging_zones.is_empty() or not priority_harvest_coords.is_empty()

func is_tile_in_logging_zone(coord: Vector2i) -> bool:
	return logging_zones.has(coord) or priority_harvest_coords.has(coord)

func set_logging_zone(coords: Array[Vector2i]) -> void:
	logging_zones.assign(coords)

func add_to_logging_zone(coord: Vector2i) -> void:
	if not logging_zones.has(coord):
		logging_zones.append(coord)

func remove_from_logging_zone(coord: Vector2i) -> void:
	logging_zones.erase(coord)

func deposit_food_batch(batch: Dictionary) -> void:
	if batch.is_empty():
		return
	var b_amount = float(batch.get("amount", 0.0))
	if b_amount <= 0.0:
		return
	var b_id = batch.get("batch_id", "")
	if b_id == "":
		b_id = "batch_%d" % _next_batch_id
		_next_batch_id += 1
	var new_b = {
		"batch_id": b_id,
		"food_type": batch.get("food_type", "berries"),
		"amount": b_amount,
		"created_sim_time": float(batch.get("created_sim_time", GameManager.sim_time_total)),
		"max_freshness_sec": float(batch.get("max_freshness_sec", 3600.0)),
		"spoilage_progress": float(batch.get("spoilage_progress", 0.0))
	}
	food_batches.append(new_b)

func consume_food(request_amount: float) -> float:
	if request_amount <= 0.0:
		return 0.0
	var _consumed = 0.0
	var rem_to_consume = request_amount
	var i = 0
	while i < food_batches.size() and rem_to_consume > 0.0:
		var b = food_batches[i]
		var b_amt = float(b.get("amount", 0.0))
		if b_amt <= rem_to_consume:
			_consumed += b_amt
			rem_to_consume -= b_amt
			food_batches.remove_at(i)
		else:
			b["amount"] = b_amt - rem_to_consume
			_consumed += rem_to_consume
			rem_to_consume = 0.0
			i += 1
	var curr_food = economy.get_resource("food")
	var actual_deduct = minf(curr_food, request_amount)
	economy.resources["food"] = maxf(0.0, curr_food - actual_deduct)
	var is_player = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "player_tribe_settlement" or id == "test_s")
	if is_player:
		EventBus.resources_updated.emit(faction_id, economy.resources)
	return actual_deduct

func update_food_spoilage(delta: float) -> void:
	if food_batches.is_empty():
		return
	var granary_factor = get_granary_spoilage_factor()
	var spoiled_total = 0.0
	var i = food_batches.size() - 1
	while i >= 0:
		var b = food_batches[i]
		var max_fresh = float(b.get("max_freshness_sec", 3600.0))
		if max_fresh <= 0.0:
			max_fresh = 3600.0
		var rate = (delta / max_fresh) * granary_factor
		b["spoilage_progress"] = float(b.get("spoilage_progress", 0.0)) + rate
		if b["spoilage_progress"] >= 1.0:
			var spoiled_amt = float(b.get("amount", 0.0))
			spoiled_total += spoiled_amt
			food_batches.remove_at(i)
		i -= 1
	if spoiled_total > 0.0:
		economy.resources["food"] = maxf(0.0, economy.get_resource("food") - spoiled_total)
		var is_player = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "player_tribe_settlement" or id == "test_s")
		if is_player:
			EventBus.resources_updated.emit(faction_id, economy.resources)
			EventBus.notification_toast.emit("Испорченная пища", "На складе испортилось %.1f ед. запасов пищи" % spoiled_total, "warning")

	# Домашняя порча пищи в хижинах (снижается на 50% при наличии кладовой hut_pantry)
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id and b.is_residential() and b.food_stockpile > 0.0:
				var home_spoil = 0.0005 * b.get_home_spoilage_multiplier() * delta
				b.food_stockpile = maxf(0.0, b.food_stockpile - home_spoil)

func deposit_resource(res_name: String, amount: float, source_name: String = "", batch_info: Dictionary = {}) -> void:
	if amount <= 0.0 or res_name == "":
		return
	economy.add_resource(res_name, amount)
	if res_name == "food":
		var b = batch_info.duplicate() if not batch_info.is_empty() else {}
		b["amount"] = amount
		deposit_food_batch(b)
	var is_player = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "player_tribe_settlement" or id == "test_s")
	if is_player:
		EventBus.resources_updated.emit(faction_id, economy.resources)
		var name_ru = RESOURCE_NAMES_RU.get(res_name, res_name)
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
	var target_job = "quarryman"
	match category:
		"wood": target_job = "woodcutter"
		"food": target_job = "forager"
		"metal": target_job = "miner"
	for c in population.citizens:
		if c.job_id == target_job and c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
			var node = GameManager.resource_manager.nodes.get(target_coord, {}) if GameManager.resource_manager else {}
			var p = GameManager.nav_grid.find_adjacent_path(c.pos, target_coord) if (GameManager and GameManager.nav_grid) else []
			var t_pos = p[-1] if not p.is_empty() else (node.get("pos", GameManager.nav_grid.tile_to_world_center(target_coord)) if (GameManager and GameManager.nav_grid) else Vector2.ZERO)
			if GameManager.resource_manager:
				GameManager.resource_manager.reserve_node(target_coord, c.citizen_id)
			match category:
				"wood": c.task_id = "chop_tree"
				"stone": c.task_id = "mine_stone"
				"metal": c.task_id = "mine_ore"
				_: c.task_id = "gather"
			c.target_coord = target_coord
			c.target_pos = t_pos
			c.target_id = node.get("id", "")
			c.path = p
			c.path_index = 0
			c.state = CitizenNPC.State.MOVING_TO_WORK
			c.last_status_reason = "Идёт на первоочередную вырубку дерева" if category == "wood" else ("Идёт на первоочередную добычу" if category in ["stone", "metal"] else "Идёт на первоочередной сбор")
			if GameManager.task_service:
				var tid = GameManager.task_service.create_task(c.task_id, c.target_id, target_coord, t_pos)
				GameManager.task_service.assign_actor(tid, c.citizen_id)
				c.task_instance_id = tid
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
	
	event_reactor = NPCEventReactor.new(self)
	relationship_graph = NPCRelationshipGraph.new(id)
	
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

func has_active_woodcutter_camp() -> bool:
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id and b.type == "woodcutter_camp":
				return true
	if "buildings" in self and buildings.has("woodcutter_camp"):
		return true
	return false

func get_active_woodcutter_camp() -> BuildingInstance:
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id and b.type == "woodcutter_camp":
				return b
	return null

func get_citizen_home_instance(c: CitizenNPC) -> BuildingInstance:
	if not c or not GameManager or not GameManager.building_instances:
		return null
	if c.home_coord != Vector2i(-1, -1) and GameManager.building_instances.has(c.home_coord):
		return GameManager.building_instances[c.home_coord]
	if c.home_id != "":
		for b in GameManager.building_instances.values():
			if b and (b.id == c.home_id or b.instance_id == c.home_id):
				return b
	return null

func get_citizen_workplace_instance(c: CitizenNPC) -> BuildingInstance:
	if not c or not GameManager or not GameManager.building_instances:
		return null
	if c.workplace_coord != Vector2i(-1, -1) and GameManager.building_instances.has(c.workplace_coord):
		return GameManager.building_instances[c.workplace_coord]
	if c.workplace_id != "":
		for b in GameManager.building_instances.values():
			if b and (b.id == c.workplace_id or b.instance_id == c.workplace_id):
				return b
	return null

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
		var idle_list = get_idle_citizens()
		idle_list.sort_custom(func(a: CitizenNPC, b: CitizenNPC) -> bool:
			var a_pref = (a.get_preferred_job() == job_id)
			var b_pref = (b.get_preferred_job() == job_id)
			if a_pref != b_pref:
				return a_pref
			return float(a.experience.get(job_id, 0.0)) > float(b.experience.get(job_id, 0.0))
		)
		for c in idle_list:
			c.set_job_by_player(job_id)
			remaining -= 1
			if remaining <= 0:
				break
	elif delta < 0:
		var remaining = -delta
		var job_holders: Array[CitizenNPC] = []
		for c in population.citizens:
			if c.job_id == job_id:
				job_holders.append(c)
		job_holders.sort_custom(func(a: CitizenNPC, b: CitizenNPC) -> bool:
			var a_dislike = (a.get_preferred_job() != job_id)
			var b_dislike = (b.get_preferred_job() != job_id)
			if a_dislike != b_dislike:
				return a_dislike
			return float(a.experience.get(job_id, 0.0)) < float(b.experience.get(job_id, 0.0))
		)
		for c in job_holders:
			if c.workplace_id != "" and GameManager and GameManager.building_instances:
				for b_inst in GameManager.building_instances.values():
					if b_inst and "id" in b_inst and b_inst.id == c.workplace_id:
						b_inst.remove_worker(c.citizen_id)
			c.set_job_by_player("idle")
			c.workplace_id = ""
			c.workplace_coord = Vector2i(-1, -1)
			remaining -= 1
			if remaining <= 0:
				break
	sync_assigned_jobs_from_citizens()
	return true

func init_citizens_on_map() -> void:
	var starter_inst = GameManager.get_or_create_building_instance(pos, "elders_house", id)
	var center_pixel = Vector2(pos.x * 32.0 + 16.0, pos.y * 32.0 + 33.0)
	for c in population.citizens:
		c.settlement_id = id
		c.home_id = starter_inst.instance_id
		c.home_coord = pos
		c.home_pos = center_pixel
		c.pos = center_pixel + Vector2(randf_range(-6.0, 6.0), randf_range(0.0, 4.0))
		if c.job_id == "elder":
			c.workplace_id = starter_inst.instance_id
			c.workplace_coord = pos
	auto_assign_housing()
	auto_assign_workplaces()

func get_building_instances() -> Array[BuildingInstance]:
	var list: Array[BuildingInstance] = []
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id:
				list.append(b)
	return list

func get_building_instance_by_id(b_id: String) -> BuildingInstance:
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.id == b_id:
				return b
	return null

func assign_citizen_to_workplace(c: CitizenNPC, b_inst: BuildingInstance) -> bool:
	if not c or not b_inst:
		return false
	var b_def = BuildingDB.get_building(b_inst.type)
	var max_w = int(b_def.get("max_workers", 0))
	if max_w <= 0 or b_inst.workers.size() >= max_w:
		return false
	
	var job_id = BuildingDB.get_job_id_for_building(b_inst.type)
	if job_id == "" or job_id == "idle":
		return false
	
	if c.workplace_id != "" and c.workplace_id != b_inst.id:
		var prev = get_building_instance_by_id(c.workplace_id)
		if prev:
			prev.remove_worker(c.citizen_id)
			
	b_inst.add_worker(c.citizen_id)
	if b_inst.manager_id == "":
		b_inst.assign_manager(c.citizen_id, c.name)
		
	c.set_job(job_id)
	c.set_workplace(b_inst.id, b_inst.pos)
	c.decision_cooldown = 0.0
	c.last_status_reason = "Устроился на работу: %s" % b_def.get("job_name", job_id)
	
	sync_assigned_jobs_from_citizens()
	return true

func unassign_citizen_from_workplace(c: CitizenNPC) -> void:
	if not c:
		return
	if c.workplace_id != "" and GameManager and GameManager.building_instances:
		for b_inst in GameManager.building_instances.values():
			if b_inst and b_inst.id == c.workplace_id:
				b_inst.remove_worker(c.citizen_id)
				break
	c.set_job("idle")
	c.workplace_id = ""
	c.workplace_coord = Vector2i(-1, -1)
	sync_assigned_jobs_from_citizens()

func _get_building_workplace_priority(b_inst: BuildingInstance) -> float:
	var food = economy.get_resource("food") if economy else 100.0
	var wood = economy.get_resource("wood") if economy else 100.0
	var stone = economy.get_resource("stone") if economy else 100.0
	var metal = economy.get_resource("metal") if economy else 100.0
	
	match b_inst.type:
		"hunting_camp":
			return 100.0 if food < 40.0 else 75.0
		"foraging_post":
			return 95.0 if food < 30.0 else 70.0
		"fishing_spot":
			return 90.0 if food < 40.0 else 72.0
		"primitive_field":
			return 85.0
		"woodcutter_camp":
			return 80.0 if wood < 30.0 else 65.0
		"stone_quarry":
			return 78.0 if stone < 20.0 else 60.0
		"ore_pit":
			return 70.0 if metal < 10.0 else 55.0
		"craft_workshop", "carpenter_workshop", "pottery_workshop", "forge":
			return 50.0
		"watchtower":
			return 45.0
		"elders_house":
			return 40.0
		"shrine", "cemetery":
			return 35.0
		"training_grounds":
			return 30.0
		_:
			return 20.0

func auto_assign_workplaces() -> void:
	if not population or not GameManager.building_instances:
		return
	
	var active_workplaces: Array[BuildingInstance] = []
	for b_inst in GameManager.building_instances.values():
		if b_inst.settlement_id != id:
			continue
		var b_def = BuildingDB.get_building(b_inst.type)
		var max_w = int(b_def.get("max_workers", 0))
		if max_w <= 0:
			continue
		
		# Очистка погибших или снятых работников
		for w_idx in range(b_inst.workers.size() - 1, -1, -1):
			var w_id = b_inst.workers[w_idx]
			var w_cit = population.find_citizen(w_id)
			if w_cit == null or not w_cit.is_alive or w_cit.workplace_id != b_inst.id:
				b_inst.workers.remove_at(w_idx)
				if b_inst.manager_id == w_id:
					b_inst.manager_id = ""
		
		if b_inst.workers.size() < max_w:
			active_workplaces.append(b_inst)
	
	# Поддерживаем также постройки из списка settlement.buildings, если для них еще нет инстанса
	if "buildings" in self and buildings is Array:
		for b_type in buildings:
			var has_inst = false
			for inst in active_workplaces:
				if inst.type == b_type:
					has_inst = true
					break
			if not has_inst and GameManager:
				var inst_id = b_type + "_" + id + "_" + str(pos.x) + "_" + str(pos.y)
				var created_inst = BuildingInstance.new(inst_id, b_type, id, pos)
				if GameManager.tile_buildings.has(pos):
					var offset_arr = GameManager.tile_buildings[pos].get("visual_offset", [0.0, 0.0])
					created_inst.visual_offset = Vector2(offset_arr[0], offset_arr[1])
				GameManager.building_instances[inst_id] = created_inst
				var b_def = BuildingDB.get_building(b_type)
				var max_w = int(b_def.get("max_workers", 0))
				if max_w > 0 and created_inst.workers.size() < max_w and not active_workplaces.has(created_inst):
					active_workplaces.append(created_inst)

	if active_workplaces.is_empty():
		return
	
	# Сортировка: сначала пустые здания (для немедленного запуска), затем по приоритету отрасли
	active_workplaces.sort_custom(func(a: BuildingInstance, b: BuildingInstance):
		var a_def = BuildingDB.get_building(a.type)
		var b_def = BuildingDB.get_building(b.type)
		var a_max = int(a_def.get("max_workers", 1))
		var b_max = int(b_def.get("max_workers", 1))
		
		if a.workers.is_empty() and not b.workers.is_empty():
			return true
		if not a.workers.is_empty() and b.workers.is_empty():
			return false
		
		var prio_a = _get_building_workplace_priority(a)
		var prio_b = _get_building_workplace_priority(b)
		if prio_a != prio_b:
			return prio_a > prio_b
		
		var a_ratio = float(a.workers.size()) / float(a_max)
		var b_ratio = float(b.workers.size()) / float(b_max)
		return a_ratio < b_ratio
	)
	
	# 2.5. Сначала привязываем соплеменников с уже установленной профессией к зданиям, если workplace_id еще не задан
	for b_inst in active_workplaces:
		var job_id = BuildingDB.get_job_id_for_building(b_inst.type)
		if job_id == "" or job_id == "idle":
			continue
		var b_def = BuildingDB.get_building(b_inst.type)
		var max_w = int(b_def.get("max_workers", 0))
		for c in population.citizens:
			if b_inst.workers.size() >= max_w:
				break
			if c.is_alive and not c.is_ruler and c.job_id == job_id and c.workplace_id == "":
				c.set_workplace(b_inst.id, b_inst.pos)
				b_inst.add_worker(c.citizen_id)
				if b_inst.manager_id == "":
					b_inst.assign_manager(c.citizen_id, c.name)

	# 3. Сбор исключительно незанятых (idle) соплеменников, не занятых уходом за детьми или переноской
	var idle_citizens: Array[CitizenNPC] = []
	for c in population.citizens:
		if c.is_alive and not c.is_ruler and c.cohort in ["adult", "youth"] and (c.job_id in ["idle", ""] and c.workplace_id == ""):
			if c.task_id == "care_for_child" or c.state in [CitizenNPC.State.WORKING, CitizenNPC.State.CARRYING, CitizenNPC.State.RESTING]:
				continue
			idle_citizens.append(c)
	
	if idle_citizens.is_empty():
		return
	
	for b_inst in active_workplaces:
		var b_def = BuildingDB.get_building(b_inst.type)
		var max_w = int(b_def.get("max_workers", 0))
		var slots_free = max_w - b_inst.workers.size()
		if slots_free <= 0:
			continue
		
		var job_id = BuildingDB.get_job_id_for_building(b_inst.type)
		if job_id == "" or job_id == "idle":
			continue
		
		while slots_free > 0 and not idle_citizens.is_empty():
			var best_idx = 0
			var best_score = -9999.0
			var b_pos_world = GameManager.nav_grid.tile_to_world_center(b_inst.pos) if GameManager.nav_grid else Vector2(b_inst.pos.x * 32.0 + 16.0, b_inst.pos.y * 32.0 + 16.0)
			
			for idx in range(idle_citizens.size()):
				var cit = idle_citizens[idx]
				var score = 10.0
				score += float(cit.experience.get(job_id, 0.0)) * 0.5
				if job_id == "hunter" and cit.traits.has("sharp_eye"):
					score += 15.0
				elif job_id in ["quarryman", "miner", "woodcutter"] and cit.traits.has("strong"):
					score += 15.0
				elif job_id == "craftsman" and cit.traits.has("inventive"):
					score += 15.0
				elif cit.traits.has("hardworking"):
					score += 8.0
				var dist = cit.pos.distance_to(b_pos_world)
				score -= dist * 0.005
				
				if score > best_score:
					best_score = score
					best_idx = idx
			
			var chosen_c = idle_citizens.pop_at(best_idx)
			assign_citizen_to_workplace(chosen_c, b_inst)
			slots_free -= 1

func _try_auto_assign_single_citizen(c: CitizenNPC) -> bool:
	if not c or not c.is_alive or c.is_ruler or not (c.cohort in ["adult", "youth"]):
		return false
	if c.task_id == "care_for_child" or c.state in [CitizenNPC.State.WORKING, CitizenNPC.State.CARRYING, CitizenNPC.State.RESTING]:
		return false
	if not (c.job_id in ["idle", ""] and c.workplace_id == ""):
		return false
	if not GameManager or not GameManager.building_instances:
		return false
	
	var active_workplaces: Array[BuildingInstance] = []
	for b_inst in GameManager.building_instances.values():
		if b_inst.settlement_id != id:
			continue
		var b_def = BuildingDB.get_building(b_inst.type)
		var max_w = int(b_def.get("max_workers", 0))
		if max_w > 0 and b_inst.workers.size() < max_w:
			active_workplaces.append(b_inst)
			
	if active_workplaces.is_empty():
		return false
		
	active_workplaces.sort_custom(func(a: BuildingInstance, b: BuildingInstance):
		if a.workers.is_empty() and not b.workers.is_empty():
			return true
		if not a.workers.is_empty() and b.workers.is_empty():
			return false
		var prio_a = _get_building_workplace_priority(a)
		var prio_b = _get_building_workplace_priority(b)
		if prio_a != prio_b:
			return prio_a > prio_b
		var a_def = BuildingDB.get_building(a.type)
		var b_def = BuildingDB.get_building(b.type)
		var a_max = int(a_def.get("max_workers", 1))
		var b_max = int(b_def.get("max_workers", 1))
		return (float(a.workers.size()) / float(a_max)) < (float(b.workers.size()) / float(b_max))
	)
	
	for b_inst in active_workplaces:
		if assign_citizen_to_workplace(c, b_inst):
			return true
	return false

func assign_citizen_to_home(c: CitizenNPC, b_inst: BuildingInstance, as_guest: bool = false, lock_player: bool = false) -> bool:
	if not b_inst or not b_inst.is_residential():
		return false
	if c.home_id != "" and GameManager.building_instances:
		for old_inst in GameManager.building_instances.values():
			if old_inst.id == c.home_id:
				old_inst.remove_occupant(c.citizen_id)
				break
	var success = false
	if as_guest:
		success = b_inst.add_guest(c.citizen_id)
	else:
		success = b_inst.add_resident(c.citizen_id)
	if not success and b_inst.has_space_for_guest():
		success = b_inst.add_guest(c.citizen_id)
		as_guest = true
	if success:
		var home_world_pos = Vector2(b_inst.pos.x * 32.0 + 16.0, b_inst.pos.y * 32.0 + 33.0)
		c.set_home(b_inst.id, b_inst.pos, home_world_pos, as_guest, b_inst.id)
		if lock_player:
			b_inst.is_locked_by_player = true
		return true
	return false

func evict_citizen(c: CitizenNPC) -> void:
	if c.home_id != "" and GameManager.building_instances:
		for inst in GameManager.building_instances.values():
			if inst.id == c.home_id:
				inst.remove_occupant(c.citizen_id)
				break
	c.clear_home()

func auto_assign_housing() -> void:
	if not population or not GameManager.building_instances:
		return
	var residential_buildings: Array[BuildingInstance] = []
	for b_inst in GameManager.building_instances.values():
		if b_inst.settlement_id == id and b_inst.is_residential():
			residential_buildings.append(b_inst)
			
	residential_buildings.sort_custom(func(a, b):
		if a.type == "great_lodge" and b.type != "great_lodge": return true
		if a.type == "hut" and b.type == "elders_house": return true
		return false
	)
	if residential_buildings.is_empty():
		for c in population.citizens:
			c.clear_home()
			c.last_status_reason = "Бездомный (нет построек для жилья)"
		return

	var building_map: Dictionary = {}
	for b in residential_buildings:
		building_map[b.id] = b

	# 1. Переселение семей/пар/граждан из временного/переполненного elders_house в доступные hut / great_lodge
	var better_homes: Array[BuildingInstance] = []
	for b in residential_buildings:
		if b.type in ["hut", "great_lodge"] and not b.is_locked_by_player and b.has_space_for_resident():
			better_homes.append(b)

	# Сортируем: сначала наименее заселённые дома — чтобы NPC расходились по разным хижинам
	better_homes.sort_custom(func(a: BuildingInstance, b_inst: BuildingInstance):
		return a.residents.size() < b_inst.residents.size()
	)

	if not better_homes.is_empty():
		# Сначала расселяем ПАРЫ — каждой паре свой отдельный дом
		var paired_ids: Array[String] = []
		for c in population.citizens:
			if c.is_ruler or paired_ids.has(c.citizen_id):
				continue
			if c.spouse_id == "":
				continue
			var sp = population.find_citizen(c.spouse_id)
			if sp == null or paired_ids.has(sp.citizen_id):
				continue

			# Ищем дом где НЕТ других жильцов (пустой) или минимально заселённый
			var target_home: BuildingInstance = null
			for b in better_homes:
				if b.residents.is_empty() and b.has_space_for_resident():
					target_home = b
					break
			if target_home == null:
				for b in better_homes:
					if b.has_space_for_resident():
						target_home = b
						break
			if target_home == null:
				continue

			var cur_b_c = building_map.get(c.home_id, null)
			var cur_b_sp = building_map.get(sp.home_id, null)
			var c_needs_rehouse = (cur_b_c == null or cur_b_c.type == "elders_house" or cur_b_c.is_crowded() or c.is_guest) and (cur_b_c == null or not cur_b_c.is_locked_by_player)
			var sp_needs_rehouse = (cur_b_sp == null or cur_b_sp.type == "elders_house" or cur_b_sp.is_crowded() or sp.is_guest) and (cur_b_sp == null or not cur_b_sp.is_locked_by_player)

			if not c_needs_rehouse and not sp_needs_rehouse:
				continue

			assign_citizen_to_home(c, target_home, false)
			paired_ids.append(c.citizen_id)
			if target_home.has_space_for_resident():
				assign_citizen_to_home(sp, target_home, false)
				paired_ids.append(sp.citizen_id)

			# Несовершеннолетние дети пары — тоже в этот дом
			for ch in population.citizens:
				if ch.cohort == "child" and (ch.guardian_id == c.citizen_id or ch.guardian_id == sp.citizen_id or ch.is_child_of(c.citizen_id) or ch.is_child_of(sp.citizen_id)):
					if target_home.has_space_for_resident() or target_home.has_space_for_guest():
						assign_citizen_to_home(ch, target_home, not target_home.has_space_for_resident())

			# Обновляем сортировку — этот дом стал занятее
			better_homes.sort_custom(func(a: BuildingInstance, b_inst: BuildingInstance):
				return a.residents.size() < b_inst.residents.size()
			)

		# Теперь расселяем одиночек — каждый в наименее заполненный дом
		for c in population.citizens:
			if c.is_ruler or paired_ids.has(c.citizen_id):
				continue
			var cur_b = building_map.get(c.home_id, null)
			var can_rehouse = (cur_b == null or cur_b.type == "elders_house" or cur_b.is_crowded() or c.is_guest) and (cur_b == null or not cur_b.is_locked_by_player)
			if not can_rehouse:
				continue
			# Берём наименее заселённый дом
			better_homes.sort_custom(func(a: BuildingInstance, b_inst: BuildingInstance):
				return a.residents.size() < b_inst.residents.size()
			)
			for target_home in better_homes:
				if target_home.has_space_for_resident():
					assign_citizen_to_home(c, target_home, false)
					break

	# 2. Проверка и расселение остальных граждан без дома
	# Сортируем дома по заполненности — чтобы граждане расходились равномерно
	residential_buildings.sort_custom(func(a: BuildingInstance, b_inst: BuildingInstance):
		if a.type == "elders_house" and b_inst.type != "elders_house": return false
		if a.type != "elders_house" and b_inst.type == "elders_house": return true
		return a.residents.size() < b_inst.residents.size()
	)
	for c in population.citizens:
		var has_valid_home = false
		if c.home_id != "":
			var b = building_map.get(c.home_id, null)
			if b != null:
				has_valid_home = true
				if not b.residents.has(c.citizen_id) and not b.guests.has(c.citizen_id):
					if b.has_space_for_resident():
						b.add_resident(c.citizen_id)
					elif b.has_space_for_guest():
						b.add_guest(c.citizen_id)
						c.is_guest = true
		if has_valid_home:
			continue
			
		var assigned = false
		if c.family_id != "" or c.spouse_id != "" or c.guardian_id != "":
			for b in residential_buildings:
				var has_relative = false
				for r_id in b.residents:
					var r_cit = population.find_citizen(r_id)
					if r_cit and (r_cit.family_id == c.family_id or r_cit.citizen_id == c.spouse_id or r_cit.citizen_id == c.guardian_id or c.guardian_id == r_cit.citizen_id):
						has_relative = true
						break
				if has_relative and b.has_space_for_resident():
					assign_citizen_to_home(c, b, false)
					assigned = true
					break
		if assigned:
			continue
			
		for b in residential_buildings:
			if b.has_space_for_resident():
				assign_citizen_to_home(c, b, false)
				assigned = true
				break
		if assigned:
			continue
			
		for b in residential_buildings:
			if b.has_space_for_guest():
				assign_citizen_to_home(c, b, true)
				assigned = true
				break
		if assigned:
			continue
			
		c.clear_home()
		c.last_status_reason = "Бездомный (нет свободного крова)"

func get_demolition_preview(coord: Vector2i) -> Dictionary:
	var b_inst: BuildingInstance = GameManager.building_instances.get(coord, null) if GameManager else null
	var b_data: Dictionary = GameManager.tile_buildings.get(coord, {}) if GameManager else {}
	if b_inst == null and b_data.is_empty():
		return {"valid": false, "reason": "Нет здания на клетке"}
		
	var b_type = b_inst.type if b_inst else b_data.get("id", "")
	var b_info = BuildingDB.get_building(b_type)
	var b_name = b_info.get("name", b_type)
	
	var affected_names: Array[String] = []
	var res_count = 0
	var guest_count = 0
	var food_amt = 0.0
	var is_res = false
	if b_inst:
		is_res = b_inst.is_residential()
		res_count = b_inst.residents.size()
		guest_count = b_inst.guests.size()
		food_amt = b_inst.food_stockpile
		for c_id in b_inst.residents:
			var c = population.find_citizen(c_id) if population else null
			if c:
				affected_names.append(c.name)
		for c_id in b_inst.guests:
			var c = population.find_citizen(c_id) if population else null
			if c:
				affected_names.append(c.name + " (гость)")
				
	# Расчет возврата материалов (75% от стоимости)
	var salvage: Dictionary = {}
	for res_key in b_info.get("cost", {}):
		salvage[res_key] = float(b_info["cost"][res_key]) * 0.75
		
	var total_pop = population.get_total_population() if population else 0
	var cur_cap = get_housing_capacity()
	var b_cap = b_inst.max_residents if b_inst else 0
	var remaining_free_cap = maxi(0, (cur_cap - b_cap) - total_pop)
	
	return {
		"valid": true,
		"building_type": b_type,
		"building_name": b_name,
		"is_residential": is_res,
		"residents_count": res_count,
		"guests_count": guest_count,
		"affected_citizens": affected_names,
		"food_stockpile": food_amt,
		"salvage_materials": salvage,
		"free_housing_capacity": remaining_free_cap
	}

func demolish_building_with_salvage(coord: Vector2i, confirmed: bool = true) -> Dictionary:
	if not confirmed:
		return {"success": false, "reason": "Действие не подтверждено"}
	var preview = get_demolition_preview(coord)
	if not preview.get("valid", false):
		return {"success": false, "reason": preview.get("reason", "Не удалось снести")}
		
	# Зачисление спасенных материалов
	var salvage = preview.get("salvage_materials", {})
	for res in salvage:
		economy.add_resource(res, float(salvage[res]))
		
	var ok = demolish_building(coord)
	if ok:
		var is_pl = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe")
		if is_pl:
			EventBus.resources_updated.emit(faction_id, economy.resources)
		return {"success": true, "salvage": salvage, "preview": preview}
	return {"success": false, "reason": "Ошибка при сносе"}

func demolish_building(coord: Vector2i) -> bool:
	var b_inst: BuildingInstance = null
	if GameManager.building_instances.has(coord):
		b_inst = GameManager.building_instances[coord]
	var b_data: Dictionary = {}
	if GameManager.tile_buildings.has(coord):
		b_data = GameManager.tile_buildings[coord]
		
	if b_inst == null and b_data.is_empty():
		return false
		
	if b_inst and b_inst.is_residential():
		var all_occupants = b_inst.residents.duplicate()
		all_occupants.append_array(b_inst.guests)
		for c_id in all_occupants:
			var c = population.find_citizen(c_id) if population else null
			if c:
				c.clear_home()
				c.last_status_reason = "Лишился крова (дом разрушен)"
				c.shout("Наш дом разрушен!", 3.0)
				c.loyalty = maxf(0.0, c.loyalty - 10.0)
		if b_inst.food_stockpile > 0.0:
			economy.add_resource("food", b_inst.food_stockpile)
			b_inst.food_stockpile = 0.0
		b_inst.residents.clear()
		b_inst.guests.clear()
		
	if b_inst:
		GameManager.building_instances.erase(coord)
		if GameManager.nav_grid:
			GameManager.nav_grid.unregister_building(coord, Vector2i(1, 1))
	if not b_data.is_empty():
		var b_type = b_data.get("id", "")
		buildings.erase(b_type)
		GameManager.tile_buildings.erase(coord)
		if GameManager.nav_grid:
			GameManager.nav_grid.unregister_building(coord, Vector2i(1, 1))
		
	auto_assign_housing()
	return true

func cancel_building_upgrade(b_inst: BuildingInstance, is_player_mandate: bool = true) -> Dictionary:
	if not b_inst or not b_inst.has_pending_upgrade():
		return {}
	var up_data = b_inst.cancel_upgrade()
	if up_data.is_empty():
		return {}
	# Возврат доставленных стройматериалов на склад
	for res in up_data.get("materials_delivered", {}):
		var amt = float(up_data["materials_delivered"][res])
		if amt > 0.0:
			deposit_resource(res, amt, "Возврат отмененного улучшения")
	if is_player_mandate and b_inst.is_residential():
		for r_id in b_inst.residents:
			var c: CitizenNPC = null
			if population and "citizens" in population:
				for cit in population.citizens:
					if cit.id == r_id:
						c = cit
						break
			if c:
				c.loyalty = maxf(0.0, c.loyalty - 10.0)
				c.add_memory("outrage", "ruler", b_inst.id, 1.0, "Правитель запретил обустройство нашего дома", false)
				c.last_status_reason = "Возмущён: правитель запретил обустройство дома"
	return up_data

func get_citizen_by_id(c_id: String) -> CitizenNPC:
	if not population or not ("citizens" in population):
		return null
	for c in population.citizens:
		if c.id == c_id:
			return c
	return null

func check_family_private_improvements() -> bool:
	if not GameManager or not GameManager.building_instances:
		return false
	
	for b_inst in GameManager.building_instances.values():
		if not b_inst or b_inst.settlement_id != id or not b_inst.is_residential():
			continue
		if b_inst.type != "hut":
			continue
		if b_inst.has_pending_upgrade():
			continue
		if b_inst.residents.is_empty():
			continue
			
		# Проверка наличия дееспособного жильца семьи
		var has_free_worker = false
		for r_id in b_inst.residents:
			var c = population.find_citizen(r_id) if population else null
			if c and c.is_alive and c.cohort in ["youth", "adult", "elder"] and c.energy > 30.0:
				has_free_worker = true
				break
		if not has_free_worker:
			continue
			
		# Определение потребности семьи
		var candidate_up = ""
		if (b_inst.is_crowded() or b_inst.residents.size() >= b_inst.get_comfort_capacity()) and not b_inst.is_upgrade_unlocked("hut_annex"):
			candidate_up = "hut_annex"
		elif b_inst.food_stockpile >= 2.0 and not b_inst.is_upgrade_unlocked("hut_pantry"):
			candidate_up = "hut_pantry"
		elif not b_inst.domestic_goods.is_empty() and not b_inst.is_upgrade_unlocked("hut_shed"):
			candidate_up = "hut_shed"
		elif not b_inst.is_upgrade_unlocked("hut_garden"):
			candidate_up = "hut_garden"
		elif not b_inst.is_upgrade_unlocked("hut_shed"):
			candidate_up = "hut_shed"
			
		if candidate_up == "":
			continue
			
		var up_def = BuildingSystem.get_upgrade(candidate_up)
		if up_def.is_empty():
			continue
		var cost = up_def.get("cost", {})
		var can_afford = true
		for res in cost:
			if economy.get_resource(res) < float(cost[res]):
				can_afford = false
				break
		if not can_afford:
			continue
			
		# Списание материалов и старт улучшения
		for res in cost:
			economy.resources[res] = maxf(0.0, economy.get_resource(res) - float(cost[res]))
		if faction_id == GameManager.player_faction_id:
			EventBus.resources_updated.emit(faction_id, economy.resources)
			
		b_inst.start_upgrade(candidate_up, cost)
		b_inst.pending_upgrade["materials_delivered"] = cost.duplicate()
		b_inst.pending_upgrade["work_left"] = 4.0
		b_inst.pending_upgrade["total_work"] = 4.0
		
		var up_name = up_def.get("name", candidate_up)
		EventBus.notification_toast.emit(
			"Частная стройка",
			"Семья из хижины (%d:%d) самостоятельно начала обустройство: %s" % [b_inst.pos.x, b_inst.pos.y, up_name],
			"info"
		)
		return true
	return false

func request_relocation(source_coord: Vector2i, target_coord: Vector2i) -> Dictionary:
	var b_inst: BuildingInstance = GameManager.building_instances.get(source_coord, null) if GameManager else null
	var b_data: Dictionary = GameManager.tile_buildings.get(source_coord, {}) if GameManager else {}
	if b_inst == null and b_data.is_empty():
		return {"success": false, "reason": "❌ Исходное здание не найдено"}
		
	if GameManager.tile_buildings.has(target_coord) or (GameManager.planet_data.has("tiles") and GameManager.planet_data["tiles"][target_coord.y][target_coord.x].get("is_water", false)):
		return {"success": false, "reason": "❌ Нельзя перенести на занятую клетку или воду"}
		
	var b_type = b_inst.type if b_inst else b_data.get("id", "")
	var saved_offset_arr = b_data.get("visual_offset", [0.0, 0.0])
	var saved_offset = Vector2(saved_offset_arr[0], saved_offset_arr[1])
	var rel_id = "reloc_" + str(source_coord.x) + "_" + str(source_coord.y) + "_to_" + str(target_coord.x) + "_" + str(target_coord.y)
	
	var saved_residents: Array[String] = []
	if b_inst:
		saved_residents = b_inst.residents.duplicate()
		for c_id in saved_residents:
			var c = population.find_citizen(c_id) if population else null
			if c:
				c.last_status_reason = "Временное жилье (дом переносится)"
				
	# Завершаем работу исходного здания и переносим на целевую точку
	if b_inst:
		GameManager.building_instances.erase(source_coord)
	GameManager.tile_buildings.erase(source_coord)
	
	# Создаем новый экземпляр на целевой точке
	var new_inst = GameManager.get_or_create_building_instance(target_coord, b_type, id)
	new_inst.residents = saved_residents.duplicate()
	new_inst.visual_offset = saved_offset
	
	# Обновляем привязки жителей
	for c_id in saved_residents:
		var c = population.find_citizen(c_id) if population else null
		if c:
			c.home_id = new_inst.instance_id
			c.home_coord = target_coord
			c.home_pos = Vector2(target_coord.x * 32.0 + 16.0, target_coord.y * 32.0 + 33.0)
			
	GameManager.tile_buildings[target_coord] = {
		"id": b_type,
		"status": "active",
		"settlement_id": id,
		"instance_id": new_inst.instance_id,
		"visual_offset": [saved_offset.x, saved_offset.y]
	}
	
	active_relocations[rel_id] = {
		"relocation_id": rel_id,
		"source_coord": source_coord,
		"target_coord": target_coord,
		"building_type": b_type,
		"status": "completed"
	}
	
	return {"success": true, "relocation_id": rel_id}

# --- СЕМЬЯ, СОЮЗЫ, РОЖДЕНИЕ И ОПЕКА (S07) ---
func start_pregnancy(mother: CitizenNPC, father: CitizenNPC = null, gestation_sec: float = 450.0) -> bool:
	if mother == null:
		return false
	var partner_id = father.citizen_id if father else ""
	return mother.start_pregnancy(partner_id, gestation_sec)

func give_birth(mother: CitizenNPC) -> CitizenNPC:
	if mother == null:
		return null
	var father_id = mother.pregnancy.get("partner_id", "")
	var father: CitizenNPC = population.find_citizen(father_id) if population else null
	
	var birth_pos = mother.home_pos if mother.home_pos != Vector2.ZERO else mother.pos
	var fam_id = mother.family_id
	if fam_id == "" and father and father.family_id != "":
		fam_id = father.family_id
		mother.family_id = fam_id
	elif fam_id == "":
		fam_id = "fam_" + mother.citizen_id
		mother.family_id = fam_id
		if father:
			father.family_id = fam_id

	var child = population.add_newborn(id, birth_pos, mother.citizen_id, father_id, fam_id)
	if child == null:
		return null
		
	child.home_id = mother.home_id
	child.home_coord = mother.home_coord
	child.home_pos = mother.home_pos
	child.household_id = mother.household_id
	
	for sibling_id in mother.get_children():
		if sibling_id != child.citizen_id:
			var sib = population.find_citizen(sibling_id)
			if sib:
				child.add_relationship(sib.citizen_id, "sibling", 80.0)
				sib.add_relationship(child.citizen_id, "sibling", 80.0)
				
	if mother.home_id != "" and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b.id == mother.home_id:
				b.add_resident(child.citizen_id)
				break

	mother.pregnancy.clear()
	mother.shout("У нас родился ребёнок!", 4.0)
	mother.last_status_reason = "Родила ребёнка (%s)" % child.name
	EventBus.person_born.emit(id)
	EventBus.notification_toast.emit("Рождение ребёнка", "В семье %s родился %s" % [mother.name, child.name], "good")
	return child

func reassign_guardianship(child: CitizenNPC) -> CitizenNPC:
	if child == null or child.cohort != "child":
		return null
	var current_guard = population.find_citizen(child.guardian_id) if population else null
	if current_guard and current_guard.is_alive and population.citizens.has(current_guard):
		return current_guard
		
	var candidates: Array[CitizenNPC] = []
	for p_id in child.get_parents():
		var p = population.find_citizen(p_id) if population else null
		if p and p.is_alive and population.citizens.has(p):
			candidates.append(p)
			break
			
	if candidates.is_empty() and population:
		for c in population.citizens:
			if c.citizen_id != child.citizen_id and c.is_alive and c.cohort in ["adult", "elder"]:
				if (child.family_id != "" and c.family_id == child.family_id) or (child.household_id != "" and c.household_id == child.household_id):
					candidates.append(c)
					break
					
	if candidates.is_empty() and population:
		for c in population.citizens:
			if c.is_alive and c.cohort == "elder":
				candidates.append(c)
				break
				
	if candidates.is_empty() and population:
		for c in population.citizens:
			if c.is_alive and c.cohort in ["adult", "elder"]:
				candidates.append(c)
				break

	if not candidates.is_empty():
		var chosen = candidates[0]
		child.guardian_id = chosen.citizen_id
		child.add_relationship(chosen.citizen_id, "guardian", 75.0)
		chosen.add_relationship(child.citizen_id, "ward", 75.0)
		if child.home_id == "" or child.home_id != chosen.home_id:
			child.home_id = chosen.home_id
			child.home_coord = chosen.home_coord
			child.home_pos = chosen.home_pos
		return chosen
	return null

func set_child_guardian(child_id: String, guardian_id: String) -> bool:
	var child = population.find_citizen(child_id) if population else null
	var guardian = population.find_citizen(guardian_id) if population else null
	if child == null or guardian == null:
		return false
	if child.cohort != "child":
		return false
	if not guardian.cohort in ["adult", "elder"] or not guardian.is_alive:
		return false
	child.guardian_id = guardian.citizen_id
	child.add_relationship(guardian.citizen_id, "guardian", 80.0)
	guardian.add_relationship(child.citizen_id, "ward", 80.0)
	return true

func handle_citizen_death(deceased_id: String) -> void:
	if not population:
		return
	for c in population.citizens:
		if c.guardian_id == deceased_id:
			reassign_guardianship(c)

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
	# На карту выставляется ровно 1 стартовое здание — Хижина Старейшины с уникальным instance_id
	var starter_inst = GameManager.get_or_create_building_instance(pos, "elders_house", id)
	GameManager.tile_buildings[pos] = {
		"id": "elders_house",
		"instance_id": starter_inst.instance_id,
		"status": "active",
		"settlement_id": id
	}

func start_construction(building_id: String, target_coord: Vector2i = Vector2i(-1, -1), visual_offset: Vector2 = Vector2.ZERO) -> bool:
	var b_info = BuildingDB.get_building(building_id)
	if b_info.is_empty():
		return false

	if target_coord == Vector2i(-1, -1):
		target_coord = find_available_tile_for_building()
	if target_coord == Vector2i(-1, -1):
		return false

	var req_materials: Dictionary = {}
	for res in b_info.get("cost", {}):
		req_materials[res] = float(b_info["cost"][res])

	construction_queue.append({
		"id": building_id,
		"coord": target_coord,
		"days_left": float(b_info["build_days"]),
		"total_days": float(b_info["build_days"]),
		"materials_required": req_materials,
		"materials_delivered": {},
		"name": b_info["name"]
	})

	GameManager.tile_buildings[target_coord] = {
		"id": building_id,
		"status": "constructing",
		"days_left": float(b_info["build_days"]),
		"total_days": int(b_info["build_days"]),
		"materials_required": req_materials,
		"materials_delivered": {},
		"settlement_id": id,
		"visual_offset": [visual_offset.x, visual_offset.y]
	}
	
	# Расчистка природного объекта / пня на строительной клетке (P01.10)
	if GameManager and GameManager.resource_manager and GameManager.resource_manager.nodes.has(target_coord):
		GameManager.resource_manager.remove_node(target_coord)
	var tiles = GameManager.planet_data.get("tiles", []) if GameManager and GameManager.planet_data else []
	if target_coord.y >= 0 and target_coord.y < tiles.size() and target_coord.x >= 0 and target_coord.x < tiles[0].size():
		tiles[target_coord.y][target_coord.x]["nature_object"] = "none"
	
	# Немедленно пробуждаем свободных рабочих и строителей для начала работ
	if population:
		for c in population.citizens:
			if c.cohort in ["youth", "adult", "elder"] and (c.job_id in ["builder", "idle"] or c.job_id == ""):
				if c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING, CitizenNPC.State.TALKING]:
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = 0.0
					c.action_timer = 0.0
					
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
	var coord = item.get("coord", Vector2i(-1, -1))
	if coord != Vector2i(-1, -1) and GameManager.tile_buildings.has(coord):
		var b = GameManager.tile_buildings[coord]
		var deliv = b.get("materials_delivered", {})
		for res in deliv:
			economy.add_resource(res, float(deliv[res]) * 0.75)
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
	var kubriki_prod = 0.0
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
	
	# Ремесленники: физический цикл NPC (S05)
	var craftsmen = assigned_jobs.get("craftsman", 0)
	prod["kubriki"] = 0.0
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
	# 1. Синхронизация очереди строительства: прогресс обеспечивается физической работой строителей на месте
	var completed = []
	for i in range(construction_queue.size()):
		var item = construction_queue[i]
		var coord = item.get("coord", Vector2i(-1, -1))
		if coord != Vector2i(-1, -1) and GameManager.tile_buildings.has(coord):
			var b = GameManager.tile_buildings[coord]
			if item.get("days_left", 1.0) <= 0.0:
				b["days_left"] = 0.0
				b["status"] = "active"
			else:
				item["days_left"] = b.get("days_left", item["days_left"])
			
			if b.get("status", "") == "active" or item["days_left"] <= 0.0 or b.get("days_left", 1.0) <= 0.0:
				b["status"] = "active"
				completed.append(i)
				if not buildings.has(item["id"]):
					buildings.append(item["id"])
				if item["id"] == "cemetery":
					if not cemetery_plots.has(coord):
						cemetery_plots.append(coord)
					_check_pending_burials()
		elif item.get("days_left", 1.0) <= 0.0:
			completed.append(i)
			if not buildings.has(item["id"]):
				buildings.append(item["id"])
			if item["id"] == "cemetery":
				var c_coord = item.get("coord", Vector2i(-1, -1))
				if c_coord != Vector2i(-1, -1) and not cemetery_plots.has(c_coord):
					cemetery_plots.append(c_coord)
				_check_pending_burials()
			
	# Удаляем завершенные из очереди
	for i in range(completed.size() - 1, -1, -1):
		construction_queue.remove_at(completed[i])
	if not completed.is_empty():
		auto_assign_workplaces()
		
	# 2. Производство и потребление
	var prod = calculate_daily_production(season)
	var spoilage_factor = get_granary_spoilage_factor()
	var _econ_result = economy.sim_daily_tick(population.get_total_population(), prod, spoilage_factor)
	_update_social_fabric()
	
	if faction_id == GameManager.player_faction_id:
		EventBus.resources_updated.emit(faction_id, economy.resources)

	# 3. Придомовые огороды (hut_garden) и проверка частных улучшений семей (P01.4 / ТЗ 6.3)
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id and b.is_residential():
				if b.is_upgrade_unlocked("hut_garden"):
					b.food_stockpile = minf(b.food_stockpile_max, b.food_stockpile + 0.5)
	check_family_private_improvements()

	# 3b. Симуляция сельского хозяйства, полей, огородов, стоянок собирателей, мельниц и пекарен
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id:
				if b.is_agricultural():
					b.advance_crop_cycle(1.0, self)
				elif b.type == "foraging_post":
					var forager_count = b.workers.size()
					if forager_count > 0:
						add_knowledge("plant_knowledge", 0.5 * forager_count)
						if b.is_upgrade_unlocked("forage_seed_sorting"):
							add_knowledge("seed_knowledge", 0.4 * forager_count)
						if b.is_upgrade_unlocked("forage_test_plot"):
							add_knowledge("cultivation_knowledge", 0.6 * forager_count)
				elif b.type == "seed_store":
					var keeper_count = b.workers.size()
					if keeper_count > 0:
						add_knowledge("seed_knowledge", 0.8 * keeper_count)
						add_knowledge("storage_knowledge", 0.5 * keeper_count)
				elif b.type == "quern_house":
					var miller_count = b.workers.size()
					if miller_count > 0 and economy.get_resource("grain") > 0.0:
						var grind_rate = 2.0 * miller_count
						if b.is_upgrade_unlocked("quern_granite_stones"):
							grind_rate *= 1.4
						var processed = minf(economy.get_resource("grain"), grind_rate)
						economy.resources["grain"] = maxf(0.0, economy.resources["grain"] - processed)
						economy.add_resource("flour", processed * 0.9)
						add_knowledge("food_processing_knowledge", 0.5 * miller_count)
				elif b.type == "bakery":
					var baker_count = b.workers.size()
					if baker_count > 0 and economy.get_resource("flour") > 0.0:
						var bake_rate = 2.5 * baker_count
						if b.is_upgrade_unlocked("bake_domed_oven"):
							bake_rate *= 1.5
						var flour_used = minf(economy.get_resource("flour"), bake_rate)
						economy.resources["flour"] = maxf(0.0, economy.resources["flour"] - flour_used)
						economy.add_resource("bread", flour_used * 1.5)
						economy.add_resource("food", flour_used * 1.5)
						add_knowledge("food_processing_knowledge", 0.8 * baker_count)
				elif b.type == "threshing_floor":
					var thresh_count = b.workers.size()
					if thresh_count > 0:
						add_knowledge("grain_knowledge", 0.4 * thresh_count)
						# Провеивание и очистка дают немного семян
						economy.add_resource("seeds", 0.2 * thresh_count)


	# 4. Демография: отношения, семейные союзы и зарождение новой жизни (S07 / P01)
	if population and population.citizens.size() > 1:
		var eligible_adults: Array[CitizenNPC] = []
		for c in population.citizens:
			if c.is_alive and not c.is_ruler and c.cohort in ["adult", "youth"] and c.age >= 18:
				eligible_adults.append(c)
		
		for i in range(eligible_adults.size()):
			for j in range(i + 1, eligible_adults.size()):
				var c1: CitizenNPC = eligible_adults[i]
				var c2: CitizenNPC = eligible_adults[j]
				if c1.gender != c2.gender and not c1.is_related_to(c2):
					var romance_gain = _get_daily_romance_gain(c1, c2)
					if romance_gain > 0.0:
						var cur_rom = c1.add_romance(c2.citizen_id, romance_gain)
						c2.add_romance(c1.citizen_id, romance_gain)
						if cur_rom >= 50.0 and c1.can_marry(c2, marriage_law).get("allowed", false):
							c1.marry(c2, marriage_law)
							EventBus.notification_toast.emit("Новый союз", "%s и %s заключили семейный союз" % [c1.name, c2.name], "good")
							auto_assign_housing()

		# Естественное зарождение новой жизни у супругов
		for c in population.citizens:
			if c.is_alive and not c.is_ruler and c.gender == "f" and c.age >= 18 and c.age <= 42:
				if not c.is_pregnant():
					var spouses = c.get_spouses()
					for sp_id in spouses:
						var spouse = population.find_citizen(sp_id)
						if spouse and spouse.is_alive and c.health > 40.0 and economy.get_resource("food") >= 3.0:
							if randf() < 0.12:
								start_pregnancy(c, spouse)
								EventBus.notification_toast.emit("Ожидание потомства", "В семье %s и %s ожидается пополнение" % [c.name, spouse.name], "good")
								break

	# 5. Автономное расселение и распределение незанятых жителей по рабочим местам
	auto_assign_housing()
	auto_assign_workplaces()

# Суточная жизнь общества: настроение людей определяет лояльность племени,
# время лечит мелкие обиды, а клики сплачивают своих и заражают недовольством
func _update_social_fabric() -> void:
	if not population:
		return
	var living: Array[CitizenNPC] = []
	var loyalty_sum = 0.0
	for c in population.citizens:
		if c.is_alive and not c.is_ruler:
			living.append(c)
			loyalty_sum += c.loyalty
	if living.is_empty():
		return
	
	# 1. Лояльность племени (HUD) тянется к реальному настроению жителей
	var avg_loyalty = loyalty_sum / float(living.size())
	economy.loyalty = clampf(lerpf(economy.loyalty, avg_loyalty, 0.25), 0.0, 100.0)
	
	# 2. Время лечит: неприязнь без памятной обиды понемногу остывает
	for c in living:
		for other_id in c.relationships:
			var rel: Dictionary = c.relationships[other_id]
			var aff = float(rel.get("affinity", 0.0))
			if aff < 0.0 and not c.has_grudge_against(other_id):
				rel["affinity"] = minf(0.0, aff + 1.0)
	
	# 3. Клики: братство сближает своих, круг недовольных тянет за собой друзей
	if relationship_graph:
		for cl in relationship_graph.get_cliques():
			var members: Array[CitizenNPC] = []
			for m_id in cl.member_ids:
				var m = population.find_citizen(m_id)
				if m and m.is_alive:
					members.append(m)
			if cl.type == "rebels":
				for rebel in members:
					for friend_id in rebel.get_friends():
						var friend = population.find_citizen(friend_id)
						if friend and friend.is_alive and not friend.is_ruler and not cl.member_ids.has(friend_id):
							friend.loyalty = clampf(friend.loyalty - 0.5, 0.0, 100.0)
			else:
				for i in range(members.size()):
					for j in range(i + 1, members.size()):
						members[i].modify_relationship(members[j].citizen_id, 0.5, 0.2)
						members[j].modify_relationship(members[i].citizen_id, 0.5, 0.2)

# Суточный рост романтики: чувства растут только между теми, кто реально общается и
# симпатизирует друг другу. Враги, обиженные и чужие супруги не влюбляются «по таймеру».
func _get_daily_romance_gain(c1: CitizenNPC, c2: CitizenNPC) -> float:
	var r1 = c1.get_relationship(c2.citizen_id)
	var r2 = c2.get_relationship(c1.citizen_id)
	if r1.get("married", false):
		return 0.0
	if marriage_law == "monogamy" and (not c1.get_spouses().is_empty() or not c2.get_spouses().is_empty()):
		return 0.0
	if c1.has_grudge_against(c2.citizen_id) or c2.has_grudge_against(c1.citizen_id):
		return 0.0
	var aff = minf(c1.get_relationship_affinity(c2.citizen_id), c2.get_relationship_affinity(c1.citizen_id))
	if r1.get("type", "") == "ex_spouse" and aff < 60.0:
		return 0.0
	var shares_home = (c1.home_id != "" and c1.home_id == c2.home_id)
	if shares_home and aff >= 0.0:
		return 6.0
	if r1.is_empty() or r2.is_empty() or aff < 20.0:
		return 0.0
	return 3.0 if randf() < 0.6 else 0.0

func sim_monthly_tick(season: String) -> void:
	var food_ratio = 1.0
	var pop_res = population.sim_monthly_tick(food_ratio, get_housing_capacity(), season, false)
	# Естественная смерть проходит тот же путь, что и гибель: освобождаются дом и работа,
	# родные горюют, сироты получают опекуна, тело предают земле
	for dying in pop_res.get("dying", []):
		var dying_c = population.find_citizen(dying["id"])
		if dying_c and dying_c.is_alive:
			dying_c.death_cause = dying["reason"]
			_process_citizen_death(dying_c)
	if pop_res["births"] > 0:
		EventBus.person_born.emit(id)
	if pop_res["deaths"] > 0:
		EventBus.person_died.emit(id, ", ".join(pop_res["reasons"]))
	EventBus.population_changed.emit(faction_id, pop_res["total"], pop_res["births"] - pop_res["deaths"], "Естественный прирост")

# ==============================================================================
# ЖИВАЯ СИМУЛЯЦИЯ ГРАЖДАН (1 ГРАЖДАНИН = 1 NPC)
# ==============================================================================
func _is_valid_grave_tile(cand: Vector2i) -> bool:
	if not GameManager or not GameManager.planet_data or not GameManager.planet_data.has("tiles") or GameManager.planet_data["tiles"].is_empty():
		if GameManager and GameManager.tile_buildings and GameManager.tile_buildings.has(cand):
			return false
		if GameManager and GameManager.building_instances and GameManager.building_instances.has(cand):
			return false
		return true
	var tiles = GameManager.planet_data.get("tiles", [])
	if cand.y < 0 or cand.y >= tiles.size() or cand.x < 0 or cand.x >= tiles[0].size():
		return false
	var tile = tiles[cand.y][cand.x]
	if tile.get("is_water", false) or float(tile.get("elevation", 0.0)) >= 0.8:
		return false
	if GameManager.tile_buildings and GameManager.tile_buildings.has(cand):
		return false
	if GameManager.building_instances and GameManager.building_instances.has(cand):
		return false
	if GameManager.tile_decorations and GameManager.tile_decorations.has(cand):
		return false
	if GameManager.nav_grid and GameManager.nav_grid.is_ready and not GameManager.nav_grid.is_walkable(cand):
		return false
	return true

func _find_cemetery_plot(allow_allocate: bool = false) -> Vector2i:
	# 1. Проверяем все существующие здания кладбища или могильника
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id and b.type in ["cemetery", "grave"]:
				var buried_cnt = b.building_data.get("buried_citizens", []).size()
				if buried_cnt < 4: # До 4 захоронений на одной клетке кладбища
					if not cemetery_plots.has(b.pos):
						cemetery_plots.append(b.pos)
					return b.pos

	# 2. Проверяем зафиксированные участки кладбища (выделенные игроком зоны)
	for plot in cemetery_plots:
		if GameManager and GameManager.building_instances and GameManager.building_instances.has(plot):
			var b = GameManager.building_instances[plot]
			if b.type in ["cemetery", "grave"]:
				var buried_cnt = b.building_data.get("buried_citizens", []).size()
				if buried_cnt < 4:
					return plot
		else:
			return plot

	# 3. Если разрешено выделить новый участок и их строго меньше лимита MAX_CEMETERY_PLOTS
	if allow_allocate and cemetery_plots.size() < MAX_CEMETERY_PLOTS:
		if not cemetery_plots.is_empty():
			var last_p = cemetery_plots[cemetery_plots.size() - 1]
			for r in range(1, 4):
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if dx == 0 and dy == 0:
							continue
						var cand = last_p + Vector2i(dx, dy)
						if not cemetery_plots.has(cand) and _is_valid_grave_tile(cand):
							cemetery_plots.append(cand)
							return cand
		else:
			# Первый начальный участок для родового могильника на окраине (1 клетка)
			for dist in range(4, 10):
				for step_x in range(-dist, dist + 1):
					for step_y in [-dist, dist]:
						var cand1 = pos + Vector2i(step_x, step_y)
						if not cemetery_plots.has(cand1) and _is_valid_grave_tile(cand1):
							cemetery_plots.append(cand1)
							return cand1
				for step_y in range(-dist + 1, dist):
					for step_x in [-dist, dist]:
						var cand2 = pos + Vector2i(step_x, step_y)
						if not cemetery_plots.has(cand2) and _is_valid_grave_tile(cand2):
							cemetery_plots.append(cand2)
							return cand2

	return Vector2i(-1, -1)

func _get_hearth_pos() -> Vector2:
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b is BuildingInstance and b.settlement_id == id and b.type in ["campfire", "elders_house", "great_lodge"]:
				return Vector2(b.pos.x * 32.0 + 16.0, b.pos.y * 32.0 + 16.0)
	return Vector2(pos.x * 32.0 + 16.0, pos.y * 32.0 + 16.0)

func find_nearest_food_target(c: CitizenNPC) -> Dictionary:
	var home_p = c.home_pos if c.home_pos != Vector2.ZERO else (Vector2(c.home_coord.x * 32 + 16, c.home_coord.y * 32 + 33) if c.home_coord != Vector2i(-1, -1) else Vector2.ZERO)
	var has_home_food = false
	if c.home_id != "" and home_p != Vector2.ZERO and GameManager and GameManager.building_instances:
		for h_inst in GameManager.building_instances.values():
			if h_inst.id == c.home_id and h_inst.food_stockpile >= 0.25:
				has_home_food = true
				break
	if has_home_food:
		return {"pos": home_p, "reason": "Идёт домой поесть"}
	if economy.get_resource("food") >= 0.25:
		return {"pos": _get_hearth_pos(), "reason": "Идёт к очагу поесть"}
	return {}

func _process_citizen_death(c: CitizenNPC) -> void:
	c.is_alive = false
	c.health = 0.0
	c.state = CitizenNPC.State.WAITING
	c.last_status_reason = "Погиб"
	
	# 1. Сохранение прижизненной профессии и освобождение рабочего места
	var lifetime_job = c.job_id
	if lifetime_job != "" and lifetime_job != "idle":
		c.custom_data["lifetime_job"] = lifetime_job
		
	var w_inst = get_citizen_workplace_instance(c)
	if w_inst:
		w_inst.remove_worker(c.citizen_id)
	c.workplace_id = ""
	c.workplace_coord = Vector2i(-1, -1)
	c.job_id = "idle"
	
	# 2. Освобождение жилья
	var h_inst = get_citizen_home_instance(c)
	if h_inst:
		h_inst.remove_resident(c.citizen_id)
	c.home_id = ""
	c.home_coord = Vector2i(-1, -1)
	c.home_pos = Vector2.ZERO
	
	# 3. Отмена текущих задач
	if GameManager and GameManager.task_service and c.task_instance_id != "":
		GameManager.task_service.cancel_task(c.task_instance_id, "Исполнитель погиб")
		c.task_instance_id = ""
	c.task_id = ""
	
	# 4. Близкие узнают о гибели: вдовство, опека над сиротами, горе родных
	_notify_citizen_death(c)
	
	# 5. Если погиб правитель
	if c.is_ruler:
		EventBus.ruler_died.emit(c.name, c.last_status_reason)
		if GameManager and GameManager.has_method("trigger_game_over"):
			GameManager.trigger_game_over("Вождь племени %s погиб. Племя осталось без предводителя." % c.name)
		return
		
	# 6. Проводы и погребение соплеменника
	_conduct_funeral_rites(c)

# Смерть меняет жизнь живых: супруг становится вдовцом, сироты получают опекуна,
# а горюют только те, кто действительно был близок покойному
func _notify_citizen_death(dead: CitizenNPC) -> void:
	for cit in population.citizens:
		if cit == dead or not cit.is_alive:
			continue
		if cit.spouse_id == dead.citizen_id:
			cit.spouse_id = ""
		var rel: Dictionary = cit.relationships.get(dead.citizen_id, {})
		if not rel.is_empty() and (rel.get("married", false) or rel.get("type", "") == "spouse"):
			rel["married"] = false
			rel["type"] = "late_spouse"
		cit.receive_world_event("citizen_died", {"deceased_id": dead.citizen_id, "deceased_name": dead.name})
	handle_citizen_death(dead.citizen_id)

func _conduct_funeral_rites(c: CitizenNPC) -> void:
	if c.is_buried or c.custom_data.get("funeral_in_progress", false):
		return
		
	var culture = GameManager.culture_memory if GameManager else null
	var is_pyre = false
	if culture:
		if culture.has_tradition("HC-18_C") or culture.has_tradition("pyre_spirit") or culture.has_tradition("pyre_cremation"):
			is_pyre = true
			
	if is_pyre:
		# Обряд погребального костра (очищающий огонь предков)
		c.is_buried = true
		c.custom_data["funeral_in_progress"] = false
		c.custom_data["needs_burial"] = false
		for cit in population.citizens:
			if not cit.is_alive:
				continue
			var is_close = (cit.family_id != "" and cit.family_id == c.family_id) or cit.spouse_id == c.citizen_id or cit.guardian_id == c.citizen_id
			if is_close:
				cit.add_memory("sacred_flame", "pyre", c.citizen_id, 1.8, "Проводил дух (%s) через священный огонь к предкам" % c.name, false)
				cit.show_emote("fire", 4.0, 3)
			elif cit.pos.distance_to(pos) < 150.0:
				cit.show_emote("respect", 3.0, 2)
		EventBus.notification_toast.emit("🔥 Священный погребальный костёр", "Тело соплеменника %s предано священному огню предков" % c.name, "good")
		if economy:
			economy.add_resource("faith", 3.0)
	else:
		# Обряд погребения в землю: подготовка участка и назначение процессии
		var grave_coord = _find_cemetery_plot(true)
		if grave_coord == Vector2i(-1, -1):
			c.is_buried = false
			c.custom_data["needs_burial"] = true
			c.custom_data["funeral_in_progress"] = false
			c.last_status_reason = "Ожидает погребения (нет мест на кладбище)"
			for cit in population.citizens:
				if not cit.is_alive or cit == c:
					continue
				var is_close = (cit.family_id != "" and cit.family_id == c.family_id) or cit.spouse_id == c.citizen_id or cit.guardian_id == c.citizen_id
				if is_close:
					cit.add_memory("grief_unburied", "death", c.citizen_id, 2.5, "Тело соплеменника %s негде похоронить! В поселении нет кладбища" % c.name, false)
					cit.show_emote("complaint", 5.0, 4, true)
					cit.loyalty = maxf(5.0, cit.loyalty - 8.0)
					cit.shout("Негде похоронить %s! Выделите священную землю под кладбище!" % c.name, 4.0)
				elif cit.pos.distance_to(c.pos) < 140.0:
					cit.show_emote("sadness", 3.0, 2)
					cit.loyalty = maxf(10.0, cit.loyalty - 3.0)
			EventBus.notification_toast.emit("🪦 Негде похоронить усопшего!", "Соплеменника %s негде предать земле. Выделите зону кладбища в меню строительства (B)." % c.name, "warning")
			return

		c.custom_data["needs_burial"] = true
		c.custom_data["funeral_in_progress"] = true
		var cur_yr = GameManager.current_year if GameManager else 1
		var cur_season = GameManager.get_season() if GameManager else "Лето"
		var cur_day = GameManager.current_day if GameManager else 1
		var cause = c.death_cause if c.death_cause != "" else "Угас от преклонного возраста"
		
		# Формируем полные данные для родового реестра усопших
		var spouse_name = ""
		if c.spouse_id != "" and population:
			var sp = population.find_citizen(c.spouse_id)
			if sp: spouse_name = sp.name
		var children_names: Array[String] = []
		if population:
			for cit in population.citizens:
				if cit.relationships.has(c.citizen_id):
					var rel_type = cit.relationships[c.citizen_id].get("type", "")
					if rel_type == "parent": # cit является ребёнком c
						children_names.append(cit.name)
				elif cit.guardian_id == c.citizen_id:
					children_names.append(cit.name)
					
		var final_job = c.custom_data.get("lifetime_job", c.job_id)
		var final_job_title = c.get_job_title() if (c.has_method("get_job_title") and c.job_id != "idle") else final_job
		
		var lifetime_summary = "Трудился на благо рода в звании: %s. Прожил %d лет, оставил добрую память соплеменникам." % [final_job_title, c.age]
		if cause.contains("бой") or cause.contains("пал") or cause.contains("ранен"):
			lifetime_summary = "Храбро защищал родную землю и пал в бою как истинный воин. Его подвиг навечно вписан в предания рода."
		elif final_job == "hunter":
			lifetime_summary = "Опытный охотник племени, добывавший дичь в лесах и оберегавший соплеменников от хищников."
		elif final_job == "woodcutter":
			lifetime_summary = "Неутомимый лесоруб, чьими трудами строились хижины и пылал священный костер рода."
			
		var dec_entry: Dictionary = {
			"citizen_id": c.citizen_id,
			"name": c.name,
			"age": c.age,
			"gender": c.gender,
			"cohort": c.cohort,
			"job_id": final_job,
			"job_title": final_job_title,
			"family_id": c.family_id,
			"spouse_id": c.spouse_id,
			"spouse_name": spouse_name,
			"children_names": children_names,
			"death_year": cur_yr,
			"death_season": cur_season,
			"death_day": cur_day,
			"death_cause": cause,
			"birth_year": maxi(1, cur_yr - c.age),
			"lifetime_summary": lifetime_summary,
			"traits": c.traits.duplicate() if "traits" in c else [],
			"sprite_path": c.custom_data.get("sprite_path", ""),
			"burial_coord": [grave_coord.x, grave_coord.y]
		}
		
		var already_in_registry = false
		for r in deceased_registry:
			if r.get("citizen_id", "") == c.citizen_id:
				already_in_registry = true
				break
		if not already_in_registry:
			deceased_registry.append(dec_entry)
		
		# Проверяем, существует ли уже здание могильника/кладбища на этом участке
		var grave_inst: BuildingInstance = null
		if GameManager and GameManager.building_instances.has(grave_coord):
			grave_inst = GameManager.building_instances[grave_coord]
		if grave_inst == null:
			var grave_id = "cemetery_%s_%d_%d" % [id, grave_coord.x, grave_coord.y]
			grave_inst = BuildingInstance.new(grave_id, "cemetery", id, grave_coord)
			grave_inst.custom_name = "🪦 Родовой могильник"
			if GameManager and GameManager.tile_buildings.has(grave_coord):
				var offset_arr = GameManager.tile_buildings[grave_coord].get("visual_offset", [0.0, 0.0])
				grave_inst.visual_offset = Vector2(offset_arr[0], offset_arr[1])
			if GameManager:
				GameManager.building_instances[grave_coord] = grave_inst
				GameManager.tile_buildings[grave_coord] = {"id": "cemetery", "coord": grave_coord, "status": "active"}
				if GameManager.nav_grid:
					GameManager.nav_grid.register_building(grave_coord, Vector2i(1, 1), grave_id)
		
		if not grave_inst.building_data.has("buried_citizens"):
			grave_inst.building_data["buried_citizens"] = []
			
		var already_buried_in_inst = false
		for b_c in grave_inst.building_data["buried_citizens"]:
			if b_c.get("citizen_id", "") == c.citizen_id:
				already_buried_in_inst = true
				break
		if not already_buried_in_inst:
			grave_inst.building_data["buried_citizens"].append(dec_entry)
			
		grave_inst.active_modifiers["deceased_name"] = c.name
		grave_inst.active_modifiers["deceased_age"] = c.age
		grave_inst.active_modifiers["deceased_job"] = c.job_id
		grave_inst.active_modifiers["death_year"] = cur_yr
		grave_inst.active_modifiers["death_season"] = cur_season
		grave_inst.active_modifiers["death_day"] = cur_day
		grave_inst.active_modifiers["death_cause"] = cause
		grave_inst.building_data["deceased_name"] = c.name
		grave_inst.building_data["deceased_age"] = c.age
		grave_inst.building_data["deceased_job"] = c.job_id
		grave_inst.building_data["death_year"] = cur_yr
		grave_inst.building_data["death_season"] = cur_season
		grave_inst.building_data["death_day"] = cur_day
		grave_inst.building_data["death_cause"] = cause
		grave_inst.building_data["family_id"] = c.family_id
		grave_inst.add_history_entry(cur_yr, "Здесь упокоен соплеменник %s (%d лет, %s). Причина гибели: %s. Год %d (%s, день %d)." % [c.name, c.age, c.job_id, cause, cur_yr, cur_season, cur_day])
		
		if not buildings.has("cemetery"):
			buildings.append("cemetery")
		if not buildings.has("grave"):
			buildings.append("grave")
			
		c.custom_data["pending_grave_inst"] = grave_inst
		c.custom_data["pending_grave_coord"] = grave_coord
		c.is_buried = false
		
		# Назначение могильщика для физической процессии погребения
		var undertaker: CitizenNPC = null
		for cit in population.citizens:
			if cit.is_alive and cit != c and cit.cohort in ["adult", "elder"]:
				if (cit.family_id != "" and cit.family_id == c.family_id) or cit.spouse_id == c.citizen_id or cit.guardian_id == c.citizen_id:
					undertaker = cit
					break
		if undertaker == null:
			for cit in population.citizens:
				if cit.is_alive and cit != c and cit.cohort in ["adult", "youth", "elder"]:
					if cit.job_id in ["idle", "guard", "elder"] or cit.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
						undertaker = cit
						break
		if undertaker == null:
			for cit in population.citizens:
				if cit.is_alive and cit != c and cit.cohort in ["adult", "youth", "elder"]:
					undertaker = cit
					break
					
		if undertaker != null:
			undertaker.task_id = "burial_procession"
			undertaker.subphase = "fetch_body"
			undertaker.target_pos = c.pos
			undertaker.target_id = c.citizen_id
			undertaker.target_coord = grave_coord
			undertaker.custom_data["grave_inst"] = grave_inst
			undertaker.state = CitizenNPC.State.MOVING_TO_WORK
			var u_path = GameManager.nav_grid.find_adjacent_path(undertaker.pos, GameManager.nav_grid.world_to_tile(c.pos)) if GameManager and GameManager.nav_grid else []
			if u_path.is_empty() and GameManager and GameManager.nav_grid:
				u_path = GameManager.nav_grid.find_path(undertaker.pos, c.pos, true)
			if u_path.is_empty() and undertaker.pos.distance_to(c.pos) <= 32.0:
				u_path = [undertaker.pos]
			undertaker.path = u_path
			undertaker.path_index = 0
			undertaker.last_status_reason = "Идёт за телом %s для предания земле" % c.name
			DebugLogger.log_info("Burial", "Назначен могильщик %s для предания земле %s (могила %s)" % [undertaker.name, c.name, grave_coord])
		else:
			# Если в поселении абсолютно никого нет для выноса тела — сразу завершаем погребение
			if GameManager and GameManager.tile_buildings.has(grave_coord):
				GameManager.tile_buildings[grave_coord]["status"] = "active"
			c.is_buried = true
			c.custom_data["needs_burial"] = false
			c.custom_data["funeral_in_progress"] = false
			
		# Проводы близкими соплеменниками (память, скорбь, шествие)
		for cit in population.citizens:
			if not cit.is_alive or cit == c:
				continue
			var is_close = (cit.family_id != "" and cit.family_id == c.family_id) or cit.spouse_id == c.citizen_id or cit.guardian_id == c.citizen_id
			if is_close:
				cit.add_memory("grief", "death", c.citizen_id, 2.0, "Похоронил близкого соплеменника (%s) на родовом кладбище" % c.name, false)
				cit.show_emote("sadness", 5.0, 4, true)
				cit.loyalty = maxf(10.0, cit.loyalty - 6.0)
				if cit != undertaker:
					cit.task_id = "funeral_march"
					cit.target_id = c.citizen_id
					cit.target_coord = grave_coord
					cit.target_pos = c.pos
					var f_path = GameManager.nav_grid.find_adjacent_path(cit.pos, GameManager.nav_grid.world_to_tile(c.pos)) if GameManager and GameManager.nav_grid else []
					if f_path.is_empty() and GameManager and GameManager.nav_grid:
						f_path = GameManager.nav_grid.find_path(cit.pos, c.pos, true)
					cit.path = f_path
					cit.path_index = 0
					cit.state = CitizenNPC.State.MOVING_TO_WORK
					cit.last_status_reason = "Участвует в погребальной процессии (%s)" % c.name
			elif cit.pos.distance_to(c.pos) < 140.0:
				cit.add_memory("sorrow", "death", c.citizen_id, 1.0, "Проводил соплеменника %s в последний путь" % c.name, false)
				cit.show_emote("grief", 3.0, 2)
				
		EventBus.notification_toast.emit("🪦 Проводы в последний путь", "Соплеменник %s (%d лет) упокоился на родовом кладбище" % [c.name, c.age], "info")

func _check_pending_burials() -> void:
	if not population:
		return
	for c in population.citizens:
		if not c.is_alive and not c.is_buried:
			var being_processed = false
			for cit in population.citizens:
				if cit.is_alive and cit.task_id == "burial_procession" and (cit.target_id == c.citizen_id or cit.carrying_deceased_id == c.citizen_id):
					being_processed = true
					break
			if not being_processed:
				if c.custom_data.get("funeral_in_progress", false):
					# Могильщик был прерван или погиб — переназначаем могильщика без дублирования обрядов и участков
					var g_coord = c.custom_data.get("pending_grave_coord", Vector2i(-1, -1))
					var g_inst = c.custom_data.get("pending_grave_inst", null)
					var new_undertaker: CitizenNPC = null
					for cit in population.citizens:
						if cit.is_alive and cit.cohort in ["adult", "youth", "elder"]:
							if cit.task_id == "" or cit.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
								new_undertaker = cit
								break
					if new_undertaker != null and g_coord != Vector2i(-1, -1):
						new_undertaker.task_id = "burial_procession"
						new_undertaker.subphase = "fetch_body"
						new_undertaker.target_pos = c.pos
						new_undertaker.target_id = c.citizen_id
						new_undertaker.target_coord = g_coord
						new_undertaker.custom_data["grave_inst"] = g_inst
						new_undertaker.state = CitizenNPC.State.MOVING_TO_WORK
						var u_path = GameManager.nav_grid.find_adjacent_path(new_undertaker.pos, GameManager.nav_grid.world_to_tile(c.pos)) if GameManager and GameManager.nav_grid else []
						if u_path.is_empty() and GameManager and GameManager.nav_grid:
							u_path = GameManager.nav_grid.find_path(new_undertaker.pos, c.pos, true)
						new_undertaker.path = u_path
						new_undertaker.path_index = 0
						new_undertaker.last_status_reason = "Идёт за телом %s для предания земле" % c.name
					elif new_undertaker == null:
						c.is_buried = true
						c.custom_data["needs_burial"] = false
						c.custom_data["funeral_in_progress"] = false
				else:
					var available_plot = _find_cemetery_plot(true)
					if available_plot != Vector2i(-1, -1):
						DebugLogger.log_info("Burial", "Обнаружено неупокоенное тело %s, инициируем погребение" % c.name)
						_conduct_funeral_rites(c)

func update_citizens(delta: float) -> void:
	if not population or population.citizens.is_empty():
		return
		
	_check_pending_burials()
	update_food_spoilage(delta)
	var cur_hour = GameManager.current_hour

	if relationship_graph:
		relationship_graph.update(delta, self)

	# Обновление Больших домов рода (гармония, группы домохозяйств, опека и наставничество)
	if GameManager and GameManager.building_instances:
		for b_inst in GameManager.building_instances.values():
			if b_inst and b_inst.settlement_id == id and b_inst.is_great_lodge():
				b_inst.recalculate_household_groups(population)
				b_inst.update_household_harmony(delta / 600.0, self)
	
	# Предварительный сбор всех активных угроз в округе (армии и опасные хищники)
	var active_threats: Array[Dictionary] = []
	for f_id in GameManager.factions:
		if f_id != faction_id:
			var f = GameManager.factions[f_id]
			for a in f.armies:
				if a.get_total_soldiers() > 0:
					active_threats.append({
						"pos": a.world_pos,
						"name": "Вражеский отряд",
						"id": "army_" + str(a.get_instance_id()),
						"is_army": true
					})

	if GameManager and GameManager.wildlife_manager and not GameManager.wildlife_manager.animals.is_empty():
		var h_pos = _get_hearth_pos()
		for a in GameManager.wildlife_manager.animals.values():
			if a and a.is_alive() and not a.is_tamed:
				var is_attacking = (a.target_citizen != null or a.state in [WildAnimal.State.DEFENDING, WildAnimal.State.HUNTING_PREY])
				var is_predator = a.species in ["bear", "wolf", "boar", "lynx"]
				var near_hearth = (a.pos.distance_to(h_pos) <= 120.0)
				if is_attacking or (is_predator and near_hearth) or a.species == "bear":
					var a_cfg = WildAnimal.SPECIES_CONFIG.get(a.type_id, {})
					var spec_ru = "Медведь" if a.species == "bear" else ("Волк" if a.species == "wolf" else ("Кабан" if a.species == "boar" else ("Рысь" if a.species == "lynx" else "Хищник")))
					var r = 120.0 if (is_attacking or near_hearth) else 65.0
					active_threats.append({
						"pos": a.pos,
						"name": a_cfg.get("name", spec_ru),
						"id": a.id,
						"is_army": false,
						"threat_radius": r
					})

	for c in population.citizens:
		# 0. Проверка жизнеспособности (смерть при HP <= 0)
		if not c.is_alive or c.health <= 0.0:
			if c.is_alive:
				_process_citizen_death(c)
			continue
			
		# 1. Индивидуальное суточное время
		var indiv_hour = cur_hour + c.schedule_offset_hours
		if indiv_hour >= 24.0: indiv_hour -= 24.0
		elif indiv_hour < 0.0: indiv_hour += 24.0
		var is_night = (indiv_hour >= 22.0 or indiv_hour < 6.0)
		
		# 2. Обновление речевого облачка и иконки эмоций/состояний
		if c.speech_timer > 0.0:
			c.speech_timer -= delta
			if c.speech_timer <= 0.0:
				c.speech_bubble = ""
				
		c.update_emote(delta)
		var cur_season = GameManager.get_season() if GameManager else "Лето"
		c.check_autonomous_emotes(delta, cur_season)
		_apply_weather_and_clothing(c, cur_season, delta)

		# 2b. Таймер устойчивости текущего выбора (Hysteresis / Commitment) (S08)
		if c.commitment_timer > 0.0:
			c.commitment_timer = maxf(0.0, c.commitment_timer - delta)
			if c.commitment_timer <= 0.0:
				c.ongoing_task_kind = ""
				
		# 2c. Кулдаун на социальное общение и оценка автономных действий
		if c.social_cooldown > 0.0:
			c.social_cooldown = maxf(0.0, c.social_cooldown - delta)
		else:
			c._evaluate_autonomous_action(delta, self)

		# Реакция на непосредственную опасность (Хищники: медведи, волки, кабаны, рыси и вражеские отряды)
		var threat_nearby = false
		var nearest_threat_pos = Vector2.ZERO
		var threat_name = "Враги"
		var threat_id = ""
		var is_army = false
		var min_threat_dist = 999999.0

		for t in active_threats:
			var d = c.pos.distance_to(t["pos"])
			var max_r = float(t.get("threat_radius", 180.0))
			if d <= max_r and d < min_threat_dist:
				min_threat_dist = d
				threat_nearby = true
				nearest_threat_pos = t["pos"]
				threat_name = t["name"]
				threat_id = t["id"]
				is_army = t["is_army"]

		if threat_nearby:
			# Оценка характера и готовности к защите племени:
			# Против вражеской армии безоружные мирные жители бегут в укрытие, стражники и воины дают бой.
			# Против диких зверей (медведь, волк, кабан) соплеменники с храбростью/топорами защищают племя.
			var is_coward = (c.cohort == "child") \
				or (c.pregnancy.get("stage", "") != "") \
				or (c.health < 25.0)

			if is_army:
				if c.job_id not in ["guard", "warrior"]:
					is_coward = true
			else:
				if c.job_id not in ["guard", "warrior", "hunter"] and float(c.traits.get("bravery", 50.0)) < 35.0 and float(c.traits.get("temper", 20.0)) < 50.0 and not c.has_tool("axe"):
					is_coward = true

			if is_coward:
				# Трусливые соплеменники, дети и тяжелораненые бегут в укрытие
				if c.state != CitizenNPC.State.FLEEING:
					c.state = CitizenNPC.State.FLEEING
					c.task_id = "fleeing_threat"
					c.target_id = threat_id
					if GameManager and GameManager.nav_grid and c.home_pos != Vector2.ZERO:
						c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos)
					else:
						c.path.clear()
					c.path_index = 0
					c.last_status_reason = "Спасается бегством от %s в укрытие!" % threat_name
					c.shout("Спасайтесь! %s близко!" % threat_name, 3.0)
					c.show_emote("fear", 3.0, 4)
				continue
			else:
				# Храбрые защитники встают на защиту поселения и соплеменников
				c.task_id = "defend_settlement"
				c.target_id = threat_id
				var d_to_threat = c.pos.distance_to(nearest_threat_pos)
				if is_army and c.job_id in ["guard", "warrior"]:
					c.facing_dir = (nearest_threat_pos - c.pos).normalized()
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Защищает поселение от врагов!"
					continue

				if d_to_threat > 24.0:
					c.target_pos = nearest_threat_pos
					if GameManager and GameManager.nav_grid:
						c.path = GameManager.nav_grid.find_path(c.pos, nearest_threat_pos)
					else:
						c.path.clear()
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.facing_dir = (nearest_threat_pos - c.pos).normalized()
					c.last_status_reason = "Бежит на защиту поселения от %s!" % threat_name
					if c.speech_bubble == "":
						c.shout("Защитим наш очаг! К оружию!", 3.0)
					c.show_emote("fight", 3.0, 4)
					continue
				else:
					c.state = CitizenNPC.State.ATTACKING
					c.facing_dir = (nearest_threat_pos - c.pos).normalized()
					c.last_status_reason = "Сражается с %s, защищая соплеменников!" % threat_name
		elif c.task_id == "fleeing_threat":
			c.task_id = ""
			c.state = CitizenNPC.State.IDLE
			c.last_status_reason = "Опасность миновала, возвращается к делам"
			c.decision_cooldown = 1.0
				
		# 3. Ночной режим: Сон в хижине (стража не спит ночью — выходит в ночной дозор)
		if is_night and c.job_id != "guard":
			var home_inst: BuildingInstance = null
			if c.home_id != "" and GameManager and GameManager.building_instances:
				for bi in GameManager.building_instances.values():
					if bi and bi.id == c.home_id:
						home_inst = bi
						break

			if c.state == CitizenNPC.State.SLEEPING:
				if home_inst != null:
					var penalty = home_inst.get_crowding_penalty()
					var sleep_rate = 12.0 * (1.0 - penalty)
					c.energy = minf(100.0, c.energy + sleep_rate * delta)
					if c.health < c.max_health:
						var heal_rate = 8.0 * (1.0 + float(home_inst.comfort) / 50.0) * (1.0 - penalty)
						if home_inst.food_stockpile > 0.0:
							heal_rate *= 1.3
						c.health = minf(c.max_health, c.health + heal_rate * delta)
					if home_inst.is_crowded():
						c.loyalty = maxf(0.0, c.loyalty - 0.05 * penalty * delta)
						c.last_status_reason = "Спит в хижине в тесноте (штраф отдыха -%d%%)" % int(penalty * 100)
					else:
						c.last_status_reason = "Спит в гостях" if c.is_guest else "Спит в хижине"
				else:
					var sleep_rate = 6.0
					c.energy = minf(100.0, c.energy + sleep_rate * delta)
					if c.health < c.max_health:
						c.health = minf(c.max_health, c.health + 4.0 * delta)
					c.loyalty = maxf(0.0, c.loyalty - 0.2 * delta)
					c.last_status_reason = "Бездомный, спит на земле (плохой отдых)"
				continue
			elif c.state == CitizenNPC.State.GOING_HOME:
				var reached = c.update_movement(delta)
				if reached or c.pos.distance_to(c.home_pos) < 6.0:
					c.state = CitizenNPC.State.SLEEPING
					if home_inst != null:
						if home_inst.is_crowded():
							c.last_status_reason = "Спит в хижине в тесноте (штраф отдыха -%d%%)" % int(home_inst.get_crowding_penalty() * 100)
						else:
							c.last_status_reason = "Спит в гостях" if c.is_guest else "Спит в хижине"
					else:
						c.last_status_reason = "Бездомный, спит на земле (плохой отдых)"
			else:
				# Если уже дома — сразу ложится спать в хижине
				if c.home_id != "" and c.home_pos != Vector2.ZERO and c.pos.distance_to(c.home_pos) <= 6.0:
					c.state = CitizenNPC.State.SLEEPING
					if home_inst != null and home_inst.is_crowded():
						c.last_status_reason = "Спит в хижине в тесноте (штраф отдыха -%d%%)" % int(home_inst.get_crowding_penalty() * 100)
					else:
						c.last_status_reason = "Спит в гостях" if c.is_guest else "Спит в хижине"
					continue
					
				# Проверка достижимости кровати
				if c.home_id != "" and c.home_pos != Vector2.ZERO:
					var h_path = GameManager.nav_grid.find_path(c.pos, c.home_pos) if GameManager.nav_grid else []
					if h_path.is_empty() and c.pos.distance_to(c.home_pos) > 20.0:
						c.state = CitizenNPC.State.SLEEPING
						c.loyalty = maxf(0.0, c.loyalty - 0.2 * delta)
						c.last_status_reason = "Нет пути к кровати! Ночует на улице"
						continue
					c.path = h_path
					c.path_index = 0
					c.state = CitizenNPC.State.GOING_HOME
					if c.cargo_amount > 0.0:
						c.last_status_reason = "Возвращается домой ко сну (с грузом в руках)"
					else:
						c.last_status_reason = "Возвращается домой ко сну"
				else:
					c.state = CitizenNPC.State.SLEEPING
					c.loyalty = maxf(0.0, c.loyalty - 0.2 * delta)
					c.last_status_reason = "Бездомный, засыпает на улице"
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
		if c.state == CitizenNPC.State.SLEEPING or (c.state == CitizenNPC.State.GOING_HOME and c.cargo_amount > 0.0):
			if c.cargo_amount > 0.0 and c.cargo_type != "":
				c.state = CitizenNPC.State.CARRYING
				var dest_p = _get_storage_pos(c)
				c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
				c.path_index = 0
				c.last_status_reason = "Наступило утро, несёт сохранённый груз на склад"
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.set_delivering(c.task_instance_id)
				continue
			else:
				c.state = CitizenNPC.State.IDLE
				if c.energy < 50.0:
					c.last_status_reason = "Не выспался (усталость)"
				else:
					c.last_status_reason = "Пробуждение"
				c.decision_cooldown = randf_range(0.5, 2.0)
			
		# Снижение бодрости и сытости (реалистичный суточный баланс: 2 приема пищи в день)
		c.energy = maxf(0.0, c.energy - 0.25 * delta)
		c.hunger = maxf(0.0, c.hunger - 0.10 * delta)
		
		# Беременность и физическое развитие плода (S07)
		if c.is_pregnant():
			var p_res = c.advance_pregnancy(delta)
			if p_res == "birth":
				give_birth(c)
				continue
			elif p_res == "late":
				c.last_status_reason = "Беременность (поздний срок)"
		
		# Питание при голоде (физически достоверное: ест дома или у очага, иначе идёт к еде)
		if c.hunger < 45.0:
			var ate = false
			var home_p = c.home_pos if c.home_pos != Vector2.ZERO else (Vector2(c.home_coord.x * 32 + 16, c.home_coord.y * 32 + 33) if c.home_coord != Vector2i(-1, -1) else Vector2.ZERO)
			var is_at_home = (c.home_id != "" and home_p != Vector2.ZERO and c.pos.distance_to(home_p) <= 22.0)
			var hearth_p = _get_hearth_pos()
			var is_at_hearth = (c.pos.distance_to(hearth_p) <= 22.0)
			
			if is_at_home and c.home_id != "" and GameManager and GameManager.building_instances:
				for h_inst in GameManager.building_instances.values():
					if h_inst.id == c.home_id and h_inst.food_stockpile >= 0.25:
						h_inst.consume_food(0.25)
						c.hunger = 100.0
						c.last_status_reason = "Поел из домашнего запаса"
						c.show_emote("eat", 3.0, 3)
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = randf_range(1.0, 2.0)
						ate = true
						break
			if not ate and is_at_hearth and economy.get_resource("food") >= 0.25:
				consume_food(0.25)
				c.hunger = 100.0
				c.last_status_reason = "Поел у очага"
				c.show_emote("eat", 3.0, 3)
				c.task_id = ""
				c.state = CitizenNPC.State.IDLE
				c.decision_cooldown = randf_range(1.0, 2.0)
				ate = true
			if not ate:
				if c.task_id == "go_eat":
					# Житель физически следует к еде, статус не перезаписываем
					pass
				else:
					if c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING, CitizenNPC.State.RESTING] or c.hunger < 30.0:
						var food_target = find_nearest_food_target(c)
						if not food_target.is_empty():
							# Критический голод прерывает активную работу — сохраняем задачу для восстановления после еды
							if c.state in [CitizenNPC.State.WORKING, CitizenNPC.State.GATHERING] and c._can_interrupt_current_task():
								c._save_task_snapshot()
							c.task_id = "go_eat"
							c.target_pos = food_target["pos"]
							c.path = GameManager.nav_grid.find_path(c.pos, food_target["pos"]) if GameManager and GameManager.nav_grid else []
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.last_status_reason = food_target["reason"]
						else:
							c.last_status_reason = "Голодает! В запасах нет еды"
							c.show_emote("hunger", 3.0, 3)
					else:
						c.last_status_reason = "Голоден"
						
				if c.hunger <= 0.0:
					c.health = maxf(0.0, c.health - 0.4 * delta)
					if c.health <= 0.0:
						c.death_cause = "От истощения и голода"
						_process_citizen_death(c)
						continue
				elif c.hunger >= 50.0 and c.health < c.max_health and c.state != CitizenNPC.State.ATTACKING:
					# Пассивная естественная регенерация сытого поселенца
					c.health = minf(c.max_health, c.health + 0.8 * delta)
			
		# Общение двух свободных жителей
		if c.state == CitizenNPC.State.TALKING:
			c.action_timer -= delta
			if c.talk_partner_id != "":
				var partner = get_citizen_by_id(c.talk_partner_id)
				if partner:
					c.facing_dir = (partner.pos - c.pos).normalized()
			if c.action_timer <= 0.0:
				c.state = CitizenNPC.State.IDLE
				c.talk_partner_id = ""
				c.last_status_reason = "Закончил разговор"
				c.decision_cooldown = randf_range(1.0, 2.0)
				c.social_cooldown = randf_range(20.0, 40.0)
			continue
			
		# Разумный отдых (RESTING) у костра, дома, на кладбище или вечерний танец (S08)
		if c.state == CitizenNPC.State.RESTING:
			c.work_timer -= delta
			c.energy = minf(100.0, c.energy + 12.0 * delta)
			
			# Восстановление здоровья при отдыхе дома / у очага
			if c.health < c.max_health:
				var my_home_inst: BuildingInstance = get_citizen_home_instance(c)
				var comfort_val: float = float(my_home_inst.comfort) if my_home_inst else 0.0
				var heal_spd: float = 8.0 * (1.0 + comfort_val / 50.0)
				if my_home_inst and my_home_inst.food_stockpile > 0.0:
					heal_spd *= 1.3
				if c.hunger > 50.0:
					heal_spd *= 1.2
				c.health = minf(c.max_health, c.health + heal_spd * delta)

			if c.task_id == "recover_at_home":
				if c.health < 80.0:
					c.last_status_reason = "Отлёживается дома после ран и битвы (%d/%d HP)" % [int(c.health), int(c.max_health)]
					continue
				else:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.ongoing_task_kind = ""
					c.last_status_reason = "Оправился от ран и готов к труду"
					c.show_emote("joy", 3.0, 2)
					c.add_memory("recovered_from_wounds", "health", "", 1.0, "Оправился от ран в тепле родного очага", false)
					c.decision_cooldown = randf_range(1.0, 2.0)
					continue
			elif c.task_id == "visit_grave":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 2.0)
					if economy:
						economy.add_resource("faith", 2.0)
						economy.loyalty = minf(100.0, economy.loyalty + 2.0)
					c.add_memory("ancestor_blessing", "grave", "", 1.5, "Почтил память предка у надгробия", true)
					c.show_emote("praise", 3.5, 3)
					c.last_status_reason = "Почтил память предка у надгробия (+2 Веры)"
					c.decision_cooldown = randf_range(25.0, 45.0)
				continue
			elif c.task_id == "offer_gifts":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					if economy and economy.get_resource("food") >= 1.0:
						economy.add_resource("food", -1.0)
						economy.add_resource("faith", 4.0)
						economy.loyalty = minf(100.0, economy.loyalty + 4.0)
						c.loyalty = minf(100.0, c.loyalty + 4.0)
						c.add_memory("offered_gifts", "grave", "", 1.8, "Возложил дары на могилу предка", true)
						c.show_emote("flower", 4.0, 3)
						c.last_status_reason = "Возложил дары на родовом могильнике (+4 Веры)"
						EventBus.notification_toast.emit("🌸 Дары предкам", "%s возложил дары на родовом могильнике (+4 Веры, благословение)" % c.name, "good")
					c.decision_cooldown = randf_range(30.0, 60.0)
				continue
			elif c.task_id == "desecrate_grave":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					var dec_name = c.custom_data.get("target_deceased_name", "недруга")
					var dec_id = c.custom_data.get("target_deceased_id", "")
					for rec in deceased_registry:
						if (dec_id != "" and rec.get("citizen_id", "") == dec_id) or rec.get("name", "") == dec_name:
							rec["is_defiled"] = true
							rec["defiled_by"] = c.name
							break
					if economy:
						economy.add_resource("faith", -3.0)
						economy.loyalty = maxf(0.0, economy.loyalty - 2.0)
					c.loyalty = maxf(0.0, c.loyalty - 5.0)
					c.last_status_reason = "Осквернил могилу %s!" % dec_name
					c.show_emote("anger", 4.0, 5, true)
					c.shout("Ты и в земле не найдешь покоя, %s!" % dec_name, 3.5)
					EventBus.notification_toast.emit("⚡ Осквернение могилы!", "%s осквернил могилу %s! Соплеменники в гневе!" % [c.name, dec_name], "warning")
					
					# Проверка свидетелей: родственники усопшего или стражники
					for other in population.citizens:
						if other.is_alive and other.citizen_id != c.citizen_id and other.pos.distance_to(c.pos) <= 160.0:
							var is_kin = false
							if dec_id != "":
								var rel = other.get_relationship(dec_id)
								if rel.get("type", "") in ["parent", "child", "spouse", "sibling"] or other.family_id == c.custom_data.get("target_family_id", "xyz"):
									is_kin = true
							if is_kin or other.job_id in ["guard", "warrior"]:
								other.shout("Как ты смеешь осквернять святыню нашего рода?!" if is_kin else "Осквернитель! Прекратить святотатство!", 3.5)
								other.show_emote("anger", 4.0, 5, true)
								c.task_id = "brawling"
								c.action_timer = 5.0
								other.task_id = "brawling" if is_kin else "stop_brawl"
								other.action_timer = 5.0
								c.loyalty = maxf(0.0, c.loyalty - 10.0)
								other.loyalty = maxf(0.0, other.loyalty - 5.0)
								break
					c.decision_cooldown = randf_range(40.0, 80.0)
				continue
			elif c.task_id == "cleanse_grave":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					for rec in deceased_registry:
						rec["is_defiled"] = false
						rec["defiled_by"] = ""
					if economy:
						economy.add_resource("faith", 3.0)
						economy.loyalty = minf(100.0, economy.loyalty + 3.0)
					c.loyalty = minf(100.0, c.loyalty + 3.0)
					c.add_memory("cleansed_shrine", "grave", "", 1.8, "Очистил и освятил осквернённую могилу предка", true)
					c.show_emote("praise", 4.0, 3)
					c.last_status_reason = "Очистил и освятил осквернённую могилу (+3 Веры)"
					EventBus.notification_toast.emit("🕊 Очищение святыни", "%s очистил и освятил осквернённую могилу (+3 Веры)" % c.name, "good")
					c.decision_cooldown = randf_range(30.0, 60.0)
				continue
			elif c.task_id == "evening_fishing":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.morale = minf(100.0, c.morale + 4.0)
					c.add_work_xp("gathering", 0.5)
					if randf() < 0.50 and economy:
						# Улов несут в амбар ногами, а не зачисляют с берега
						c.cargo_type = "food"
						c.cargo_amount = 2.0
						c.cargo_batch = {
							"food_type": "fish",
							"amount": 2.0,
							"created_sim_time": GameManager.sim_time_total,
							"max_freshness_sec": 3000.0,
							"spoilage_progress": 0.0
						}
						c.state = CitizenNPC.State.CARRYING
						c.path = GameManager.nav_grid.find_path(c.pos, _get_storage_pos(c)) if GameManager.nav_grid else []
						c.path_index = 0
						c.show_emote("joy", 3.0, 2)
						c.last_status_reason = "Удачно порыбачил вечерком, несёт 2 рыбы в амбар"
					else:
						c.show_emote("calm", 3.0, 1)
						c.last_status_reason = "Спокойно отдохнул на вечерней рыбалке"
					c.decision_cooldown = randf_range(20.0, 45.0)
				continue
			elif c.task_id == "evening_training":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.add_work_xp("combat_training", 0.6)
					c.show_emote("strength", 3.0, 2)
					c.last_status_reason = "Закончил вечернюю воинскую разминку"
					c.decision_cooldown = randf_range(20.0, 45.0)
				continue
			elif c.task_id == "evening_walk":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.morale = minf(100.0, c.morale + 3.0)
					c.show_emote("calm", 3.0, 1)
					c.last_status_reason = "Прогулялся по поселению на закате"
					c.decision_cooldown = randf_range(20.0, 40.0)
				continue
			elif c.task_id == "evening_porch_rest":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.energy = minf(100.0, c.energy + 8.0)
					c.last_status_reason = "Отдохнул на крыльце хижины"
					c.decision_cooldown = randf_range(20.0, 40.0)
				continue
			elif c.task_id == "funeral_vigil":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.last_status_reason = "Простился с соплеменником у могилы"
					c.add_memory("honored_burial", "grave", c.target_id, 2.0, "Проводил соплеменника в последний путь с почестями", true)
					c.loyalty = minf(100.0, c.loyalty + 4.0)
					c.decision_cooldown = randf_range(5.0, 15.0)
				continue
			elif c.task_id == "campfire_dance":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 2.0)
					c.last_status_reason = "Весело провёл вечер у костра"
					c.decision_cooldown = randf_range(15.0, 30.0)
				continue
			elif c.task_id == "visiting_friend":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 2.5)
					c.last_status_reason = "Приятно погостил у соплеменника"
					c.decision_cooldown = randf_range(20.0, 45.0)
				continue
			elif c.task_id == "dating_walk":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 3.0)
					c.last_status_reason = "Вернулся с романтической прогулки"
					c.decision_cooldown = randf_range(25.0, 50.0)
				continue
			elif c.task_id == "reconcile_quarrel":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 3.0)
					c.last_status_reason = "В добром согласии с соплеменниками"
					c.decision_cooldown = randf_range(25.0, 50.0)
				continue
			elif c.task_id == "pet_animal":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 1.5)
					c.last_status_reason = "Порадовался общению с питомцем"
					c.decision_cooldown = randf_range(15.0, 35.0)
				continue
			elif c.task_id == "campfire_story":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 2.0)
					c.last_status_reason = "Послушал увлекательные предания у костра"
					c.decision_cooldown = randf_range(15.0, 35.0)
				continue
			elif c.task_id == "play_dice":
				if c.work_timer <= 0.0:
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.loyalty = minf(100.0, c.loyalty + 2.0)
					c.last_status_reason = "Сыграл партию в кости у очага"
					c.decision_cooldown = randf_range(15.0, 35.0)
				continue
			if c.work_timer <= 0.0 or c.energy >= 85.0:
				c.state = CitizenNPC.State.IDLE
				c.ongoing_task_kind = ""
				c.last_status_reason = "Отдохнул и полон сил"
				c.decision_cooldown = randf_range(0.5, 1.5)
			continue
			
		# Потасовка / драка между соплеменниками (BRAWLING)
		if c.task_id == "brawling":
			c.action_timer -= delta
			if c.action_timer <= 0.0:
				c.task_id = ""
				c.state = CitizenNPC.State.IDLE
				c.last_status_reason = "Отходит от потасовки (ушибы и ссадины)"
				c.decision_cooldown = randf_range(4.0, 8.0)
			continue
			
		# Вмешательство стражника / воина для прекращения потасовки
		if c.task_id == "stop_brawl":
			var broke_up = false
			for brawler in population.citizens:
				if brawler.is_alive and brawler.task_id == "brawling" and brawler.pos.distance_to(c.pos) <= 60.0:
					brawler.task_id = ""
					brawler.state = CitizenNPC.State.IDLE
					brawler.last_status_reason = "Успокоен стражником после драки"
					brawler.show_emote("fear", 3.0, 3)
					broke_up = true
			if broke_up or c.target_pos == Vector2.ZERO or c.pos.distance_to(c.target_pos) <= 45.0:
				c.task_id = ""
				c.state = CitizenNPC.State.IDLE
				c.last_status_reason = "Восстановил порядок в поселении"
				EventBus.notification_toast.emit("🛡 Порядок восстановлен", "%s разнял уличную потасовку" % c.name, "info")
				continue
			
		# Автономные действия на кладбище и вечерний разнообразный досуг (S08)
		if c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING] and c.decision_cooldown <= 0.0 and c.task_id == "":
			var is_evening = (indiv_hour >= 17.5 and indiv_hour < 22.0)
			
			# 1. Проверка необходимости очистить осквернённую могилу
			var has_defiled_grave = false
			for rec in deceased_registry:
				if rec.get("is_defiled", false) or rec.get("defiled_by", "") != "":
					has_defiled_grave = true
					break
			if has_defiled_grave and not (c.job_id == "builder" and not construction_queue.is_empty()) and (float(c.traits.get("tradition", 50.0)) > 40.0 or c.job_id in ["priest", "sage", "elder"] or randf() < 0.25):
				var g_target = _find_cemetery_target(c)
				if not g_target.is_empty():
					c.task_id = "cleanse_grave"
					c.target_pos = g_target["pos"]
					c.target_coord = g_target["coord"]
					c.custom_data["target_deceased_id"] = g_target.get("deceased_id", "")
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.path = GameManager.nav_grid.find_path(c.pos, g_target["pos"]) if GameManager and GameManager.nav_grid else []
					c.path_index = 0
					c.last_status_reason = "Идёт очистить и освятить осквернённую могилу"
					continue
					
			# 2. Осквернение могилы недруга NPC с высоким гневом / враждой к усопшему
			if not deceased_registry.is_empty() and not (c.job_id == "builder" and not construction_queue.is_empty()) and (float(c.traits.get("temper", 20.0)) > 45.0 or c.traits.get("unpredictable", false)) and randf() < 0.12:
				for d_rec in deceased_registry:
					var dec_id = d_rec.get("citizen_id", "")
					var aff = c.get_relationship_affinity(dec_id)
					var has_feud = c.has_memory_of(dec_id, "feud") or c.has_memory_of(dec_id, "rival") or c.has_memory_of(dec_id, "betrayal")
					if aff < -20.0 or has_feud or (c.traits.get("unpredictable", false) and randf() < 0.08):
						var g_target = _find_cemetery_target(c)
						if not g_target.is_empty():
							c.task_id = "desecrate_grave"
							c.target_pos = g_target["pos"]
							c.target_coord = g_target["coord"]
							c.custom_data["target_deceased_id"] = dec_id
							c.custom_data["target_deceased_name"] = d_rec.get("name", "недруга")
							c.custom_data["target_family_id"] = d_rec.get("family_id", "")
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.path = GameManager.nav_grid.find_path(c.pos, g_target["pos"]) if GameManager and GameManager.nav_grid else []
							c.path_index = 0
							c.last_status_reason = "Идёт с дурными намерениями к могиле %s!" % d_rec.get("name", "")
							break
				if c.task_id == "desecrate_grave":
					continue

			# 3. Почтить память / возложить дары на родовом кладбище
			if not (c.job_id == "builder" and not construction_queue.is_empty()) and (c.job_id in ["idle", "priest", "sage"] or is_evening or c.has_memory("grief") or c.has_memory("sorrow")) and (c.has_memory("grief") or c.has_memory("sorrow") or c.has_memory("honored_burial") or float(c.traits.get("tradition", 50.0)) > 45.0 or c.job_id in ["priest", "sage"]) and randf() < (0.25 if is_evening else 0.10):
				var g_target = _find_cemetery_target(c)
				if not g_target.is_empty():
					var can_offer = (economy and economy.get_resource("food") >= 1.0 and randf() < 0.40)
					c.task_id = "offer_gifts" if can_offer else "visit_grave"
					c.target_pos = g_target["pos"]
					c.target_coord = g_target["coord"]
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.path = GameManager.nav_grid.find_path(c.pos, g_target["pos"]) if GameManager and GameManager.nav_grid else []
					c.path_index = 0
					var dec_name = g_target.get("deceased_name", "предков")
					c.last_status_reason = ("Несёт дары на могилу %s" if can_offer else "Идёт на кладбище помянуть %s") % dec_name
					continue

			# 4. Вечернее разнообразие досуга и живая социальная жизнь (S08 / Living NPC Sim)
			if is_evening and c.energy > 25.0 and not (c.job_id == "builder" and not construction_queue.is_empty()):
				# 4a. Примирение со старыми обидчиками при остывшем гневе / высокой эмпатии
				if (c.has_memory("grudge") or c.has_memory("offense")) and randf() < 0.30:
					if _try_reconcile_quarrel(c):
						continue

				# 4b. Влюблённые / супруги идут на свидание и романтическую прогулку
				if (c.spouse_id != "" or c.cohort in ["youth", "adult"]) and randf() < 0.28:
					if _try_start_dating_walk(c):
						continue

				# 4c. Походы в гости к друзьям, родителям, старейшинам и соседям
				if randf() < 0.32:
					if _try_visit_friend(c):
						continue

				# 4d. Ласка и игра с прирученными животными (волчонок, питомцы)
				if randf() < 0.22:
					if _try_pet_animal(c):
						continue

				var roll = randf()
				# 4e. Вечерняя рыбалка у берега реки/водоёма (20%)
				if roll < 0.20 or c.job_id == "fisherman":
					var shore_pos = _find_shore_pos(c)
					if shore_pos != Vector2.ZERO:
						c.task_id = "evening_fishing"
						c.target_pos = shore_pos
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.path = GameManager.nav_grid.find_path(c.pos, shore_pos) if GameManager and GameManager.nav_grid else []
						c.path_index = 0
						c.last_status_reason = "Идёт к воде на вечернюю рыбалку"
						continue
				# 4f. Вечерняя воинская разминка и тренировка (20%)
				elif roll < 0.40 and (c.job_id in ["guard", "warrior", "hunter"] or c.cohort == "youth" or float(c.traits.get("bravery", 50.0)) > 55.0):
					var train_pos = _get_hearth_pos() + Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
					c.task_id = "evening_training"
					c.target_pos = train_pos
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.path = GameManager.nav_grid.find_path(c.pos, train_pos) if GameManager and GameManager.nav_grid else []
					c.path_index = 0
					c.last_status_reason = "Идёт на площадку для вечерней тренировки"
					continue
				# 4g. Прогулка по тропинкам и окрестностям (15%)
				elif roll < 0.55:
					var walk_pos = _find_scenic_walk_pos(c)
					if walk_pos != Vector2.ZERO:
						c.task_id = "evening_walk"
						c.target_pos = walk_pos
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.path = GameManager.nav_grid.find_path(c.pos, walk_pos) if GameManager and GameManager.nav_grid else []
						c.path_index = 0
						c.last_status_reason = "Гуляет по поселению на закате"
						continue
				# 4h. Отдых на крыльце хижины (15%)
				elif roll < 0.70 and c.home_pos != Vector2.ZERO:
					var porch_pos = c.home_pos + Vector2(randf_range(-10.0, 10.0), randf_range(1.0, 6.0))
					c.task_id = "evening_porch_rest"
					c.target_pos = porch_pos
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.path = GameManager.nav_grid.find_path(c.pos, porch_pos) if GameManager and GameManager.nav_grid else []
					c.path_index = 0
					c.last_status_reason = "Идёт отдохнуть на крыльце дома"
					continue
				# 4i. Личное благоустройство и украшение поселения / мусор
				elif roll < 0.82:
					_try_personal_decoration_action(c)
					if c.task_id == "place_decoration" or c.task_id == "cleanup_trash":
						continue
				# 4j. Истории, игры в кости и танцы у костра
				else:
					if _try_hearth_game_or_story(c):
						continue
					var h_pos = _get_hearth_pos()
					if c.pos.distance_to(h_pos) <= 120.0:
						c.task_id = "campfire_dance"
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(6.0, 10.0)
						c.show_emote("dance", 4.0, 3)
						c.last_status_reason = "Танцует и поёт у вечернего костра"
						continue
			
		# Движение к цели
		if c.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.GOING_HOME]:
			# Особая обработка охотника на ходу (преследование и дистанция атаки)
			# Профессии с особым движением (погоня охотника за зверем)
			var moving_behavior = ProfessionRegistry.get_behavior(c.job_id)
			if moving_behavior and moving_behavior.on_moving(self, c, delta):
				continue
			var target_center = GameManager.nav_grid.tile_to_world_center(c.target_coord) if GameManager and GameManager.nav_grid and c.target_coord != Vector2i(-1, -1) else c.target_pos
			var is_near_work = c.pos.distance_to(c.target_pos) <= 75.0 or c.pos.distance_to(target_center) <= 75.0
			if c.state == CitizenNPC.State.MOVING_TO_WORK and c.path.is_empty() and c.target_pos != Vector2.ZERO and not is_near_work:
				c.state = CitizenNPC.State.WAITING
				c.last_status_reason = "Нет пути к цели"
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.fail_task(c.task_instance_id, "Нет пути", true)
				continue

			if c.carrying_deceased_id != "":
				var d_body = get_citizen_by_id(c.carrying_deceased_id)
				if c.task_id != "burial_procession" or d_body == null or d_body.is_buried:
					c.carrying_deceased_id = ""
					if c.subphase == "carry_to_grave":
						c.subphase = ""
				elif d_body:
					d_body.pos = c.pos + Vector2(0, -4)

			var arrived = c.update_movement(delta)
			if not arrived and c.speech_timer <= 0.0 and c.social_cooldown <= 0.0:
				c.social_cooldown = randf_range(15.0, 30.0)
				for other_passer in population.citizens:
					if other_passer != c and other_passer.is_alive and other_passer.pos.distance_to(c.pos) <= 24.0:
						var aff = c.get_relationship_affinity(other_passer.citizen_id)
						if aff >= 15.0 or c.is_related_to(other_passer) or c.spouse_id == other_passer.citizen_id:
							c.shout(_pick_phrase(c, [
								"Привет, %s!" % other_passer.name,
								"Доброго дня, %s!" % other_passer.name,
								"Удачного дня, %s!" % other_passer.name,
								"Рад видеть тебя, %s!" % other_passer.name
							]), 2.2)
							c.show_emote("sympathy" if randf() < 0.5 else "dialog", 2.2, 1)
							break
			if arrived:
				if c.state == CitizenNPC.State.MOVING_TO_WORK:
					if c.task_id == "go_eat":
						var my_h: BuildingInstance = null
						if c.home_id != "" and GameManager and GameManager.building_instances:
							for h in GameManager.building_instances.values():
								if h.id == c.home_id:
									my_h = h
									break
						if my_h and my_h.food_stockpile >= 0.25 and c.pos.distance_to(c.home_pos) <= 22.0:
							my_h.consume_food(0.25)
							c.hunger = 100.0
							c.show_emote("eat", 3.0, 3)
							c.last_status_reason = "Поел из домашнего запаса"
							if not c._restore_task_snapshot():
								c.state = CitizenNPC.State.IDLE
								c.task_id = ""
							c.decision_cooldown = randf_range(1.0, 2.0)
						elif c.pos.distance_to(_get_hearth_pos()) <= 22.0 and economy.get_resource("food") >= 0.25:
							consume_food(0.25)
							c.hunger = 100.0
							c.show_emote("eat", 3.0, 3)
							c.last_status_reason = "Поел у очага"
							if not c._restore_task_snapshot():
								c.state = CitizenNPC.State.IDLE
								c.task_id = ""
							c.decision_cooldown = randf_range(1.0, 2.0)
						else:
							if not c._restore_task_snapshot():
								c.state = CitizenNPC.State.IDLE
								c.task_id = ""
							c.last_status_reason = "Голодает! Нет еды у очага"
						continue
					elif c.task_id == "social_action_pending":
						var pending_action = c.pending_social_action
						c.pending_social_action = ""
						c.task_id = ""
						if pending_action == "complain":
							c.state = CitizenNPC.State.COMPLAINING
							c.social_timer = 8.0
							c.last_status_reason = "Жалуется вождю на несправедливость"
						elif pending_action == "help_neighbor":
							c.state = CitizenNPC.State.HELPING
							c.social_timer = 8.0
							var target_c = get_citizen_by_id(c.target_id)
							if target_c and target_c.is_alive and target_c.pos.distance_to(c.pos) <= 60.0:
								c.facing_dir = (target_c.pos - c.pos).normalized()
								target_c.facing_dir = (c.pos - target_c.pos).normalized()
								if target_c.hunger < 35.0 and economy.get_resource("food") >= 0.5:
									consume_food(0.5)
									target_c.hunger = minf(100.0, target_c.hunger + 30.0)
									target_c.show_emote("eat", 3.0, 2)
								elif target_c.health < target_c.max_health:
									target_c.health = minf(target_c.max_health, target_c.health + 15.0)
								c.modify_relationship(target_c.citizen_id, 10.0, 5.0)
								target_c.modify_relationship(c.citizen_id, 10.0, 5.0)
								c.add_memory("helped_neighbor", "social", target_c.citizen_id, 1.3, "Помог соплеменнику %s в трудную минуту" % target_c.name)
								target_c.add_memory("was_helped", "social", c.citizen_id, 1.3, "Получил помощь от %s" % c.name)
							c.last_status_reason = "Помогает нуждающемуся соплеменнику"
						else:
							if not c._restore_task_snapshot():
								c.state = CitizenNPC.State.IDLE
						continue
					elif c.task_id == "burial_procession":
						var dead_c = get_citizen_by_id(c.target_id)
						if c.subphase == "fetch_body":
							c.subphase = "carry_to_grave"
							c.carrying_deceased_id = c.target_id
							var g_pos = GameManager.nav_grid.tile_to_world_center(c.target_coord) if GameManager and GameManager.nav_grid else Vector2(c.target_coord.x * 32 + 16, c.target_coord.y * 32 + 16)
							c.target_pos = g_pos
							c.path = GameManager.nav_grid.find_path(c.pos, g_pos) if GameManager and GameManager.nav_grid else []
							c.path_index = 0
							c.last_status_reason = "Несёт тело %s к месту погребения" % (dead_c.name if dead_c else "соплеменника")
							c.show_emote("grief", 4.0, 3)
							# Скорбящие следуют за могильщиком к кладбищу
							for m in population.citizens:
								if m.is_alive and m.task_id == "funeral_march":
									m.target_pos = g_pos
									m.path = GameManager.nav_grid.find_path(m.pos, g_pos) if GameManager and GameManager.nav_grid else []
									m.path_index = 0
									m.last_status_reason = "Идёт в погребальной процессии (%s)" % (dead_c.name if dead_c else "")
							continue
						elif c.subphase == "carry_to_grave":
							c.subphase = "digging_grave"
							c.state = CitizenNPC.State.WORKING
							c.work_timer = 4.0
							c.show_emote("shovel", 4.0, 3)
							c.last_status_reason = "Предает земле и обустраивает могилу %s" % (dead_c.name if dead_c else "соплеменника")
							
							# Скорбящие родственники выстраиваются в круг прощания (Funeral Vigil) вокруг могилы
							var g_pos = c.pos
							var mourners: Array[CitizenNPC] = []
							for m in population.citizens:
								if m.is_alive and (m.task_id == "funeral_march" or m.task_id == "funeral_vigil"):
									mourners.append(m)
							var farewell_lines = [
								"Покойся с миром, %s...",
								"Мы сохраним память о тебе, %s...",
								"Пусть предки примут тебя, %s...",
								"Ты навсегда в наших сердцах, %s..."
							]
							var m_count = max(1, mourners.size())
							for m_idx in range(mourners.size()):
								var m = mourners[m_idx]
								var ang = (float(m_idx) / float(m_count)) * TAU
								var offset = Vector2(cos(ang), sin(ang)) * 20.0
								var vigil_pos = g_pos + offset
								m.pos = vigil_pos
								m.target_pos = vigil_pos
								m.facing_dir = (g_pos - vigil_pos).normalized()
								m.task_id = "funeral_vigil"
								m.state = CitizenNPC.State.RESTING
								m.work_timer = 5.0
								m.show_emote("candle", 5.0, 4, true)
								m.shout(farewell_lines[m_idx % farewell_lines.size()] % (dead_c.name if dead_c else "соплеменник"), 4.0)
								m.last_status_reason = "Стоит в кругу прощания у могилы %s" % (dead_c.name if dead_c else "")
							continue
					elif c.task_id in ["funeral_march", "funeral_vigil"]:
						c.state = CitizenNPC.State.RESTING
						c.work_timer = 5.0
						c.show_emote("candle", 5.0, 4, true)
						c.last_status_reason = "Стоит у места погребения, прощаясь"
						continue
					elif c.task_id == "visit_grave":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = 5.0
						c.show_emote("candle", 5.0, 4, true)
						c.facing_dir = (c.target_pos - c.pos).normalized()
						c.last_status_reason = "Чтит память соплеменника у могилы"
						continue
					elif c.task_id == "offer_gifts":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = 5.0
						c.show_emote("flower", 5.0, 4, true)
						c.facing_dir = (c.target_pos - c.pos).normalized()
						c.last_status_reason = "Возлагает дары на могилу предка"
						continue
					elif c.task_id == "desecrate_grave":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = 4.0
						c.show_emote("anger", 4.0, 5, true)
						c.facing_dir = (c.target_pos - c.pos).normalized()
						c.last_status_reason = "Оскверняет могилу своего недруга!"
						continue
					elif c.task_id == "cleanse_grave":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = 5.0
						c.show_emote("praise", 5.0, 4, true)
						c.facing_dir = (c.target_pos - c.pos).normalized()
						c.last_status_reason = "Очищает и освящает осквернённую могилу"
						continue
					elif c.task_id == "evening_fishing":
						var c_coord = Vector2i(int(floor(c.pos.x / 32.0)), int(floor(c.pos.y / 32.0)))
						var found_water = false
						if GameManager and GameManager.nav_grid:
							# Сначала проверяем сохранённую клетку воды
							if c.target_coord != Vector2i(-1, -1) and GameManager.nav_grid.is_water_tile(c.target_coord):
								var w_center = GameManager.nav_grid.tile_to_world_center(c.target_coord)
								c.facing_dir = (w_center - c.pos).normalized()
								found_water = true
							else:
								for n_off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]:
									var check_c = c_coord + n_off
									if GameManager.nav_grid.is_water_tile(check_c):
										var w_center = GameManager.nav_grid.tile_to_world_center(check_c)
										c.facing_dir = (w_center - c.pos).normalized()
										c.target_coord = check_c
										found_water = true
										break
						if not found_water:
							c.state = CitizenNPC.State.IDLE
							c.task_id = ""
							c.last_status_reason = "Не нашёл берега с водой"
							continue
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(6.0, 10.0)
						c.last_status_reason = "Рыбачит в лучах вечернего заката"
						continue
					elif c.task_id == "evening_training":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(5.0, 8.0)
						c.show_emote("strength", 4.0, 2)
						c.last_status_reason = "Тренируется в боевом искусстве"
						continue
					elif c.task_id == "evening_walk":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(4.0, 7.0)
						c.show_emote("calm", 3.0, 1)
						c.last_status_reason = "Любуется закатом и природой"
						continue
					elif c.task_id == "evening_porch_rest":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(5.0, 9.0)
						c.show_emote("calm", 3.0, 1)
						c.last_status_reason = "Отдыхает на крыльце у дома"
						continue
					elif c.task_id == "visit_friend_home":
						c.state = CitizenNPC.State.RESTING
						c.task_id = "visiting_friend"
						c.work_timer = randf_range(7.0, 12.0)
						c.show_emote("dialog", 3.5, 2)
						var host_c = get_citizen_by_id(c.target_id)
						if host_c and host_c.is_alive and host_c.pos.distance_to(c.pos) <= 60.0:
							c.facing_dir = (host_c.pos - c.pos).normalized()
							host_c.facing_dir = (c.pos - host_c.pos).normalized()
							c.shout(_pick_phrase(c, [
								"Мир твоему очагу, %s!" % host_c.name,
								"Заглянул проведать тебя, %s." % host_c.name,
								"Рад видеть тебя в добром здравии, %s!" % host_c.name
							]), 3.5)
							host_c.shout(_pick_phrase(host_c, [
								"Заходи, %s, гостем будешь!" % c.name,
								"Всегда рад тебе, %s! Присаживайся к теплу." % c.name,
								"Добро пожаловать в мой дом, %s!" % c.name
							]), 3.5)
							host_c.show_emote("joy", 3.0, 2)
							c.modify_relationship(host_c.citizen_id, 8.0, 4.0)
							host_c.modify_relationship(c.citizen_id, 8.0, 4.0)
							c.add_memory("visit", "social", host_c.citizen_id, 1.2, "Погостил у соплеменника %s" % host_c.name)
							host_c.add_memory("guest", "social", c.citizen_id, 1.2, "Принял в гостях соплеменника %s" % c.name)
							if c.target_coord != Vector2i(-1, -1) and GameManager.building_instances:
								var b_inst = GameManager.building_instances.get(c.target_coord, null)
								if b_inst and b_inst.food_stockpile >= 0.5:
									b_inst.consume_food(0.2)
									c.hunger = minf(100.0, c.hunger + 15.0)
									host_c.hunger = minf(100.0, host_c.hunger + 10.0)
									c.show_emote("eat", 3.0, 2)
							c.last_status_reason = "Гостит у соплеменника %s" % host_c.name
						else:
							c.last_status_reason = "Отдыхает на крыльце хижины друга"
						continue
					elif c.task_id == "dating_walk":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(8.0, 14.0)
						c.show_emote("love", 4.0, 3)
						var partner_c = get_citizen_by_id(c.target_id)
						if partner_c and partner_c.is_alive and partner_c.pos.distance_to(c.pos) <= 60.0:
							c.facing_dir = (partner_c.pos - c.pos).normalized()
							partner_c.facing_dir = (c.pos - partner_c.pos).normalized()
							partner_c.state = CitizenNPC.State.RESTING
							partner_c.task_id = "dating_walk"
							partner_c.work_timer = c.work_timer
							partner_c.show_emote("romance", 4.0, 3)
							c.shout(_pick_phrase(c, [
								"С тобой этот вечер по-настоящему особенный, %s...",
								"Я собрал эти цветы для тебя, %s!",
								"Моё сердце радуется рядом с тобой, %s..."
							]), 4.0)
							partner_c.shout(_pick_phrase(partner_c, [
								"И я счастлива быть рядом с тобой, %s...",
								"Ты самый надёжный человек во всём племени, %s.",
								"Пусть этот вечер длится дольше..."
							]), 4.0)
							var cur_rel = c.get_relationship(partner_c.citizen_id)
							var new_rom = float(cur_rel.get("romance", 0.0)) + 20.0
							c.add_relationship(partner_c.citizen_id, "friend", 70.0, new_rom, cur_rel.get("married", false))
							partner_c.add_relationship(c.citizen_id, "friend", 70.0, new_rom, cur_rel.get("married", false))
							c.modify_relationship(partner_c.citizen_id, 10.0, 5.0)
							partner_c.modify_relationship(c.citizen_id, 10.0, 5.0)
							c.add_memory("romance_date", "love", partner_c.citizen_id, 1.8, "Провёл романтический вечер с %s" % partner_c.name)
							partner_c.add_memory("romance_date", "love", c.citizen_id, 1.8, "Провела романтический вечер с %s" % partner_c.name)
							if new_rom >= 50.0 and not cur_rel.get("married", false) and c.can_marry(partner_c, marriage_law).get("allowed", false):
								c.marry(partner_c, marriage_law)
								c.shout("Ты будешь моей спутницей жизни? — Да, я согласна!", 4.5)
								partner_c.shout("Мы связали наши судьбы перед духами предков!", 4.5)
								c.show_emote("marriage", 5.0, 4)
								partner_c.show_emote("marriage", 5.0, 4)
								EventBus.notification_toast.emit("💍 Новый союз", "%s и %s заключили священный союз" % [c.name, partner_c.name], "good")
								auto_assign_housing()
							c.last_status_reason = "На свидании с любимым человеком (%s)" % partner_c.name
							partner_c.last_status_reason = "На свидании с любимым человеком (%s)" % c.name
						else:
							c.last_status_reason = "Гуляет и любуется вечерней природой"
						continue
					elif c.task_id == "reconcile_quarrel":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(5.0, 8.0)
						c.show_emote("handshake", 4.0, 3)
						var rival_c = get_citizen_by_id(c.target_id)
						if rival_c and rival_c.is_alive and rival_c.pos.distance_to(c.pos) <= 60.0:
							c.facing_dir = (rival_c.pos - c.pos).normalized()
							rival_c.facing_dir = (c.pos - rival_c.pos).normalized()
							c.shout("Забудем старую обиду, %s. Нам незачем враждовать в одном племени!" % rival_c.name, 4.0)
							rival_c.shout("Ты прав, %s. Мир важнее старых ссор. Забудем былое!" % c.name, 4.0)
							rival_c.show_emote("joy", 3.5, 3)
							c.clear_grudge(rival_c.citizen_id)
							rival_c.clear_grudge(c.citizen_id)
							c.modify_relationship(rival_c.citizen_id, 25.0, 10.0)
							rival_c.modify_relationship(c.citizen_id, 25.0, 10.0)
							c.loyalty = minf(100.0, c.loyalty + 4.0)
							rival_c.loyalty = minf(100.0, rival_c.loyalty + 4.0)
							c.add_memory("reconciled", "peace", rival_c.citizen_id, 2.0, "Помирился с соплеменником %s и забыл старую обиду" % rival_c.name, true)
							rival_c.add_memory("reconciled", "peace", c.citizen_id, 2.0, "Помирился с соплеменником %s" % c.name, true)
							EventBus.notification_toast.emit("🤝 Примирение", "%s и %s помирились и забыли старую обиду" % [c.name, rival_c.name], "good")
							c.last_status_reason = "Помирился с %s" % rival_c.name
						else:
							c.last_status_reason = "Ищет примирения с соплеменником"
						continue
					elif c.task_id == "pet_animal":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(4.0, 6.0)
						c.show_emote("heart" if randf() < 0.5 else "praise", 3.5, 3)
						if GameManager and GameManager.wildlife_manager and GameManager.wildlife_manager.animals.has(c.target_id):
							var anim_pet = GameManager.wildlife_manager.animals[c.target_id]
							c.facing_dir = (anim_pet.pos - c.pos).normalized()
							anim_pet.facing_dir = (c.pos - anim_pet.pos).normalized()
							c.shout(_pick_phrase(c, [
								"Кто у нас тут самый славный друг?",
								"Хороший волчонок, умница!",
								"Держи лакомство, дружок!",
								"Славный наш зверёк!"
							]), 3.5)
							c.loyalty = minf(100.0, c.loyalty + 2.5)
							c.last_status_reason = "Гладит и играет с питомцем"
						else:
							c.last_status_reason = "Общается с прирученным животным"
						continue
					elif c.task_id == "place_decoration":
						_finish_decoration_placement(c)
						continue
					elif c.task_id == "cleanup_trash":
						_finish_trash_cleanup(c)
						continue
					elif c.task_id == "recover_at_home":
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(8.0, 16.0)
						c.ongoing_task_kind = "resting"
						c.commitment_timer = c.work_timer
						c.last_status_reason = "Отлёживается дома после ран и битвы (%d/%d HP)" % [int(c.health), int(c.max_health)]
						continue
					elif c.task_id == "defend_settlement":
						c.state = CitizenNPC.State.ATTACKING
						c.work_timer = 0.0
						c.last_status_reason = "Сражается с врагом, защищая соплеменников!"
						continue
					elif c.task_id == "stop_brawl":
						for brawler in population.citizens:
							if brawler.is_alive and brawler.task_id == "brawling" and brawler.pos.distance_to(c.pos) <= 45.0:
								brawler.task_id = ""
								brawler.state = CitizenNPC.State.IDLE
								brawler.last_status_reason = "Успокоен стражником после драки"
								brawler.show_emote("fear", 3.0, 3)
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.last_status_reason = "Восстановил порядок в поселении"
						EventBus.notification_toast.emit("🛡 Порядок восстановлен", "%s разнял уличную потасовку" % c.name, "info")
						continue
					elif c.task_id == "fetch_home_food":
						var my_home: BuildingInstance = null
						if GameManager.building_instances:
							for h in GameManager.building_instances.values():
								if h.id == c.home_id:
									my_home = h
									break
						var needed_food = 4.0
						if my_home:
							needed_food = minf(4.0, my_home.food_stockpile_max - my_home.food_stockpile)
						var take_amt = minf(needed_food, economy.get_resource("food"))
						if take_amt >= 0.5:
							consume_food(take_amt)
							c.cargo_type = "food"
							c.cargo_amount = take_amt
							c.task_id = "deliver_home_food"
							c.state = CitizenNPC.State.CARRYING
							c.target_pos = c.home_pos
							c.path = GameManager.nav_grid.find_path(c.pos, c.home_pos) if GameManager.nav_grid else []
							c.path_index = 0
							c.last_status_reason = "Несёт %d еды домой" % int(c.cargo_amount)
						else:
							c.state = CitizenNPC.State.WAITING
							c.task_id = ""
							c.last_status_reason = "На складе нет еды для дома"
							c.decision_cooldown = 2.0
						continue
					elif c.task_id == "fetch_clothes":
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 1.0
						if economy.get_resource("clothes") >= 1.0:
							economy.resources["clothes"] = economy.get_resource("clothes") - 1.0
							c.warm_clothes = WARM_CLOTHES_MAX
							c.is_freezing = false
							c.show_emote("joy", 3.0, 2)
							c.last_status_reason = "Взял со склада новую тёплую одежду"
							if is_player_settlement():
								EventBus.resources_updated.emit(faction_id, economy.resources)
						else:
							c.last_status_reason = "На складе не осталось тёплой одежды"
						continue
					elif c.task_id == "assist_relative":
						c.state = CitizenNPC.State.WORKING
						c.work_timer = 2.5
						c.last_status_reason = "Помогает родственнику в общем деле"
						continue
					elif c.task_id == "place_decoration":
						_finish_decoration_placement(c)
						continue
					elif c.task_id == "cleanup_trash":
						_finish_trash_cleanup(c)
						continue
					elif c.job_id == "forager":
						c.state = CitizenNPC.State.GATHERING
						c.work_timer = randf_range(2.0, 3.5)
						c.last_status_reason = "Собирает ягоды"
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.set_arrived(c.task_instance_id)
							GameManager.task_service.start_task(c.task_instance_id)
					elif c.job_id == "fisherman":
						c.state = CitizenNPC.State.GATHERING
						c.work_timer = randf_range(3.0, 5.0)
						c.last_status_reason = "Ловит рыбу у берега"
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.set_arrived(c.task_instance_id)
							GameManager.task_service.start_task(c.task_instance_id)
					elif _profession_arrived(c):
						pass
					elif c.job_id == "builder" or c.task_id in ["fetch_materials", "fetch_upgrade_materials", "build", "upgrade_work"]:
						if c.task_id == "fetch_materials":
							var constr_coord = c.target_coord
							var take_res = ""
							var take_amt = 0.0
							var camp = get_active_woodcutter_camp()
							if GameManager.tile_buildings.has(constr_coord):
								var b = GameManager.tile_buildings[constr_coord]
								var req = b.get("materials_required", {})
								var deliv = b.get("materials_delivered", {})
								if c.target_id != "" and req.has(c.target_id):
									var needed = float(req[c.target_id]) - float(deliv.get(c.target_id, 0.0))
									var wood_in_camp = camp.local_buffer_wood if (camp and c.target_id == "wood") else 0.0
									var avail = economy.get_resource(c.target_id) + wood_in_camp
									if needed > 0.0 and avail > 0.0:
										take_res = c.target_id
										var want = minf(needed, c.max_carry)
										var from_econ = minf(want, economy.get_resource(take_res))
										if from_econ > 0.0:
											economy.resources[take_res] = maxf(0.0, economy.resources[take_res] - from_econ)
											take_amt += from_econ
										if take_amt < want and take_res == "wood" and camp and camp.local_buffer_wood > 0.0:
											var from_camp = camp.take_wood(want - take_amt)
											take_amt += from_camp
								if take_res == "":
									for r in req:
										var needed = float(req[r]) - float(deliv.get(r, 0.0))
										var wood_in_camp = camp.local_buffer_wood if (camp and r == "wood") else 0.0
										var avail = economy.get_resource(r) + wood_in_camp
										if needed > 0.0 and avail > 0.0:
											take_res = r
											var want = minf(needed, c.max_carry)
											var from_econ = minf(want, economy.get_resource(take_res))
											if from_econ > 0.0:
												economy.resources[take_res] = maxf(0.0, economy.resources[take_res] - from_econ)
												take_amt += from_econ
											if take_amt < want and take_res == "wood" and camp and camp.local_buffer_wood > 0.0:
												var from_camp = camp.take_wood(want - take_amt)
												take_amt += from_camp
											break
							if take_res != "" and take_amt > 0.0:
								var is_pl = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "test_s")
								if is_pl:
									EventBus.resources_updated.emit(faction_id, economy.resources)
								c.cargo_type = take_res
								c.cargo_amount = take_amt
								c.task_id = "haul_to_site"
								c.state = CitizenNPC.State.CARRYING
								c.target_pos = GameManager.nav_grid.tile_to_world_center(constr_coord)
								c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
								c.path_index = 0
								c.last_status_reason = "Несёт %d %s на стройплощадку" % [int(c.cargo_amount), c.cargo_type]
							else:
								c.state = CitizenNPC.State.WAITING
								c.task_id = ""
								c.last_status_reason = "Стройка остановлена: нет материалов"
								c.decision_cooldown = randf_range(2.0, 4.0)
							continue
						elif c.task_id == "fetch_upgrade_materials":
							var up_coord = c.target_coord
							var take_res = ""
							var take_amt = 0.0
							var camp = get_active_woodcutter_camp()
							if GameManager.building_instances.has(up_coord):
								var b_inst = GameManager.building_instances[up_coord]
								if b_inst and b_inst.has_pending_upgrade():
									var req = b_inst.pending_upgrade.get("materials_required", {})
									var deliv = b_inst.pending_upgrade.get("materials_delivered", {})
									if c.target_id != "" and req.has(c.target_id):
										var needed = float(req[c.target_id]) - float(deliv.get(c.target_id, 0.0))
										var wood_in_camp = camp.local_buffer_wood if (camp and c.target_id == "wood") else 0.0
										var avail = economy.get_resource(c.target_id) + wood_in_camp
										if needed > 0.0 and avail > 0.0:
											take_res = c.target_id
											var want = minf(needed, c.max_carry)
											var from_econ = minf(want, economy.get_resource(take_res))
											if from_econ > 0.0:
												economy.resources[take_res] = maxf(0.0, economy.resources[take_res] - from_econ)
												take_amt += from_econ
											if take_amt < want and take_res == "wood" and camp and camp.local_buffer_wood > 0.0:
												var from_camp = camp.take_wood(want - take_amt)
												take_amt += from_camp
									if take_res == "":
										for r in req:
											var needed = float(req[r]) - float(deliv.get(r, 0.0))
											var wood_in_camp = camp.local_buffer_wood if (camp and r == "wood") else 0.0
											var avail = economy.get_resource(r) + wood_in_camp
											if needed > 0.0 and avail > 0.0:
												take_res = r
												var want = minf(needed, c.max_carry)
												var from_econ = minf(want, economy.get_resource(take_res))
												if from_econ > 0.0:
													economy.resources[take_res] = maxf(0.0, economy.resources[take_res] - from_econ)
													take_amt += from_econ
												if take_amt < want and take_res == "wood" and camp and camp.local_buffer_wood > 0.0:
													var from_camp = camp.take_wood(want - take_amt)
													take_amt += from_camp
												break
							if take_res != "" and take_amt > 0.0:
								var is_pl = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "test_s")
								if is_pl:
									EventBus.resources_updated.emit(faction_id, economy.resources)
								c.cargo_type = take_res
								c.cargo_amount = take_amt
								c.task_id = "haul_to_upgrade"
								c.state = CitizenNPC.State.CARRYING
								c.target_pos = GameManager.nav_grid.tile_to_world_center(up_coord)
								c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
								c.path_index = 0
								c.last_status_reason = "Несёт %d %s для улучшения здания" % [int(c.cargo_amount), c.cargo_type]
							else:
								c.state = CitizenNPC.State.WAITING
								c.task_id = ""
								c.last_status_reason = "Улучшение остановлено: нет материалов"
								c.decision_cooldown = randf_range(2.0, 4.0)
							continue
						elif c.task_id in ["build", "upgrade_work"]:
							c.state = CitizenNPC.State.WORKING
							c.work_timer = 2.0
							c.last_status_reason = "Возводит здание" if c.task_id == "build" else "Работает над улучшением"
							continue
						else:
							c.state = CitizenNPC.State.WORKING
							c.work_timer = 2.0
							c.last_status_reason = "Работает на стройке"
					else:
						c.state = CitizenNPC.State.WORKING
						c.work_timer = randf_range(3.0, 5.5)
						c.last_status_reason = _get_job_action_name(c.job_id)
				elif c.state == CitizenNPC.State.CARRYING or c.state == CitizenNPC.State.GOING_HOME:
					if _profession_cargo_delivered(c):
						continue
					elif c.task_id == "haul_to_site":
						var constr_coord = c.target_coord
						if GameManager.tile_buildings.has(constr_coord):
							var b = GameManager.tile_buildings[constr_coord]
							var deliv = b.get("materials_delivered", {})
							deliv[c.cargo_type] = float(deliv.get(c.cargo_type, 0.0)) + c.cargo_amount
							b["materials_delivered"] = deliv
						c.cargo_type = ""
						c.cargo_amount = 0.0
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 0.5
						c.last_status_reason = "Доставил материалы на стройплощадку"
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.complete_task(c.task_instance_id)
							c.task_instance_id = ""
						continue
					elif c.task_id == "haul_to_upgrade":
						var up_coord = c.target_coord
						if GameManager.building_instances.has(up_coord):
							var b_inst = GameManager.building_instances[up_coord]
							if b_inst and b_inst.has_pending_upgrade():
								var deliv = b_inst.pending_upgrade.get("materials_delivered", {})
								deliv[c.cargo_type] = float(deliv.get(c.cargo_type, 0.0)) + c.cargo_amount
								b_inst.pending_upgrade["materials_delivered"] = deliv
						c.cargo_type = ""
						c.cargo_amount = 0.0
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 0.5
						c.last_status_reason = "Доставил материалы для улучшения"
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.complete_task(c.task_instance_id)
							c.task_instance_id = ""
						continue
					elif c.task_id == "deliver_home_food":
						if GameManager.building_instances:
							for h in GameManager.building_instances.values():
								if h.id == c.home_id:
									h.store_food(c.cargo_amount)
									break
						c.cargo_type = ""
						c.cargo_amount = 0.0
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 1.0
						c.last_status_reason = "Пополнил домашний запас еды"
						continue
					elif (c.cargo_type != "" and c.cargo_amount > 0) or c.custom_data.has("hunt_byproducts"):
						# Шкуры, мех, кости и перья, принесённые охотником вместе с мясом
						if c.custom_data.has("hunt_byproducts"):
							var hunt_extras: Dictionary = c.custom_data["hunt_byproducts"]
							c.custom_data.erase("hunt_byproducts")
							for res_key in hunt_extras:
								deposit_resource(res_key, float(hunt_extras[res_key]), c.name)
						deposit_resource(c.cargo_type, c.cargo_amount, c.name, c.cargo_batch)
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.complete_task(c.task_instance_id)
							c.task_instance_id = ""
						c.last_status_reason = "Сдал %d %s в амбар" % [int(c.cargo_amount), RESOURCE_NAMES_RU.get(c.cargo_type, c.cargo_type)]
						c.cargo_type = ""
						c.cargo_amount = 0.0
						c.cargo_batch.clear()
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = randf_range(1.5, 3.0)
			continue
			
		# Сбор ягод и растений (GATHERING)
		if c.state == CitizenNPC.State.GATHERING:
			c.work_timer -= delta * c.get_work_speed_multiplier()
			if c.work_timer <= 0.0:
				var harvested = 0.0
				if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
					harvested = GameManager.resource_manager.harvest_from_node(c.target_coord, 4.0)
					GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
				if harvested > 0.0:
					c.cargo_type = "food"
					c.cargo_amount += harvested
					c.cargo_batch = {
						"food_type": "fish" if c.task_id == "fish" else "berries",
						"amount": c.cargo_amount,
						"created_sim_time": GameManager.sim_time_total,
						"max_freshness_sec": 3000.0 if c.task_id == "fish" else 3600.0,
						"spoilage_progress": 0.0
					}
				c.target_coord = Vector2i(-1, -1)
				c.state = CitizenNPC.State.CARRYING
				var dest_p = _get_storage_pos(c)
				c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
				c.path_index = 0
				c.last_status_reason = "Несёт %d рыбы в амбар" % int(c.cargo_amount) if c.task_id == "fish" else "Несёт %d еды в амбар" % int(c.cargo_amount)
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.set_delivering(c.task_instance_id)
			continue
			
		# Атака зверя охотником или защитником поселения (ATTACKING)
		if c.state == CitizenNPC.State.ATTACKING:
			c.work_timer -= delta
			if not GameManager.wildlife_manager.animals.has(c.target_id):
				c.target_id = ""
				c.task_id = ""
				c.state = CitizenNPC.State.IDLE
				c.decision_cooldown = 1.0
				c.last_status_reason = "Угроза устранена"
				continue
			var animal = GameManager.wildlife_manager.animals[c.target_id]
			c.facing_dir = (animal.pos - c.pos).normalized()
			if c.work_timer <= 0.0:
				c.work_timer = 1.2
				var base_dmg = 15.0
				if c.job_id in ["guard", "warrior"]:
					base_dmg = 26.0
				elif c.job_id == "hunter":
					var camp_inst = _get_hunting_camp_instance(c)
					base_dmg = 20.0 * (camp_inst.get_hunter_damage_mult() if camp_inst else 1.0)
				elif c.has_tool("axe"):
					base_dmg = 22.0
				elif c.has_tool("pickaxe"):
					base_dmg = 18.0
				else:
					base_dmg = maxf(12.0, float(c.traits.get("bravery", 50.0)) * 0.2 + float(c.traits.get("temper", 20.0)) * 0.2)

				var killed = animal.take_damage(base_dmg, c.citizen_id)
				if not killed and animal.is_alive():
					# Зверь даёт сдачи защитнику
					var a_dmg = animal.attack_damage if animal.attack_damage > 0.0 else 10.0
					c.take_damage(a_dmg * 0.4, animal.species)
					if c.health <= 0.0:
						continue

				if killed:
					var carcass = GameManager.wildlife_manager.create_carcass_from_animal(animal)
					GameManager.wildlife_manager.animals.erase(c.target_id)
					if c.job_id == "hunter":
						c.target_id = carcass["id"]
						c.target_pos = carcass["pos"]
						c.path = GameManager.nav_grid.find_path(c.pos, carcass["pos"]) if GameManager.nav_grid else []
						c.path_index = 0
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.last_status_reason = "Добыл зверя, идёт к туше"
					else:
						c.target_id = ""
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.last_status_reason = "Одолел опасного зверя и защитил племя!"
						c.shout("Зверь повержен! Поселение в безопасности!", 3.5)
						c.show_emote("praise", 3.5, 3)
						c.loyalty = minf(100.0, c.loyalty + 6.0)
						c.add_memory("defended_tribe", "hero", animal.id, 2.0, "Защитил соплеменников от опасного зверя", true)
						EventBus.notification_toast.emit("🛡 Угроза устранена!", "%s защитил поселение и одолел зверя!" % c.name, "good")
				else:
					c.target_pos = animal.pos
					c.path = GameManager.nav_grid.find_path(c.pos, animal.pos) if GameManager.nav_grid else []
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Преследует зверя в бою"
			continue

		# Особые рабочие состояния профессий (разделка туши охотником)
		if c.state == CitizenNPC.State.BUTCHERING:
			if ProfessionRegistry.get_behavior("hunter").on_state_tick(self, c, delta):
				continue
			c.state = CitizenNPC.State.IDLE
			continue

		# Выполнение работы на месте
		if c.state == CitizenNPC.State.WORKING:
			c.work_timer -= delta * c.get_work_speed_multiplier()
			if c.work_timer <= 0.0:
				if c.task_id == "burial_procession" and c.subphase == "digging_grave":
					var d_c = get_citizen_by_id(c.target_id)
					if d_c:
						d_c.is_buried = true
					var g_coord = c.target_coord
					var g_inst: BuildingInstance = c.custom_data.get("grave_inst", null)
					if g_inst == null and d_c and d_c.custom_data.has("pending_grave_inst"):
						g_inst = d_c.custom_data["pending_grave_inst"]
					if g_inst != null and GameManager:
						GameManager.building_instances[g_coord] = g_inst
						GameManager.tile_buildings[g_coord] = {"id": "cemetery", "coord": g_coord, "status": "active"}
						if GameManager.nav_grid:
							GameManager.nav_grid.register_building(g_coord, Vector2i(1, 1), g_inst.id)
						if not buildings.has("cemetery"):
							buildings.append("cemetery")
						if not buildings.has("grave"):
							buildings.append("grave")
					c.subphase = ""
					c.carrying_deceased_id = ""
					c.task_id = ""
					c.state = CitizenNPC.State.IDLE
					c.last_status_reason = "Завершил обряд погребения"
					c.show_emote("respect", 4.0, 3)
					EventBus.notification_toast.emit("⚰ Погребение завершено", "Соплеменник %s предан земле в родовом могильнике" % (d_c.name if d_c else ""), "good")
					for mourner in population.citizens:
						if mourner.is_alive and (mourner.task_id == "funeral_march" or mourner.task_id == "funeral_vigil"):
							mourner.task_id = ""
							mourner.state = CitizenNPC.State.IDLE
							mourner.last_status_reason = "Простился с соплеменником у могилы"
							mourner.add_memory("honored_burial", "grave", c.target_id, 2.0, "Проводил соплеменника в последний путь с почестями", true)
							mourner.show_emote("respect", 4.0, 3)
							mourner.loyalty = minf(100.0, mourner.loyalty + 4.0)
					continue
				elif c.task_id == "care_for_child":
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.decision_cooldown = randf_range(1.5, 3.0)
					c.last_status_reason = "Завершил уход за ребёнком"
					continue
				elif c.task_id == "assist_relative":
					# S08: Помощник завершил цикл помощи — получает XP, но НЕ создаёт ресурсов (не дублирует)
					c.gain_profession_xp(c.job_id if c.job_id != "idle" else "forager", 2.5)
					c.state = CitizenNPC.State.IDLE
					c.task_id = ""
					c.target_id = ""
					c.decision_cooldown = randf_range(1.5, 3.0)
					c.last_status_reason = "Помог родственнику"
					continue
				elif _profession_work_done(c):
					pass
				elif c.job_id == "builder" or c.task_id in ["build", "upgrade_work"]:
					if c.task_id == "upgrade_work":
						if GameManager.building_instances.has(c.target_coord):
							var b_inst = GameManager.building_instances[c.target_coord]
							if b_inst and b_inst.has_pending_upgrade():
								var up = b_inst.pending_upgrade
								var is_missing = false
								for r in up.get("materials_required", {}):
									if float(up.get("materials_delivered", {}).get(r, 0.0)) < float(up["materials_required"][r]):
										is_missing = true
										break
								if is_missing:
									c.state = CitizenNPC.State.WAITING
									c.last_status_reason = "Улучшение остановлено: не все материалы на площадке"
									c.decision_cooldown = 2.0
								else:
									up["work_left"] = maxf(0.0, float(up.get("work_left", 4.0)) - 1.5)
									c.add_work_xp("building", 0.25)
									if up["work_left"] <= 0.0:
										var up_id = up["id"]
										b_inst.unlock_upgrade(up_id)
										c.last_status_reason = "Завершил улучшение здания"
										var up_name = BuildingSystem.get_upgrade(up_id).get("name", up_id)
										EventBus.notification_toast.emit("Улучшение завершено", "Здание улучшено: %s" % up_name, "good")
										c.state = CitizenNPC.State.IDLE
										c.task_id = ""
										c.decision_cooldown = 1.0
									else:
										c.work_timer = 0.65
										c.last_status_reason = "Работает над улучшением здания"
					else:
						# Обычное строительство здания
						if GameManager.tile_buildings.has(c.target_coord):
							var b = GameManager.tile_buildings[c.target_coord]
							if b.get("status", "") == "constructing":
								var is_missing = false
								for r in b.get("materials_required", {}):
									if float(b.get("materials_delivered", {}).get(r, 0.0)) < float(b["materials_required"][r]):
										is_missing = true
										break
								if is_missing:
									c.state = CitizenNPC.State.WAITING
									c.last_status_reason = "Стройка остановлена: нет материалов на площадке"
									c.decision_cooldown = 2.0
								else:
									b["days_left"] = maxf(0.0, float(b.get("days_left", 1.0)) - 0.70)
									c.add_work_xp("building", 0.25)
									if b["days_left"] <= 0.0:
										b["status"] = "active"
										var b_inst = GameManager.get_or_create_building_instance(c.target_coord, b["id"], id)
										b["instance_id"] = b_inst.instance_id
										if not buildings.has(b["id"]):
											buildings.append(b["id"])
										for q_i in range(construction_queue.size() - 1, -1, -1):
											if construction_queue[q_i].get("coord", Vector2i(-1, -1)) == c.target_coord:
												construction_queue.remove_at(q_i)
										c.last_status_reason = "Завершил строительство здания"
										var b_name = BuildingDB.get_building(b["id"]).get("name", b["id"])
										EventBus.notification_toast.emit("Стройка завершена", "Построено: %s" % b_name, "good")
										auto_assign_workplaces()
										c.state = CitizenNPC.State.IDLE
										c.task_id = ""
										c.decision_cooldown = 1.0
									else:
										c.work_timer = 0.65
										c.last_status_reason = "Строит здание (осталось %.1f дней)" % b["days_left"]
						else:
							c.state = CitizenNPC.State.IDLE
							c.decision_cooldown = 1.0
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
					# Ресурсы появляются только из реальных узлов карты, туш и полей —
					# «работа на месте» без цели ничего не создаёт из воздуха
					c.state = CitizenNPC.State.IDLE
					c.decision_cooldown = randf_range(2.0, 4.0)
			continue
			
		# Свободный выбор нового действия (IDLE или WAITING)
		if c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
			c.decision_cooldown -= delta
			if c.decision_cooldown > 0.0:
				continue
				
			# 0000. Восстановление после ран: раненый житель пропускает работу и отлёживается дома
			if c.health < 80.0 and c.cargo_amount == 0.0:
				if c.home_id != "" and c.home_pos != Vector2.ZERO:
					if c.pos.distance_to(c.home_pos) > 16.0:
						var r_path: Array[Vector2] = GameManager.nav_grid.find_path(c.pos, c.home_pos) if (GameManager and GameManager.nav_grid) else []
						if not r_path.is_empty():
							c.task_id = "recover_at_home"
							c.target_pos = c.home_pos
							c.path = r_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.ongoing_task_kind = "resting"
							c.commitment_timer = 12.0
							c.last_status_reason = "Ранен! Идёт домой отлежаться и восстановить силы (%d/%d HP)" % [int(c.health), int(c.max_health)]
							c.decision_cooldown = 1.0
							continue
					else:
						c.task_id = "recover_at_home"
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(8.0, 16.0)
						c.ongoing_task_kind = "resting"
						c.commitment_timer = c.work_timer
						c.last_status_reason = "Отлёживается дома после ран и битвы (%d/%d HP)" % [int(c.health), int(c.max_health)]
						continue
				else:
					c.task_id = "recover_at_home"
					c.state = CitizenNPC.State.RESTING
					c.work_timer = randf_range(6.0, 12.0)
					c.ongoing_task_kind = "resting"
					c.commitment_timer = c.work_timer
					c.last_status_reason = "Залечивает раны у костра (%d/%d HP)" % [int(c.health), int(c.max_health)]
					continue

			# 000. Вечерние посиделки у костра (18:00 - 21:45)
			# Свободные жители и рабочие после смены собираются у костра племени, общаются и слушают предания
			if indiv_hour >= 18.0 and indiv_hour < 21.8 and c.job_id != "guard" and c.cargo_amount == 0.0 and not (c.job_id == "builder" and not construction_queue.is_empty()):
				var campfire_center = GameManager.nav_grid.tile_to_world_center(pos) if GameManager.nav_grid else Vector2(pos.x * 32.0 + 16, pos.y * 32.0 + 16)
				var dist_to_fire = c.pos.distance_to(campfire_center)
				if dist_to_fire > 42.0:
					var angle = randf_range(0.0, TAU)
					var sit_radius = randf_range(16.0, 32.0)
					var target_fire_spot = campfire_center + Vector2(cos(angle), sin(angle)) * sit_radius
					var f_path = GameManager.nav_grid.find_path(c.pos, target_fire_spot) if GameManager.nav_grid else []
					if not f_path.is_empty():
						c.task_id = "evening_campfire"
						c.target_pos = target_fire_spot
						c.path = f_path
						c.path_index = 0
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.last_status_reason = "Идёт к вечернему костру племени"
						c.decision_cooldown = 1.0
						continue
				else:
					c.state = CitizenNPC.State.RESTING
					c.work_timer = randf_range(6.0, 12.0)
					c.ongoing_task_kind = "evening_campfire"
					c.commitment_timer = c.work_timer
					c.last_status_reason = "Греется и общается у костра"
					c.facing_dir = (campfire_center - c.pos).normalized()
					c.loyalty = minf(100.0, c.loyalty + 0.08)
					c.energy = minf(100.0, c.energy + 4.0)
					if randf() < 0.3:
						var emotes = ["hearth", "dialog", "joy", "praise", "wave", "sing"]
						c.show_emote(emotes[randi() % emotes.size()], 3.0, 1)
					continue
					
			# 000a2. Вечерние посиделки у очага Большого дома рода (18:00 - 22:00)
			if indiv_hour >= 18.0 and indiv_hour < 22.0 and c.cargo_amount == 0.0 and c.home_id != "":
				var lodge_inst: BuildingInstance = null
				if GameManager and GameManager.building_instances:
					for bi in GameManager.building_instances.values():
						if bi and bi.id == c.home_id and bi.is_great_lodge() and bi.is_upgrade_unlocked("great_hearth"):
							lodge_inst = bi
							break
				if lodge_inst != null:
					var lodge_pos = GameManager.nav_grid.tile_to_world_center(lodge_inst.pos) if GameManager.nav_grid else Vector2(lodge_inst.pos.x * 32.0 + 16, lodge_inst.pos.y * 32.0 + 16)
					if c.pos.distance_to(lodge_pos) > 28.0:
						var l_path = GameManager.nav_grid.find_path(c.pos, lodge_pos) if GameManager.nav_grid else []
						if not l_path.is_empty():
							c.task_id = "lodge_hearth_gathering"
							c.target_pos = lodge_pos
							c.path = l_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.last_status_reason = "Идёт к общему очагу Большого дома"
							c.decision_cooldown = 1.0
							continue
					else:
						c.state = CitizenNPC.State.RESTING
						c.work_timer = randf_range(6.0, 10.0)
						c.ongoing_task_kind = "lodge_hearth"
						c.commitment_timer = c.work_timer
						c.facing_dir = (lodge_pos - c.pos).normalized()
						c.loyalty = minf(100.0, c.loyalty + 0.12)
						c.energy = minf(100.0, c.energy + 5.0)
						if c.cohort == "elder":
							c.last_status_reason = "Рассказывает родовые предания у очага"
							if randf() < 0.4:
								c.show_emote("storytelling", 3.5, 1)
						else:
							c.last_status_reason = "Греется и слушает предания у очага рода"
							if randf() < 0.3:
								c.show_emote("dialog", 3.0, 1)
						continue

			# 000b. Дети играют в поселении и общаются со сверстниками (08:00 - 18:00)
			if c.cohort == "child" and c.cargo_amount == 0.0 and indiv_hour >= 8.0 and indiv_hour < 18.0:
				var campfire_center = GameManager.nav_grid.tile_to_world_center(pos) if GameManager.nav_grid else Vector2(pos.x * 32.0 + 16, pos.y * 32.0 + 16)
				var play_angle = randf_range(0.0, TAU)
				var play_radius = randf_range(14.0, 46.0)
				var play_pos = campfire_center + Vector2(cos(play_angle), sin(play_angle)) * play_radius
				var p_path = GameManager.nav_grid.find_path(c.pos, play_pos) if GameManager.nav_grid else []
				if not p_path.is_empty() and randf() < 0.6:
					c.task_id = "playing"
					c.target_pos = play_pos
					c.path = p_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Играет и резвится в лагере"
					c.decision_cooldown = randf_range(3.0, 6.0)
					continue
				else:
					c.state = CitizenNPC.State.RESTING
					c.work_timer = randf_range(3.0, 6.0)
					c.last_status_reason = "Играет со сверстниками"
					if randf() < 0.4:
						var play_emotes = ["game", "joy", "idea", "curiosity"]
						c.show_emote(play_emotes[randi() % play_emotes.size()], 2.5, 1)
					continue
				
			# 000c. Специальные социальные роли Большого дома рода (Опекун, Хранитель знаний, Старейшина)
			var assigned_lodge: BuildingInstance = null
			if GameManager and GameManager.building_instances:
				for bi in GameManager.building_instances.values():
					if bi and bi.is_great_lodge() and (bi.caretaker_id == c.citizen_id or bi.knowledge_keeper_id == c.citizen_id or bi.clan_elder_id == c.citizen_id):
						assigned_lodge = bi
						break

			# Роль 1: Опекун детей Большого дома рода (07:00 - 15:00)
			if (c.job_id == "caretaker" or (assigned_lodge != null and assigned_lodge.caretaker_id == c.citizen_id)) and indiv_hour >= 7.0 and indiv_hour < 15.0 and c.cargo_amount == 0.0:
				c.state = CitizenNPC.State.WORKING
				c.work_timer = randf_range(3.0, 5.0)
				c.ongoing_task_kind = "childcare"
				c.commitment_timer = c.work_timer
				if indiv_hour < 8.3:
					c.last_status_reason = "Собирает детей Большого дома"
				elif indiv_hour < 10.0:
					c.last_status_reason = "Проводит игры и развивающие занятия с детьми"
					if randf() < 0.35: c.show_emote("game", 3.0, 1)
				elif indiv_hour < 12.0:
					c.last_status_reason = "Вывел детей рода на прогулку"
				elif indiv_hour < 13.0:
					c.last_status_reason = "Кормит детей у очага"
				else:
					c.last_status_reason = "Организует дневной отдых детей"
				# Развитие навыков детей под опекой
				if assigned_lodge != null:
					for child_id in assigned_lodge.residents:
						var child_npc = population.get_citizen_by_id(child_id)
						if child_npc != null and child_npc.cohort == "child":
							child_npc.skills["speech"] = minf(100.0, float(child_npc.skills.get("speech", 10.0)) + 0.05)
							child_npc.skills["survival"] = minf(100.0, float(child_npc.skills.get("survival", 10.0)) + 0.03)
				continue

			# Роль 2: Хранитель знаний (10:00 - 17:00)
			if (c.job_id == "knowledge_keeper" or (assigned_lodge != null and assigned_lodge.knowledge_keeper_id == c.citizen_id)) and indiv_hour >= 10.0 and indiv_hour < 17.0 and c.cargo_amount == 0.0:
				c.state = CitizenNPC.State.WORKING
				c.work_timer = randf_range(4.0, 6.0)
				c.ongoing_task_kind = "teaching"
				c.commitment_timer = c.work_timer
				c.last_status_reason = "Обучает молодых ремеслу и мудрости в Круге знаний"
				if randf() < 0.35: c.show_emote("book_01", 3.0, 1)
				if assigned_lodge != null:
					for young_id in assigned_lodge.residents:
						if young_id != c.citizen_id:
							var young_npc = population.get_citizen_by_id(young_id)
							if young_npc != null and young_npc.age < 30:
								assigned_lodge.transfer_knowledge(young_npc, delta * 2.0)
				continue

			# Роль 3: Старейшина рода (09:00 - 18:00)
			if (c.job_id == "clan_elder" or (assigned_lodge != null and assigned_lodge.clan_elder_id == c.citizen_id)) and indiv_hour >= 9.0 and indiv_hour < 18.0 and c.cargo_amount == 0.0:
				c.state = CitizenNPC.State.WORKING
				c.work_timer = randf_range(3.0, 5.0)
				c.ongoing_task_kind = "clan_council"
				c.commitment_timer = c.work_timer
				c.last_status_reason = "Разрешает споры и укрепляет согласие рода"
				if randf() < 0.3: c.show_emote("handshake", 3.0, 1)
				continue
			# 00. Священный обряд погребения и прощания (не прерывается бытовыми делами)
			if c.task_id in ["burial_procession", "funeral_march", "funeral_vigil"]:
				continue

			# 00. Уход за маленьким ребёнком (S07: физическая занятость опекуна)
			if c.cohort in ["adult", "elder"] and c.cargo_amount == 0.0 and c.job_id != "guard":
				var needs_care_child: CitizenNPC = null
				for other in population.citizens:
					if other.cohort == "child" and other.age < 6 and other.guardian_id == c.citizen_id:
						needs_care_child = other
						break
				if needs_care_child != null:
					c.task_id = "care_for_child"
					c.target_pos = needs_care_child.pos
					c.state = CitizenNPC.State.WORKING
					c.work_timer = randf_range(2.0, 4.0)
					c.last_status_reason = "Ухаживает за ребёнком (%s)" % needs_care_child.name
					continue
				
			# 00a. S08: Разумный отдых — измотанный житель отдыхает у костра / дома
			if c.energy < 35.0 and c.job_id != "guard" and c.cohort in ["youth", "adult", "elder"]:
				c.state = CitizenNPC.State.RESTING
				c.work_timer = randf_range(4.0, 8.0)
				c.ongoing_task_kind = "rest"
				c.commitment_timer = c.work_timer
				c.last_status_reason = "Отдыхает (силы на исходе)"
				continue
				
			# 00b. S08: Помощь свободного родственника работающему (без дублирования ресурсов)
			if c.job_id == "idle" and c.cohort in ["youth", "adult"] and c.cargo_amount == 0.0:
				var best_relative: CitizenNPC = null
				var best_dist: float = 999999.0
				for other in population.citizens:
					if other.citizen_id == c.citizen_id:
						continue
					if other.state != CitizenNPC.State.WORKING:
						continue
					if other.task_id == "care_for_child" or other.task_id == "assist_relative":
						continue
					# Проверка родственной связи
					var rel = c.get_relationship(other.citizen_id)
					if rel.is_empty():
						continue
					var d = c.pos.distance_to(other.pos)
					if d < best_dist:
						best_dist = d
						best_relative = other
				if best_relative != null and best_dist < 500.0:
					c.task_id = "assist_relative"
					c.target_id = best_relative.citizen_id
					c.target_pos = best_relative.pos
					c.path = GameManager.nav_grid.find_path(c.pos, best_relative.pos) if GameManager.nav_grid else []
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.ongoing_task_kind = "assist_relative"
					c.commitment_timer = 5.0
					c.last_status_reason = "Идёт помогать %s" % best_relative.name
					continue

			# 0a. Износилась тёплая одежда — сходить на склад за новой, пока есть запас
			if c.warm_clothes < WARM_CLOTHES_REPLACE_AT and c.cargo_amount == 0.0 and economy.get_resource("clothes") >= 1.0:
				var clothes_p = _get_storage_pos(c)
				var clothes_path = GameManager.nav_grid.find_path(c.pos, clothes_p) if GameManager.nav_grid else []
				if not clothes_path.is_empty() or c.pos.distance_to(clothes_p) <= 24.0:
					c.target_pos = clothes_p
					c.task_id = "fetch_clothes"
					c.path = clothes_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт на склад за тёплой одеждой" if not c.is_freezing else "Замерзает! Идёт на склад за тёплой одеждой"
					c.decision_cooldown = 1.0
					continue

			# 0. Домашняя забота о запасе еды (S06: доставка пищи со склада в дом свободными жителями)
			if c.home_id != "" and not c.is_guest and c.cohort in ["youth", "adult"] and c.cargo_amount == 0.0 and c.job_id == "idle":
				var my_home: BuildingInstance = null
				if GameManager.building_instances:
					for h in GameManager.building_instances.values():
						if h.id == c.home_id:
							my_home = h
							break
				if my_home and my_home.food_stockpile < (my_home.food_stockpile_max * 0.5):
					if economy.get_resource("food") >= 2.0:
						var storage_p = _get_storage_pos(c)
						var p_path = GameManager.nav_grid.find_path(c.pos, storage_p) if GameManager.nav_grid else []
						if not p_path.is_empty():
							c.target_pos = storage_p
							c.task_id = "fetch_home_food"
							c.path = p_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.last_status_reason = "Идёт на склад за едой для дома"
							c.decision_cooldown = 1.0
							continue
				
			# Профессии с модулями поведения (src/simulation/professions): охотник, лесоруб,
			# каменотёс, рудокоп, ремесленник, скорняк
			var job_behavior = ProfessionRegistry.get_behavior(c.job_id)
			if job_behavior and job_behavior.pick_task(self, c, delta):
				continue

			# 1. Особая логика для Собирателя (Этап B)
			if c.job_id == "forager" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount >= c.max_carry:
					c.state = CitizenNPC.State.CARRYING
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
					if GameManager.task_service and c.task_instance_id != "":
						GameManager.task_service.set_delivering(c.task_instance_id)
					continue
					
				var f_node = GameManager.resource_manager.find_available_node(pos, "food", 14, c.citizen_id)
				if f_node.is_empty() and GameManager.resource_manager:
					f_node = GameManager.resource_manager.find_available_node(pos, "food", 36, c.citizen_id)
				if not f_node.is_empty():
					var f_path = GameManager.nav_grid.find_adjacent_path(c.pos, f_node["coord"]) if GameManager.nav_grid else []
					if f_path.is_empty() and GameManager.nav_grid:
						f_path = GameManager.nav_grid.find_path(c.pos, f_node["pos"], true)
					if f_path.is_empty() and c.pos.distance_to(f_node["pos"]) <= 36.0:
						f_path = [c.pos]
						
					if f_path.is_empty():
						if GameManager.task_service:
							var blocked_id = GameManager.task_service.create_task("forage_food", f_node.get("id", ""), f_node["coord"], f_node["pos"])
							GameManager.task_service.fail_task(blocked_id, "Нет пути к кусту", true)
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути к ягодным кустам"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					GameManager.resource_manager.reserve_node(f_node["coord"], c.citizen_id)
					c.task_id = "forage_food"
					c.target_coord = f_node["coord"]
					c.target_pos = f_path[-1] if not f_path.is_empty() else f_node["pos"]
					c.target_id = f_node["id"]
					c.path = f_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт к: %s" % f_node["name"]
					c.decision_cooldown = 0.8
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("forage_food", f_node["id"], f_node["coord"], f_node["pos"])
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступных ягодных кустов"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue
				
			# 2a. Рыбак: физический путь к береговому рыбному месту, ловля и доставка
			if c.job_id == "fisherman" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount > 0.0:
					c.state = CitizenNPC.State.CARRYING
					var fish_storage = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, fish_storage)
					c.path_index = 0
					c.last_status_reason = "Несёт %d рыбы в амбар" % int(c.cargo_amount)
					continue
				var fish_node = GameManager.resource_manager.find_available_node(pos, "fish", 24, c.citizen_id) if GameManager.resource_manager else {}
				if fish_node.is_empty():
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступных рыбных мест"
					c.decision_cooldown = randf_range(3.0, 5.0)
					continue
				var fish_path = GameManager.nav_grid.find_adjacent_path(c.pos, fish_node["coord"]) if GameManager.nav_grid else []
				if fish_path.is_empty() and GameManager.nav_grid:
					fish_path = GameManager.nav_grid.find_path(c.pos, fish_node["pos"], true)
				if fish_path.is_empty() and c.pos.distance_to(fish_node["pos"]) <= 48.0:
					fish_path = [c.pos]
					
				if fish_path.is_empty():
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет пути к рыбному месту"
					c.decision_cooldown = randf_range(2.0, 4.0)
					continue
				GameManager.resource_manager.reserve_node(fish_node["coord"], c.citizen_id)
				c.task_id = "fish"
				c.target_coord = fish_node["coord"]
				c.target_pos = fish_path[-1] if not fish_path.is_empty() else fish_node["pos"]
				c.target_id = fish_node["id"]
				c.path = fish_path
				c.path_index = 0
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Идёт к рыбному месту"
				c.decision_cooldown = 0.8
				if GameManager.task_service:
					var fish_task_id = GameManager.task_service.create_task("fish", fish_node["id"], fish_node["coord"], fish_node["pos"])
					GameManager.task_service.assign_actor(fish_task_id, c.citizen_id)
					c.task_instance_id = fish_task_id
				continue

			# 6. Особая логика для Строителя (S05: реальная доставка материалов, стройка и улучшения)
			if c.job_id == "builder" and c.cohort in ["youth", "adult", "elder"]:
				_try_assign_construction_task(c)
				continue

			# 8. Особая логика для Стражника (Этап E)
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
				
			# 8b. Особая логика для Строителя
			if c.job_id == "builder" and c.cohort in ["youth", "adult", "elder"]:
				_try_assign_construction_task(c)
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
				# 10. Свободные трудоспособные жители помогают на стройках в первую очередь!
				if c.cohort in ["youth", "adult"] and (c.job_id in ["idle", ""] or c.workplace_id == ""):
					if not construction_queue.is_empty() and _try_assign_construction_task(c):
						continue

				# 10a. Свободные трудоспособные жители переносят древесину из лагеря лесорубов на склад при накоплении буфера
				if c.cohort in ["youth", "adult"] and c.job_id == "idle":
					var camp_idle = get_active_woodcutter_camp()
					if camp_idle and camp_idle.local_buffer_wood >= 10.0:
						var take_amt = camp_idle.take_wood(c.max_carry)
						if take_amt > 0.0:
							c.cargo_type = "wood"
							c.cargo_amount = take_amt
							c.task_id = "haul_from_camp"
							c.state = CitizenNPC.State.CARRYING
							var s_pos = _get_storage_pos(c)
							c.path = GameManager.nav_grid.find_path(c.pos, s_pos) if GameManager.nav_grid else []
							c.path_index = 0
							c.last_status_reason = "Несёт %d дров из лагеря на склад" % int(take_amt)
							continue

				# 10b. Автоматическое устройство на работу в действующие здания (каменоломни, охотники, шахты, мастерские и др.)
				if c.cohort in ["youth", "adult"] and (c.job_id in ["idle", ""] and c.workplace_id == ""):
					if _try_auto_assign_single_citizen(c):
						c.decision_cooldown = 0.0
						continue

				# 11. Свободные жители, дети и старики (Этап D / Живая симуляция)
				# 11a. Примирение со старыми обидчиками при остывшем гневе
				if (c.has_memory("grudge") or c.has_memory("offense")) and randf() < 0.25:
					if _try_reconcile_quarrel(c):
						continue

				# 11b. Свидание и прогулка для влюбленных пар / супругов
				if (c.spouse_id != "" or c.cohort in ["youth", "adult"]) and randf() < 0.22:
					if _try_start_dating_walk(c):
						continue

				# 11c. Поход в гости к соседям / друзьям / родителям / старейшинам
				if randf() < 0.28:
					if _try_visit_friend(c):
						continue

				# 11d. Ласка и игра с прирученными животными
				if randf() < 0.20:
					if _try_pet_animal(c):
						continue

				# 11e. Личные украшения поселения: кусты, таблички, скамейки, идолы, мусор, уборка
				if c.cohort in ["adult", "youth", "elder"] and c.cargo_amount == 0.0 and c.energy > 30.0 and indiv_hour >= 9.0 and indiv_hour < 18.0:
					_try_personal_decoration_action(c)
					if c.state != CitizenNPC.State.IDLE and c.state != CitizenNPC.State.WAITING:
						continue

				var partner = _find_chat_partner(c)
				if partner != null and randf() < 0.55:
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

func _get_materials_in_transit(target_coord: Vector2i, res_name: String, exclude_citizen: CitizenNPC = null) -> float:
	var total: float = 0.0
	for other in population.citizens:
		if other == exclude_citizen:
			continue
		if other.target_coord == target_coord:
			if other.task_id in ["haul_to_site", "haul_to_upgrade"] and other.cargo_type == res_name:
				total += other.cargo_amount
			elif other.task_id in ["fetch_materials", "fetch_upgrade_materials"] and other.target_id == res_name:
				total += other.max_carry
	return total

func _try_assign_construction_task(c: CitizenNPC) -> bool:
	# 1. Если уже держит груз стройматериалов в руках — несёт на площадку
	if c.cargo_amount > 0.0:
		if c.task_id == "haul_to_site" and c.target_coord != Vector2i(-1, -1):
			c.state = CitizenNPC.State.CARRYING
			c.target_pos = GameManager.nav_grid.tile_to_world_center(c.target_coord)
			c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
			c.path_index = 0
			c.last_status_reason = "Несёт %d %s на стройплощадку" % [int(c.cargo_amount), c.cargo_type]
			return true
		elif c.task_id == "haul_to_upgrade" and c.target_coord != Vector2i(-1, -1):
			c.state = CitizenNPC.State.CARRYING
			c.target_pos = GameManager.nav_grid.tile_to_world_center(c.target_coord)
			c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
			c.path_index = 0
			c.last_status_reason = "Несёт %d %s для улучшения здания" % [int(c.cargo_amount), c.cargo_type]
			return true

	var missing_warehouse_res = ""

	# 2. Поиск доставки материалов для всех строек в очереди (не зависаем на первом проекте!)
	var camp = get_active_woodcutter_camp()
	for item in construction_queue:
		var q_c = item.get("coord", Vector2i(-1, -1))
		if q_c != Vector2i(-1, -1) and GameManager.tile_buildings.has(q_c):
			var b = GameManager.tile_buildings[q_c]
			if b.get("status", "") == "constructing":
				var req = b.get("materials_required", {})
				var deliv = b.get("materials_delivered", {})
				for r in req:
					var already_delivered = float(deliv.get(r, 0.0))
					var in_transit = _get_materials_in_transit(q_c, r, c)
					var needed = float(req[r]) - (already_delivered + in_transit)
					if needed > 0.0:
						var in_storage = economy.get_resource(r)
						var wood_in_camp = camp.local_buffer_wood if (camp and r == "wood") else 0.0
						if in_storage >= 1.0 or wood_in_camp >= 1.0:
							var fetch_p = _get_storage_pos(c)
							var is_from_camp = false
							if in_storage < 1.0 and wood_in_camp >= 1.0 and camp:
								fetch_p = GameManager.nav_grid.tile_to_world_center(camp.pos) if GameManager.nav_grid else Vector2(camp.pos.x * 32.0 + 16, camp.pos.y * 32.0 + 16)
								is_from_camp = true
							elif wood_in_camp >= 10.0 and camp:
								fetch_p = GameManager.nav_grid.tile_to_world_center(camp.pos) if GameManager.nav_grid else Vector2(camp.pos.x * 32.0 + 16, camp.pos.y * 32.0 + 16)
								is_from_camp = true
							
							var p_path = GameManager.nav_grid.find_path(c.pos, fetch_p) if GameManager.nav_grid else []
							if p_path.is_empty():
								continue
							c.target_pos = fetch_p
							c.target_coord = q_c
							c.target_id = r
							c.task_id = "fetch_materials"
							c.path = p_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							if is_from_camp:
								c.last_status_reason = "Идёт в лагерь лесорубов за деревом для стройки"
							else:
								c.last_status_reason = "Идёт на склад за стройматериалами (%s)" % r
							c.decision_cooldown = 0.8
							if GameManager.task_service:
								var tid = GameManager.task_service.create_task("haul_materials", b.get("id", ""), q_c, fetch_p)
								GameManager.task_service.assign_actor(tid, c.citizen_id)
								c.task_instance_id = tid
							return true
						else:
							if missing_warehouse_res == "":
								missing_warehouse_res = r

	# 3. Физическая работа на стройплощадках, где все материалы уже доставлены
	for item in construction_queue:
		var q_c = item.get("coord", Vector2i(-1, -1))
		if q_c != Vector2i(-1, -1) and GameManager.tile_buildings.has(q_c):
			var b = GameManager.tile_buildings[q_c]
			if b.get("status", "") == "constructing" and float(b.get("days_left", 1.0)) > 0.0:
				var req = b.get("materials_required", {})
				var deliv = b.get("materials_delivered", {})
				var all_delivered = true
				for r in req:
					if float(deliv.get(r, 0.0)) < float(req[r]):
						all_delivered = false
						break
				if all_delivered:
					var site_p = GameManager.nav_grid.tile_to_world_center(q_c) if GameManager.nav_grid else Vector2.ZERO
					var s_path = GameManager.nav_grid.find_adjacent_path(c.pos, q_c) if GameManager.nav_grid else []
					if s_path.is_empty() and GameManager.nav_grid:
						s_path = GameManager.nav_grid.find_path(c.pos, site_p, true)
					if s_path.is_empty() and c.pos.distance_to(site_p) <= 36.0:
						s_path = [c.pos]
					if s_path.is_empty():
						DebugLogger.log_warn("Builder", "Строитель %s не нашел путь к стройплощадке %s на %s" % [c.name, b.get("id", ""), q_c])
						continue
					c.target_coord = q_c
					c.target_pos = site_p
					c.task_id = "build"
					c.path = s_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт строить: %s" % b.get("id", "")
					c.decision_cooldown = 0.8
					DebugLogger.log_info("Builder", "Строитель %s назначен на стройку %s на %s" % [c.name, b.get("id", ""), q_c])
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("build", b.get("id", ""), q_c, site_p)
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
					return true

	# 4. Поиск активных улучшений зданий
	if GameManager.building_instances:
		for b_inst in GameManager.building_instances.values():
			if b_inst and b_inst.has_pending_upgrade():
				var up = b_inst.pending_upgrade
				var req = up.get("materials_required", {})
				var deliv = up.get("materials_delivered", {})
				for r in req:
					var already_delivered = float(deliv.get(r, 0.0))
					var in_transit = _get_materials_in_transit(b_inst.pos, r, c)
					var needed = float(req[r]) - (already_delivered + in_transit)
					if needed > 0.0:
						var in_storage = economy.get_resource(r)
						var wood_in_camp = camp.local_buffer_wood if (camp and r == "wood") else 0.0
						if in_storage >= 1.0 or wood_in_camp >= 1.0:
							var fetch_p = _get_storage_pos(c)
							var is_from_camp = false
							if in_storage < 1.0 and wood_in_camp >= 1.0 and camp:
								fetch_p = GameManager.nav_grid.tile_to_world_center(camp.pos) if GameManager.nav_grid else Vector2(camp.pos.x * 32.0 + 16, camp.pos.y * 32.0 + 16)
								is_from_camp = true
							elif wood_in_camp >= 10.0 and camp:
								fetch_p = GameManager.nav_grid.tile_to_world_center(camp.pos) if GameManager.nav_grid else Vector2(camp.pos.x * 32.0 + 16, camp.pos.y * 32.0 + 16)
								is_from_camp = true
							
							var p_path = GameManager.nav_grid.find_path(c.pos, fetch_p) if GameManager.nav_grid else []
							if p_path.is_empty():
								continue
							c.target_pos = fetch_p
							c.target_coord = b_inst.pos
							c.target_id = r
							c.task_id = "fetch_upgrade_materials"
							c.path = p_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							if is_from_camp:
								c.last_status_reason = "Идёт в лагерь лесорубов за деревом для улучшения"
							else:
								c.last_status_reason = "Идёт на склад за материалами для улучшения (%s)" % r
							c.decision_cooldown = 0.8
							return true
						else:
							if missing_warehouse_res == "":
								missing_warehouse_res = r

				var all_up_delivered = true
				for r in req:
					if float(deliv.get(r, 0.0)) < float(req[r]):
						all_up_delivered = false
						break
				if all_up_delivered:
					var b_pos = GameManager.nav_grid.tile_to_world_center(b_inst.pos) if GameManager.nav_grid else Vector2.ZERO
					var s_path = GameManager.nav_grid.find_path(c.pos, b_pos) if GameManager.nav_grid else []
					if s_path.is_empty():
						continue
					c.target_coord = b_inst.pos
					c.target_pos = b_pos
					c.task_id = "upgrade_work"
					c.path = s_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт улучшать здание (%s)" % up.get("id", "")
					c.decision_cooldown = 0.8
					return true

	# Если задач нет:
	if c.job_id == "builder":
		if missing_warehouse_res != "":
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Стройка остановлена: нет материалов на складе (%s)" % missing_warehouse_res
			c.decision_cooldown = randf_range(2.0, 4.0)
			if GameManager.task_service and c.task_instance_id != "":
				GameManager.task_service.fail_task(c.task_instance_id, "Нехватка материалов", true)
				c.task_instance_id = ""
		else:
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Нет активных строек"
			c.decision_cooldown = randf_range(3.0, 5.0)

	return false

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
		"tanner": return "Скорняжня"
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
		"tanner": return "Выделывает шкуры"
		"sage": return "Размышляет в совете"
		"priest": return "Творит священный обряд"
		"guard": return "Охраняет поселение"
		"warrior": return "Отрабатывает удары"
		_: return "Занят делом"

# --- Тёплая одежда и холод ---
const WARM_CLOTHES_MAX: float = 100.0
const WARM_CLOTHES_REPLACE_AT: float = 25.0
const WARM_CLOTHES_FREEZE_AT: float = 10.0
const WARM_CLOTHES_WEAR_WINTER: float = 0.05 # в секунду (≈22 за зиму)
const WARM_CLOTHES_WEAR_OTHER: float = 0.01 # в секунду в тёплые сезоны
const COLD_ENERGY_DRAIN: float = 0.15 # доп. потеря сил в секунду
const COLD_HEALTH_DRAIN: float = 0.02 # потеря здоровья в секунду

# Одежда изнашивается; зимой житель без тёплой одежды мёрзнет, если он не под крышей дома
func _apply_weather_and_clothing(c: CitizenNPC, season: String, delta: float) -> void:
	var wear = WARM_CLOTHES_WEAR_WINTER if season == "Зима" else WARM_CLOTHES_WEAR_OTHER
	if c.warm_clothes > 0.0:
		c.warm_clothes = maxf(0.0, c.warm_clothes - wear * delta)
	if season != "Зима" or c.warm_clothes > WARM_CLOTHES_FREEZE_AT:
		c.is_freezing = false
		return
	var at_home = c.home_id != "" and c.home_pos != Vector2.ZERO and (c.state == CitizenNPC.State.SLEEPING or c.pos.distance_to(c.home_pos) <= 22.0)
	c.is_freezing = not at_home
	if c.is_freezing:
		c.energy = maxf(0.0, c.energy - COLD_ENERGY_DRAIN * delta)
		c.health = maxf(0.0, c.health - COLD_HEALTH_DRAIN * delta)
		if c.health <= 0.0 and c.death_cause == "":
			c.death_cause = "Замёрз зимой без тёплой одежды"

# --- Диспетчеры модулей профессий (src/simulation/professions) ---

# Стройка общая для всех: жителя на задаче стройки ведёт логика строителя, а не его профессия
const CONSTRUCTION_TASKS: Array[String] = ["build", "upgrade_work", "fetch_materials", "fetch_upgrade_materials", "haul_to_site", "haul_to_upgrade"]

func _get_job_behavior(c: CitizenNPC) -> ProfessionBehavior:
	if c.task_id in CONSTRUCTION_TASKS:
		return null
	return ProfessionRegistry.get_behavior(c.job_id)

func _profession_arrived(c: CitizenNPC) -> bool:
	var b = _get_job_behavior(c)
	return b != null and b.on_arrived(self, c)

func _profession_work_done(c: CitizenNPC) -> bool:
	var b = _get_job_behavior(c)
	return b != null and b.on_work_done(self, c)

func _profession_cargo_delivered(c: CitizenNPC) -> bool:
	# Туша разделывается в лагере, кто бы её ни донёс
	if c.cargo_type == "carcass":
		return ProfessionRegistry.get_behavior("hunter").on_cargo_delivered(self, c)
	var b = _get_job_behavior(c)
	return b != null and b.on_cargo_delivered(self, c)

func is_player_settlement() -> bool:
	return faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "player_tribe_settlement" or id == "test_s"

func _find_chat_partner(citizen: CitizenNPC) -> CitizenNPC:
	if citizen.social_cooldown > 0.0:
		return null
	if citizen.job_id != "idle" and citizen.cohort in ["youth", "adult"]:
		return null
	
	var best_partner: CitizenNPC = null
	var best_score: float = -9999.0
	
	for other in population.citizens:
		if other == citizen:
			continue
		if other.social_cooldown > 0.0:
			continue
		if not (other.job_id == "idle" or other.cohort in ["child", "elder"]):
			continue
		if not other.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING]:
			continue
		if other.pos.distance_to(citizen.pos) >= 70.0:
			continue
		
		# Скоринг: предпочитаем тех, кого знаем и к кому есть чувства
		var score = 0.0
		var aff = citizen.get_relationship_affinity(other.citizen_id)
		score += aff * 0.5  # знакомые предпочтительнее

		# Высокая общительность тянется к людям
		score += (float(citizen.traits.get("sociability", 50.0)) - 50.0) * 0.1

		# Ненавидящие — не стремятся, но могут поссориться
		if aff < -40.0:
			score -= 30.0 + (float(citizen.traits.get("temper", 20.0)) - 50.0) * 0.3

		# Дети и старики интереснее для empathy-персонажей
		if other.cohort in ["child", "elder"] and float(citizen.traits.get("empathy", 50.0)) > 60.0:
			score += 15.0

		if score > best_score:
			best_score = score
			best_partner = other
	
	return best_partner

func _start_social_dialog(c1: CitizenNPC, c2: CitizenNPC) -> void:
	c1.facing_dir = (c2.pos - c1.pos).normalized()
	c2.facing_dir = (c1.pos - c2.pos).normalized()
	c1.state = CitizenNPC.State.TALKING
	c2.state = CitizenNPC.State.TALKING
	c1.action_timer = 4.5
	c2.action_timer = 4.5
	c1.social_cooldown = randf_range(15.0, 30.0)
	c2.social_cooldown = randf_range(15.0, 30.0)
	c1.talk_partner_id = c2.citizen_id
	c2.talk_partner_id = c1.citizen_id

	# --- Умные диалоги по чертам, отношениям и воспоминаниям ---
	var aff = c1.get_relationship_affinity(c2.citizen_id)
	var ph1: String
	var ph2: String
	var emote1: String = "dialog"
	var emote2: String = "dialog"

	# Семейный кризис и развод при разрушенных отношениях супругов
	if c1.spouse_id == c2.citizen_id and (aff < -15.0 or c1.has_memory("grudge")):
		ph1 = "Мы больше не можем быть вместе, %s. Наш союз расторгнут!" % c2.name
		ph2 = "И слава предкам! Забирай свои вещи и уходи."
		emote1 = "broken_heart"
		emote2 = "disgust"
		c1.spouse_id = ""
		c2.spouse_id = ""
		# Союз действительно расторгнут: иначе get_spouses() продолжает считать их супругами
		for pair in [[c1, c2], [c2, c1]]:
			var div_rel: Dictionary = pair[0].relationships.get(pair[1].citizen_id, {})
			if not div_rel.is_empty():
				div_rel["married"] = false
				div_rel["type"] = "ex_spouse"
				div_rel["romance"] = 0.0
		c1.modify_relationship(c2.citizen_id, -25.0, -50.0)
		c2.modify_relationship(c1.citizen_id, -25.0, -50.0)
		c1.add_memory("divorce", "breakup", c2.citizen_id, 3.5, "Развёлся с %s после тяжёлой ссоры" % c2.name)
		c2.add_memory("divorce", "breakup", c1.citizen_id, 3.5, "Развелась с %s после тяжёлой ссоры" % c1.name)
		_relocate_divorced_spouse(c2)
		EventBus.notification_toast.emit("💔 Расторжение союза", "%s и %s расторгли союз и разъехались" % [c1.name, c2.name], "info")

	# Острый спор, обида и возможность потасовки
	elif (float(c1.traits.get("temper", 50.0)) > 60.0 or float(c2.traits.get("temper", 50.0)) > 60.0 or float(c1.traits.get("pride", 50.0)) > 65.0) and aff < 15.0:
		ph1 = _pick_phrase(c1, [
			"Не смей указывать мне, %s!" % c2.name,
			"Твоя гордыня переходит все границы!",
			"Ты присвоил общую добычу и думаешь, никто не заметил?!",
			"С меня довольно твоих упрёков!"
		])
		ph2 = _pick_phrase(c2, [
			"А ты не зарывайся! Я знаю своё место, а ты — своё!",
			"Посмотрим, что на это скажут старейшины!",
			"Не бросайся словами, если не можешь ответить!",
			"Ты сам во всём виноват!"
		])
		emote1 = "anger"
		emote2 = "quarrel"
		c1.modify_relationship(c2.citizen_id, -8.0, 0.0)
		c2.modify_relationship(c1.citizen_id, -8.0, 0.0)
		c1.add_memory("grudge", "offense", c2.citizen_id, 2.5, "Обиделся на %s после перепалки" % c2.name)
		c2.add_memory("grudge", "offense", c1.citizen_id, 2.5, "Затаил обиду на %s" % c1.name)
		
		# Эскалация в кулачный бой при горячем нраве обоих
		if float(c1.traits.get("temper", 50.0)) > 65.0 and float(c2.traits.get("temper", 50.0)) > 65.0 and (float(c1.traits.get("temper", 50.0)) >= 75.0 or randf() < 0.40):
			c1.task_id = "brawling"
			c2.task_id = "brawling"
			c1.action_timer = 4.5
			c2.action_timer = 4.5
			c1.state = CitizenNPC.State.ATTACKING
			c2.state = CitizenNPC.State.ATTACKING
			c1.take_damage(6.0, "Потасовка с %s" % c2.name)
			c2.take_damage(6.0, "Потасовка с %s" % c1.name)
			c1.show_emote("fight", 4.0, 4)
			c2.show_emote("fight", 4.0, 4)
			c1.last_status_reason = "Сцепился в потасовке с %s!" % c2.name
			c2.last_status_reason = "Сцепился в потасовке с %s!" % c1.name
			EventBus.notification_toast.emit("⚔ Потасовка!", "%s и %s сцепились в драке на улице!" % [c1.name, c2.name], "warning")
			for g in population.citizens:
				if g.is_alive and g.job_id in ["guard", "warrior"] and g.pos.distance_to(c1.pos) <= 180.0:
					g.task_id = "stop_brawl"
					g.target_pos = c1.pos
					g.path = GameManager.nav_grid.find_path(g.pos, c1.pos) if GameManager and GameManager.nav_grid else []
					g.path_index = 0
					g.state = CitizenNPC.State.MOVING_TO_WORK
					g.last_status_reason = "Спешит разнять драку между соплеменниками"
					g.shout("Прекратить драку! Оружие к ноге!", 3.5)
					break

	# Дружеские подарки и проявление чуткости
	elif float(c1.traits.get("empathy", 50.0)) > 60.0 and aff >= 20.0 and (float(c1.traits.get("empathy", 50.0)) >= 75.0 or randf() < 0.35) and _try_give_gift(c1, c2) != "":
		# Подарок настоящий: вещь или еда действительно переходят от дарителя к получателю
		var gift_desc: String = c1.custom_data.get("last_gift", "")
		ph1 = "Я приберёг это для тебя, %s: %s. Пусть служит тебе на пользу." % [c2.name, gift_desc]
		ph2 = "Какая щедрость, %s! Я не забуду этого." % c1.name
		emote1 = "gift"
		emote2 = "joy"
		c1.modify_relationship(c2.citizen_id, 8.0, 4.0)
		c2.modify_relationship(c1.citizen_id, 8.0, 4.0)
		c2.loyalty = minf(100.0, c2.loyalty + 4.0)
		c1.add_memory("gift", "friendship", c2.citizen_id, 1.5, "Подарил соплеменнику %s: %s" % [c2.name, gift_desc])
		c2.add_memory("gift_received", "friendship", c1.citizen_id, 1.2, "Получил в дар от %s: %s" % [c1.name, gift_desc])

	# Враги / антипатия
	elif aff < -35.0:
		var hostile1 = _pick_phrase(c1, [
			"Держись подальше от меня, %s." % c2.name,
			"С тобой я не хочу говорить.",
			"Ты знаешь, что я о тебе думаю.",
			"Зачем ты подошёл ко мне?",
		])
		var hostile2 = _pick_phrase(c2, [
			"Взаимно. Не навязывайся.",
			"Я тоже помню всё, что ты сделал.",
			"Мы можем не разговаривать.",
			"Ты мне не нравишься, %s." % c1.name,
		])
		ph1 = hostile1
		ph2 = hostile2
		emote1 = "anger" if randf() < 0.5 else "disgust"
		emote2 = "discontent" if randf() < 0.5 else "skepticism"
		# Негатив усиливается от встречи
		c1.modify_relationship(c2.citizen_id, -3.0, 0.0)
		c2.modify_relationship(c1.citizen_id, -3.0, 0.0)
		c1.add_memory("social", c2.citizen_id, "", 0.4, "Неприятный разговор с %s" % c2.name)
		c2.add_memory("social", c1.citizen_id, "", 0.4, "Неприятный разговор с %s" % c1.name)

	# Близкие / супруги / друзья
	elif aff >= 50.0 or c1.spouse_id == c2.citizen_id:
		var warm1 = _pick_phrase_by_trait(c1, c2, "warm")
		var warm2 = _pick_phrase_by_trait(c2, c1, "warm")
		ph1 = warm1
		ph2 = warm2
		emote1 = "sympathy" if randf() < 0.6 else "joy"
		emote2 = "sympathy" if randf() < 0.6 else "calm"
		c1.modify_relationship(c2.citizen_id, 2.0, 1.0)
		c2.modify_relationship(c1.citizen_id, 2.0, 1.0)

	# Нейтральное знакомство
	else:
		ph1 = _pick_phrase_by_trait(c1, c2, "neutral")
		ph2 = _pick_phrase_by_trait(c2, c1, "neutral")
		emote1 = "dialog"
		emote2 = "thought" if randf() < 0.3 else "dialog"
		c1.modify_relationship(c2.citizen_id, 1.0, 0.0)
		c2.modify_relationship(c1.citizen_id, 1.0, 0.0)

	# Воспоминания: если c1 помнит что-то плохое о c2 — может упомянуть
	if c1.has_memory_of(c2.citizen_id, "injury") or c1.has_memory_of(c2.citizen_id, "disappointment"):
		if randf() < 0.4:
			ph1 = "Я ещё не забыл, что ты сделал, %s." % c2.name
			emote1 = "suspicion"

	# Gossiping: любопытные / общительные сплетничают
	var gossip_chance = (float(c1.traits.get("sociability", 50.0)) + float(c1.traits.get("curiosity", 50.0))) / 200.0
	if randf() < gossip_chance * 0.4 and not population.citizens.is_empty():
		var subject = _pick_gossip_subject(c1, c2)
		if subject != "":
			ph1 = subject
			emote1 = "gossip"

	c1.shout(ph1, 4.5)
	c2.shout(ph2, 4.5)
	c1.show_emote(emote1, 3.5, 2)
	c2.show_emote(emote2, 3.5, 2)
	c1.last_status_reason = "Беседует с " + c2.name
	c2.last_status_reason = "Беседует с " + c1.name

	# --- Романтика и брак (S07) ---
	if c1.age >= 18 and c2.age >= 18 and not c1.is_related_to(c2):
		if c1.gender != c2.gender:
			var r1 = c1.get_relationship(c2.citizen_id)
			var r_romance = float(r1.get("romance", 0.0)) + 20.0
			c1.add_relationship(c2.citizen_id, r1.get("type", "friend"), 60.0, r_romance, r1.get("married", false))
			c2.add_relationship(c1.citizen_id, r1.get("type", "friend"), 60.0, r_romance, r1.get("married", false))

			if r_romance >= 50.0 and not r1.get("married", false):
				if c1.can_marry(c2, marriage_law).get("allowed", false):
					c1.marry(c2, marriage_law)
					c1.shout("Мы решили быть вместе!", 4.0)
					c2.shout("Мы связали наши судьбы!", 4.0)
					c1.show_emote("marriage", 4.0, 4)
					c2.show_emote("marriage", 4.0, 4)
					EventBus.notification_toast.emit("Новый союз", "%s и %s заключили союз" % [c1.name, c2.name], "good")
					auto_assign_housing()

			var female_partner = c1 if c1.gender == "f" else c2
			var male_partner = c2 if c1.gender == "f" else c1
			if female_partner.get_spouses().has(male_partner.citizen_id) and not female_partner.is_pregnant():
				if female_partner.age >= 18 and female_partner.age <= 42 and randf() < 0.25:
					start_pregnancy(female_partner, male_partner)

# Настоящий подарок: даритель отдаёт то, что у него реально есть. Возвращает описание дара
# (и кладёт его в custom_data["last_gift"]) или "" — если дарить нечего, подарка не будет.
func _try_give_gift(giver: CitizenNPC, receiver: CitizenNPC) -> String:
	var desc = ""
	var giver_home = get_citizen_home_instance(giver)
	var receiver_home = get_citizen_home_instance(receiver)
	var giver_food = giver_home.food_stockpile if giver_home else 0.0
	# 1. Голодному — еду из своих домашних запасов, съедается сразу
	if receiver.hunger < 60.0 and giver_food >= 1.0:
		giver_home.food_stockpile -= 1.0
		receiver.hunger = minf(100.0, receiver.hunger + 20.0)
		desc = "еду из своих запасов"
	# 2. Мёрзнущему — свою тёплую одежду, если у самого она крепкая
	elif receiver.warm_clothes < WARM_CLOTHES_REPLACE_AT and giver.warm_clothes >= 70.0:
		var shared = giver.warm_clothes * 0.5
		giver.warm_clothes -= shared
		receiver.warm_clothes = minf(WARM_CLOTHES_MAX, receiver.warm_clothes + shared)
		receiver.is_freezing = false
		desc = "тёплую накидку"
	# 3. Гостинец в чужой дом из своего
	elif giver_food >= 2.0 and receiver_home and receiver_home != giver_home and receiver_home.food_stockpile < receiver_home.food_stockpile_max:
		giver_home.food_stockpile -= 1.0
		receiver_home.store_food(1.0)
		desc = "гостинец для семьи"
	giver.custom_data["last_gift"] = desc
	return desc

func _relocate_divorced_spouse(c: CitizenNPC) -> void:
	var h_inst = get_citizen_home_instance(c)
	if h_inst:
		h_inst.remove_resident(c.citizen_id)
	c.home_id = ""
	c.home_coord = Vector2i(-1, -1)
	c.home_pos = Vector2.ZERO
	auto_assign_housing()

# Выбор фразы по одной черте личности (для случайного выбора)
func _pick_phrase(c: CitizenNPC, pool: Array) -> String:
	if pool.is_empty():
		return "..."
	# Используем seed персонажа + случайность для детерминированного, но живого выбора
	return pool[(c.seed_val + randi()) % pool.size()]

# Умный выбор фразы по типу разговора и чертам говорящего
func _pick_phrase_by_trait(speaker: CitizenNPC, listener: CitizenNPC, mode: String) -> String:
	var diligence = float(speaker.traits.get("diligence", 50.0))
	var tradition = float(speaker.traits.get("tradition", 50.0))
	var empathy = float(speaker.traits.get("empathy", 50.0))
	var bravery = float(speaker.traits.get("bravery", 50.0))
	var curiosity = float(speaker.traits.get("curiosity", 50.0))
	var sociability = float(speaker.traits.get("sociability", 50.0))
	var temper = float(speaker.traits.get("temper", 20.0))
	var honesty = float(speaker.traits.get("honesty", 50.0))

	if mode == "warm":
		if speaker.spouse_id == listener.citizen_id:
			return ["Рад видеть тебя, %s." % listener.name,
					"Как ты сегодня, %s?" % listener.name,
					"Я думал о тебе весь день.",
					"Вместе нам всё по плечу."][randi() % 4]
		if empathy > 65.0:
			return ["Как ты себя чувствуешь?",
					"Если тебе нужна помощь — я рядом.",
					"Рад тебя видеть, %s." % listener.name][randi() % 3]
		if tradition > 65.0:
			return ["Предки хранят наш очаг и наши дружбы.",
					"Мы из одного рода — это крепкая связь.",
					"Старые друзья — самые надёжные."][randi() % 3]
		if sociability > 65.0:
			return ["Как дела? Давно не разговаривали!",
					"Хорошо, что встретились.",
					"Всегда рад поболтать с тобой, %s." % listener.name][randi() % 3]
		return ["Рад видеть тебя.",
				"Всё хорошо у тебя?",
				"Держимся вместе."][randi() % 3]

	# Нейтральный разговор
	if diligence > 65.0:
		return ["Работы не убавляется — я в деле.",
				"Лучше трудиться, чем сидеть без дела.",
				"Запасы сами себя не соберут."][randi() % 3]
	if curiosity > 65.0:
		return ["Ты слышал, что происходит?",
				"Интересно, что будет дальше с племенем.",
				"Я всё думаю, как бы улучшить наш лагерь."][randi() % 3]
	if tradition > 65.0:
		return ["Предки хранят наш огонь.",
				"Так жили наши деды — и мы не хуже.",
				"Нельзя забывать старые обычаи."][randi() % 3]
	if temper > 65.0:
		return ["Надоело всё, если честно.",
				"Не лезь ко мне сегодня.",
				"Что тебе нужно?"][randi() % 3]
	if bravery > 65.0:
		return ["Видел медведя у опушки — не испугался.",
				"Самое время для новых вылазок.",
				"Опасность меня не пугает."][randi() % 3]
	if honesty > 75.0:
		return ["Скажу прямо: нам нужно больше еды.",
				"Если честно, мне нравится здесь.",
				"Не буду лукавить — нелегко нам приходится."][randi() % 3]

	# Универсальные нейтральные
	var general = [
		"Славная погода сегодня.",
		"В лесу полно дичи.",
		"Запасы племени растут.",
		"Огонь очага греет душу.",
		"Как у тебя дела?",
		"Нужно держаться вместе.",
		"Предки хранят наше племя.",
	]
	return general[randi() % general.size()]

# Сплетня: говорящий упоминает третьего персонажа
func _pick_gossip_subject(speaker: CitizenNPC, _listener: CitizenNPC) -> String:
	if not population:
		return ""
	# Ищем кого-то кого знает говорящий с заметной репутацией
	for other in population.citizens:
		if other == speaker or other == _listener:
			continue
		var aff = speaker.get_relationship_affinity(other.citizen_id)
		if aff < -30.0:
			return "Скажу тебе — %s мне совсем не нравится." % other.name
		if aff > 60.0 and other.job_id != "idle":
			return "%s работает лучше всех в поселении." % other.name
		if other.cohort == "elder" and float(speaker.traits.get("tradition", 50.0)) > 60.0:
			return "Старейшина %s — мудрый человек." % other.name
	return ""

# --- ЖИВАЯ СОЦИАЛЬНАЯ СИМУЛЯЦИЯ (ПОХОДЫ В ГОСТИ, РОМАНТИКА, СВИДАНИЯ, ПРИМИРЕНИЯ, ПИТОМЦЫ) ---
func _try_visit_friend(c: CitizenNPC) -> bool:
	if not population or population.citizens.is_empty():
		return false
	var candidates: Array[CitizenNPC] = []
	for other in population.citizens:
		if other == c or not other.is_alive:
			continue
		if other.home_id == "" or other.home_pos == Vector2.ZERO:
			continue
		if other.home_id == c.home_id and c.home_id != "":
			continue
		var aff = c.get_relationship_affinity(other.citizen_id)
		var is_kin = c.is_related_to(other)
		var is_elder = (other.cohort == "elder")
		if aff >= 15.0 or is_kin or is_elder:
			candidates.append(other)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b):
		var aff_a = c.get_relationship_affinity(a.citizen_id) + (20.0 if c.is_related_to(a) else 0.0)
		var aff_b = c.get_relationship_affinity(b.citizen_id) + (20.0 if c.is_related_to(b) else 0.0)
		return aff_a > aff_b
	)
	var host = candidates[0]
	var target_porch = host.home_pos + Vector2(randf_range(-12.0, 12.0), randf_range(2.0, 8.0))
	var v_path: Array[Vector2] = GameManager.nav_grid.find_path(c.pos, target_porch) if GameManager and GameManager.nav_grid else []
	if v_path.is_empty():
		v_path.append(target_porch)
	c.task_id = "visit_friend_home"
	c.target_id = host.citizen_id
	c.target_pos = target_porch
	c.target_coord = host.home_coord
	c.path = v_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.last_status_reason = "Идёт в гости к %s" % host.name
	c.decision_cooldown = 1.0
	return true

# Свободен для досуга: не занят делом (визит на могилу, рыбалка и т.п. тоже идут в RESTING)
func _is_free_for_leisure(c: CitizenNPC) -> bool:
	return c.state in [CitizenNPC.State.IDLE, CitizenNPC.State.WAITING] or (c.state == CitizenNPC.State.RESTING and c.task_id == "")

func _try_start_dating_walk(c: CitizenNPC) -> bool:
	if not population or population.citizens.is_empty():
		return false
	if c.cohort not in ["youth", "adult"]:
		return false
	var partner: CitizenNPC = null
	# Если уже состоит в браке — идёт на прогулку с супругом
	if c.spouse_id != "":
		var sp = get_citizen_by_id(c.spouse_id)
		if sp and sp.is_alive and _is_free_for_leisure(sp) and sp.pos.distance_to(c.pos) <= 300.0:
			partner = sp
	else:
		# Ищет объект взаимной симпатии противоположного пола
		for other in population.citizens:
			if other == c or not other.is_alive or other.gender == c.gender:
				continue
			if other.cohort not in ["youth", "adult"] or c.is_related_to(other):
				continue
			if other.spouse_id != "" and marriage_law == "monogamy":
				continue
			if not _is_free_for_leisure(other):
				continue
			if c.has_grudge_against(other.citizen_id) or other.has_grudge_against(c.citizen_id):
				continue
			# Симпатия должна быть взаимной: на прогулку зовут тех, с кем уже сложились тёплые отношения,
			# а с малознакомыми — лишь изредка и только при отсутствии неприязни
			var aff = minf(c.get_relationship_affinity(other.citizen_id), other.get_relationship_affinity(c.citizen_id))
			var rom = float(c.get_relationship(other.citizen_id).get("romance", 0.0))
			if rom >= 15.0 or aff >= 30.0 or (aff >= 0.0 and randf() < 0.08):
				partner = other
				break
	if partner == null:
		return false
	var walk_pos = _find_scenic_walk_pos(c)
	if walk_pos == Vector2.ZERO:
		walk_pos = _find_shore_pos(c)
	if walk_pos == Vector2.ZERO:
		walk_pos = _get_hearth_pos() + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	var w_path: Array[Vector2] = GameManager.nav_grid.find_path(c.pos, walk_pos) if GameManager and GameManager.nav_grid else []
	if w_path.is_empty():
		w_path.append(walk_pos)
	var p_path: Array[Vector2] = GameManager.nav_grid.find_path(partner.pos, walk_pos) if GameManager and GameManager.nav_grid else []
	if p_path.is_empty():
		p_path.append(walk_pos)
	c.task_id = "dating_walk"
	c.target_id = partner.citizen_id
	c.target_pos = walk_pos
	c.path = w_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.last_status_reason = "Пригласил %s на романтическую прогулку" % partner.name
	c.shout("Пойдём со мной прогуляться, %s?" % partner.name, 3.5)
	c.show_emote("love", 3.5, 2)
	
	if not p_path.is_empty():
		partner.task_id = "dating_walk"
		partner.target_id = c.citizen_id
		partner.target_pos = walk_pos
		partner.path = p_path
		partner.path_index = 0
		partner.state = CitizenNPC.State.MOVING_TO_WORK
		partner.last_status_reason = "Идёт на прогулку с %s" % c.name
		partner.shout("С радостью, %s!" % c.name, 3.5)
		partner.show_emote("romance", 3.5, 2)
	c.decision_cooldown = 1.0
	return true

func _try_reconcile_quarrel(c: CitizenNPC) -> bool:
	if not population or population.citizens.is_empty():
		return false
	var rival: CitizenNPC = null
	for other in population.citizens:
		if other == c or not other.is_alive:
			continue
		if c.has_grudge_against(other.citizen_id) or c.get_relationship_affinity(other.citizen_id) <= -20.0:
			rival = other
			break
	if rival == null:
		return false
	var r_path: Array[Vector2] = GameManager.nav_grid.find_path(c.pos, rival.pos) if GameManager and GameManager.nav_grid else []
	if r_path.is_empty():
		r_path.append(rival.pos)
	c.task_id = "reconcile_quarrel"
	c.target_id = rival.citizen_id
	c.target_pos = rival.pos
	c.path = r_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.last_status_reason = "Идёт помириться с %s" % rival.name
	c.decision_cooldown = 1.0
	return true

func _try_pet_animal(c: CitizenNPC) -> bool:
	if not GameManager or not GameManager.wildlife_manager:
		return false
	var nearest_pet: WildAnimal = null
	var min_d = 280.0
	for a in GameManager.wildlife_manager.animals.values():
		if a.is_alive() and a.is_tamed:
			var d = c.pos.distance_to(a.pos)
			if d < min_d:
				min_d = d
				nearest_pet = a
	if nearest_pet == null:
		return false
	var p_path: Array[Vector2] = GameManager.nav_grid.find_path(c.pos, nearest_pet.pos) if GameManager.nav_grid else []
	if p_path.is_empty():
		p_path.append(nearest_pet.pos)
	c.task_id = "pet_animal"
	c.target_id = nearest_pet.id
	c.target_pos = nearest_pet.pos
	c.path = p_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.last_status_reason = "Идёт приласкать питомца (%s)" % (nearest_pet.custom_name if nearest_pet.custom_name != "" else "зверька")
	c.decision_cooldown = 1.0
	return true

func _try_hearth_game_or_story(c: CitizenNPC) -> bool:
	var h_pos = _get_hearth_pos()
	if c.pos.distance_to(h_pos) > 90.0:
		return false
	if randf() < 0.5:
		c.task_id = "play_dice"
		c.state = CitizenNPC.State.RESTING
		c.work_timer = randf_range(6.0, 10.0)
		c.show_emote("game", 4.0, 2)
		c.shout(_pick_phrase(c, [
			"Бросаю кости! Шестёрка на удачу!",
			"Ха, мой бросок точнее!",
			"Кто следующий рискнет сыграть в кости?"
		]), 3.5)
		c.last_status_reason = "Играет в кости у костра"
		return true
	else:
		c.task_id = "campfire_story"
		c.state = CitizenNPC.State.RESTING
		c.work_timer = randf_range(7.0, 12.0)
		c.show_emote("storytelling" if c.cohort in ["elder", "adult"] else "curiosity", 4.5, 2)
		c.shout(_pick_phrase(c, [
			"Слушайте предание о духах северных ветров...",
			"В тот год зверь был свиреп, но наше племя выстояло!",
			"Предки оставили нам эту землю и священный огонь."
		]), 4.0)
		c.last_status_reason = "Рассказывает сказания у костра" if c.cohort in ["elder", "adult"] else "Слушает сказания у костра"
		return true

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
				if GameManager.nav_grid and coord is Vector2i:
					return GameManager.nav_grid.tile_to_world_center(coord)
	if GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and "type" in b and b.type == "hunting_camp" and b.settlement_id == id:
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(b.pos)
	return c.home_pos

func _get_hunting_camp_instance(c: CitizenNPC) -> BuildingInstance:
	if GameManager.building_instances:
		if c.workplace_coord != Vector2i(-1, -1) and GameManager.building_instances.has(c.workplace_coord):
			var b = GameManager.building_instances[c.workplace_coord]
			if b and b.type == "hunting_camp":
				return b
		for b in GameManager.building_instances.values():
			if b and "type" in b and b.type == "hunting_camp" and b.settlement_id == id:
				return b
	return null

func _find_craftsman_workshop_pos(c: CitizenNPC) -> Vector2:
	if c.workplace_coord != Vector2i(-1, -1) and GameManager.nav_grid:
		return GameManager.nav_grid.tile_to_world_center(c.workplace_coord)
	if GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and "type" in b and b.type in ["craft_workshop", "carpenter_workshop", "pottery_workshop", "forge", "craftsman_workshop"] and b.settlement_id == id:
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(b.pos)
	return c.home_pos

func _get_storage_pos(c: CitizenNPC) -> Vector2:
	# Склад поселения: Хижина старейшины, амбар или центр стоянки
	if GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and "type" in b and b.type in ["granary", "elders_house"] and b.settlement_id == id:
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(b.pos)
	return c.home_pos

const RESOURCE_NAMES_RU: Dictionary = {
	"wood": "древесины",
	"food": "пищи",
	"stone": "камня",
	"metal": "руды",
	"leather": "шкур",
	"fur": "меха",
	"bone": "костей",
	"feathers": "перьев",
	"clothes": "тёплой одежды",
	"kubriki": "кубриков"
}

func _format_hunt_byproducts(byproducts: Dictionary) -> String:
	var parts: Array[String] = []
	for res_key in byproducts:
		var amt = int(byproducts[res_key])
		if amt > 0:
			parts.append("%d %s" % [amt, RESOURCE_NAMES_RU.get(res_key, res_key)])
	return ", ".join(parts)

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
	var queue_serialized = []
	for q in construction_queue:
		var q_c = q.get("coord", Vector2i(-1, -1))
		var deliv = q.get("materials_delivered", {}).duplicate()
		var req = q.get("materials_required", {}).duplicate()
		if q_c != Vector2i(-1, -1) and GameManager and GameManager.tile_buildings.has(q_c):
			var tb = GameManager.tile_buildings[q_c]
			deliv = tb.get("materials_delivered", deliv).duplicate()
			req = tb.get("materials_required", req).duplicate()
		queue_serialized.append({
			"id": q.get("id", ""),
			"coord": [q_c.x, q_c.y],
			"days_left": q.get("days_left", 0.0),
			"total_days": q.get("total_days", 1),
			"materials_required": req,
			"materials_delivered": deliv,
			"settlement_id": q.get("settlement_id", id),
			"is_paused": q.get("is_paused", false)
		})
	return {
		"id": id,
		"name": name,
		"faction_id": faction_id,
		"pos_x": pos.x,
		"pos_y": pos.y,
		"buildings": buildings.duplicate(),
		"assigned_jobs": assigned_jobs.duplicate(),
		"economy": economy.resources.duplicate(),
		"food_batches": food_batches.duplicate(true),
		"next_batch_id": _next_batch_id,
		"marriage_law": marriage_law,
		"reserved_zones": reserved_zones.duplicate(true),
		"logging_zones": logging_zones.map(func(c): return [c.x, c.y]),
		"active_relocations": active_relocations.duplicate(true),
		"equipment_stockpile": equipment_stockpile.duplicate(),
		"cemetery_plots": cemetery_plots.map(func(c): return [c.x, c.y]),
		"deceased_registry": deceased_registry.duplicate(true),
		"construction_queue": queue_serialized,
		"population": population.serialize() if population else {}
	}

func deserialize(data: Dictionary) -> void:
	id = data.get("id", id)
	name = data.get("name", name)
	faction_id = data.get("faction_id", faction_id)
	pos = Vector2i(data.get("pos_x", pos.x), data.get("pos_y", pos.y))
	buildings.assign(data.get("buildings", []))
	assigned_jobs = data.get("assigned_jobs", {}).duplicate()
	if data.has("economy"):
		economy.resources = data["economy"].duplicate()
	equipment_stockpile = data.get("equipment_stockpile", {}).duplicate()
	if data.has("food_batches"):
		food_batches.clear()
		for b in data["food_batches"]:
			if b is Dictionary:
				food_batches.append(b)
	_next_batch_id = data.get("next_batch_id", 1)
	marriage_law = data.get("marriage_law", "monogamy")
	reserved_zones.clear()
	for zone in data.get("reserved_zones", []):
		if zone is Dictionary:
			reserved_zones.append(zone.duplicate(true))
	logging_zones.clear()
	for p in data.get("logging_zones", []):
		if p is Array and p.size() >= 2:
			logging_zones.append(Vector2i(p[0], p[1]))
	active_relocations = data.get("active_relocations", {}).duplicate(true)
	cemetery_plots.clear()
	for p in data.get("cemetery_plots", []):
		if p is Array and p.size() >= 2:
			cemetery_plots.append(Vector2i(p[0], p[1]))
	deceased_registry.clear()
	for r in data.get("deceased_registry", []):
		if r is Dictionary:
			deceased_registry.append(r.duplicate(true))
	if data.has("construction_queue"):
		construction_queue.clear()
		for q in data["construction_queue"]:
			var c_arr = q.get("coord", [-1, -1])
			var q_obj = {
				"id": q.get("id", ""),
				"coord": Vector2i(c_arr[0], c_arr[1]),
				"days_left": float(q.get("days_left", 0.0)),
				"total_days": int(q.get("total_days", 1)),
				"materials_required": q.get("materials_required", {}).duplicate(),
				"materials_delivered": q.get("materials_delivered", {}).duplicate(),
				"settlement_id": q.get("settlement_id", id),
				"is_paused": bool(q.get("is_paused", false))
			}
			construction_queue.append(q_obj)
			var q_coord = q_obj["coord"]
			if q_coord != Vector2i(-1, -1) and GameManager and GameManager.tile_buildings.has(q_coord):
				var tb = GameManager.tile_buildings[q_coord]
				if not tb.has("materials_delivered") or tb["materials_delivered"].is_empty():
					tb["materials_delivered"] = q_obj["materials_delivered"].duplicate()
				else:
					q_obj["materials_delivered"] = tb["materials_delivered"].duplicate()
				if not tb.has("materials_required") or tb["materials_required"].is_empty():
					tb["materials_required"] = q_obj["materials_required"].duplicate()
				else:
					q_obj["materials_required"] = tb["materials_required"].duplicate()
	if data.has("population") and population:
		population.deserialize(data["population"])

func get_settlement_footpaths() -> Array[Dictionary]:
	var footpaths: Array[Dictionary] = []
	var hub_world = GameManager.nav_grid.tile_to_world_center(pos) if GameManager.nav_grid else Vector2(pos.x * 32.0 + 16, pos.y * 32.0 + 16)
	
	# Сбор только активных жилых домов и основных мастерских
	var key_coords: Array[Vector2i] = []
	if GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == id and b.pos != pos:
				if b.is_residential() or b.workers.size() > 0:
					if not key_coords.has(b.pos):
						key_coords.append(b.pos)
						
	# Тропинки только от жилых домов и рабочих мест к центральному костру (без паутины между соседями)
	for b_c in key_coords:
		var b_world = GameManager.nav_grid.tile_to_world_center(b_c) if GameManager.nav_grid else Vector2(b_c.x * 32.0 + 16, b_c.y * 32.0 + 16)
		var p_pts = GameManager.nav_grid.find_path(b_world, hub_world) if GameManager.nav_grid else []
		if p_pts.size() >= 2:
			footpaths.append({"points": p_pts, "type": "hub"})
		else:
			footpaths.append({"points": [b_world, hub_world], "type": "hub"})
			
	return footpaths


# ==============================================================================
# ЛИЧНЫЕ УКРАШЕНИЯ И ПОВЕДЕНИЕ NPC В ПОСЕЛЕНИИ
# Таблички, посаженные кусты, скамейки, идолы, мусор, уборка мусора
# ==============================================================================

# Типы декораций и их вероятности по чертам личности
const DECORATION_DEFS: Dictionary = {
	"sign":         {"tradition": 40.0, "empathy": 30.0,  "min_days": 0,  "label": "повесил табличку у дома"},
	"bush_planted": {"diligence": 35.0, "tradition": 25.0, "min_days": 0,  "label": "посадил куст у тропинки"},
	"bench":        {"empathy": 45.0,  "sociability": 40.0, "min_days": 0,  "label": "смастерил скамейку"},
	"flowers":      {"empathy": 30.0,  "curiosity": 25.0,  "min_days": 0,  "label": "высадил цветы"},
	"totem_small":  {"tradition": 60.0, "bravery": 35.0,   "min_days": 0,  "label": "соорудил небольшого идола"},
	"idol":         {"tradition": 75.0, "pride": 50.0,     "min_days": 0,  "label": "соорудил идола предков"},
	"trash":        {"diligence": -1.0, "temper": 55.0,    "min_days": 0,  "label": "бросил мусор"},  # бросает мусор — низкое усердие
}

# Радиус поиска клеток рядом с домом для размещения декорации
const DECO_SEARCH_RADIUS: int = 3
# Максимум декораций на поселение (кроме мусора)
const MAX_DECORATIONS_PER_SETTLEMENT: int = 48
# Базовый шанс (за один тик решений) что NPC займётся украшением/мусором
const DECO_BASE_CHANCE: float = 0.35

func _try_personal_decoration_action(c: CitizenNPC) -> void:
	if not GameManager:
		return
	if randf() > DECO_BASE_CHANCE:
		return

	var day = GameManager.total_simulation_days

	# --- 1. Проверка: может ли NPC убрать чужой мусор ---
	var empathy_val = float(c.traits.get("empathy", 50.0))
	var diligence_val = float(c.traits.get("diligence", 50.0))
	if empathy_val > 55.0 or diligence_val > 60.0:
		var trash_coord = _find_trash_near(c)
		if trash_coord != Vector2i(-1, -1):
			_cleanup_trash(c, trash_coord, day)
			return

	# --- 2. Мусорящий NPC: низкое усердие + высокий темперамент ---
	var temper_val = float(c.traits.get("temper", 20.0))
	if diligence_val < 30.0 and temper_val > 50.0 and randf() < 0.25:
		_place_trash(c, day)
		return

	# --- 3. Размещение позитивной декорации около дома / во дворе ---
	var deco_count = 0
	for deco in GameManager.tile_decorations.values():
		if deco.get("settlement_id", "") == id and deco.get("type", "") != "trash":
			deco_count += 1
	if deco_count >= MAX_DECORATIONS_PER_SETTLEMENT:
		return

	var base_home = c.home_coord
	if base_home == Vector2i(-1, -1):
		base_home = Vector2i(int(c.pos.x / 32.0), int(c.pos.y / 32.0))
		
	var personal_placed = 0
	for adj_coord in _get_adjacent_deco_coords(base_home, DECO_SEARCH_RADIUS):
		var existing = GameManager.tile_decorations.get(adj_coord, {})
		if existing.get("placer_id", "") == c.citizen_id:
			personal_placed += 1
	if personal_placed >= 3:
		return # До 3 личных украшений на жителя во дворе

	# Выбор типа декорации на основе черт личности
	var best_type = ""
	var best_score = -1.0
	for deco_type in DECORATION_DEFS:
		if deco_type == "trash":
			continue
		var def = DECORATION_DEFS[deco_type]
		var score = 0.0
		for trait_name in def:
			if trait_name == "min_days" or trait_name == "label":
				continue
			score += maxf(0.0, float(c.traits.get(trait_name, 50.0)) - 35.0) * 0.015
		score += randf() * 0.4
		if score > best_score:
			best_score = score
			best_type = deco_type

	if best_type == "" or best_score < 0.05:
		return

	# Поиск свободной клетки рядом с домом
	var target_coord = _find_free_deco_coord(base_home)
	if target_coord == Vector2i(-1, -1):
		return

	# NPC идёт к выбранной клетке
	var target_pos = GameManager.nav_grid.tile_to_world_center(target_coord) if GameManager.nav_grid else Vector2(target_coord.x * 32.0 + 16, target_coord.y * 32.0 + 16)
	var deco_path = GameManager.nav_grid.find_path(c.pos, target_pos) if GameManager.nav_grid else []
	
	c.task_id = "place_decoration"
	c.target_coord = target_coord
	c.target_pos = target_pos
	c.task_instance_id = best_type
	var label = DECORATION_DEFS[best_type].get("label", "украшает поселение")
	c.last_status_reason = label

	if deco_path.is_empty() or c.pos.distance_to(target_pos) <= 24.0:
		_finish_decoration_placement(c)
		return

	c.path = deco_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.action_timer = randf_range(2.5, 5.0)
	c.decision_cooldown = randf_range(15.0, 35.0)

func _finish_decoration_placement(c: CitizenNPC) -> void:
	# Вызывается из update_citizens когда NPC достиг цели task_id == "place_decoration"
	var coord = c.target_coord
	var deco_type = c.task_instance_id
	if coord == Vector2i(-1, -1) or deco_type == "":
		c.task_id = ""
		c.task_instance_id = ""
		c.state = CitizenNPC.State.IDLE
		return

	# Проверяем что клетка ещё свободна
	if GameManager.tile_decorations.has(coord) or (GameManager.tile_buildings and GameManager.tile_buildings.has(coord)):
		c.task_id = ""
		c.task_instance_id = ""
		c.state = CitizenNPC.State.IDLE
		return

	var variant = randi() % 3
	GameManager.tile_decorations[coord] = {
		"type": deco_type,
		"placer_id": c.citizen_id,
		"placer_name": c.name,
		"settlement_id": id,
		"placed_day": GameManager.total_simulation_days,
		"variant": variant
	}

	var label = DECORATION_DEFS.get(deco_type, {}).get("label", "украсил поселение")
	c.show_emote("build", 3.0, 2)
	c.loyalty = minf(100.0, c.loyalty + 3.0)
	c.add_memory("decorated_home", "home", "", 1.5, "Обустроил и украсил двор родного поселения (%s)" % label, true)
	c.task_id = ""
	c.task_instance_id = ""
	c.state = CitizenNPC.State.IDLE
	c.decision_cooldown = randf_range(15.0, 30.0)
	c.last_status_reason = label

	EventBus.notification_toast.emit(
		"🏡 Благоустройство",
		"%s %s" % [c.name, label],
		"good"
	)

func _place_trash(c: CitizenNPC, day: int) -> void:
	# Найти свободную клетку рядом с позицией NPC
	var tiles = GameManager.planet_data.get("tiles", [])
	var candidates: Array[Vector2i] = []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var tile_x = int(floor(c.pos.x / 32.0)) + dx
			var tile_y = int(floor(c.pos.y / 32.0)) + dy
			var tc = Vector2i(tile_x, tile_y)
			if tile_x < 0 or tile_y < 0:
				continue
			if tile_y >= tiles.size() or tile_x >= tiles[0].size():
				continue
			if GameManager.tile_decorations.has(tc):
				continue
			if GameManager.tile_buildings.has(tc):
				continue
			candidates.append(tc)
	if candidates.is_empty():
		return

	var tc = candidates[randi() % candidates.size()]
	GameManager.tile_decorations[tc] = {
		"type": "trash",
		"placer_id": c.citizen_id,
		"placer_name": c.name,
		"settlement_id": id,
		"placed_day": day,
		"variant": randi() % 2
	}
	c.last_status_reason = "Бросил мусор"

func _find_trash_near(c: CitizenNPC) -> Vector2i:
	# Поиск мусора в радиусе нескольких клеток от дома NPC
	var search_center = c.home_coord if c.home_coord != Vector2i(-1, -1) else Vector2i(int(c.pos.x / 32.0), int(c.pos.y / 32.0))
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var tc = Vector2i(search_center.x + dx, search_center.y + dy)
			var deco = GameManager.tile_decorations.get(tc, {})
			if deco.get("type", "") == "trash":
				# Не убирает свой мусор
				if deco.get("placer_id", "") != c.citizen_id:
					return tc
	return Vector2i(-1, -1)

func _cleanup_trash(c: CitizenNPC, trash_coord: Vector2i, _day: int) -> void:
	var trash_data = GameManager.tile_decorations.get(trash_coord, {})
	if trash_data.is_empty():
		return

	var target_pos = GameManager.nav_grid.tile_to_world_center(trash_coord) if GameManager.nav_grid else Vector2(trash_coord.x * 32.0 + 16, trash_coord.y * 32.0 + 16)
	var clean_path = GameManager.nav_grid.find_path(c.pos, target_pos) if GameManager.nav_grid else []
	if clean_path.is_empty():
		return

	c.task_id = "cleanup_trash"
	c.target_coord = trash_coord
	c.target_pos = target_pos
	c.path = clean_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.action_timer = 2.0
	c.task_instance_id = trash_data.get("placer_id", "")
	c.last_status_reason = "Убирает мусор"
	c.decision_cooldown = randf_range(10.0, 20.0)

func _finish_trash_cleanup(c: CitizenNPC) -> void:
	var coord = c.target_coord
	var trash_placer_id = c.task_instance_id
	if coord == Vector2i(-1, -1):
		c.task_id = ""
		c.task_instance_id = ""
		c.state = CitizenNPC.State.IDLE
		return

	GameManager.tile_decorations.erase(coord)

	c.show_emote("praise", 2.0, 1)
	c.task_id = ""
	c.task_instance_id = ""
	c.state = CitizenNPC.State.IDLE
	c.last_status_reason = "Убрал мусор"

	# Отношения: уборщик недоволен мусорящим
	if trash_placer_id != "" and trash_placer_id != c.citizen_id:
		c.modify_relationship(trash_placer_id, -8.0, -5.0)
		# Если мусорящий ещё жив — он тоже видит недовольство
		if population:
			var slob = population.find_citizen(trash_placer_id)
			if slob:
				slob.modify_relationship(c.citizen_id, -4.0, 0.0)
				if randf() < 0.3:
					slob.shout("Зачем убирать, всё равно запачкается!", 3.0)

func _find_free_deco_coord(home_coord: Vector2i) -> Vector2i:
	var tiles = GameManager.planet_data.get("tiles", [])
	var candidates: Array[Vector2i] = []
	for dx in range(-DECO_SEARCH_RADIUS, DECO_SEARCH_RADIUS + 1):
		for dy in range(-DECO_SEARCH_RADIUS, DECO_SEARCH_RADIUS + 1):
			if dx == 0 and dy == 0:
				continue
			var tc = Vector2i(home_coord.x + dx, home_coord.y + dy)
			if tc.x < 0 or tc.y < 0:
				continue
			if tc.y >= tiles.size() or tc.x >= tiles[0].size():
				continue
			if tiles[tc.y][tc.x].get("is_water", false):
				continue
			if GameManager.tile_decorations.has(tc):
				continue
			if GameManager.tile_buildings.has(tc):
				continue
			candidates.append(tc)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[randi() % candidates.size()]

func _get_adjacent_deco_coords(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			result.append(Vector2i(center.x + dx, center.y + dy))
	return result

func _find_shore_pos(c: CitizenNPC) -> Vector2:
	if not GameManager or not GameManager.planet_data or not GameManager.nav_grid:
		return Vector2.ZERO
	var tiles = GameManager.planet_data.get("tiles", [])
	if tiles.is_empty():
		return Vector2.ZERO
	var c_coord = Vector2i(int(floor(c.pos.x / 32.0)), int(floor(c.pos.y / 32.0)))
	var best_pos = Vector2.ZERO
	var best_dist = 999999.0
	var best_water_coord = Vector2i(-1, -1)
	
	for dx in range(-12, 13):
		for dy in range(-12, 13):
			var tx = c_coord.x + dx
			var ty = c_coord.y + dy
			var coord = Vector2i(tx, ty)
			if tx < 0 or ty < 0 or ty >= tiles.size() or tx >= tiles[0].size():
				continue
			# Клетка суши (не вода и проходима)
			if GameManager.nav_grid.is_water_tile(coord):
				continue
			# Проверяем соседство с настоящим водоёмом
			var found_water = false
			var adj_water = Vector2i(-1, -1)
			for n_off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n_coord = coord + n_off
				if GameManager.nav_grid.is_water_tile(n_coord):
					found_water = true
					adj_water = n_coord
					break
			if found_water:
				var candidate_p = GameManager.nav_grid.tile_to_world_center(coord)
				var d = c.pos.distance_to(candidate_p)
				if d < best_dist:
					var test_path = GameManager.nav_grid.find_path(c.pos, candidate_p)
					if not test_path.is_empty():
						best_dist = d
						best_pos = candidate_p
						best_water_coord = adj_water
						
	if best_pos != Vector2.ZERO:
		c.target_coord = best_water_coord
		return best_pos
	return Vector2.ZERO

func _find_cemetery_target(c: CitizenNPC) -> Dictionary:
	if not cemetery_plots.is_empty():
		var coord = cemetery_plots[randi() % cemetery_plots.size()]
		var g_pos = GameManager.nav_grid.tile_to_world_center(coord) if GameManager and GameManager.nav_grid else Vector2(coord.x * 32.0 + 16.0, coord.y * 32.0 + 16.0)
		return {"coord": coord, "pos": g_pos, "deceased_id": "", "deceased_name": "предков"}
	if GameManager and GameManager.building_instances:
		for bi in GameManager.building_instances.values():
			if bi is BuildingInstance and bi.settlement_id == id and bi.type in ["grave", "cemetery"]:
				var g_pos = Vector2(bi.pos.x * 32.0 + 16.0, bi.pos.y * 32.0 + 16.0)
				var dec_name = bi.building_data.get("deceased_name", "предков")
				var dec_id = bi.building_data.get("deceased_id", "")
				return {"coord": bi.pos, "pos": g_pos, "deceased_id": dec_id, "deceased_name": dec_name}
	return {}

func _find_scenic_walk_pos(c: CitizenNPC) -> Vector2:
	var h_pos = _get_hearth_pos()
	var angle = randf() * TAU
	var dist = randf_range(40.0, 110.0)
	var walk_p = h_pos + Vector2(cos(angle), sin(angle)) * dist
	if GameManager and GameManager.nav_grid:
		var tile_c = Vector2i(int(walk_p.x / 32.0), int(walk_p.y / 32.0))
		if GameManager.nav_grid.is_tile_walkable(tile_c):
			return GameManager.nav_grid.tile_to_world_center(tile_c)
	return walk_p
