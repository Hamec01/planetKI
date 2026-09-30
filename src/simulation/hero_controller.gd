class_name HeroController
extends Node

# ==============================================================================
# РЕЖИМ КОРОЛЯ: ПРЯМОЕ УПРАВЛЕНИЕ ПРАВИТЕЛЕМ, КАК В DOTA 2 / LEAGUE OF LEGENDS
# ------------------------------------------------------------------------------
# ПКМ — всё: по земле идти, по жителю заговорить, по дереву рубить, по камню
# добывать, по кусту/грибам собирать, по цветам сорвать, по рыбному месту
# рыбачить, по зверю бить, по туше разделывать, по очагу поесть из общего котла,
# по складу сдать сумку, по своему дому отдохнуть, по стройке — помочь строить.
# Каждое действие даёт опыт героя (уровни -> очки характеристик и навыков) и
# вызывает HeroAnimations.play(...) — место для будущих анимаций.
# WASD — идти (перебивает приказ), E — заговорить с ближайшим.
# Пока управляет игрок, ИИ поселения не распоряжается Королём, но голод, силы,
# холод и выносливость действуют. Добытое идёт в личную сумку (PlayerHero.bag).
# Мир реагирует на поступки: RulerDeeds (свидетели, родня, стража, совет).
# ==============================================================================

signal talk_requested(npc: CitizenNPC)

const SPEED_MULT: float = 3.0 # Король — живой персонаж игрока, ходит быстрее шага симуляции жителей
const TALK_RANGE: float = 56.0
const CALL_RANGE: float = 110.0
const CALL_SCAN_INTERVAL: float = 1.5
const WAYPOINT_REACHED: float = 4.0
const REPATH_INTERVAL: float = 0.5

# Дальность и темп действий
const ACTION_RANGE: Dictionary = {
	"chop": 34.0, "mine": 34.0, "gather": 30.0, "flowers": 26.0, "carcass": 26.0,
	"hearth": 44.0, "storage": 44.0, "animal": 30.0, "attack_citizen": 28.0,
	"fish": 34.0, "home": 40.0, "build": 40.0
}
const WORK_INTERVAL: Dictionary = {"chop": 1.6, "mine": 1.8, "gather": 1.2, "flowers": 0.8, "carcass": 1.5, "fish": 3.0, "home": 2.0, "build": 1.5}
# Опыт героя за действия (уровень -> +3 очка характеристик и +1 очко навыка)
const XP_REWARDS: Dictionary = {
	"chop": 1.0, "mine": 1.0, "gather": 0.5, "fish": 1.5, "flowers": 0.5,
	"carcass": 2.0, "deposit": 2.0, "build": 2.0, "hearth": 0.0
}
const XP_REASONS: Dictionary = {
	"chop": "Рубка леса", "mine": "Добыча камня", "gather": "Сбор даров леса", "fish": "Рыбалка",
	"flowers": "Сбор цветов", "carcass": "Разделка добычи", "deposit": "Добыча сдана на склад", "build": "Работа на стройке"
}

func _award(s: SettlementData, kind: String, mult: float = 1.0) -> void:
	var amount = float(XP_REWARDS.get(kind, 0.0)) * mult
	if amount > 0.0 and s.hero:
		s.hero.add_xp(s, amount, String(XP_REASONS.get(kind, "Дела Короля")))
const WORK_STAMINA: float = 4.0
const FIGHT_DISENGAGE: float = 260.0
const FLEE_SPEED_MULT: float = 1.6

var active: bool = false
var in_dialogue: bool = false
var _call_timer: float = 0.0
# Маршрут по приказу мыши
var click_path: Array[Vector2] = []
var click_path_index: int = 0
var talk_target: CitizenNPC = null
var _repath_timer: float = 0.0
# Текущее действие: {"kind", цель, "timer"}
var action: Dictionary = {}
# Драка с соплеменниками: жертва, заступники, сбежавшие
var fight_victim: CitizenNPC = null
var fight_victim_fights: bool = false
var fight_defenders: Array[CitizenNPC] = []
var _fight_timers: Dictionary = {} # citizen_id -> таймер удара по Королю

func _ready() -> void:
	if not EventBus.hero_move_order.is_connected(order_move):
		EventBus.hero_move_order.connect(order_move)
	if not EventBus.hero_interact_order.is_connected(order_interact):
		EventBus.hero_interact_order.connect(order_interact)

func _exit_tree() -> void:
	if EventBus.hero_move_order.is_connected(order_move):
		EventBus.hero_move_order.disconnect(order_move)
	if EventBus.hero_interact_order.is_connected(order_interact):
		EventBus.hero_interact_order.disconnect(order_interact)

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
	# Король бросает дела ИИ: игрок сам решает, куда идти
	ruler._clear_reservations()
	ruler.path.clear()
	ruler.path_index = 0
	ruler.task_id = ""
	ruler.target_id = ""
	ruler.state = CitizenNPC.State.IDLE
	ruler.decision_cooldown = 0.5
	ruler.last_status_reason = "Под вашим управлением" if on else "Вернулся к делам племени"

func cancel_order() -> void:
	click_path.clear()
	click_path_index = 0
	talk_target = null
	cancel_action()

func cancel_action() -> void:
	var s = _get_settlement()
	if s and action.get("kind", "") in ["chop", "mine", "gather"] and GameManager.resource_manager:
		var ruler = get_ruler()
		if ruler:
			GameManager.resource_manager.release_node(action.get("coord", Vector2i(-1, -1)), ruler.citizen_id)
	action = {}
	end_fight()

# --- МАРШРУТ ---

func _set_path_to(ruler: CitizenNPC, dest: Vector2, solid_tile: Vector2i = Vector2i(-1, -1)) -> bool:
	var p: Array[Vector2] = []
	if GameManager.nav_grid == null:
		p = [dest]
	elif solid_tile != Vector2i(-1, -1):
		p = GameManager.nav_grid.find_adjacent_path(ruler.pos, solid_tile)
	else:
		p = GameManager.nav_grid.find_path(ruler.pos, dest)
	if p.is_empty():
		return false
	click_path = p
	click_path_index = 0
	_repath_timer = REPATH_INTERVAL
	return true

# ПКМ по земле или жителю (разговор)
func order_move(world_pos: Vector2, target_citizen: RefCounted = null) -> bool:
	if not active or in_dialogue:
		return false
	var ruler = get_ruler()
	if ruler == null:
		return false
	cancel_order()
	talk_target = target_citizen as CitizenNPC
	var dest = talk_target.pos if talk_target else world_pos
	if talk_target and ruler.pos.distance_to(dest) <= TALK_RANGE:
		var npc = talk_target
		cancel_order()
		talk_requested.emit(npc)
		return true
	if not _set_path_to(ruler, dest):
		cancel_order()
		EventBus.notification_toast.emit("🚫 Не пройти", "Туда нет пути.", "info")
		return false
	return true

# ПКМ по объекту: target = {"kind": ..., + данные цели}
func order_interact(world_pos: Vector2, target: Dictionary) -> bool:
	var kind = String(target.get("kind", "ground"))
	if kind == "ground":
		return order_move(world_pos)
	if kind == "citizen":
		return order_move(world_pos, target.get("ref", null))
	if not active or in_dialogue:
		return false
	var ruler = get_ruler()
	if ruler == null:
		return false
	cancel_order()
	action = target.duplicate()
	action["timer"] = 0.0
	var pos = _action_target_pos()
	if pos == null:
		action = {}
		return false
	if ruler.pos.distance_to(pos) > float(ACTION_RANGE.get(kind, 30.0)):
		var solid = action.get("coord", Vector2i(-1, -1)) if kind in ["chop", "mine"] else Vector2i(-1, -1)
		if not _set_path_to(ruler, pos, solid):
			action = {}
			EventBus.notification_toast.emit("🚫 Не подойти", "К цели нет пути.", "info")
			return false
	return true

# Нападение на соплеменника (из разговора)
func order_attack_citizen(victim: CitizenNPC) -> bool:
	if victim == null or not victim.is_alive or victim.is_ruler:
		return false
	return order_interact(victim.pos, {"kind": "attack_citizen", "ref": victim})

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
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_set_path_to(ruler, talk_target.pos)
	if click_path_index >= click_path.size():
		if not click_path.is_empty():
			click_path.clear()
			ruler.state = CitizenNPC.State.IDLE
		return false
	var wp = click_path[click_path_index]
	var to_wp = wp - ruler.pos
	var step = ruler.get_speed() * SPEED_MULT * delta
	HeroAnimations.play(ruler, "walk")
	if to_wp.length() <= maxf(step, WAYPOINT_REACHED):
		ruler.pos = wp
		click_path_index += 1
	else:
		ruler.pos += to_wp.normalized() * step
		ruler.facing_dir = to_wp.normalized()
	ruler.state = CitizenNPC.State.MOVING_TO_WORK
	return true

# --- ДЕЙСТВИЯ ---

# Где сейчас цель действия (null — цели больше нет)
func _action_target_pos():
	var kind = String(action.get("kind", ""))
	var s = _get_settlement()
	match kind:
		"chop", "mine", "gather", "fish":
			var node = GameManager.resource_manager.nodes.get(action.get("coord", Vector2i(-1, -1)), {}) if GameManager.resource_manager else {}
			if node.is_empty() or node.get("depleted", false):
				return null
			return node["pos"]
		"flowers":
			var c: Vector2i = action.get("coord", Vector2i(-1, -1))
			return GameManager.nav_grid.tile_to_world_center(c) if GameManager.nav_grid else Vector2(c.x * 32 + 16, c.y * 32 + 16)
		"carcass":
			var carc = GameManager.wildlife_manager.carcasses.get(action.get("id", ""), {}) if GameManager.wildlife_manager else {}
			return carc.get("pos", null) if not carc.is_empty() else null
		"animal":
			var a = GameManager.wildlife_manager.animals.get(action.get("id", ""), null) if GameManager.wildlife_manager else null
			return a.pos if a and a.is_alive() else null
		"attack_citizen":
			var v: CitizenNPC = action.get("ref", null)
			return v.pos if v and v.is_alive else null
		"hearth":
			return s._get_hearth_pos() if s else null
		"storage":
			var ruler = get_ruler()
			return s._get_storage_pos(ruler) if s and ruler else null
		"home":
			var ruler_h = get_ruler()
			return ruler_h.home_pos if ruler_h and ruler_h.home_id != "" and ruler_h.home_pos != Vector2.ZERO else null
		"build":
			var bc: Vector2i = action.get("coord", Vector2i(-1, -1))
			if GameManager.tile_buildings.has(bc) and GameManager.tile_buildings[bc].get("status", "") == "constructing":
				return GameManager.nav_grid.tile_to_world_center(bc) if GameManager.nav_grid else Vector2(bc.x * 32 + 16, bc.y * 32 + 16)
			return null
	return null

func _tick_action(ruler: CitizenNPC, delta: float) -> void:
	var kind = String(action.get("kind", ""))
	var target_pos = _action_target_pos()
	if target_pos == null:
		if kind == "animal" and action.has("carcass_id"):
			# Зверь повержен — Король сразу разделывает тушу
			action = {"kind": "carcass", "id": action["carcass_id"], "timer": 0.0}
			return
		cancel_action()
		ruler.state = CitizenNPC.State.IDLE
		return
	var reach = float(ACTION_RANGE.get(kind, 30.0))
	if ruler.pos.distance_to(target_pos) > reach:
		# Цель движется (зверь, соплеменник) — путь пересчитывается
		if kind in ["animal", "attack_citizen"]:
			if ruler.pos.distance_to(target_pos) > FIGHT_DISENGAGE and kind == "attack_citizen" and action.get("started", false):
				EventBus.notification_toast.emit("⚔ Драка окончена", "Король отступил.", "info")
				cancel_action()
				return
			_repath_timer -= delta
			if _repath_timer <= 0.0 or click_path_index >= click_path.size():
				_set_path_to(ruler, target_pos)
		elif click_path_index >= click_path.size():
			var solid = action.get("coord", Vector2i(-1, -1)) if kind in ["chop", "mine"] else Vector2i(-1, -1)
			if not _set_path_to(ruler, target_pos, solid):
				cancel_action()
				return
		follow_path(ruler, delta)
		return
	click_path.clear()
	ruler.facing_dir = (target_pos - ruler.pos).normalized() if target_pos != ruler.pos else ruler.facing_dir
	action["timer"] = float(action.get("timer", 0.0)) - delta
	if float(action["timer"]) > 0.0:
		return
	perform_action_step(ruler)

# Один шаг действия у цели (удар топором, взмах кайлом, горсть ягод, удар в бою...)
func perform_action_step(ruler: CitizenNPC) -> void:
	var s = _get_settlement()
	var hero: PlayerHero = s.hero
	var kind = String(action.get("kind", ""))
	match kind:
		"chop", "mine", "gather", "fish":
			_work_node(s, hero, ruler, kind)
		"home":
			_rest_at_home(s, ruler)
		"build":
			_help_build(s, ruler)
		"flowers":
			_pick_flowers(s, hero, ruler)
		"carcass":
			_butcher(s, hero, ruler)
		"hearth":
			HeroAnimations.play(ruler, "eat")
			var res = s.hero_eat(ruler)
			EventBus.notification_toast.emit("🍖 Общий очаг", res["reason"], "good" if res["ok"] else "info")
			cancel_action()
			ruler.state = CitizenNPC.State.IDLE
		"storage":
			HeroAnimations.play(ruler, "deposit")
			var res = hero.deposit_bag(s)
			if res["ok"]:
				_award(s, "deposit")
			EventBus.notification_toast.emit("📦 Склад", res["reason"], "good" if res["ok"] else "info")
			cancel_action()
			ruler.state = CitizenNPC.State.IDLE
		"animal":
			_strike_animal(s, hero, ruler)
		"attack_citizen":
			_strike_citizen(s, ruler)

func _work_node(s: SettlementData, hero: PlayerHero, ruler: CitizenNPC, kind: String) -> void:
	var coord: Vector2i = action.get("coord", Vector2i(-1, -1))
	var node: Dictionary = GameManager.resource_manager.nodes.get(coord, {})
	if node.is_empty():
		cancel_action()
		return
	var item = "berries"
	if node["category"] == "fish":
		item = "fish"
	elif node["category"] == "wood":
		item = "wood"
	elif node["category"] in ["stone", "metal"]:
		item = "stone" if node["category"] == "stone" else "metal"
	if hero.is_bag_full(s, item):
		EventBus.notification_toast.emit("🎒 Сумка полна", "Сдайте добычу на склад (ПКМ по складу) или съешьте еду.", "warning")
		cancel_action()
		ruler.state = CitizenNPC.State.IDLE
		return
	if ruler.stamina_current < WORK_STAMINA:
		ruler.state = CitizenNPC.State.RESTING
		action["timer"] = 1.0
		ruler.last_status_reason = "Выбился из сил, переводит дух"
		return
	action["timer"] = float(WORK_INTERVAL.get(kind, 1.5))
	ruler.stamina_current = maxf(0.0, ruler.stamina_current - WORK_STAMINA)
	ruler.state = CitizenNPC.State.WORKING
	var weapon = String(ruler.equipment.get("weapon", "unarmed"))
	var tool_mult = 1.0
	var amount = 4.0
	if kind == "chop":
		tool_mult = 1.0 if weapon.contains("axe") else 0.5 # голыми руками дерево не свалить быстро
		amount = 12.5 * ruler.get_vitality_multiplier() * tool_mult
		ruler.add_work_xp("woodcutting", 0.4)
	elif kind == "mine":
		tool_mult = 1.0 if weapon.contains("pick") or weapon.contains("axe") else 0.6
		amount = 4.0 * tool_mult
		ruler.add_work_xp("ore_mining" if item == "metal" else "stone_mining", 0.3)
	else:
		ruler.add_work_xp("gathering", 0.3)
	HeroAnimations.play(ruler, {"chop": "chop", "mine": "mine", "gather": "gather", "fish": "fish"}.get(kind, "gather"))
	amount = minf(amount, (hero.get_bag_capacity(s) - hero.get_bag_weight()) / float(PlayerHero.BAG_ITEMS[item]["weight"]))
	var got = GameManager.resource_manager.harvest_from_node(coord, amount)
	hero.bag_add(s, item, got)
	if got > 0.0:
		_award(s, kind)
	ruler.last_status_reason = "Добывает: %s (+%.1f)" % [PlayerHero.BAG_ITEMS[item]["name"], got]
	var gone = not GameManager.resource_manager.nodes.has(coord) or GameManager.resource_manager.nodes[coord].get("depleted", false)
	if kind == "chop" and gone:
		RulerDeeds.on_tree_felled(s, ruler, coord)
	if gone or got <= 0.0:
		cancel_action()
		ruler.state = CitizenNPC.State.IDLE

func _pick_flowers(s: SettlementData, hero: PlayerHero, ruler: CitizenNPC) -> void:
	var coord: Vector2i = action.get("coord", Vector2i(-1, -1))
	var tiles = GameManager.planet_data.get("tiles", [])
	if coord.y >= 0 and coord.y < tiles.size() and coord.x >= 0 and coord.x < tiles[coord.y].size():
		var nat = String(tiles[coord.y][coord.x].get("nature_object", ""))
		var picked = nat
		if picked == "":
			picked = TileTextureManager.get_nature_name(tiles[coord.y][coord.x]["biome"], coord, tiles[coord.y][coord.x].get("resource", null), "")
		if picked.begins_with("flowers") or picked == "bush_flowers":
			if hero.bag_add(s, "flowers", 1.0) > 0.0:
				HeroAnimations.play(ruler, "pick_flowers")
				tiles[coord.y][coord.x]["nature_object"] = "none" # цветы сорваны — их больше нет на поляне
				_award(s, "flowers")
				ruler.last_status_reason = "Сорвал цветы"
			else:
				EventBus.notification_toast.emit("🎒 Сумка полна", "Некуда положить цветы.", "warning")
	cancel_action()
	ruler.state = CitizenNPC.State.IDLE

func _butcher(s: SettlementData, hero: PlayerHero, ruler: CitizenNPC) -> void:
	var cid = String(action.get("id", ""))
	var free_meat = (hero.get_bag_capacity(s) - hero.get_bag_weight()) / float(PlayerHero.BAG_ITEMS["meat"]["weight"])
	if free_meat <= 0.1:
		EventBus.notification_toast.emit("🎒 Сумка полна", "Туша не поместится. Сдайте добычу на склад.", "warning")
		cancel_action()
		return
	HeroAnimations.play(ruler, "butcher")
	_award(s, "carcass")
	var res = GameManager.wildlife_manager.harvest_carcass(cid, free_meat)
	hero.bag_add(s, "meat", float(res.get("meat", 0.0)))
	var byp: Dictionary = res.get("byproducts", {})
	for k in byp:
		hero.bag_add(s, k, float(byp[k]))
	ruler.add_work_xp("hunting_tracking", 0.4)
	ruler.last_status_reason = "Разделал тушу (+%.1f мяса)" % float(res.get("meat", 0.0))
	action["timer"] = float(WORK_INTERVAL["carcass"])
	if not GameManager.wildlife_manager.carcasses.has(cid):
		cancel_action()
		ruler.state = CitizenNPC.State.IDLE

# Отдых в своём доме: силы и выносливость восстанавливаются, пока Король дома
func _rest_at_home(s: SettlementData, ruler: CitizenNPC) -> void:
	HeroAnimations.play(ruler, "rest")
	action["timer"] = float(WORK_INTERVAL["home"])
	ruler.state = CitizenNPC.State.RESTING
	ruler.energy = minf(100.0, ruler.energy + 10.0)
	ruler.stamina_current = minf(ruler.stamina_max, ruler.stamina_current + 20.0)
	ruler.last_status_reason = "Отдыхает дома"
	if ruler.energy >= 100.0 and ruler.stamina_current >= ruler.stamina_max:
		EventBus.notification_toast.emit("🏠 Дом", "Король отдохнул и полон сил.", "good")
		cancel_action()
		ruler.state = CitizenNPC.State.IDLE

# Помощь на стройке: тот же шаг работы, что у строителя (нужны материалы на площадке)
func _help_build(s: SettlementData, ruler: CitizenNPC) -> void:
	var coord: Vector2i = action.get("coord", Vector2i(-1, -1))
	if ruler.stamina_current < WORK_STAMINA:
		ruler.state = CitizenNPC.State.RESTING
		action["timer"] = 1.0
		return
	var res = s.apply_construction_work(ruler, coord)
	match String(res["result"]):
		"missing_materials":
			EventBus.notification_toast.emit("🔨 Стройка", "На площадке не хватает материалов — строители их ещё не поднесли.", "info")
			cancel_action()
			ruler.state = CitizenNPC.State.IDLE
		"progress":
			HeroAnimations.play(ruler, "build")
			ruler.stamina_current = maxf(0.0, ruler.stamina_current - WORK_STAMINA)
			ruler.state = CitizenNPC.State.WORKING
			action["timer"] = float(WORK_INTERVAL["build"])
			_award(s, "build")
			ruler.last_status_reason = "Строит вместе с родом (осталось %.1f дн.)" % float(GameManager.tile_buildings[coord].get("days_left", 0.0))
		"completed":
			_award(s, "build", 5.0)
			EventBus.notification_toast.emit("🔨 Король достроил", "%s готово — Король сам положил последнее бревно." % res.get("name", "Здание"), "good")
			cancel_action()
			ruler.state = CitizenNPC.State.IDLE
		_:
			cancel_action()

func _strike_animal(s: SettlementData, hero: PlayerHero, ruler: CitizenNPC) -> void:
	var a: WildAnimal = GameManager.wildlife_manager.animals.get(action.get("id", ""), null)
	if a == null or not a.is_alive():
		cancel_action()
		return
	var stats = ruler.get_combat_stats()
	action["timer"] = float(stats["attack_interval"])
	ruler.state = CitizenNPC.State.ATTACKING
	HeroAnimations.play(ruler, "attack", minf(0.8, float(stats["attack_interval"])))
	var atk = stats.duplicate()
	atk["raw_damage"] = float(stats["raw_damage"]) * (1.0 + ruler.beast_damage_bonus) * (0.6 if ruler.is_exhausted() else 1.0)
	var outcome = CombatStatsResolver.resolve_attack(atk, a.get_combat_stats())
	# Зверь понимает, кто на него напал: защищающийся бьёт в ответ, пугливый бежит
	a.target_citizen = ruler
	a.target_threat_pos = ruler.pos
	if not outcome["is_hit"]:
		ruler.last_status_reason = "Промахнулся по зверю"
		return
	var killed = a.take_damage(float(outcome["damage"]), ruler.citizen_id)
	ruler.last_status_reason = "Бьёт зверя (-%d)" % int(outcome["damage"])
	if killed:
		var threat = float(CombatStatsResolver.calculate_animal_stats(a.type_id).get("threat", 0.5))
		hero.add_xp(s, 10.0 + threat * 20.0, "Победа над зверем: %s" % s._get_animal_display_name(a.type_id))
		var carcass = GameManager.wildlife_manager.create_carcass_from_animal(a)
		GameManager.wildlife_manager.animals.erase(a.id)
		action["carcass_id"] = carcass["id"]
		EventBus.notification_toast.emit("🏹 Добыча Короля", "%s повержен. Король разделывает тушу." % s._get_animal_display_name(a.type_id), "good")

# --- ДРАКА С СОПЛЕМЕННИКАМИ ---

func _strike_citizen(s: SettlementData, ruler: CitizenNPC) -> void:
	var victim: CitizenNPC = action.get("ref", null)
	if victim == null or not victim.is_alive:
		cancel_action()
		return
	if not action.get("started", false):
		action["started"] = true
		var reaction = RulerDeeds.on_citizen_assaulted(s, ruler, victim)
		fight_victim = victim
		fight_victim_fights = reaction["victim_fights"]
		fight_defenders = reaction["defenders"]
		victim.custom_data["fighting_ruler"] = true
		for d in fight_defenders:
			d.custom_data["fighting_ruler"] = true
	var stats = ruler.get_combat_stats()
	action["timer"] = float(stats["attack_interval"])
	ruler.state = CitizenNPC.State.ATTACKING
	HeroAnimations.play(ruler, "attack", minf(0.8, float(stats["attack_interval"])))
	var atk = stats.duplicate()
	if ruler.is_exhausted():
		atk["raw_damage"] = float(stats["raw_damage"]) * 0.6
	var outcome = CombatStatsResolver.resolve_attack(atk, victim.get_combat_stats())
	if not outcome["is_hit"]:
		return
	var died = victim.take_damage(float(outcome["damage"]), "Вождь %s" % ruler.name)
	if died:
		RulerDeeds.on_citizen_killed(s, ruler, victim)
		cancel_action()
		ruler.state = CitizenNPC.State.IDLE

# Жертва (если храбра) и заступники бьют Короля; трусливая жертва убегает
func _tick_fight(ruler: CitizenNPC, delta: float) -> void:
	if fight_victim == null:
		return
	if not fight_victim.is_alive and fight_defenders.is_empty():
		end_fight()
		return
	var fighters: Array[CitizenNPC] = []
	if fight_victim.is_alive:
		if fight_victim_fights:
			fighters.append(fight_victim)
		else:
			var away = (fight_victim.pos - ruler.pos).normalized()
			var flee_to = fight_victim.pos + away * fight_victim.get_speed() * FLEE_SPEED_MULT * delta
			if GameManager.nav_grid == null or GameManager.nav_grid.is_tile_walkable(GameManager.nav_grid.world_to_tile(flee_to)):
				fight_victim.pos = flee_to
			fight_victim.state = CitizenNPC.State.FLEEING
			fight_victim.facing_dir = away
	for d in fight_defenders:
		if d.is_alive:
			fighters.append(d)
	for f in fighters:
		var dist = f.pos.distance_to(ruler.pos)
		if dist > FIGHT_DISENGAGE:
			continue
		if dist > 26.0:
			var to_r = (ruler.pos - f.pos).normalized()
			f.pos += to_r * f.get_speed() * SPEED_MULT * 0.8 * delta
			f.facing_dir = to_r
			f.state = CitizenNPC.State.MOVING_TO_WORK
			continue
		f.state = CitizenNPC.State.ATTACKING
		f.facing_dir = (ruler.pos - f.pos).normalized()
		var t = float(_fight_timers.get(f.citizen_id, 0.0)) - delta
		if t <= 0.0:
			var fs = f.get_combat_stats()
			t = float(fs["attack_interval"])
			var out = CombatStatsResolver.resolve_attack(fs, ruler.get_combat_stats())
			if out["is_hit"]:
				HeroAnimations.play(ruler, "hit")
				ruler.take_damage(float(out["damage"]), f.name)
		_fight_timers[f.citizen_id] = t

func end_fight() -> void:
	if fight_victim:
		fight_victim.custom_data.erase("fighting_ruler")
		if fight_victim.is_alive:
			fight_victim.state = CitizenNPC.State.IDLE
	for d in fight_defenders:
		d.custom_data.erase("fighting_ruler")
		if d.is_alive:
			d.state = CitizenNPC.State.IDLE
	fight_victim = null
	fight_defenders.clear()
	_fight_timers.clear()

# --- КЛАВИАТУРА И ОКРУЖЕНИЕ ---

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

# Шаг движения с учётом препятствий. Возвращает true, если Король сдвинулся.
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
	HeroAnimations.play(ruler, "walk" if moved else "idle")
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
		EventBus.notification_toast.emit("💬 Рядом никого", "Подойдите ближе к жителю, чтобы заговорить (E) или кликните по нему ПКМ.", "info")
		return null
	cancel_order()
	talk_requested.emit(npc)
	return npc

# Жители окликают Короля, если у них неотложное дело
func scan_calls() -> void:
	var s = _get_settlement()
	var ruler = get_ruler()
	if s == null or ruler == null:
		return
	for c in s.population.citizens:
		if c == ruler or not c.is_alive or c.state in [CitizenNPC.State.SLEEPING, CitizenNPC.State.TALKING] or c.custom_data.get("fighting_ruler", false):
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
			click_path.clear()
			talk_target = null
			if action.get("kind", "") != "attack_citizen":
				cancel_action() # WASD перебивает приказ; из драки можно отойти, но она продолжается, пока близко
			move_ruler(ruler, dir, delta)
		elif not action.is_empty():
			_tick_action(ruler, delta)
		elif not click_path.is_empty() or talk_target:
			follow_path(ruler, delta)
		else:
			move_ruler(ruler, Vector2.ZERO, delta)
	_tick_fight(ruler, delta)
	_call_timer -= delta
	if _call_timer <= 0.0:
		_call_timer = CALL_SCAN_INTERVAL
		scan_calls()
