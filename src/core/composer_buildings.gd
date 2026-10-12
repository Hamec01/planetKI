class_name ComposerBuildings
extends RefCounted

## Central loader, geometry resolver, and runtime renderer for Asset Composer
## settlement buildings (7 bases x 5 states) and modules/upgrades/tools (36 items).

const PACK_ROOT: String = "res://Assets/composer/settlement-buildings-v1/"
const ADULT_CHIBI_HEIGHT: float = 224.0
# Single global scale factor K: adult chibi in game (~8.96 px) / 224 composer units = 0.04
const UNIT_SCALE: float = 0.04
const LOGICAL_FRAME_SIZE: Vector2 = Vector2(600.0, 560.0)

const STATES: Array[String] = ["foundation", "half_built", "complete", "damaged", "ruined"]

# Relative ground offsets (px in game space) for yard upgrades around the building ground pivot (0, 0)
const YARD_UPGRADE_OFFSETS: Dictionary = {
	# Большой дом рода (great_lodge)
	"knowledge_circle": Vector2(40.0, 10.0),
	"clan_totems": Vector2(0.0, -4.0),
	"clan_council": Vector2(-42.0, 12.0),
	
	# Стоянка собирателей (foraging_post)
	"forage_baskets": Vector2(-20.0, 8.0),
	"forage_sorting_table": Vector2(22.0, -8.0),
	"forage_drying_racks": Vector2(-22.0, -10.0),
	"forage_storage_pit": Vector2(22.0, 10.0),
	"forage_route_markers": Vector2(28.0, 2.0),
	"forage_seed_sorting": Vector2(0.0, 12.0),
	"forage_test_plot": Vector2(-26.0, 12.0),
	"forage_grain_station": Vector2(14.0, 14.0),
	
	# Охотничий лагерь (hunting_camp)
	"hunt_tracking": Vector2(-24.0, -12.0),
	"hunt_butchering_area": Vector2(24.0, 6.0),
	"hunt_butcher_table": Vector2(24.0, 6.0),
	"hunt_master_butcher": Vector2(30.0, -4.0),
	"hunt_weapon_rack": Vector2(18.0, -14.0),
	"hunt_target": Vector2(-30.0, 6.0),
	"hunt_mentor": Vector2(-18.0, 10.0),
	"hunt_dogs": Vector2(-32.0, -8.0),
	"hunt_outpost": Vector2(34.0, 12.0),
	"hunt_trophies": Vector2(-12.0, -18.0),
	"hunt_smokehouse": Vector2(20.0, -16.0),
}

# Interior module blueprint offsets for dedicated interior preview mode
const INTERIOR_PREVIEW_OFFSETS: Dictionary = {
	"great_hearth": Vector2(0.0, -16.0),
	"partitions": Vector2(-26.0, -22.0),
	"nursery_corner": Vector2(-28.0, -6.0),
	"caretaker_quarters": Vector2(-28.0, 12.0),
	"elders_quarters": Vector2(28.0, -22.0),
	"communal_store": Vector2(28.0, -6.0),
	"infirmary_corner": Vector2(28.0, 12.0),
}

static var manifest: Dictionary = {}
static var upgrades_manifest: Dictionary = {}
static var buildings_by_id: Dictionary = {}
static var upgrades_by_id: Dictionary = {}
static var upgrades_by_game_id: Dictionary = {}
static var textures: Dictionary = {}
static var is_loaded: bool = false
static var load_errors: Array[String] = []

static func ready_pack() -> bool:
	if is_loaded:
		return not buildings_by_id.is_empty()
	is_loaded = true
	load_errors.clear()
	
	# 1. Загрузка manifest.json (здания)
	var m_path = PACK_ROOT + "manifest.json"
	if not FileAccess.file_exists(m_path) and not ResourceLoader.exists(m_path):
		load_errors.append("Manifest not found: " + m_path)
		push_error("ComposerBuildings: manifest.json not found at " + m_path)
		return false
	
	var m_raw = FileAccess.get_file_as_string(m_path)
	var m_json = JSON.parse_string(m_raw)
	if not m_json is Dictionary:
		load_errors.append("Failed to parse manifest.json")
		push_error("ComposerBuildings: failed to parse manifest.json")
		return false
	
	manifest = m_json
	if int(manifest.get("version", 0)) != 1:
		load_errors.append("Unsupported manifest version: %s" % str(manifest.get("version")))
		push_warning("ComposerBuildings: unexpected manifest version %s" % str(manifest.get("version")))
	
	var base_atlas_size = manifest.get("atlasSize", [1536, 1024])
	var raw_buildings = manifest.get("buildings", [])
	for b in raw_buildings:
		if not b is Dictionary: continue
		var b_id = String(b.get("id", ""))
		if b_id == "": continue
		var scale = float(b.get("scale", 3.0))
		var frames = b.get("frames", [])
		if frames.size() < 5:
			load_errors.append("Building %s has only %d frames (expected 5)" % [b_id, frames.size()])
		
		# Валидация прямоугольников
		for i in range(frames.size()):
			var f = frames[i]
			if f.size() >= 4:
				var rx = float(f[0])
				var ry = float(f[1])
				var rw = float(f[2])
				var rh = float(f[3])
				if rx < 0 or ry < 0 or rx + rw > base_atlas_size[0] or ry + rh > base_atlas_size[1]:
					load_errors.append("Building %s frame %d [%f,%f,%f,%f] out of atlas bounds [%d,%d]" % [b_id, i, rx, ry, rw, rh, base_atlas_size[0], base_atlas_size[1]])
		
		buildings_by_id[b_id] = {
			"id": b_id,
			"name": String(b.get("name", b_id)),
			"file": String(b.get("file", "")),
			"scale": scale,
			"frames": frames,
			"gameMapping": String(b.get("gameMapping", b_id)),
			"layersReady": bool(b.get("layersReady", false)),
			"interactionReady": bool(b.get("interactionReady", false))
		}
	
	# 2. Загрузка upgrades.json (улучшения и предметы)
	var u_path = PACK_ROOT + "upgrades.json"
	if not FileAccess.file_exists(u_path) and not ResourceLoader.exists(u_path):
		load_errors.append("Upgrades manifest not found: " + u_path)
		push_error("ComposerBuildings: upgrades.json not found at " + u_path)
		return false
	
	var u_raw = FileAccess.get_file_as_string(u_path)
	var u_json = JSON.parse_string(u_raw)
	if not u_json is Dictionary:
		load_errors.append("Failed to parse upgrades.json")
		push_error("ComposerBuildings: failed to parse upgrades.json")
		return false
	
	upgrades_manifest = u_json
	var atlas_sizes: Dictionary = upgrades_manifest.get("atlasSizes", {})
	var raw_items = upgrades_manifest.get("items", [])
	for it in raw_items:
		if not it is Dictionary: continue
		var item_id = String(it.get("id", ""))
		var building_id = String(it.get("buildingId", ""))
		var upgrade_id = String(it.get("upgradeId", ""))
		var atlas = String(it.get("atlas", ""))
		var s_rect = it.get("sourceRect", [0, 0, 0, 0])
		var world_width = float(it.get("worldWidth", 300.0))
		var placement = String(it.get("placement", "yard"))
		
		var aw = float(atlas_sizes.get(atlas, [1536, 1024])[0])
		var ah = float(atlas_sizes.get(atlas, [1536, 1024])[1])
		var rx = float(s_rect[0])
		var ry = float(s_rect[1])
		var rw = float(s_rect[2])
		var rh = float(s_rect[3])
		if rx < 0 or ry < 0 or rx + rw > aw or ry + rh > ah:
			load_errors.append("Item %s rect [%f,%f,%f,%f] out of atlas %s bounds [%f,%f]" % [item_id, rx, ry, rw, rh, atlas, aw, ah])
		
		var entry = {
			"id": item_id,
			"buildingId": building_id,
			"upgradeId": upgrade_id,
			"name": String(it.get("name", upgrade_id)),
			"atlas": atlas,
			"file": atlas + ".png",
			"sourceRect": s_rect,
			"worldWidth": world_width,
			"placement": placement,
			"states": it.get("states", ["complete"]),
			"layersReady": bool(it.get("layersReady", false)),
			"interactionReady": bool(it.get("interactionReady", false))
		}
		upgrades_by_id[item_id] = entry
		upgrades_by_game_id[upgrade_id] = entry
		# Добавляем алиас для связки hunt_butchering_area -> hunt_butcher_table
		if upgrade_id == "hunt_butchering_area":
			upgrades_by_game_id["hunt_butcher_table"] = entry
	
	return not buildings_by_id.is_empty()

static func texture(file_or_atlas: String) -> Texture2D:
	var file = file_or_atlas
	if not file.ends_with(".png"):
		file = file + ".png"
	if textures.has(file):
		return textures[file]
	
	var path = PACK_ROOT + file
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			tex = ImageTexture.create_from_image(img)
	
	if tex == null:
		push_error("ComposerBuildings: failed to load texture: " + path)
	else:
		textures[file] = tex
	return tex

static func has_building(b_id: String) -> bool:
	if not ready_pack(): return false
	return buildings_by_id.has(b_id)

static func get_building_data(b_id: String) -> Dictionary:
	if not ready_pack(): return {}
	return buildings_by_id.get(b_id, {})

static func has_upgrade(id_or_upgrade: String) -> bool:
	if not ready_pack(): return false
	return upgrades_by_id.has(id_or_upgrade) or upgrades_by_game_id.has(id_or_upgrade)

static func get_upgrade_data(id_or_upgrade: String) -> Dictionary:
	if not ready_pack(): return {}
	if upgrades_by_id.has(id_or_upgrade):
		return upgrades_by_id[id_or_upgrade]
	if upgrades_by_game_id.has(id_or_upgrade):
		return upgrades_by_game_id[id_or_upgrade]
	return {}

static func state_to_index(state: String) -> int:
	match state:
		"foundation": return 0
		"half_built": return 1
		"complete": return 2
		"damaged": return 3
		"ruined": return 4
		_: return 2

static func resolve_building_state(status: String, condition: float, progress_pct: float = 1.0) -> String:
	if status == "constructing":
		return "foundation" if progress_pct < 0.5 else "half_built"
	if condition <= 0.0:
		return "ruined"
	if condition < 50.0:
		return "damaged"
	return "complete"

## Отрисовка здания через CanvasItem в текущих мировых координатах игры.
## ground_pos — опора на земле (низ центра здания).
static func draw_building(canvas: CanvasItem, b_id: String, state: String, ground_pos: Vector2, modulate: Color = Color.WHITE) -> bool:
	if not ready_pack() or not buildings_by_id.has(b_id):
		return false
	var b = buildings_by_id[b_id]
	var tex = texture(b["file"])
	if tex == null:
		return false
	
	var idx = clampi(state_to_index(state), 0, b["frames"].size() - 1)
	var f: Array = b["frames"][idx]
	var src_rect = Rect2(float(f[0]), float(f[1]), float(f[2]), float(f[3]))
	
	var s: float = float(b["scale"]) * UNIT_SCALE
	var dst_w: float = src_rect.size.x * s
	var dst_h: float = src_rect.size.y * s
	var dst_rect = Rect2(ground_pos.x - dst_w * 0.5, ground_pos.y - dst_h, dst_w, dst_h)
	
	canvas.draw_texture_rect_region(tex, dst_rect, src_rect, modulate)
	return true

## Размер спрайта завершённого здания на карте (px) — по нему проверяется перекрытие построек
static func get_sprite_size(b_id: String) -> Vector2:
	if not ready_pack() or not buildings_by_id.has(b_id):
		return Vector2.ZERO
	var b = buildings_by_id[b_id]
	var frames: Array = b["frames"]
	if frames.is_empty():
		return Vector2.ZERO
	var f: Array = frames[clampi(2, 0, frames.size() - 1)]
	var s: float = float(b["scale"]) * UNIT_SCALE
	return Vector2(float(f[2]) * s, float(f[3]) * s)

## Логический холст здания frameSize * scale * K (600x560 до масштаба).
## Сохраняет стабильный логический габарит при смене строительных состояний.
static func get_building_canvas_rect(b_id: String, ground_pos: Vector2) -> Rect2:
	if not ready_pack() or not buildings_by_id.has(b_id):
		return Rect2(ground_pos, Vector2.ZERO)
	var b = buildings_by_id[b_id]
	var s: float = float(b.get("scale", 4.0)) * UNIT_SCALE
	var f_size: Array = b.get("frameSize", [600, 560])
	var w: float = float(f_size[0]) * s
	var h: float = float(f_size[1]) * s
	return Rect2(ground_pos.x - w * 0.5, ground_pos.y - h, w, h)

## Отрисовка улучшения или предмета через CanvasItem.
## ground_pos — опора на земле предмета.
static func draw_upgrade(canvas: CanvasItem, id_or_upgrade: String, ground_pos: Vector2, modulate: Color = Color.WHITE) -> bool:
	if not ready_pack(): return false
	var it = get_upgrade_data(id_or_upgrade)
	if it.is_empty(): return false
	var tex = texture(it["atlas"])
	if tex == null: return false
	
	var r: Array = it["sourceRect"]
	var src_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var s: float = (float(it["worldWidth"]) / src_rect.size.x) * UNIT_SCALE
	var dst_w: float = src_rect.size.x * s
	var dst_h: float = src_rect.size.y * s
	var dst_rect = Rect2(ground_pos.x - dst_w * 0.5, ground_pos.y - dst_h, dst_w, dst_h)
	
	canvas.draw_texture_rect_region(tex, dst_rect, src_rect, modulate)
	return true

## Возвращает AtlasTexture для UI или кнопок инспектора
static func get_building_atlas_texture(b_id: String, state: String = "complete") -> AtlasTexture:
	if not ready_pack() or not buildings_by_id.has(b_id):
		return null
	var b = buildings_by_id[b_id]
	var tex = texture(b["file"])
	if tex == null: return null
	var idx = clampi(state_to_index(state), 0, b["frames"].size() - 1)
	var f: Array = b["frames"][idx]
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(float(f[0]), float(f[1]), float(f[2]), float(f[3]))
	at.filter_clip = true
	return at

## Возвращает AtlasTexture для предмета или улучшения
static func get_upgrade_atlas_texture(id_or_upgrade: String) -> AtlasTexture:
	if not ready_pack(): return null
	var it = get_upgrade_data(id_or_upgrade)
	if it.is_empty(): return null
	var tex = texture(it["atlas"])
	if tex == null: return null
	var r: Array = it["sourceRect"]
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	at.filter_clip = true
	return at

## Создание Sprite2D узла по точному контракту документации передачи
static func make_visual(tex: Texture2D, rect: Rect2, source_scale: float, k: float, ground_position: Vector2) -> Node2D:
	var root := Node2D.new()
	root.position = ground_position
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = rect
	sprite.region_filter_clip_enabled = true
	sprite.centered = false
	var s := source_scale * k
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(-rect.size.x * s * 0.5, -rect.size.y * s)
	root.add_child(sprite)
	return root

static func get_yard_offset(upgrade_id: String) -> Vector2:
	return YARD_UPGRADE_OFFSETS.get(upgrade_id, Vector2.ZERO)

static func get_interior_offset(upgrade_id: String) -> Vector2:
	return INTERIOR_PREVIEW_OFFSETS.get(upgrade_id, Vector2.ZERO)

static func is_yard_upgrade(id_or_upgrade: String) -> bool:
	var it = get_upgrade_data(id_or_upgrade)
	return it.get("placement", "") == "yard"

static func is_interior_upgrade(id_or_upgrade: String) -> bool:
	var it = get_upgrade_data(id_or_upgrade)
	return it.get("placement", "") == "interior"

static func is_prop(id_or_upgrade: String) -> bool:
	var it = get_upgrade_data(id_or_upgrade)
	return it.get("placement", "") == "prop"

static func get_all_building_ids() -> Array:
	if not ready_pack(): return []
	return buildings_by_id.keys()

static func get_all_upgrade_ids() -> Array:
	if not ready_pack(): return []
	return upgrades_by_id.keys()
