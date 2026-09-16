class_name ReligionSystem
extends RefCounted

const RELIGIONS: Dictionary = {
	"ancestor_spirits": {
		"id": "ancestor_spirits",
		"name": "Вера Предков",
		"values": ["Семья", "Честь", "Традиция", "Старшие"],
		"bonuses": "Устойчивые семьи, высокая рождаемость (+15%), уважение к старейшинам.",
		"risks": "Сопротивление реформам и новшествам.",
		"birth_multiplier": 1.15
	},
	"solarism": {
		"id": "solarism",
		"name": "Соляризм",
		"values": ["Порядок", "Семья", "Труд", "Дисциплина"],
		"bonuses": "Лояльность при сильной власти, производительность труда (+10%).",
		"risks": "Усиление жречества и нетерпимость к иноверцам.",
		"production_multiplier": 1.10
	},
	"world_spirits": {
		"id": "world_spirits",
		"name": "Духи Мира (Анимизм)",
		"values": ["Природа", "Гармония", "Охота", "Лес"],
		"bonuses": "Повышенная добыча в лесах и на охоте (+20%), скорость разведки.",
		"risks": "Регионализм и сложность централизации.",
		"forage_multiplier": 1.20
	},
	"balance_path": {
		"id": "balance_path",
		"name": "Учение о Равновесии",
		"values": ["Баланс", "Мудрость", "Дипломатия", "Знания"],
		"bonuses": "Дипломатическое доверие соседей (+20), генерация знаний (+15%).",
		"risks": "Сложнее мобилизовать народ на войну.",
		"knowledge_multiplier": 1.15
	},
	"conqueror_cult": {
		"id": "conqueror_cult",
		"name": "Культ Победителя",
		"values": ["Сила", "Слава", "Доблесть", "Завоевания"],
		"bonuses": "Боевой дух (+25), слава генералов, устрашение соседей.",
		"risks": "Поражения резко обрушивают авторитет вождя.",
		"combat_morale_bonus": 25.0
	}
}

static func get_religion(id: String) -> Dictionary:
	return RELIGIONS.get(id, RELIGIONS["ancestor_spirits"])
