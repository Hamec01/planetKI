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

# --- ДОМОХОЗЯЙСТВО, ЖИЛЬЦЫ И ЗАПАСЫ (S06) ---
var residents: Array[String] = [] # IDs постоянных членов домохозяйства
var guests: Array[String] = [] # IDs временных гостей (гостевое проживание)
var max_residents: int = 8
var max_guests: int = 2
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
		max_guests = maxi(2, int(ceil(max_residents * 0.25)))
		food_stockpile_max = float(max_residents * 2)
	elif type == "elders_house":
		max_residents = 4
		max_guests = 2
		food_stockpile_max = 12.0
	else:
		max_residents = 0
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

func get_total_occupants() -> int:
	return residents.size() + guests.size()

func get_total_capacity() -> int:
	return max_residents + max_guests

func has_space_for_resident() -> bool:
	return residents.size() < max_residents

func has_space_for_guest() -> bool:
	return get_total_occupants() < get_total_capacity()

func add_resident(citizen_id: String) -> bool:
	if has_space_for_resident():
		if not residents.has(citizen_id):
			guests.erase(citizen_id)
			residents.append(citizen_id)
			return true
	return false

func remove_resident(citizen_id: String) -> void:
	residents.erase(citizen_id)

func add_guest(citizen_id: String) -> bool:
	if has_space_for_guest():
		if not guests.has(citizen_id) and not residents.has(citizen_id):
			guests.append(citizen_id)
			return true
	return false

func remove_guest(citizen_id: String) -> void:
	guests.erase(citizen_id)

func remove_occupant(citizen_id: String) -> void:
	residents.erase(citizen_id)
	guests.erase(citizen_id)

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
		"max_guests": max_guests,
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
	max_residents = data.get("max_residents", max_residents)
	max_guests = data.get("max_guests", max_guests)
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

