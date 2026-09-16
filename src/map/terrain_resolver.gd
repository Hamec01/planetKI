class_name TerrainResolver
extends RefCounted

const BiomeType = BiomeDefinitions.BiomeType

# Иерархия слоев биомов для плавного наложения (от нижнего к верхнему)
const BIOME_LAYERS: Dictionary = {
	BiomeType.DEEP_OCEAN: 0,
	BiomeType.SHALLOW_COAST: 0,
	BiomeType.DESERT: 1,
	BiomeType.SWAMP: 2,
	BiomeType.HILLS: 3,
	BiomeType.SAVANNA: 4,
	BiomeType.PLAINS: 5,
	BiomeType.MEADOW: 5,
	BiomeType.DECIDUOUS_FOREST: 5,
	BiomeType.PINE_TAIGA: 5,
	BiomeType.JUNGLE: 5,
	BiomeType.TUNDRA: 6,
	BiomeType.MOUNTAINS: 7,
	BiomeType.SNOW_PEAKS: 8
}

static func get_biome_layer(biome: int) -> int:
	return BIOME_LAYERS.get(biome, 5)

static func get_biome_folder_name(biome: int) -> String:
	match biome:
		BiomeType.DEEP_OCEAN: return "water_deep"
		BiomeType.SHALLOW_COAST: return "water_shallow"
		BiomeType.PLAINS: return "plains"
		BiomeType.MEADOW: return "meadow"
		BiomeType.DECIDUOUS_FOREST: return "plains"
		BiomeType.PINE_TAIGA: return "plains"
		BiomeType.JUNGLE: return "meadow"
		BiomeType.SAVANNA: return "savanna"
		BiomeType.DESERT: return "sand"
		BiomeType.SWAMP: return "swamp"
		BiomeType.HILLS: return "dirt"
		BiomeType.MOUNTAINS: return "mountains"
		BiomeType.SNOW_PEAKS: return "snow_peaks"
		BiomeType.TUNDRA: return "snow"
		_: return "plains"

# Возвращает список необходимых оверлеев переходов для тайла (x, y)
static func get_transition_overlays(tiles: Array, x: int, y: int, width: int, height: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if y < 0 or y >= height or x < 0 or x >= width:
		return result
		
	var cur_tile = tiles[y][x]
	var cur_biome = cur_tile["biome"]
	var cur_layer = get_biome_layer(cur_biome)
	
	# Соседи по сторонам света
	var n_biome = tiles[y-1][x]["biome"] if y > 0 else cur_biome
	var s_biome = tiles[y+1][x]["biome"] if y < height - 1 else cur_biome
	var w_biome = tiles[y][x-1]["biome"] if x > 0 else cur_biome
	var e_biome = tiles[y][x+1]["biome"] if x < width - 1 else cur_biome
	
	var n_layer = get_biome_layer(n_biome)
	var s_layer = get_biome_layer(s_biome)
	var w_layer = get_biome_layer(w_biome)
	var e_layer = get_biome_layer(e_biome)
	
	# Не накладываем водные оверлеи
	if n_layer > cur_layer and not _is_water_biome(n_biome):
		result.append({"biome_folder": get_biome_folder_name(n_biome), "mask": "edge_n"})
	if s_layer > cur_layer and not _is_water_biome(s_biome):
		result.append({"biome_folder": get_biome_folder_name(s_biome), "mask": "edge_s"})
	if w_layer > cur_layer and not _is_water_biome(w_biome):
		result.append({"biome_folder": get_biome_folder_name(w_biome), "mask": "edge_w"})
	if e_layer > cur_layer and not _is_water_biome(e_biome):
		result.append({"biome_folder": get_biome_folder_name(e_biome), "mask": "edge_e"})
		
	# Внешние диагональные углы
	if y > 0 and x > 0:
		var nw_biome = tiles[y-1][x-1]["biome"]
		if get_biome_layer(nw_biome) > cur_layer and n_layer <= cur_layer and w_layer <= cur_layer and not _is_water_biome(nw_biome):
			result.append({"biome_folder": get_biome_folder_name(nw_biome), "mask": "corner_outer_nw"})
			
	if y > 0 and x < width - 1:
		var ne_biome = tiles[y-1][x+1]["biome"]
		if get_biome_layer(ne_biome) > cur_layer and n_layer <= cur_layer and e_layer <= cur_layer and not _is_water_biome(ne_biome):
			result.append({"biome_folder": get_biome_folder_name(ne_biome), "mask": "corner_outer_ne"})
			
	if y < height - 1 and x > 0:
		var sw_biome = tiles[y+1][x-1]["biome"]
		if get_biome_layer(sw_biome) > cur_layer and s_layer <= cur_layer and w_layer <= cur_layer and not _is_water_biome(sw_biome):
			result.append({"biome_folder": get_biome_folder_name(sw_biome), "mask": "corner_outer_sw"})
			
	if y < height - 1 and x < width - 1:
		var se_biome = tiles[y+1][x+1]["biome"]
		if get_biome_layer(se_biome) > cur_layer and s_layer <= cur_layer and e_layer <= cur_layer and not _is_water_biome(se_biome):
			result.append({"biome_folder": get_biome_folder_name(se_biome), "mask": "corner_outer_se"})
			
	return result

static func _is_water_biome(biome: int) -> bool:
	return biome == BiomeType.DEEP_OCEAN or biome == BiomeType.SHALLOW_COAST
