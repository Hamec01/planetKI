class_name HeroAnimations
extends RefCounted

# ==============================================================================
# МЕСТО ДЛЯ АНИМАЦИЙ КОРОЛЯ (Режим Короля)
# ------------------------------------------------------------------------------
# ⚠ АНИМАЦИЙ ПОКА НЕТ. Для каждого действия ниже в будущем нужна своя анимация
#   персонажа игрока (отдельный набор кадров для героя, не общий с жителями).
#
# Все действия Короля уже вызывают play(ruler, <действие>). Сейчас play() только
# записывает текущее действие в ruler.custom_data["anim_action"] и время его
# окончания в ["anim_until"], чтобы отрисовщик (world_map_view.gd,
# _draw_single_citizen_body) мог взять оттуда нужную анимацию, когда кадры
# появятся. Логика игры от анимаций не зависит.
# ==============================================================================

# id действия -> что должна показывать будущая анимация и сколько она длится (сек)
const ACTIONS: Dictionary = {
	"idle": {"desc": "Стоит, дышит, оглядывается", "duration": 0.0},
	"walk": {"desc": "Идёт (цикл шага в 4 направлениях)", "duration": 0.0},
	"chop": {"desc": "Замах и удар топором по стволу", "duration": 1.6},
	"mine": {"desc": "Удар кайлом/камнем по породе", "duration": 1.8},
	"gather": {"desc": "Наклон и сбор ягод/грибов в ладонь", "duration": 1.2},
	"pick_flowers": {"desc": "Присесть и сорвать цветы", "duration": 0.8},
	"fish": {"desc": "Заброс и вытягивание снасти у воды", "duration": 3.0},
	"butcher": {"desc": "Разделка туши ножом на коленях", "duration": 1.5},
	"eat": {"desc": "Ест у очага или из сумки", "duration": 1.5},
	"rest": {"desc": "Садится/ложится отдохнуть дома", "duration": 2.0},
	"build": {"desc": "Работа молотом/брёвнами на стройке", "duration": 1.5},
	"deposit": {"desc": "Выгружает сумку у склада", "duration": 1.0},
	"talk": {"desc": "Разговаривает, жестикулирует", "duration": 0.0},
	"give": {"desc": "Протягивает подарок", "duration": 1.0},
	"attack": {"desc": "Удар оружием (свой набор для кулаков, топора, копья, лука)", "duration": 0.8},
	"hit": {"desc": "Получил удар: отшатнулся", "duration": 0.4},
	"death": {"desc": "Падение и смерть", "duration": 2.0}
}

static func play(c: CitizenNPC, action_id: String, duration: float = -1.0) -> void:
	if c == null or not ACTIONS.has(action_id):
		return
	var dur = float(ACTIONS[action_id]["duration"]) if duration < 0.0 else duration
	c.custom_data["anim_action"] = action_id
	c.custom_data["anim_until"] = (float(GameManager.sim_time_total) if GameManager else 0.0) + dur

static func current(c: CitizenNPC) -> String:
	return String(c.custom_data.get("anim_action", "idle")) if c else "idle"
