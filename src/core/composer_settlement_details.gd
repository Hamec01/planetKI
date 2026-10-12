class_name ComposerSettlementDetails
extends RefCounted

## Optional complete-state layers and real equipped tools. Original state atlases
## remain the fallback for construction, damage and ruins.
static var loaded := false
static var valid := false
static var buildings: Dictionary = {}
static var equipment: Dictionary = {}
static var mechanisms: Dictionary = {}

static func ready_pack() -> bool:
	if loaded:
		return valid
	loaded = true
	for file in ["layers.json", "equipment.json", "mechanisms.json"]:
		var path: String = ComposerBuildings.PACK_ROOT + file
		if not FileAccess.file_exists(path):
			push_error("Settlement details missing: " + path)
			return false
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or int(data.get("version", 0)) != 1:
			push_error("Invalid settlement detail manifest: " + path)
			return false
		if file == "layers.json":
			for b in data.get("buildings", []):
				buildings[String(b["id"])] = b
		elif file == "equipment.json":
			for item in data.get("items", []):
				equipment[String(item["id"])] = item
		else:
			mechanisms = data
	valid = not buildings.is_empty() and not equipment.is_empty() and not mechanisms.is_empty()
	return valid

static func has_layers(id: String) -> bool:
	return ready_pack() and buildings.has(id)

static func rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))

static func draw_layer(canvas: CanvasItem, id: String, role: String, ground: Vector2, tint := Color.WHITE) -> void:
	if not has_layers(id): return
	var b: Dictionary = buildings[id]
	var texture := ComposerBuildings.texture(String(b["file"]))
	if texture == null: return
	for layer in b["layers"]:
		if layer["id"] != role: continue
		var source := rect(layer["sourceRect"])
		var offset := Vector2(float(layer["position"][0]), float(layer["position"][1]))
		var size := source.size * float(layer["scale"])
		canvas.draw_texture_rect_region(texture, Rect2(ground + offset * ComposerBuildings.UNIT_SCALE, size * ComposerBuildings.UNIT_SCALE), source, tint)

static func draw_front(canvas: CanvasItem, id: String, ground: Vector2, open: bool) -> void:
	draw_layer(canvas, id, "front", ground, Color(1, 1, 1, 0.22) if open else Color.WHITE)
	if not open:
		draw_layer(canvas, id, "roof", ground)

static func tool_binding(id: String) -> Dictionary:
	ready_pack()
	return equipment.get(id, {})

static func equipped_tool_id(c: CitizenNPC) -> String:
	ready_pack()
	if c.cargo_amount > 0 or c.state == CitizenNPC.State.ATTACKING:
		return ""
	var tool_id := String(c.equipped_tool.get("id", ""))
	if c.has_tool(String(c.equipped_tool.get("type", ""))) and equipment.has(tool_id):
		return tool_id
	# Some inventory adapters store the item ID as the type.
	var tool_type := String(c.equipped_tool.get("type", ""))
	if c.has_tool(tool_type) and equipment.has(tool_type):
		return tool_type
	var weapon := String(c.equipment.get("weapon", ""))
	return weapon if equipment.has(weapon) else ""

static func tool_transform(binding: Dictionary) -> Transform2D:
	var item := ComposerBuildings.get_upgrade_data(String(binding["assetId"]))
	var r: Array = item["sourceRect"]
	var s := float(binding["length"]) / maxf(float(r[2]), float(r[3]))
	var grip := Vector2(float(binding["grip"][0]), float(binding["grip"][1])) * s
	var result := Transform2D(deg_to_rad(float(binding["rotation"])), Vector2.ZERO)
	result.origin = -(result.basis_xform(grip))
	return result

static func draw_equipped_tool(canvas: CanvasItem, c: CitizenNPC, world: Transform2D, frame: Dictionary) -> void:
	var id := equipped_tool_id(c)
	if id == "" or not frame.has("token_weapon"): return
	var binding: Dictionary = equipment[id]
	var item := ComposerBuildings.get_upgrade_data(String(binding["assetId"]))
	var tex := ComposerBuildings.texture(String(item["atlas"]))
	if tex == null: return
	var source := rect(item["sourceRect"])
	var s := float(binding["length"]) / maxf(source.size.x, source.size.y)
	canvas.draw_set_transform_matrix(world * ComposerAssets.matrix(frame["token_weapon"]) * tool_transform(binding))
	canvas.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, source.size * s), source)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

static func flame_index(seconds: float) -> int:
	ready_pack()
	var o: Dictionary = mechanisms["oven"]
	var duration := float(o["durationMs"]) / 1000.0
	return int(floor(fposmod(seconds, duration) / duration * o["flameRects"].size()))

static func _draw_part(canvas: CanvasItem, source: Rect2, width: float, ground: Vector2) -> void:
	var tex := ComposerBuildings.texture(String(mechanisms["file"]))
	if tex == null: return
	var size := source.size * width / source.size.x * ComposerBuildings.UNIT_SCALE
	canvas.draw_texture_rect_region(tex, Rect2(ground - Vector2(size.x / 2.0, size.y), size), source)

static func draw_mechanism(canvas: CanvasItem, id: String, ground: Vector2, active: bool, seconds: float) -> void:
	if not ready_pack(): return
	var k := ComposerBuildings.UNIT_SCALE
	if id == "quern_house":
		var q: Dictionary = mechanisms["quern"]
		_draw_part(canvas, rect(q["baseRect"]), float(q["worldWidth"]), ground)
		var offset := Vector2(float(q["rotorOffset"][0]), float(q["rotorOffset"][1])) * k
		var angle := fposmod(seconds * TAU / (float(q["durationMs"]) / 1000.0), TAU) if active else 0.0
		# Rotate in its horizontal plane BEFORE the isometric projection.
		var projection := Transform2D(Vector2(k, 0), Vector2(0, k * float(q["planeScaleY"])), ground + offset)
		canvas.draw_set_transform_matrix(projection * Transform2D(angle, Vector2.ZERO))
		var width := float(q["rotorWidth"])
		var tex := ComposerBuildings.texture(String(mechanisms["file"]))
		if tex != null:
			canvas.draw_texture_rect_region(tex, Rect2(-width / 2.0, -width / 2.0, width, width), rect(q["rotorRect"]))
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	elif id == "bakery":
		var o: Dictionary = mechanisms["oven"]
		_draw_part(canvas, rect(o["sourceRect"]), float(o["worldWidth"]), ground)
		if active:
			var offset := Vector2(float(o["fireOffset"][0]), float(o["fireOffset"][1])) * k
			_draw_part(canvas, rect(o["flameRects"][flame_index(seconds)]), float(o["fireWidth"]), ground + offset)
