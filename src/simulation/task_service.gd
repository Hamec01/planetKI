class_name TaskService
extends RefCounted

# ==============================================================================
# TASK SERVICE (PLANETKI v2 / РАЗДЕЛЫ 10, 23.3, 24 S03)
# ==============================================================================
# Авторитетный менеджер жизненного цикла задач поселения:
# AVAILABLE -> RESERVED -> IN_PROGRESS -> ARRIVED -> DELIVERING -> COMPLETED
# При невозможности пути: NO_PATH / BLOCKED

enum TaskState {
	AVAILABLE,
	RESERVED,
	IN_PROGRESS,
	ARRIVED,
	DELIVERING,
	COMPLETED,
	BLOCKED,
	NO_PATH,
	CANCELLED
}

# Реестр активных задач: task_instance_id -> Dictionary
var tasks: Dictionary = {}
var _next_task_id: int = 1

func create_task(kind_id: String, target_id: String, target_coord: Vector2i, target_pos: Vector2, source_id: String = "", dest_id: String = "") -> String:
	var t_id = "task_%d" % _next_task_id
	_next_task_id += 1
	tasks[t_id] = {
		"task_instance_id": t_id,
		"kind_id": kind_id,              # "chop_tree", "plant_tree", "gather_food", "mine_stone", "haul", etc.
		"actor_id": "",                  # citizen_id исполнителя
		"target_id": target_id,          # ID сущности/ресурса/здания
		"target_coord": target_coord,    # Vector2i плитки
		"target_pos": target_pos,        # Vector2 в пикселях мира
		"source_container_id": source_id,
		"dest_container_id": dest_id,
		"state": TaskState.AVAILABLE,
		"progress": 0.0,
		"reserved_items": {},            # {"wood": 100.0}
		"cancellation_reason": "",
		"retry_timer": 0.0
	}
	return t_id

func get_task(task_id: String) -> Dictionary:
	return tasks.get(task_id, {})

func assign_actor(task_id: String, citizen_id: String) -> bool:
	if not tasks.has(task_id):
		return false
	var t = tasks[task_id]
	if t["state"] not in [TaskState.AVAILABLE, TaskState.RESERVED]:
		return false
	t["actor_id"] = citizen_id
	t["state"] = TaskState.RESERVED
	return true

func start_task(task_id: String) -> bool:
	if not tasks.has(task_id):
		return false
	tasks[task_id]["state"] = TaskState.IN_PROGRESS
	return true

func set_arrived(task_id: String) -> void:
	if tasks.has(task_id):
		tasks[task_id]["state"] = TaskState.ARRIVED

func set_delivering(task_id: String) -> void:
	if tasks.has(task_id):
		tasks[task_id]["state"] = TaskState.DELIVERING

func complete_task(task_id: String) -> void:
	if tasks.has(task_id):
		tasks[task_id]["state"] = TaskState.COMPLETED
		tasks.erase(task_id)

func fail_task(task_id: String, reason: String, no_path: bool = false) -> void:
	if tasks.has(task_id):
		var t = tasks[task_id]
		t["state"] = TaskState.NO_PATH if no_path else TaskState.BLOCKED
		t["cancellation_reason"] = reason
		t["actor_id"] = ""

func cancel_task(task_id: String, reason: String = "Отменено") -> void:
	if tasks.has(task_id):
		var t = tasks[task_id]
		t["state"] = TaskState.CANCELLED
		t["cancellation_reason"] = reason
		tasks.erase(task_id)

func serialize() -> Dictionary:
	var serialized_tasks = []
	for t_id in tasks:
		var t = tasks[t_id]
		serialized_tasks.append({
			"task_instance_id": t["task_instance_id"],
			"kind_id": t["kind_id"],
			"actor_id": t["actor_id"],
			"target_id": t["target_id"],
			"target_coord": [t["target_coord"].x, t["target_coord"].y],
			"target_pos": [t["target_pos"].x, t["target_pos"].y],
			"source_container_id": t["source_container_id"],
			"dest_container_id": t["dest_container_id"],
			"state": t["state"],
			"progress": t["progress"],
			"reserved_items": t["reserved_items"].duplicate(),
			"cancellation_reason": t["cancellation_reason"],
			"retry_timer": t["retry_timer"]
		})
	return {
		"next_task_id": _next_task_id,
		"tasks": serialized_tasks
	}

func deserialize(data: Dictionary) -> void:
	tasks.clear()
	_next_task_id = data.get("next_task_id", 1)
	for item in data.get("tasks", []):
		var tc = item.get("target_coord", [0, 0])
		var tp = item.get("target_pos", [0.0, 0.0])
		var t_id = item.get("task_instance_id", "")
		tasks[t_id] = {
			"task_instance_id": t_id,
			"kind_id": item.get("kind_id", ""),
			"actor_id": item.get("actor_id", ""),
			"target_id": item.get("target_id", ""),
			"target_coord": Vector2i(tc[0], tc[1]),
			"target_pos": Vector2(tp[0], tp[1]),
			"source_container_id": item.get("source_container_id", ""),
			"dest_container_id": item.get("dest_container_id", ""),
			"state": item.get("state", TaskState.AVAILABLE),
			"progress": item.get("progress", 0.0),
			"reserved_items": item.get("reserved_items", {}).duplicate(),
			"cancellation_reason": item.get("cancellation_reason", ""),
			"retry_timer": item.get("retry_timer", 0.0)
		}
