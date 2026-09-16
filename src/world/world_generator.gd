class_name WorldGenerator
extends RefCounted

const MAP_WIDTH: int = 160
const MAP_HEIGHT: int = 160

const SEA_LEVEL: float = 0.36
const COAST_LEVEL: float = 0.44
const HILLS_LEVEL: float = 0.67
const MOUNTAIN_LEVEL: float = 0.80
const SNOW_LEVEL: float = 0.90

static func generate_world(seed_str: String) -> Dictionary:
	var seed_hash = hash(seed_str)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_hash
	
	# 1. Шум континентальных массивов
	var continent_noise = FastNoiseLite.new()
	continent_noise.seed = seed_hash
	continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	continent_noise.fractal_octaves = 5
	continent_noise.fractal_lacunarity = 2.0
	continent_noise.fractal_gain = 0.52
	continent_noise.frequency = 0.022
	
	# 2. Шум искажения пространства (Domain Warping для органичных берегов и фьордов)
	var warp_noise_x = FastNoiseLite.new()
	warp_noise_x.seed = seed_hash + 43
	warp_noise_x.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_noise_x.frequency = 0.035
	
	var warp_noise_y = FastNoiseLite.new()
	warp_noise_y.seed = seed_hash + 97
	warp_noise_y.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_noise_y.frequency = 0.035
	
	# 3. Шум горных хребтов (Tectonic Ridge Noise)
	var mountain_noise = FastNoiseLite.new()
	mountain_noise.seed = seed_hash + 211
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_PING_PONG
	mountain_noise.fractal_octaves = 4
	mountain_noise.fractal_ping_pong_strength = 2.2
	mountain_noise.frequency = 0.032
	
	# 4. Шум детализации и микрорельефа
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = seed_hash + 337
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.frequency = 0.065
	
	# 5. Шум влажности и осадков
	var moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = seed_hash + 521
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 4
	moisture_noise.frequency = 0.030
	
	# 6. Шум температурных аномалий
	var temp_noise = FastNoiseLite.new()
	temp_noise.seed = seed_hash + 733
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency = 0.025
	
	var tiles: Array = []
	var land_tiles: Array[Vector2i] = []
	
	for y in range(MAP_HEIGHT):
		var row: Array = []
		for x in range(MAP_WIDTH):
			# Доменное искривление координат
			var wx = x + warp_noise_x.get_noise_2d(x, y) * 12.0
			var wy = y + warp_noise_y.get_noise_2d(x, y) * 12.0
			
			# Базовая континентальная форма
			var base_cont = (continent_noise.get_noise_2d(wx, wy) + 1.0) * 0.5
			var micro = (detail_noise.get_noise_2d(x, y) + 1.0) * 0.5
			
			# Хребтовый шум для вытягивания горных цепей
			var raw_ridge = (mountain_noise.get_noise_2d(wx * 1.1, wy * 1.1) + 1.0) * 0.5
			var ridge_val = pow(raw_ridge, 2.2) * 0.45
			
			# Мягкое океаническое обрамление карты (smoothstep)
			var nx = float(x) / float(MAP_WIDTH)
			var ny = float(y) / float(MAP_HEIGHT)
			var dist_x = 1.0 - pow(abs(nx - 0.5) * 2.0, 3.5)
			var dist_y = 1.0 - pow(abs(ny - 0.5) * 2.0, 3.5)
			var edge_mask = clampf(dist_x * dist_y * 1.25, 0.0, 1.0)
			
			# Итоговая высота
			var combined_h = (base_cont * 0.65 + micro * 0.15 + ridge_val) * edge_mask
			var elevation = clampf(combined_h, 0.0, 1.0)
			
			# Климат: широтный градиент (экватор теплый, полюса холодные) + высотное охлаждение
			var lat = 1.0 - abs(float(y) / float(MAP_HEIGHT) - 0.5) * 2.0
			var temp_anomaly = temp_noise.get_noise_2d(x, y) * 0.12
			var temperature = clampf(lat * 0.88 + 0.08 + temp_anomaly - elevation * 0.45, 0.0, 1.0)
			
			# Влажность: базовый шум + близость к океану - влияние засушливых высот
			var raw_m = (moisture_noise.get_noise_2d(wx, wy) + 1.0) * 0.5
			var ocean_proximity = 1.0 - abs(elevation - COAST_LEVEL) * 1.5
			var moisture = clampf(raw_m * 0.7 + clampf(ocean_proximity * 0.25, 0.0, 0.3) - (elevation - 0.5) * 0.2, 0.0, 1.0)
			
			var is_water = elevation < COAST_LEVEL
			
			var tile = {
				"coord": Vector2i(x, y),
				"elevation": elevation,
				"temperature": temperature,
				"moisture": moisture,
				"biome": BiomeDefinitions.BiomeType.PLAINS,
				"is_water": is_water,
				"is_river": false,
				"resource": null,
				"settlement_id": "",
				"road": false
			}
			row.append(tile)
		tiles.append(row)
		
	# 1. Первичный расчет биомов суши
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var t = tiles[y][x]
			t["biome"] = _determine_biome(t["elevation"], t["temperature"], t["moisture"])
			
	# 2. Настройка красивых прибрежных мелководий (Шельф вокруг всех материков)
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var t = tiles[y][x]
			if t["is_water"]:
				var near_land = false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx = x + dx
						var ny = y + dy
						if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
							if not tiles[ny][nx]["is_water"]:
								near_land = true
								break
					if near_land:
						break
				if near_land:
					t["biome"] = BiomeDefinitions.BiomeType.SHALLOW_COAST
				else:
					t["biome"] = BiomeDefinitions.BiomeType.DEEP_OCEAN
					
	# 3. Сглаживание биомов (Majority filter) для устранения неприятного шума
	_smooth_biomes(tiles)
	
	# Сбор клеток суши
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var t = tiles[y][x]
			if not t["is_water"] and t["elevation"] < MOUNTAIN_LEVEL:
				land_tiles.append(Vector2i(x, y))

				
	# Генерация реалистичных речных сетей
	_generate_rivers(tiles, rng)
	
	# Генерация залежей ресурсов по геологическим правилам
	_generate_resources(tiles, land_tiles, rng)
	
	# Размещение стартовой стоянки игрока и ИИ-племён
	var faction_spawns = _place_tribes(tiles, land_tiles, rng)
	
	return {
		"seed": seed_str,
		"width": MAP_WIDTH,
		"height": MAP_HEIGHT,
		"tiles": tiles,
		"spawns": faction_spawns
	}

static func _determine_biome(elev: float, temp: float, moist: float) -> int:
	if elev < SEA_LEVEL:
		return BiomeDefinitions.BiomeType.DEEP_OCEAN
	if elev < COAST_LEVEL:
		return BiomeDefinitions.BiomeType.SHALLOW_COAST
	if elev >= SNOW_LEVEL or (elev >= MOUNTAIN_LEVEL and temp < 0.24):
		return BiomeDefinitions.BiomeType.SNOW_PEAKS
	if elev >= MOUNTAIN_LEVEL:
		return BiomeDefinitions.BiomeType.MOUNTAINS
	if elev >= HILLS_LEVEL:
		return BiomeDefinitions.BiomeType.HILLS
		
	# Суша: определяем по климатическим поясам
	if temp < 0.22:
		return BiomeDefinitions.BiomeType.TUNDRA
	elif temp < 0.44:
		# Северный умеренный пояс
		if moist > 0.40:
			return BiomeDefinitions.BiomeType.PINE_TAIGA
		elif moist > 0.25:
			return BiomeDefinitions.BiomeType.PLAINS
		else:
			return BiomeDefinitions.BiomeType.TUNDRA
	elif temp < 0.74:
		# Умеренный пояс
		if moist > 0.62:
			return BiomeDefinitions.BiomeType.DECIDUOUS_FOREST
		elif moist > 0.44:
			return BiomeDefinitions.BiomeType.MEADOW
		elif moist > 0.26:
			return BiomeDefinitions.BiomeType.PLAINS
		else:
			return BiomeDefinitions.BiomeType.SAVANNA
	else:
		# Тропический и субтропический пояс
		if moist > 0.60:
			return BiomeDefinitions.BiomeType.JUNGLE
		elif moist > 0.45:
			return BiomeDefinitions.BiomeType.SWAMP if elev < 0.50 else BiomeDefinitions.BiomeType.SAVANNA
		elif moist > 0.24:
			return BiomeDefinitions.BiomeType.SAVANNA
		else:
			return BiomeDefinitions.BiomeType.DESERT

static func _smooth_biomes(tiles: Array) -> void:
	# 1. Устранение одиночных 1-2 клеточных луж и псевдо-водоемов на суше
	for y in range(1, MAP_HEIGHT - 1):
		for x in range(1, MAP_WIDTH - 1):
			var t = tiles[y][x]
			if t["is_water"]:
				var water_neighbors = 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0: continue
						if tiles[y + dy][x + dx]["is_water"]:
							water_neighbors += 1
				# Если у воды меньше 3 водных соседей (одиночная лужа на суше), превращаем в сушу
				if water_neighbors < 3:
					t["is_water"] = false
					t["elevation"] = maxf(t["elevation"], COAST_LEVEL + 0.05)
					t["biome"] = _determine_biome(t["elevation"], t["temperature"], t["moisture"])

	# 2. Сглаживает одиночные выбросы биомов среди соседей
	for y in range(1, MAP_HEIGHT - 1):
		for x in range(1, MAP_WIDTH - 1):
			var current = tiles[y][x]
			if current["is_water"] or current["elevation"] >= HILLS_LEVEL:
				continue
				
			var biome_counts: Dictionary = {}
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n_biome = tiles[y + dy][x + dx]["biome"]
					biome_counts[n_biome] = biome_counts.get(n_biome, 0) + 1
					
			var dominant_biome = current["biome"]
			var max_count = 0
			for b in biome_counts:
				if biome_counts[b] > max_count:
					max_count = biome_counts[b]
					dominant_biome = b
					
			if max_count >= 6 and dominant_biome != current["biome"]:
				current["biome"] = dominant_biome

static func _generate_rivers(_tiles: Array, _rng: RandomNumberGenerator) -> void:
	# Речные псевдо-линии отключены
	return

static func _generate_resources(tiles: Array, land_tiles: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for pos in land_tiles:
		var tile = tiles[pos.y][pos.x]
		var biome = tile["biome"]
		var roll = rng.randf()
		
		# Речные поймы получают плодородную почву
		if tile["is_river"] and roll < 0.40 and tile["resource"] == null:
			tile["resource"] = {"type": "soil", "name": "Плодородная речная пойма", "yield": 5}
			continue
			
		match biome:
			BiomeDefinitions.BiomeType.DECIDUOUS_FOREST:
				if roll < 0.38:
					tile["resource"] = {"type": "wood", "name": "Вековая дубрава", "yield": 5}
				elif roll < 0.60:
					tile["resource"] = {"type": "game", "name": "Охотничьи угодья (олени, кабаны)", "yield": 5}
			BiomeDefinitions.BiomeType.PINE_TAIGA:
				if roll < 0.40:
					tile["resource"] = {"type": "wood", "name": "Корабельный хвойный бор", "yield": 5}
				elif roll < 0.58:
					tile["resource"] = {"type": "game", "name": "Таёжная дичь и пушнина", "yield": 4}
			BiomeDefinitions.BiomeType.JUNGLE:
				if roll < 0.35:
					tile["resource"] = {"type": "wood", "name": "Джунгли красного дерева", "yield": 5}
				elif roll < 0.55:
					tile["resource"] = {"type": "food", "name": "Экзотические плоды и дичь", "yield": 5}
			BiomeDefinitions.BiomeType.HILLS:
				if roll < 0.30:
					tile["resource"] = {"type": "stone", "name": "Выход кремня и сланца", "yield": 4}
				elif roll < 0.50:
					tile["resource"] = {"type": "metal", "name": "Медная жила", "yield": 4}
			BiomeDefinitions.BiomeType.MOUNTAINS:
				if roll < 0.30:
					tile["resource"] = {"type": "stone", "name": "Скалистый гранитный карьер", "yield": 5}
				elif roll < 0.52:
					tile["resource"] = {"type": "metal", "name": "Богатая железная руда", "yield": 5}
			BiomeDefinitions.BiomeType.PLAINS, BiomeDefinitions.BiomeType.MEADOW:
				if roll < 0.26:
					tile["resource"] = {"type": "soil", "name": "Черноземные луга", "yield": 5}
				elif roll < 0.48:
					tile["resource"] = {"type": "game", "name": "Стадо диких бизонов", "yield": 4}
			BiomeDefinitions.BiomeType.SWAMP:
				if roll < 0.35:
					tile["resource"] = {"type": "metal", "name": "Болотная железная руда", "yield": 3}
			BiomeDefinitions.BiomeType.DESERT:
				if roll < 0.15:
					tile["resource"] = {"type": "stone", "name": "Выход песчаника", "yield": 3}
			BiomeDefinitions.BiomeType.TUNDRA:
				if roll < 0.25:
					tile["resource"] = {"type": "game", "name": "Стадо северных оленей", "yield": 4}
					
		# Редкие древние святилища и мегалиты
		if rng.randf() < 0.009 and tile["resource"] == null:
			tile["resource"] = {"type": "relic", "name": "Древний менгир / Руины предков", "yield": 5}

static func _place_tribes(tiles: Array, land_tiles: Array[Vector2i], rng: RandomNumberGenerator) -> Dictionary:
	var spawns: Dictionary = {}
	
	# Оценка пригодности клеток для стартового племени игрока
	var best_score = -1.0
	var player_pos = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
	
	for pos in land_tiles:
		var tile = tiles[pos.y][pos.x]
		if tile["is_water"] or tile["elevation"] >= MOUNTAIN_LEVEL:
			continue
			
		# Проверяем, что вокруг клетки сплошная суша (минимум 18 из 25 клеток вокруг — суша)
		var land_count = 0
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var nx = pos.x + dx
				var ny = pos.y + dy
				if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
					if not tiles[ny][nx]["is_water"]:
						land_count += 1
		if land_count < 18:
			continue
			
		var score = 0.0
		# Река дает огромный бонус к выживанию
		if tile["is_river"]:
			score += 5.0
		# Умеренный климат
		if tile["temperature"] >= 0.38 and tile["temperature"] <= 0.68:
			score += 4.0
		# Плодородные биомы
		if tile["biome"] in [BiomeDefinitions.BiomeType.PLAINS, BiomeDefinitions.BiomeType.MEADOW, BiomeDefinitions.BiomeType.DECIDUOUS_FOREST]:
			score += 5.0
			
		# Проверка разнообразия ресурсов в окрестности 3 клеток
		var has_wood = false
		var has_food = false
		var has_stone = false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var nx = pos.x + dx
				var ny = pos.y + dy
				if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
					var nt = tiles[ny][nx]
					if nt["resource"]:
						if nt["resource"]["type"] == "wood": has_wood = true
						if nt["resource"]["type"] in ["game", "soil", "food"]: has_food = true
						if nt["resource"]["type"] in ["stone", "metal"]: has_stone = true
		if has_wood: score += 3.0
		if has_food: score += 3.5
		if has_stone: score += 2.5
		
		# Центр карты предпочтительнее краев
		var center_dist = pos.distance_to(Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2))
		score += maxf(0.0, 3.0 - center_dist * 0.08)
		
		if score > best_score:
			best_score = score
			player_pos = pos
			
	spawns["player"] = {
		"id": "player_tribe",
		"name": "Племя Первого Костра",
		"pos": player_pos,
		"leader_name": "Вождь Таргон",
		"is_player": true,
		"color": Color(0.2, 0.6, 0.95),
		"culture": "Охотники и созидатели",
		"religion": "Духи Огня и Предков"
	}
	tiles[player_pos.y][player_pos.x]["settlement_id"] = "player_tribe_settlement"
	
	# Генерируем 4 ИИ-племени на гармоничном удалении от игрока
	var ai_configs = [
		{
			"id": "ai_stone_wolves",
			"name": "Племя Каменных Волков",
			"leader_name": "Краг Красный",
			"color": Color(0.9, 0.25, 0.25),
			"culture": "Воинственные налётчики",
			"religion": "Культ Победителя",
			"personality": "aggressive"
		},
		{
			"id": "ai_river_keepers",
			"name": "Хранители Реки",
			"leader_name": "Алард Мирный",
			"color": Color(0.2, 0.8, 0.5),
			"culture": "Рыболовы и торговцы",
			"religion": "Учение о Равновесии",
			"personality": "peaceful"
		},
		{
			"id": "ai_forest_shadows",
			"name": "Тени Леса",
			"leader_name": "Селина Мудрая",
			"color": Color(0.75, 0.45, 0.85),
			"culture": "Лесные шаманы и охотники",
			"religion": "Духи Мира",
			"personality": "diplomatic"
		},
		{
			"id": "ai_sun_worshippers",
			"name": "Дети Солнца",
			"leader_name": "Жрец Ирам",
			"color": Color(0.95, 0.75, 0.2),
			"culture": "Солнечные земледельцы",
			"religion": "Соляризм",
			"personality": "religious"
		}
	]
	
	spawns["ai"] = []
	for cfg in ai_configs:
		var found_pos = Vector2i(-1, -1)
		var best_cand_score = -1.0
		
		for pos in land_tiles:
			var tile = tiles[pos.y][pos.x]
			if tile["is_water"] or tile["settlement_id"] != "" or tile["elevation"] >= MOUNTAIN_LEVEL:
				continue
			var d = pos.distance_to(player_pos)
			if d >= 26.0 and d <= 70.0:
				var too_close = false
				for existing in spawns["ai"]:
					if pos.distance_to(existing["pos"]) < 20.0:
						too_close = true
						break
				if not too_close:
					var cand_score = 10.0 - abs(d - 40.0) * 0.2
					if tile["is_river"]: cand_score += 2.0
					if cand_score > best_cand_score:
						best_cand_score = cand_score
						found_pos = pos
						
		if found_pos == Vector2i(-1, -1):
			found_pos = land_tiles[rng.randi() % land_tiles.size()]
			
		cfg["pos"] = found_pos
		cfg["is_player"] = false
		tiles[found_pos.y][found_pos.x]["settlement_id"] = cfg["id"] + "_settlement"
		spawns["ai"].append(cfg)
		
	return spawns
