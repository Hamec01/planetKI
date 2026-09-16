class_name CustomMapManager
extends RefCounted

const MAPS_DIR: String = "user://custom_maps"

static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(MAPS_DIR)

static func create_blank_map(width: int = 48, height: int = 48, default_biome: int = BiomeDefinitions.BiomeType.PLAINS) -> Dictionary:
	var tiles: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			var is_water = (default_biome == BiomeDefinitions.BiomeType.DEEP_OCEAN or default_biome == BiomeDefinitions.BiomeType.SHALLOW_COAST)
			row.append({
				"coord": Vector2i(x, y),
				"biome": default_biome,
				"elevation": 0.2 if is_water else 0.5,
				"temperature": 0.5,
				"moisture": 0.5,
				"is_water": is_water,
				"is_river": false,
				"resource": null,
				"settlement_id": "",
				"nature_object": "", # Имя конкретного спрайта из редактора
				"road": false
			})
		tiles.append(row)
		
	return {
		"name": "Новая карта",
		"width": width,
		"height": height,
		"tiles": tiles,
		"spawns": {
			"player": {"pos": Vector2i(width / 2, height / 2), "name": "Стоянка Первого Костра"},
			"ai": []
		}
	}

static func save_map(map_data: Dictionary, map_name: String) -> bool:
	ensure_dir()
	var clean_name = map_name.strip_edges()
	if clean_name == "":
		clean_name = "custom_map"
	map_data["name"] = clean_name
	
	var file_path = "%s/%s.json" % [MAPS_DIR, clean_name]
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
		
	# Сериализация тайлов
	var serialized: Dictionary = {
		"name": map_data["name"],
		"width": map_data["width"],
		"height": map_data["height"],
		"spawns": {
			"player": {
				"pos": [map_data["spawns"]["player"]["pos"].x, map_data["spawns"]["player"]["pos"].y],
				"name": map_data["spawns"]["player"]["name"]
			},
			"ai": []
		},
		"tiles": []
	}
	
	for ai_s in map_data["spawns"].get("ai", []):
		serialized["spawns"]["ai"].append({
			"pos": [ai_s["pos"].x, ai_s["pos"].y],
			"name": ai_s.get("name", "ИИ-племя")
		})
		
	for y in range(map_data["height"]):
		var row_data: Array = []
		for x in range(map_data["width"]):
			var t = map_data["tiles"][y][x]
			row_data.append({
				"b": t["biome"],
				"w": t["is_water"],
				"n": t.get("nature_object", ""),
				"res": t.get("resource", null)
			})
		serialized["tiles"].append(row_data)
		
	var json_str = JSON.stringify(serialized, "  ")
	file.store_string(json_str)
	file.close()
	return true

static func load_map(map_name: String) -> Dictionary:
	var file_path = "%s/%s.json" % [MAPS_DIR, map_name]
	if not FileAccess.file_exists(file_path):
		return {}
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
		
	var text = file.get_as_text()
	file.close()
	
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
		
	var width = parsed["width"]
	var height = parsed["height"]
	var tiles: Array = []
	
	for y in range(height):
		var row: Array = []
		for x in range(width):
			var raw_t = parsed["tiles"][y][x]
			var is_water = raw_t.get("w", false)
			row.append({
				"coord": Vector2i(x, y),
				"biome": raw_t.get("b", BiomeDefinitions.BiomeType.PLAINS),
				"elevation": 0.2 if is_water else 0.5,
				"temperature": 0.5,
				"moisture": 0.5,
				"is_water": is_water,
				"is_river": false,
				"resource": raw_t.get("res", null),
				"settlement_id": "",
				"nature_object": raw_t.get("n", ""),
				"road": false
			})
		tiles.append(row)
		
	var p_pos_arr = parsed["spawns"]["player"]["pos"]
	var result: Dictionary = {
		"name": parsed["name"],
		"width": width,
		"height": height,
		"tiles": tiles,
		"spawns": {
			"player": {
				"id": "player_tribe",
				"name": parsed["spawns"]["player"].get("name", "Стоянка Первого Костра"),
				"pos": Vector2i(p_pos_arr[0], p_pos_arr[1]),
				"leader_name": "Вожак",
				"color": Color(0.2, 0.7, 1.0),
				"culture": "desert_nomads" if GameManager.player_race == "desert" else ("savanna_tribes" if GameManager.player_race == "savanna" else "northern_clans")
			},
			"ai": []
		}
	}
	
	for i in range(parsed["spawns"].get("ai", []).size()):
		var raw_ai = parsed["spawns"]["ai"][i]
		var ai_pos_arr = raw_ai["pos"]
		result["spawns"]["ai"].append({
			"id": "ai_tribe_%d" % (i + 1),
			"name": raw_ai.get("name", "Племя %d" % (i + 1)),
			"pos": Vector2i(ai_pos_arr[0], ai_pos_arr[1]),
			"leader_name": "Вождь %d" % (i + 1),
			"color": Color(0.9, 0.3, 0.3),
			"culture": "savanna_tribes",
			"personality": "neutral"
		})
		
	return result

static func get_saved_maps_list() -> Array[String]:
	ensure_dir()
	var result: Array[String] = []
	var dir = DirAccess.open(MAPS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				result.append(file_name.replace(".json", ""))
			file_name = dir.get_next()
	return result
