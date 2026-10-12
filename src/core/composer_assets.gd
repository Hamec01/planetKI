class_name ComposerAssets
extends RefCounted

const ROOT = "res://Assets/composer/planetki-chibi/"
static var manifest: Dictionary = {}
static var animations: Dictionary = {}
static var textures: Dictionary = {}
static var _atlas_images: Dictionary = {}
static var tried: bool = false
static var proxies: Dictionary = {}
const WEAPONS = {"club":"weapons_5", "knife":"weapons_2", "work_axe":"weapons_4", "copper_work_axe":"weapons_4", "battle_axe":"weapons_4", "simple_spear":"weapons_1", "reinforced_spear":"weapons_1", "short_sword":"weapons_2", "hunting_bow":"weapons_0", "improved_hunting_bow":"weapons_0", "longbow":"weapons_0"}
const ARMOR = {"clothes":"clothes_0", "padded_armor":"clothes_3", "leather_armor":"clothes_4", "chainmail":"clothes_5"}
const HATS = {"iron_helmet":"helmets_0", "reinforced_helmet":"helmets_2"}
const TOOLS = {"axe":"weapons_4", "pickaxe":"work_tools_0", "hoe":"props_3", "hammer":"work_tools_3", "fishing_rod":"work_tools_1", "rod":"work_tools_1", "knife":"work_tools_2"}
const CARGO = {"wood":"work_stations_12", "stone":"work_stations_14", "metal":"work_stations_10", "food":"work_tools_4", "fish":"work_stations_9", "leather":"work_tools_15", "fur":"work_tools_15", "clothes":"work_extra_5", "kubriki":"work_stations_17"}
const WORK = {"chop_tree":"axe_chop", "plant_tree":"sow_seeds", "mine_stone":"pickaxe_swing", "mine_ore":"mine", "hunt_animal":"bow_attack", "harvest_carcass":"butcher_knife", "fish":"fish", "evening_fishing":"wait_fish", "build":"build", "upgrade_work":"lay_bricks", "tan_hides":"scrape_hide", "craft":"anvil_hammer", "workshop_work":"work", "gather":"forage_pick", "forage_food":"forage_pick", "burial_procession":"dig_grave", "cleanse_grave":"sweep_clean", "cleanup_trash":"sweep_clean", "place_decoration":"work", "offer_gifts":"incense_offering", "care_for_child":"rock_baby", "evening_training":"drill_training", "campfire_story":"tell_stories", "campfire_dance":"dance", "desecrate_grave":"defile_grave", "funeral_vigil":"mourn_kneel", "pet_animal":"give", "go_eat":"eat", "lodge_hearth_gathering":"eat_at_hearth", "evening_campfire":"sit", "evening_porch_rest":"sit"}
# Работа по профессии, если задача не названа явно
const JOB_WORK = {"farmer":"hoe_till", "sage":"inspect_scroll", "priest":"ritual_prayer", "guard":"guard_patrol", "warrior":"drill_training", "miller":"quern_grind", "baker":"knead_dough", "tanner":"scrape_hide", "craftsman":"anvil_hammer", "smith":"anvil_hammer", "quarryman":"pickaxe_swing", "miner":"mine", "forager":"forage_pick", "builder":"build", "elder":"council_talk", "healer":"brew_medicine"}
# Что несут в руках — так и выглядит переноска
const CARRY = {"wood":"carry_logs", "stone":"carry_sack", "metal":"carry_ore_bucket", "food":"carry_sack", "meat":"carcass_carry", "fish":"carry_fish_basket", "grain":"carry_sheaves", "straw":"carry_sheaves", "leather":"carry_box", "fur":"carry_box", "clothes":"carry_box"}

# --- КАТАЛОГИ МОДУЛЕЙ ВНЕШНОСТИ (ИЗ MANIFEST.JSON CHIBI) ---
const HAIRSTYLES_FEMALE: Array = [
	"hair_1", "hair_2", "hair_3", "hair_4", "hair_5",
	"hair_plus_1", "hair_plus_2", "hair_plus_7",
	"hair_extra_1", "hair_extra_2", "hair_extra_4", "hair_extra_5", "hair_extra_6"
]

const HAIRSTYLES_MALE: Array = [
	"hair_0", "hair_6", "hair_7",
	"hair_plus_0", "hair_plus_3", "hair_plus_4", "hair_plus_5", "hair_plus_6",
	"hair_extra_0", "hair_extra_3", "hair_extra_7"
]

const HAIRSTYLES_ELDER: Array = [
	"hair_7", "hair_plus_4", "hair_extra_4", "hair_extra_0"
]

const HAIR_COLOR_MAP: Dictionary = {
	"hair_7": "silver", "hair_plus_4": "silver", "hair_extra_4": "silver",
	"hair_1": "blonde", "hair_plus_2": "blonde", "hair_extra_1": "blonde",
	"hair_5": "red", "hair_extra_6": "red", "hair_2": "red", "hair_plus_6": "red", "hair_extra_2": "red",
	"hair_3": "dark", "hair_6": "dark", "hair_plus_1": "dark", "hair_plus_7": "dark", "hair_extra_3": "dark", "hair_extra_7": "dark",
	"hair_0": "brown", "hair_4": "brown", "hair_plus_0": "brown", "hair_plus_3": "brown", "hair_plus_5": "brown", "hair_extra_0": "brown", "hair_extra_5": "brown"
}

const BEARDS_BY_COLOR: Dictionary = {
	"silver": ["extras_2", "beards_extra_4", "beards_extra_7"],
	"blonde": ["beards_extra_2"],
	"red": ["extras_3", "beards_extra_1", "extras_0"],
	"dark": ["extras_4", "beards_extra_5", "extras_7"],
	"brown": ["extras_1", "beards_extra_0", "beards_extra_3", "beards_extra_6"]
}

const EYES_MODULES: Array = [
	"face_0", "face_1", "face_2", "face_3", "face_4", "face_5", "face_6", "face_7",
	"face_plus_0", "face_plus_1", "face_plus_2", "face_plus_3", "face_plus_4", "face_plus_5", "face_plus_6", "face_plus_7",
	"face_extra_0", "face_extra_1", "face_extra_2", "face_extra_3", "face_extra_4", "face_extra_5", "face_extra_6", "face_extra_7"
]

const BROWS_MODULES: Array = [
	"brows_extra_0", "brows_extra_1", "brows_extra_2", "brows_extra_3", "brows_extra_4", "brows_extra_5", "brows_extra_6", "brows_extra_7",
	"face_plus_8", "face_plus_9", "face_plus_10", "face_plus_11", "face_plus_13", "face_plus_14", "face_plus_15", "face_15"
]

const NOSE_MODULES: Array = [
	"noses_extra_0", "noses_extra_1", "noses_extra_2", "noses_extra_3", "noses_extra_4", "noses_extra_5", "noses_extra_6", "noses_extra_7",
	"face_8", "face_9"
]

const MOUTH_MODULES: Array = [
	"face_plus_16", "face_plus_17", "face_plus_18", "face_plus_19", "face_plus_20", "face_plus_21", "face_plus_22", "face_plus_23",
	"face_10", "face_11",
	"face_extra_16", "face_extra_17", "face_extra_18", "face_extra_19", "face_extra_20", "face_extra_21", "face_extra_22", "face_extra_23"
]

const SCAR_MODULES: Array = [
	"face_12", "face_13", "face_extra_24", "face_extra_25", "face_extra_26", "face_extra_27"
]

const FRECKLE_MODULES: Array = [
	"face_14", "face_extra_28", "face_extra_29"
]

const MOLE_MODULES: Array = [
	"face_extra_30", "face_extra_31"
]

const TORSO_CLOTHES: Array = [
	"clothes_0", "clothes_1", "clothes_2", "clothes_3", "clothes_4", "clothes_5",
	"work_clothes_0", "work_clothes_1", "work_clothes_2", "work_clothes_3",
	"work_clothes_4", "work_clothes_5", "work_clothes_6", "work_clothes_7"
]

static func two_handed(item: String) -> bool:
	return item in ["simple_spear","reinforced_spear","hunting_bow","improved_hunting_bow","longbow","two_handed_sword"]

static func proxy(id: String, role: String = "villager", gender: String = "m") -> CitizenNPC:
	if not proxies.has(id):
		proxies[id] = CitizenNPC.new(id, id, gender)
	var c: CitizenNPC = proxies[id]
	c.equipment["weapon"] = {"warrior":"short_sword","spearman":"simple_spear","archer":"hunting_bow","general":"short_sword"}.get(role,"unarmed")
	return c

static func get_appearance_slots(c: CitizenNPC) -> Dictionary:
	var slots: Dictionary = c.custom_data.get("composer_slots", {})
	if slots.is_empty():
		slots = generate_npc_appearance(c)
	return slots

static func apply_preset_look(c: CitizenNPC, look_id: String) -> void:
	if not ready_pack(): return
	for look in manifest.get("looks", []):
		if look.get("id", "") == look_id:
			c.visual_appearance_id = look_id
			var slots: Dictionary = {}
			for s in look.get("slots", []):
				var item = s.get("itemId")
				if item != null and item != "":
					slots[s["slotId"]] = String(item).replace("token_item_", "")
			c.custom_data["composer_slots"] = slots
			return

static func generate_npc_appearance(c: CitizenNPC, force_reroll: bool = false) -> Dictionary:
	if not force_reroll and c.custom_data.has("composer_slots") and not (c.custom_data["composer_slots"] as Dictionary).is_empty():
		return c.custom_data["composer_slots"]
	ready_pack()
	
	var seed_num = c.seed_val
	if seed_num == 0:
		seed_num = abs((c.citizen_id + ":" + c.name + ":" + str(c.age)).hash())
		c.seed_val = seed_num
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_num
	
	var is_female = (c.gender == "f")
	var is_elder = (c.cohort == "elder" or c.age >= 46)
	var is_young = (c.cohort in ["child", "youth"] or c.age < 18)
	
	var slots: Dictionary = {}
	
	# 1. Причёска
	var hair_pool: Array = []
	if is_elder and rng.randf() < 0.75:
		hair_pool = HAIRSTYLES_ELDER
	elif is_female:
		hair_pool = HAIRSTYLES_FEMALE
	else:
		hair_pool = HAIRSTYLES_MALE
	var picked_hair: String = hair_pool[rng.randi() % hair_pool.size()]
	slots["token_hair"] = picked_hair
	
	# 2. Борода (только взрослые и пожилые мужчины)
	if not is_female and not is_young:
		var beard_chance = 0.85 if is_elder else 0.45
		if rng.randf() < beard_chance:
			var hair_color = HAIR_COLOR_MAP.get(picked_hair, "brown")
			if is_elder and rng.randf() < 0.8:
				hair_color = "silver"
			var beard_pool: Array = BEARDS_BY_COLOR.get(hair_color, BEARDS_BY_COLOR["brown"])
			slots["token_beard"] = beard_pool[rng.randi() % beard_pool.size()]
			
	# 3. Глаза
	slots["token_eyes"] = EYES_MODULES[rng.randi() % EYES_MODULES.size()]
	
	# 4. Брови
	slots["token_brows"] = BROWS_MODULES[rng.randi() % BROWS_MODULES.size()]
	
	# 5. Нос
	slots["token_nose"] = NOSE_MODULES[rng.randi() % NOSE_MODULES.size()]
	
	# 6. Рот
	slots["token_mouth"] = MOUTH_MODULES[rng.randi() % MOUTH_MODULES.size()]
	
	# 7. Особые приметы (веснушки, шрамы, родинки)
	if is_young or rng.randf() < 0.25:
		slots["token_freckles"] = FRECKLE_MODULES[rng.randi() % FRECKLE_MODULES.size()]
	if (c.job_id in ["hunter", "guard", "warrior"] or rng.randf() < 0.15) and not is_young:
		slots["token_scar"] = SCAR_MODULES[rng.randi() % SCAR_MODULES.size()]
	if rng.randf() < 0.12:
		slots["token_mole"] = MOLE_MODULES[rng.randi() % MOLE_MODULES.size()]
		
	# 8. Базовая одежда торса
	var cloth_idx = rng.randi() % TORSO_CLOTHES.size()
	slots["token_torso"] = TORSO_CLOTHES[cloth_idx]
	
	c.custom_data["composer_slots"] = slots
	return slots

static func icon(module_id: String) -> Texture2D:
	if not ready_pack(): return null
	for m in manifest["modules"]:
		if m["id"] != module_id: continue
		var atlas: Dictionary = manifest["atlases"][m["atlas"]]
		var r: Array = atlas["rects"][int(m["index"])]
		var tex = AtlasTexture.new()
		tex.atlas = texture(atlas["file"])
		tex.region = Rect2(r[0],r[1],r[2],r[3])
		tex.filter_clip = true
		return tex
	return null

static func ready_pack() -> bool:
	if tried:
		return not manifest.is_empty()
	tried = true
	if not FileAccess.file_exists(ROOT + "manifest.json"):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	if not data is Dictionary or data.get("version",0) != 1 or data.get("rig","") != "chibi_token_v1":
		push_error("Composer: unsupported or invalid manifest")
		return false
	manifest = data
	for m in manifest.get("modules", []):
		if m.get("id") == "weapons_0":
			m["mirror"] = true
	var clips = JSON.parse_string(FileAccess.get_file_as_string(ROOT + String(data.get("animations","animations.json"))))
	if not clips is Dictionary:
		manifest = {}
		return false
	animations = clips
	return true

static func texture(file: String) -> Texture2D:
	if textures.has(file):
		return textures[file]
	var path = ROOT + file
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image:
			tex = ImageTexture.create_from_image(image)
	textures[file] = tex
	return tex

static func look_for(c: CitizenNPC) -> Dictionary:
	if not ready_pack():
		return {}
	var sex = "female" if c.gender == "f" else "male"
	# Защита от повреждённых луков (look-6 и look-7 в ассет-паке содержат только контур уха без кожи лица)
	if c.visual_appearance_id == "citizen-look-6":
		c.visual_appearance_id = "citizen-look-4"
	elif c.visual_appearance_id == "citizen-look-7":
		c.visual_appearance_id = "citizen-look-5"
	var pool: Array = []
	for look in manifest.get("looks",[]):
		if look.get("id","") in ["citizen-look-6", "citizen-look-7"]:
			continue
		if look.get("sex","") == sex:
			pool.append(look)
			if look.get("id","") == c.visual_appearance_id:
				return look
	if pool.is_empty():
		return {}
	var picked: Dictionary = pool[posmod((c.citizen_id + ":" + str(c.seed_val)).hash(),pool.size())]
	c.visual_appearance_id = picked["id"]
	return picked

static func age_key(c: CitizenNPC) -> String:
	return "teen" if c.cohort == "youth" else c.cohort if c.cohort in ["child","adult","elder"] else "adult"

static func head_texture(c: CitizenNPC, emotion: String = "neutral") -> Texture2D:
	var look = look_for(c)
	if look.is_empty():
		return null
	if look.get("id","") in ["citizen-look-6", "citizen-look-7"]:
		var fallback_id = "citizen-look-4" if look.get("sex","") == "male" else "citizen-look-5"
		for l in manifest.get("looks",[]):
			if l.get("id","") == fallback_id:
				look = l
				break
	var young = "young" if age_key(c) in ["child","teen"] else "adult"
	var hat = String(HATS.get(c.equipment.get("helmet",""),""))
	return texture(String(look["heads"].get("%s/%s/%s" % [young,hat,emotion],look["heads"].get("%s//neutral" % young,""))))

static func _get_atlas_image(atlas_name: String) -> Image:
	if _atlas_images.has(atlas_name):
		return _atlas_images[atlas_name]
	var a: Dictionary = manifest.get("atlases", {}).get(atlas_name, {})
	if a.is_empty():
		return null
	var tex = texture(a["file"])
	if tex == null:
		return null
	var img = tex.get_image()
	_atlas_images[atlas_name] = img
	return img

static func render_portrait(c: CitizenNPC, target_size: Vector2i = Vector2i(120, 125)) -> Texture2D:
	if not ready_pack():
		return null
	if c.custom_data.has("composer_portrait_tex"):
		var cached = c.custom_data["composer_portrait_tex"]
		if cached != null and cached is Texture2D:
			return cached
			
	var base_tex = head_texture(c, "neutral")
	if base_tex == null:
		return null
	var base_img = base_tex.get_image().duplicate()
	if base_img == null:
		return null
	base_img.resize(240, 250, Image.INTERPOLATE_LANCZOS)
	
	var slots = get_appearance_slots(c)
	var queue: Array = []
	for m in manifest.get("modules", []):
		if m.get("bone") == "head" and slots.get(m["slot"], "") == m["id"] and m.get("slot") != "token_headshape":
			queue.append(m)
	queue.sort_custom(func(a, b): return float(a["z"]) < float(b["z"]))
	
	for m in queue:
		var atlas_img = _get_atlas_image(m["atlas"])
		if atlas_img == null:
			continue
		var a_info: Dictionary = manifest["atlases"][m["atlas"]]
		var r: Array = a_info["rects"][int(m["index"])]
		var region_img = atlas_img.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
		var w = int(m["width"])
		var h = int(m["height"])
		region_img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		
		var dest_x = 120 + int(m["x"]) - w / 2
		var dest_y = 220 + int(m["y"]) - h / 2
		if bool(m.get("mirror", false)):
			region_img.flip_x()
		base_img.blend_rect(region_img, Rect2i(0, 0, w, h), Vector2i(dest_x, dest_y))
		
	if target_size != Vector2i(240, 250) and target_size.x > 0 and target_size.y > 0:
		base_img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		
	var tex = ImageTexture.create_from_image(base_img)
	c.custom_data["composer_portrait_tex"] = tex
	return tex

static func visual_equipment(c: CitizenNPC) -> Dictionary:
	var slots: Dictionary = {}
	var armor = String(c.equipment.get("body_armor","clothes"))
	if armor != "":
		slots["token_torso"] = ARMOR.get(armor,"clothes_0")
	var weapon = String(c.equipment.get("weapon","unarmed"))
	if WEAPONS.has(weapon):
		slots["token_main"] = WEAPONS[weapon]
	if c.has_tool(String(c.equipped_tool.get("type",""))) and c.state != CitizenNPC.State.ATTACKING:
		var tool = String(c.equipped_tool.get("type",""))
		if TOOLS.has(tool):
			slots["token_main"] = TOOLS[tool]
	if c.cargo_amount > 0:
		slots["token_main"] = CARGO.get(c.cargo_type,"work_tools_4")
	var s_details = load("res://src/core/composer_settlement_details.gd")
	var settlement_tool: String = s_details.equipped_tool_id(c) if s_details and s_details.has_method("equipped_tool_id") else ""
	if settlement_tool != "":
		slots["token_main"] = "settlement_item_" + settlement_tool
	if settlement_tool == "" and String(c.equipment.get("shield","")) != "" and slots.get("token_main","") not in ["weapons_0","weapons_1","weapons_3","props_3","work_tools_0","work_tools_1"]:
		slots["token_off"] = "weapons_6"
	if slots.get("token_main","") == "weapons_0":
		slots["token_projectile"] = "weapons_7"
	return slots

static func resolve_action(c: CitizenNPC) -> String:
	if not c.is_alive:
		return "death"
	var explicit_action = String(c.custom_data.get("anim_action",""))
	if float(c.custom_data.get("anim_until",-1)) > GameManager.sim_time_total and explicit_action != "":
		return explicit_action
	var weapon = String(c.equipment.get("weapon","unarmed"))
	var module = String(WEAPONS.get(weapon,""))
	if c.state == CitizenNPC.State.ATTACKING:
		return {"weapons_0":"bow_attack","weapons_1":"spear_attack","weapons_2":"sword_attack","weapons_4":"axe_attack","weapons_5":"mace_attack"}.get(module,"punch")
	if c.state in [CitizenNPC.State.WORKING,CitizenNPC.State.GATHERING,CitizenNPC.State.BUTCHERING]:
		if c.task_id == "chop_tree" and GameManager.resource_manager:
			var node: Dictionary = GameManager.resource_manager.nodes.get(c.target_coord,{})
			if node.get("tree_stage", "standing") in ["logs", "stump"]: return "pickup"
			if node.get("tree_stage", "standing") == "falling": return "idle"
		if c.state == CitizenNPC.State.BUTCHERING:
			return "butcher_knife"
		if WORK.has(c.task_id):
			return String(WORK[c.task_id])
		return String(JOB_WORK.get(c.job_id, "gather"))
	if c.state in [CitizenNPC.State.FLEEING,CitizenNPC.State.FLEEING_HOME]:
		return "child_hide_cower" if c.cohort == "child" and c.path.is_empty() else "run"
	if c.carrying_deceased_id != "":
		return "carry_stretcher"
	if c.cargo_amount > 0 and (not c.path.is_empty() or c.state == CitizenNPC.State.CARRYING):
		return String(CARRY.get(c.cargo_type, "carry"))
	if not c.path.is_empty() or c.state in [CitizenNPC.State.MOVING_TO_WORK,CitizenNPC.State.GOING_HOME]:
		# Идут с орудием своего дела, старики — с посохом, дети бегом
		if c.cohort == "child":
			return "child_run_play"
		if c.cohort == "elder":
			return "walk_with_staff"
		if c.job_id == "woodcutter" or module == "weapons_4":
			return "axe_walk"
		if c.job_id in ["hunter", "archer"] or module == "weapons_0":
			return "walk_hunter"
		if c.job_id in ["guard", "warrior"] or module == "weapons_2":
			return "sword_walk"
		return "walk"
	if c.state == CitizenNPC.State.TALKING:
		return "council_talk" if c.cohort == "elder" else "talk"
	if c.state == CitizenNPC.State.RESTING and WORK.has(c.task_id):
		return String(WORK[c.task_id])
	if c.state == CitizenNPC.State.MOURNING:
		return "mourn_kneel"
	var by_state = {CitizenNPC.State.EATING:"eat",CitizenNPC.State.SLEEPING:"rest",CitizenNPC.State.RESTING:"sit",CitizenNPC.State.CELEBRATING:"dance",CitizenNPC.State.PRAYING:"ritual_prayer",CitizenNPC.State.CONFRONTING:"indignation",CitizenNPC.State.COMPLAINING:"indignation",CitizenNPC.State.HELPING:"give"}
	if by_state.has(c.state):
		return by_state[c.state]
	# Простой без дела: дети играют, охотник ждёт с луком, остальные стоят
	if c.cohort == "child":
		return "child_run_play"
	if c.job_id in ["hunter", "archer"]:
		return "idle_hunter"
	return "idle"

# --- ЖИВОЕ ТЕЛО: вторичная анимация поверх клипа ---
# Плавный разворот (тело «поворачивается», а не мгновенно зеркалится), наклон и покачивание
# при ходьбе, дыхание в покое, прыжок и кувырок Короля, сплющивание при приземлении.
const BODY_CENTER_Y: float = 4.6 # px над ступнями — середина фигурки чиби

static func body_motion(c: CitizenNPC, action: String, now: float, flip: float) -> Transform2D:
	var cd: Dictionary = c.custom_data
	var last = float(cd.get("_bm_t", now))
	var dt = clampf(now - last, 0.0, 0.1)
	cd["_bm_t"] = now
	# 1. Разворот: видимая «ширина» тела проходит через ноль, как при повороте
	var flip_vis = float(cd.get("_bm_flip", flip))
	flip_vis = move_toward(flip_vis, flip, dt * 9.0)
	cd["_bm_flip"] = flip_vis
	var sx = flip_vis if absf(flip_vis) > 0.18 else 0.18 * signf(flip_vis if flip_vis != 0.0 else flip)
	var sy = 1.0
	var lean = 0.0
	var lift = 0.0
	var angle = 0.0
	var seed_phase = float(posmod(c.seed_val, 97)) * 0.13
	var moving = action in ["walk", "run", "carry", "carry_logs", "carry_sack", "carry_ore_bucket", "carry_fish_basket", "carry_sheaves", "carry_box", "carcass_carry", "carry_stretcher", "axe_walk", "walk_hunter", "sword_walk", "walk_with_staff", "child_run_play"]
	if c.is_alive:
		if moving:
			var speed_k = 1.6 if action in ["run", "child_run_play"] else 1.0
			var step = now * 9.0 * speed_k + seed_phase
			lift = absf(sin(step)) * 0.55 * speed_k
			# Шаг: на касании земли тело чуть сплющивается
			var contact = 1.0 - absf(sin(step))
			sx *= 1.0 + contact * 0.05
			sy *= 1.0 - contact * 0.05
			lean = -0.10 * signf(c.facing_dir.x) * speed_k if absf(c.facing_dir.x) > 0.2 else 0.0
			if action.begins_with("carry") or action == "carcass_carry":
				lean *= 0.5 # с грузом наклон меньше, походка тяжелее
				lift *= 0.6
		elif action in ["idle", "idle_hunter", "talk", "council_talk", "sit"]:
			# Дыхание
			sy *= 1.0 + sin(now * 2.2 + seed_phase) * 0.018
		# Король: прыжок, кувырок, приземление (HeroController пишет состояние в custom_data)
		var jump_h = float(cd.get("jump_h", 0.0))
		lift += jump_h
		var roll_p = float(cd.get("roll_p", -1.0))
		if roll_p >= 0.0:
			var dir_sign = signf(c.facing_dir.x) if absf(c.facing_dir.x) > 0.1 else 1.0
			angle = roll_p * TAU * dir_sign
			sy *= 0.82
			lift += sin(roll_p * PI) * 1.5
		var squash = float(cd.get("land_squash", 0.0))
		if squash > 0.0:
			sx *= 1.0 + squash * 0.16
			sy *= 1.0 - squash * 0.16
		if jump_h > 0.5:
			sx *= 0.94
			sy *= 1.06
	var m = Transform2D(0.0, Vector2(0.0, -lift))
	if angle != 0.0:
		m = m * Transform2D(0.0, Vector2(0.0, -BODY_CENTER_Y)) * Transform2D(angle, Vector2.ZERO) * Transform2D(0.0, Vector2(0.0, BODY_CENTER_Y))
	m = m * Transform2D(Vector2(1.0, 0.0), Vector2(lean, 1.0), Vector2.ZERO)
	m = m * Transform2D(Vector2(sx, 0.0), Vector2(0.0, sy), Vector2.ZERO)
	return m

static func matrix(a: Array) -> Transform2D:
	return Transform2D(Vector2(float(a[0]),float(a[1])),Vector2(float(a[2]),float(a[3])),Vector2(float(a[4]),float(a[5])))

static func _draw_region(canvas: CanvasItem, atlas: String, index: int, bounds: Rect2, transform: Transform2D, mirror: bool = false) -> void:
	var a: Dictionary = manifest.get("atlases",{}).get(atlas,{})
	if a.is_empty():
		return
	var tex = texture(a["file"])
	if tex == null:
		return
	var r: Array = a["rects"][index]
	var final_transform = transform
	if mirror:
		final_transform = transform * Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	canvas.draw_set_transform_matrix(final_transform)
	canvas.draw_texture_rect_region(tex, bounds, Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))

static func draw_citizen(canvas: CanvasItem, c: CitizenNPC, now: float, override_action: String = "") -> bool:
	if not ready_pack():
		return false
	var look = look_for(c)
	if look.is_empty():
		return false
	var age = age_key(c)
	var action = override_action if override_action != "" else resolve_action(c)
	var library: Dictionary = animations.get(age,animations["adult"])
	if not library.has(action):
		action = "idle"
	var previous = String(c.custom_data.get("composer_action",""))
	if previous != action:
		c.custom_data["composer_action"] = action
		c.custom_data["composer_action_start"] = now
	var clip: Dictionary = library[action]
	var elapsed = maxf(0,now - float(c.custom_data.get("composer_action_start",now)))
	var duration = maxf(.01,float(clip["duration"]))
	var phase = fmod(elapsed,duration) if clip["loop"] else minf(elapsed,duration-.001)
	if not c.is_alive:
		phase = duration-.001
	var frames: Array = clip["frames"]
	var frame: Dictionary = frames[mini(frames.size()-1,int(phase*float(clip["fps"])))]
	var flip = -1.0 if c.facing_dir.x < -.1 else 1.0
	var scale = float(manifest.get("unitScale",.04))
	var world = Transform2D(0.0, c.pos) * body_motion(c, action, now, flip) * Transform2D(Vector2(scale,0),Vector2(0,scale),Vector2.ZERO)
	var chest = world * matrix(frame["chest"])
	_draw_region(canvas,"anatomy",int(look["skin"])+4,Rect2(-62,-46,124,92),chest)
	var equip_slots = visual_equipment(c)
	var app_slots = get_appearance_slots(c)
	var slots = app_slots.duplicate()
	for k in equip_slots:
		slots[k] = equip_slots[k]
	var queue: Array = []
	for m in manifest["modules"]:
		if slots.get(m["slot"],"") == m["id"]:
			queue.append(m)
	queue.sort_custom(func(a,b): return float(a["z"]) < float(b["z"]))
	var head_drawn = false
	for m in queue:
		if not head_drawn and float(m["z"]) > -790:
			_draw_head(canvas,c,world*matrix(frame["head"]),action,phase,now)
			head_drawn = true
		if m.get("slot") == "token_headshape":
			continue
		var bone = String(m["bone"])
		if not frame.has(bone):
			continue
		var bounds = Rect2(float(m["x"])-float(m["width"])*.5,float(m["y"])-float(m["height"])*.5,float(m["width"]),float(m["height"]))
		_draw_region(canvas,m["atlas"],int(m["index"]),bounds,world*matrix(frame[bone]),bool(m.get("mirror",false)))
	if not head_drawn:
		_draw_head(canvas,c,world*matrix(frame["head"]),action,phase,now)
	var s_details = load("res://src/core/composer_settlement_details.gd")
	if s_details and s_details.has_method("draw_equipped_tool"):
		s_details.draw_equipped_tool(canvas, c, world, frame)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true

static func _draw_head(canvas: CanvasItem,c: CitizenNPC,transform: Transform2D,action: String,phase: float,now: float) -> void:
	var emotion = "neutral"
	if action in ["dance","child_run_play"]:
		emotion = "happy"
	elif "attack" in action or action in ["punch","axe_chop"]:
		emotion = "angry"
	elif action in ["death","mourn","hide"]:
		emotion = "sad"
	elif action in ["jump","fall"]:
		emotion = "surprised"
	if c.is_alive and fmod(now + float(posmod(c.seed_val,20))*.17,2.6) < .12:
		emotion = "blink"
	elif emotion in ["happy","angry","surprised"] and fmod(phase,.65) > .36:
		emotion = "neutral"
	var tex = head_texture(c,emotion)
	if tex:
		canvas.draw_set_transform_matrix(transform)
		canvas.draw_texture_rect(tex,Rect2(-120,-220,240,250),false)
