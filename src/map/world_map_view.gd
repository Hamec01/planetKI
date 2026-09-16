class_name WorldMapView
extends Node2D

const TILE_SIZE: float = 32.0

var planet_data: Dictionary = {}
var hovered_tile_coord: Vector2i = Vector2i(-1, -1)
var selected_tile_coord: Vector2i = Vector2i(-1, -1)

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
	_sync_population_villagers()
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
# 1:1 СИНХРОНИЗАЦИЯ НАСЕЛЕНИЯ С КАРТОЙ
# ==============================================================================
func _sync_population_villagers() -> void:
	var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	if player_s == null:
		return
		
	var target_count = player_s.population.get_total_population()
	var center_pos = Vector2(player_s.pos.x * TILE_SIZE + 16, player_s.pos.y * TILE_SIZE + 16)
	
	# Создаем пул ролей на основе реальных assigned_jobs
	var role_pool: Array[String] = []
	for job_id in player_s.assigned_jobs:
		var count = player_s.assigned_jobs[job_id]
		for _k in range(count):
			role_pool.append(job_id)
			
	while role_pool.size() < target_count:
		role_pool.append("villager")
	if role_pool.size() > target_count:
		role_pool.resize(target_count)
		
	# Синхронизируем размер массива
	while ambient_villagers.size() < target_count:
		var idx = ambient_villagers.size()
		var job = role_pool[idx] if idx < role_pool.size() else "villager"
		ambient_villagers.append({
			"pos": center_pos + Vector2(randf_range(-14, 14), randf_range(-14, 14)),
			"home_pos": center_pos,
			"target_pos": center_pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)),
			"speed": randf_range(16.0, 24.0),
			"state": 0, # 0 = walk to target, 1 = work, 2 = return
			"work_timer": randf_range(1.5, 4.0),
			"cargo": _get_cargo_for_job(job),
			"carrying": false,
			"type": job,
			"seed": idx * 19 + randi() % 100,
			"tex": CharacterTextureManager.get_character_for_job(job, idx)
		})
		
	while ambient_villagers.size() > target_count:
		ambient_villagers.pop_back()
		
	# Обновляем роли существующих жителей
	for i in range(ambient_villagers.size()):
		var v = ambient_villagers[i]
		var job = role_pool[i] if i < role_pool.size() else "villager"
		if v["type"] != job:
			v["type"] = job
			v["cargo"] = _get_cargo_for_job(job)
			v["tex"] = CharacterTextureManager.get_character_for_job(job, v.get("seed", 0))

func _get_cargo_for_job(job: String) -> String:
	match job:
		"woodcutter": return "wood"
		"quarryman", "miner": return "stone"
		"hunter": return "game"
		"forager", "farmer": return "food"
		"craftsman": return "kubriki"
		"builder": return "stone"
		_: return ""

func _find_job_target_position(v: Dictionary, player_s: SettlementData) -> Vector2:
	var center = Vector2(player_s.pos.x * TILE_SIZE + 16, player_s.pos.y * TILE_SIZE + 16)
	var job = v.get("type", "villager")
	
	if not planet_data.has("tiles"):
		return center
	var tiles = planet_data["tiles"]
	
	# Строители бегут к реальной стройплощадке на суше!
	if job == "builder":
		for c in GameManager.tile_buildings:
			var b_data = GameManager.tile_buildings[c]
			if b_data.get("status", "") == "constructing":
				return Vector2(c.x * TILE_SIZE + 16 + randf_range(-6, 6), c.y * TILE_SIZE + 16 + randf_range(-6, 6))
				
	# Лесорубы идут к природным деревьям на суше
	if job == "woodcutter":
		var candidates: Array[Vector2i] = []
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var tx = player_s.pos.x + dx
				var ty = player_s.pos.y + dy
				if ty >= 0 and ty < tiles.size() and tx >= 0 and tx < tiles[0].size():
					var t = tiles[ty][tx]
					if not t.get("is_water", false) and t["biome"] in [BiomeDefinitions.BiomeType.DECIDUOUS_FOREST, BiomeDefinitions.BiomeType.PINE_TAIGA, BiomeDefinitions.BiomeType.JUNGLE]:
						candidates.append(Vector2i(tx, ty))
		if not candidates.is_empty():
			var chosen = candidates[randi() % candidates.size()]
			return Vector2(chosen.x * TILE_SIZE + 16 + randf_range(-6, 6), chosen.y * TILE_SIZE + 16 + randf_range(-6, 6))
						
	# Шахтеры идут к горам / камням на суше
	if job == "miner" or job == "quarryman":
		var candidates: Array[Vector2i] = []
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var tx = player_s.pos.x + dx
				var ty = player_s.pos.y + dy
				if ty >= 0 and ty < tiles.size() and tx >= 0 and tx < tiles[0].size():
					var t = tiles[ty][tx]
					if not t.get("is_water", false) and t["biome"] in [BiomeDefinitions.BiomeType.MOUNTAINS, BiomeDefinitions.BiomeType.HILLS]:
						candidates.append(Vector2i(tx, ty))
		if not candidates.is_empty():
			var chosen = candidates[randi() % candidates.size()]
			return Vector2(chosen.x * TILE_SIZE + 16 + randf_range(-6, 6), chosen.y * TILE_SIZE + 16 + randf_range(-6, 6))
						
	# Поиск сухих клеток вокруг стоянки для остальных жителей (собиратели, фермеры, охотники)
	var dry_candidates: Array[Vector2i] = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var tx = player_s.pos.x + dx
			var ty = player_s.pos.y + dy
			if ty >= 0 and ty < tiles.size() and tx >= 0 and tx < tiles[0].size():
				var t = tiles[ty][tx]
				if not t.get("is_water", false):
					dry_candidates.append(Vector2i(tx, ty))
					
	if not dry_candidates.is_empty():
		var chosen = dry_candidates[randi() % dry_candidates.size()]
		return Vector2(chosen.x * TILE_SIZE + 16 + randf_range(-6, 6), chosen.y * TILE_SIZE + 16 + randf_range(-6, 6))
		
	return center

# ==============================================================================
# ГЛАВНЫЙ ЦИКЛ ОБНОВЛЕНИЯ
# ==============================================================================
func _process(delta: float) -> void:
	anim_time += delta
	redraw_timer += delta
	
	# 1. Синхронизация 1:1 жителей
	if fmod(anim_time, 1.0) < delta:
		_sync_population_villagers()
		
	var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	if player_s:
		# Обновление движения жителей (строго по суше!)
		for v in ambient_villagers:
			if v["state"] == 0: # Идёт к работе
				var dir = (v["target_pos"] - v["pos"]).normalized()
				v["pos"] += dir * v["speed"] * delta
				if v["pos"].distance_to(v["target_pos"]) < 4.0:
					v["state"] = 1
					v["work_timer"] = randf_range(2.0, 4.5)
					v["carrying"] = (v["cargo"] != "")
			elif v["state"] == 1: # Работает на месте
				v["work_timer"] -= delta
				if v["work_timer"] <= 0.0:
					v["state"] = 2
			elif v["state"] == 2: # Несет ресурсы домой
				var dir = (v["home_pos"] - v["pos"]).normalized()
				v["pos"] += dir * v["speed"] * delta
				if v["pos"].distance_to(v["home_pos"]) < 4.0:
					v["state"] = 0
					v["carrying"] = false
					v["target_pos"] = _find_job_target_position(v, player_s)
					
			# Защита от захода в воду
			if planet_data.has("tiles"):
				var cur_tx = int(floor(v["pos"].x / TILE_SIZE))
				var cur_ty = int(floor(v["pos"].y / TILE_SIZE))
				var tiles = planet_data["tiles"]
				if cur_ty >= 0 and cur_ty < tiles.size() and cur_tx >= 0 and cur_tx < tiles[0].size():
					if tiles[cur_ty][cur_tx].get("is_water", false):
						v["pos"] = v["home_pos"]
						v["target_pos"] = _find_job_target_position(v, player_s)
					
	# 2. Обновление перемещения армий на карте
	for f_id in GameManager.factions:
		var f: FactionData = GameManager.factions[f_id]
		for a in f.armies:
			if a.speech_timer > 0.0:
				a.speech_timer -= delta
				if a.speech_timer <= 0.0:
					a.speech_bubble = ""
					
			if a.is_moving:
				var dest = Vector2(a.target_pos.x * TILE_SIZE + 16, a.target_pos.y * TILE_SIZE + 16)
				var to_dest = dest - a.world_pos
				var dist = to_dest.length()
				if dist <= a.move_speed * delta or dist < 2.0:
					a.world_pos = dest
					a.pos = a.target_pos
					a.is_moving = false
				else:
					a.world_pos += to_dest.normalized() * a.move_speed * delta
					a.pos = Vector2i(int(floor(a.world_pos.x / TILE_SIZE)), int(floor(a.world_pos.y / TILE_SIZE)))
					
	# 3. Реал-тайм RTS БОЕВАЯ СИСТЕМА
	_process_rts_combat(delta)
	
	# 4. Обновление стрел и эффектов
	_process_combat_effects(delta)
	
	# 5. Обработка наведения мыши
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
					
	# 4. ОБЫЧНЫЙ ВЫБОР ОБЪЕКТА / ТАЙЛА / АРМИИ (ЛКМ)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hovered_tile_coord != Vector2i(-1, -1) and planet_data.has("tiles"):
			# Проверяем, кликнули ли мы по армии
			var clicked_army = _get_army_at_tile(hovered_tile_coord)
			if clicked_army != null:
				selected_army = clicked_army
				EventBus.army_selected.emit(clicked_army)
				queue_redraw()
				return
				
			selected_tile_coord = hovered_tile_coord
			var tile = planet_data["tiles"][selected_tile_coord.y][selected_tile_coord.x]
			var mouse_pos = get_viewport().get_mouse_position()
			EventBus.tile_selected.emit(selected_tile_coord, tile)
			EventBus.tile_right_clicked.emit(selected_tile_coord, tile, mouse_pos)
			
			if tile["settlement_id"] != "":
				var s_data = GameManager.settlements.get(tile["settlement_id"], null)
				if s_data:
					EventBus.settlement_selected.emit(s_data)
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
		
	var dist = float(abs(coord.x - player_s.pos.x) + abs(coord.y - player_s.pos.y))
	if dist > 8.0:
		return {"valid": false, "reason": "❌ Слишком далеко от стоянки (макс 8 клеток)"}
		
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
				
			# Плавные органические переходы биомов (Autotiling overlays)
			var overlays = TerrainResolver.get_transition_overlays(tiles, x, y, width, height)
			for ov in overlays:
				var ov_tex = TileTextureManager.get_overlay_texture(ov["biome_folder"], ov["mask"])
				if ov_tex:
					draw_texture_rect(ov_tex, rect, false, mod_color)
				
			# Динамические реки с бесшовным соединением
			if tile["is_river"] and not tile["is_water"]:
				var r_name = TerrainResolver.resolve_river_texture_name(tiles, x, y, width, height)
				var river_tex = TileTextureManager.get_river_texture(r_name)
				if river_tex:
					draw_texture_rect(river_tex, rect, false)
				else:
					var c = rect.get_center()
					var half = TILE_SIZE * 0.5
					var river_outer = Color(0.22, 0.56, 0.84, 0.90)
					var river_inner = Color(0.60, 0.88, 0.98, 0.75)
					
					var has_left = (x > 0 and (tiles[y][x-1]["is_river"] or tiles[y][x-1]["is_water"]))
					var has_right = (x < tiles[0].size() - 1 and (tiles[y][x+1]["is_river"] or tiles[y][x+1]["is_water"]))
					var has_up = (y > 0 and (tiles[y-1][x]["is_river"] or tiles[y-1][x]["is_water"]))
					var has_down = (y < tiles.size() - 1 and (tiles[y+1][x]["is_river"] or tiles[y+1][x]["is_water"]))
					
					draw_circle(c, 3.2, river_outer)
					if has_left: draw_line(c, c + Vector2(-half, 0), river_outer, 3.6)
					if has_right: draw_line(c, c + Vector2(half, 0), river_outer, 3.6)
					if has_up: draw_line(c, c + Vector2(0, -half), river_outer, 3.6)
					if has_down: draw_line(c, c + Vector2(0, half), river_outer, 3.6)
					
					draw_circle(c, 1.4, river_inner)
					if has_left: draw_line(c, c + Vector2(-half, 0), river_inner, 1.6)
					if has_right: draw_line(c, c + Vector2(half, 0), river_inner, 1.6)
					if has_up: draw_line(c, c + Vector2(0, -half), river_inner, 1.6)
					if has_down: draw_line(c, c + Vector2(0, half), river_inner, 1.6)
				
			# Деревья, скалы, кустарники
			var nature_tex = TileTextureManager.get_nature_overlay(tile["biome"], tile["coord"])
			if nature_tex and tile["settlement_id"] == "" and not GameManager.tile_buildings.has(Vector2i(x, y)):
				var c = rect.get_center()
				var n_size = nature_tex.get_size()
				var aspect = n_size.x / maxf(1.0, n_size.y)
				var is_major = tile["biome"] in [
					BiomeDefinitions.BiomeType.DECIDUOUS_FOREST,
					BiomeDefinitions.BiomeType.PINE_TAIGA,
					BiomeDefinitions.BiomeType.JUNGLE,
					BiomeDefinitions.BiomeType.MOUNTAINS
				]
				var target_h = 24.0 if is_major else 16.0
				var target_w = target_h * aspect
				
				draw_circle(c + Vector2(0, 10.0), target_w * 0.32, Color(0, 0, 0, 0.22))
				var n_rect = Rect2(c.x - target_w * 0.5, c.y + 11.0 - target_h, target_w, target_h)
				draw_texture_rect(nature_tex, n_rect, false)
				
			# Иконки ресурсов
			if tile["resource"] != null:
				var should_draw_res = (current_map_mode == "resources" or hovered_tile_coord == tile["coord"])
				if should_draw_res:
					_draw_resource_icon(rect, tile["resource"]["type"])

	# 2. Построенные и строящиеся здания
	_draw_visible_settlement_buildings()

	# 3. Центры поселений
	for s_id in GameManager.settlements:
		var s = GameManager.settlements[s_id]
		var s_rect = Rect2(s.pos.x * TILE_SIZE, s.pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		_draw_settlement_hub(s_rect, s)
		
	# 4. 1:1 Жители (микро-человечки 10x10)
	_draw_ambient_villagers()

	# 5. Дружины и армии (RTS на карте)
	_draw_armies_and_combat()
	
	# 6. Эффекты стрел, урона и искр
	_draw_combat_effects()

	# 7. ПОДСВЕТКА И ПРИЗРАК ПРИ СТРОИТЕЛЬСТВЕ НА КАРТЕ
	if placement_building_id != "" and hovered_tile_coord != Vector2i(-1, -1):
		_draw_building_placement_preview()
	elif hovered_tile_coord != Vector2i(-1, -1):
		var h_rect = Rect2(hovered_tile_coord.x * TILE_SIZE, hovered_tile_coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		draw_rect(h_rect, Color(1.0, 1.0, 1.0, 0.4), false, 1.5)
		
	# 8. Выбранный тайл
	if selected_tile_coord != Vector2i(-1, -1):
		var s_rect = Rect2(selected_tile_coord.x * TILE_SIZE, selected_tile_coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		draw_rect(s_rect, Color(1.0, 0.85, 0.2, 0.9), false, 2.5)

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

# --- ОТРИСОВКА 1:1 ЖИТЕЛЕЙ ---
func _draw_ambient_villagers() -> void:
	for v in ambient_villagers:
		var p = v["pos"]
		var char_tex = v.get("tex", null)
		if char_tex == null:
			char_tex = CharacterTextureManager.get_character_for_job(v["type"], v.get("seed", 0))
			v["tex"] = char_tex
			
		var char_size = Vector2(10.0, 10.0)
		var bob = sin(anim_time * 9.0 + v.get("seed", 0)) * 0.7 if v["state"] != 1 else 0.0
		var char_rect = Rect2(p.x - char_size.x * 0.5, p.y - char_size.y + 2.0 + bob, char_size.x, char_size.y)
		
		# Тень
		draw_circle(p + Vector2(0, 1.5), 2.2, Color(0, 0, 0, 0.35))
		
		if char_tex:
			draw_texture_rect(char_tex, char_rect, false)
		else:
			draw_circle(p, 1.8, Color(0.9, 0.8, 0.7))
			draw_circle(p + Vector2(0, 2.0), 2.0, Color(0.35, 0.45, 0.6))
			
		# Значок переносимого груза
		if v["carrying"]:
			var cargo_icon = ItemTextureManager.get_icon(v["cargo"])
			var icon_pos = p + Vector2(-3.5, -char_size.y - 5.0 + bob)
			draw_circle(icon_pos + Vector2(3.5, 3.5), 4.2, Color(0.08, 0.1, 0.15, 0.90))
			if cargo_icon:
				draw_texture_rect(cargo_icon, Rect2(icon_pos + Vector2(0.5, 0.5), Vector2(6.0, 6.0)), false)
			else:
				draw_circle(icon_pos + Vector2(3.5, 3.5), 2.0, Color(0.9, 0.7, 0.2))

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
				
			# Отрисовка строя мини-воинов вокруг генерала (3-5 фигурок)
			var formation_offsets = [
				Vector2(-10, 4), Vector2(10, 4), Vector2(-6, 9), Vector2(6, 9),
				Vector2(-12, -4), Vector2(12, -4), Vector2(0, 10)
			]
			
			for k in range(formation_offsets.size()):
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
