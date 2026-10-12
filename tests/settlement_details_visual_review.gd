extends Node2D

func _ready() -> void:
	scale = Vector2(3, 3)
	queue_redraw()
	if get_parent() is SubViewport: return
	# Fixed offscreen canvas: desktop window aspect/size must not crop the review.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1680,1920)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var board = get_script().new()
	viewport.add_child(board)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		get_tree().quit(1)
		return
	var result := image.save_png("res://scratch/settlement-details-godot.png")
	print("SETTLEMENT DETAIL VISUAL REVIEW: ", result)
	get_tree().quit(0 if result == OK else 1)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 560, 640), Color("30383b"))
	if not ComposerSettlementDetails.ready_pack(): return
	var font := ThemeDB.fallback_font
	var ids: Array = ComposerSettlementDetails.buildings.keys()
	for i in range(ids.size()):
		for mode in range(2):
			var index := i * 2 + mode
			var ground := Vector2(70 + (index % 4) * 140, 110 + (index / 4) * 130)
			var id := String(ids[i])
			ComposerSettlementDetails.draw_layer(self, id, "back", ground)
			if id in ["quern_house", "bakery"]:
				ComposerSettlementDetails.draw_mechanism(self, id, ground + Vector2(0, -18), mode == 1, 1.0)
			var citizen := CitizenNPC.new("review-" + id, "Worker", "m", 25, "adult")
			citizen.pos = ground + Vector2(0, -18)
			citizen.equipped_tool = {"id":"flint_sickle", "type":"hoe", "durability":100.0}
			citizen.facing_dir = Vector2.LEFT if mode == 1 else Vector2.RIGHT
			ComposerAssets.draw_citizen(self, citizen, 1.0, "walk")
			ComposerSettlementDetails.draw_front(self, id, ground, mode == 1)
			draw_string(font, ground + Vector2(-60, 12), id + (" OPEN" if mode == 1 else " CLOSED"), HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	var row := 0
	for id in ComposerSettlementDetails.equipment:
		for side in range(2):
			var citizen := CitizenNPC.new("tool-" + id, "Worker", "m", 25, "adult")
			citizen.pos = Vector2(30 + row * 85, 600 + side * 20)
			citizen.equipped_tool = {"id":id, "type":"hoe", "durability":100.0}
			citizen.facing_dir = Vector2.LEFT if side == 1 else Vector2.RIGHT
			ComposerAssets.draw_citizen(self, citizen, float(side) * 0.2, "walk")
		draw_string(font, Vector2(8 + row * 85, 635), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
		row += 1
