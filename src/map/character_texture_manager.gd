class_name CharacterTextureManager
extends RefCounted

const RACES: Array[String] = ["desert", "savanna", "north"]

static var race_textures: Dictionary = {
	"desert": {},
	"savanna": {},
	"north": {}
}

# Привязка игровых профессий к конкретным спрайтам ролей из ТЗ
static var job_to_roles: Dictionary = {
	"leader": ["leader_m", "leader_f", "elder_m", "elder_f"],
	"hunter": ["hunter_m", "hunter_f", "villager_ranger_m"],
	"forager": ["forager_m", "forager_f"],
	"farmer": ["farmer_m", "farmer_f"],
	"fisherman": ["fisherman_m", "fisherman_f", "villager_ranger_m"],
	"woodcutter": ["woodcutter_m", "woodcutter_f", "villager_ranger_m"],
	"quarryman": ["mason_m", "mason_f"],
	"miner": ["miner_m", "miner_f"],
	"builder": ["builder_m", "builder_f"],
	"craftsman": ["blacksmith_m", "potter_m", "potter_f", "weaver_f"],
	"sage": ["sage_m", "sage_f"],
	"priest": ["priest_m", "priest_f"],
	"warrior": ["warrior_m", "warrior_f", "spearman_m", "spearman_f", "villager_ranger_m"],
	"guard": ["guard_m", "guard_f", "spearman_m", "spearman_f", "villager_ranger_m"],
	"archer": ["archer_m", "archer_f", "villager_ranger_m"],
	"general": ["commander_m", "commander_f", "veteran_m", "veteran_f"],
	"elder": ["grandpa_staff", "grandma", "elder_citizen_m", "elder_citizen_f", "senior_m", "senior_f"],
	"child": ["child_boy_1", "child_girl_1", "child_boy_2", "child_girl_2"],
	"teenager": ["teen_boy_1", "teen_boy_2", "teen_girl_1", "teen_girl_2"],
	"family": ["mother_baby", "father_baby"],
	"villager": ["villager_brown_m", "villager_green_f", "villager_blue_m", "villager_red_f", "adult_1", "adult_2", "adult_3", "adult_4", "villager_ranger_m"]
}

static var is_loaded: bool = false

# Généric-поза действия поверх портрета жителя (не привязана к расе) — сейчас только рубка/переноска дров
static var action_textures: Dictionary = {}
static var actions_loaded: bool = false

static func load_all_actions() -> void:
	if actions_loaded:
		return
	var dir_path = "res://Assets/characters/_actions"
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var f_name = dir.get_next()
		while f_name != "":
			if not dir.current_is_dir() and f_name.ends_with(".png") and not f_name.ends_with(".import"):
				var key = f_name.replace(".png", "")
				var full_p = dir_path + "/" + f_name
				var tex: Texture2D = null
				if ResourceLoader.exists(full_p):
					tex = load(full_p)
				if tex == null and FileAccess.file_exists(full_p):
					var g_path = ProjectSettings.globalize_path(full_p)
					var img = Image.load_from_file(g_path)
					if img:
						tex = ImageTexture.create_from_image(img)
				if tex:
					action_textures[key] = tex
			f_name = dir.get_next()
	actions_loaded = true

static func get_action_texture(name: String) -> Texture2D:
	load_all_actions()
	return action_textures.get(name, null)

static func load_all() -> void:
	if is_loaded:
		return

	for race_id in RACES:
		var dir_path = "res://Assets/characters/%s" % race_id
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var f_name = dir.get_next()
			while f_name != "":
				if not dir.current_is_dir() and f_name.ends_with(".png") and not f_name.ends_with(".import"):
					var role_key = f_name.replace(".png", "")
					var full_p = dir_path + "/" + f_name
					var tex: Texture2D = null
					if ResourceLoader.exists(full_p):
						tex = load(full_p)
					if tex == null and FileAccess.file_exists(full_p):
						var g_path = ProjectSettings.globalize_path(full_p)
						var img = Image.load_from_file(g_path)
						if img:
							tex = ImageTexture.create_from_image(img)
					if tex:
						race_textures[race_id][role_key] = tex
				f_name = dir.get_next()
				
	is_loaded = true

static func get_character_for_job(job_id: String, seed_val: int = 0, race_id: String = "", gender: String = "") -> Texture2D:
	load_all()
	var effective_race = race_id
	if effective_race == "":
		effective_race = GameManager.player_race if "player_race" in GameManager else "north"
	if not race_textures.has(effective_race):
		effective_race = "north"
		
	var pool = job_to_roles.get(job_id, job_to_roles["villager"])
	if gender != "":
		var filtered = []
		for r in pool:
			if gender == "m":
				if r.ends_with("_m") or r in ["adult_1", "adult_3", "child_boy_1", "child_boy_2", "teen_boy_1", "teen_boy_2", "grandpa_staff", "father_baby"]:
					filtered.append(r)
			elif gender == "f":
				if r.ends_with("_f") or r in ["adult_2", "adult_4", "child_girl_1", "child_girl_2", "teen_girl_1", "teen_girl_2", "grandma", "mother_baby"]:
					filtered.append(r)
		if not filtered.is_empty():
			pool = filtered

	var picked_role = pool[abs(seed_val) % pool.size()]
	
	var tex = race_textures[effective_race].get(picked_role, null)
	if tex == null:
		# Фолбек на подходящего по полу жителя расы
		var fallback_key = "villager_brown_m" if gender != "f" else "villager_green_f"
		tex = race_textures[effective_race].get(fallback_key, null)
	return tex

static func get_role_texture(race_id: String, role_name: String) -> Texture2D:
	load_all()
	var race_dict = race_textures.get(race_id, race_textures["north"])
	return race_dict.get(role_name, null)

static func get_leader_portrait(faction_id: String) -> Texture2D:
	load_all()
	var race_id = "north"
	if faction_id == GameManager.player_faction_id:
		race_id = GameManager.player_race
	elif GameManager.faction_races.has(faction_id):
		race_id = GameManager.faction_races[faction_id]
	else:
		var hash_val = abs(faction_id.hash())
		race_id = RACES[hash_val % RACES.size()]
		
	var pool = ["leader_m", "leader_f", "elder_m", "elder_f", "commander_m", "commander_f"]
	var f_hash = abs(faction_id.hash())
	var role = pool[f_hash % pool.size()] if faction_id != GameManager.player_faction_id else "leader_m"
	return get_role_texture(race_id, role)

static func get_random_race_character(race_id: String, seed_val: int = 0) -> Texture2D:
	load_all()
	var race_dict = race_textures.get(race_id, race_textures["north"])
	var keys = race_dict.keys()
	if keys.is_empty():
		return null
	var key = keys[abs(seed_val) % keys.size()]
	return race_dict[key]
