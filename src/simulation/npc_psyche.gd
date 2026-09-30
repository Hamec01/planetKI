class_name NPCPsyche
extends RefCounted

# ==============================================================================
# ПСИХИКА ЖИТЕЛЯ
# ------------------------------------------------------------------------------
# Стресс (0..100) копится от пережитого (память) и от тягот (голод, холод, раны,
# бездомность, вражда), снимается добрыми событиями, семьёй и друзьями.
# Из стресса и характера вырастает душевное состояние:
#   stable  — в себе;
#   despair — уныние: погибла вся родня или горе раздавило мягкого человека.
#             Работает вполсилы, сидит в тоске, теряет веру в вождя;
#   bitter  — озлобленность: слишком много зла пережито. Характер ожесточается
#             НАВСЕГДА (вспыльчивость ↑, сочувствие и честность ↓) — такие воруют,
#             затевают драки и мстят;
#   mad     — помешательство: стресс за пределом сил несколько дней подряд.
#             Бродит, кричит бессвязное, может кинуться на соплеменника.
# Все переходы меняют поведение (NPCIntentions), скорость работы и лояльность.
# ==============================================================================

# Вклад воспоминаний в стресс (умножается на важность, не меньше 0.5)
const STRESS_WEIGHTS: Dictionary = {
	# тяжёлое
	"grief": 25.0, "grief_unburied": 15.0, "sorrow": 10.0, "grudge": 8.0, "feud": 10.0,
	"divorce": 15.0, "disappointment": 6.0, "injury": 10.0, "outrage": 8.0,
	"ruler_violence": 12.0, "kin_murdered_by_ruler": 35.0, "kin_murdered": 35.0,
	"ruler_murder": 10.0, "decree_overrode": 5.0, "council_sidelined": 4.0,
	"council_dismissed": 6.0, "job_discontent": 4.0, "regent_revoked": 5.0,
	"regent_replaced": 4.0, "robbed": 12.0, "assaulted": 20.0, "punished": 8.0,
	"witnessed_crime": 3.0, "jailed": 10.0, "ruler_felled_forest": 2.0,
	"coup_crushed": 15.0,
	# светлое
	"gratitude": -8.0, "was_helped": -8.0, "reconciled": -12.0, "romance_date": -6.0,
	"gift": -3.0, "gift_received": -6.0, "comforted_by_ruler": -15.0, "comforted": -12.0,
	"ruler_fed": -6.0, "ruler_housed": -10.0, "flowers_from_ruler": -6.0, "visit": -4.0,
	"job_happiness": -4.0, "honored_burial": -5.0, "ancestor_blessing": -5.0,
	"council_appointed": -6.0, "recovered_from_wounds": -5.0, "helped_neighbor": -4.0,
	"acceptance": -4.0, "decorated_home": -4.0, "defended_tribe": -5.0,
	"sacred_flame": -4.0, "cleansed_shrine": -4.0, "guest": -3.0, "hosted_ruler": -4.0,
	"coming_of_age": -5.0, "council_restored": -4.0, "regent_appointed": -6.0,
	"good_deed": -6.0, "vengeance_done": -20.0, "blood_price": -15.0
}

const STATE_NAMES: Dictionary = {
	"stable": "в себе", "despair": "в унынии", "bitter": "озлоблен", "mad": "помешался"
}
const STATE_ICONS: Dictionary = {"stable": "🙂", "despair": "😞", "bitter": "😠", "mad": "🌀"}

const KIN_TYPES: Array[String] = ["spouse", "late_spouse", "parent", "child", "sibling"]
# Сколько дней стресс ≥ 95 нужно выдержать, чтобы помешаться
const MAD_DAYS: int = 3
const BITTER_BAD_MEMORIES: int = 5

static func memory_stress(p_type: String, p_importance: float) -> float:
	var w = float(STRESS_WEIGHTS.get(p_type, 0.0))
	if w == 0.0:
		return 0.0
	return w * maxf(clampf(p_importance, 0.0, 1.0), 0.5)

static func work_mult(c: CitizenNPC) -> float:
	match c.mental_state:
		"despair":
			return 0.5
		"mad":
			return 0.7
	return 1.0

static func is_warlike(c: CitizenNPC) -> bool:
	if c.cohort == "child":
		return false
	var brave = float(c.traits.get("bravery", 50.0))
	var temper = float(c.traits.get("temper", 20.0))
	var aggr = float(c.traits.get("aggression", 20.0))
	return brave >= 60.0 or temper >= 60.0 or aggr >= 50.0 or (c.mental_state == "bitter" and brave >= 45.0)

static func is_bad_memory(m: Dictionary) -> bool:
	return float(STRESS_WEIGHTS.get(String(m.get("type", "")), 0.0)) >= 8.0 and float(m.get("strength", 100.0)) > 20.0

static func bad_memory_count(c: CitizenNPC) -> int:
	var n = 0
	for m in c.memories:
		if is_bad_memory(m):
			n += 1
	return n

# Была ли у жителя родня — и умерла ли вся
static func kin_all_dead(s: SettlementData, c: CitizenNPC) -> bool:
	var had_kin = false
	for o_id in c.relationships:
		var r: Dictionary = c.relationships[o_id]
		if not (String(r.get("type", "")) in KIN_TYPES or r.get("is_parent", false)):
			continue
		had_kin = true
		var o = s.get_citizen_by_id(o_id)
		if o and o.is_alive:
			return false
	return had_kin

static func _now() -> float:
	return float(GameManager.sim_time_total) if GameManager else 0.0

# --- СУТОЧНОЕ ОБНОВЛЕНИЕ ---

static func daily_update(s: SettlementData, c: CitizenNPC) -> void:
	if not c.is_alive or c.is_ruler or c.custom_data.get("player_controlled", false):
		return
	# 1. Тяготы дня: сколько времени за сутки житель реально голодал и мёрз
	var day = float(GameManager.base_tick_interval) if GameManager else 600.0
	var d = 0.0
	d += 10.0 * clampf(float(c.psyche_counters.get("hungry_sec", 0.0)) / day, 0.0, 1.0)
	d += 8.0 * clampf(float(c.psyche_counters.get("cold_sec", 0.0)) / day, 0.0, 1.0)
	c.psyche_counters["hungry_sec"] = 0.0
	c.psyche_counters["cold_sec"] = 0.0
	if c.health < 50.0:
		d += 4.0
	if c.home_id == "" and c.cohort != "child":
		d += 3.0
	if c.get_rivals().size() >= 2:
		d += 2.0
	if float(c.custom_data.get("jailed_until", 0.0)) > _now():
		d += 4.0
	# 2. Опора: время, семья, друзья, вера в вождя
	var relief = 5.0
	if c.spouse_id != "":
		var sp = s.get_citizen_by_id(c.spouse_id)
		if sp and sp.is_alive:
			relief += 3.0
	if c.get_friends().size() >= 2:
		relief += 2.0
	if c.loyalty >= 70.0:
		relief += 1.0
	if c.mental_state == "despair":
		relief *= 0.6 # тоска сама себя держит
	c.stress = clampf(c.stress + d - relief, 0.0, 100.0)

	# 3. Счётчики дней
	var pc = c.psyche_counters
	pc["overload_days"] = int(pc.get("overload_days", 0)) + 1 if c.stress >= 95.0 else 0
	pc["calm_days"] = int(pc.get("calm_days", 0)) + 1 if c.stress < 40.0 else 0
	pc["state_days"] = int(pc.get("state_days", 0)) + 1

	# 4. Переходы состояний
	var bad = bad_memory_count(c)
	var unpredictable = bool(c.traits.get("unpredictable", false))
	var goes_mad = int(pc["overload_days"]) >= MAD_DAYS or (unpredictable and c.stress >= 85.0)
	match c.mental_state:
		"stable":
			if goes_mad:
				set_state(s, c, "mad", "Разум не выдержал того, что пришлось пережить")
			elif kin_all_dead(s, c) and c.stress >= 30.0 and c.cohort != "child":
				set_state(s, c, "despair", "Вся родня ушла к предкам — не для кого жить")
			elif c.stress >= 70.0 and (float(c.traits.get("empathy", 50.0)) >= 55.0 or float(c.traits.get("bravery", 50.0)) < 45.0):
				set_state(s, c, "despair", "Горе раздавило мягкую душу")
			elif (bad >= BITTER_BAD_MEMORIES and c.stress >= 50.0) or (c.stress >= 75.0 and float(c.traits.get("temper", 20.0)) >= 55.0):
				set_state(s, c, "bitter", "Слишком много зла видел — ожесточился")
		"despair":
			if goes_mad:
				set_state(s, c, "mad", "Тоска свела с ума")
			elif c.stress < 25.0:
				set_state(s, c, "stable", "Снова находит радость в жизни")
			elif int(pc["state_days"]) >= 6 and bad >= BITTER_BAD_MEMORIES and float(c.traits.get("temper", 20.0)) >= 40.0:
				set_state(s, c, "bitter", "Тоска переросла в злобу на весь мир")
		"bitter":
			if goes_mad:
				set_state(s, c, "mad", "Злоба выжгла рассудок")
			elif c.stress < 25.0 and bad < 3:
				set_state(s, c, "stable", "Оттаял душой (но характер уже не тот)")
		"mad":
			if int(pc.get("calm_days", 0)) >= 3:
				set_state(s, c, "stable", "Пришёл в себя после помешательства")

	# 5. Последствия состояния за день
	match c.mental_state:
		"despair":
			c.loyalty = maxf(0.0, c.loyalty - 0.5)
			c.show_emote("depression", 5.0, 3)
		"bitter":
			c.loyalty = maxf(0.0, c.loyalty - 1.0)
			for r_id in c.get_rivals():
				c.modify_relationship(r_id, -2.0, 0.0)
			_bitter_seek_revenge(s, c)
		"mad":
			c.loyalty = maxf(0.0, c.loyalty - 0.5)

	# 6. Ожесточённые воины помнят кровные обиды и выбирают, кому мстить
	if c.revenge_target_id != "":
		var t = s.get_citizen_by_id(c.revenge_target_id)
		if t == null or not t.is_alive:
			c.revenge_target_id = ""
			c.revenge_reason = ""

# Покадровый учёт тягот (вызывается из NPCIntentions.tick для каждого жителя)
static func accumulate(c: CitizenNPC, delta: float) -> void:
	if c.hunger < 35.0:
		c.psyche_counters["hungry_sec"] = float(c.psyche_counters.get("hungry_sec", 0.0)) + delta
	if c.is_freezing:
		c.psyche_counters["cold_sec"] = float(c.psyche_counters.get("cold_sec", 0.0)) + delta

static func set_state(s: SettlementData, c: CitizenNPC, new_state: String, reason: String) -> void:
	if c.mental_state == new_state:
		return
	var old = c.mental_state
	c.mental_state = new_state
	c.psyche_counters["state_days"] = 0
	c.psyche_counters["overload_days"] = 0
	c.psyche_counters["calm_days"] = 0
	c.custom_data["mental_reason"] = reason
	var toast_kind = "warning"
	match new_state:
		"despair":
			c.show_emote("depression", 6.0, 5, true)
			c.shout("Зачем всё это... Никого не осталось.", 4.0)
			c.add_memory("fell_into_despair", "", c.citizen_id, 1.0, "Впал в уныние: %s" % reason, true)
		"bitter":
			c.show_emote("rage", 5.0, 5, true)
			c.shout("Хватит! Больше никому не дам себя в обиду!", 4.0)
			c.add_memory("became_bitter", "", c.citizen_id, 1.0, "Ожесточился: %s" % reason, true)
			if not c.bitterness_applied:
				c.bitterness_applied = true
				c.traits["temper"] = clampf(float(c.traits.get("temper", 20.0)) + 15.0, 0.0, 100.0)
				c.traits["aggression"] = clampf(float(c.traits.get("aggression", 20.0)) + 15.0, 0.0, 100.0)
				c.traits["empathy"] = clampf(float(c.traits.get("empathy", 50.0)) - 15.0, 0.0, 100.0)
				c.traits["honesty"] = clampf(float(c.traits.get("honesty", 50.0)) - 10.0, 0.0, 100.0)
		"mad":
			toast_kind = "danger"
			c.show_emote("dizziness", 6.0, 6, true)
			c.shout("Они шепчут... из огня... они все шепчут!", 4.5)
			c.loyalty = maxf(0.0, c.loyalty - 10.0)
			c.add_memory("went_mad", "", c.citizen_id, 1.0, "Помешался: %s" % reason, true)
			if GameManager:
				GameManager.add_history_entry(GameManager.current_year, "Помешательство", "%s лишился рассудка: %s" % [c.name, reason], "Люди")
		"stable":
			toast_kind = "good"
			c.show_emote("relief", 4.0, 4, true)
			c.shout("Кажется... отпустило.", 3.0)
			c.add_memory("recovered_mind", "", c.citizen_id, 1.0, "%s" % reason)
	if s.is_player_settlement():
		EventBus.notification_toast.emit("%s %s %s" % [STATE_ICONS.get(new_state, ""), c.name, STATE_NAMES.get(new_state, new_state)],
			"%s (было: %s). Стресс %d." % [reason, STATE_NAMES.get(old, old), int(c.stress)], toast_kind)

# Озлобленный воин сам выбирает, с кем свести счёты: самая сильная обида на живого соплеменника
static func _bitter_seek_revenge(s: SettlementData, c: CitizenNPC) -> void:
	if c.revenge_target_id != "" or not is_warlike(c):
		return
	var best: CitizenNPC = null
	var best_aff = -25.0
	for r_id in c.get_rivals():
		var r = s.get_citizen_by_id(r_id)
		if r == null or not r.is_alive or r.cohort == "child":
			continue
		var aff = c.get_relationship_affinity(r_id)
		if aff < best_aff:
			best_aff = aff
			best = r
	if best:
		consider_revenge(s, c, best, "Давняя обида на %s не даёт покоя" % best.name)

# Воинственный житель клянётся отомстить. Возвращает true, если клятва дана.
static func consider_revenge(s: SettlementData, c: CitizenNPC, target: CitizenNPC, reason: String) -> bool:
	if c == null or target == null or not c.is_alive or c == target or c.is_ruler or c.cohort == "child":
		return false
	if c.custom_data.get("player_controlled", false) or not is_warlike(c):
		return false
	# На вождя поднимают руку лишь те, кто в нём разуверился
	if target.is_ruler and c.loyalty >= 45.0:
		return false
	if c.revenge_target_id == target.citizen_id:
		return true
	c.revenge_target_id = target.citizen_id
	c.revenge_reason = reason
	c.add_memory("vengeance_vow", c.citizen_id, target.citizen_id, 1.0, "Поклялся отомстить %s: %s" % [target.name, reason], true)
	c.show_emote("rage", 5.0, 5, true)
	c.shout("%s ответит за это!" % target.name, 4.0)
	if s.is_player_settlement() and target.is_ruler:
		EventBus.notification_toast.emit("🗡 Клятва мести вождю", "%s поклялся отомстить вам: %s" % [c.name, reason], "danger")
	return true

static func clear_revenge(c: CitizenNPC, memory_type: String, desc: String) -> void:
	var t_id = c.revenge_target_id
	c.revenge_target_id = ""
	c.revenge_reason = ""
	c.clear_grudge(t_id)
	c.add_memory(memory_type, t_id, c.citizen_id, 1.0, desc)

# --- ДЛЯ ИНТЕРФЕЙСА ---

static func describe(c: CitizenNPC) -> String:
	var txt = "%s %s • стресс %d" % [STATE_ICONS.get(c.mental_state, ""), STATE_NAMES.get(c.mental_state, c.mental_state), int(c.stress)]
	if c.revenge_target_id != "":
		txt += " • жаждет мести"
	if float(c.custom_data.get("jailed_until", 0.0)) > _now():
		txt += " • под стражей"
	return txt
