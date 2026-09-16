class_name EventsDialog
extends PanelContainer

@onready var title_label: Label = $Margin/VBox/Title
@onready var speaker_label: Label = $Margin/VBox/Speaker
@onready var text_label: Label = $Margin/VBox/Text
@onready var choices_container: VBoxContainer = $Margin/VBox/ChoicesBox

var current_event_data: Dictionary = {}

func _ready() -> void:
	EventBus.event_triggered.connect(_on_event_triggered)
	visible = false

func _on_event_triggered(data: Dictionary) -> void:
	current_event_data = data
	title_label.text = "📜 " + data.get("title", "Событие племени")
	speaker_label.text = "— " + data.get("speaker", "Вестник")
	text_label.text = data.get("text", "")
	
	for child in choices_container.get_children():
		child.queue_free()
		
	var choices = data.get("choices", [])
	for i in range(choices.size()):
		var choice = choices[i]
		var btn = Button.new()
		btn.text = "%d. %s\n(%s)" % [i + 1, choice["text"], choice.get("hint", "")]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		var choice_idx = i
		btn.pressed.connect(func():
			visible = false
			EventManager.resolve_choice(current_event_data["id"], choice_idx)
			GameManager.toggle_pause() # Снимаем с паузы
		)
		choices_container.add_child(btn)
		
	visible = true
