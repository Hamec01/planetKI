class_name StarSystemGenerator
extends RefCounted

static func generate_system(seed_str: String) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(seed_str + "_star_system")
	
	var star_types = [
		{"type": "Жёлтый карлик (G-класс)", "color": Color(1.0, 0.95, 0.4), "stability": "Высокая", "lum": 1.0},
		{"type": "Оранжевый карлик (K-класс)", "color": Color(1.0, 0.65, 0.2), "stability": "Очень высокая", "lum": 0.6},
		{"type": "Красный карлик (M-класс)", "color": Color(1.0, 0.35, 0.2), "stability": "Умеренная (вспышечная)", "lum": 0.15},
		{"type": "Бело-жёлтая звезда (F-класс)", "color": Color(0.9, 0.95, 1.0), "stability": "Стабильная", "lum": 2.2}
	]
	var star = star_types[rng.randi() % star_types.size()]
	
	var star_names = ["Аурелия", "Гелиос", "Вега-Прим", "Альтаир", "Кеплер-X", "Эридан", "Сириус-Б", "Тау-Сети", "Нова-Россь"]
	var star_name = star_names[rng.randi() % star_names.size()]
	
	var planet_names = ["Аурелион", "Нова", "Гайя", "Терра-Прима", "Элизиум", "Авалон", "Аркадия", "Таллия", "Орион-4"]
	var home_planet_name = planet_names[rng.randi() % planet_names.size()]
	
	var moons_count = rng.randi_range(1, 3)
	var moon_names = ["Лира", "Кед", "Фобос", "Ори", "Селена", "Ио", "Калисто", "Нимфа"]
	var moons: Array[String] = []
	for i in range(moons_count):
		moons.append(moon_names[(rng.randi() + i) % moon_names.size()])
		
	var planets: Array[Dictionary] = []
	var total_planets = rng.randi_range(4, 7)
	var home_index = rng.randi_range(1, 2)
	
	for i in range(total_planets):
		if i == home_index:
			planets.append({
				"name": home_planet_name,
				"type": "Пригодный мир (Стартовая планета)",
				"habitable": true,
				"moons": moons,
				"distance_au": 0.8 + i * 0.4
			})
		elif i < home_index:
			planets.append({
				"name": "Внутренняя-" + str(i + 1),
				"type": "Раскалённый каменный мир",
				"habitable": false,
				"moons": [],
				"distance_au": 0.3 + i * 0.3
			})
		else:
			var p_type = "Холодный океанический мир" if i == home_index + 1 else "Газовый гигант"
			planets.append({
				"name": "Внешняя-" + str(i + 1),
				"type": p_type,
				"habitable": false,
				"moons": ["Спутник-" + str(i)],
				"distance_au": 1.5 + (i - home_index) * 1.2
			})
			
	return {
		"star_name": star_name,
		"star_type": star["type"],
		"star_color": star["color"],
		"star_lum": star["lum"],
		"star_stability": star["stability"],
		"home_planet_name": home_planet_name,
		"moons": moons,
		"planets": planets,
		"asteroid_belts": rng.randi_range(1, 2)
	}
