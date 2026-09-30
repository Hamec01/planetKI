class_name HeroPanel
extends PanelContainer

# ==============================================================================
# ПАНЕЛЬ ГЕРОЯ-ВОЖДЯ: Инвентарь • Персонаж • Навыки
# Всё действует на самого правителя (PlayerHero -> CitizenNPC -> CombatStatsResolver)
# и обновляется вживую, пока панель открыта.
# ==============================================================================

const TAB_INVENTORY: int = 0
const TAB_CHARACTER: int = 1
const TAB_SKILLS: int = 2

var tabs: TabContainer
var inventory_box: VBoxContainer
var character_box: VBoxContainer
var skills_box: VBoxContainer
var status_lbl: Label
var _refresh_timer: float = 0.0
var _signature: String = ""

func _ready() -> void:
	visible = false
	_build_ui()

func _get_settlement() -> SettlementData:
	var s = GameManager.get_player_settlement() if GameManager else null
	return s if s is SettlementData else null

func open_tab(tab: int) -> void:
	if visible and tabs.current_tab == tab:
		visible = false
		return
	tabs.current_tab = tab
	visible = true
	_signature = ""
	refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		refresh()

# --- ПОСТРОЕНИЕ ---

func _style(bg: Color, border: Color, width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb

func _label(text: String, size: int, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _button(text: String, tip: String = "") -> Button:
	var b = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(0, 24)
	return b

func _card(highlight: bool = false) -> Array:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(
		Color(0.18, 0.15, 0.08, 0.95) if highlight else Color(0.12, 0.15, 0.21, 0.9),
		Color(0.85, 0.68, 0.28, 0.9) if highlight else Color(0.3, 0.4, 0.55, 0.6)))
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	return [p, v]

func _tab_scroll(tab_name: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box

func _build_ui() -> void:
	anchors_preset = Control.PRESET_CENTER
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -380.0
	offset_top = -290.0
	offset_right = 380.0
	offset_bottom = 250.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb = _style(Color(0.08, 0.10, 0.15, 0.98), Color(0.85, 0.68, 0.28, 1.0), 2, 10)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 16
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var main = VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	add_child(main)
	var top = HBoxContainer.new()
	main.add_child(top)
	var title = _label("👑 КОРОЛЬ", 14, Color(1.0, 0.9, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(func(): visible = false)
	top.add_child(close_btn)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(tabs)
	inventory_box = _tab_scroll("🎒 Инвентарь")
	character_box = _tab_scroll("🧍 Персонаж")
	skills_box = _tab_scroll("✨ Навыки")
	status_lbl = _label("", 10, Color(1.0, 0.7, 0.5))
	main.add_child(status_lbl)

# --- ОБНОВЛЕНИЕ ---

func refresh() -> void:
	var s = _get_settlement()
	if s == null or s.hero == null:
		return
	var ruler = PlayerHero.get_ruler(s)
	if ruler == null:
		_clear(inventory_box)
		inventory_box.add_child(_label("Вождь ушёл к предкам.", 12, Color(1.0, 0.6, 0.5)))
		return
	var hero: PlayerHero = s.hero
	var sig = "%d|%d|%d|%d|%s|%s|%s|%s|%d|%d" % [tabs.current_tab, hero.level, hero.unspent_attr_points, hero.unspent_skill_points,
		str(hero.allocated), str(hero.skill_ranks), str(ruler.equipment), str(s.equipment_stockpile), int(ruler.health), int(hero.xp)] + str(hero.bag) + str(int(ruler.hunger / 10.0))
	if sig == _signature:
		return
	_signature = sig
	match tabs.current_tab:
		TAB_INVENTORY: _fill_inventory(s, hero, ruler)
		TAB_CHARACTER: _fill_character(s, hero, ruler)
		TAB_SKILLS: _fill_skills(s, hero)

func _clear(box: Container) -> void:
	for ch in box.get_children():
		ch.queue_free()

func _fill_inventory(s: SettlementData, hero: PlayerHero, ruler: CitizenNPC) -> void:
	_clear(inventory_box)
	var stats = ruler.get_combat_stats()
	inventory_box.add_child(_label("Бой: урон %.1f • броня %d • точность %d%% • удар раз в %.2fс • оружие: %s" % [
		float(stats["raw_damage"]), int(stats["armor"]), int(float(stats["accuracy"]) * 100.0), float(stats["attack_interval"]), stats["weapon_name"]], 11, Color(0.8, 0.9, 1.0)))
	# Сумка Короля: то, что он сам добыл
	inventory_box.add_child(_label("🎒 Сумка: %.1f / %.1f (вместимость растёт с силой) • сытость %d" % [hero.get_bag_weight(), hero.get_bag_capacity(s), int(ruler.hunger)], 11, Color(0.7, 0.85, 1.0)))
	if hero.bag.is_empty():
		inventory_box.add_child(_label("Пусто. ПКМ по дереву, камню, кусту, цветам или туше — Король добудет сам.", 10, Color(0.75, 0.75, 0.75)))
	for item in hero.bag:
		var bc = _card(false)
		var bv: VBoxContainer = bc[1]
		var brow = HBoxContainer.new()
		bv.add_child(brow)
		var blbl = _label("%s × %.2f" % [PlayerHero.BAG_ITEMS.get(item, {"name": item})["name"], float(hero.bag[item])], 11, Color(0.95, 0.92, 0.8))
		blbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		brow.add_child(blbl)
		if PlayerHero.BAG_ITEMS.get(item, {}).get("food", false):
			var eat_btn = _button("Съесть", "Сытная еда: %.2f ед." % PlayerHero.MEAL_AMOUNT)
			var eat_item = item
			eat_btn.pressed.connect(func():
				var res = hero.eat_from_bag(s, eat_item)
				status_lbl.text = String(res["reason"])
				_signature = ""
				refresh()
			)
			brow.add_child(eat_btn)
		inventory_box.add_child(bc[0])
	inventory_box.add_child(_label("Сдать добычу — ПКМ по складу. Цветы остаются у Короля для подарков в разговоре.", 9, Color(0.7, 0.72, 0.78)))
	inventory_box.add_child(_label("Надето на Короле:", 11, Color(0.7, 0.85, 1.0)))
	for slot in PlayerHero.SLOTS:
		var c = _card(false)
		var v: VBoxContainer = c[1]
		var item_id = String(ruler.equipment.get(slot, PlayerHero.SLOTS[slot]["empty"]))
		var empty = item_id == "" or item_id == PlayerHero.SLOTS[slot]["empty"]
		var row = HBoxContainer.new()
		v.add_child(row)
		var lbl = _label("%s: %s" % [PlayerHero.SLOTS[slot]["name"], "пусто" if empty and item_id == "" else PlayerHero.describe_item(item_id)], 11, Color(0.95, 0.92, 0.8))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if not empty:
			var off = _button("Снять", "Вернуть на склад снаряжения племени")
			var sl = slot
			off.pressed.connect(func():
				hero.unequip(s, sl)
				_signature = ""
				refresh()
			)
			row.add_child(off)
		inventory_box.add_child(c[0])
	inventory_box.add_child(_label("Склад снаряжения племени (изготовлено в кузнице и мастерских):", 11, Color(0.7, 0.85, 1.0)))
	var items = hero.get_stockpile_items(s)
	if items.is_empty():
		inventory_box.add_child(_label("Склад пуст. Закажите оружие и доспехи в кузнице или мастерской.", 10, Color(0.75, 0.75, 0.75)))
	for it in items:
		var c = _card(false)
		var v: VBoxContainer = c[1]
		var row = HBoxContainer.new()
		v.add_child(row)
		var lbl = _label("%s — %s ×%d" % [PlayerHero.SLOTS[it["slot"]]["name"], PlayerHero.describe_item(it["id"]), int(it["count"])], 10, Color(0.9, 0.9, 0.9))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var on = _button("Надеть")
		var iid = it["id"]
		on.pressed.connect(func():
			var res = hero.equip_from_stockpile(s, iid)
			status_lbl.text = "" if res["ok"] else "⚠ " + String(res["reason"])
			_signature = ""
			refresh()
		)
		row.add_child(on)
		inventory_box.add_child(c[0])

func _fill_character(s: SettlementData, hero: PlayerHero, ruler: CitizenNPC) -> void:
	_clear(character_box)
	var head = _card(true)
	var hv: VBoxContainer = head[1]
	hv.add_child(_label("%s, %d лет — уровень %d" % [ruler.name, ruler.age, hero.level], 13, Color(1.0, 0.9, 0.5)))
	hv.add_child(_label("Опыт: %d / %d • Свободные очки характеристик: %d • очки навыков: %d" % [int(hero.xp), int(PlayerHero.xp_to_next(hero.level)), hero.unspent_attr_points, hero.unspent_skill_points], 11, Color(0.85, 0.9, 1.0)))
	hv.add_child(_label("За каждый уровень: +%d очка характеристик и +%d очко навыка. Опыт — за личные решения, созывы совета, указы и победы над зверем." % [PlayerHero.POINTS_PER_LEVEL, PlayerHero.SKILL_POINTS_PER_LEVEL], 9, Color(0.7, 0.75, 0.8)))
	character_box.add_child(head[0])
	for attr in PlayerHero.ATTRIBUTES:
		var c = _card(false)
		var v: VBoxContainer = c[1]
		var row = HBoxContainer.new()
		v.add_child(row)
		var natural = hero.get_attribute(s, attr) - PlayerHero.BASE_ATTR - int(hero.allocated.get(attr, 0))
		var lbl = _label("%s: %d  (база %d + вложено %d + развито трудом %d)" % [PlayerHero.ATTRIBUTES[attr]["name"], hero.get_attribute(s, attr), PlayerHero.BASE_ATTR, int(hero.allocated.get(attr, 0)), natural], 12, Color(0.95, 0.92, 0.8))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var plus = _button("  +  ", "Вложить очко")
		plus.disabled = hero.unspent_attr_points <= 0
		var a = attr
		plus.pressed.connect(func():
			hero.allocate_point(s, a)
			_signature = ""
			refresh()
		)
		row.add_child(plus)
		v.add_child(_label(PlayerHero.ATTRIBUTES[attr]["desc"], 9, Color(0.72, 0.8, 0.9)))
		character_box.add_child(c[0])
	var stats = ruler.get_combat_stats()
	character_box.add_child(_label("Здоровье %d/%d • Выносливость %d/%d • Урон %.1f • Точность %d%% • Переносит %.1f" % [
		int(ruler.health), int(ruler.max_health), int(ruler.stamina_current), int(ruler.stamina_max),
		float(stats["raw_damage"]), int(float(stats["accuracy"]) * 100.0), ruler.get_effective_max_carry()], 11, Color(0.8, 0.95, 0.8)))
	var tr_parts: Array[String] = []
	var trait_names = {"bravery": "храбрость", "empathy": "сострадание", "diligence": "трудолюбие", "tradition": "традиции",
		"ambition": "честолюбие", "curiosity": "любопытство", "temper": "вспыльчивость", "sociability": "общительность"}
	for t in trait_names:
		tr_parts.append("%s %d" % [trait_names[t], int(float(ruler.traits.get(t, 50.0)))])
	character_box.add_child(_label("Характер (как у жителей): " + ", ".join(tr_parts), 9, Color(0.7, 0.72, 0.78)))
	if not hero.xp_log.is_empty():
		character_box.add_child(_label("Последний опыт:", 10, Color(0.7, 0.85, 1.0)))
		for e in hero.xp_log:
			character_box.add_child(_label("+%d — %s" % [int(e.get("amount", 0)), e.get("reason", "")], 9, Color(0.8, 0.8, 0.75)))

func _fill_skills(s: SettlementData, hero: PlayerHero) -> void:
	_clear(skills_box)
	skills_box.add_child(_label("Свободные очки навыков: %d (уровень вождя %d)" % [hero.unspent_skill_points, hero.level], 12, Color(1.0, 0.9, 0.5)))
	for sk in PlayerHero.SKILLS:
		var cfg: Dictionary = PlayerHero.SKILLS[sk]
		var rank = hero.get_skill_rank(sk)
		var c = _card(rank > 0)
		var v: VBoxContainer = c[1]
		var row = HBoxContainer.new()
		v.add_child(row)
		var lbl = _label("%s — ранг %d/%d (с %d ур.)" % [cfg["name"], rank, int(cfg["max_rank"]), int(cfg["req_level"])], 11, Color(0.95, 0.92, 0.8))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var check = hero.can_learn(sk)
		var learn = _button("Изучить", check["reason"])
		learn.disabled = not check["ok"]
		var skill_id = sk
		learn.pressed.connect(func():
			hero.learn_skill(s, skill_id)
			_signature = ""
			refresh()
		)
		row.add_child(learn)
		v.add_child(_label(cfg["desc"], 9, Color(0.72, 0.8, 0.9)))
		skills_box.add_child(c[0])
