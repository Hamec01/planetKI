class_name BuildingTextureManager
extends RefCounted

static var textures: Dictionary = {}
static var is_loaded: bool = false

static func load_all() -> void:
	if is_loaded:
		return
		
	var building_ids = [
		"hut", "great_lodge", "hunting_camp", "foraging_post",
		"granary", "woodcutter_camp", "stone_quarry", "ore_pit",
		"craft_workshop", "elders_house", "shrine", "fire_square",
		"palisade", "watchtower", "training_grounds", "fishing_spot", "cemetery",
		"house_1_blue", "house_1_green", "house_1_red", "house_1_yellow",
		"house_2_blue", "house_2_green", "house_2_red", "house_2_yellow",
		"castle_blue", "castle_green", "castle_red", "castle_yellow",
		"tower_blue", "tower_green", "tower_red", "tower_yellow",
		"bridge"
	]
	
	for b_id in building_ids:
		var path = "res://Assets/buildings/%s.png" % b_id
		if ResourceLoader.exists(path):
			textures[b_id] = load(path)
			
	# Подключаем ассеты для хижины и её улучшений из Assets/buildings/House/
	_load_if_exists("hut", "res://Assets/buildings/House/main_house.png")
	_load_if_exists("hut_main", "res://Assets/buildings/House/main_house.png")
	_load_if_exists("hut_annex", "res://Assets/buildings/House/House_update.png")
	_load_if_exists("hut_pantry", "res://Assets/buildings/House/pantry.png")
	_load_if_exists("hut_garden", "res://Assets/buildings/House/garden.png")
	_load_if_exists("hut_shed", "res://Assets/buildings/House/barn.png")
	_load_if_exists("dest_house", "res://Assets/buildings/House/dest_house.png")

	# Подключаем ассеты Большого дома рода (Great Lodge) из Assets/buildings/Dom_roda/
	_load_if_exists("great_lodge", "res://Assets/buildings/Dom_roda/doma_roda.png")
	_load_if_exists("great_lodge_1", "res://Assets/buildings/Dom_roda/doma_roda.png")
	_load_if_exists("great_lodge_2", "res://Assets/buildings/Dom_roda/doma_roda2.png")
	_load_if_exists("great_lodge_3", "res://Assets/buildings/Dom_roda/doma_roda3.png")
	_load_if_exists("great_lodge_4", "res://Assets/buildings/Dom_roda/doma_roda4.png")
	_load_if_exists("great_lodge_5", "res://Assets/buildings/Dom_roda/doma_roda5.png")
	_load_if_exists("great_lodge_6", "res://Assets/buildings/Dom_roda/doma_roda6.png")
	_load_if_exists("great_lodge_7", "res://Assets/buildings/Dom_roda/doma_roda7.png")
	_load_if_exists("great_lodge_8", "res://Assets/buildings/Dom_roda/doma_roda8.png")
	_load_if_exists("great_lodge_9", "res://Assets/buildings/Dom_roda/doma_roda9.png")
	_load_if_exists("destr_great_lodge", "res://Assets/buildings/Dom_roda/destr_doma_roda.png")
	_load_if_exists("great_lodge_nursery", "res://Assets/buildings/Dom_roda/детская пристройка.png")
	_load_if_exists("great_lodge_caretaker", "res://Assets/buildings/Dom_roda/место опекуна.png")
	_load_if_exists("great_lodge_knowledge", "res://Assets/buildings/Dom_roda/круг знаний.png")
	_load_if_exists("great_lodge_store", "res://Assets/buildings/Dom_roda/общие запасы.png")
	_load_if_exists("great_lodge_totems", "res://Assets/buildings/Dom_roda/родовые знания.png")

	# Подключаем новые ассеты из Buildings/
	_load_if_exists("house_1_blue", "res://Buildings/House/house_1_blue.png")
	_load_if_exists("house_1_green", "res://Buildings/House/house_1_green.png")
	_load_if_exists("house_1_red", "res://Buildings/House/house_1_red.png")
	_load_if_exists("house_1_yellow", "res://Buildings/House/house_1_yellow.png")
	_load_if_exists("house_2_blue", "res://Buildings/House/house_2_blue.png")
	_load_if_exists("house_2_green", "res://Buildings/House/house_2_green.png")
	_load_if_exists("house_2_red", "res://Buildings/House/house_2_red.png")
	_load_if_exists("house_2_yellow", "res://Buildings/House/house_2_yellow.png")
	
	_load_if_exists("castle_blue", "res://Buildings/Castle/castle_blue.png")
	_load_if_exists("castle_green", "res://Buildings/Castle/castle_green.png")
	_load_if_exists("castle_red", "res://Buildings/Castle/castle_red.png")
	_load_if_exists("castle_yellow", "res://Buildings/Castle/castle_yellow.png")
	
	_load_if_exists("tower_blue", "res://Buildings/Tower/tower_blue.png")
	_load_if_exists("tower_green", "res://Buildings/Tower/tower_green.png")
	_load_if_exists("tower_red", "res://Buildings/Tower/tower_red.png")
	_load_if_exists("tower_yellow", "res://Buildings/Tower/tower_yellow.png")
	
	_load_if_exists("bridge", "res://Buildings/Bridge/bridge_1x3.png")
	
	# Привязка алиасов
	if not textures.has("watchtower") and textures.has("tower_blue"):
		textures["watchtower"] = textures["tower_blue"]
	if not textures.has("elders_house") and textures.has("house_2_blue"):
		textures["elders_house"] = textures["house_2_blue"]
	if not textures.has("cemetery") and textures.has("shrine"):
		textures["cemetery"] = textures["shrine"]
		
	is_loaded = true

static func _load_if_exists(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		textures[key] = load(path)

static func load_all_textures() -> void:
	load_all()

static func get_texture(building_id: String) -> Texture2D:
	load_all()
	return textures.get(building_id, null)

static func get_faction_building_texture(building_id: String, faction_color: String = "blue") -> Texture2D:
	load_all()
	var key = "%s_%s" % [building_id, faction_color]
	if textures.has(key):
		return textures[key]
	return get_texture(building_id)
