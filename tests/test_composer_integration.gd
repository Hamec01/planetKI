extends Node

var failures: Array[String] = []
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	call_deferred("run")

func run() -> void:
	check(ComposerAssets.ready_pack(), "Composer pack loads")
	check(ComposerTrees.ready_pack(), "Three native tree atlases load")
	var c = CitizenNPC.new("test-chibi", "Тест", "f", 25, "adult")
	check(ComposerAssets.head_texture(c) != null, "Female head texture loads")
	var identity = c.visual_appearance_id
	c.set_job("woodcutter")
	check(ComposerAssets.look_for(c)["id"] == identity, "Job change preserves face")
	c.equipment = {"weapon":"unarmed","body_armor":"","shield":"","helmet":""}
	check(ComposerAssets.visual_equipment(c).is_empty(), "Unselected equipment stays absent")
	check(ComposerAssets.animations["adult"].has("axe_chop"), "Chop animation exists")
	check(ComposerAssets.animations["child"].has("idle"), "Child animations exist")
	var resources = MapResourceManager.new()
	var coord = Vector2i(1,1)
	resources.nodes[coord] = {"id":"tree_test","coord":coord,"pos":Vector2(48,48),"category":"wood","amount":20.0,"max_amount":20.0,"depleted":false,"reserved_by":"","original_sprite":"tree_oak","depleted_sprite":"none","updates_tile":false}
	resources.strike_tree(coord,8)
	check(resources.collect_tree_logs(coord,100) == 0, "Standing wood cannot enter inventory")
	check(resources.nodes[coord]["chop_hits"] == 1, "Strike creates notch and chips")
	resources.strike_tree(coord,12)
	check(resources.nodes[coord]["tree_stage"] == "falling", "Final strike starts fall")
	check(resources.collect_tree_logs(coord,100) == 0, "Cannot pick logs during fall")
	resources.nodes[coord]["fall_start"] -= 2
	var first = resources.collect_tree_logs(coord,7)
	var remaining = resources.collect_tree_logs(coord,100)
	check(is_equal_approx(first+remaining,20), "Tree conserves exact wood quantity")
	check(resources.nodes[coord]["tree_stage"] == "stump", "Harvest leaves stump")
	check(resources.collect_tree_logs(coord,100) == 0, "Cannot duplicate harvested logs")
	var camp = BuildingInstance.new()
	camp.type = "woodcutter_camp"
	camp._init_camp_tools()
	check(is_equal_approx(camp.store_wood(first+remaining),20), "Camp receives physical log quantity")
	check(is_equal_approx(camp.take_wood(8),8) and is_equal_approx(camp.local_buffer_wood,12), "Hauling subtracts camp stock")
	print("COMPOSER INTEGRATION: ", "PASS" if failures.is_empty() else failures)
	get_tree().quit(0 if failures.is_empty() else 1)
