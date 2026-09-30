class_name NPCEventReactor
extends RefCounted

# ==============================================================================
# ЦЕНТРАЛЬНЫЙ ДИСПЕТЧЕР СОБЫТИЙ ДЛЯ ЖИВЫХ NPC (PLANETKI / ТЗ РАЗДЕЛ 8)
# ==============================================================================

var settlement: RefCounted = null
var active_event_history: Array[Dictionary] = []

func _init(p_settlement: RefCounted) -> void:
	settlement = p_settlement
	_connect_event_bus()

func _connect_event_bus() -> void:
	if not EventBus:
		return
		
	if not EventBus.civilization_event_triggered.is_connected(_on_civilization_event):
		EventBus.civilization_event_triggered.connect(_on_civilization_event)
		
	if not EventBus.event_resolved.is_connected(_on_event_resolved):
		EventBus.event_resolved.connect(_on_event_resolved)
		
	if not EventBus.person_died.is_connected(_on_person_died):
		EventBus.person_died.connect(_on_person_died)
		
	if not EventBus.law_enacted.is_connected(_on_law_enacted):
		EventBus.law_enacted.connect(_on_law_enacted)
		
	if not EventBus.building_constructed.is_connected(_on_building_constructed):
		EventBus.building_constructed.connect(_on_building_constructed)
		
	if not EventBus.battle_started.is_connected(_on_battle_started):
		EventBus.battle_started.connect(_on_battle_started)
		
	if not EventBus.npc_celebration.is_connected(_on_npc_celebration):
		EventBus.npc_celebration.connect(_on_npc_celebration)

func disconnect_signals() -> void:
	if not EventBus:
		return
	if EventBus.civilization_event_triggered.is_connected(_on_civilization_event):
		EventBus.civilization_event_triggered.disconnect(_on_civilization_event)
	if EventBus.event_resolved.is_connected(_on_event_resolved):
		EventBus.event_resolved.disconnect(_on_event_resolved)
	if EventBus.person_died.is_connected(_on_person_died):
		EventBus.person_died.disconnect(_on_person_died)
	if EventBus.law_enacted.is_connected(_on_law_enacted):
		EventBus.law_enacted.disconnect(_on_law_enacted)
	if EventBus.building_constructed.is_connected(_on_building_constructed):
		EventBus.building_constructed.disconnect(_on_building_constructed)
	if EventBus.battle_started.is_connected(_on_battle_started):
		EventBus.battle_started.disconnect(_on_battle_started)
	if EventBus.npc_celebration.is_connected(_on_npc_celebration):
		EventBus.npc_celebration.disconnect(_on_npc_celebration)

func _get_citizens() -> Array:
	if settlement == null:
		return []
	if settlement.citizens is Dictionary:
		return settlement.citizens.values()
	elif settlement.citizens is Array:
		return settlement.citizens
	return []

func _on_civilization_event(event_data: Dictionary) -> void:
	if settlement == null:
		return
	var s_id = event_data.get("settlement_id", "")
	if s_id != "" and settlement.id != s_id:
		return
		
	var citizens_list = _get_citizens()
	for c in citizens_list:
		if c != null and c.is_alive:
			c.receive_civilization_event(event_data)
			
	_recalculate_settlement_morale()

func _on_event_resolved(event_id: String, choice_index: int, results: Dictionary) -> void:
	if settlement == null:
		return
		
	# Реакции на исход решения берутся из шаблона события; общие npc_reactions уже сработали
	# при появлении события, повторно их не применяем
	var ev_data: Dictionary = results.get("event", {}).duplicate()
	ev_data.erase("npc_reactions")
	ev_data["id"] = event_id
	ev_data["resolved_choice"] = choice_index
	ev_data["results"] = results
	var s_id = ev_data.get("settlement_id", "")
	if s_id != "" and settlement.id != s_id:
		return
	
	var citizens_list = _get_citizens()
	for c in citizens_list:
		if c != null and c.is_alive:
			c.receive_civilization_event(ev_data, [{"choice_index": choice_index}])
			
	_recalculate_settlement_morale()

func _on_person_died(p_settlement_id: String, _reason: String) -> void:
	if settlement == null or (p_settlement_id != "" and settlement.id != p_settlement_id):
		return
		
	# Личная реакция (горе родных, вдовство) выполняется поселением в _notify_citizen_death
	# с конкретным покойным; здесь только пересчёт общего настроя
	_recalculate_settlement_morale()

func _on_law_enacted(faction_id: String, law_id: String) -> void:
	if settlement == null:
		return
	var citizens_list = _get_citizens()
	for c in citizens_list:
		if c != null and c.is_alive:
			c.receive_world_event("law_enacted", {"law_id": law_id})
			
	_recalculate_settlement_morale()

func _on_building_constructed(p_settlement_id: String, building_data: Dictionary) -> void:
	if settlement == null or (p_settlement_id != "" and settlement.id != p_settlement_id):
		return
	var b_name = building_data.get("name", building_data.get("id", "Здание"))
	var citizens_list = _get_citizens()
	for c in citizens_list:
		if c != null and c.is_alive:
			c.receive_world_event("building_constructed", {"building_name": b_name, "building_data": building_data})
			
	_recalculate_settlement_morale()

func _on_battle_started(battle_data: Dictionary) -> void:
	if settlement == null:
		return
	var citizens_list = _get_citizens()
	for c in citizens_list:
		if c != null and c.is_alive:
			c.receive_world_event("attack_started", battle_data)

func _on_npc_celebration(p_settlement_id: String, reason: String, _pos: Vector2) -> void:
	if settlement == null or (p_settlement_id != "" and settlement.id != p_settlement_id):
		return
	var citizens_list = _get_citizens()
	for c in citizens_list:
		if c != null and c.is_alive:
			c.receive_world_event("celebration_started", {"reason": reason})
			
	_recalculate_settlement_morale()

func _recalculate_settlement_morale() -> void:
	if settlement == null:
		return
	var citizens_list = _get_citizens()
	if citizens_list.is_empty():
		return
		
	var total_loyalty = 0.0
	var count = 0
	for c in citizens_list:
		if c != null and c.is_alive:
			total_loyalty += c.loyalty
			count += 1
			
	if count > 0:
		var avg_loyalty = total_loyalty / float(count)
		EventBus.loyalty_changed.emit(settlement.id if "id" in settlement else "player_faction", avg_loyalty)
