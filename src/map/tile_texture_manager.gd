class_name TileTextureManager
extends RefCounted

const BiomeType = BiomeDefinitions.BiomeType

static var base_textures: Dictionary = {}
static var nature_sprites: Dictionary = {}
static var is_loaded: bool = false

static func load_all_textures() -> void:
	if is_loaded:
		return
		
	# 1. Базовые текстуры поверхности (высокое качество, бесшовные)
	base_textures[BiomeType.DEEP_OCEAN] = _load_dir("res://Assets/clean_tiles/ocean_deep")
	base_textures[BiomeType.SHALLOW_COAST] = _load_dir("res://Assets/clean_tiles/ocean_shallow")
	base_textures[BiomeType.PLAINS] = _load_dir("res://Assets/clean_tiles/plains")
	base_textures[BiomeType.MEADOW] = _load_dir("res://Assets/clean_tiles/meadow")
	base_textures[BiomeType.DECIDUOUS_FOREST] = _load_dir("res://Assets/clean_tiles/plains")
	base_textures[BiomeType.PINE_TAIGA] = _load_dir("res://Assets/clean_tiles/plains")
	base_textures[BiomeType.JUNGLE] = _load_dir("res://Assets/clean_tiles/meadow")
	base_textures[BiomeType.SAVANNA] = _load_dir("res://Assets/clean_tiles/plains")
	base_textures[BiomeType.DESERT] = _load_dir("res://Assets/clean_tiles/sand")
	base_textures[BiomeType.SWAMP] = _load_dir("res://Assets/clean_tiles/dirt")
	base_textures[BiomeType.HILLS] = _load_dir("res://Assets/clean_tiles/dirt")
	base_textures[BiomeType.MOUNTAINS] = _load_dir("res://Assets/clean_tiles/dirt")
	base_textures[BiomeType.SNOW_PEAKS] = _load_dir("res://Assets/clean_tiles/snow")
	base_textures[BiomeType.TUNDRA] = _load_dir("res://Assets/clean_tiles/snow")
	
	# 2. Чистые отдельные спрайты деревьев, скал и кустарников
	nature_sprites["tree_oak_green"] = _load_single("res://Assets/nature/tree_oak_green.png")
	nature_sprites["tree_pine_dark"] = _load_single("res://Assets/nature/tree_pine_dark.png")
	nature_sprites["tree_pine_small"] = _load_single("res://Assets/nature/tree_pine_small.png")
	nature_sprites["tree_snow"] = _load_single("res://Assets/nature/tree_snow.png")
	nature_sprites["tree_autumn_gold"] = _load_single("res://Assets/nature/tree_autumn_gold.png")
	nature_sprites["tree_autumn_red"] = _load_single("res://Assets/nature/tree_autumn_red.png")
	nature_sprites["tree_berry"] = _load_single("res://Assets/nature/tree_berry.png")
	nature_sprites["rock_mountain"] = _load_single("res://Assets/nature/rock_mountain.png")
	nature_sprites["rock_boulder"] = _load_single("res://Assets/nature/rock_boulder.png")
	nature_sprites["bush_green"] = _load_single("res://Assets/nature/bush_green.png")
	nature_sprites["bush_flowers"] = _load_single("res://Assets/nature/bush_flowers.png")
	nature_sprites["bush_snow"] = _load_single("res://Assets/nature/bush_snow.png")
	nature_sprites["bush_gold"] = _load_single("res://Assets/nature/bush_gold.png")
	
	is_loaded = true

static func _load_single(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func _load_dir(dir_path: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".png") and not file_name.ends_with(".import"):
				var full_p = dir_path + "/" + file_name
				if ResourceLoader.exists(full_p):
					var tex = load(full_p)
					if tex:
						result.append(tex)
			file_name = dir.get_next()
	return result

static func get_tile_texture(biome: int, coord: Vector2i, _is_river: bool = false) -> Texture2D:
	load_all_textures()
	var list: Array = base_textures.get(biome, [])
	if list.is_empty():
		list = base_textures.get(BiomeType.PLAINS, [])
	if list.is_empty():
		return null
	var seed_val = (coord.x * 73856093) ^ (coord.y * 19349663)
	var rand_idx = abs(seed_val) % list.size()
	return list[rand_idx]

static func get_nature_overlay(biome: int, coord: Vector2i) -> Texture2D:
	load_all_textures()
	var seed_val = (coord.x * 374761393) ^ (coord.y * 668265263)
	var rand_idx = abs(seed_val)
	
	match biome:
		BiomeType.DECIDUOUS_FOREST:
			var pool = ["tree_oak_green", "tree_berry", "tree_autumn_red"]
			return nature_sprites.get(pool[rand_idx % pool.size()], null)
			
		BiomeType.PINE_TAIGA:
			var pool = ["tree_pine_dark", "tree_pine_small"]
			return nature_sprites.get(pool[rand_idx % pool.size()], null)
			
		BiomeType.JUNGLE:
			var pool = ["tree_berry", "tree_oak_green"]
			return nature_sprites.get(pool[rand_idx % pool.size()], null)
			
		BiomeType.SAVANNA:
			# В саванне деревья редкие (на 35% клеток)
			if rand_idx % 100 < 35:
				return nature_sprites.get("tree_autumn_gold", null)
			elif rand_idx % 100 < 60:
				return nature_sprites.get("bush_gold", null)
			return null
			
		BiomeType.HILLS:
			# Холмистые гряды и валуны
			if rand_idx % 100 < 65:
				return nature_sprites.get("rock_boulder", null)
			return null
			
		BiomeType.MOUNTAINS:
			# Скалистые горные вершины
			return nature_sprites.get("rock_mountain", null)
			
		BiomeType.SNOW_PEAKS:
			# Заснеженные скалы
			return nature_sprites.get("rock_mountain", null)
			
		BiomeType.TUNDRA:
			# Заснеженные деревья и сугробы
			if rand_idx % 100 < 45:
				return nature_sprites.get("tree_snow", null)
			elif rand_idx % 100 < 70:
				return nature_sprites.get("bush_snow", null)
			return null
			
		BiomeType.MEADOW:
			# На лугах изредка встречаются цветочные кусты
			if rand_idx % 100 < 25:
				return nature_sprites.get("bush_flowers", null)
			return null
			
		BiomeType.PLAINS:
			# На равнинах изредка зеленые кустики
			if rand_idx % 100 < 15:
				return nature_sprites.get("bush_green", null)
			return null
			
		_:
			return null

