class_name CombatStatsResolver
extends RefCounted

const EquipmentDB = preload("res://src/combat/equipment_db.gd")

# ==============================================================================
# ЕДИНЫЙ КАЛЬКУЛЯТОР ХАРАКТЕРИСТИК, ОРУЖИЯ, БРОНИ, ОПЫТА И СТАРЕНИЯ (PLANETKI v2)
# ==============================================================================

# 1. Возрастная база людей (Раздел 6 ТЗ)
const AGE_BASES = {
	"child":  {"min_age": 0,  "max_age": 13, "base_hp": 35.0,  "base_attack": 0.0, "armor": 0.0, "stamina": 50.0,  "speed_mult": 0.80},
	"youth":  {"min_age": 14, "max_age": 17, "base_hp": 80.0,  "base_attack": 3.0, "armor": 0.0, "stamina": 85.0,  "speed_mult": 1.00},
	"adult":  {"min_age": 18, "max_age": 45, "base_hp": 100.0, "base_attack": 5.0, "armor": 0.0, "stamina": 100.0, "speed_mult": 1.00},
	"elder":  {"min_age": 46, "max_age": 59, "base_hp": 90.0,  "base_attack": 4.0, "armor": 0.0, "stamina": 85.0,  "speed_mult": 0.90},
	"old":    {"min_age": 60, "max_age": 120,"base_hp": 65.0,  "base_attack": 2.0, "armor": 0.0, "stamina": 60.0,  "speed_mult": 0.75}
}

# 2. Точки интерполяции старения (Раздел 27 ТЗ)
const AGING_POINTS = [
	{"age": 14, "P": 0.65, "R": 0.90},
	{"age": 18, "P": 0.85, "R": 1.00},
	{"age": 25, "P": 1.00, "R": 1.00},
	{"age": 40, "P": 1.00, "R": 1.00},
	{"age": 50, "P": 0.90, "R": 0.95},
	{"age": 60, "P": 0.75, "R": 0.85},
	{"age": 70, "P": 0.55, "R": 0.70},
	{"age": 80, "P": 0.35, "R": 0.55}
]

# 3. Бонусы оружейных навыков за 1 уровень (0..20) (Раздел 24 ТЗ)
const WEAPON_SKILL_BONUSES = {
	"sword": {"dmg_pct": 0.01,   "acc_pct": 0.0075, "speed_bonus": 0.005},
	"axe":   {"dmg_pct": 0.0125, "acc_pct": 0.005,  "speed_bonus": 0.004},
	"spear": {"dmg_pct": 0.01,   "acc_pct": 0.0075, "speed_bonus": 0.004},
	"bow":   {"dmg_pct": 0.01,   "acc_pct": 0.01,   "speed_bonus": 0.005}
}

# 4. Базовые характеристики животных (Разделы 3 и 4 ТЗ)
const ANIMAL_STATS = {
	# Взрослые особи
	"wolf_grey":     {"hp": 65.0,  "dmg": 12.0, "armor": 0.0,  "atk_interval": 1.3, "run_mult": 1.65, "threat": 1.25, "acc": 0.85},
	"wolf_dark":     {"hp": 65.0,  "dmg": 12.0, "armor": 0.0,  "atk_interval": 1.3, "run_mult": 1.65, "threat": 1.25, "acc": 0.85},
	"hare_brown":    {"hp": 12.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.85, "threat": 0.10, "acc": 0.0},
	"hare_white":    {"hp": 12.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.85, "threat": 0.10, "acc": 0.0},
	"deer_stag":     {"hp": 85.0,  "dmg": 16.0, "armor": 0.0,  "atk_interval": 1.8, "run_mult": 1.75, "threat": 1.00, "acc": 0.85},
	"deer_doe":      {"hp": 70.0,  "dmg": 10.0, "armor": 0.0,  "atk_interval": 1.8, "run_mult": 1.75, "threat": 1.00, "acc": 0.85},
	"moose_bull":    {"hp": 160.0, "dmg": 28.0, "armor": 5.0,  "atk_interval": 2.0, "run_mult": 1.55, "threat": 2.00, "acc": 0.85},
	"moose_cow":     {"hp": 140.0, "dmg": 24.0, "armor": 5.0,  "atk_interval": 2.0, "run_mult": 1.55, "threat": 2.00, "acc": 0.85},
	"bear_brown":    {"hp": 240.0, "dmg": 32.0, "armor": 10.0, "atk_interval": 2.2, "run_mult": 1.45, "threat": 3.00, "acc": 0.85},
	"bear_dark":     {"hp": 240.0, "dmg": 32.0, "armor": 10.0, "atk_interval": 2.2, "run_mult": 1.45, "threat": 3.00, "acc": 0.85},
	"boar_male":     {"hp": 110.0, "dmg": 20.0, "armor": 8.0,  "atk_interval": 1.6, "run_mult": 1.50, "threat": 1.50, "acc": 0.85},
	"boar_female":   {"hp": 100.0, "dmg": 18.0, "armor": 8.0,  "atk_interval": 1.6, "run_mult": 1.50, "threat": 1.50, "acc": 0.85},
	"fox_adult":     {"hp": 30.0,  "dmg": 5.0,  "armor": 0.0,  "atk_interval": 1.2, "run_mult": 1.65, "threat": 0.25, "acc": 0.85},
	"lynx_adult":    {"hp": 70.0,  "dmg": 15.0, "armor": 0.0,  "atk_interval": 1.4, "run_mult": 1.70, "threat": 1.25, "acc": 0.85},
	"badger_adult":  {"hp": 45.0,  "dmg": 9.0,  "armor": 5.0,  "atk_interval": 1.5, "run_mult": 0.95, "threat": 0.50, "acc": 0.85},
	"drake":         {"hp": 10.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 0.75, "threat": 0.10, "acc": 0.0},
	"duck":          {"hp": 10.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 0.75, "threat": 0.10, "acc": 0.0},
	
	# Детёныши
	"wolf_pup":      {"hp": 20.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.10, "threat": 0.0,  "acc": 0.0},
	"hare_leveret":  {"hp": 6.0,   "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.25, "threat": 0.0,  "acc": 0.0},
	"deer_fawn":     {"hp": 25.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.20, "threat": 0.0,  "acc": 0.0},
	"moose_calf":    {"hp": 40.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.10, "threat": 0.0,  "acc": 0.0},
	"bear_cub":      {"hp": 55.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.00, "threat": 0.0,  "acc": 0.0},
	"boar_piglet":   {"hp": 25.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.15, "threat": 0.0,  "acc": 0.0},
	"fox_kit":       {"hp": 12.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 0.0, "run_mult": 1.10, "threat": 0.0,  "acc": 0.0}
}

# ==============================================================================
# РАСЧЁТ КОЭФФИЦИЕНТОВ СТАРЕНИЯ (P - физика, R - реакция)
# ==============================================================================
static func get_aging_coefficients(age: int) -> Dictionary:
	if age < 14:
		return {"P": 0.0, "R": 0.0} # До 14 лет взрослое развитие заблокировано
	if age <= 14:
		return {"P": 0.65, "R": 0.90}
	if age >= 80:
		return {"P": 0.35, "R": 0.55}
		
	for i in range(AGING_POINTS.size() - 1):
		var p1 = AGING_POINTS[i]
		var p2 = AGING_POINTS[i + 1]
		if age >= p1["age"] and age <= p2["age"]:
			var t = float(age - p1["age"]) / float(p2["age"] - p1["age"])
			var p_val = lerpf(p1["P"], p2["P"], t)
			var r_val = lerpf(p1["R"], p2["R"], t)
			return {"P": p_val, "R": r_val}
			
	return {"P": 1.0, "R": 1.0}

# ==============================================================================
# ВОЗРАСТНАЯ БАЗОВАЯ СТАТИСТИКА ЧЕЛОВЕКА
# ==============================================================================
static func get_age_base_stats(age: int) -> Dictionary:
	if age <= 13:
		return AGE_BASES["child"]
	elif age <= 17:
		return AGE_BASES["youth"]
	elif age <= 45:
		return AGE_BASES["adult"]
	elif age <= 59:
		return AGE_BASES["elder"]
	else:
		return AGE_BASES["old"]

# ==============================================================================
# РАСЧЁТ ПОЛНОГО БОЕВОГО И ФИЗИЧЕСКОГО ПРОФИЛЯ ГРАЖДАНИНА (РАЗДЕЛ 28)
# ==============================================================================
static func calculate_citizen_stats(citizen) -> Dictionary:
	var age = citizen.age if "age" in citizen else 25
	var base = get_age_base_stats(age)
	var aging = get_aging_coefficients(age)
	var P: float = aging["P"]
	var R: float = aging["R"]
	
	var S: float = float(citizen.get("strength_level")) if citizen.get("strength_level") != null else 0.0
	var E: float = float(citizen.get("endurance_level")) if citizen.get("endurance_level") != null else 0.0
	var G: float = float(citizen.get("encounter_growth_points")) if citizen.get("encounter_growth_points") != null else 0.0
	G = clampf(G, 0.0, 20.0)
	
	# 1. Максимальное HP и выносливость
	# max_hp = age_base_hp + P * (S + 3*G) + explicit_hp_modifiers
	var explicit_hp = float(citizen.get("explicit_hp_modifiers")) if citizen.get("explicit_hp_modifiers") != null else 0.0
	var max_hp = base["base_hp"] + P * (S + 3.0 * G) + explicit_hp
	
	# stamina_max = age_base_stamina + P * (3*E) + explicit_stamina_modifiers
	var explicit_stamina = float(citizen.get("explicit_stamina_modifiers")) if citizen.get("explicit_stamina_modifiers") != null else 0.0
	var stamina_max = base["stamina"] + P * (3.0 * E) + explicit_stamina
	
	# 2. Оружие и экипировка
	var eq = citizen.get("equipment") if citizen.get("equipment") != null else {}
	var weapon_id = eq.get("weapon", "unarmed")
	var weapon_data = EquipmentDB.get_weapon(weapon_id)
	var is_ranged = weapon_data.get("is_ranged", false)
	
	# Модификации оружия
	var weapon_mods = eq.get("weapon_mods", [])
	var sharpening_flat = 2.0 if weapon_mods.has("sharpening") and not is_ranged else 0.0
	var item_mult = 1.15 if weapon_mods.has("tempering") and not is_ranged else 1.0
	var arrow_mod = 1.20 if is_ranged and eq.get("arrows", "") == "forged_arrows" else 1.0
	
	var base_w_dmg = float(weapon_data.get("damage", 0.0))
	var weapon_component = (base_w_dmg + sharpening_flat) * item_mult
	if is_ranged:
		weapon_component *= arrow_mod
		
	# 3. Физическая добавка и закалка
	var physical_damage = P * (0.4 * S) if not is_ranged else 0.0
	var encounter_damage = P * G
	
	# 4. Оружейный навык
	var skill_key = weapon_data.get("skill_type", "axe")
	var weapon_skill_level = 0
	if "weapon_skills" in citizen and citizen.weapon_skills is Dictionary:
		weapon_skill_level = int(citizen.weapon_skills.get(skill_key + "_level", 0))
	# Синергия лесоруба и боевого топора: max(axe_lvl, min(3, woodcutting/4))
	if skill_key == "axe":
		var prof_levels = citizen.get("profession_levels") if citizen.get("profession_levels") != null else {}
		var woodcut_lvl = int(prof_levels.get("woodcutter", 0))
		if "experience" in citizen and citizen.experience is Dictionary:
			var wc_exp = citizen.experience.get("woodcutter", 0)
			woodcut_lvl = maxi(woodcut_lvl, int(floor(sqrt(float(wc_exp) / 50.0))))
		var bonus_axe_lvl = mini(3, int(floor(float(woodcut_lvl) / 4.0)))
		weapon_skill_level = maxi(weapon_skill_level, bonus_axe_lvl)
	weapon_skill_level = clamp(weapon_skill_level, 0, 20)
	
	var skill_cfg = WEAPON_SKILL_BONUSES.get(skill_key, {"dmg_pct": 0.0, "acc_pct": 0.0, "speed_bonus": 0.0})
	var weapon_skill_dmg_bonus = float(weapon_skill_level) * skill_cfg["dmg_pct"]
	var allowed_other_dmg = float(citizen.get("allowed_other_damage_bonus")) if citizen.get("allowed_other_damage_bonus") != null else 0.0
	
	# 5. Урон до брони (raw_damage)
	var raw_damage = (base["base_attack"] + weapon_component + physical_damage + encounter_damage) * (1.0 + weapon_skill_dmg_bonus + allowed_other_dmg)
	
	# 6. Броня гражданина (одежда + броня тела + шлем + щит)
	var total_armor = 0.0
	var body_armor_id = eq.get("body_armor", "clothes")
	total_armor += EquipmentDB.get_armor_value(body_armor_id)
	
	var helmet_id = eq.get("helmet", "")
	if helmet_id != "":
		total_armor += EquipmentDB.get_helmet_value(helmet_id)
		
	# Щит даёт защиту, только если НЕ стреляет из двуручного лука
	var shield_id = eq.get("shield", "")
	if shield_id != "" and not is_ranged:
		total_armor += EquipmentDB.get_shield_value(shield_id)
		
	# Локальные бонусы (например, защита сторожевой вышки)
	if citizen.get("is_on_watchtower") == true and is_ranged:
		total_armor += 15.0 # +15 брони против стрел
		
	# 7. Интервал атаки
	# attack_interval = weapon_interval * (1 - speed_bonus) / R
	var base_interval = float(weapon_data.get("interval", 1.8))
	var weapon_skill_speed_bonus = float(weapon_skill_level) * skill_cfg["speed_bonus"]
	weapon_skill_speed_bonus = minf(weapon_skill_speed_bonus, 0.25) # максимум 0.25
	var eff_R = maxf(0.1, R)
	var attack_interval = (base_interval * (1.0 - weapon_skill_speed_bonus)) / eff_R
	attack_interval = maxf(0.6, attack_interval) # минимум 0.6 с
	
	# 8. Точность
	# базовая точность оружия + навык, clamp 5–95%
	var base_acc = 0.65 if is_ranged else 0.75
	var accuracy = base_acc + float(weapon_skill_level) * skill_cfg["acc_pct"]
	accuracy = clampf(accuracy, 0.05, 0.95)
	
	# 9. Пробитие брони
	var pen_flat = float(weapon_data.get("pen_flat", 0.0))
	var pen_frac = float(weapon_data.get("pen_fraction", 0.0))
	
	# 10. Дальность атаки
	var attack_range = float(weapon_data.get("range", 0.8))
	if citizen.get("is_on_watchtower") == true:
		attack_range += 3.0 # +3 клетки обнаружения и обстрела
		
	return {
		"max_hp": max_hp,
		"stamina_max": stamina_max,
		"raw_damage": raw_damage,
		"display_damage": int(round(raw_damage)),
		"armor": total_armor,
		"attack_interval": attack_interval,
		"accuracy": accuracy,
		"attack_range": attack_range,
		"is_ranged": is_ranged,
		"pen_flat": pen_flat,
		"pen_fraction": pen_frac,
		"P": P,
		"R": R,
		"S": S,
		"E": E,
		"G": G,
		"weapon_skill_level": weapon_skill_level,
		"weapon_id": weapon_id,
		"weapon_name": weapon_data.get("name", "Кулаки"),
		"breakdown": {
			"base_attack": base["base_attack"],
			"weapon_component": weapon_component,
			"physical_damage": physical_damage,
			"encounter_damage": encounter_damage,
			"skill_mult": 1.0 + weapon_skill_dmg_bonus + allowed_other_dmg
		}
	}

# ==============================================================================
# РАСЧЁТ СТАТИСТИКИ ЖИВОТНОГО
# ==============================================================================
static func calculate_animal_stats(type_id: String) -> Dictionary:
	var cfg = ANIMAL_STATS.get(type_id, {
		"hp": 20.0, "dmg": 0.0, "armor": 0.0, "atk_interval": 0.0, "run_mult": 1.0, "threat": 0.0, "acc": 0.0
	})
	return {
		"max_hp": float(cfg["hp"]),
		"raw_damage": float(cfg["dmg"]),
		"display_damage": int(round(float(cfg["dmg"]))),
		"armor": float(cfg["armor"]),
		"attack_interval": float(cfg["atk_interval"]),
		"accuracy": float(cfg.get("acc", 0.85)),
		"threat": float(cfg["threat"]),
		"run_mult": float(cfg["run_mult"]),
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"is_ranged": false
	}

# ==============================================================================
# ЕДИНАЯ ФОРМУЛА РЕШЕНИЯ УДАРА / АТАКИ (РАЗДЕЛЫ 10 И 28 ТЗ)
# ==============================================================================
static func resolve_attack(attacker_stats: Dictionary, defender_stats: Dictionary) -> Dictionary:
	var raw_dmg = float(attacker_stats.get("raw_damage", 0.0))
	if raw_dmg <= 0.0:
		return {"is_hit": false, "damage": 0, "effective_armor": 0.0}
		
	var acc = float(attacker_stats.get("accuracy", 0.75))
	var hit_roll = randf()
	if hit_roll > acc:
		return {"is_hit": false, "damage": 0, "effective_armor": 0.0} # Промах
		
	var target_armor = float(defender_stats.get("armor", 0.0))
	var pen_frac = float(attacker_stats.get("pen_fraction", 0.0))
	var pen_flat = float(attacker_stats.get("pen_flat", 0.0))
	
	# effective_armor = max(0, target_armor * (1 - pen_fraction) - pen_flat)
	var effective_armor = maxf(0.0, target_armor * (1.0 - pen_frac) - pen_flat)
	
	# final_damage = max(1, round(raw_damage * 100 / (100 + effective_armor)))
	var final_damage = maxi(1, int(round(raw_dmg * 100.0 / (100.0 + effective_armor))))
	
	return {
		"is_hit": true,
		"damage": final_damage,
		"raw_damage": raw_dmg,
		"effective_armor": effective_armor
	}
