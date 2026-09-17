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

signal event_triggered(event_data: Dictionary)
signal choice_applied(event_id: String, choice_id: String)

func reset() -> void:
	triggered_events.clear()
	chain_cooldowns.clear()
	active_event.clear()
	event_queue.clear()

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
	active_event = ev
	var ev_id = ev["id"]
	if not triggered_events.has(ev_id):
		triggered_events.append(ev_id)
		
	var chain_id = ev.get("chain_id", "")
	if chain_id != "":
		chain_cooldowns[chain_id] = 10 # 10 дней кулдаун на следующую ступень цепочки
		
	event_triggered.emit(ev)
	if EventBus:
		EventBus.civilization_event_triggered.emit(ev)

func apply_choice(ev_id: String, choice_id: String, extra_data: Dictionary = {}) -> void:
	var ev = CivilizationEventDB.get_event(ev_id)
	if ev.is_empty():
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
	var tradition_id = chosen_choice.get("tradition_id", ev_id + "_" + choice_id)
	var title = ev.get("title", "Событие")
	var choice_title = chosen_choice.get("title", "Выбор")
	var category = ev.get("category", "Общее")
	
	# 1. Запись в CultureMemory
	culture.set_tradition(tradition_id, group_name, group_value, title, ev_id, choice_title, category, cur_year, cur_day)
	
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
	
	active_event.clear()
	choice_applied.emit(ev_id, choice_id)
