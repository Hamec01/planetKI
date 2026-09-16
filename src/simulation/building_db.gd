class_name BuildingDB
extends RefCounted

const BUILDINGS: Dictionary = {
	# Эпоха 1 — Племя
	"hut": {
		"id": "hut",
		"name": "Жилая хижина",
		"epoch": 1,
		"category": "housing",
		"cost": {"wood": 15},
		"build_days": 10,
		"housing": 8,
		"max_workers": 0,
		"description": "Простое жилище из веток, шкур и глины. Даёт кров 8 соплеменникам."
	},
	"great_lodge": {
		"id": "great_lodge",
		"name": "Большой дом рода",
		"epoch": 1,
		"category": "housing",
		"cost": {"wood": 45, "stone": 15},
		"build_days": 30,
		"housing": 25,
		"max_workers": 0,
		"description": "Просторный длинный дом с очагом. Повышает сплочённость и вмещает 25 жителей."
	},
	"hunting_camp": {
		"id": "hunting_camp",
		"name": "Охотничий лагерь",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 20},
		"build_days": 15,
		"housing": 0,
		"max_workers": 6,
		"job_name": "Охотник",
		"produces": {"food": 1.4}, # за 1 рабочего в день
		"description": "Снабжает племя свежей дичью, шкурами и костями."
	},
	"foraging_post": {
		"id": "foraging_post",
		"name": "Стоянка собирателей",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 10},
		"build_days": 8,
		"housing": 0,
		"max_workers": 8,
		"job_name": "Собиратель",
		"produces": {"food": 1.1},
		"description": "Сбор ягод, съедобных кореньев, грибов и трав."
	},
	"fishing_spot": {
		"id": "fishing_spot",
		"name": "Рыбацкая стоянка",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 25},
		"build_days": 12,
		"housing": 0,
		"max_workers": 5,
		"job_name": "Рыбак",
		"produces": {"food": 1.5},
		"requires_water": true,
		"description": "Плетёные верши и гарпуны для стабильной добычи рыбы из реки или моря."
	},
	"primitive_field": {
		"id": "primitive_field",
		"name": "Обработанное поле",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 15, "stone": 5},
		"build_days": 25,
		"housing": 0,
		"max_workers": 6,
		"job_name": "Земледелец",
		"produces": {"food": 1.8},
		"seasonal": true, # Высокая отдача летом/осенью, 0 зимой
		"description": "Первые опыты посева диких злаков. Даёт обильный урожай осенью."
	},
	"granary": {
		"id": "granary",
		"name": "Амбар-хранилище",
		"epoch": 1,
		"category": "storage",
		"cost": {"wood": 35, "stone": 10},
		"build_days": 20,
		"housing": 0,
		"max_workers": 0,
		"food_capacity": 500,
		"food_spoilage_reduction": 0.5,
		"description": "Защищает запасы пищи от сырости и грызунов, снижая порчу на 50%."
	},
	"woodcutter_camp": {
		"id": "woodcutter_camp",
		"name": "Лагерь лесорубов",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 15, "stone": 5},
		"build_days": 12,
		"housing": 0,
		"max_workers": 6,
		"job_name": "Лесоруб",
		"produces": {"wood": 1.2},
		"description": "Заготовка брёвен и ветвей для строительства и костров."
	},
	"stone_quarry": {
		"id": "stone_quarry",
		"name": "Каменоломня",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 25},
		"build_days": 18,
		"housing": 0,
		"max_workers": 5,
		"job_name": "Каменотёс",
		"produces": {"stone": 1.0},
		"description": "Добыча кремня, сланца и твёрдой породы для орудий и очагов."
	},
	"ore_pit": {
		"id": "ore_pit",
		"name": "Рудная яма",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 30, "stone": 15},
		"build_days": 30,
		"housing": 0,
		"max_workers": 4,
		"job_name": "Рудокоп",
		"produces": {"metal": 0.5},
		"description": "Сбор самородной меди и болотной руды для первых металлических наконечников."
	},
	"craft_workshop": {
		"id": "craft_workshop",
		"name": "Мастерская ремёсел",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 30, "stone": 15},
		"build_days": 20,
		"housing": 0,
		"max_workers": 4,
		"job_name": "Мастер",
		"produces": {"kubriki": 1.0, "knowledge": 0.3},
		"description": "Изготовление качественных топоров, керамики и украшений для обмена."
	},
	"elders_house": {
		"id": "elders_house",
		"name": "Дом старейшин",
		"epoch": 1,
		"category": "society",
		"cost": {"wood": 40, "stone": 20},
		"build_days": 25,
		"housing": 0,
		"max_workers": 3,
		"job_name": "Мудрец",
		"produces": {"knowledge": 0.8},
		"stability_bonus": 5.0,
		"description": "Место советов и хранения преданий. Генерирует знания и укрепляет порядок."
	},
	"shrine": {
		"id": "shrine",
		"name": "Святилище духов",
		"epoch": 1,
		"category": "society",
		"cost": {"wood": 20, "stone": 30},
		"build_days": 20,
		"housing": 0,
		"max_workers": 3,
		"job_name": "Жрец / Шаман",
		"produces": {"faith": 1.0, "loyalty": 0.2},
		"description": "Идолы и жертвенный огонь. Поддерживает религиозное рвение и лояльность."
	},
	"fire_square": {
		"id": "fire_square",
		"name": "Костровая площадь",
		"epoch": 1,
		"category": "society",
		"cost": {"wood": 20, "stone": 10},
		"build_days": 10,
		"housing": 0,
		"max_workers": 0,
		"loyalty_bonus": 8.0,
		"description": "Центр племенных праздников, ритуалов и танцев у ночного огня."
	},
	"palisade": {
		"id": "palisade",
		"name": "Деревянный частокол",
		"epoch": 1,
		"category": "defense",
		"cost": {"wood": 50, "stone": 10},
		"build_days": 25,
		"housing": 0,
		"defense_bonus": 15.0,
		"description": "Ограда из заострённых бревен, защищающая стоянку от диких зверей и набегов."
	},
	"watchtower": {
		"id": "watchtower",
		"name": "Сторожевая вышка",
		"epoch": 1,
		"category": "defense",
		"cost": {"wood": 25, "stone": 5},
		"build_days": 15,
		"housing": 0,
		"max_workers": 2,
		"job_name": "Дозорный",
		"scouting_range": 4,
		"description": "Позволяет заблаговременно заметить приближение чужих отрядов и хищников."
	},
	"training_grounds": {
		"id": "training_grounds",
		"name": "Площадка воинов",
		"epoch": 1,
		"category": "military",
		"cost": {"wood": 35, "stone": 15},
		"build_days": 20,
		"housing": 0,
		"max_workers": 4,
		"job_name": "Воин-наставник",
		"military_spirit_bonus": 10.0,
		"description": "Обучение юношей метанию копий, стрельбе из лука и рукопашному бою."
	}
}

static func get_building(id: String) -> Dictionary:
	return BUILDINGS.get(id, {})
