class_name TechTree
extends RefCounted

const TECHNOLOGIES: Dictionary = {
	"trapping_hunting": {
		"id": "trapping_hunting",
		"name": "Силки и охотничьи луки",
		"epoch": 1,
		"cost": 25.0, # знание
		"description": "Эффективные ловушки и составные луки. Увеличивают добычу пищи охотниками на 25%.",
		"unlocked_by": [],
		"effects": {"hunter_bonus": 0.25}
	},
	"flint_knapping": {
		"id": "flint_knapping",
		"name": "Обработка кремня и сланца",
		"epoch": 1,
		"cost": 30.0,
		"description": "Острые кремневые топоры и резцы. Повышают заготовку дерева и камня на 20%.",
		"unlocked_by": [],
		"effects": {"wood_bonus": 0.20, "stone_bonus": 0.20}
	},
	"food_preservation": {
		"id": "food_preservation",
		"name": "Сушка и копчение",
		"epoch": 1,
		"cost": 40.0,
		"description": "Коптильни и сушильные ямы позволяют дольше сохранять мясо и рыбу перед зимой.",
		"unlocked_by": ["trapping_hunting"],
		"effects": {"spoilage_reduction": 0.3}
	},
	"primitive_agriculture": {
		"id": "primitive_agriculture",
		"name": "Подсечное земледелие",
		"epoch": 1,
		"cost": 50.0,
		"description": "Посев диких зёрен на расчищенных участках. Открывает постройку полей.",
		"unlocked_by": ["flint_knapping"],
		"effects": {"unlock_field": true}
	},
	"primitive_pottery": {
		"id": "primitive_pottery",
		"name": "Глиняная посуда",
		"epoch": 1,
		"cost": 45.0,
		"description": "Обжиг сосудов для хранения воды, зерна и семян. Открывает постройку амбара.",
		"unlocked_by": ["flint_knapping"],
		"effects": {"unlock_granary": true}
	},
	"shamanic_rites": {
		"id": "shamanic_rites",
		"name": "Шаманские обряды и травы",
		"epoch": 1,
		"cost": 40.0,
		"description": "Лечебные травы и ритуалы единения. Снижают смертность от болезней на 20%.",
		"unlocked_by": [],
		"effects": {"health_bonus": 10.0}
	},
	"bronze_working": {
		"id": "bronze_working",
		"name": "Выплавка меди и бронзы",
		"epoch": 1,
		"cost": 80.0,
		"description": "Первые тигли и плавка самородной руды. Открывает рудные ямы и бронзовое оружие.",
		"unlocked_by": ["flint_knapping"],
		"effects": {"unlock_metallurgy": true}
	},
	"tribal_diplomacy": {
		"id": "tribal_diplomacy",
		"name": "Обычаи гостеприимства",
		"epoch": 1,
		"cost": 35.0,
		"description": "Ритуальный обмен дарами и брачные союзы между племенами.",
		"unlocked_by": [],
		"effects": {"diplomacy_bonus": 15.0}
	}
}

static func get_tech(id: String) -> Dictionary:
	return TECHNOLOGIES.get(id, {})
