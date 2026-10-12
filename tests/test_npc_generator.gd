extends Node

const NPCGenerator = preload("res://src/simulation/npc_generator.gd")
const ComposerAssets = preload("res://src/core/composer_assets.gd")
const CitizenNPC = preload("res://src/simulation/citizen_npc.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _ready() -> void:
	print("========================================")
	print("TEST: RUNNING NPC GENERATOR & COMPOSER APPEARANCE TESTS")
	print("========================================")
	
	# 1. Загрузка пака
	check(ComposerAssets.ready_pack(), "Composer pack must load")
	
	# 2. Тест генерации одиночного гражданина
	var c_m = NPCGenerator.generate_citizen({"gender": "m", "cohort": "adult", "job_id": "woodcutter"})
	check(c_m != null, "generate_citizen must return CitizenNPC instance")
	check(c_m.gender == "m", "Male citizen has gender 'm'")
	check(c_m.cohort == "adult", "Adult citizen has cohort 'adult'")
	check(c_m.job_id == "woodcutter", "Woodcutter has job_id 'woodcutter'")
	check(c_m.equipped_tool.get("type") == "axe", "Woodcutter is equipped with axe tool")
	
	# Проверка внешности
	var slots_m = c_m.custom_data.get("composer_slots", {})
	check(not slots_m.is_empty(), "Citizen has generated composer_slots")
	check(slots_m.has("token_hair"), "Citizen has hair module")
	check(slots_m.has("token_eyes"), "Citizen has eyes module")
	check(slots_m.has("token_brows"), "Citizen has eyebrows module")
	check(slots_m.has("token_nose"), "Citizen has nose module")
	check(slots_m.has("token_mouth"), "Citizen has mouth module")
	check(slots_m.has("token_torso"), "Citizen has torso clothes module")
	print("OK 1. Basic citizen generation and appearance slots verified.")
	
	# 3. Тест женщин: никогда не имеют бороды
	for i in range(15):
		var c_f = NPCGenerator.generate_citizen({"gender": "f", "cohort": "adult"})
		var s_f = c_f.custom_data.get("composer_slots", {})
		check(not s_f.has("token_beard") or s_f.get("token_beard", "") == "", "Female citizen must NEVER have a beard")
	print("OK 2. Female beard exclusion verified (0/15 beards).")
	
	# 4. Тест детей и подростков: никогда не имеют бороды
	for i in range(15):
		var c_child = NPCGenerator.generate_child("test_settlement", "m")
		var s_child = c_child.custom_data.get("composer_slots", {})
		check(not s_child.has("token_beard") or s_child.get("token_beard", "") == "", "Child citizen must NEVER have a beard")
		check(c_child.age <= 13, "Child age must be <= 13")
	print("OK 3. Child/youth beard exclusion verified (0/15 beards).")
	
	# 5. Тест старейшин: высокая частота седых волос и бород
	var elder_beards = 0
	for i in range(20):
		var c_elder = NPCGenerator.generate_elder("test_settlement", "m")
		var s_elder = c_elder.custom_data.get("composer_slots", {})
		if s_elder.has("token_beard") and s_elder["token_beard"] != "":
			elder_beards += 1
	check(elder_beards >= 12, "Male elders have high beard frequency (>= 60 percent, got %d/20)" % elder_beards)
	print("OK 4. Elder demographic traits and high beard frequency verified (%d/20)." % elder_beards)
	
	# 6. Тест воинов: защитные характеристики и оружие
	var warrior = NPCGenerator.generate_warrior("test_settlement", "warrior")
	check(warrior.traits["bravery"] >= 70.0, "Warrior bravery is high")
	check(warrior.strength_level >= 5, "Warrior strength level is enhanced")
	check(warrior.equipment.get("weapon") == "short_sword", "Warrior is equipped with short sword")
	check(warrior.equipment.get("body_armor") == "chainmail", "Warrior is equipped with armor")
	check(warrior.equipment.get("helmet") == "iron_helmet", "Warrior is equipped with helmet")
	check(warrior.equipment.get("shield") == "weapons_6", "Warrior is equipped with shield")
	print("OK 5. Warrior role generation and combat loadout verified.")
	
	# 7. Тест сериализации и персистентности внешности (Save / Load)
	var serialized = c_m.serialize()
	check(serialized.has("composer_slots"), "Serialized citizen must contain composer_slots")
	var restored = CitizenNPC.new()
	restored.deserialize(serialized)
	var restored_slots = restored.custom_data.get("composer_slots", {})
	check(restored_slots == slots_m, "Deserialized composer_slots must match original 100%")
	print("OK 6. Full appearance persistence across serialize/deserialize verified.")
	
	# 8. Тест массовой генерации группы уникальных NPC (Batch Generation)
	var batch = NPCGenerator.generate_batch(10)
	check(batch.size() == 10, "Batch must produce 10 citizens")
	var unique_hairs: Dictionary = {}
	var unique_names: Dictionary = {}
	for c in batch:
		unique_names[c.name] = true
		var h = c.custom_data.get("composer_slots", {}).get("token_hair", "")
		if h != "":
			unique_hairs[h] = true
	check(unique_names.size() >= 7, "Batch produces diverse names (got %d/10 unique)" % unique_names.size())
	check(unique_hairs.size() >= 4, "Batch produces diverse hairstyles (got %d/10 unique)" % unique_hairs.size())
	print("OK 7. Batch generation diversity verified (%d unique hairstyles across 10 NPCs)." % unique_hairs.size())
	
	# 9. Тест отрисовки через ComposerAssets.draw_citizen в контексте CanvasItem.draw
	var test_canvas = Node2D.new()
	add_child(test_canvas)
	test_canvas.draw.connect(func():
		var draw_ok = ComposerAssets.draw_citizen(test_canvas, c_m, 1.0, "idle")
		check(draw_ok, "ComposerAssets.draw_citizen must return true")
	)
	test_canvas.queue_redraw()
	await get_tree().process_frame
	test_canvas.queue_free()
	print("OK 8. Modular draw_citizen execution verified.")
	
	# 9. Тест композитного портрета через ComposerAssets.render_portrait и c.get_texture()
	var portrait_tex = c_m.get_texture()
	check(portrait_tex != null, "Citizen get_texture() must return non-null composite portrait")
	check(portrait_tex is Texture2D, "Portrait is a valid Texture2D")
	var p_img = portrait_tex.get_image() if portrait_tex else null
	if p_img:
		p_img.save_png("res://scratch/test_portrait_9.png")
	print("OK 9. Composite modular portrait generation verified (%dx%d)." % [p_img.get_width(), p_img.get_height()])
	
	print("========================================")
	print("ALL NPC GENERATOR TESTS: ", "PASS" if failures.is_empty() else failures)
	print("========================================")
	get_tree().quit(0 if failures.is_empty() else 1)
