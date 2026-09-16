class_name ArmyCommandPanel
extends PanelContainer

var current_army: RefCounted = null # ArmyData

var general_portrait: TextureRect
var general_name_lbl: Label
var traits_lbl: Label
var status_lbl: Label
var composition_lbl: Label
var morale_bar: ProgressBar

var btn_assault: Button
var btn_defend: Button
var btn_shoot: Button
var btn_flank: Button
var btn_retreat: Button
var btn_move: Button

signal march_mode_toggled(active: bool)

func _ready() -> void:
	visible = false
	_build_ui()
	EventBus.army_selected.connect(_on_army_selected)
	EventBus.army_deselected.connect(_on_army_deselected)

func _build_ui() -> void:
	anchors_preset = Control.PRESET_BOTTOM_RIGHT
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -370.0
	offset_top = -30.0
	offset_right = -18.0
	offset_bottom = -30.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(350, 0)
	
	# Стиль военной карточки генерала (тёмное дерево / бронзовая окантовка)
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	sbox.border_color = Color(0.85, 0.65, 0.25, 1.0)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(8)
	sbox.shadow_color = Color(0, 0, 0, 0.5)
	sbox.shadow_size = 6
	sbox.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sbox)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)
	
	# Верхняя строка: Портрет + Имя + Закрыть
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(top_hbox)
	
	general_portrait = TextureRect.new()
	general_portrait.custom_minimum_size = Vector2(40, 40)
	general_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	general_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top_hbox.add_child(general_portrait)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(info_vbox)
	
	general_name_lbl = Label.new()
	general_name_lbl.text = "Генерал Брок Сокрушитель"
	general_name_lbl.add_theme_font_size_override("font_size", 13)
	general_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	info_vbox.add_child(general_name_lbl)
	
	traits_lbl = Label.new()
	traits_lbl.text = "Храбрость: 95 | Хитрость: 40 | Тактика: 80"
	traits_lbl.add_theme_font_size_override("font_size", 10)
	traits_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	info_vbox.add_child(traits_lbl)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.pressed.connect(func():
		visible = false
		EventBus.army_deselected.emit()
	)
	top_hbox.add_child(close_btn)
	
	# Статус и Состав отряда
	var mid_hbox = HBoxContainer.new()
	main_vbox.add_child(mid_hbox)
	
	composition_lbl = Label.new()
	composition_lbl.text = "⚔️ 20 воинов  🛡️ 15 копейщиков  🏹 10 лучников"
	composition_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composition_lbl.add_theme_font_size_override("font_size", 11)
	mid_hbox.add_child(composition_lbl)
	
	status_lbl = Label.new()
	status_lbl.text = "Статус: Ожидание"
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	mid_hbox.add_child(status_lbl)
	
	# Полоса морали
	morale_bar = ProgressBar.new()
	morale_bar.custom_minimum_size = Vector2(0, 10)
	morale_bar.value = 85.0
	morale_bar.show_percentage = false
	main_vbox.add_child(morale_bar)
	
	# Сетка тактических приказов Генералу
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(grid)
	
	btn_assault = _create_cmd_btn("⚔️ Штурм", "Приказ генералу немедленно атаковать цель")
	btn_assault.pressed.connect(func(): _give_cmd("assault"))
	grid.add_child(btn_assault)
	
	btn_defend = _create_cmd_btn("🛡️ Оборона", "Встать в глухую оборону (+30% стойкости)")
	btn_defend.pressed.connect(func(): _give_cmd("defend"))
	grid.add_child(btn_defend)
	
	btn_shoot = _create_cmd_btn("🏹 Залп стрел", "Стрелкам открыть шквальный огонь")
	btn_shoot.pressed.connect(func(): _give_cmd("skirmish"))
	grid.add_child(btn_shoot)
	
	btn_flank = _create_cmd_btn("⚡ Маневр", "Ложный отход и фланговый обход")
	btn_flank.pressed.connect(func(): _give_cmd("flank"))
	grid.add_child(btn_flank)
	
	btn_move = _create_cmd_btn("📍 Марш...", "Кликните на карту для отправки дружины в поход")
	btn_move.pressed.connect(func():
		march_mode_toggled.emit(true)
		if current_army:
			EventBus.army_command_given.emit(current_army.id if current_army.id != "" else "player_main_army", "march", null)
		EventBus.notification_toast.emit("Приказ марша", "Кликните по карте (ЛКМ или ПКМ), чтобы отправить дружину в поход.", "info")
	)
	grid.add_child(btn_move)
	
	btn_retreat = _create_cmd_btn("🏳️ Отход", "Организованно отступить к родной стоянке")
	btn_retreat.pressed.connect(func(): _give_cmd("retreat"))
	grid.add_child(btn_retreat)

func _create_cmd_btn(text: String, tooltip: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(110, 28)
	btn.add_theme_font_size_override("font_size", 10)
	return btn

func _on_army_selected(army_data: RefCounted) -> void:
	if not (army_data is ArmyData):
		visible = false
		current_army = null
		return
		
	current_army = army_data
	var gen: Dictionary = current_army.general if current_army.general else {}
	general_name_lbl.text = gen.get("name", current_army.name)
	traits_lbl.text = "Храбрость: %d | Хитрость: %d | Тактика: %d" % [
		gen.get("bravery", 60), gen.get("cunning", 50), gen.get("intellect", 50)
	]
	
	composition_lbl.text = "⚔️ %d воинов  🛡️ %d копейщиков  🏹 %d лучников" % [
		current_army.warriors, current_army.spearmen, current_army.archers
	]
	
	status_lbl.text = "Статус: В походе" if current_army.is_moving else "Статус: В строю"
	morale_bar.value = current_army.morale
	
	general_portrait.texture = CharacterTextureManager.get_character_for_job("general", 1)
	visible = true

func _on_army_deselected() -> void:
	current_army = null
	visible = false

func _give_cmd(cmd: String) -> void:
	if current_army == null:
		return
	var army_id = current_army.id if current_army.id != "" else "player_main_army"
	EventBus.army_command_given.emit(army_id, cmd, null)
	EventBus.notification_toast.emit("Приказ отдан", "Генерал принял распоряжение: %s" % cmd, "info")
