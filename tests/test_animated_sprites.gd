extends SceneTree

func _init() -> void:
	print("Testing SpriteFrames loading...")
	var sf_brock = load("res://spriteframes/units/f1_3rdgeneral.tres")
	if sf_brock is SpriteFrames:
		print("SUCCESS: Loaded f1_3rdgeneral.tres! Animations: ", sf_brock.get_animation_names())
	else:
		printerr("FAILED to load f1_3rdgeneral.tres")
		
	var sf_gwen = load("res://spriteframes/units/f2_altgeneral.tres")
	if sf_gwen is SpriteFrames:
		print("SUCCESS: Loaded f2_altgeneral.tres! Animations: ", sf_gwen.get_animation_names())
	else:
		printerr("FAILED to load f2_altgeneral.tres")
		
	var sf_fx = load("res://spriteframes/fx/fx_bladestorm.tres")
	if sf_fx is SpriteFrames:
		print("SUCCESS: Loaded fx_bladestorm.tres! Animations: ", sf_fx.get_animation_names())
	else:
		printerr("FAILED to load fx_bladestorm.tres")
		
	var item_icon = ItemTextureManager.get_icon("food")
	if item_icon:
		print("SUCCESS: Loaded food icon texture: ", item_icon.resource_path)
	else:
		printerr("FAILED to load food icon")
		
	quit(0)
