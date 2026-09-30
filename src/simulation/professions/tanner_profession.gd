class_name TannerProfession
extends WorkshopProfession

# ==============================================================================
# СКОРНЯК: выделывает шкуры и мех от охотников в тёплую одежду.
#   1 мех + 1 шкура -> 1 тёплая одежда (быстрее, меховая)
#   2 шкуры          -> 1 тёплая одежда
# Шьёт, пока одежды на складе меньше, чем жителей: остальные шкуры
# остаются для построек и улучшений.
# ==============================================================================

func get_job_ids() -> Array[String]:
	return ["tanner"]

func get_workshop_types() -> Array[String]:
	return ["tannery"]

func product_type() -> String: return "clothes"
func task_fetch() -> String: return "fetch_hides"
func task_work() -> String: return "tan_hides"
func task_deliver() -> String: return "deliver_clothes"

func clothes_target(s: SettlementData) -> float:
	return float(s.population.get_total_population()) if s.population else 0.0

func choose_recipe(s: SettlementData) -> Dictionary:
	if s.economy.get_resource("clothes") >= clothes_target(s):
		return {}
	if s.economy.get_resource("fur") >= 1.0 and s.economy.get_resource("leather") >= 1.0:
		return {"take": {"leather": 1.0, "fur": 1.0}, "product": "clothes", "amount": 1.0, "label": "мех и шкура", "work": 3.0}
	if s.economy.get_resource("leather") >= 2.0:
		return {"take": {"leather": 2.0}, "product": "clothes", "amount": 1.0, "label": "2 шкуры", "work": 4.0}
	return {}

func idle_reason(s: SettlementData) -> String:
	if s.economy.get_resource("clothes") >= clothes_target(s):
		return "Тёплой одежды хватает на всех"
	return "Простаивает: нет шкур и меха для выделки"

func work_seconds() -> float: return 4.0
func work_reason() -> String: return "Выделывает шкуры и шьёт тёплую одежду"
func fetch_reason(recipe: Dictionary) -> String: return "Идёт на склад за шкурами (%s)" % recipe.get("label", "")
func carry_raw_reason(recipe: Dictionary) -> String: return "Несёт в скорняжню: %s" % recipe.get("label", "шкуры")
func carry_product_reason(_recipe: Dictionary) -> String: return "Сшил тёплую одежду, несёт на склад"
func delivered_reason(_product: String, _amount: float) -> String: return "Сдал тёплую одежду на склад"

func on_arrived(s: SettlementData, c: CitizenNPC) -> bool:
	var handled = super.on_arrived(s, c)
	# Меховая одежда шьётся быстрее
	if c.state == CitizenNPC.State.WORKING:
		c.work_timer = float(_get_recipe_in_hands(c).get("work", work_seconds()))
	return handled
