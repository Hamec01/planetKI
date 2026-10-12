class_name BattleTest
extends Node2D

# ==============================================================================
# ТЕСТОВЫЙ БОЙ «СТЕНКА НА СТЕНКУ» (кнопка в главном меню)
# ------------------------------------------------------------------------------
# Небольшая расчищенная поляна, два племени: игрок (Король + 10 воинов) и
# «Чёрный Волк» (10 воинов). Всем выдаётся случайное оружие из арсенала
# (мечи, топоры, копья, луки) и, кому повезёт, щит и доспех. Бой — настоящий:
# урон считает CombatStatsResolver по оружию, броне и навыкам, раненые
# анимируются, погибшие остаются на поле. Король управляется игроком
# (WASD, Пробел, Shift-перекат, E/ПКМ — удар по врагу).
# ==============================================================================

const ARENA_HALF: Vector2i = Vector2i(15, 8) # поляна 31 x 17 клеток
const TEAM_SIZE: int = 10
const ENEMY_FACTION: String = "enemy_wolf_tribe"
const ENEMY_SETTLEMENT: String = "enemy_wolf_tribe_settlement"
const COUNTDOWN: float = 4.0
const RETARGET_INTERVAL: float = 0.5
const SEPARATION_DIST: float = 6.0
const MELEE_WEAPONS: Array[String] = ["short_sword", "battle_axe", "work_axe", "simple_spear", "club"]
const RANGED_WEAPONS: Array[String] = ["hunting_bow", "improved_hunting_bow", "longbow"]
const SHIELDS: Array[String] = ["wooden_shield", "reinforced_shield"]
const ARMORS: Array[String] = ["clothes", "padded_armor", "leather_armor"]

var countdown: float = COUNTDOWN
var finished: bool = false
var player_team: Array[CitizenNPC] = []
var enemy_team: Array[CitizenNPC] = []
var arrows: Array[Dictionary] = [] # {from, to, t, dur}
var floaters: Array[Dictionary] = [] # {pos, text, t, color}
var _cooldowns: Dictionary = {} # citizen_id -> секунд до удара
var _targets: Dictionary = {} # citizen_id -> CitizenNPC
var _retarget_timer: float = 0.0
var kills: Dictionary = {"player": 0, "enemy": 0}

var hud: CanvasLayer = null
var score_lbl: Label = null
var center_lbl: Label = null
var end_panel: PanelContainer = null

# --- КАРТА: обычный мир, но вокруг стоянки игрока расчищена ровная поляна ---
static func build_world(seed_str: String) -> Dictionary:
	var world = WorldGenerator.generate_world(seed_str)
	var tiles: Array = world["tiles"]
	var h = tiles.size()
	var w = tiles[0].size()
	var center = Vector2i(w / 2, h / 2)
	for y in range(center.y - ARENA_HALF.y - 3, center.y + ARENA_HALF.y + 4):
		for x in range(center.x - ARENA_HALF.x - 3, center.x + ARENA_HALF.x + 4):
			if y < 0 or y >= h or x < 0 or x >= w:
				continue
			var t: Dictionary = tiles[y][x]
			var inside = absi(x - center.x) <= ARENA_HALF.x and absi(y - center.y) <= ARENA_HALF.y
			t["is_water"] = false
			t["is_river"] = false
			t["resource"] = null
			t["elevation"] = 0.45
			t["biome"] = BiomeDefinitions.BiomeType.PLAINS if inside else BiomeDefinitions.BiomeType.DECIDUOUS_FOREST
			# Кромка леса вокруг поляны — граница «маленькой карты»
			if inside:
				t["nature_object"] = "none" if (x + y * 7) % 11 != 0 else "flowers_yellow"
			else:
				t["nature_object"] = ["tree_oak", "tree_birch", "tree_pine"][absi(x * 3 + y) % 3]
	world["spawns"]["player"]["pos"] = center + Vector2i(-ARENA_HALF.x + 2, 0)
	world["spawns"]["ai"] = []
	world["arena_center"] = center
	return world

# --- РАССТАНОВКА ВОЙСК ---
func setup() -> void:
	var player_s: SettlementData = GameManager.get_player_settlement()
	var center: Vector2i = GameManager.planet_data.get("arena_center", player_s.pos)
	# Враждебное племя
	var enemy_f = FactionData.new(ENEMY_FACTION, "Племя Чёрного Волка", "Вожак Гром", Color(0.85, 0.25, 0.2), false)
	GameManager.factions[enemy_f.id] = enemy_f
	var pf: FactionData = GameManager.factions[GameManager.player_faction_id]
	pf.get_relation(enemy_f.id)["is_at_war"] = true
	enemy_f.get_relation(pf.id)["is_at_war"] = true
	var enemy_s = SettlementData.new(ENEMY_SETTLEMENT, "Стан Чёрного Волка", enemy_f.id, center + Vector2i(ARENA_HALF.x - 2, 0))
	GameManager.settlements[enemy_s.id] = enemy_s
	enemy_s.init_citizens_on_map()

	player_team = _prepare_team(player_s, center + Vector2i(-ARENA_HALF.x + 4, 0), 1.0, false)
	enemy_team = _prepare_team(enemy_s, center + Vector2i(ARENA_HALF.x - 4, 0), -1.0, true)
	_build_hud()
	EventBus.notification_toast.emit("⚔ Тестовый бой", "Племя Чёрного Волка вышло на поляну. Через %d секунд — стенка на стенку!" % int(COUNTDOWN), "warning")

func _prepare_team(s: SettlementData, front: Vector2i, facing: float, is_enemy: bool) -> Array[CitizenNPC]:
	var team: Array[CitizenNPC] = []
	var fighters: Array[CitizenNPC] = []
	var ruler: CitizenNPC = null
	for c in s.population.citizens:
		if not c.is_alive:
			continue
		if c.is_ruler:
			if is_enemy:
				c.is_ruler = false # у врагов вожак — просто сильный воин, его гибель не конец игры
				c.name = "Вожак Гром"
			else:
				ruler = c
				continue
		fighters.append(c)
	while fighters.size() > TEAM_SIZE:
		fighters.pop_back()
	var front_px = Vector2(front.x * 32.0 + 16.0, front.y * 32.0 + 16.0)
	for i in range(fighters.size()):
		var c = fighters[i]
		if is_enemy:
			c.citizen_id = "wolf_" + c.citizen_id
			c.name = c.name.get_slice(" ", 0) + " Волчий" if not c.name.begins_with("Вожак") else c.name
		_arm(c)
		# Строй: ближний бой в первой линии, лучники за спиной
		var ranged = RANGED_WEAPONS.has(String(c.equipment["weapon"]))
		var row = 1 if ranged else 0
		var col = i % 5
		c.pos = front_px + Vector2(-facing * row * 26.0 + randf_range(-3, 3), (col - 2) * 18.0 + randf_range(-3, 3))
		c.path.clear()
		c.facing_dir = Vector2(facing, 0)
		c.state = CitizenNPC.State.IDLE
		c.health = c.max_health
		c.custom_data["in_battle"] = true
		c.custom_data["battle_team"] = "enemy" if is_enemy else "player"
		c.last_status_reason = "Стоит в строю"
		team.append(c)
	if ruler:
		ruler.equipment["weapon"] = "short_sword"
		ruler.equipment["shield"] = "wooden_shield"
		ruler.equipment["body_armor"] = "leather_armor"
		ruler.pos = front_px + Vector2(-facing * 12.0, 0)
		ruler.facing_dir = Vector2(facing, 0)
		ruler.health = ruler.max_health
		ruler.custom_data["in_battle"] = true
		ruler.custom_data["battle_team"] = "player"
		team.append(ruler)
	return team

static func _arm(c: CitizenNPC) -> void:
	var ranged = randf() < 0.3
	var weapon = RANGED_WEAPONS.pick_random() if ranged else MELEE_WEAPONS.pick_random()
	c.equipment["weapon"] = weapon
	c.equipment["shield"] = SHIELDS.pick_random() if (not ranged and randf() < 0.55) else ""
	c.equipment["body_armor"] = ARMORS.pick_random()
	c.equipment["helmet"] = "iron_helmet" if randf() < 0.2 else ""
	c.job_id = "warrior"

# --- ИИ БОЯ ---
func _process(delta: float) -> void:
	if GameManager.is_paused:
		queue_redraw()
		return
	var sim_dt = delta * GameManager.game_speed
	for a in arrows:
		a["t"] += sim_dt
	arrows = arrows.filter(func(a): return a["t"] < a["dur"])
	for f in floaters:
		f["t"] += delta
	floaters = floaters.filter(func(f): return f["t"] < 1.1)
	if finished:
		queue_redraw()
		return
	if countdown > 0.0:
		countdown -= delta
		center_lbl.text = "Бой через %d…" % int(ceil(countdown)) if countdown > 0.0 else "В БОЙ!"
		if countdown <= 0.0:
			for c in player_team + enemy_team:
				c.shout(["За племя!", "Вперёд!", "Ааа!", "Бей их!"].pick_random(), 1.6)
			var t = get_tree().create_timer(1.2)
			t.timeout.connect(func(): if is_instance_valid(center_lbl) and not finished: center_lbl.text = "")
		_update_score()
		queue_redraw()
		return
	_retarget_timer -= sim_dt
	var retarget = _retarget_timer <= 0.0
	if retarget:
		_retarget_timer = RETARGET_INTERVAL
	for c in player_team:
		_tick_fighter(c, enemy_team, player_team, sim_dt, retarget)
	for c in enemy_team:
		_tick_fighter(c, player_team, enemy_team, sim_dt, retarget)
	_update_score()
	_check_end()
	queue_redraw()

func _alive(team: Array[CitizenNPC]) -> Array[CitizenNPC]:
	return team.filter(func(c): return c.is_alive and c.health > 0.0)

func _tick_fighter(c: CitizenNPC, foes: Array[CitizenNPC], friends: Array[CitizenNPC], dt: float, retarget: bool) -> void:
	if not c.is_alive or c.health <= 0.0:
		return
	# Короля в Режиме Короля ведёт игрок
	if c.is_ruler and GameManager.hero_control_active:
		return
	var cd = float(_cooldowns.get(c.citizen_id, 0.0)) - dt
	_cooldowns[c.citizen_id] = cd
	var target: CitizenNPC = _targets.get(c.citizen_id, null)
	if retarget or target == null or not target.is_alive:
		target = _nearest(c, foes)
		_targets[c.citizen_id] = target
	if target == null:
		c.state = CitizenNPC.State.CELEBRATING
		return
	var stats = c.get_combat_stats()
	var ranged = bool(stats.get("is_ranged", false))
	var reach = maxf(12.0, float(stats.get("attack_range", 0.8)) * 20.0)
	var to = target.pos - c.pos
	var dist = to.length()
	c.facing_dir = to.normalized() if dist > 0.1 else c.facing_dir
	var move = Vector2.ZERO
	if dist > reach:
		move = to.normalized()
	elif ranged and dist < reach * 0.45:
		move = -to.normalized() # лучник отступает, держит дистанцию
	# Не толпиться в одной точке
	for f in friends:
		if f != c and f.is_alive:
			var d = c.pos.distance_to(f.pos)
			if d < SEPARATION_DIST and d > 0.01:
				move += (c.pos - f.pos).normalized() * (1.0 - d / SEPARATION_DIST) * 0.8
	if move != Vector2.ZERO:
		var spd = c.get_speed() * (1.8 if not ranged else 1.5)
		HeroMotion.step(c, move.normalized() * spd * dt)
		if dist > reach:
			c.state = CitizenNPC.State.MOVING_TO_WORK
			c.last_status_reason = "Бежит на %s" % target.name
	if dist <= reach:
		c.state = CitizenNPC.State.ATTACKING
		if cd <= 0.0:
			_cooldowns[c.citizen_id] = float(stats.get("attack_interval", 1.2))
			_strike(c, target, stats, ranged)

func _nearest(c: CitizenNPC, foes: Array[CitizenNPC]) -> CitizenNPC:
	var best: CitizenNPC = null
	var best_d = INF
	for f in foes:
		if f.is_alive and f.health > 0.0:
			var d = c.pos.distance_squared_to(f.pos)
			if d < best_d:
				best_d = d
				best = f
	return best

# Удар по правилам игры: точность, броня, пробитие. Лучники пускают видимую стрелу.
func _strike(attacker: CitizenNPC, victim: CitizenNPC, stats: Dictionary, ranged: bool) -> void:
	var outcome = CombatStatsResolver.resolve_attack(stats, victim.get_combat_stats())
	if ranged:
		arrows.append({"from": attacker.pos + Vector2(0, -5), "to": victim.pos + Vector2(randf_range(-3, 3), -4), "t": 0.0, "dur": clampf(attacker.pos.distance_to(victim.pos) / 260.0, 0.12, 0.6)})
	if not outcome["is_hit"]:
		_floater(victim.pos, "мимо", Color(0.8, 0.8, 0.8))
		return
	var dmg = float(outcome["damage"])
	var was_alive = victim.is_alive
	victim.take_damage(dmg, attacker.name)
	if victim.is_ruler and victim.custom_data.has("dodged_at") and float(victim.custom_data["dodged_at"]) >= GameManager.sim_time_total - 0.05:
		_floater(victim.pos, "уклон!", Color(0.5, 0.9, 1.0))
		return
	if victim.custom_data.has("blocked_at") and float(victim.custom_data["blocked_at"]) >= GameManager.sim_time_total - 0.05:
		_floater(victim.pos, "блок", Color(0.6, 0.85, 1.0))
	_floater(victim.pos, "-%d" % int(dmg), Color(1.0, 0.35, 0.3) if victim.custom_data.get("battle_team", "") == "player" else Color(1.0, 0.9, 0.4))
	attacker.add_work_xp("combat_training", 0.05)
	if was_alive and (not victim.is_alive or victim.health <= 0.0):
		var side = String(attacker.custom_data.get("battle_team", "player"))
		kills[side] = int(kills.get(side, 0)) + 1
		_feed("%s  ⚔  %s  (%s)" % [attacker.name, victim.name, String(stats.get("weapon_name", ""))], Color(0.6, 0.85, 1.0) if side == "player" else Color(1.0, 0.55, 0.45))

# Король бьёт врага (E / ПКМ по врагу) — тот же расчёт урона
func ruler_strike(ruler: CitizenNPC, victim: CitizenNPC) -> void:
	var stats = ruler.get_combat_stats()
	_strike(ruler, victim, stats, bool(stats.get("is_ranged", false)))

var feed_box: VBoxContainer = null

func _feed(text: String, color: Color) -> void:
	if feed_box == null:
		return
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		var old = feed_box.get_child(0)
		feed_box.remove_child(old)
		old.queue_free()

func _floater(pos: Vector2, text: String, color: Color) -> void:
	floaters.append({"pos": pos + Vector2(randf_range(-3, 3), -10), "text": text, "t": 0.0, "color": color})

func _check_end() -> void:
	var p_alive = _alive(player_team).size()
	var e_alive = _alive(enemy_team).size()
	if p_alive > 0 and e_alive > 0:
		return
	finished = true
	for c in player_team + enemy_team:
		if c.is_alive:
			c.state = CitizenNPC.State.CELEBRATING
	var won = e_alive == 0 and p_alive > 0
	center_lbl.text = "ПОБЕДА!" if won else "ПОРАЖЕНИЕ"
	center_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if won else Color(1.0, 0.4, 0.35))
	end_panel.get_node("VBox/Result").text = "Выжило ваших: %d · врагов: %d\nВы сразили: %d · потеряли: %d" % [p_alive, e_alive, int(kills["player"]), int(kills["enemy"])]
	end_panel.visible = true

func _update_score() -> void:
	if score_lbl:
		score_lbl.text = "⚔  Ваше племя: %d / %d      Чёрный Волк: %d / %d" % [_alive(player_team).size(), player_team.size(), _alive(enemy_team).size(), enemy_team.size()]

# --- ОТРИСОВКА: стрелы и цифры урона поверх карты ---
func _draw() -> void:
	for a in arrows:
		var k = clampf(a["t"] / a["dur"], 0.0, 1.0)
		var p = a["from"].lerp(a["to"], k) + Vector2(0, -sin(k * PI) * 8.0)
		var dir = (a["to"] - a["from"]).normalized()
		draw_line(p - dir * 4.0, p, Color(0.35, 0.22, 0.1), 1.0, true)
		draw_circle(p, 0.7, Color(0.85, 0.85, 0.85))
	var font = ThemeDB.fallback_font
	var cam = get_viewport().get_camera_2d()
	var inv = 1.0 / maxf(0.5, cam.zoom.x if cam else 1.0)
	for f in floaters:
		var k = f["t"] / 1.1
		var col: Color = f["color"]
		col.a = 1.0 - k * k
		var at: Vector2 = f["pos"] + Vector2(0, -k * 10.0)
		draw_set_transform(at, 0.0, Vector2(inv, inv))
		var w = font.get_string_size(f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(font, Vector2(-w * 0.5, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, col.a))
		draw_string(font, Vector2(-w * 0.5, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Метки команд над головами: синие свои, красные враги
	for c in player_team + enemy_team:
		if c.is_alive and c.health > 0.0:
			var col = Color(0.35, 0.65, 1.0) if c.custom_data.get("battle_team", "") == "player" else Color(1.0, 0.35, 0.3)
			var hp = clampf(c.health / maxf(1.0, c.max_health), 0.0, 1.0)
			var base = c.pos + Vector2(-5, -14)
			draw_rect(Rect2(base, Vector2(10, 1.6)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(base, Vector2(10 * hp, 1.6)), col)

# --- ИНТЕРФЕЙС БОЯ ---
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 20
	add_child(hud)
	var top = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.05, 0.9)
	st.border_color = Color(0.95, 0.7, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	top.add_theme_stylebox_override("panel", st)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -260
	top.offset_right = 260
	top.offset_top = 90
	hud.add_child(top)
	score_lbl = Label.new()
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 18)
	top.add_child(score_lbl)
	center_lbl = Label.new()
	center_lbl.anchor_left = 0.0
	center_lbl.anchor_right = 1.0
	center_lbl.anchor_top = 0.3
	center_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_lbl.add_theme_font_size_override("font_size", 56)
	center_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	center_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	center_lbl.add_theme_constant_override("outline_size", 10)
	center_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(center_lbl)
	end_panel = PanelContainer.new()
	end_panel.add_theme_stylebox_override("panel", st)
	end_panel.anchor_left = 0.5
	end_panel.anchor_right = 0.5
	end_panel.anchor_top = 0.5
	end_panel.anchor_bottom = 0.5
	end_panel.offset_left = -220
	end_panel.offset_right = 220
	end_panel.offset_top = -10
	end_panel.offset_bottom = 120
	end_panel.visible = false
	hud.add_child(end_panel)
	var vb = VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 10)
	end_panel.add_child(vb)
	var res = Label.new()
	res.name = "Result"
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.add_theme_font_size_override("font_size", 16)
	vb.add_child(res)
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var again = Button.new()
	again.text = "⚔ Ещё бой"
	again.custom_minimum_size = Vector2(150, 40)
	again.pressed.connect(func(): BattleTest.start_from_menu(get_tree()))
	hb.add_child(again)
	var menu = Button.new()
	menu.text = "В меню"
	menu.custom_minimum_size = Vector2(150, 40)
	menu.pressed.connect(func():
		GameManager.battle_test_mode = false
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn"))
	hb.add_child(menu)
	var hint = Label.new()
	hint.text = "Вы — Король в строю. WASD — идти, Пробел — прыжок, ЛКМ — удар, Q — блок, Shift — перекат (уклон), E/ПКМ по врагу — атаковать. V — смотреть со стороны."
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.offset_left = -420
	hint.offset_right = 420
	hint.offset_top = 140
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_constant_override("outline_size", 4)
	hud.add_child(hint)
	feed_box = VBoxContainer.new()
	feed_box.anchor_left = 1.0
	feed_box.anchor_right = 1.0
	feed_box.offset_left = -440
	feed_box.offset_right = -16
	feed_box.offset_top = 90
	feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed_box)

# Запуск из меню (и «Ещё бой»): новый мир с поляной
static func start_from_menu(tree: SceneTree) -> void:
	GameManager.battle_test_mode = true
	GameManager.is_game_active = false
	GameManager.world_seed = "PLN-ARENA-%d" % randi_range(1, 9999)
	GameManager.custom_map_to_play = build_world(GameManager.world_seed)
	tree.change_scene_to_file("res://src/game.tscn")
