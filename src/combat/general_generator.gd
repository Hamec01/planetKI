class_name GeneralGenerator
extends RefCounted

static func create_brock() -> Dictionary:
	return {
		"id": "gen_brock",
		"name": "Брок Громовержец",
		"title": "Сокрушитель врагов",
		"age": 32,
		"bravery": 95,
		"intellect": 40,
		"cunning": 30,
		"discipline": 55,
		"charisma": 90,
		"logistics": 45,
		"prestige": 80,
		"traits": ["Бесстрашный", "Прямолинейный", "Любимец воинов"],
		"quote": "«Холмы? Значит, им будет дальше падать.»",
		"color": Color(0.9, 0.3, 0.2)
	}

static func create_gwen() -> Dictionary:
	return {
		"id": "gen_gwen",
		"name": "Гвен Хитрый Лис",
		"title": "Хозяйка засад",
		"age": 28,
		"bravery": 60,
		"intellect": 90,
		"cunning": 95,
		"discipline": 80,
		"charisma": 65,
		"logistics": 85,
		"prestige": 75,
		"traits": ["Мастер засад", "Разведчица", "Хладнокровная"],
		"quote": "«Побеждает не тот, кто громче кричит, а тот, кто бьёт из тени.»",
		"color": Color(0.2, 0.7, 0.4)
	}

static func generate_random_general(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
		
	var first_names = ["Торн", "Кормак", "Драган", "Варг", "Мира", "Хельга", "Яромир", "Бран", "Рагнар", "Тира"]
	var nick_names = ["Быстроногий", "Скала", "Острый Глаз", "Железный Кулак", "Седой", "Бесшумный", "Смелый", "Вещий"]
	
	var name = first_names[rng.randi() % first_names.size()] + " " + nick_names[rng.randi() % nick_names.size()]
	
	return {
		"id": "gen_" + str(rng.randi() % 100000),
		"name": name,
		"title": "Военачальник рода",
		"age": rng.randi_range(22, 50),
		"bravery": rng.randi_range(40, 90),
		"intellect": rng.randi_range(40, 85),
		"cunning": rng.randi_range(30, 90),
		"discipline": rng.randi_range(40, 85),
		"charisma": rng.randi_range(40, 90),
		"logistics": rng.randi_range(40, 80),
		"prestige": rng.randi_range(20, 60),
		"traits": ["Опытный следопыт"],
		"quote": "«За честь нашего костра и память предков!»",
		"color": Color(0.6, 0.6, 0.8)
	}
