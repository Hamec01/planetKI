class_name TerrainResolver
extends RefCounted

const BiomeType = BiomeDefinitions.BiomeType

# Иерархия высот и слоев биомов для плавного наложения (от нижнего к верхнему)
const BIOME_LAYERS: Dictionary = {
	BiomeType.DEEP_OCEAN: 0,
	BiomeType.SHALLOW_COAST: 1,
	BiomeType.DESERT: 2,
	BiomeType.SWAMP: 3,
	BiomeType.HILLS: 4,
	BiomeType.SAVANNA: 5,
	BiomeType.PLAINS: 6,
	BiomeType.MEADOW: 6,
	BiomeType.DECIDUOUS_FOREST: 6,
	BiomeType.PINE_TAIGA: 6,
	BiomeType.JUNGLE: 6,
	BiomeType.TUNDRA: 7,
	BiomeType.MOUNTAINS: 8,
	BiomeType.SNOW_PEAKS: 9
}

static func get_biome_layer(biome: int) -> int:
	return BIOME_LAYERS.get(biome, 6)

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
# Каждая запись: {"biome_folder": String, "mask": String}
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
	
	# 1. Прямые края (N, S, W, E)
	if n_layer > cur_layer:
		result.append({"biome_folder": get_biome_folder_name(n_biome), "mask": "edge_n"})
	if s_layer > cur_layer:
		result.append({"biome_folder": get_biome_folder_name(s_biome), "mask": "edge_s"})
	if w_layer > cur_layer:
		result.append({"biome_folder": get_biome_folder_name(w_biome), "mask": "edge_w"})
	if e_layer > cur_layer:
		result.append({"biome_folder": get_biome_folder_name(e_biome), "mask": "edge_e"})
		
	# 2. Внешние диагональные углы (когда прямой край не перекрывает угол)
	if y > 0 and x > 0:
		var nw_biome = tiles[y-1][x-1]["biome"]
		if get_biome_layer(nw_biome) > cur_layer and n_layer <= cur_layer and w_layer <= cur_layer:
			result.append({"biome_folder": get_biome_folder_name(nw_biome), "mask": "corner_outer_nw"})
			
	if y > 0 and x < width - 1:
		var ne_biome = tiles[y-1][x+1]["biome"]
		if get_biome_layer(ne_biome) > cur_layer and n_layer <= cur_layer and e_layer <= cur_layer:
			result.append({"biome_folder": get_biome_folder_name(ne_biome), "mask": "corner_outer_ne"})
			
	if y < height - 1 and x > 0:
		var sw_biome = tiles[y+1][x-1]["biome"]
		if get_biome_layer(sw_biome) > cur_layer and s_layer <= cur_layer and w_layer <= cur_layer:
			result.append({"biome_folder": get_biome_folder_name(sw_biome), "mask": "corner_outer_sw"})
			
	if y < height - 1 and x < width - 1:
		var se_biome = tiles[y+1][x+1]["biome"]
		if get_biome_layer(se_biome) > cur_layer and s_layer <= cur_layer and e_layer <= cur_layer:
			result.append({"biome_folder": get_biome_folder_name(se_biome), "mask": "corner_outer_se"})
			
	return result

# Определяет текстуру реки для тайла
static func resolve_river_texture_name(tiles: Array, x: int, y: int, width: int, height: int) -> String:
	var n = (y > 0 and (tiles[y-1][x]["is_river"] or tiles[y-1][x]["is_water"]))
	var s = (y < height - 1 and (tiles[y+1][x]["is_river"] or tiles[y+1][x]["is_water"]))
	var w = (x > 0 and (tiles[y][x-1]["is_river"] or tiles[y][x-1]["is_water"]))
	var e = (x < width - 1 and (tiles[y][x+1]["is_river"] or tiles[y][x+1]["is_water"]))
	
	var count = (1 if n else 0) + (1 if s else 0) + (1 if w else 0) + (1 if e else 0)
	
	if count >= 4:
		return "river_cross"
	elif count == 3:
		if not n: return "river_t_s"
		if not s: return "river_t_n"
		if not w: return "river_t_e"
		if not e: return "river_t_w"
	elif count == 2:
		if w and e: return "river_h"
		if n and s: return "river_v"
		if n and e: return "river_turn_ne"
		if n and w: return "river_turn_nw"
		if s and e: return "river_turn_se"
		if s and w: return "river_turn_sw"
	elif count == 1:
		if w or e: return "river_h"
		if n or s: return "river_v"
		
	return "river_h"
