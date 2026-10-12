class_name WaterRenderLayer
extends Node2D

const TILE_SIZE: float = 32.0
const WaterShader = preload("res://Assets/shaders/water.gdshader")

@export var map_view: WorldMapView = null

var redraw_timer: float = 0.0

func _ready() -> void:
	var mat = ShaderMaterial.new()
	mat.shader = WaterShader
	material = mat
	z_index = -1 # Рисуется под переходами биомов и остальным содержимым WorldMapView
	if map_view == null:
		map_view = get_parent().get_node_or_null("MapView") as WorldMapView

func _process(delta: float) -> void:
	redraw_timer += delta
	if redraw_timer >= 0.033:
		redraw_timer = 0.0
		queue_redraw()

func _draw() -> void:
	if map_view == null or not map_view.planet_data.has("tiles"):
		return
	var tiles = map_view.planet_data["tiles"]
	var bounds = map_view.get_visible_tile_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	var min_tx = bounds.position.x
	var min_ty = bounds.position.y
	var max_tx = bounds.position.x + bounds.size.x - 1
	var max_ty = bounds.position.y + bounds.size.y - 1

	for y in range(min_ty, max_ty + 1):
		for x in range(min_tx, max_tx + 1):
			var tile = tiles[y][x]
			if not tile.get("is_water", false):
				continue
			var tex = TileTextureManager.get_tile_texture(tile["biome"], tile["coord"], false)
			if tex == null:
				continue
			var rect = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			if tile["biome"] == BiomeDefinitions.BiomeType.DEEP_OCEAN:
				# Глубина темнеет постепенно: одиночная «яма» среди мелководья не выглядит чёрным квадратом
				var deep_n = 0
				var total_n = 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var ny = y + dy
						var nx = x + dx
						if ny < 0 or ny >= tiles.size() or nx < 0 or nx >= tiles[ny].size():
							continue
						total_n += 1
						if tiles[ny][nx]["biome"] == BiomeDefinitions.BiomeType.DEEP_OCEAN:
							deep_n += 1
				if total_n > 0 and deep_n < total_n:
					var shallow = TileTextureManager.get_tile_texture(BiomeDefinitions.BiomeType.SHALLOW_COAST, tile["coord"], false)
					if shallow:
						draw_texture_rect(shallow, rect, false)
						draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.25 + 0.75 * float(deep_n) / float(total_n)))
						continue
			draw_texture_rect(tex, rect, false)
