class_name MapResourceManager
extends RefCounted

# Хранилище всех активных ресурсных узлов на карте: coord -> NodeDictionary
var nodes: Dictionary = {}
var is_initialized: bool = false

# Типы ресурсов
const RESOURCE_NATURE_CONFIG = {
	# ПИЩА (Ягоды и грибы)
	"bush_berries_red": {"type": "berries", "category": "food", "amount": 12.0, "depleted_sprite": "bush_light", "name": "Куст красных ягод"},
	"bush_berries_blue": {"type": "berries", "category": "food", "amount": 12.0, "depleted_sprite": "bush_light", "name": "Куст черники"},
	"bush_berry_low": {"type": "berries", "category": "food", "amount": 8.0, "depleted_sprite": "grass_tuft_low", "name": "Низкая брусника"},
	"mushrooms_brown": {"type": "mushrooms", "category": "food", "amount": 10.0, "depleted_sprite": "none", "name": "Грибная поляна (боровики)"},
	"mushrooms_flyagaric": {"type": "mushrooms", "category": "food", "amount": 6.0, "depleted_sprite": "none", "name": "Грибное место"},

	# ДРЕВЕСИНА (Деревья) -> 1 взрослое дерево = 18-20 дров, молодое = 8 дров. При срубе исчезает с карты (nature_object = none)
	"tree_oak": {"type": "wood", "category": "wood", "amount": 20.0, "depleted_sprite": "none", "name": "Могучий дуб"},
	"tree_birch": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Берёза"},
	"tree_pine": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Сосна"},
	"tree_spruce": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Ель"},
	"tree_maple_green": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Клён"},
	"tree_poplar": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Тополь"},
	"tree_willow": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Ива"},
	"tree_autumn_red": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Красное дерево"},
	"tree_birch_yellow": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Золотая берёза"},
	"tree_spruce_blue": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Голубая ель"},
	"tree_spruce_snow": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Заснеженная ель"},
	"tree_pine_snow": {"type": "wood", "category": "wood", "amount": 18.0, "depleted_sprite": "none", "name": "Заснеженная сосна"},
	"tree_bare": {"type": "wood", "category": "wood", "amount": 12.0, "depleted_sprite": "none", "name": "Облетевшее дерево"},
	"tree_dead": {"type": "wood", "category": "wood", "amount": 10.0, "depleted_sprite": "none", "name": "Сухостой"},
	"tree_spruce_young": {"type": "wood", "category": "wood", "amount": 8.0, "depleted_sprite": "none", "name": "Молодая ёлочка"},
	"tree_young": {"type": "wood", "category": "wood", "amount": 8.0, "depleted_sprite": "none", "name": "Молодое деревце"},
	# Валежник: лежит на земле, не перекрывает проход, разбирается на дрова
	"log_fallen": {"type": "wood", "category": "wood", "amount": 6.0, "depleted_sprite": "none", "name": "Поваленное бревно", "blocks": false},

	# КАМЕНЬ (Валуны и скалы). Камень не отрастает: выработанная порода распадается на
	# следующую стадию (скала -> плиты -> россыпь -> ничего) и в итоге исчезает с карты.
	"rock_round_boulder": {"type": "stone", "category": "stone", "amount": 25.0, "depleted_sprite": "rock_small_pebbles", "name": "Округлый валун"},
	"rock_flat_slabs": {"type": "stone", "category": "stone", "amount": 20.0, "depleted_sprite": "rock_small_pebbles", "name": "Каменные плиты"},
	"rock_mossy": {"type": "stone", "category": "stone", "amount": 22.0, "depleted_sprite": "rock_small_pebbles", "name": "Мшистый валун"},
	"rock_cliff_group": {"type": "stone", "category": "stone", "amount": 35.0, "depleted_sprite": "rock_flat_slabs", "name": "Скальная гряда"},
	"rock_limestone": {"type": "stone", "category": "stone", "amount": 25.0, "depleted_sprite": "rock_small_pebbles", "name": "Известняк"},
	"rock_snow_boulder": {"type": "stone", "category": "stone", "amount": 25.0, "depleted_sprite": "rock_small_pebbles", "name": "Заснеженный валун"},
	# Россыпь камней: последняя стадия породы, проходима, собирается до конца
	"rock_small_pebbles": {"type": "stone", "category": "stone", "amount": 4.0, "depleted_sprite": "none", "name": "Россыпь камней", "blocks": false},

	# РУДА (Красный камень / железистые жилы). После выработки остаётся каменная россыпь.
	"rock_red_stone": {"type": "metal", "category": "metal", "amount": 20.0, "depleted_sprite": "rock_small_pebbles", "name": "Рудная жила"}
}
# Категории, которые восстанавливаются сами (кусты, грибницы, рыба). Дерево отрастает
# только из пня/саженца, а камень и руда — невозобновляемы.
const RENEWABLE_CATEGORIES: Array[String] = ["food", "fish"]
const FOOD_NATURE_TYPES = RESOURCE_NATURE_CONFIG

const CHUNK_SIZE: int = 16
var spatial_grid: Dictionary = {} # Vector2i(chunk_x, chunk_y) -> Array[Vector2i]

func initialize_from_tiles(tiles_data: Array, width: int, height: int) -> void:
	nodes.clear()
	spatial_grid.clear()
	for y in range(mini(height, tiles_data.size())):
		var row = tiles_data[y]
		for x in range(mini(width, row.size())):
			var tile = row[x]
			var coord = Vector2i(x, y)
			
			var custom_nat = tile.get("nature_object", "")
			var sprite_name = TileTextureManager.get_nature_name(tile["biome"], coord, tile.get("resource", null), custom_nat)
			if RESOURCE_NATURE_CONFIG.has(sprite_name):
				_create_node(coord, sprite_name)
	_add_fishing_spots(tiles_data, width, height)
	is_initialized = true

# Создаёт (или пересоздаёт) ресурсный узел по виду природного объекта
func _create_node(coord: Vector2i, sprite_name: String) -> Dictionary:
	var cfg = RESOURCE_NATURE_CONFIG[sprite_name]
	var node = {
		"id": "res_%d_%d" % [coord.x, coord.y],
		"coord": coord,
		"pos": Vector2(coord.x * 32.0 + 16.0, coord.y * 32.0 + 16.0),
		"type": cfg["type"],
		"category": cfg["category"],
		"name": cfg["name"],
		"amount": cfg["amount"],
		"max_amount": cfg["amount"],
		"reserved_by": "",
		"depleted": false,
		"original_sprite": sprite_name,
		"depleted_sprite": cfg["depleted_sprite"],
		"blocks": cfg.get("blocks", cfg["category"] in ["wood", "stone", "metal"]),
		"regrowth_timer": 0.0,
		"regrowth_duration": randf_range(35.0, 55.0)
	}
	nodes[coord] = node
	var chunk_k = Vector2i(coord.x / CHUNK_SIZE, coord.y / CHUNK_SIZE)
	if not spatial_grid.has(chunk_k):
		spatial_grid[chunk_k] = []
	if not spatial_grid[chunk_k].has(coord):
		spatial_grid[chunk_k].append(coord)
	# Непроходимые природные объекты (стволы, валуны, скалы) регистрируются в навигации
	if GameManager and GameManager.nav_grid:
		if node["blocks"]:
			GameManager.nav_grid.register_resource(coord, cfg["category"])
		elif GameManager.nav_grid.resource_tiles.has(coord):
			GameManager.nav_grid.unregister_resource(coord)
	return node

func _set_tile_nature(coord: Vector2i, sprite_name: String) -> void:
	if not GameManager or GameManager.planet_data.is_empty():
		return
	var tiles = GameManager.planet_data.get("tiles", [])
	if coord.y < tiles.size() and coord.x < tiles[coord.y].size():
		tiles[coord.y][coord.x]["nature_object"] = sprite_name

func _add_fishing_spots(tiles_data: Array, width: int, height: int) -> void:
	if not GameManager.nav_grid:
		return
	for y in range(2, height - 2, 4):
		for x in range(2, width - 2, 4):
			var water_coord = Vector2i(x, y)
			if not GameManager.nav_grid.is_water_tile(water_coord):
				continue
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var shore_coord = water_coord + offset
				if nodes.has(shore_coord) or not GameManager.nav_grid.is_tile_walkable(shore_coord):
					continue
				nodes[shore_coord] = {
					"id": "fish_%d_%d" % [shore_coord.x, shore_coord.y],
					"coord": shore_coord,
					"pos": Vector2(shore_coord.x * 32.0 + 16.0, shore_coord.y * 32.0 + 16.0),
					"type": "fish",
					"category": "fish",
					"name": "Рыбное место",
					"amount": 18.0,
					"max_amount": 18.0,
					"reserved_by": "",
					"depleted": false,
					"original_sprite": "",
					"depleted_sprite": "",
					"updates_tile": false,
					"regrowth_timer": 0.0,
					"regrowth_duration": 90.0
				}
				var chunk_k = Vector2i(shore_coord.x / CHUNK_SIZE, shore_coord.y / CHUNK_SIZE)
				if not spatial_grid.has(chunk_k):
					spatial_grid[chunk_k] = []
				spatial_grid[chunk_k].append(shore_coord)
				break

func find_available_node(center_coord: Vector2i, category: String, max_radius: int, citizen_id: String) -> Dictionary:
	var best_node: Dictionary = {}
	var best_dist: float = 999999.0
	
	var min_cx = int(floor(float(center_coord.x - max_radius) / float(CHUNK_SIZE)))
	var max_cx = int(floor(float(center_coord.x + max_radius) / float(CHUNK_SIZE)))
	var min_cy = int(floor(float(center_coord.y - max_radius) / float(CHUNK_SIZE)))
	var max_cy = int(floor(float(center_coord.y + max_radius) / float(CHUNK_SIZE)))
	
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var chunk_k = Vector2i(cx, cy)
			if not spatial_grid.has(chunk_k):
				continue
			var stale_coords: Array[Vector2i] = []
			for coord in spatial_grid[chunk_k]:
				if not nodes.has(coord):
					stale_coords.append(coord)
					continue
				var node = nodes[coord]
				if node.get("category", "") != category:
					continue
				if node.get("depleted", false) or node.get("amount", 0.0) <= 0.0:
					continue
				if node.get("reserved_by", "") != "" and node["reserved_by"] != citizen_id:
					continue
				# Саженец ещё растёт — рубить его рано
				if growing_trees.has(coord):
					continue
					
				var dist = float(abs(coord.x - center_coord.x) + abs(coord.y - center_coord.y))
				if dist <= float(max_radius) and dist < best_dist:
					if GameManager and GameManager.nav_grid:
						if not GameManager.nav_grid.is_valid_coord(coord) or GameManager.nav_grid.water_tiles.has(coord):
							continue
					best_dist = dist
					best_node = node
			for sc in stale_coords:
				spatial_grid[chunk_k].erase(sc)
				
	return best_node

func remove_node(coord: Vector2i) -> void:
	if GameManager and GameManager.nav_grid:
		GameManager.nav_grid.unregister_resource(coord)
	if nodes.has(coord):
		nodes.erase(coord)
	var chunk_k = Vector2i(int(floor(float(coord.x) / float(CHUNK_SIZE))), int(floor(float(coord.y) / float(CHUNK_SIZE))))
	if spatial_grid.has(chunk_k):
		spatial_grid[chunk_k].erase(coord)

func reserve_node(coord: Vector2i, citizen_id: String) -> bool:
	if not nodes.has(coord):
		return false
	var node = nodes[coord]
	if node["reserved_by"] == "" or node["reserved_by"] == citizen_id:
		node["reserved_by"] = citizen_id
		return true
	return false

func release_node(coord: Vector2i, citizen_id: String) -> void:
	if nodes.has(coord):
		var node = nodes[coord]
		if node["reserved_by"] == citizen_id:
			node["reserved_by"] = ""

var growing_trees: Dictionary = {} # coord -> {"timer": float, "mature_species": String}

func harvest_from_node(coord: Vector2i, request_amount: float) -> float:
	if not nodes.has(coord):
		return 0.0
	var node = nodes[coord]
	if node["depleted"] or node["amount"] <= 0.0:
		return 0.0
		
	var gathered = minf(node["amount"], request_amount)
	node["amount"] -= gathered
	
	if node["amount"] <= 0.0:
		_on_node_depleted(coord, node)
			
	return gathered

# Исчерпание узла: дерево падает, камень распадается на следующую стадию, куст пустеет
func _on_node_depleted(coord: Vector2i, node: Dictionary) -> void:
	var dep_spr: String = node.get("depleted_sprite", "none")
	var category: String = node.get("category", "")
	growing_trees.erase(coord)
	
	# Порода распадается на следующую стадию (скала -> плиты -> россыпь), которую можно добывать дальше
	if category in ["stone", "metal"] and RESOURCE_NATURE_CONFIG.has(dep_spr):
		_create_node(coord, dep_spr)
		_set_tile_nature(coord, dep_spr)
		return
	
	node["depleted"] = true
	node["reserved_by"] = ""
	if GameManager and GameManager.nav_grid and category in ["wood", "stone", "metal"]:
		GameManager.nav_grid.unregister_resource(coord)
	if category == "wood":
		node["regrowth_timer"] = node.get("regrowth_duration", 300.0) if dep_spr == "stump_fresh" else 9999999.0
	else:
		node["regrowth_timer"] = node.get("regrowth_duration", 60.0)
		
	# Обновляем спрайт на карте (куст пустеет / дерево срублено под корень / камень выбран)
	if node.get("updates_tile", true):
		_set_tile_nature(coord, dep_spr)
		
	# Дерево без пня и выбранный до конца камень физически исчезают с карты
	if dep_spr == "none" and category in ["wood", "stone", "metal"]:
		remove_node(coord)

func find_plantable_tile(center_coord: Vector2i, max_radius: int) -> Vector2i:
	var tiles = GameManager.planet_data.get("tiles", [])
	if tiles.is_empty():
		return Vector2i(-1, -1)
	var height = tiles.size()
	var width = tiles[0].size()
	
	for r in range(2, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var check_c = center_coord + Vector2i(dx, dy)
				if check_c.x < 1 or check_c.x >= width - 1 or check_c.y < 1 or check_c.y >= height - 1:
					continue
				if not GameManager.nav_grid.is_tile_walkable(check_c):
					continue
				if GameManager.nav_grid.is_water_tile(check_c):
					continue
				if GameManager.tile_buildings.has(check_c):
					continue
				var t = tiles[check_c.y][check_c.x]
				var nat = t.get("nature_object", "")
				if nat == "" or nat == "none" or nat == "stump_fresh" or nat == "stump_mossy":
					if not nodes.has(check_c) or nodes[check_c]["depleted"]:
						return check_c
	return Vector2i(-1, -1)

func plant_tree(coord: Vector2i, young_species: String = "tree_young", mature_species: String = "tree_pine") -> bool:
	var tiles = GameManager.planet_data.get("tiles", [])
	if coord.y >= tiles.size() or coord.x >= tiles[0].size():
		return false
	var t = tiles[coord.y][coord.x]
	t["nature_object"] = young_species
	
	var node_id = "res_%d_%d" % [coord.x, coord.y]
	nodes[coord] = {
		"id": node_id,
		"coord": coord,
		"pos": Vector2(coord.x * 32.0 + 16.0, coord.y * 32.0 + 16.0),
		"type": "wood",
		"category": "wood",
		"name": "Молодой саженец",
		"amount": 3.0,
		"max_amount": 3.0,
		"reserved_by": "",
		"depleted": false,
		"original_sprite": young_species,
		"depleted_sprite": "none",
		"blocks": false,
		"regrowth_timer": 9999999.0,
		"regrowth_duration": 9999999.0
	}
	var chunk_k = Vector2i(coord.x / CHUNK_SIZE, coord.y / CHUNK_SIZE)
	if not spatial_grid.has(chunk_k):
		spatial_grid[chunk_k] = []
	if not spatial_grid[chunk_k].has(coord):
		spatial_grid[chunk_k].append(coord)
		
	growing_trees[coord] = {
		"timer": 30.0, # 30 секунд до превращения в зрелое дерево
		"mature_species": mature_species
	}
	return true

func update_regrowth(delta: float) -> void:
	var tiles = GameManager.planet_data.get("tiles", [])
	if tiles.is_empty():
		return
		
	# 1. Рост посаженных саженцев во взрослые деревья
	var mature_coords = []
	for coord in growing_trees.keys():
		var gt = growing_trees[coord]
		gt["timer"] -= delta
		if gt["timer"] <= 0.0:
			mature_coords.append(coord)
			
	for coord in mature_coords:
		var gt = growing_trees[coord]
		var mature_sp = gt["mature_species"]
		growing_trees.erase(coord)
		if coord.y < tiles.size() and coord.x < tiles[0].size():
			tiles[coord.y][coord.x]["nature_object"] = mature_sp
		if nodes.has(coord):
			var n = nodes[coord]
			n["original_sprite"] = mature_sp
			var mature_cfg = RESOURCE_NATURE_CONFIG.get(mature_sp, {})
			n["name"] = mature_cfg.get("name", "Зрелое дерево")
			n["amount"] = float(mature_cfg.get("amount", 18.0))
			n["max_amount"] = n["amount"]
			n["depleted"] = false
			n["blocks"] = true
		if GameManager and GameManager.nav_grid:
			GameManager.nav_grid.register_resource(coord, "wood")
			
	# 2. Восстановление природных кустов ягод, грибов и рыбных мест (камень и руда не отрастают)
	for coord in nodes:
		var node = nodes[coord]
		if node["category"] in RENEWABLE_CATEGORIES and node["depleted"]:
			node["regrowth_timer"] -= delta
			if node["regrowth_timer"] <= 0.0:
				node["depleted"] = false
				node["amount"] = node["max_amount"]
				node["reserved_by"] = ""
				if node.get("updates_tile", true) and coord.y < tiles.size() and coord.x < tiles[0].size():
					tiles[coord.y][coord.x]["nature_object"] = node["original_sprite"]

	# 3. Естественное восстановление пней (P01.10)
	var cleared_stumps: Array[Vector2i] = []
	for coord in nodes.keys():
		if not nodes.has(coord):
			continue
		var node = nodes[coord]
		if node.get("category", "") == "wood" and node.get("depleted", false):
			# Если на клетке пня построено здание, пень уничтожается безвозвратно
			if GameManager and GameManager.tile_buildings.has(coord):
				cleared_stumps.append(coord)
				continue
			var timer = float(node.get("regrowth_timer", 300.0)) - delta
			node["regrowth_timer"] = timer
			if timer <= 0.0:
				node["depleted"] = false
				node["amount"] = node["max_amount"]
				node["reserved_by"] = ""
				var orig_sp = node.get("original_sprite", "tree_pine")
				if coord.y < tiles.size() and coord.x < tiles[0].size():
					tiles[coord.y][coord.x]["nature_object"] = orig_sp
				if GameManager and GameManager.nav_grid:
					GameManager.nav_grid.register_resource(coord, "wood")
	for sc in cleared_stumps:
		remove_node(sc)

# Сериализация для сохранений
func serialize() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for coord in nodes:
		var n = nodes[coord]
		var item = {
			"coord": [coord.x, coord.y],
			"amount": n.get("amount", 0.0),
			"depleted": n.get("depleted", false),
			"regrowth_timer": n.get("regrowth_timer", 0.0),
			"reserved_by": n.get("reserved_by", ""),
			"sprite": n.get("original_sprite", "")
		}
		if growing_trees.has(coord):
			item["growing_tree"] = growing_trees[coord].duplicate()
		list.append(item)
	return list

func deserialize(data_list: Array) -> void:
	growing_trees.clear()
	for item in data_list:
		var c_arr = item.get("coord", [0, 0])
		var coord = Vector2i(c_arr[0], c_arr[1])
		# Порода, перешедшая в следующую стадию выработки (скала -> плиты -> россыпь)
		var saved_sprite: String = item.get("sprite", "")
		if saved_sprite != "" and RESOURCE_NATURE_CONFIG.has(saved_sprite) and RESOURCE_NATURE_CONFIG[saved_sprite]["category"] in ["stone", "metal"]:
			if not nodes.has(coord) or nodes[coord].get("original_sprite", "") != saved_sprite:
				_create_node(coord, saved_sprite)
		if nodes.has(coord):
			var n = nodes[coord]
			n["amount"] = item.get("amount", n["max_amount"])
			n["depleted"] = item.get("depleted", false)
			n["regrowth_timer"] = item.get("regrowth_timer", 0.0)
			n["reserved_by"] = item.get("reserved_by", "")
			if item.has("growing_tree"):
				growing_trees[coord] = item["growing_tree"].duplicate()
