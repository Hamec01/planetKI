class_name LawSystem
extends RefCounted

const LAWS: Dictionary = {
	"rule_warrior_chief": {
		"id": "rule_warrior_chief",
		"category": "power",
		"name": "Право сильнейшего воина",
		"epoch": 1,
		"description": "Вождём становится самый могучий боец. Повышает военный дух, но увеличивает риск кровавой борьбы за власть.",
		"effects": {"military_spirit": 15.0, "stability": -5.0}
	},
	"rule_elders_council": {
		"id": "rule_elders_council",
		"category": "power",
		"name": "Совет старейшин",
		"epoch": 1,
		"description": "Решения принимаются главами родов. Укрепляет традиции и стабильность, но замедляет радикальные реформы.",
		"effects": {"stability": 15.0, "knowledge_rate": 0.2}
	},
	"rule_priest_rule": {
		"id": "rule_priest_rule",
		"category": "power",
		"name": "Жреческое правление",
		"epoch": 1,
		"description": "Священнослужители направляют народ волей духов. Высокая вера и послушание.",
		"effects": {"faith": 20.0, "loyalty": 10.0}
	},
	"land_communal": {
		"id": "land_communal",
		"category": "land",
		"name": "Общинная земля",
		"epoch": 1,
		"description": "Охотничьи угодья и поля принадлежат всему роду. Уменьшает социальное неравенство.",
		"effects": {"loyalty": 10.0, "happiness": 5.0}
	},
	"tax_tribute_in_kind": {
		"id": "tax_tribute_in_kind",
		"category": "tax",
		"name": "Натуральная дань родов",
		"epoch": 1,
		"description": "Каждый охотник и собиратель отдает десятую долю добычи в общий котёл вождя.",
		"effects": {"food_yield": 0.1, "loyalty": -3.0}
	},
	"mil_tribal_levy": {
		"id": "mil_tribal_levy",
		"category": "military",
		"name": "Племенное всеобщее ополчение",
		"epoch": 1,
		"description": "При угрозе нападения каждый способный держать копьё встает в строй.",
		"effects": {"mobilization_rate": 0.3, "economy_penalty_on_war": 0.25}
	}
}

static func get_law(id: String) -> Dictionary:
	return LAWS.get(id, {})
