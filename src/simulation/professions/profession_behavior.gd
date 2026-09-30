class_name ProfessionBehavior
extends RefCounted

# ==============================================================================
# ПОВЕДЕНИЕ ПРОФЕССИИ — базовый класс
# ------------------------------------------------------------------------------
# Логика профессии разбита на крючки, которые поселение вызывает на своих фазах
# обновления жителя. Каждый крючок возвращает true, если он обработал жителя на
# этом шаге (поселение тогда переходит к следующему жителю), и false — если
# жителя нужно отдать общей логике (стройка, быт, досуг).
# ==============================================================================

# Профессии (job_id), которыми управляет это поведение
func get_job_ids() -> Array[String]:
	return []

# Житель свободен (IDLE/WAITING): выбрать следующую рабочую задачу
func pick_task(_s: SettlementData, _c: CitizenNPC, _delta: float) -> bool:
	return false

# Житель дошёл до места работы (состояние MOVING_TO_WORK завершило путь)
func on_arrived(_s: SettlementData, _c: CitizenNPC) -> bool:
	return false

# Житель в пути (MOVING_TO_WORK/CARRYING) — для профессий с особым движением (погоня охотника)
func on_moving(_s: SettlementData, _c: CitizenNPC, _delta: float) -> bool:
	return false

# Житель донёс груз до цели (состояние CARRYING завершило путь)
func on_cargo_delivered(_s: SettlementData, _c: CitizenNPC) -> bool:
	return false

# Таймер работы на месте (WORKING) истёк
func on_work_done(_s: SettlementData, _c: CitizenNPC) -> bool:
	return false

# Особые рабочие состояния профессии (например, разделка туши)
func on_state_tick(_s: SettlementData, _c: CitizenNPC, _delta: float) -> bool:
	return false

# --- Общие помощники ---

static func is_working_age(c: CitizenNPC) -> bool:
	return c.cohort in ["youth", "adult", "elder"]

static func send_to(c: CitizenNPC, target: Vector2, state: int, reason: String) -> void:
	c.target_pos = target
	c.path = GameManager.nav_grid.find_path(c.pos, target) if GameManager and GameManager.nav_grid else []
	c.path_index = 0
	c.state = state
	c.last_status_reason = reason

static func start_task_timer(c: CitizenNPC) -> void:
	if GameManager.task_service and c.task_instance_id != "":
		GameManager.task_service.set_arrived(c.task_instance_id)
		GameManager.task_service.start_task(c.task_instance_id)
