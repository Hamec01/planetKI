class_name ElderCouncil
extends RefCounted

# ==============================================================================
# СОВЕТ СТАРЕЙШИН И ПРАВАЯ РУКА ВОЖДЯ
# ------------------------------------------------------------------------------
# • Совет: естественные старейшины (46+ лет), работники Дома старейшин и
#   уважаемые взрослые, которых вождь сам призвал в совет (до MAX_APPOINTED).
# • Правая рука (верховный старейшина) — один член совета. Вождь может поручить
#   ему решать события по сферам (хозяйство, семья, закон, вера, угрозы).
# • Поручённые события Правая рука решает сам — по своему характеру (традиции,
#   сострадание, трудолюбие, честолюбие, храбрость, любопытство). Каждое решение
#   записывается в журнал совета с объяснением и в летопись.
# • Решения реально меняют отношение жителей к Правой руке: близкие ему по духу
#   уважают его больше, несогласные — меньше. Нелояльный вождю старейшина может
#   сложить полномочия, а его гибель возвращает все решения вождю.
# ==============================================================================

const MAX_APPOINTED: int = 5
const MIN_APPOINT_AGE: int = 25
const ELDER_AGE: int = 46
const RESIGN_LOYALTY: float = 25.0
const JOURNAL_LIMIT: int = 40

# Сферы поручений: id -> название и ключевые слова категорий событий
const SPHERES: Dictionary = {
	"economy": {"name": "🌾 Хозяйство и промысел", "keys": ["хозяйств", "эконом", "лесозаготов", "охот", "промысел", "запас", "ремесл", "собственност", "распределен", "приручен", "природ", "эколог", "аврал", "вредител", "изобретен", "труд", "земл"]},
	"family": {"name": "👪 Семья и дети", "keys": ["семья", "семьи", "воспитан", "сирот", "обучен", "поколен", "социальные узы", "дружба", "гостеприим", "община", "жизнь племени", "безопасность дома", "кров"]},
	"law": {"name": "⚖️ Закон и власть", "keys": ["власт", "право", "закон", "мораль", "табу", "политик", "спор", "суд", "общество"]},
	"faith": {"name": "🔮 Вера и традиции", "keys": ["вер", "святын", "традиц", "памят", "культур", "знани", "наблюден", "обыча"]},
	"danger": {"name": "⚠️ Угрозы и беды", "keys": ["опасн", "война", "кризис", "поиск", "спасен", "ветеран", "угроз", "нападен", "хищник"]}
}

var settlement_id: String = ""
var appointed_ids: Array[String] = [] # Призванные вождём в совет
var regent_id: String = "" # Правая рука — верховный старейшина
var delegated_spheres: Array[String] = [] # Сферы, решения по которым поручены Правой руке
var journal: Array[Dictionary] = [] # Записи о решениях Правой руки

func _init(p_settlement_id: String = "") -> void:
	settlement_id = p_settlement_id

# --- СОСТАВ СОВЕТА ---

func is_natural_elder(c: CitizenNPC) -> bool:
	return c.cohort == "elder" or c.age >= ELDER_AGE or c.job_id == "elder"

func get_members(s: SettlementData) -> Array[CitizenNPC]:
	var result: Array[CitizenNPC] = []
	if s == null or s.population == null:
		return result
	for c in s.population.citizens:
		if not c.is_alive or c.is_ruler:
			continue
		if is_natural_elder(c) or appointed_ids.has(c.citizen_id):
			result.append(c)
	return result

# Кого вождь может призвать в совет (взрослые, ещё не члены)
func get_candidates(s: SettlementData) -> Array[CitizenNPC]:
	var result: Array[CitizenNPC] = []
	if s == null or s.population == null:
		return result
	for c in s.population.citizens:
		if not c.is_alive or c.is_ruler or c.age < MIN_APPOINT_AGE:
			continue
		if is_natural_elder(c) or appointed_ids.has(c.citizen_id):
			continue
		result.append(c)
	result.sort_custom(func(a, b): return get_authority(s, a) > get_authority(s, b))
	return result

func is_member(s: SettlementData, citizen_id: String) -> bool:
	for m in get_members(s):
		if m.citizen_id == citizen_id:
			return true
	return false

func appoint_member(s: SettlementData, citizen_id: String) -> Dictionary:
	var c = s.population.find_citizen(citizen_id) if s and s.population else null
	if c == null or not c.is_alive or c.is_ruler:
		return {"ok": false, "reason": "Житель не найден"}
	if is_member(s, citizen_id):
		return {"ok": false, "reason": "%s уже в совете" % c.name}
	if c.age < MIN_APPOINT_AGE:
		return {"ok": false, "reason": "В совет призывают с %d лет" % MIN_APPOINT_AGE}
	if appointed_ids.size() >= MAX_APPOINTED:
		return {"ok": false, "reason": "В совете уже %d призванных — сначала отпустите кого-то" % MAX_APPOINTED}
	appointed_ids.append(citizen_id)
	c.loyalty = minf(100.0, c.loyalty + 6.0)
	c.add_memory("council_appointed", "ruler", c.citizen_id, 2.0, "Вождь призвал в Совет старейшин", true)
	c.show_emote("respect", 4.0, 3)
	EventBus.notification_toast.emit("🏛 Совет старейшин", "%s призван(а) в Совет старейшин" % c.name, "good")
	return {"ok": true, "reason": ""}

func dismiss_member(s: SettlementData, citizen_id: String) -> Dictionary:
	if not appointed_ids.has(citizen_id):
		return {"ok": false, "reason": "Естественных старейшин нельзя отпустить из совета"}
	appointed_ids.erase(citizen_id)
	var c = s.population.find_citizen(citizen_id) if s and s.population else null
	if c:
		c.loyalty = maxf(0.0, c.loyalty - 8.0)
		c.add_memory("council_dismissed", "ruler", c.citizen_id, 1.5, "Вождь отпустил из Совета старейшин")
	if regent_id == citizen_id:
		revoke_regent(s, "отпущен из совета")
	return {"ok": true, "reason": ""}

# Авторитет в племени: уважение соплеменников + возраст + мастерство + преданность вождю
func get_authority(s: SettlementData, c: CitizenNPC) -> float:
	var respect_sum = 0.0
	var count = 0
	if s and s.population:
		for other in s.population.citizens:
			if other == c or not other.is_alive:
				continue
			var rel = other.get_relationship(c.citizen_id)
			if rel.is_empty():
				continue
			respect_sum += float(rel.get("respect", 0.0)) + float(rel.get("affinity", 0.0)) * 0.3
			count += 1
	var respect = respect_sum / float(count) if count > 0 else 0.0
	var best_xp = 0.0
	for k in c.experience:
		best_xp = maxf(best_xp, float(c.experience[k]))
	return clampf(35.0 + respect * 0.5 + minf(20.0, float(c.age - 20) * 0.5) + minf(15.0, best_xp * 0.1) + (c.loyalty - 50.0) * 0.2, 0.0, 100.0)

# Краткая характеристика, как будет решать этот человек
func describe_style(c: CitizenNPC) -> String:
	var parts: Array[String] = []
	var tr = float(c.traits.get("tradition", 50.0))
	var em = float(c.traits.get("empathy", 50.0))
	var di = float(c.traits.get("diligence", 50.0))
	var am = float(c.traits.get("ambition", 50.0))
	var br = float(c.traits.get("bravery", 50.0))
	var cu = float(c.traits.get("curiosity", 50.0))
	if tr >= 60.0: parts.append("чтит обычаи предков")
	elif tr <= 40.0: parts.append("открыт новому")
	if em >= 60.0: parts.append("милосерден")
	elif em <= 35.0: parts.append("суров")
	if di >= 60.0: parts.append("бережёт труд и запасы")
	if am >= 65.0: parts.append("честолюбив, тянет власть к себе")
	if br >= 65.0: parts.append("смел до безрассудства")
	elif br <= 35.0: parts.append("осторожен")
	if cu >= 65.0: parts.append("жаден до знаний")
	if parts.is_empty():
		parts.append("рассудителен, без крайностей")
	return ", ".join(parts)

# --- ПРАВАЯ РУКА ---

func get_regent(s: SettlementData) -> CitizenNPC:
	if regent_id == "" or s == null or s.population == null:
		return null
	var c = s.population.find_citizen(regent_id)
	if c == null or not c.is_alive:
		return null
	return c

func appoint_regent(s: SettlementData, citizen_id: String) -> Dictionary:
	if not is_member(s, citizen_id):
		return {"ok": false, "reason": "Правой рукой может стать только член совета"}
	var c = s.population.find_citizen(citizen_id)
	if c.loyalty < RESIGN_LOYALTY + 5.0:
		return {"ok": false, "reason": "%s не доверяет вождю (преданность %d) и отказывается" % [c.name, int(c.loyalty)]}
	var prev = get_regent(s)
	if prev and prev != c:
		prev.add_memory("regent_replaced", "ruler", prev.citizen_id, 1.5, "Вождь сменил Правую руку")
		prev.loyalty = maxf(0.0, prev.loyalty - 5.0)
	regent_id = citizen_id
	c.loyalty = minf(100.0, c.loyalty + 10.0)
	c.add_memory("regent_appointed", "ruler", c.citizen_id, 3.0, "Стал Правой рукой вождя — верховным старейшиной", true)
	c.show_emote("respect", 5.0, 4)
	c.shout("Я буду вершить дела рода по совести!", 3.5)
	EventBus.notification_toast.emit("👑 Правая рука вождя", "%s — верховный старейшина. %s." % [c.name, describe_style(c).capitalize()], "good")
	GameManager.add_history_entry(GameManager.current_year, "Верховный старейшина", "Вождь назначил %s своей Правой рукой" % c.name, "Власть и закон")
	return {"ok": true, "reason": ""}

func revoke_regent(s: SettlementData, reason: String = "") -> void:
	var c = get_regent(s) if s else null
	var name = c.name if c else "Правая рука"
	regent_id = ""
	var had_power = not delegated_spheres.is_empty()
	delegated_spheres.clear()
	if c:
		c.add_memory("regent_revoked", "ruler", c.citizen_id, 1.5, "Лишился поста Правой руки")
	if had_power or reason != "":
		EventBus.notification_toast.emit("👑 Власть возвращена вождю", "%s больше не Правая рука%s. Все решения снова за вождём." % [name, (" (" + reason + ")") if reason != "" else ""], "warning")

func set_sphere_delegated(s: SettlementData, sphere: String, enabled: bool) -> void:
	if not SPHERES.has(sphere):
		return
	if enabled:
		if get_regent(s) == null:
			return
		if not delegated_spheres.has(sphere):
			delegated_spheres.append(sphere)
	else:
		delegated_spheres.erase(sphere)

func delegate_all(s: SettlementData, enabled: bool) -> void:
	for sp in SPHERES:
		set_sphere_delegated(s, sp, enabled)

static func get_event_sphere(ev: Dictionary) -> String:
	var cat = String(ev.get("category", "")).to_lower()
	if ev.get("is_threat", false) or ev.get("type", "") in ["incident", "threat"]:
		return "danger"
	for sp in ["danger", "family", "faith", "law", "economy"]:
		for k in SPHERES[sp]["keys"]:
			if cat.contains(k):
				return sp
	return "law"

func is_delegated(s: SettlementData, ev: Dictionary) -> bool:
	return get_regent(s) != null and delegated_spheres.has(get_event_sphere(ev))

# Проверка состояния Правой руки (вызывается поселением раз в день)
func daily_check(s: SettlementData) -> void:
	if regent_id == "":
		return
	var c = s.population.find_citizen(regent_id) if s and s.population else null
	if c == null or not c.is_alive:
		revoke_regent(s, "Правая рука ушёл(ла) к предкам")
		return
	if c.loyalty < RESIGN_LOYALTY:
		c.shout("Я не стану больше служить этому вождю!", 3.5)
		revoke_regent(s, "%s сложил(а) полномочия из-за недоверия к вождю" % c.name)

# --- ПРИНЯТИЕ РЕШЕНИЙ ---

# Оценка варианта по чертам характера. Возвращает {"score": float, "reason": String}
func score_choice(c: CitizenNPC, choice: Dictionary) -> Dictionary:
	var tr = float(c.traits.get("tradition", 50.0)) - 50.0
	var em = float(c.traits.get("empathy", 50.0)) - 50.0
	var di = float(c.traits.get("diligence", 50.0)) - 50.0
	var am = float(c.traits.get("ambition", 50.0)) - 50.0
	var br = float(c.traits.get("bravery", 50.0)) - 50.0
	var cu = float(c.traits.get("curiosity", 50.0)) - 50.0
	var f = _choice_features(choice)
	# Вклад каждой черты и то, как старейшина объяснит решение (зависит от знака черты)
	var contributions = [
		[tr * f["tradition"] - tr * 0.5 * f["innovation"], "чтит заветы предков" if tr >= 0.0 else "не держится за старое"],
		[cu * f["innovation"], "ищет новое знание" if cu >= 0.0 else "не доверяет новшествам"],
		[em * (f["compassion"] - 0.8 * f["harsh"]), "милосерден к слабым" if em >= 0.0 else "считает, что род держится на строгости"],
		[di * (f["gain"] - 0.6 * f["cost"]), "бережёт труд и запасы" if di >= 0.0 else "не хочет лишних хлопот"],
		[am * f["authority"], "укрепляет власть" if am >= 0.0 else "не любит лишней власти"],
		[br * f["bravery"], "ценит смелость" if br >= 0.0 else "осторожен и бережёт людей"]
	]
	# Общее благо ценит любой старейшина: согласие в роду, запасы, отсутствие потерь
	var score = f["harmony"] * 6.0 + f["gain"] * 3.0 - f["cost"] * 3.0
	var best_reason = "ради согласия в роду" if f["harmony"] > 0.0 else "по здравому смыслу"
	var best_val = maxf(0.0, f["harmony"] * 6.0)
	for pair in contributions:
		score += float(pair[0])
		if float(pair[0]) > best_val:
			best_val = float(pair[0])
			best_reason = pair[1]
	return {"score": score, "reason": best_reason}

func _choice_features(choice: Dictionary) -> Dictionary:
	var f = {"harmony": 0.0, "tradition": 0.0, "innovation": 0.0, "compassion": 0.0, "harsh": 0.0,
		"gain": 0.0, "cost": 0.0, "authority": 0.0, "bravery": 0.0}
	var cons: Dictionary = choice.get("consequences", {})
	for key in cons:
		var v = cons[key]
		var num = 1.0
		if v is float or v is int:
			num = float(v)
		elif v is bool and not v:
			num = 0.0
		match key:
			"modify_harmony", "cohesion", "tribal_loyalty", "modify_loyalty_all", "hunter_cohesion", "clans_reconciled", "generational_balance":
				f["harmony"] += clampf(num / 5.0, -3.0, 3.0)
			"traditions", "elder_respect", "traditional_elder_power", "ancient_blood_customs", "clan_purity", "balanced_tradition", "ancestor_burial", "nature_respect", "shrine_sanctity", "spiritual_zeal", "clan_elder_influence", "hunter_blessing_ritual", "waste_taboo", "sustainable_nature", "sustainable_hunting":
				f["tradition"] += 1.0
			"innovation_boost", "meritocracy_power", "knowledge_public", "humanist_education", "individualism", "private_property", "knowledge_transfer_boost", "apprentice_trained", "mandatory_teaching", "pragmatism":
				f["innovation"] += 1.0
			"care_weak", "ward_of_lodge", "family_adoption", "save_hunter", "tracker_rescue", "safety_priority", "cautious_youth", "stranger_admitted", "tradition_spare_mothers", "mentor_bond", "parent_work_boost":
				f["compassion"] += 1.0
			"hunter_loss_risk", "domestic_brawl", "meat_waste", "consume_all_seeds":
				f["harsh"] += 1.0
				f["cost"] += 1.0
			"wood_cost", "labor_cost", "bone_cost", "consume_half_seeds":
				f["cost"] += 1.0
			"add_food", "leather", "bone", "add_grain", "add_bread", "add_straw", "modify_resources", "preserve_seeds", "master_skill_saved":
				f["gain"] += 1.0
			"ruler_authority", "ruler_prestige", "clan_nobility", "landlord_concept", "tribal_tax_concept":
				f["authority"] += 1.0
			"bravery_test", "hunter_courage", "hunt_damage_boost", "hunter_morale", "hunter_motivation", "youth_hunt_training", "bear_totem":
				f["bravery"] += 1.0
		if key.begins_with("unlock_") or key.begins_with("add_knowledge"):
			f["gain"] += 0.5
			f["innovation"] += 0.3
	# Варианты без последствий (становление обычаев) оцениваются по смыслу текста
	var txt = (String(choice.get("title", "")) + " " + String(choice.get("desc", "")) + " " + String(choice.get("effects_desc", ""))).to_lower()
	var kw = {
		"tradition": ["предк", "обыча", "традиц", "старейшин", "завет", "дух"],
		"innovation": ["нов", "знани", "учить", "откры", "опыт", "разум"],
		"compassion": ["помо", "забот", "защит", "спас", "накорм", "сирот", "дет", "слаб", "милос", "прият"],
		"harsh": ["изгн", "наказ", "выгн", "казн", "силой", "драк", "запрет", "выселить", "отказ"],
		"authority": ["вожд", "власт", "правител"],
		"bravery": ["охот", "бой", "смел", "испыта", "сраж"],
		"gain": ["запас", "добыч", "урожа", "еды", "дров"]
	}
	for feat in kw:
		for w in kw[feat]:
			if txt.contains(w):
				f[feat] += 0.35
	if txt.contains("согласи") or txt.contains("мир"):
		f["harmony"] += 0.5
	return f

# Правая рука выбирает вариант. Возвращает {"choice_id", "choice_title", "reason"} или {}
func decide(s: SettlementData, ev: Dictionary) -> Dictionary:
	var c = get_regent(s)
	var choices: Array = ev.get("choices", [])
	if c == null or choices.is_empty():
		return {}
	var best: Dictionary = {}
	var best_score = -INF
	var best_reason = ""
	for ch in choices:
		var r = score_choice(c, ch)
		# Своеволие: у нелояльного вождю старейшины больше случайности в решениях
		var whim = randf_range(0.0, 4.0) + (randf_range(0.0, 12.0) if c.loyalty < 45.0 else 0.0)
		var total = float(r["score"]) + whim
		if total > best_score:
			best_score = total
			best = ch
			best_reason = r["reason"]
	return {"choice_id": best.get("id", ""), "choice_title": best.get("title", ""), "reason": best_reason, "choice": best}

# После решения: жители близкие по духу уважают Правую руку больше, несогласные — меньше
func apply_social_effects(s: SettlementData, regent: CitizenNPC, choice: Dictionary) -> Dictionary:
	var f = _choice_features(choice)
	var approve = 0
	var oppose = 0
	for other in s.population.citizens:
		if other == regent or not other.is_alive or other.is_ruler or other.cohort == "child":
			continue
		var r = score_choice(other, choice)
		if float(r["score"]) >= 8.0:
			other.modify_relationship(regent.citizen_id, 1.0, 2.0)
			approve += 1
		elif float(r["score"]) <= -8.0:
			other.modify_relationship(regent.citizen_id, -1.0, -2.0)
			oppose += 1
	regent.loyalty = minf(100.0, regent.loyalty + (1.0 if f["authority"] <= 0.0 else 0.5))
	return {"approve": approve, "oppose": oppose}

func add_journal_entry(entry: Dictionary) -> void:
	journal.push_front(entry)
	if journal.size() > JOURNAL_LIMIT:
		journal.resize(JOURNAL_LIMIT)

# --- СОХРАНЕНИЕ ---

func serialize() -> Dictionary:
	return {
		"appointed_ids": appointed_ids.duplicate(),
		"regent_id": regent_id,
		"delegated_spheres": delegated_spheres.duplicate(),
		"journal": journal.duplicate(true)
	}

func deserialize(data: Dictionary) -> void:
	appointed_ids.clear()
	for cid in data.get("appointed_ids", []):
		appointed_ids.append(String(cid))
	regent_id = String(data.get("regent_id", ""))
	delegated_spheres.clear()
	for sp in data.get("delegated_spheres", []):
		if SPHERES.has(String(sp)):
			delegated_spheres.append(String(sp))
	journal.clear()
	for e in data.get("journal", []):
		if e is Dictionary:
			journal.append(e)
