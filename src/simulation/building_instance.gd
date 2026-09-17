class_name BuildingInstance
extends RefCounted

var id: String = ""
var type: String = "" # "forge", "carpenter_workshop", "stone_quarry", "granary", "elders_house", "shrine", "hunting_camp", "training_grounds"
var settlement_id: String = ""
var pos: Vector2i = Vector2i.ZERO
var condition: float = 100.0 # 0 - 100%

var manager_id: String = "" # ID назначенного мастера/руководителя (напр. "cit_2")
var workers: Array[String] = [] # IDs соплеменников

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
	_init_default_mode()

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

func is_upgrade_unlocked(u_id: String) -> bool:
	return unlocked_upgrades.has(u_id)

func unlock_upgrade(u_id: String) -> bool:
	if not is_upgrade_unlocked(u_id):
		unlocked_upgrades.append(u_id)
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
