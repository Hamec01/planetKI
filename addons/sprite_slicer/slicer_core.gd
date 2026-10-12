@tool
class_name SpriteSlicerCore
extends RefCounted

## Чистая логика нарезки спрайт-листов — порт tools/sprite_slicer/slicer_core.py на GDScript,
## чтобы работать прямо внутри редактора Godot без внешних зависимостей (Python/PIL не нужны).
##
## Пайплайн для одного кадра:
##   1. sample_bg_color   — определить цвет фона (обычно угол листа)
##   2. detect_grid_axis  — найти границы строк/колонок по "швам" фона
##   3. crop_percent      — (опционально) вручную отсечь долю ячейки (например, убрать скелета)
##   4. chroma_key        — сделать фон прозрачным, с плавным затуханием на границе
##   5. trim_to_content   — обрезать по границе непрозрачного содержимого


static func sample_bg_color(img: Image, x: int = 2, y: int = 2) -> Color:
	x = clampi(x, 0, img.get_width() - 1)
	y = clampi(y, 0, img.get_height() - 1)
	return img.get_pixel(x, y)


## Возвращает Dictionary: {"boundaries": PackedInt32Array, "gap_runs": Array, "cell_count": int}
static func detect_grid_axis(
	img: Image,
	bg: Color,
	axis: String,
	threshold: float = 0.97,
	min_gap: int = 6,
	color_tol: float = 12.0 / 255.0
) -> Dictionary:
	var w = img.get_width()
	var h = img.get_height()
	var axis_len = w if axis == "col" else h
	var other_len = h if axis == "col" else w

	var bg_mask := PackedByteArray()
	bg_mask.resize(axis_len)

	for i in range(axis_len):
		var bg_count = 0
		for j in range(other_len):
			var px: Color = img.get_pixel(i, j) if axis == "col" else img.get_pixel(j, i)
			if _color_close(px, bg, color_tol):
				bg_count += 1
		var frac = float(bg_count) / float(max(1, other_len))
		bg_mask[i] = 1 if frac > threshold else 0

	var gap_runs = _runs_from_mask(bg_mask, min_gap)

	# Швы у самого края листа — это поля, а не разделители между кадрами (иначе счётчик
	# кадров уезжает на +1 за каждый обнаруженный край — тот самый баг, что был в Python-версии
	# до исправления).
	var content_start = 0
	var content_end = axis_len
	var internal_gaps: Array = []
	for run in gap_runs:
		var s: int = run[0]
		var e: int = run[1]
		if s <= 0:
			content_start = maxi(content_start, e + 1)
		elif e >= axis_len - 1:
			content_end = mini(content_end, s)
		else:
			internal_gaps.append(run)

	var boundaries := PackedInt32Array()
	boundaries.append(content_start)
	for run in internal_gaps:
		boundaries.append(int((run[0] + run[1]) / 2.0))
	boundaries.append(content_end)

	# Убираем дубликаты и сортируем
	var uniq: Dictionary = {}
	for b in boundaries:
		uniq[b] = true
	var sorted_boundaries := PackedInt32Array(uniq.keys())
	sorted_boundaries.sort()

	return {
		"boundaries": sorted_boundaries,
		"gap_runs": gap_runs,
		"cell_count": maxi(0, sorted_boundaries.size() - 1),
	}


static func _color_close(a: Color, b: Color, tol: float) -> bool:
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return (dr * dr + dg * dg + db * db) < (tol * tol)


static func _runs_from_mask(mask: PackedByteArray, min_gap: int) -> Array:
	var runs: Array = []
	var start = -1
	var n = mask.size()
	for i in range(n):
		if mask[i] == 1 and start == -1:
			start = i
		elif mask[i] == 0 and start != -1:
			if i - start >= min_gap:
				runs.append([start, i - 1])
			start = -1
	if start != -1 and n - start >= min_gap:
		runs.append([start, n - 1])
	return runs


static func uniform_boundaries(axis_len: int, count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if count <= 0:
		result.append(0)
		result.append(axis_len)
		return result
	var step = float(axis_len) / float(count)
	for i in range(count + 1):
		result.append(int(round(i * step)))
	return result


static func crop_percent(img: Image, left: float, right: float, top: float, bottom: float) -> Image:
	var w = img.get_width()
	var h = img.get_height()
	var x0 = int(w * (left / 100.0))
	var x1 = int(w * (1.0 - right / 100.0))
	var y0 = int(h * (top / 100.0))
	var y1 = int(h * (1.0 - bottom / 100.0))
	x1 = maxi(x0 + 1, x1)
	y1 = maxi(y0 + 1, y1)
	x1 = mini(x1, w)
	y1 = mini(y1, h)
	return img.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))


## Убирает фон: пиксели ближе tol к фону становятся прозрачными, полоса между tol и
## edge_tol плавно затухает (чтобы не было цветной окантовки на границе персонажа).
## tol/edge_tol заданы в той же шкале 0-255, что и в Python-версии, для единообразия.
static func chroma_key(img: Image, bg: Color, tol: float = 24.0, edge_tol: float = 48.0) -> Image:
	var out := img.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	var w = out.get_width()
	var h = out.get_height()
	var tol01 = tol / 255.0
	var edge_tol01 = edge_tol / 255.0
	var denom = maxf(0.0001, edge_tol01 - tol01)

	for y in range(h):
		for x in range(w):
			var px = out.get_pixel(x, y)
			var dr = px.r - bg.r
			var dg = px.g - bg.g
			var db = px.b - bg.b
			var dist = sqrt(dr * dr + dg * dg + db * db)
			if dist < tol01:
				px.a = 0.0
				out.set_pixel(x, y, px)
			elif dist < edge_tol01:
				var fade = clampf((dist - tol01) / denom, 0.0, 1.0)
				px.a *= fade
				out.set_pixel(x, y, px)
	return out


## Обрезает изображение по границе непрозрачного содержимого (аналог PIL Image.getbbox()).
static func trim_to_content(img: Image) -> Image:
	var w = img.get_width()
	var h = img.get_height()
	var min_x = w
	var min_y = h
	var max_x = -1
	var max_y = -1

	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)

	if max_x < min_x or max_y < min_y:
		return img  # полностью прозрачное изображение — обрезать нечего
	return img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


static func process_cell(
	sheet: Image,
	cell_box: Rect2i,
	bg: Color,
	tol: float,
	edge_tol: float,
	crop_left: float = 0.0,
	crop_right: float = 0.0,
	crop_top: float = 0.0,
	crop_bottom: float = 0.0
) -> Image:
	var cell = sheet.get_region(cell_box)
	cell.convert(Image.FORMAT_RGBA8)
	if crop_left > 0.0 or crop_right > 0.0 or crop_top > 0.0 or crop_bottom > 0.0:
		cell = crop_percent(cell, crop_left, crop_right, crop_top, crop_bottom)
	var keyed = chroma_key(cell, bg, tol, edge_tol)
	return trim_to_content(keyed)


## Имя экспортируемого файла по схеме {тип_юнита}_{действие}_{вариант}.png — контракт между
## инструментом и игрой: код в игре ищет файл по job_id + текущему действию, без хардкода
## каждого юнита. При total<=1 суффикс варианта не добавляется.
static func build_export_filename(unit: String, action: String, variant_index: int, total: int) -> String:
	var unit_slug = unit.strip_edges().to_lower().replace(" ", "_")
	if unit_slug == "":
		unit_slug = "unit"
	var action_slug = action.strip_edges().to_lower().replace(" ", "_")
	if action_slug == "":
		action_slug = "frame"
	if total <= 1:
		return "%s_%s.png" % [unit_slug, action_slug]
	var letter: String
	if variant_index < 26:
		letter = char(97 + variant_index)  # 'a' + index
	else:
		letter = str(variant_index + 1)
	return "%s_%s_%s.png" % [unit_slug, action_slug, letter]


static func resize_to_height(img: Image, target_h: float) -> Image:
	var w = img.get_width()
	var h = img.get_height()
	if h <= 0:
		return img
	var scale = target_h / float(h)
	var new_w = maxi(1, int(round(w * scale)))
	var new_h = maxi(1, int(round(target_h)))
	# Resource.duplicate() возвращает статический тип Resource, хотя по факту это Image —
	# явный каст нужен, иначе GDScript не даст вызвать resize() на переменной.
	var out = img.duplicate() as Image
	out.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)
	return out
