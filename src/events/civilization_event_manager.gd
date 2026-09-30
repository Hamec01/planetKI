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
var _last_cooldown_day: int = -1  # день последнего уменьшения кулдаунов

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

func process_daily_triggers(current_day: int, total_days: int, p_settlement: RefCounted = null) -> void:
	var cur_settlement = p_settlement
	if cur_settlement == null and GameManager:
		cur_settlement = GameManager.get_player_settlement()
	self.settlement = cur_settlement
	
	# Если уже есть активное ожидающее решение событие — не спамим
	if not active_event.is_empty():
		return

	# Уменьшаем кулдауны цепочек ТОЛЬКО раз в игровой день
	var today = GameManager.total_simulation_days if GameManager else total_days
	if today != _last_cooldown_day:
		_last_cooldown_day = today
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
		if _check_event_conditions(conds, total_days, cur_settlement):
			if ev_id == "HUT-01":
				var hut_ctx = check_hut_dispute_trigger(cur_settlement)
				if hut_ctx.is_empty():
					continue
			elif ev_id == "HUT-02":
				var hut2_ctx = check_hut_02_dispute_trigger(cur_settlement)
				if hut2_ctx.is_empty():
					continue
			elif ev_id == "WC-01":
				var wc1_ctx = check_wc_01_trigger(cur_settlement)
				if wc1_ctx.is_empty():
					continue
			elif ev_id == "NPC-FEUD-01":
				var feud_ctx = check_npc_feud_trigger(cur_settlement)
				if feud_ctx.is_empty():
					continue
				# Глобальный кулдаун на NPC-события — не чаще раза в 30 дней
				if chain_cooldowns.get("npc_event_global", 0) > 0:
					continue
			elif ev_id == "NPC-GOSSIP-01":
				var gossip_ctx = check_npc_gossip_trigger(cur_settlement)
				if gossip_ctx.is_empty():
					continue
				if chain_cooldowns.get("npc_event_global", 0) > 0:
					continue
			eligible.append(ev)
			
	if eligible.is_empty():
		return
		
	# Сортируем по приоритету (строгий строгий порядок без мутации словарей базы данных)
	eligible.sort_custom(func(a, b): 
		var p_a = int(a.get("priority", 50))
		var p_b = int(b.get("priority", 50))
		if p_a != p_b:
			return p_a > p_b
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	
	var chosen_event = eligible[0]
	var event_context = {}
	if chosen_event.get("id", "") == "HUT-01":
		event_context = check_hut_dispute_trigger(cur_settlement)
	elif chosen_event.get("id", "") == "HUT-02":
		event_context = check_hut_02_dispute_trigger(cur_settlement)
	elif chosen_event.get("id", "") == "WC-01":
		event_context = check_wc_01_trigger(cur_settlement)
	elif chosen_event.get("id", "") == "NPC-FEUD-01":
		event_context = check_npc_feud_trigger(cur_settlement)
	elif chosen_event.get("id", "") == "NPC-GOSSIP-01":
		event_context = check_npc_gossip_trigger(cur_settlement)
	elif chosen_event.get("id", "").begins_with("HC-"):
		event_context = check_hc_event_trigger(cur_settlement)
	trigger_event(chosen_event, event_context)

func check_hc_event_trigger(p_settlement: RefCounted) -> Dictionary:
	if not p_settlement or not ("id" in p_settlement):
		return {}
	var camp_id = ""
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == p_settlement.id and b.is_hunting_camp():
				camp_id = b.id
				break
	return {
		"target_building_id": camp_id,
		"causes": ["Деятельность охотничьего лагеря", "Промысел дичи в тайге"],
		"context_data": {
			"camp_id": camp_id,
			"settlement_name": p_settlement.name if "name" in p_settlement else ""
		}
	}

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

func check_wc_01_trigger(p_settlement: RefCounted) -> Dictionary:
	if not p_settlement:
		return {}
	if not p_settlement.has_active_woodcutter_camp():
		return {}
	var camp = p_settlement.get_active_woodcutter_camp()
	var b_id = camp.id if camp else ""
	return {
		"target_building_id": b_id,
		"causes": ["Завершение строительства лагеря лесорубов", "Необходимость определить границы порубки"],
		"context_data": {
			"camp_id": b_id,
			"settlement_name": p_settlement.name
		}
	}

func _check_event_conditions(conds: Dictionary, total_days: int, settlement: RefCounted) -> bool:
	if conds.is_empty():
		return true
	var effective_days = maxf(float(total_days), (GameManager.sim_time_total / 300.0) if GameManager else float(total_days))
	if conds.has("min_days") and effective_days < float(conds["min_days"]):
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
		if conds.has("food_less_than") and "economy" in settlement and settlement.economy.get_resource("food") >= float(conds["food_less_than"]):
			return false
		if conds.has("has_seeds") and "economy" in settlement and settlement.economy.get_resource("seeds") <= 0.0:
			return false
		if conds.has("has_grain") and "economy" in settlement and settlement.economy.get_resource("grain") <= 0.0:
			return false
		if conds.has("required_building"):
			var b_req = conds["required_building"]
			var has_b = false
			if "buildings" in settlement and settlement.buildings.has(b_req):
				has_b = true
			elif GameManager and GameManager.building_instances:
				for b in GameManager.building_instances.values():
					if b and b.type == b_req and b.settlement_id == settlement.id:
						has_b = true
						break
			if not has_b:
				return false
		if conds.has("min_huts"):
			var hut_cnt = 0
			if GameManager and GameManager.building_instances:
				for b in GameManager.building_instances.values():
					if b and b.settlement_id == settlement.id and b.type == "hut":
						hut_cnt += 1
			if hut_cnt < int(conds["min_huts"]):
				return false
	elif conds.has("min_iron") or conds.has("required_building") or conds.has("min_huts") or conds.has("has_seeds") or conds.has("has_grain"):
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
	
	# Форматирование шаблонов {key} в заголовке, описании и вариантах выбора
	if not context.is_empty() and context.has("context_data"):
		var c_data = context["context_data"]
		for key in ["title", "description"]:
			if instance.has(key) and instance[key] is String:
				var txt: String = instance[key]
				for ctx_k in c_data:
					txt = txt.replace("{" + ctx_k + "}", str(c_data[ctx_k]))
				instance[key] = txt
		# Форматируем тексты вариантов выбора
		var formatted_choices: Array = []
		for choice in instance.get("choices", []):
			var ch: Dictionary = choice.duplicate(true)
			for field in ["title", "desc", "effects_desc"]:
				if ch.has(field) and ch[field] is String:
					var ftxt: String = ch[field]
					for ctx_k in c_data:
						ftxt = ftxt.replace("{" + ctx_k + "}", str(c_data[ctx_k]))
					ch[field] = ftxt
			formatted_choices.append(ch)
		instance["choices"] = formatted_choices

	active_event = instance.duplicate(true)
	event_instances[instance_id] = instance
	if not triggered_events.has(template_id):
		triggered_events.append(template_id)
		
	var chain_id = instance.get("chain_id", "")
	if chain_id != "":
		chain_cooldowns[chain_id] = 10 # 10 дней кулдаун на следующую ступень цепочки

	# Глобальный кулдаун для NPC-событий (Feud/Gossip) — не спамить
	if template_id in ["NPC-FEUD-01", "NPC-GOSSIP-01"]:
		chain_cooldowns["npc_event_global"] = 30
		
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
	if cur_settlement == null and GameManager and not GameManager.settlements.is_empty():
		cur_settlement = GameManager.settlements.values()[0]
		
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
	if pop == null and GameManager and not GameManager.settlements.is_empty():
		for s_cand in GameManager.settlements.values():
			if s_cand and "population" in s_cand and s_cand.population:
				pop = s_cand.population
	var culture = GameManager.culture_memory if GameManager else null
	
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

	# Последствия WC-01 (Зоны вырубки леса)
	if consequences.get("set_logging_zone_near", false) and settlement:
		var camp = settlement.get_active_woodcutter_camp()
		var center_tile = camp.pos if camp else settlement.pos
		var near_tiles: Array[Vector2i] = []
		if GameManager and GameManager.resource_manager:
			for coord in GameManager.resource_manager.nodes:
				var n = GameManager.resource_manager.nodes[coord]
				if n.get("category", "") == "wood" and not n.get("depleted", false):
					if maxi(abs(coord.x - center_tile.x), abs(coord.y - center_tile.y)) <= 8:
						near_tiles.append(coord)
		settlement.set_logging_zone(near_tiles)
		if camp:
			camp.add_history_entry(GameManager.current_year if GameManager else 1, "Утверждена ближняя зона вырубки леса (до 8 клеток)")

	if consequences.get("set_logging_zone_far", false) and settlement:
		var camp = settlement.get_active_woodcutter_camp()
		var center_tile = camp.pos if camp else settlement.pos
		var far_tiles: Array[Vector2i] = []
		if GameManager and GameManager.resource_manager:
			for coord in GameManager.resource_manager.nodes:
				var n = GameManager.resource_manager.nodes[coord]
				if n.get("category", "") == "wood" and not n.get("depleted", false):
					var dist = maxi(abs(coord.x - center_tile.x), abs(coord.y - center_tile.y))
					if dist > 8 and dist <= 24:
						far_tiles.append(coord)
		settlement.set_logging_zone(far_tiles)
		if camp:
			camp.add_history_entry(GameManager.current_year if GameManager else 1, "Утверждена дальняя зона вырубки леса (ближняя роща сохранена)")

	if consequences.get("set_logging_zone_all", false) and settlement:
		var camp = settlement.get_active_woodcutter_camp()
		var all_tiles: Array[Vector2i] = []
		if GameManager and GameManager.resource_manager:
			for coord in GameManager.resource_manager.nodes:
				var n = GameManager.resource_manager.nodes[coord]
				if n.get("category", "") == "wood" and not n.get("depleted", false):
					all_tiles.append(coord)
		settlement.set_logging_zone(all_tiles)
		if camp:
			camp.add_history_entry(GameManager.current_year if GameManager else 1, "Объявлена свободная вырубка по всей округе")

	if consequences.get("no_logging_zone", false) and settlement:
		settlement.logging_zones.clear()
		var camp = settlement.get_active_woodcutter_camp()
		if camp:
			camp.add_history_entry(GameManager.current_year if GameManager else 1, "Вырубка живого леса запрещена вождём")

	# --- ПОСЛЕДСТВИЯ ДЛЯ БОЛЬШОГО ДОМА РОДА (GREAT LODGE) ---
	var lodge_inst: BuildingInstance = null
	var target_b_id = ev.get("target_building_id", "")
	if GameManager and GameManager.building_instances:
		for bi in GameManager.building_instances.values():
			if bi and bi.is_great_lodge():
				if target_b_id != "" and (bi.id == target_b_id or bi.instance_id == target_b_id):
					lodge_inst = bi
					break
				elif lodge_inst == null:
					lodge_inst = bi

	if culture != null:
		if consequences.get("unlock_upgrade_nursery", false):
			culture.unlock_upgrade_globally("great_lodge", "nursery_corner")
		if consequences.get("unlock_upgrade_elders", false):
			culture.unlock_upgrade_globally("great_lodge", "elders_quarters")
		if consequences.get("unlock_upgrade_knowledge", false):
			culture.unlock_upgrade_globally("great_lodge", "knowledge_circle")
		if consequences.get("unlock_upgrade_store", false):
			culture.unlock_upgrade_globally("great_lodge", "communal_store")
		if consequences.get("unlock_role_caretaker", false):
			culture.unlock_upgrade_globally("great_lodge", "caretaker_quarters")

	if lodge_inst != null:
		if consequences.has("modify_harmony"):
			var d_harm = float(consequences["modify_harmony"])
			lodge_inst.household_harmony = clampf(lodge_inst.household_harmony + d_harm, -100.0, 100.0)
			lodge_inst.add_history_entry(GameManager.current_year if GameManager else 1, "Согласие в роду изменилось на %+d (Итог: %+d)" % [int(d_harm), int(lodge_inst.household_harmony)])
		if consequences.get("unlock_upgrade_nursery", false):
			lodge_inst.unlock_upgrade("nursery_corner")
		if consequences.get("unlock_upgrade_elders", false):
			lodge_inst.unlock_upgrade("elders_quarters")
		if consequences.get("unlock_upgrade_knowledge", false):
			lodge_inst.unlock_upgrade("knowledge_circle")
		if consequences.get("unlock_upgrade_store", false):
			lodge_inst.unlock_upgrade("communal_store")
		if consequences.get("unlock_role_caretaker", false):
			lodge_inst.unlock_upgrade("caretaker_quarters")
		if consequences.get("ward_of_lodge", false):
			var ward_pop = pop
			if lodge_inst and lodge_inst.settlement_id != "" and GameManager and GameManager.settlements.has(lodge_inst.settlement_id):
				ward_pop = GameManager.settlements[lodge_inst.settlement_id].population
			var actor_ids = ev.get("actor_ids", [])
			if ward_pop:
				if not actor_ids.is_empty():
					for act in actor_ids:
						var c = _find_citizen(ward_pop, _resolve_placeholder_str(str(act), ev))
						if c:
							c.is_ward_of_lodge = true
							c.home_id = lodge_inst.id
							lodge_inst.add_resident(c.citizen_id, "ward")
				else:
					for c in ward_pop.citizens:
						if c.cohort == "child" and (c.is_ward_of_lodge or c.home_id == "" or c.family_id == "" or c.relationships.is_empty()):
							c.is_ward_of_lodge = true
							c.home_id = lodge_inst.id
							lodge_inst.add_resident(c.citizen_id, "ward")
		if consequences.get("replace_caretaker", false):
			lodge_inst.caretaker_id = ""
			for r_id in lodge_inst.residents:
				var cand = pop.get_citizen_by_id(r_id) if pop else null
				if cand and cand.cohort in ["adult", "elder"]:
					lodge_inst.caretaker_id = cand.citizen_id
					cand.job_id = "caretaker"
					break

	# Регистрация глобальных улучшений охотничьего лагеря
	if culture != null:
		if consequences.get("unlock_upgrade_dogs", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_dogs")
		if consequences.get("unlock_upgrade_smokehouse", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_smokehouse")
		if consequences.get("unlock_upgrade_outpost", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_outpost")
		if consequences.get("unlock_upgrade_master_butcher", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_master_butcher")
		if consequences.get("unlock_upgrade_mentor", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_mentor")
		if consequences.get("unlock_upgrade_target", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_target")
		if consequences.get("unlock_upgrade_trophies", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_trophies")

	# Поиск охотничьего лагеря (Hunting Camp) для применения улучшений и эффектов
	var camp_inst: BuildingInstance = null
	if GameManager and GameManager.building_instances:
		for bi in GameManager.building_instances.values():
			if bi and bi.is_hunting_camp():
				if target_b_id != "" and (bi.id == target_b_id or bi.instance_id == target_b_id):
					camp_inst = bi
					break
				elif camp_inst == null:
					camp_inst = bi

	if camp_inst != null:
		if consequences.get("unlock_upgrade_dogs", false):
			camp_inst.unlock_upgrade("hunt_dogs")
		if consequences.get("unlock_upgrade_smokehouse", false):
			camp_inst.unlock_upgrade("hunt_smokehouse")
		if consequences.get("unlock_upgrade_outpost", false):
			camp_inst.unlock_upgrade("hunt_outpost")
		if consequences.get("unlock_upgrade_master_butcher", false):
			camp_inst.unlock_upgrade("hunt_master_butcher")
		if consequences.get("unlock_upgrade_mentor", false):
			camp_inst.unlock_upgrade("hunt_mentor")
		if consequences.get("unlock_upgrade_target", false):
			camp_inst.unlock_upgrade("hunt_target")
		if consequences.get("unlock_upgrade_trophies", false):
			camp_inst.unlock_upgrade("hunt_trophies")
	if consequences.has("hunter_morale") and pop:
		var d_mor = float(consequences["hunter_morale"])
		for c in pop.citizens:
			if c.job_id == "hunter":
				c.loyalty = clampf(c.loyalty + d_mor, 0.0, 100.0)
				c.energy = minf(100.0, c.energy + maxf(0.0, d_mor * 0.5))
	if consequences.has("hunter_cohesion") and pop:
		var d_coh = float(consequences["hunter_cohesion"])
		for c in pop.citizens:
			if c.job_id == "hunter":
				c.loyalty = clampf(c.loyalty + d_coh, 0.0, 100.0)

	# --- ФИЗИЧЕСКОЕ ПРИРУЧЕНИЕ ЖИВОТНЫХ (DEER & WOLF) ---
	# Приручение оленёнка (HC-05 и цепочки животноводства)
	if consequences.get("domestication_seed", false) or consequences.get("tame_deer", false):
		var spawn_pos = Vector2.ZERO
		if camp_inst != null:
			spawn_pos = Vector2(camp_inst.pos.x * 32.0 + 16.0, camp_inst.pos.y * 32.0 + 16.0)
		elif settlement:
			spawn_pos = Vector2(settlement.pos.x * 32.0 + 16.0, settlement.pos.y * 32.0 + 16.0)
		spawn_pos += Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		
		var s_id = settlement.id if settlement else ""
		if GameManager and GameManager.wildlife_manager:
			var fawn = GameManager.wildlife_manager.spawn_tamed_animal("deer_fawn", spawn_pos, s_id, "Прирученный оленёнок")
			if fawn:
				fawn.state = WildAnimal.State.GRAZING
				
		if culture != null:
			culture.unlock_building("animal_pen")
		EventBus.notification_toast.emit(
			"🦌 Приручение оленёнка",
			"В лагере поселился прирученный оленёнок! Открыто строительство Загона для скота (animal_pen).",
			"good"
		)

	# Приручение волчонка / охотничьи собаки (HC-08)
	if consequences.get("dog_taming", false) or consequences.get("tame_wolf", false):
		var spawn_pos = Vector2.ZERO
		if camp_inst != null:
			spawn_pos = Vector2(camp_inst.pos.x * 32.0 + 16.0, camp_inst.pos.y * 32.0 + 16.0)
		elif settlement:
			spawn_pos = Vector2(settlement.pos.x * 32.0 + 16.0, settlement.pos.y * 32.0 + 16.0)
		spawn_pos += Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		
		var s_id = settlement.id if settlement else ""
		if GameManager and GameManager.wildlife_manager:
			var already_has_wolf = false
			for a in GameManager.wildlife_manager.animals.values():
				if a.is_tamed and a.species == "wolf" and a.tamed_settlement_id == s_id:
					already_has_wolf = true
					break
			if not already_has_wolf:
				var pup = GameManager.wildlife_manager.spawn_tamed_animal("wolf_pup", spawn_pos, s_id, "Ручной волчонок")
				if pup:
					pup.state = WildAnimal.State.GRAZING
					pup.set_tamed_role(consequences.get("tame_role", "guardian"))
				
		if culture != null:
			culture.unlock_upgrade_globally("hunting_camp", "hunt_dogs")
		if camp_inst != null:
			camp_inst.unlock_upgrade("hunt_dogs")
			
		var role_str = "Защитник поселения" if consequences.get("tame_role", "guardian") == "guardian" else "Охотничий спутник"
		EventBus.notification_toast.emit(
			"🐺 Верный спутник",
			"В лагере появился ручной волчонок (%s)! Открыто улучшение «Охотничьи собаки»." % role_str,
			"good"
		)

	if consequences.has("young_skill_boost") and pop:
		var boost_amt = float(consequences["young_skill_boost"])
		for c in pop.citizens:
			if c.age < 30 and c.cohort in ["youth", "adult"]:
				c.skills["hunting"] = minf(100.0, float(c.skills.get("hunting", 10.0)) + boost_amt)
				c.skills["woodcutting"] = minf(100.0, float(c.skills.get("woodcutting", 10.0)) + boost_amt)
				c.skills["survival"] = minf(100.0, float(c.skills.get("survival", 10.0)) + boost_amt)

	if (consequences.has("young_hunter_skill_boost") or consequences.has("skill_boost_youth")) and pop:
		var h_boost = float(consequences.get("young_hunter_skill_boost", consequences.get("skill_boost_youth", 2.0)))
		for c in pop.citizens:
			if c.job_id == "hunter" or (c.age < 25 and c.cohort in ["youth", "adult"]):
				c.skill_hunter = minf(100.0, c.skill_hunter + h_boost)

	# --- ПОСЛЕДСТВИЯ АГРАРНОЙ ЭВОЛЮЦИИ И ЗЕМЛЕДЕЛИЯ ---
	if settlement:
		if consequences.has("add_knowledge_cultivation") and "add_knowledge" in settlement:
			settlement.add_knowledge("cultivation_knowledge", float(consequences["add_knowledge_cultivation"]))
		if consequences.has("add_knowledge_plant") and "add_knowledge" in settlement:
			settlement.add_knowledge("plant_knowledge", float(consequences["add_knowledge_plant"]))
		if consequences.has("add_knowledge_seed") and "add_knowledge" in settlement:
			settlement.add_knowledge("seed_knowledge", float(consequences["add_knowledge_seed"]))
		if consequences.has("add_knowledge_soil") and "add_knowledge" in settlement:
			settlement.add_knowledge("soil_knowledge", float(consequences["add_knowledge_soil"]))
		if consequences.has("add_knowledge_water") and "add_knowledge" in settlement:
			settlement.add_knowledge("water_management_knowledge", float(consequences["add_knowledge_water"]))
		if consequences.has("add_knowledge_storage") and "add_knowledge" in settlement:
			settlement.add_knowledge("storage_knowledge", float(consequences["add_knowledge_storage"]))
		if consequences.has("add_knowledge_food_processing") and "add_knowledge" in settlement:
			settlement.add_knowledge("food_processing_knowledge", float(consequences["add_knowledge_food_processing"]))
		if consequences.has("add_food") and "economy" in settlement:
			settlement.economy.add_resource("food", float(consequences["add_food"]))
		if consequences.has("add_grain") and "economy" in settlement:
			settlement.economy.add_resource("grain", float(consequences["add_grain"]))
		if consequences.has("add_straw") and "economy" in settlement:
			settlement.economy.add_resource("straw", float(consequences["add_straw"]))
		if consequences.has("add_bread") and "economy" in settlement:
			settlement.economy.add_resource("bread", float(consequences["add_bread"]))
			settlement.economy.add_resource("food", float(consequences["add_bread"]))
		if consequences.get("consume_half_seeds", false) and "economy" in settlement:
			var cur_s = settlement.economy.get_resource("seeds")
			settlement.economy.resources["seeds"] = maxf(0.0, cur_s * 0.5)
		if consequences.get("consume_all_seeds", false) and "economy" in settlement:
			settlement.economy.resources["seeds"] = 0.0

	if culture:
		if consequences.get("unlock_ox_plow", false):
			culture.unlock_upgrade_globally("primitive_field", "field_ox_plow")
			culture.unlock_upgrade_globally("wheat_field", "wheat_ox_plow")
		if consequences.get("unlock_upgrade_manure", false):
			culture.unlock_upgrade_globally("primitive_field", "field_manure_spreading")
		if consequences.get("unlock_upgrade_trophies", false):
			culture.unlock_upgrade_globally("hunting_camp", "hunt_trophies")

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

# --- ТРИГГЕР: Личный конфликт двух NPC (NPC-FEUD-01) ---
# Ищет пару жителей с affinity < -50 — они поссорились публично
func check_npc_feud_trigger(p_settlement: RefCounted) -> Dictionary:
	if not p_settlement or not ("population" in p_settlement):
		return {}
	var pop = p_settlement.population
	if not pop:
		return {}

	# Ищем пару с максимальной взаимной антипатией
	var worst_a: CitizenNPC = null
	var worst_b: CitizenNPC = null
	var worst_aff: float = -49.0  # порог: только если реально плохо

	for c in pop.citizens:
		if not c.is_alive or c.cohort == "child":
			continue
		for other_id in c.relationships:
			var aff = c.get_relationship_affinity(other_id)
			if aff < worst_aff:
				var other = _find_citizen(pop, other_id)
				if other and other.is_alive and other.cohort != "child":
					worst_aff = aff
					worst_a = c
					worst_b = other

	if worst_a == null or worst_b == null:
		return {}

	# Кулдаун: не вызывать одну и ту же пару снова менее чем через 30 дней
	var feud_key = "feud_%s_%s" % [worst_a.citizen_id, worst_b.citizen_id]
	if chain_cooldowns.get(feud_key, 0) > 0:
		return {}
	chain_cooldowns[feud_key] = 45  # 45 игровых дней = ~1.5 месяца

	worst_a.show_emote("quarrel", 4.0, 3, true)
	worst_b.show_emote("anger", 4.0, 3, true)

	return {
		"actor_ids": [worst_a.citizen_id, worst_b.citizen_id],
		"actor_names": [worst_a.name, worst_b.name],
		"target_building_id": "",
		"causes": ["Взаимная антипатия (affinity %.0f)" % worst_aff],
		"context_data": {
			"actor_0": worst_a.name,
			"actor_1": worst_b.name,
			"affinity": "%.0f" % worst_aff
		}
	}

# --- ТРИГГЕР: Сплетня / доносчик (NPC-GOSSIP-01) ---
# Ищет NPC с высокой склонностью к сплетням (curiosity + low honesty) и жертву
func check_npc_gossip_trigger(p_settlement: RefCounted) -> Dictionary:
	if not p_settlement or not ("population" in p_settlement):
		return {}
	var pop = p_settlement.population
	if not pop or pop.citizens.size() < 4:
		return {}

	# Ищем сплетника: высокая curiosity + низкая honesty + средняя sociability
	var gossiper: CitizenNPC = null
	var best_gossip_score: float = 60.0  # порог

	for c in pop.citizens:
		if not c.is_alive or c.cohort in ["child"] or c.is_ruler:
			continue
		var gossip_score = float(c.traits.get("curiosity", 50.0)) * 0.5 \
			+ (100.0 - float(c.traits.get("honesty", 50.0))) * 0.5 \
			+ float(c.traits.get("sociability", 50.0)) * 0.2
		if gossip_score > best_gossip_score:
			best_gossip_score = gossip_score
			gossiper = c

	if gossiper == null:
		return {}

	# Ищем жертву: кого сплетник недолюбливает (affinity < 0)
	var target: CitizenNPC = null
	var worst_aff: float = -1.0
	for other_id in gossiper.relationships:
		var aff = gossiper.get_relationship_affinity(other_id)
		if aff < worst_aff:
			var other = _find_citizen(pop, other_id)
			if other and other.is_alive and other.citizen_id != gossiper.citizen_id and not other.is_ruler:
				worst_aff = aff
				target = other

	if target == null:
		# Нет явного врага — ищем кого-то кто просто не знаком
		for c in pop.citizens:
			if c != gossiper and c.is_alive and not c.is_ruler and c.cohort != "child":
				if not gossiper.relationships.has(c.citizen_id):
					target = c
					break

	if target == null:
		return {}

	# Кулдаун: не повторять про одну и ту же пару слишком часто
	var gossip_key = "gossip_%s_%s" % [gossiper.citizen_id, target.citizen_id]
	if chain_cooldowns.get(gossip_key, 0) > 0:
		return {}
	chain_cooldowns[gossip_key] = 60  # 60 игровых дней = 2 месяца

	gossiper.show_emote("gossip", 4.0, 2, true)
	target.show_emote("shock", 3.0, 3, true)

	return {
		"actor_ids": [gossiper.citizen_id, target.citizen_id],
		"actor_names": [gossiper.name, target.name],
		"target_building_id": "",
		"causes": ["Слухи и наговор"],
		"context_data": {
			"actor_0": gossiper.name,
			"actor_1": target.name
		}
	}
