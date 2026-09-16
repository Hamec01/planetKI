class_name EconomySim
extends RefCounted

# Основные ресурсы (Стартовый базовый запас на 10 человек)
var resources: Dictionary = {
	"kubriki": 0.0,
	"food": 50.0,
	"wood": 25.0,
	"stone": 10.0,
	"metal": 0.0,
	"knowledge": 0.0
}

# Вторичные показатели государства/племени
var loyalty: float = 75.0      # 0 - 100 (к вождю)
var stability: float = 80.0    # 0 - 100 (порядок в обществе)
var military_spirit: float = 65.0 # 0 - 100 (боевой дух)
var faith: float = 50.0        # 0 - 100 (религиозность)

# Дневное потребление пищи на 1 жителя
const FOOD_CONSUMPTION_PER_POP_DAILY: float = 0.08 # ~2.4 единицы еды в месяц на человека

func get_resource(res_name: String) -> float:
	return resources.get(res_name, 0.0)

func add_resource(res_name: String, amount: float) -> void:
	if resources.has(res_name):
		resources[res_name] = max(0.0, resources[res_name] + amount)

func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if resources.get(res, 0.0) < cost[res]:
			return false
	return true

func deduct_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res in cost:
		resources[res] -= cost[res]
	return true

func sim_daily_tick(total_population: int, daily_production: Dictionary, granary_spoilage_factor: float) -> Dictionary:
	# 1. Потребление еды
	var food_needed = total_population * FOOD_CONSUMPTION_PER_POP_DAILY
	var food_available = resources["food"]
	var food_consumed = min(food_available, food_needed)
	resources["food"] -= food_consumed
	
	var food_satisfaction_ratio = 1.0
	if food_needed > 0.0:
		food_satisfaction_ratio = food_consumed / food_needed
		
	# 2. Добавление дневной добычи
	for res in daily_production:
		if resources.has(res):
			resources[res] += daily_production[res]
		elif res == "faith":
			faith = clampf(faith + daily_production[res], 0.0, 100.0)
		elif res == "loyalty":
			loyalty = clampf(loyalty + daily_production[res], 0.0, 100.0)
		elif res == "stability":
			stability = clampf(stability + daily_production[res], 0.0, 100.0)
			
	# 3. Естественная порча излишков еды (очень медленная, замедляется амбарами)
	if resources["food"] > 200.0:
		var excess = resources["food"] - 200.0
		var spoil_rate = 0.001 * granary_spoilage_factor
		resources["food"] -= excess * spoil_rate
		
	# 4. Влияние голода на лояльность и стабильность
	if food_satisfaction_ratio < 0.95:
		var penalty = (1.0 - food_satisfaction_ratio) * 0.5
		loyalty = clampf(loyalty - penalty, 0.0, 100.0)
		stability = clampf(stability - penalty * 0.7, 0.0, 100.0)
	elif food_satisfaction_ratio >= 1.0 and loyalty < 70.0:
		loyalty = clampf(loyalty + 0.05, 0.0, 100.0)
		
	return {
		"food_satisfaction": food_satisfaction_ratio,
		"food_consumed": food_consumed,
		"food_needed": food_needed,
		"resources": resources.duplicate()
	}
