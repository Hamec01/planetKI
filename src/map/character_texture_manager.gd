class_name CharacterTextureManager
extends RefCounted

static var character_textures: Array[Texture2D] = []
static var is_loaded: bool = false

# Роли и подходящие индексы спрайтов (1..40)
static var role_indices: Dictionary = {
	"leader": [1, 7, 13, 24, 37],
	"hunter": [4, 18, 29, 39],
	"forager": [6, 25, 34, 21],
	"farmer": [2, 11, 20, 33],
	"woodcutter": [8, 14, 30],
	"quarryman": [17, 22, 38],
	"miner": [17, 22, 38],
	"craftsman": [5, 19, 36],
	"builder": [5, 19, 36],
	"sage": [9, 15, 27, 31],
	"priest": [9, 15, 27, 31],
	"warrior": [10, 16, 26, 40],
	"guard": [10, 16, 26, 40],
	"general": [1, 7, 24, 26],
	"villager": [3, 12, 23, 28, 32, 35]
}

static func load_all() -> void:
	if is_loaded:
		return
		
	character_textures.clear()
	for i in range(1, 41):
		var path = "res://Characters/Character - 128 x 128/character_%03d.png" % i
		if ResourceLoader.exists(path):
			var tex = load(path)
			character_textures.append(tex)
			
	is_loaded = true

static func get_character_texture(char_idx_1_based: int) -> Texture2D:
	load_all()
	if character_textures.is_empty():
		return null
	var idx = clamp(char_idx_1_based - 1, 0, character_textures.size() - 1)
	return character_textures[idx]

static func get_random_character(seed_val: int = 0) -> Texture2D:
	load_all()
	if character_textures.is_empty():
		return null
	var rand_idx = abs(seed_val) % character_textures.size()
	return character_textures[rand_idx]

static func get_character_for_job(job_id: String, seed_val: int = 0) -> Texture2D:
	load_all()
	if character_textures.is_empty():
		return null
		
	var pool = role_indices.get(job_id, role_indices["villager"])
	var picked_idx = pool[abs(seed_val) % pool.size()]
	return get_character_texture(picked_idx)

static func get_leader_portrait(faction_id: String) -> Texture2D:
	load_all()
	if character_textures.is_empty():
		return null
	if faction_id == "player_tribe":
		return get_character_texture(1) # Главный лидер игрока
	var hash_val = abs(faction_id.hash())
	var pool = role_indices["leader"]
	var picked_idx = pool[hash_val % pool.size()]
	return get_character_texture(picked_idx)
