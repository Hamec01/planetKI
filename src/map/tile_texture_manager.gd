class_name TileTextureManager
extends RefCounted

const BiomeType = BiomeDefinitions.BiomeType

static var base_textures: Dictionary = {}
static var overlay_textures: Dictionary = {} # "biome_folder/mask_name" -> Texture2D
static var river_textures: Dictionary = {} # "river_name" -> Texture2D
static var nature_sprites: Dictionary = {} # "sprite_name" -> Texture2D
static var special_tiles: Dictionary = {} # "farm_plowed", "farm_crops", "farm_wheat", "cobblestone"
static var is_loaded: bool = false

static func load_all_textures() -> void:
	if is_loaded:
		return
		
	# 1. Загрузка бесшовного terrain-атласа
	_load_base_biome(BiomeType.DEEP_OCEAN, ["res://Assets/terrain_atlas/base/water_deep.png"])
	_load_base_biome(BiomeType.SHALLOW_COAST, ["res://Assets/terrain_atlas/base/water_shallow.png"])
	_load_base_biome(BiomeType.PLAINS, ["res://Assets/terrain_atlas/base/plains.png"])
	_load_base_biome(BiomeType.MEADOW, ["res://Assets/terrain_atlas/base/meadow.png"])
	_load_base_biome(BiomeType.DECIDUOUS_FOREST, ["res://Assets/terrain_atlas/base/plains.png"])
	_load_base_biome(BiomeType.PINE_TAIGA, ["res://Assets/terrain_atlas/base/plains.png"])
	_load_base_biome(BiomeType.JUNGLE, ["res://Assets/terrain_atlas/base/meadow.png"])
	_load_base_biome(BiomeType.SAVANNA, ["res://Assets/terrain_atlas/base/savanna.png"])
	_load_base_biome(BiomeType.DESERT, ["res://Assets/terrain_atlas/base/sand.png", "res://Assets/terrain_atlas/base/sand_alt.png"])
	_load_base_biome(BiomeType.SWAMP, ["res://Assets/terrain_atlas/base/swamp.png"])
	_load_base_biome(BiomeType.HILLS, ["res://Assets/terrain_atlas/base/dirt.png", "res://Assets/terrain_atlas/base/dirt_alt.png"])
	_load_base_biome(BiomeType.MOUNTAINS, ["res://Assets/terrain_atlas/base/mountains.png", "res://Assets/terrain_atlas/base/stone.png"])
	_load_base_biome(BiomeType.SNOW_PEAKS, ["res://Assets/terrain_atlas/base/snow_peaks.png"])
	_load_base_biome(BiomeType.TUNDRA, ["res://Assets/terrain_atlas/base/snow.png"])
	
	# Спец-покрытия
	special_tiles["farm_plowed"] = _load_single("res://Assets/terrain_atlas/base/farm_plowed.png")
	special_tiles["farm_crops"] = _load_single("res://Assets/terrain_atlas/base/farm_crops.png")
	special_tiles["farm_wheat"] = _load_single("res://Assets/terrain_atlas/base/farm_wheat.png")
	special_tiles["cobblestone"] = _load_single("res://Assets/terrain_atlas/base/cobblestone.png")
	
	# 2. Оверлеи переходов
	_load_all_overlays()
	
	# 3. Реки
	_load_all_rivers()
	
	# 4. Загрузка 64 природных объектов нового набора Assets/nature_v2/
	_load_all_nature()
	
	is_loaded = true

static func _load_base_biome(biome: int, paths: Array) -> void:
	var list: Array[Texture2D] = []
	for p in paths:
		var t = _load_single(p)
		if t:
			list.append(t)
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

static func _load_all_nature() -> void:
	var nature_dir = "res://Assets/nature_v2"
	var dir = DirAccess.open(nature_dir)
	if dir:
		dir.list_dir_begin()
		var f_name = dir.get_next()
		while f_name != "":
			if not dir.current_is_dir() and f_name.ends_with(".png") and not f_name.ends_with(".import"):
				var sprite_name = f_name.replace(".png", "")
				var full_p = nature_dir + "/" + f_name
				var tex = load(full_p)
				if tex:
					nature_sprites[sprite_name] = tex
			f_name = dir.get_next()

static func _load_single(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

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

static func get_special_texture(key: String) -> Texture2D:
	load_all_textures()
	return special_tiles.get(key, null)

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
	var roll = rand_idx % 100
	
	match biome:
		# 1. ЗИМНИЕ БИОМЫ (СТРОГО ТОЛЬКО ЗИМНИЕ ДЕРЕВЬЯ И СНЕЖНЫЕ КАМНИ)
		BiomeType.SNOW_PEAKS:
			if roll < 55:
				var pool = ["rock_snow_boulder", "tree_spruce_snow", "tree_dead"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		BiomeType.TUNDRA:
			if roll < 65:
				var pool = ["tree_spruce_snow", "tree_pine_snow", "tree_bare", "bush_dry_thorny", "rock_snow_boulder"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 2. ХВОЙНЫЙ ЛЕС (ТАЙГА)
		BiomeType.PINE_TAIGA:
			if roll < 80:
				var pool = ["tree_spruce", "tree_spruce_blue", "tree_pine", "tree_spruce_young", "stump_mossy", "log_fallen", "mushrooms_brown", "plant_dense_fern"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 3. ШИРОКОЛИСТВЕННЫЙ ЛЕС
		BiomeType.DECIDUOUS_FOREST:
			if roll < 85:
				var pool = ["tree_oak", "tree_birch", "tree_maple_green", "tree_poplar", "tree_autumn_red", "tree_birch_yellow", "bush_berries_red", "bush_berries_blue", "mushrooms_brown", "mushrooms_flyagaric"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 4. ДЖУНГЛИ
		BiomeType.JUNGLE:
			if roll < 85:
				var pool = ["tree_willow", "tree_maple_green", "plant_dense_fern", "plant_broadleaf", "bush_round_green", "bush_berries_red"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 5. ЛУГ
		BiomeType.MEADOW:
			if roll < 45:
				var pool = ["flowers_white", "flowers_yellow", "flowers_purple", "flowers_poppies", "grass_tall_meadow", "bush_flowers", "bush_berry_low", "sapling"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 6. РАВНИНЫ
		BiomeType.PLAINS:
			if roll < 25:
				var pool = ["grass_dense", "grass_tuft_low", "bush_round_green", "bush_light", "tree_young"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 7. САВАННА
		BiomeType.SAVANNA:
			if roll < 40:
				var pool = ["grass_dry_yellow", "grass_steppe_orange", "tumbleweed", "bush_dry_thorny", "rock_red_stone", "tree_autumn_red"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 8. ПУСТЫНЯ
		BiomeType.DESERT:
			if roll < 20:
				var pool = ["cactus_branched", "cactus_round", "tumbleweed", "rock_limestone"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 9. БОЛОТО
		BiomeType.SWAMP:
			if roll < 60:
				var pool = ["reeds", "cattails", "marsh_grass", "marsh_broadleaf", "stump_mossy", "tree_willow"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		# 10. ХОЛМЫ И ГОРЫ
		BiomeType.HILLS:
			if roll < 50:
				var pool = ["rock_round_boulder", "rock_small_pebbles", "rock_mossy", "bush_dark", "grass_thin"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		BiomeType.MOUNTAINS:
			if roll < 70:
				var pool = ["rock_cliff_group", "rock_flat_slabs", "rock_round_boulder", "rock_small_pebbles"]
				return nature_sprites.get(pool[rand_idx % pool.size()], null)
			return null
			
		_:
			return null
