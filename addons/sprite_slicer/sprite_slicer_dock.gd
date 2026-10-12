@tool
extends Control

## Панель Sprite Slicer: открыть спрайт-лист, авто-детект/ручная сетка, обрезка лишнего
## персонажа, удаление фона, экспорт кадров в Assets — не выходя из редактора Godot.

const Core = preload("res://addons/sprite_slicer/slicer_core.gd")

var sheet: Image
var sheet_path: String = ""
var bg_color: Color = Color.WHITE
var col_boundaries: PackedInt32Array = PackedInt32Array()
var row_boundaries: PackedInt32Array = PackedInt32Array()
var selected_cells: Dictionary = {}  # "row_col" -> true
var preview_cell: Vector2i = Vector2i(-1, -1)
var pick_bg_mode: bool = false
var display_scale: float = 1.0

# --- UI-ноды (создаются в _ready) ---
var open_btn: Button
var pick_bg_check: CheckButton
var bg_swatch: ColorRect
var bg_manual_picker: ColorPickerButton
var status_label: Label
var canvas: SlicerCanvas
var threshold_slider: HSlider
var auto_detect_btn: Button
var cols_spin: SpinBox
var rows_spin: SpinBox
var tol_slider: HSlider
var edge_tol_slider: HSlider
var crop_left_spin: SpinBox
var crop_right_spin: SpinBox
var crop_top_spin: SpinBox
var crop_bottom_spin: SpinBox
var select_all_btn: Button
var select_none_btn: Button
var sel_count_label: Label
var preview_before: TextureRect
var preview_after: TextureRect
var preview_scaled: TextureRect
var preview_dims_label: Label
var export_btn: Button
var unit_type_edit: LineEdit
var action_edit: LineEdit
var export_preview_label: Label

var play_btn: Button
var fps_spin: SpinBox
var play_frame_label: Label
var play_true_rect: TextureRect
var play_mag_rect: TextureRect
var play_timer: Timer
var is_playing: bool = false
var play_index: int = 0

var open_dialog: FileDialog
var export_dialog: FileDialog


func _ready() -> void:
	custom_minimum_size = Vector2(420, 600)
	_build_ui()


func _build_ui() -> void:
	var root_v = VBoxContainer.new()
	root_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_v)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(margin)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	# --- Открыть лист ---
	open_btn = Button.new()
	open_btn.text = "Открыть спрайт-лист…"
	open_btn.pressed.connect(_on_open_pressed)
	v.add_child(open_btn)

	status_label = Label.new()
	status_label.text = "Файл не загружен"
	status_label.modulate = Color(1, 1, 1, 0.6)
	v.add_child(status_label)

	# --- Цвет фона ---
	var bg_row = HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 6)
	v.add_child(bg_row)

	pick_bg_check = CheckButton.new()
	pick_bg_check.text = "Пипетка (клик по листу)"
	pick_bg_check.toggled.connect(func(on): pick_bg_mode = on)
	bg_row.add_child(pick_bg_check)

	bg_swatch = ColorRect.new()
	bg_swatch.custom_minimum_size = Vector2(24, 24)
	bg_swatch.color = bg_color
	bg_row.add_child(bg_swatch)

	bg_manual_picker = ColorPickerButton.new()
	bg_manual_picker.text = "Цвет вручную"
	bg_manual_picker.custom_minimum_size = Vector2(120, 0)
	bg_manual_picker.color = bg_color
	bg_manual_picker.color_changed.connect(_on_bg_color_selected)
	bg_row.add_child(bg_manual_picker)

	v.add_child(HSeparator.new())

	# --- Холст ---
	var canvas_frame = PanelContainer.new()
	canvas_frame.custom_minimum_size = Vector2(0, 340)
	v.add_child(canvas_frame)

	canvas = SlicerCanvas.new()
	canvas.dock = self
	canvas_frame.add_child(canvas)

	var legend = Label.new()
	legend.text = "Зелёная рамка — кадр выбран для экспорта. Жёлтая — кадр в предпросмотре. Клик — выбрать/снять."
	legend.modulate = Color(1, 1, 1, 0.6)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(legend)

	v.add_child(HSeparator.new())

	# --- Сетка ---
	var grid_label = Label.new()
	grid_label.text = "Сетка кадров"
	grid_label.add_theme_font_size_override("font_size", 14)
	v.add_child(grid_label)

	v.add_child(_labeled_slider("Чувствительность авто-детекта", func(s): threshold_slider = s, 0.80, 0.999, 0.97, 0.001))

	auto_detect_btn = Button.new()
	auto_detect_btn.text = "Авто-детект сетки"
	auto_detect_btn.pressed.connect(_on_auto_detect_pressed)
	v.add_child(auto_detect_btn)

	var grid_row = HBoxContainer.new()
	grid_row.add_theme_constant_override("separation", 12)
	v.add_child(grid_row)

	grid_row.add_child(_labeled_spinbox("Колонок:", func(s): cols_spin = s, 1, 60, 1, _on_manual_grid_changed))
	grid_row.add_child(_labeled_spinbox("Строк:", func(s): rows_spin = s, 1, 60, 1, _on_manual_grid_changed))

	var hint = Label.new()
	hint.text = "Если авто-детект ошибся — поправь числа руками."
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)

	v.add_child(HSeparator.new())

	# --- Удаление фона ---
	var key_label = Label.new()
	key_label.text = "Удаление фона"
	key_label.add_theme_font_size_override("font_size", 14)
	v.add_child(key_label)

	v.add_child(_labeled_slider("Допуск (порог прозрачности)", func(s): tol_slider = s, 0, 120, 24, 1, _on_key_params_changed))
	v.add_child(_labeled_slider("Плавность границы (feather)", func(s): edge_tol_slider = s, 0, 150, 48, 1, _on_key_params_changed))

	v.add_child(HSeparator.new())

	# --- Ручная обрезка ---
	var crop_label = Label.new()
	crop_label.text = "Ручная обрезка кадра (%) — убрать лишнего персонажа"
	crop_label.add_theme_font_size_override("font_size", 14)
	crop_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(crop_label)

	var crop_row = GridContainer.new()
	crop_row.columns = 4
	crop_row.add_theme_constant_override("h_separation", 8)
	v.add_child(crop_row)

	crop_row.add_child(_labeled_spinbox("Слева", func(s): crop_left_spin = s, 0, 90, 0, _on_key_params_changed))
	crop_row.add_child(_labeled_spinbox("Справа", func(s): crop_right_spin = s, 0, 90, 0, _on_key_params_changed))
	crop_row.add_child(_labeled_spinbox("Сверху", func(s): crop_top_spin = s, 0, 90, 0, _on_key_params_changed))
	crop_row.add_child(_labeled_spinbox("Снизу", func(s): crop_bottom_spin = s, 0, 90, 0, _on_key_params_changed))

	v.add_child(HSeparator.new())

	# --- Выбор кадров ---
	var sel_row = HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 8)
	v.add_child(sel_row)

	select_all_btn = Button.new()
	select_all_btn.text = "Выбрать все"
	select_all_btn.pressed.connect(_on_select_all)
	sel_row.add_child(select_all_btn)

	select_none_btn = Button.new()
	select_none_btn.text = "Снять выбор"
	select_none_btn.pressed.connect(_on_select_none)
	sel_row.add_child(select_none_btn)

	sel_count_label = Label.new()
	sel_count_label.text = "Выбрано: 0"
	sel_row.add_child(sel_count_label)

	v.add_child(HSeparator.new())

	# --- Проигрыватель: прогоняет выбранные кадры в порядке клика как анимацию ---
	var player_label = Label.new()
	player_label.text = "Проигрыватель (выбранные кадры по порядку клика)"
	player_label.add_theme_font_size_override("font_size", 14)
	v.add_child(player_label)

	var player_row = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	v.add_child(player_row)

	play_btn = Button.new()
	play_btn.text = "▶ Играть"
	play_btn.pressed.connect(_on_play_toggle)
	player_row.add_child(play_btn)

	var fps_lbl = Label.new()
	fps_lbl.text = "Кадров/сек:"
	player_row.add_child(fps_lbl)

	fps_spin = SpinBox.new()
	fps_spin.min_value = 1
	fps_spin.max_value = 24
	fps_spin.value = 6
	fps_spin.value_changed.connect(_on_fps_changed)
	player_row.add_child(fps_spin)

	play_frame_label = Label.new()
	play_frame_label.text = "кадр —/—"
	player_row.add_child(play_frame_label)

	var play_prev_row = HBoxContainer.new()
	play_prev_row.add_theme_constant_override("separation", 8)
	v.add_child(play_prev_row)
	play_true_rect = _make_preview_box(play_prev_row, "Истинный размер")
	play_mag_rect = _make_preview_box(play_prev_row, "Увеличено ×10")

	play_timer = Timer.new()
	play_timer.one_shot = false
	play_timer.timeout.connect(_on_play_tick)
	add_child(play_timer)

	v.add_child(HSeparator.new())

	# --- Предпросмотр ---
	var prev_label = Label.new()
	prev_label.text = "Предпросмотр выбранного кадра"
	prev_label.add_theme_font_size_override("font_size", 14)
	v.add_child(prev_label)

	var prev_row = HBoxContainer.new()
	prev_row.add_theme_constant_override("separation", 8)
	v.add_child(prev_row)

	preview_before = _make_preview_box(prev_row, "Было")
	preview_after = _make_preview_box(prev_row, "Стало")
	preview_scaled = _make_preview_box(prev_row, "Игра ×8")

	preview_dims_label = Label.new()
	preview_dims_label.text = "—"
	preview_dims_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(preview_dims_label)

	v.add_child(HSeparator.new())

	var export_label = Label.new()
	export_label.text = "Экспорт — имя файла = тип_юнита + действие + вариант"
	export_label.add_theme_font_size_override("font_size", 14)
	v.add_child(export_label)

	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	v.add_child(name_row)

	var unit_col = VBoxContainer.new()
	unit_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(unit_col)
	var unit_lbl = Label.new()
	unit_lbl.text = "Тип юнита (job_id)"
	unit_col.add_child(unit_lbl)
	unit_type_edit = LineEdit.new()
	unit_type_edit.text = "warrior"
	unit_type_edit.text_changed.connect(func(_t): _update_export_preview())
	unit_col.add_child(unit_type_edit)

	var action_col = VBoxContainer.new()
	action_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(action_col)
	var action_lbl = Label.new()
	action_lbl.text = "Действие"
	action_col.add_child(action_lbl)
	action_edit = LineEdit.new()
	action_edit.text = "attack"
	action_edit.text_changed.connect(func(_t): _update_export_preview())
	action_col.add_child(action_edit)

	export_preview_label = Label.new()
	export_preview_label.text = "Пример: —"
	export_preview_label.modulate = Color(1, 1, 1, 0.6)
	export_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(export_preview_label)

	export_btn = Button.new()
	export_btn.text = "Экспортировать выбранные кадры…"
	export_btn.pressed.connect(_on_export_pressed)
	v.add_child(export_btn)

	# --- Диалоги ---
	open_dialog = FileDialog.new()
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.add_filter("*.png,*.webp,*.jpg,*.jpeg", "Изображения")
	open_dialog.file_selected.connect(_on_sheet_selected)
	open_dialog.size = Vector2i(800, 600)
	add_child(open_dialog)

	export_dialog = FileDialog.new()
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	export_dialog.dir_selected.connect(_on_export_dir_selected)
	export_dialog.size = Vector2i(800, 600)
	add_child(export_dialog)


func _labeled_slider(label_text: String, assign: Callable, min_v: float, max_v: float, default_v: float, step: float, on_change: Callable = Callable()) -> VBoxContainer:
	var box = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	box.add_child(lbl)
	var slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = default_v
	if on_change.is_valid():
		slider.value_changed.connect(func(_v): on_change.call())
	box.add_child(slider)
	assign.call(slider)
	return box


func _labeled_spinbox(label_text: String, assign: Callable, min_v: float, max_v: float, default_v: float, on_change: Callable) -> VBoxContainer:
	var box = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	box.add_child(lbl)
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = default_v
	spin.value_changed.connect(func(_v): on_change.call())
	box.add_child(spin)
	assign.call(spin)
	return box


func _make_preview_box(parent: Control, title: String) -> TextureRect:
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var lbl = Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	var rect = TextureRect.new()
	rect.custom_minimum_size = Vector2(100, 100)
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(rect)
	return rect


# ------------------------------------------------------------------ события

func _on_open_pressed() -> void:
	open_dialog.popup_centered()


func _on_sheet_selected(path: String) -> void:
	var img = Image.new()
	var err = img.load(path)
	if err != OK:
		push_error("Sprite Slicer: не удалось открыть файл: %s (код %d)" % [path, err])
		status_label.text = "Ошибка открытия файла"
		return

	sheet = img
	sheet_path = path
	bg_color = Core.sample_bg_color(img)
	bg_swatch.color = bg_color
	bg_manual_picker.color = bg_color
	col_boundaries = PackedInt32Array()
	row_boundaries = PackedInt32Array()
	selected_cells.clear()
	preview_cell = Vector2i(-1, -1)
	status_label.text = "%s — %dx%d px" % [path.get_file(), img.get_width(), img.get_height()]
	canvas.queue_redraw()
	_on_auto_detect_pressed()


func _on_bg_color_selected(color: Color) -> void:
	bg_color = color
	bg_swatch.color = color
	_refresh_preview()


func _on_auto_detect_pressed() -> void:
	if sheet == null:
		return
	var thr = threshold_slider.value
	var cols_res = Core.detect_grid_axis(sheet, bg_color, "col", thr, 6)
	var rows_res = Core.detect_grid_axis(sheet, bg_color, "row", thr, 6)

	if cols_res["cell_count"] < 1 or rows_res["cell_count"] < 1:
		status_label.text = "Авто-детект не нашёл сетку — поправь фон/чувствительность"
		return

	col_boundaries = cols_res["boundaries"]
	row_boundaries = rows_res["boundaries"]
	cols_spin.set_value_no_signal(cols_res["cell_count"])
	rows_spin.set_value_no_signal(rows_res["cell_count"])
	selected_cells.clear()
	preview_cell = Vector2i(-1, -1)
	status_label.text = "%s — сетка %dx%d (авто)" % [sheet_path.get_file(), cols_res["cell_count"], rows_res["cell_count"]]
	_update_sel_count()
	canvas.queue_redraw()


func _on_manual_grid_changed() -> void:
	if sheet == null:
		return
	var cols_n = maxi(1, int(cols_spin.value))
	var rows_n = maxi(1, int(rows_spin.value))
	col_boundaries = Core.uniform_boundaries(sheet.get_width(), cols_n)
	row_boundaries = Core.uniform_boundaries(sheet.get_height(), rows_n)

	var kept: Dictionary = {}
	for key in selected_cells.keys():
		var parts = key.split("_")
		var r = int(parts[0])
		var c = int(parts[1])
		if r < rows_n and c < cols_n:
			kept[key] = true
	selected_cells = kept

	status_label.text = "%s — сетка %dx%d (вручную)" % [sheet_path.get_file(), cols_n, rows_n]
	_update_sel_count()
	canvas.queue_redraw()
	_refresh_preview()


func _on_key_params_changed() -> void:
	_refresh_preview()


func _on_select_all() -> void:
	if not _grid_ready():
		return
	selected_cells.clear()
	for r in range(row_boundaries.size() - 1):
		for c in range(col_boundaries.size() - 1):
			selected_cells["%d_%d" % [r, c]] = true
	_update_sel_count()
	canvas.queue_redraw()


func _on_select_none() -> void:
	selected_cells.clear()
	_update_sel_count()
	canvas.queue_redraw()


func _update_sel_count() -> void:
	sel_count_label.text = "Выбрано: %d" % selected_cells.size()
	_update_export_preview()
	_stop_playback()


func _update_export_preview() -> void:
	if export_preview_label == null:
		return
	var total = maxi(1, selected_cells.size())
	var unit = unit_type_edit.text if unit_type_edit else "warrior"
	var action = action_edit.text if action_edit else "attack"
	var names := PackedStringArray()
	for i in range(mini(total, 3)):
		names.append(Core.build_export_filename(unit, action, i, total))
	var suffix = ", …" if total > 3 else ""
	export_preview_label.text = "Пример (%d шт.): %s%s" % [total, ", ".join(names), suffix]


func _grid_ready() -> bool:
	return sheet != null and col_boundaries.size() >= 2 and row_boundaries.size() >= 2


func cell_box(row: int, col: int) -> Rect2i:
	if row + 1 >= row_boundaries.size() or col + 1 >= col_boundaries.size():
		return Rect2i()
	return Rect2i(
		col_boundaries[col], row_boundaries[row],
		col_boundaries[col + 1] - col_boundaries[col],
		row_boundaries[row + 1] - row_boundaries[row]
	)


## Вызывается холстом при клике по кадру (или для пипетки фона).
func on_canvas_clicked(img_x: int, img_y: int) -> void:
	if sheet == null:
		return

	if pick_bg_mode:
		if img_x >= 0 and img_x < sheet.get_width() and img_y >= 0 and img_y < sheet.get_height():
			bg_color = sheet.get_pixel(img_x, img_y)
			bg_swatch.color = bg_color
			bg_manual_picker.color = bg_color
			pick_bg_check.button_pressed = false
			pick_bg_mode = false
			_refresh_preview()
		return

	if not _grid_ready():
		return

	var col = _index_for(img_x, col_boundaries)
	var row = _index_for(img_y, row_boundaries)
	if col == -1 or row == -1:
		return

	var key = "%d_%d" % [row, col]
	if selected_cells.has(key):
		selected_cells.erase(key)
	else:
		selected_cells[key] = true
	preview_cell = Vector2i(row, col)
	_update_sel_count()
	canvas.queue_redraw()
	_refresh_preview()


static func _index_for(pos: int, boundaries: PackedInt32Array) -> int:
	for i in range(boundaries.size() - 1):
		if pos >= boundaries[i] and pos < boundaries[i + 1]:
			return i
	return -1


func _refresh_preview() -> void:
	if preview_cell.x < 0 or not _grid_ready():
		return
	var row = preview_cell.x
	var col = preview_cell.y
	var box = cell_box(row, col)
	if box.size.x <= 0 or box.size.y <= 0:
		return

	var raw_cell = sheet.get_region(box)
	var processed = Core.process_cell(
		sheet, box, bg_color,
		tol_slider.value, edge_tol_slider.value,
		crop_left_spin.value, crop_right_spin.value, crop_top_spin.value, crop_bottom_spin.value
	)

	preview_before.texture = ImageTexture.create_from_image(raw_cell)
	preview_after.texture = ImageTexture.create_from_image(processed)

	var game_scale = Core.resize_to_height(processed, 12.0)
	var big = game_scale.duplicate() as Image
	big.resize(game_scale.get_width() * 8, game_scale.get_height() * 8, Image.INTERPOLATE_NEAREST)
	preview_scaled.texture = ImageTexture.create_from_image(big)

	preview_dims_label.text = "исходный %dx%d → обработан %dx%d → игра ~12px высотой" % [
		raw_cell.get_width(), raw_cell.get_height(), processed.get_width(), processed.get_height()
	]


func _on_export_pressed() -> void:
	if selected_cells.is_empty():
		status_label.text = "Выбери хотя бы один кадр (клик по нему на листе)"
		return
	export_dialog.popup_centered()


func _on_export_dir_selected(dir_path: String) -> void:
	var crop = [crop_left_spin.value, crop_right_spin.value, crop_top_spin.value, crop_bottom_spin.value]
	var unit = unit_type_edit.text
	var action = action_edit.text
	# Dictionary в Godot 4 сохраняет порядок вставки — это и есть порядок клика по кадрам,
	# важный для букв-вариантов a/b/c и для совпадения с порядком в проигрывателе.
	var keys = selected_cells.keys()
	var total = keys.size()
	var saved = 0
	for i in range(total):
		var parts: PackedStringArray = String(keys[i]).split("_")
		var row = int(parts[0])
		var col = int(parts[1])
		var box = cell_box(row, col)
		if box.size.x <= 0 or box.size.y <= 0:
			continue
		var processed = Core.process_cell(
			sheet, box, bg_color, tol_slider.value, edge_tol_slider.value,
			crop[0], crop[1], crop[2], crop[3]
		)
		var filename = Core.build_export_filename(unit, action, i, total)
		var out_path = dir_path.path_join(filename)
		processed.save_png(out_path)
		saved += 1

	status_label.text = "Экспортировано кадров: %d → %s" % [saved, dir_path]


# --------------------------------------------------------------- проигрыватель

func _on_fps_changed(_v: float) -> void:
	if is_playing:
		play_timer.wait_time = 1.0 / maxf(1.0, fps_spin.value)


func _on_play_toggle() -> void:
	if is_playing:
		_stop_playback()
		return
	if selected_cells.is_empty():
		status_label.text = "Выбери хотя бы один кадр (клик по нему на листе)"
		return
	is_playing = true
	play_index = 0
	play_btn.text = "⏸ Стоп"
	play_timer.wait_time = 1.0 / maxf(1.0, fps_spin.value)
	play_timer.start()
	_on_play_tick()


func _stop_playback() -> void:
	play_timer.stop()
	if is_playing:
		is_playing = false
		play_btn.text = "▶ Играть"


func _on_play_tick() -> void:
	var keys = selected_cells.keys()
	if keys.is_empty():
		_stop_playback()
		return

	play_index = play_index % keys.size()
	var parts: PackedStringArray = String(keys[play_index]).split("_")
	var row = int(parts[0])
	var col = int(parts[1])
	var box = cell_box(row, col)
	if box.size.x > 0 and box.size.y > 0:
		var processed = Core.process_cell(
			sheet, box, bg_color, tol_slider.value, edge_tol_slider.value,
			crop_left_spin.value, crop_right_spin.value, crop_top_spin.value, crop_bottom_spin.value
		)
		var true_size = Core.resize_to_height(processed, 12.0)
		var mag = true_size.duplicate() as Image
		mag.resize(true_size.get_width() * 10, true_size.get_height() * 10, Image.INTERPOLATE_NEAREST)

		play_true_rect.texture = ImageTexture.create_from_image(true_size)
		play_mag_rect.texture = ImageTexture.create_from_image(mag)
		play_frame_label.text = "кадр %d/%d" % [play_index + 1, keys.size()]

	play_index += 1


# ============================================================================
# Внутренний класс: холст с листом, сеткой и обработкой кликов
# ============================================================================
class SlicerCanvas extends Control:
	# Без явного типа (не Control) — иначе GDScript откажется собирать скрипт: у Control
	# нет полей вроде sheet/col_boundaries, которые реально есть у внешнего дока.
	# Динамический доступ проверяется в рантайме, а не статическим анализатором.
	var dock

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 320)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		if dock == null or dock.sheet == null:
			return

		var sw = dock.sheet.get_width()
		var sh = dock.sheet.get_height()
		var avail = get_rect().size
		var scale = minf(minf(avail.x / float(sw), avail.y / float(sh)), 1.0)
		dock.display_scale = scale

		var tex = ImageTexture.create_from_image(dock.sheet)
		var disp_size = Vector2(sw * scale, sh * scale)
		draw_texture_rect(tex, Rect2(Vector2.ZERO, disp_size), false)

		for x in dock.col_boundaries:
			var xd = x * scale
			draw_line(Vector2(xd, 0), Vector2(xd, disp_size.y), Color(1, 0.31, 0.31, 0.9), 1.0)
		for y in dock.row_boundaries:
			var yd = y * scale
			draw_line(Vector2(0, yd), Vector2(disp_size.x, yd), Color(1, 0.31, 0.31, 0.9), 1.0)

		for key in dock.selected_cells.keys():
			var parts = key.split("_")
			var r = int(parts[0])
			var c = int(parts[1])
			var box: Rect2i = dock.cell_box(r, c)
			if box.size.x <= 0:
				continue
			var r0 = Rect2(Vector2(box.position) * scale, Vector2(box.size) * scale)
			draw_rect(r0, Color(0.3, 0.8, 0.3, 0.9), false, 2.0)

		if dock.preview_cell.x >= 0:
			var box: Rect2i = dock.cell_box(dock.preview_cell.x, dock.preview_cell.y)
			if box.size.x > 0:
				var r0 = Rect2(Vector2(box.position) * scale, Vector2(box.size) * scale)
				draw_rect(r0, Color(1.0, 0.84, 0.29, 0.95), false, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if dock == null or dock.sheet == null:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if dock.display_scale <= 0.0:
				return
			var img_x = int(event.position.x / dock.display_scale)
			var img_y = int(event.position.y / dock.display_scale)
			dock.on_canvas_clicked(img_x, img_y)
