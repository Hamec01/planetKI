class_name CivilizationEventManager
extends RefCounted

# ==============================================================================
# PLANETKI — CENTRALIZED CIVILIZATION EVENT ENGINE
# Управляет проверкой условий, цепочками, приоритетами и эффектами событий
# ==============================================================================

var triggered_events: Array[String] = []
var chain_cooldowns: Dictionary = {}
var active_event: Dictionary = {}
var event_queue: Array[Dictionary] = []
var event_instances: Dictionary = {}
var resolved_events: Array[Dictionary] = []
var next_instance_number: int = 1

signal event_triggered(event_data: Dictionary)
signal choice_applied(event_id: String, choice_id: String)

func reset() -> void:
	triggered_events.clear()
	chain_cooldowns.clear()
	active_event.clear()
	event_queue.clear()
	event_instances.clear()
	resolved_events.clear()
	next_instance_number = 1

# Ежедневная проверка условий запуска фундаментальных событий
func process_daily_triggers(current_day: int, total_days: int, settlement: RefCounted) -> void:
	# Если уже есть активное ожидающее решение событие — не спамим
	if not active_event.is_empty():
		return
		
	# Уменьшаем кулдауны цепочек
	for ch in chain_cooldowns.keys():
		chain_cooldowns[ch] = max(0, chain_cooldowns[ch] - 1)
		if chain_cooldowns[ch] <= 0:
			chain_cooldowns.erase(ch)
			
	var culture: CultureMemory = GameManager.culture_memory
	if culture == null:
		return
		
	var eligible: Array[Dictionary] = []
	
	for ev in CivilizationEventDB.get_all_events():
		var ev_id = ev["id"]
		var chain_id = ev.get("chain_id", "")
		var is_once = ev.get("once", true)
		
		if is_once and triggered_events.has(ev_id):
			continue
			
		if chain_cooldowns.has(chain_id) and chain_cooldowns[chain_id] > 0:
			continue
			
		var ex_group = ev.get("exclusive_group", "")
		if ex_group != "" and culture.get_group_value(ex_group) != "UNDEFINED":
			# Решение по этой теме уже принято в обществе
			continue
			
		var conds = ev.get("conditions", {})
		if _check_event_conditions(conds, total_days, settlement):
			eligible.append(ev)
			
	if eligible.is_empty():
		return
		
	# Сортируем по приоритету (наивысший в начале)
	eligible.sort_custom(func(a, b): return a.get("priority", 50) > b.get("priority", 50))
	
	var chosen_event = eligible[0]
	trigger_event(chosen_event)

func _check_event_conditions(conds: Dictionary, total_days: int, _settlement: RefCounted) -> bool:
	var min_days = conds.get("min_days", 0)
	if total_days < min_days:
		return false
	return true

func trigger_event(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	var template_id = ev.get("id", "")
	if template_id == "":
		return
	var instance_id = "%s#%d" % [template_id, next_instance_number]
	next_instance_number += 1
	var instance = ev.duplicate(true)
	instance["template_id"] = template_id
	instance["instance_id"] = instance_id
	instance["status"] = "pending"
	instance["created_day"] = GameManager.total_simulation_days
	instance["resolved_day"] = -1
	instance["chosen_choice_id"] = ""
	active_event = instance.duplicate(true)
	event_instances[instance_id] = instance
	if not triggered_events.has(template_id):
		triggered_events.append(template_id)
		
	var chain_id = instance.get("chain_id", "")
	if chain_id != "":
		chain_cooldowns[chain_id] = 10 # 10 дней кулдаун на следующую ступень цепочки
		
	event_triggered.emit(active_event)
	if EventBus:
		EventBus.civilization_event_triggered.emit(active_event)

func apply_choice(instance_id: String, choice_id: String, extra_data: Dictionary = {}) -> void:
	var ev: Dictionary = event_instances.get(instance_id, {})
	if ev.is_empty() or ev.get("status", "") != "pending":
		return
	var settlement: RefCounted = GameManager.settlements.get(GameManager.player_faction_id + "_settlement", null)
	if not _check_event_conditions(ev.get("conditions", {}), GameManager.total_simulation_days, settlement):
		ev["status"] = "obsolete"
		ev["resolved_day"] = GameManager.total_simulation_days
		event_instances[instance_id] = ev
		resolved_events.append(ev.duplicate(true))
		if active_event.get("instance_id", "") == instance_id:
			active_event.clear()
		EventBus.notification_toast.emit("Ситуация изменилась", "Выбранное действие больше не актуально.", "info")
		return
		
	var chosen_choice: Dictionary = {}
	for c in ev.get("choices", []):
		if c["id"] == choice_id:
			chosen_choice = c
			break
			
	if chosen_choice.is_empty():
		return
		
	var culture: CultureMemory = GameManager.culture_memory
	var cur_year = GameManager.current_year
	var cur_day = GameManager.current_day
	
	var group_name = ev.get("exclusive_group", "")
	var group_value = chosen_choice.get("group_value", "")
	var template_id = ev.get("template_id", instance_id)
	var tradition_id = chosen_choice.get("tradition_id", template_id + "_" + choice_id)
	var title = ev.get("title", "Событие")
	var choice_title = chosen_choice.get("title", "Выбор")
	var category = ev.get("category", "Общее")
	
	# 1. Запись в CultureMemory
	culture.set_tradition(tradition_id, group_name, group_value, title, template_id, choice_title, category, cur_year, cur_day)
	
	# 2. Обработка религии
	if group_name == "religion_base":
		culture.religion_data["defined"] = true
		culture.religion_data["type"] = group_value
		culture.religion_data["established_year"] = cur_year
		match group_value:
			"ANIMISM":
				culture.religion_data["name"] = "Культ духов природы"
			"MONOTHEISM":
				var god_name = extra_data.get("deity_name", "Творец Небес")
				culture.religion_data["name"] = "Вера в %s" % god_name
				culture.religion_data["deity_name"] = god_name
			"POLYTHEISM":
				var pantheon = extra_data.get("pantheon_name", "Великий Пантеон")
				culture.religion_data["name"] = pantheon
				culture.religion_data["pantheon_name"] = pantheon
			"ANCESTOR_WORSHIP":
				culture.religion_data["name"] = "Почитание предков"
			"EARLY_RATIONALISM":
				culture.religion_data["name"] = "Естественный разум"
				
	# 3. Разблокировка специальных зданий
	var unlock_b = chosen_choice.get("unlock_building", "")
	if unlock_b != "":
		culture.unlock_building(unlock_b)
		
	# 4. Разблокировка практик
	var unlock_p = chosen_choice.get("unlock_practice", "")
	if unlock_p != "":
		culture.unlock_practice(unlock_p)
		
	# 5. Запись в глобальную историю игры
	GameManager.add_history_entry(cur_year, title, "Народ постановил: «%s»" % choice_title, category)
	
	# 6. Всплывающее уведомление
	EventBus.notification_toast.emit("🏛 Выбор народа: %s" % title, "Принято решение: %s" % choice_title, "good")
	
	ev["status"] = "resolved"
	ev["resolved_day"] = GameManager.total_simulation_days
	ev["chosen_choice_id"] = choice_id
	event_instances[instance_id] = ev
	resolved_events.append(ev.duplicate(true))
	if active_event.get("instance_id", "") == instance_id:
		active_event.clear()
	choice_applied.emit(instance_id, choice_id)

func defer_event(instance_id: String) -> void:
	var ev: Dictionary = event_instances.get(instance_id, {})
	if ev.is_empty() or ev.get("status", "") != "pending":
		return
	ev["deferred"] = true
	event_instances[instance_id] = ev
	if active_event.get("instance_id", "") == instance_id:
		active_event.clear()

func resolve_without_intervention(instance_id: String) -> void:
	var ev: Dictionary = event_instances.get(instance_id, {})
	if ev.is_empty() or ev.get("status", "") != "pending":
		return
	ev["status"] = "resolved"
	ev["resolved_day"] = GameManager.total_simulation_days
	ev["chosen_choice_id"] = ""
	ev["outcome"] = "no_intervention"
	event_instances[instance_id] = ev
	resolved_events.append(ev.duplicate(true))
	if active_event.get("instance_id", "") == instance_id:
		active_event.clear()
	GameManager.add_history_entry(GameManager.current_year, ev.get("title", "Событие"), "Правитель не вмешался.", ev.get("category", "Общее"))

func serialize() -> Dictionary:
	return {
		"triggered_events": triggered_events.duplicate(),
		"chain_cooldowns": chain_cooldowns.duplicate(true),
		"active_event": active_event.duplicate(true),
		"event_instances": event_instances.duplicate(true),
		"resolved_events": resolved_events.duplicate(true),
		"next_instance_number": next_instance_number
	}

func deserialize(data: Dictionary) -> void:
	triggered_events.assign(data.get("triggered_events", []))
	chain_cooldowns = data.get("chain_cooldowns", {}).duplicate(true)
	active_event = data.get("active_event", {}).duplicate(true)
	event_instances = data.get("event_instances", {}).duplicate(true)
	resolved_events.assign(data.get("resolved_events", []))
	next_instance_number = int(data.get("next_instance_number", event_instances.size() + 1))
	# Compatibility with saves created before event instances existed.
	if not active_event.is_empty() and event_instances.is_empty():
		var legacy_event = active_event.duplicate(true)
		var legacy_template_id = legacy_event.get("id", "")
		if legacy_template_id != "":
			legacy_event["template_id"] = legacy_template_id
			legacy_event["instance_id"] = "%s#%d" % [legacy_template_id, next_instance_number]
			legacy_event["status"] = "pending"
			next_instance_number += 1
			active_event = legacy_event
			event_instances[legacy_event["instance_id"]] = legacy_event
