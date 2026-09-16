class_name MapCamera
extends Camera2D

var zoom_target: Vector2 = Vector2(1.4, 1.4)
var zoom_speed: float = 12.0
var min_zoom: float = 0.35
var max_zoom: float = 2.8

var pan_speed: float = 800.0
var is_dragging: bool = false

var map_bounds_rect: Rect2 = Rect2(0, 0, 5120, 5120)

func _ready() -> void:
	zoom = Vector2(1.4, 1.4)
	zoom_target = zoom
	EventBus.world_generated.connect(_on_world_generated)

func _on_world_generated(world_data: Dictionary) -> void:
	var w = world_data.get("width", 160)
	var h = world_data.get("height", 160)
	var tile_sz = 32.0
	map_bounds_rect = Rect2(0, 0, w * tile_sz, h * tile_sz)

func _process(delta: float) -> void:
	# Плавная интерполяция зума строго с фиксацией точки под курсором мыши
	if zoom.distance_to(zoom_target) > 0.001:
		var prev_zoom = zoom.x
		zoom = zoom.lerp(zoom_target, clampf(zoom_speed * delta, 0.0, 1.0))
		var cur_zoom = zoom.x
		
		# Корректируем позицию камеры так, чтобы мир под курсором мыши не смещался
		var mouse_viewport = get_viewport().get_mouse_position()
		var vp_center = get_viewport_rect().size * 0.5
		var mouse_offset = mouse_viewport - vp_center
		position += mouse_offset * (1.0 / prev_zoom - 1.0 / cur_zoom)
		_clamp_position()
	
	var focused = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
		
	# Перемещение клавиатурой (WASD / Стрелки)
	var move_vec = Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_vec.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_vec.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_vec.y += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_vec.y -= 1.0
		
	if move_vec != Vector2.ZERO:
		position += move_vec.normalized() * (pan_speed / zoom.x) * delta
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	# Зум колесиком мыши
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom_step(1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom_step(1.0 / 1.2)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_dragging = true
			else:
				is_dragging = false
				
	elif event is InputEventMouseMotion and is_dragging:
		position -= event.relative / zoom.x
		_clamp_position()

func _apply_zoom_step(factor: float) -> void:
	var new_zoom_val = clampf(zoom_target.x * factor, min_zoom, max_zoom)
	zoom_target = Vector2(new_zoom_val, new_zoom_val)

func focus_on(target_pos: Vector2, target_zoom: float = 1.4) -> void:
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", target_pos, 0.45)
	zoom_target = Vector2(target_zoom, target_zoom)
	tween.tween_property(self, "zoom", zoom_target, 0.45)

func _clamp_position() -> void:
	position.x = clampf(position.x, map_bounds_rect.position.x, map_bounds_rect.end.x)
	position.y = clampf(position.y, map_bounds_rect.position.y, map_bounds_rect.end.y)

func focus_on_tile(tile_coord: Vector2i, tile_size: float = 32.0) -> void:
	position = Vector2(tile_coord.x * tile_size + tile_size * 0.5, tile_coord.y * tile_size + tile_size * 0.5)
	zoom_target = Vector2(1.4, 1.4)
	zoom = zoom_target
	_clamp_position()


