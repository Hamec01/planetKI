class_name FactionView
extends PanelContainer

@onready var tab_container: TabContainer = $Margin/VBox/TabContainer
@onready var close_btn: Button = $Margin/VBox/Header/CloseBtn

# Laws
@onready var laws_list: VBoxContainer = $Margin/VBox/TabContainer/Законы/Scroll/LawsList

# Religion
@onready var relig_name_label: Label = $Margin/VBox/TabContainer/Вера/VBox/ReligName
@onready var relig_bonuses_label: Label = $Margin/VBox/TabContainer/Вера/VBox/ReligBonuses
@onready var relig_values_label: Label = $Margin/VBox/TabContainer/Вера/VBox/ReligValues
@onready var relig_select_box: VBoxContainer = $Margin/VBox/TabContainer/Вера/VBox/SelectBox

# Technologies
@onready var tech_progress_bar: ProgressBar = $Margin/VBox/TabContainer/Наука/VBox/TechProgress
@onready var current_tech_label: Label = $Margin/VBox/TabContainer/Наука/VBox/CurrentTechLabel
@onready var tech_list: VBoxContainer = $Margin/VBox/TabContainer/Наука/VBox/Scroll/TechList

# Generals & Army
@onready var generals_list: VBoxContainer = $Margin/VBox/TabContainer/Армия/VBox/Scroll/GeneralsList
@onready var recruit_army_btn: Button = $Margin/VBox/TabContainer/Армия/VBox/RecruitArmyBtn

# Diplomacy
@onready var diplo_list: VBoxContainer = $Margin/VBox/TabContainer/Дипломатия/VBox/Scroll/DiploList

# History
@onready var history_text: RichTextLabel = $Margin/VBox/TabContainer/Хроника/Scroll/HistoryText

# Star system
@onready var star_system_text: RichTextLabel = $Margin/VBox/TabContainer/Система/Scroll/StarText

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(func(): visible = false)
	EventBus.day_passed.connect(_on_tick)
	recruit_army_btn.pressed.connect(_on_recruit_army)

func open_tab(tab_name: String) -> void:
	visible = true
	match tab_name:
		"laws": tab_container.current_tab = 0
		"relig": tab_container.current_tab = 1
		"tech": tab_container.current_tab = 2
		"army": tab_container.current_tab = 3
		"diplomacy": tab_container.current_tab = 4
		"history": tab_container.current_tab = 5
		"starsystem": tab_container.current_tab = 6
	_refresh_all()

func _on_tick(_d: int, _m: int, _y: int) -> void:
	if visible:
		_refresh_all()

func _refresh_all() -> void:
	var player_f: FactionData = GameManager.factions.get(GameManager.player_faction_id, null)
	if player_f == null:
		return
		
	_refresh_laws(player_f)
	_refresh_religion(player_f)
	_refresh_tech(player_f)
	_refresh_generals(player_f)
	_refresh_diplomacy(player_f)
	_refresh_history()
	_refresh_star_system()

func _refresh_laws(f: FactionData) -> void:
	for child in laws_list.get_children():
		child.queue_free()
		
	for law_id in LawSystem.LAWS:
		var law = LawSystem.get_law(law_id)
		var row = HBoxContainer.new()
		var is_active = f.active_laws.has(law_id)
		
		var lbl = Label.new()
		lbl.text = ("✅ " if is_active else "⬜ ") + law["name"] + "\n" + law["description"]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		
		var btn = Button.new()
		btn.text = "Принят" if is_active else "Принять закон"
		btn.disabled = is_active
		btn.pressed.connect(func():
			f.active_laws.append(law_id)
			GameManager.add_history_entry(GameManager.current_year, "Принят закон", "Вождь утвердил закон: " + law["name"], "Политика")
			_refresh_laws(f)
		)
		row.add_child(btn)
		laws_list.add_child(row)

func _refresh_religion(f: FactionData) -> void:
	var cur_rel = ReligionSystem.get_religion(f.religion_id)
	relig_name_label.text = "🏛 Вера: " + cur_rel["name"]
	relig_values_label.text = "Ценности: " + ", ".join(cur_rel["values"])
	relig_bonuses_label.text = "Бонусы: " + cur_rel["bonuses"] + "\nРиски: " + cur_rel["risks"]
	
	for child in relig_select_box.get_children():
		child.queue_free()
		
	for rel_id in ReligionSystem.RELIGIONS:
		if rel_id == f.religion_id:
			continue
		var r = ReligionSystem.get_religion(rel_id)
		var btn = Button.new()
		btn.text = "Принять культ: " + r["name"]
		btn.pressed.connect(func():
			f.religion_id = rel_id
			GameManager.add_history_entry(GameManager.current_year, "Смена веры", "Племя обратилось к культу: " + r["name"], "Религия")
			_refresh_religion(f)
		)
		relig_select_box.add_child(btn)

func _refresh_tech(f: FactionData) -> void:
	if f.current_research_tech != "":
		var cur_t = TechTree.get_tech(f.current_research_tech)
		current_tech_label.text = "Изучается: %s (%.1f / %.1f очков знаний)" % [cur_t["name"], f.research_progress, cur_t["cost"]]
		tech_progress_bar.max_value = cur_t["cost"]
		tech_progress_bar.value = f.research_progress
	else:
		current_tech_label.text = "Исследование не выбрано"
		tech_progress_bar.value = 0
		
	for child in tech_list.get_children():
		child.queue_free()
		
	for t_id in TechTree.TECHNOLOGIES:
		var t = TechTree.get_tech(t_id)
		var row = HBoxContainer.new()
		var is_unlocked = f.unlocked_techs.has(t_id)
		var is_current = (f.current_research_tech == t_id)
		
		var lbl = Label.new()
		var status_icon = "✅ " if is_unlocked else ("🔬 " if is_current else "🔒 ")
		lbl.text = "%s %s (Цена: %d зн.)\n%s" % [status_icon, t["name"], int(t["cost"]), t["description"]]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		
		if not is_unlocked and not is_current:
			var btn = Button.new()
			btn.text = "Исследовать"
			btn.pressed.connect(func():
				f.current_research_tech = t_id
				f.research_progress = 0.0
				_refresh_tech(f)
			)
			row.add_child(btn)
			
		tech_list.add_child(row)

func _refresh_generals(f: FactionData) -> void:
	for child in generals_list.get_children():
		child.queue_free()
		
	for i in range(f.generals.size()):
		var g = f.generals[i]
		var card = PanelContainer.new()
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		
		# Портрет генерала/вождя
		var portrait_tr = TextureRect.new()
		portrait_tr.texture = CharacterTextureManager.get_character_for_job("general", i + 1)
		portrait_tr.custom_minimum_size = Vector2(52, 52)
		portrait_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(portrait_tr)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl = Label.new()
		name_lbl.text = "🎖 %s (%s, %d лет)" % [g["name"], g["title"], g["age"]]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
		vbox.add_child(name_lbl)
		
		var stats_lbl = Label.new()
		stats_lbl.text = "Смелость: %d | Интеллект: %d | Хитрость: %d | Дисциплина: %d | Харизма: %d" % [
			g["bravery"], g["intellect"], g["cunning"], g["discipline"], g["charisma"]
		]
		stats_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(stats_lbl)
		
		var quote_lbl = Label.new()
		quote_lbl.text = "«%s»" % g.get("quote", "За племя!")
		quote_lbl.add_theme_font_size_override("font_size", 11)
		quote_lbl.modulate = Color(0.8, 0.85, 0.95)
		vbox.add_child(quote_lbl)
		
		hbox.add_child(vbox)
		card.add_child(hbox)
		generals_list.add_child(card)

func _on_recruit_army() -> void:
	var s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
	var f: FactionData = GameManager.factions.get(GameManager.player_faction_id, null)
	if s and f and not f.generals.is_empty():
		if s.economy.get_resource("food") >= 30 and s.economy.get_resource("wood") >= 20:
			s.economy.add_resource("food", -30)
			s.economy.add_resource("wood", -20)
			var army = ArmyData.new()
			army.id = "player_army_" + str(f.armies.size() + 1)
			army.faction_id = f.id
			army.name = "Дружина Вождя"
			army.pos = s.pos
			army.general = f.generals[0] # Брок или первый генерал
			f.armies.append(army)
			GameManager.add_history_entry(GameManager.current_year, "Сбор дружины", "Сформирован боевой отряд под началом %s." % army.general["name"], "Армия")
			_refresh_generals(f)

func _refresh_diplomacy(player_f: FactionData) -> void:
	for child in diplo_list.get_children():
		child.queue_free()
		
	for f_id in GameManager.factions:
		if f_id == player_f.id:
			continue
		var other_f: FactionData = GameManager.factions[f_id]
		var rel = player_f.get_relation(f_id)
		
		var card = PanelContainer.new()
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		
		# Портрет иностранного вождя
		var portrait_tr = TextureRect.new()
		portrait_tr.texture = CharacterTextureManager.get_leader_portrait(other_f.id)
		portrait_tr.custom_minimum_size = Vector2(52, 52)
		portrait_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(portrait_tr)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl = Label.new()
		name_lbl.text = "🤝 %s (Вождь: %s)" % [other_f.name, other_f.leader_name]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
		vbox.add_child(name_lbl)
		
		var details_lbl = Label.new()
		details_lbl.text = "Культура: %s | Вера: %s\nОтношение: %d | Доверие: %d | Страх: %d" % [
			other_f.culture, other_f.religion_id, rel["opinion"], rel["trust"], rel["fear"]
		]
		details_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(details_lbl)
		
		var btn_box = HBoxContainer.new()
		btn_box.add_theme_constant_override("separation", 8)
		var gift_btn = Button.new()
		gift_btn.text = "Отправить дары (+пища/-кубрики)"
		gift_btn.pressed.connect(func():
			var s: SettlementData = GameManager.settlements.get("player_tribe_settlement", null)
			if s and s.economy.get_resource("food") >= 20:
				s.economy.add_resource("food", -20)
				player_f.change_opinion(f_id, 15)
				_refresh_diplomacy(player_f)
		)
		btn_box.add_child(gift_btn)
		
		var raid_btn = Button.new()
		raid_btn.text = "⚔️ Объявить набег"
		raid_btn.pressed.connect(func():
			player_f.change_opinion(f_id, -40)
			# Запуск битвы с соседним племенем
			var player_s = GameManager.settlements.get("player_tribe_settlement", null)
			var enemy_s = GameManager.settlements.get(f_id + "_settlement", null)
			if player_s and enemy_s and not player_f.generals.is_empty():
				var att_army = ArmyData.new()
				att_army.faction_id = player_f.id
				att_army.name = "Воины Набега"
				att_army.general = player_f.generals[0]
				
				var def_army = ArmyData.new()
				def_army.faction_id = other_f.id
				def_army.name = "Защитники Стоянки"
				def_army.general = other_f.generals[0] if not other_f.generals.is_empty() else GeneralGenerator.generate_random_general()
				
				var battle = BattleInstance.new("battle_" + str(randi()), enemy_s.pos, att_army, def_army, "Холмистая долина")
				EventBus.battle_started.emit({
					"id": battle.id,
					"pos": enemy_s.pos,
					"battle": battle
				})
				_refresh_diplomacy(player_f)
		)
		btn_box.add_child(raid_btn)
		
		vbox.add_child(btn_box)
		card.add_child(vbox)
		diplo_list.add_child(card)

func _refresh_history() -> void:
	var text = "[b]ХРОНИКА ВЕКОВ И ДЕЯНИЙ[/b]\n\n"
	for entry in GameManager.history_log:
		text += "[color=gold]Год %d, Месяц %d, День %d[/color] — [b]%s[/b] ([i]%s[/i])\n%s\n\n" % [
			entry["year"], entry["month"], entry["day"], entry["title"], entry["category"], entry["description"]
		]
	history_text.text = text

func _refresh_star_system() -> void:
	var s_data = GameManager.star_system_data
	if s_data.is_empty():
		return
	var text = "[b]ЗВЁЗДНАЯ СИСТЕМА: %s[/b]\n" % s_data.get("star_name", "Аурелия")
	text += "Звезда: %s (Светимость: %.1f)\n" % [s_data.get("star_type", ""), s_data.get("star_lum", 1.0)]
	text += "Стартовая планета: %s (Спутники: %s)\n" % [s_data.get("home_planet_name", ""), ", ".join(s_data.get("moons", []))]
	text += "Seed генерации: %s\n\n" % GameManager.world_seed
	text += "[b]Планетарные тела системы:[/b]\n"
	for p in s_data.get("planets", []):
		text += "• %s — %s (Дистанция: %.1f а.е.)\n" % [p["name"], p["type"], p["distance_au"]]
	star_system_text.text = text
