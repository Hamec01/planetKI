class_name EventManager
extends RefCounted

static var triggered_event_ids: Dictionary = {}
static var last_event_day: int = 120
static var last_ambient_toast_day: int = 25

static func reset() -> void:
	triggered_event_ids.clear()
	last_event_day = 120 # Первые 4 месяца (120 дней) без навязчивых модальных окон!
	last_ambient_toast_day = 25

static func check_triggers() -> void:
	var current_total_days = GameManager.current_year * 360 + GameManager.current_month * 30 + GameManager.current_day
	
	# 1. Фоновые малые оповещения (Toasts) каждые 20-30 дней
	if current_total_days - last_ambient_toast_day >= 25:
		last_ambient_toast_day = current_total_days
		_trigger_ambient_toast()
		
	# 2. Проверка крупных сюжетных дилемм (не чаще чем раз в 60 дней и только после периода адаптации)
	if current_total_days < last_event_day or current_total_days - last_event_day < 60:
		return

		
	var player_settlement = GameManager.settlements.get("player_tribe_settlement", null)
	if player_settlement == null:
		return
		
	var food = player_settlement.economy.get_resource("food")
	var season = GameManager.get_season()
	
	# Проверка "Голодной зимы"
	if season == "Зима" and food < 40.0 and not triggered_event_ids.has("EVENT_001"):
		_trigger("EVENT_001", current_total_days)
		return
		
	# Проверка "Великой засухи" летом
	if season == "Лето" and randf() < 0.35 and not triggered_event_ids.has("EVENT_007"):
		_trigger("EVENT_007", current_total_days)
		return
		
	# Проверка событий генералов
	if randf() < 0.25 and not triggered_event_ids.has("EVENT_G_001"):
		_trigger("EVENT_G_001", current_total_days)
		return
		
	# Случайные племенные дилеммы
	var tribal_events = ["EVENT_002", "EVENT_003", "EVENT_004", "EVENT_005", "EVENT_006", "EVENT_008", "EVENT_009", "EVENT_010"]
	tribal_events.shuffle()
	for ev_id in tribal_events:
		if not triggered_event_ids.has(ev_id):
			_trigger(ev_id, current_total_days)
			return

static func _trigger_ambient_toast() -> void:
	var ambient_pool = [
		{"title": "Охотничья удача", "msg": "Охотники выследили крупного оленя (+15 еды).", "type": "good", "effects": {"food": 15}},
		{"title": "Собиратели ягод", "msg": "В лесной низине собраны сочные ягоды и орехи (+10 еды).", "type": "good", "effects": {"food": 10}},
		{"title": "Находка кремния", "msg": "У ручья найдены острые кремниевые желваки (+5 камня).", "type": "info", "effects": {"stone": 5}},
		{"title": "Совет у костра", "msg": "Старейшины провели вечер бесед о законах предков (+3 лояльности).", "type": "info", "effects": {"loyalty": 3}},
		{"title": "Следы чужаков", "msg": "Дозорные заметили следы неизвестного отряда на границе.", "type": "danger", "effects": {}},
		{"title": "Рождение дитя", "msg": "В семье охотников родился здоровый первенец!", "type": "birth", "effects": {}}
	]
	var choice = ambient_pool[randi() % ambient_pool.size()]
	EventBus.notification_toast.emit(choice["title"], choice["msg"], choice["type"])
	
	var player_s = GameManager.settlements.get("player_tribe_settlement", null)
	if player_s and choice.has("effects"):
		for res in choice["effects"]:
			if res == "loyalty":
				player_s.economy.loyalty = min(100.0, player_s.economy.loyalty + choice["effects"][res])
			else:
				player_s.economy.add_resource(res, choice["effects"][res])

static func _trigger(event_id: String, total_days: int) -> void:
	triggered_event_ids[event_id] = true
	last_event_day = total_days
	var ev_data = EventDB.get_event(event_id)
	if not ev_data.is_empty():
		GameManager.toggle_pause()
		EventBus.event_triggered.emit(ev_data)

static func resolve_choice(event_id: String, choice_index: int) -> void:
	var ev_data = EventDB.get_event(event_id)
	if ev_data.is_empty() or choice_index >= ev_data["choices"].size():
		return
		
	var choice = ev_data["choices"][choice_index]
	var effects = choice.get("effects", {})
	var player_settlement = GameManager.settlements.get("player_tribe_settlement", null)
	
	if player_settlement:
		if effects.has("food"):
			player_settlement.economy.add_resource("food", effects["food"])
		if effects.has("wood"):
			player_settlement.economy.add_resource("wood", effects["wood"])
		if effects.has("stone"):
			player_settlement.economy.add_resource("stone", effects["stone"])
		if effects.has("metal"):
			player_settlement.economy.add_resource("metal", effects["metal"])
		if effects.has("kubriki"):
			player_settlement.economy.add_resource("kubriki", effects["kubriki"])
		if effects.has("knowledge"):
			player_settlement.economy.add_resource("knowledge", effects["knowledge"])
		if effects.has("faith"):
			player_settlement.economy.faith = clampf(player_settlement.economy.faith + effects["faith"], 0.0, 100.0)
		if effects.has("loyalty"):
			player_settlement.economy.loyalty = clampf(player_settlement.economy.loyalty + effects["loyalty"], 0.0, 100.0)
		if effects.has("stability"):
			player_settlement.economy.stability = clampf(player_settlement.economy.stability + effects["stability"], 0.0, 100.0)
		if effects.has("military_spirit"):
			player_settlement.economy.military_spirit = clampf(player_settlement.economy.military_spirit + effects["military_spirit"], 0.0, 100.0)
			
	GameManager.add_history_entry(
		GameManager.current_year,
		ev_data.get("title", "Событие"),
		"Принято решение: " + choice.get("text", "") + ". " + choice.get("hint", ""),
		ev_data.get("category", "Хроника")
	)
	
	EventBus.event_resolved.emit(event_id, choice_index, effects)
	GameManager.toggle_pause()
