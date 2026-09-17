class_name WorldMapView
extends Node2D

const TILE_SIZE: float = 32.0

var planet_data: Dictionary = {}
var hovered_tile_coord: Vector2i = Vector2i(-1, -1)
var selected_tile_coord: Vector2i = Vector2i(-1, -1)
var selected_nature_coord: Vector2i = Vector2i(-1, -1)
var selected_nature_info: Dictionary = {}
var selected_animal_id: String = ""

var current_map_mode: String = "normal"
var anim_time: float = 0.0
var redraw_timer: float = 0.0

# 1. СТРОИТЕЛЬСТВО НА КАРТЕ
var placement_building_id: String = ""

# 2. 1:1 НАСЕЛЕНИЕ НА КАРТЕ
var ambient_villagers: Array[Dictionary] = []

# 3. RTS БОИ И АРМИИ НА КАРТЕ
var selected_army: ArmyData = null
var march_mode_active: bool = false
var arrows: Array[Dictionary] = [] # {from: Vector2, to: Vector2, t: float, speed: float, damage: int, target: ArmyData}
var damage_floats: Array[Dictionary] = [] # {pos: Vector2, text: String, color: Color, life: float}
var combat_sparks: Array[Dictionary] = [] # {pos: Vector2, life: float, color: Color}

var tex_hare = preload("res://Assets/nature_clean/animal_hare.png")
var tex_deer = preload("res://Assets/nature_clean/animal_deer.png")
var tex_carcass = preload("res://Assets/nature_clean/carcass.png")

func _ready() -> void:
	TileTextureManager.load_all_textures()
	BuildingTextureManager.load_all_textures()
	
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.map_mode_changed.connect(_on_map_mode_changed)
	EventBus.start_building_placement.connect(_on_start_building_placement)
	EventBus.cancel_building_placement.connect(_on_cancel_building_placement)
	EventBus.army_selected.connect(_on_army_selected)
	EventBus.army_deselected.connect(_on_army_deselected)
	EventBus.army_command_given.connect(_on_army_command_given)
	
	queue_redraw()

func _on_world_generated(data: Dictionary) -> void:
	planet_data = data
	queue_redraw()

func _on_map_mode_changed(mode_name: String) -> void:
	current_map_mode = mode_name
	queue_redraw()

func _on_start_building_placement(b_id: String) -> void:
	placement_building_id = b_id
	queue_redraw()

func _on_cancel_building_placement() -> void:
	placement_building_id = ""
	queue_redraw()

func _on_army_selected(army_data: RefCounted) -> void:
	if army_data is ArmyData:
		selected_army = army_data
	queue_redraw()

func _on_army_deselected() -> void:
	selected_army = null
	march_mode_active = false
	queue_redraw()

func _on_army_command_given(army_id: String, cmd: String, _target: Variant) -> void:
	var army = _find_army_by_id(army_id)
	if army == null:
		return
		
	army.current_order = cmd
	match cmd:
		"assault":
			army.shout("⚔️ В атаку! Сокрушить вражеский строй!", 4.0)
			# Ищем ближайшую вражескую армию для сближения
			var enemy = _find_nearest_enemy_army(army)
			if enemy:
				army.target_pos = enemy.pos
				army.is_moving = true
		"defend":
			army.shout("🛡️ Держать строй! Сомкнуть щиты!", 4.0)
		"skirmish":
			army.shout("🏹 Стрелки, залп! Осыпать стрелами!", 4.0)
			_trigger_archer_volley(army)
		"flank":
			army.shout("⚡ Обходи с фланга! Заходи в тыл!", 4.0)
		"retreat":
			army.shout("🏳️ Отступаем к стоянке!", 4.0)
			var s = GameManager.settlements.get(army.faction_id + "_settlement", null)
			if s:
				army.target_pos = s.pos
				army.is_moving = true
		"march":
			march_mode_active = true
	queue_redraw()

func _find_army_by_id(army_id: String) -> ArmyData:
	for f_id in GameManager.factions:
		var f: FactionData = GameManager.factions[f_id]
		for a in f.armies:
			if a.id == army_id:
				return a
	return null

func _find_nearest_enemy_army(army: ArmyData) -> ArmyData:
	var best_dist = 999999.0
	var best_a: ArmyData = null
	for f_id in GameManager.factions:
		if f_id != army.faction_id:
			var f: FactionData = GameManager.factions[f_id]
			for a in f.armies:
				var d = army.world_pos.distance_to(a.world_pos)
				if d < best_dist:
					best_dist = d
					best_a = a
	return best_a

# ==============================================================================
# ЖИТЕЛИ (NPC) — ПОЛУЧЕНИЕ ВЫБРАННОГО ГРАЖДАНИНА ПО КЛИКУ
# ==============================================================================
func _get_citizen_near_position(m_pos: Vector2, max_dist: float = 20.0) -> CitizenNPC:
	var player_s = GameManager.settlements.get("player_tribe_settlement", null)
	if not player_s or not player_s.population:
		return null
	var best_c: CitizenNPC = null
	var best_dist = max_dist
	for c in player_s.population.citizens:
		if c.state == CitizenNPC.State.SLEEPING and c.home_id != "":
			continue
		var d = c.pos.distance_to(m_pos)
		if d < best_dist:
			best_dist = d
			best_c = c
	return best_c

func _get_animal_near_position(m_pos: Vector2, max_dist: float = 24.0) -> WildAnimal:
	if not GameManager.wildlife_manager:
		return null
	var best_a: WildAnimal = null
	var best_dist = max_dist
	for animal in GameManager.wildlife_manager.animals.values():
		if not animal.is_alive():
			continue
		var d = animal.pos.distance_to(m_pos)
		if d < best_dist:
			best_dist = d
			best_a = animal
	return best_a

func _get_nature_object_at_position(m_pos: Vector2) -> Dictionary:
	if not planet_data.has("tiles"):
		return {}
	var center_t = Vector2i(int(floor(m_pos.x / TILE_SIZE)), int(floor(m_pos.y / TILE_SIZE)))
	var candidates: Array[Dictionary] = []
	
	for dy in range(2, -3, -1):
		for dx in range(-1, 2):
			var ct = center_t + Vector2i(dx, dy)
			if ct.x < 0 or ct.x >= planet_data["width"] or ct.y < 0 or ct.y >= planet_data["height"]:
				continue
			var tile = planet_data["tiles"][ct.y][ct.x]
			if tile.get("settlement_id", "") != "" or GameManager.tile_buildings.has(ct):
				continue
			var custom_nat = tile.get("nature_object", "")
			var n_data = TileTextureManager.get_nature_data(tile["biome"], ct, tile.get("resource", null), custom_nat)
			if n_data.is_empty() or n_data.get("tex", null) == null:
				continue
				
			var c = Vector2(ct.x * TILE_SIZE + 16.0, ct.y * TILE_SIZE + 16.0)
			var n_tex: Texture2D = n_data["tex"]
			var orig_size = n_tex.get_size()
			var aspect = orig_size.x / maxf(1.0, orig_size.y)
			var target_h: float = n_data.get("scale_h", 20.0)
			var target_w: float = target_h * aspect
			var foot_y = c.y + 11.0
			var n_rect = Rect2(c.x - target_w * 0.5, foot_y - target_h, target_w, target_h)
			
			var hit_rect = n_rect.grow(5.0)
			if hit_rect.has_point(m_pos):
				var node_data = {}
				if GameManager.resource_manager and GameManager.resource_manager.nodes.has(ct):
					node_data = GameManager.resource_manager.nodes[ct]
				candidates.append({
					"coord": ct,
					"tile": tile,
					"n_data": n_data,
					"rect": n_rect,
					"foot_y": foot_y,
					"center": c,
					"target_w": target_w,
					"target_h": target_h,
					"node": node_data
				})
				
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return a["foot_y"] > b["foot_y"])
	return candidates[0]

# ==============================================================================
# ГЛАВНЫЙ ЦИКЛ ОБНОВЛЕНИЯ
# ==============================================================================
func _process(delta: float) -> void:
	anim_time += delta
	redraw_timer += delta
	
	# Симуляция граждан, фауны и армий перенесена в авторитетный runner GameManager (S01).
	# RTS бой и визуальные боевые эффекты исполняются только когда игра не на паузе:
	if not GameManager.is_paused:
		var sim_delta = delta * GameManager.game_speed
		_process_rts_combat(sim_delta)
		_process_combat_effects(sim_delta)
	
	# Обработка наведения мыши
	_process_mouse_hover()
	
	if redraw_timer >= 0.033:
		redraw_timer = 0.0
		queue_redraw()

func _process_rts_combat(delta: float) -> void:
	var player_f: FactionData = GameManager.factions.get(GameManager.player_faction_id, null)
	if player_f == null or player_f.armies.is_empty():
		return
		
	var player_army = player_f.armies[0]
	if player_army.get_total_soldiers() <= 0:
		return
		
	for f_id in GameManager.factions:
		if f_id == GameManager.player_faction_id:
			continue
		var enemy_f: FactionData = GameManager.factions[f_id]
		for enemy_army in enemy_f.armies:
			if enemy_army.get_total_soldiers() <= 0:
				continue
				
			var dist = player_army.world_pos.distance_to(enemy_army.world_pos)
			
			# Если армии сошлись в радиусе боя (~50 пикселей)
			if dist <= 56.0:
				player_army.in_combat = true
				enemy_army.in_combat = true
				
				# Кулдаун ударов и выстрелов
				player_army.attack_cooldown -= delta
				enemy_army.attack_cooldown -= delta
				
				if player_army.attack_cooldown <= 0.0:
					player_army.attack_cooldown = randf_range(1.0, 1.6)
					_execute_army_attack(player_army, enemy_army)
					
				if enemy_army.attack_cooldown <= 0.0:
					enemy_army.attack_cooldown = randf_range(1.2, 1.8)
					_execute_army_attack(enemy_army, player_army)
					
				# Проверка исхода боя
				if enemy_army.morale <= 15.0 or enemy_army.get_total_soldiers() <= 2:
					enemy_army.shout("🏳️ Мы разбиты! Спасайтесь!", 5.0)
					enemy_army.current_order = "retreat"
					EventBus.notification_toast.emit("Победа в бою!", "Дружина под началом генерала %s сокрушила %s!" % [
						player_army.general.get("name", "Брок"), enemy_army.name
					], "good")
					GameManager.add_history_entry(GameManager.current_year, "Славная победа", "Дружина племени разгромила вражеских воинов в прямом столкновении.", "Война")
				elif player_army.morale <= 15.0 or player_army.get_total_soldiers() <= 2:
					player_army.shout("🏳️ Отступаем к костру!", 5.0)
					player_army.current_order = "retreat"
					EventBus.notification_toast.emit("Поражение в бою", "Ваши воины понесли тяжелые потери и отступили.", "bad")
			else:
				if player_army.in_combat and enemy_army.in_combat:
					player_army.in_combat = false
					enemy_army.in_combat = false

func _execute_army_attack(attacker: ArmyData, defender: ArmyData) -> void:
	var att_p = attacker.get_power_rating()
	var def_mult = defender.get_defense_multiplier()
	var is_crit = (randf() < 0.20)
	var raw_damage = int((att_p * randf_range(0.06, 0.11) + 1.0) * (1.5 if is_crit else 1.0) * def_mult)
	
	defender.apply_casualties(raw_damage)
	
	# Если есть лучники — пускаем стрелы!
	if attacker.archers > 0:
		_spawn_arrow(attacker.world_pos, defender.world_pos, raw_damage, defender)
		
	# Искры и текст урона
	var hit_pos = defender.world_pos + Vector2(randf_range(-12, 12), randf_range(-12, 12))
	combat_sparks.append({"pos": hit_pos, "life": 0.35, "color": Color(1.0, 0.8, 0.2)})
	
	var txt = "-%d" % raw_damage
	if is_crit: txt = "КРИТ -%d!" % raw_damage
	elif defender.current_order == "defend": txt = "БЛОК -%d" % raw_damage
	
	var col = Color(1.0, 0.3, 0.2) if is_crit else (Color(0.4, 0.9, 1.0) if defender.current_order == "defend" else Color(1.0, 0.9, 0.3))
	damage_floats.append({"pos": hit_pos + Vector2(0, -10), "text": txt, "color": col, "life": 1.2})
	
	# Боевой клич командира
	if randf() < 0.25 and attacker.speech_timer <= 0.0:
		var phrases = [
			"Руби их!", "Не отступать!", "Вперед за вождя!", "Держать напор!", "Сломать строй!"
		]
		attacker.shout(phrases[randi() % phrases.size()], 2.5)

func _trigger_archer_volley(army: ArmyData) -> void:
	var enemy = _find_nearest_enemy_army(army)
	if enemy and army.archers > 0:
		for i in range(mini(6, army.archers)):
			var delay = i * 0.08
			get_tree().create_timer(delay).timeout.connect(func():
				if is_instance_valid(self):
					_spawn_arrow(army.world_pos, enemy.world_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10)), 2, enemy)
			)

func _spawn_arrow(from: Vector2, to: Vector2, dmg: int, target: ArmyData) -> void:
	arrows.append({
		"from": from,
		"to": to,
		"pos": from,
		"t": 0.0,
		"speed": randf_range(200.0, 260.0),
		"damage": dmg,
		"target": target
	})

func _process_combat_effects(delta: float) -> void:
	# Стрелы
	var i = arrows.size() - 1
	while i >= 0:
		var arr = arrows[i]
		var total_dist = arr["from"].distance_to(arr["to"])
		arr["t"] += (arr["speed"] * delta) / maxf(1.0, total_dist)
		arr["pos"] = arr["from"].lerp(arr["to"], arr["t"])
		if arr["t"] >= 1.0:
			combat_sparks.append({"pos": arr["to"], "life": 0.25, "color": Color(0.9, 0.9, 0.6)})
			arrows.remove_at(i)
		i -= 1
		
	# Цифры урона
	i = damage_floats.size() - 1
	while i >= 0:
		var df = damage_floats[i]
		df["life"] -= delta
		df["pos"] += Vector2(0, -18.0 * delta)
		if df["life"] <= 0.0:
			damage_floats.remove_at(i)
		i -= 1
		
	# Вспышки
	i = combat_sparks.size() - 1
	while i >= 0:
		var cs = combat_sparks[i]
		cs["life"] -= delta
		if cs["life"] <= 0.0:
			combat_sparks.remove_at(i)
		i -= 1

func _process_mouse_hover() -> void:
	var hovered_ui = get_viewport().gui_get_hovered_control()
	if hovered_ui != null and hovered_ui.visible and not (hovered_ui.name == "MapView" or hovered_ui.name == "Game"):
		if hovered_tile_coord != Vector2i(-1, -1):
			hovered_tile_coord = Vector2i(-1, -1)
			queue_redraw()
		return
		
	var mouse_world = get_global_mouse_position()
	var tx = int(floor(mouse_world.x / TILE_SIZE))
	var ty = int(floor(mouse_world.y / TILE_SIZE))
	
	if planet_data.has("width") and planet_data.has("height"):
		if tx >= 0 and tx < planet_data["width"] and ty >= 0 and ty < planet_data["height"]:
			if hovered_tile_coord != Vector2i(tx, ty):
				hovered_tile_coord = Vector2i(tx, ty)
				queue_redraw()
		else:
			if hovered_tile_coord != Vector2i(-1, -1):
				hovered_tile_coord = Vector2i(-1, -1)
				queue_redraw()

# ==============================================================================
# ОБРАБОТКА ВВОДА (КЛИК ПО КАРТЕ, РАЗМЕЩЕНИЕ, ВЫБОР АРМИИ, МАРШ)
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	var hovered_ui = get_viewport().gui_get_hovered_control()
	if hovered_ui != null and hovered_ui.visible and not (hovered_ui.name == "MapView" or hovered_ui.name == "Game"):
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if placement_building_id != "":
				placement_building_id = ""
				EventBus.cancel_building_placement.emit()
				queue_redraw()
				return
			if selected_army != null:
				selected_army = null
				EventBus.army_deselected.emit()
				queue_redraw()
				return
				
	# 1. РЕЖИМ СТРОИТЕЛЬСТВА НА КАРТЕ
	if placement_building_id != "":
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				placement_building_id = ""
				EventBus.cancel_building_placement.emit()
				queue_redraw()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if hovered_tile_coord != Vector2i(-1, -1):
					_try_place_building_at_hovered()
				return
				
	# 2. РЕЖИМ МАРША АРМИИ (ПКМ или клик в режиме марша)
	if selected_army != null:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and march_mode_active):
				if hovered_tile_coord != Vector2i(-1, -1):
					selected_army.target_pos = hovered_tile_coord
					selected_army.is_moving = true
					selected_army.shout("📍 В поход к клетке (%d:%d)!" % [hovered_tile_coord.x, hovered_tile_coord.y], 3.5)
					march_mode_active = false
					EventBus.notification_toast.emit("Приказ марша", "Дружина выступает к цели (%d:%d)" % [hovered_tile_coord.x, hovered_tile_coord.y], "info")
					queue_redraw()
					return
					
	# 3. ПКМ ПО КАРТЕ — КОНТЕКСТНОЕ МЕНЮ ДЕЙСТВИЯ (ПОСТРОИТЬ ЗДЕСЬ И Т.Д.)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if hovered_tile_coord != Vector2i(-1, -1) and planet_data.has("tiles"):
			selected_tile_coord = hovered_tile_coord
			var tile = planet_data["tiles"][selected_tile_coord.y][selected_tile_coord.x]
			var mouse_pos = get_viewport().get_mouse_position()
			EventBus.tile_right_clicked.emit(selected_tile_coord, tile, mouse_pos)
			queue_redraw()
			return
					
	# 4. ОБЫЧНЫЙ ВЫБОР ОБЪЕКТА (СПРАЙТА) / АРМИИ / ЖИТЕЛЯ (ЛКМ)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world = get_global_mouse_position()
		
		# 4.1 Клик по конкретному гражданину (NPC)
		var clicked_citizen = _get_citizen_near_position(mouse_world)
		if clicked_citizen != null:
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = ""
			selected_tile_coord = Vector2i(-1, -1)
			EventBus.citizen_selected.emit(clicked_citizen)
			queue_redraw()
			return

		# 4.2 Клик по дикому животному (фауна)
		var clicked_animal = _get_animal_near_position(mouse_world)
		if clicked_animal != null:
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = clicked_animal.id
			selected_tile_coord = Vector2i(-1, -1)
			var mouse_pos = get_viewport().get_mouse_position()
			EventBus.animal_selected.emit(clicked_animal, mouse_pos)
			queue_redraw()
			return
			
		# 4.3 Клик по армии
		if hovered_tile_coord != Vector2i(-1, -1) and planet_data.has("tiles"):
			var clicked_army = _get_army_at_tile(hovered_tile_coord)
			if clicked_army != null:
				selected_army = clicked_army
				selected_nature_coord = Vector2i(-1, -1)
				selected_nature_info = {}
				selected_animal_id = ""
				selected_tile_coord = Vector2i(-1, -1)
				EventBus.army_selected.emit(clicked_army)
				queue_redraw()
				return

		# 4.4 Клик по природному объекту (дерево, гриб, камень, куст)
		var clicked_nature = _get_nature_object_at_position(mouse_world)
		if not clicked_nature.is_empty():
			selected_nature_coord = clicked_nature["coord"]
			selected_nature_info = clicked_nature
			selected_animal_id = ""
			selected_tile_coord = Vector2i(-1, -1)
			var mouse_pos = get_viewport().get_mouse_position()
			EventBus.nature_object_selected.emit(clicked_nature, mouse_pos)
			queue_redraw()
			return

		# 4.5 Клик по зданию или центру поселения
		var tile_under = Vector2i(int(floor(mouse_world.x / TILE_SIZE)), int(floor(mouse_world.y / TILE_SIZE)))
		if planet_data.has("tiles") and tile_under.x >= 0 and tile_under.x < planet_data["width"] and tile_under.y >= 0 and tile_under.y < planet_data["height"]:
			var tile = planet_data["tiles"][tile_under.y][tile_under.x]
			if GameManager.tile_buildings.has(tile_under) or tile.get("settlement_id", "") != "":
				selected_tile_coord = tile_under
				selected_nature_coord = Vector2i(-1, -1)
				selected_nature_info = {}
				selected_animal_id = ""
				var mouse_pos = get_viewport().get_mouse_position()
				EventBus.tile_selected.emit(selected_tile_coord, tile)
				if tile["settlement_id"] != "":
					var s_data = GameManager.settlements.get(tile["settlement_id"], null)
					if s_data:
						EventBus.settlement_selected.emit(s_data)
				queue_redraw()
				return

		# 4.6 Клик по пустой земле (трава, вода, песок) — СБРОС ВЫБОРА!
		selected_nature_coord = Vector2i(-1, -1)
		selected_nature_info = {}
		selected_animal_id = ""
		selected_tile_coord = Vector2i(-1, -1)
		EventBus.selection_cleared.emit()
		queue_redraw()

func _get_army_at_tile(coord: Vector2i) -> ArmyData:
	for f_id in GameManager.factions:
		var f: FactionData = GameManager.factions[f_id]
		for a in f.armies:
			if a.pos == coord or (a.world_pos.distance_to(Vector2(coord.x * TILE_SIZE + 16, coord.y * TILE_SIZE + 16)) < 24.0):
				return a
	return null

func _can_place_building_at(coord: Vector2i, b_id: String) -> Dictionary:
	var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	if player_s == null:
		return {"valid": false, "reason": "Нет поселения"}
		
	var b_info = BuildingDB.get_building(b_id)
	if b_info.is_empty():
		return {"valid": false, "reason": "Неизвестное здание"}
		
	if not planet_data.has("tiles"):
		return {"valid": false, "reason": "Карта не готова"}
		
	var tiles = planet_data["tiles"]
	if coord.y < 0 or coord.y >= tiles.size() or coord.x < 0 or coord.x >= tiles[0].size():
		return {"valid": false, "reason": "За пределами карты"}
		
	var tile = tiles[coord.y][coord.x]
	if tile.get("is_water", false):
		return {"valid": false, "reason": "❌ Нельзя строить на воде"}
		
	if GameManager.tile_buildings.has(coord):
		return {"valid": false, "reason": "❌ Клетка уже занята"}
		
	if coord == player_s.pos:
		return {"valid": false, "reason": "❌ Центр поселения"}
		
	if not player_s.economy.can_afford(b_info["cost"]):
		return {"valid": false, "reason": "❌ Не хватает ресурсов для стройки"}
		
	return {"valid": true, "reason": "✅ ЛКМ: Заложить фундамент", "cost": b_info["cost"], "name": b_info["name"]}

func _try_place_building_at_hovered() -> void:
	var check = _can_place_building_at(hovered_tile_coord, placement_building_id)
	if check["valid"]:
		var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
		if player_s and player_s.start_construction(placement_building_id, hovered_tile_coord):
			EventBus.building_placed_on_map.emit(placement_building_id, hovered_tile_coord)
			EventBus.notification_toast.emit("Строительство", "Заложено здание: %s" % check["name"], "good")
			if not Input.is_key_pressed(KEY_SHIFT):
				placement_building_id = ""
			queue_redraw()
	else:
		EventBus.notification_toast.emit("Нельзя построить", check["reason"], "bad")

# ==============================================================================
# ОТРИСОВКА КАРТЫ, ПОСТРОЕК, ЖИТЕЛЕЙ, АРМИЙ И ЭФФЕКТОВ
# ==============================================================================
func _draw() -> void:
	if not planet_data.has("tiles") or planet_data["tiles"].is_empty():
		return
		
	var width = planet_data["width"]
	var height = planet_data["height"]
	var tiles = planet_data["tiles"]
	
	# Camera Culling
	var cam = get_viewport().get_camera_2d()
	var cam_pos = cam.global_position if cam else Vector2(width * TILE_SIZE * 0.5, height * TILE_SIZE * 0.5)
	var cam_zoom = cam.zoom.x if (cam and cam.zoom.x > 0.01) else 1.0
	var vp_size = get_viewport_rect().size
	
	var margin = 2
	var min_tx = clampi(int(floor((cam_pos.x - (vp_size.x * 0.5) / cam_zoom) / TILE_SIZE)) - margin, 0, width - 1)
	var max_tx = clampi(int(ceil((cam_pos.x + (vp_size.x * 0.5) / cam_zoom) / TILE_SIZE)) + margin, 0, width - 1)
	var min_ty = clampi(int(floor((cam_pos.y - (vp_size.y * 0.5) / cam_zoom) / TILE_SIZE)) - margin, 0, height - 1)
	var max_ty = clampi(int(ceil((cam_pos.y + (vp_size.y * 0.5) / cam_zoom) / TILE_SIZE)) + margin, 0, height - 1)
	
	# 1. Базовые тайлы поверхности и плавные переходы биомов
	for y in range(min_ty, max_ty + 1):
		for x in range(min_tx, max_tx + 1):
			var tile = tiles[y][x]
			var rect = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			
			var tex = TileTextureManager.get_tile_texture(tile["biome"], tile["coord"], tile["is_river"])
			var mod_color = Color.WHITE
			
			if current_map_mode == "fertility":
				var moisture = tile.get("moisture", 0.5)
				var elevation = tile.get("elevation", 0.5)
				var fertility_score = moisture * (1.0 - abs(elevation - 0.4))
				mod_color = Color(1.0 - fertility_score * 0.8, 1.0 + fertility_score * 0.5, 0.6)
			elif current_map_mode == "political":
				if tile["settlement_id"] != "":
					var is_pl = (tile["settlement_id"] == "player_tribe_settlement")
					mod_color = Color(0.7, 0.9, 1.2) if is_pl else Color(1.2, 0.8, 0.8)
			elif current_map_mode == "religion":
				mod_color = Color(1.1, 1.0, 1.25)
				
			if tex:
				draw_texture_rect(tex, rect, false, mod_color)
			else:
				var biome_info = BiomeDefinitions.get_biome_info(tile["biome"])
				draw_rect(rect, biome_info["color"])
				
			# Плавные переходы биомов суши к воде и между слоями
			var overlays = TerrainResolver.get_transition_overlays(tiles, x, y, width, height)
			for ov in overlays:
				var ov_tex = TileTextureManager.get_overlay_texture(ov["biome_folder"], ov["mask"])
				if ov_tex:
					draw_texture_rect(ov_tex, rect, false, mod_color)
					
			# 2. Природные объекты (деревья, скалы, кустарники, трава, цветы, грибы)
			var custom_nat = tile.get("nature_object", "")
			var n_data = TileTextureManager.get_nature_data(tile["biome"], tile["coord"], tile.get("resource", null), custom_nat)
			if not n_data.is_empty() and n_data.get("tex", null) != null and tile["settlement_id"] == "" and not GameManager.tile_buildings.has(Vector2i(x, y)):
				var c = rect.get_center()
				var n_tex: Texture2D = n_data["tex"]
				var orig_size = n_tex.get_size()
				var aspect = orig_size.x / maxf(1.0, orig_size.y)
				var target_h: float = n_data.get("scale_h", 20.0)
				var target_w: float = target_h * aspect
				
				# Основание объекта на земле тайла
				var foot_y = c.y + 11.0
				var n_rect = Rect2(c.x - target_w * 0.5, foot_y - target_h, target_w, target_h)
				
				# Мягкая эллиптическая тень под основанием
				var shadow_radius = target_w * (0.30 if n_data.get("category", "") == "tree" else 0.40)
				draw_circle(Vector2(c.x, foot_y - 1.0), shadow_radius, Color(0, 0, 0, 0.22))
				
				draw_texture_rect(n_tex, n_rect, false)
				
			# Иконки ресурсов отображаются ТОЛЬКО в специальном режиме карты "Ресурсы"
			if tile["resource"] != null and current_map_mode == "resources":
				_draw_resource_icon(rect, tile["resource"]["type"])

	# 2. Построенные и строящиеся здания
	_draw_visible_settlement_buildings()

	# 3. Центры поселений
	for s_id in GameManager.settlements:
		var s = GameManager.settlements[s_id]
		var s_rect = Rect2(s.pos.x * TILE_SIZE, s.pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		_draw_settlement_hub(s_rect, s)
		
	# 4. 1:1 Граждане поселения (живая симуляция NPC)
	_draw_citizens()

	# 4.1 Дикие животные и туши на карте (Этап C)
	_draw_wildlife()

	# 5. Дружины и армии (RTS на карте)
	_draw_armies_and_combat()
	
	# 6. Эффекты стрел, урона и искр
	_draw_combat_effects()

	# 7. ПОДСВЕТКА И ПРИЗРАК ПРИ СТРОИТЕЛЬСТВЕ НА КАРТЕ
	if placement_building_id != "" and hovered_tile_coord != Vector2i(-1, -1):
		_draw_building_placement_preview()
		
	# 8. ПОДСВЕТКА ВЫБРАННОГО ПРИРОДНОГО СПРАЙТА (ДЕРЕВО / КАМЕНЬ / ГРИБ / КУСТ)
	if selected_nature_coord != Vector2i(-1, -1) and not selected_nature_info.is_empty():
		_draw_selected_nature_highlight()
		
	# 9. ПОДСВЕТКА ВЫБРАННОГО ДИКОГО ЖИВОТНОГО
	if selected_animal_id != "":
		_draw_selected_animal_highlight()

# --- ОТРИСОВКА РЕЖИМА СТРОИТЕЛЬСТВА НА КАРТЕ ---
func _draw_building_placement_preview() -> void:
	var coord = hovered_tile_coord
	var check = _can_place_building_at(coord, placement_building_id)
	var rect = Rect2(coord.x * TILE_SIZE, coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var c = rect.get_center()
	
	var is_valid = check["valid"]
	var grid_color = Color(0.2, 0.9, 0.3, 0.75) if is_valid else Color(0.95, 0.25, 0.2, 0.75)
	var fill_color = Color(0.2, 0.9, 0.3, 0.20) if is_valid else Color(0.95, 0.25, 0.2, 0.25)
	
	# Подсветка тайла
	draw_rect(rect, fill_color)
	draw_rect(rect, grid_color, false, 2.0)
	
	# Полупрозрачный силуэт здания
	var b_tex = BuildingTextureManager.get_texture(placement_building_id)
	if b_tex:
		var b_size = TILE_SIZE * 0.9
		var b_rect = Rect2(c.x - b_size * 0.5, c.y - b_size * 0.5, b_size, b_size)
		var tint = Color(0.6, 1.0, 0.6, 0.8) if is_valid else Color(1.0, 0.5, 0.5, 0.65)
		draw_texture_rect(b_tex, b_rect, false, tint)
		
	# Всплывающий тултип с ценой и статусом
	var tip_pos = c + Vector2(0, -TILE_SIZE * 0.8)
	var tip_text = check["reason"]
	var font = ThemeDB.fallback_font
	var text_w = tip_text.length() * 6.5 + 16
	var tip_rect = Rect2(tip_pos.x - text_w * 0.5, tip_pos.y - 8, text_w, 18)
	draw_rect(tip_rect, Color(0.08, 0.1, 0.15, 0.95))
	draw_rect(tip_rect, grid_color, false, 1.2)
	draw_string(font, tip_pos + Vector2(-text_w * 0.5 + 8, 5), tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

# --- ОТРИСОВКА ВЫДЕЛЕНИЯ ПРИРОДНОГО СПРАЙТА (ДЕРЕВО / КАМЕНЬ / ГРИБЫ) ---
func _draw_selected_nature_highlight() -> void:
	var info = selected_nature_info
	var c: Vector2 = info.get("center", Vector2.ZERO)
	var foot_y: float = info.get("foot_y", c.y + 11.0)
	var target_w: float = info.get("target_w", 24.0)
	var target_h: float = info.get("target_h", 24.0)
	var coord: Vector2i = info.get("coord", Vector2i(-1, -1))
	
	# Получаем актуальные данные ресурса (включая остаток)
	var node = {}
	if GameManager.resource_manager and GameManager.resource_manager.nodes.has(coord):
		node = GameManager.resource_manager.nodes[coord]
	elif info.has("node") and not info["node"].is_empty():
		node = info["node"]
		
	# 1. Плавное пульсирующее кольцо у основания объекта
	var pulse = 1.0 + sin(anim_time * 4.5) * 0.08
	var sel_rad = maxf(9.0, target_w * 0.38) * pulse
	var base_pos = Vector2(c.x, foot_y - 2.0)
	
	draw_circle(base_pos, sel_rad, Color(0.2, 0.9, 0.45, 0.22))
	draw_arc(base_pos, sel_rad, 0.0, TAU, 28, Color(0.35, 1.0, 0.55, 0.95), 1.8)
	
	# 2. Информационный парящий бейдж над макушкой объекта: "🌲 100 / 100"
	var font = ThemeDB.fallback_font
	var res_amt = float(node.get("amount", 100.0)) if not node.is_empty() else 100.0
	var max_amt = float(node.get("max_amount", 100.0)) if not node.is_empty() else 100.0
	var res_type = node.get("type", "wood") if not node.is_empty() else "wood"
	
	var icon_sym = "🌲"
	if res_type in ["berries", "mushrooms"]:
		icon_sym = "🍄" if res_type == "mushrooms" else "🍓"
	elif res_type in ["stone", "metal"]:
		icon_sym = "🪨" if res_type == "stone" else "⛏"
		
	var label_txt = "%s %d / %d" % [icon_sym, int(res_amt), int(max_amt)]
	var txt_w = label_txt.length() * 6.5 + 16.0
	var badge_pos = Vector2(c.x, foot_y - target_h - 18.0)
	var badge_rect = Rect2(badge_pos.x - txt_w * 0.5, badge_pos.y - 8.0, txt_w, 18.0)
	
	# Тень, плашка и рамка бейджа
	draw_circle(Vector2(c.x, foot_y - target_h - 9.0), 3.0, Color(0.35, 1.0, 0.55, 0.9))
	draw_rect(badge_rect, Color(0.08, 0.12, 0.16, 0.94))
	draw_rect(badge_rect, Color(0.35, 1.0, 0.55, 0.9), false, 1.2)
	
	# Мини-индикатор заполненности ресурса в бейдже
	var fill_pct = clampf(res_amt / maxf(1.0, max_amt), 0.0, 1.0)
	var bar_y = badge_rect.end.y - 2.0
	draw_line(Vector2(badge_rect.position.x + 2, bar_y), Vector2(badge_rect.position.x + 2 + (txt_w - 4) * fill_pct, bar_y), Color(0.35, 1.0, 0.55, 0.95), 2.0)
	
	draw_string(font, badge_pos + Vector2(-txt_w * 0.5 + 8, 4), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

# --- ОТРИСОВКА ВЫДЕЛЕНИЯ ДИКОГО ЖИВОТНОГО ---
func _draw_selected_animal_highlight() -> void:
	if not GameManager.wildlife_manager:
		return
	var animal = GameManager.wildlife_manager.animals.get(selected_animal_id, null)
	if animal == null or not animal.is_alive():
		return
	var p = animal.pos
	var pulse = 1.0 + sin(anim_time * 5.0) * 0.08
	var r = 11.0 * pulse * animal.get_scale()
	draw_circle(p + Vector2(0, 1.5), r, Color(1.0, 0.85, 0.3, 0.20))
	draw_arc(p + Vector2(0, 1.5), r, 0.0, TAU, 24, Color(1.0, 0.88, 0.35, 0.95), 1.8)

# --- ОТРИСОВКА ЗДАНИЙ ---
func _draw_visible_settlement_buildings() -> void:
	for coord in GameManager.tile_buildings:
		var b_data = GameManager.tile_buildings[coord]
		var b_id = b_data.get("id", "")
		var status = b_data.get("status", "active")
		var c = Vector2(coord.x * TILE_SIZE + 16, coord.y * TILE_SIZE + 16)
		var b_size = TILE_SIZE * 0.88
		var b_rect = Rect2(c.x - b_size * 0.5, c.y - b_size * 0.5, b_size, b_size)
		
		draw_circle(c, b_size * 0.42, Color(0.18, 0.22, 0.16, 0.6))
		
		var b_tex = BuildingTextureManager.get_texture(b_id)
		if status == "constructing":
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false, Color(1, 1, 1, 0.45))
			
			# Строительные леса
			var scaffold_rect = Rect2(c.x - 13, c.y - 13, 26, 26)
			draw_rect(scaffold_rect, Color(0.85, 0.65, 0.25, 0.7), false, 1.8)
			draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), Color(0.85, 0.65, 0.25, 0.8), 1.5)
			draw_line(c + Vector2(11, -11), c + Vector2(-11, 11), Color(0.85, 0.65, 0.25, 0.8), 1.5)
			
			# Прогресс-бар стройки
			var days_left = float(b_data.get("days_left", 1.0))
			var total_days = float(b_data.get("total_days", 1.0))
			var pct = clampf(1.0 - (days_left / maxf(total_days, 1.0)), 0.0, 1.0)
			
			var p_rect = Rect2(c.x - 14, c.y + 11, 28, 5)
			draw_rect(p_rect, Color(0.08, 0.1, 0.14, 0.9))
			draw_rect(Rect2(p_rect.position.x + 1, p_rect.position.y + 1, (p_rect.size.x - 2) * pct, p_rect.size.y - 2), Color(0.35, 0.88, 0.35, 0.95))
			draw_rect(p_rect, Color(0.85, 0.7, 0.3, 0.7), false, 1.0)
		else:
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)

# --- ОТРИСОВКА ЦЕНТРА ПОСЕЛЕНИЯ ---
func _draw_settlement_hub(rect: Rect2, s: SettlementData) -> void:
	var c = rect.get_center()
	var is_player = (s.id == "player_tribe_settlement")
	var theme_color = Color(0.2, 0.7, 1.0) if is_player else Color(0.95, 0.35, 0.25)
	
	var pulse = 1.0 + sin(anim_time * 2.0) * 0.05
	draw_circle(c, TILE_SIZE * 1.1 * pulse, Color(theme_color.r, theme_color.g, theme_color.b, 0.18))
	draw_circle(c, TILE_SIZE * 1.1 * pulse, Color(theme_color.r, theme_color.g, theme_color.b, 0.8), false, 1.5)
	
	# Костер
	var fire_pos = c + Vector2(0, 8)
	var fire_radius = 4.5 + sin(anim_time * 8.0) * 1.2
	draw_circle(fire_pos, fire_radius * 1.6, Color(1.0, 0.5, 0.1, 0.35))
	draw_circle(fire_pos, fire_radius, Color(1.0, 0.75, 0.1, 0.9))
	draw_circle(fire_pos, fire_radius * 0.5, Color(1.0, 0.95, 0.7, 1.0))
	
	var smoke_offset = Vector2(sin(anim_time * 2.5) * 4.0, -12.0 - fmod(anim_time * 12.0, 16.0))
	draw_circle(fire_pos + smoke_offset, 2.5, Color(0.85, 0.85, 0.9, 0.35))
	
	var main_b_id = "elders_house" if is_player else "hunting_camp"
	if s.buildings.has("great_lodge"):
		main_b_id = "great_lodge"
	var b_tex = BuildingTextureManager.get_texture(main_b_id)
	if b_tex:
		var b_size = TILE_SIZE * 1.1
		var b_rect = Rect2(c.x - b_size * 0.5, c.y - b_size * 0.5 - 6, b_size, b_size)
		draw_texture_rect(b_tex, b_rect, false)
		
	# 4. Информационная плашка над поселением отображается ТОЛЬКО при наведении мыши или клике
	var is_hovered = (hovered_tile_coord == s.pos)
	var is_selected = (selected_tile_coord == s.pos)
	if is_hovered or is_selected:
		var title_pos = c + Vector2(0, -TILE_SIZE * 0.95)
		var full_text = "%s • %d чел." % [s.name, s.population.get_total_population()]
		var text_w = full_text.length() * 6.5 + 14
		var banner_rect = Rect2(title_pos.x - text_w * 0.5, title_pos.y - 9, text_w, 18)
		draw_rect(banner_rect, Color(0.12, 0.15, 0.22, 0.94))
		draw_rect(banner_rect, theme_color, false, 1.2)
		
		var font = ThemeDB.fallback_font
		draw_string(font, title_pos + Vector2(-text_w * 0.5 + 7, 4), full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.7))

# --- ОТРИСОВКА 1:1 ЖИТЕЛЕЙ (NPC) ---
func _draw_citizens() -> void:
	var font = ThemeDB.fallback_font
	
	for s_id in GameManager.settlements:
		var s: SettlementData = GameManager.settlements[s_id]
		if not s.population:
			continue
			
		for c in s.population.citizens:
			# Если житель спит в доме — скрываем со двора
			if c.state == CitizenNPC.State.SLEEPING and c.home_id != "":
				continue
				
			var p = c.pos
			var char_tex = c.get_texture()
			var char_size = Vector2(12.0, 12.0)
			
			var is_moving = (c.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.GOING_HOME, CitizenNPC.State.FLEEING] or not c.path.is_empty())
			var is_working = (c.state in [CitizenNPC.State.WORKING, CitizenNPC.State.GATHERING, CitizenNPC.State.BUTCHERING])
			
			var bob = sin(anim_time * 10.0 + float(c.seed_val % 100)) * 0.8 if is_moving else 0.0
			var char_rect = Rect2(p.x - char_size.x * 0.5, p.y - char_size.y + 2.0 + bob, char_size.x, char_size.y)
			
			# Тень под ногами
			draw_circle(p + Vector2(0, 1.5), 2.5, Color(0, 0, 0, 0.35))
			
			if char_tex:
				draw_texture_rect(char_tex, char_rect, false)
			else:
				draw_circle(p, 2.0, Color(0.9, 0.8, 0.7))
				draw_circle(p + Vector2(0, 2.0), 2.2, Color(0.35, 0.45, 0.6))

			# Визуальные движения инструмента при работе и оружие стражи
			if is_working:
				var swing = sin(anim_time * 8.0) * 4.0
				if c.job_id == "woodcutter":
					draw_line(p + Vector2(4, -6), p + Vector2(7 + swing, -10 - swing * 0.5), Color(0.65, 0.45, 0.25), 1.6)
					draw_circle(p + Vector2(7 + swing, -10 - swing * 0.5), 2.2, Color(0.75, 0.8, 0.85))
				elif c.job_id in ["quarryman", "miner"]:
					draw_line(p + Vector2(4, -6), p + Vector2(7 - swing, -9 + swing * 0.5), Color(0.6, 0.4, 0.2), 1.6)
					draw_circle(p + Vector2(7 - swing, -9 + swing * 0.5), 2.0, Color(0.85, 0.75, 0.4))
				elif c.job_id == "builder":
					draw_line(p + Vector2(4, -5), p + Vector2(7, -8 + swing * 0.6), Color(0.6, 0.4, 0.2), 1.5)
			elif c.job_id in ["guard", "warrior"]:
				draw_line(p + Vector2(5.0, 1.0), p + Vector2(5.0, -char_size.y - 4.0), Color(0.55, 0.38, 0.2), 1.5)
				draw_line(p + Vector2(5.0, -char_size.y - 4.0), p + Vector2(5.0, -char_size.y - 7.0), Color(0.8, 0.85, 0.9), 2.0)
				
			# Индикатор сна под открытым небом
			if c.state == CitizenNPC.State.SLEEPING:
				draw_string(font, p + Vector2(-6, -char_size.y - 2), "zZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.8, 1.0, 0.85))
				
			# Значок переносимого груза
			if c.cargo_type != "" and c.cargo_amount > 0:
				var cargo_icon = ItemTextureManager.get_icon(c.cargo_type)
				var icon_pos = p + Vector2(-4.0, -char_size.y - 6.0 + bob)
				draw_circle(icon_pos + Vector2(4.0, 4.0), 5.0, Color(0.08, 0.1, 0.15, 0.92))
				if cargo_icon:
					draw_texture_rect(cargo_icon, Rect2(icon_pos + Vector2(0.5, 0.5), Vector2(7.0, 7.0)), false)
				else:
					draw_circle(icon_pos + Vector2(4.0, 4.0), 2.5, Color(0.9, 0.7, 0.2))
					
			# Речевое облачко при общении
			if c.speech_timer > 0.0 and c.speech_bubble != "":
				var txt_size = font.get_string_size(c.speech_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
				var b_rect = Rect2(p.x - txt_size.x * 0.5 - 4, p.y - char_size.y - 18.0, txt_size.x + 8, 13)
				draw_rect(b_rect, Color(0.1, 0.12, 0.16, 0.92), true)
				draw_rect(b_rect, Color(0.7, 0.85, 1.0, 0.85), false, 1.0)
				draw_string(font, Vector2(b_rect.position.x + 4, b_rect.position.y + 10), c.speech_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 1.0, 0.9))
				
			# Визуальная анимация рубки дерева со щепками
			if c.job_id == "woodcutter" and c.state == CitizenNPC.State.WORKING:
				var chop_phase = sin(anim_time * 12.0)
				var axe_dir = 1.0 if c.facing_dir.x >= 0 else -1.0
				var axe_blade = p + Vector2(6.0 * axe_dir, -6.0 + chop_phase * 4.0)
				draw_line(p + Vector2(2 * axe_dir, -4), axe_blade, Color(0.5, 0.35, 0.2), 2.0)
				draw_circle(axe_blade, 2.2, Color(0.75, 0.8, 0.85))
				if chop_phase > 0.3:
					for chip_i in range(3):
						var chip_off = Vector2(sin(anim_time * 10.0 + chip_i) * 8.0, -8.0 - cos(anim_time * 10.0 + chip_i) * 5.0)
						draw_circle(axe_blade + chip_off, 1.2, Color(0.85, 0.7, 0.4, 0.9))

			# Полоска здоровья над раненым жителем
			if c.health < c.max_health:
				var hp_pct = clampf(c.health / c.max_health, 0.0, 1.0)
				var bar_w = 12.0
				var bar_pos = p + Vector2(-bar_w * 0.5, -char_size.y - 5.0)
				draw_rect(Rect2(bar_pos.x, bar_pos.y, bar_w, 2.0), Color(0.1, 0.1, 0.1, 0.8))
				draw_rect(Rect2(bar_pos.x, bar_pos.y, bar_w * hp_pct, 2.0), Color(0.9, 0.2, 0.2, 0.95))

			# Видимый момент атаки охотника (выстрел стрелы / бросок копья)
			if c.state == CitizenNPC.State.ATTACKING and c.target_id != "" and GameManager.wildlife_manager:
				if GameManager.wildlife_manager.animals.has(c.target_id):
					var anim_target = GameManager.wildlife_manager.animals[c.target_id]
					var to_t = anim_target.pos - p
					var dist = to_t.length()
					if dist > 4.0:
						var dir = to_t.normalized()
						var shot_pct = 1.0 - clampf(c.work_timer / 1.2, 0.0, 1.0)
						var arrow_p = p + dir * (dist * shot_pct)
						draw_line(arrow_p - dir * 5.0, arrow_p, Color(1.0, 0.88, 0.35, 0.95), 1.6)

# --- ОТРИСОВКА ДИКИХ ЖИВОТНЫХ И ТУШ (24 ВИДА) ---
func _draw_wildlife() -> void:
	if not GameManager.wildlife_manager:
		return
		
	# 1. Туши на земле
	for c in GameManager.wildlife_manager.carcasses.values():
		var p = c["pos"]
		draw_circle(p + Vector2(0, 1.0), 4.0, Color(0, 0, 0, 0.35))
		if tex_carcass:
			var c_size = 14.0 if c.get("max_meat", 3.0) > 10.0 else 10.0
			draw_texture_rect(tex_carcass, Rect2(p.x - c_size * 0.5, p.y - c_size * 0.5, c_size, c_size), false)
		else:
			draw_circle(p, 3.5, Color(0.65, 0.25, 0.2))
			
	# 2. 24 вида диких животных
	for animal in GameManager.wildlife_manager.animals.values():
		if not animal.is_alive():
			continue
		var p = animal.pos
		var is_moving = (animal.state in [WildAnimal.State.FLEEING, WildAnimal.State.GRAZING, WildAnimal.State.FOLLOWING, WildAnimal.State.SWIMMING, WildAnimal.State.DEFENDING])
		var bob = sin(animal.wobble_timer) * 0.8 if is_moving else 0.0
		
		# Эффект ряби на воде для плавающих уток
		if animal.state == WildAnimal.State.SWIMMING:
			draw_arc(p + Vector2(0, 2.0), 6.0 + sin(anim_time * 4.0) * 1.5, 0, TAU, 12, Color(0.6, 0.85, 1.0, 0.4), 1.0)
		else:
			var shadow_r = 5.0 * animal.get_scale()
			draw_circle(p + Vector2(0, 1.5), shadow_r, Color(0, 0, 0, 0.26))
			
		var a_tex = animal.get_texture()
		var a_scale = animal.get_scale()
		var base_dim = 16.0
		if animal.species in ["moose", "bear"]:
			base_dim = 22.0
		elif animal.species in ["deer", "boar", "wolf"]:
			base_dim = 18.0
		elif animal.species in ["fox", "lynx", "badger"]:
			base_dim = 15.0
		else:
			base_dim = 13.0
			
		var a_size = Vector2(base_dim, base_dim) * a_scale
		
		# Отражение по горизонтали в зависимости от facing_dir
		var flipped = (animal.facing_dir.x < 0.0)
		var a_rect: Rect2
		if flipped:
			a_rect = Rect2(p.x + a_size.x * 0.5, p.y - a_size.y + 2.0 + bob, -a_size.x, a_size.y)
		else:
			a_rect = Rect2(p.x - a_size.x * 0.5, p.y - a_size.y + 2.0 + bob, a_size.x, a_size.y)
			
		if a_tex:
			draw_texture_rect(a_tex, a_rect, false)
		else:
			draw_circle(p, 3.0, Color(0.8, 0.6, 0.4))
			
		# Полоска здоровья при ранении
		if animal.health < animal.max_health:
			var hp_pct = clampf(animal.health / animal.max_health, 0.0, 1.0)
			var bar_w = 14.0 * a_scale
			var bar_pos = p + Vector2(-bar_w * 0.5, -a_size.y - 3.0)
			draw_rect(Rect2(bar_pos.x, bar_pos.y, bar_w, 2.0), Color(0.2, 0.2, 0.2, 0.8))
			draw_rect(Rect2(bar_pos.x, bar_pos.y, bar_w * hp_pct, 2.0), Color(0.9, 0.2, 0.2, 0.95))

# --- ОТРИСОВКА RTS АРМИЙ, ГЕНЕРАЛОВ И СТРОЯ ---
func _draw_armies_and_combat() -> void:
	var font = ThemeDB.fallback_font
	
	for f_id in GameManager.factions:
		var f: FactionData = GameManager.factions[f_id]
		var is_pl = (f_id == GameManager.player_faction_id)
		
		for a in f.armies:
			if a.get_total_soldiers() <= 0:
				continue
				
			var p = a.world_pos
			var is_sel = (selected_army == a)
			var a_tile = Vector2i(int(floor(p.x / TILE_SIZE)), int(floor(p.y / TILE_SIZE)))
			var is_hovered = (hovered_tile_coord == a.pos or hovered_tile_coord == a_tile)
			
			# Линия пути марша если армия идет
			if a.is_moving:
				var dest = Vector2(a.target_pos.x * TILE_SIZE + 16, a.target_pos.y * TILE_SIZE + 16)
				draw_dashed_line(p, dest, Color(1.0, 0.85, 0.3, 0.7) if is_pl else Color(1.0, 0.3, 0.3, 0.5), 1.5, 4.0)
				draw_circle(dest, 3.5, Color(1.0, 0.85, 0.3, 0.9))
				
			# Круг селекта под армией
			if is_sel:
				var pulse = 1.0 + sin(anim_time * 6.0) * 0.1
				draw_circle(p, 18.0 * pulse, Color(0.2, 0.8, 1.0, 0.25))
				draw_circle(p, 18.0 * pulse, Color(0.2, 0.8, 1.0, 0.9), false, 2.0)
				
			# Отрисовка строя мини-воинов вокруг генерала (по числу реальных воинов)
			var formation_offsets = [
				Vector2(-10, 4), Vector2(10, 4), Vector2(-6, 9), Vector2(6, 9),
				Vector2(-12, -4), Vector2(12, -4), Vector2(0, 10)
			]
			
			var soldier_count = mini(formation_offsets.size(), a.get_total_soldiers())
			for k in range(soldier_count):
				var f_off = formation_offsets[k]
				var soldier_pos = p + f_off
				var s_type = "warrior" if k % 3 == 0 else ("spearman" if k % 3 == 1 else "archer")
				var s_tex = CharacterTextureManager.get_character_for_job(s_type, k * 7)
				
				var s_bob = sin(anim_time * 8.0 + k) * 0.6 if a.is_moving or a.in_combat else 0.0
				var s_rect = Rect2(soldier_pos.x - 4, soldier_pos.y - 8 + s_bob, 8, 8)
				
				draw_circle(soldier_pos + Vector2(0, 1), 1.5, Color(0, 0, 0, 0.3))
				if s_tex:
					draw_texture_rect(s_tex, s_rect, false)
				else:
					draw_circle(soldier_pos, 1.6, f.color)
					
			# Фигурка Генерала в центре строя
			var gen_tex = CharacterTextureManager.get_character_for_job("general", 1)
			var gen_bob = sin(anim_time * 7.0) * 0.8 if a.is_moving else 0.0
			var gen_rect = Rect2(p.x - 6, p.y - 12 + gen_bob, 12, 12)
			
			draw_circle(p + Vector2(0, 1), 2.8, Color(0, 0, 0, 0.45))
			if gen_tex:
				draw_texture_rect(gen_tex, gen_rect, false)
			else:
				draw_circle(p, 2.8, Color(1.0, 0.85, 0.3))
				
			# Знамя и плашка армии отображаются ТОЛЬКО при наведении или выборе
			if is_sel or is_hovered:
				var banner_pos = p + Vector2(0, -18)
				var gen_dict = a.general if a.general else {}
				var g_name = gen_dict.get("name", a.name)
				var army_title = "⚔️ %s (%d)" % [g_name, a.get_total_soldiers()]
				var bw = army_title.length() * 5.8 + 10
				var b_rect = Rect2(banner_pos.x - bw * 0.5, banner_pos.y - 7, bw, 14)
				
				draw_rect(b_rect, Color(0.1, 0.12, 0.18, 0.92))
				draw_rect(b_rect, f.color, false, 1.2)
				draw_string(font, banner_pos + Vector2(-bw * 0.5 + 5, 3), army_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.95, 0.8))
				
				# Полоса морали под плашкой
				var m_pct = clampf(a.morale / 100.0, 0.0, 1.0)
				var m_bar = Rect2(banner_pos.x - bw * 0.5, banner_pos.y + 8, bw, 3)
				draw_rect(m_bar, Color(0.1, 0.1, 0.1, 0.8))
				draw_rect(Rect2(m_bar.position.x, m_bar.position.y, bw * m_pct, 3), Color(0.3, 0.85, 0.3) if m_pct > 0.4 else Color(0.9, 0.25, 0.2))
			
			# Облачко боевого клика Генерала
			if a.speech_bubble != "":
				var s_text = a.speech_bubble
				var sw = s_text.length() * 6.2 + 12
				var s_rect = Rect2(p.x - sw * 0.5, p.y - 38, sw, 16)
				draw_rect(s_rect, Color(1.0, 0.98, 0.85, 0.95))
				draw_rect(s_rect, Color(0.2, 0.15, 0.1), false, 1.2)
				draw_string(font, Vector2(s_rect.position.x + 6, s_rect.position.y + 11), s_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.1, 0.08, 0.05))

# --- ОТРИСОВКА СТРЕЛ И ЭФФЕКТОВ БОЯ ---
func _draw_combat_effects() -> void:
	var font = ThemeDB.fallback_font
	
	# Стрелы
	for arr in arrows:
		var p1 = arr["pos"]
		var dir = (arr["to"] - arr["from"]).normalized()
		var p2 = p1 - dir * 6.0
		draw_line(p2, p1, Color(0.9, 0.85, 0.65, 0.95), 1.6)
		draw_circle(p1, 1.2, Color(0.3, 0.3, 0.3))
		
	# Вспышки ударов
	for cs in combat_sparks:
		draw_circle(cs["pos"], 3.5, cs["color"])
		
	# Цифры урона
	for df in damage_floats:
		var txt = df["text"]
		var p = df["pos"]
		var col = df["color"]
		draw_string(font, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0, 0, 0, 0.8))
		draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, col)

func _draw_resource_icon(rect: Rect2, res_type: String) -> void:
	var tex = ItemTextureManager.get_icon(res_type)
	var c = rect.get_center()
	var s = TILE_SIZE * 0.65
	var icon_rect = Rect2(c.x - s * 0.5, c.y - s * 0.5, s, s)
	
	draw_circle(c, s * 0.6, Color(0.08, 0.1, 0.14, 0.85))
	draw_circle(c, s * 0.6, Color(1.0, 0.85, 0.3, 0.7), false, 1.0)
	
	if tex:
		draw_texture_rect(tex, icon_rect, false)
	else:
		draw_circle(c, 4.0, Color(1.0, 0.8, 0.2, 0.9))
