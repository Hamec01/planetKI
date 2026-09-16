class_name PopulationSim
extends RefCounted

# Демографические когорты (Старт: 10 жителей)
var children: int = 0       # 0–13 лет
var youth: int = 1          # 14–17 лет
var adults_m: int = 4       # 18–45 лет мужчины
var adults_f: int = 4       # 18–45 лет женщины
var elders: int = 1         # 46–60 лет (Старейшина)
var old_folk: int = 0       # 60+ лет

var health_index: float = 95.0 # 0 - 100
var happiness_index: float = 80.0 # 0 - 100

# Индивидуальный список граждан племени
var citizens: Array[Dictionary] = []

func _init() -> void:
	_init_starter_citizens()

func _init_starter_citizens() -> void:
	citizens.clear()
	var starter_roster = [
		{"id": "cit_1", "name": "Старейшина Мирослав", "gender": "m", "age": 52, "cohort": "elder", "job": "idle", "loyalty": 90.0, "health": 90.0, "exp": {"sage": 40, "woodcutter": 10}},
		{"id": "cit_2", "name": "Брок", "gender": "m", "age": 28, "cohort": "adult", "job": "woodcutter", "loyalty": 85.0, "health": 100.0, "exp": {"woodcutter": 25, "hunter": 15}},
		{"id": "cit_3", "name": "Ратибор", "gender": "m", "age": 24, "cohort": "adult", "job": "hunter", "loyalty": 80.0, "health": 100.0, "exp": {"hunter": 30, "builder": 10}},
		{"id": "cit_4", "name": "Ярополк", "gender": "m", "age": 31, "cohort": "adult", "job": "builder", "loyalty": 85.0, "health": 95.0, "exp": {"builder": 20, "quarryman": 15}},
		{"id": "cit_5", "name": "Светозар", "gender": "m", "age": 22, "cohort": "adult", "job": "woodcutter", "loyalty": 80.0, "health": 100.0, "exp": {"woodcutter": 15, "forager": 10}},
		{"id": "cit_6", "name": "Велена", "gender": "f", "age": 26, "cohort": "adult", "job": "forager", "loyalty": 88.0, "health": 100.0, "exp": {"forager": 35, "craftsman": 10}},
		{"id": "cit_7", "name": "Дарина", "gender": "f", "age": 23, "cohort": "adult", "job": "forager", "loyalty": 85.0, "health": 100.0, "exp": {"forager": 25, "priest": 10}},
		{"id": "cit_8", "name": "Лада", "gender": "f", "age": 29, "cohort": "adult", "job": "idle", "loyalty": 90.0, "health": 95.0, "exp": {"forager": 20, "craftsman": 20}},
		{"id": "cit_9", "name": "Забава", "gender": "f", "age": 21, "cohort": "adult", "job": "idle", "loyalty": 85.0, "health": 100.0, "exp": {"forager": 15, "farmer": 15}},
		{"id": "cit_10", "name": "Радомир", "gender": "m", "age": 16, "cohort": "youth", "job": "idle", "loyalty": 80.0, "health": 100.0, "exp": {"hunter": 10, "forager": 10}}
	]
	citizens.append_array(starter_roster)

func get_citizen_by_id(c_id: String) -> Dictionary:
	for c in citizens:
		if c["id"] == c_id:
			return c
	return {}

func set_citizen_job(c_id: String, new_job: String) -> bool:
	for c in citizens:
		if c["id"] == c_id:
			c["job"] = new_job
			return true
	return false

func add_citizen_exp(c_id: String, job_key: String, amount: int = 1) -> void:
	for c in citizens:
		if c["id"] == c_id:
			if not c.has("exp"):
				c["exp"] = {}
			c["exp"][job_key] = c["exp"].get(job_key, 0) + amount
			break

func get_total_population() -> int:
	if not citizens.is_empty():
		return citizens.size()
	return children + youth + adults_m + adults_f + elders + old_folk

func get_workforce_total() -> int:
	var count = 0
	for c in citizens:
		if c["cohort"] in ["adult", "youth", "elder"]:
			count += 1
	if count > 0:
		return count
	return adults_m + adults_f + int(youth * 0.7) + int(elders * 0.5)

func get_mobilization_pool() -> int:
	var count = 0
	for c in citizens:
		if c["cohort"] in ["adult", "youth"] and c["gender"] == "m":
			count += 1
	if count > 0:
		return count
	return adults_m + int(youth * 0.5)

func sim_monthly_tick(food_ratio: float, housing_capacity: int, season: String) -> Dictionary:
	var total_pop = get_total_population()
	var births = 0
	var deaths = 0
	var death_reasons = []
	
	# 1. Рождаемость
	# Базовый шанс рождений зависит от числа взрослых женщин и сытости
	if food_ratio >= 1.0:
		var fertile_couples = min(adults_m, adults_f)
		var birth_rate = 0.035 # ~3.5% в месяц при достатке
		if total_pop > housing_capacity:
			birth_rate *= 0.6 # Теснота сдерживает рождаемость
		if season == "Весна" or season == "Лето":
			birth_rate *= 1.2
			
		var potential_births = int(fertile_couples * birth_rate)
		if randf() < (fertile_couples * birth_rate - potential_births):
			potential_births += 1
		births = potential_births
		children += births
	
	# 2. Смертность
	# Естественная от старости
	if old_folk > 0 and randf() < 0.12:
		old_folk -= 1
		deaths += 1
		death_reasons.append("преклонный возраст")
	if elders > 0 and randf() < 0.03:
		elders -= 1
		deaths += 1
		death_reasons.append("болезни преклонных лет")
		
	# Смертность от голода
	if food_ratio < 0.9:
		var starve_deficit = 1.0 - food_ratio
		var starve_deaths = int(total_pop * starve_deficit * 0.08) + (1 if randf() < 0.5 else 0)
		for i in range(starve_deaths):
			if children > 5:
				children -= 1
				deaths += 1
			elif old_folk > 0:
				old_folk -= 1
				deaths += 1
			elif elders > 2:
				elders -= 1
				deaths += 1
			elif adults_m > 5:
				adults_m -= 1
				deaths += 1
			elif adults_f > 5:
				adults_f -= 1
				deaths += 1
		if starve_deaths > 0:
			death_reasons.append("голод")
			health_index = clampf(health_index - 15.0, 10.0, 100.0)
	else:
		health_index = clampf(health_index + 2.0, 10.0, 100.0)
		
	# Холодная зима
	if season == "Зима" and total_pop > housing_capacity:
		if randf() < 0.35 and children > 5:
			children -= 1
			deaths += 1
			death_reasons.append("зимняя стужа и нехватка крова")
			
	return {
		"births": births,
		"deaths": deaths,
		"reasons": death_reasons,
		"total": get_total_population()
	}

func sim_yearly_aging() -> void:
	# Взросление и переход между когортами раз в год
	# ~1/14 детей становятся молодежью
	var children_grad = int(children / 14.0) + (1 if randf() < 0.4 and children > 5 else 0)
	children -= children_grad
	youth += children_grad
	
	# ~1/4 молодежи становятся взрослыми
	var youth_grad = int(youth / 4.0) + (1 if randf() < 0.5 and youth > 2 else 0)
	youth -= youth_grad
	var m_grad = int(youth_grad / 2.0)
	var f_grad = youth_grad - m_grad
	adults_m += m_grad
	adults_f += f_grad
	
	# ~1/28 взрослых становятся старейшинами
	var adults_grad_m = int(adults_m / 28.0) + (1 if randf() < 0.3 and adults_m > 10 else 0)
	var adults_grad_f = int(adults_f / 28.0) + (1 if randf() < 0.3 and adults_f > 10 else 0)
	adults_m -= adults_grad_m
	adults_f -= adults_grad_f
	elders += (adults_grad_m + adults_grad_f)
	
	# ~1/15 старейшин переходят в глубокие старики
	var elders_grad = int(elders / 15.0) + (1 if randf() < 0.3 and elders > 4 else 0)
	elders -= elders_grad
	old_folk += elders_grad
