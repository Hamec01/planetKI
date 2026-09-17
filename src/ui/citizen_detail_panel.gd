class_name CitizenDetailPanel
extends PanelContainer

var current_citizen: CitizenNPC = null
var is_following_camera: bool = false

var portrait_rect: TextureRect
var name_lbl: Label
var subtitle_lbl: Label
var job_lbl: Label
var workplace_lbl: Label
var home_lbl: Label
var action_lbl: Label
var cargo_lbl: Label
var cargo_icon: TextureRect

var health_bar: ProgressBar
var hunger_bar: ProgressBar
var energy_bar: ProgressBar

var combat_stats_vbox: VBoxContainer
var combat_title_lbl: Label
var phys_stats_lbl: Label
var weapon_skill_lbl: Label
var dmg_breakdown_lbl: Label

var btn_follow: Button
var btn_close: Button
var debug_lbl: Label

func _ready() -> void:
	visible = false
	_build_ui()
	EventBus.citizen_selected.connect(_on_citizen_selected)
	EventBus.citizen_deselected.connect(_on_citizen_deselected)

func _build_ui() -> void:
	anchors_preset = Control.PRESET_BOTTOM_RIGHT
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -340.0
	offset_top = -30.0
	offset_right = -16.0
	offset_bottom = -30.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(320, 0)
	
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.12, 0.16, 0.95)
	sbox.border_color = Color(0.35, 0.65, 0.85, 0.9)
	sbox.set_border_width_all(2)
	sbox.set_corner_radius_all(8)
	sbox.shadow_color = Color(0, 0, 0, 0.5)
	sbox.shadow_size = 6
	sbox.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sbox)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	
	# 1. Шапка: Портрет + Имя + Кнопка закрытия
	var top_box = HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 10)
	vbox.add_child(top_box)
	
	portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(56, 56)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top_box.add_child(portrait_rect)
	
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_box.add_child(title_box)
	
	name_lbl = Label.new()
	name_lbl.text = "Имя жителя"
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	title_box.add_child(name_lbl)
	
	subtitle_lbl = Label.new()
	subtitle_lbl.text = "Возраст 25 · Взрослый"
	subtitle_lbl.add_theme_font_size_override("font_size", 12)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	title_box.add_child(subtitle_lbl)
	
	btn_close = Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(24, 24)
	btn_close.pressed.connect(func():
		EventBus.citizen_deselected.emit()
	)
	top_box.add_child(btn_close)
	
	vbox.add_child(HSeparator.new())
	
	# 2. Профессия и Рабочее место
	var job_box = HBoxContainer.new()
	job_box.add_theme_constant_override("separation", 6)
	vbox.add_child(job_box)
	
	var job_tag = Label.new()
	job_tag.text = "Занятие:"
	job_tag.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	job_box.add_child(job_tag)
	
	job_lbl = Label.new()
	job_lbl.text = "Собиратель"
	job_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	job_box.add_child(job_lbl)
	
	workplace_lbl = Label.new()
	workplace_lbl.text = "· Стоянка собирателей"
	workplace_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	job_box.add_child(workplace_lbl)
	
	# 3. Жилье
	var home_box = HBoxContainer.new()
	home_box.add_theme_constant_override("separation", 6)
	vbox.add_child(home_box)
	
	var home_tag = Label.new()
	home_tag.text = "Жильё:"
	home_tag.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	home_box.add_child(home_tag)
	
	home_lbl = Label.new()
	home_lbl.text = "Хижина Старейшины"
	home_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	home_box.add_child(home_lbl)
	
	# 4. Текущее действие (Статус)
	var action_box = HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 6)
	vbox.add_child(action_box)
	
	var action_tag = Label.new()
	action_tag.text = "Действие:"
	action_tag.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	action_box.add_child(action_tag)
	
	action_lbl = Label.new()
	action_lbl.text = "Идёт к ягодным кустам"
	action_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	action_box.add_child(action_lbl)
	
	# 5. Груз / Инвентарь
	var cargo_box = HBoxContainer.new()
	cargo_box.add_theme_constant_override("separation", 6)
	vbox.add_child(cargo_box)
	
	var cargo_tag = Label.new()
	cargo_tag.text = "Груз:"
	cargo_tag.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	cargo_box.add_child(cargo_tag)
	
	cargo_icon = TextureRect.new()
	cargo_icon.custom_minimum_size = Vector2(16, 16)
	cargo_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cargo_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cargo_box.add_child(cargo_icon)
	
	cargo_lbl = Label.new()
	cargo_lbl.text = "Пусто (0 / 6)"
	cargo_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cargo_box.add_child(cargo_lbl)
	
	vbox.add_child(HSeparator.new())
	
	# 6. Шкалы потребностей: Здоровье, Сытость, Бодрость
	var bars_grid = GridContainer.new()
	bars_grid.columns = 2
	bars_grid.add_theme_constant_override("h_separation", 8)
	bars_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(bars_grid)
	
	var h_lbl = Label.new()
	h_lbl.text = "Здоровье"
	bars_grid.add_child(h_lbl)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(160, 14)
	health_bar.max_value = 100.0
	health_bar.show_percentage = true
	bars_grid.add_child(health_bar)
	
	var f_lbl = Label.new()
	f_lbl.text = "Сытость"
	bars_grid.add_child(f_lbl)
	hunger_bar = ProgressBar.new()
	hunger_bar.custom_minimum_size = Vector2(160, 14)
	hunger_bar.max_value = 100.0
	hunger_bar.show_percentage = true
	bars_grid.add_child(hunger_bar)
	
	var e_lbl = Label.new()
	e_lbl.text = "Бодрость"
	bars_grid.add_child(e_lbl)
	energy_bar = ProgressBar.new()
	energy_bar.custom_minimum_size = Vector2(160, 14)
	energy_bar.max_value = 100.0
	energy_bar.show_percentage = true
	bars_grid.add_child(energy_bar)
	
	vbox.add_child(HSeparator.new())
	
	# 7. Боевые характеристики и развитие (PlanetKI v2 ТЗ)
	combat_stats_vbox = VBoxContainer.new()
	combat_stats_vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(combat_stats_vbox)
	
	combat_title_lbl = Label.new()
	combat_title_lbl.text = "⚔ Боевой профиль и подготовка:"
	combat_title_lbl.add_theme_font_size_override("font_size", 11)
	combat_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	combat_stats_vbox.add_child(combat_title_lbl)
	
	phys_stats_lbl = Label.new()
	phys_stats_lbl.text = "Сила: 0 (ур. 0) | Выносливость: 0 (ур. 0) | EGP: 0.0"
	phys_stats_lbl.add_theme_font_size_override("font_size", 10)
	phys_stats_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	combat_stats_vbox.add_child(phys_stats_lbl)
	
	weapon_skill_lbl = Label.new()
	weapon_skill_lbl.text = "Оружие: Кулаки | Броня: 0 | Темп: 1.8 с"
	weapon_skill_lbl.add_theme_font_size_override("font_size", 10)
	weapon_skill_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	combat_stats_vbox.add_child(weapon_skill_lbl)
	
	dmg_breakdown_lbl = Label.new()
	dmg_breakdown_lbl.text = "Урон: 5"
	dmg_breakdown_lbl.add_theme_font_size_override("font_size", 10)
	dmg_breakdown_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
	combat_stats_vbox.add_child(dmg_breakdown_lbl)
	
	vbox.add_child(HSeparator.new())
	
	# 8. Действия: Следовать камерой
	var btns_box = HBoxContainer.new()
	btns_box.add_theme_constant_override("separation", 8)
	vbox.add_child(btns_box)
	
	btn_follow = Button.new()
	btn_follow.text = "🎥 Следовать камерой"
	btn_follow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_follow.pressed.connect(_toggle_follow_camera)
	btns_box.add_child(btn_follow)
	
	# 9. Отладочная строка
	debug_lbl = Label.new()
	debug_lbl.text = ""
	debug_lbl.add_theme_font_size_override("font_size", 10)
	debug_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	vbox.add_child(debug_lbl)

func _on_citizen_selected(citizen: RefCounted) -> void:
	if citizen is CitizenNPC:
		current_citizen = citizen
		visible = true
		_update_ui_values()

func _on_citizen_deselected() -> void:
	current_citizen = null
	is_following_camera = false
	visible = false

func _toggle_follow_camera() -> void:
	is_following_camera = not is_following_camera
	if is_following_camera:
		btn_follow.text = "⏹ Остановить камеру"
		btn_follow.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	else:
		btn_follow.text = "🎥 Следовать камерой"
		btn_follow.remove_theme_color_override("font_color")

func _process(_delta: float) -> void:
	if not visible or current_citizen == null:
		return
	_update_ui_values()
	if is_following_camera and current_citizen != null:
		var cam = get_viewport().get_camera_2d()
		if cam:
			cam.position = cam.position.lerp(current_citizen.pos, 0.1)

func _get_job_display_name(j_id: String) -> String:
	match j_id:
		"hunter": return "Охотник"
		"forager": return "Собиратель"
		"woodcutter": return "Лесоруб"
		"quarryman": return "Каменотёс"
		"miner": return "Рудокоп"
		"builder": return "Строитель"
		"farmer": return "Земледелец"
		"craftsman": return "Ремесленник"
		"sage": return "Мудрец"
		"priest": return "Жрец"
		"guard": return "Стражник"
		"warrior": return "Воин"
		_: return "Свободный житель"

func _update_ui_values() -> void:
	if current_citizen == null:
		return
		
	portrait_rect.texture = current_citizen.get_texture()
	name_lbl.text = current_citizen.name
	
	var gender_str = "мужчина" if current_citizen.gender == "m" else "женщина"
	var cohort_str = "взрослый"
	match current_citizen.cohort:
		"child": cohort_str = "ребёнок"
		"youth": cohort_str = "подросток"
		"elder": cohort_str = "старейшина"
	subtitle_lbl.text = "%d лет · %s, %s" % [current_citizen.age, cohort_str, gender_str]
	
	job_lbl.text = _get_job_display_name(current_citizen.job_id)
	
	if current_citizen.workplace_id != "":
		workplace_lbl.text = "· " + current_citizen.workplace_id
	else:
		workplace_lbl.text = "· Без постоянного места"
		
	if current_citizen.home_id != "":
		home_lbl.text = current_citizen.home_id
	else:
		home_lbl.text = "Под открытым небом"
		
	action_lbl.text = current_citizen.last_status_reason
	
	if current_citizen.cargo_type != "" and current_citizen.cargo_amount > 0:
		cargo_lbl.text = "%.1f ед. (%s)" % [current_citizen.cargo_amount, current_citizen.cargo_type]
		cargo_icon.texture = ItemTextureManager.get_icon(current_citizen.cargo_type)
		cargo_icon.visible = true
	else:
		cargo_lbl.text = "Пусто (0 / %.0f)" % current_citizen.max_carry
		cargo_icon.visible = false
		
	health_bar.value = current_citizen.health
	hunger_bar.value = current_citizen.hunger
	energy_bar.value = current_citizen.energy
	
	# Обновление боевого профиля (PlanetKI v2 ТЗ: динамический расчёт)
	var stats = current_citizen.get_combat_stats()
	phys_stats_lbl.text = "Сила: %d | Выносливость: %d | Опыт столкновений (EGP): %.1f" % [
		stats["S"], stats["E"], stats["G"]
	]
	weapon_skill_lbl.text = "%s | Броня: %d | Темп: %.2f с | Точность: %d%%" % [
		stats["weapon_name"], int(stats["armor"]), stats["attack_interval"], int(stats["accuracy"] * 100)
	]
	
	var bd = stats["breakdown"]
	dmg_breakdown_lbl.text = "Урон: %d (основа %.1f + оруж. %.1f + сила %.1f + закалка %.1f)" % [
		stats["display_damage"], bd["base_attack"], bd["weapon_component"], bd["physical_damage"], bd["encounter_damage"]
	]
	
	debug_lbl.text = "ID: %s | State: %d | Pos: (%.0f, %.0f) | P: %.2f R: %.2f" % [
		current_citizen.citizen_id, current_citizen.state, current_citizen.pos.x, current_citizen.pos.y, stats["P"], stats["R"]
	]
