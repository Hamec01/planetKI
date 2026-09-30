class_name NPCIntentions
extends RefCounted

# ==============================================================================
# ПОСТУПКИ ЖИТЕЛЕЙ ПО СОБСТВЕННОЙ ВОЛЕ
# ------------------------------------------------------------------------------
# Из характера, душевного состояния (NPCPsyche) и нужды рождаются дела, которых
# никто не приказывал:
#   • кража — нечестный или озлобленный житель уносит еду/добро со склада или из
#     чужой хижины к себе домой. Свидетели ловят вора, стража берёт под стражу,
#     украденное возвращается; незамеченная кража бьёт по спокойствию рода;
#   • добрые дела — сострадательный житель несёт еду голодному из своего дома,
#     утешает горюющего, перевязывает раненого;
#   • месть и драки — поклявшийся отомстить выслеживает обидчика и нападает
#     (кровная месть — до смерти). Стража вступается за закон, убийца идёт под
#     стражу, родня убитого клянётся мстить в ответ (кровная вражда);
#   • уныние — житель уходит сидеть в тоске; помешательство — бродит и кричит,
#     иногда кидается на людей.
# Всё это меняет запасы, здоровье, память, отношения и лояльность по-настоящему.
#
# Хранение: custom_data["intent"] — текущее дело, ["duel"] — схватка,
# ["jailed_until"] — время освобождения из-под стражи (sim_time_total).
# ==============================================================================

const GUARD_RADIUS: float = 360.0
const WITNESS_RADIUS: float = 160.0
const MELEE_RANGE: float = 26.0
const DUEL_GIVE_UP_DIST: float = 420.0
const THEFT_ITEMS: Array[String] = ["leather", "fur", "clothes", "metal", "tools"]
const MAD_LINES: Array[String] = [
	"Огонь говорит со мной!", "Не смотрите на меня!", "Вороны... вороны всё знают!",
	"Где мои дети?! Кто их спрятал?!", "Земля шевелится!", "Я вижу предков, они злы!"
]
const DESPAIR_LINES: Array[String] = ["Зачем всё это...", "Никого не осталось.", "Оставьте меня.", "Хоть бы и мне к предкам."]

static func _now() -> float:
	return float(GameManager.sim_time_total) if GameManager else 0.0

static func day_len() -> float:
	return float(GameManager.base_tick_interval) if GameManager else 600.0

static func _is_guard(c: CitizenNPC) -> bool:
	return c.job_id in ["guard", "warrior"]

static func is_jailed(c: CitizenNPC) -> bool:
	return float(c.custom_data.get("jailed_until", 0.0)) > _now()

static func is_busy(c: CitizenNPC) -> bool:
	return c.custom_data.has("duel") or c.custom_data.has("intent") or is_jailed(c)

# Журнал поступков поселения (преступления и добрые дела)
static func log_deed(s: SettlementData, kind: String, actor: CitizenNPC, victim_name: String, desc: String, discovered: bool = true) -> void:
	s.deeds_log.append({
		"day": GameManager.current_day if GameManager else 0,
		"year": GameManager.current_year if GameManager else 1,
		"kind": kind,
		"actor_id": actor.citizen_id if actor else "",
		"actor_name": actor.name if actor else "",
		"victim": victim_name,
		"desc": desc,
		"discovered": discovered
	})
	if s.deeds_log.size() > 60:
		s.deeds_log.remove_at(0)

# ==============================================================================
# ПОКАДРОВОЕ ИСПОЛНЕНИЕ (вызывается из update_citizens до обычного распорядка)
# Возвращает true, если житель сейчас занят своим делом/схваткой/сидит под стражей.
# ==============================================================================

static func tick(s: SettlementData, c: CitizenNPC, delta: float) -> bool:
	NPCPsyche.accumulate(c, delta)
	if c.custom_data.has("jailed_until"):
		if is_jailed(c):
			_body_decay(c, delta)
			_tick_jail(s, c, delta)
			return true
		_release(s, c)
	if c.custom_data.has("duel"):
		_body_decay(c, delta)
		_tick_duel(s, c, delta)
		return true
	if c.custom_data.has("intent"):
		_body_decay(c, delta)
		_tick_intent(s, c, delta)
		return true
	return false

static func _body_decay(c: CitizenNPC, delta: float) -> void:
	c.energy = maxf(0.0, c.energy - 0.25 * delta)
	c.hunger = maxf(0.0, c.hunger - 0.10 * delta)

static func _cancel_task(c: CitizenNPC, why: String) -> void:
	if GameManager and GameManager.task_service and c.task_instance_id != "":
		GameManager.task_service.cancel_task(c.task_instance_id, why)
	c.task_instance_id = ""
	c.task_id = ""
	c.path.clear()
	c.path_index = 0

# Шаг к точке по навигационной сетке: 1 — дошёл, 0 — идёт, -1 — не пройти
static func _walk(c: CitizenNPC, dest: Vector2, delta: float, reach: float = 12.0) -> int:
	if c.pos.distance_to(dest) <= reach:
		c.path.clear()
		c.path_index = 0
		return 1
	if c.path.is_empty():
		var p: Array[Vector2] = []
		if GameManager and GameManager.nav_grid:
			p = GameManager.nav_grid.find_path(c.pos, dest)
		if p.is_empty():
			return 1 if c.pos.distance_to(dest) <= reach * 2.5 else -1
		c.path = p
		c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	var done = c.update_movement(delta)
	if done and c.pos.distance_to(dest) <= reach * 2.5:
		return 1
	return 0

# Шаг напрямую к движущейся цели (в схватке), в обход — по сетке
static func _step_toward(c: CitizenNPC, target_pos: Vector2, delta: float, speed_mult: float = 1.3) -> void:
	var dir = (target_pos - c.pos).normalized()
	var nxt = c.pos + dir * c.get_speed() * speed_mult * delta
	c.facing_dir = dir
	if GameManager == null or GameManager.nav_grid == null or GameManager.nav_grid.is_tile_walkable(GameManager.nav_grid.world_to_tile(nxt)):
		c.pos = nxt
		c.path.clear()
	else:
		_walk(c, target_pos, delta, MELEE_RANGE)

static func _finish_intent(c: CitizenNPC, cooldown: float = 3.0) -> void:
	c.custom_data.erase("intent")
	c.path.clear()
	c.path_index = 0
	c.state = CitizenNPC.State.IDLE
	c.decision_cooldown = cooldown

static func _home_world_pos(b: BuildingInstance) -> Vector2:
	return Vector2(b.pos.x * 32.0 + 16.0, b.pos.y * 32.0 + 33.0)

# ==============================================================================
# ВЫБОР ПОСТУПКА (из фазы решений, когда житель свободен)
# ==============================================================================

static func try_start(s: SettlementData, c: CitizenNPC) -> bool:
	if c.is_ruler or c.cohort == "child" or c.custom_data.get("player_controlled", false) or is_busy(c):
		return false
	if c.cargo_amount > 0.0:
		return false
	var now = _now()
	# Свои дела житель начинает обдумывать не в первый же миг (после рождения, прихода, загрузки)
	if not c.custom_data.has("next_intent_eval"):
		c.custom_data["next_intent_eval"] = now + randf_range(20.0, 60.0)
		return false
	if now < float(c.custom_data.get("next_intent_eval", -1.0)):
		return false
	c.custom_data["next_intent_eval"] = now + randf_range(12.0, 24.0)
	# Помешавшийся живёт в своём мире
	if c.mental_state == "mad" and randf() < 0.45:
		return start_mad_episode(s, c)
	if c.health < 35.0:
		return false
	# Месть — дело чести
	if c.revenge_target_id != "" and now >= float(c.custom_data.get("next_revenge", -1.0)) and randf() < 0.5:
		if start_hunt(s, c):
			return true
	if c.mental_state == "despair" and randf() < 0.4:
		return start_despair(s, c)
	# Озлобленный задира лезет в драку с недругом поблизости
	if c.mental_state == "bitter" and float(c.traits.get("temper", 20.0)) >= 60.0 and randf() < 0.06:
		for r_id in c.get_rivals():
			var r = s.get_citizen_by_id(r_id)
			if r and r.is_alive and not r.is_ruler and r.cohort != "child" and r.pos.distance_to(c.pos) <= 220.0 and not is_busy(r):
				start_duel(s, c, r, false, "Затеял драку с недругом")
				return true
	# Воровство
	if now >= float(c.custom_data.get("next_theft", -1.0)) and _is_tempted_to_steal(s, c):
		if start_theft(s, c):
			return true
	# Добрые дела
	if now >= float(c.custom_data.get("next_good_deed", -1.0)) and _is_kind(c) and randf() < 0.3:
		if start_good_deed(s, c):
			return true
	return false

static func _is_kind(c: CitizenNPC) -> bool:
	return c.mental_state in ["stable", "despair"] and float(c.traits.get("empathy", 50.0)) >= 65.0

static func _is_tempted_to_steal(s: SettlementData, c: CitizenNPC) -> bool:
	if _is_guard(c):
		return false
	var honesty = float(c.traits.get("honesty", 50.0))
	var home = s.get_citizen_home_instance(c)
	var desperate = c.hunger < 25.0 and (home == null or home.food_stockpile < SettlementData.MEAL_FOOD)
	var inclined = honesty < 40.0 or (c.mental_state == "bitter" and honesty < 55.0) or (desperate and honesty < 60.0)
	if not inclined:
		return false
	var chance = 0.04
	if desperate:
		chance += 0.12
	if c.mental_state == "bitter":
		chance += 0.04
	if c.loyalty < 30.0:
		chance += 0.03
	return randf() < chance

# --- КРАЖА ---

static func start_theft(s: SettlementData, c: CitizenNPC) -> bool:
	c.custom_data["next_theft"] = _now() + day_len() * 1.5
	var hungry = c.hunger < 45.0
	var options: Array[Dictionary] = []
	var storage_p = s._get_storage_pos(c)
	if s.economy.get_resource("food") >= 1.0:
		options.append({"from": "storage", "res": "food", "dest": storage_p, "w": 3.0 if hungry else 1.0})
	for res in THEFT_ITEMS:
		if s.economy.get_resource(res) >= 1.0:
			options.append({"from": "storage", "res": res, "dest": storage_p, "w": 0.3 if hungry else 1.0})
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.settlement_id == s.id and b.is_residential() and b.id != c.home_id and b.food_stockpile >= 0.5 and not b.residents.is_empty():
				options.append({"from": "home", "home_id": b.id, "res": "food", "dest": _home_world_pos(b), "w": 2.0 if hungry else 0.8})
	if options.is_empty():
		return false
	var total = 0.0
	for o in options:
		total += float(o["w"])
	var roll = randf() * total
	var pick: Dictionary = options[0]
	for o in options:
		roll -= float(o["w"])
		if roll <= 0.0:
			pick = o
			break
	_cancel_task(c, "Ушёл по своим делам")
	pick["kind"] = "steal"
	pick["stage"] = "go"
	pick["t0"] = _now()
	c.custom_data["intent"] = pick
	c.last_status_reason = "Крадётся к %s" % ("складу" if pick["from"] == "storage" else "чужой хижине")
	return true

static func _home_by_id(home_id: String) -> BuildingInstance:
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and b.id == home_id:
				return b
	return null

static func _do_steal(s: SettlementData, c: CitizenNPC, it: Dictionary) -> void:
	var res = String(it["res"])
	var amount = 0.0
	var victim_name = "склад рода"
	var home: BuildingInstance = null
	if it["from"] == "storage":
		if res == "food":
			amount = s.consume_food(minf(1.5, s.economy.get_resource("food")))
		else:
			amount = minf(2.0, floorf(s.economy.get_resource(res)))
			if amount > 0.0:
				s.economy.add_resource(res, -amount)
				if s.is_player_settlement():
					EventBus.resources_updated.emit(s.faction_id, s.economy.resources)
	else:
		home = _home_by_id(String(it.get("home_id", "")))
		if home:
			amount = minf(1.5, home.food_stockpile)
			home.food_stockpile -= amount
			var owner = s.get_citizen_by_id(home.residents[0]) if not home.residents.is_empty() else null
			victim_name = "хижина %s" % (owner.name if owner else "соседей")
	if amount <= 0.0:
		_finish_intent(c)
		return
	it["amount"] = amount
	c.show_emote("thief", 3.0, 4, true)
	# Кто-то мог заметить
	var catcher: CitizenNPC = null
	for w in s.population.citizens:
		if w == c or not w.is_alive or w.is_ruler or w.cohort == "child" or w.state == CitizenNPC.State.SLEEPING or is_busy(w):
			continue
		if w.pos.distance_to(c.pos) > WITNESS_RADIUS:
			continue
		var p = 0.25 + (0.35 if _is_guard(w) else 0.0) + (float(w.traits.get("honesty", 50.0)) - 50.0) / 200.0 - float(c.agility_level) * 0.02
		if randf() < p:
			catcher = w
			break
	if catcher:
		_caught_thief(s, c, catcher, it, victim_name)
		return
	# Незамеченная кража: пропажу обнаружат, но вора не знают
	c.stress = clampf(c.stress + (5.0 if float(c.traits.get("honesty", 50.0)) >= 30.0 else 0.0), 0.0, 100.0)
	if home:
		for r_id in home.residents:
			var r = s.get_citizen_by_id(r_id)
			if r and r.is_alive:
				r.add_memory("robbed", "", c.citizen_id, 1.0, "Из нашей хижины украли еду")
				r.show_emote("shock", 3.0, 3)
	else:
		s.economy.stability = maxf(0.0, s.economy.stability - 1.0)
	log_deed(s, "theft", c, victim_name, "Кража: %.1f %s" % [amount, SettlementData.RESOURCE_NAMES_RU.get(res, res)], false)
	if s.is_player_settlement():
		EventBus.notification_toast.emit("🕵 Пропажа!", "Из места «%s» пропало %.1f %s. Вор не пойман." % [victim_name, amount, SettlementData.RESOURCE_NAMES_RU.get(res, res)], "warning")
	it["stage"] = "flee"
	c.path.clear()
	c.last_status_reason = "Уносит краденое домой"

static func _return_loot(s: SettlementData, it: Dictionary) -> void:
	var amount = float(it.get("amount", 0.0))
	if amount <= 0.0:
		return
	it["amount"] = 0.0
	if it["from"] == "storage":
		s.deposit_resource(String(it["res"]), amount)
	else:
		var home = _home_by_id(String(it.get("home_id", "")))
		if home:
			home.food_stockpile = minf(home.food_stockpile_max, home.food_stockpile + amount)
		else:
			s.deposit_resource("food", amount)

static func _caught_thief(s: SettlementData, thief: CitizenNPC, catcher: CitizenNPC, it: Dictionary, victim_name: String) -> void:
	catcher.shout("Держи вора! %s ворует!" % thief.name, 3.5)
	catcher.show_emote("justice", 3.5, 5, true)
	catcher.add_memory("witnessed_crime", thief.citizen_id, thief.citizen_id, 1.0, "Поймал %s на воровстве" % thief.name)
	catcher.modify_relationship(thief.citizen_id, -25.0, -20.0)
	thief.modify_relationship(catcher.citizen_id, -20.0, 0.0)
	thief.add_memory("punished", catcher.citizen_id, thief.citizen_id, 1.0, "Меня поймали на краже")
	thief.show_emote("shame", 3.5, 5, true)
	_return_loot(s, it)
	log_deed(s, "theft", thief, victim_name, "Пойман на краже (%s)" % catcher.name, true)
	c_erase_intent(thief)
	# Озлобленный вор не сдаётся — бросается на того, кто его поймал
	if thief.mental_state == "bitter" and NPCPsyche.is_warlike(thief):
		thief.shout("Не твоё дело!", 3.0)
		start_duel(s, thief, catcher, false, "Бросился на того, кто поймал его на краже")
		return
	var guard = catcher if _is_guard(catcher) else _nearest_loyal_guard(s, thief, [])
	if guard:
		arrest(s, thief, guard, 0.5, "кража")
	else:
		thief.state = CitizenNPC.State.IDLE
		thief.decision_cooldown = 5.0
		if s.is_player_settlement():
			EventBus.notification_toast.emit("🕵 Вор пойман", "%s поймал %s на краже. Украденное вернули, но стражи рядом нет." % [catcher.name, thief.name], "warning")

static func c_erase_intent(c: CitizenNPC) -> void:
	c.custom_data.erase("intent")
	c.path.clear()
	c.path_index = 0

static func _stash_loot(s: SettlementData, c: CitizenNPC, it: Dictionary) -> void:
	var amount = float(it.get("amount", 0.0))
	if amount <= 0.0:
		return
	var res = String(it["res"])
	var home = s.get_citizen_home_instance(c)
	if res == "food":
		if home:
			home.food_stockpile = minf(home.food_stockpile_max + amount, home.food_stockpile + amount)
		else:
			c.hunger = minf(100.0, c.hunger + amount * 40.0) # бездомный съедает краденое сразу
	else:
		var stash: Dictionary = c.custom_data.get("stash", {})
		stash[res] = float(stash.get(res, 0.0)) + amount
		c.custom_data["stash"] = stash
	it["amount"] = 0.0
	c.last_status_reason = "Спрятал краденое"

# Изъятие тайника вора в пользу рода
static func confiscate_stash(s: SettlementData, c: CitizenNPC) -> float:
	var total = 0.0
	var stash: Dictionary = c.custom_data.get("stash", {})
	for res in stash:
		var amt = float(stash[res])
		if amt > 0.0:
			s.deposit_resource(String(res), amt)
			total += amt
	c.custom_data.erase("stash")
	return total

# --- ДОБРЫЕ ДЕЛА ---

static func start_good_deed(s: SettlementData, c: CitizenNPC) -> bool:
	var best: CitizenNPC = null
	var kind = ""
	var best_d = 700.0
	var home = s.get_citizen_home_instance(c)
	var can_feed = home != null and home.food_stockpile >= 0.5
	for o in s.population.citizens:
		if o == c or not o.is_alive or o.is_ruler or o.custom_data.has("duel") or is_jailed(o) or o.custom_data.get("fighting_ruler", false):
			continue
		var d = o.pos.distance_to(c.pos)
		if d >= best_d:
			continue
		var k = ""
		if o.health < 50.0:
			k = "heal"
		elif o.hunger < 35.0 and can_feed:
			k = "feed"
		elif o.mental_state == "despair" or o.stress >= 60.0:
			k = "comfort"
		if k != "":
			best = o
			kind = k
			best_d = d
	if best == null:
		c.custom_data["next_good_deed"] = _now() + day_len() * 0.2
		return false
	c.custom_data["next_good_deed"] = _now() + day_len() * 0.5
	_cancel_task(c, "Пошёл помочь соплеменнику")
	var stage = "fetch" if kind == "feed" else "go"
	c.custom_data["intent"] = {"kind": "good_" + kind, "target_id": best.citizen_id, "stage": stage, "t0": _now()}
	c.last_status_reason = {"heal": "Спешит перевязать раненого %s", "feed": "Несёт еду голодному %s", "comfort": "Идёт утешить %s"}[kind] % best.name
	return true

static func _do_good_deed(s: SettlementData, c: CitizenNPC, t: CitizenNPC, kind: String, it: Dictionary) -> void:
	c.facing_dir = (t.pos - c.pos).normalized()
	match kind:
		"good_feed":
			var food = float(it.get("carried_food", 0.0))
			t.hunger = minf(100.0, t.hunger + food * 90.0)
			t.add_memory("was_helped", c.citizen_id, t.citizen_id, 1.0, "%s принёс мне еды, когда я голодал" % c.name)
			c.shout("Держи, поешь. Своих не бросаем.", 3.0)
			t.show_emote("eat", 3.0, 4, true)
			log_deed(s, "good_deed", c, t.name, "Накормил голодного своей едой")
		"good_heal":
			t.health = minf(t.max_health, t.health + 15.0 + float(c.traits.get("empathy", 50.0)) * 0.1)
			t.add_memory("was_helped", c.citizen_id, t.citizen_id, 1.0, "%s перевязал мои раны" % c.name)
			c.shout("Потерпи, сейчас перевяжу.", 3.0)
			t.show_emote("relief", 3.0, 4, true)
			log_deed(s, "good_deed", c, t.name, "Перевязал раны")
		"good_comfort":
			t.add_memory("comforted", c.citizen_id, t.citizen_id, 1.0, "%s утешил меня в тяжёлый час" % c.name)
			c.shout("Ты не один. Мы рядом.", 3.0)
			t.show_emote("sympathy", 3.5, 4, true)
			log_deed(s, "good_deed", c, t.name, "Утешил горюющего")
	t.modify_relationship(c.citizen_id, 12.0, 6.0)
	c.modify_relationship(t.citizen_id, 6.0, 0.0)
	c.add_memory("good_deed", c.citizen_id, t.citizen_id, 0.8, "Помог %s" % t.name)
	c.show_emote("sympathy", 3.0, 3)
	# Добрую славу видят соседи
	for w in RulerDeeds.witnesses(s, c.pos, [c, t]):
		w.modify_relationship(c.citizen_id, 3.0, 4.0)

# --- МЕСТЬ И СХВАТКИ ---

static func start_hunt(s: SettlementData, c: CitizenNPC) -> bool:
	c.custom_data["next_revenge"] = _now() + day_len() * 0.3
	var t = s.get_citizen_by_id(c.revenge_target_id)
	if t == null or not t.is_alive:
		c.revenge_target_id = ""
		c.revenge_reason = ""
		return false
	if is_jailed(t):
		return false
	# Вождя подстерегают, лишь когда он неподалёку
	if t.is_ruler and t.pos.distance_to(c.pos) > 520.0:
		return false
	if t.pos.distance_to(c.pos) > 1400.0:
		return false
	_cancel_task(c, "Ушёл мстить")
	c.custom_data["intent"] = {"kind": "hunt", "target_id": t.citizen_id, "stage": "go", "t0": _now(), "repath": 0.0}
	c.last_status_reason = "Выслеживает %s: %s" % [t.name, c.revenge_reason]
	c.show_emote("rage", 3.0, 4)
	return true

# Кровная месть — насмерть; обычная обида — до крови
static func revenge_is_lethal(c: CitizenNPC) -> bool:
	var t_id = c.revenge_target_id
	for m in c.memories:
		if m.get("type", "") in ["kin_murdered", "kin_murdered_by_ruler"] and (m.get("actor_id", "") == t_id or m.get("target_id", "") == t_id or m.get("actor_id", "") == "ruler"):
			return true
	return c.mental_state == "bitter" and float(c.traits.get("temper", 20.0)) >= 75.0

static func start_duel(s: SettlementData, attacker: CitizenNPC, target: CitizenNPC, lethal: bool, reason: String) -> void:
	if attacker == null or target == null or not attacker.is_alive or not target.is_alive:
		return
	c_erase_intent(attacker)
	_cancel_task(attacker, "Схватка")
	attacker.custom_data["duel"] = {"target_id": target.citizen_id, "lethal": lethal, "reason": reason, "role": "attacker", "timer": 0.2, "t0": _now()}
	attacker.state = CitizenNPC.State.ATTACKING
	attacker.show_emote("combat", 4.0, 6, true)
	attacker.shout(("Кровь за кровь, %s!" if lethal else "Получай, %s!") % target.name, 3.0)
	attacker.last_status_reason = "Дерётся с %s: %s" % [target.name, reason]
	# Жертва отбивается или бежит
	if not target.is_ruler and not target.custom_data.get("player_controlled", false) and not target.custom_data.has("duel"):
		c_erase_intent(target)
		_cancel_task(target, "На него напали")
		var fights = float(target.traits.get("bravery", 50.0)) >= 50.0 or float(target.traits.get("temper", 20.0)) >= 50.0 or _is_guard(target)
		target.custom_data["duel"] = {"target_id": attacker.citizen_id, "lethal": false, "role": "defender", "fights": fights, "timer": 0.6, "t0": _now()}
		target.show_emote("combat" if fights else "panic", 3.5, 6, true)
		target.shout("Ах ты!.." if fights else "Помогите! Убивают!", 3.0)
	target.add_memory("assaulted", attacker.citizen_id, target.citizen_id, 1.0, "%s напал на меня" % attacker.name)
	target.add_memory("grudge", "offense", attacker.citizen_id, 1.0, "%s поднял на меня руку" % attacker.name)
	target.modify_relationship(attacker.citizen_id, -30.0, -10.0)
	for w in RulerDeeds.witnesses(s, attacker.pos, [attacker, target]):
		w.add_memory("witnessed_crime", attacker.citizen_id, target.citizen_id, 0.6, "Видел, как %s напал на %s" % [attacker.name, target.name])
		w.show_emote("shock", 2.5, 3)
	log_deed(s, "assault", attacker, target.name, reason)
	_summon_guards(s, attacker, target)
	if s.is_player_settlement():
		if target.is_ruler:
			EventBus.notification_toast.emit("🗡 На вождя напали!", "%s бросился на вас: %s. Защищайтесь (ПКМ по нападающему)!" % [attacker.name, reason], "danger")
		elif lethal:
			EventBus.notification_toast.emit("⚔ Кровная месть", "%s напал на %s: %s" % [attacker.name, target.name, reason], "danger")

static func _nearest_loyal_guard(s: SettlementData, offender: CitizenNPC, exclude: Array) -> CitizenNPC:
	var best: CitizenNPC = null
	var best_d = GUARD_RADIUS
	for g in s.population.citizens:
		if not g.is_alive or g.is_ruler or g == offender or exclude.has(g) or not _is_guard(g) or is_busy(g):
			continue
		if g.loyalty < 50.0 or RulerDeeds.is_kin(g, offender) or g.revenge_target_id != "":
			continue
		var d = g.pos.distance_to(offender.pos)
		if d < best_d:
			best_d = d
			best = g
	return best

# Верная стража встаёт на сторону закона и бьёт нарушителя, пока тот не сдастся
static func _summon_guards(s: SettlementData, offender: CitizenNPC, victim: CitizenNPC) -> int:
	var n = 0
	for g in s.population.citizens:
		if not g.is_alive or g.is_ruler or g == offender or g == victim or not _is_guard(g) or is_busy(g):
			continue
		if g.pos.distance_to(offender.pos) > GUARD_RADIUS or RulerDeeds.is_kin(g, offender):
			continue
		# За вождя вступается стража, если хоть сколько-то ему верна
		var need_loyalty = 35.0 if victim and victim.is_ruler else 50.0
		if g.loyalty < need_loyalty:
			g.shout("Не моё это дело...", 2.5)
			continue
		_cancel_task(g, "Стража вмешалась")
		g.custom_data["duel"] = {"target_id": offender.citizen_id, "lethal": false, "role": "guard", "timer": 0.8, "t0": _now()}
		g.shout("Стоять, %s! Именем закона!" % offender.name, 3.0)
		g.show_emote("justice", 3.5, 6, true)
		n += 1
	return n

static func _duel_opponent_active(c: CitizenNPC, opp: CitizenNPC) -> bool:
	var od: Dictionary = opp.custom_data.get("duel", {})
	return not od.is_empty() and String(od.get("target_id", "")) == c.citizen_id

static func end_duel(c: CitizenNPC) -> void:
	c.custom_data.erase("duel")
	c.path.clear()
	if c.is_alive:
		c.state = CitizenNPC.State.IDLE
		c.decision_cooldown = randf_range(2.0, 4.0)

static func _tick_duel(s: SettlementData, c: CitizenNPC, delta: float) -> void:
	var duel: Dictionary = c.custom_data["duel"]
	var role = String(duel.get("role", "attacker"))
	var t = s.get_citizen_by_id(String(duel.get("target_id", "")))
	if t == null or not t.is_alive or is_jailed(t):
		end_duel(c)
		return
	# Защитник/стражник прекращают, когда нападавший отступил или бой кончился
	if role == "defender" and not _duel_opponent_active(c, t):
		end_duel(c)
		return
	if role == "guard" and not t.custom_data.has("duel") and t.pos.distance_to(c.pos) > 200.0:
		end_duel(c)
		return
	var elapsed = _now() - float(duel.get("t0", _now()))
	# Израненный отступает (кровник держится до последнего)
	var yield_at = 0.12 if (role == "attacker" and duel.get("lethal", false)) else 0.3
	if c.health <= c.max_health * yield_at:
		_yield(s, c, t, role)
		return
	var dist = c.pos.distance_to(t.pos)
	if role == "defender" and not duel.get("fights", true):
		# Трус бежит прочь
		var away = (c.pos - t.pos).normalized()
		var flee_to = c.pos + away * c.get_speed() * 1.5 * delta
		if GameManager == null or GameManager.nav_grid == null or GameManager.nav_grid.is_tile_walkable(GameManager.nav_grid.world_to_tile(flee_to)):
			c.pos = flee_to
		c.facing_dir = away
		c.state = CitizenNPC.State.FLEEING
		c.last_status_reason = "Спасается от %s" % t.name
		if dist > 300.0:
			end_duel(c)
		return
	if dist > MELEE_RANGE:
		if dist > DUEL_GIVE_UP_DIST and elapsed > 4.0:
			if role == "attacker":
				c.shout("Ещё встретимся, %s!" % t.name, 3.0)
			end_duel(c)
			return
		c.state = CitizenNPC.State.MOVING_TO_WORK
		_step_toward(c, t.pos, delta)
		return
	c.state = CitizenNPC.State.ATTACKING
	c.facing_dir = (t.pos - c.pos).normalized()
	duel["timer"] = float(duel.get("timer", 0.0)) - delta
	if float(duel["timer"]) > 0.0:
		return
	var cs = c.get_combat_stats()
	duel["timer"] = float(cs["attack_interval"])
	var atk = cs.duplicate()
	if c.is_exhausted():
		atk["raw_damage"] = float(cs["raw_damage"]) * 0.6
	var out = CombatStatsResolver.resolve_attack(atk, t.get_combat_stats())
	if not out["is_hit"]:
		return
	var dmg = float(out["damage"])
	if t.is_ruler:
		HeroAnimations.play(t, "hit")
	var lethal = role == "attacker" and duel.get("lethal", false)
	if not lethal:
		# Драка «до крови»: не добивают
		var floor_hp = t.max_health * 0.25
		if t.health - dmg <= floor_hp:
			t.health = maxf(1.0, minf(t.health, floor_hp))
			_beaten(s, c, t, role)
			return
		t.take_damage(dmg, c.name)
		return
	if t.health - dmg <= 0.0:
		t.death_cause = ("Убит мстителем %s" if c.revenge_target_id == t.citizen_id else "Убит соплеменником %s") % c.name
	var died = t.take_damage(dmg, c.name)
	if died:
		on_murder(s, c, t)

# Нападавший сломлен и отступает
static func _yield(s: SettlementData, c: CitizenNPC, t: CitizenNPC, role: String) -> void:
	c.shout("Хватит... хватит!", 2.5)
	c.show_emote("pain", 3.0, 5, true)
	end_duel(c)
	if role == "attacker":
		c.add_memory("injury", t.citizen_id, c.citizen_id, 0.8, "Проиграл схватку с %s" % t.name)
		# Если его ломали стражники — под стражу
		for g in s.population.citizens:
			if g.is_alive and g != c and g.custom_data.get("duel", {}).get("role", "") == "guard" and g.custom_data["duel"].get("target_id", "") == c.citizen_id:
				arrest(s, c, g, 1.0 if c.custom_data.get("murderer", false) else 0.5, "нападение")
				return
		c.custom_data["next_revenge"] = _now() + day_len()

# Противник повержен (без смерти)
static func _beaten(s: SettlementData, c: CitizenNPC, t: CitizenNPC, role: String) -> void:
	t.show_emote("injury", 4.0, 6, true)
	t.shout("Сдаюсь!..", 2.5)
	match role:
		"guard":
			arrest(s, t, c, 1.0 if t.custom_data.get("murderer", false) else 0.5, "нападение")
		"attacker":
			c.shout("Будешь знать, %s!" % t.name, 3.0)
			if c.revenge_target_id == t.citizen_id:
				NPCPsyche.clear_revenge(c, "vengeance_done", "Проучил %s — обида смыта" % t.name)
			end_duel(c)
			if t.custom_data.has("duel"):
				end_duel(t)
		"defender":
			c.shout("Не лезь больше ко мне!", 3.0)
			end_duel(c)
			if t.custom_data.has("duel"):
				end_duel(t)

static func on_murder(s: SettlementData, killer: CitizenNPC, victim: CitizenNPC) -> void:
	var avenged = killer.revenge_target_id == victim.citizen_id
	end_duel(killer)
	killer.custom_data["murderer"] = true
	if avenged:
		NPCPsyche.clear_revenge(killer, "vengeance_done", "Отомстил %s. Кровь смыта кровью" % victim.name)
	else:
		killer.add_memory("grudge", "offense", victim.citizen_id, 0.5, "Убил %s" % victim.name)
	killer.stress = clampf(killer.stress + (5.0 if avenged else 15.0), 0.0, 100.0)
	if victim.is_ruler:
		return # гибель вождя — конец партии (CitizenNPC.take_damage)
	log_deed(s, "murder", killer, victim.name, victim.death_cause)
	if GameManager:
		GameManager.add_history_entry(GameManager.current_year, "Кровь между своими", "%s убил %s. %s" % [killer.name, victim.name, "Кровная месть" if avenged else "Убийство"], "Власть и закон")
	s.economy.stability = maxf(0.0, s.economy.stability - 5.0)
	for w in RulerDeeds.witnesses(s, killer.pos, [killer, victim]):
		w.add_memory("witnessed_crime", killer.citizen_id, victim.citizen_id, 1.0, "Видел, как %s убил %s" % [killer.name, victim.name])
		w.modify_relationship(killer.citizen_id, -25.0, -10.0)
	# Родня убитого: горе и кровная вражда
	var avengers: Array[String] = []
	for k in s.population.citizens:
		if not k.is_alive or k == killer or k == victim or k.is_ruler:
			continue
		if RulerDeeds.is_kin(k, victim):
			k.add_memory("kin_murdered", killer.citizen_id, victim.citizen_id, 1.0, "%s убил моего родича %s" % [killer.name, victim.name], true)
			k.add_memory("grudge", "offense", killer.citizen_id, 1.0, "Кровь %s на руках %s" % [victim.name, killer.name], true)
			k.modify_relationship(killer.citizen_id, -60.0, -20.0)
			if NPCPsyche.consider_revenge(s, k, killer, "Кровь за %s" % victim.name):
				avengers.append(k.name)
	var guards = _summon_guards(s, killer, victim)
	if guards > 0:
		killer.custom_data["duel"] = {"target_id": _first_guard_on(s, killer), "lethal": false, "role": "defender", "fights": NPCPsyche.is_warlike(killer), "timer": 0.6, "t0": _now()}
	if s.is_player_settlement():
		var tail = ""
		if not avengers.is_empty():
			tail += " Родня клянётся мстить: %s." % ", ".join(avengers)
		tail += " Стража хватает убийцу." if guards > 0 else " Стражи рядом нет — убийца на свободе."
		EventBus.notification_toast.emit("🩸 Убийство!", "%s убил %s.%s" % [killer.name, victim.name, tail], "danger")

static func _first_guard_on(s: SettlementData, offender: CitizenNPC) -> String:
	for g in s.population.citizens:
		if g.is_alive and g.custom_data.get("duel", {}).get("role", "") == "guard" and g.custom_data["duel"].get("target_id", "") == offender.citizen_id:
			return g.citizen_id
	return ""

# --- СТРАЖА И ЗАКОН ---

static func arrest(s: SettlementData, prisoner: CitizenNPC, by: CitizenNPC, days: float, crime: String) -> void:
	if prisoner == null or not prisoner.is_alive:
		return
	c_erase_intent(prisoner)
	prisoner.custom_data.erase("duel")
	_cancel_task(prisoner, "Взят под стражу")
	# Все, кто бился с арестованным, расходятся
	for o in s.population.citizens:
		if o.is_alive and o.custom_data.get("duel", {}).get("target_id", "") == prisoner.citizen_id:
			end_duel(o)
	prisoner.custom_data["jailed_until"] = _now() + day_len() * days
	prisoner.state = CitizenNPC.State.WAITING
	prisoner.add_memory("jailed", by.citizen_id if by else "", prisoner.citizen_id, 1.0, "Взят под стражу за %s" % crime)
	prisoner.show_emote("prison", 5.0, 6, true)
	if by:
		prisoner.modify_relationship(by.citizen_id, -15.0, 5.0)
		by.shout("Посидишь у столба, %s. Закон есть закон." % prisoner.name, 3.0)
	var confiscated = confiscate_stash(s, prisoner)
	log_deed(s, "arrest", prisoner, by.name if by else "", "Под стражей за %s%s" % [crime, (" (изъято краденое: %.1f)" % confiscated) if confiscated > 0.0 else ""])
	s.economy.stability = minf(100.0, s.economy.stability + 1.0)
	if s.is_player_settlement():
		EventBus.notification_toast.emit("⛓ Под стражей", "%s взят под стражу за %s%s." % [prisoner.name, crime, (". Изъято краденое: %.1f" % confiscated) if confiscated > 0.0 else ""], "info")

static func _jail_pos(s: SettlementData) -> Vector2:
	return s._get_hearth_pos() + Vector2(0.0, 44.0)

static func _tick_jail(s: SettlementData, c: CitizenNPC, delta: float) -> void:
	var left_h = (float(c.custom_data["jailed_until"]) - _now()) / day_len() * 24.0
	if _walk(c, _jail_pos(s), delta, 16.0) != 0:
		c.state = CitizenNPC.State.WAITING
	c.last_status_reason = "Под стражей у столба (ещё %d ч)" % int(ceil(left_h))
	# Узника кормят из общих запасов
	if c.hunger < 40.0 and s.economy.get_resource("food") >= SettlementData.MEAL_FOOD:
		s.consume_food(SettlementData.MEAL_FOOD)
		c.hunger = 100.0
	if c.energy < 20.0:
		c.energy = minf(100.0, c.energy + 6.0 * delta) # дремлет сидя

static func _release(s: SettlementData, c: CitizenNPC) -> void:
	c.custom_data.erase("jailed_until")
	c.custom_data.erase("murderer")
	c.state = CitizenNPC.State.IDLE
	c.decision_cooldown = 2.0
	c.path.clear()
	c.shout("Свобода... Больше не попадусь.", 3.0)
	c.show_emote("freedom", 3.0, 4)
	c.last_status_reason = "Отпущен из-под стражи"
	# Честный урок или новая злоба — решает характер
	if float(c.traits.get("honesty", 50.0)) >= 40.0 or c.mental_state == "stable":
		c.traits["honesty"] = clampf(float(c.traits.get("honesty", 50.0)) + 5.0, 0.0, 100.0)
	else:
		c.stress = clampf(c.stress + 8.0, 0.0, 100.0)
	if s.is_player_settlement():
		EventBus.notification_toast.emit("🔓 Отпущен", "%s отбыл срок под стражей." % c.name, "info")

# --- УНЫНИЕ И ПОМЕШАТЕЛЬСТВО ---

static func start_despair(s: SettlementData, c: CitizenNPC) -> bool:
	var dest = c.home_pos if c.home_pos != Vector2.ZERO else c.pos
	# Горюющий по мёртвым сидит у могил
	if not s.cemetery_plots.is_empty() and randf() < 0.5:
		var g = s.cemetery_plots[randi() % s.cemetery_plots.size()]
		dest = Vector2(g.x * 32.0 + 16.0, g.y * 32.0 + 40.0)
	_cancel_task(c, "Уныние")
	c.custom_data["intent"] = {"kind": "despair", "stage": "go", "dest": dest, "t0": _now()}
	c.last_status_reason = "Бредёт куда-то, погружённый в тоску"
	return true

static func start_mad_episode(s: SettlementData, c: CitizenNPC) -> bool:
	# Иногда безумец кидается на ближайшего
	if randf() < 0.15 and (NPCPsyche.is_warlike(c) or float(c.traits.get("temper", 20.0)) >= 40.0):
		var near: CitizenNPC = null
		var best_d = 160.0
		for o in s.population.citizens:
			if o != c and o.is_alive and not o.is_ruler and o.cohort != "child" and not is_busy(o):
				var d = o.pos.distance_to(c.pos)
				if d < best_d:
					best_d = d
					near = o
		if near:
			c.shout("Ты! Это ты шепчешь!", 3.0)
			start_duel(s, c, near, false, "Кинулся в помешательстве")
			return true
	var dest = c.pos + Vector2(randf_range(-160.0, 160.0), randf_range(-160.0, 160.0))
	if GameManager and GameManager.nav_grid and not GameManager.nav_grid.is_tile_walkable(GameManager.nav_grid.world_to_tile(dest)):
		dest = s._get_hearth_pos() + Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
	_cancel_task(c, "Помешательство")
	c.custom_data["intent"] = {"kind": "mad", "stage": "go", "dest": dest, "t0": _now()}
	c.last_status_reason = "Бродит, бормоча бессвязное"
	c.show_emote("dizziness", 3.0, 4, true)
	return true

# ==============================================================================
# ИСПОЛНЕНИЕ ДЕЛ
# ==============================================================================

static func _tick_intent(s: SettlementData, c: CitizenNPC, delta: float) -> void:
	var it: Dictionary = c.custom_data["intent"]
	var kind = String(it.get("kind", ""))
	# Слишком долго — бросает
	if _now() - float(it.get("t0", _now())) > 150.0:
		if kind == "steal" and float(it.get("amount", 0.0)) > 0.0:
			_stash_loot(s, c, it)
		_finish_intent(c)
		return
	if kind != "mad" and (c.health < 20.0 or c.hunger < 8.0):
		if kind == "steal":
			_stash_loot(s, c, it)
		_finish_intent(c)
		return
	match kind:
		"steal":
			if it["stage"] == "go":
				var r = _walk(c, it["dest"], delta, 18.0)
				if r == -1:
					_finish_intent(c)
				elif r == 1:
					_do_steal(s, c, it)
			elif it["stage"] == "flee":
				var home_p = c.home_pos
				if home_p == Vector2.ZERO:
					_stash_loot(s, c, it)
					_finish_intent(c, 5.0)
					return
				var r2 = _walk(c, home_p, delta, 14.0)
				if r2 != 0:
					_stash_loot(s, c, it)
					_finish_intent(c, 5.0)
		"good_feed", "good_heal", "good_comfort":
			var t = s.get_citizen_by_id(String(it.get("target_id", "")))
			if t == null or not t.is_alive or t.custom_data.has("duel") or is_jailed(t):
				_give_back_food(s, c, it)
				_finish_intent(c)
				return
			if it["stage"] == "fetch":
				var r = _walk(c, c.home_pos, delta, 16.0) if c.home_pos != Vector2.ZERO else -1
				if r == -1:
					_finish_intent(c)
				elif r == 1:
					var home = s.get_citizen_home_instance(c)
					if home == null or home.food_stockpile < 0.5:
						_finish_intent(c)
						return
					home.food_stockpile -= 0.5
					it["carried_food"] = 0.5
					it["stage"] = "go"
					c.last_status_reason = "Несёт еду из дома для %s" % t.name
				return
			if c.pos.distance_to(t.pos) <= MELEE_RANGE + 6.0:
				_do_good_deed(s, c, t, kind, it)
				it["carried_food"] = 0.0
				_finish_intent(c, 4.0)
				return
			_chase(c, t, it, delta)
		"hunt":
			var t = s.get_citizen_by_id(String(it.get("target_id", "")))
			if t == null or not t.is_alive or is_jailed(t):
				_finish_intent(c)
				return
			if c.pos.distance_to(t.pos) <= MELEE_RANGE + 4.0:
				start_duel(s, c, t, revenge_is_lethal(c), c.revenge_reason if c.revenge_reason != "" else "Месть")
				return
			_chase(c, t, it, delta)
		"despair":
			if it["stage"] == "go":
				if _walk(c, it["dest"], delta, 14.0) != 0:
					it["stage"] = "sit"
					it["until"] = _now() + randf_range(25.0, 45.0)
					c.shout(DESPAIR_LINES[randi() % DESPAIR_LINES.size()], 3.0)
			else:
				c.state = CitizenNPC.State.MOURNING
				c.last_status_reason = "Сидит в унынии, ни на что нет сил"
				c.show_emote("depression", 3.0, 3)
				if _now() >= float(it.get("until", 0.0)):
					_finish_intent(c, 5.0)
		"mad":
			if _walk(c, it["dest"], delta, 14.0) != 0:
				c.shout(MAD_LINES[randi() % MAD_LINES.size()], 3.5)
				c.show_emote("dizziness", 3.0, 4, true)
				# Крики пугают соседей
				for w in RulerDeeds.witnesses(s, c.pos, [c]):
					w.show_emote("fear", 2.0, 2)
				_finish_intent(c, randf_range(3.0, 6.0))
		_:
			_finish_intent(c)

static func _chase(c: CitizenNPC, t: CitizenNPC, it: Dictionary, delta: float) -> void:
	it["repath"] = float(it.get("repath", 0.0)) - delta
	if float(it["repath"]) <= 0.0 or c.path.is_empty():
		it["repath"] = 2.0
		c.path.clear()
	if _walk(c, t.pos, delta, MELEE_RANGE) == -1:
		_step_toward(c, t.pos, delta, 1.0)

static func _give_back_food(s: SettlementData, c: CitizenNPC, it: Dictionary) -> void:
	var food = float(it.get("carried_food", 0.0))
	if food <= 0.0:
		return
	var home = s.get_citizen_home_instance(c)
	if home:
		home.food_stockpile += food
	else:
		s.deposit_resource("food", food)
	it["carried_food"] = 0.0
