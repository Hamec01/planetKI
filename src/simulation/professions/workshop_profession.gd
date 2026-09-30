class_name WorkshopProfession
extends ProfessionBehavior

# ==============================================================================
# МАСТЕРСКАЯ: общий цикл ремесла без ресурсов «из воздуха».
#   склад (забрать сырьё, списать с экономики) -> мастерская (работа)
#   -> склад (сдать изделие, зачислить в экономику)
# Наследник задаёт рецепт, типы мастерских и тексты.
# ==============================================================================

# --- Что переопределяет наследник ---

func get_workshop_types() -> Array[String]:
	return []

# Ресурс, который производит мастерская
func product_type() -> String:
	return ""

# Имена задач цикла: забор сырья, работа, доставка изделия
func task_fetch() -> String: return "fetch_raw"
func task_work() -> String: return "workshop_work"
func task_deliver() -> String: return "workshop_delivery"

# Рецепт, который можно выполнить из запасов склада прямо сейчас:
# {"take": {ресурс: кол-во}, "product": ресурс, "amount": кол-во, "label": "что несёт"} или {} если нельзя
func choose_recipe(_s: SettlementData) -> Dictionary:
	return {}

# Почему мастер простаивает, когда рецепт недоступен
func idle_reason(_s: SettlementData) -> String:
	return "Простаивает: нет сырья"

func work_seconds() -> float: return 2.5
func work_reason() -> String: return "Работает в мастерской"
func fetch_reason(recipe: Dictionary) -> String: return "Идёт на склад за сырьём (%s)" % recipe.get("label", "")
func carry_raw_reason(recipe: Dictionary) -> String: return "Несёт сырьё в мастерскую (%s)" % recipe.get("label", "")
func carry_product_reason(_recipe: Dictionary) -> String: return "Несёт изделие на склад"
func delivered_reason(_product: String, _amount: float) -> String: return "Сдал изделие на склад"

# --- Общий цикл ---

func find_workshop_pos(s: SettlementData, c: CitizenNPC) -> Vector2:
	if c.workplace_coord != Vector2i(-1, -1) and GameManager.nav_grid:
		return GameManager.nav_grid.tile_to_world_center(c.workplace_coord)
	if GameManager.building_instances:
		for b in GameManager.building_instances.values():
			if b and "type" in b and b.type in get_workshop_types() and b.settlement_id == s.id:
				if GameManager.nav_grid:
					return GameManager.nav_grid.tile_to_world_center(b.pos)
	return c.home_pos

func _get_recipe_in_hands(c: CitizenNPC) -> Dictionary:
	return c.custom_data.get("workshop_recipe", {})

func pick_task(s: SettlementData, c: CitizenNPC, _delta: float) -> bool:
	if not is_working_age(c):
		return false
	var recipe_in_hands = _get_recipe_in_hands(c)
	# Готовое изделие в руках — на склад
	if c.cargo_type == product_type() and c.cargo_amount > 0.0:
		c.task_id = task_deliver()
		send_to(c, s._get_storage_pos(c), CitizenNPC.State.CARRYING, carry_product_reason(recipe_in_hands))
		return true
	# Сырьё в руках — в мастерскую
	if c.task_id == task_work() and c.cargo_amount > 0.0:
		send_to(c, find_workshop_pos(s, c), CitizenNPC.State.MOVING_TO_WORK, carry_raw_reason(recipe_in_hands))
		return true
	var recipe = choose_recipe(s)
	if recipe.is_empty():
		c.state = CitizenNPC.State.WAITING
		c.last_status_reason = idle_reason(s)
		c.decision_cooldown = randf_range(3.0, 5.0)
		return true
	var storage_p = s._get_storage_pos(c)
	var p_path = GameManager.nav_grid.find_path(c.pos, storage_p) if GameManager.nav_grid else []
	if p_path.is_empty():
		c.state = CitizenNPC.State.WAITING
		c.last_status_reason = "Нет пути на склад за сырьём"
		c.decision_cooldown = 2.0
		return true
	c.target_pos = storage_p
	c.task_id = task_fetch()
	c.path = p_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.last_status_reason = fetch_reason(recipe)
	c.decision_cooldown = 0.8
	return true

func on_arrived(s: SettlementData, c: CitizenNPC) -> bool:
	if c.task_id == task_fetch():
		# Рецепт выбирается заново на складе: пока мастер шёл, запасы могли измениться
		var recipe = choose_recipe(s)
		if recipe.is_empty():
			c.state = CitizenNPC.State.WAITING
			c.task_id = ""
			c.last_status_reason = idle_reason(s)
			c.decision_cooldown = randf_range(3.0, 5.0)
			return true
		var taken = 0.0
		for res in recipe["take"]:
			var amt = float(recipe["take"][res])
			s.economy.resources[res] = maxf(0.0, s.economy.get_resource(res) - amt)
			taken += amt
		if s.is_player_settlement():
			EventBus.resources_updated.emit(s.faction_id, s.economy.resources)
		# В руках одна связка сырья; тип груза — первое сырьё рецепта (при сбое вернётся на склад им)
		c.cargo_type = recipe["take"].keys()[0]
		c.cargo_amount = taken
		c.custom_data["workshop_recipe"] = recipe
		c.task_id = task_work()
		send_to(c, find_workshop_pos(s, c), CitizenNPC.State.MOVING_TO_WORK, carry_raw_reason(recipe))
		return true
	c.state = CitizenNPC.State.WORKING
	c.work_timer = work_seconds()
	c.last_status_reason = work_reason()
	return true

func on_work_done(s: SettlementData, c: CitizenNPC) -> bool:
	var recipe = _get_recipe_in_hands(c)
	if recipe.is_empty() or c.cargo_amount <= 0.0:
		c.state = CitizenNPC.State.IDLE
		c.task_id = ""
		c.decision_cooldown = randf_range(1.0, 2.0)
		return true
	# Сырьё в руках превращается в изделие
	c.cargo_type = product_type()
	c.cargo_amount = float(recipe["amount"])
	c.task_id = task_deliver()
	c.add_work_xp("crafting", 0.3)
	send_to(c, s._get_storage_pos(c), CitizenNPC.State.CARRYING, carry_product_reason(recipe))
	return true

func on_cargo_delivered(s: SettlementData, c: CitizenNPC) -> bool:
	var recipe = _get_recipe_in_hands(c)
	if c.cargo_type != product_type() or c.cargo_amount <= 0.0:
		return false
	var product = c.cargo_type
	var amount = c.cargo_amount
	s.deposit_resource(product, amount, c.name)
	c.custom_data.erase("workshop_recipe")
	c.cargo_type = ""
	c.cargo_amount = 0.0
	c.task_id = ""
	c.state = CitizenNPC.State.IDLE
	c.decision_cooldown = 1.0
	c.last_status_reason = delivered_reason(product, amount)
	return true
