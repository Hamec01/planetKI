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
			draw_texture_rect(tex, rect, false)
