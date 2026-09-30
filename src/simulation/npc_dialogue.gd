class_name NPCDialogue
extends RefCounted

# ==============================================================================
# РАЗГОВОР ВОЖДЯ С ЖИТЕЛЕМ
# ------------------------------------------------------------------------------
# Темы берутся из настоящего состояния жителя: голод, износ одежды, нет дома,
# горе, обида на соседа, нет работы, недовольство вождём, увиденный хищник,
# мнение о последнем решении, сплетни. Житель может и сам поделиться — угостить
# вождя из домашних запасов.
# Каждый ответ вождя реально меняет мир: склад, дом, работа, отношения,
# лояльность, память. После ответа тема на время затихает (без «фарма»).
# ==============================================================================

const TOPIC_COOLDOWN: float = 180.0 # сек симуляции
const CALL_COOLDOWN: float = 90.0
const DANGER_RADIUS_TILES: int = 25
const HELP_XP: float = 3.0

# --- НАСТРОЙ ЖИТЕЛЯ ---

static func get_attitude(npc: CitizenNPC, ruler: CitizenNPC) -> float:
	return npc.get_relationship_affinity(ruler.citizen_id) * 0.5 + (npc.loyalty - 50.0)

static func refuses_to_talk(npc: CitizenNPC, ruler: CitizenNPC) -> bool:
	return npc.loyalty < 15.0 or npc.get_relationship_affinity(ruler.citizen_id) < -50.0

static func get_greeting(npc: CitizenNPC, ruler: CitizenNPC) -> Dictionary:
	if refuses_to_talk(npc, ruler):
		return {"text": "Мне не о чем с тобой говорить, %s." % ruler.name, "mood": "hostile"}
	var att = get_attitude(npc, ruler)
	if npc.cohort == "child":
		return {"text": "Вождь! Ты правда самый сильный в роду?", "mood": "warm"}
	if att >= 25.0:
		return {"text": "Рад тебя видеть, вождь! Присядь, поговорим.", "mood": "warm"}
	if att >= -5.0:
		return {"text": "Здравствуй, вождь. Слушаю тебя.", "mood": "neutral"}
	return {"text": "Чего тебе, вождь?", "mood": "cold"}

# --- ТЕМЫ ---

static func _now() -> float:
	return float(GameManager.sim_time_total) if GameManager else 0.0

static func _on_cooldown(npc: CitizenNPC, topic_id: String) -> bool:
	var cds: Dictionary = npc.custom_data.get("dlg_cd", {})
	return float(cds.get(topic_id, -1.0)) > _now()

static func _set_cooldown(npc: CitizenNPC, topic_id: String) -> void:
	var cds: Dictionary = npc.custom_data.get("dlg_cd", {})
	cds[topic_id] = _now() + TOPIC_COOLDOWN
	npc.custom_data["dlg_cd"] = cds

static func _topic(id: String, icon: String, line: String, options: Array) -> Dictionary:
	return {"id": id, "icon": icon, "npc_line": line, "options": options}

static func _opt(id: String, text: String) -> Dictionary:
	return {"id": id, "text": text}

static func _find_free_home(s: SettlementData) -> BuildingInstance:
	if not GameManager or not GameManager.building_instances:
		return null
	for b in GameManager.building_instances.values():
		if b and b.settlement_id == s.id and b.is_residential() and b.residents.size() < b.max_residents:
			return b
	return null

static func _has_open_workplace(s: SettlementData) -> bool:
	if not GameManager or not GameManager.building_instances:
		return false
	for b in GameManager.building_instances.values():
		if b and b.settlement_id == s.id and b.workers.size() < int(BuildingDB.get_building(b.type).get("max_workers", 0)):
			return true
	return false

static func _get_grudge_target(s: SettlementData, npc: CitizenNPC) -> CitizenNPC:
	for other_id in npc.get_rivals():
		if npc.has_grudge_against(other_id):
			var other = s.get_citizen_by_id(other_id)
			if other and other.is_alive and not other.is_ruler:
				return other
	return null

static func _get_grief_name(npc: CitizenNPC) -> String:
	for m in npc.memories:
		if m.get("type", "") == "grief":
			var desc: String = m.get("description", "")
			var idx = desc.find(": ")
			return desc.substr(idx + 2) if idx >= 0 else "близкого"
	return ""

static func _direction_word(from: Vector2, to: Vector2) -> String:
	var d = to - from
	if absf(d.x) > absf(d.y):
		return "к востоку" if d.x > 0.0 else "к западу"
	return "к югу" if d.y > 0.0 else "к северу"

static func _get_danger(s: SettlementData) -> Dictionary:
	if not GameManager or not GameManager.wildlife_manager:
		return {}
	var center = Vector2(s.pos.x * 32.0 + 16.0, s.pos.y * 32.0 + 16.0)
	var best: Dictionary = {}
	var best_d = float(DANGER_RADIUS_TILES) * 32.0
	for a in GameManager.wildlife_manager.animals.values():
		if a.is_tamed or not a.is_alive():
			continue
		var threat = float(CombatStatsResolver.calculate_animal_stats(a.type_id).get("threat", 0.0))
		if threat < 1.0:
			continue
		var d = center.distance_to(a.pos)
		if d < best_d:
			best_d = d
			best = {"name": s._get_animal_display_name(a.type_id), "pos": a.pos, "tiles": int(d / 32.0), "dir": _direction_word(center, a.pos)}
	return best

static func _latest_decision(s: SettlementData, npc: CitizenNPC) -> Dictionary:
	var cem = GameManager.civilization_event_manager if GameManager else null
	if cem == null or s.council == null:
		return {}
	var latest: Dictionary = {}
	for ev in cem.event_instances.values():
		if ev.get("status", "") == "resolved" and int(ev.get("resolved_day", -1)) >= int(latest.get("resolved_day", -1)):
			latest = ev
	if latest.is_empty():
		return {}
	var ch = cem.get_choice(latest, String(latest.get("chosen_choice_id", "")))
	if ch.is_empty():
		return {}
	var r = s.council.score_choice(npc, ch)
	return {"title": latest.get("title", ""), "choice": ch.get("title", ""), "score": float(r["score"]), "reason": r["reason"]}

static func get_topics(s: SettlementData, npc: CitizenNPC, ruler: CitizenNPC) -> Array[Dictionary]:
	var topics: Array[Dictionary] = []
	if refuses_to_talk(npc, ruler):
		if not _on_cooldown(npc, "discontent"):
			topics.append(_topic("discontent", "😠", "Ты для меня больше не вождь. Слишком много зла я от тебя видел.", [_opt("promise", "Я исправлюсь. Дай мне шанс."), _opt("rebuke", "Знай своё место!")]))
		_append_deeds(s, npc, ruler, topics)
		return topics
	var adult = npc.cohort in ["youth", "adult", "elder"]
	if npc.hunger < 45.0 and not _on_cooldown(npc, "hunger"):
		var opts = [_opt("wait", "Потерпи, всем сейчас тяжело.")]
		if s.economy.get_resource("food") >= SettlementData.MEAL_FOOD:
			opts.push_front(_opt("feed", "Возьми еды из общих запасов."))
		topics.append(_topic("hunger", "🍖", "Вождь, я давно ничего не ел... Живот сводит.", opts))
	if npc.warm_clothes < SettlementData.WARM_CLOTHES_REPLACE_AT and not _on_cooldown(npc, "clothes"):
		var opts = [_opt("wait", "Скорняк скоро сошьёт новую.")]
		if s.economy.get_resource("clothes") >= 1.0:
			opts.push_front(_opt("give_clothes", "Бери тёплую одежду со склада."))
		topics.append(_topic("clothes", "🧥", "Моя одежда совсем истрепалась. %s" % ("Зуб на зуб не попадает!" if npc.is_freezing else "Зимой замёрзну."), opts))
	if adult and npc.home_id == "" and not _on_cooldown(npc, "home"):
		var opts = [_opt("wait", "Скоро поставим новые хижины.")]
		var free_home = _find_free_home(s)
		if free_home:
			opts.push_front(_opt("house", "Поселю тебя — есть свободное место."))
		topics.append(_topic("home", "🏚", "Мне негде преклонить голову, вождь. Сплю где придётся.", opts))
	var grief_name = _get_grief_name(npc)
	if grief_name != "" and not _on_cooldown(npc, "grief"):
		topics.append(_topic("grief", "🕯", "Не могу забыть %s... Всё напоминает о потере." % grief_name, [_opt("comfort", "Я скорблю вместе с тобой. Род тебя не оставит."), _opt("move_on", "Жизнь продолжается. Держись.")]))
	var foe = _get_grudge_target(s, npc)
	if foe and not _on_cooldown(npc, "grudge"):
		topics.append(_topic("grudge", "⚔", "%s мне покоя не даёт. Ещё немного — и дойдёт до драки." % foe.name, [_opt("reconcile", "Я помирю вас. Позову %s к костру." % foe.name), _opt("ignore", "Разбирайтесь сами.")]))
	if adult and npc.job_id in ["idle", ""] and not npc.is_ruler and not _on_cooldown(npc, "work") and _has_open_workplace(s):
		topics.append(_topic("work", "🔨", "Мне нечем заняться, вождь. Руки чешутся без дела.", [_opt("assign", "Иди работать — есть свободное место."), _opt("rest", "Отдохни пока.")]))
	if npc.loyalty < 40.0 and not _on_cooldown(npc, "discontent"):
		var why = "Люди ропщут на тебя."
		if npc.has_memory("decree_overrode"):
			why = "Ты переступил через совет своим указом."
		elif npc.has_memory("council_sidelined"):
			why = "Ты правишь один и не слушаешь старейшин."
		elif npc.hunger < 45.0:
			why = "Род голодает, а ты молчишь."
		topics.append(_topic("discontent", "😠", "Многие недовольны тобой, вождь. %s" % why, [_opt("promise", "Обещаю править по совести."), _opt("rebuke", "Знай своё место!")]))
	var danger = _get_danger(s)
	if not danger.is_empty() and not _on_cooldown(npc, "danger"):
		topics.append(_topic("danger", "🐾", "Берегись, вождь! Видел %s %s, шагах в %d от стоянки." % [danger["name"], danger["dir"], danger["tiles"]], [_opt("thanks", "Спасибо. Буду настороже.")]))
	if ruler.hunger < 80.0 and not _on_cooldown(npc, "gift") and get_attitude(npc, ruler) >= 20.0:
		var home = s.get_citizen_home_instance(npc)
		if home and home.food_stockpile >= SettlementData.MEAL_FOOD:
			topics.append(_topic("gift", "🎁", "Вождь, ты выглядишь голодным. Поешь с нами — у нас есть еда.", [_opt("accept", "Благодарю, не откажусь."), _opt("decline", "Оставь своей семье.")]))
	var dec = _latest_decision(s, npc)
	if not dec.is_empty() and absf(float(dec["score"])) >= 8.0 and not _on_cooldown(npc, "opinion"):
		var line = "Хорошо рассудили насчёт «%s»: %s — это правильно." % [dec["title"], dec["choice"]] if float(dec["score"]) > 0.0 else "Не по душе мне решение насчёт «%s». «%s» — не так бы я сделал." % [dec["title"], dec["choice"]]
		topics.append(_topic("opinion", "📜", line, [_opt("glad", "Рад, что ты со мной согласен.") if float(dec["score"]) > 0.0 else _opt("explain", "Выслушай, почему так решено.")]))
	if not _on_cooldown(npc, "gossip"):
		var gossip = s._pick_gossip_subject(npc, ruler)
		if gossip != "":
			topics.append(_topic("gossip", "👂", gossip, [_opt("listen", "Любопытно... Что ещё говорят?")]))
	if not _on_cooldown(npc, "smalltalk"):
		topics.append(_topic("smalltalk", "💬", "", [_opt("how", "Как живёшь?")]))
	_append_deeds(s, npc, ruler, topics)
	return topics

# Поступки Короля в разговоре: подарить цветы из сумки или напасть
static func _append_deeds(s: SettlementData, npc: CitizenNPC, ruler: CitizenNPC, topics: Array[Dictionary]) -> void:
	if s.hero and float(s.hero.bag.get("flowers", 0.0)) >= 1.0 and not _on_cooldown(npc, "flowers") and not refuses_to_talk(npc, ruler):
		topics.append(_topic("flowers", "🌸", "", [_opt("give", "Подарить цветы %s" % npc.name)]))
	if npc.cohort != "child":
		topics.append(_topic("deed", "⚔", "", [_opt("attack", "Напасть на %s" % npc.name)]))

# Житель сам окликает вождя, если у него что-то неотложное. Возвращает реплику или ""
static func get_urgent_call(s: SettlementData, npc: CitizenNPC, ruler: CitizenNPC) -> String:
	if float(npc.custom_data.get("called_ruler_until", -1.0)) > _now() or refuses_to_talk(npc, ruler):
		return ""
	var line = ""
	if npc.hunger < 30.0 and not _on_cooldown(npc, "hunger"):
		line = "Вождь! Мы голодаем!"
	elif npc.is_freezing and not _on_cooldown(npc, "clothes"):
		line = "Вождь, я замерзаю! Нужна тёплая одежда!"
	elif npc.cohort in ["youth", "adult", "elder"] and npc.home_id == "" and not _on_cooldown(npc, "home"):
		line = "Вождь, мне негде жить!"
	elif npc.loyalty < 30.0 and not _on_cooldown(npc, "discontent"):
		line = "Эй, вождь! Нам надо поговорить."
	elif not _get_danger(s).is_empty() and not _on_cooldown(npc, "danger") and npc.cohort != "child" and randf() < 0.3:
		line = "Вождь, я видел зверя у стоянки!"
	if line != "":
		npc.custom_data["called_ruler_until"] = _now() + CALL_COOLDOWN
	return line

# --- ОТВЕТ ВОЖДЯ ---

static func _warm(npc: CitizenNPC, ruler: CitizenNPC, affinity: float, respect: float = 0.0) -> void:
	npc.modify_relationship(ruler.citizen_id, affinity, respect)
	ruler.modify_relationship(npc.citizen_id, affinity * 0.5, 0.0)

static func respond(s: SettlementData, npc: CitizenNPC, ruler: CitizenNPC, topic_id: String, option_id: String) -> Dictionary:
	_set_cooldown(npc, topic_id)
	var reply = "..."
	var helped = false
	match topic_id + ":" + option_id:
		"hunger:feed":
			if s.economy.get_resource("food") >= SettlementData.MEAL_FOOD:
				s.consume_food(SettlementData.MEAL_FOOD)
				npc.hunger = 100.0
				npc.loyalty = minf(100.0, npc.loyalty + 4.0)
				_warm(npc, ruler, 8.0, 4.0)
				npc.add_memory("ruler_fed", "ruler", ruler.citizen_id, 1.5, "Вождь сам накормил меня в голодный час")
				npc.show_emote("eat", 3.0, 3)
				reply = "Спасибо, вождь! Не забуду твоей доброты."
				helped = true
			else:
				reply = "Но ведь в запасах уже ничего нет..."
		"hunger:wait":
			npc.loyalty = maxf(0.0, npc.loyalty - (1.0 if float(npc.traits.get("empathy", 50.0)) >= 50.0 else 3.0))
			reply = "Потерплю... куда деваться."
		"clothes:give_clothes":
			if s.economy.get_resource("clothes") >= 1.0:
				s.economy.resources["clothes"] = s.economy.get_resource("clothes") - 1.0
				npc.warm_clothes = SettlementData.WARM_CLOTHES_MAX
				npc.is_freezing = false
				_warm(npc, ruler, 6.0, 3.0)
				npc.show_emote("joy", 3.0, 3)
				reply = "Тепло-то как! Благодарю, вождь."
				helped = true
			else:
				reply = "На складе пусто, вождь."
		"clothes:wait":
			reply = "Буду ждать. Лишь бы до холодов."
		"home:house":
			var free_home = _find_free_home(s)
			if free_home and s.assign_citizen_to_home(npc, free_home):
				npc.loyalty = minf(100.0, npc.loyalty + 6.0)
				_warm(npc, ruler, 10.0, 5.0)
				npc.add_memory("ruler_housed", "ruler", ruler.citizen_id, 2.0, "Вождь дал мне кров", true)
				reply = "Своя крыша над головой! Спасибо, вождь!"
				helped = true
			else:
				reply = "Но там уже нет места..."
		"home:wait":
			reply = "Хорошо бы поскорее."
		"grief:comfort":
			npc.loyalty = minf(100.0, npc.loyalty + 3.0)
			npc.morale = minf(100.0, npc.morale + 5.0)
			_warm(npc, ruler, 6.0, 2.0)
			npc.add_memory("comforted_by_ruler", "ruler", ruler.citizen_id, 1.5, "Вождь разделил со мной горе")
			npc.show_emote("sympathy", 3.0, 3)
			reply = "Спасибо, что не оставил меня одного в горе."
			helped = true
		"grief:move_on":
			if float(npc.traits.get("empathy", 50.0)) >= 60.0:
				_warm(npc, ruler, -3.0)
				reply = "Легко тебе говорить..."
			else:
				reply = "Да... надо жить дальше."
		"grudge:reconcile":
			var foe = _get_grudge_target(s, npc)
			if foe:
				npc.clear_grudge(foe.citizen_id)
				foe.clear_grudge(npc.citizen_id)
				npc.modify_relationship(foe.citizen_id, 15.0, 5.0)
				foe.modify_relationship(npc.citizen_id, 15.0, 5.0)
				npc.add_memory("reconciled", "peace", foe.citizen_id, 2.0, "Вождь помирил меня с %s" % foe.name)
				foe.add_memory("reconciled", "peace", npc.citizen_id, 2.0, "Вождь помирил меня с %s" % npc.name)
				_warm(npc, ruler, 5.0, 5.0)
				foe.modify_relationship(ruler.citizen_id, 3.0, 3.0)
				reply = "Ладно... ради тебя, вождь, забуду обиду на %s." % foe.name
				helped = true
			else:
				reply = "Он уже сам ко мне подходил. Всё улажено."
		"grudge:ignore":
			reply = "Как знаешь. Но добром это не кончится."
		"work:assign":
			npc.state = CitizenNPC.State.IDLE
			if s._try_auto_assign_single_citizen(npc):
				npc.loyalty = minf(100.0, npc.loyalty + 2.0)
				_warm(npc, ruler, 3.0, 3.0)
				reply = "Иду! Теперь я %s." % s._get_job_display_name(npc.job_id).to_lower()
				helped = true
			else:
				reply = "Но свободных мест уже нет..."
			npc.state = CitizenNPC.State.TALKING
		"work:rest":
			reply = "Отдохну, раз так."
		"discontent:promise":
			if npc.has_memory("ruler_promise"):
				reply = "Ты уже обещал. Слова ничего не стоят — покажи делом."
			else:
				npc.loyalty = minf(100.0, npc.loyalty + 5.0)
				npc.add_memory("ruler_promise", "ruler", ruler.citizen_id, 1.5, "Вождь обещал править по совести")
				reply = "Посмотрим, вождь. Я запомню твоё слово."
		"discontent:rebuke":
			if float(npc.traits.get("bravery", 50.0)) >= 60.0 or float(npc.traits.get("temper", 20.0)) >= 60.0:
				npc.loyalty = maxf(0.0, npc.loyalty - 6.0)
				_warm(npc, ruler, -10.0, -5.0)
				npc.add_memory("grudge", "offense", ruler.citizen_id, 2.0, "Вождь унизил меня перед всеми")
				reply = "Ты ещё пожалеешь об этих словах!"
			else:
				npc.loyalty = maxf(0.0, npc.loyalty - 2.0)
				_warm(npc, ruler, -5.0, 2.0)
				reply = "...Как скажешь, вождь."
		"danger:thanks":
			_warm(npc, ruler, 2.0)
			var d = _get_danger(s)
			if not d.is_empty():
				EventBus.notification_toast.emit("🐾 %s %s" % [d["name"], d["dir"]], "Со слов %s: зверь в %d шагах от стоянки (%d, %d)." % [npc.name, d["tiles"], int(d["pos"].x / 32.0), int(d["pos"].y / 32.0)], "warning")
			reply = "Береги себя, вождь."
		"gift:accept":
			var home = s.get_citizen_home_instance(npc)
			if home and home.food_stockpile >= SettlementData.MEAL_FOOD:
				home.consume_food(SettlementData.MEAL_FOOD)
				ruler.hunger = 100.0
				_warm(npc, ruler, 4.0, 2.0)
				npc.add_memory("hosted_ruler", "ruler", ruler.citizen_id, 1.2, "Угостил вождя у своего очага")
				reply = "Ешь на здоровье, вождь!"
			else:
				reply = "Ох... а еда-то кончилась."
		"gift:decline":
			_warm(npc, ruler, 2.0, 3.0)
			reply = "Ты заботишься о нас. Спасибо."
		"opinion:glad":
			_warm(npc, ruler, 2.0, 1.0)
			reply = "Так и держи, вождь."
		"opinion:explain":
			if float(npc.traits.get("curiosity", 50.0)) >= 50.0 or float(npc.traits.get("sociability", 50.0)) >= 60.0:
				npc.loyalty = minf(100.0, npc.loyalty + 2.0)
				reply = "Теперь понимаю, хоть и не во всём согласен."
			else:
				reply = "Слова словами, а я при своём мнении."
		"gossip:listen":
			_warm(npc, ruler, 1.0)
			reply = "Только я тебе ничего не говорил!"
		"flowers:give":
			if s.hero and s.hero.bag_take("flowers", 1.0) > 0.0:
				HeroAnimations.play(ruler, "give")
				_warm(npc, ruler, 10.0, 2.0)
				var romantic = npc.cohort in ["youth", "adult"] and npc.gender != ruler.gender and npc.get_spouses().is_empty() and not npc.is_related_to(ruler)
				if romantic:
					npc.add_romance(ruler.citizen_id, 10.0)
				npc.add_memory("flowers_from_ruler", "ruler", ruler.citizen_id, 1.5, "Вождь подарил мне цветы")
				npc.show_emote("romance" if romantic else "joy", 3.5, 3)
				reply = "Ох... это мне? Какие красивые!" if romantic else "Спасибо, вождь! Порадую ими дом."
			else:
				reply = "..."
		"deed:attack":
			return {"reply": "Вождь, что ты задумал?!", "attack": true}
		"smalltalk:how":
			_warm(npc, ruler, 1.0)
			reply = describe_life(s, npc)
		_:
			reply = "..."
	if helped and s.hero:
		s.hero.add_xp(s, HELP_XP, "Забота о %s" % npc.name)
	return {"reply": reply}

# «Как живёшь?» — житель рассказывает о своей настоящей жизни
static func describe_life(s: SettlementData, npc: CitizenNPC) -> String:
	var parts: Array[String] = []
	if npc.cohort == "child":
		parts.append("Играю с ребятами у костра!")
	elif npc.job_id in ["idle", ""]:
		parts.append("Без дела хожу.")
	else:
		parts.append("Тружусь: %s." % s._get_job_display_name(npc.job_id).to_lower())
	if npc.spouse_id != "":
		var sp = s.get_citizen_by_id(npc.spouse_id)
		if sp:
			parts.append("С %s живём душа в душу." % sp.name if npc.get_relationship_affinity(sp.citizen_id) >= 30.0 else "С %s не всё ладно." % sp.name)
	if npc.home_id == "" and npc.cohort != "child":
		parts.append("Своего угла нет.")
	if npc.hunger < 45.0:
		parts.append("Голодно.")
	elif npc.energy < 30.0:
		parts.append("Устал очень.")
	if npc.loyalty >= 75.0:
		parts.append("Хорошо нам при тебе, вождь.")
	elif npc.loyalty < 40.0:
		parts.append("А жить при тебе всё труднее.")
	return " ".join(parts)
