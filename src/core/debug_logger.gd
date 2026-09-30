class_name DebugLogger
extends RefCounted

# ==============================================================================
# PLANETKI — LIVE REAL-TIME SIMULATION LOGGER & DIAGNOSTICS
# ==============================================================================

static var log_buffer: Array[Dictionary] = []
static var max_entries: int = 150
static var log_file_path: String = "user://planetki_debug.log"
static var file_handle: FileAccess = null

static func log_info(category: String, message: String) -> void:
	_append_log("INFO", category, message)

static func log_warn(category: String, message: String) -> void:
	_append_log("WARN", category, message)

static func log_error(category: String, message: String) -> void:
	_append_log("ERROR", category, message)

static func _append_log(level: String, category: String, message: String) -> void:
	var time_str = Time.get_time_string_from_system()
	var day_str = "D%d H%d" % [GameManager.current_day if GameManager else 1, int(GameManager.current_hour) if GameManager else 12]
	var entry = {
		"time": time_str,
		"day_hour": day_str,
		"level": level,
		"category": category,
		"message": message
	}
	log_buffer.append(entry)
	if log_buffer.size() > max_entries:
		log_buffer.pop_front()
		
	var formatted = "[%s][%s][%s][%s] %s" % [time_str, day_str, level, category, message]
	print(formatted)
	
	# Запись в файл на диске
	var fa = FileAccess.open(log_file_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_file_path) else FileAccess.WRITE)
	if fa:
		fa.seek_end()
		fa.store_line(formatted)
		fa.flush()

static func get_recent_logs() -> Array[Dictionary]:
	return log_buffer

static func get_full_log_text() -> String:
	var lines: Array[String] = []
	for entry in log_buffer:
		lines.append("[%s][%s] %s: %s" % [entry["time"], entry["level"], entry["category"], entry["message"]])
	return "\n".join(lines)
