class_name PopulationSim
extends RefCounted

const CitizenNPCScript = preload("res://src/simulation/citizen_npc.gd")

# Демографические когорты (синхронизируются 1:1 с citizens)
var children: int = 0       # 0–13 лет
var youth: int = 1          # 14–17 лет
var adults_m: int = 4       # 18–45 лет мужчины
var adults_f: int = 4       # 18–45 лет женщины
var elders: int = 1         # 46–60 лет
var old_folk: int = 0       # 60+ лет

var health_index: float = 95.0 # 0 - 100
var happiness_index: float = 80.0 # 0 - 100

# Индивидуальный список граждан племени (1 гражданин = 1 NPC)
var citizens: Array[CitizenNPC] = []
var next_citizen_num: int = 11

func _init() -> void:
	_init_starter_citizens()

func _init_starter_citizens() -> void:
	citizens.clear()
	var race = GameManager.player_race if "player_race" in GameManager else "north"
	
	var starter_data = [
		{"id": "cit_1", "name": "Старейшина Мирослав", "gender": "m", "age": 52, "cohort": "elder", "job": "elder", "exp": {"sage": 40, "woodcutter": 10}},
		{"id": "cit_2", "name": "Брок", "gender": "m", "age": 28, "cohort": "adult", "job": "woodcutter", "exp": {"woodcutter": 25, "hunter": 15}},
		{"id": "cit_3", "name": "Ратибор", "gender": "m", "age": 24, "cohort": "adult", "job": "hunter", "exp": {"hunter": 30, "builder": 10}},
		{"id": "cit_4", "name": "Ярополк", "gender": "m", "age": 31, "cohort": "adult", "job": "builder", "exp": {"builder": 20, "quarryman": 15}},
		{"id": "cit_5", "name": "Светозар", "gender": "m", "age": 22, "cohort": "adult", "job": "woodcutter", "exp": {"woodcutter": 15, "forager": 10}},
		{"id": "cit_6", "name": "Велена", "gender": "f", "age": 26, "cohort": "adult", "job": "forager", "exp": {"forager": 35, "craftsman": 10}},
		{"id": "cit_7", "name": "Дарина", "gender": "f", "age": 23, "cohort": "adult", "job": "forager", "exp": {"forager": 25, "priest": 10}},
		{"id": "cit_8", "name": "Лада", "gender": "f", "age": 29, "cohort": "adult", "job": "idle", "exp": {"forager": 20, "craftsman": 20}},
		{"id": "cit_9", "name": "Забава", "gender": "f", "age": 21, "cohort": "adult", "job": "idle", "exp": {"forager": 15, "farmer": 15}},
		{"id": "cit_10", "name": "Радомир", "gender": "m", "age": 16, "cohort": "youth", "job": "idle", "exp": {"hunter": 10, "forager": 10}}
	]
	
	for s in starter_data:
		var c = CitizenNPCScript.new(s["id"], s["name"], s["gender"], s["age"], s["cohort"], race)
		c.job_id = s["job"]
		c.experience = s["exp"].duplicate()
		citizens.append(c)
		
	sync_cohorts()

func sync_cohorts() -> void:
	children = 0
	youth = 0
	adults_m = 0
	adults_f = 0
	elders = 0
	old_folk = 0
	
	for c in citizens:
		if c.age <= 13:
			c.cohort = "child"
			children += 1
		elif c.age <= 17:
			c.cohort = "youth"
			youth += 1
		elif c.age <= 45:
			c.cohort = "adult"
			if c.gender == "m":
				adults_m += 1
			else:
				adults_f += 1
		elif c.age <= 60:
			c.cohort = "elder"
			elders += 1
		else:
			c.cohort = "elder"
			old_folk += 1

func get_citizen_by_id(c_id: String) -> CitizenNPC:
	for c in citizens:
		if c.citizen_id == c_id:
			return c
	return null

func set_citizen_job(c_id: String, new_job: String) -> bool:
	for c in citizens:
		if c.citizen_id == c_id:
			c.set_job(new_job)
			return true
	return false

func add_citizen_exp(c_id: String, job_key: String, amount: int = 1) -> void:
	for c in citizens:
		if c.citizen_id == c_id:
			c.experience[job_key] = c.experience.get(job_key, 0) + amount
			break

func get_total_population() -> int:
	return citizens.size()

func get_workforce_total() -> int:
	var count = 0
	for c in citizens:
		if c.cohort in ["adult", "youth", "elder"]:
			count += 1
	return count

func get_mobilization_pool() -> int:
	var count = 0
	for c in citizens:
		if c.cohort in ["adult", "youth"] and c.gender == "m":
			count += 1
	return count

func add_newborn(parent_settlement_id: String = "", spawn_pos: Vector2 = Vector2.ZERO) -> CitizenNPC:
	var race = GameManager.player_race if "player_race" in GameManager else "north"
	var is_male = randf() < 0.5
	var gender_str = "m" if is_male else "f"
	var male_names = ["Мирослав", "Любомир", "Яромир", "Святослав", "Богдан", "Володар", "Всеволод", "Тихомир", "Добрыня", "Влад"]
	var female_names = ["Мирослава", "Любомира", "Радослава", "Злата", "Ярослава", "Милана", "Светлана", "Богдана", "Веселина", "Доброгнева"]
	var picked_name = male_names[randi() % male_names.size()] if is_male else female_names[randi() % female_names.size()]
	
	var c_id = "cit_" + str(next_citizen_num)
	next_citizen_num += 1
	
	var child = CitizenNPCScript.new(c_id, picked_name, gender_str, 0, "child", race)
	child.settlement_id = parent_settlement_id
	child.pos = spawn_pos
	child.home_pos = spawn_pos
	child.last_status_reason = "Новорождённый"
	citizens.append(child)
	sync_cohorts()
	return child

func remove_citizen(c_id: String) -> CitizenNPC:
	for i in range(citizens.size()):
		if citizens[i].citizen_id == c_id:
			var c = citizens[i]
			c._clear_reservations()
			citizens.remove_at(i)
			sync_cohorts()
			return c
	return null

func sim_monthly_tick(food_ratio: float, housing_capacity: int, season: String) -> Dictionary:
	sync_cohorts()
	var total_pop = get_total_population()
	var births = 0
	var deaths = 0
	var death_reasons = []
	
	# 1. Рождаемость
	if food_ratio >= 1.0:
		var fertile_couples = min(adults_m, adults_f)
		var birth_rate = 0.035
		if total_pop > housing_capacity:
			birth_rate *= 0.6
		if season == "Весна" or season == "Лето":
			birth_rate *= 1.2
			
		var potential_births = int(fertile_couples * birth_rate)
		if randf() < (fertile_couples * birth_rate - potential_births):
			potential_births += 1
		births = potential_births
		for _b in range(births):
			add_newborn()
	
	# 2. Смертность
	var to_kill: Array[String] = []
	
	# От старости
	for c in citizens:
		if c.age >= 60 and randf() < 0.12:
			to_kill.append(c.citizen_id)
			death_reasons.append("преклонный возраст (%s)" % c.name)
		elif c.age >= 46 and c.cohort == "elder" and randf() < 0.03:
			to_kill.append(c.citizen_id)
			death_reasons.append("болезни преклонных лет (%s)" % c.name)
			
	# От голода
	if food_ratio < 0.9:
		var starve_deficit = 1.0 - food_ratio
		var starve_deaths = int(total_pop * starve_deficit * 0.08) + (1 if randf() < 0.5 else 0)
		for i in range(starve_deaths):
			if citizens.size() > 2:
				var victim = citizens[randi() % citizens.size()]
				if not to_kill.has(victim.citizen_id):
					to_kill.append(victim.citizen_id)
					death_reasons.append("голод (%s)" % victim.name)
		health_index = clampf(health_index - 15.0, 10.0, 100.0)
	else:
		health_index = clampf(health_index + 2.0, 10.0, 100.0)
		
	# Холодная зима
	if season == "Зима" and total_pop > housing_capacity:
		if randf() < 0.35:
			for c in citizens:
				if c.cohort == "child" and not to_kill.has(c.citizen_id):
					to_kill.append(c.citizen_id)
					death_reasons.append("зимняя стужа и нехватка крова (%s)" % c.name)
					break
					
	for cid in to_kill:
		remove_citizen(cid)
		deaths += 1
		
	return {
		"births": births,
		"deaths": deaths,
		"reasons": death_reasons,
		"total": get_total_population()
	}

func sim_yearly_aging() -> void:
	for c in citizens:
		c.age += 1
	sync_cohorts()

func serialize() -> Dictionary:
	var cit_arr = []
	for c in citizens:
		cit_arr.append(c.serialize())
	return {
		"next_citizen_num": next_citizen_num,
		"citizens": cit_arr
	}

func deserialize(data: Dictionary) -> void:
	next_citizen_num = data.get("next_citizen_num", 11)
	citizens.clear()
	var cit_arr = data.get("citizens", [])
	for c_data in cit_arr:
		var c = CitizenNPCScript.new()
		c.deserialize(c_data)
		citizens.append(c)
	sync_cohorts()
