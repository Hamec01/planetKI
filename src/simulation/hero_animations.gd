class_name HeroAnimations
extends RefCounted

# ==============================================================================
# АНИМАЦИИ КОРОЛЯ
# ------------------------------------------------------------------------------
# Лист кадров: art/hero/king_sheet.png — 16 колонок × 15 рядов, клетка 64×36,
# фон вырезан (скрипт нарезки: art/hero/cut_king_sheet.py). Кадры нумеруются
# слева направо, сверху вниз (0..239). Боковые кадры (ходьба, работа, удар)
# смотрят вправо — влево отражаются.
#
# Все действия Короля вызывают play(ruler, <действие>): записывается действие,
# время начала и окончания в custom_data. Отрисовщик (world_map_view.gd)
# вызывает draw_king(...) и получает нужный кадр: разовое действие проигрывается
# за своё время, потом — ходьба/покой/разговор/отдых по состоянию.
# Логика игры от анимаций не зависит.
# ==============================================================================

const SHEET_PATHS: Array[String] = ["res://Assets/hero/king_sheet.png", "res://art/hero/king_sheet.png"]
const CELL: Vector2 = Vector2(64.0, 36.0)
const COLS: int = 16
# Размер Короля в мире: высота клетки листа (персонаж ~27 из 36 px -> ~11.5 px мира, чуть выше жителей)
const WORLD_CELL_H: float = 15.5
const FOOT_Y: float = 33.0 # где в клетке стоят ноги (px)

static func _range(a: int, b: int) -> Array:
	var r: Array = []
	for i in range(a, b + 1):
		r.append(i)
	return r

# id действия -> кадры листа, длительность разового проигрыша (сек), цикл
const ACTIONS: Dictionary = {
	"idle": {"desc": "Стоит, дышит, моргает", "duration": 0.0},
	"walk": {"desc": "Идёт", "duration": 0.0},
	"chop": {"desc": "Замах и удар топором по стволу", "duration": 1.6},
	"mine": {"desc": "Удар кайлом по породе", "duration": 1.8},
	"gather": {"desc": "Наклон и сбор ягод/грибов", "duration": 1.2},
	"pick_flowers": {"desc": "Присесть и сорвать цветы", "duration": 0.8},
	"fish": {"desc": "Заброс и удочка у воды", "duration": 3.0},
	"butcher": {"desc": "Разделка туши тесаком", "duration": 1.5},
	"eat": {"desc": "Ест", "duration": 1.5},
	"rest": {"desc": "Присел отдохнуть", "duration": 2.0},
	"build": {"desc": "Работа молотом на стройке", "duration": 1.5},
	"deposit": {"desc": "Выгружает сумку у склада", "duration": 1.0},
	"talk": {"desc": "Разговаривает, жестикулирует", "duration": 0.0},
	"give": {"desc": "Протягивает подарок", "duration": 1.0},
	"attack": {"desc": "Удар (кулак или оружие с росчерком)", "duration": 0.8},
	"hit": {"desc": "Получил удар", "duration": 0.4},
	"death": {"desc": "Падает", "duration": 2.0}
}

static var FRAMES: Dictionary = {
	"idle": _range(16, 25),
	"walk": _range(0, 11),
	"punch": _range(26, 35),
	"chop": _range(37, 47),
	"mine": _range(48, 57),
	"gather": _range(65, 71),
	"pick_flowers": _range(65, 71),
	"fish": _range(77, 84),
	"butcher": _range(85, 97),
	"build": _range(98, 109),
	"eat": _range(110, 119),
	"deposit": _range(136, 142),
	"rest": _range(138, 148),
	"talk": _range(152, 167),
	"give": _range(168, 179),
	"attack": _range(196, 207),
	"hit": _range(208, 213),
	"death": _range(218, 221)
}
# Скорость циклов (кадров/сек)
const LOOP_FPS: Dictionary = {"idle": 5.0, "walk": 14.0, "talk": 7.0, "rest": 4.0, "fish": 4.0}
# Боковые анимации (отражаются при взгляде влево)
const SIDE_VIEW: Array[String] = ["walk", "punch", "chop", "mine", "fish", "butcher", "build", "attack", "gather", "pick_flowers", "give", "talk"]

static var _sheet: Texture2D = null
static var _sheet_tried: bool = false

static func _now() -> float:
	return float(GameManager.sim_time_total) if GameManager else 0.0

static func play(c: CitizenNPC, action_id: String, duration: float = -1.0) -> void:
	if c == null or not ACTIONS.has(action_id):
		return
	var dur = float(ACTIONS[action_id]["duration"]) if duration < 0.0 else duration
	c.custom_data["anim_action"] = action_id
	c.custom_data["anim_start"] = _now()
	c.custom_data["anim_until"] = _now() + dur

static func current(c: CitizenNPC) -> String:
	return String(c.custom_data.get("anim_action", "idle")) if c else "idle"

# Лист кадров: импортированный ресурс, а если проект ещё не импортирован — прямо из PNG
static func get_sheet() -> Texture2D:
	if _sheet_tried:
		return _sheet
	_sheet_tried = true
	for path in SHEET_PATHS:
		if ResourceLoader.exists(path):
			_sheet = load(path)
			if _sheet:
				return _sheet
		var abs_path = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img = Image.load_from_file(abs_path)
			if img:
				_sheet = ImageTexture.create_from_image(img)
				return _sheet
	return null

# Какая анимация и какой кадр сейчас: {"anim": id, "frame": номер кадра листа}
static func resolve_frame(c: CitizenNPC, loop_time: float) -> Dictionary:
	var anim = "idle"
	var frame_i = 0
	var now = _now()
	var act = current(c)
	var until = float(c.custom_data.get("anim_until", -1.0))
	if not c.is_alive:
		anim = "death"
		return {"anim": anim, "frame": FRAMES["death"][FRAMES["death"].size() - 1]}
	if act in FRAMES and act not in ["idle", "walk", "talk", "rest"] and now < until:
		anim = act
		if anim == "attack" and String(c.equipment.get("weapon", "unarmed")) in ["", "unarmed"]:
			anim = "punch"
		var start = float(c.custom_data.get("anim_start", until - float(ACTIONS[act]["duration"])))
		var t = clampf((now - start) / maxf(0.05, until - start), 0.0, 0.999)
		var frames: Array = FRAMES[anim]
		frame_i = frames[int(t * frames.size())]
		return {"anim": anim, "frame": frame_i}
	# Циклы по состоянию
	match c.state:
		CitizenNPC.State.MOVING_TO_WORK, CitizenNPC.State.CARRYING, CitizenNPC.State.GOING_HOME, CitizenNPC.State.FLEEING, CitizenNPC.State.FLEEING_HOME:
			anim = "walk"
		CitizenNPC.State.TALKING:
			anim = "talk"
		CitizenNPC.State.RESTING, CitizenNPC.State.SLEEPING, CitizenNPC.State.MOURNING:
			anim = "rest"
		CitizenNPC.State.EATING:
			anim = "eat"
		_:
			anim = "idle"
	if anim == "idle" and not c.path.is_empty():
		anim = "walk"
	var loop_frames: Array = FRAMES[anim]
	var fps = float(LOOP_FPS.get(anim, 8.0))
	frame_i = loop_frames[int(loop_time * fps + float(c.seed_val % 7)) % loop_frames.size()]
	return {"anim": anim, "frame": frame_i}

# Рисует Короля кадром из листа. Возвращает false, если листа нет (тогда рисуется обычный портрет).
static func draw_king(canvas: CanvasItem, c: CitizenNPC, loop_time: float) -> bool:
	var tex = get_sheet()
	if tex == null:
		return false
	var fr = resolve_frame(c, loop_time)
	var idx: int = fr["frame"]
	var src = Rect2(Vector2(float(idx % COLS) * CELL.x, float(idx / COLS) * CELL.y), CELL)
	var scale = WORLD_CELL_H / CELL.y
	var size = CELL * scale
	var flip = c.facing_dir.x < -0.1 and String(fr["anim"]) in SIDE_VIEW
	var origin = c.pos
	var rect = Rect2(Vector2(-size.x * 0.5, -FOOT_Y * scale), size)
	canvas.draw_set_transform(origin, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	canvas.draw_texture_rect_region(tex, rect, src)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
