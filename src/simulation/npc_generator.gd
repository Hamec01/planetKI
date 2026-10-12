class_name NPCGenerator
extends RefCounted

## NPCGenerator — Генератор разнообразных NPC по требованию (PlanetKI x Asset Composer)
## Создаёт живых соплеменников с индивидуальными характеристиками, профессиями,
## чертами характера и уникальной модульной чиби-внешностью.

const CitizenNPCScript = preload("res://src/simulation/citizen_npc.gd")
const ComposerAssetsScript = preload("res://src/core/composer_assets.gd")

const MALE_NAMES: Array[String] = [
	"Мирослав", "Любомир", "Яромир", "Святослав", "Богдан", "Володар",
	"Всеволод", "Тихомир", "Добрыня", "Влад", "Ратибор", "Брок",
	"Ярополк", "Светозар", "Радомир", "Борислав", "Велимир", "Горыня",
	"Даромир", "Ждан", "Златозар", "Мстислав", "Остромир", "Пересвет",
	"Радим", "Ростислав", "Судислав", "Твердислав", "Храбр", "Яровит"
]

const FEMALE_NAMES: Array[String] = [
	"Мирослава", "Любомира", "Радослава", "Злата", "Ярослава", "Милана",
	"Светлана", "Богдана", "Веселина", "Доброгнева", "Велена", "Дарина",
	"Лада", "Забава", "Радмила", "Беляна", "Власта", "Голуба",
	"Красава", "Любава", "Милонега", "Рогнеда", "Снежана", "Цветана",
	"Часлава", "Ярогнева", "Купава", "Берегиня", "Верхуслава", "Добрава"
]

const JOBS: Array[String] = [
	"idle", "woodcutter", "hunter", "forager", "builder",
	"miner", "quarryman", "craftsman", "tanner"
]

const TOOLS_BY_JOB: Dictionary = {
	"woodcutter": {"id": "tool_axe", "type": "axe", "durability": 100.0, "max_durability": 100.0},
	"miner": {"id": "tool_pick", "type": "pickaxe", "durability": 100.0, "max_durability": 100.0},
	"quarryman": {"id": "tool_pick", "type": "pickaxe", "durability": 100.0, "max_durability": 100.0},
	"craftsman": {"id": "tool_hammer", "type": "hammer", "durability": 100.0, "max_durability": 100.0},
	"forager": {"id": "tool_knife", "type": "knife", "durability": 100.0, "max_durability": 100.0},
	"hunter": {"id": "tool_knife", "type": "knife", "durability": 100.0, "max_durability": 100.0}
}

const WEAPONS_BY_JOB: Dictionary = {
	"hunter": "hunting_bow",
	"warrior": "short_sword",
	"spearman": "simple_spear",
	"guard": "short_sword"
}

static var _counter: int = 1000

## Генерация единичного жителя с заданными или случайными параметрами
static func generate_citizen(options: Dictionary = {}) -> CitizenNPC:
	_counter += 1
	var c_id = String(options.get("id", "cit_gen_%d_%d" % [_counter, Time.get_ticks_usec()]))
	
	# Пол: "m" или "f"
	var gender = String(options.get("gender", ""))
	if gender != "m" and gender != "f":
		gender = "m" if randf() < 0.5 else "f"
		
	# Имя
	var name = String(options.get("name", ""))
	if name == "":
		var pool = MALE_NAMES if gender == "m" else FEMALE_NAMES
		name = pool[randi() % pool.size()]
		
	# Когорта и возраст
	var cohort = String(options.get("cohort", ""))
	var age = int(options.get("age", -1))
	if age < 0:
		if cohort == "child":
			age = randi_range(2, 13)
		elif cohort == "youth":
			age = randi_range(14, 17)
		elif cohort == "elder":
			age = randi_range(46, 68)
		else:
			age = randi_range(18, 45)
			
	if cohort == "":
		if age <= 13:
			cohort = "child"
		elif age <= 17:
			cohort = "youth"
		elif age <= 45:
			cohort = "adult"
		else:
			cohort = "elder"
			
	var race = String(options.get("race_id", "north"))
	
	var c = CitizenNPCScript.new(c_id, name, gender, age, cohort, race)
	
	# Позиция и поселение
	if options.has("pos"):
		c.pos = options["pos"]
	if options.has("home_pos"):
		c.home_pos = options["home_pos"]
	elif options.has("pos"):
		c.home_pos = options["pos"]
	if options.has("settlement_id"):
		c.settlement_id = options["settlement_id"]
		
	# Профессия
	var job = String(options.get("job_id", ""))
	if job == "":
		if cohort in ["adult", "youth"]:
			job = JOBS[randi() % JOBS.size()]
		elif cohort == "elder":
			job = "elder" if randf() < 0.6 else "craftsman"
		else:
			job = "idle"
	c.job_id = job
	
	# Опыт в профессии
	if job != "idle":
		var base_xp = float(randi_range(15, 60))
		c.experience[job] = base_xp
		c.skills[job] = base_xp
		
	# Инструменты и оружие
	if TOOLS_BY_JOB.has(job):
		c.equipped_tool = (TOOLS_BY_JOB[job] as Dictionary).duplicate()
	if WEAPONS_BY_JOB.has(job):
		c.equipment["weapon"] = WEAPONS_BY_JOB[job]
	if options.has("equipment") and options["equipment"] is Dictionary:
		for k in options["equipment"]:
			c.equipment[k] = options["equipment"][k]
			
	# Личность и причуды
	c.init_personality(c.seed_val)
	c.init_quirks(c.seed_val)
	if options.has("traits") and options["traits"] is Dictionary:
		for k in options["traits"]:
			c.traits[k] = options["traits"][k]
			
	# Модульная внешность (Composer Appearance)
	if options.has("composer_slots") and options["composer_slots"] is Dictionary:
		c.custom_data["composer_slots"] = options["composer_slots"].duplicate()
	else:
		ComposerAssetsScript.generate_npc_appearance(c, true)
		
	return c

## Генерация группы разнообразных NPC
static func generate_batch(count: int, options: Dictionary = {}) -> Array[CitizenNPC]:
	var list: Array[CitizenNPC] = []
	for i in range(count):
		var opt = options.duplicate()
		if not opt.has("gender"):
			opt["gender"] = "m" if (i % 2 == 0) else "f"
		list.append(generate_citizen(opt))
	return list

## Генерация иммигранта/странника, готового вступить в племя
static func generate_immigrant(settlement_id: String, race_id: String = "north") -> CitizenNPC:
	var is_youth = randf() < 0.25
	var c = generate_citizen({
		"settlement_id": settlement_id,
		"race_id": race_id,
		"cohort": "youth" if is_youth else "adult",
		"job_id": "idle"
	})
	c.last_status_reason = "Пришелец из диких земель"
	return c

## Генерация воина / стража с усиленной экипировкой
static func generate_warrior(settlement_id: String, role: String = "warrior") -> CitizenNPC:
	var gender = "m" if randf() < 0.7 else "f"
	var c = generate_citizen({
		"settlement_id": settlement_id,
		"gender": gender,
		"cohort": "adult",
		"job_id": "guard"
	})
	c.traits["bravery"] = randf_range(70.0, 95.0)
	c.strength_level = randi_range(6, 12)
	c.endurance_level = randi_range(6, 12)
	c.agility_level = randi_range(6, 12)
	c.stamina_current = 100.0
	c.stamina_max = 100.0
	
	if role == "archer":
		c.equipment["weapon"] = "hunting_bow"
		c.equipment["body_armor"] = "padded_armor"
	elif role == "spearman":
		c.equipment["weapon"] = "simple_spear"
		c.equipment["body_armor"] = "leather_armor"
		c.equipment["shield"] = "weapons_6"
	else:
		c.equipment["weapon"] = "short_sword"
		c.equipment["body_armor"] = "chainmail"
		c.equipment["helmet"] = "iron_helmet"
		c.equipment["shield"] = "weapons_6"
		
	c.last_status_reason = "Защитник племени"
	return c

## Генерация мудрого старейшины
static func generate_elder(settlement_id: String, gender: String = "") -> CitizenNPC:
	return generate_citizen({
		"settlement_id": settlement_id,
		"gender": gender,
		"cohort": "elder",
		"job_id": "elder",
		"age": randi_range(50, 68)
	})

## Генерация ребёнка
static func generate_child(settlement_id: String, gender: String = "") -> CitizenNPC:
	return generate_citizen({
		"settlement_id": settlement_id,
		"gender": gender,
		"cohort": "child",
		"job_id": "idle",
		"age": randi_range(3, 12)
	})
