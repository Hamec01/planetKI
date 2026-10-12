extends Node

const ComposerBuildings = preload("res://src/core/composer_buildings.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	call_deferred("run")

func run() -> void:
	print("--- TESTING COMPOSER BUILDINGS INTEGRATION ---")
	
	# 1. Загрузка пакета
	var ready = ComposerBuildings.ready_pack()
	check(ready, "ComposerBuildings.ready_pack() must succeed")
	check(ComposerBuildings.load_errors.is_empty(), "No load errors allowed, got: %s" % str(ComposerBuildings.load_errors))
	
	# 2. Проверка 7 зданий
	var expected_buildings = ["tannery", "seed_store", "great_lodge", "foraging_post", "hunting_camp", "quern_house", "bakery"]
	check(ComposerBuildings.get_all_building_ids().size() == 7, "Must have exactly 7 buildings loaded (got %d)" % ComposerBuildings.get_all_building_ids().size())
	for b_id in expected_buildings:
		check(ComposerBuildings.has_building(b_id), "Building %s must exist in catalog" % b_id)
		var b_data = ComposerBuildings.get_building_data(b_id)
		check(b_data["frames"].size() == 5, "Building %s must have 5 state frames" % b_id)
		check(b_data["scale"] in [3.0, 4.0], "Building %s scale must be 3 or 4 (got %f)" % [b_id, b_data["scale"]])
		check(ResourceLoader.exists("res://Assets/composer/settlement-buildings-v1/" + b_data["file"]), "Atlas %s must exist in assets" % b_data["file"])
		
		# Проверка всех 5 состояний и генерации AtlasTexture
		for st in ComposerBuildings.STATES:
			var at = ComposerBuildings.get_building_atlas_texture(b_id, st)
			check(at != null and at.atlas != null, "AtlasTexture for %s state %s must load" % [b_id, st])
			check(at.region.size.x > 0 and at.region.size.y > 0, "AtlasTexture for %s state %s must have positive region" % [b_id, st])
	
	# 3. Проверка 36 улучшений и предметов
	var expected_items_count = 36
	var all_upgrades = ComposerBuildings.get_all_upgrade_ids()
	check(all_upgrades.size() == expected_items_count, "Must have exactly 36 items loaded (got %d)" % all_upgrades.size())
	
	# 4. Проверка отдельного кремнёвого серпа (flint_sickle) 1254x1254
	check(ComposerBuildings.has_upgrade("agriculture__flint_sickle"), "agriculture__flint_sickle must exist")
	check(ComposerBuildings.has_upgrade("flint_sickle"), "flint_sickle short ID must exist")
	var sickle_data = ComposerBuildings.get_upgrade_data("flint_sickle")
	check(sickle_data["atlas"] == "flint_sickle", "Sickle must use separate flint_sickle atlas")
	var sickle_tex = ComposerBuildings.texture("flint_sickle.png")
	check(sickle_tex != null, "flint_sickle.png texture must load")
	check(sickle_tex.get_width() == 1254 and sickle_tex.get_height() == 1254, "flint_sickle.png must be 1254x1254 (got %dx%d)" % [sickle_tex.get_width(), sickle_tex.get_height()])
	var sickle_rect = Rect2(sickle_data["sourceRect"][0], sickle_data["sourceRect"][1], sickle_data["sourceRect"][2], sickle_data["sourceRect"][3])
	check(sickle_rect.position.x >= 0 and sickle_rect.end.x <= 1254, "Sickle rect must be within 1254 bounds")
	check(sickle_rect.position.y >= 0 and sickle_rect.end.y <= 1254, "Sickle rect must be within 1254 bounds")
	
	# 5. Проверка единого коэффициента K = 0.04 и масштаба
	check(is_equal_approx(ComposerBuildings.UNIT_SCALE, 0.04), "UNIT_SCALE must be exactly 0.04")
	var adult_game_height = ComposerBuildings.ADULT_CHIBI_HEIGHT * ComposerBuildings.UNIT_SCALE
	check(is_equal_approx(adult_game_height, 8.96), "Adult chibi height in game units must be 8.96 px")
	
	# 6. Проверка Sprite2D конструктора make_visual
	var lodge_complete_rect = Rect2(1024, 33, 506, 432)
	var node = ComposerBuildings.make_visual(sickle_tex, lodge_complete_rect, 4.0, ComposerBuildings.UNIT_SCALE, Vector2(100, 100))
	check(node != null and node.get_child_count() == 1, "make_visual must construct Node2D with Sprite2D")
	var sprite: Sprite2D = node.get_child(0) as Sprite2D
	check(sprite.region_enabled and sprite.region_filter_clip_enabled, "Sprite2D must enable region and filter clip")
	check(is_equal_approx(sprite.scale.x, 4.0 * 0.04), "Sprite2D scale must match source_scale * k")
	node.free()
	
	# 7. Проверка переходов строительных состояний
	check(ComposerBuildings.resolve_building_state("constructing", 100.0, 0.2) == "foundation", "constructing < 50% -> foundation")
	check(ComposerBuildings.resolve_building_state("constructing", 100.0, 0.7) == "half_built", "constructing >= 50% -> half_built")
	check(ComposerBuildings.resolve_building_state("active", 100.0, 1.0) == "complete", "active full hp -> complete")
	check(ComposerBuildings.resolve_building_state("active", 30.0, 1.0) == "damaged", "active damaged hp -> damaged")
	check(ComposerBuildings.resolve_building_state("active", 0.0, 1.0) == "ruined", "active destroyed -> ruined")
	
	# 8. Проверка категорий улучшений (interior, yard, prop)
	check(ComposerBuildings.is_interior_upgrade("great_hearth"), "great_hearth is interior")
	check(ComposerBuildings.is_interior_upgrade("partitions"), "partitions is interior")
	check(ComposerBuildings.is_yard_upgrade("knowledge_circle"), "knowledge_circle is yard")
	check(ComposerBuildings.is_yard_upgrade("clan_totems"), "clan_totems is yard")
	check(ComposerBuildings.is_yard_upgrade("hunt_tracking"), "hunt_tracking is yard")
	check(ComposerBuildings.is_yard_upgrade("forage_baskets"), "forage_baskets is yard")
	check(ComposerBuildings.is_prop("flint_sickle"), "flint_sickle is prop")
	check(ComposerBuildings.is_prop("digging_stick"), "digging_stick is prop")
	
	# 9. Проверка интеграции BuildingTextureManager
	var lodge_tex = BuildingTextureManager.get_texture("great_lodge")
	check(lodge_tex != null, "BuildingTextureManager must serve great_lodge")
	var foundation_tex = BuildingTextureManager.get_texture("composer_great_lodge_foundation")
	check(foundation_tex != null, "BuildingTextureManager must serve discrete state composer_great_lodge_foundation")
	var ruined_tex = BuildingTextureManager.get_texture("destr_great_lodge")
	check(ruined_tex != null, "BuildingTextureManager must serve destr_great_lodge")
	
	# 10. Проверка интеграции ItemTextureManager для сельскохозяйственных орудий
	var sickle_item_tex = ItemTextureManager.get_icon("flint_sickle")
	check(sickle_item_tex != null, "ItemTextureManager must serve flint_sickle from composer pack")
	var hoe_item_tex = ItemTextureManager.get_icon("stone_hoe")
	check(hoe_item_tex != null, "ItemTextureManager must serve stone_hoe from composer pack")
	
	# 11. Проверка EquipmentDB: 5 орудий в WEAPONS и 8 рецептов в RECIPES
	check(EquipmentDB.WEAPONS.has("flint_sickle"), "EquipmentDB.WEAPONS must include flint_sickle")
	check(EquipmentDB.WEAPONS.has("digging_stick"), "EquipmentDB.WEAPONS must include digging_stick")
	check(EquipmentDB.WEAPONS.has("stone_hoe"), "EquipmentDB.WEAPONS must include stone_hoe")
	check(EquipmentDB.WEAPONS.has("wooden_hoe"), "EquipmentDB.WEAPONS must include wooden_hoe")
	check(EquipmentDB.WEAPONS.has("threshing_flail"), "EquipmentDB.WEAPONS must include threshing_flail")
	var expected_recipes = ["flint_sickle", "digging_stick", "stone_hoe", "wooden_hoe", "threshing_flail", "winnowing_sieve", "wooden_ard", "ox_yoke"]
	for r_id in expected_recipes:
		check(EquipmentDB.RECIPES.has(r_id), "EquipmentDB.RECIPES must include %s" % r_id)
		var r_data = EquipmentDB.RECIPES[r_id]
		check(r_data.has("cost") and r_data.has("workshop_type"), "Recipe %s must have cost and workshop_type" % r_id)
	
	# 12. Проверка сериализации сохранений: только ID и состояния, никаких base64 URI
	var b_inst = BuildingInstance.new("inst_test_01", "great_lodge", "player_tribe_settlement", Vector2i(5, 5))
	b_inst.condition = 75.0
	b_inst.unlock_upgrade("great_lodge__nursery_corner")
	b_inst.unlock_upgrade("great_lodge__clan_totems")
	var save_dict = b_inst.serialize()
	check(save_dict["id"] == "inst_test_01", "Serialized id matches")
	check(save_dict["type"] == "great_lodge", "Serialized type matches")
	check(save_dict["unlocked_upgrades"] == ["great_lodge__nursery_corner", "great_lodge__clan_totems"], "Serialized upgrades must be array of string IDs")
	var save_json = JSON.stringify(save_dict)
	check(not save_json.contains("data:image"), "Save file must NEVER contain embedded data:image or base64")
	
	# 13. Проверка геометрии логического холста 600x560 и ground pivot
	var canvas_rect = ComposerBuildings.get_building_canvas_rect("great_lodge", Vector2(100, 200))
	# scale=4.0, K=0.04 -> s = 0.16 -> 600*0.16 = 96, 560*0.16 = 89.6
	check(is_equal_approx(canvas_rect.size.x, 600.0 * 0.16), "Canvas width must be 600 * s")
	check(is_equal_approx(canvas_rect.size.y, 560.0 * 0.16), "Canvas height must be 560 * s")
	check(is_equal_approx(canvas_rect.position.x, 100.0 - (600.0 * 0.16 * 0.5)), "Canvas left must be ground_pos.x - w*0.5")
	check(is_equal_approx(canvas_rect.end.y, 200.0), "Canvas bottom must be exactly ground_pos.y (ground pivot)")
	
	print("COMPOSER BUILDINGS INTEGRATION: ", "PASS" if failures.is_empty() else failures)
	get_tree().quit(0 if failures.is_empty() else 1)

