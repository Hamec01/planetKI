class_name NPCNavigation
extends RefCounted

var astar: AStarGrid2D = null
var width: int = 160
var height: int = 160
var cell_size: float = 32.0
var is_ready: bool = false

var water_tiles: Dictionary = {}

func initialize_grid(tiles_data: Array, map_w: int, map_h: int) -> void:
	width = map_w
	height = map_h
	water_tiles.clear()
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

func set_cell_solid(coord: Vector2i, solid: bool) -> void:
	if astar and is_valid_coord(coord):
		astar.set_point_solid(coord, solid)

func is_valid_coord(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < width and c.y >= 0 and c.y < height

func is_water_tile(c: Vector2i) -> bool:
	return water_tiles.has(c)

func is_tile_walkable(c: Vector2i) -> bool:
	if not astar or not is_valid_coord(c):
		return false
	return not astar.is_point_solid(c)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / cell_size)), int(floor(world_pos.y / cell_size)))

func world_pos_to_tile(world_pos: Vector2) -> Vector2i:
	return world_to_tile(world_pos)

func tile_to_world_center(coord: Vector2i) -> Vector2:
	return Vector2(coord.x * cell_size + cell_size * 0.5, coord.y * cell_size + cell_size * 0.5)

# Поиск пути между двумя мировыми позициями
func find_path(from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not astar or not is_ready:
		result.append(to_world)
		return result
		
	var start_tile = world_to_tile(from_world)
	var end_tile = world_to_tile(to_world)
	
	# Если начальная точка вне сетки или в воде (например, край карты), корректируем
	if not is_tile_walkable(start_tile):
		start_tile = find_nearest_walkable_tile(start_tile)
	if not is_tile_walkable(end_tile):
		end_tile = find_nearest_walkable_tile(end_tile)
		
	if start_tile == end_tile:
		result.append(to_world)
		return result
		
	var cell_path = astar.get_point_path(start_tile, end_tile)
	if cell_path.is_empty():
		# Путь не найден (например, другой континент)
		return []
		
	for p in cell_path:
		# Преобразуем координаты сетки в центр клетки
		result.append(p + Vector2(cell_size * 0.5, cell_size * 0.5))
		
	# Заменяем последнюю точку на точную целевую позицию
	if not result.is_empty():
		result[result.size() - 1] = to_world
		
	return result

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
