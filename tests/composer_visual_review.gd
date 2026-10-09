extends Node2D

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,900))
	get_viewport().size = Vector2i(1280,900)
	get_tree().create_timer(40).timeout.connect(func(): get_tree().quit(2))
	for i in range(8):
		var c = CitizenNPC.new("review_%d" % i,"","f" if i%2 else "m")
		c.visual_appearance_id = "citizen-look-%d" % i
		c.cohort = ["adult","adult","child","youth","elder","adult","adult","adult"][i]
		c.equipment["weapon"] = ["unarmed","short_sword","unarmed","unarmed","work_axe","hunting_bow","simple_spear","unarmed"][i]
		c.equipment["helmet"] = "iron_helmet" if i == 6 else ""
		c.pos = Vector2.ZERO
		var canvas = Node2D.new()
		canvas.position = Vector2(85+i*155,260)
		canvas.scale = Vector2(11,11)
		add_child(canvas)
		canvas.draw.connect(func(): ComposerAssets.draw_citizen(canvas,c,.45,"idle"))
		canvas.queue_redraw()
	for row in range(2):
		for col in range(3):
			var canvas = Node2D.new()
			canvas.position = Vector2(200+col*420,540+row*300)
			canvas.scale = Vector2(5,5)
			add_child(canvas)
			var node = {"category":"wood","original_sprite":["tree_oak","tree_pine","tree_birch"][col],"tree_stage":"standing" if row==0 else "logs","chop_hits":1 if col==1 and row==0 else 0}
			canvas.draw.connect(func(): ComposerTrees.draw_tree(canvas,node,Vector2.ZERO,1))
			canvas.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	if image.is_empty():
		push_error("Visual review needs a rendering driver")
		get_tree().quit(1)
		return
	image.save_png("res://scratch/composer-visual-review.png")
	print("COMPOSER VISUAL REVIEW SAVED")
	get_tree().quit()
