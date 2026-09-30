class_name CraftsmanProfession
extends WorkshopProfession

# Ремесленник: 1 ед. дерева/металла/камня со склада -> 1 кубрик (изделие для обмена)

func get_job_ids() -> Array[String]:
	return ["craftsman"]

func get_workshop_types() -> Array[String]:
	return ["craft_workshop", "carpenter_workshop", "pottery_workshop", "forge", "craftsman_workshop"]

func product_type() -> String: return "kubriki"
func task_fetch() -> String: return "fetch_craft_raw"
func task_work() -> String: return "craft"
func task_deliver() -> String: return "craft_delivery"

func choose_recipe(s: SettlementData) -> Dictionary:
	for raw in ["wood", "metal", "stone"]:
		if s.economy.get_resource(raw) >= 1.0:
			return {"take": {raw: 1.0}, "product": "kubriki", "amount": 1.0, "label": raw}
	return {}

func idle_reason(_s: SettlementData) -> String:
	return "Простаивает: нет сырья для ремесла"

func work_reason() -> String: return "Изготавливает изделия в мастерской"
func carry_product_reason(_recipe: Dictionary) -> String: return "Изготовил кубрики, несёт на склад"
func delivered_reason(_product: String, _amount: float) -> String: return "Сдал изготовленные кубрики на склад"
