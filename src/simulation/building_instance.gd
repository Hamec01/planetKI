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
var size: Vector2i = Vector2i(1, 1)
var visual_offset: Vector2 = Vector2.ZERO # Косметический суб-клеточный сдвиг спрайта (px)
var custom_name: String = ""
var building_data: Dictionary = {}
var tile_coord: Vector2i:
	get: return pos
	set(val): pos = val
var condition: float = 100.0 # 0 - 100%
var is_open: bool = false # Для ворот и проходов (открыто/заперто)

var manager_id: String = "" # ID назначенного мастера/руководителя (напр. "cit_2")
var workers: Array[String] = [] # IDs соплеменников

# --- ДОМОХОЗЯЙСТВО, ЖИЛЬЦЫ И ЗАПАСЫ (S06 / P01.3) ---
var residents: Array[String] = [] # IDs постоянных членов домохозяйства
var guests: Array[String] = [] # IDs временных гостей (гостевое проживание)
var max_residents: int = 8
var comfort_capacity: int = 6
var comfort: float = 20.0 # Уровень уюта жилья (0-100)
var max_guests: int = 2
var household_head_id: String = ""
var resident_roles: Dictionary = {} # citizen_id -> "owner" | "resident" | "guest" | "dependent" | "ward"
var domestic_goods: Dictionary = {} # Личные вещи и материалы домохозяйства
var food_stockpile: float = 0.0 # Домашний запас пищи
var domestic_food_stock: float:
	get: return food_stockpile
	set(val): food_stockpile = val
var food_stockpile_max: float = 16.0 # Целевой запас на 2 дня
var is_locked_by_player: bool = false # Запрет автоматического выселения игроком

# --- БОЛЬШОЙ ДОМ РОДА (GREAT LODGE) СОЦИАЛЬНЫЙ ИНСТИТУТ ---
var visual_variant: int = 1 # 1..9 (рандомно выбирается при постройке из 9 вариаций)
var household_harmony: float = 0.0 # От -100 до +100 (согласие и мир между семьями дома)
var household_groups: Dictionary = {
	"families": {},   # family_id -> [citizen_ids]
	"elders": [],     # [citizen_ids] (возраст >= 60 или без семьи)
	"wards": [],      # [citizen_ids] (сироты под опекой дома)
	"unrelated": [],  # [citizen_ids] (одинокие неродственные жители)
	"children": []    # [citizen_ids] (все дети дома)
}
var caretaker_id: String = "" # ID назначенного Опекуна детей
var knowledge_keeper_id: String = "" # ID Хранителя знаний
var clan_elder_id: String = "" # ID Старейшины рода
var lodge_storage: Dictionary = {"food": 0.0, "hides": 0.0, "clothes": 0.0, "tools": 0.0}
var lodge_storage_mode: String = "family_shared" # "family_private", "family_shared", "all_communal"
var clan_cohesion_bonus: float = 0.0

var active_mode: String = "default"
var production_queue: Array[Dictionary] = [] # Заказы: [{"id": "item_id", "name": "...", "count": 10, "progress": 0.0, "cost": {}}]

var unlocked_upgrades: Array[String] = []
var specialization: String = ""

var active_modifiers: Dictionary = {}
var event_history: Array[Dictionary] = []
var active_events: Array[Dictionary] = []
var construction_year: int = 1

# --- БУФЕР И ИНВЕНТАРЬ ИНСТРУМЕНТОВ ЛАГЕРЯ (P01.8) ---
var local_buffer_wood: float = 0.0
var local_buffer_max: float = 50.0
var tool_inventory: Array[Dictionary] = [] # [{"id": "...", "type": "axe", "name": "...", "durability": 100.0, "max_durability": 100.0, "quality": 1.0, "assigned_to": ""}]

# --- СЕЛЬСКОХОЗЯЙСТВЕННЫЕ ПОЛЯ, ОГОРОДЫ И САДЫ (6 СТАДИЙ РОСТА) ---
var growth_stage: int = 1 # 1..6 (1: Посев/Всходы, 2: Рост, 3: Цветение, 4: Созревание, 5: Спелый урожай, 6: Стерня/Отдых)
var growth_progress: float = 0.0 # 0.0 - 1.0 (внутри текущей стадии)
var stage_duration_days: float = 8.0 # Дней на 1 стадию
var crop_type: String = "wheat" # "wheat", "roots", "vegetables", "herbs", "fruits"
var soil_fertility: float = 90.0 # 0 - 100%
var soil_moisture: float = 65.0 # 0 - 100%
var weeds_level: float = 5.0 # 0 - 100% (сорняки отнимают влагу и урожай)
var seed_stock: float = 25.0 # Запас семян на делянке
var last_harvest_yield: float = 0.0 # Результат последнего сбора
var disease_risk: float = 0.0 # 0 - 100%


func _init_camp_tools() -> void:
	if type == "woodcutter_camp":
		local_buffer_max = 50.0
		local_buffer_wood = 0.0
		tool_inventory.clear()
		for i in range(3):
			tool_inventory.append({
				"id": "axe_%s_%d" % [id, i + 1],
				"type": "axe",
				"name": "Каменный топор",
				"durability": 100.0,
				"max_durability": 100.0,
				"quality": 1.0,
				"assigned_to": ""
			})

func has_available_tool(tool_type: String = "axe") -> bool:
	for t in tool_inventory:
		if t.get("type", "") == tool_type and t.get("assigned_to", "") == "" and float(t.get("durability", 0.0)) > 0.0:
			return true
	return false

func take_tool(tool_type: String = "axe", citizen_id: String = "") -> Dictionary:
	for t in tool_inventory:
		if t.get("type", "") == tool_type and t.get("assigned_to", "") == "" and float(t.get("durability", 0.0)) > 0.0:
			t["assigned_to"] = citizen_id
			return t
	return {}

func return_tool(tool_id: String, current_durability: float) -> void:
	for t in tool_inventory:
		if t.get("id", "") == tool_id:
			t["assigned_to"] = ""
			t["durability"] = maxf(0.0, current_durability)
			break

func can_store_wood(amount: float) -> bool:
	return (local_buffer_wood + amount) <= (local_buffer_max + 0.01)

func is_buffer_full() -> bool:
	return local_buffer_wood >= local_buffer_max

func store_wood(amount: float) -> float:
	var space = maxf(0.0, local_buffer_max - local_buffer_wood)
	var added = minf(amount, space)
	local_buffer_wood += added
	return added

func take_wood(request_amount: float) -> float:
	var taken = minf(request_amount, local_buffer_wood)
	local_buffer_wood = maxf(0.0, local_buffer_wood - taken)
	return taken

func _init(p_id: String = "", p_type: String = "", p_settlement: String = "", p_pos: Vector2i = Vector2i.ZERO) -> void:
	id = p_id
	type = p_type
	settlement_id = p_settlement
	pos = p_pos
	condition = 100.0
	construction_year = GameManager.current_year if GameManager else 1
	_init_housing_capacity()
	_init_default_mode()
	_init_camp_tools()
	if GameManager and GameManager.culture_memory:
		for up in GameManager.culture_memory.get_global_unlocked_upgrades(type):
			unlock_upgrade(up)

func _init_housing_capacity() -> void:
	if type == "great_lodge":
		max_residents = 35
		comfort_capacity = 25
		max_guests = 5
		food_stockpile_max = 70.0
		visual_variant = randi_range(1, 9)
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
		var b_info = BuildingDB.get_building(type)
		if b_info.has("housing") and b_info["housing"] > 0:
			max_residents = b_info["housing"]
			comfort_capacity = b_info.get("comfort_housing", 6 if type == "hut" else max_residents)
			max_guests = b_info.get("max_guests", maxi(2, int(ceil(max_residents * 0.25))))
			food_stockpile_max = float(max_residents * 2)
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
		"foraging_post": active_mode = "forage"
		"primitive_garden": active_mode = "mixed_herbs"
		"primitive_field", "wheat_field": active_mode = "wheat"
		"threshing_floor": active_mode = "threshing"
		"quern_house": active_mode = "fine_flour"
		"bakery": active_mode = "bread"
		"orchard": active_mode = "fruits"
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
		"custom_name": custom_name,
		"building_data": building_data.duplicate(true),
		"type": type,
		"settlement_id": settlement_id,
		"pos": [pos.x, pos.y],
		"visual_offset": [visual_offset.x, visual_offset.y],
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
		"construction_year": construction_year,
		"local_buffer_wood": local_buffer_wood,
		"local_buffer_max": local_buffer_max,
		"tool_inventory": tool_inventory.duplicate(true),
		"visual_variant": visual_variant,
		"household_harmony": household_harmony,
		"caretaker_id": caretaker_id,
		"knowledge_keeper_id": knowledge_keeper_id,
		"clan_elder_id": clan_elder_id,
		"lodge_storage": lodge_storage.duplicate(),
		"lodge_storage_mode": lodge_storage_mode,
		"clan_cohesion_bonus": clan_cohesion_bonus
	}

func deserialize(data: Dictionary) -> void:
	id = data.get("id", id)
	custom_name = data.get("custom_name", custom_name)
	building_data = data.get("building_data", building_data).duplicate(true)
	type = data.get("type", type)
	settlement_id = data.get("settlement_id", settlement_id)
	var p = data.get("pos", [pos.x, pos.y])
	pos = Vector2i(p[0], p[1])
	var vo = data.get("visual_offset", [0.0, 0.0])
	visual_offset = Vector2(vo[0], vo[1])
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
	
	local_buffer_wood = float(data.get("local_buffer_wood", 0.0))
	local_buffer_max = float(data.get("local_buffer_max", 50.0))
	tool_inventory.assign(data.get("tool_inventory", []))
	if type == "woodcutter_camp" and tool_inventory.is_empty():
		_init_camp_tools()

	# Great Lodge данные
	visual_variant = int(data.get("visual_variant", visual_variant))
	household_harmony = float(data.get("household_harmony", household_harmony))
	caretaker_id = data.get("caretaker_id", caretaker_id)
	knowledge_keeper_id = data.get("knowledge_keeper_id", knowledge_keeper_id)
	clan_elder_id = data.get("clan_elder_id", clan_elder_id)
	lodge_storage = data.get("lodge_storage", lodge_storage).duplicate()
	lodge_storage_mode = data.get("lodge_storage_mode", lodge_storage_mode)
	clan_cohesion_bonus = float(data.get("clan_cohesion_bonus", clan_cohesion_bonus))

# --- МЕТОДЫ БОЛЬШОГО ДОМА РОДА (GREAT LODGE) ---
func is_great_lodge() -> bool:
	return type == "great_lodge"

func recalculate_household_groups(population: RefCounted) -> Dictionary:
	household_groups = {
		"families": {},
		"elders": [],
		"wards": [],
		"unrelated": [],
		"children": []
	}
	if not population or not ("citizens" in population):
		return household_groups
		
	for r_id in residents:
		var c = population.get_citizen_by_id(r_id)
		if c == null:
			continue
		var is_child = (c.cohort == "child" or c.age < 16)
		var is_elder = (c.cohort == "elder" or c.age >= 60)
		
		if is_child:
			household_groups["children"].append(c.citizen_id)
		if c.is_ward_of_lodge:
			household_groups["wards"].append(c.citizen_id)
			
		if is_elder:
			household_groups["elders"].append(c.citizen_id)
			
		if c.family_id != "":
			if not household_groups["families"].has(c.family_id):
				household_groups["families"][c.family_id] = []
			household_groups["families"][c.family_id].append(c.citizen_id)
		else:
			if not is_elder and not c.is_ward_of_lodge:
				household_groups["unrelated"].append(c.citizen_id)
				
	return household_groups

func get_comfort_status() -> String:
	var cur = residents.size()
	if cur <= comfort_capacity:
		return "Комфортно"
	elif cur <= 30:
		return "Тесно"
	elif cur <= 35:
		return "Переполнено"
	else:
		return "Критическое перенаселение"

func get_harmony_status_name() -> String:
	if household_harmony >= 70.0:
		return "Единый род"
	elif household_harmony >= 30.0:
		return "Мирное сосуществование"
	elif household_harmony >= 0.0:
		return "Безразличие"
	elif household_harmony >= -30.0:
		return "Постоянные споры"
	elif household_harmony >= -80.0:
		return "Вражда"
	else:
		return "Раскол рода"

func get_harmony_color() -> Color:
	if household_harmony >= 70.0:
		return Color(0.25, 0.9, 0.45) # Ярко-зеленый
	elif household_harmony >= 30.0:
		return Color(0.5, 0.85, 0.7)  # Мятный
	elif household_harmony >= 0.0:
		return Color(0.85, 0.85, 0.5) # Желтоватый
	elif household_harmony >= -30.0:
		return Color(0.95, 0.65, 0.3) # Оранжевый
	elif household_harmony >= -80.0:
		return Color(0.95, 0.4, 0.3)  # Красно-оранжевый
	else:
		return Color(0.9, 0.2, 0.2)   # Темно-красный

func update_household_harmony(delta_days: float, settlement: RefCounted) -> void:
	if not is_great_lodge():
		return
	var cur_res = residents.size()
	var d_harm = 0.0
	
	# Фактор перенаселения
	if cur_res > comfort_capacity:
		var crowding_excess = cur_res - comfort_capacity
		d_harm -= 0.5 * float(crowding_excess) * delta_days
		
	# Фактор перегородок
	if is_upgrade_unlocked("partitions"):
		d_harm += 0.2 * delta_days
		
	# Фактор очага
	if is_upgrade_unlocked("great_hearth"):
		d_harm += 0.3 * delta_days
		
	# Фактор старейшины рода
	if clan_elder_id != "":
		d_harm += 0.4 * delta_days
		
	# Фактор тотемов
	if is_upgrade_unlocked("clan_totems"):
		d_harm += 0.15 * delta_days
		
	household_harmony = clampf(household_harmony + d_harm, -100.0, 100.0)

func transfer_knowledge(apprentice: RefCounted, amount: float, p_settlement: RefCounted = null) -> void:
	if knowledge_keeper_id == "" or apprentice == null:
		return
	var master = null
	if p_settlement != null and "population" in p_settlement:
		master = p_settlement.population.get_citizen_by_id(knowledge_keeper_id)
	if master == null and GameManager:
		if GameManager.settlements.has(settlement_id):
			master = GameManager.settlements[settlement_id].population.get_citizen_by_id(knowledge_keeper_id)
		if master == null:
			for st in GameManager.settlements.values():
				if st and "population" in st:
					master = st.population.get_citizen_by_id(knowledge_keeper_id)
					if master != null:
						break
	if master == null:
		return
	# Ищем самый сильный навык наставника
	var best_skill = ""
	var best_val = 0.0
	for sk in master.skills:
		if float(master.skills[sk]) > best_val:
			best_val = float(master.skills[sk])
			best_skill = sk
	# Профессиональный опыт (рубка, охота, стройка) наставник тоже передаёт
	var best_prof = ""
	var best_prof_val = 0.0
	for pk in master.experience:
		if float(master.experience[pk]) > best_prof_val:
			best_prof_val = float(master.experience[pk])
			best_prof = pk
	if best_prof != "" and best_prof_val > apprentice.get_profession_xp(best_prof):
		var curr_xp = apprentice.get_profession_xp(best_prof)
		apprentice.experience[best_prof] = curr_xp + minf(amount * 0.2, best_prof_val - curr_xp)
	if best_skill != "" and best_val > float(apprentice.skills.get(best_skill, 0.0)):
		var curr = float(apprentice.skills.get(best_skill, 10.0))
		var growth = minf(amount * 0.2, best_val - curr)
		apprentice.skills[best_skill] = minf(100.0, curr + growth)

func add_to_lodge_storage(res_name: String, amount: float) -> void:
	lodge_storage[res_name] = float(lodge_storage.get(res_name, 0.0)) + amount

func take_from_lodge_storage(res_name: String, amount: float) -> float:
	var curr = float(lodge_storage.get(res_name, 0.0))
	var taken = minf(amount, curr)
	lodge_storage[res_name] = maxf(0.0, curr - taken)
	return taken

# --- МЕТОДЫ ОХОТНИЧЬЕГО ЛАГЕРЯ ---
func is_hunting_camp() -> bool:
	return type == "hunting_camp"

func get_butchering_speed_mult() -> float:
	if is_hunting_camp():
		if is_upgrade_unlocked("hunt_master_butcher"):
			return 1.80 # Профессиональный мастер разделывает на 80% быстрее
		elif is_upgrade_unlocked("hunt_butcher_table"):
			return 1.45 # На 45% быстрее разделка на оборудованной площадке
	return 1.0

func get_meat_yield_mult() -> float:
	var mult = 1.0
	if is_hunting_camp():
		if is_upgrade_unlocked("hunt_butcher_table"):
			mult += 0.15 # +15% мяса за счет аккуратной разделки
		if is_upgrade_unlocked("hunt_master_butcher"):
			mult += 0.20 # +20% мяса за счет мастера разделки без потерь
		if is_upgrade_unlocked("hunt_tracking"):
			mult += 0.10 # +10% мяса за счет лучшего выбора добычи
	return mult

func get_fur_bonus() -> int:
	var bonus = 0
	if is_hunting_camp():
		if is_upgrade_unlocked("hunt_fur_rack"):
			bonus += 1 # +1 качественная шкура со зверя при наличии сушилки
		if is_upgrade_unlocked("hunt_master_butcher"):
			bonus += 1 # +1 шкура гарантированно благодаря мастеру разделки
	return bonus

func get_bone_bonus() -> int:
	var bonus = 0
	if is_hunting_camp():
		if is_upgrade_unlocked("hunt_trophies"):
			bonus += 2 # +2 кости и рога для мастерской трофеев
		elif is_upgrade_unlocked("hunt_bone_traps"):
			bonus += 1
	return bonus

func get_hunter_damage_mult() -> float:
	var mult = 1.0
	if is_hunting_camp() and is_upgrade_unlocked("hunt_weapon_rack"):
		mult += 0.25 # +25% к урону охотников благодаря стойке оружия
	return mult

func is_dogs_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_dogs")

func is_smokehouse_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_smokehouse")

func is_outpost_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_outpost")

func is_master_butcher_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_master_butcher")

func is_target_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_target")

func is_mentor_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_mentor")

func is_trophies_unlocked() -> bool:
	return is_hunting_camp() and is_upgrade_unlocked("hunt_trophies")

func get_hunt_radius_mult() -> float:
	if is_hunting_camp() and is_upgrade_unlocked("hunt_outpost"):
		return 1.50 # Дальняя стоянка расширяет радиус на 50%
	return 1.0

func get_hunter_speed_mult() -> float:
	if is_hunting_camp() and is_upgrade_unlocked("hunt_dogs"):
		return 1.50 # Собаки загоняют дичь и ускоряют охоту на 50%
	return 1.0

func get_spoilage_reduction_mult() -> float:
	if is_hunting_camp() and is_upgrade_unlocked("hunt_smokehouse"):
		return 0.20 # Снижает порчу мяса на 80% (копчение)
	return 1.0

# --- СЕЛЬСКОХОЗЯЙСТВЕННЫЕ МЕТОДЫ (ПОЛЯ, ОГОРОДЫ, САДЫ) ---
func is_agricultural() -> bool:
	return type in ["primitive_garden", "primitive_field", "wheat_field", "orchard"]

func get_growth_stage_name() -> String:
	match type:
		"primitive_garden":
			match growth_stage:
				1: return "Прорастание семян (1/6)"
				2: return "Зелёная ботва (2/6)"
				3: return "Цветение грядок (3/6)"
				4: return "Формирование плодов (4/6)"
				5: return "Спелый урожай — Сбор (5/6)"
				6: return "Восстановление делянки (6/6)"
				_: return "Стадия %d" % growth_stage
		"primitive_field", "wheat_field":
			match growth_stage:
				1: return "Вспашка / Посев (1/6)"
				2: return "Зелёные всходы (2/6)"
				3: return "Кущение и рост (3/6)"
				4: return "Высокие колосья (4/6)"
				5: return "Золотая спелость — Жатва (5/6)"
				6: return "Сжатая стерня / Отдых (6/6)"
				_: return "Стадия %d" % growth_stage
		"orchard":
			match growth_stage:
				1: return "Саженцы (1/6)"
				2: return "Густая крона (2/6)"
				3: return "Цветение сада (3/6)"
				4: return "Завязи плодов (4/6)"
				5: return "Спелые плоды — Сбор (5/6)"
				6: return "Отдых деревьев (6/6)"
				_: return "Стадия %d" % growth_stage
		_:
			return "Стадия %d" % growth_stage

func get_growth_texture_id() -> String:
	if type == "primitive_garden":
		return "primitive_garden_stage_%d" % clampi(growth_stage, 1, 6)
	elif type in ["primitive_field", "wheat_field"]:
		return "wheat_field_stage_%d" % clampi(growth_stage, 1, 6)
	return type

func water_crop(amount: float = 25.0) -> void:
	soil_moisture = clampf(soil_moisture + amount, 0.0, 100.0)

func weed_crop(amount: float = 30.0) -> void:
	weeds_level = clampf(weeds_level - amount, 0.0, 100.0)

func fertilize_crop(amount: float = 35.0) -> void:
	soil_fertility = clampf(soil_fertility + amount, 0.0, 100.0)

func harvest_crop(settlement: RefCounted) -> Dictionary:
	if growth_stage != 5:
		return {"harvested": false, "reason": "Урожай ещё не созрел"}
		
	var base_yield = 20.0
	if type in ["primitive_field", "wheat_field"]:
		base_yield = 35.0
		if is_upgrade_unlocked("wheat_ox_plow") or is_upgrade_unlocked("field_ox_plow"):
			base_yield *= 1.5
		elif is_upgrade_unlocked("field_wooden_ard"):
			base_yield *= 1.3
		if is_upgrade_unlocked("wheat_sickles"):
			base_yield *= 1.2
	elif type == "primitive_garden":
		base_yield = 22.0
		if is_upgrade_unlocked("garden_compost"):
			base_yield *= 1.25
	elif type == "orchard":
		base_yield = 28.0
		if is_upgrade_unlocked("orchard_grafting"):
			base_yield *= 1.3
			
	# Модификаторы плодородия, влажности и сорняков
	var fert_mod = clampf(soil_fertility / 80.0, 0.3, 1.5)
	var moist_mod = clampf(soil_moisture / 60.0, 0.4, 1.3)
	var weed_pen = clampf(1.0 - (weeds_level / 150.0), 0.4, 1.0)
	
	var total_yield = base_yield * fert_mod * moist_mod * weed_pen
	last_harvest_yield = total_yield
	
	var gathered_resources: Dictionary = {}
	if settlement and "economy" in settlement:
		if type in ["primitive_field", "wheat_field"]:
			var grain_amt = total_yield * 0.8
			var straw_amt = total_yield * 0.4
			var seeds_amt = total_yield * 0.25
			settlement.economy.add_resource("grain", grain_amt)
			settlement.economy.add_resource("straw", straw_amt)
			settlement.economy.add_resource("seeds", seeds_amt)
			settlement.economy.add_resource("food", grain_amt * 0.5)
			gathered_resources = {"grain": grain_amt, "straw": straw_amt, "seeds": seeds_amt}
			if "add_knowledge" in settlement:
				settlement.add_knowledge("grain_knowledge", 8.0)
				settlement.add_knowledge("cultivation_knowledge", 6.0)
		elif type == "primitive_garden":
			var veg_amt = total_yield * 0.6
			var roots_amt = total_yield * 0.4
			var herbs_amt = total_yield * 0.3
			var seeds_amt = total_yield * 0.2
			settlement.economy.add_resource("food", veg_amt + roots_amt)
			settlement.economy.add_resource("roots", roots_amt)
			settlement.economy.add_resource("herbs", herbs_amt)
			settlement.economy.add_resource("seeds", seeds_amt)
			gathered_resources = {"roots": roots_amt, "herbs": herbs_amt, "seeds": seeds_amt, "food": veg_amt + roots_amt}
			if "add_knowledge" in settlement:
				settlement.add_knowledge("plant_knowledge", 6.0)
				settlement.add_knowledge("cultivation_knowledge", 8.0)
		elif type == "orchard":
			var fruits_amt = total_yield
			settlement.economy.add_resource("food", fruits_amt)
			settlement.economy.add_resource("berries", fruits_amt * 0.5)
			gathered_resources = {"fruits": fruits_amt, "food": fruits_amt}
			if "add_knowledge" in settlement:
				settlement.add_knowledge("plant_knowledge", 8.0)
				
	# Переход на 6 стадию (стерня / отдых) и истощение почвы
	growth_stage = 6
	growth_progress = 0.0
	soil_fertility = clampf(soil_fertility - 15.0, 10.0, 100.0)
	weeds_level = clampf(weeds_level + 15.0, 0.0, 100.0)
	
	var yr = GameManager.current_year if GameManager else 1
	add_history_entry(yr, "Собран урожай (%s): %.1f ед." % [type, total_yield])
	return {"harvested": true, "yield": total_yield, "resources": gathered_resources}

func advance_crop_cycle(delta_days: float, settlement: RefCounted = null) -> Dictionary:
	if not is_agricultural():
		return {}
		
	# 1. Высыхание почвы и рост сорняков
	var evap_rate = 1.2 * delta_days
	if type == "wheat_field" and is_upgrade_unlocked("wheat_irrigation_furrows"):
		evap_rate *= 0.6
	elif type == "primitive_garden" and is_upgrade_unlocked("garden_water_trough"):
		evap_rate *= 0.7
	soil_moisture = clampf(soil_moisture - evap_rate, 0.0, 100.0)
	
	# Сорняки растут быстрее при влажной и плодородной почве
	weeds_level = clampf(weeds_level + (0.8 * delta_days), 0.0, 100.0)
	
	# 2. Если есть работники-земледельцы — они автоматически ухаживают за полем
	var worker_count = workers.size()
	if worker_count > 0:
		# Прополка
		weeds_level = clampf(weeds_level - (1.5 * worker_count * delta_days), 0.0, 100.0)
		# Полив, если почва сухая
		if soil_moisture < 50.0:
			soil_moisture = clampf(soil_moisture + (1.0 * worker_count * delta_days), 0.0, 85.0)
			
	# 3. Продвижение стадии роста
	var growth_speed = 1.0
	# Снижение скорости из-за засухи или сорняков
	if soil_moisture < 20.0:
		growth_speed *= 0.35
	elif soil_moisture < 40.0:
		growth_speed *= 0.7
	if weeds_level > 60.0:
		growth_speed *= 0.6
	if soil_fertility < 30.0:
		growth_speed *= 0.5
		
	var stage_time = stage_duration_days
	if type == "orchard":
		stage_time *= 1.5
		
	growth_progress += (delta_days * growth_speed) / stage_time
	
	var stage_changed = false
	if growth_progress >= 1.0:
		growth_progress = 0.0
		growth_stage += 1
		stage_changed = true
		
		# Если дошли до 7 -> переход в 1 (новый цикл)
		if growth_stage > 6:
			growth_stage = 1
			# На 6 стадии почва восстанавливается
			soil_fertility = clampf(soil_fertility + 10.0, 0.0, 100.0)
			
		var yr = GameManager.current_year if GameManager else 1
		add_history_entry(yr, "Фаза роста изменилась: %s" % get_growth_stage_name())
		
	# Авто-сбор если на поле есть работники на 5 стадии
	if growth_stage == 5 and worker_count > 0:
		harvest_crop(settlement)
		
	return {
		"stage": growth_stage,
		"stage_name": get_growth_stage_name(),
		"stage_changed": stage_changed,
		"fertility": soil_fertility,
		"moisture": soil_moisture,
		"weeds": weeds_level
	}
