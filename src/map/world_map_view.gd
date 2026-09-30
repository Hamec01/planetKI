class_name WorldMapView
extends Node2D

const EmoteTextureManager = preload("res://src/core/emote_texture_manager.gd")
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
var placement_visual_offset: Vector2 = Vector2.ZERO
var is_shift_drag_placing: bool = false
var shift_drag_start_coord: Vector2i = Vector2i(-1, -1)
var shift_drag_current_coord: Vector2i = Vector2i(-1, -1)

# 1.1 ПЕРЕМЕЩЕНИЕ ЗДАНИЙ НА КАРТЕ
var relocation_source_coord: Vector2i = Vector2i(-1, -1)
var relocation_building_id: String = ""

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

var _map_font: Font = null

func _get_map_font() -> Font:
	if _map_font == null:
		var sf = SystemFont.new()
		sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Roboto", "Noto Sans", "DejaVu Sans", "sans-serif"])
		_map_font = sf
	return _map_font

func _ready() -> void:
	TileTextureManager.load_all_textures()
	BuildingTextureManager.load_all_textures()
	
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.map_mode_changed.connect(_on_map_mode_changed)
	EventBus.start_building_placement.connect(_on_start_building_placement)
	EventBus.cancel_building_placement.connect(_on_cancel_building_placement)
	EventBus.start_building_relocation.connect(_on_start_building_relocation)
	EventBus.cancel_building_relocation.connect(_on_cancel_building_relocation)
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
	placement_visual_offset = Vector2.ZERO
	is_shift_drag_placing = false
	shift_drag_start_coord = Vector2i(-1, -1)
	shift_drag_current_coord = Vector2i(-1, -1)
	_on_cancel_building_relocation()
	queue_redraw()

func _on_cancel_building_placement() -> void:
	placement_building_id = ""
	placement_visual_offset = Vector2.ZERO
	is_shift_drag_placing = false
	shift_drag_start_coord = Vector2i(-1, -1)
	shift_drag_current_coord = Vector2i(-1, -1)
	queue_redraw()

func _on_start_building_relocation(source_coord: Vector2i, b_id: String) -> void:
	relocation_source_coord = source_coord
	relocation_building_id = b_id
	placement_building_id = ""
	placement_visual_offset = Vector2.ZERO
	is_shift_drag_placing = false
	queue_redraw()

func _on_cancel_building_relocation() -> void:
	relocation_source_coord = Vector2i(-1, -1)
	relocation_building_id = ""
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
func _get_citizen_near_position(m_pos: Vector2, max_dist: float = 6.5) -> CitizenNPC:
	var player_s = GameManager.settlements.get("player_tribe_settlement", null)
	if not player_s or not player_s.population:
		return null
	var best_c: CitizenNPC = null
	var best_dist = max_dist
	for c in player_s.population.citizens:
		if c.state == CitizenNPC.State.SLEEPING and c.home_id != "":
			continue
		var sprite_center = c.pos + Vector2(0.0, -4.0)
		var d = sprite_center.distance_to(m_pos)
		if d < best_dist:
			best_dist = d
			best_c = c
	return best_c

func _get_animal_near_position(m_pos: Vector2, max_dist: float = 14.0) -> WildAnimal:
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

	# Косметический суб-клеточный сдвиг при одиночном (не shift-drag) размещении здания
	if placement_building_id != "" and not is_shift_drag_placing and hovered_tile_coord != Vector2i(-1, -1):
		var tile_center = Vector2(hovered_tile_coord.x * TILE_SIZE + TILE_SIZE * 0.5, hovered_tile_coord.y * TILE_SIZE + TILE_SIZE * 0.5)
		var raw_offset = mouse_world - tile_center
		var max_off = TILE_SIZE * 0.4
		var new_offset = Vector2(clampf(raw_offset.x, -max_off, max_off), clampf(raw_offset.y, -max_off, max_off))
		if new_offset != placement_visual_offset:
			placement_visual_offset = new_offset
			queue_redraw()

# ==============================================================================
# ОБРАБОТКА ВВОДА (КЛИК ПО КАРТЕ, РАЗМЕЩЕНИЕ, ВЫБОР АРМИИ, МАРШ)
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_game_over:
		return
		
	var hovered_ui = get_viewport().gui_get_hovered_control()
	if hovered_ui != null and hovered_ui.visible and not (hovered_ui.name == "MapView" or hovered_ui.name == "Game"):
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if relocation_source_coord != Vector2i(-1, -1):
				_on_cancel_building_relocation()
				EventBus.cancel_building_relocation.emit()
				queue_redraw()
				return
			if placement_building_id != "":
				is_shift_drag_placing = false
				shift_drag_start_coord = Vector2i(-1, -1)
				shift_drag_current_coord = Vector2i(-1, -1)
				placement_building_id = ""
				EventBus.cancel_building_placement.emit()
				queue_redraw()
				return
			if selected_army != null:
				selected_army = null
				EventBus.army_deselected.emit()
				queue_redraw()
				return
				
	# 0. РЕЖИМ ПЕРЕМЕЩЕНИЯ ЗДАНИЙ
	if relocation_source_coord != Vector2i(-1, -1):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_on_cancel_building_relocation()
				EventBus.cancel_building_relocation.emit()
				EventBus.notification_toast.emit("Перемещение отменено", "Перемещение здания отменено.", "info")
				queue_redraw()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if hovered_tile_coord != Vector2i(-1, -1):
					if hovered_tile_coord == relocation_source_coord:
						EventBus.notification_toast.emit("Перемещение", "Выбрана исходная клетка. Перемещение отменено.", "info")
						_on_cancel_building_relocation()
						EventBus.cancel_building_relocation.emit()
						queue_redraw()
						return
					var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
					if player_s:
						var res = player_s.request_relocation(relocation_source_coord, hovered_tile_coord)
						if res.get("success", false):
							EventBus.notification_toast.emit("Перемещение завершено", "Здание успешно перенесено на клетку (%d:%d)!" % [hovered_tile_coord.x, hovered_tile_coord.y], "good")
							_on_cancel_building_relocation()
							EventBus.cancel_building_relocation.emit()
							queue_redraw()
							return
						else:
							EventBus.notification_toast.emit("Ошибка перемещения", res.get("reason", "Нельзя переместить на эту клетку"), "warning")
							return
		return

	# 1. РЕЖИМ СТРОИТЕЛЬСТВА НА КАРТЕ (С РАСТЯГИВАНИЕМ ПО SHIFT + ЛКМ)
	if placement_building_id != "":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_shift_drag_placing:
				is_shift_drag_placing = false
				shift_drag_start_coord = Vector2i(-1, -1)
				shift_drag_current_coord = Vector2i(-1, -1)
				EventBus.notification_toast.emit("Размещение отменено", "Растягивание постройки отменено.", "info")
				queue_redraw()
				return
			else:
				placement_building_id = ""
				EventBus.cancel_building_placement.emit()
				queue_redraw()
				return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if Input.is_key_pressed(KEY_SHIFT):
					is_shift_drag_placing = true
					shift_drag_start_coord = hovered_tile_coord
					shift_drag_current_coord = hovered_tile_coord
					queue_redraw()
					return
				else:
					if hovered_tile_coord != Vector2i(-1, -1):
						_try_place_building_at_hovered()
					return
			else:
				# Отпускание ЛКМ при растягивании
				if is_shift_drag_placing:
					is_shift_drag_placing = false
					if shift_drag_start_coord != Vector2i(-1, -1) and shift_drag_current_coord != Vector2i(-1, -1):
						var line_tiles = _get_tiles_in_line(shift_drag_start_coord, shift_drag_current_coord)
						var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
						var placed_count = 0
						for c in line_tiles:
							# Растягивание по Shift всегда размещает по центру клетки, без суб-клеточного сдвига
							var check = _can_place_building_at(c, placement_building_id, Vector2.ZERO)
							if check.get("valid", false) and player_s:
								if player_s.start_construction(placement_building_id, c, Vector2.ZERO):
									placed_count += 1
									EventBus.building_placed_on_map.emit(placement_building_id, c)
						if placed_count > 0:
							var b_name = BuildingDB.get_building(placement_building_id).get("name", placement_building_id)
							EventBus.notification_toast.emit("Строительство", "Заложено объектов «%s»: %d шт." % [b_name, placed_count], "good")
					shift_drag_start_coord = Vector2i(-1, -1)
					shift_drag_current_coord = Vector2i(-1, -1)
					if not Input.is_key_pressed(KEY_SHIFT):
						placement_building_id = ""
						EventBus.cancel_building_placement.emit()
					queue_redraw()
					return
		elif event is InputEventMouseMotion:
			if is_shift_drag_placing:
				if hovered_tile_coord != Vector2i(-1, -1) and shift_drag_current_coord != hovered_tile_coord:
					shift_drag_current_coord = hovered_tile_coord
					queue_redraw()
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
					
	# 3. ПКМ ПО КАРТЕ — КОНТЕКСТНОЕ МЕНЮ ДЕЙСТВИЯ (ПОСТРОИТЬ ЗДЕСЬ, ОХОТА, ОСМОТР)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var mouse_world = get_global_mouse_position()
		var mouse_pos = get_viewport().get_mouse_position()
		var tile_under = Vector2i(int(floor(mouse_world.x / TILE_SIZE)), int(floor(mouse_world.y / TILE_SIZE)))
		var has_valid_tile = planet_data.has("tiles") and tile_under.x >= 0 and tile_under.x < planet_data["width"] and tile_under.y >= 0 and tile_under.y < planet_data["height"]
		var tile = planet_data["tiles"][tile_under.y][tile_under.x] if has_valid_tile else {}
		var tile_has_building = has_valid_tile and (GameManager.tile_buildings.has(tile_under) or tile.get("settlement_id", "") != "")

		# Если клик над зданием: сначала проверяем точное попадание в NPC (радиус 5.0)
		if tile_has_building:
			var clicked_citizen = _get_citizen_near_position(mouse_world, 5.0)
			if clicked_citizen != null:
				selected_nature_coord = Vector2i(-1, -1)
				selected_nature_info = {}
				selected_animal_id = ""
				selected_tile_coord = Vector2i(-1, -1)
				EventBus.citizen_selected.emit(clicked_citizen)
				queue_redraw()
				return
			
			# Иначе клик идет строго по зданию / клетке поселения
			selected_tile_coord = tile_under
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = ""
			EventBus.tile_right_clicked.emit(selected_tile_coord, tile, mouse_pos)
			queue_redraw()
			return

		# 3.1 Клик ПКМ по дикому животному (фауна) -> открыть карточку зверя с охотой
		var clicked_animal = _get_animal_near_position(mouse_world, 14.0)
		if clicked_animal != null:
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = clicked_animal.id
			selected_tile_coord = Vector2i(-1, -1)
			EventBus.animal_selected.emit(clicked_animal, mouse_pos)
			queue_redraw()
			return
			
		# 3.2 Клик ПКМ по конкретному гражданину (NPC) вне зданий
		var clicked_citizen = _get_citizen_near_position(mouse_world, 6.5)
		if clicked_citizen != null:
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = ""
			selected_tile_coord = Vector2i(-1, -1)
			EventBus.citizen_selected.emit(clicked_citizen)
			queue_redraw()
			return
			
		# 3.3 Клик ПКМ по клетке карты (природный ресурс, свободная земля)
		if has_valid_tile:
			selected_tile_coord = tile_under
			EventBus.tile_right_clicked.emit(selected_tile_coord, tile, mouse_pos)
			queue_redraw()
			return
					
	# 4. ОБЫЧНЫЙ ВЫБОР ОБЪЕКТА (СПРАЙТА) / АРМИИ / ЖИТЕЛЯ (ЛКМ)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world = get_global_mouse_position()
		var tile_under = Vector2i(int(floor(mouse_world.x / TILE_SIZE)), int(floor(mouse_world.y / TILE_SIZE)))
		var has_valid_tile = planet_data.has("tiles") and tile_under.x >= 0 and tile_under.x < planet_data["width"] and tile_under.y >= 0 and tile_under.y < planet_data["height"]
		var tile = planet_data["tiles"][tile_under.y][tile_under.x] if has_valid_tile else {}
		var tile_has_building = has_valid_tile and (GameManager.tile_buildings.has(tile_under) or tile.get("settlement_id", "") != "")

		# Если клик над зданием или поселением:
		# Проверяем клик по NPC только при ТОЧНОМ наведении на спрайт NPC (радиус 5.0)
		if tile_has_building:
			# Дублирование постройки по Shift + Клик (Пипетка / Быстрое копирование как в RTS)
			if Input.is_key_pressed(KEY_SHIFT):
				var b_id_to_clone = ""
				if GameManager.tile_buildings.has(tile_under):
					b_id_to_clone = GameManager.tile_buildings[tile_under].get("id", "")
				elif tile.get("settlement_id", "") != "":
					b_id_to_clone = "hut"
				if b_id_to_clone != "":
					placement_building_id = b_id_to_clone
					EventBus.start_building_placement.emit(b_id_to_clone)
					var b_name = BuildingDB.get_building(b_id_to_clone).get("name", b_id_to_clone)
					EventBus.notification_toast.emit("Дублирование постройки", "Выбрано для размещения: %s" % b_name, "info")
					queue_redraw()
					return

			# Интерактивное открытие/закрытие ворот по обычному клику
			if GameManager.tile_buildings.has(tile_under):
				var b_dict = GameManager.tile_buildings[tile_under]
				if b_dict.get("id", "") == "wooden_gate" and b_dict.get("status", "") == "active":
					var is_op = not b_dict.get("is_open", false)
					b_dict["is_open"] = is_op
					if GameManager.building_instances and GameManager.building_instances.has(tile_under):
						GameManager.building_instances[tile_under].is_open = is_op
					if GameManager.nav_grid:
						GameManager.nav_grid.set_tile_walkable(tile_under, is_op)
					var msg = "🚪 Ворота открыты (проход свободен)" if is_op else "🔒 Ворота заперты (проход закрыт)"
					EventBus.notification_toast.emit("Деревянные ворота", msg, "good" if is_op else "info")
					queue_redraw()
					return

			var clicked_citizen = _get_citizen_near_position(mouse_world, 5.0)
			if clicked_citizen != null:
				selected_nature_coord = Vector2i(-1, -1)
				selected_nature_info = {}
				selected_animal_id = ""
				selected_tile_coord = Vector2i(-1, -1)
				EventBus.citizen_selected.emit(clicked_citizen)
				queue_redraw()
				return
			
			# Иначе кликаем строго по самому зданию!
			selected_tile_coord = tile_under
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = ""
			EventBus.tile_selected.emit(selected_tile_coord, tile)
			if tile.get("settlement_id", "") != "":
				var s_data = GameManager.settlements.get(tile["settlement_id"], null)
				if s_data:
					EventBus.settlement_selected.emit(s_data)
			queue_redraw()
			return

		# 4.1 Клик по конкретному гражданину (NPC) на открытой местности
		var clicked_citizen = _get_citizen_near_position(mouse_world, 6.5)
		if clicked_citizen != null:
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_animal_id = ""
			selected_tile_coord = Vector2i(-1, -1)
			EventBus.citizen_selected.emit(clicked_citizen)
			queue_redraw()
			return

		# 4.2 Клик по дикому/прирученному животному (фауна)
		var clicked_animal = _get_animal_near_position(mouse_world, 14.0)
		if clicked_animal != null:
			selected_nature_coord = Vector2i(-1, -1)
			selected_nature_info = {}
			selected_tile_coord = Vector2i(-1, -1)
			
			# Если прирученное животное уже выделено — переключаем роль (Защитник <-> Охотник)
			if clicked_animal.is_tamed and selected_animal_id == clicked_animal.id:
				clicked_animal.toggle_tamed_role()
			else:
				selected_animal_id = clicked_animal.id
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

		# 4.5 Клик по пустой земле (трава, вода, песок) — СБРОС ВЫБОРА!
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

func _get_tiles_in_line(start_c: Vector2i, end_c: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start_c == Vector2i(-1, -1) or end_c == Vector2i(-1, -1):
		return result
	var dx = absi(end_c.x - start_c.x)
	var dy = absi(end_c.y - start_c.y)
	var sx = 1 if start_c.x < end_c.x else -1
	var sy = 1 if start_c.y < end_c.y else -1
	var err = dx - dy
	
	var cur = start_c
	while true:
		result.append(cur)
		if cur == end_c:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			cur.x += sx
		if e2 < dx:
			err += dx
			cur.y += sy
	return result

func _is_fence_or_gate(c: Vector2i) -> bool:
	if GameManager and GameManager.tile_buildings.has(c):
		var id = GameManager.tile_buildings[c].get("id", "")
		return id in ["wooden_fence", "wooden_gate", "palisade"] or id.begins_with("fence_")
	return false

func _is_fence_at_or_in(c: Vector2i, extra: Array) -> bool:
	if extra.has(c):
		return true
	return _is_fence_or_gate(c)

func _get_fence_texture_for_tile(coord: Vector2i, extra_fences: Array = []) -> Texture2D:
	var has_w = _is_fence_at_or_in(coord + Vector2i(-1, 0), extra_fences)
	var has_e = _is_fence_at_or_in(coord + Vector2i(1, 0), extra_fences)
	var has_n = _is_fence_at_or_in(coord + Vector2i(0, -1), extra_fences)
	var has_s = _is_fence_at_or_in(coord + Vector2i(0, 1), extra_fences)
	var has_nw = _is_fence_at_or_in(coord + Vector2i(-1, -1), extra_fences)
	var has_ne = _is_fence_at_or_in(coord + Vector2i(1, -1), extra_fences)
	var has_sw = _is_fence_at_or_in(coord + Vector2i(-1, 1), extra_fences)
	var has_se = _is_fence_at_or_in(coord + Vector2i(1, 1), extra_fences)
	
	var fence_tex: Texture2D = null
	if (has_nw or has_se) and not (has_w or has_e or has_n or has_s):
		fence_tex = BuildingTextureManager.get_texture("fence_diag_nw_se")
	elif (has_ne or has_sw) and not (has_w or has_e or has_n or has_s):
		fence_tex = BuildingTextureManager.get_texture("fence_diag_ne_sw")
	elif (has_n or has_s) and not (has_w or has_e):
		fence_tex = BuildingTextureManager.get_texture("fence_vertical")
	elif has_w and (has_n or has_s):
		fence_tex = BuildingTextureManager.get_texture("fence_corner_flipped")
	elif has_e and (has_n or has_s):
		fence_tex = BuildingTextureManager.get_texture("fence_corner")
	elif has_w and has_e:
		fence_tex = BuildingTextureManager.get_texture("fence_horizontal")
	elif has_w or has_e:
		fence_tex = BuildingTextureManager.get_texture("fence_horizontal_short")
	else:
		fence_tex = BuildingTextureManager.get_texture("fence_post")
	return fence_tex

func _get_building_footprint_size(b_id: String) -> Vector2:
	var s = TILE_SIZE * 0.46 if b_id == "grave" else TILE_SIZE * 0.88
	return Vector2(s, s)

func _get_building_visual_rect(coord: Vector2i, b_id: String, offset: Vector2) -> Rect2:
	var center = Vector2(coord.x * TILE_SIZE + TILE_SIZE * 0.5, coord.y * TILE_SIZE + TILE_SIZE * 0.5) + offset
	var size = _get_building_footprint_size(b_id)
	return Rect2(center - size * 0.5, size)

func _get_visual_offset_from_tile_data(b_data: Dictionary) -> Vector2:
	var arr = b_data.get("visual_offset", [0.0, 0.0])
	return Vector2(arr[0], arr[1])

func _can_place_building_at(coord: Vector2i, b_id: String, offset: Vector2 = Vector2.ZERO) -> Dictionary:
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

	# Реальная проверка пересечения спрайтов с соседними постройками (а не просто "занята ли клетка")
	var candidate_rect = _get_building_visual_rect(coord, b_id, offset)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n_coord = coord + Vector2i(dx, dy)
			if not GameManager.tile_buildings.has(n_coord):
				continue
			var n_data = GameManager.tile_buildings[n_coord]
			var n_offset = _get_visual_offset_from_tile_data(n_data)
			var n_rect = _get_building_visual_rect(n_coord, n_data.get("id", ""), n_offset)
			if candidate_rect.intersects(n_rect):
				return {"valid": false, "reason": "❌ Здание перекрывает соседнюю постройку"}

	return {"valid": true, "reason": "✅ ЛКМ: Заложить фундамент", "cost": b_info["cost"], "name": b_info["name"]}

func _try_place_building_at_hovered() -> void:
	var check = _can_place_building_at(hovered_tile_coord, placement_building_id, placement_visual_offset)
	if check["valid"]:
		var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
		if player_s and player_s.start_construction(placement_building_id, hovered_tile_coord, placement_visual_offset):
			EventBus.building_placed_on_map.emit(placement_building_id, hovered_tile_coord)
			EventBus.notification_toast.emit("Строительство", "Заложено здание: %s" % check["name"], "good")
			if not Input.is_key_pressed(KEY_SHIFT):
				placement_building_id = ""
			placement_visual_offset = Vector2.ZERO
			queue_redraw()
	else:
		EventBus.notification_toast.emit("Нельзя построить", check["reason"], "bad")

# ==============================================================================
# ОТРИСОВКА КАРТЫ, ПОСТРОЕК, ЖИТЕЛЕЙ, АРМИЙ И ЭФФЕКТОВ
# ==============================================================================
func get_visible_tile_bounds() -> Rect2i:
	if not planet_data.has("width") or not planet_data.has("height"):
		return Rect2i(0, 0, 0, 0)
	var width = planet_data["width"]
	var height = planet_data["height"]
	var cam = get_viewport().get_camera_2d()
	var cam_pos = cam.global_position if cam else Vector2(width * TILE_SIZE * 0.5, height * TILE_SIZE * 0.5)
	var cam_zoom = cam.zoom.x if (cam and cam.zoom.x > 0.01) else 1.0
	var vp_size = get_viewport_rect().size
	var margin = 2
	var min_tx = clampi(int(floor((cam_pos.x - (vp_size.x * 0.5) / cam_zoom) / TILE_SIZE)) - margin, 0, width - 1)
	var max_tx = clampi(int(ceil((cam_pos.x + (vp_size.x * 0.5) / cam_zoom) / TILE_SIZE)) + margin, 0, width - 1)
	var min_ty = clampi(int(floor((cam_pos.y - (vp_size.y * 0.5) / cam_zoom) / TILE_SIZE)) - margin, 0, height - 1)
	var max_ty = clampi(int(ceil((cam_pos.y + (vp_size.y * 0.5) / cam_zoom) / TILE_SIZE)) + margin, 0, height - 1)
	return Rect2i(min_tx, min_ty, max_tx - min_tx + 1, max_ty - min_ty + 1)

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

	var tile_bounds = get_visible_tile_bounds()
	var min_tx = tile_bounds.position.x
	var min_ty = tile_bounds.position.y
	var max_tx = tile_bounds.position.x + tile_bounds.size.x - 1
	var max_ty = tile_bounds.position.y + tile_bounds.size.y - 1

	var margin_px = TILE_SIZE * 3
	var screen_rect = Rect2(
		cam_pos.x - (vp_size.x * 0.5) / cam_zoom - margin_px,
		cam_pos.y - (vp_size.y * 0.5) / cam_zoom - margin_px,
		(vp_size.x / cam_zoom) + margin_px * 2,
		(vp_size.y / cam_zoom) + margin_px * 2
	)
	
	var ambient_color = _get_ambient_light_color()
	var night_factor = _get_night_darkness_factor()

	# =========================================================================
	# PASS 1: БАЗОВЫЕ ТАЙЛЫ ПОВЕРХНОСТИ, ПЕРЕХОДЫ БИОМОВ, ИКОНКИ И ТРОПИНКИ
	# =========================================================================
	for y in range(min_ty, max_ty + 1):
		for x in range(min_tx, max_tx + 1):
			var tile = tiles[y][x]
			var rect = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			
			var tex = TileTextureManager.get_tile_texture(tile["biome"], tile["coord"], tile["is_river"])
			var mod_color = ambient_color
			
			if current_map_mode == "fertility":
				var moisture = tile.get("moisture", 0.5)
				var elevation = tile.get("elevation", 0.5)
				var fertility_score = moisture * (1.0 - abs(elevation - 0.4))
				mod_color = Color(1.0 - fertility_score * 0.8, 1.0 + fertility_score * 0.5, 0.6) * ambient_color
			elif current_map_mode == "political":
				if tile["settlement_id"] != "":
					var is_pl = (tile["settlement_id"] == "player_tribe_settlement")
					mod_color = (Color(0.7, 0.9, 1.2) if is_pl else Color(1.2, 0.8, 0.8)) * ambient_color
			elif current_map_mode == "religion":
				mod_color = Color(1.1, 1.0, 1.25) * ambient_color
				
			# Водные тайлы теперь рисуются отдельным WaterRenderLayer (анимированный шейдер), см. water.gdshader
			if tex and not tile.get("is_water", false):
				draw_texture_rect(tex, rect, false, mod_color)
			elif not tex and not tile.get("is_water", false):
				var biome_info = BiomeDefinitions.get_biome_info(tile["biome"])
				var b_col = biome_info["color"]
				draw_rect(rect, Color(b_col.r * ambient_color.r, b_col.g * ambient_color.g, b_col.b * ambient_color.b, b_col.a))
				
			# Плавные переходы биомов суши к воде и между слоями
			var overlays = TerrainResolver.get_transition_overlays(tiles, x, y, width, height)
			for ov in overlays:
				var ov_tex = TileTextureManager.get_overlay_texture(ov["biome_folder"], ov["mask"])
				if ov_tex:
					draw_texture_rect(ov_tex, rect, false, mod_color)

			# Иконки ресурсов отображаются ТОЛЬКО в специальном режиме карты "Ресурсы"
			if tile["resource"] != null and current_map_mode == "resources":
				_draw_resource_icon(rect, tile["resource"]["type"])

	# Протоптанные тропинки рисуются поверх земли, но под стоящими объектами
	_draw_beaten_footpaths()

	# =========================================================================
	# PASS 2: СБОР И ГЛУБИННАЯ СОРТИРОВКА (Y-SORTING) ВСЕХ ОБЪЕКТОВ МИРА
	# Деревья, дома, NPC, животные, декорации рисуются от заднего плана к переднему
	# =========================================================================
	var y_entities: Array[Dictionary] = []

	# 1. Природные объекты (деревья, скалы, кустарники, трава, цветы, грибы)
	for y in range(min_ty, max_ty + 1):
		for x in range(min_tx, max_tx + 1):
			var tile = tiles[y][x]
			if tile["settlement_id"] != "" or GameManager.tile_buildings.has(Vector2i(x, y)):
				continue
			var custom_nat = tile.get("nature_object", "")
			var n_data = TileTextureManager.get_nature_data(tile["biome"], tile["coord"], tile.get("resource", null), custom_nat)
			if n_data.is_empty() or n_data.get("tex", null) == null:
				continue
			var rect = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var c = rect.get_center()
			var foot_y = c.y + 11.0
			y_entities.append({
				"y": foot_y,
				"x": c.x,
				"type": "nature",
				"c": c,
				"n_data": n_data
			})

	# 2. Построенные и строящиеся здания
	for coord in GameManager.tile_buildings:
		if coord.x >= min_tx - 2 and coord.x <= max_tx + 2 and coord.y >= min_ty - 2 and coord.y <= max_ty + 2:
			var b_data = GameManager.tile_buildings[coord]
			var b_id = b_data.get("id", "")
			var b_size = _get_building_footprint_size(b_id).y
			var b_offset_y = 4.0 if b_id == "grave" else 0.0
			var c = Vector2(coord.x * TILE_SIZE + 16, coord.y * TILE_SIZE + 16) + _get_visual_offset_from_tile_data(b_data)
			var foot_y = c.y + b_size * 0.5 + b_offset_y
			y_entities.append({
				"y": foot_y,
				"x": c.x,
				"type": "building",
				"coord": coord,
				"b_data": b_data
			})

	# 3. Центры поселений (хаб / костер / дом старейшин)
	for s_id in GameManager.settlements:
		var s: SettlementData = GameManager.settlements[s_id]
		if s.pos.x >= min_tx - 2 and s.pos.x <= max_tx + 2 and s.pos.y >= min_ty - 2 and s.pos.y <= max_ty + 2:
			var c = Vector2(s.pos.x * TILE_SIZE + 16, s.pos.y * TILE_SIZE + 16)
			var foot_y = c.y + 12.0
			y_entities.append({
				"y": foot_y,
				"x": c.x,
				"type": "settlement_hub",
				"s": s,
				"rect": Rect2(s.pos.x * TILE_SIZE, s.pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			})

	# 4. Персональные декорации NPC
	if GameManager and not GameManager.tile_decorations.is_empty():
		for coord in GameManager.tile_decorations:
			var world_pos = Vector2(coord.x * TILE_SIZE + 16.0, coord.y * TILE_SIZE + 16.0)
			if screen_rect.has_point(world_pos):
				y_entities.append({
					"y": world_pos.y + 4.0,
					"x": world_pos.x,
					"type": "npc_decoration",
					"center": world_pos,
					"deco": GameManager.tile_decorations[coord]
				})

	# 5. Жители (NPC)
	var visible_citizens: Array[CitizenNPC] = []
	for s_id in GameManager.settlements:
		var s: SettlementData = GameManager.settlements[s_id]
		if not s.population:
			continue
		for c in s.population.citizens:
			if not c.is_alive and c.is_buried:
				continue
			if c.state == CitizenNPC.State.SLEEPING and c.home_id != "":
				continue
			if screen_rect.has_point(c.pos):
				y_entities.append({
					"y": c.pos.y,
					"x": c.pos.x,
					"type": "citizen",
					"citizen": c
				})
				visible_citizens.append(c)

	# 6. Дикие животные и туши
	var visible_animals: Array[WildAnimal] = []
	if GameManager.wildlife_manager:
		for carc in GameManager.wildlife_manager.carcasses.values():
			var p = carc["pos"]
			if screen_rect.has_point(p):
				y_entities.append({
					"y": p.y,
					"x": p.x,
					"type": "carcass",
					"carcass": carc
				})
		for animal in GameManager.wildlife_manager.animals.values():
			if animal.is_alive() and screen_rect.has_point(animal.pos):
				y_entities.append({
					"y": animal.pos.y,
					"x": animal.pos.x,
					"type": "animal",
					"animal": animal
				})
				visible_animals.append(animal)

	# 7. RTS Армии
	var visible_armies: Array[Dictionary] = []
	for f_id in GameManager.factions:
		var f: FactionData = GameManager.factions[f_id]
		for a in f.armies:
			if a.get_total_soldiers() > 0 and screen_rect.has_point(a.world_pos):
				y_entities.append({
					"y": a.world_pos.y,
					"x": a.world_pos.x,
					"type": "army",
					"army": a,
					"faction": f
				})
				visible_armies.append({"army": a, "faction": f})

	# Глубинная сортировка по координате Y основания (меньший Y рисуется раньше / дальше).
	# Детерминированный tie-break по X обязателен: sort_custom в Godot нестабилен, и при
	# равном Y (например, несколько деревьев в одном ряду тайлов) порядок мог "плавать"
	# от кадра к кадру из-за движущихся сущностей (NPC/животных) в том же массиве, что
	# выглядело как случайная смена слоёв между соседними объектами.
	y_entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["y"] != b["y"]:
			return a["y"] < b["y"]
		return a.get("x", 0.0) < b.get("x", 0.0)
	)

	# Отрисовка всех объектов мира в строгом порядке глубины
	for entity in y_entities:
		match entity["type"]:
			"nature":
				_draw_single_nature_object(entity["n_data"], entity["c"], entity["y"])
			"building":
				_draw_single_building(entity["coord"], entity["b_data"])
			"settlement_hub":
				_draw_single_settlement_hub(entity["rect"], entity["s"])
			"npc_decoration":
				_draw_single_npc_decoration(entity["center"], entity["deco"])
			"citizen":
				_draw_single_citizen_body(entity["citizen"])
			"carcass":
				_draw_single_carcass(entity["carcass"])
			"animal":
				_draw_single_animal_body(entity["animal"])
			"army":
				_draw_single_army_formation(entity["army"], entity["faction"])

	# =========================================================================
	# PASS 2.5: НОЧНАЯ АТМОСФЕРА, ПЛАМЯ КОСТРОВ, СВЕТ В ОКНАХ И ФАКЕЛЫ
	# =========================================================================
	_draw_night_atmosphere(screen_rect, night_factor)

	# =========================================================================
	# PASS 3: ПАРЯЩИЙ UI, ЭМОЦИИ, ДИАЛОГИ И ЭФФЕКТЫ (ВСЕГДА ПОВЕРХ ГЕОМЕТРИИ)
	# =========================================================================
	var font = ThemeDB.fallback_font

	# 1. Оверлеи граждан (эмодзи, диалоговые облачка, полоски здоровья, грузы, стрелы)
	for c in visible_citizens:
		_draw_citizen_overlays(c, font)

	# 2. Оверлеи животных (полоски здоровья, клички прирученных)
	for animal in visible_animals:
		_draw_animal_overlays(animal, font)

	# 3. Оверлеи армий (маршруты, знамена, мораль, боевые фразы генерала)
	for entry in visible_armies:
		_draw_army_overlays(entry["army"], entry["faction"], font)

	# 4. Информационные плашки над поселениями
	for s_id in GameManager.settlements:
		var s: SettlementData = GameManager.settlements[s_id]
		_draw_settlement_hub_overlay(s, font)

	# 5. Эффекты стрел, урона и искр
	_draw_combat_effects()

	# 6. Подсветка и призрак при строительстве
	if placement_building_id != "":
		_draw_building_placement_preview()
		
	# 6.1 Подсветка и призрак при перемещении здания
	if relocation_source_coord != Vector2i(-1, -1):
		_draw_building_relocation_preview()
		
	# 7. Подсветка выбранного природного объекта
	if selected_nature_coord != Vector2i(-1, -1) and not selected_nature_info.is_empty():
		_draw_selected_nature_highlight()
		
	# 8. Подсветка выбранного дикого животного
	if selected_animal_id != "":
		_draw_selected_animal_highlight()

# --- ОТРИСОВКА ОДНОГО ПРИРОДНОГО ОБЪЕКТА (ДЕРЕВО / КАМЕНЬ / КУСТ) ---
func _draw_single_nature_object(n_data: Dictionary, c: Vector2, foot_y: float) -> void:
	var n_tex: Texture2D = n_data["tex"]
	var orig_size = n_tex.get_size()
	var aspect = orig_size.x / maxf(1.0, orig_size.y)
	var variant_seed: int = n_data.get("variant_seed", 0)

	# Детерминированная по координате вариативность: отражение, масштаб, лёгкое тонирование
	var scale_jitter = 0.90 + float(variant_seed % 26) / 100.0
	var target_h: float = n_data.get("scale_h", 20.0) * scale_jitter
	var target_w: float = target_h * aspect

	var n_rect = Rect2(c.x - target_w * 0.5, foot_y - target_h, target_w, target_h)
	var flip_h = (variant_seed % 2) == 0
	if flip_h:
		n_rect = Rect2(n_rect.position + Vector2(n_rect.size.x, 0), Vector2(-n_rect.size.x, n_rect.size.y))

	# Мягкая эллиптическая тень под основанием
	var shadow_radius = target_w * (0.30 if n_data.get("category", "") == "tree" else 0.40)
	draw_circle(Vector2(c.x, foot_y - 1.0), absf(shadow_radius), Color(0, 0, 0, 0.22))

	var brightness = 0.92 + float(variant_seed % 17) / 100.0
	draw_texture_rect(n_tex, n_rect, false, Color(brightness, brightness, brightness))

# --- ОТРИСОВКА ПРОТОПТАННЫХ ТРОПИНОК МЕЖДУ ДОМАМИ И КОСТРОМ ---
func _draw_beaten_footpaths() -> void:
	if not GameManager:
		return
		
	# 1. Динамические тропинки от поселений (от домов к костру и между соседними хижинами)
	for s_id in GameManager.settlements:
		var s: SettlementData = GameManager.settlements[s_id]
		if not s:
			continue
		var paths = s.get_settlement_footpaths()
		for p_data in paths:
			var pts: Array = p_data.get("points", [])
			if pts.size() < 2:
				continue
			var packed_pts = PackedVector2Array()
			for pt in pts:
				if pt is Vector2:
					packed_pts.append(pt)
				var is_hub = (p_data.get("type", "") == "hub")
				# Мягкая естественная тропинка (утоптанная земля)
				draw_polyline(packed_pts, Color(0.48, 0.40, 0.28, 0.22 if is_hub else 0.16), 2.0 if is_hub else 1.5, true)

	# 2. Протоптанные клетки от частого передвижения жителей (GameManager.trample_map)
	if GameManager.trample_map:
		for coord in GameManager.trample_map:
			var wear = float(GameManager.trample_map[coord])
			if wear >= 0.15:
				var center = Vector2(coord.x * TILE_SIZE + 16, coord.y * TILE_SIZE + 16)
				var radius = 6.0 + wear * 6.0
				var alpha = clampf(wear * 0.45, 0.12, 0.40)
				draw_circle(center, radius, Color(0.52, 0.40, 0.26, alpha))

# --- ОТРИСОВКА РЕЖИМА СТРОИТЕЛЬСТВА НА КАРТЕ ---
func _draw_building_placement_preview() -> void:
	var font = ThemeDB.fallback_font
	var player_s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	var b_info = BuildingDB.get_building(placement_building_id)
	var single_cost = b_info.get("cost", {})
	var b_name = b_info.get("name", placement_building_id)
	
	if is_shift_drag_placing and shift_drag_start_coord != Vector2i(-1, -1) and shift_drag_current_coord != Vector2i(-1, -1):
		var line_tiles = _get_tiles_in_line(shift_drag_start_coord, shift_drag_current_coord)
		var total_cost: Dictionary = {}
		var valid_count = 0
		
		for coord in line_tiles:
			var check = _can_place_building_at(coord, placement_building_id, Vector2.ZERO)
			var is_valid = check.get("valid", false)
			if is_valid:
				valid_count += 1
				for res in single_cost:
					total_cost[res] = total_cost.get(res, 0.0) + float(single_cost[res])
			
			var rect = Rect2(coord.x * TILE_SIZE, coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var c = rect.get_center()
			var grid_color = Color(0.2, 0.9, 0.3, 0.8) if is_valid else Color(0.95, 0.25, 0.2, 0.8)
			var fill_color = Color(0.2, 0.9, 0.3, 0.22) if is_valid else Color(0.95, 0.25, 0.2, 0.25)
			
			draw_rect(rect, fill_color)
			draw_rect(rect, grid_color, false, 2.0)
			
			var b_tex: Texture2D = null
			if placement_building_id == "wooden_fence":
				b_tex = _get_fence_texture_for_tile(coord, line_tiles)
			else:
				b_tex = BuildingTextureManager.get_texture(placement_building_id)
				
			if b_tex:
				var tw = float(b_tex.get_width())
				var th = float(b_tex.get_height())
				var b_w = TILE_SIZE * 0.92
				var b_h = TILE_SIZE * 0.92
				if tw > th:
					b_w = TILE_SIZE * 0.95
					b_h = b_w * (th / tw)
				elif th > tw:
					b_h = TILE_SIZE * 0.95
					b_w = b_h * (tw / th)
				var b_rect = Rect2(c.x - b_w * 0.5, c.y - b_h * 0.5, b_w, b_h)
				var tint = Color(0.6, 1.0, 0.6, 0.85) if is_valid else Color(1.0, 0.45, 0.45, 0.7)
				draw_texture_rect(b_tex, b_rect, false, tint)
				
		# Парящий бейдж над текущим положением мыши
		var mouse_coord = hovered_tile_coord if hovered_tile_coord != Vector2i(-1, -1) else shift_drag_current_coord
		var center_mouse = Vector2(mouse_coord.x * TILE_SIZE + 16.0, mouse_coord.y * TILE_SIZE + 16.0)
		
		# Формируем строку цены
		var cost_parts = []
		var can_afford_all = true
		for res in total_cost:
			var req = int(total_cost[res])
			var cur = int(player_s.economy.get_resource(res)) if player_s else 0
			var icon_res = "🪵" if res == "wood" else ("🪨" if res == "stone" else ("⛏" if res == "metal" else res))
			cost_parts.append("%s %d/%d" % [icon_res, req, cur])
			if cur < req:
				can_afford_all = false
		var cost_str = " | ".join(cost_parts) if cost_parts.size() > 0 else "бесплатно"
		
		var line1 = "🔨 Растягивание: %s (%d шт.) — %s" % [b_name, valid_count, cost_str]
		var line2 = "💡 Отпустите ЛКМ: Построить • ПКМ: Отмена"
		
		var w1 = line1.length() * 6.5 + 20.0
		var w2 = line2.length() * 6.0 + 20.0
		var box_w = maxf(w1, w2)
		var box_h = 34.0
		var box_pos = center_mouse + Vector2(-box_w * 0.5, -TILE_SIZE * 1.1 - box_h)
		var box_rect = Rect2(box_pos.x, box_pos.y, box_w, box_h)
		
		draw_rect(box_rect, Color(0.08, 0.12, 0.18, 0.96))
		draw_rect(box_rect, Color(0.2, 0.9, 0.4, 0.9) if can_afford_all else Color(1.0, 0.35, 0.35, 0.9), false, 1.5)
		draw_string(font, box_pos + Vector2(10, 14), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.4) if can_afford_all else Color(1.0, 0.5, 0.4))
		draw_string(font, box_pos + Vector2(10, 28), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.92, 1.0))
		
	elif hovered_tile_coord != Vector2i(-1, -1):
		var coord = hovered_tile_coord
		var check = _can_place_building_at(coord, placement_building_id, placement_visual_offset)
		var rect = Rect2(coord.x * TILE_SIZE, coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		var c = rect.get_center() + placement_visual_offset

		var is_valid = check.get("valid", false)
		var grid_color = Color(0.2, 0.9, 0.3, 0.75) if is_valid else Color(0.95, 0.25, 0.2, 0.75)
		var fill_color = Color(0.2, 0.9, 0.3, 0.20) if is_valid else Color(0.95, 0.25, 0.2, 0.25)
		
		draw_rect(rect, fill_color)
		draw_rect(rect, grid_color, false, 2.0)
		
		var b_tex: Texture2D = null
		if placement_building_id == "wooden_fence":
			b_tex = _get_fence_texture_for_tile(coord, [])
		elif placement_building_id in ["cemetery", "grave"]:
			var soil_rect = Rect2(c.x - TILE_SIZE * 0.46, c.y - TILE_SIZE * 0.46, TILE_SIZE * 0.92, TILE_SIZE * 0.92)
			draw_rect(soil_rect, Color(0.24, 0.17, 0.11, 0.85) if is_valid else Color(0.35, 0.15, 0.12, 0.7))
			draw_rect(soil_rect, Color(0.15, 0.10, 0.06, 0.9), false, 1.0)
			# Угловые священные камни границы
			var p_tl = soil_rect.position
			var p_tr = Vector2(soil_rect.end.x, soil_rect.position.y)
			var p_bl = Vector2(soil_rect.position.x, soil_rect.end.y)
			var p_br = soil_rect.end
			draw_circle(p_tl + Vector2(2, 2), 1.6, Color(0.6, 0.58, 0.52, 0.9))
			draw_circle(p_tr + Vector2(-2, 2), 1.6, Color(0.6, 0.58, 0.52, 0.9))
			draw_circle(p_bl + Vector2(2, -2), 1.6, Color(0.6, 0.58, 0.52, 0.9))
			draw_circle(p_br + Vector2(-2, -2), 1.6, Color(0.6, 0.58, 0.52, 0.9))
		else:
			b_tex = BuildingTextureManager.get_texture(placement_building_id)
			
		if b_tex:
			var tw = float(b_tex.get_width())
			var th = float(b_tex.get_height())
			var b_w = TILE_SIZE * 0.9
			var b_h = TILE_SIZE * 0.9
			if tw > th:
				b_w = TILE_SIZE * 0.95
				b_h = b_w * (th / tw)
			elif th > tw:
				b_h = TILE_SIZE * 0.95
				b_w = b_h * (tw / th)
			var b_rect = Rect2(c.x - b_w * 0.5, c.y - b_h * 0.5, b_w, b_h)
			var tint = Color(0.6, 1.0, 0.6, 0.8) if is_valid else Color(1.0, 0.5, 0.5, 0.65)
			draw_texture_rect(b_tex, b_rect, false, tint)
			
		var tip_pos = c + Vector2(0, -TILE_SIZE * 0.8)
		var tip_text = "%s (Shift+ЛКМ: Растянуть)" % check.get("reason", "")
		var text_w = tip_text.length() * 6.2 + 16
		var tip_rect = Rect2(tip_pos.x - text_w * 0.5, tip_pos.y - 8, text_w, 18)
		draw_rect(tip_rect, Color(0.08, 0.1, 0.15, 0.95))
		draw_rect(tip_rect, grid_color, false, 1.2)
		draw_string(font, tip_pos + Vector2(-text_w * 0.5 + 8, 5), tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

# --- ОТРИСОВКА РЕЖИМА ПЕРЕМЕЩЕНИЯ ЗДАНИЙ ---
func _draw_building_relocation_preview() -> void:
	var font = ThemeDB.fallback_font
	var src_coord = relocation_source_coord
	var src_c = Vector2(src_coord.x * TILE_SIZE + 16.0, src_coord.y * TILE_SIZE + 16.0)
	var pulse = 1.0 + sin(anim_time * 4.0) * 0.08
	
	# Подсветка исходной клетки здания
	var src_rect = Rect2(src_coord.x * TILE_SIZE, src_coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	draw_rect(src_rect, Color(0.9, 0.7, 0.1, 0.35))
	draw_rect(src_rect, Color(1.0, 0.85, 0.2, 0.95), false, 2.2)
	draw_arc(src_c, TILE_SIZE * 0.6 * pulse, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.9), 1.5)
	
	var src_lbl = "📦 Исходное здание"
	var src_lbl_w = src_lbl.length() * 6.5 + 12.0
	draw_rect(Rect2(src_c.x - src_lbl_w * 0.5, src_c.y - TILE_SIZE * 0.8 - 6, src_lbl_w, 16), Color(0.08, 0.1, 0.15, 0.9))
	draw_rect(Rect2(src_c.x - src_lbl_w * 0.5, src_c.y - TILE_SIZE * 0.8 - 6, src_lbl_w, 16), Color(1.0, 0.85, 0.2, 0.9), false, 1.0)
	draw_string(font, Vector2(src_c.x - src_lbl_w * 0.5 + 6, src_c.y - TILE_SIZE * 0.8 + 6), src_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.9, 0.4))
	
	# Если наведен курсор на целевую клетку
	if hovered_tile_coord != Vector2i(-1, -1):
		var target_coord = hovered_tile_coord
		var target_c = Vector2(target_coord.x * TILE_SIZE + 16.0, target_coord.y * TILE_SIZE + 16.0)
		var target_rect = Rect2(target_coord.x * TILE_SIZE, target_coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		
		# Проверка доступности целевой клетки
		var is_valid = true
		var fail_reason = ""
		if not planet_data.has("tiles"):
			is_valid = false
			fail_reason = "Карта не готова"
		else:
			var tiles = planet_data["tiles"]
			if target_coord.y < 0 or target_coord.y >= tiles.size() or target_coord.x < 0 or target_coord.x >= tiles[0].size():
				is_valid = false
				fail_reason = "За границами карты"
			elif tiles[target_coord.y][target_coord.x].get("is_water", false):
				is_valid = false
				fail_reason = "Нельзя перенести на воду"
			elif GameManager.tile_buildings.has(target_coord):
				is_valid = false
				fail_reason = "Клетка уже занята"
				
		var target_col = Color(0.2, 0.9, 0.4, 0.85) if is_valid else Color(0.95, 0.25, 0.2, 0.85)
		var target_fill = Color(0.2, 0.9, 0.4, 0.22) if is_valid else Color(0.95, 0.25, 0.2, 0.25)
		
		# Линия перемещения от исходной к целевой
		draw_line(src_c, target_c, Color(0.3, 0.8, 1.0, 0.75), 2.0)
		draw_circle(target_c, 3.5, Color(0.3, 0.8, 1.0, 0.9))
		
		draw_rect(target_rect, target_fill)
		draw_rect(target_rect, target_col, false, 2.0)
		
		# Призрак здания
		var b_tex = BuildingTextureManager.get_texture(relocation_building_id)
		if b_tex:
			var b_size = TILE_SIZE * 0.9
			var b_rect = Rect2(target_c.x - b_size * 0.5, target_c.y - b_size * 0.5, b_size, b_size)
			var tint = Color(0.6, 1.0, 0.6, 0.85) if is_valid else Color(1.0, 0.45, 0.45, 0.65)
			draw_texture_rect(b_tex, b_rect, false, tint)
			
		# Всплывающая подсказка
		var b_name = BuildingDB.get_building(relocation_building_id).get("name", relocation_building_id)
		var tip_text = "📦 ЛКМ: Перенести «%s» сюда" % b_name if is_valid else "❌ %s" % fail_reason
		var tip_w = tip_text.length() * 6.5 + 16.0
		var tip_rect = Rect2(target_c.x - tip_w * 0.5, target_c.y - TILE_SIZE * 0.85 - 8.0, tip_w, 18.0)
		draw_rect(tip_rect, Color(0.08, 0.12, 0.18, 0.95))
		draw_rect(tip_rect, target_col, false, 1.2)
		draw_string(font, Vector2(target_c.x - tip_w * 0.5 + 8, target_c.y - TILE_SIZE * 0.85 + 5), tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

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
# --- ОТРИСОВКА ОДНОГО ЗДАНИЯ ---
func _draw_single_building(coord: Vector2i, b_data: Dictionary) -> void:
	var b_id = b_data.get("id", "")
	var status = b_data.get("status", "active")
	var c = Vector2(coord.x * TILE_SIZE + 16, coord.y * TILE_SIZE + 16) + _get_visual_offset_from_tile_data(b_data)
	var b_size = _get_building_footprint_size(b_id).x
	var b_offset_y = 4.0 if b_id == "grave" else 0.0
	var b_rect = Rect2(c.x - b_size * 0.5, c.y - b_size * 0.5 + b_offset_y, b_size, b_size)
	
	var b_inst: BuildingInstance = null
	if GameManager and GameManager.building_instances:
		if GameManager.building_instances.has(coord):
			b_inst = GameManager.building_instances[coord]
		else:
			for bi in GameManager.building_instances.values():
				if bi is BuildingInstance and bi.pos == coord:
					b_inst = bi
					break
	
	var b_tex: Texture2D = null
	if b_id == "hut" or b_id.begins_with("hut"):
		if b_inst and b_inst.condition <= 0.0:
			b_tex = BuildingTextureManager.get_texture("dest_house")
		elif b_inst and b_inst.is_upgrade_unlocked("hut_annex"):
			b_tex = BuildingTextureManager.get_texture("hut_annex")
		else:
			b_tex = BuildingTextureManager.get_texture("hut_main")
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("hut")
	elif b_id == "great_lodge":
		if b_inst and b_inst.condition <= 0.0:
			b_tex = BuildingTextureManager.get_texture("destr_great_lodge")
		elif b_inst:
			var var_key = "great_lodge_%d" % b_inst.visual_variant
			b_tex = BuildingTextureManager.get_texture(var_key)
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("great_lodge")
	elif b_id == "hunting_camp":
		if b_inst and b_inst.condition <= 0.0:
			b_tex = BuildingTextureManager.get_texture("destr_hunting_camp")
		elif b_inst and b_inst.visual_variant == 1:
			b_tex = BuildingTextureManager.get_texture("hunter_shelter")
		else:
			b_tex = BuildingTextureManager.get_texture("hunter_lodge")
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("hunting_camp")
	elif b_id == "foraging_post":
		if b_inst and b_inst.condition <= 0.0:
			b_tex = BuildingTextureManager.get_texture("destr_foraging_post")
		else:
			b_tex = BuildingTextureManager.get_texture("foraging_post_main")
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("foraging_post")
	elif b_id == "seed_store":
		if b_inst and b_inst.condition <= 0.0:
			b_tex = BuildingTextureManager.get_texture("destr_seed_store")
		else:
			b_tex = BuildingTextureManager.get_texture("seed_store")
	elif b_id == "primitive_garden":
		var stg = b_inst.growth_stage if b_inst else 1
		b_tex = BuildingTextureManager.get_texture("primitive_garden_stage_%d" % clampi(stg, 1, 6))
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("primitive_garden")
	elif b_id in ["primitive_field", "wheat_field"]:
		var stg = b_inst.growth_stage if b_inst else 1
		b_tex = BuildingTextureManager.get_texture("wheat_field_stage_%d" % clampi(stg, 1, 6))
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("primitive_field")
	elif b_id == "quern_house":
		b_tex = BuildingTextureManager.get_texture("foraging_quern")
		if b_tex == null:
			b_tex = BuildingTextureManager.get_texture("quern_house")
	else:
		b_tex = BuildingTextureManager.get_texture(b_id)

	
	if status == "constructing":
		draw_circle(c, b_size * 0.42, Color(0.18, 0.22, 0.16, 0.6))
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
		# Отрисовка хижины с пристройками или Большого дома рода с пристройками
		if (b_id == "hut" or b_id.begins_with("hut")) and b_inst != null:
			# 1. Пристройка на заднем плане: Кладовая (hut_pantry)
			if b_inst.is_upgrade_unlocked("hut_pantry"):
				var pantry_tex = BuildingTextureManager.get_texture("hut_pantry")
				if pantry_tex:
					var p_size = b_size * 0.48
					var p_rect = Rect2(c.x + b_size * 0.18, c.y - b_size * 0.48, p_size, p_size)
					draw_circle(p_rect.get_center() + Vector2(0, p_size * 0.35), p_size * 0.35, Color(0.12, 0.15, 0.1, 0.45))
					draw_texture_rect(pantry_tex, p_rect, false)
			
			# 2. Основной дом хижины (main_house / House_update / dest_house)
			draw_circle(c + Vector2(0, b_size * 0.2), b_size * 0.42, Color(0.18, 0.22, 0.16, 0.6))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)
			
			# 3. Пристройка на переднем плане справа: Огород (hut_garden)
			if b_inst.is_upgrade_unlocked("hut_garden"):
				var garden_tex = BuildingTextureManager.get_texture("hut_garden")
				if garden_tex:
					var g_size = b_size * 0.52
					var g_rect = Rect2(c.x + b_size * 0.15, c.y + b_size * 0.08, g_size, g_size)
					draw_texture_rect(garden_tex, g_rect, false)
			
			# 4. Пристройка на переднем плане слева: Сарай (hut_shed / barn)
			if b_inst.is_upgrade_unlocked("hut_shed"):
				var shed_tex = BuildingTextureManager.get_texture("hut_shed")
				if shed_tex:
					var s_size = b_size * 0.50
					var s_rect = Rect2(c.x - b_size * 0.58, c.y + b_size * 0.06, s_size, s_size)
					draw_circle(s_rect.get_center() + Vector2(0, s_size * 0.35), s_size * 0.35, Color(0.12, 0.15, 0.1, 0.45))
					draw_texture_rect(shed_tex, s_rect, false)
		elif b_id == "great_lodge" and b_inst != null:
			# Большой дом рода с пристройками
			# 1. Пристройка на заднем плане: Детский угол (great_lodge_nursery)
			if b_inst.is_upgrade_unlocked("nursery_corner"):
				var nursery_tex = BuildingTextureManager.get_texture("great_lodge_nursery")
				if nursery_tex:
					var n_size = b_size * 0.52
					var n_rect = Rect2(c.x - b_size * 0.55, c.y - b_size * 0.45, n_size, n_size)
					draw_texture_rect(nursery_tex, n_rect, false)

			# 2. Пристройка сбоку: Место опекуна (great_lodge_caretaker)
			if b_inst.is_upgrade_unlocked("caretaker_quarters"):
				var care_tex = BuildingTextureManager.get_texture("great_lodge_caretaker")
				if care_tex:
					var ck_size = b_size * 0.48
					var ck_rect = Rect2(c.x - b_size * 0.65, c.y - b_size * 0.10, ck_size, ck_size)
					draw_texture_rect(care_tex, ck_rect, false)

			# 3. Основной Большой дом рода
			draw_circle(c + Vector2(0, b_size * 0.2), b_size * 0.46, Color(0.18, 0.22, 0.16, 0.6))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)

			# 4. Пристройка справа: Общие запасы (great_lodge_store)
			if b_inst.is_upgrade_unlocked("communal_store"):
				var store_tex = BuildingTextureManager.get_texture("great_lodge_store")
				if store_tex:
					var st_size = b_size * 0.50
					var st_rect = Rect2(c.x + b_size * 0.22, c.y - b_size * 0.35, st_size, st_size)
					draw_texture_rect(store_tex, st_rect, false)

			# 5. Пристройка на переднем плане: Круг знаний (great_lodge_knowledge)
			if b_inst.is_upgrade_unlocked("knowledge_circle"):
				var know_tex = BuildingTextureManager.get_texture("great_lodge_knowledge")
				if know_tex:
					var kn_size = b_size * 0.56
					var kn_rect = Rect2(c.x + b_size * 0.12, c.y + b_size * 0.08, kn_size, kn_size)
					draw_texture_rect(know_tex, kn_rect, false)

			# 6. Родовые знаки поверх фасада (great_lodge_totems)
			if b_inst.is_upgrade_unlocked("clan_totems"):
				var totem_tex = BuildingTextureManager.get_texture("great_lodge_totems")
				if totem_tex:
					var tt_size = b_size * 0.45
					var tt_rect = Rect2(c.x - tt_size * 0.5, c.y - b_size * 0.25, tt_size, tt_size)
					draw_texture_rect(totem_tex, tt_rect, false)
		elif b_id == "hunting_camp" and b_inst != null:
			# Охотничий лагерь с модульными улучшениями
			# 1. Задний план слева: Сушилка шкур (hunt_fur_rack)
			if b_inst.is_upgrade_unlocked("hunt_fur_rack"):
				var fur_tex = BuildingTextureManager.get_texture("hunt_fur_rack")
				if fur_tex:
					var fr_size = b_size * 0.52
					var fr_rect = Rect2(c.x - b_size * 0.58, c.y - b_size * 0.42, fr_size, fr_size)
					draw_texture_rect(fur_tex, fr_rect, false)

			# 2. Задний план справа: Стойка оружия (hunt_weapon_rack)
			if b_inst.is_upgrade_unlocked("hunt_weapon_rack"):
				var wep_tex = BuildingTextureManager.get_texture("hunt_weapon_rack")
				if wep_tex:
					var wr_size = b_size * 0.50
					var wr_rect = Rect2(c.x + b_size * 0.18, c.y - b_size * 0.40, wr_size, wr_size)
					draw_texture_rect(wep_tex, wr_rect, false)

			# 3. Основное здание лагеря (hunter_lodge / destr_hunter_lodge / hunter_shelter)
			draw_circle(c + Vector2(0, b_size * 0.2), b_size * 0.46, Color(0.18, 0.22, 0.16, 0.6))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)

			# 4. Передний план слева: Охотничий костёр (hunt_campfire)
			if b_inst.is_upgrade_unlocked("hunt_campfire"):
				var fire_tex = BuildingTextureManager.get_texture("hunt_campfire")
				if fire_tex:
					var fc_size = b_size * 0.50
					var fc_rect = Rect2(c.x - b_size * 0.56, c.y + b_size * 0.08, fc_size, fc_size)
					draw_texture_rect(fire_tex, fc_rect, false)

			# 5. Передний план справа: Площадка разделки (hunt_butcher_table)
			if b_inst.is_upgrade_unlocked("hunt_butcher_table"):
				var butcher_tex = BuildingTextureManager.get_texture("hunt_butcher_table")
				if butcher_tex:
					var bt_size = b_size * 0.54
					var bt_rect = Rect2(c.x + b_size * 0.12, c.y + b_size * 0.06, bt_size, bt_size)
					draw_texture_rect(butcher_tex, bt_rect, false)

			# 6. Верные охотничьи собаки (hunt_dogs) у лагерного костра
			if b_inst.is_upgrade_unlocked("hunt_dogs"):
				var dog_tex = BuildingTextureManager.get_texture("hunt_dogs")
				if dog_tex:
					var dg_size = b_size * 0.40
					var dg_rect = Rect2(c.x - b_size * 0.28, c.y + b_size * 0.15, dg_size, dg_size)
					draw_texture_rect(dog_tex, dg_rect, false)
		elif b_id == "foraging_post" and b_inst != null:
			# 1. Задний план: Сушильные рамки (forage_drying_racks)
			if b_inst.is_upgrade_unlocked("forage_drying_racks"):
				var dry_tex = BuildingTextureManager.get_texture("foraging_drying_racks")
				if dry_tex:
					var dr_size = b_size * 0.50
					var dr_rect = Rect2(c.x - b_size * 0.58, c.y - b_size * 0.42, dr_size, dr_size)
					draw_texture_rect(dry_tex, dr_rect, false)

			# 2. Задний план справа: Стол сортировки растений (forage_sorting_table)
			if b_inst.is_upgrade_unlocked("forage_sorting_table"):
				var sort_tex = BuildingTextureManager.get_texture("foraging_sorting_table")
				if sort_tex:
					var st_size = b_size * 0.50
					var st_rect = Rect2(c.x + b_size * 0.16, c.y - b_size * 0.40, st_size, st_size)
					draw_texture_rect(sort_tex, st_rect, false)

			# 3. Основной навес стоянки
			draw_circle(c + Vector2(0, b_size * 0.2), b_size * 0.46, Color(0.18, 0.22, 0.16, 0.6))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)

			# 4. Передний план слева: Плетёные корзины (forage_baskets)
			if b_inst.is_upgrade_unlocked("forage_baskets"):
				var bsk_tex = BuildingTextureManager.get_texture("foraging_baskets")
				if bsk_tex:
					var bk_size = b_size * 0.44
					var bk_rect = Rect2(c.x - b_size * 0.55, c.y + b_size * 0.08, bk_size, bk_size)
					draw_texture_rect(bsk_tex, bk_rect, false)

			# 5. Передний план справа: Яма-хранилище (forage_storage_pit)
			if b_inst.is_upgrade_unlocked("forage_storage_pit"):
				var pit_tex = BuildingTextureManager.get_texture("foraging_storage_pit")
				if pit_tex:
					var pt_size = b_size * 0.48
					var pt_rect = Rect2(c.x + b_size * 0.12, c.y + b_size * 0.08, pt_size, pt_size)
					draw_texture_rect(pit_tex, pt_rect, false)

			# 6. Опытная грядка / делянка
			if b_inst.is_upgrade_unlocked("forage_test_plot"):
				var plot_tex = BuildingTextureManager.get_texture("foraging_test_plot")
				if plot_tex:
					var pl_size = b_size * 0.46
					var pl_rect = Rect2(c.x - b_size * 0.24, c.y + b_size * 0.18, pl_size, pl_size)
					draw_texture_rect(plot_tex, pl_rect, false)
		elif b_id == "seed_store" and b_inst != null:
			draw_circle(c + Vector2(0, b_size * 0.2), b_size * 0.46, Color(0.18, 0.22, 0.16, 0.6))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)
			if b_inst.is_upgrade_unlocked("seed_selection_bench"):
				var sel_tex = BuildingTextureManager.get_texture("seed_sorting_table")
				if sel_tex:
					var sl_size = b_size * 0.45
					var sl_rect = Rect2(c.x - sl_size * 0.5, c.y + b_size * 0.10, sl_size, sl_size)
					draw_texture_rect(sel_tex, sl_rect, false)
		elif (b_id in ["primitive_garden", "primitive_field", "wheat_field", "orchard"]) and b_inst != null:
			# Сельскохозяйственные посадки
			draw_circle(c, b_size * 0.46, Color(0.15, 0.18, 0.12, 0.65))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)
				
			# Индикаторы и подсказки при наведении
			if hovered_tile_coord == coord and status == "active":
				var font = ThemeDB.fallback_font
				var stg_name = b_inst.get_growth_stage_name()
				var tip_text = "%s | 💧%.0f%% 🌱%.0f%%" % [stg_name, b_inst.soil_moisture, b_inst.soil_fertility]
				var tw = tip_text.length() * 6.2 + 12
				draw_rect(Rect2(c.x - tw * 0.5, c.y - b_size * 0.65 - 12, tw, 16), Color(0.08, 0.1, 0.15, 0.9))
				draw_string(font, Vector2(c.x - tw * 0.5 + 6, c.y - b_size * 0.65), tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 1.0, 0.6))
		elif b_id == "grave":

			if status == "preparing":
				# Подготавливаемая яма для предания земле
				draw_circle(c + Vector2(0, 3), b_size * 0.44, Color(0.18, 0.12, 0.08, 0.75))
				draw_circle(c + Vector2(0, 3), b_size * 0.30, Color(0.10, 0.06, 0.04, 0.90))
				draw_circle(c + Vector2(-5, 2), 2.2, Color(0.35, 0.25, 0.16, 0.85))
			else:
				draw_circle(c + Vector2(0, 5), b_size * 0.48, Color(0.22, 0.16, 0.10, 0.45))
				draw_circle(c + Vector2(0, 5), b_size * 0.35, Color(0.32, 0.24, 0.16, 0.65))
				if b_tex:
					draw_texture_rect(b_tex, b_rect, false)
		elif b_id == "wooden_fence":
			var fence_tex = _get_fence_texture_for_tile(coord, [])
			if fence_tex == null:
				fence_tex = b_tex
			var draw_w = TILE_SIZE
			var draw_h = TILE_SIZE
				
			if fence_tex:
				var tw = float(fence_tex.get_width())
				var th = float(fence_tex.get_height())
				if tw > th:
					draw_w = TILE_SIZE * 0.95
					draw_h = draw_w * (th / tw)
				else:
					draw_h = TILE_SIZE * 0.95
					draw_w = draw_h * (tw / th)
					
			draw_circle(c + Vector2(0, 3), 4.5, Color(0.12, 0.10, 0.08, 0.35))
			if fence_tex:
				var f_rect = Rect2(c.x - draw_w * 0.5, c.y - draw_h * 0.5, draw_w, draw_h)
				draw_texture_rect(fence_tex, f_rect, false)
		elif b_id == "wooden_gate":
			var is_op = b_data.get("is_open", false)
			var gate_tex = BuildingTextureManager.get_texture("gate_open" if is_op else "gate_closed")
			if gate_tex == null:
				gate_tex = BuildingTextureManager.get_texture("wooden_gate_open" if is_op else "wooden_gate_closed")
			if gate_tex == null:
				gate_tex = b_tex
				
			var gw = TILE_SIZE * 0.92
			var gh = TILE_SIZE * 0.92
			if gate_tex:
				var tw = float(gate_tex.get_width())
				var th = float(gate_tex.get_height())
				gw = TILE_SIZE * 0.95
				gh = gw * (th / tw)
				
			draw_circle(c + Vector2(0, 4), 6.0, Color(0.12, 0.10, 0.08, 0.35))
			if gate_tex:
				var g_rect = Rect2(c.x - gw * 0.5, c.y - gh * 0.5, gw, gh)
				draw_texture_rect(gate_tex, g_rect, false)
				
			if hovered_tile_coord == coord and status == "active":
				var tip = "🚪 Открыто (Клик: Запереть)" if is_op else "🔒 Заперто (Клик: Открыть)"
				var font = ThemeDB.fallback_font
				var tw = tip.length() * 6.5 + 12
				draw_rect(Rect2(c.x - tw * 0.5, c.y - b_size * 0.65 - 12, tw, 16), Color(0.08, 0.1, 0.15, 0.9))
				draw_string(font, Vector2(c.x - tw * 0.5 + 6, c.y - b_size * 0.65), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.5))
		elif b_id in ["cemetery", "grave"]:
			# --- ВЫДЕЛЕННЫЙ УЧАСТОК КЛАДБИЩА (СВЯЩЕННАЯ ЗЕМЛЯ И ДО 4 МОГИЛОК) ---
			# 1. Отрисовка священной вспаханной/освящённой почвы (площадка кладбища)
			var soil_rect = Rect2(c.x - TILE_SIZE * 0.47, c.y - TILE_SIZE * 0.47, TILE_SIZE * 0.94, TILE_SIZE * 0.94)
			# Мягкий темный земляной покров
			draw_rect(soil_rect, Color(0.22, 0.16, 0.10, 0.82))
			draw_rect(soil_rect, Color(0.14, 0.09, 0.05, 0.90), false, 1.0)
			
			# Небольшие угловые священные камни/колышки границы
			var p_tl = soil_rect.position
			var p_tr = Vector2(soil_rect.end.x, soil_rect.position.y)
			var p_bl = Vector2(soil_rect.position.x, soil_rect.end.y)
			var p_br = soil_rect.end
			draw_circle(p_tl + Vector2(2, 2), 1.8, Color(0.58, 0.55, 0.48, 0.95))
			draw_circle(p_tr + Vector2(-2, 2), 1.8, Color(0.58, 0.55, 0.48, 0.95))
			draw_circle(p_bl + Vector2(2, -2), 1.8, Color(0.58, 0.55, 0.48, 0.95))
			draw_circle(p_br + Vector2(-2, -2), 1.8, Color(0.58, 0.55, 0.48, 0.95))
			
			# 2. Отрисовка установленных могилок соплеменников (до 4 на клетку)
			var buried_list: Array = []
			if b_inst and b_inst.building_data.has("buried_citizens"):
				buried_list = b_inst.building_data["buried_citizens"]
			elif b_data.has("buried_citizens"):
				buried_list = b_data["buried_citizens"]
			var buried_count = mini(4, buried_list.size())
			
			# 4 позиции для могилок внутри клетки 32x32:
			# 0: Верх-Лево, 1: Верх-Право, 2: Низ-Лево, 3: Низ-Право
			var grave_offsets = [
				Vector2(-7.0, -6.0),
				Vector2(7.0, -6.0),
				Vector2(-7.0, 6.0),
				Vector2(7.0, 6.0)
			]
			
			var grave_tex = BuildingTextureManager.get_texture("grave")
			for i in range(buried_count):
				var g_pos = c + grave_offsets[i]
				# Земляной могильный холмик
				draw_circle(g_pos + Vector2(0, 3), 4.2, Color(0.18, 0.12, 0.08, 0.8))
				draw_circle(g_pos + Vector2(0, 3), 2.8, Color(0.30, 0.20, 0.12, 0.9))
				
				# Маленький надгробный памятник / крест / стела
				if grave_tex:
					var gw = 10.0
					var gh = 10.0
					var g_rect = Rect2(g_pos.x - gw * 0.5, g_pos.y - gh * 0.7, gw, gh)
					draw_texture_rect(grave_tex, g_rect, false)
				else:
					# Процедурное миниатюрное каменное надгробие
					draw_rect(Rect2(g_pos.x - 2.5, g_pos.y - 6.0, 5.0, 7.0), Color(0.58, 0.56, 0.52, 0.95))
					draw_line(g_pos + Vector2(0, -4.5), g_pos + Vector2(0, -1.5), Color(0.35, 0.33, 0.30), 1.0)
					draw_line(g_pos + Vector2(-1.5, -3.0), g_pos + Vector2(1.5, -3.0), Color(0.35, 0.33, 0.30), 1.0)
					
			if hovered_tile_coord == coord and status == "active":
				var font = ThemeDB.fallback_font
				var tip_text = "🪦 Родовое кладбище (%d/4 захоронений)" % buried_count
				var tw = tip_text.length() * 6.5 + 12
				draw_rect(Rect2(c.x - tw * 0.5, c.y - b_size * 0.65 - 12, tw, 16), Color(0.08, 0.1, 0.15, 0.9))
				draw_string(font, Vector2(c.x - tw * 0.5 + 6, c.y - b_size * 0.65), tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.5))
		else:
			draw_circle(c, b_size * 0.42, Color(0.18, 0.22, 0.16, 0.6))
			if b_tex:
				draw_texture_rect(b_tex, b_rect, false)

# --- ОТРИСОВКА ЦЕНТРА ПОСЕЛЕНИЯ (РОДОВОЙ ОЧАГ / КОСТРИЩЕ) ---
func _draw_single_settlement_hub(rect: Rect2, s: SettlementData) -> void:
	var c = rect.get_center()
	var is_player = (s.id == "player_tribe_settlement")
	var theme_color = Color(0.2, 0.7, 1.0) if is_player else Color(0.95, 0.35, 0.25)
	
	var pulse = 1.0 + sin(anim_time * 2.0) * 0.05
	# Утоптанная площадка родового круга
	draw_circle(c, TILE_SIZE * 0.48 * pulse, Color(0.35, 0.26, 0.16, 0.55))
	draw_circle(c, TILE_SIZE * 0.48 * pulse, Color(theme_color.r, theme_color.g, theme_color.b, 0.5), false, 1.2)
	
	# Брёвна / скамьи для отдыха соплеменников вокруг очага
	draw_line(c + Vector2(-10, -5), c + Vector2(-10, 5), Color(0.48, 0.34, 0.20), 2.8)
	draw_line(c + Vector2(10, -5), c + Vector2(10, 5), Color(0.48, 0.34, 0.20), 2.8)
	
	# Кольцо очажных камней
	var stone_count = 8
	for i in range(stone_count):
		var ang = float(i) * (TAU / float(stone_count))
		var stone_pos = c + Vector2(cos(ang) * 7.5, sin(ang) * 7.5 + 2.0)
		draw_circle(stone_pos, 1.8, Color(0.55, 0.52, 0.48, 0.95))
		draw_circle(stone_pos, 1.2, Color(0.70, 0.68, 0.62, 0.95))
	
	# Живое священное пламя родового костра
	var fire_pos = c + Vector2(0, 2.0)
	var fire_radius = 4.0 + sin(anim_time * 8.0) * 1.0
	draw_circle(fire_pos, fire_radius * 1.5, Color(1.0, 0.45, 0.1, 0.30))
	draw_circle(fire_pos, fire_radius, Color(1.0, 0.70, 0.1, 0.85))
	draw_circle(fire_pos, fire_radius * 0.55, Color(1.0, 0.95, 0.6, 0.98))
	
	# Дым от костра
	var smoke_offset = Vector2(sin(anim_time * 2.5) * 3.5, -10.0 - fmod(anim_time * 10.0, 14.0))
	draw_circle(fire_pos + smoke_offset, 2.2, Color(0.85, 0.85, 0.9, 0.30))

# --- ИНФОРМАЦИОННАЯ ПЛАШКА НАД ПОСЕЛЕНИЕМ ---
func _draw_settlement_hub_overlay(s: SettlementData, font: Font) -> void:
	var is_hovered = (hovered_tile_coord == s.pos)
	var is_selected = (selected_tile_coord == s.pos)
	if is_hovered or is_selected:
		var is_player = (s.id == "player_tribe_settlement")
		var theme_color = Color(0.2, 0.7, 1.0) if is_player else Color(0.95, 0.35, 0.25)
		var c = Vector2(s.pos.x * TILE_SIZE + 16, s.pos.y * TILE_SIZE + 16)
		var title_pos = c + Vector2(0, -TILE_SIZE * 0.95)
		var full_text = "%s • %d чел." % [s.name, s.population.get_total_population()]
		var text_w = full_text.length() * 6.5 + 14
		var banner_rect = Rect2(title_pos.x - text_w * 0.5, title_pos.y - 9, text_w, 18)
		draw_rect(banner_rect, Color(0.12, 0.15, 0.22, 0.94))
		draw_rect(banner_rect, theme_color, false, 1.2)
		draw_string(font, title_pos + Vector2(-text_w * 0.5 + 7, 4), full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.7))

# --- ОТРИСОВКА ТЕЛА ЖИТЕЛЯ (NPC) ---
# Возвращает ключ N-кадровой последовательности ("prefix_1".."prefix_count") по времени —
# настоящая покадровая анимация вместо чередования 2 поз (кадры реально нарисованы в листе,
# не интерполяция, поэтому движение читается плавнее без доп. затрат на отрисовку).
func _cycle_frame_key(prefix: String, count: int, fps: float) -> String:
	var idx = int(anim_time * fps) % count
	return "%s_%d" % [prefix, idx + 1]

# Поза действия (рубка/бой/переноска) поверх обычного портрета жителя.
# Возвращает null, если у жителя нет активного действия с отдельной позой — тогда рисуется обычный портрет.
func _get_citizen_action_texture(c: CitizenNPC) -> Texture2D:
	if c.state == CitizenNPC.State.WORKING and c.task_id == "chop_tree":
		return CharacterTextureManager.get_action_texture(_cycle_frame_key("woodcutter_axe", 4, 4.0))
	if c.state == CitizenNPC.State.CARRYING and c.cargo_type == "wood":
		return CharacterTextureManager.get_action_texture("carry_logs")
	if c.state == CitizenNPC.State.ATTACKING:
		# Охотник и лучник дерутся одинаково (лук) — общий спрайт на оба job_id.
		if c.job_id in ["hunter", "archer"]:
			return CharacterTextureManager.get_action_texture(_cycle_frame_key("hunter_bow", 4, 5.0))
		# Страж и воин дерутся одинаково (меч) — общий спрайт на оба job_id.
		if c.job_id in ["guard", "warrior"]:
			return CharacterTextureManager.get_action_texture(_cycle_frame_key("warrior_sword", 5, 6.0))
	# В пути к цели (не в бою и не за работой) — показываем позу "с оружием на ходу",
	# а не голый портрет: иначе казалось, что житель "не идёт", хотя он физически движется.
	if c.state == CitizenNPC.State.MOVING_TO_WORK:
		if c.job_id in ["hunter", "archer"]:
			return CharacterTextureManager.get_action_texture("hunter_bow_walk")
		if c.job_id == "woodcutter":
			return CharacterTextureManager.get_action_texture("woodcutter_axe_walk")
		if c.job_id in ["guard", "warrior"]:
			return CharacterTextureManager.get_action_texture("warrior_sword_walk")
	return null

func _draw_single_citizen_body(c: CitizenNPC) -> void:
	if not c.is_alive:
		if c.is_buried:
			return
		# Проверяем, не несёт ли уже могильщик тело на руках
		var is_carried = false
		if GameManager and GameManager.settlements:
			for s in GameManager.settlements.values():
				if s is SettlementData and s.population:
					for cit in s.population.citizens:
						if cit.is_alive and cit.carrying_deceased_id == c.citizen_id:
							is_carried = true
							break
				if is_carried:
					break
		if is_carried:
			return
			
		var p_dead = c.pos
		var tex_dead = c.get_texture()
		var sz_dead = Vector2(9.5, 9.5)
		draw_circle(p_dead + Vector2(0, 0.5), 4.5, Color(0, 0, 0, 0.25))
		if tex_dead:
			draw_set_transform(p_dead + Vector2(0, -1.0), PI * 0.5, Vector2(0.85, 0.85))
			draw_texture_rect(tex_dead, Rect2(-sz_dead.x * 0.5, -sz_dead.y * 0.5, sz_dead.x, sz_dead.y), false, Color(0.70, 0.70, 0.78, 0.85))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Мягкий полупрозрачный покров земли без белых ящиков
		var cover_rect = Rect2(p_dead.x - 4.5, p_dead.y - 2.5, 9.0, 4.5)
		draw_rect(cover_rect, Color(0.48, 0.42, 0.35, 0.35), true)
		return
		
	var p = c.pos
	var char_tex = c.get_texture()
	var char_size = Vector2(9.5, 9.5)
	if c.cohort == "child":
		char_size = Vector2(6.5, 6.5)
	elif c.cohort == "youth":
		char_size = Vector2(8.0, 8.0)
	
	var is_moving = (c.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.GOING_HOME, CitizenNPC.State.FLEEING] or not c.path.is_empty())
	var is_working = (c.state in [CitizenNPC.State.WORKING, CitizenNPC.State.GATHERING, CitizenNPC.State.BUTCHERING])

	var bob = sin(anim_time * 10.0 + float(c.seed_val % 100)) * 0.8 if is_moving else 0.0
	var flipped = (c.facing_dir.x < 0.0)
	var y_offset = -char_size.y * 0.95 + bob

	# Тень под ногами строго центрирована на c.pos (сбалансированная под новый размер)
	draw_circle(p + Vector2(0, 0.5), char_size.x * 0.20, Color(0, 0, 0, 0.26))

	# Поза действия поверх обычного портрета — чтобы было видно, что житель реально рубит/несёт,
	# а не просто покачивается. Не привязана к расе/полу, только к текущему занятию.
	var action_tex = _get_citizen_action_texture(c)
	if action_tex:
		var a_orig = action_tex.get_size()
		var a_aspect = a_orig.x / maxf(1.0, a_orig.y)
		var a_h = char_size.y
		var a_w = a_h * a_aspect
		var a_y_offset = -a_h * 0.95 + bob
		if flipped:
			draw_set_transform(p, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(action_tex, Rect2(-a_w * 0.5, a_y_offset, a_w, a_h), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(action_tex, Rect2(p.x - a_w * 0.5, p.y + a_y_offset, a_w, a_h), false)
	elif char_tex:
		if flipped:
			draw_set_transform(p, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(char_tex, Rect2(-char_size.x * 0.5, y_offset, char_size.x, char_size.y), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var char_rect = Rect2(p.x - char_size.x * 0.5, p.y + y_offset, char_size.x, char_size.y)
			draw_texture_rect(char_tex, char_rect, false)
	else:
		draw_circle(p + Vector2(0, y_offset + char_size.y * 0.3), 2.0, Color(0.9, 0.8, 0.7))
		draw_circle(p + Vector2(0, y_offset + char_size.y * 0.7), 2.2, Color(0.35, 0.45, 0.6))

	var facing_sign = -1.0 if flipped else 1.0

	# Тело усопшего, бережно несомое могильщиком на носилках/в руках на уровне пояса
	if c.carrying_deceased_id != "":
		var carry_y = p.y - 2.5 + bob
		var f_dir = -1.0 if flipped else 1.0
		# Деревянные жерди носилок
		draw_line(p + Vector2(-5.5 * f_dir, carry_y + 1.2), p + Vector2(5.5 * f_dir, carry_y + 1.2), Color(0.42, 0.28, 0.16), 1.2)
		draw_line(p + Vector2(-5.5 * f_dir, carry_y - 1.2), p + Vector2(5.5 * f_dir, carry_y - 1.2), Color(0.42, 0.28, 0.16), 1.2)
		# Мягкое льняное полотно с усопшим (компактное, аккуратно уложенное на носилках)
		var bier_rect = Rect2(p.x - 3.8, carry_y - 1.8, 7.6, 3.6)
		draw_rect(bier_rect, Color(0.55, 0.48, 0.40, 0.92), true)
		draw_rect(bier_rect, Color(0.38, 0.32, 0.25, 0.75), false, 0.8)
		# Руки могильщика, удерживающие жерди
		draw_circle(p + Vector2(-2.5 * f_dir, carry_y), 1.0, Color(0.82, 0.68, 0.52))
		draw_circle(p + Vector2(2.5 * f_dir, carry_y), 1.0, Color(0.82, 0.68, 0.52))

	# Визуальные движения инструмента при работе и оружие стражи
	# (лесоруб теперь получает позу с топором прямо из спрайта _get_citizen_action_texture — здесь ему рисовать нечего)
	if is_working:
		var swing = sin(anim_time * 8.0) * 3.0
		if c.job_id in ["quarryman", "miner"]:
			draw_line(p + Vector2(2.5 * facing_sign, -4.0), p + Vector2((5.0 - swing) * facing_sign, -6.0 + swing * 0.35), Color(0.6, 0.4, 0.2), 1.3)
			draw_circle(p + Vector2((5.0 - swing) * facing_sign, -6.0 + swing * 0.35), 1.4, Color(0.85, 0.75, 0.4))
		elif c.job_id == "builder" or c.task_id in ["build", "upgrade_work"]:
			draw_line(p + Vector2(2.5 * facing_sign, -3.5), p + Vector2(5.0 * facing_sign, -5.5 + swing * 0.45), Color(0.6, 0.4, 0.2), 1.2)
	elif c.job_id in ["guard", "warrior"] and c.state != CitizenNPC.State.ATTACKING:
		# Во время атаки меч уже виден на спрайте из _get_citizen_action_texture — эта
		# процедурная линия нужна только вне боя, как признак "всегда при оружии".
		draw_line(p + Vector2(3.5 * facing_sign, 0.5), p + Vector2(3.5 * facing_sign, -char_size.y - 2.5), Color(0.55, 0.38, 0.2), 1.2)
		draw_line(p + Vector2(3.5 * facing_sign, -char_size.y - 2.5), p + Vector2(3.5 * facing_sign, -char_size.y - 4.5), Color(0.8, 0.85, 0.9), 1.5)

	# Анимация рыбалки (удочка с леской, поплавок на воде, круги на воде и выпрыгивающая рыбка)
	var is_fishing_task = c.task_id in ["evening_fishing", "fish"] or (c.job_id == "fisherman" and (is_working or c.state in [CitizenNPC.State.WORKING, CitizenNPC.State.GATHERING, CitizenNPC.State.RESTING]))
	if is_fishing_task:
		var f_dir = 1.0 if c.facing_dir.x >= 0 else -1.0
		
		# Если житель идёт к месту рыбалки — он просто несёт удочку в руке
		if is_moving or c.state == CitizenNPC.State.MOVING_TO_WORK:
			var rod_hand = p + Vector2(2.0 * f_dir, -2.0 + bob)
			var rod_tip = rod_hand + Vector2(-6.0 * f_dir, -10.0) # Удочка за плечом
			draw_line(rod_hand, rod_tip, Color(0.52, 0.36, 0.20), 1.4)
			draw_line(rod_hand + Vector2(0.5 * f_dir, 1.0), rod_hand, Color(0.38, 0.24, 0.12), 1.6)
		else:
			# Проверяем, есть ли рядом настоящий водоём
			var c_coord = Vector2i(int(floor(c.pos.x / 32.0)), int(floor(c.pos.y / 32.0)))
			var has_water = false
			var water_dir = Vector2(f_dir, 0.0)
			
			if GameManager and GameManager.nav_grid:
				for n_off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]:
					var check_c = c_coord + n_off
					if GameManager.nav_grid.is_water_tile(check_c):
						has_water = true
						var w_center = GameManager.nav_grid.tile_to_world_center(check_c)
						var diff = w_center - c.pos
						if diff.length_squared() > 0.001:
							water_dir = diff.normalized()
						break
						
			if has_water:
				var cast_dir = 1.0 if water_dir.x >= 0 else -1.0
				var rod_hand = p + Vector2(2.5 * cast_dir, -3.5 + bob)
				var rod_tip = rod_hand + Vector2(8.0 * cast_dir, -7.0 + sin(anim_time * 2.5) * 0.7)
				
				# Удилище направлено к воде
				draw_line(rod_hand, rod_tip, Color(0.52, 0.36, 0.20), 1.3)
				draw_line(rod_hand + Vector2(-0.8 * cast_dir, 0.7), rod_hand, Color(0.38, 0.24, 0.12), 1.5)
				
				# Леска, свисающая точно к воде
				var float_offset = Vector2(water_dir.x * 12.0, maxf(4.0, water_dir.y * 10.0 + 6.0))
				var float_pos = rod_tip + float_offset + Vector2(0, sin(anim_time * 4.0) * 0.6)
				var mid_line = (rod_tip + float_pos) * 0.5 + Vector2(-0.6 * cast_dir, 1.2)
				draw_line(rod_tip, mid_line, Color(0.85, 0.90, 0.95, 0.75), 0.9)
				draw_line(mid_line, float_pos, Color(0.85, 0.90, 0.95, 0.75), 0.9)
				
				# Поплавок на воде
				draw_circle(float_pos, 1.4, Color(0.95, 0.25, 0.25, 0.95))
				draw_circle(float_pos + Vector2(0, 0.6), 0.8, Color(1.0, 1.0, 1.0, 0.95))
				
				# Круги на воде от поплавка (ripples)
				var rip_phase = fmod(anim_time * 2.0 + float(c.seed_val % 10), 1.0)
				var rip_rad = 1.5 + rip_phase * 3.5
				var rip_alpha = maxf(0.0, (1.0 - rip_phase) * 0.65)
				draw_arc(float_pos + Vector2(0, 0.7), rip_rad, 0, TAU, 10, Color(0.65, 0.85, 1.0, rip_alpha), 0.9)
				
				# Момент клева / выпрыгивающая из воды рыбка
				var catch_cycle = fmod(anim_time * 0.4 + float(c.seed_val % 7), 1.0)
				if catch_cycle > 0.75:
					var leap_p = (catch_cycle - 0.75) / 0.25
					var fish_y = -sin(leap_p * PI) * 6.0
					var fish_x = lerpf(0.0, -6.0 * cast_dir, leap_p)
					var fish_pos = float_pos + Vector2(fish_x, fish_y)
					draw_circle(fish_pos, 1.4, Color(0.75, 0.85, 0.95))
					draw_line(fish_pos, fish_pos + Vector2(1.6 * cast_dir, -0.6), Color(0.60, 0.75, 0.90), 1.0)
					draw_circle(float_pos + Vector2(-1.0, -1.2), 0.8, Color(0.85, 0.95, 1.0, 0.8))
					draw_circle(float_pos + Vector2(1.0, -1.5), 0.8, Color(0.85, 0.95, 1.0, 0.8))
			else:
				# Если воды рядом нет — удочка просто держится вертикально в руке
				var rod_hand = p + Vector2(2.5 * f_dir, -3.5 + bob)
				var rod_tip = rod_hand + Vector2(1.5 * f_dir, -12.0)
				draw_line(rod_hand, rod_tip, Color(0.52, 0.36, 0.20), 1.3)

	# Анимация вечерней тренировки и боевой разминки
	if c.task_id == "evening_training":
		var f_dir = 1.0 if c.facing_dir.x >= 0 else -1.0
		var strike_phase = sin(anim_time * 12.0)
		var weapon_base = p + Vector2(2.0 * f_dir, -3.5)
		var weapon_tip = weapon_base + Vector2((6.0 + strike_phase * 3.0) * f_dir, -2.0 + strike_phase * 2.0)
		draw_line(weapon_base, weapon_tip, Color(0.75, 0.80, 0.88), 1.4)
		if strike_phase > 0.4:
			draw_arc(weapon_base, 7.0, -0.6 if f_dir > 0 else PI - 0.4, 0.4 if f_dir > 0 else PI + 0.6, 6, Color(1.0, 0.9, 0.5, 0.6), 1.0)
			draw_circle(weapon_tip + Vector2(1.5 * f_dir, 0), 1.0, Color(1.0, 0.8, 0.3, 0.9))

	# Анимация осквернения могилы недругом (пинки, комья земли)
	if c.task_id == "desecrate_grave":
		var f_dir = 1.0 if c.facing_dir.x >= 0 else -1.0
		var kick_phase = sin(anim_time * 14.0)
		if kick_phase > 0.2:
			for d_i in range(3):
				var d_pos = p + Vector2((-3.0 - d_i * 2.0) * f_dir, -1.2 - sin(anim_time * 16.0 + d_i) * 3.0)
				draw_circle(d_pos, 1.1, Color(0.38, 0.24, 0.12, 0.85))

	# Анимация копки могилы лопатой со свежей землёй
	if c.task_id == "burial_procession" and c.subphase == "digging_grave":
		var dig_phase = sin(anim_time * 10.0)
		var f_dir = 1.0 if c.facing_dir.x >= 0 else -1.0
		var shovel_h = p + Vector2(3.0 * f_dir, -4.0 + dig_phase * 2.0)
		var shovel_tip = p + Vector2(5.0 * f_dir, 1.2 + dig_phase * 1.5)
		draw_line(p + Vector2(1.5 * f_dir, -3.0), shovel_h, Color(0.55, 0.38, 0.22), 1.5)
		draw_line(shovel_h, shovel_tip, Color(0.6, 0.65, 0.7), 1.8)
		draw_circle(shovel_tip, 1.4, Color(0.5, 0.55, 0.6))
		if dig_phase > 0.2:
			for dirt_i in range(3):
				var dirt_off = Vector2(sin(anim_time * 12.0 + dirt_i) * 4.5 * f_dir, -3.0 - cos(anim_time * 12.0 + dirt_i) * 3.0)
				draw_circle(shovel_tip + dirt_off, 1.0, Color(0.40, 0.28, 0.16, 0.95))

# --- ПАРЯЩИЙ UI И ОВЕРЛЕИ ЖИТЕЛЯ (ВСЕГДА ПОВЕРХ ДЕРЕВЬЕВ) ---
func _draw_citizen_overlays(c: CitizenNPC, font: Font) -> void:
	if not c.is_alive:
		return
	var p = c.pos
	var char_size = Vector2(9.5, 9.5)
	if c.cohort == "child":
		char_size = Vector2(6.5, 6.5)
	elif c.cohort == "youth":
		char_size = Vector2(8.0, 8.0)
	var is_moving = (c.state in [CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.GOING_HOME, CitizenNPC.State.FLEEING] or not c.path.is_empty())
	var bob = sin(anim_time * 10.0 + float(c.seed_val % 100)) * 0.8 if is_moving else 0.0

	# Свеча памяти в руках скорбящего / поминающего соплеменника
	if c.task_id in ["funeral_vigil", "visit_grave"]:
		var c_dir = 1.0 if c.facing_dir.x >= 0 else -1.0
		var candle_base = p + Vector2(5.0 * c_dir, -4.0)
		var flick = sin(anim_time * 14.0 + float(c.seed_val % 10)) * 0.8
		draw_line(candle_base, candle_base + Vector2(0, -4.0), Color(0.92, 0.90, 0.80), 1.6)
		draw_circle(candle_base + Vector2(0, -4.5), 3.5 + flick * 0.5, Color(1.0, 0.8, 0.2, 0.35))
		draw_circle(candle_base + Vector2(0, -4.8), 1.3, Color(1.0, 0.55, 0.1, 0.95))

	# Индикатор сна под открытым небом
	if c.state == CitizenNPC.State.SLEEPING:
		var z_bob = sin(anim_time * 3.0 + float(c.seed_val % 20)) * 2.0
		draw_string(font, p + Vector2(-6, -char_size.y - 4.0 + z_bob), "zZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.85, 1.0, 0.9))
		
	# Индикатор ожидания / простоя (?)
	elif c.state == CitizenNPC.State.WAITING:
		var wait_bob = sin(anim_time * 6.0 + float(c.seed_val % 50)) * 1.5
		var badge_pos = p + Vector2(0, -char_size.y - 8.0 + wait_bob)
		draw_circle(badge_pos, 5.2, Color(0.9, 0.7, 0.12, 0.95))
		draw_arc(badge_pos, 5.2, 0, TAU, 16, Color(1.0, 0.95, 0.6, 0.95), 1.0)
		draw_string(font, badge_pos + Vector2(-2.5, 3.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.12, 0.08, 0.02, 1.0))
		
	# Индикатор отдыха у костра / дома
	elif c.state == CitizenNPC.State.RESTING:
		var rest_bob = sin(anim_time * 4.0) * 1.2
		var badge_pos = p + Vector2(0, -char_size.y - 7.5 + rest_bob)
		draw_circle(badge_pos, 4.5, Color(0.18, 0.45, 0.6, 0.92))
		draw_arc(badge_pos, 4.5, 0, TAU, 16, Color(0.6, 0.85, 1.0, 0.9), 1.0)
		draw_string(font, badge_pos + Vector2(-3.5, 3.0), "~", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.9, 0.5))

	# Значок переносимого груза
	if c.cargo_type != "" and c.cargo_amount > 0:
		var cargo_icon = ItemTextureManager.get_icon(c.cargo_type)
		var icon_pos = p + Vector2(-4.0, -char_size.y - 6.0 + bob)
		draw_circle(icon_pos + Vector2(4.0, 4.0), 5.0, Color(0.08, 0.1, 0.15, 0.92))
		if cargo_icon:
			draw_texture_rect(cargo_icon, Rect2(icon_pos + Vector2(0.5, 0.5), Vector2(7.0, 7.0)), false)
		else:
			draw_circle(icon_pos + Vector2(4.0, 4.0), 2.5, Color(0.9, 0.7, 0.2))

	# Активное графическое облачко-эмоция / состояние над персонажем (Emote Bubble)
	if c.emote_timer > 0.0 and c.active_emote_id != "":
		var emote_tex = EmoteTextureManager.get_emote_texture(c.active_emote_id)
		if emote_tex:
			var pop_progress = clampf((c.emote_max_duration - c.emote_timer) / 0.2, 0.0, 1.0)
			var fade_progress = clampf(c.emote_timer / 0.35, 0.0, 1.0)
			var e_scale = pop_progress * (0.95 + 0.05 * sin(anim_time * 5.0))
			var e_alpha = fade_progress
			
			var e_bob = sin(anim_time * 4.0 + float(c.seed_val % 30)) * 1.5
			var e_size = Vector2(14.0, 14.0) * e_scale
			var emote_center = p + Vector2(0.0, -char_size.y - 8.0 + e_bob)
			var emote_rect = Rect2(emote_center.x - e_size.x * 0.5, emote_center.y - e_size.y * 0.5, e_size.x, e_size.y)
			
			draw_texture_rect(emote_tex, emote_rect, false, Color(1, 1, 1, e_alpha))



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

# --- ОТРИСОВКА ОДНОЙ ТУШИ ---
func _draw_single_carcass(c: Dictionary) -> void:
	var p = c["pos"]
	draw_circle(p + Vector2(0, 1.0), 4.0, Color(0, 0, 0, 0.35))
	if tex_carcass:
		var c_size = 14.0 if c.get("max_meat", 3.0) > 10.0 else 10.0
		draw_texture_rect(tex_carcass, Rect2(p.x - c_size * 0.5, p.y - c_size * 0.5, c_size, c_size), false)
	else:
		draw_circle(p, 3.5, Color(0.65, 0.25, 0.2))

# --- ОТРИСОВКА ТЕЛА ДИКОГО ЖИВОТНОГО ---
func _draw_single_animal_body(animal: WildAnimal) -> void:
	var p = animal.pos
	var is_moving = (animal.state in [WildAnimal.State.FLEEING, WildAnimal.State.GRAZING, WildAnimal.State.FOLLOWING, WildAnimal.State.SWIMMING, WildAnimal.State.DEFENDING])
	var bob = sin(animal.wobble_timer) * 0.8 if is_moving else 0.0
	
	# Эффект ряби на воде для плавающих уток или аура прирученного животного
	if animal.is_tamed:
		var pulse_t = 1.0 + sin(anim_time * 3.5) * 0.08
		var ring_r = maxf(4.5, (5.0 if (animal.is_child or animal.type_id.ends_with("_pup")) else 7.5) * pulse_t * animal.get_scale())
		draw_circle(p + Vector2(0, 1.0), ring_r, Color(0.2, 0.85, 0.45, 0.22))
		draw_arc(p + Vector2(0, 1.0), ring_r, 0, TAU, 16, Color(0.3, 0.95, 0.55, 0.65), 1.0)
	elif animal.state == WildAnimal.State.SWIMMING:
		draw_arc(p + Vector2(0, 2.0), 6.0 + sin(anim_time * 4.0) * 1.5, 0, TAU, 12, Color(0.6, 0.85, 1.0, 0.4), 1.0)
	else:
		var shadow_r = maxf(2.5, 4.5 * animal.get_scale())
		draw_circle(p + Vector2(0, 1.2), shadow_r, Color(0, 0, 0, 0.26))
		
	var a_tex = animal.get_texture()
	var a_scale = animal.get_scale()
	var base_dim = 14.0
	if animal.is_child or animal.type_id in ["wolf_pup", "deer_fawn", "boar_piglet", "bear_cub", "fox_kit"]:
		base_dim = 11.0
	elif animal.species in ["moose", "bear"]:
		base_dim = 20.0
	elif animal.species in ["deer", "boar", "wolf"]:
		base_dim = 15.0
	elif animal.species in ["fox", "lynx", "badger"]:
		base_dim = 13.0
	else:
		base_dim = 11.0
		
	var a_size = Vector2(base_dim, base_dim) * a_scale
	var flipped = (animal.facing_dir.x < 0.0)
	if a_tex:
		if flipped:
			draw_set_transform(p, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(a_tex, Rect2(-a_size.x * 0.5, -a_size.y + 2.0 + bob, a_size.x, a_size.y), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var a_rect = Rect2(p.x - a_size.x * 0.5, p.y - a_size.y + 2.0 + bob, a_size.x, a_size.y)
			draw_texture_rect(a_tex, a_rect, false)
	else:
		draw_circle(p, 2.5, Color(0.8, 0.6, 0.4))

# --- ПАРЯЩИЙ UI ЖИВОТНОГО (ЗДОРОВЬЕ, КЛИЧКА) ---
func _draw_animal_overlays(animal: WildAnimal, font: Font) -> void:
	var p = animal.pos
	var a_scale = animal.get_scale()
	var base_dim = 14.0
	if animal.is_child or animal.type_id in ["wolf_pup", "deer_fawn", "boar_piglet", "bear_cub", "fox_kit"]:
		base_dim = 11.0
	elif animal.species in ["moose", "bear"]:
		base_dim = 20.0
	elif animal.species in ["deer", "boar", "wolf"]:
		base_dim = 15.0
	elif animal.species in ["fox", "lynx", "badger"]:
		base_dim = 13.0
	else:
		base_dim = 11.0
	var a_size = Vector2(base_dim, base_dim) * a_scale

	# Полоска здоровья при ранении
	if animal.health < animal.max_health:
		var hp_pct = clampf(animal.health / animal.max_health, 0.0, 1.0)
		var bar_w = 14.0 * a_scale
		var bar_pos = p + Vector2(-bar_w * 0.5, -a_size.y - 3.0)
		draw_rect(Rect2(bar_pos.x, bar_pos.y, bar_w, 2.0), Color(0.2, 0.2, 0.2, 0.8))
		draw_rect(Rect2(bar_pos.x, bar_pos.y, bar_w * hp_pct, 2.0), Color(0.9, 0.2, 0.2, 0.95))

	# Для прирученных животных: аккуратный компактный бейдж (только при наведении / выделении)
	if animal.is_tamed:
		var mouse_w = get_global_mouse_position()
		var is_hovered = (mouse_w.distance_to(p) <= 18.0)
		var is_selected = (selected_animal_id == animal.id)
		
		var role_icon = "🛡" if animal.tamed_role == "guardian" else "🏹"
		var role_title = "Защитник" if animal.tamed_role == "guardian" else "Охотник"
		
		if is_hovered or is_selected:
			var tag_name = animal.custom_name if animal.custom_name != "" else "Питомец"
			var full_label = "%s %s • %s" % [role_icon, tag_name, role_title]
			var str_w = font.get_string_size(full_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 8).x
			var tag_p = p + Vector2(-str_w * 0.5, -a_size.y - (9.0 if animal.health < animal.max_health else 6.0))
			var b_rect = Rect2(tag_p.x - 4, tag_p.y - 2, str_w + 8, 12)
			
			draw_rect(Rect2(b_rect.position + Vector2(1, 1), b_rect.size), Color(0, 0, 0, 0.4), true)
			draw_rect(b_rect, Color(0.08, 0.15, 0.12, 0.92), true)
			draw_rect(b_rect, Color(0.35, 0.85, 0.55, 0.85), false, 1.0)
			draw_string(font, tag_p + Vector2(0, 7), full_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 1.0, 0.90))
			
			if is_selected:
				var hint_txt = "[Клик: сменить роль]"
				var h_w = font.get_string_size(hint_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 7).x
				var h_p = p + Vector2(-h_w * 0.5, tag_p.y - 8.0)
				draw_string(font, h_p + Vector2(0, 6), hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1.0, 0.9, 0.45, 0.9))
		else:
			pass

# --- ОТРИСОВКА СТРОЯ И ФИГУРОК RTS АРМИИ ---
func _draw_single_army_formation(a: ArmyData, f: FactionData) -> void:
	var p = a.world_pos
	
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

# --- ПАРЯЩИЙ UI АРМИИ (МАРШРУТ, ЗНАМЯ, МОРАЛЬ, РЕЧЬ) ---
func _draw_army_overlays(a: ArmyData, f: FactionData, font: Font) -> void:
	var p = a.world_pos
	var is_sel = (selected_army == a)
	var a_tile = Vector2i(int(floor(p.x / TILE_SIZE)), int(floor(p.y / TILE_SIZE)))
	var is_hovered = (hovered_tile_coord == a.pos or hovered_tile_coord == a_tile)
	var is_pl = (f.id == GameManager.player_faction_id)
	
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
	var s = 14.0
	var icon_rect = Rect2(c.x - s * 0.5, c.y - s * 0.5, s, s)
	
	# Полупрозрачная подложка под иконкой ресурса
	draw_circle(c, s * 0.6, Color(0.1, 0.12, 0.15, 0.85))
	draw_circle(c, s * 0.6, Color(1.0, 0.85, 0.3, 0.7), false, 1.0)
	
	if tex:
		draw_texture_rect(tex, icon_rect, false)
	else:
		draw_circle(c, 4.0, Color(1.0, 0.8, 0.2, 0.9))

# --- ОТРИСОВКА ОДНОЙ ПЕРСОНАЛЬНОЙ ДЕКОРАЦИИ NPC ---
func _draw_single_npc_decoration(center: Vector2, deco: Dictionary) -> void:
	var font = ThemeDB.fallback_font
	var dtype = deco.get("type", "")
	var variant = int(deco.get("variant", 0))

	match dtype:
		"sign":
			# Деревянная табличка: столбик + прямоугольная доска
			var post_top = center + Vector2(0, -5)
			var post_bot = center + Vector2(0, 1)
			draw_line(post_bot, post_top, Color(0.55, 0.38, 0.22), 1.0)
			var board_rect = Rect2(center.x - 4, center.y - 8, 8, 4.5)
			draw_rect(board_rect, Color(0.70, 0.52, 0.30, 0.95))
			draw_rect(board_rect, Color(0.40, 0.28, 0.15, 0.9), false, 0.8)
			draw_line(center + Vector2(-2.5, -6), center + Vector2(2.5, -6), Color(0.25, 0.18, 0.10, 0.8), 0.8)

		"bush_planted":
			# Посаженный куст — аккуратный компактный шарик
			var bush_col = [Color(0.25, 0.55, 0.20), Color(0.30, 0.60, 0.18), Color(0.20, 0.50, 0.25)][variant]
			draw_circle(center + Vector2(0, -1), 3.0, Color(0, 0, 0, 0.18))
			draw_circle(center + Vector2(-1, -2), 2.5, bush_col)
			draw_circle(center + Vector2(1, -2), 2.2, bush_col.lightened(0.1))
			draw_circle(center + Vector2(0, -3.5), 2.0, bush_col.lightened(0.05))
			if variant == 1:
				draw_circle(center + Vector2(-0.5, -3), 0.9, Color(0.9, 0.25, 0.20))
			elif variant == 2:
				draw_circle(center + Vector2(0.5, -2.5), 0.9, Color(0.95, 0.85, 0.2))

		"bench":
			# Скамейка: миниатюрные ножки + сиденье
			var bench_col = Color(0.58, 0.42, 0.25)
			var dark_col = Color(0.38, 0.27, 0.14)
			draw_line(center + Vector2(-3.5, 0), center + Vector2(-3.5, -2.5), dark_col, 1.0)
			draw_line(center + Vector2(3.5, 0), center + Vector2(3.5, -2.5), dark_col, 1.0)
			draw_rect(Rect2(center.x - 4.5, center.y - 4, 9, 2), bench_col)
			draw_rect(Rect2(center.x - 4.5, center.y - 4, 9, 2), dark_col, false, 0.6)
			if variant != 1:
				draw_rect(Rect2(center.x - 4, center.y - 6.5, 8, 1.5), bench_col.darkened(0.1))

		"flowers":
			# Цветочная клумба: миниатюрные разноцветные бутоны
			var petal_colors = [
				[Color(1.0, 0.35, 0.35), Color(1.0, 0.9, 0.2), Color(0.9, 0.55, 0.85)],
				[Color(0.9, 0.85, 0.2), Color(0.95, 0.5, 0.2), Color(0.8, 0.3, 0.7)],
				[Color(0.55, 0.7, 1.0), Color(1.0, 0.9, 0.4), Color(0.8, 0.35, 0.35)]
			][variant]
			for i in range(3):
				var fx = center.x + [-2.2, 0.0, 2.0][i]
				var fy = center.y + [-0.5, -1.8, 0.2][i]
				draw_line(Vector2(fx, fy + 2), Vector2(fx, fy - 1), Color(0.3, 0.55, 0.2), 0.8)
				draw_circle(Vector2(fx, fy - 1), 1.4, petal_colors[i])

		"totem_small":
			# Небольшой тотемчик
			draw_line(center + Vector2(0, 2), center + Vector2(0, -6), Color(0.50, 0.34, 0.18), 2.0)
			var mask_rect = Rect2(center.x - 2.5, center.y - 9, 5, 4.5)
			draw_rect(mask_rect, Color(0.72, 0.50, 0.28, 0.95))
			draw_rect(mask_rect, Color(0.35, 0.22, 0.10), false, 0.8)
			draw_circle(center + Vector2(-1.2, -7.5), 0.8, Color(0.15, 0.10, 0.05))
			draw_circle(center + Vector2(1.2, -7.5), 0.8, Color(0.15, 0.10, 0.05))
			draw_line(center + Vector2(0, -9), center + Vector2(-2, -12), Color(0.85, 0.25, 0.15), 1.0)
			draw_line(center + Vector2(0, -9), center + Vector2(2, -12), Color(0.90, 0.80, 0.10), 1.0)

		"idol":
			# Резной идол предков
			draw_line(center + Vector2(0, 2), center + Vector2(0, -7), Color(0.48, 0.32, 0.16), 3.0)
			draw_circle(center + Vector2(0, -9.5), 3.5, Color(0.62, 0.44, 0.24))
			draw_circle(center + Vector2(0, -9.5), 3.5, Color(0.32, 0.20, 0.08), false, 0.8)
			draw_circle(center + Vector2(-1.4, -10), 0.9, Color(0.10, 0.07, 0.03))
			draw_circle(center + Vector2(1.4, -10), 0.9, Color(0.10, 0.07, 0.03))
			draw_line(center + Vector2(-1.2, -8.2), center + Vector2(1.2, -8.2), Color(0.20, 0.12, 0.05), 1.0)
			var placer = deco.get("placer_name", "")
			if placer != "":
				draw_string(font, center + Vector2(0, 6), placer, HORIZONTAL_ALIGNMENT_CENTER, -1, 6, Color(0.9, 0.8, 0.5, 0.75))

		"trash":
			# Мусор
			var trash_col = Color(0.40, 0.35, 0.22, 0.80)
			var dark_trash = Color(0.28, 0.24, 0.14, 0.70)
			draw_circle(center + Vector2(-1.2, 0.5), 1.8, trash_col)
			draw_circle(center + Vector2(1.2, -0.5), 1.5, dark_trash)
			if variant == 1:
				# Кость/щепка
				draw_line(center + Vector2(-3, -2), center + Vector2(3, 2), Color(0.75, 0.70, 0.55, 0.8), 1.5)
			else:
				# Тряпка
				draw_rect(Rect2(center.x - 3, center.y - 3, 5, 3), Color(0.55, 0.48, 0.30, 0.7))

# ==============================================================================
# ДЕНЬ И НОЧЬ: СВЕТОВОЕ ОКРУЖЕНИЕ, ОЧАГИ, ОКНА И ТЬМА
# ==============================================================================
func _get_ambient_light_color() -> Color:
	var hour = GameManager.current_hour if GameManager else 12.0
	if hour < 4.5:
		return Color(0.32, 0.36, 0.58) # Глубокая лунная ночь (индиго)
	elif hour < 6.0:
		var t = (hour - 4.5) / 1.5
		return Color(0.32, 0.36, 0.58).lerp(Color(0.85, 0.68, 0.65), t) # Предрассвет
	elif hour < 8.5:
		var t = (hour - 6.0) / 2.5
		return Color(0.85, 0.68, 0.65).lerp(Color(1.0, 1.0, 1.0), t) # Рассвет -> День
	elif hour < 17.0:
		return Color(1.0, 1.0, 1.0) # Полный день
	elif hour < 19.5:
		var t = (hour - 17.0) / 2.5
		return Color(1.0, 1.0, 1.0).lerp(Color(1.08, 0.82, 0.60), t) # Золотистый закат
	elif hour < 21.75:
		var t = (hour - 19.5) / 2.25
		return Color(1.08, 0.82, 0.60).lerp(Color(0.50, 0.46, 0.66), t) # Закат -> Сумерки
	else:
		var t = (hour - 21.75) / 2.25
		return Color(0.50, 0.46, 0.66).lerp(Color(0.32, 0.36, 0.58), t) # Сумерки -> Ночь

func _get_night_darkness_factor() -> float:
	var hour = GameManager.current_hour if GameManager else 12.0
	if hour >= 22.0 or hour < 5.0:
		return 1.0
	elif hour >= 19.5 and hour < 22.0:
		return (hour - 19.5) / 2.5
	elif hour >= 5.0 and hour < 7.5:
		return 1.0 - (hour - 5.0) / 2.5
	return 0.0

func _draw_night_atmosphere(screen_rect: Rect2, night_factor: float) -> void:
	if night_factor <= 0.01:
		return
		
	# 1. Полночный сине-индиговый покров тьмы
	draw_rect(screen_rect, Color(0.03, 0.05, 0.16, 0.48 * night_factor))
	
	# 2. Очаги и костры поселений (живое пламя и тепловой ореол)
	if GameManager and GameManager.settlements:
		for s in GameManager.settlements.values():
			if s is SettlementData:
				var c_pos = Vector2(s.pos.x * TILE_SIZE + 16, s.pos.y * TILE_SIZE + 16)
				if screen_rect.has_point(c_pos):
					var flicker = 1.0 + 0.08 * sin(anim_time * 7.5 + float(s.pos.x))
					# Тройной тёплый ореол огня, пробивающий ночную тьму
					draw_circle(c_pos, 85.0 * flicker, Color(1.0, 0.65, 0.20, 0.26 * night_factor))
					draw_circle(c_pos, 52.0 * flicker, Color(1.0, 0.80, 0.35, 0.42 * night_factor))
					draw_circle(c_pos, 22.0 * flicker, Color(1.0, 0.95, 0.65, 0.65 * night_factor))
					# Взлетающие золотые искры
					for i in range(5):
						var spark_y = c_pos.y - fmod(anim_time * 28.0 + float(i * 11), 36.0)
						var spark_x = c_pos.x + sin(anim_time * 4.0 + float(i * 2)) * 6.0
						draw_circle(Vector2(spark_x, spark_y), 1.3, Color(1.0, 0.88, 0.35, 0.85 * night_factor))

	# 3. Тёплый свет в окнах и у входа жилых хижин и Большого дома
	if GameManager and GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b is BuildingInstance and (b.is_residential() or b.type in ["great_lodge", "elders_house", "hunting_camp"]):
				var b_pos = Vector2(b.pos.x * TILE_SIZE + 16, b.pos.y * TILE_SIZE + 16)
				if screen_rect.has_point(b_pos):
					var b_flicker = 1.0 + 0.05 * sin(anim_time * 5.0 + float(b.pos.x + b.pos.y))
					# Тёплый свет у порога
					draw_circle(b_pos + Vector2(0, 4), 36.0 * b_flicker, Color(1.0, 0.75, 0.30, 0.28 * night_factor))
					# Золотистый уютный свет в окошках
					var win_left = Rect2(b_pos.x - 5.5, b_pos.y - 3.5, 3.2, 3.2)
					var win_right = Rect2(b_pos.x + 2.5, b_pos.y - 3.5, 3.2, 3.2)
					draw_circle(win_left.get_center(), 6.0, Color(1.0, 0.85, 0.35, 0.40 * night_factor))
					draw_circle(win_right.get_center(), 6.0, Color(1.0, 0.85, 0.35, 0.40 * night_factor))
					draw_rect(win_left, Color(1.0, 0.92, 0.45, 0.95 * night_factor))
					draw_rect(win_right, Color(1.0, 0.92, 0.45, 0.95 * night_factor))

	# 4. Факелы сторожевых вышек
	if GameManager and GameManager.tile_buildings:
		for coord in GameManager.tile_buildings:
			var tb = GameManager.tile_buildings[coord]
			if tb.get("id", "") == "watchtower":
				var tw_pos = Vector2(coord.x * TILE_SIZE + 16, coord.y * TILE_SIZE + 16)
				if screen_rect.has_point(tw_pos):
					var tf = 1.0 + 0.1 * sin(anim_time * 8.0 + float(coord.x))
					draw_circle(tw_pos + Vector2(-6, -12), 24.0 * tf, Color(1.0, 0.78, 0.28, 0.35 * night_factor))
					draw_circle(tw_pos + Vector2(6, -12), 24.0 * tf, Color(1.0, 0.78, 0.28, 0.35 * night_factor))

	# 5. Факелы ночной стражи
	if GameManager and GameManager.settlements:
		for s in GameManager.settlements.values():
			if s is SettlementData and s.population:
				for c in s.population.citizens:
					if c.is_alive and c.job_id in ["guard", "warrior"] and c.state != CitizenNPC.State.SLEEPING:
						if screen_rect.has_point(c.pos):
							var gf = 1.0 + 0.08 * sin(anim_time * 9.0 + float(c.seed_val))
							draw_circle(c.pos + Vector2(0, -3), 26.0 * gf, Color(1.0, 0.80, 0.35, 0.32 * night_factor))
							var torch_pos = c.pos + Vector2(3.5 * c.facing_dir.x, -6)
							draw_circle(torch_pos, 2.0, Color(1.0, 0.95, 0.55, 0.95 * night_factor))

	# 6. Мягко мерцающие светлячки в диких лесах и лугах
	for i in range(16):
		var fx = screen_rect.position.x + fmod(float(i * 137.5 + anim_time * 8.0), maxf(10.0, screen_rect.size.x))
		var fy = screen_rect.position.y + fmod(float(i * 93.1 + sin(anim_time * 1.5 + float(i)) * 20.0), maxf(10.0, screen_rect.size.y))
		var f_pos = Vector2(fx, fy)
		var pulse = (sin(anim_time * 3.5 + float(i * 1.7)) + 1.0) * 0.5
		draw_circle(f_pos, 1.2 * pulse, Color(0.85, 1.0, 0.35, 0.65 * pulse * night_factor))
