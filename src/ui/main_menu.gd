class_name MainMenu
extends Control

@onready var seed_input: LineEdit = $CenterContainer/MenuCard/Margin/VBox/SeedBox/SeedInput
@onready var random_seed_btn: Button = $CenterContainer/MenuCard/Margin/VBox/SeedBox/RandomSeedBtn
@onready var new_game_btn: Button = $CenterContainer/MenuCard/Margin/VBox/NewGameBtn
@onready var continue_btn: Button = $CenterContainer/MenuCard/Margin/VBox/ContinueBtn
@onready var map_editor_btn: Button = $CenterContainer/MenuCard/Margin/VBox/MapEditorBtn
@onready var exit_btn: Button = $CenterContainer/MenuCard/Margin/VBox/ExitBtn

func _ready() -> void:
	seed_input.text = GameManager._generate_random_seed()
	random_seed_btn.pressed.connect(func():
		seed_input.text = GameManager._generate_random_seed()
	)
	
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	map_editor_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://src/editor/map_editor.tscn")
	)
	exit_btn.pressed.connect(func(): get_tree().quit())
	
	continue_btn.disabled = not SaveSystem.has_save_file()

func _on_new_game() -> void:
	var seed_val = seed_input.text.strip_edges()
	if seed_val == "":
		seed_val = GameManager._generate_random_seed()
	GameManager.world_seed = seed_val
	get_tree().change_scene_to_file("res://src/game.tscn")

func _on_continue() -> void:
	if SaveSystem.load_game():
		get_tree().change_scene_to_file("res://src/game.tscn")
