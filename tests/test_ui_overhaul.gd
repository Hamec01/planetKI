extends SceneTree

func _init() -> void:
	print("--- Running UI & Map UX Overhaul Tests ---")
	
	# 1. Тестирование расчёта доходов и сметы SettlementData
	var s = SettlementData.new("test_s", "Тестовый Лагерь", "player_tribe", Vector2i(10, 10))
	var ledger = s.get_detailed_ledger("Лето")
	assert(ledger.has("income") and ledger.has("expense") and ledger.has("net"), "Ledger structure invalid")
	assert(ledger["income"]["food"] > 0, "Food income should be > 0 with hunters/foragers")
	assert(ledger["expense"]["food"] > 0, "Food expense should be > 0 with pop")
	print("SUCCESS: Settlement ledger calculated correctly. Net food: ", ledger["net"]["food"])
	
	# 2. Тестирование очереди строительства (добавление, перемещение, отмена)
	s.economy.add_resource("wood", 500)
	s.economy.add_resource("stone", 500)
	s.start_construction("granary")
	s.start_construction("watchtower")
	assert(s.construction_queue.size() == 2, "Queue should have 2 items")
	assert(s.construction_queue[0]["id"] == "granary", "First should be granary")
	
	s.move_queue_item(0, 1)
	assert(s.construction_queue[0]["id"] == "watchtower", "First should now be watchtower")
	
	s.cancel_queue_item(0)
	assert(s.construction_queue.size() == 1, "Queue should now have 1 item")
	assert(s.construction_queue[0]["id"] == "granary", "Remaining should be granary")
	print("SUCCESS: Construction queue reordering and cancellation verified!")
	
	# 3. Тестирование EventDB и EventManager
	var ev_count = EventDB.EVENTS.size()
	assert(ev_count >= 10, "EventDB should have >= 10 narrative events")
	print("SUCCESS: EventDB has %d narrative events!" % ev_count)
	
	# 4. Тестирование ItemTextureManager
	var food_icon = ItemTextureManager.get_icon("food")
	var wood_icon = ItemTextureManager.get_icon("wood")
	assert(food_icon != null, "Food icon must load")
	assert(wood_icon != null, "Wood icon must load")
	print("SUCCESS: ItemTextureManager successfully returned icons!")
	
	print("ALL UI & MAP OVERHAUL TESTS PASSED!")
	quit(0)
