@tool
extends EditorPlugin

const DockScript = preload("res://addons/sprite_slicer/sprite_slicer_dock.gd")

var dock_instance: Control


func _enter_tree() -> void:
	dock_instance = DockScript.new()
	dock_instance.name = "SpriteSlicer"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)


func _exit_tree() -> void:
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.queue_free()
		dock_instance = null
