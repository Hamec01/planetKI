class_name WildlifeManager
extends RefCounted

const WildAnimalScript = preload("res://src/simulation/wild_animal.gd")

var animals: Dictionary = {} # animal_id -> WildAnimal
var carcasses: Dictionary = {} # carcass_id -> Dictionary
var is_initialized: bool = false
var respawn_timer: float = 0.0
const RESPAWN_INTERVAL: float = 30.0 # Проверка восполнения фауны раз в 30 с

# Максимальные популяции по категориям
const MAX_TOTAL_ANIMALS: int = 36
const MAX_HUNTERS_PER_GROUP: int = 3

var _next_animal_id: int = 1
var _next_carcass_id: int = 1
var hunt_groups: Dictionary = {} # animal_id -> Array[String]

func init_wildlife(world_data: Dictionary, nav_grid) -> void:
	animals.clear()
	carcasses.clear()
	hunt_groups.clear()
	_next_animal_id = 1
	_next_carcass_id = 1
	
	if not world_data.has("tiles") or not nav_grid:
		is_initialized = true
		return
		
	var tiles = world_data["tiles"]
	var width = world_data.get("width", 160)
	var height = world_data.get("height", 160)
	
	var forest_tiles: Array[Vector2i] = []
	var plains_tiles: Array[Vector2i] = []
	var water_near_tiles: Array[Vector2i] = []
	var all_walkable_tiles: Array[Vector2i] = []
	
	for y in range(4, height - 4, 3):
		for x in range(4, width - 4, 3):
			var tile = tiles[y][x]
			var biome = tile.get("biome", -1)
			var coord = Vector2i(x, y)
			
			if not nav_grid.is_tile_walkable(coord):
				continue
				
			all_walkable_tiles.append(coord)
			
			if biome in [BiomeDefinitions.BiomeType.DECIDUOUS_FOREST, BiomeDefinitions.BiomeType.PINE_TAIGA, BiomeDefinitions.BiomeType.SWAMP]:
				forest_tiles.append(coord)
			elif biome in [BiomeDefinitions.BiomeType.PLAINS, BiomeDefinitions.BiomeType.MEADOW, BiomeDefinitions.BiomeType.SAVANNA]:
				plains_tiles.append(coord)
				
			# Проверка близости к воде для уток
			var has_water_neighbor = false
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if nav_grid.is_water_tile(coord + Vector2i(dx, dy)):
						has_water_neighbor = true
						break
				if has_water_neighbor:
					break
			if has_water_neighbor:
				water_near_tiles.append(coord)
				
	forest_tiles.shuffle()
	plains_tiles.shuffle()
	water_near_tiles.shuffle()
	all_walkable_tiles.shuffle()
	
	if forest_tiles.is_empty(): forest_tiles = all_walkable_tiles.duplicate()
	if plains_tiles.is_empty(): plains_tiles = all_walkable_tiles.duplicate()
	if water_near_tiles.is_empty(): water_near_tiles = all_walkable_tiles.duplicate()
	
	# Определяем позицию поселения игрока для создания богатой местной фауны
	var player_spawn: Vector2i = Vector2i(width / 2, height / 2)
	if world_data.has("spawns") and world_data["spawns"] is Dictionary and world_data["spawns"].has("player"):
		var p_spawn = world_data["spawns"]["player"]
		if p_spawn is Dictionary and p_spawn.has("pos"):
			var raw_p = p_spawn["pos"]
			if raw_p is Vector2i:
				player_spawn = raw_p
			elif raw_p is Array and raw_p.size() >= 2:
				player_spawn = Vector2i(int(raw_p[0]), int(raw_p[1]))
			elif raw_p is String:
				var clean = raw_p.replace("(", "").replace(")", "").replace(" ", "")
				var parts = clean.split(",")
				if parts.size() >= 2:
					player_spawn = Vector2i(int(parts[0]), int(parts[1]))
		
	var near_plains: Array[Vector2i] = []
	var near_forest: Array[Vector2i] = []
	var near_water: Array[Vector2i] = []
	
	for c in plains_tiles:
		var d = float(abs(c.x - player_spawn.x) + abs(c.y - player_spawn.y))
		if d >= 7.0 and d <= 26.0:
			near_plains.append(c)
	for c in forest_tiles:
		var d = float(abs(c.x - player_spawn.x) + abs(c.y - player_spawn.y))
		if d >= 9.0 and d <= 30.0:
			near_forest.append(c)
	for c in water_near_tiles:
		var d = float(abs(c.x - player_spawn.x) + abs(c.y - player_spawn.y))
		if d >= 6.0 and d <= 28.0:
			near_water.append(c)
			
	near_plains.shuffle()
	near_forest.shuffle()
	near_water.shuffle()
	
	var use_near_plains = near_plains if not near_plains.is_empty() else plains_tiles
	var use_near_forest = near_forest if not near_forest.is_empty() else forest_tiles
	var use_near_water = near_water if not near_water.is_empty() else water_near_tiles
	
	# --- ГАРАНТИРОВАННАЯ МЕСТНАЯ ФАУНА ВОКРУГ СТОЯНКИ ИГРОКА ---
	# 1. Зайцы на ближайших лугах (быстро замечаются охотником)
	_spawn_group("hare_brown", use_near_plains, nav_grid, 2, "hare_leveret", 2)
	# 2. Стадо оленей в соседней роще
	_spawn_family("deer_stag", "deer_doe", "deer_fawn", use_near_forest, nav_grid, 1)
	# 3. Кабаны неподалеку
	_spawn_family("boar_male", "boar_female", "boar_piglet", use_near_forest, nav_grid, 1)
	# 4. Утки на ближайшем озере/реке
	_spawn_group("duck", use_near_water, nav_grid, 2, "drake", 2)
	# 5. Стая волков в окрестных чащах
	_spawn_family("wolf_grey", "wolf_dark", "wolf_pup", use_near_forest, nav_grid, 1)
	
	# --- ДИКАЯ ФАУНА ПО ВСЕМУ ОСТАЛЬНОМУ МИРУ ---
	_spawn_group("hare_brown", plains_tiles, nav_grid, 3, "hare_leveret", 2)
	_spawn_group("hare_white", forest_tiles, nav_grid, 3, "hare_leveret", 1)
	_spawn_family("deer_stag", "deer_doe", "deer_fawn", forest_tiles, nav_grid, 2)
	_spawn_family("moose_bull", "moose_cow", "moose_calf", forest_tiles, nav_grid, 2)
	_spawn_family("boar_male", "boar_female", "boar_piglet", forest_tiles, nav_grid, 2)
	_spawn_single("bear_brown", forest_tiles, nav_grid, 2)
	_spawn_family("bear_dark", "bear_dark", "bear_cub", forest_tiles, nav_grid, 1)
	_spawn_family("wolf_grey", "wolf_dark", "wolf_pup", forest_tiles, nav_grid, 1)
	_spawn_family("fox_adult", "fox_adult", "fox_kit", plains_tiles, nav_grid, 2)
	_spawn_single("lynx_adult", forest_tiles, nav_grid, 2)
	_spawn_single("badger_adult", plains_tiles, nav_grid, 2)
	_spawn_group("duck", water_near_tiles, nav_grid, 2, "drake", 2)
	
	is_initialized = true
	print("WildlifeManager: Initialized with %d animals across 24 species/variants (including local habitat around player)." % animals.size())

func _spawn_single(type_id: String, tiles_pool: Array[Vector2i], nav_grid, count: int) -> void:
	for i in range(count):
		if tiles_pool.is_empty(): return
		var coord = tiles_pool.pop_back()
		var pos = nav_grid.tile_to_world_center(coord) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		var a_id = "%s_%d" % [type_id, _next_animal_id]
		_next_animal_id += 1
		var animal = WildAnimalScript.new(a_id, type_id, pos)
		animals[a_id] = animal

func _spawn_group(type_id: String, tiles_pool: Array[Vector2i], nav_grid, count: int, extra_type: String = "", extra_count: int = 0) -> void:
	for i in range(count):
		if tiles_pool.is_empty(): return
		var coord = tiles_pool.pop_back()
		var pos = nav_grid.tile_to_world_center(coord) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		var a_id = "%s_%d" % [type_id, _next_animal_id]
		_next_animal_id += 1
		var animal = WildAnimalScript.new(a_id, type_id, pos)
		animals[a_id] = animal
		
		# Детёныши или спутники рядом
		for j in range(extra_count):
			var c_id = "%s_%d" % [extra_type, _next_animal_id]
			_next_animal_id += 1
			var c_pos = pos + Vector2(randf_range(-18, 18), randf_range(-18, 18))
			var child = WildAnimalScript.new(c_id, extra_type, c_pos)
			child.parent_id = a_id
			animals[c_id] = child

func _spawn_family(male_type: String, female_type: String, child_type: String, tiles_pool: Array[Vector2i], nav_grid, count: int) -> void:
	for i in range(count):
		if tiles_pool.is_empty(): return
		var coord = tiles_pool.pop_back()
		var pos = nav_grid.tile_to_world_center(coord)
		
		# Мать / лидер
		var m_id = "%s_%d" % [female_type, _next_animal_id]
		_next_animal_id += 1
		var female = WildAnimalScript.new(m_id, female_type, pos)
		animals[m_id] = female
		
		# Самец рядом
		var s_id = "%s_%d" % [male_type, _next_animal_id]
		_next_animal_id += 1
		var male = WildAnimalScript.new(s_id, male_type, pos + Vector2(randf_range(-22, 22), randf_range(-22, 22)))
		animals[s_id] = male
		
		# Детёныш рядом, привязанный к матери
		if child_type != "":
			var c_id = "%s_%d" % [child_type, _next_animal_id]
			_next_animal_id += 1
			var child = WildAnimalScript.new(c_id, child_type, pos + Vector2(randf_range(-14, 14), randf_range(-14, 14)))
			child.parent_id = m_id
			animals[c_id] = child

func update(delta: float, nav_grid, threat_positions: Array = []) -> void:
	# 1. Обновление поведения всех живых животных
	for a_id in animals.keys():
		var animal = animals[a_id]
		if animal.is_alive():
			var parent_obj = animals.get(animal.parent_id, null)
			animal.update(delta, nav_grid, threat_positions, parent_obj)
		else:
			create_carcass_from_animal(animal)
			animals.erase(a_id)
			
	# 2. Обновление туш (таймер распада)
	for c_id in carcasses.keys():
		var carcass = carcasses[c_id]
		carcass["decay_timer"] -= delta
		if carcass["decay_timer"] <= 0.0 or carcass["meat_remaining"] <= 0.0:
			carcasses.erase(c_id)
			
	# 3. Восполнение популяций в диких зонах со временем
	respawn_timer += delta
	if respawn_timer >= RESPAWN_INTERVAL:
		respawn_timer = 0.0
		_check_and_replenish_wildlife(nav_grid)

func _check_and_replenish_wildlife(nav_grid) -> void:
	if animals.size() >= MAX_TOTAL_ANIMALS or not nav_grid:
		return
		
	# Выбираем случайную дикую клетку вдали от центра
	var test_coord = Vector2i(randi_range(12, 148), randi_range(12, 148))
	var walk_coord = nav_grid.find_random_walkable_nearby(test_coord, 6)
	if not nav_grid.is_tile_walkable(walk_coord):
		return
		
	var pool = ["hare_brown", "hare_white", "deer_doe", "fox_adult", "duck", "badger_adult"]
	var picked = pool[randi() % pool.size()]
	var pos = nav_grid.tile_to_world_center(walk_coord)
	var a_id = "%s_%d" % [picked, _next_animal_id]
	_next_animal_id += 1
	var animal = WildAnimalScript.new(a_id, picked, pos)
	animals[a_id] = animal

func find_nearest_hunt_target(from_pos: Vector2, max_radius: float, hunter_id: String) -> WildAnimal:
	var nearest_animal: WildAnimal = null
	var min_dist: float = max_radius
	
	# Приоритет 1: Взрослая дичь (олени, лоси, кабаны, зайцы)
	for animal in animals.values():
		if not animal.is_alive():
			continue
		if not can_join_hunt_group(animal.id, hunter_id):
			continue
		if animal.is_child: # Детёнышей не берем в приоритет
			continue
		var d = from_pos.distance_to(animal.pos)
		if d < min_dist:
			min_dist = d
			nearest_animal = animal
			
	if nearest_animal != null:
		return nearest_animal
		
	# Приоритет 2: Любая доступная цель, если взрослой нет
	for animal in animals.values():
		if not animal.is_alive():
			continue
		if not can_join_hunt_group(animal.id, hunter_id):
			continue
		var d = from_pos.distance_to(animal.pos)
		if d < min_dist:
			min_dist = d
			nearest_animal = animal
			
	return nearest_animal

func find_nearest_carcass(from_pos: Vector2, max_radius: float, hunter_id: String) -> Dictionary:
	var nearest_carcass: Dictionary = {}
	var min_dist: float = max_radius
	
	for c_id in carcasses.keys():
		var c = carcasses[c_id]
		if c["meat_remaining"] <= 0.0:
			continue
		if c["reserved_by"] != "" and c["reserved_by"] != hunter_id:
			continue
		var c_pos = c.get("pos", Vector2.ZERO)
		if c_pos is String:
			var parsed = str_to_var(c_pos)
			c_pos = parsed if parsed is Vector2 else Vector2.ZERO
			c["pos"] = c_pos
		elif c_pos is Array:
			c_pos = Vector2(float(c_pos[0]), float(c_pos[1]))
			c["pos"] = c_pos
		var d = from_pos.distance_to(c_pos)
		if d < min_dist:
			min_dist = d
			nearest_carcass = c
			
	return nearest_carcass

func reserve_animal(animal_id: String, citizen_id: String) -> bool:
	if not animals.has(animal_id):
		return false
	var a = animals[animal_id]
	if a.reserved_by == "" or a.reserved_by == citizen_id:
		a.reserved_by = citizen_id
		return true
	return false

func release_animal(animal_id: String, citizen_id: String) -> void:
	if animals.has(animal_id):
		var a = animals[animal_id]
		if a.reserved_by == citizen_id:
			a.reserved_by = ""

func can_join_hunt_group(animal_id: String, citizen_id: String) -> bool:
	if not animals.has(animal_id):
		return false
	var group: Array = hunt_groups.get(animal_id, [])
	if group.has(citizen_id):
		return true
	var animal = animals[animal_id]
	if group.is_empty() and animal.reserved_by != "" and animal.reserved_by != citizen_id:
		return false
	return group.size() < MAX_HUNTERS_PER_GROUP

func join_hunt_group(animal_id: String, citizen_id: String) -> bool:
	if not can_join_hunt_group(animal_id, citizen_id):
		return false
	var group: Array = hunt_groups.get(animal_id, [])
	if not group.has(citizen_id):
		group.append(citizen_id)
		hunt_groups[animal_id] = group
	animals[animal_id].reserved_by = "hunt_group:%s" % animal_id
	return true

func leave_hunt_group(animal_id: String, citizen_id: String) -> void:
	if not hunt_groups.has(animal_id):
		return
	var group: Array = hunt_groups[animal_id]
	group.erase(citizen_id)
	if group.is_empty():
		hunt_groups.erase(animal_id)
		if animals.has(animal_id):
			animals[animal_id].reserved_by = ""
	else:
		hunt_groups[animal_id] = group

func find_group_carcass_for_hunter(citizen_id: String) -> Dictionary:
	for carcass in carcasses.values():
		if carcass.get("assigned_hunters", []).has(citizen_id) and carcass.get("meat_remaining", 0.0) > 0.0:
			return carcass
	return {}

func reserve_carcass(carcass_id: String, citizen_id: String) -> bool:
	if not carcasses.has(carcass_id):
		return false
	var c = carcasses[carcass_id]
	if c["reserved_by"] == "" or c["reserved_by"] == citizen_id:
		c["reserved_by"] = citizen_id
		return true
	return false

func release_carcass(carcass_id: String, citizen_id: String) -> void:
	if carcasses.has(carcass_id):
		var c = carcasses[carcass_id]
		if c["reserved_by"] == citizen_id:
			c["reserved_by"] = ""

func create_carcass_from_animal(animal: WildAnimal) -> Dictionary:
	var c_id = "carcass_%d" % _next_carcass_id
	_next_carcass_id += 1
	var assigned_hunters: Array = hunt_groups.get(animal.id, []).duplicate()
	if assigned_hunters.is_empty() and animal.reserved_by != "" and not animal.reserved_by.begins_with("hunt_group:"):
		assigned_hunters.append(animal.reserved_by)
	hunt_groups.erase(animal.id)
	var carcass = {
		"id": c_id,
		"species": animal.species,
		"type_id": animal.type_id,
		"pos": animal.pos,
		"coord": Vector2i(int(animal.pos.x / 32.0), int(animal.pos.y / 32.0)),
		"meat_remaining": animal.meat_yield,
		"max_meat": animal.meat_yield,
		"extra_material": animal.extra_material,
		"extra_material_count": animal.extra_material_count,
		"extra_remaining": animal.extra_material_count,
		"reserved_by": animal.reserved_by,
		"assigned_hunters": assigned_hunters,
		"decay_timer": 300.0 # 5 минут игрового времени
	}
	carcasses[c_id] = carcass
	return carcass

func harvest_carcass(carcass_id: String, max_amount: float) -> Dictionary:
	if not carcasses.has(carcass_id):
		return {"meat": 0.0, "material": "", "material_count": 0}
	var c = carcasses[carcass_id]
	var take_meat = min(max_amount, c["meat_remaining"])
	c["meat_remaining"] -= take_meat
	
	# Забираем сопутствующий материал (шкурка/мех/перья)
	var mat = c.get("extra_material", "")
	var mat_cnt = c.get("extra_remaining", 0)
	c["extra_remaining"] = 0
	
	if c["meat_remaining"] <= 0.0:
		carcasses.erase(carcass_id)
		
	return {
		"meat": take_meat,
		"material": mat,
		"material_count": mat_cnt
	}

func serialize() -> Dictionary:
	var anim_list = []
	for a in animals.values():
		anim_list.append(a.serialize())
	var carcass_list = []
	for c in carcasses.values():
		var c_dict = c.duplicate()
		var c_pos = c.get("pos", Vector2.ZERO)
		if c_pos is Vector2:
			c_dict["pos_x"] = c_pos.x
			c_dict["pos_y"] = c_pos.y
		carcass_list.append(c_dict)
	return {
		"animals": anim_list,
		"carcasses": carcass_list,
		"next_animal_id": _next_animal_id,
		"next_carcass_id": _next_carcass_id,
		"respawn_timer": respawn_timer,
		"hunt_groups": hunt_groups
	}

func deserialize(data: Dictionary) -> void:
	animals.clear()
	carcasses.clear()
	hunt_groups = data.get("hunt_groups", {}).duplicate()
	_next_animal_id = data.get("next_animal_id", 1)
	_next_carcass_id = data.get("next_carcass_id", 1)
	respawn_timer = data.get("respawn_timer", 0.0)
	
	var anim_list = data.get("animals", [])
	for a_data in anim_list:
		var animal = WildAnimalScript.new()
		animal.deserialize(a_data)
		animals[animal.id] = animal
		
	var carcass_list = data.get("carcasses", [])
	for c_data in carcass_list:
		var c_dict = c_data.duplicate()
		if c_dict.has("pos_x") and c_dict.has("pos_y"):
			c_dict["pos"] = Vector2(float(c_dict["pos_x"]), float(c_dict["pos_y"]))
		elif c_dict.get("pos") is String:
			var parsed = str_to_var(c_dict["pos"])
			c_dict["pos"] = parsed if parsed is Vector2 else Vector2.ZERO
		elif c_dict.get("pos") is Array:
			c_dict["pos"] = Vector2(float(c_dict["pos"][0]), float(c_dict["pos"][1]))
		carcasses[c_dict["id"]] = c_dict
	is_initialized = true
