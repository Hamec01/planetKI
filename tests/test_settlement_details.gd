extends Node2D

var failures: Array[String] = []

class ReviewPopulation extends RefCounted:
	var citizens: Array[CitizenNPC] = []

class ReviewSettlement extends RefCounted:
	var id := "details-test"
	var population := ReviewPopulation.new()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	check(ComposerSettlementDetails.ready_pack(), "Layer/equipment manifests load")
	check(ComposerSettlementDetails.buildings.size() == 7, "Seven buildings have layers")
	check(ComposerSettlementDetails.equipment.size() == 6, "Six handheld tools, no handheld plough/yoke")
	for id in ComposerSettlementDetails.buildings:
		var building: Dictionary = ComposerSettlementDetails.buildings[id]
		var tex := ComposerBuildings.texture(String(building["file"]))
		check(tex != null, "Layer atlas loads: " + id)
		for layer in building["layers"]:
			var source := ComposerSettlementDetails.rect(layer["sourceRect"])
			check(Rect2(Vector2.ZERO, tex.get_size()).encloses(source), "Layer within atlas: " + id)
	var citizen := CitizenNPC.new("agriculture-review", "Worker", "m", 25, "adult")
	citizen.equipment = {"weapon": "unarmed", "body_armor": "", "shield": "", "helmet": ""}
	check(ComposerSettlementDetails.equipped_tool_id(citizen) == "", "No equipment appears automatically")
	for id in ComposerSettlementDetails.equipment:
		citizen.equipped_tool = {"id": id, "type": "hoe", "durability": 100.0}
		check(ComposerSettlementDetails.equipped_tool_id(citizen) == id, "Actual inventory ID controls equipped art: " + id)
		check(ComposerAssets.visual_equipment(citizen).get("token_main", "") == "settlement_item_" + id, "Real tool replaces old generic sprite")
		var binding: Dictionary = ComposerSettlementDetails.equipment[id]
		var item := ComposerBuildings.get_upgrade_data(String(binding["assetId"]))
		var source: Array = item["sourceRect"]
		var scale := float(binding["length"]) / maxf(float(source[2]), float(source[3]))
		var grip := Vector2(float(binding["grip"][0]), float(binding["grip"][1])) * scale
		check((ComposerSettlementDetails.tool_transform(binding) * grip).length() < 0.0001, "Grip stays at socket: " + id)
		var restored := CitizenNPC.new("restored", "Worker", "m", 25, "adult")
		restored.deserialize(citizen.serialize())
		check(ComposerSettlementDetails.equipped_tool_id(restored) == id, "Equipped art survives save/load")
		citizen.equipped_tool["durability"] = 0.0
		check(ComposerSettlementDetails.equipped_tool_id(citizen) == "", "Broken tools are not displayed")
	check(ComposerSettlementDetails.flame_index(0.0) == 0, "Fire first frame")
	check(ComposerSettlementDetails.flame_index(0.21) == 1, "Fire second frame")
	check(ComposerSettlementDetails.flame_index(0.41) == 2, "Fire third frame")
	check(ComposerSettlementDetails.flame_index(0.6) == 0, "Fire loops")
	# Load the actual world renderer too; parse failures must fail this integration.
	var world := load("res://src/map/world_map_view.gd") as GDScript
	check(world != null and world.can_instantiate(), "World renderer compiles with real layers")
	if world != null and world.can_instantiate():
		var view := world.new() as Node2D
		view.set("selected_tile_coord", Vector2i(9, 9))
		check(view.call("_composer_interior_open", Vector2i(9,9), {"id":"great_lodge"}, Vector2.ZERO), "Selecting building opens actual interior")
		view.set("selected_tile_coord", Vector2i(-999,-999))
		view.set("hovered_tile_coord", Vector2i(-999,-999))
		var saved_settlements: Dictionary = GameManager.settlements.duplicate()
		var settlement := ReviewSettlement.new()
		settlement.population.citizens.append(citizen)
		GameManager.settlements.clear()
		GameManager.settlements[settlement.id] = settlement
		var work: Array = ComposerSettlementDetails.buildings["great_lodge"]["interior"]["work"]
		citizen.pos = Vector2(float(work[0]),float(work[1])) * ComposerBuildings.UNIT_SCALE
		check(view.call("_composer_interior_open", Vector2i(9,9), {"id":"great_lodge"}, Vector2.ZERO), "Living NPC in actual floor opens roof")
		citizen.pos = Vector2(1000,1000)
		check(not view.call("_composer_interior_open", Vector2i(9,9), {"id":"great_lodge"}, Vector2.ZERO), "NPC outside floor does not open roof")
		var building := BuildingInstance.new()
		building.workers.append(citizen.citizen_id)
		citizen.state = CitizenNPC.State.WORKING
		check(not view.call("_composer_work_active", building), "No order: no fake mechanism production")
		building.production_queue.append({"id":"food", "progress":0.0})
		check(view.call("_composer_work_active", building), "Real order and working assigned NPC activate mechanism")
		citizen.state = CitizenNPC.State.MOVING_TO_WORK
		check(not view.call("_composer_work_active", building), "Travelling worker does not run mechanism")
		GameManager.settlements = saved_settlements
		view.free()
	print("SETTLEMENT DETAILS: ", "PASS" if failures.is_empty() else failures)
	get_tree().quit(0 if failures.is_empty() else 1)
