class_name HeroController
extends Node

# ==============================================================================
# ПРЯМОЕ УПРАВЛЕНИЕ ВОЖДЁМ (режим «Путь вождя»)
# • WASD / стрелки — ходьба по карте в реальном времени; деревья, камни, вода
#   и стены построек не пропускают (скольжение вдоль препятствия).
# • Пока управляет игрок, ИИ поселения не распоряжается вождём, но голод,
#   силы, холод и выносливость продолжают действовать (settlement.gd).
# • ПКМ (как в Dota 2 / League of Legends): по земле — идти туда по найденному
#   пути, по жителю — подойти и заговорить. Любое нажатие WASD отменяет маршрут.
# • E — заговорить с ближайшим жителем, F — поесть у очага/склада/дома.
# • Жители с неотложным делом сами окликают проходящего мимо вождя.
# ==============================================================================

signal talk_requested(npc: CitizenNPC)

const SPEED_MULT: float = 3.0 # вождь ходит быстрее симуляционного шага жителей: это живой персонаж игрока
const TALK_RANGE: float = 56.0
const CALL_RANGE: float = 110.0
const CALL_SCAN_INTERVAL: float = 1.5

var active: bool = false
var in_dialogue: bool = false
var _call_timer: float = 0.0
# Маршрут по приказу мыши
var click_path: Array[Vector2] = []
var click_path_index: int = 0
var talk_target: CitizenNPC = null
var _repath_timer: float = 0.0

const WAYPOINT_REACHED: float = 4.0
const REPATH_INTERVAL: float = 0.5

func _ready() -> void:
	if not EventBus.hero_move_order.is_connected(order_move):
		EventBus.hero_move_order.connect(order_move)

func _exit_tree() -> void:
	if EventBus.hero_move_order.is_connected(order_move):
		EventBus.hero_move_order.disconnect(order_move)

func cancel_order() -> void:
	click_path.clear()
	click_path_index = 0
	talk_target = null

# Приказ правой кнопкой: идти в точку или подойти к жителю и заговорить
func order_move(world_pos: Vector2, target_citizen: RefCounted = null) -> bool:
	if not active or in_dialogue:
		return false
	var ruler = get_ruler()
	if ruler == null:
		return false
	talk_target = target_citizen as CitizenNPC
	var dest = talk_target.pos if talk_target else world_pos
	if talk_target and ruler.pos.distance_to(dest) <= TALK_RANGE:
		var npc = talk_target
		cancel_order()
		talk_requested.emit(npc)
		return true
	var p: Array[Vector2] = GameManager.nav_grid.find_path(ruler.pos, dest) if GameManager.nav_grid else [dest]
	if p.is_empty():
		cancel_order()
		EventBus.notification_toast.emit("🚫 Не пройти", "Туда нет пути.", "info")
		return false
	click_path = p
	click_path_index = 0
	_repath_timer = REPATH_INTERVAL
	return true

# Шаг по маршруту. Возвращает true, пока вождь идёт.
func follow_path(ruler: CitizenNPC, delta: float) -> bool:
	if talk_target:
		if not talk_target.is_alive:
			cancel_order()
			return false
		if ruler.pos.distance_to(talk_target.pos) <= TALK_RANGE:
			var npc = talk_target
			cancel_order()
			ruler.state = CitizenNPC.State.IDLE
			talk_requested.emit(npc)
			return false
		# Житель движется — путь к нему время от времени пересчитывается
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = REPATH_INTERVAL
			var np: Array[Vector2] = GameManager.nav_grid.find_path(ruler.pos, talk_target.pos) if GameManager.nav_grid else [talk_target.pos]
			if not np.is_empty():
				click_path = np
				click_path_index = 0
	if click_path_index >= click_path.size():
		if not click_path.is_empty():
			click_path.clear()
			ruler.state = CitizenNPC.State.IDLE
		return false
	var wp = click_path[click_path_index]
	var to_wp = wp - ruler.pos
	var step = ruler.get_speed() * SPEED_MULT * delta
	if to_wp.length() <= maxf(step, WAYPOINT_REACHED):
		ruler.pos = wp
		click_path_index += 1
	else:
		ruler.pos += to_wp.normalized() * step
		ruler.facing_dir = to_wp.normalized()
	ruler.state = CitizenNPC.State.MOVING_TO_WORK
	return true

func _get_settlement() -> SettlementData:
	var s = GameManager.get_player_settlement() if GameManager else null
	return s if s is SettlementData else null

func get_ruler() -> CitizenNPC:
	return PlayerHero.get_ruler(_get_settlement())

func set_active(on: bool) -> void:
	active = on
	cancel_order()
	GameManager.hero_control_active = on
	var ruler = get_ruler()
	if ruler == null:
		return
	ruler.custom_data["player_controlled"] = on
	# Вождь бросает дела ИИ: игрок сам решает, куда идти
	ruler._clear_reservations()
	ruler.path.clear()
	ruler.path_index = 0
	ruler.task_id = ""
	ruler.target_id = ""
	ruler.state = CitizenNPC.State.IDLE
	ruler.decision_cooldown = 0.5
	ruler.last_status_reason = "Под вашим управлением" if on else "Вернулся к делам племени"

# Проходима ли точка мира для вождя
func _is_walkable_at(world_pos: Vector2) -> bool:
	if GameManager.nav_grid == null:
		return true
	return GameManager.nav_grid.is_tile_walkable(GameManager.nav_grid.world_to_tile(world_pos))

func get_move_input() -> Vector2:
	var focused = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused is LineEdit or focused is TextEdit:
		return Vector2.ZERO
	var v = Vector2.ZERO
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1.0
	return v.normalized()

# Шаг движения с учётом препятствий. Возвращает true, если вождь сдвинулся.
func move_ruler(ruler: CitizenNPC, dir: Vector2, delta: float) -> bool:
	if dir == Vector2.ZERO:
		if ruler.state == CitizenNPC.State.MOVING_TO_WORK:
			ruler.state = CitizenNPC.State.IDLE
		return false
	var step = dir * ruler.get_speed() * SPEED_MULT * delta
	var start_blocked = not _is_walkable_at(ruler.pos) # застрял на непроходимой клетке — даём выйти
	var moved = false
	for axis_step in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		if axis_step == Vector2.ZERO:
			continue
		var target = ruler.pos + axis_step
		if start_blocked or _is_walkable_at(target):
			ruler.pos = target
			moved = true
	ruler.facing_dir = dir
	ruler.state = CitizenNPC.State.MOVING_TO_WORK if moved else CitizenNPC.State.IDLE
	return moved

func find_nearest_npc(ruler: CitizenNPC, max_dist: float = TALK_RANGE) -> CitizenNPC:
	var s = _get_settlement()
	if s == null:
		return null
	var best: CitizenNPC = null
	var best_d = max_dist
	for c in s.population.citizens:
		if c == ruler or not c.is_alive or c.state == CitizenNPC.State.SLEEPING:
			continue
		var d = c.pos.distance_to(ruler.pos)
		if d <= best_d:
			best_d = d
			best = c
	return best

func try_talk() -> CitizenNPC:
	var ruler = get_ruler()
	if ruler == null or in_dialogue:
		return null
	var npc = find_nearest_npc(ruler)
	if npc == null:
		EventBus.notification_toast.emit("💬 Рядом никого", "Подойдите ближе к жителю, чтобы заговорить (E).", "info")
		return null
	talk_requested.emit(npc)
	return npc

func try_eat() -> Dictionary:
	var s = _get_settlement()
	var ruler = get_ruler()
	if s == null or ruler == null:
		return {"ok": false, "reason": ""}
	var res = s.hero_eat(ruler)
	EventBus.notification_toast.emit("🍖 Еда", res["reason"], "good" if res["ok"] else "info")
	return res

# Жители окликают вождя, если у них неотложное дело
func scan_calls() -> void:
	var s = _get_settlement()
	var ruler = get_ruler()
	if s == null or ruler == null:
		return
	for c in s.population.citizens:
		if c == ruler or not c.is_alive or c.state in [CitizenNPC.State.SLEEPING, CitizenNPC.State.TALKING]:
			continue
		if c.pos.distance_to(ruler.pos) > CALL_RANGE:
			continue
		var line = NPCDialogue.get_urgent_call(s, c, ruler)
		if line != "":
			c.facing_dir = (ruler.pos - c.pos).normalized()
			c.shout(line, 3.5)
			c.show_emote("question", 3.5, 4, true)

func _process(delta: float) -> void:
	if not active or GameManager.is_paused:
		return
	var ruler = get_ruler()
	if ruler == null:
		return
	if not in_dialogue:
		var dir = get_move_input()
		if dir != Vector2.ZERO:
			cancel_order() # WASD перебивает приказ мышью
			move_ruler(ruler, dir, delta)
		elif not click_path.is_empty() or talk_target:
			follow_path(ruler, delta)
		else:
			move_ruler(ruler, Vector2.ZERO, delta)
	_call_timer -= delta
	if _call_timer <= 0.0:
		_call_timer = CALL_SCAN_INTERVAL
		scan_calls()
