class_name HeroMotion
extends RefCounted

# ==============================================================================
# СВОБОДНОЕ ДВИЖЕНИЕ КОРОЛЯ (без привязки к сетке)
# ------------------------------------------------------------------------------
# Сетка A* остаётся только «картой проходимости» для обхода. Сам Король:
#   • стоит и ходит в любой точке (не в центрах клеток);
#   • упирается не во всю клетку с деревом/камнем, а в ствол/валун (круг);
#     вода, здания и горные пики непроходимы целиком;
#   • идёт по прямой, если путь свободен, а обход препятствий сглаживается
#     (лишние изломы пути по клеткам выбрасываются — «натягивание нити»);
#   • кликнул в непроходимое место — идёт в ближайшую доступную точку.
# ==============================================================================

const BODY_RADIUS: float = 5.0
const LOS_STEP: float = 4.0
# Радиус препятствия в клетке с ресурсом (ствол, валун, рудная глыба)
const OBSTACLE_RADIUS: Dictionary = {"wood": 8.0, "stone": 11.0, "metal": 11.0}

static func _nav() -> NPCNavigation:
	return GameManager.nav_grid if GameManager else null

# Можно ли находиться в точке (без учёта тела)
static func is_point_free(p: Vector2) -> bool:
	var nav = _nav()
	if nav == null or nav.astar == null:
		return true
	var c = nav.world_to_tile(p)
	if not nav.is_valid_coord(c):
		return false
	if not nav.astar.is_point_solid(c):
		return true
	# Клетка непроходима из-за дерева/камня — мешает только сам ствол/валун
	if nav.resource_tiles.has(c) and not nav.building_tiles.has(c) and not nav.is_water_tile(c):
		var node: Dictionary = GameManager.resource_manager.nodes.get(c, {}) if GameManager.resource_manager else {}
		var center: Vector2 = node.get("pos", nav.tile_to_world_center(c))
		return p.distance_to(center) > float(OBSTACLE_RADIUS.get(String(nav.resource_tiles[c]), 9.0))
	return false

# Помещается ли тело Короля в точке
static func can_stand(p: Vector2) -> bool:
	if not is_point_free(p):
		return false
	for off in [Vector2(BODY_RADIUS, 0.0), Vector2(-BODY_RADIUS, 0.0), Vector2(0.0, BODY_RADIUS), Vector2(0.0, -BODY_RADIUS)]:
		if not is_point_free(p + off):
			return false
	return true

# Прямая видимость для прохода: тело пройдёт от a до b по прямой
static func has_line(a: Vector2, b: Vector2) -> bool:
	var dist = a.distance_to(b)
	var steps = int(ceil(dist / LOS_STEP))
	for i in range(1, steps + 1):
		if not can_stand(a.lerp(b, float(i) / float(steps))):
			return false
	return true

# Ближайшая к p точка, где можно стоять (спираль до max_r пикселей)
static func nearest_standable(p: Vector2, max_r: float = 56.0) -> Variant:
	if can_stand(p):
		return p
	var r = 4.0
	while r <= max_r:
		var best = null
		var best_d = INF
		for i in range(16):
			var q = p + Vector2.RIGHT.rotated(TAU * float(i) / 16.0) * r
			if can_stand(q):
				var d = q.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = q
		if best != null:
			return best
		r += 4.0
	return null

# Путь без привязки к сетке. Возвращает точки (без стартовой); пусто — не пройти.
static func find_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var dest = nearest_standable(to)
	if dest == null:
		return result
	if has_line(from, dest):
		result.append(dest)
		return result
	var nav = _nav()
	if nav == null:
		result.append(dest)
		return result
	var cells: Array[Vector2] = nav.find_path(from, dest)
	if cells.is_empty():
		return result
	# Опорные точки: клетки пути без первой (центр стартовой клетки) и с точной целью в конце
	var pts: Array[Vector2] = [from]
	for i in range(1, cells.size() - 1):
		pts.append(cells[i])
	pts.append(dest)
	# Натягивание нити: из каждой точки идём к самой дальней видимой
	var i0 = 0
	while i0 < pts.size() - 1:
		var j = pts.size() - 1
		while j > i0 + 1 and not has_line(pts[i0], pts[j]):
			j -= 1
		result.append(pts[j])
		i0 = j
	return result

# Точка, откуда удобно работать с объектом (дерево, камень): со стороны Короля, у самого ствола
static func approach_point(from: Vector2, target: Vector2, reach: float) -> Vector2:
	var dir = (from - target).normalized() if from != target else Vector2.DOWN
	for k in range(8):
		var a = dir.rotated((PI / 4.0) * float((k + 1) / 2) * (1.0 if k % 2 == 0 else -1.0))
		var q = nearest_standable(target + a * reach * 0.7, 10.0)
		if q != null and q.distance_to(target) <= reach:
			return q
	return target + dir * reach * 0.7

# Шаг движения со скольжением вдоль препятствий. Возвращает true, если сдвинулся.
static func step(c: CitizenNPC, move: Vector2) -> bool:
	if move == Vector2.ZERO:
		return false
	if not can_stand(c.pos):
		c.pos += move # застрял в препятствии — даём выйти
		return true
	if can_stand(c.pos + move):
		c.pos += move
		return true
	# Скольжение: пробуем составляющие по осям
	var moved = false
	for axis in [Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
		if axis != Vector2.ZERO and can_stand(c.pos + axis):
			c.pos += axis
			moved = true
	return moved
