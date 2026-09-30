class_name CitizenNPC
extends RefCounted


enum State {
	IDLE,
	SEARCHING_TASK,
	MOVING_TO_WORK,
	WORKING,
	GATHERING,
	CARRYING,
	DELIVERING,
	GOING_HOME,
	EATING,
	RESTING,
	SLEEPING,
	TALKING,
	FLEEING,
	ATTACKING,
	BUTCHERING,
	WAITING,
	CELEBRATING,
	MOURNING,
	CONFRONTING,
	COMPLAINING,
	HELPING,
	PRAYING,
	FLEEING_HOME
}

# --- ИДЕНТИЧНОСТЬ И ДАННЫЕ ГРАЖДАНИНА ---
var citizen_id: String = ""
var id: String:
	get: return citizen_id
	set(val): citizen_id = val
var name: String = ""
var gender: String = "m" # "m" или "f"
var age: int = 25
var age_progress: float = 0.0 # Дробный прогресс взросления к следующему году (1800 сек = 1 год)
var is_ruler: bool = false    # Правитель не стареет и возраст скрыт (PlanetKI v2 ТЗ)
var cohort: String = "adult" # "child", "youth", "adult", "elder"
var race_id: String = "north" # "desert", "savanna", "north"
var appearance_role: String = "villager_brown_m"
var seed_val: int = 0

# --- ПРОФЕССИЯ И ПРИВЯЗКИ ---
var job_id: String = "idle"
var workplace_id: String = ""
var workplace_coord: Vector2i = Vector2i(-1, -1)
var home_id: String = ""
var home_building_id: String:
	get: return home_id
	set(val): home_id = val
var home_coord: Vector2i = Vector2i(-1, -1)
var household_id: String = ""
var is_guest: bool = false
var family_id: String = ""
var spouse_id: String = ""
var settlement_id: String = ""
var custom_data: Dictionary = {}

# --- СЕМЕЙНЫЕ СВЯЗИ, ОТНОШЕНИЯ И ОПЕКА (S07) ---
var relationships: Dictionary = {} # other_id -> {"type": "spouse"|"parent"|"child"|"sibling"|"guardian"|"ward", "closeness": float, "romance": float, "married": bool}
var guardian_id: String = "" # ID опекуна для детей/сирот
var is_ward_of_lodge: bool = false # Опека Большого дома рода над сиротой
var pregnancy: Dictionary = {} # {"partner_id": String, "progress_sec": float, "gestation_sec": float, "stage": String, "health_risk": float}

# --- ПОЗИЦИОНИРОВАНИЕ И НАВИГАЦИЯ ---
var pos: Vector2 = Vector2.ZERO
var home_pos: Vector2 = Vector2.ZERO
var facing_dir: Vector2 = Vector2.DOWN
var path: Array[Vector2] = []
var path_index: int = 0
var base_speed: float = 24.0
var stuck_timer: float = 0.0
var last_stuck_pos: Vector2 = Vector2.ZERO

# --- СОСТОЯНИЕ И ЗАДАНИЕ ---
var state: int = State.IDLE
var task_id: String = ""
var task_instance_id: String = ""
var target_type: String = "none" # "none", "resource", "building", "home", "animal", "citizen"
var target_id: String = ""
var target_coord: Vector2i = Vector2i(-1, -1)
var target_pos: Vector2 = Vector2.ZERO
var reservation_ids: Array[String] = []


# --- ИНВЕНТАРЬ И ГРУЗ ---
var cargo_type: String = "" # "food", "wood", "stone", "metal", "game", "carcass", etc.
var cargo_amount: float = 0.0
var cargo_batch: Dictionary = {}
var max_carry: float = 6.0

# --- ПОТРЕБНОСТИ И ЗДОРОВЬЕ ---
var health: float = 100.0 # 0 .. 100
var max_health: float = 100.0
var is_alive: bool = true
var is_buried: bool = false
var carrying_deceased_id: String = ""
var subphase: String = ""
var hunger: float = 100.0 # 100 = сыт, 0 = умирает от голода
var energy: float = 100.0 # 100 = бодр, 0 = валится с ног
var loyalty: float = 85.0
# Тёплая одежда (прочность 0..100): изнашивается, зимой без неё на улице житель мёрзнет
var warm_clothes: float = 60.0
var is_freezing: bool = false
var morale: float:
	get: return loyalty
	set(val): loyalty = clampf(val, 0.0, 100.0)
var experience: Dictionary = {}
var skills: Dictionary = {}

# --- 4 ВЕКТОРА РАЗВИТИЯ И ЭКИПИРОВКА (PLANETKI v2 / ТЗ РАЗДЕЛЫ 21-32 / P01.2) ---
# 1. Физическая форма (S: 0..20, E: 0..20, A: 0..20)
var strength_xp: float = 0.0
var strength_level: int = 0
var endurance_xp: float = 0.0
var endurance_level: int = 0
var agility_xp: float = 0.0
var agility_level: int = 0
var stamina_current: float = 100.0
var stamina_max: float = 100.0

# Бонусы, которые накладывают герой-вождь (очки характеристик) и его навыки.
# CombatStatsResolver читает их при расчёте HP, выносливости, урона и точности.
var bonus_strength: int = 0
var bonus_endurance: int = 0
var bonus_agility: int = 0
var explicit_hp_modifiers: float = 0.0
var explicit_stamina_modifiers: float = 0.0
var allowed_other_damage_bonus: float = 0.0
var accuracy_bonus: float = 0.0
var beast_damage_bonus: float = 0.0

const EXHAUSTED_STAMINA: float = 15.0

func is_exhausted() -> bool:
	return stamina_current < EXHAUSTED_STAMINA

# 2. Оружейная техника (0..20 уровни)
var weapon_skills: Dictionary = {
	"sword_xp": 0.0, "sword_level": 0,
	"axe_xp": 0.0, "axe_level": 0,
	"spear_xp": 0.0, "spear_level": 0,
	"bow_xp": 0.0, "bow_level": 0
}

var profession_levels: Dictionary = {}

# Навыки читаются из накопленного опыта (experience растёт от реальной работы в add_work_xp)
var skill_builder: float:
	get: return get_profession_xp("builder")
	set(val): experience["builder"] = val
var skill_woodcutter: float:
	get: return get_profession_xp("woodcutter")
	set(val): experience["woodcutter"] = val
var skill_stonecutter: float:
	get: return get_profession_xp("quarryman")
	set(val): experience["quarryman"] = val
var skill_miner: float:
	get: return get_profession_xp("miner")
	set(val): experience["miner"] = val
var skill_gatherer: float:
	get: return get_profession_xp("forager")
	set(val): experience["forager"] = val
var skill_hunter: float:
	get: return get_profession_xp("hunter")
	set(val): experience["hunter"] = val

# Старые ключи опыта из ранних сохранений -> ключ профессии (job_id)
const LEGACY_PROFESSION_KEYS: Dictionary = {"quarryman": "stonecutter", "forager": "gatherer"}

func get_profession_xp(prof_key: String) -> float:
	var xp = float(experience.get(prof_key, 0.0))
	xp = maxf(xp, float(skills.get(prof_key, 0.0)))
	var legacy = LEGACY_PROFESSION_KEYS.get(prof_key, "")
	if legacy != "":
		xp = maxf(xp, maxf(float(experience.get(legacy, 0.0)), float(skills.get(legacy, 0.0))))
	return xp

# Уровень мастерства в профессии (порог L: 50 * L^2, как в add_work_xp)
func get_profession_level(prof_key: String) -> int:
	return mini(20, int(floor(sqrt(get_profession_xp(prof_key) / 50.0))))

# 3. Опыт опасных столкновений (EGP: 0..20) и антифарм история (20 последних)
var encounter_growth_points: float = 0.0
var recent_encounters: Array[Dictionary] = []

# 4. Экипировка (физические предметы)
var equipment: Dictionary = {
	"weapon": "unarmed",
	"shield": "",
	"body_armor": "clothes",
	"helmet": "",
	"weapon_mods": [],
	"arrows": "basic_arrows"
}
var equipped_tool: Dictionary = {} # {"id": String, "type": "axe", "durability": float, ...}

func has_tool(tool_type: String = "axe") -> bool:
	return not equipped_tool.is_empty() and equipped_tool.get("type", "") == tool_type and float(equipped_tool.get("durability", 0.0)) > 0.0

func wear_tool(amount: float = 2.0) -> bool:
	if equipped_tool.is_empty():
		return false
	equipped_tool["durability"] = maxf(0.0, float(equipped_tool.get("durability", 100.0)) - amount)
	return float(equipped_tool["durability"]) <= 0.0

# Суточные лимиты роста (максимум 8 часов физики, 8 часов профессии, 40 XP охоты)
var daily_physical_hours: float = 0.0
var daily_profession_hours: float = 0.0
var daily_hunt_xp: float = 0.0

# --- ЛИЧНОСТЬ, ХАРАКТЕР И ПАМЯТЬ (P01.2 / ТЗ РАЗДЕЛ 4) ---
# 9 скрытых шкал личности + непредсказуемость + совместимость с S08
var personality: Dictionary:
	get: return traits
	set(val): traits = val
var traits: Dictionary = {
	"diligence": 50.0,       # Трудолюбие (0..100)
	"bravery": 50.0,         # Храбрость (0..100)
	"empathy": 50.0,         # Сочувствие (0..100)
	"sociability": 50.0,     # Общительность (0..100)
	"temper": 20.0,          # Вспыльчивость (0..100)
	"honesty": 50.0,         # Честность (0..100)
	"ambition": 50.0,        # Честолюбие (0..100)
	"tradition": 50.0,       # Приверженность традициям (0..100)
	"curiosity": 50.0,       # Любопытство (0..100)
	"unpredictable": false,  # Редкая черта: нестабильные поступки при сильном стрессе
	# Совместимость с S08:
	"pride": 50.0,
	"loyalty_ruler": 50.0,
	"tolerance": 50.0,
	"aggression": 20.0
}
var commitment_timer: float = 0.0 # Таймер устойчивости выбора (защита от метания)
var ongoing_task_kind: String = "" # Текущий закрепленный тип задачи
var interrupted_task: Dictionary = {} # Снимок задачи, прерванной социальным действием/голодом (не пусто = есть что восстановить)
var pending_social_action: String = "" # Тип соц. действия, ожидающего исполнения по прибытии ("complain", "help_neighbor", ...)
var social_cooldown: float = 0.0 # Кулдаун на повторные социальные диалоги
var death_cause: String = "" # Причина гибели: "В бою с волком", "От голода", "От старости"

# Память о значимых событиях (P01.2 / ТЗ 4.3): спасение, жильё, выселение, предательство
var memories: Array[Dictionary] = []

# Индивидуальные причуды и мнения (Система живых NPC / ТЗ Разделы 2-5)
var quirks: Array[String] = []
var opinions: Dictionary = {} # decision_id -> {"stance": "support"|"oppose"|"neutral", "importance": float, "reason": String, "formed_at_tick": int}
var active_social_action: String = ""
var social_target_id: String = ""
var social_timer: float = 0.0

func take_damage(amount: float, source_name: String = "") -> bool:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		is_alive = false
		if death_cause == "":
			if source_name != "":
				if "волк" in source_name.to_lower():
					death_cause = "В схватке с волком"
				elif "медвед" in source_name.to_lower():
					death_cause = "В схватке с медведем"
				elif "кабан" in source_name.to_lower():
					death_cause = "В схватке с кабаном"
				elif "голод" in source_name.to_lower():
					death_cause = "От истощения и голода"
				elif "старост" in source_name.to_lower():
					death_cause = "От преклонного возраста"
				else:
					death_cause = "Погиб от: %s" % source_name
			else:
				death_cause = "От ран и опасностей диких земель"
		if is_ruler:
			var killer = death_cause
			EventBus.ruler_died.emit(name, killer)
			if GameManager and GameManager.has_method("trigger_game_over"):
				GameManager.trigger_game_over("Вождь племени %s погиб от: %s. Племя осталось без предводителя." % [name, killer])
		elif GameManager and GameManager.settlements:
			var s = GameManager.settlements.get(settlement_id, null)
			if s == null and not GameManager.settlements.is_empty():
				s = GameManager.settlements.values()[0]
			if s and s.has_method("_process_citizen_death"):
				s._process_citizen_death(self)
		return true # Погиб
	else:
		if health < 30.0:
			show_emote("injury", 4.0, 5, true)
		else:
			show_emote("pain", 3.0, 4, true)
	return false

func get_combat_stats() -> Dictionary:
	return CombatStatsResolver.calculate_citizen_stats(self)

# Добавление физического и профессионального опыта от полезного труда (Раздел 23 ТЗ)
func add_work_xp(activity: String, hours: float) -> void:
	if hours <= 0.0:
		return
	var usable_hours = minf(hours, maxf(0.0, 8.0 - daily_physical_hours))
	if usable_hours <= 0.0:
		return
	daily_physical_hours += usable_hours
	
	var s_rate = 0.0
	var e_rate = 0.0
	var a_rate = 0.0
	var prof_key = ""
	var prof_rate = 0.0
	
	match activity:
		"woodcutting":
			s_rate = 2.0; e_rate = 1.5; a_rate = 0.5; prof_key = "woodcutter"; prof_rate = 3.0
		"stone_mining":
			s_rate = 2.2; e_rate = 1.5; a_rate = 0.2; prof_key = "quarryman"; prof_rate = 3.0
		"ore_mining":
			s_rate = 2.0; e_rate = 1.5; a_rate = 0.2; prof_key = "miner"; prof_rate = 3.0
		"building":
			s_rate = 1.5; e_rate = 1.5; a_rate = 0.8; prof_key = "builder"; prof_rate = 3.0
		"carrying":
			s_rate = 1.0; e_rate = 2.0; a_rate = 0.4
		"gathering", "farming":
			s_rate = 0.4; e_rate = 1.2; a_rate = 1.2; prof_key = "forager"; prof_rate = 3.0
		"hunting_tracking":
			s_rate = 0.2; e_rate = 1.8; a_rate = 2.0; prof_key = "hunter"; prof_rate = 2.0
		"combat_training":
			s_rate = 1.0; e_rate = 1.5; a_rate = 1.5
		"crafting":
			s_rate = 0.3; e_rate = 0.5; a_rate = 1.2; prof_key = job_id if job_id != "idle" else ""; prof_rate = 3.0
			
	# Начисление силы, выносливости и ловкости (порог L: 200 * L^2)
	strength_xp += s_rate * usable_hours
	strength_level = mini(20, int(floor(sqrt(strength_xp / 200.0))))
	
	endurance_xp += e_rate * usable_hours
	endurance_level = mini(20, int(floor(sqrt(endurance_xp / 200.0))))
	
	agility_xp += a_rate * usable_hours
	agility_level = mini(20, int(floor(sqrt(agility_xp / 200.0))))
	
	# Профессиональный опыт (порог L: 50 * L^2)
	if prof_key != "" and prof_rate > 0.0:
		var cur_exp = float(experience.get(prof_key, 0.0))
		experience[prof_key] = cur_exp + prof_rate * usable_hours
		
	# Обновление максимальных параметров без бесплатного исцеления
	var stats = get_combat_stats()
	max_health = stats["max_hp"]
	stamina_max = stats["stamina_max"]
	health = minf(health, max_health)
	stamina_current = minf(stamina_current, stamina_max)

# Добавление оружейного опыта (Раздел 24 ТЗ: порог L: 50 * L^2)
func add_weapon_xp(weapon_type: String, amount: float) -> void:
	if amount <= 0.0 or not weapon_skills.has(weapon_type + "_xp"):
		return
	var cur_xp = float(weapon_skills.get(weapon_type + "_xp", 0.0)) + amount
	weapon_skills[weapon_type + "_xp"] = cur_xp
	var new_lvl = mini(20, int(floor(sqrt(cur_xp / 50.0))))
	weapon_skills[weapon_type + "_level"] = new_lvl

# Начисление опыта опасных столкновений (EGP) с защитой от бесконечного фарма (Раздел 25 ТЗ)
func award_encounter(threat: float, target_species: String, contribution_ratio: float) -> void:
	if threat <= 0.0 or contribution_ratio <= 0.0:
		return
	contribution_ratio = clampf(contribution_ratio, 0.0, 1.0)
	var base_egp = threat * contribution_ratio
	
	# Подсчёт встреч этого же вида в окне из последних 20
	var count_same_species = 0
	for enc in recent_encounters:
		if enc.get("species", "") == target_species:
			count_same_species += 1
			
	var anti_farm_mult = 1.0
	if count_same_species >= 5:
		anti_farm_mult = 0.1
	elif count_same_species >= 2:
		anti_farm_mult = 0.5
		
	var granted_egp = base_egp * anti_farm_mult
	encounter_growth_points = clampf(encounter_growth_points + granted_egp, 0.0, 20.0)
	
	# Запись в историю встреч
	recent_encounters.push_front({"species": target_species, "threat": threat, "share": contribution_ratio})
	if recent_encounters.size() > 20:
		recent_encounters.resize(20)
		
	# Обновление максимума здоровья без мгновенного лечения
	var stats = get_combat_stats()
	max_health = stats["max_hp"]
	stamina_max = stats["stamina_max"]
	health = minf(health, max_health)

# --- ТАЙМЕРЫ И РАСПИСАНИЕ ---
var schedule_offset_hours: float = 0.0
var work_timer: float = 0.0
var action_timer: float = 0.0
var decision_cooldown: float = 0.0
var wander_cooldown: float = 0.0

# --- ОБЩЕНИЕ И СОЦИАЛИЗАЦИЯ ---
var talk_partner_id: String = ""
var speech_bubble: String = ""
var speech_timer: float = 0.0

# --- ВИЗУАЛЬНЫЕ ОБЛАЧКИ-ЭМОЦИИ И СОСТОЯНИЯ (EMOTES) ---
var active_emote_id: String = ""
var emote_timer: float = 0.0
var emote_max_duration: float = 3.5
var emote_cooldown: float = 0.0
var emote_priority: int = 0

# --- ПОНЯТНОЕ ОПИСАНИЕ ДЛЯ ИГРОКА ---
var last_status_reason: String = "Отдыхает"

# --- ТЕКСТУРА ПЕРСОНАЖА (КЭШ) ---
var cached_texture: Texture2D = null

func _init(p_id: String = "", p_name: String = "", p_gender: String = "m", p_age: int = 25, p_cohort: String = "adult", p_race: String = "north") -> void:
	citizen_id = p_id
	name = p_name
	gender = p_gender
	age = p_age
	cohort = p_cohort
	race_id = p_race
	seed_val = abs((p_id + p_name).hash())
	schedule_offset_hours = randf_range(-0.4, 0.4)
	_pick_initial_appearance()
	if p_id != "":
		init_personality(seed_val)

func _pick_initial_appearance() -> void:
	if appearance_role != "" and appearance_role != "villager_brown_m":
		# Валидация: проверяем что сохранённая роль соответствует текущему гендеру и когорте
		if _is_appearance_valid_for_gender():
			return
		# Роль не соответствует — сбрасываем и переназначаем
		appearance_role = ""

	var pool = []
	if cohort == "child":
		pool = ["child_boy_1", "child_boy_2"] if gender == "m" else ["child_girl_1", "child_girl_2"]
	elif cohort == "youth":
		pool = ["teen_boy_1", "teen_boy_2"] if gender == "m" else ["teen_girl_1", "teen_girl_2"]
	elif cohort == "elder":
		pool = ["grandpa_staff", "elder_citizen_m", "senior_m"] if gender == "m" else ["grandma", "elder_citizen_f", "senior_f"]
	else:
		if gender == "m":
			pool = ["villager_brown_m", "villager_blue_m", "adult_1", "adult_3"]
		else:
			pool = ["villager_green_f", "villager_red_f", "adult_2", "adult_4"]
	if not pool.is_empty():
		appearance_role = pool[seed_val % pool.size()]

# Роли закреплённые за мужским гендером (32 роли)
const MALE_ROLES: Array = [
	"leader_m", "sage_m", "priest_m", "elder_m",
	"forager_m", "hunter_m", "farmer_m", "fisherman_m",
	"woodcutter_m", "mason_m", "miner_m", "builder_m",
	"blacksmith_m", "potter_m", "villager_brown_m", "villager_blue_m",
	"warrior_m", "guard_m", "archer_m", "spearman_m",
	"commander_m", "veteran_m", "adult_1", "adult_3",
	"child_boy_1", "child_boy_2", "teen_boy_1", "teen_boy_2",
	"grandpa_staff", "elder_citizen_m", "senior_m", "father_baby"
]
# Роли закреплённые за женским гендером (32 роли)
const FEMALE_ROLES: Array = [
	"leader_f", "sage_f", "priest_f", "elder_f",
	"forager_f", "hunter_f", "farmer_f", "fisherman_f",
	"woodcutter_f", "mason_f", "miner_f", "builder_f",
	"potter_f", "weaver_f", "villager_green_f", "villager_red_f",
	"warrior_f", "guard_f", "archer_f", "spearman_f",
	"commander_f", "veteran_f", "adult_2", "adult_4",
	"child_girl_1", "child_girl_2", "teen_girl_1", "teen_girl_2",
	"grandma", "elder_citizen_f", "senior_f", "mother_baby"
]

func _is_appearance_valid_for_gender() -> bool:
	if appearance_role == "":
		return false
	if gender == "m":
		# Если роль явно женская — невалидна
		if FEMALE_ROLES.has(appearance_role):
			return false
	else:
		# Если роль явно мужская — невалидна
		if MALE_ROLES.has(appearance_role):
			return false
	return true

func get_texture() -> Texture2D:
	if cached_texture != null:
		return cached_texture
	CharacterTextureManager.load_all()
	if job_id != "idle" and cohort in ["youth", "adult", "elder"]:
		cached_texture = CharacterTextureManager.get_character_for_job(job_id, seed_val, race_id, gender)
	else:
		cached_texture = CharacterTextureManager.get_role_texture(race_id, appearance_role)
	if cached_texture == null:
		cached_texture = CharacterTextureManager.get_random_race_character(race_id, seed_val)
	return cached_texture

var preferred_job: String = ""

func get_preferred_job() -> String:
	if preferred_job != "" and preferred_job != "idle":
		return preferred_job
	var best_j = "forager"
	var max_exp = -1.0
	for j in experience:
		var ev = float(experience[j])
		if ev > max_exp:
			max_exp = ev
			best_j = j
	if max_exp <= 0.0:
		if traits.get("diligence", 50.0) > 55.0:
			best_j = "builder" if randf() < 0.5 else "woodcutter"
		elif traits.get("temper", 50.0) > 55.0 or traits.get("bravery", 50.0) > 55.0:
			best_j = "hunter"
		elif traits.get("empathy", 50.0) > 55.0:
			best_j = "forager"
	preferred_job = best_j
	return preferred_job

func set_job_by_player(new_job: String) -> void:
	var pref = get_preferred_job()
	var job_titles = {
		"hunter": "охотник",
		"woodcutter": "лесоруб",
		"forager": "собиратель",
		"quarryman": "каменотёс",
		"miner": "рудокоп",
		"builder": "строитель",
		"farmer": "земледелец",
		"craftsman": "ремесленник",
		"tanner": "скорняк",
		"sage": "мудрец",
		"priest": "жрец",
		"guard": "стражник",
		"elder": "старейшина",
		"idle": "свободный житель"
	}
	var new_name = job_titles.get(new_job, new_job)
	var pref_name = job_titles.get(pref, pref)
	
	if new_job == pref:
		loyalty = minf(100.0, loyalty + 5.0)
		add_memory("job_happiness", "profession", "", 1.5, "Вождь доверил мне любимое дело: %s!" % new_name, true)
		show_emote("joy", 3.0, 3)
	elif new_job != "idle":
		loyalty = maxf(10.0, loyalty - 8.0)
		add_memory("job_discontent", "profession", "", -1.2, "Вождь заставил меня работать %s, хотя я хотел быть %s..." % [new_name, pref_name], true)
		show_emote("protest", 3.5, 4)
	else:
		show_emote("sympathy", 2.0, 2)
		
	set_job(new_job)

func set_job(new_job: String) -> void:
	if job_id == new_job:
		return
	job_id = new_job
	cached_texture = null
	decision_cooldown = 0.0
	if state in [State.MOVING_TO_WORK, State.WORKING, State.GATHERING, State.ATTACKING, State.BUTCHERING]:
		_clear_reservations()
		state = State.IDLE
		last_status_reason = "Сменил занятие"

func is_idle() -> bool:
	return job_id == "idle" and workplace_id == "" and cohort in ["adult", "youth"]

func set_home(p_home_id: String, p_coord: Vector2i, p_pos: Vector2, p_is_guest: bool = false, p_household_id: String = "") -> void:
	home_id = p_home_id
	home_coord = p_coord
	home_pos = p_pos
	is_guest = p_is_guest
	household_id = p_household_id if p_household_id != "" else p_home_id

func clear_home() -> void:
	home_id = ""
	home_coord = Vector2i(-1, -1)
	home_pos = Vector2.ZERO
	is_guest = false
	household_id = ""

func set_workplace(p_work_id: String, p_coord: Vector2i) -> void:
	workplace_id = p_work_id
	workplace_coord = p_coord

func get_speed() -> float:
	var spd = base_speed * (0.9 + float(agility_level) * 0.04)
	if cohort == "elder":
		spd *= 0.8
	elif cohort == "child":
		spd *= 0.9
	if hunger < 25.0:
		spd *= 0.8
	if energy < 20.0:
		spd *= 0.75
	if health < 40.0:
		spd *= 0.65
	# Бонус скорости на протоптанных тропинках (+15%)
	if GameManager and GameManager.trample_map:
		var tile_c = Vector2i(int(floor(pos.x / 32.0)), int(floor(pos.y / 32.0)))
		if GameManager.trample_map.get(tile_c, 0.0) >= 0.2:
			spd *= 1.15
	return maxf(6.0, spd)

# --- ЭФФЕКТИВНЫЕ ПАРАМЕТРЫ И ВИТАЛЬНЫЙ МНОЖИТЕЛЬ (P01.2 / ТЗ 4.1) ---
func get_vitality_multiplier() -> float:
	var mult = 1.0
	if hunger < 20.0:
		mult *= 0.4
	elif hunger < 50.0:
		mult *= 0.75
	if energy < 15.0:
		mult *= 0.5
	elif energy < 40.0:
		mult *= 0.8
	if health < 30.0:
		mult *= 0.5
	elif health < 70.0:
		mult *= 0.85
	return mult

func get_effective_strength() -> float:
	return maxf(0.2, (float(strength_level + bonus_strength) + 1.0) * get_vitality_multiplier())

func get_effective_endurance() -> float:
	return maxf(0.2, (float(endurance_level + bonus_endurance) + 1.0) * get_vitality_multiplier())

func get_effective_agility() -> float:
	return maxf(0.2, (float(agility_level + bonus_agility) + 1.0) * get_vitality_multiplier())

func get_effective_max_carry() -> float:
	var base = max_carry + (float(strength_level + bonus_strength) * 0.5)
	return maxf(2.0, base * get_vitality_multiplier())

func get_physical_status_descriptors() -> Array[String]:
	var desc: Array[String] = []
	if strength_level >= 4:
		desc.append("силач")
	elif strength_level == 0 and get_vitality_multiplier() < 0.7:
		desc.append("хилый")
	if endurance_level >= 4:
		desc.append("выносливый")
	if agility_level >= 4:
		desc.append("ловкий")
	if hunger < 20.0:
		desc.append("истощён")
	elif hunger < 50.0:
		desc.append("голоден")
	if energy < 20.0:
		desc.append("валится с ног")
	elif energy < 45.0:
		desc.append("не выспался")
	if health < 35.0:
		desc.append("тяжело ранен")
	elif health < 75.0:
		desc.append("ранен")
	if get_vitality_multiplier() < 0.7 and not desc.has("истощён") and not desc.has("голоден"):
		desc.append("ослаблен")
	return desc

# --- ХАРАКТЕР И ЛИЧНОСТЬ (P01.2 / ТЗ 4.2) ---
func init_personality(seed_num: int = 0) -> void:
	var s = seed_num if seed_num != 0 else seed_val
	var rng = RandomNumberGenerator.new()
	rng.seed = s
	traits["diligence"] = rng.randf_range(20.0, 80.0)
	traits["bravery"] = rng.randf_range(20.0, 80.0)
	traits["empathy"] = rng.randf_range(20.0, 80.0)
	traits["sociability"] = rng.randf_range(20.0, 80.0)
	traits["temper"] = rng.randf_range(10.0, 70.0)
	traits["honesty"] = rng.randf_range(30.0, 85.0)
	traits["ambition"] = rng.randf_range(15.0, 75.0)
	traits["tradition"] = rng.randf_range(30.0, 80.0)
	traits["curiosity"] = rng.randf_range(25.0, 85.0)
	traits["unpredictable"] = rng.randf() < 0.05
	traits["aggression"] = traits["temper"]
	traits["pride"] = traits["ambition"]
	traits["loyalty_ruler"] = rng.randf_range(40.0, 90.0)
	traits["tolerance"] = rng.randf_range(30.0, 80.0)
	init_quirks(s)

func inherit_traits_from_parents(mother: CitizenNPC, father: CitizenNPC) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	var m_traits = mother.traits if mother != null else {}
	var f_traits = father.traits if father != null else {}
	
	for key in ["diligence", "bravery", "empathy", "sociability", "temper", "honesty", "ambition", "tradition", "curiosity", "loyalty_ruler", "tolerance"]:
		var m_val = float(m_traits.get(key, 50.0))
		var f_val = float(f_traits.get(key, 50.0))
		var avg = (m_val + f_val) * 0.5 if (mother and father) else (m_val if mother else f_val)
		var spread = rng.randf_range(-15.0, 15.0)
		traits[key] = clampf(avg + spread, 0.0, 100.0)
	traits["unpredictable"] = (mother and mother.traits.get("unpredictable", false)) or (father and father.traits.get("unpredictable", false)) or (rng.randf() < 0.03)
	traits["aggression"] = traits["temper"]
	traits["pride"] = traits["ambition"]
	init_quirks(seed_val)

# --- ПАМЯТЬ И ЗНАНИЕ О МИРЕ (P01.2 / ТЗ 4.3) ---
func add_memory(p_type: String, p_actor_id: String, p_target_id: String, p_importance: float, p_desc: String, p_permanent: bool = false) -> void:
	var mem_id = "mem_%d_%d" % [int(Time.get_ticks_msec()), randi() % 1000]
	var current_year = GameManager.current_year if GameManager else 1
	var current_time = GameManager.sim_time_total if GameManager else 0.0
	memories.append({
		"id": mem_id,
		"type": p_type,
		"actor_id": p_actor_id,
		"target_id": p_target_id,
		"importance": clampf(p_importance, 0.0, 1.0),
		"strength": 100.0,
		"is_permanent": p_permanent,
		"created_year": current_year,
		"created_time": current_time,
		"description": p_desc
	})
	if memories.size() > 30:
		_prune_memories()

func has_memory_of(p_actor_id: String, p_type: String = "") -> bool:
	for m in memories:
		if m.get("actor_id", "") == p_actor_id:
			if p_type == "" or m.get("type", "") == p_type:
				return true
	return false

func has_memory(p_type: String) -> bool:
	for m in memories:
		if m.get("type", "") == p_type:
			return true
	return false

func has_grudge_against(p_actor_id: String) -> bool:
	for m in memories:
		if (m.get("actor_id", "") == p_actor_id or m.get("target_id", "") == p_actor_id) and (m.get("type", "") in ["grudge", "offense", "brawl", "feud", "rival", "betrayal"]):
			return true
	return false

func clear_grudge(p_actor_id: String) -> void:
	var i = memories.size() - 1
	while i >= 0:
		var m = memories[i]
		if (m.get("actor_id", "") == p_actor_id or m.get("target_id", "") == p_actor_id) and (m.get("type", "") in ["grudge", "offense", "brawl", "feud", "rival", "betrayal"]):
			memories.remove_at(i)
		i -= 1

func get_memories_about(p_actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for m in memories:
		if m.get("actor_id", "") == p_actor_id or m.get("target_id", "") == p_actor_id:
			result.append(m)
	return result

func update_memories(delta_days: float) -> void:
	if delta_days <= 0.0 or memories.is_empty():
		return
	var i = memories.size() - 1
	while i >= 0:
		var m = memories[i]
		if not m.get("is_permanent", false):
			var fade_rate = 5.0 * (1.0 - float(m.get("importance", 0.5)) * 0.5)
			m["strength"] = float(m.get("strength", 100.0)) - (fade_rate * delta_days)
			if m["strength"] <= 0.0:
				memories.remove_at(i)
		i -= 1

func _prune_memories() -> void:
	memories.sort_custom(func(a, b):
		var a_p = 1.0 if a.get("is_permanent", false) else 0.0
		var b_p = 1.0 if b.get("is_permanent", false) else 0.0
		if a_p != b_p:
			return a_p > b_p
		return float(a.get("importance", 0.5)) * float(a.get("strength", 100.0)) > float(b.get("importance", 0.5)) * float(b.get("strength", 100.0))
	)
	if memories.size() > 30:
		memories.resize(30)

func can_observe_event(event_world_pos: Vector2, sound_level: String = "normal") -> bool:
	var dist = pos.distance_to(event_world_pos)
	match sound_level:
		"quiet", "subtle":
			return dist <= 64.0  # 2 тайла
		"loud", "shout", "fight":
			return dist <= 320.0 # 10 тайлов
		_:
			return dist <= 160.0 # 5 тайлов (нормальный разговор/действие)

func shout(text: String, duration: float = 2.5) -> void:
	speech_bubble = text
	speech_timer = duration

func clear_speech() -> void:
	speech_bubble = ""
	speech_timer = 0.0

func show_emote(p_emote_id: String, duration: float = 3.5, priority: int = 1, force: bool = false) -> void:
	if p_emote_id == "":
		clear_emote()
		return
	if not force and emote_timer > 0.0 and priority < emote_priority:
		return
	active_emote_id = p_emote_id
	emote_max_duration = maxf(1.0, duration)
	emote_timer = emote_max_duration
	emote_priority = priority
	emote_cooldown = emote_max_duration + randf_range(8.0, 16.0)

func clear_emote() -> void:
	active_emote_id = ""
	emote_timer = 0.0
	emote_priority = 0

func update_emote(delta: float) -> void:
	if emote_timer > 0.0:
		emote_timer = maxf(0.0, emote_timer - delta)
		if emote_timer <= 0.0:
			active_emote_id = ""
			emote_priority = 0
	if emote_cooldown > 0.0:
		emote_cooldown = maxf(0.0, emote_cooldown - delta)

func check_autonomous_emotes(delta: float, season: String = "Лето") -> void:
	if emote_timer > 0.0 or emote_cooldown > 0.0:
		return
		
	# 1. Критическая опасность и паника
	if state == State.FLEEING:
		show_emote("panic", 3.5, 5)
		return
		
	# 2. Здоровье и ранения
	if health < 30.0:
		show_emote("injury", 3.5, 4)
		return
	elif health < 60.0:
		show_emote("pain", 3.0, 4)
		return
		
	# 3. Физиологические потребности
	if hunger < 20.0:
		show_emote("hunger", 3.5, 4)
		return
	elif energy < 15.0:
		show_emote("fatigue", 3.0, 3)
		return
	elif energy < 30.0 and state == State.SLEEPING:
		show_emote("sleepy", 3.0, 3)
		return
	elif season == "Зима" and is_freezing:
		if randf() < 0.05:
			show_emote("cold", 3.5, 3)
			return
			
	# 4. Социальное общение
	if state == State.TALKING and talk_partner_id != "":
		var rel = get_relationship(talk_partner_id)
		if rel.get("married", false) or float(rel.get("romance", 0.0)) >= 20.0:
			show_emote("romance" if randf() < 0.5 else "love", 3.5, 3)
			return
		elif float(rel.get("closeness", 50.0)) >= 75.0:
			show_emote("sympathy" if randf() < 0.5 else "joy", 3.0, 2)
			return
		elif cohort in ["child", "youth"]:
			show_emote("question" if randf() < 0.5 else "dialog", 3.0, 2)
			return
		else:
			show_emote("dialog" if randf() < 0.6 else "thought", 3.0, 2)
			return
			
	# 5. Особые роли и профессии
	if job_id == "guard" and state == State.WORKING:
		if randf() < 0.02:
			show_emote("observation", 3.0, 2)
			return
	elif job_id == "priest" and state == State.WORKING:
		if randf() < 0.02:
			show_emote("prayer", 3.5, 2)
			return
	elif job_id in ["sage", "elder"] and state == State.WORKING:
		if randf() < 0.02:
			show_emote("thought" if randf() < 0.5 else "justice", 3.0, 2)
			return
	elif state == State.WORKING:
		if randf() < 0.005:
			show_emote("work" if randf() < 0.7 else "idea", 2.5, 1)
			return
			
	# 6. Отдых и настроение
	if state == State.RESTING:
		if randf() < 0.03:
			show_emote("calm" if randf() < 0.6 else "joy", 3.0, 1)
			return
			
	# 7. Недовольство и лояльность
	if loyalty < 30.0:
		if randf() < 0.02:
			show_emote("discontent" if randf() < 0.7 else "rebellion", 3.5, 3)
			return

func _clear_reservations() -> void:
	if target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
		GameManager.resource_manager.release_node(target_coord, citizen_id)
	if target_id != "" and GameManager.wildlife_manager:
		GameManager.wildlife_manager.release_animal(target_id, citizen_id)
		GameManager.wildlife_manager.release_carcass(target_id, citizen_id)
	reservation_ids.clear()
	target_id = ""
	target_coord = Vector2i(-1, -1)

# --- ПЕРЕМЕЩЕНИЕ ПО ПУТИ ---
func update_movement(delta: float) -> bool:
	if path.is_empty() or path_index >= path.size():
		return true
		
	var next_point = path[path_index]
	var dist = pos.distance_to(next_point)
	var spd = get_speed()
	
	if dist <= spd * delta:
		pos = next_point
		path_index += 1
		if path_index >= path.size():
			path.clear()
			path_index = 0
			return true
	else:
		var dir = (next_point - pos).normalized()
		pos += dir * spd * delta
		facing_dir = dir
		
	# Протаптывание тропинки под ногами идущего жителя
	if GameManager and is_alive:
		var cur_tile = Vector2i(int(floor(pos.x / 32.0)), int(floor(pos.y / 32.0)))
		GameManager.add_tile_trample(cur_tile, delta * 0.15)
		
	# Обнаружение застревания
	if pos.distance_to(last_stuck_pos) < 1.0:
		stuck_timer += delta
		if stuck_timer > 3.5:
			path.clear()
			path_index = 0
			stuck_timer = 0.0
			return true
	else:
		stuck_timer = 0.0
		last_stuck_pos = pos
		
	return false

# --- СЕРИАЛИЗАЦИЯ ДЛЯ СОХРАНЕНИЯ ---
func serialize() -> Dictionary:
	return {
		"citizen_id": citizen_id,
		"name": name,
		"gender": gender,
		"age": age,
		"age_progress": age_progress,
		"is_ruler": is_ruler,
		"cohort": cohort,
		"race_id": race_id,
		"appearance_role": appearance_role,
		"job_id": job_id,
		"preferred_job": preferred_job,
		"workplace_id": workplace_id,
		"workplace_coord": [workplace_coord.x, workplace_coord.y],
		"home_id": home_id,
		"home_coord": [home_coord.x, home_coord.y],
		"household_id": household_id,
		"is_guest": is_guest,
		"family_id": family_id,
		"spouse_id": spouse_id,
		"settlement_id": settlement_id,
		"pos": [pos.x, pos.y],
		"home_pos": [home_pos.x, home_pos.y],
		"state": state,
		"task_id": task_id,
		"task_instance_id": task_instance_id,
		"cargo_type": cargo_type,
		"cargo_amount": cargo_amount,
		"cargo_batch": cargo_batch.duplicate(),
		"hunt_byproducts": custom_data.get("hunt_byproducts", {}).duplicate(),
		"health": health,
		"hunger": hunger,
		"energy": energy,
		"warm_clothes": warm_clothes,
		"loyalty": loyalty,
		"experience": experience.duplicate(),
		"skills": skills.duplicate(),
		"last_status_reason": last_status_reason,
		"death_cause": death_cause,
		"is_buried": is_buried,
		"carrying_deceased_id": carrying_deceased_id,
		"subphase": subphase,
		"strength_xp": strength_xp,
		"strength_level": strength_level,
		"endurance_xp": endurance_xp,
		"endurance_level": endurance_level,
		"agility_xp": agility_xp,
		"agility_level": agility_level,
		"stamina_current": stamina_current,
		"stamina_max": stamina_max,
		"weapon_skills": weapon_skills,
		"encounter_growth_points": encounter_growth_points,
		"recent_encounters": recent_encounters,
		"equipment": equipment,
		"relationships": relationships.duplicate(true),
		"guardian_id": guardian_id,
		"is_ward_of_lodge": is_ward_of_lodge,
		"pregnancy": pregnancy.duplicate(),
		"traits": traits.duplicate(),
		"memories": memories.duplicate(true),
		"commitment_timer": commitment_timer,
		"social_cooldown": social_cooldown,
		"profession_levels": profession_levels.duplicate(),
		"equipped_tool": equipped_tool.duplicate(true),
		"active_emote_id": active_emote_id,
		"emote_timer": emote_timer,
		"emote_max_duration": emote_max_duration
	}

func deserialize(data: Dictionary) -> void:
	citizen_id = data.get("citizen_id", "")
	name = data.get("name", "")
	death_cause = data.get("death_cause", "")
	is_buried = bool(data.get("is_buried", false))
	carrying_deceased_id = data.get("carrying_deceased_id", "")
	subphase = data.get("subphase", "")
	gender = data.get("gender", "m")
	age = data.get("age", 25)
	age_progress = data.get("age_progress", 0.0)
	is_ruler = data.get("is_ruler", false)
	cohort = data.get("cohort", "adult")
	race_id = data.get("race_id", "north")
	appearance_role = data.get("appearance_role", "villager_brown_m")
	job_id = data.get("job_id", "idle")
	preferred_job = data.get("preferred_job", "")
	workplace_id = data.get("workplace_id", "")
	var wc = data.get("workplace_coord", [-1, -1])
	workplace_coord = Vector2i(wc[0], wc[1])
	home_id = data.get("home_id", "")
	var hc = data.get("home_coord", [-1, -1])
	home_coord = Vector2i(hc[0], hc[1])
	household_id = data.get("household_id", home_id)
	is_guest = bool(data.get("is_guest", false))
	family_id = data.get("family_id", "")
	spouse_id = data.get("spouse_id", "")
	settlement_id = data.get("settlement_id", "")
	relationships = data.get("relationships", {}).duplicate(true)
	guardian_id = data.get("guardian_id", "")
	is_ward_of_lodge = bool(data.get("is_ward_of_lodge", false))
	pregnancy = data.get("pregnancy", {}).duplicate()
	var loaded_traits = data.get("traits", {})
	if loaded_traits is Dictionary:
		for k in loaded_traits:
			traits[k] = loaded_traits[k]
	memories.clear()
	for m in data.get("memories", []):
		if m is Dictionary:
			memories.append(m.duplicate(true))
	commitment_timer = float(data.get("commitment_timer", 0.0))
	social_cooldown = float(data.get("social_cooldown", 0.0))
	profession_levels = data.get("profession_levels", {}).duplicate()
	active_emote_id = data.get("active_emote_id", "")
	emote_timer = float(data.get("emote_timer", 0.0))
	emote_max_duration = float(data.get("emote_max_duration", 3.5))
	var p = data.get("pos", [0, 0])
	pos = Vector2(p[0], p[1])
	var hp = data.get("home_pos", [0, 0])
	home_pos = Vector2(hp[0], hp[1])
	state = data.get("state", State.IDLE)
	task_id = data.get("task_id", "")
	task_instance_id = data.get("task_instance_id", "")
	cargo_type = data.get("cargo_type", "")
	cargo_amount = data.get("cargo_amount", 0.0)
	cargo_batch = data.get("cargo_batch", {}).duplicate()
	var saved_byproducts: Dictionary = data.get("hunt_byproducts", {})
	if not saved_byproducts.is_empty():
		custom_data["hunt_byproducts"] = saved_byproducts.duplicate()
	health = data.get("health", 100.0)
	hunger = data.get("hunger", 100.0)
	energy = data.get("energy", 100.0)
	warm_clothes = float(data.get("warm_clothes", 60.0))
	loyalty = data.get("loyalty", 85.0)
	experience = data.get("experience", {}).duplicate()
	skills = data.get("skills", experience).duplicate()
	last_status_reason = data.get("last_status_reason", "Отдыхает")
	strength_xp = data.get("strength_xp", 0.0)
	strength_level = data.get("strength_level", 0)
	endurance_xp = data.get("endurance_xp", 0.0)
	endurance_level = data.get("endurance_level", 0)
	agility_xp = float(data.get("agility_xp", 0.0))
	agility_level = int(data.get("agility_level", 0))
	stamina_current = data.get("stamina_current", 100.0)
	stamina_max = data.get("stamina_max", 100.0)
	weapon_skills = data.get("weapon_skills", {
		"sword_xp": 0.0, "sword_level": 0,
		"axe_xp": 0.0, "axe_level": 0,
		"spear_xp": 0.0, "spear_level": 0,
		"bow_xp": 0.0, "bow_level": 0
	})
	encounter_growth_points = data.get("encounter_growth_points", 0.0)
	recent_encounters.clear()
	for item in data.get("recent_encounters", []):
		if item is Dictionary:
			recent_encounters.append(item)
	equipment = data.get("equipment", {
		"weapon": "unarmed",
		"shield": "",
		"body_armor": "clothes",
		"helmet": "",
		"weapon_mods": [],
		"arrows": "basic_arrows"
	})
	equipped_tool = data.get("equipped_tool", {}).duplicate(true)
	cached_texture = null
	# Валидация appearance_role после загрузки — исправляет несоответствие гендера
	_pick_initial_appearance()

func sim_aging(sim_delta: float) -> void:
	if is_ruler:
		return
	var year_duration = 1800.0
	if "NPC_YEAR_DURATION" in GameManager:
		year_duration = GameManager.NPC_YEAR_DURATION
		
	# Ускорение взросления:
	# 0-17 лет (дети и подростки) растут в 4x быстрее (450с на биографический год)
	# 18+ лет (взрослые) стареют с нормальной базовой скоростью 1x (1800с на год)
	var age_speed_mult = 1.0
	if age < 18:
		age_speed_mult = 4.0
		
	age_progress += (sim_delta * age_speed_mult) / year_duration
	while age_progress >= 1.0:
		age_progress -= 1.0
		age += 1
		_sync_cohort_on_age_change()

func _sync_cohort_on_age_change() -> void:
	var old_cohort = cohort
	if age <= 13:
		cohort = "child"
	elif age <= 17:
		cohort = "youth"
	elif age <= 45:
		cohort = "adult"
	else:
		cohort = "elder"
		
	if cohort != old_cohort:
		appearance_role = ""
		_pick_initial_appearance()
		cached_texture = null
		if old_cohort in ["child", "youth"] and cohort == "adult" and not is_ruler:
			choose_profession_on_adulthood()

func choose_profession_on_adulthood() -> String:
	# Если у взрослого жителя уже есть назначенная профессия (не idle/child/youth), сохраняем её
	if job_id != "" and job_id != "idle" and job_id != "child" and job_id != "youth":
		return job_id
		
	var scores: Dictionary = {
		"hunter": 10.0,
		"woodcutter": 10.0,
		"forager": 10.0,
		"builder": 8.0,
		"guard": 8.0,
		"quarryman": 6.0
	}
	
	# Влияние характеристик и черт характера (traits)
	var temper = float(traits.get("temper", 50.0))
	var pride = float(traits.get("pride", 50.0))
	var empathy = float(traits.get("empathy", 50.0))
	var diligence = float(traits.get("diligence", 50.0))
	
	if temper > 55.0 or pride > 55.0:
		scores["guard"] += 14.0
		scores["hunter"] += 10.0
	if empathy > 55.0:
		scores["forager"] += 15.0
	if diligence > 55.0:
		scores["builder"] += 12.0
		scores["woodcutter"] += 12.0
		scores["quarryman"] += 10.0
		
	# Влияние накопленного в юности опыта (experience)
	for p_job in scores.keys():
		var exp_val = float(experience.get(p_job, 0.0))
		scores[p_job] += exp_val * 1.5
		
	# Влияние профессии родителей (преемственность ремесла)
	for rel_id in relationships:
		var r_data = relationships[rel_id]
		if r_data.get("is_parent", false) or r_data.get("type", "") == "parent":
			if GameManager and GameManager.settlements and GameManager.settlements.has(settlement_id):
				var p_sett = GameManager.settlements[settlement_id]
				if p_sett and p_sett.population:
					var parent_c = p_sett.population.get_citizen_by_id(rel_id)
					if parent_c and parent_c.job_id in scores:
						scores[parent_c.job_id] += 12.0
						
	# Влияние потребностей поселения (нехватка ресурсов)
	if GameManager and GameManager.settlements and GameManager.settlements.has(settlement_id):
		var p_sett = GameManager.settlements[settlement_id]
		if p_sett and p_sett.economy:
			var food_amt = float(p_sett.economy.resources.get("food", 0.0))
			var wood_amt = float(p_sett.economy.resources.get("wood", 0.0))
			var stone_amt = float(p_sett.economy.resources.get("stone", 0.0))
			if food_amt < 25.0:
				scores["hunter"] += 14.0
				scores["forager"] += 14.0
			if wood_amt < 20.0:
				scores["woodcutter"] += 14.0
			if stone_amt < 10.0:
				scores["quarryman"] += 10.0
				
	# Выбор наилучшей профессии
	var best_job = "forager"
	var best_score = -999.0
	for j_id in scores:
		var randomized_score = scores[j_id] + randf_range(-1.5, 1.5)
		if randomized_score > best_score:
			best_score = randomized_score
			best_job = j_id
			
	set_job(best_job)
	
	var job_titles_ru = {
		"hunter": "охотника",
		"woodcutter": "дровосека",
		"forager": "собирателя",
		"builder": "строителя",
		"guard": "стражника",
		"quarryman": "каменотёса"
	}
	var job_name_ru = job_titles_ru.get(best_job, best_job)
	
	add_memory("coming_of_age", "adulthood", "", 2.0, "Достиг совершеннолетия (18 лет) и избрал ремесло %s" % job_name_ru, true)
	show_emote("joy", 4.0, 3)
	shout("Мне 18! Мой путь — ремесло %s!" % job_name_ru, 4.0)
	last_status_reason = "Избрал ремесло %s" % job_name_ru
	EventBus.notification_toast.emit("🌱 Совершеннолетие", "%s достиг 18 лет и избрал путь %s" % [name, job_name_ru], "good")
	
	return best_job

# --- МЕТОДЫ ОТНОШЕНИЙ, СОЮЗОВ И ОПЕКИ (S07) ---
func add_relationship(other_id: String, rel_type: String, closeness: float = 50.0, romance: float = 0.0, married: bool = false) -> void:
	var was_parent = false
	if relationships.has(other_id):
		was_parent = relationships[other_id].get("type", "") == "parent" or relationships[other_id].get("is_parent", false)
	relationships[other_id] = {
		"type": rel_type,
		"closeness": closeness,
		"affinity": closeness,
		"romance": romance,
		"respect": 0.0,
		"married": married,
		"is_parent": (rel_type == "parent" or was_parent)
	}
	if rel_type == "spouse" or married:
		spouse_id = other_id

func modify_relationship(other_id: String, delta_affinity: float, delta_respect: float = 0.0) -> void:
	if not relationships.has(other_id):
		relationships[other_id] = {
			"type": "peer",
			"closeness": 50.0,
			"affinity": 0.0,
			"romance": 0.0,
			"respect": 0.0,
			"married": false,
			"is_parent": false
		}
	var rel = relationships[other_id]
	rel["affinity"] = clampf(float(rel.get("affinity", 0.0)) + delta_affinity, -100.0, 100.0)
	rel["closeness"] = clampf(float(rel.get("closeness", 50.0)) + delta_affinity * 0.5, 0.0, 100.0)
	rel["respect"] = clampf(float(rel.get("respect", 0.0)) + delta_respect, -100.0, 100.0)

# Наращивает романтику, не трогая симпатию, уважение и тип связи (в отличие от add_relationship)
func add_romance(other_id: String, amount: float) -> float:
	if not relationships.has(other_id):
		modify_relationship(other_id, 0.0, 0.0)
	var rel = relationships[other_id]
	rel["romance"] = clampf(float(rel.get("romance", 0.0)) + amount, 0.0, 100.0)
	return float(rel["romance"])

func remove_relationship(other_id: String) -> void:
	relationships.erase(other_id)
	if spouse_id == other_id:
		spouse_id = ""

func get_relationship(other_id: String) -> Dictionary:
	return relationships.get(other_id, {})

func get_relationship_affinity(other_id: String) -> float:
	var rel = relationships.get(other_id, {})
	if rel.has("affinity"):
		return float(rel["affinity"])
	return float(rel.get("closeness", 0.0))

func get_relationship_with(other_id: String) -> float:
	return get_relationship_affinity(other_id)

func get_spouses() -> Array[String]:
	var result: Array[String] = []
	for o_id in relationships:
		var r = relationships[o_id]
		if r.get("type", "") == "spouse" or r.get("married", false):
			result.append(o_id)
	return result

func get_parents() -> Array[String]:
	var result: Array[String] = []
	for o_id in relationships:
		var r = relationships[o_id]
		if r.get("type", "") == "parent" or r.get("is_parent", false):
			result.append(o_id)
	return result

func get_children() -> Array[String]:
	var result: Array[String] = []
	for o_id in relationships:
		if relationships[o_id].get("type", "") == "child":
			result.append(o_id)
	return result

func is_child_of(parent_id: String) -> bool:
	return get_parents().has(parent_id)

func get_friends() -> Array[String]:
	var result: Array[String] = []
	for o_id in relationships:
		var r = relationships[o_id]
		if float(r.get("affinity", 0.0)) >= 25.0 or float(r.get("closeness", 0.0)) >= 65.0:
			result.append(o_id)
	return result

func get_rivals() -> Array[String]:
	var result: Array[String] = []
	for o_id in relationships:
		var r = relationships[o_id]
		if float(r.get("affinity", 0.0)) <= -20.0 or has_grudge_against(o_id):
			result.append(o_id)
	return result

func is_dating_with(other_id: String) -> bool:
	var r = relationships.get(other_id, {})
	return float(r.get("romance", 0.0)) >= 20.0 or r.get("married", false)

func is_related_to(other: CitizenNPC) -> bool:
	if other == null or other.citizen_id == citizen_id:
		return false
	if family_id != "" and other.family_id != "" and family_id == other.family_id:
		return true
	var r = get_relationship(other.citizen_id)
	if not r.is_empty() and r.get("type", "") in ["parent", "child", "sibling"]:
		return true
	var my_parents = get_parents()
	var other_parents = other.get_parents()
	for p in my_parents:
		if other_parents.has(p):
			return true
	return false

func can_marry(other: CitizenNPC, marriage_law: String = "monogamy") -> Dictionary:
	if other == null:
		return {"allowed": false, "reason": "Партнёр не существует"}
	if other.citizen_id == citizen_id:
		return {"allowed": false, "reason": "Нельзя вступить в союз с самим собой"}
	if age < 18 or other.age < 18:
		return {"allowed": false, "reason": "Совершеннолетие для союзов — с 18 лет"}
	if is_related_to(other):
		return {"allowed": false, "reason": "Близкое кровное родство исключает союз"}
	
	if marriage_law == "monogamy":
		if not get_spouses().is_empty():
			return {"allowed": false, "reason": "При моногамии гражданин уже состоит в браке"}
		if not other.get_spouses().is_empty():
			return {"allowed": false, "reason": "При моногамии избранник уже состоит в браке"}
	elif marriage_law == "polygamy":
		if get_spouses().size() >= 4:
			return {"allowed": false, "reason": "Достигнут предел супругов"}
	return {"allowed": true, "reason": "Союз разрешён"}

func marry(other: CitizenNPC, marriage_law: String = "monogamy") -> bool:
	var check = can_marry(other, marriage_law)
	if not check.get("allowed", false):
		return false
	add_relationship(other.citizen_id, "spouse", 80.0, 80.0, true)
	other.add_relationship(citizen_id, "spouse", 80.0, 80.0, true)
	if family_id == "" and other.family_id == "":
		family_id = "fam_" + citizen_id
		other.family_id = family_id
	elif family_id != "" and other.family_id == "":
		other.family_id = family_id
	elif family_id == "" and other.family_id != "":
		family_id = other.family_id
	return true

func is_pregnant() -> bool:
	return not pregnancy.is_empty()

func start_pregnancy(partner_id: String, p_gestation_sec: float = 450.0) -> bool:
	if gender != "f" or age < 18 or age > 45 or is_pregnant():
		return false
	pregnancy = {
		"partner_id": partner_id,
		"progress_sec": 0.0,
		"gestation_sec": p_gestation_sec,
		"stage": "early",
		"health_risk": 0.0
	}
	return true

func advance_pregnancy(delta: float) -> String:
	if pregnancy.is_empty():
		return ""
	pregnancy["progress_sec"] = float(pregnancy.get("progress_sec", 0.0)) + delta
	var progress = float(pregnancy["progress_sec"])
	var total = float(pregnancy.get("gestation_sec", 450.0))
	var ratio = progress / maxf(1.0, total)
	if ratio >= 1.0:
		pregnancy["stage"] = "labor"
		return "birth"
	elif ratio >= 0.75:
		pregnancy["stage"] = "late"
	elif ratio >= 0.35:
		pregnancy["stage"] = "mid"
	else:
		pregnancy["stage"] = "early"
	return pregnancy["stage"]

# --- ОЦЕНКА ПОЛЕЗНОСТИ ЗАДАЧ И ОПЫТ (S08) ---
func score_task(task_type: String, target_distance: float = 0.0, is_family_task: bool = false, requires_skill: String = "") -> float:
	var score = 50.0
	
	if requires_skill != "" and (requires_skill == job_id or weapon_skills.has(requires_skill + "_level")):
		score += 25.0
	elif job_id != "idle" and task_type != job_id and task_type != "rest":
		score -= (float(traits.get("pride", 50.0)) * 0.25)
		
	score -= target_distance * 0.05
	
	if energy < 35.0 or hunger < 40.0:
		if task_type == "rest":
			score += 60.0
		else:
			score -= (40.0 - energy) * 1.5
	elif task_type == "rest":
		score -= 40.0
		
	if is_family_task:
		score += (float(traits.get("empathy", 50.0)) * 0.5)
		
	score += (float(traits.get("diligence", 50.0)) - 50.0) * 0.3
	
	if task_type == ongoing_task_kind and commitment_timer > 0.0:
		score += 30.0
		
	return score

func gain_profession_xp(prof_name: String, work_seconds: float) -> void:
	if prof_name == "" or prof_name == "idle":
		return
	var gained_xp = (work_seconds / 900.0) * 100.0
	experience[prof_name] = float(experience.get(prof_name, 0.0)) + gained_xp
	var cur_xp = float(experience[prof_name])
	var cur_level = int(profession_levels.get(prof_name, 0))
	var next_level_thresh = (cur_level + 1) * 100.0
	if cur_xp >= next_level_thresh:
		profession_levels[prof_name] = cur_level + 1
		EventBus.notification_toast.emit(
			"Рост мастерства",
			"%s повысил уровень в ремесле (%s: ур. %d)" % [name, prof_name, cur_level + 1],
			"good"
		)


# ==============================================================================
# СИСТЕМА ЖИВЫХ NPC (PLANETKI / ТЗ NPC_ALIVE_SYSTEM_TZ.md)
# ==============================================================================

# --- ПРИЧУДЫ (QUIRKS) И АРХЕТИПЫ ---

func init_quirks(seed_num: int = 0) -> void:
	quirks.clear()
	var s = seed_num if seed_num != 0 else seed_val
	var rng = RandomNumberGenerator.new()
	rng.seed = s + 101
	
	var pool: Array[String] = [
		"early_bird", "night_owl", "glutton", "ascetic",
		"chatterbox", "superstitious", "workaholic", "perfectionist",
		"brawler", "romantic", "gossip", "hoarder"
	]
	
	# Склонность к определённым причудам на основе черт характера
	var weighted_pool: Array[String] = []
	for q in pool:
		var weight = 1.0
		match q:
			"workaholic":
				if float(traits.get("diligence", 50.0)) > 65.0: weight += 2.5
			"perfectionist":
				if float(traits.get("diligence", 50.0)) > 60.0 and float(traits.get("temper", 50.0)) < 40.0: weight += 2.0
			"chatterbox", "gossip":
				if float(traits.get("sociability", 50.0)) > 65.0: weight += 2.5
			"ascetic":
				if float(traits.get("sociability", 50.0)) < 35.0: weight += 2.0
			"brawler":
				if float(traits.get("temper", 50.0)) > 60.0 or float(traits.get("bravery", 50.0)) > 65.0: weight += 2.5
			"superstitious":
				if float(traits.get("tradition", 50.0)) > 65.0: weight += 2.5
			"romantic":
				if float(traits.get("empathy", 50.0)) > 60.0 and float(traits.get("sociability", 50.0)) > 55.0: weight += 2.0
			"glutton":
				if float(traits.get("temper", 50.0)) < 40.0 and float(traits.get("diligence", 50.0)) < 50.0: weight += 1.5
		var count = maxi(1, int(round(weight)))
		for i in range(count):
			weighted_pool.append(q)
	
	# Выбираем 1-2 причуды
	var num_quirks = 1 if rng.randf() > 0.4 else 2
	for i in range(num_quirks):
		if weighted_pool.is_empty():
			break
		var idx = rng.randi_range(0, weighted_pool.size() - 1)
		var chosen = weighted_pool[idx]
		if not quirks.has(chosen):
			quirks.append(chosen)
		# Удаляем все вхождения выбранной причуды
		var new_pool: Array[String] = []
		for q_item in weighted_pool:
			if q_item != chosen:
				new_pool.append(q_item)
		weighted_pool = new_pool

func has_quirk(quirk_id: String) -> bool:
	return quirks.has(quirk_id)

func get_quirk_effects() -> Dictionary:
	var effects = {
		"work_speed_mult": 1.0,
		"hunger_rate_mult": 1.0,
		"social_rate_mult": 1.0,
		"morale_bonus": 0.0
	}
	for q in quirks:
		match q:
			"early_bird":
				effects["work_speed_mult"] *= 1.1
			"night_owl":
				effects["work_speed_mult"] *= 1.05
			"glutton":
				effects["hunger_rate_mult"] *= 1.25
			"ascetic":
				effects["hunger_rate_mult"] *= 0.8
			"chatterbox":
				effects["social_rate_mult"] *= 1.4
			"gossip":
				effects["social_rate_mult"] *= 1.25
			"brawler":
				effects["morale_bonus"] += 2.0
			"workaholic":
				if state == State.WORKING or state == State.GATHERING:
					effects["work_speed_mult"] *= 1.15
				elif state == State.IDLE:
					effects["morale_bonus"] -= 3.0
			"perfectionist":
				effects["work_speed_mult"] *= 0.9
	return effects

func get_personality_archetype() -> String:
	var d = float(traits.get("diligence", 50.0))
	var b = float(traits.get("bravery", 50.0))
	var e = float(traits.get("empathy", 50.0))
	var s = float(traits.get("sociability", 50.0))
	var t = float(traits.get("temper", 50.0))
	var a = float(traits.get("ambition", 50.0))
	var tr = float(traits.get("tradition", 50.0))
	var c = float(traits.get("curiosity", 50.0))
	var lr = float(traits.get("loyalty_ruler", 50.0))
	
	if a >= 65.0 and s >= 55.0:
		return "leader"
	if b >= 65.0 and t >= 45.0:
		return "fighter"
	if t >= 60.0 and tr <= 40.0:
		return "rebel"
	if tr >= 65.0 and lr >= 55.0:
		return "keeper"
	if s >= 65.0 and e >= 55.0:
		return "diplomat"
	if e >= 65.0 and d >= 45.0:
		return "caretaker"
	if c >= 65.0 and tr <= 45.0:
		return "visionary"
	if s <= 35.0 and d >= 45.0:
		return "loner"
	if d >= 60.0 and tr >= 45.0:
		return "worker"
	
	# Fallback по наивысшей доминирующей черте
	var max_val = maxf(d, maxf(b, maxf(e, maxf(s, maxf(t, maxf(a, maxf(tr, c)))))))
	if max_val == a: return "leader"
	if max_val == b: return "fighter"
	if max_val == t: return "rebel"
	if max_val == tr: return "keeper"
	if max_val == s: return "diplomat"
	if max_val == e: return "caretaker"
	if max_val == c: return "visionary"
	if max_val == d: return "worker"
	return "worker"


# --- ПАРСИНГ И ВЫЧИСЛЕНИЕ УСЛОВИЙ РЕАКЦИЙ ---

func _evaluate_condition(condition_str: String, event_data: Dictionary = {}) -> bool:
	var cond = condition_str.strip_edges()
	if cond == "" or cond == "true" or cond == "default":
		return true
	if cond == "false":
		return false
	
	# Разделение по " or "
	if " or " in cond:
		var or_parts = cond.split(" or ")
		for part in or_parts:
			if _evaluate_condition(part.strip_edges(), event_data):
				return true
		return false
		
	# Разделение по " and "
	if " and " in cond:
		var and_parts = cond.split(" and ")
		for part in and_parts:
			if not _evaluate_condition(part.strip_edges(), event_data):
				return false
		return true
		
	# Одиночные проверки
	if cond.begins_with("has_quirk(") and cond.ends_with(")"):
		var q_name = cond.substr(10, cond.length() - 11).replace("\"", "").replace("'", "").strip_edges()
		return has_quirk(q_name)
		
	if cond.begins_with("has_memory(") and cond.ends_with(")"):
		var m_name = cond.substr(11, cond.length() - 12).replace("\"", "").replace("'", "").strip_edges()
		return has_memory(m_name)
		
	# Проверка операторов сравнения: ==, !=, >=, <=, >, <
	for op in [">=", "<=", "!=", "==", ">", "<"]:
		if op in cond:
			var parts = cond.split(op, false, 1)
			if parts.size() == 2:
				var left = parts[0].strip_edges()
				var right = parts[1].strip_edges().replace("\"", "").replace("'", "")
				var left_val: Variant = null
				
				if left == "cohort":
					left_val = cohort
				elif left == "job_id":
					left_val = job_id
				elif left == "gender":
					left_val = gender
				elif left == "is_ruler":
					left_val = is_ruler
				elif left == "personality" or left == "archetype":
					left_val = get_personality_archetype()
				elif left == "loyalty" or left == "morale":
					left_val = loyalty
				elif left == "health":
					left_val = health
				elif left == "hunger":
					left_val = hunger
				elif left == "energy":
					left_val = energy
				elif left == "age":
					left_val = float(age)
				elif left.begins_with("traits."):
					var trait_key = left.substr(7)
					left_val = float(traits.get(trait_key, 50.0))
				elif left.begins_with("event."):
					var ev_key = left.substr(6)
					left_val = event_data.get(ev_key, null)
				else:
					left_val = traits.get(left, null)
					
				if left_val != null:
					if typeof(left_val) == TYPE_BOOL:
						var r_bool = right.to_lower() == "true"
						return (left_val == r_bool) if op == "==" else (left_val != r_bool)
					elif typeof(left_val) == TYPE_STRING:
						var r_str = str(right)
						return (str(left_val) == r_str) if op == "==" else (str(left_val) != r_str)
					elif typeof(left_val) in [TYPE_INT, TYPE_FLOAT]:
						var r_num = float(right)
						var l_num = float(left_val)
						match op:
							"==": return is_equal_approx(l_num, r_num)
							"!=": return not is_equal_approx(l_num, r_num)
							">=": return l_num >= r_num
							"<=": return l_num <= r_num
							">":  return l_num > r_num
							"<":  return l_num < r_num
	return false


# --- ОБРАБОТКА СОБЫТИЙ ЦИВИЛИЗАЦИИ И МИРА ---

func receive_civilization_event(event_data: Dictionary, choices_history: Array = []) -> void:
	if not is_alive:
		return
	
	var reactions = event_data.get("npc_reactions", [])
	if reactions is Dictionary:
		reactions = [reactions]
	elif not (reactions is Array):
		reactions = []
		
	# Если есть реакции, привязанные к конкретным выборам игрока
	var choice_reactions = event_data.get("reactions_by_choice", {})
	if not choice_reactions.is_empty() and not choices_history.is_empty():
		var last_choice = choices_history.back()
		var last_choice_idx = int(last_choice.get("choice_index", -1)) if last_choice is Dictionary else int(last_choice)
		if choice_reactions.has(str(last_choice_idx)):
			var extra = choice_reactions[str(last_choice_idx)]
			if extra is Array:
				reactions.append_array(extra)
			elif extra is Dictionary:
				reactions.append(extra)
				
	var reacted = false
	for r in reactions:
		if not (r is Dictionary):
			continue
		var filter_str = r.get("filter", "true")
		if _evaluate_condition(filter_str, event_data):
			reacted = true
			var morale_delta = float(r.get("morale_delta", 0.0))
			if not is_zero_approx(morale_delta):
				loyalty = clampf(loyalty + morale_delta, 0.0, 100.0)
				
			if r.has("memory") and r["memory"] is Dictionary:
				var m = r["memory"]
				add_memory(
					m.get("type", "civ_event"),
					"event",
					event_data.get("id", ""),
					float(m.get("importance", 0.6)),
					m.get("desc", event_data.get("title", "Событие поселения"))
				)
				
			if r.has("emote"):
				var dur = float(r.get("duration", 3.5))
				var prio = int(r.get("priority", 3))
				show_emote(str(r["emote"]), dur, prio, true)
				
			if r.has("shout"):
				var sh_dur = float(r.get("shout_duration", 3.0))
				shout(str(r["shout"]), sh_dur)
				
			if r.has("trait_changes") and r["trait_changes"] is Dictionary:
				for t_key in r["trait_changes"]:
					var old_val = float(traits.get(t_key, 50.0))
					var delta = float(r["trait_changes"][t_key])
					traits[t_key] = clampf(old_val + delta, 0.0, 100.0)
					EventBus.npc_trait_changed.emit(citizen_id, t_key, old_val, traits[t_key])
					
			if r.has("autonomous_action"):
				_trigger_reaction_action(str(r["autonomous_action"]), event_data)
				
	# Если нет персональных реакций, применяем базовый эффект события по умолчанию
	if not reacted:
		var def_morale = float(event_data.get("default_morale_delta", 0.0))
		if not is_zero_approx(def_morale):
			loyalty = clampf(loyalty + def_morale, 0.0, 100.0)

func receive_world_event(event_type: String, event_params: Dictionary) -> void:
	if not is_alive:
		return
	var state_before = state
	_receive_world_event_impl(event_type, event_params)
	# Вождём под управлением игрока ИИ-реакции не двигают (бегство, траур, праздник)
	if custom_data.get("player_controlled", false):
		state = state_before

func _receive_world_event_impl(event_type: String, event_params: Dictionary) -> void:
		
	match event_type:
		"citizen_died":
			var deceased_id = event_params.get("deceased_id", "")
			var deceased_name = event_params.get("deceased_name", "Соплеменник")
			if deceased_id == citizen_id:
				return
				
			# Без известного покойного нельзя угадывать близость: пустой id совпал бы с пустым
			# spouse_id/guardian_id у каждого одинокого жителя, и в траур уходило бы всё племя
			var rel = relationships.get(deceased_id, {}) if deceased_id != "" else {}
			var kin_types = ["spouse", "late_spouse", "parent", "child", "sibling", "guardian", "ward"]
			var is_close = deceased_id != "" and (
				rel.get("type", "") in kin_types
				or rel.get("is_parent", false)
				or float(rel.get("affinity", 0.0)) >= 40.0
				or deceased_id == guardian_id
			)
			var is_rival = deceased_id != "" and has_grudge_against(deceased_id)
			
			if is_close:
				add_memory("grief", "death", deceased_id, 2.5, "Потерял близкого человека: %s" % deceased_name, true)
				loyalty = clampf(loyalty - 15.0, 0.0, 100.0)
				state = State.MOURNING
				social_timer = 18.0
				show_emote("grief", 5.0, 5, true)
				shout("Горе нам! Покойся с миром, %s..." % deceased_name)
			elif is_rival:
				loyalty = clampf(loyalty + 4.0, 0.0, 100.0)
				show_emote("relief", 3.0, 2)
			else:
				var emp = float(traits.get("empathy", 50.0))
				loyalty = clampf(loyalty - (emp * 0.05), 0.0, 100.0)
				if emp > 65.0:
					state = State.MOURNING
					social_timer = 8.0
					show_emote("sorrow", 3.0, 3)
					
		"law_enacted":
			var law_id = event_params.get("law_id", "")
			var tr = float(traits.get("tradition", 50.0))
			var tmp = float(traits.get("temper", 50.0))
			var arch = get_personality_archetype()
			
			if arch == "keeper" or tr >= 65.0:
				loyalty = clampf(loyalty + 6.0, 0.0, 100.0)
				show_emote("cheer", 3.0, 2)
				shout("Закон укрепляет наш порядок!")
			elif arch == "rebel" or (tmp >= 60.0 and tr <= 35.0):
				loyalty = clampf(loyalty - 8.0, 0.0, 100.0)
				state = State.COMPLAINING
				social_timer = 12.0
				show_emote("disapproval", 4.0, 4)
				shout("Опять вождь стесняет нашу волю!")
				EventBus.npc_complaint_to_ruler.emit(citizen_id, "law_discontent")
				
		"building_constructed":
			var b_name = event_params.get("building_name", "Здание")
			var is_builder = (job_id == "builder")
			if is_builder:
				loyalty = clampf(loyalty + 5.0, 0.0, 100.0)
				show_emote("cheer", 3.0, 2)
				shout("Наш труд украсил поселение (%s)!" % b_name)
			else:
				loyalty = clampf(loyalty + 2.0, 0.0, 100.0)
				
		"attack_started":
			var brv = float(traits.get("bravery", 50.0))
			if brv < 40.0:
				state = State.FLEEING_HOME
				social_timer = 15.0
				show_emote("fear", 4.0, 5, true)
				shout("Нападение! Спасайтесь в домах!")
			elif brv >= 65.0 or get_personality_archetype() == "fighter":
				show_emote("anger", 4.0, 5, true)
				shout("К оружию! Защитим очаг!")
				
		"celebration_started":
			if state != State.MOURNING and state != State.FLEEING:
				state = State.CELEBRATING
				social_timer = 20.0
				loyalty = clampf(loyalty + 8.0, 0.0, 100.0)
				show_emote("dance", 5.0, 3)
				shout("Слава нашему роду!")
				
		"revolt_risk":
			if loyalty < 35.0 and (get_personality_archetype() in ["rebel", "leader"]):
				state = State.CONFRONTING
				social_timer = 15.0
				show_emote("anger", 5.0, 5, true)
				shout("Вождь ведёт нас к гибели! Пора всё менять!")

func _trigger_reaction_action(action_name: String, event_data: Dictionary) -> void:
	# Вождём управляет игрок: чувства и память остаются, но действие за него не выбирается
	if custom_data.get("player_controlled", false):
		return
	active_social_action = action_name
	match action_name:
		"celebrate":
			state = State.CELEBRATING
			social_timer = 15.0
		"mourn":
			state = State.MOURNING
			social_timer = 15.0
		"confront", "protest":
			state = State.CONFRONTING
			social_timer = 12.0
		"complain":
			state = State.COMPLAINING
			social_timer = 10.0
			EventBus.npc_complaint_to_ruler.emit(citizen_id, event_data.get("id", "general_complaint"))
		"pray":
			state = State.PRAYING
			social_timer = 12.0
		"help":
			state = State.HELPING
			social_timer = 10.0
		"flee_home":
			state = State.FLEEING_HOME
			social_timer = 15.0


# --- МНЕНИЯ И ОЦЕНКА РЕШЕНИЙ (OPINIONS) ---

func form_opinion_on_decision(decision_id: String, decision_data: Dictionary) -> Dictionary:
	var tags = decision_data.get("tags", [])
	var support_score = 0.0
	var oppose_score = 0.0
	var reasons: Array[String] = []
	
	var tr = float(traits.get("tradition", 50.0))
	var emp = float(traits.get("empathy", 50.0))
	var dil = float(traits.get("diligence", 50.0))
	var amb = float(traits.get("ambition", 50.0))
	var tmp = float(traits.get("temper", 50.0))
	var brv = float(traits.get("bravery", 50.0))
	
	for tag in tags:
		match tag:
			"tradition":
				if tr >= 55.0:
					support_score += (tr - 50.0) * 0.5
					reasons.append("уважает заветы предков")
				else:
					oppose_score += (50.0 - tr) * 0.5
					reasons.append("хочет новизны и перемен")
			"reform", "innovation":
				if tr <= 45.0:
					support_score += (50.0 - tr) * 0.5
					reasons.append("стремится к развитию")
				else:
					oppose_score += (tr - 50.0) * 0.5
					reasons.append("опасается ломки устоев")
			"mercy", "charity":
				if emp >= 55.0:
					support_score += (emp - 50.0) * 0.5
					reasons.append("проявляет сострадание")
				else:
					oppose_score += (50.0 - emp) * 0.3
			"harsh_punishment", "sacrifice":
				if emp >= 60.0:
					oppose_score += (emp - 40.0) * 0.6
					reasons.append("не приемлет жестокости")
				elif tmp >= 60.0 or brv >= 65.0:
					support_score += 15.0
					reasons.append("верит в силу строгого порядка")
			"hard_work", "tax":
				if dil >= 60.0:
					support_score += (dil - 50.0) * 0.3
				else:
					oppose_score += (60.0 - dil) * 0.4
					reasons.append("тяготится лишним бременем")
			"expansion", "war":
				if amb >= 55.0 or brv >= 60.0:
					support_score += (amb + brv - 100.0) * 0.4
					reasons.append("жаждет побед и славы")
				else:
					oppose_score += 20.0
					reasons.append("хочет мирного спокойствия")
					
	var stance = "neutral"
	var diff = support_score - oppose_score
	if diff >= 8.0:
		stance = "support"
	elif diff <= -8.0:
		stance = "oppose"
		
	var importance = clampf(absf(diff) / 30.0, 0.2, 1.0)
	var reason_str = ", ".join(reasons) if not reasons.is_empty() else "считает это обычным делом"
	
	var opinion_data = {
		"stance": stance,
		"importance": importance,
		"reason": reason_str,
		"score_diff": diff,
		"formed_year": GameManager.current_year if GameManager else 1
	}
	
	opinions[decision_id] = opinion_data
	EventBus.npc_opinion_formed.emit(citizen_id, decision_id, stance)
	return opinion_data

func get_opinion(decision_id: String) -> Dictionary:
	return opinions.get(decision_id, {})


# --- АВТОНОМНЫЕ СОЦИАЛЬНЫЕ ДЕЙСТВИЯ (ТЗ РАЗДЕЛЫ 5-7) ---

func _can_interrupt_current_task() -> bool:
	if not interrupted_task.is_empty():
		return false # Уже есть активное прерывание — не накладываем второе поверх первого
	if state in [State.FLEEING, State.FLEEING_HOME, State.ATTACKING, State.BUTCHERING]:
		return false # Бегство, бой и разделка туши всегда доводятся до конца
	return true

func _save_task_snapshot() -> void:
	interrupted_task = {
		"state": state,
		"task_id": task_id,
		"task_instance_id": task_instance_id,
		"target_id": target_id,
		"target_coord": target_coord,
		"target_pos": target_pos,
		"path": path.duplicate(),
		"path_index": path_index,
		"cargo_type": cargo_type,
		"cargo_amount": cargo_amount,
		"cargo_batch": cargo_batch.duplicate(true),
		"subphase": subphase,
		"work_timer": work_timer,
		"action_timer": action_timer,
		"commitment_timer": commitment_timer,
		"ongoing_task_kind": ongoing_task_kind
	}

func _restore_task_snapshot() -> bool:
	if interrupted_task.is_empty():
		return false
	var snap = interrupted_task
	interrupted_task = {}
	state = snap["state"]
	task_id = snap["task_id"]
	task_instance_id = snap["task_instance_id"]
	target_id = snap["target_id"]
	target_coord = snap["target_coord"]
	target_pos = snap["target_pos"]
	path = snap["path"]
	path_index = snap["path_index"]
	cargo_type = snap["cargo_type"]
	cargo_amount = snap["cargo_amount"]
	cargo_batch = snap["cargo_batch"]
	subphase = snap["subphase"]
	work_timer = snap["work_timer"]
	action_timer = snap["action_timer"]
	commitment_timer = snap["commitment_timer"]
	ongoing_task_kind = snap["ongoing_task_kind"]
	return true

func get_work_speed_multiplier() -> float:
	var mult = 1.0
	var effects = get_quirk_effects()
	if effects.has("work_speed_mult"):
		mult *= float(effects["work_speed_mult"])
	var diligence = float(traits.get("diligence", 50.0))
	mult *= 1.0 + (diligence - 50.0) / 200.0
	# Выбившийся из сил работает заметно медленнее
	if is_exhausted():
		mult *= 0.6
	# Мастерство: каждый уровень профессии ускоряет работу на 3% (до +30%)
	if job_id != "" and job_id != "idle":
		mult *= 1.0 + float(mini(10, get_profession_level(job_id))) * 0.03
	return clampf(mult, 0.6, 1.9)

func _evaluate_autonomous_action(delta: float, settlement: RefCounted) -> void:
	if not is_alive or settlement == null:
		return
		
	# Обработка активных состояний реакций
	if social_timer > 0.0:
		social_timer -= delta
		if social_timer <= 0.0:
			if state in [State.CELEBRATING, State.MOURNING, State.CONFRONTING, State.COMPLAINING, State.HELPING, State.PRAYING, State.FLEEING_HOME]:
				active_social_action = ""
				if not _restore_task_snapshot():
					state = State.IDLE
		return
		
	if social_cooldown > 0.0:
		social_cooldown -= delta
		return
		
	# Раз в 12-20 секунд NPC ищет социальное взаимодействие
	social_cooldown = randf_range(12.0, 20.0)
	
	# Если настроение критически низкое, жалуемся или протестуем
	if loyalty < 30.0:
		var arch = get_personality_archetype()
		if arch in ["rebel", "fighter", "leader"] and _can_interrupt_current_task():
			_save_task_snapshot()
			var ruler_pos: Vector2 = settlement._get_hearth_pos() if settlement.has_method("_get_hearth_pos") else pos
			var c_path: Array[Vector2] = GameManager.nav_grid.find_path(pos, ruler_pos) if GameManager and GameManager.nav_grid else []
			if c_path.is_empty():
				c_path.append(ruler_pos)
			path = c_path
			path_index = 0
			target_pos = ruler_pos
			task_id = "social_action_pending"
			pending_social_action = "complain"
			state = State.MOVING_TO_WORK
			social_timer = 8.0
			show_emote("disapproval", 3.5, 4)
			shout("Вождю нет дела до простых людей!")
			EventBus.npc_complaint_to_ruler.emit(citizen_id, "low_loyalty")
			EventBus.npc_autonomous_action.emit(citizen_id, "complain", "")
			return
			
	# Поиск ближайшего соплеменника для общения
	var citizens_list: Array = settlement.citizens.values() if settlement.citizens is Dictionary else settlement.citizens
	if citizens_list.size() < 2:
		return
		
	var other_c: CitizenNPC = null
	for c_cand in citizens_list:
		if c_cand != null and c_cand.citizen_id != citizen_id and c_cand.is_alive:
			if pos.distance_to(c_cand.pos) <= 80.0: # В пределах 2.5 тайлов
				other_c = c_cand
				break
				
	if other_c == null:
		return
		
	var other_id = other_c.citizen_id
	var other_rel = relationships.get(other_id, {})
	var closeness = float(other_rel.get("closeness", 50.0))
	var temper_a = float(traits.get("temper", 50.0))
	var temper_b = float(other_c.traits.get("temper", 50.0))
	var emp_a = float(traits.get("empathy", 50.0))
	
	# Конфликт / Вражда (если оба вспыльчивы или есть обида)
	if has_grudge_against(other_id) or (temper_a > 65.0 and temper_b > 65.0 and randf() < 0.25):
		closeness = maxf(0.0, closeness - 15.0)
		relationships[other_id] = {"type": "rival", "closeness": closeness, "romance": 0.0, "married": false}
		other_c.relationships[citizen_id] = {"type": "rival", "closeness": closeness, "romance": 0.0, "married": false}
		
		add_memory("feud", "social", other_id, 1.5, "Поссорился с %s" % other_c.name)
		other_c.add_memory("feud", "social", citizen_id, 1.5, "Поссорился с %s" % name)
		
		show_emote("anger", 3.0, 4)
		other_c.show_emote("anger", 3.0, 4)
		shout("Опять ты мне дорогу переходишь, %s?!" % other_c.name)
		
		EventBus.npc_feud_started.emit(citizen_id, other_id, "hot_temper_argument")
		EventBus.npc_autonomous_action.emit(citizen_id, "feud_quarrel", other_id)
		return
		
	# Дружба (если общительные и эмпатичные)
	if closeness >= 70.0 and randf() < 0.3:
		relationships[other_id] = {"type": "friend", "closeness": minf(100.0, closeness + 5.0), "romance": other_rel.get("romance", 0.0), "married": other_rel.get("married", false)}
		other_c.relationships[citizen_id] = {"type": "friend", "closeness": minf(100.0, closeness + 5.0), "romance": other_rel.get("romance", 0.0), "married": other_rel.get("married", false)}
		
		show_emote("talk", 2.5, 2)
		other_c.show_emote("talk", 2.5, 2)
		shout("Рад видеть тебя в добром здравии, друг %s!" % other_c.name)
		
		EventBus.npc_friendship_formed.emit(citizen_id, other_id)
		EventBus.npc_autonomous_action.emit(citizen_id, "friendly_chat", other_id)
		return
		
	# Помощь нуждающемуся
	if emp_a >= 60.0 and (other_c.hunger < 35.0 or other_c.health < 40.0) and _can_interrupt_current_task():
		_save_task_snapshot()
		var h_path: Array[Vector2] = GameManager.nav_grid.find_path(pos, other_c.pos) if GameManager and GameManager.nav_grid else []
		if h_path.is_empty():
			h_path.append(other_c.pos)
		path = h_path
		path_index = 0
		target_id = other_id
		target_pos = other_c.pos
		task_id = "social_action_pending"
		pending_social_action = "help_neighbor"
		state = State.MOVING_TO_WORK
		social_timer = 8.0
		show_emote("gift", 3.0, 3)
		shout("Держись, %s, я помогу тебе!" % other_c.name)
		other_c.show_emote("relief", 3.0, 3)
		EventBus.npc_autonomous_action.emit(citizen_id, "help_neighbor", other_id)
		return

