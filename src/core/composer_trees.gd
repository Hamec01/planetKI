class_name ComposerTrees
extends RefCounted

static var data: Dictionary = {}
static var textures: Dictionary = {}

static func ready_pack() -> bool:
	if data.is_empty():
		var f = FileAccess.open("res://Assets/composer/trees/manifest.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				data = parsed
	return not data.is_empty()

static func species(sprite: String) -> String:
	if sprite == "tree_birch": return "birch"
	if sprite == "tree_pine": return "pine"
	return "oak"

static func region(canvas: CanvasItem, kind: String, frame: String, position: Vector2, height: float, angle: float = 0.0) -> void:
	if not data[kind]["frames"].has(frame): return
	if not textures.has(kind):
		textures[kind] = ComposerAssets.texture("../trees/" + kind + ".png")
	var tex = textures[kind]
	if tex == null: return
	var r: Array = data[kind]["frames"][frame]
	var width = height * float(r[2]) / float(r[3])
	canvas.draw_set_transform(position,angle)
	canvas.draw_texture_rect_region(tex,Rect2(-width*.5,-height,width,height),Rect2(r[0],r[1],r[2],r[3]))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

static func draw_tree(canvas: CanvasItem, node: Dictionary, foot: Vector2, now: float) -> bool:
	if not ready_pack() or node.get("category","") != "wood" or not String(node.get("original_sprite","")).begins_with("tree_"): return false
	var kind = species(node["original_sprite"])
	var stage = String(node.get("tree_stage","standing"))
	var height = 46.0 if kind == "pine" else 40.0
	if stage == "stump" or stage == "logs" or stage == "falling":
		region(canvas,kind,"stump",foot,8.0)
	if stage == "logs":
		region(canvas,kind,"logs",foot+Vector2(9,3),10.0)
	elif stage == "falling":
		var t = clampf((now-float(node.get("fall_start",now)))/1.2,0,1)
		if t < 1:
			region(canvas,kind,"cut",foot, height, t*t*PI*.5)
		else:
			region(canvas,kind,"logs",foot+Vector2(9,3),10.0)
	elif stage != "stump":
		var hit_time = now-float(node.get("last_chop_time",-100))
		var angle = sin(hit_time*35)*.035*(1-hit_time/.5) if hit_time >= 0 and hit_time < .5 else sin(now*1.3+foot.x)*.012
		region(canvas,kind,"cut" if int(node.get("chop_hits",0))>0 else "standing",foot,height,angle)
		if hit_time >= 0 and hit_time < .8:
			for i in range(3):
				region(canvas,kind,"chip%d" % i,foot+Vector2((i-1)*hit_time*18,-height*.18-hit_time*18+hit_time*hit_time*30),1.7,hit_time*(i+2))
	return true
