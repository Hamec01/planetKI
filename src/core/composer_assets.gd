class_name ComposerAssets
extends RefCounted

const ROOT = "res://Assets/composer/planetki-chibi/"
static var manifest: Dictionary = {}
static var animations: Dictionary = {}
static var textures: Dictionary = {}
static var tried: bool = false
static var proxies: Dictionary = {}
const WEAPONS = {"club":"weapons_5", "knife":"weapons_2", "work_axe":"weapons_4", "copper_work_axe":"weapons_4", "battle_axe":"weapons_4", "simple_spear":"weapons_1", "reinforced_spear":"weapons_1", "short_sword":"weapons_2", "hunting_bow":"weapons_0", "improved_hunting_bow":"weapons_0", "longbow":"weapons_0"}
const ARMOR = {"clothes":"clothes_0", "padded_armor":"clothes_3", "leather_armor":"clothes_4", "chainmail":"clothes_5"}
const HATS = {"iron_helmet":"helmets_0", "reinforced_helmet":"helmets_2"}
const TOOLS = {"axe":"weapons_4", "pickaxe":"work_tools_0", "hoe":"props_3", "hammer":"work_tools_3", "fishing_rod":"work_tools_1", "rod":"work_tools_1", "knife":"work_tools_2"}
const CARGO = {"wood":"work_stations_12", "stone":"work_stations_14", "metal":"work_stations_10", "food":"work_tools_4", "fish":"work_stations_9", "leather":"work_tools_15", "fur":"work_tools_15", "clothes":"work_extra_5", "kubriki":"work_stations_17"}
const WORK = {"chop_tree":"axe_chop", "plant_tree":"gather", "mine_stone":"mine", "mine_ore":"mine", "hunt_animal":"bow_attack", "harvest_carcass":"butcher", "fish":"fish", "evening_fishing":"fish", "build":"build", "upgrade_work":"build", "tan_hides":"sew", "craft":"anvil_hammer"}

static func two_handed(item: String) -> bool:
	return item in ["simple_spear","reinforced_spear","hunting_bow","improved_hunting_bow","longbow","two_handed_sword"]

static func proxy(id: String, role: String = "villager", gender: String = "m") -> CitizenNPC:
	if not proxies.has(id): proxies[id] = CitizenNPC.new(id, "", gender)
	var c: CitizenNPC = proxies[id]
	c.equipment["weapon"] = {"warrior":"short_sword","spearman":"simple_spear","archer":"hunting_bow","general":"short_sword"}.get(role,"unarmed")
	return c

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
	var pool: Array = []
	for look in manifest.get("looks",[]):
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
	var young = "young" if age_key(c) in ["child","teen"] else "adult"
	var hat = String(HATS.get(c.equipment.get("helmet",""),""))
	return texture(String(look["heads"].get("%s/%s/%s" % [young,hat,emotion],look["heads"].get("%s//neutral" % young,""))))

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
	if String(c.equipment.get("shield","")) != "" and slots.get("token_main","") not in ["weapons_0","weapons_1","weapons_3","props_3","work_tools_0","work_tools_1"]:
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
	if c.state == CitizenNPC.State.ATTACKING:
		var weapon = String(c.equipment.get("weapon","unarmed"))
		var module = String(WEAPONS.get(weapon,""))
		return {"weapons_0":"bow_attack","weapons_1":"spear_attack","weapons_2":"sword_attack","weapons_4":"axe_attack","weapons_5":"mace_attack"}.get(module,"punch")
	if c.state in [CitizenNPC.State.WORKING,CitizenNPC.State.GATHERING,CitizenNPC.State.BUTCHERING]:
		if c.task_id == "chop_tree" and GameManager.resource_manager:
			var node: Dictionary = GameManager.resource_manager.nodes.get(c.target_coord,{})
			if node.get("tree_stage", "standing") in ["logs", "stump"]: return "pickup"
			if node.get("tree_stage", "standing") == "falling": return "idle"
		return String(WORK.get(c.task_id,"gather"))
	if c.state in [CitizenNPC.State.FLEEING,CitizenNPC.State.FLEEING_HOME]:
		return "run"
	if c.cargo_amount > 0 and (not c.path.is_empty() or c.state == CitizenNPC.State.CARRYING):
		return "carry"
	if not c.path.is_empty() or c.state in [CitizenNPC.State.MOVING_TO_WORK,CitizenNPC.State.GOING_HOME]:
		return "walk"
	return {CitizenNPC.State.TALKING:"talk",CitizenNPC.State.EATING:"eat",CitizenNPC.State.SLEEPING:"rest",CitizenNPC.State.RESTING:"rest",CitizenNPC.State.CELEBRATING:"dance",CitizenNPC.State.MOURNING:"mourn"}.get(c.state,"idle")

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
	canvas.draw_set_transform_matrix(transform)
	var target = bounds
	if mirror:
		target = Rect2(bounds.position + Vector2(bounds.size.x,0),Vector2(-bounds.size.x,bounds.size.y))
	canvas.draw_texture_rect_region(tex,target,Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3])))

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
	var world = Transform2D(Vector2(flip*scale,0),Vector2(0,scale),c.pos)
	var chest = world * matrix(frame["chest"])
	_draw_region(canvas,"anatomy",int(look["skin"])+4,Rect2(-62,-46,124,92),chest)
	var slots = visual_equipment(c)
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
		var bone = String(m["bone"])
		if not frame.has(bone):
			continue
		var bounds = Rect2(float(m["x"])-float(m["width"])*.5,float(m["y"])-float(m["height"])*.5,float(m["width"]),float(m["height"]))
		_draw_region(canvas,m["atlas"],int(m["index"]),bounds,world*matrix(frame[bone]),bool(m.get("mirror",false)))
	if not head_drawn:
		_draw_head(canvas,c,world*matrix(frame["head"]),action,phase,now)
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
