class_name EventsDialog
extends PanelContainer

@onready var title_label: Label = $Margin/VBox/Title
@onready var speaker_label: Label = $Margin/VBox/Speaker
@onready var text_label: Label = $Margin/VBox/Text
@onready var choices_container: VBoxContainer = $Margin/VBox/ChoicesBox

var current_event_data: Dictionary = {}

func _ready() -> void:
	# Слушаем только старый (event_triggered) сигнал.
	# Цивилизационные события обрабатываются специализированным окном CivilizationEventModal в MainHUD.
	EventBus.event_triggered.connect(_on_event_triggered)
	visible = false

func _on_civilization_event_triggered(data: Dictionary) -> void:
	# Новый путь: данные из CivilizationEventManager
	# Поля: title, description (текст), choices[{id, title, desc, effects_desc}], instance_id
	current_event_data = data
	title_label.text = "📜 " + data.get("title", "Событие племени")

	# Спикер: берём имя первого актора если есть, иначе "Вестник"
	var actor_names = data.get("actor_names", [])
	if not actor_names.is_empty():
		speaker_label.text = "— " + str(actor_names[0])
	else:
		speaker_label.text = "— " + data.get("speaker", "Вестник")

	# Текст: поле description (уже отформатировано через {actor_0} замены в trigger_event)
	text_label.text = data.get("description", data.get("text", ""))

	for child in choices_container.get_children():
		child.queue_free()

	var choices = data.get("choices", [])
	var instance_id = data.get("instance_id", "")

	for i in range(choices.size()):
		var choice = choices[i]
		var choice_id = choice.get("id", str(i))
		# Текст кнопки: title (заголовок) + desc (описание) + effects_desc (эффекты)
		var btn_title = choice.get("title", choice.get("text", "Выбор %d" % (i + 1)))
		var btn_desc = choice.get("desc", choice.get("hint", ""))
		var btn_effects = choice.get("effects_desc", "")
		var btn_text = "%d. %s" % [i + 1, btn_title]
		if btn_desc != "":
			btn_text += "\n   %s" % btn_desc
		if btn_effects != "":
			btn_text += "\n   %s" % btn_effects

		var btn = Button.new()
		btn.text = btn_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 44)

		var captured_choice_id = choice_id
		var captured_instance_id = instance_id
		btn.pressed.connect(func():
			visible = false
			if GameManager.civilization_event_manager:
				GameManager.civilization_event_manager.apply_choice(captured_instance_id, captured_choice_id)
		)
		choices_container.add_child(btn)

	visible = true

func _on_event_triggered(data: Dictionary) -> void:
	# Старый путь (legacy EventManager) — оставляем для совместимости
	current_event_data = data
	title_label.text = "📜 " + data.get("title", "Событие племени")
	speaker_label.text = "— " + data.get("speaker", "Вестник")
	text_label.text = data.get("text", data.get("description", ""))

	for child in choices_container.get_children():
		child.queue_free()

	var choices = data.get("choices", [])
	for i in range(choices.size()):
		var choice = choices[i]
		var btn = Button.new()
		btn.text = "%d. %s\n(%s)" % [i + 1, choice.get("text", choice.get("title", "")), choice.get("hint", choice.get("desc", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var choice_idx = i
		btn.pressed.connect(func():
			visible = false
			# Пробуем новый путь сначала
			var inst_id = current_event_data.get("instance_id", "")
			var chs = current_event_data.get("choices", [])
			if inst_id != "" and choice_idx < chs.size() and GameManager.civilization_event_manager:
				var cid = chs[choice_idx].get("id", str(choice_idx))
				GameManager.civilization_event_manager.apply_choice(inst_id, cid)
			elif "EventManager" in Engine.get_singleton_list():
				EventManager.resolve_choice(current_event_data.get("id", ""), choice_idx)
		)
		choices_container.add_child(btn)

	visible = true
