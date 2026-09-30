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
		"animal_pen", "grave",
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

	# Подключаем ассеты Охотничьего лагеря из Assets/buildings/dom_ohotnika/
	_load_if_exists("hunting_camp", "res://Assets/buildings/dom_ohotnika/hunter_lodge.png")
	_load_if_exists("hunter_lodge", "res://Assets/buildings/dom_ohotnika/hunter_lodge.png")
	_load_if_exists("dom_ohotnika", "res://Assets/buildings/dom_ohotnika/hunter_lodge.png")
	_load_if_exists("destr_hunting_camp", "res://Assets/buildings/dom_ohotnika/destr_hunter_lodge.png")
	_load_if_exists("destr_hunter_lodge", "res://Assets/buildings/dom_ohotnika/destr_hunter_lodge.png")
	_load_if_exists("hunter_shelter", "res://Assets/buildings/dom_ohotnika/hunter_shelter.png")
	_load_if_exists("hunt_campfire", "res://Assets/buildings/dom_ohotnika/hunt_campfire.png")
	_load_if_exists("hunt_weapon_rack", "res://Assets/buildings/dom_ohotnika/hunt_weapon_rack.png")
	_load_if_exists("hunt_fur_rack", "res://Assets/buildings/dom_ohotnika/hunt_fur_rack.png")
	_load_if_exists("hunt_butcher_table", "res://Assets/buildings/dom_ohotnika/hunt_butcher_table.png")
	_load_if_exists("hunt_dogs", "res://Assets/buildings/dom_ohotnika/hunt_dogs.png")
	_load_if_exists("grave", "res://Assets/buildings/grave.png")
	_load_if_exists("cemetery", "res://Assets/buildings/grave.png")

	# Подключаем ассеты модульных заборов и ворот
	_load_if_exists("wooden_fence", "res://Assets/buildings/wooden_fence.png")
	_load_if_exists("fence_horizontal", "res://Assets/buildings/fence/fence_horizontal.png")
	_load_if_exists("fence_horizontal_short", "res://Assets/buildings/fence/fence_horizontal_short.png")
	_load_if_exists("fence_vertical", "res://Assets/buildings/fence/fence_vertical.png")
	_load_if_exists("fence_corner", "res://Assets/buildings/fence/fence_corner.png")
	_load_if_exists("fence_corner_flipped", "res://Assets/buildings/fence/fence_corner_flipped.png")
	_load_if_exists("fence_diag_nw_se", "res://Assets/buildings/fence/fence_diag_nw_se.png")
	_load_if_exists("fence_diag_ne_sw", "res://Assets/buildings/fence/fence_diag_ne_sw.png")
	_load_if_exists("fence_plank", "res://Assets/buildings/fence/fence_plank.png")
	_load_if_exists("fence_post", "res://Assets/buildings/fence/fence_post.png")
	_load_if_exists("fence_solid", "res://Assets/buildings/fence/fence_solid.png")
	_load_if_exists("wooden_gate", "res://Assets/buildings/wooden_gate.png")
	_load_if_exists("wooden_gate_closed", "res://Assets/buildings/wooden_gate.png")
	_load_if_exists("wooden_gate_open", "res://Assets/buildings/wooden_gate_open.png")
	_load_if_exists("gate_closed", "res://Assets/buildings/fence/gate_closed.png")
	_load_if_exists("gate_open", "res://Assets/buildings/fence/gate_open.png")

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
	
	# Подключаем ассеты Стоянки собирателей и аграрного комплекса из Assets/buildings/foraging/extracted/
	_load_if_exists("foraging_post", "res://Assets/buildings/foraging/extracted/foraging_post.png")
	_load_if_exists("foraging_post_main", "res://Assets/buildings/foraging/extracted/foraging_post_main.png")
	_load_if_exists("destr_foraging_post", "res://Assets/buildings/foraging/extracted/destr_foraging_post.png")
	
	_load_if_exists("seed_store", "res://Assets/buildings/foraging/extracted/seed_store.png")
	_load_if_exists("destr_seed_store", "res://Assets/buildings/foraging/extracted/destr_seed_store.png")
	
	_load_if_exists("primitive_garden", "res://Assets/buildings/foraging/extracted/garden_stage_3.png")
	_load_if_exists("primitive_garden_stage_1", "res://Assets/buildings/foraging/extracted/garden_stage_1.png")
	_load_if_exists("primitive_garden_stage_2", "res://Assets/buildings/foraging/extracted/garden_stage_2.png")
	_load_if_exists("primitive_garden_stage_3", "res://Assets/buildings/foraging/extracted/garden_stage_3.png")
	_load_if_exists("primitive_garden_stage_4", "res://Assets/buildings/foraging/extracted/garden_stage_4.png")
	_load_if_exists("primitive_garden_stage_5", "res://Assets/buildings/foraging/extracted/garden_stage_5.png")
	_load_if_exists("primitive_garden_stage_6", "res://Assets/buildings/foraging/extracted/garden_stage_6.png")
	
	_load_if_exists("primitive_field", "res://Assets/buildings/foraging/extracted/wheat_field_stage_4.png")
	_load_if_exists("wheat_field", "res://Assets/buildings/foraging/extracted/wheat_field_stage_5.png")
	_load_if_exists("large_field", "res://Assets/buildings/foraging/extracted/wheat_field_stage_6.png")
	_load_if_exists("wheat_field_stage_1", "res://Assets/buildings/foraging/extracted/wheat_field_stage_1.png")
	_load_if_exists("wheat_field_stage_2", "res://Assets/buildings/foraging/extracted/wheat_field_stage_2.png")
	_load_if_exists("wheat_field_stage_3", "res://Assets/buildings/foraging/extracted/wheat_field_stage_3.png")
	_load_if_exists("wheat_field_stage_4", "res://Assets/buildings/foraging/extracted/wheat_field_stage_4.png")
	_load_if_exists("wheat_field_stage_5", "res://Assets/buildings/foraging/extracted/wheat_field_stage_5.png")
	_load_if_exists("wheat_field_stage_6", "res://Assets/buildings/foraging/extracted/wheat_field_stage_6.png")
	
	_load_if_exists("threshing_floor", "res://Assets/buildings/foraging/extracted/threshing_floor.png")
	_load_if_exists("quern_house", "res://Assets/buildings/foraging/extracted/foraging_quern.png")
	_load_if_exists("bakery", "res://Assets/buildings/foraging/extracted/foraging_grain_station.png")
	_load_if_exists("orchard", "res://Assets/buildings/foraging/extracted/garden_stage_5.png")
	_load_if_exists("irrigation_ditch", "res://Assets/buildings/foraging/extracted/irrigation_ditch_h.png")
	_load_if_exists("irrigation_sluice", "res://Assets/buildings/foraging/extracted/irrigation_sluice.png")
	_load_if_exists("irrigation_reservoir", "res://Assets/buildings/foraging/extracted/irrigation_reservoir.png")
	
	_load_if_exists("foraging_baskets", "res://Assets/buildings/foraging/extracted/foraging_baskets.png")
	_load_if_exists("foraging_sorting_table", "res://Assets/buildings/foraging/extracted/foraging_sorting_table.png")
	_load_if_exists("foraging_drying_racks", "res://Assets/buildings/foraging/extracted/foraging_drying_racks.png")
	_load_if_exists("foraging_storage_pit", "res://Assets/buildings/foraging/extracted/foraging_storage_pit.png")
	_load_if_exists("foraging_test_plot", "res://Assets/buildings/foraging/extracted/foraging_test_plot.png")
	_load_if_exists("foraging_grain_station", "res://Assets/buildings/foraging/extracted/foraging_grain_station.png")
	_load_if_exists("foraging_seed_sorting", "res://Assets/buildings/foraging/extracted/seed_sorting_table.png")
	
	_load_if_exists("ox_cart", "res://Assets/buildings/foraging/extracted/ox_cart.png")
	_load_if_exists("ox_plow", "res://Assets/buildings/foraging/extracted/ox_plow.png")
	
	# Привязка алиасов
	if not textures.has("watchtower") and textures.has("tower_blue"):
		textures["watchtower"] = textures["tower_blue"]
	if not textures.has("elders_house") and textures.has("house_2_blue"):
		textures["elders_house"] = textures["house_2_blue"]
	if not textures.has("cemetery") and textures.has("shrine"):
		textures["cemetery"] = textures["shrine"]
	if not textures.has("meeting_place") and textures.has("fire_square"):
		textures["meeting_place"] = textures["fire_square"]
		
	is_loaded = true

static func _load_if_exists(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			textures[key] = res
			return
	if FileAccess.file_exists(path):
		var g_path = ProjectSettings.globalize_path(path)
		var img = Image.load_from_file(g_path)
		if img:
			textures[key] = ImageTexture.create_from_image(img)

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
