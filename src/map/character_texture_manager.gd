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
	"hunter": ["hunter_m", "hunter_f"],
	"forager": ["forager_m", "forager_f"],
	"farmer": ["farmer_m", "farmer_f"],
	"fisherman": ["fisherman_m", "fisherman_f"],
	"woodcutter": ["woodcutter_m", "woodcutter_f"],
	"quarryman": ["mason_m", "mason_f"],
	"miner": ["miner_m", "miner_f"],
	"builder": ["builder_m", "builder_f"],
	"craftsman": ["blacksmith_m", "potter_m", "potter_f", "weaver_f"],
	"sage": ["sage_m", "sage_f"],
	"priest": ["priest_m", "priest_f"],
	"warrior": ["warrior_m", "warrior_f", "spearman_m", "spearman_f"],
	"guard": ["guard_m", "guard_f", "spearman_m", "spearman_f"],
	"archer": ["archer_m", "archer_f"],
	"general": ["commander_m", "commander_f", "veteran_m", "veteran_f"],
	"elder": ["grandpa_staff", "grandma", "elder_citizen_m", "elder_citizen_f"],
	"child": ["child_boy_1", "child_girl_1", "child_boy_2", "child_girl_2"],
	"teenager": ["teen_boy_1", "teen_boy_2", "teen_girl_1", "teen_girl_2"],
	"family": ["mother_baby", "father_baby"],
	"villager": ["villager_brown_m", "villager_green_f", "villager_blue_m", "villager_red_f", "adult_1", "adult_2", "adult_3", "adult_4"]
}

static var is_loaded: bool = false

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
					var tex = load(full_p)
					if tex:
						race_textures[race_id][role_key] = tex
				f_name = dir.get_next()
				
	is_loaded = true

static func get_character_for_job(job_id: String, seed_val: int = 0, race_id: String = "") -> Texture2D:
	load_all()
	var effective_race = race_id
	if effective_race == "":
		effective_race = GameManager.player_race if "player_race" in GameManager else "north"
	if not race_textures.has(effective_race):
		effective_race = "north"
		
	var pool = job_to_roles.get(job_id, job_to_roles["villager"])
	var picked_role = pool[abs(seed_val) % pool.size()]
	
	var tex = race_textures[effective_race].get(picked_role, null)
	if tex == null:
		# Фолбек на любого жителя расы
		tex = race_textures[effective_race].get("villager_brown_m", null)
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
