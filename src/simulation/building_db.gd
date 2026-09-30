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
		"comfort_housing": 6,
		"max_guests": 2,
		"max_workers": 0,
		"description": "Простое жилище из веток, шкур и глины. Комфортно вмещает 4–6 соплеменников, до 8 — тесно."
	},
	"great_lodge": {
		"id": "great_lodge",
		"name": "Большой дом рода",
		"epoch": 1,
		"category": "housing",
		"cost": {"wood": 45, "stone": 15},
		"build_days": 30,
		"housing": 35,
		"comfort_housing": 25,
		"max_guests": 5,
		"max_workers": 0,
		"description": "Первое настоящее общественное и родовое здание. Совместное проживание больших семей, забота о детях и стариках, круг знаний и совет рода."
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
		"description": "Сбор ягод, съедобных кореньев, грибов и трав. Накопление знаний о растениях и семенах."
	},
	"primitive_garden": {
		"id": "primitive_garden",
		"name": "Примитивный огород",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 10, "stone": 4},
		"build_days": 10,
		"housing": 0,
		"max_workers": 4,
		"job_name": "Собиратель-огородник",
		"produces": {"food": 1.4, "herbs": 0.3},
		"description": "Первые окультуренные посадки у поселения: корнеплоды, бобовые, травы. 6 стадий созревания."
	},
	"seed_store": {
		"id": "seed_store",
		"name": "Склад семян",
		"epoch": 1,
		"category": "storage",
		"cost": {"wood": 20, "stone": 5},
		"build_days": 14,
		"housing": 0,
		"max_workers": 2,
		"job_name": "Хранитель семян",
		"description": "Приподнятый деревянный склад для сохранения семенного фонда, защиты семян от грызунов и сырости."
	},
	"wheat_field": {
		"id": "wheat_field",
		"name": "Поле злаков",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 15, "stone": 5},
		"build_days": 18,
		"housing": 0,
		"max_workers": 6,
		"job_name": "Земледелец",
		"produces": {"grain": 2.0, "straw": 1.0},
		"description": "Поле для выращивания пшеницы и диких злаков. 6 стадий роста от всходов до золотых колосьев."
	},
	"threshing_floor": {
		"id": "threshing_floor",
		"name": "Гумно",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 18, "stone": 8},
		"build_days": 12,
		"housing": 0,
		"max_workers": 4,
		"job_name": "Земледелец",
		"description": "Площадка для сушки снопов, обмолота зерна цепами и провеивания чистого зерна."
	},
	"quern_house": {
		"id": "quern_house",
		"name": "Дом жерновов",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 20, "stone": 15},
		"build_days": 16,
		"housing": 0,
		"max_workers": 3,
		"job_name": "Мельник",
		"produces": {"flour": 1.8},
		"description": "Помещение с каменными жерновами для перетирания зерна в муку."
	},
	"bakery": {
		"id": "bakery",
		"name": "Пекарня",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 25, "stone": 20},
		"build_days": 20,
		"housing": 0,
		"max_workers": 3,
		"job_name": "Пекарь",
		"produces": {"bread": 2.5},
		"description": "Глинобитная сводчатая печь для выпечки питательных лепёшек и сытного хлеба."
	},
	"orchard": {
		"id": "orchard",
		"name": "Плодовый сад",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 15, "stone": 5},
		"build_days": 22,
		"housing": 0,
		"max_workers": 3,
		"job_name": "Земледелец",
		"produces": {"fruits": 1.6},
		"description": "Посадки многолетних плодовых деревьев. Стабильный урожай плодов."
	},
	"irrigation_ditch": {
		"id": "irrigation_ditch",
		"name": "Оросительный канал",
		"epoch": 1,
		"category": "infrastructure",
		"cost": {"wood": 6, "stone": 4},
		"build_days": 4,
		"housing": 0,
		"max_workers": 0,
		"description": "Канавы и шлюзы для подачи воды из реки на поля, защищающие урожай от засухи."
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
		"seasonal": true,
		"description": "Первые опыты посева диких злаков. Даёт обильный урожай."
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
	"tannery": {
		"id": "tannery",
		"name": "Скорняжня",
		"epoch": 1,
		"category": "production",
		"cost": {"wood": 20, "stone": 6},
		"build_days": 15,
		"housing": 0,
		"max_workers": 2,
		"job_name": "Скорняк",
		"description": "Выделка шкур и меха от охотников в тёплую одежду. Скорняк сам носит сырьё со склада и сдаёт готовую одежду. Зимой без тёплой одежды жители мёрзнут: теряют силы и здоровье."
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
	"wooden_fence": {
		"id": "wooden_fence",
		"name": "Деревянный забор",
		"epoch": 1,
		"category": "defense",
		"cost": {"wood": 2},
		"build_days": 1,
		"housing": 0,
		"max_workers": 0,
		"defense_bonus": 2.0,
		"description": "Модульная ограда из деревянных планок и кольев. Стыкуется во всех направлениях (горизонталь, вертикаль, углы)."
	},
	"wooden_gate": {
		"id": "wooden_gate",
		"name": "Деревянные ворота",
		"epoch": 1,
		"category": "defense",
		"cost": {"wood": 5},
		"build_days": 2,
		"housing": 0,
		"max_workers": 0,
		"defense_bonus": 4.0,
		"description": "Распашные деревянные ворота на засове. Кликните мышью для открытия или закрытия прохода."
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
	},
	"cemetery": {
		"id": "cemetery",
		"name": "Кладбище (Зона захоронений)",
		"epoch": 1,
		"category": "society",
		"cost": {"wood": 5, "stone": 2},
		"build_days": 1,
		"housing": 0,
		"max_workers": 1,
		"job_name": "Хранитель предков",
		"max_capacity": 4,
		"loyalty_bonus": 5.0,
		"stability_bonus": 5.0,
		"description": "Выделенный священный участок земли для упокоения усопших соплеменников (до 4 могилок на клетку). Без выделенного кладбища люди не могут похоронить мёртвых и ропщут."
	},
	"grave": {
		"id": "grave",
		"name": "Могила соплеменника",
		"epoch": 1,
		"category": "memorial",
		"cost": {"stone": 5},
		"build_days": 1,
		"housing": 0,
		"max_workers": 0,
		"stability_bonus": 2.0,
		"description": "Священное место вечного упокоения ушедшего соплеменника с резным каменным надгробием."
	},
	"animal_pen": {
		"id": "animal_pen",
		"name": "Загон для скота",
		"epoch": 1,
		"category": "food",
		"cost": {"wood": 25, "stone": 5},
		"build_days": 12,
		"housing": 0,
		"max_workers": 2,
		"job_name": "Пастух",
		"produces": {"food": 1.2, "leather": 0.5},
		"description": "Огороженный загон для содержания прирученной дичи (олени, козы, молодняк). Защищает животных от хищников и даёт регулярные продукты."
	},
	"meeting_place": {
		"id": "meeting_place",
		"name": "Место сбора племени",
		"epoch": 1,
		"category": "society",
		"cost": {"wood": 20, "stone": 10},
		"build_days": 10,
		"housing": 0,
		"max_workers": 0,
		"loyalty_bonus": 8.0,
		"description": "Центр племенных сходов, обсуждений и праздников у ночного огня."
	}
}

static func get_building(id: String) -> Dictionary:
	return BUILDINGS.get(id, {})

static func get_job_id_for_building(b_type: String) -> String:
	match b_type:
		"hunting_camp": return "hunter"
		"foraging_post": return "forager"
		"fishing_spot": return "fisherman"
		"primitive_garden": return "forager"
		"seed_store": return "seed_keeper"
		"primitive_field", "wheat_field", "animal_pen", "threshing_floor", "orchard": return "farmer"
		"quern_house": return "miller"
		"bakery": return "baker"
		"woodcutter_camp": return "woodcutter"
		"stone_quarry": return "quarryman"
		"ore_pit": return "miner"
		"craft_workshop", "carpenter_workshop", "pottery_workshop", "forge": return "craftsman"
		"tannery": return "tanner"
		"elders_house": return "elder"
		"shrine", "cemetery": return "priest"
		"watchtower": return "guard"
		"training_grounds": return "warrior"
		_: return "idle"

const UPGRADES: Dictionary = {
	"hut": [
		{"id": "hut_annex", "name": "Пристройка", "cost": {"wood": 10}, "desc": "+2 к вместимости жилья"},
		{"id": "pantry", "name": "Кладовая", "cost": {"wood": 8}, "desc": "+8 к запасу домашней еды"},
		{"id": "garden", "name": "Огород", "cost": {"wood": 6, "stone": 2}, "desc": "Домашний огород, +1.0 к комфорту"},
		{"id": "barn", "name": "Сарай", "cost": {"wood": 12, "stone": 4}, "desc": "Хранение домашнего инвентаря"}
	],
	"great_lodge": [
		{"id": "great_hearth", "name": "Большой общий очаг", "cost": {"wood": 15, "stone": 5}, "desc": "Центральный очаг и место вечернего сбора. Настроение +5%, тепло, сказы стариков."},
		{"id": "partitions", "name": "Спальные перегородки", "cost": {"wood": 12, "leather": 6}, "desc": "Стены из шкур и дерева. Конфликты -20%, сон +10%, настроение +3, сплочённость -5%."},
		{"id": "nursery_corner", "name": "Детский угол", "cost": {"wood": 10, "leather": 4}, "desc": "Безопасная зона для детей. Открывает коллективный присмотр за малышами."},
		{"id": "caretaker_quarters", "name": "Место опекуна", "cost": {"wood": 8, "leather": 4}, "req": "nursery_corner", "desc": "Открывает роль: Опекун детей. Следит за 8 детьми, освобождая родителей (+2-4ч работы)."},
		{"id": "elders_quarters", "name": "Место старших", "cost": {"wood": 8, "stone": 8, "leather": 4}, "desc": "Особая зона для стариков. Бездомные старики селятся сюда, помогая с детьми и делами."},
		{"id": "knowledge_circle", "name": "Круг знаний", "cost": {"wood": 10, "stone": 10}, "req": "elders_quarters", "desc": "Открывает роль: Хранитель знаний. Пожилой мастер передаёт реальные навыки молодым."},
		{"id": "clan_totems", "name": "Родовые знаки", "cost": {"wood": 6, "leather": 4, "bone": 4}, "desc": "Шкуры, рога и тотемы. Традиции +10, сплочённость +5, замкнутость рода."},
		{"id": "clan_council", "name": "Круг рода", "cost": {"wood": 12, "stone": 6}, "desc": "Открывает роль: Старейшина рода. Решает внутренние споры и представляет дом."},
		{"id": "communal_store", "name": "Общие запасы", "cost": {"wood": 12}, "desc": "Внутренняя кладовая дома для еды, шкур, одежды и инструмента."},
		{"id": "infirmary_corner", "name": "Место ухода", "cost": {"wood": 10, "leather": 6}, "desc": "Лежанки для слабых, раненых и рожениц. HP +15%, восстановление +10%."}
	],
	"hunting_camp": [
		{"id": "hunt_butcher_table", "name": "Площадка разделки", "cost": {"wood": 10, "stone": 6}, "desc": "Разделочный пень с тесаком и подвес для мяса. Ускоряет разделку на 35%, выход мяса +15%."},
		{"id": "hunt_weapon_rack", "name": "Стойка оружия", "cost": {"wood": 10, "stone": 5}, "desc": "Копья, луки и щиты. Охотники вооружены, +25% урона и защита от травм."},
		{"id": "hunt_fur_rack", "name": "Сушилка шкур", "cost": {"wood": 8, "leather": 2}, "desc": "Стойка просушки пушнины. +1 качественная шкура с крупной дичи."},
		{"id": "hunt_campfire", "name": "Охотничий костёр", "cost": {"wood": 8, "stone": 6}, "desc": "Кострище и брёвна-лежанки. Обогрев и отдых охотников, восстановление сил."},
		{"id": "hunt_tracking", "name": "Стойка следопыта", "cost": {"wood": 15, "leather": 3}, "desc": "Карты следов и троп. Дальность обнаружения дичи +30%."},
		{"id": "hunt_bone_traps", "name": "Костяные силки", "cost": {"wood": 12, "bone": 4}, "desc": "+20% к пассивной добыче мелкой дичи и перьев."},
		{"id": "hunt_dogs", "name": "Охотничьи собаки", "cost": {"food": 25, "wood": 15}, "req": "hunt_tracking", "desc": "Охотники загоняют дичь вдвое быстрее, защита от хищников."},
		{"id": "hunt_master_butcher", "name": "Стол мастера разделки", "cost": {"wood": 12, "stone": 8}, "req": "hunt_butcher_table", "desc": "Роль мастера разделки. 0 потерь мяса (+20%), гарантированные целые шкуры."},
		{"id": "hunt_target", "name": "Тренировочная мишень", "cost": {"wood": 8, "leather": 2}, "req": "hunt_weapon_rack", "desc": "Тренировка свободных охотников стрельбе из лука и броскам копья."},
		{"id": "hunt_mentor", "name": "Место наставника", "cost": {"wood": 10, "leather": 4}, "req": "hunt_target", "desc": "Опытные ветераны обучают молодых охотников, передавая навыки ремесла."},
		{"id": "hunt_outpost", "name": "Дальняя стоянка", "cost": {"wood": 15, "leather": 4}, "req": "hunt_campfire", "desc": "Дальние переходы и ночлег в тайге. Радиус охоты +50%."},
		{"id": "hunt_trophies", "name": "Мастерская трофеев", "cost": {"wood": 12, "bone": 6}, "req": "hunt_fur_rack", "desc": "Инструменты, обереги и изделия из рогов, костей и зубов."},
		{"id": "hunt_smokehouse", "name": "Коптильная яма", "cost": {"wood": 12, "stone": 8}, "req": "hunt_campfire", "desc": "Заготовка копчёного мяса. Снижает скорость порчи провианта на 80%."}
	],
	"foraging_post": [
		{"id": "forage_baskets", "name": "Плетёные корзины", "cost": {"wood": 8}, "desc": "Увеличивают переносимый вес на 30%, собиратели приносят больше трав, ягод и корней."},
		{"id": "forage_sorting_table", "name": "Стол сортировки растений", "cost": {"wood": 10, "stone": 4}, "desc": "Разделение съедобных, целебных и ядовитых трав. Знание растений растёт быстрее, риск отравлений 0%."},
		{"id": "forage_drying_racks", "name": "Сушильные рамки", "cost": {"wood": 8, "stone": 2}, "desc": "Сушка ягод, грибов и корней. Снижает порчу сырой пищи на 60%."},
		{"id": "forage_storage_pit", "name": "Яма-хранилище", "cost": {"wood": 12, "stone": 6}, "desc": "Хранение клубней, орехов и семян под навесом. Защищает от сырости."},
		{"id": "forage_route_markers", "name": "Знаки маршрутов", "cost": {"wood": 6, "stone": 4}, "desc": "Зарубки и вешки на ягодных полянах и дубравах. Ускоряет передвижение собирателей на 25%."},
		{"id": "forage_seed_sorting", "name": "Место сортировки семян", "cost": {"wood": 12, "stone": 4}, "req": "forage_sorting_table", "desc": "Первая селекция: отбор самых крупных семян диких злаков и корнеплодов."},
		{"id": "forage_test_plot", "name": "Опытная грядка", "cost": {"wood": 10, "stone": 6}, "req": "forage_seed_sorting", "desc": "Небольшая делянка возле стоянки. NPC экспериментируют с поливом и прополкой, ускоряя открытие огородов."},
		{"id": "forage_grain_station", "name": "Место обработки зерна", "cost": {"wood": 14, "stone": 8}, "req": "forage_seed_sorting", "desc": "Выбивание зерна из колосьев и перетирание камнями на кашу."}
	],
	"seed_store": [
		{"id": "seed_raised_floor", "name": "Приподнятый настил", "cost": {"wood": 12, "stone": 6}, "desc": "Деревянные опоры спасают мешки с семенами от сырой земли и гнили."},
		{"id": "seed_sealed_jars", "name": "Глиняные кувшины", "cost": {"stone": 10, "clay": 8, "wood": 6}, "desc": "Герметичные сосуды защищают посевной фонд от жучков и мышей."},
		{"id": "seed_selection_bench", "name": "Стол отбора элиты", "cost": {"wood": 10, "stone": 4}, "desc": "Тщательная калибровка семян: повышает урожайность полей на +20%."},
		{"id": "seed_rodent_traps", "name": "Мышеловки", "cost": {"wood": 6, "bone": 4}, "desc": "Костяные капканы от грызунов. Потери семян снижаются на 90%."}
	],
	"primitive_garden": [
		{"id": "garden_fencing", "name": "Плетёный плетень", "cost": {"wood": 10}, "desc": "Ограда от диких зверей и вытаптывания. Защита урожая +30%."},
		{"id": "garden_compost", "name": "Компостная яма", "cost": {"wood": 8, "stone": 4}, "desc": "Органические остатки и зола восстанавливают плодородие грядок на +25%."},
		{"id": "garden_water_trough", "name": "Корыта для полива", "cost": {"wood": 12, "stone": 4}, "desc": "Запас дождевой и речной воды. Уменьшает восприимчивость огорода к засухе."},
		{"id": "garden_herbal_bed", "name": "Лекарственная делянка", "cost": {"wood": 8, "stone": 4}, "desc": "Выращивание ромашки, подорожника и тысячелистника для врачевания."}
	],
	"primitive_field": [
		{"id": "field_stone_clearing", "name": "Расчистка от валунов", "cost": {"wood": 6, "stone": 12}, "desc": "Убирает камни из пахоты, снижает поломку мотыг и ускоряет вспашку."},
		{"id": "field_manure_spreading", "name": "Удобрение навозом", "cost": {"wood": 8, "food": 5}, "desc": "Использование органики с загонов для скота. Повышает плодородие почвы на +40%."},
		{"id": "field_wooden_ard", "name": "Деревянное рало", "cost": {"wood": 16, "stone": 6}, "desc": "Рыхлит почву глубже мотыг, увеличивая отдачу зерна на +30%."},
		{"id": "field_ox_plow", "name": "Рало на воловьей тяге", "cost": {"wood": 24, "stone": 10, "leather": 6}, "req": "field_wooden_ard", "desc": "Упряжь для пары волов. Втрое ускоряет вспашку крупных участков."}
	],
	"wheat_field": [
		{"id": "wheat_irrigation_furrows", "name": "Оросительные борозды", "cost": {"wood": 10, "stone": 8}, "desc": "Борозды для равномерного распределения воды из каналов."},
		{"id": "wheat_scarecrow", "name": "Пугала и колотушки", "cost": {"wood": 6, "straw": 10}, "desc": "Защищает золотые колосья от воробьев и птичьих стай."},
		{"id": "wheat_sickles", "name": "Кремнёвые серпы", "cost": {"wood": 10, "stone": 10}, "desc": "Ускоряет сбор урожая вдвое, предотвращая осыпание зерна при перезревании."},
		{"id": "wheat_ox_plow", "name": "Тягловый плуг", "cost": {"wood": 25, "stone": 12, "leather": 8}, "desc": "Глубокая вспашка на волах. Увеличивает максимальную урожайность пшеницы на +50%."}
	],
	"threshing_floor": [
		{"id": "thresh_hard_clay", "name": "Глиняная утрамбовка", "cost": {"stone": 10, "wood": 6}, "desc": "Ровная утрамбованная площадка: зерно не забивается в трещины и не теряется в пыли."},
		{"id": "thresh_flails", "name": "Деревянные цепы", "cost": {"wood": 12, "leather": 4}, "desc": "Составные цепы ускоряют обмолот снопов на 50%."},
		{"id": "thresh_winnow_baskets", "name": "Веяльные лопаты и сита", "cost": {"wood": 8, "straw": 6}, "desc": "Провеивание на ветру начисто отделяет шелуху от чистого зерна."},
		{"id": "thresh_sheaf_canopy", "name": "Навес для снопов", "cost": {"wood": 15, "straw": 12}, "desc": "Защищает сжатую пшеницу от неожиданных дождей перед молотьбой."}
	],
	"quern_house": [
		{"id": "quern_granite_stones", "name": "Гранитные жернова", "cost": {"stone": 20, "wood": 8}, "desc": "Тяжёлые прочные жернова: выход тонкой муки +40%, без каменной крошки."},
		{"id": "quern_rotary_handle", "name": "Вращательный рычаг", "cost": {"wood": 12, "leather": 4}, "desc": "Удобный рычаг и подвес: мельник тратит меньше сил, скорость помола +35%."},
		{"id": "quern_flour_sifter", "name": "Тканевое сито", "cost": {"wood": 6, "leather": 4}, "desc": "Отделяет отруби от белой муки для пышного хлеба."},
		{"id": "quern_dust_ventilation", "name": "Вытяжное окно", "cost": {"wood": 10}, "desc": "Удаляет мучную пыль, защищая легкие мельников от болезней."}
	],
	"bakery": [
		{"id": "bake_domed_oven", "name": "Сводчатая печь из шамота", "cost": {"stone": 20, "wood": 10}, "desc": "Толстый купол долго держит ровный жар: выпекает до 10 буханок одновременно."},
		{"id": "bake_kneading_trough", "name": "Дубовое квасильное корыто", "cost": {"wood": 14}, "desc": "Удобный замес большого объёма дрожжевого и пресного теста."},
		{"id": "bake_wood_rack", "name": "Дровяной навес", "cost": {"wood": 10}, "desc": "Сухие дрова горят без копоти, хлеб получается ароматным и румяным."},
		{"id": "bake_cooling_shelves", "name": "Стеллажи для остывания", "cost": {"wood": 12}, "desc": "Правильное остывание хлеба, буханки не отмокают и дольше хранятся."}
	],
	"orchard": [
		{"id": "orchard_grafting", "name": "Прививка черенков", "cost": {"wood": 8}, "desc": "Скрещивание сладких сортов: плоды крупнее, урожайность +30%."},
		{"id": "orchard_irrigation", "name": "Поливочные канавки", "cost": {"wood": 10, "stone": 6}, "desc": "Подвод речной воды к корням плодовых деревьев."},
		{"id": "orchard_smoke_pots", "name": "Дымовые кучи", "cost": {"wood": 6, "straw": 8}, "desc": "Окуривание дымом защищает завязи от заморозков и вредителей."}
	],
	"irrigation_ditch": [
		{"id": "irrigation_stone_lining", "name": "Каменная обкладка", "cost": {"stone": 12}, "desc": "Защищает берега канала от размывания ливнями и обрушения."},
		{"id": "irrigation_sluice_gate", "name": "Деревянные шлюзы", "cost": {"wood": 10, "stone": 4}, "desc": "Регулирует подачу воды на поля в засушливые дни."}
	]
}

static func get_upgrades_for_building(b_type: String) -> Array:
	return UPGRADES.get(b_type, [])

static func get_upgrade_info(b_type: String, up_id: String) -> Dictionary:
	var list = get_upgrades_for_building(b_type)
	for u in list:
		if u.get("id", "") == up_id:
			return u
	return {}


