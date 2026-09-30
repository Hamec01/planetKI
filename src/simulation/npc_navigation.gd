class_name NPCNavigation
extends RefCounted

var astar: AStarGrid2D = null
var width: int = 160
var height: int = 160
var cell_size: float = 32.0
var is_ready: bool = false

var water_tiles: Dictionary = {}
var building_tiles: Dictionary = {} # coord -> building_id or true
var resource_tiles: Dictionary = {} # coord -> category ("wood", "stone", "metal")

func initialize_grid(tiles_data: Array, map_w: int, map_h: int) -> void:
	width = map_w
	height = map_h
	water_tiles.clear()
	building_tiles.clear()
	resource_tiles.clear()
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	
	for y in range(mini(height, tiles_data.size())):
		var row = tiles_data[y]
		for x in range(mini(width, row.size())):
			var tile = row[x]
			var is_solid = false
			# 1. Вода
			if tile.get("is_water", false) or tile.get("biome", -1) in [0, 1]: # Deep Ocean, Shallow Coast
				is_solid = true
				water_tiles[Vector2i(x, y)] = true
			# 2. Непроходимые заснеженные горные пики
			var elev = tile.get("elevation", 0.0)
			if elev >= 0.89:
				is_solid = true
				
			astar.set_point_solid(Vector2i(x, y), is_solid)
			
	is_ready = true

# Регистрация препятствий (здания)
func register_building(coord: Vector2i, size: Vector2i = Vector2i(1, 1), b_id: String = "") -> void:
	for dy in range(size.y):
		for dx in range(size.x):
			var c = coord + Vector2i(dx, dy)
			if is_valid_coord(c):
				building_tiles[c] = b_id if b_id != "" else true
				if astar:
					astar.set_point_solid(c, true)

func unregister_building(coord: Vector2i, size: Vector2i = Vector2i(1, 1)) -> void:
	for dy in range(size.y):
		for dx in range(size.x):
			var c = coord + Vector2i(dx, dy)
			if is_valid_coord(c):
				building_tiles.erase(c)
				if astar and not is_water_tile(c) and not resource_tiles.has(c):
					astar.set_point_solid(c, false)

# Регистрация природных препятствий (деревья, валуны, скалы)
func register_resource(coord: Vector2i, category: String = "wood") -> void:
	if not is_valid_coord(coord):
		return
	if category in ["wood", "stone", "metal"]:
		resource_tiles[coord] = category
		if astar:
			astar.set_point_solid(coord, true)

func unregister_resource(coord: Vector2i) -> void:
	if not is_valid_coord(coord):
		return
	resource_tiles.erase(coord)
	if astar and not is_water_tile(coord) and not building_tiles.has(coord):
		astar.set_point_solid(coord, false)

func is_obstacle(coord: Vector2i) -> bool:
	return building_tiles.has(coord) or resource_tiles.has(coord) or is_water_tile(coord)

func set_cell_solid(coord: Vector2i, solid: bool) -> void:
	if astar and is_valid_coord(coord):
		astar.set_point_solid(coord, solid)

func set_tile_walkable(coord: Vector2i, walkable: bool) -> void:
	set_cell_solid(coord, not walkable)

func is_valid_coord(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < width and c.y >= 0 and c.y < height

func is_water_tile(c: Vector2i) -> bool:
	return water_tiles.has(c)

func is_tile_walkable(c: Vector2i) -> bool:
	if not astar or not is_valid_coord(c):
		return false
	return not astar.is_point_solid(c)

func is_walkable(c: Vector2i) -> bool:
	return is_tile_walkable(c)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / cell_size)), int(floor(world_pos.y / cell_size)))

func world_pos_to_tile(world_pos: Vector2) -> Vector2i:
	return world_to_tile(world_pos)

func tile_to_world_center(coord: Vector2i) -> Vector2:
	return Vector2(coord.x * cell_size + cell_size * 0.5, coord.y * cell_size + cell_size * 0.5)

# Поиск пути между двумя мировыми позициями
# allow_dest_solid: разрешает дойти до целевой клетки если она занята (например вход в дом или хранилище),
# при этом все остальные здания, деревья и валуны остаются непроходимыми препятствиями для обхода.
func find_path(from_world: Vector2, to_world: Vector2, allow_dest_solid: bool = true) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not astar or not is_ready:
		result.append(to_world)
		return result
		
	var start_tile = world_to_tile(from_world)
	var end_tile = world_to_tile(to_world)
	
	# Если начальная или конечная точка в здании/на препятствии, временно снимаем solid для поиска пути
	var start_was_solid = false
	if astar and is_valid_coord(start_tile) and astar.is_point_solid(start_tile):
		start_was_solid = true
		astar.set_point_solid(start_tile, false)
		
	var end_was_solid = false
	if astar and is_valid_coord(end_tile) and astar.is_point_solid(end_tile):
		if allow_dest_solid:
			end_was_solid = true
			astar.set_point_solid(end_tile, false)
		else:
			end_tile = find_nearest_walkable_tile(end_tile)
		
	if start_tile == end_tile:
		if start_was_solid and astar and is_valid_coord(start_tile):
			astar.set_point_solid(start_tile, true)
		if end_was_solid and astar and is_valid_coord(end_tile):
			astar.set_point_solid(end_tile, true)
		result.append(to_world)
		return result
		
	var cell_path = astar.get_point_path(start_tile, end_tile)
	
	if start_was_solid and astar and is_valid_coord(start_tile):
		astar.set_point_solid(start_tile, true)
	if end_was_solid and astar and is_valid_coord(end_tile):
		astar.set_point_solid(end_tile, true)
		
	if cell_path.is_empty():
		# Путь не найден (например, изолированный остров)
		return []
		
	for p in cell_path:
		# Преобразуем координаты сетки в центр клетки
		result.append(p + Vector2(cell_size * 0.5, cell_size * 0.5))
		
	# Заменяем последнюю точку на точную целевую позицию
	if not result.is_empty():
		result[result.size() - 1] = to_world
		
	return result

# Поиск пути вплотную к свободной соседней клетке рядом с целевым объектом (дерево, камень, стена)
func find_adjacent_path(from_world: Vector2, target_tile: Vector2i) -> Array[Vector2]:
	var start_tile = world_to_tile(from_world)
	var target_center = tile_to_world_center(target_tile)
	if not is_valid_coord(target_tile):
		return find_path(from_world, target_center)
		
	# Соседние клетки (4 стороны + 4 диагонали)
	var neighbors: Array[Vector2i] = [
		target_tile + Vector2i(0, 1),
		target_tile + Vector2i(0, -1),
		target_tile + Vector2i(1, 0),
		target_tile + Vector2i(-1, 0),
		target_tile + Vector2i(1, 1),
		target_tile + Vector2i(-1, 1),
		target_tile + Vector2i(1, -1),
		target_tile + Vector2i(-1, -1)
	]
	
	# Выбираем наиболее подходящую соседнюю проходимую клетку
	var best_tile = Vector2i(-1, -1)
	if neighbors.has(start_tile) and is_tile_walkable(start_tile):
		best_tile = start_tile
	else:
		var best_dist = INF
		for n in neighbors:
			if is_tile_walkable(n):
				var d = from_world.distance_squared_to(tile_to_world_center(n))
				if d < best_dist:
					best_dist = d
					best_tile = n
					
	if best_tile == Vector2i(-1, -1):
		best_tile = find_nearest_walkable_tile(target_tile)
		
	# Вычисляем точку вплотную на границе соседней клетки, ближайшую к центру объекта
	var target_x = target_center.x
	var target_y = target_center.y
	
	if best_tile.x < target_tile.x:
		target_x = float((best_tile.x + 1) * cell_size) - 2.0
	elif best_tile.x > target_tile.x:
		target_x = float(best_tile.x * cell_size) + 2.0
		
	if best_tile.y < target_tile.y:
		target_y = float((best_tile.y + 1) * cell_size) - 2.0
	elif best_tile.y > target_tile.y:
		target_y = float(best_tile.y * cell_size) + 2.0
		
	var contact_pos = Vector2(target_x, target_y)
	
	# Если житель уже стоит вплотную к точке контакта
	if from_world.distance_to(contact_pos) <= 2.5:
		return [contact_pos]
		
	return find_path(from_world, contact_pos, false)

func find_nearest_walkable_tile(coord: Vector2i, max_radius: int = 5) -> Vector2i:
	if is_tile_walkable(coord):
		return coord
		
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(abs(dx), abs(dy)) != r:
					continue
				var c = coord + Vector2i(dx, dy)
				if is_tile_walkable(c):
					return c
	return coord

func find_random_walkable_nearby(center_coord: Vector2i, radius: int = 4) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c = center_coord + Vector2i(dx, dy)
			if is_tile_walkable(c):
				candidates.append(c)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	return center_coord
