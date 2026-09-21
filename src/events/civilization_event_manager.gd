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
var settlement: RefCounted = null

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
			if ev_id == "HUT-01":
				var hut_ctx = check_hut_dispute_trigger(settlement)
				if hut_ctx.is_empty():
					continue
			elif ev_id == "HUT-02":
				var hut2_ctx = check_hut_02_dispute_trigger(settlement)
				if hut2_ctx.is_empty():
					continue
			eligible.append(ev)
			
	if eligible.is_empty():
		return
		
	# Сортируем по приоритету (наивысший в начале)
	eligible.sort_custom(func(a, b): return a.get("priority", 50) > b.get("priority", 50))
	
	var chosen_event = eligible[0]
	var event_context = {}
	if chosen_event.get("id", "") == "HUT-01":
		event_context = check_hut_dispute_trigger(settlement)
	elif chosen_event.get("id", "") == "HUT-02":
		event_context = check_hut_02_dispute_trigger(settlement)
	trigger_event(chosen_event, event_context)

func check_hut_dispute_trigger(p_settlement: RefCounted) -> Dictionary:
	if not p_settlement or not ("id" in p_settlement):
		return {}
	if not GameManager or not GameManager.building_instances:
		return {}
	for b in GameManager.building_instances.values():
		if not b or b.settlement_id != p_settlement.id or b.type != "hut":
			continue
		if b.residents.size() >= 2:
			var c0 = _find_citizen(p_settlement.population, b.residents[0])
			var c1 = _find_citizen(p_settlement.population, b.residents[1])
			if c0 and c1:
				return {
					"target_building_id": b.id,
					"actor_ids": [c0.id, c1.id],
					"actor_names": [c0.name, c1.name],
					"causes": ["Нехватка жилплощади в поселении", "Претензия на право первого очага"],
					"context_data": {
						"building_id": b.id,
						"actor_0": c0.name,
						"actor_1": c1.name
					}
				}
	return {}

func check_hut_02_dispute_trigger(p_settlement: RefCounted) -> Dictionary:
	if not p_settlement or not ("id" in p_settlement):
		return {}
	if not GameManager or not GameManager.building_instances:
		return {}
	for b in GameManager.building_instances.values():
		if not b or b.settlement_id != p_settlement.id or b.type != "hut":
			continue
		if b.residents.size() >= 2:
			var cause = ""
			if b.food_stockpile < 1.5:
				cause = "Нехватка припасов и спор о доле в котле"
			elif b.is_crowded():
				cause = "Теснота и спор о личном пространстве"
			elif b.has_unresolved_dispute():
				cause = "Старая неприязнь и нерешённый спор о правах на дом"
			
			if cause != "":
				var c0 = _find_citizen(p_settlement.population, b.residents[0])
				var c1 = _find_citizen(p_settlement.population, b.residents[1])
				if c0 and c1:
					return {
						"target_building_id": b.id,
						"actor_ids": [c0.id, c1.id],
						"actor_names": [c0.name, c1.name],
						"causes": [cause],
						"context_data": {
							"building_id": b.id,
							"actor_0": c0.name,
							"actor_1": c1.name,
							"dispute_cause": cause
						}
					}
	return {}

func _check_event_conditions(conds: Dictionary, total_days: int, settlement: RefCounted) -> bool:
	if conds.is_empty():
		return true
	if conds.has("min_days") and total_days < int(conds["min_days"]):
		return false
	if conds.has("required_event_resolved"):
		var req_ev = conds["required_event_resolved"]
		if not triggered_events.has(req_ev):
			return false
	if conds.has("required_choice"):
		var req_c = conds["required_choice"] # {"event_id": "...", "choice_id": "..."}
		var found_choice = false
		for rev in resolved_events:
			if rev.get("template_id", "") == req_c.get("event_id", "") and rev.get("chosen_choice_id", "") == req_c.get("choice_id", ""):
				found_choice = true
				break
		if not found_choice:
			return false
	if conds.has("forbidden_choice"):
		var forb_c = conds["forbidden_choice"]
		for rev in resolved_events:
			if rev.get("template_id", "") == forb_c.get("event_id", "") and rev.get("chosen_choice_id", "") == forb_c.get("choice_id", ""):
				return false
	if settlement != null:
		if conds.has("min_population") and "population" in settlement and settlement.population.get_total_population() < int(conds["min_population"]):
			return false
		if conds.has("min_wood") and "economy" in settlement and settlement.economy.get_resource("wood") < float(conds["min_wood"]):
			return false
		if conds.has("min_food") and "economy" in settlement and settlement.economy.get_resource("food") < float(conds["min_food"]):
			return false
		if conds.has("min_stone") and "economy" in settlement and settlement.economy.get_resource("stone") < float(conds["min_stone"]):
			return false
		if conds.has("min_iron") and "economy" in settlement and settlement.economy.get_resource("iron") < float(conds["min_iron"]):
			return false
		if conds.has("required_building") and "buildings" in settlement and not settlement.buildings.has(conds["required_building"]):
			return false
		if conds.has("min_huts"):
			var hut_cnt = 0
			if GameManager and GameManager.building_instances:
				for b in GameManager.building_instances.values():
					if b and b.settlement_id == settlement.id and b.type == "hut":
						hut_cnt += 1
			if hut_cnt < int(conds["min_huts"]):
				return false
	elif conds.has("min_iron") or conds.has("required_building") or conds.has("min_huts"):
		return false
	return true

func trigger_event(ev: Dictionary, context: Dictionary = {}) -> String:
	if ev.is_empty():
		return ""
	var template_id = ev.get("id", "")
	if template_id == "":
		return ""
	var instance_id = "%s#%d" % [template_id, next_instance_number]
	next_instance_number += 1
	var instance = ev.duplicate(true)
	instance["template_id"] = template_id
	instance["instance_id"] = instance_id
	instance["status"] = "pending"
	instance["created_day"] = GameManager.total_simulation_days
	instance["resolved_day"] = -1
	instance["chosen_choice_id"] = ""
	instance["actor_ids"] = context.get("actor_ids", instance.get("actor_ids", []))
	instance["actor_names"] = context.get("actor_names", instance.get("actor_names", []))
	instance["target_building_id"] = context.get("target_building_id", instance.get("target_building_id", ""))
	instance["causes"] = context.get("causes", instance.get("causes", []))
	instance["context_data"] = context.get("context_data", instance.get("context_data", {}))
	
	# Форматирование шаблонов {key} в заголовке и описании
	if not context.is_empty() and context.has("context_data"):
		var c_data = context["context_data"]
		for key in ["title", "description"]:
			if instance.has(key) and instance[key] is String:
				var txt: String = instance[key]
				for ctx_k in c_data:
					txt = txt.replace("{" + ctx_k + "}", str(c_data[ctx_k]))
				instance[key] = txt

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
	return instance_id

func apply_choice(instance_id: String, choice_id: String, extra_data: Dictionary = {}) -> void:
	var ev: Dictionary = event_instances.get(instance_id, {})
	if ev.is_empty() or ev.get("status", "") != "pending":
		return
	var cur_settlement: RefCounted = settlement
	if cur_settlement == null:
		cur_settlement = GameManager.settlements.get(GameManager.player_faction_id + "_settlement", null)
	if not _check_event_conditions(ev.get("conditions", {}), GameManager.total_simulation_days, cur_settlement):
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
		
	# 5. Применение реальных последствий (отношения, верность, память, жильё, ресурсы)
	var consequences = chosen_choice.get("consequences", {})
	if not consequences.is_empty():
		_apply_choice_consequences(ev, chosen_choice, consequences, cur_settlement)
		
	if ev.get("status", "") == "resolved":
		return

	# 6. Запись в глобальную историю игры
	GameManager.add_history_entry(cur_year, title, "Народ постановил: «%s»" % choice_title, category)
	
	# 7. Всплывающее уведомление
	EventBus.notification_toast.emit("🏛 Выбор народа: %s" % title, "Принято решение: %s" % choice_title, "good")
	
	ev["status"] = "resolved"
	ev["resolved_day"] = GameManager.total_simulation_days
	ev["chosen_choice_id"] = choice_id
	event_instances[instance_id] = ev
	resolved_events.append(ev.duplicate(true))
	if active_event.get("instance_id", "") == instance_id:
		active_event.clear()
	choice_applied.emit(instance_id, choice_id)

func _find_citizen(pop: RefCounted, cit_id: String) -> CitizenNPC:
	if not pop or not ("citizens" in pop):
		return null
	for c in pop.citizens:
		if c.id == cit_id:
			return c
	return null

func _resolve_placeholder_str(val: String, ev: Dictionary) -> String:
	var actor_ids = ev.get("actor_ids", [])
	for idx in range(actor_ids.size()):
		val = val.replace("{actor_%d}" % idx, str(actor_ids[idx]))
	var ctx = ev.get("context_data", {})
	for k in ctx:
		val = val.replace("{" + k + "}", str(ctx[k]))
	return val

func _apply_choice_consequences(ev: Dictionary, choice: Dictionary, consequences: Dictionary, settlement: RefCounted) -> void:
	var pop = settlement.population if settlement and "population" in settlement else null
	
	# Отношения между участниками
	if consequences.has("modify_relations") and pop:
		for rel_mod in consequences["modify_relations"]:
			var a_id = _resolve_placeholder_str(rel_mod.get("actor_a", rel_mod.get("from", "")), ev)
			var b_id = _resolve_placeholder_str(rel_mod.get("actor_b", rel_mod.get("to", "")), ev)
			var delta_aff = float(rel_mod.get("delta_affinity", rel_mod.get("delta", 0.0)))
			var delta_resp = float(rel_mod.get("delta_respect", 0.0))
			var cit_a = _find_citizen(pop, a_id)
			var cit_b = _find_citizen(pop, b_id)
			if cit_a and cit_b:
				cit_a.modify_relationship(b_id, delta_aff, delta_resp)
				cit_b.modify_relationship(a_id, delta_aff, delta_resp)
				
	# Изменение верности участников
	if consequences.has("modify_loyalty") and pop:
		for loy_mod in consequences["modify_loyalty"]:
			var act_id = _resolve_placeholder_str(loy_mod.get("actor_id", ""), ev)
			var delta_loy = float(loy_mod.get("delta", 0.0))
			var cit = _find_citizen(pop, act_id)
			if cit:
				cit.loyalty = clampf(cit.loyalty + delta_loy, 0.0, 100.0)
				
	# Добавление памяти участникам
	if consequences.has("modify_memory") and pop:
		for mem_data in consequences["modify_memory"]:
			var act_id = _resolve_placeholder_str(mem_data.get("actor_id", ""), ev)
			var cit = _find_citizen(pop, act_id)
			if cit:
				cit.add_memory(
					mem_data.get("type", "social"),
					mem_data.get("actor", "ruler"),
					mem_data.get("target", ev.get("target_building_id", "")),
					float(mem_data.get("importance", 1.0)),
					mem_data.get("desc", ""),
					mem_data.get("permanent", false)
				)
				
	# Изменение статуса владения зданием (housing_tenure)
	if consequences.has("housing_tenure"):
		var tenure = consequences["housing_tenure"]
		var b_id = ev.get("target_building_id", "")
		if GameManager and GameManager.building_instances:
			for b_inst in GameManager.building_instances.values():
				if b_inst and (b_inst.id == b_id or b_id == ""):
					if tenure is Dictionary:
						if tenure.has("owner_id"):
							var owner_id = _resolve_placeholder_str(str(tenure["owner_id"]), ev)
							b_inst.household_head_id = owner_id
							b_inst.resident_roles[owner_id] = "Владелец"
						if tenure.has("tenant_ids"):
							for tid in tenure["tenant_ids"]:
								var res_tid = _resolve_placeholder_str(str(tid), ev)
								b_inst.resident_roles[res_tid] = "Жилец"
						if tenure.has("dependent_ids"):
							for did in tenure["dependent_ids"]:
								var res_did = _resolve_placeholder_str(str(did), ev)
								b_inst.resident_roles[res_did] = "Зависимый"
						if tenure.has("co_owners"):
							for co_id in tenure["co_owners"]:
								var res_coid = _resolve_placeholder_str(str(co_id), ev)
								b_inst.resident_roles[res_coid] = "Совладелец"
					else:
						b_inst.active_modifiers["housing_tenure"] = tenure
					b_inst.add_history_entry(GameManager.current_year, "Установлен статус владения: %s" % str(tenure))
					
	# Изменение ресурсов поселения
	if consequences.has("modify_resources") and settlement and "economy" in settlement:
		for res_k in consequences["modify_resources"]:
			var amt = float(consequences["modify_resources"][res_k])
			if amt > 0.0:
				settlement.deposit_resource(res_k, amt, "Решение: " + choice.get("title", ""))
			elif amt < 0.0:
				settlement.economy.resources[res_k] = maxf(0.0, settlement.economy.get_resource(res_k) + amt)
		if settlement.faction_id == GameManager.player_faction_id:
			EventBus.resources_updated.emit(settlement.faction_id, settlement.economy.resources)

	# Решение суда общины (council_vote)
	if consequences.get("council_vote", false) and pop:
		var actor_ids = ev.get("actor_ids", [])
		if actor_ids.size() >= 2:
			var act_0_id = _resolve_placeholder_str(str(actor_ids[0]), ev)
			var act_1_id = _resolve_placeholder_str(str(actor_ids[1]), ev)
			var cit_0 = _find_citizen(pop, act_0_id)
			var cit_1 = _find_citizen(pop, act_1_id)
			if cit_0 and cit_1:
				var votes_0 = 0
				var votes_1 = 0
				var score_0 = cit_0.personality.get("pride", 50.0) * 0.5 + cit_0.skill_builder * 2.0
				var score_1 = cit_1.personality.get("sociability", 50.0) * 0.5 + (100.0 - cit_1.personality.get("greed", 50.0)) * 0.5
				for c in pop.citizens:
					if c.is_alive and c.cohort in ["youth", "adult", "elder"]:
						var aff_0 = c.get_relationship_affinity(act_0_id)
						var aff_1 = c.get_relationship_affinity(act_1_id)
						if (aff_0 + score_0 * 0.1) >= (aff_1 + score_1 * 0.1):
							votes_0 += 1
						else:
							votes_1 += 1
				
				var b_id = ev.get("target_building_id", "")
				var b_inst = null
				if GameManager and GameManager.building_instances:
					b_inst = GameManager.building_instances.get(b_id, null)
				
				if votes_0 >= votes_1:
					if b_inst:
						b_inst.household_head_id = act_0_id
						b_inst.resident_roles[act_0_id] = "Владелец"
						b_inst.resident_roles[act_1_id] = "Жилец"
						b_inst.active_modifiers["council_verdict"] = "property"
						b_inst.add_history_entry(GameManager.current_year, "Совет общины признал права строителя (%d против %d)" % [votes_0, votes_1])
					cit_0.loyalty = clampf(cit_0.loyalty + 10.0, 0.0, 100.0)
					cit_1.modify_relationship(act_0_id, -15.0, 5.0)
					cit_0.add_memory("gratitude", "council", b_id, 1.0, "Совет племени признал дом нашей собственностью", true)
					cit_1.add_memory("acceptance", "council", b_id, 0.8, "Совет племени решил дело в пользу строителя", false)
				else:
					if b_inst:
						b_inst.resident_roles[act_0_id] = "Совладелец"
						b_inst.resident_roles[act_1_id] = "Совладелец"
						b_inst.active_modifiers["council_verdict"] = "communal"
						b_inst.add_history_entry(GameManager.current_year, "Совет общины объявил дом общим (%d против %d)" % [votes_1, votes_0])
					cit_1.loyalty = clampf(cit_1.loyalty + 10.0, 0.0, 100.0)
					cit_0.modify_relationship(act_1_id, -10.0, 0.0)
					cit_1.add_memory("gratitude", "council", b_id, 1.0, "Совет племени защитил наш кров в общем доме", true)
					cit_0.add_memory("disappointment", "council", b_id, 0.8, "Совет племени не отдал дом в единоличную собственность", false)

	# Выселение жильцов (evict_tenants)
	if consequences.has("evict_tenants"):
		var b_id = ev.get("target_building_id", "")
		var b_inst = GameManager.building_instances.get(b_id, null) if GameManager and GameManager.building_instances else null
		for raw_t in consequences["evict_tenants"]:
			var tid = _resolve_placeholder_str(str(raw_t), ev)
			if b_inst:
				b_inst.remove_resident(tid)
				b_inst.add_history_entry(GameManager.current_year if GameManager else 1, "Жилец %s выселен по указу вождя" % tid)
			var c = _find_citizen(pop, tid) if pop else null
			if c:
				c.home_id = ""
				c.last_status_reason = "Выселен из дома, без крова"
		if b_inst:
			b_inst.active_modifiers.erase("unresolved_housing_dispute")

	# Защита прав жильцов (protect_tenants)
	if consequences.get("protect_tenants", false):
		var b_id = ev.get("target_building_id", "")
		var b_inst = GameManager.building_instances.get(b_id, null) if GameManager and GameManager.building_instances else null
		if b_inst:
			b_inst.active_modifiers["protected_tenancy"] = true
			b_inst.active_modifiers.erase("unresolved_housing_dispute")
			b_inst.add_history_entry(GameManager.current_year if GameManager else 1, "Вождь защитил право жильцов на кров")

	# Приказ разделить дом перегородкой (partition_hut)
	if consequences.get("partition_hut", false):
		var b_id = ev.get("target_building_id", "")
		var b_inst = GameManager.building_instances.get(b_id, null) if GameManager and GameManager.building_instances else null
		if b_inst:
			b_inst.active_modifiers["partitioned"] = true
			b_inst.active_modifiers.erase("unresolved_housing_dispute")
			b_inst.add_history_entry(GameManager.current_year if GameManager else 1, "В доме возведена внутренняя перегородка за счёт общины")

	# Бытовая драка при невмешательстве (domestic_brawl)
	if consequences.get("domestic_brawl", false):
		var b_id = ev.get("target_building_id", "")
		var b_inst = GameManager.building_instances.get(b_id, null) if GameManager and GameManager.building_instances else null
		if b_inst:
			b_inst.active_modifiers["unresolved_housing_dispute"] = true
			b_inst.add_history_entry(GameManager.current_year if GameManager else 1, "В доме произошла драка жильцов")
		var actor_ids = ev.get("actor_ids", [])
		if pop:
			for raw_act in actor_ids:
				var a_id = _resolve_placeholder_str(str(raw_act), ev)
				var c = _find_citizen(pop, a_id)
				if c:
					c.health = maxf(1.0, c.health - 15.0)
					c.last_status_reason = "Пострадал в домашней драке"
					c.add_memory("injury", "brawl", b_id, 1.0, "Пострадал в домашней драке из-за спорной крыши", false)

	# Невмешательство из карточки выбора
	if consequences.get("no_intervention", false):
		resolve_without_intervention(ev.get("instance_id", ""))

func defer_event(instance_id: String) -> void:
	var ev: Dictionary = event_instances.get(instance_id, {})
	if ev.is_empty() or ev.get("status", "") != "pending":
		return
	ev["status"] = "deferred"
	ev["deferred_until_day"] = GameManager.total_simulation_days + 3
	event_instances[instance_id] = ev
	if active_event.get("instance_id", "") == instance_id:
		active_event.clear()
	GameManager.add_history_entry(GameManager.current_year, ev.get("title", "Событие"), "Решение отложено на 3 дня.", ev.get("category", "Общее"))
	choice_applied.emit(instance_id, "deferred")

func resolve_without_intervention(instance_id: String) -> void:
	var ev: Dictionary = event_instances.get(instance_id, {})
	if ev.is_empty() or ev.get("status", "") != "pending":
		return
	ev["status"] = "resolved"
	ev["resolved_day"] = GameManager.total_simulation_days
	ev["chosen_choice_id"] = "no_intervention"
	ev["outcome"] = "unresolved_tension"
	
	# Негативные последствия бездействия: напряжение между участниками
	var cur_settlement: RefCounted = settlement
	if cur_settlement == null:
		cur_settlement = GameManager.settlements.get(GameManager.player_faction_id + "_settlement", null)
	var pop = cur_settlement.population if cur_settlement and "population" in cur_settlement else null
	var actor_ids = ev.get("actor_ids", [])
	if pop and actor_ids.size() >= 2:
		for i in range(actor_ids.size()):
			for j in range(i + 1, actor_ids.size()):
				var c1 = _find_citizen(pop, actor_ids[i])
				var c2 = _find_citizen(pop, actor_ids[j])
				if c1 and c2:
					c1.modify_relationship(c2.id, -15.0, -10.0)
					c2.modify_relationship(c1.id, -15.0, -10.0)
	if pop:
		for act_id in actor_ids:
			var c = _find_citizen(pop, act_id)
			if c:
				c.loyalty = maxf(0.0, c.loyalty - 5.0)
				c.add_memory("disappointment", "ruler", ev.get("target_building_id", ""), 0.8, "Правитель уклонился от решения спора в нашем доме", false)
				c.last_status_reason = "Недовольство: спор остался неразрешённым"

	var b_id = ev.get("target_building_id", "")
	if GameManager and GameManager.building_instances:
		for b_inst in GameManager.building_instances.values():
			if b_inst and b_inst.id == b_id:
				b_inst.active_modifiers["unresolved_housing_dispute"] = true
				b_inst.add_history_entry(GameManager.current_year, "Спор остался неразрешённым (правитель не вмешался)")

	event_instances[instance_id] = ev
	resolved_events.append(ev.duplicate(true))
	if active_event.get("instance_id", "") == instance_id:
		active_event.clear()
	GameManager.add_history_entry(GameManager.current_year, ev.get("title", "Событие"), "Правитель не вмешался (сохраняется напряжение).", ev.get("category", "Общее"))
	choice_applied.emit(instance_id, "no_intervention")

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
