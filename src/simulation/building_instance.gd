class_name BuildingInstance
extends RefCounted

var id: String = ""
var instance_id: String:
	get: return id
	set(val): id = val
var type: String = "" # "forge", "carpenter_workshop", "stone_quarry", "granary", "elders_house", "shrine", "hunting_camp", "training_grounds"
var building_type: String:
	get: return type
	set(val): type = val
var settlement_id: String = ""
var pos: Vector2i = Vector2i.ZERO
var tile_coord: Vector2i:
	get: return pos
	set(val): pos = val
var condition: float = 100.0 # 0 - 100%

var manager_id: String = "" # ID назначенного мастера/руководителя (напр. "cit_2")
var workers: Array[String] = [] # IDs соплеменников

# --- ДОМОХОЗЯЙСТВО, ЖИЛЬЦЫ И ЗАПАСЫ (S06 / P01.3) ---
var residents: Array[String] = [] # IDs постоянных членов домохозяйства
var guests: Array[String] = [] # IDs временных гостей (гостевое проживание)
var max_residents: int = 8
var comfort_capacity: int = 6
var max_guests: int = 2
var household_head_id: String = ""
var resident_roles: Dictionary = {} # citizen_id -> "owner" | "resident" | "guest" | "dependent"
var domestic_goods: Dictionary = {} # Личные вещи и материалы домохозяйства
var food_stockpile: float = 0.0 # Домашний запас пищи
var food_stockpile_max: float = 16.0 # Целевой запас на 2 дня
var is_locked_by_player: bool = false # Запрет автоматического выселения игроком

var active_mode: String = "default"
var production_queue: Array[Dictionary] = [] # Заказы: [{"id": "item_id", "name": "...", "count": 10, "progress": 0.0, "cost": {}}]

var unlocked_upgrades: Array[String] = []
var specialization: String = ""

var active_modifiers: Dictionary = {}
var event_history: Array[Dictionary] = []
var active_events: Array[Dictionary] = []
var construction_year: int = 1

func _init(p_id: String = "", p_type: String = "", p_settlement: String = "", p_pos: Vector2i = Vector2i.ZERO) -> void:
	id = p_id
	type = p_type
	settlement_id = p_settlement
	pos = p_pos
	condition = 100.0
	construction_year = GameManager.current_year if GameManager else 1
	_init_housing_capacity()
	_init_default_mode()

func _init_housing_capacity() -> void:
	var b_info = BuildingDB.get_building(type)
	if b_info.has("housing") and b_info["housing"] > 0:
		max_residents = b_info["housing"]
		comfort_capacity = b_info.get("comfort_housing", 6 if type == "hut" else max_residents)
		max_guests = b_info.get("max_guests", maxi(2, int(ceil(max_residents * 0.25))))
		food_stockpile_max = float(max_residents * 2)
	elif type == "elders_house":
		max_residents = 4
		comfort_capacity = 4
		max_guests = 2
		food_stockpile_max = 12.0
	elif type == "granary":
		max_residents = 0
		comfort_capacity = 0
		max_guests = 0
		food_stockpile_max = 100.0
	else:
		max_residents = 0
		comfort_capacity = 0
		max_guests = 0
		food_stockpile_max = 0.0

func _init_default_mode() -> void:
	match type:
		"forge": active_mode = "tools"
		"carpenter_workshop": active_mode = "construction"
		"stone_quarry": active_mode = "mass"
		"granary": active_mode = "normal"
		"elders_house": active_mode = "council"
		"shrine": active_mode = "rituals"
		"hunting_camp": active_mode = "plains"
		"training_grounds": active_mode = "drills"
		"woodcutter_camp": active_mode = "logging"
		_: active_mode = "default"

func add_history_entry(year: int, text: String) -> void:
	event_history.append({
		"year": year,
		"text": text
	})

var pending_upgrade: Dictionary = {}

func is_upgrade_unlocked(u_id: String) -> bool:
	return unlocked_upgrades.has(u_id)

func has_pending_upgrade() -> bool:
	return not pending_upgrade.is_empty()

func start_upgrade(u_id: String, custom_cost: Dictionary = {}) -> bool:
	if is_upgrade_unlocked(u_id) or has_pending_upgrade():
		return false
	var cost = custom_cost
	if cost.is_empty() and BuildingSystem.UPGRADES.has(u_id):
		cost = BuildingSystem.UPGRADES[u_id].get("cost", {}).duplicate()
	pending_upgrade = {
		"id": u_id,
		"materials_required": cost,
		"materials_delivered": {},
		"work_left": 4.0,
		"total_work": 4.0
	}
	var year = GameManager.current_year if GameManager else 1
	add_history_entry(year, "Начато улучшение: %s" % u_id)
	return true

func unlock_upgrade(u_id: String) -> bool:
	if not is_upgrade_unlocked(u_id):
		unlocked_upgrades.append(u_id)
		if pending_upgrade.get("id", "") == u_id:
			pending_upgrade.clear()
		var year = GameManager.current_year if GameManager else 1
		add_history_entry(year, "Исследовано улучшение: %s" % u_id)
		return true
	return false

func cancel_upgrade() -> Dictionary:
	if not has_pending_upgrade():
		return {}
	var saved_pending = pending_upgrade.duplicate(true)
	pending_upgrade.clear()
	var year = GameManager.current_year if GameManager else 1
	add_history_entry(year, "Отменено улучшение: %s" % saved_pending.get("id", ""))
	return saved_pending

func set_mode(new_mode: String) -> void:
	active_mode = new_mode
	var year = GameManager.current_year if GameManager else 1
	add_history_entry(year, "Сменен рабочий режим на: %s" % new_mode)

func assign_manager(citizen_id: String, citizen_name: String = "") -> void:
	manager_id = citizen_id
	if not workers.has(citizen_id) and citizen_id != "":
		workers.append(citizen_id)
	var year = GameManager.current_year if GameManager else 1
	var title = citizen_name if citizen_name != "" else citizen_id
	add_history_entry(year, "Руководителем назначен: %s" % title)

func remove_worker(citizen_id: String) -> void:
	workers.erase(citizen_id)
	if manager_id == citizen_id:
		manager_id = ""

func add_worker(citizen_id: String) -> void:
	if not workers.has(citizen_id):
		workers.append(citizen_id)

func is_residential() -> bool:
	return max_residents > 0

func has_unresolved_dispute() -> bool:
	return active_modifiers.get("unresolved_housing_dispute", false)

func get_max_residents() -> int:
	var cap = max_residents
	if type == "hut" and is_upgrade_unlocked("hut_annex"):
		cap += 2
	return cap

func get_comfort_capacity() -> int:
	if type == "hut":
		var cap = comfort_capacity
		if is_upgrade_unlocked("hut_annex"):
			cap += 2
		if active_modifiers.get("partitioned", false):
			cap += 1
		return cap
	return comfort_capacity

func get_domestic_goods_capacity() -> float:
	var cap = 10.0
	if is_upgrade_unlocked("hut_shed"):
		cap += 15.0
	return cap

func get_home_spoilage_multiplier() -> float:
	if is_upgrade_unlocked("hut_pantry"):
		return 0.5
	return 1.0

func is_crowded() -> bool:
	return is_residential() and residents.size() > get_comfort_capacity()

func get_crowding_penalty() -> float:
	if not is_crowded():
		return 0.0
	var excess = residents.size() - get_comfort_capacity()
	return clampf(float(excess) * 0.12, 0.0, 0.35)

func get_total_occupants() -> int:
	return residents.size() + guests.size()

func get_total_capacity() -> int:
	return get_max_residents() + max_guests

func has_space_for_resident() -> bool:
	return residents.size() < get_max_residents()

func has_space_for_guest() -> bool:
	return guests.size() < max_guests

func get_resident_role(citizen_id: String) -> String:
	if guests.has(citizen_id):
		return "guest"
	if resident_roles.has(citizen_id):
		return resident_roles[citizen_id]
	if household_head_id == citizen_id or (household_head_id == "" and residents.size() > 0 and residents[0] == citizen_id):
		return "owner"
	if residents.has(citizen_id):
		return "resident"
	return "none"

func set_resident_role(citizen_id: String, role: String) -> void:
	if role == "guest":
		if not guests.has(citizen_id):
			add_guest(citizen_id)
		resident_roles[citizen_id] = "guest"
	else:
		if not residents.has(citizen_id):
			add_resident(citizen_id, role)
		else:
			resident_roles[citizen_id] = role
		if role == "owner":
			household_head_id = citizen_id

func add_resident(citizen_id: String, role: String = "resident") -> bool:
	if has_space_for_resident():
		if not residents.has(citizen_id):
			guests.erase(citizen_id)
			residents.append(citizen_id)
			if household_head_id == "" or role == "owner":
				household_head_id = citizen_id
				resident_roles[citizen_id] = "owner"
			else:
				resident_roles[citizen_id] = role
			return true
	return false

func remove_resident(citizen_id: String) -> void:
	residents.erase(citizen_id)
	resident_roles.erase(citizen_id)
	if household_head_id == citizen_id:
		household_head_id = residents[0] if not residents.is_empty() else ""
		if household_head_id != "":
			resident_roles[household_head_id] = "owner"

func add_guest(citizen_id: String) -> bool:
	if has_space_for_guest():
		if not guests.has(citizen_id) and not residents.has(citizen_id):
			guests.append(citizen_id)
			resident_roles[citizen_id] = "guest"
			return true
	return false

func remove_guest(citizen_id: String) -> void:
	guests.erase(citizen_id)
	resident_roles.erase(citizen_id)

func remove_occupant(citizen_id: String) -> void:
	remove_resident(citizen_id)
	remove_guest(citizen_id)

func add_production_order(item_id: String, count: int = 1, maintain_stock: int = 0) -> Dictionary:
	var recipe = EquipmentDB.RECIPES.get(item_id, {})
	if recipe.is_empty():
		return {"success": false, "reason": "Неизвестный рецепт"}
		
	var order_id = "ord_" + item_id + "_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
	var work_sec = float(recipe.get("work_days", 1.0)) * 120.0 # 120 сек работы мастера на партию
	var new_order = {
		"order_id": order_id,
		"item_id": item_id,
		"name": recipe.get("name", item_id),
		"count": count,
		"maintain_stock": maintain_stock,
		"work_required": work_sec,
		"work_progress": 0.0,
		"cost": recipe.get("cost", {}).duplicate(),
		"materials_delivered": {},
		"status": "pending"
	}
	production_queue.append(new_order)
	add_history_entry(GameManager.current_year if GameManager else 1, "Заказано производство: %s (%d шт.)" % [recipe.get("name", item_id), count])
	return {"success": true, "order": new_order}

func cancel_production_order(order_id: String, settlement: RefCounted = null) -> bool:
	for i in range(production_queue.size()):
		var o = production_queue[i]
		if o.get("order_id", "") == order_id:
			if settlement and "economy" in settlement:
				for r in o.get("materials_delivered", {}):
					settlement.economy.add_resource(r, float(o["materials_delivered"][r]))
			production_queue.remove_at(i)
			return true
	return false

func process_production_tick(delta: float, worker_count: int, settlement: RefCounted) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	if production_queue.is_empty() or worker_count <= 0 or settlement == null:
		return completed
		
	var current_order = production_queue[0]
	var cost = current_order.get("cost", {})
	var deliv = current_order.get("materials_delivered", {})
	
	# Проверка доставки материалов
	var needs_materials = false
	for r in cost:
		var req_amt = float(cost[r])
		var del_amt = float(deliv.get(r, 0.0))
		if del_amt < req_amt:
			needs_materials = true
			if settlement.economy.get_resource(r) >= (req_amt - del_amt):
				var take = req_amt - del_amt
				settlement.economy.resources[r] = maxf(0.0, settlement.economy.resources[r] - take)
				deliv[r] = del_amt + take
				current_order["materials_delivered"] = deliv
				needs_materials = false
			break
			
	if needs_materials:
		current_order["status"] = "waiting_materials"
		return completed
		
	current_order["status"] = "in_progress"
	var labor_speed = float(worker_count)
	current_order["work_progress"] = float(current_order.get("work_progress", 0.0)) + delta * labor_speed
	
	var target_work = float(current_order.get("work_required", 60.0))
	if current_order["work_progress"] >= target_work:
		var item_id = current_order["item_id"]
		var item_name = current_order["name"]
		if "equipment_stockpile" in settlement:
			settlement.equipment_stockpile[item_id] = settlement.equipment_stockpile.get(item_id, 0) + 1
		completed.append(current_order)
		add_history_entry(GameManager.current_year if GameManager else 1, "Завершено изготовление: %s" % item_name)
		
		current_order["count"] = int(current_order.get("count", 1)) - 1
		if current_order["count"] <= 0:
			production_queue.remove_at(0)
		else:
			current_order["work_progress"] = 0.0
			current_order["materials_delivered"] = {}
			
	return completed

func store_food(amount: float) -> float:
	var space = maxf(0.0, food_stockpile_max - food_stockpile)
	var added = minf(amount, space)
	food_stockpile += added
	return added

func consume_food(amount: float) -> float:
	var consumed = minf(amount, food_stockpile)
	food_stockpile = maxf(0.0, food_stockpile - consumed)
	return consumed

func serialize() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"settlement_id": settlement_id,
		"pos": [pos.x, pos.y],
		"condition": condition,
		"manager_id": manager_id,
		"workers": workers.duplicate(),
		"residents": residents.duplicate(),
		"guests": guests.duplicate(),
		"max_residents": max_residents,
		"comfort_capacity": comfort_capacity,
		"max_guests": max_guests,
		"household_head_id": household_head_id,
		"resident_roles": resident_roles.duplicate(),
		"domestic_goods": domestic_goods.duplicate(),
		"food_stockpile": food_stockpile,
		"food_stockpile_max": food_stockpile_max,
		"is_locked_by_player": is_locked_by_player,
		"active_mode": active_mode,
		"production_queue": production_queue.duplicate(true),
		"unlocked_upgrades": unlocked_upgrades.duplicate(),
		"specialization": specialization,
		"active_modifiers": active_modifiers.duplicate(true),
		"event_history": event_history.duplicate(true),
		"active_events": active_events.duplicate(true),
		"pending_upgrade": pending_upgrade.duplicate(true),
		"construction_year": construction_year
	}

func deserialize(data: Dictionary) -> void:
	id = data.get("id", id)
	type = data.get("type", type)
	settlement_id = data.get("settlement_id", settlement_id)
	var p = data.get("pos", [pos.x, pos.y])
	pos = Vector2i(p[0], p[1])
	condition = data.get("condition", 100.0)
	manager_id = data.get("manager_id", "")
	workers.assign(data.get("workers", []))
	residents.assign(data.get("residents", []))
	guests.assign(data.get("guests", []))
	var b_info = BuildingDB.get_building(type)
	var default_max_res = b_info.get("housing", 0) if not b_info.is_empty() else 0
	var default_comfort = b_info.get("comfort_housing", 6 if type == "hut" else default_max_res) if not b_info.is_empty() else 0
	var default_guests = b_info.get("max_guests", maxi(2, int(ceil(default_max_res * 0.25))) if default_max_res > 0 else 0) if not b_info.is_empty() else 0

	max_residents = data.get("max_residents", default_max_res)
	comfort_capacity = data.get("comfort_capacity", default_comfort)
	max_guests = data.get("max_guests", default_guests)
	household_head_id = data.get("household_head_id", "")
	resident_roles = data.get("resident_roles", {}).duplicate()
	domestic_goods = data.get("domestic_goods", {}).duplicate()
	food_stockpile = float(data.get("food_stockpile", 0.0))
	food_stockpile_max = float(data.get("food_stockpile_max", food_stockpile_max))
	is_locked_by_player = bool(data.get("is_locked_by_player", false))
	active_mode = data.get("active_mode", active_mode)
	production_queue.assign(data.get("production_queue", []))
	unlocked_upgrades.assign(data.get("unlocked_upgrades", []))
	specialization = data.get("specialization", "")
	active_modifiers = data.get("active_modifiers", {}).duplicate(true)
	event_history.assign(data.get("event_history", []))
	active_events.assign(data.get("active_events", []))
	pending_upgrade = data.get("pending_upgrade", {}).duplicate(true)
	construction_year = data.get("construction_year", 1)
	
	# Миграция старых данных жителей (P01.3):
	if household_head_id == "" and not residents.is_empty():
		household_head_id = residents[0]
	for res_id in residents:
		if not resident_roles.has(res_id):
			resident_roles[res_id] = "owner" if res_id == household_head_id else "resident"
	for gst_id in guests:
		if not resident_roles.has(gst_id):
			resident_roles[gst_id] = "guest"

