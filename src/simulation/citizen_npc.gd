class_name CitizenNPC
extends RefCounted

const CombatStatsResolver = preload("res://src/combat/combat_stats_resolver.gd")

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
var name: String = ""
var gender: String = "m" # "m" или "f"
var age: int = 25
var cohort: String = "adult" # "child", "youth", "adult", "elder"
var race_id: String = "north" # "desert", "savanna", "north"
var appearance_role: String = "villager_brown_m"
var seed_val: int = 0

# --- ПРОФЕССИЯ И ПРИВЯЗКИ ---
var job_id: String = "idle"
var workplace_id: String = ""
var workplace_coord: Vector2i = Vector2i(-1, -1)
var home_id: String = ""
var home_coord: Vector2i = Vector2i(-1, -1)
var settlement_id: String = ""

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
var target_type: String = "none" # "none", "resource", "building", "home", "animal", "citizen"
var target_id: String = ""
var target_coord: Vector2i = Vector2i(-1, -1)
var target_pos: Vector2 = Vector2.ZERO
var reservation_ids: Array[String] = []

# --- ИНВЕНТАРЬ И ГРУЗ ---
var cargo_type: String = "" # "food", "wood", "stone", "metal", "game", "carcass", etc.
var cargo_amount: float = 0.0
var max_carry: float = 6.0

# --- ПОТРЕБНОСТИ И ЗДОРОВЬЕ ---
var health: float = 100.0 # 0 .. 100
var max_health: float = 100.0
var is_alive: bool = true
var hunger: float = 100.0 # 100 = сыт, 0 = умирает от голода
var energy: float = 100.0 # 100 = бодр, 0 = валится с ног
var loyalty: float = 85.0
var experience: Dictionary = {}

# --- 4 ВЕКТОРА РАЗВИТИЯ И ЭКИПИРОВКА (PLANETKI v2 / ТЗ РАЗДЕЛЫ 21-32) ---
# 1. Физическая форма (S: 0..20, E: 0..20)
var strength_xp: float = 0.0
var strength_level: int = 0
var endurance_xp: float = 0.0
var endurance_level: int = 0
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

# Суточные лимиты роста (максимум 8 часов физики, 8 часов профессии, 40 XP охоты)
var daily_physical_hours: float = 0.0
var daily_profession_hours: float = 0.0
var daily_hunt_xp: float = 0.0

func take_damage(amount: float, source_name: String = "") -> bool:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		is_alive = false
		return true # Погиб
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
	var prof_key = ""
	var prof_rate = 0.0
	
	match activity:
		"woodcutting":
			s_rate = 2.0; e_rate = 1.5; prof_key = "woodcutter"; prof_rate = 3.0
		"stone_mining":
			s_rate = 2.2; e_rate = 1.5; prof_key = "stonecutter"; prof_rate = 3.0
		"ore_mining":
			s_rate = 2.0; e_rate = 1.5; prof_key = "miner"; prof_rate = 3.0
		"building":
			s_rate = 1.5; e_rate = 1.5; prof_key = "builder"; prof_rate = 3.0
		"carrying":
			s_rate = 1.0; e_rate = 2.0
		"gathering", "farming":
			s_rate = 0.4; e_rate = 1.2; prof_key = "gatherer"; prof_rate = 3.0
		"hunting_tracking":
			s_rate = 0.2; e_rate = 1.8; prof_key = "hunter"; prof_rate = 2.0
		"combat_training":
			s_rate = 1.0; e_rate = 1.5
			
	# Начисление силы и выносливости (порог L: 200 * L^2)
	strength_xp += s_rate * usable_hours
	strength_level = mini(20, int(floor(sqrt(strength_xp / 200.0))))
	
	endurance_xp += e_rate * usable_hours
	endurance_level = mini(20, int(floor(sqrt(endurance_xp / 200.0))))
	
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

func _pick_initial_appearance() -> void:
	if appearance_role != "" and appearance_role != "villager_brown_m":
		return
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
	if state in [State.MOVING_TO_WORK, State.WORKING, State.GATHERING, State.ATTACKING, State.BUTCHERING]:
		_clear_reservations()
		state = State.IDLE
		last_status_reason = "Сменил занятие"

func is_idle() -> bool:
	return job_id == "idle" and workplace_id == "" and cohort in ["adult", "youth"]

func set_home(p_home_id: String, p_coord: Vector2i, p_pos: Vector2) -> void:
	home_id = p_home_id
	home_coord = p_coord
	home_pos = p_pos

func set_workplace(p_work_id: String, p_coord: Vector2i) -> void:
	workplace_id = p_work_id
	workplace_coord = p_coord

func get_speed() -> float:
	var spd = base_speed
	if cohort == "elder":
		spd *= 0.8
	elif cohort == "child":
		spd *= 0.9
	if energy < 20.0:
		spd *= 0.75
	if health < 40.0:
		spd *= 0.65
	return spd

func shout(text: String, duration: float = 2.5) -> void:
	speech_bubble = text
	speech_timer = duration

func clear_speech() -> void:
	speech_bubble = ""
	speech_timer = 0.0

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
		"cohort": cohort,
		"race_id": race_id,
		"appearance_role": appearance_role,
		"job_id": job_id,
		"workplace_id": workplace_id,
		"workplace_coord": [workplace_coord.x, workplace_coord.y],
		"home_id": home_id,
		"home_coord": [home_coord.x, home_coord.y],
		"settlement_id": settlement_id,
		"pos": [pos.x, pos.y],
		"home_pos": [home_pos.x, home_pos.y],
		"state": state,
		"cargo_type": cargo_type,
		"cargo_amount": cargo_amount,
		"health": health,
		"hunger": hunger,
		"energy": energy,
		"loyalty": loyalty,
		"experience": experience,
		"last_status_reason": last_status_reason,
		"strength_xp": strength_xp,
		"strength_level": strength_level,
		"endurance_xp": endurance_xp,
		"endurance_level": endurance_level,
		"stamina_current": stamina_current,
		"stamina_max": stamina_max,
		"weapon_skills": weapon_skills,
		"encounter_growth_points": encounter_growth_points,
		"recent_encounters": recent_encounters,
		"equipment": equipment
	}

func deserialize(data: Dictionary) -> void:
	citizen_id = data.get("citizen_id", "")
	name = data.get("name", "")
	gender = data.get("gender", "m")
	age = data.get("age", 25)
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
	settlement_id = data.get("settlement_id", "")
	var p = data.get("pos", [0, 0])
	pos = Vector2(p[0], p[1])
	var hp = data.get("home_pos", [0, 0])
	home_pos = Vector2(hp[0], hp[1])
	state = data.get("state", State.IDLE)
	cargo_type = data.get("cargo_type", "")
	cargo_amount = data.get("cargo_amount", 0.0)
	health = data.get("health", 100.0)
	hunger = data.get("hunger", 100.0)
	energy = data.get("energy", 100.0)
	loyalty = data.get("loyalty", 85.0)
	experience = data.get("experience", {})
	last_status_reason = data.get("last_status_reason", "Отдыхает")
	strength_xp = data.get("strength_xp", 0.0)
	strength_level = data.get("strength_level", 0)
	endurance_xp = data.get("endurance_xp", 0.0)
	endurance_level = data.get("endurance_level", 0)
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
	cached_texture = null
