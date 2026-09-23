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
	WAITING
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
var hunger: float = 100.0 # 100 = сыт, 0 = умирает от голода
var energy: float = 100.0 # 100 = бодр, 0 = валится с ног
var loyalty: float = 85.0
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

# 2. Оружейная техника (0..20 уровни)
var weapon_skills: Dictionary = {
	"sword_xp": 0.0, "sword_level": 0,
	"axe_xp": 0.0, "axe_level": 0,
	"spear_xp": 0.0, "spear_level": 0,
	"bow_xp": 0.0, "bow_level": 0
}

var profession_levels: Dictionary = {}

var skill_builder: float:
	get: return float(skills.get("builder", experience.get("builder", 0.0)))
	set(val):
		skills["builder"] = val
		experience["builder"] = val
var skill_woodcutter: float:
	get: return float(skills.get("woodcutter", experience.get("woodcutter", 0.0)))
	set(val):
		skills["woodcutter"] = val
		experience["woodcutter"] = val
var skill_stonecutter: float:
	get: return float(skills.get("stonecutter", experience.get("stonecutter", 0.0)))
	set(val):
		skills["stonecutter"] = val
		experience["stonecutter"] = val
var skill_miner: float:
	get: return float(skills.get("miner", experience.get("miner", 0.0)))
	set(val):
		skills["miner"] = val
		experience["miner"] = val
var skill_gatherer: float:
	get: return float(skills.get("gatherer", experience.get("gatherer", 0.0)))
	set(val):
		skills["gatherer"] = val
		experience["gatherer"] = val
var skill_hunter: float:
	get: return float(skills.get("hunter", experience.get("hunter", 0.0)))
	set(val):
		skills["hunter"] = val
		experience["hunter"] = val

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
var social_cooldown: float = 0.0 # Кулдаун на повторные социальные диалоги

# Память о значимых событиях (P01.2 / ТЗ 4.3): спасение, жильё, выселение, предательство
var memories: Array[Dictionary] = []

func take_damage(amount: float, source_name: String = "") -> bool:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		is_alive = false
		if is_ruler:
			var killer = source_name if source_name != "" else "Опасности диких земель"
			EventBus.ruler_died.emit(name, killer)
			if GameManager and GameManager.has_method("trigger_game_over"):
				GameManager.trigger_game_over("Вождь племени %s погиб от: %s. Племя осталось без предводителя." % [name, killer])
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
			s_rate = 2.2; e_rate = 1.5; a_rate = 0.2; prof_key = "stonecutter"; prof_rate = 3.0
		"ore_mining":
			s_rate = 2.0; e_rate = 1.5; a_rate = 0.2; prof_key = "miner"; prof_rate = 3.0
		"building":
			s_rate = 1.5; e_rate = 1.5; a_rate = 0.8; prof_key = "builder"; prof_rate = 3.0
		"carrying":
			s_rate = 1.0; e_rate = 2.0; a_rate = 0.4
		"gathering", "farming":
			s_rate = 0.4; e_rate = 1.2; a_rate = 1.2; prof_key = "gatherer"; prof_rate = 3.0
		"hunting_tracking":
			s_rate = 0.2; e_rate = 1.8; a_rate = 2.0; prof_key = "hunter"; prof_rate = 2.0
		"combat_training":
			s_rate = 1.0; e_rate = 1.5; a_rate = 1.5
			
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
		pool = ["grandpa_staff", "elder_citizen_m"] if gender == "m" else ["grandma", "elder_citizen_f"]
	else:
		if gender == "m":
			pool = ["villager_brown_m", "villager_blue_m", "adult_1", "adult_3"]
		else:
			pool = ["villager_green_f", "villager_red_f", "adult_2", "adult_4"]
	if not pool.is_empty():
		appearance_role = pool[seed_val % pool.size()]

# Роли закреплённые за мужским гендером
const MALE_ROLES: Array = [
	"villager_brown_m", "villager_blue_m", "adult_1", "adult_3",
	"teen_boy_1", "teen_boy_2", "child_boy_1", "child_boy_2",
	"grandpa_staff", "elder_citizen_m"
]
# Роли закреплённые за женским гендером
const FEMALE_ROLES: Array = [
	"villager_green_f", "villager_red_f", "adult_2", "adult_4",
	"teen_girl_1", "teen_girl_2", "child_girl_1", "child_girl_2",
	"grandma", "elder_citizen_f"
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
		cached_texture = CharacterTextureManager.get_character_for_job(job_id, seed_val, race_id)
	else:
		cached_texture = CharacterTextureManager.get_role_texture(race_id, appearance_role)
	if cached_texture == null:
		cached_texture = CharacterTextureManager.get_random_race_character(race_id, seed_val)
	return cached_texture

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
	return maxf(0.2, (float(strength_level) + 1.0) * get_vitality_multiplier())

func get_effective_endurance() -> float:
	return maxf(0.2, (float(endurance_level) + 1.0) * get_vitality_multiplier())

func get_effective_agility() -> float:
	return maxf(0.2, (float(agility_level) + 1.0) * get_vitality_multiplier())

func get_effective_max_carry() -> float:
	var base = max_carry + (float(strength_level) * 0.5)
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

func inherit_traits_from_parents(mother: CitizenNPC, father: CitizenNPC) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	var m_traits = mother.traits if mother != null else {}
	var f_traits = father.traits if father != null else {}
	
	for key in ["diligence", "bravery", "empathy", "sociability", "temper", "honesty", "ambition", "tradition", "curiosity"]:
		var m_val = float(m_traits.get(key, 50.0))
		var f_val = float(f_traits.get(key, 50.0))
		var avg = (m_val + f_val) * 0.5 if (mother and father) else (m_val if mother else f_val)
		var spread = rng.randf_range(-15.0, 15.0)
		traits[key] = clampf(avg + spread, 0.0, 100.0)
	traits["unpredictable"] = (mother and mother.traits.get("unpredictable", false)) or (father and father.traits.get("unpredictable", false)) or (rng.randf() < 0.03)
	traits["aggression"] = traits["temper"]
	traits["pride"] = traits["ambition"]

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
	elif season == "Зима" and home_id == "":
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
		"health": health,
		"hunger": hunger,
		"energy": energy,
		"loyalty": loyalty,
		"experience": experience.duplicate(),
		"skills": skills.duplicate(),
		"last_status_reason": last_status_reason,
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
	gender = data.get("gender", "m")
	age = data.get("age", 25)
	age_progress = data.get("age_progress", 0.0)
	is_ruler = data.get("is_ruler", false)
	cohort = data.get("cohort", "adult")
	race_id = data.get("race_id", "north")
	appearance_role = data.get("appearance_role", "villager_brown_m")
	job_id = data.get("job_id", "idle")
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
	health = data.get("health", 100.0)
	hunger = data.get("hunger", 100.0)
	energy = data.get("energy", 100.0)
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

