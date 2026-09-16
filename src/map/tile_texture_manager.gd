class_name TileTextureManager
extends RefCounted

const BiomeType = BiomeDefinitions.BiomeType

static var base_textures: Dictionary = {}
static var overlay_textures: Dictionary = {} # "biome_folder/mask_name" -> Texture2D
static var river_textures: Dictionary = {} # "river_name" -> Texture2D
static var nature_sprites: Dictionary = {}
static var is_loaded: bool = false

static func load_all_textures() -> void:
	if is_loaded:
		return
		
	# 1. Загрузка бесшовных базовых текстур нового атласа
	_load_base_biome(BiomeType.DEEP_OCEAN, ["res://Assets/terrain_atlas/base/water_deep.png", "res://Assets/clean_tiles/ocean_deep"])
	_load_base_biome(BiomeType.SHALLOW_COAST, ["res://Assets/terrain_atlas/base/water_shallow.png", "res://Assets/clean_tiles/ocean_shallow"])
	_load_base_biome(BiomeType.PLAINS, ["res://Assets/terrain_atlas/base/plains.png", "res://Assets/clean_tiles/plains"])
	_load_base_biome(BiomeType.MEADOW, ["res://Assets/terrain_atlas/base/meadow.png", "res://Assets/clean_tiles/meadow"])
	_load_base_biome(BiomeType.DECIDUOUS_FOREST, ["res://Assets/terrain_atlas/base/plains.png", "res://Assets/clean_tiles/plains"])
	_load_base_biome(BiomeType.PINE_TAIGA, ["res://Assets/terrain_atlas/base/plains.png", "res://Assets/clean_tiles/plains"])
	_load_base_biome(BiomeType.JUNGLE, ["res://Assets/terrain_atlas/base/meadow.png", "res://Assets/clean_tiles/meadow"])
	_load_base_biome(BiomeType.SAVANNA, ["res://Assets/terrain_atlas/base/savanna.png", "res://Assets/clean_tiles/plains"])
	_load_base_biome(BiomeType.DESERT, ["res://Assets/terrain_atlas/base/sand.png", "res://Assets/clean_tiles/sand"])
	_load_base_biome(BiomeType.SWAMP, ["res://Assets/terrain_atlas/base/swamp.png", "res://Assets/clean_tiles/dirt"])
	_load_base_biome(BiomeType.HILLS, ["res://Assets/terrain_atlas/base/dirt.png", "res://Assets/clean_tiles/dirt"])
	_load_base_biome(BiomeType.MOUNTAINS, ["res://Assets/terrain_atlas/base/mountains.png", "res://Assets/clean_tiles/dirt"])
	_load_base_biome(BiomeType.SNOW_PEAKS, ["res://Assets/terrain_atlas/base/snow_peaks.png", "res://Assets/clean_tiles/snow"])
	_load_base_biome(BiomeType.TUNDRA, ["res://Assets/terrain_atlas/base/snow.png", "res://Assets/clean_tiles/snow"])
	
	# 2. Загрузка оверлеев переходов между биомами
	_load_all_overlays()
	
	# 3. Загрузка процедурных речных коннекторов
	_load_all_rivers()
	
	# 4. Чистые отдельные спрайты деревьев, скал и кустарников
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

static func _load_base_biome(biome: int, paths: Array) -> void:
	var list: Array[Texture2D] = []
	for p in paths:
		if p.ends_with(".png"):
			var t = _load_single(p)
			if t:
				list.append(t)
		else:
			var dir_list = _load_dir(p)
			list.append_array(dir_list)
	base_textures[biome] = list

static func _load_all_overlays() -> void:
	var overlay_base = "res://Assets/terrain_atlas/overlays"
	var dir = DirAccess.open(overlay_base)
	if dir:
		dir.list_dir_begin()
		var biome_f = dir.get_next()
		while biome_f != "":
			if dir.current_is_dir() and not biome_f.begins_with("."):
				var sub_path = overlay_base + "/" + biome_f
				var sub_dir = DirAccess.open(sub_path)
				if sub_dir:
					sub_dir.list_dir_begin()
					var mask_f = sub_dir.get_next()
					while mask_f != "":
						if not sub_dir.current_is_dir() and mask_f.ends_with(".png") and not mask_f.ends_with(".import"):
							var mask_name = mask_f.replace(".png", "")
							var full_p = sub_path + "/" + mask_f
							var tex = load(full_p)
							if tex:
								overlay_textures[biome_f + "/" + mask_name] = tex
						mask_f = sub_dir.get_next()
			biome_f = dir.get_next()

static func _load_all_rivers() -> void:
	var river_path = "res://Assets/terrain_atlas/rivers"
	var dir = DirAccess.open(river_path)
	if dir:
		dir.list_dir_begin()
		var f_name = dir.get_next()
		while f_name != "":
			if not dir.current_is_dir() and f_name.ends_with(".png") and not f_name.ends_with(".import"):
				var river_name = f_name.replace(".png", "")
				var full_p = river_path + "/" + f_name
				var tex = load(full_p)
				if tex:
					river_textures[river_name] = tex
			f_name = dir.get_next()

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

static func get_overlay_texture(biome_folder: String, mask_name: String) -> Texture2D:
	load_all_textures()
	var key = biome_folder + "/" + mask_name
	return overlay_textures.get(key, null)

static func get_river_texture(river_name: String) -> Texture2D:
	load_all_textures()
	return river_textures.get(river_name, null)

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
			if rand_idx % 100 < 35:
				return nature_sprites.get("tree_autumn_gold", null)
			elif rand_idx % 100 < 60:
				return nature_sprites.get("bush_gold", null)
			return null
			
		BiomeType.HILLS:
			if rand_idx % 100 < 65:
				return nature_sprites.get("rock_boulder", null)
			return null
			
		BiomeType.MOUNTAINS:
			return nature_sprites.get("rock_mountain", null)
			
		BiomeType.SNOW_PEAKS:
			return nature_sprites.get("rock_mountain", null)
			
		BiomeType.TUNDRA:
			if rand_idx % 100 < 45:
				return nature_sprites.get("tree_snow", null)
			elif rand_idx % 100 < 70:
				return nature_sprites.get("bush_snow", null)
			return null
			
		BiomeType.MEADOW:
			if rand_idx % 100 < 25:
				return nature_sprites.get("bush_flowers", null)
			return null
			
		BiomeType.PLAINS:
			if rand_idx % 100 < 15:
				return nature_sprites.get("bush_green", null)
			return null
			
		_:
			return null
