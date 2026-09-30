class_name CoupPlot
extends RefCounted

# ==============================================================================
# ЗАГОВОР И ПЕРЕВОРОТ
# ------------------------------------------------------------------------------
# Когда племя разуверилось в вожде, честолюбивый или воинственный недовольный
# собирает вокруг себя заговорщиков: недовольных, обиженных вождём, родню убитых.
# Заговор тайный — о нём можно узнать из слухов (разговор с жителями) или от
# верного доносчика. Вождь может взять главаря под стражу (через разговор, если
# есть верная стража), казнить его, либо вернуть людям веру в себя — тогда
# заговорщики отпадают.
# Созревший заговор поднимает мятеж: силы заговорщиков против вождя, правой руки
# и верных. Победа мятежников — вождь свергнут (конец партии). Поражение —
# главарь гибнет, заговорщики изранены и напуганы, порядок в племени подорван.
# Состояние: SettlementData.coup_plot
#   {leader_id, members: [ids], days, revealed, informant_id}
# ==============================================================================

const MIN_MEMBERS: int = 3
const RIPE_DAYS: int = 4
const REVEALED_RIPE_DAYS: int = 3
const COOLDOWN_DAYS: int = 12

static func _adults(s: SettlementData) -> Array[CitizenNPC]:
	var res: Array[CitizenNPC] = []
	for c in s.population.citizens:
		if c.is_alive and not c.is_ruler and c.cohort in ["youth", "adult", "elder"]:
			res.append(c)
	return res

static func _hates_ruler(c: CitizenNPC, ruler: CitizenNPC) -> bool:
	return c.has_memory("kin_murdered_by_ruler") or (ruler != null and c.revenge_target_id == ruler.citizen_id) or (ruler != null and c.has_grudge_against(ruler.citizen_id))

static func is_member(s: SettlementData, c: CitizenNPC) -> bool:
	return not s.coup_plot.is_empty() and s.coup_plot.get("members", []).has(c.citizen_id)

static func is_leader(s: SettlementData, c: CitizenNPC) -> bool:
	return not s.coup_plot.is_empty() and String(s.coup_plot.get("leader_id", "")) == c.citizen_id

static func get_leader(s: SettlementData) -> CitizenNPC:
	if s.coup_plot.is_empty():
		return null
	return s.get_citizen_by_id(String(s.coup_plot.get("leader_id", "")))

static func daily_tick(s: SettlementData) -> void:
	if not s.is_player_settlement():
		return
	var ruler = PlayerHero.get_ruler(s)
	if ruler == null or not ruler.is_alive:
		return
	var day = GameManager.current_day if GameManager else 0
	if s.coup_plot.is_empty():
		if day >= s.coup_cooldown_day:
			_try_form(s, ruler)
		return
	var plot = s.coup_plot
	var leader = get_leader(s)
	# Главарь мёртв или под стражей — заговор рассыпается
	if leader == null or not leader.is_alive or NPCIntentions.is_jailed(leader):
		_collapse(s, "Главарь заговора %s" % ("под стражей" if leader and leader.is_alive else "мёртв"))
		return
	plot["days"] = int(plot.get("days", 0)) + 1
	_recruit(s, ruler, leader)
	_drop_loyal(s)
	var members: Array = plot["members"]
	if members.size() <= 1 and int(plot["days"]) >= 3:
		_collapse(s, "Никто не поддержал %s" % leader.name)
		return
	if not plot.get("revealed", false):
		_try_inform(s, ruler, leader)
	# Созрел ли мятеж?
	var adults = _adults(s)
	var need = maxi(MIN_MEMBERS, int(ceil(adults.size() * 0.25)))
	var ripe_days = REVEALED_RIPE_DAYS if plot.get("revealed", false) else RIPE_DAYS
	if int(plot["days"]) >= ripe_days and members.size() >= need and (s.economy.loyalty < 40.0 or plot.get("revealed", false)):
		execute(s, ruler)

static func _try_form(s: SettlementData, ruler: CitizenNPC) -> void:
	var best: CitizenNPC = null
	var best_score = 0.0
	for c in _adults(s):
		if NPCIntentions.is_jailed(c) or c.mental_state == "mad":
			continue
		var hates = _hates_ruler(c, ruler)
		if c.loyalty >= 30.0 and not (hates and c.loyalty < 45.0):
			continue
		if not (float(c.traits.get("ambition", 50.0)) >= 60.0 or NPCPsyche.is_warlike(c)):
			continue
		if s.economy.loyalty >= 45.0 and not hates:
			continue
		var score = float(c.traits.get("ambition", 50.0)) + (100.0 - c.loyalty) + (30.0 if hates else 0.0)
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		return
	s.coup_plot = {"leader_id": best.citizen_id, "members": [best.citizen_id], "days": 0, "revealed": false, "informant_id": ""}
	best.add_memory("conspiracy", best.citizen_id, ruler.citizen_id, 1.0, "Задумал свергнуть вождя", true)
	best.show_emote("rebellion", 4.0, 4)

static func _recruit(s: SettlementData, ruler: CitizenNPC, leader: CitizenNPC) -> void:
	var members: Array = s.coup_plot["members"]
	for c in _adults(s):
		if members.has(c.citizen_id) or NPCIntentions.is_jailed(c) or c.mental_state == "mad":
			continue
		if s.council and s.council.get_regent(s) == c:
			continue
		var hates = _hates_ruler(c, ruler)
		var ready = c.loyalty < 40.0 or hates or (c.mental_state == "bitter" and c.loyalty < 55.0)
		if not ready:
			continue
		var chance = 0.3
		# Легче вербуют друзья и родня заговорщиков
		for m_id in members:
			var aff = c.get_relationship_affinity(m_id)
			if aff >= 25.0:
				chance += 0.2
			elif aff <= -20.0:
				chance -= 0.2
		if hates:
			chance += 0.25
		if randf() < clampf(chance, 0.05, 0.9):
			members.append(c.citizen_id)
			c.add_memory("conspiracy", leader.citizen_id, ruler.citizen_id, 1.0, "%s позвал меня в заговор против вождя" % leader.name, true)

# Вернувший веру в вождя выходит из заговора — и может донести
static func _drop_loyal(s: SettlementData) -> void:
	var members: Array = s.coup_plot["members"]
	var i = members.size() - 1
	while i >= 0:
		var c = s.get_citizen_by_id(String(members[i]))
		if c == null or not c.is_alive:
			members.remove_at(i)
		elif String(members[i]) != String(s.coup_plot["leader_id"]) and c.loyalty >= 60.0 and not c.has_memory("kin_murdered_by_ruler"):
			members.remove_at(i)
			if not s.coup_plot.get("revealed", false) and float(c.traits.get("honesty", 50.0)) >= 50.0:
				_reveal(s, c, "одумался и выдал бывших товарищей")
		i -= 1

static func _try_inform(s: SettlementData, ruler: CitizenNPC, leader: CitizenNPC) -> void:
	if int(s.coup_plot["days"]) < 2:
		return
	var members: Array = s.coup_plot["members"]
	for c in _adults(s):
		if members.has(c.citizen_id) or c.loyalty < 65.0:
			continue
		var close_to_plot = false
		for m_id in members:
			if c.get_relationship_affinity(m_id) >= 10.0 or RulerDeeds.is_kin(c, s.get_citizen_by_id(m_id)):
				close_to_plot = true
				break
		var is_council = s.council != null and s.council.is_member(s, c.citizen_id)
		if not close_to_plot and not is_council:
			continue
		if randf() < (0.35 if is_council else 0.2):
			_reveal(s, c, "доносит вождю")
			return

static func _reveal(s: SettlementData, informant: CitizenNPC, how: String) -> void:
	var leader = get_leader(s)
	s.coup_plot["revealed"] = true
	s.coup_plot["informant_id"] = informant.citizen_id if informant else ""
	if informant:
		informant.add_memory("informed_on_plot", informant.citizen_id, leader.citizen_id if leader else "", 1.0, "Предупредил вождя о заговоре")
	GameManager.add_history_entry(GameManager.current_year, "Раскрыт заговор", "%s %s: %s собирает людей против вождя" % [informant.name if informant else "Кто-то", how, leader.name if leader else "?"], "Власть и закон")
	EventBus.notification_toast.emit("🗡 Заговор против вождя!",
		"%s %s: %s собирает заговорщиков (%d чел.). Возьмите главаря под стражу (поговорите с ним в Режиме Короля) или верните доверие племени — иначе будет мятеж!" % [informant.name if informant else "Кто-то", how, leader.name if leader else "?", s.coup_plot["members"].size()], "danger")

static func reveal_by_gossip(s: SettlementData, teller: CitizenNPC) -> void:
	if not s.coup_plot.is_empty() and not s.coup_plot.get("revealed", false):
		_reveal(s, teller, "проболтался")

static func _collapse(s: SettlementData, why: String) -> void:
	for m_id in s.coup_plot.get("members", []):
		var c = s.get_citizen_by_id(String(m_id))
		if c and c.is_alive:
			c.add_memory("disappointment", "", c.citizen_id, 0.8, "Заговор рассыпался: %s" % why)
	if s.coup_plot.get("revealed", false):
		EventBus.notification_toast.emit("🕊 Заговор рассыпался", why, "good")
	s.coup_plot = {}
	s.coup_cooldown_day = (GameManager.current_day if GameManager else 0) + COOLDOWN_DAYS

static func _fighter_power(c: CitizenNPC) -> float:
	var st = c.get_combat_stats()
	var p = float(st.get("raw_damage", 5.0)) * (c.health / maxf(1.0, c.max_health))
	if c.job_id in ["guard", "warrior"]:
		p *= 1.5
	return p

# Сравнение сил мятежа и верных
static func get_balance(s: SettlementData, ruler: CitizenNPC) -> Dictionary:
	var members: Array = s.coup_plot.get("members", [])
	var rebel = 0.0
	var loyal = _fighter_power(ruler) * 2.0 if ruler else 0.0
	var regent = s.council.get_regent(s) if s.council else null
	for c in _adults(s):
		if NPCIntentions.is_jailed(c):
			continue
		if members.has(c.citizen_id):
			rebel += _fighter_power(c)
		elif c == regent or (c.job_id in ["guard", "warrior"] and c.loyalty >= 50.0):
			loyal += _fighter_power(c)
		elif c.loyalty >= 60.0:
			loyal += _fighter_power(c) * 0.5
	return {"rebel": rebel, "loyal": loyal}

static func execute(s: SettlementData, ruler: CitizenNPC) -> void:
	var leader = get_leader(s)
	var bal = get_balance(s, ruler)
	var rebel = bal["rebel"] * randf_range(0.85, 1.15)
	var loyal = bal["loyal"] * randf_range(0.85, 1.15)
	var members: Array = s.coup_plot["members"].duplicate()
	if rebel > loyal:
		GameManager.add_history_entry(GameManager.current_year, "Переворот", "%s с %d заговорщиками сверг вождя %s" % [leader.name, members.size(), ruler.name], "Власть и закон")
		s.coup_plot = {}
		GameManager.trigger_game_over("Переворот! %s и ещё %d заговорщиков свергли вождя %s. Племя больше не признаёт вас своим предводителем." % [leader.name, members.size() - 1, ruler.name])
		return
	# Мятеж подавлен
	leader.death_cause = "Погиб при подавлении мятежа"
	leader.take_damage(leader.health + 1.0, "мятеж")
	var hurt = 0
	for m_id in members:
		var c = s.get_citizen_by_id(String(m_id))
		if c == null or not c.is_alive:
			continue
		c.health = maxf(5.0, c.health - 30.0)
		c.add_memory("coup_crushed", ruler.citizen_id, c.citizen_id, 1.0, "Мятеж подавлен, %s погиб" % leader.name, true)
		c.show_emote("fear", 4.0, 5, true)
		hurt += 1
	# Верные изранены в стычке, но их вера крепнет
	for c in _adults(s):
		if not members.has(c.citizen_id) and c.job_id in ["guard", "warrior"] and c.loyalty >= 50.0:
			c.health = maxf(10.0, c.health - 15.0)
			c.add_memory("defended_tribe", ruler.citizen_id, c.citizen_id, 1.0, "Защитил вождя от мятежников")
			c.loyalty = minf(100.0, c.loyalty + 5.0)
	s.economy.stability = maxf(0.0, s.economy.stability - 15.0)
	GameManager.add_history_entry(GameManager.current_year, "Мятеж подавлен", "Мятеж %s против вождя %s подавлен. Главарь погиб, %d заговорщиков изранены" % [leader.name, ruler.name, hurt], "Власть и закон")
	EventBus.notification_toast.emit("⚔ Мятеж подавлен!", "%s поднял мятеж и погиб. Заговорщики (%d) изранены и напуганы. Силы: мятеж %d против верных %d." % [leader.name, hurt, int(rebel), int(loyal)], "warning")
	s.coup_plot = {}
	s.coup_cooldown_day = (GameManager.current_day if GameManager else 0) + COOLDOWN_DAYS

# Вождь приказывает взять заговорщика под стражу (нужна верная стража)
static func order_arrest(s: SettlementData, ruler: CitizenNPC, suspect: CitizenNPC) -> Dictionary:
	var guard = NPCIntentions._nearest_loyal_guard(s, suspect, [])
	if guard == null:
		for g in s.population.citizens:
			if g.is_alive and g.job_id in ["guard", "warrior"] and g.loyalty >= 50.0 and g != suspect and not NPCIntentions.is_busy(g):
				guard = g
				break
	if guard == null:
		return {"ok": false, "reply": "И кто меня возьмёт? Твоя стража тебе не верна!"}
	var was_leader = is_leader(s, suspect)
	NPCIntentions.arrest(s, suspect, guard, 2.0, "заговор против вождя")
	if is_member(s, suspect):
		s.coup_plot["members"].erase(suspect.citizen_id)
	# Остальные видят силу вождя
	for c in _adults(s):
		if is_member(s, c):
			c.loyalty = maxf(0.0, c.loyalty - 3.0)
			c.stress = clampf(c.stress + 6.0, 0.0, 100.0)
	return {"ok": true, "was_leader": was_leader, "reply": "Будь ты проклят, вождь! Ещё посмотрим, чья возьмёт..."}
