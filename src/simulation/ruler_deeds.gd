class_name RulerDeeds
extends RefCounted

# ==============================================================================
# ПОСТУПКИ КОРОЛЯ И РЕАКЦИЯ МИРА (Режим Короля)
# Король — такой же житель, только под управлением игрока. Его дела видят
# соплеменники: запоминают, меняют отношение и лояльность, заступаются, мстят.
# ==============================================================================

const WITNESS_RADIUS: float = 220.0
const GUARD_RADIUS: float = 320.0
const FOREST_WITNESS_COOLDOWN: float = 120.0

static func _now() -> float:
	return float(GameManager.sim_time_total) if GameManager else 0.0

static func is_kin(c: CitizenNPC, other: CitizenNPC) -> bool:
	if c == null or other == null:
		return false
	if c.spouse_id == other.citizen_id or c.guardian_id == other.citizen_id or other.guardian_id == c.citizen_id:
		return true
	if c.family_id != "" and c.family_id == other.family_id:
		return true
	var rel = c.get_relationship(other.citizen_id)
	return rel.get("type", "") in ["spouse", "parent", "child", "sibling", "guardian", "ward"] or rel.get("is_parent", false)

static func witnesses(s: SettlementData, at: Vector2, exclude: Array = []) -> Array[CitizenNPC]:
	var result: Array[CitizenNPC] = []
	for c in s.population.citizens:
		if c.is_alive and not c.is_ruler and not exclude.has(c) and c.state != CitizenNPC.State.SLEEPING and c.pos.distance_to(at) <= WITNESS_RADIUS:
			result.append(c)
	return result

# --- ЛЕС ---

# Король сам рубит дерево. Вне отведённой зоны вырубки (или когда лагеря лесорубов нет)
# чтящие обычаи свидетели недовольны. Возвращает число недовольных.
static func on_tree_felled(s: SettlementData, ruler: CitizenNPC, coord: Vector2i) -> int:
	var outside_zone = s.has_active_logging_zone() and not s.is_tile_in_logging_zone(coord)
	var no_camp = not s.has_active_woodcutter_camp()
	if not outside_zone and not no_camp:
		return 0
	var upset = 0
	for w in witnesses(s, ruler.pos):
		if float(w.traits.get("tradition", 50.0)) < 60.0:
			continue
		if float(w.custom_data.get("saw_forest_felling_until", -1.0)) > _now():
			continue
		w.custom_data["saw_forest_felling_until"] = _now() + FOREST_WITNESS_COOLDOWN
		w.loyalty = maxf(0.0, w.loyalty - 1.5)
		w.add_memory("ruler_felled_forest", "ruler", ruler.citizen_id, 1.0, "Вождь сам валил живой лес %s" % ("вне отведённой рощи" if outside_zone else "без лагеря и обряда"))
		w.show_emote("disapproval", 3.0, 3)
		upset += 1
	return upset

# --- НАСИЛИЕ НАД СВОИМИ ---

# Первый удар по соплеменнику. Возвращает реакцию жертвы и заступников:
# {"victim_fights": bool, "defenders": Array[CitizenNPC]}
static func on_citizen_assaulted(s: SettlementData, ruler: CitizenNPC, victim: CitizenNPC) -> Dictionary:
	# Самооборона: житель сам кинулся на вождя (месть, помешательство) — ответ вождя законен
	if is_self_defense(ruler, victim):
		victim.shout("Не возьмёшь, вождь!", 3.0)
		for w in witnesses(s, victim.pos, [victim]):
			w.add_memory("witnessed_crime", victim.citizen_id, ruler.citizen_id, 0.6, "%s напал на вождя, и вождь защищался" % victim.name)
		EventBus.notification_toast.emit("🛡 Самооборона", "%s напал на вас — вы защищаетесь, соплеменники на вашей стороне." % victim.name, "warning")
		var nobody: Array[CitizenNPC] = []
		return {"victim_fights": true, "defenders": nobody}
	victim.add_memory("grudge", "offense", ruler.citizen_id, 3.0, "Вождь поднял на меня руку", true)
	victim.add_memory("assaulted", ruler.citizen_id, victim.citizen_id, 1.0, "Вождь избил меня")
	victim.modify_relationship(ruler.citizen_id, -40.0, -20.0)
	victim.loyalty = maxf(0.0, victim.loyalty - 25.0)
	victim.show_emote("fear", 4.0, 5, true)
	for w in witnesses(s, victim.pos, [victim]):
		w.add_memory("ruler_violence", "ruler", victim.citizen_id, 2.5, "Видел, как вождь напал на %s" % victim.name, true)
		w.loyalty = maxf(0.0, w.loyalty - 6.0)
		w.show_emote("fear", 3.5, 4, true)
		if is_kin(w, victim):
			w.add_memory("grudge", "offense", ruler.citizen_id, 3.0, "Вождь напал на моего родича %s" % victim.name, true)
			w.modify_relationship(ruler.citizen_id, -30.0, -15.0)
	var fights = float(victim.traits.get("bravery", 50.0)) >= 60.0 or float(victim.traits.get("temper", 20.0)) >= 60.0
	# Воинственный не забудет побоев
	NPCPsyche.consider_revenge(s, victim, ruler, "Вождь поднял на меня руку")
	victim.shout("Ты что творишь, вождь?!" if fights else "Помогите! Вождь обезумел!", 3.5)
	# Стражники, не доверяющие Королю, вступаются за соплеменника
	var defenders: Array[CitizenNPC] = []
	for g in s.population.citizens:
		if g.is_alive and not g.is_ruler and g != victim and g.job_id in ["guard", "warrior"] and g.pos.distance_to(victim.pos) <= GUARD_RADIUS:
			if g.loyalty < 50.0 or is_kin(g, victim):
				defenders.append(g)
				g.shout("Оставь %s, вождь! Я не позволю!" % victim.name, 3.5)
			else:
				g.shout("Не моё дело, вождь знает, что делает...", 3.0)
	EventBus.notification_toast.emit("⚔ Король напал на соплеменника!", "%s: %s. Свидетели в ужасе%s." % [victim.name, "даёт сдачи" if fights else "бежит", (", за него вступаются стражники: %d" % defenders.size()) if not defenders.is_empty() else ""], "danger")
	return {"victim_fights": fights, "defenders": defenders}

# Король убил соплеменника: удар по всему роду
static func is_self_defense(ruler: CitizenNPC, victim: CitizenNPC) -> bool:
	var duel: Dictionary = victim.custom_data.get("duel", {})
	return not duel.is_empty() and String(duel.get("role", "")) == "attacker" and String(duel.get("target_id", "")) == ruler.citizen_id

static func on_citizen_killed(s: SettlementData, ruler: CitizenNPC, victim: CitizenNPC) -> void:
	if is_self_defense(ruler, victim):
		victim.death_cause = "Погиб, напав на вождя %s" % ruler.name
		victim.custom_data.erase("duel")
		GameManager.add_history_entry(GameManager.current_year, "Вождь отбился", "%s напал на вождя %s и погиб" % [victim.name, ruler.name], "Власть и закон")
		for c in s.population.citizens:
			if c.is_alive and not c.is_ruler and c != victim and is_kin(c, victim):
				c.add_memory("sorrow", "ruler", victim.citizen_id, 1.0, "%s погиб, напав на вождя" % victim.name)
		EventBus.notification_toast.emit("🛡 Вождь отбился", "%s погиб, напав на вас. Род признаёт: вы защищались." % victim.name, "warning")
		return
	if victim.death_cause == "" or victim.death_cause.begins_with("Погиб от"):
		victim.death_cause = "Убит вождём %s" % ruler.name
	var council_ids: Array[String] = []
	if s.council:
		for m in s.council.get_members(s):
			council_ids.append(m.citizen_id)
	for c in s.population.citizens:
		if not c.is_alive or c.is_ruler or c == victim:
			continue
		var loss = 8.0
		if is_kin(c, victim):
			loss = 20.0
			c.add_memory("kin_murdered_by_ruler", "ruler", victim.citizen_id, 5.0, "Вождь убил моего родича %s" % victim.name, true)
			c.add_memory("grudge", "offense", ruler.citizen_id, 4.0, "Кровь %s на руках вождя" % victim.name, true)
			c.modify_relationship(ruler.citizen_id, -50.0, -30.0)
			NPCPsyche.consider_revenge(s, c, ruler, "Кровь %s на руках вождя" % victim.name)
		elif council_ids.has(c.citizen_id):
			loss = 15.0
			c.add_memory("ruler_murder", "ruler", victim.citizen_id, 3.0, "Вождь пролил кровь соплеменника %s" % victim.name, true)
		c.loyalty = maxf(0.0, c.loyalty - loss)
	s.economy.stability = maxf(0.0, s.economy.stability - 10.0)
	s.economy.loyalty = maxf(0.0, s.economy.loyalty - 8.0)
	GameManager.add_history_entry(GameManager.current_year, "Кровь на руках вождя", "Вождь %s убил соплеменника %s" % [ruler.name, victim.name], "Власть и закон")
	EventBus.notification_toast.emit("🩸 Король убил соплеменника", "%s мёртв(а). Род в ужасе, родня жаждет мести, совет возмущён." % victim.name, "danger")
