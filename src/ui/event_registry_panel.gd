class_name EventRegistryPanel
extends PanelContainer

signal event_open_requested(event_data: Dictionary)

var tab_container: TabContainer
var decisions_list: VBoxContainer
var incidents_list: VBoxContainer
var chronicle_list: VBoxContainer
var last_revision: String = ""

func _ready() -> void:
	visible = false
	anchors_preset = Control.PRESET_CENTER
	offset_left = -360.0
	offset_top = -250.0
	offset_right = 360.0
	offset_bottom = 250.0
	_build_ui()

func _process(_delta: float) -> void:
	if visible:
		_refresh_if_changed()

func open_registry() -> void:
	visible = true
	last_revision = ""
	_refresh_if_changed()

func _build_ui() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	style.border_color = Color(0.85, 0.68, 0.28, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var root = VBoxContainer.new()
	add_child(root)
	var header = HBoxContainer.new()
	root.add_child(header)
	var title = Label.new()
	title.text = "События поселения"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(func(): visible = false)
	header.add_child(close_button)
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tab_container)
	decisions_list = _add_tab("Решения")
	incidents_list = _add_tab("Происшествия")
	chronicle_list = _add_tab("Летопись")

func _add_tab(tab_name: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list

func _refresh_if_changed() -> void:
	var manager: CivilizationEventManager = GameManager.civilization_event_manager
	var revision = str(manager.event_instances) if manager else ""
	if revision == last_revision:
		return
	last_revision = revision
	_render_list(decisions_list, _events_for("decision"), "Нерешённых вопросов нет.")
	_render_list(incidents_list, _events_for("incident"), "Активных происшествий нет.")
	_render_list(chronicle_list, _events_for("chronicle"), "Летопись пока пуста.")

func _events_for(kind: String) -> Array[Dictionary]:
	var manager: CivilizationEventManager = GameManager.civilization_event_manager
	var result: Array[Dictionary] = []
	if manager == null:
		return result
	for event_data in manager.event_instances.values():
		if not event_data is Dictionary:
			continue
		var status = event_data.get("status", "pending")
		var is_incident = event_data.get("type", "") == "incident" or event_data.get("category", "") == "Происшествия"
		if kind == "decision" and status == "pending" and not is_incident:
			result.append(event_data)
		elif kind == "incident" and status == "pending" and is_incident:
			result.append(event_data)
		elif kind == "chronicle" and status == "resolved":
			result.append(event_data)
	return result

func _render_list(list: VBoxContainer, events: Array[Dictionary], empty_text: String) -> void:
	for child in list.get_children():
		child.queue_free()
	if events.is_empty():
		var empty = Label.new()
		empty.text = empty_text
		empty.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		list.add_child(empty)
		return
	for event_data in events:
		var row = VBoxContainer.new()
		var title = Label.new()
		title.text = event_data.get("title", "Событие")
		title.add_theme_font_size_override("font_size", 12)
		row.add_child(title)
		var details = Label.new()
		details.text = event_data.get("description", "")
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_theme_font_size_override("font_size", 10)
		row.add_child(details)
		var instance = Label.new()
		instance.text = "ID: %s" % event_data.get("instance_id", "")
		instance.add_theme_font_size_override("font_size", 9)
		instance.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		row.add_child(instance)
		if event_data.get("status", "") == "pending":
			var open_button = Button.new()
			open_button.text = "Открыть"
			open_button.pressed.connect(func(): event_open_requested.emit(event_data))
			row.add_child(open_button)
		list.add_child(row)
		list.add_child(HSeparator.new())