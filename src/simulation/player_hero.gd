class_name PlayerHero
extends RefCounted

# ==============================================================================
# ГЕРОЙ-ВОЖДЬ: развитие персонажа игрока
# ------------------------------------------------------------------------------
# Персонаж игрока — это правитель поселения (житель с is_ruler). Здесь хранится
# его развитие как героя:
#   • уровень и опыт (за личные решения, советы, указы и победы над зверем);
#   • очки характеристик: POINTS_PER_LEVEL за уровень, вкладываются в Силу,
#     Выносливость и Ловкость — те же характеристики, что у жителей;
#   • очки навыков: SKILL_POINTS_PER_LEVEL за уровень на пассивные навыки;
#   • снаряжение: берётся со склада снаряжения племени и возвращается туда.
# Всё применяется к самому правителю, и CombatStatsResolver считает из этого
# реальные HP, выносливость, урон, точность и броню.
# ==============================================================================

const BASE_ATTR: int = 5
const POINTS_PER_LEVEL: int = 3
const SKILL_POINTS_PER_LEVEL: int = 1
const XP_LOG_LIMIT: int = 12

const ATTRIBUTES: Dictionary = {
	"strength": {"name": "💪 Сила", "desc": "Урон в ближнем бою (+0.4 за очко), здоровье (+1 за очко), переносимый груз."},
	"endurance": {"name": "🫀 Выносливость", "desc": "Запас выносливости (+3 за очко): дольше бьётся и работает, не выбиваясь из сил."},
	"agility": {"name": "🤸 Ловкость", "desc": "Точность (+0.5% за очко) и скорость ударов (-1% интервала за очко, до -20%)."}
}

# Пассивные навыки: ранги, требуемый уровень и реальный эффект за ранг
const SKILLS: Dictionary = {
	"mighty_arm": {"name": "⚔ Богатырская рука", "max_rank": 3, "req_level": 1, "desc": "+8% урона за ранг."},
	"hardened_body": {"name": "🛡 Закалённое тело", "max_rank": 3, "req_level": 1, "desc": "+12 к здоровью за ранг."},
	"second_wind": {"name": "🌬 Второе дыхание", "max_rank": 3, "req_level": 1, "desc": "+12 к выносливости за ранг."},
	"keen_eye": {"name": "🎯 Зоркий глаз", "max_rank": 2, "req_level": 2, "desc": "+4% точности за ранг."},
	"beast_bane": {"name": "🐺 Гроза зверя", "max_rank": 2, "req_level": 3, "desc": "+15% урона по диким зверям за ранг."},
	"chief_voice": {"name": "🗣 Голос вождя", "max_rank": 3, "req_level": 2, "desc": "Старейшины охотнее поддерживают вас на совете (+6 к доводу за ранг)."},
	"iron_authority": {"name": "👑 Непререкаемость", "max_rank": 2, "req_level": 3, "desc": "Указы злят людей на 30% меньше за ранг, и племя признаёт их даже при меньшей лояльности."},
	"heart_of_clan": {"name": "❤ Сердце рода", "max_rank": 3, "req_level": 2, "desc": "Ваши личные решения прибавляют +1 лояльности за ранг тем, кто с ними согласен."}
}

# Слоты снаряжения и их реестры
const SLOTS: Dictionary = {
	"weapon": {"name": "🗡 Оружие", "empty": "unarmed"},
	"shield": {"name": "🛡 Щит", "empty": ""},
	"body_armor": {"name": "🦺 Доспех", "empty": "clothes"},
	"helmet": {"name": "⛑ Шлем", "empty": ""}
}

# Личная сумка Короля: то, что он сам добыл (ресурс -> количество).
# Вместимость ограничена весом и растёт с силой.
const BAG_ITEMS: Dictionary = {
	"wood": {"name": "🪵 Древесина", "weight": 1.0},
	"stone": {"name": "🪨 Камень", "weight": 1.5},
	"metal": {"name": "⛏ Руда", "weight": 1.5},
	"berries": {"name": "🫐 Ягоды и грибы", "weight": 0.3, "food": true},
	"meat": {"name": "🥩 Мясо", "weight": 0.5, "food": true},
	"fish": {"name": "🐟 Рыба", "weight": 0.5, "food": true},
	"leather": {"name": "🟫 Шкуры", "weight": 0.5},
	"fur": {"name": "🐾 Мех", "weight": 0.5},
	"bone": {"name": "🦴 Кости", "weight": 0.3},
	"feathers": {"name": "🪶 Перья", "weight": 0.1},
	"flowers": {"name": "🌸 Цветы", "weight": 0.1}
}
const BAG_BASE_CAPACITY: float = 20.0
const MEAL_AMOUNT: float = 0.25 # как у жителей: 0.25 ед. пищи — сытная еда

var bag: Dictionary = {}

var level: int = 1
var xp: float = 0.0
var unspent_attr_points: int = 0
var unspent_skill_points: int = 0
var allocated: Dictionary = {"strength": 0, "endurance": 0, "agility": 0}
var skill_ranks: Dictionary = {}
var xp_log: Array[Dictionary] = []

# --- ПРАВИТЕЛЬ ---

static func get_ruler(s: SettlementData) -> CitizenNPC:
	if s == null or s.population == null:
		return null
	for c in s.population.citizens:
		if c.is_ruler and c.is_alive:
			return c
	return null

# --- ОПЫТ И УРОВНИ ---

static func xp_to_next(p_level: int) -> float:
	return 100.0 + float(p_level - 1) * 75.0

func add_xp(s: SettlementData, amount: float, reason: String) -> int:
	if amount <= 0.0:
		return 0
	xp += amount
	xp_log.push_front({"amount": amount, "reason": reason, "day": GameManager.total_simulation_days if GameManager else 0})
	if xp_log.size() > XP_LOG_LIMIT:
		xp_log.resize(XP_LOG_LIMIT)
	var gained_levels = 0
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		gained_levels += 1
		unspent_attr_points += POINTS_PER_LEVEL
		unspent_skill_points += SKILL_POINTS_PER_LEVEL
	if gained_levels > 0:
		var ruler = get_ruler(s)
		EventBus.notification_toast.emit("⭐ Вождь достиг %d уровня!" % level, "+%d очков характеристик и +%d очко навыка. Откройте «Персонаж» и «Навыки»." % [POINTS_PER_LEVEL * gained_levels, SKILL_POINTS_PER_LEVEL * gained_levels], "good")
		if ruler:
			ruler.show_emote("joy", 4.0, 4)
	return gained_levels

# --- ХАРАКТЕРИСТИКИ ---

# Итоговое значение: база героя + вложенные очки + развитое трудом (как у жителей)
func get_attribute(s: SettlementData, attr: String) -> int:
	var natural = 0
	var ruler = get_ruler(s)
	if ruler:
		match attr:
			"strength": natural = ruler.strength_level
			"endurance": natural = ruler.endurance_level
			"agility": natural = ruler.agility_level
	return BASE_ATTR + int(allocated.get(attr, 0)) + natural

func allocate_point(s: SettlementData, attr: String) -> bool:
	if unspent_attr_points <= 0 or not ATTRIBUTES.has(attr):
		return false
	unspent_attr_points -= 1
	allocated[attr] = int(allocated.get(attr, 0)) + 1
	apply_to_ruler(s)
	return true

# --- НАВЫКИ ---

func get_skill_rank(skill_id: String) -> int:
	return int(skill_ranks.get(skill_id, 0))

func can_learn(skill_id: String) -> Dictionary:
	if not SKILLS.has(skill_id):
		return {"ok": false, "reason": "Нет такого навыка"}
	var cfg = SKILLS[skill_id]
	if get_skill_rank(skill_id) >= int(cfg["max_rank"]):
		return {"ok": false, "reason": "Навык освоен полностью"}
	if level < int(cfg["req_level"]):
		return {"ok": false, "reason": "Нужен %d уровень" % int(cfg["req_level"])}
	if unspent_skill_points <= 0:
		return {"ok": false, "reason": "Нет очков навыков"}
	return {"ok": true, "reason": ""}

func learn_skill(s: SettlementData, skill_id: String) -> bool:
	if not can_learn(skill_id)["ok"]:
		return false
	unspent_skill_points -= 1
	skill_ranks[skill_id] = get_skill_rank(skill_id) + 1
	apply_to_ruler(s)
	return true

# Бонус к доводу вождя на совете (навык «Голос вождя»)
func get_council_persuasion() -> float:
	return 6.0 * float(get_skill_rank("chief_voice"))

# Во сколько раз ослабляется гнев людей от указа (навык «Непререкаемость»)
func get_decree_anger_mult() -> float:
	return maxf(0.2, 1.0 - 0.3 * float(get_skill_rank("iron_authority")))

# Насколько ниже порог лояльности, при котором племя признаёт указ
func get_decree_threshold_relief() -> float:
	return 8.0 * float(get_skill_rank("iron_authority"))

# --- ПРИМЕНЕНИЕ К ПРАВИТЕЛЮ ---

func apply_to_ruler(s: SettlementData) -> void:
	var ruler = get_ruler(s)
	if ruler == null:
		return
	ruler.bonus_strength = BASE_ATTR + int(allocated.get("strength", 0))
	ruler.bonus_endurance = BASE_ATTR + int(allocated.get("endurance", 0))
	ruler.bonus_agility = BASE_ATTR + int(allocated.get("agility", 0))
	ruler.allowed_other_damage_bonus = 0.08 * float(get_skill_rank("mighty_arm"))
	ruler.explicit_hp_modifiers = 12.0 * float(get_skill_rank("hardened_body"))
	ruler.explicit_stamina_modifiers = 12.0 * float(get_skill_rank("second_wind"))
	ruler.accuracy_bonus = 0.04 * float(get_skill_rank("keen_eye"))
	ruler.beast_damage_bonus = 0.15 * float(get_skill_rank("beast_bane"))
	var stats = ruler.get_combat_stats()
	var old_max_hp = ruler.max_health
	var old_max_st = ruler.stamina_max
	ruler.max_health = float(stats["max_hp"])
	ruler.stamina_max = float(stats["stamina_max"])
	# Прирост максимума сразу прибавляется к текущему значению (без полного исцеления)
	ruler.health = clampf(ruler.health + maxf(0.0, ruler.max_health - old_max_hp), 0.0, ruler.max_health)
	ruler.stamina_current = clampf(ruler.stamina_current + maxf(0.0, ruler.stamina_max - old_max_st), 0.0, ruler.stamina_max)

# --- СНАРЯЖЕНИЕ ---

static func get_item_slot(item_id: String) -> String:
	if EquipmentDB.WEAPONS.has(item_id):
		return "weapon"
	if EquipmentDB.BODY_ARMOR.has(item_id):
		return "body_armor"
	if EquipmentDB.HELMETS.has(item_id):
		return "helmet"
	if EquipmentDB.SHIELDS.has(item_id):
		return "shield"
	return ""

static func get_item_info(item_id: String) -> Dictionary:
	for reg in [EquipmentDB.WEAPONS, EquipmentDB.BODY_ARMOR, EquipmentDB.HELMETS, EquipmentDB.SHIELDS]:
		if reg.has(item_id):
			return reg[item_id]
	return {}

static func describe_item(item_id: String) -> String:
	var info = get_item_info(item_id)
	if info.is_empty():
		return "—"
	var parts: Array[String] = [String(info.get("name", item_id))]
	if info.has("damage"):
		parts.append("урон %d" % int(info["damage"]))
		parts.append("интервал %.1fс" % float(info.get("interval", 1.8)))
	if info.has("armor"):
		parts.append("броня %d" % int(info["armor"]))
	if info.has("speed_mod") and float(info["speed_mod"]) != 0.0:
		parts.append("скорость %d%%" % int(float(info["speed_mod"]) * 100.0))
	return ", ".join(parts)

# Предметы на складе снаряжения, которые можно надеть: [{id, slot, count}]
func get_stockpile_items(s: SettlementData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if s == null:
		return result
	for item_id in s.equipment_stockpile:
		var cnt = int(s.equipment_stockpile[item_id])
		var slot = get_item_slot(item_id)
		if cnt > 0 and slot != "":
			result.append({"id": item_id, "slot": slot, "count": cnt})
	return result

# Надеть предмет со склада; прежний предмет слота возвращается на склад
func equip_from_stockpile(s: SettlementData, item_id: String) -> Dictionary:
	var ruler = get_ruler(s)
	if ruler == null:
		return {"ok": false, "reason": "Вождя нет в живых"}
	var slot = get_item_slot(item_id)
	if slot == "":
		return {"ok": false, "reason": "Этот предмет нельзя надеть"}
	if int(s.equipment_stockpile.get(item_id, 0)) <= 0:
		return {"ok": false, "reason": "На складе этого нет"}
	if slot == "shield" and EquipmentDB.get_weapon(ruler.equipment.get("weapon", "unarmed")).get("is_ranged", false):
		return {"ok": false, "reason": "С луком щит не удержать"}
	unequip(s, slot)
	s.equipment_stockpile[item_id] = int(s.equipment_stockpile[item_id]) - 1
	if int(s.equipment_stockpile[item_id]) <= 0:
		s.equipment_stockpile.erase(item_id)
	ruler.equipment[slot] = item_id
	apply_to_ruler(s)
	return {"ok": true, "reason": ""}

# Снять предмет: он возвращается на склад снаряжения племени
func unequip(s: SettlementData, slot: String) -> bool:
	var ruler = get_ruler(s)
	if ruler == null or not SLOTS.has(slot):
		return false
	var current: String = String(ruler.equipment.get(slot, SLOTS[slot]["empty"]))
	if current == "" or current == SLOTS[slot]["empty"]:
		return false
	s.equipment_stockpile[current] = int(s.equipment_stockpile.get(current, 0)) + 1
	ruler.equipment[slot] = SLOTS[slot]["empty"]
	apply_to_ruler(s)
	return true

# --- СУМКА ---

func get_bag_capacity(s: SettlementData) -> float:
	return BAG_BASE_CAPACITY + float(get_attribute(s, "strength")) * 1.5

func get_bag_weight() -> float:
	var w = 0.0
	for item in bag:
		w += float(bag[item]) * float(BAG_ITEMS.get(item, {"weight": 1.0})["weight"])
	return w

# Положить в сумку сколько влезет. Возвращает сколько положено.
func bag_add(s: SettlementData, item: String, amount: float) -> float:
	if amount <= 0.0 or not BAG_ITEMS.has(item):
		return 0.0
	var unit_w = float(BAG_ITEMS[item]["weight"])
	var free = maxf(0.0, get_bag_capacity(s) - get_bag_weight())
	var fits = minf(amount, free / unit_w) if unit_w > 0.0 else amount
	if fits <= 0.0:
		return 0.0
	bag[item] = float(bag.get(item, 0.0)) + fits
	return fits

func bag_take(item: String, amount: float) -> float:
	var have = float(bag.get(item, 0.0))
	var taken = minf(have, amount)
	if taken <= 0.0:
		return 0.0
	if have - taken <= 0.0001:
		bag.erase(item)
	else:
		bag[item] = have - taken
	return taken

func is_bag_full(s: SettlementData, item: String) -> bool:
	return get_bag_weight() + float(BAG_ITEMS.get(item, {"weight": 1.0})["weight"]) * 0.25 > get_bag_capacity(s)

# Съесть еду из сумки: как у жителей, 0.25 ед. — сытная еда
func eat_from_bag(s: SettlementData, item: String) -> Dictionary:
	var ruler = get_ruler(s)
	if ruler == null:
		return {"ok": false, "reason": "Короля нет в живых"}
	if not BAG_ITEMS.get(item, {}).get("food", false):
		return {"ok": false, "reason": "Это нельзя съесть"}
	if float(bag.get(item, 0.0)) < MEAL_AMOUNT:
		return {"ok": false, "reason": "В сумке слишком мало"}
	if ruler.hunger >= 90.0:
		return {"ok": false, "reason": "Король сыт"}
	bag_take(item, MEAL_AMOUNT)
	ruler.hunger = 100.0
	ruler.show_emote("eat", 3.0, 3)
	return {"ok": true, "reason": "Король поел: %s" % BAG_ITEMS[item]["name"]}

# Сдать сумку на склад поселения: ресурсы реально зачисляются в экономику
func deposit_bag(s: SettlementData) -> Dictionary:
	var ruler = get_ruler(s)
	if ruler == null or bag.is_empty():
		return {"ok": false, "reason": "Сумка пуста"}
	var parts: Array[String] = []
	for item in bag.keys():
		var amt = float(bag[item])
		if item == "flowers":
			continue # цветы Король оставляет себе — для подарков
		var res_key = item
		var batch = {}
		if item in ["berries", "meat", "fish"]:
			res_key = "food"
			batch = {"food_type": item, "created_sim_time": GameManager.sim_time_total, "max_freshness_sec": 4500.0 if item != "berries" else 3600.0, "spoilage_progress": 0.0}
		s.deposit_resource(res_key, amt, ruler.name, batch)
		parts.append("%s %.1f" % [BAG_ITEMS[item]["name"], amt])
		bag.erase(item)
	if parts.is_empty():
		return {"ok": false, "reason": "Сдавать нечего (цветы остаются у Короля)"}
	return {"ok": true, "reason": "Сдано на склад: " + ", ".join(parts)}

# --- СОХРАНЕНИЕ ---

func serialize() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"unspent_attr_points": unspent_attr_points,
		"unspent_skill_points": unspent_skill_points,
		"allocated": allocated.duplicate(),
		"skill_ranks": skill_ranks.duplicate(),
		"xp_log": xp_log.duplicate(true),
		"bag": bag.duplicate()
	}

func deserialize(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = float(data.get("xp", 0.0))
	unspent_attr_points = int(data.get("unspent_attr_points", 0))
	unspent_skill_points = int(data.get("unspent_skill_points", 0))
	var alloc: Dictionary = data.get("allocated", {})
	for attr in ATTRIBUTES:
		allocated[attr] = int(alloc.get(attr, 0))
	skill_ranks = {}
	var ranks: Dictionary = data.get("skill_ranks", {})
	for sk in ranks:
		if SKILLS.has(sk):
			skill_ranks[sk] = mini(int(ranks[sk]), int(SKILLS[sk]["max_rank"]))
	bag = {}
	var saved_bag: Dictionary = data.get("bag", {})
	for item in saved_bag:
		if BAG_ITEMS.has(item):
			bag[item] = float(saved_bag[item])
	xp_log.clear()
	for e in data.get("xp_log", []):
		if e is Dictionary:
			xp_log.append(e)
