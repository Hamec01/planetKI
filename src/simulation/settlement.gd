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
	"fisherman": 0,
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
var food_batches: Array[Dictionary] = []
var _next_batch_id: int = 1
var marriage_law: String = "monogamy" # "monogamy", "polygamy", "free_union"
var reserved_zones: Array[Dictionary] = []

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
	var consumed = 0.0
	var rem_to_consume = request_amount
	var i = 0
	while i < food_batches.size() and rem_to_consume > 0.0:
		var b = food_batches[i]
		var b_amt = float(b.get("amount", 0.0))
		if b_amt <= rem_to_consume:
			consumed += b_amt
			rem_to_consume -= b_amt
			food_batches.remove_at(i)
		else:
			b["amount"] = b_amt - rem_to_consume
			consumed += rem_to_consume
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
			var node = GameManager.resource_manager.nodes.get(target_coord, {}) if GameManager.resource_manager else {}
			var t_pos = node.get("pos", GameManager.nav_grid.tile_to_world_center(target_coord)) if GameManager.nav_grid else Vector2.ZERO
			var p = GameManager.nav_grid.find_path(c.pos, t_pos) if GameManager.nav_grid else []
			if GameManager.resource_manager:
				GameManager.resource_manager.reserve_node(target_coord, c.citizen_id)
			c.task_id = "chop_tree" if category == "wood" else "gather"
			c.target_coord = target_coord
			c.target_pos = t_pos
			c.target_id = node.get("id", "")
			c.path = p
			c.path_index = 0
			c.state = CitizenNPC.State.MOVING_TO_WORK
			c.last_status_reason = "Идёт на первоочередную вырубку дерева" if category == "wood" else "Идёт на первоочередной сбор"
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
	var starter_inst = GameManager.get_or_create_building_instance(pos, "elders_house", id)
	var center_pixel = Vector2(pos.x * 32.0 + 16.0, pos.y * 32.0 + 16.0)
	for c in population.citizens:
		c.settlement_id = id
		c.home_id = starter_inst.instance_id
		c.home_coord = pos
		c.home_pos = center_pixel
		c.pos = center_pixel + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		if c.job_id == "elder":
			c.workplace_id = starter_inst.instance_id
			c.workplace_coord = pos
	auto_assign_housing()

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
		var home_world_pos = GameManager.nav_grid.tile_to_world_center(b_inst.pos) if GameManager.nav_grid else Vector2(b_inst.pos.x * 32.0 + 16, b_inst.pos.y * 32.0 + 16)
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
	
	for c in population.citizens:
		var has_valid_home = false
		if c.home_id != "":
			for b in residential_buildings:
				if b.id == c.home_id:
					has_valid_home = true
					if not b.residents.has(c.citizen_id) and not b.guests.has(c.citizen_id):
						if b.has_space_for_resident():
							b.add_resident(c.citizen_id)
						elif b.has_space_for_guest():
							b.add_guest(c.citizen_id)
							c.is_guest = true
					break
		if has_valid_home:
			continue
			
		var assigned = false
		if c.family_id != "" or c.spouse_id != "":
			for b in residential_buildings:
				var has_relative = false
				for r_id in b.residents:
					var r_cit = population.find_citizen(r_id)
					if r_cit and (r_cit.family_id == c.family_id or r_cit.citizen_id == c.spouse_id):
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
	if not b_data.is_empty():
		var b_type = b_data.get("id", "")
		buildings.erase(b_type)
		GameManager.tile_buildings.erase(coord)
		
	auto_assign_housing()
	return true

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

func start_construction(building_id: String, target_coord: Vector2i = Vector2i(-1, -1)) -> bool:
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
		elif item.get("days_left", 1.0) <= 0.0:
			completed.append(i)
			if not buildings.has(item["id"]):
				buildings.append(item["id"])
			
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
		
	update_food_spoilage(delta)
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

		# 2b. Таймер устойчивости текущего выбора (Hysteresis / Commitment) (S08)
		if c.commitment_timer > 0.0:
			c.commitment_timer = maxf(0.0, c.commitment_timer - delta)
			if c.commitment_timer <= 0.0:
				c.ongoing_task_kind = ""

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
				var sleep_rate = 12.0 if c.home_id != "" else 6.0
				c.energy = minf(100.0, c.energy + sleep_rate * delta)
				if c.home_id == "":
					c.loyalty = maxf(0.0, c.loyalty - 0.2 * delta)
					c.last_status_reason = "Бездомный, спит на земле"
				else:
					c.last_status_reason = "Спит в гостях" if c.is_guest else "Спит в хижине"
				continue
			elif c.state == CitizenNPC.State.GOING_HOME:
				var reached = c.update_movement(delta)
				if reached or c.pos.distance_to(c.home_pos) < 6.0:
					c.state = CitizenNPC.State.SLEEPING
					c.last_status_reason = "Спит в хижине" if c.home_id != "" else "Спит под звёздами"
			else:
				# Если уже дома — сразу ложится спать в хижине
				if c.home_id != "" and c.home_pos != Vector2.ZERO and c.pos.distance_to(c.home_pos) <= 6.0:
					c.state = CitizenNPC.State.SLEEPING
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
				c.last_status_reason = "Пробуждение"
				c.decision_cooldown = randf_range(0.5, 2.0)
			
		# Снижение бодрости и сытости
		c.energy = maxf(0.0, c.energy - 0.4 * delta)
		c.hunger = maxf(0.0, c.hunger - 0.5 * delta)
		
		# Беременность и физическое развитие плода (S07)
		if c.is_pregnant():
			var p_res = c.advance_pregnancy(delta)
			if p_res == "birth":
				give_birth(c)
				continue
			elif p_res == "late":
				c.last_status_reason = "Беременность (поздний срок)"
		
		# Питание при сильном голоде (S06: приоритет домашнего запаса еды)
		if c.hunger < 45.0:
			var ate = false
			if c.home_id != "" and GameManager.building_instances:
				for h_inst in GameManager.building_instances.values():
					if h_inst.id == c.home_id and h_inst.food_stockpile >= 0.5:
						h_inst.consume_food(0.5)
						c.hunger = 100.0
						c.last_status_reason = "Поел из домашнего запаса"
						ate = true
						break
			if not ate and economy.get_resource("food") >= 0.5:
				consume_food(0.5)
				c.hunger = 100.0
				c.last_status_reason = "Поел у очага"
				ate = true
			if not ate:
				c.last_status_reason = "Голодает!"
			
		# Общение двух свободных жителей
		if c.state == CitizenNPC.State.TALKING:
			c.action_timer -= delta
			if c.action_timer <= 0.0:
				c.state = CitizenNPC.State.IDLE
				c.talk_partner_id = ""
				c.last_status_reason = "Закончил разговор"
			continue
			
		# Разумный отдых (RESTING) у костра или дома (S08)
		if c.state == CitizenNPC.State.RESTING:
			c.work_timer -= delta
			c.energy = minf(100.0, c.energy + 12.0 * delta)
			if c.work_timer <= 0.0 or c.energy >= 85.0:
				c.state = CitizenNPC.State.IDLE
				c.ongoing_task_kind = ""
				c.last_status_reason = "Отдохнул и полон сил"
				c.decision_cooldown = randf_range(0.5, 1.5)
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
						var group_carcass = GameManager.wildlife_manager.find_group_carcass_for_hunter(c.citizen_id)
						if not group_carcass.is_empty():
							c.target_id = group_carcass["id"]
							c.target_pos = group_carcass["pos"]
							c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
							c.path_index = 0
							c.last_status_reason = "Идёт делить добычу группы"
						else:
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
			if c.state == CitizenNPC.State.MOVING_TO_WORK and c.path.is_empty() and c.target_pos != Vector2.ZERO and c.pos.distance_to(c.target_pos) > 40.0:
				c.state = CitizenNPC.State.WAITING
				c.last_status_reason = "Нет пути к цели"
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.fail_task(c.task_instance_id, "Нет пути", true)
				continue

			var arrived = c.update_movement(delta)
			if arrived:
				if c.state == CitizenNPC.State.MOVING_TO_WORK:
					if c.task_id == "fetch_home_food":
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
					elif c.task_id == "assist_relative":
						c.state = CitizenNPC.State.WORKING
						c.work_timer = 2.5
						c.last_status_reason = "Помогает родственнику в общем деле"
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
					elif c.job_id == "woodcutter":
						c.state = CitizenNPC.State.WORKING
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.set_arrived(c.task_instance_id)
							GameManager.task_service.start_task(c.task_instance_id)
						if c.task_id == "plant_tree":
							c.work_timer = 2.5
							c.last_status_reason = "Сажает саженец дерева"
						else:
							c.work_timer = 0.75
							c.last_status_reason = "Рубит дерево топором"
					elif c.job_id in ["quarryman", "miner"]:
						c.state = CitizenNPC.State.WORKING
						c.work_timer = randf_range(3.0, 4.5)
						c.last_status_reason = _get_job_action_name(c.job_id)
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.set_arrived(c.task_instance_id)
							GameManager.task_service.start_task(c.task_instance_id)
					elif c.job_id == "builder":
						if c.task_id == "fetch_materials":
							var constr_coord = c.target_coord
							var take_res = ""
							var take_amt = 0.0
							if GameManager.tile_buildings.has(constr_coord):
								var b = GameManager.tile_buildings[constr_coord]
								var req = b.get("materials_required", {})
								var deliv = b.get("materials_delivered", {})
								for r in req:
									var needed = float(req[r]) - float(deliv.get(r, 0.0))
									if needed > 0.0 and economy.get_resource(r) > 0.0:
										take_res = r
										take_amt = minf(needed, minf(c.max_carry, economy.get_resource(r)))
										break
							if take_res != "" and take_amt > 0.0:
								economy.resources[take_res] = maxf(0.0, economy.resources[take_res] - take_amt)
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
								c.last_status_reason = "Стройка остановлена: нет материалов на складе"
								c.decision_cooldown = randf_range(2.0, 4.0)
							continue
						elif c.task_id == "fetch_upgrade_materials":
							var up_coord = c.target_coord
							var take_res = ""
							var take_amt = 0.0
							if GameManager.building_instances.has(up_coord):
								var b_inst = GameManager.building_instances[up_coord]
								if b_inst and b_inst.has_pending_upgrade():
									var req = b_inst.pending_upgrade.get("materials_required", {})
									var deliv = b_inst.pending_upgrade.get("materials_delivered", {})
									for r in req:
										var needed = float(req[r]) - float(deliv.get(r, 0.0))
										if needed > 0.0 and economy.get_resource(r) > 0.0:
											take_res = r
											take_amt = minf(needed, minf(c.max_carry, economy.get_resource(r)))
											break
							if take_res != "" and take_amt > 0.0:
								economy.resources[take_res] = maxf(0.0, economy.resources[take_res] - take_amt)
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
								c.last_status_reason = "Улучшение остановлено: нет материалов на складе"
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
					elif c.job_id == "craftsman":
						if c.task_id == "fetch_craft_raw":
							var raw_mat = ""
							if economy.get_resource("wood") >= 1.0: raw_mat = "wood"
							elif economy.get_resource("metal") >= 1.0: raw_mat = "metal"
							elif economy.get_resource("stone") >= 1.0: raw_mat = "stone"
							if raw_mat != "":
								economy.resources[raw_mat] = maxf(0.0, economy.resources[raw_mat] - 1.0)
								var is_pl = (faction_id == GameManager.player_faction_id or faction_id == "player_tribe" or id == "test_s")
								if is_pl:
									EventBus.resources_updated.emit(faction_id, economy.resources)
								c.cargo_type = raw_mat
								c.cargo_amount = 1.0
								c.task_id = "craft"
								var ws_pos = _find_craftsman_workshop_pos(c)
								c.target_pos = ws_pos
								c.path = GameManager.nav_grid.find_path(c.pos, ws_pos)
								c.path_index = 0
								c.state = CitizenNPC.State.MOVING_TO_WORK
								c.last_status_reason = "Несёт сырьё в мастерскую (%s)" % raw_mat
							else:
								c.state = CitizenNPC.State.WAITING
								c.task_id = ""
								c.last_status_reason = "Простаивает: нет сырья для ремесла"
								c.decision_cooldown = randf_range(3.0, 5.0)
							continue
						elif c.task_id == "craft":
							c.state = CitizenNPC.State.WORKING
							c.work_timer = 2.5
							c.last_status_reason = "Изготавливает изделия в мастерской"
							continue
						else:
							c.state = CitizenNPC.State.WORKING
							c.work_timer = 2.5
							c.last_status_reason = "Ремесленное дело"
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
					elif c.task_id == "craft_delivery" or (c.job_id == "craftsman" and c.cargo_type == "kubriki"):
						deposit_resource("kubriki", c.cargo_amount, c.name)
						c.cargo_type = ""
						c.cargo_amount = 0.0
						c.task_id = ""
						c.state = CitizenNPC.State.IDLE
						c.decision_cooldown = 1.0
						c.last_status_reason = "Сдал изготовленные кубрики на склад"
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
					elif c.cargo_type != "" and c.cargo_amount > 0:
						deposit_resource(c.cargo_type, c.cargo_amount, c.name, c.cargo_batch)
						if GameManager.task_service and c.task_instance_id != "":
							GameManager.task_service.complete_task(c.task_instance_id)
							c.task_instance_id = ""
						c.last_status_reason = "Сдал %d %s в амбар" % [int(c.cargo_amount), c.cargo_type]
						c.cargo_type = ""
						c.cargo_amount = 0.0
						c.cargo_batch.clear()
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
				c.cargo_batch = {
					"food_type": "meat",
					"amount": c.cargo_amount,
					"created_sim_time": GameManager.sim_time_total,
					"max_freshness_sec": 4500.0,
					"spoilage_progress": 0.0
				}
				c.state = CitizenNPC.State.CARRYING
				var dest_p = _get_storage_pos(c)
				c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
				c.path_index = 0
				c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.set_delivering(c.task_instance_id)
			continue

		# Выполнение работы на месте
		if c.state == CitizenNPC.State.WORKING:
			c.work_timer -= delta
			if c.work_timer <= 0.0:
				if c.task_id == "care_for_child":
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
				elif c.job_id == "woodcutter":
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
								var dest_p = _get_storage_pos(c)
								c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
								c.path_index = 0
								c.last_status_reason = "Срубил дерево, несёт %d дров на склад" % int(c.cargo_amount)
								if GameManager.task_service and c.task_instance_id != "":
									GameManager.task_service.set_delivering(c.task_instance_id)
							else:
								c.state = CitizenNPC.State.IDLE
								c.decision_cooldown = 1.0
								if GameManager.task_service and c.task_instance_id != "":
									GameManager.task_service.cancel_task(c.task_instance_id, "Дерево пустое")
									c.task_instance_id = ""
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
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.last_status_reason = "Несёт %d %s на склад" % [int(c.cargo_amount), c.cargo_type]
					if GameManager.task_service and c.task_instance_id != "":
						GameManager.task_service.set_delivering(c.task_instance_id)
				elif c.job_id == "builder":
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
									up["work_left"] = maxf(0.0, float(up.get("work_left", 4.0)) - 0.5)
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
										c.work_timer = 1.5
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
									b["days_left"] = maxf(0.0, float(b.get("days_left", 1.0)) - 0.25)
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
										c.state = CitizenNPC.State.IDLE
										c.task_id = ""
										c.decision_cooldown = 1.0
									else:
										c.work_timer = 1.5
										c.last_status_reason = "Строит здание (осталось %.1f дней)" % b["days_left"]
						else:
							c.state = CitizenNPC.State.IDLE
							c.decision_cooldown = 1.0
				elif c.job_id == "craftsman":
					c.cargo_type = "kubriki"
					c.cargo_amount = 1.0
					c.task_id = "craft_delivery"
					c.state = CitizenNPC.State.CARRYING
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.last_status_reason = "Изготовил кубрики, несёт на склад"
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
				if not f_node.is_empty():
					var f_path = GameManager.nav_grid.find_path(c.pos, f_node["pos"]) if GameManager.nav_grid else []
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
					c.target_pos = f_node["pos"]
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
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.state = CitizenNPC.State.CARRYING
					c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
					if GameManager.task_service and c.task_instance_id != "":
						GameManager.task_service.set_delivering(c.task_instance_id)
					continue
					
				var carcass = GameManager.wildlife_manager.find_nearest_carcass(c.pos, 500.0, c.citizen_id)
				if not carcass.is_empty():
					var c_path = GameManager.nav_grid.find_path(c.pos, carcass["pos"]) if GameManager.nav_grid else []
					if c_path.is_empty():
						if GameManager.task_service:
							var blocked_id = GameManager.task_service.create_task("harvest_carcass", carcass["id"], Vector2i(-1, -1), carcass["pos"])
							GameManager.task_service.fail_task(blocked_id, "Нет пути к туше", true)
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути к туше"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					GameManager.wildlife_manager.reserve_carcass(carcass["id"], c.citizen_id)
					c.task_id = "harvest_carcass"
					c.target_id = carcass["id"]
					c.target_pos = carcass["pos"]
					c.path = c_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт забирать тушу (%s)" % _get_animal_display_name(carcass.get("type_id", carcass["species"]))
					c.decision_cooldown = 0.8
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("harvest_carcass", carcass["id"], Vector2i(-1, -1), carcass["pos"])
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
					continue
					
				var target_animal = GameManager.wildlife_manager.find_nearest_hunt_target(c.pos, 1000.0, c.citizen_id)
				if target_animal != null:
					var a_path = GameManager.nav_grid.find_path(c.pos, target_animal.pos) if GameManager.nav_grid else []
					if a_path.is_empty():
						if GameManager.task_service:
							var blocked_id = GameManager.task_service.create_task("hunt_animal", target_animal.id, Vector2i(-1, -1), target_animal.pos)
							GameManager.task_service.fail_task(blocked_id, "Нет пути к добыче", true)
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути к добыче"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					if not GameManager.wildlife_manager.join_hunt_group(target_animal.id, c.citizen_id):
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Охотничья группа уже укомплектована"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					c.task_id = "hunt_animal"
					c.target_id = target_animal.id
					c.target_pos = target_animal.pos
					c.path = a_path
					c.path_index = 0
					c.action_timer = 0.0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Выслеживает %s" % _get_animal_display_name(target_animal.type_id)
					c.decision_cooldown = 0.8
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("hunt_animal", target_animal.id, Vector2i(-1, -1), target_animal.pos)
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступной добычи"
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
				var fish_path = GameManager.nav_grid.find_path(c.pos, fish_node["pos"]) if GameManager.nav_grid else []
				if fish_path.is_empty():
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет пути к рыбному месту"
					c.decision_cooldown = randf_range(2.0, 4.0)
					continue
				GameManager.resource_manager.reserve_node(fish_node["coord"], c.citizen_id)
				c.task_id = "fish"
				c.target_coord = fish_node["coord"]
				c.target_pos = fish_node["pos"]
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

			# 3. Особая логика для Лесоруба (Рубка 1 дерево = 100 дров + Посадка леса)
			if c.job_id == "woodcutter" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount > 0.0:
					c.state = CitizenNPC.State.CARRYING
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.last_status_reason = "Несёт %d дров на склад" % int(c.cargo_amount)
					if GameManager.task_service and c.task_instance_id != "":
						GameManager.task_service.set_delivering(c.task_instance_id)
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
					var t_path = GameManager.nav_grid.find_path(c.pos, tree["pos"]) if GameManager.nav_grid else []
					if t_path.is_empty():
						if GameManager.task_service:
							var blocked_id = GameManager.task_service.create_task("chop_tree", tree.get("id", ""), tree["coord"], tree["pos"])
							GameManager.task_service.fail_task(blocked_id, "Нет пути к дереву", true)
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути к дереву"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					GameManager.resource_manager.reserve_node(tree["coord"], c.citizen_id)
					c.task_id = "chop_tree"
					c.target_coord = tree["coord"]
					c.target_pos = tree["pos"]
					c.target_id = tree["id"]
					c.path = t_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт рубить: %s" % tree["name"]
					c.decision_cooldown = 0.8
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("chop_tree", tree["id"], tree["coord"], tree["pos"])
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
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
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.last_status_reason = "Несёт %d камня на склад" % int(c.cargo_amount)
					if GameManager.task_service and c.task_instance_id != "":
						GameManager.task_service.set_delivering(c.task_instance_id)
					continue
				var rock = GameManager.resource_manager.find_available_node(pos, "stone", 16, c.citizen_id)
				if not rock.is_empty():
					var r_path = GameManager.nav_grid.find_path(c.pos, rock["pos"]) if GameManager.nav_grid else []
					if r_path.is_empty():
						if GameManager.task_service:
							var blocked_id = GameManager.task_service.create_task("mine_stone", rock.get("id", ""), rock["coord"], rock["pos"])
							GameManager.task_service.fail_task(blocked_id, "Нет пути к камню", true)
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути к камню"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					GameManager.resource_manager.reserve_node(rock["coord"], c.citizen_id)
					c.task_id = "mine_stone"
					c.target_coord = rock["coord"]
					c.target_pos = rock["pos"]
					c.target_id = rock["id"]
					c.path = r_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт добывать: %s" % rock["name"]
					c.decision_cooldown = 0.8
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("mine_stone", rock["id"], rock["coord"], rock["pos"])
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступного камня"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue

			# 5. Особая логика для Рудокопа (Этап E)
			if c.job_id == "miner" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_amount >= c.max_carry:
					c.state = CitizenNPC.State.CARRYING
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.last_status_reason = "Несёт %d руды на склад" % int(c.cargo_amount)
					if GameManager.task_service and c.task_instance_id != "":
						GameManager.task_service.set_delivering(c.task_instance_id)
					continue
				var ore = GameManager.resource_manager.find_available_node(pos, "metal", 20, c.citizen_id)
				if not ore.is_empty():
					var o_path = GameManager.nav_grid.find_path(c.pos, ore["pos"]) if GameManager.nav_grid else []
					if o_path.is_empty():
						if GameManager.task_service:
							var blocked_id = GameManager.task_service.create_task("mine_ore", ore.get("id", ""), ore["coord"], ore["pos"])
							GameManager.task_service.fail_task(blocked_id, "Нет пути к руде", true)
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути к руде"
						c.decision_cooldown = randf_range(2.0, 4.0)
						continue
					GameManager.resource_manager.reserve_node(ore["coord"], c.citizen_id)
					c.task_id = "mine_ore"
					c.target_coord = ore["coord"]
					c.target_pos = ore["pos"]
					c.target_id = ore["id"]
					c.path = o_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт к: %s" % ore["name"]
					c.decision_cooldown = 0.8
					if GameManager.task_service:
						var tid = GameManager.task_service.create_task("mine_ore", ore["id"], ore["coord"], ore["pos"])
						GameManager.task_service.assign_actor(tid, c.citizen_id)
						c.task_instance_id = tid
				else:
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Нет доступных жил руды"
					c.decision_cooldown = randf_range(3.0, 5.0)
				continue

			# 6. Особая логика для Строителя (S05: реальная доставка материалов, стройка и улучшения)
			if c.job_id == "builder" and c.cohort in ["youth", "adult", "elder"]:
				# 1. Если уже держит груз стройматериалов в руках — несёт на площадку
				if c.cargo_amount > 0.0:
					if c.task_id == "haul_to_site" and c.target_coord != Vector2i(-1, -1):
						c.state = CitizenNPC.State.CARRYING
						c.target_pos = GameManager.nav_grid.tile_to_world_center(c.target_coord)
						c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
						c.path_index = 0
						c.last_status_reason = "Несёт %d %s на стройплощадку" % [int(c.cargo_amount), c.cargo_type]
						continue
					elif c.task_id == "haul_to_upgrade" and c.target_coord != Vector2i(-1, -1):
						c.state = CitizenNPC.State.CARRYING
						c.target_pos = GameManager.nav_grid.tile_to_world_center(c.target_coord)
						c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
						c.path_index = 0
						c.last_status_reason = "Несёт %d %s для улучшения здания" % [int(c.cargo_amount), c.cargo_type]
						continue
				
				# 2. Поиск активной стройки здания (из очереди строительства поселения)
				var constr_coord = Vector2i(-1, -1)
				var constr_b: Dictionary = {}
				for item in construction_queue:
					var q_c = item.get("coord", Vector2i(-1, -1))
					if q_c != Vector2i(-1, -1) and GameManager.tile_buildings.has(q_c):
						var b = GameManager.tile_buildings[q_c]
						if b.get("status", "") == "constructing":
							constr_coord = q_c
							constr_b = b
							break
				
				if constr_coord != Vector2i(-1, -1):
					# Проверяем нехватку стройматериалов на площадке
					var missing_r = ""
					var missing_amt = 0.0
					var req = constr_b.get("materials_required", {})
					var deliv = constr_b.get("materials_delivered", {})
					for r in req:
						var needed = float(req[r]) - float(deliv.get(r, 0.0))
						if needed > 0.0:
							missing_r = r
							missing_amt = needed
							break
					
					if missing_r != "":
						# Требуется доставка материалов со склада
						var storage_p = _get_storage_pos(c)
						var in_storage = economy.get_resource(missing_r)
						if in_storage >= 1.0:
							var p_path = GameManager.nav_grid.find_path(c.pos, storage_p) if GameManager.nav_grid else []
							if p_path.is_empty():
								c.state = CitizenNPC.State.WAITING
								c.last_status_reason = "Нет пути на склад"
								c.decision_cooldown = 2.0
								continue
							c.target_pos = storage_p
							c.target_coord = constr_coord
							c.task_id = "fetch_materials"
							c.path = p_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.last_status_reason = "Идёт на склад за стройматериалами (%s)" % missing_r
							c.decision_cooldown = 0.8
							if GameManager.task_service:
								var tid = GameManager.task_service.create_task("haul_materials", constr_b.get("id", ""), constr_coord, storage_p)
								GameManager.task_service.assign_actor(tid, c.citizen_id)
								c.task_instance_id = tid
							continue
						else:
							# Нехватка материалов на складе останавливает стройку!
							c.state = CitizenNPC.State.WAITING
							c.last_status_reason = "Стройка остановлена: нет материалов на складе (%s)" % missing_r
							c.decision_cooldown = randf_range(2.0, 4.0)
							if GameManager.task_service and c.task_instance_id != "":
								GameManager.task_service.fail_task(c.task_instance_id, "Нехватка материалов", true)
								c.task_instance_id = ""
							continue
					else:
						# Все материалы доставлены: физическая работа на стройплощадке
						var site_p = GameManager.nav_grid.tile_to_world_center(constr_coord)
						var s_path = GameManager.nav_grid.find_path(c.pos, site_p) if GameManager.nav_grid else []
						if s_path.is_empty():
							c.state = CitizenNPC.State.WAITING
							c.last_status_reason = "Нет пути к стройплощадке"
							c.decision_cooldown = 2.0
							continue
						c.target_coord = constr_coord
						c.target_pos = site_p
						c.task_id = "build"
						c.path = s_path
						c.path_index = 0
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.last_status_reason = "Идёт строить: %s" % constr_b.get("id", "")
						c.decision_cooldown = 0.8
						if GameManager.task_service:
							var tid = GameManager.task_service.create_task("build", constr_b.get("id", ""), constr_coord, site_p)
							GameManager.task_service.assign_actor(tid, c.citizen_id)
							c.task_instance_id = tid
						continue
				
				# 3. Поиск активного улучшения здания (если нет новых строек)
				var up_coord = Vector2i(-1, -1)
				var up_inst: BuildingInstance = null
				for b_inst in GameManager.building_instances.values():
					if b_inst and b_inst.has_pending_upgrade():
						up_coord = b_inst.pos
						up_inst = b_inst
						break
				if up_coord != Vector2i(-1, -1) and up_inst != null:
					var up = up_inst.pending_upgrade
					var missing_r = ""
					var req = up.get("materials_required", {})
					var deliv = up.get("materials_delivered", {})
					for r in req:
						var needed = float(req[r]) - float(deliv.get(r, 0.0))
						if needed > 0.0:
							missing_r = r
							break
					if missing_r != "":
						var storage_p = _get_storage_pos(c)
						var in_storage = economy.get_resource(missing_r)
						if in_storage >= 1.0:
							var p_path = GameManager.nav_grid.find_path(c.pos, storage_p) if GameManager.nav_grid else []
							if p_path.is_empty():
								c.state = CitizenNPC.State.WAITING
								c.last_status_reason = "Нет пути на склад"
								c.decision_cooldown = 2.0
								continue
							c.target_pos = storage_p
							c.target_coord = up_coord
							c.task_id = "fetch_upgrade_materials"
							c.path = p_path
							c.path_index = 0
							c.state = CitizenNPC.State.MOVING_TO_WORK
							c.last_status_reason = "Идёт на склад за материалами для улучшения (%s)" % missing_r
							c.decision_cooldown = 0.8
							continue
						else:
							c.state = CitizenNPC.State.WAITING
							c.last_status_reason = "Улучшение остановлено: нет материалов на складе (%s)" % missing_r
							c.decision_cooldown = randf_range(2.0, 4.0)
							continue
					else:
						# Все материалы доставлены: физическая работа над улучшением
						var b_pos = GameManager.nav_grid.tile_to_world_center(up_coord)
						var s_path = GameManager.nav_grid.find_path(c.pos, b_pos) if GameManager.nav_grid else []
						if s_path.is_empty():
							c.state = CitizenNPC.State.WAITING
							c.last_status_reason = "Нет пути к зданию для улучшения"
							c.decision_cooldown = 2.0
							continue
						c.target_coord = up_coord
						c.target_pos = b_pos
						c.task_id = "upgrade_work"
						c.path = s_path
						c.path_index = 0
						c.state = CitizenNPC.State.MOVING_TO_WORK
						c.last_status_reason = "Идёт улучшать здание (%s)" % up.get("id", "")
						c.decision_cooldown = 0.8
						continue
						
				c.state = CitizenNPC.State.WAITING
				c.last_status_reason = "Нет активных строек"
				c.decision_cooldown = randf_range(4.0, 7.0)
				continue

			# 7. Особая логика для Ремесленника (S05: забор сырья со склада, крафт в мастерской, сдача готовых изделий)
			if c.job_id == "craftsman" and c.cohort in ["youth", "adult", "elder"]:
				if c.cargo_type == "kubriki" and c.cargo_amount > 0.0:
					var dest_p = _get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.state = CitizenNPC.State.CARRYING
					c.task_id = "craft_delivery"
					c.last_status_reason = "Несёт %d кубриков на склад" % int(c.cargo_amount)
					continue
				if c.cargo_type in ["wood", "metal", "stone"] and c.cargo_amount > 0.0 and c.task_id == "craft":
					var ws_pos = _find_craftsman_workshop_pos(c)
					c.target_pos = ws_pos
					c.path = GameManager.nav_grid.find_path(c.pos, ws_pos)
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Несёт сырьё в мастерскую"
					continue
				
				# Проверяем наличие сырья на складе
				var raw_mat = ""
				if economy.get_resource("wood") >= 1.0: raw_mat = "wood"
				elif economy.get_resource("metal") >= 1.0: raw_mat = "metal"
				elif economy.get_resource("stone") >= 1.0: raw_mat = "stone"
				
				if raw_mat == "":
					c.state = CitizenNPC.State.WAITING
					c.last_status_reason = "Простаивает: нет сырья для ремесла"
					c.decision_cooldown = randf_range(3.0, 5.0)
					continue
				else:
					var storage_p = _get_storage_pos(c)
					var p_path = GameManager.nav_grid.find_path(c.pos, storage_p) if GameManager.nav_grid else []
					if p_path.is_empty():
						c.state = CitizenNPC.State.WAITING
						c.last_status_reason = "Нет пути на склад за сырьём"
						c.decision_cooldown = 2.0
						continue
					c.target_pos = storage_p
					c.task_id = "fetch_craft_raw"
					c.path = p_path
					c.path_index = 0
					c.state = CitizenNPC.State.MOVING_TO_WORK
					c.last_status_reason = "Идёт на склад за сырьём (%s)" % raw_mat
					c.decision_cooldown = 0.8
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
	
	# Романтические отношения и брачные союзы (S07: строго 18+ лет, дети исключены)
	if c1.age >= 18 and c2.age >= 18 and not c1.is_related_to(c2):
		if c1.gender != c2.gender:
			var r1 = c1.get_relationship(c2.citizen_id)
			var r_romance = float(r1.get("romance", 0.0)) + 15.0
			c1.add_relationship(c2.citizen_id, r1.get("type", "friend"), 60.0, r_romance, r1.get("married", false))
			c2.add_relationship(c1.citizen_id, r1.get("type", "friend"), 60.0, r_romance, r1.get("married", false))
			
			# Возможность заключения брака при взаимных чувствах
			if r_romance >= 50.0 and not r1.get("married", false):
				if c1.can_marry(c2, marriage_law).get("allowed", false):
					c1.marry(c2, marriage_law)
					c1.shout("Мы решили быть вместе!", 3.5)
					EventBus.notification_toast.emit("Новый союз", "%s и %s заключили союз" % [c1.name, c2.name], "good")
			
			# Возможность зарождения новой жизни у супругов
			var female_partner = c1 if c1.gender == "f" else c2
			var male_partner = c2 if c1.gender == "f" else c1
			if female_partner.get_spouses().has(male_partner.citizen_id) and not female_partner.is_pregnant():
				if female_partner.age >= 18 and female_partner.age <= 42 and randf() < 0.15:
					start_pregnancy(female_partner, male_partner)

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

func _find_craftsman_workshop_pos(c: CitizenNPC) -> Vector2:
	if c.workplace_coord != Vector2i(-1, -1) and GameManager.nav_grid:
		return GameManager.nav_grid.tile_to_world_center(c.workplace_coord)
	if GameManager.building_instances:
		for coord in GameManager.building_instances.keys():
			var b = GameManager.building_instances[coord]
			if b and "type" in b and b.type in ["carpenter_workshop", "forge", "craftsman_workshop"]:
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(coord)
	return c.home_pos

func _get_storage_pos(c: CitizenNPC) -> Vector2:
	# Склад поселения: Хижина старейшины, амбар или центр стоянки
	if GameManager.building_instances:
		for coord in GameManager.building_instances.keys():
			var b = GameManager.building_instances[coord]
			if b and "type" in b and b.type in ["granary", "elders_house"]:
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
