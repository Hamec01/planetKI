class_name BuildingSystem
extends RefCounted

# --- РЕЖИМЫ ПРОИЗВОДСТВА ДЛЯ 8 АКТИВНЫХ ЗДАНИЙ ---
const BUILDING_MODES: Dictionary = {
	"forge": [
		{"id": "tools", "name": "🪓 Инструменты", "desc": "Топоры, кирки, строительные наборы (+15% к добыче ресурсов и стройке)"},
		{"id": "weapons", "name": "⚔️ Оружие и щиты", "desc": "Наконечники, копья, топоры, мечи для воинов племени"},
		{"id": "hunting", "name": "🏹 Охотничье снаряжение", "desc": "Кованые наконечники стрел и крючья (+20% к охоте)"},
		{"id": "repair", "name": "🛠 Ремонт и обслуживание", "desc": "Снижает износ орудий труда и продлевает срок службы построек"},
		{"id": "experiments", "name": "🧪 Металлургические опыты", "desc": "Высокий расход руды. Шанс открыть новые сплавы и редкие рецепты"}
	],
	"carpenter_workshop": [
		{"id": "construction", "name": "🪵 Стройматериалы", "desc": "Балки, стропила, настилы (+20% к скорости строительства)"},
		{"id": "bows", "name": "🏹 Луки и древки", "desc": "Охотничьи и боевые дальнобойные луки"},
		{"id": "transport", "name": "🛞 Повозки и колеса", "desc": "Сани и телеги (увеличивают перенос ресурсов рабочими)"},
		{"id": "furniture", "name": "🪑 Обустройство очагов", "desc": "Уют в хижинах (+10% к лояльности соплеменников)"}
	],
	"stone_quarry": [
		{"id": "mass", "name": "⛏ Массовая добыча", "desc": "Максимальный валовый объём камня и булыжников"},
		{"id": "quality", "name": "💎 Отборный кремень", "desc": "Высококачественный камень для оружия и инструментов"},
		{"id": "ore_search", "name": "🔍 Поиск рудных жил", "desc": "Повышенный шанс наткнуться на самородную медь и минералы"},
		{"id": "blocks", "name": "🧱 Обтёска каменных блоков", "desc": "Заготовка блоков для возведения прочных каменных стен"}
	],
	"granary": [
		{"id": "normal", "name": "🌾 Обычное хранение", "desc": "Стандартный рацион и умеренное распределение запасов"},
		{"id": "reserve", "name": "🔒 Стратегический резерв", "desc": "Экономия пищи на случай засухи или неурожая"},
		{"id": "children_first", "name": "👶 Приоритет детям и матерям", "desc": "Снижает детскую смертность и ускоряет рост населения"},
		{"id": "army_first", "name": "⚔️ Приоритет дружине", "desc": "Высокий паёк воинам (+15% к боевому духу)"},
		{"id": "feast", "name": "🍗 Праздничная раздача", "desc": "Щедрые порции у костра (+20% к счастью и лояльности)"}
	],
	"elders_house": [
		{"id": "council", "name": "👴 Совет Старейшин", "desc": "Разрешение споров, поддержание стабильности и порядка"},
		{"id": "traditions", "name": "📜 Хранение преданий", "desc": "Генерация культурных озарений и воспитание молодёжи"},
		{"id": "diplomacy", "name": "🤝 Приём послов", "desc": "Укрепление связей и торговли с соседними племенами"},
		{"id": "chief_rule", "name": "👑 Прямая воля Вождя", "desc": "Усиление авторитета и быстрое принятие решений"}
	],
	"shrine": [
		{"id": "rituals", "name": "🕯 Священные обряды", "desc": "Поддержание религиозного рвения и душевного мира"},
		{"id": "ancestors", "name": "💀 Поминовение Предков", "desc": "Укрепление семейных уз и верности традициям рода"},
		{"id": "hunt_blessing", "name": "🐺 Благословение Охоты", "desc": "Обряд удачи перед выходом охотников в дикие земли"},
		{"id": "war_prayer", "name": "⚔️ Молитва о Победе", "desc": "Вселяет бесстрашие в сердца защитников племени"}
	],
	"hunting_camp": [
		{"id": "plains", "name": "🌾 Охота на равнинах", "desc": "Быстроногая дичь, перья, мелкие шкуры (безопасно)"},
		{"id": "forest", "name": "🌲 Таёжный промысел", "desc": "Крупные олени, кабаны, ценная пушнина (умеренный риск)"},
		{"id": "beasts", "name": "🐻 Охота на хищников", "desc": "Медведи и волки: клыки, толстые шкуры, проверка на храбрость"},
		{"id": "trapping", "name": "🪤 Ловушки и силки", "desc": "Пассивный стабильный сбор мелкой дичи без риска травм"}
	],
	"training_grounds": [
		{"id": "drills", "name": "🏹 Учебные стрельбы и бой", "desc": "Базовая боевая подготовка молодых соплеменников"},
		{"id": "formation", "name": "🛡 Отработка строя", "desc": "Слаженность в рядах дружины (+защита в бою)"},
		{"id": "endurance", "name": "🏃 Марш-броски и выносливость", "desc": "Повышает скорость передвижения отрядов по карте"},
		{"id": "spartans", "name": "⚔️ Жестокие спарринги", "desc": "Быстро растит ветеранов ценой легких травм"}
	],
	"woodcutter_camp": [
		{"id": "logging", "name": "🪓 Сплошная заготовка", "desc": "Лесорубы валят взрослые деревья для максимального сбора древесины (1 дерево = 100 дров)"},
		{"id": "reforestation", "name": "🌱 Лесопосадка и уход", "desc": "Лесорубы и лесники сеют саженцы деревьев на вырубках и пустых полях, восстанавливая лес"},
		{"id": "selective", "name": "🌲 Выборочная санитарная рубка", "desc": "Рубка только сухих и старых деревьев с бережным сохранением лесного массива"}
	]
}

# --- ПОЛНЫЙ КАТАЛОГ АПГРЕЙДОВ ДЛЯ 8 АКТИВНЫХ ЗДАНИЙ ---
const UPGRADES: Dictionary = {
	# 1. КУЗНИЦА / ПЛАВИЛЬНЯ
	"forge_copper_axes": {
		"id": "forge_copper_axes", "building_type": "forge",
		"name": "Медные топоры", "desc": "+15% к скорости заготовки леса, +5% к эффективности плотников.",
		"category": "tools", "unlock_type": "ordinary",
		"cost": {"wood": 15, "metal": 10}, "prerequisites": [],
		"effects": {"woodcutting_speed": 0.15, "carpenter_boost": 0.05}
	},
	"forge_reinforced_pickaxes": {
		"id": "forge_reinforced_pickaxes", "building_type": "forge",
		"name": "Усиленные кирки", "desc": "+15% к добыче камня, +10% шанс обнаружить рудную жилу.",
		"category": "tools", "unlock_type": "practical",
		"cost": {"wood": 20, "metal": 15}, "prerequisites": ["forge_copper_axes"],
		"req_practice": {"stone_mined": 50},
		"effects": {"stone_speed": 0.15, "ore_chance": 0.10}
	},
	"forge_builder_kit": {
		"id": "forge_builder_kit", "building_type": "forge",
		"name": "Набор строителя", "desc": "+10% к скорости возведения всех построек на карте.",
		"category": "tools", "unlock_type": "ordinary",
		"cost": {"wood": 15, "metal": 15}, "prerequisites": ["forge_copper_axes"],
		"effects": {"build_speed": 0.10}
	},
	"forge_arrow_heads": {
		"id": "forge_arrow_heads", "building_type": "forge",
		"name": "Кованые наконечники стрел", "desc": "+20% к урону охотников и лучников дружины.",
		"category": "weapons", "unlock_type": "ordinary",
		"cost": {"wood": 10, "metal": 15}, "prerequisites": [],
		"effects": {"archer_damage": 0.20, "hunter_damage": 0.20}
	},
	"forge_bronze_spears": {
		"id": "forge_bronze_spears", "building_type": "forge",
		"name": "Усиленные наконечники копий", "desc": "Открывает улучшенных копейщиков (+15% пробитие защиты).",
		"category": "weapons", "unlock_type": "ordinary",
		"cost": {"wood": 15, "metal": 20}, "prerequisites": ["forge_arrow_heads"],
		"effects": {"spear_armor_pierce": 0.15}
	},
	"forge_short_swords": {
		"id": "forge_short_swords", "building_type": "forge",
		"name": "Короткие мечи", "desc": "Позволяет вооружить мечников ближнего боя для дружины.",
		"category": "weapons", "unlock_type": "practical",
		"cost": {"wood": 15, "metal": 30}, "prerequisites": ["forge_bronze_spears"],
		"effects": {"unlock_swordsmen": true}
	},
	"forge_bellows": {
		"id": "forge_bellows", "building_type": "forge",
		"name": "Кожаные мехи", "desc": "Повышает температуру горна (+25% к скорости плавки руды).",
		"category": "smelting", "unlock_type": "ordinary",
		"cost": {"wood": 20, "metal": 10}, "prerequisites": [],
		"effects": {"smelting_speed": 0.25}
	},
	"forge_tempering": {
		"id": "forge_tempering", "building_type": "forge",
		"name": "Закалка металла в воде", "desc": "+25% к прочности оружия и долговечности инструментов.",
		"category": "smelting", "unlock_type": "event",
		"cost": {"metal": 20, "stone": 10}, "prerequisites": ["forge_bellows"],
		"effects": {"durability": 0.25, "weapon_power": 0.15}
	},

	# 2. МАСТЕРСКАЯ ПЛОТНИКА
	"carpenter_durable_handles": {
		"id": "carpenter_durable_handles", "building_type": "carpenter_workshop",
		"name": "Прочные ясеневые рукояти", "desc": "Снижает износ всех рабочих орудий труда на 20%.",
		"category": "tools", "unlock_type": "ordinary",
		"cost": {"wood": 25}, "prerequisites": [],
		"effects": {"tool_wear_reduction": 0.20}
	},
	"carpenter_hunting_bow": {
		"id": "carpenter_hunting_bow", "building_type": "carpenter_workshop",
		"name": "Охотничий составной лук", "desc": "+25% к дальности стрельбы и меткости охотников.",
		"category": "bows", "unlock_type": "ordinary",
		"cost": {"wood": 30}, "prerequisites": [],
		"effects": {"bow_range": 0.25}
	},
	"carpenter_longbow": {
		"id": "carpenter_longbow", "building_type": "carpenter_workshop",
		"name": "Тиссовый длинный лук", "desc": "Мощные дальнобойные луки для профессиональных лучников дружины.",
		"category": "bows", "unlock_type": "practical",
		"cost": {"wood": 40}, "prerequisites": ["carpenter_hunting_bow"],
		"effects": {"unlock_longbows": true, "archer_damage": 0.25}
	},
	"carpenter_wheel": {
		"id": "carpenter_wheel", "building_type": "carpenter_workshop",
		"name": "Изобретение колеса", "desc": "Огромный прорыв в логистике: открывает повозки и тачки.",
		"category": "transport", "unlock_type": "event",
		"cost": {"wood": 45, "stone": 10}, "prerequisites": [],
		"effects": {"logistics_boost": 0.35}
	},
	"carpenter_cart": {
		"id": "carpenter_cart", "building_type": "carpenter_workshop",
		"name": "Грузовые повозки", "desc": "+50% к вместимости переносимых ресурсов соплеменниками.",
		"category": "transport", "unlock_type": "ordinary",
		"cost": {"wood": 40}, "prerequisites": ["carpenter_wheel"],
		"effects": {"carry_capacity": 0.50}
	},
	"carpenter_timber_beams": {
		"id": "carpenter_timber_beams", "building_type": "carpenter_workshop",
		"name": "Несущие балки и стропила", "desc": "Позволяет строить двухэтажные дома и укрепленные здания.",
		"category": "construction", "unlock_type": "ordinary",
		"cost": {"wood": 50}, "prerequisites": ["carpenter_durable_handles"],
		"effects": {"building_tier_2_unlocked": true}
	},

	# 3. КАМЕНОЛОМНЯ
	"quarry_block_shaping": {
		"id": "quarry_block_shaping", "building_type": "stone_quarry",
		"name": "Обтёска каменных блоков", "desc": "+20% к прочности всех строений и оборонительных стен.",
		"category": "processing", "unlock_type": "ordinary",
		"cost": {"wood": 15, "stone": 30}, "prerequisites": [],
		"effects": {"building_hp_boost": 0.20}
	},
	"quarry_deep_shafts": {
		"id": "quarry_deep_shafts", "building_type": "stone_quarry",
		"name": "Глубокая проходка пластов", "desc": "+25% к шансу нахождения медной и железной руды в камне.",
		"category": "mining", "unlock_type": "practical",
		"cost": {"wood": 25, "stone": 40}, "prerequisites": ["quarry_block_shaping"],
		"effects": {"metal_find_chance": 0.25}
	},
	"quarry_stone_walls": {
		"id": "quarry_stone_walls", "building_type": "stone_quarry",
		"name": "Технология каменных стен", "desc": "Открывает строительство каменных фортификаций и башен.",
		"category": "construction", "unlock_type": "ordinary",
		"cost": {"wood": 20, "stone": 60}, "prerequisites": ["quarry_block_shaping"],
		"effects": {"unlock_stone_walls": true}
	},

	# 4. АМБАР-ХРАНИЛИЩЕ
	"granary_dry_decking": {
		"id": "granary_dry_decking", "building_type": "granary",
		"name": "Сухие приподнятые настилы", "desc": "Снижает порчу зерна и сушеных припасов на 30%.",
		"category": "preservation", "unlock_type": "ordinary",
		"cost": {"wood": 25}, "prerequisites": [],
		"effects": {"spoilage_reduction": 0.30}
	},
	"granary_pest_protection": {
		"id": "granary_pest_protection", "building_type": "granary",
		"name": "Защита от грызунов и сырости", "desc": "Снижает потери запасов на 60%, защищает амбар от вредителей.",
		"category": "preservation", "unlock_type": "ordinary",
		"cost": {"wood": 20, "stone": 20}, "prerequisites": ["granary_dry_decking"],
		"effects": {"spoilage_reduction": 0.60}
	},
	"granary_ice_cellar": {
		"id": "granary_ice_cellar", "building_type": "granary",
		"name": "Ледник-погреб", "desc": "Позволяет сохранять свежее мясо и рыбу без порчи в теплое время.",
		"category": "cooling", "unlock_type": "event",
		"cost": {"wood": 30, "stone": 40}, "prerequisites": ["granary_pest_protection"],
		"effects": {"meat_spoilage_zero": true}
	},

	# 5. ХИЖИНА СТАРЕЙШИНЫ
	"elders_lore_hearth": {
		"id": "elders_lore_hearth", "building_type": "elders_house",
		"name": "Очаг родовых преданий", "desc": "+15% к лояльности племени к вождю, сплоченность общины.",
		"category": "culture", "unlock_type": "ordinary",
		"cost": {"wood": 30, "stone": 15}, "prerequisites": [],
		"effects": {"loyalty_boost": 15.0}
	},
	"elders_council_chamber": {
		"id": "elders_council_chamber", "building_type": "elders_house",
		"name": "Зал Совета Рода", "desc": "Быстрое разрешение споров, снижение риска мятежей на 40%.",
		"category": "governance", "unlock_type": "ordinary",
		"cost": {"wood": 40, "stone": 25}, "prerequisites": ["elders_lore_hearth"],
		"effects": {"revolt_risk_reduction": 0.40}
	},
	"elders_chief_residence": {
		"id": "elders_chief_residence", "building_type": "elders_house",
		"name": "Хоромы Вождя", "desc": "Повышает дипломатический авторитет племени среди соседей.",
		"category": "power", "unlock_type": "ordinary",
		"cost": {"wood": 60, "stone": 35}, "prerequisites": ["elders_council_chamber"],
		"effects": {"diplo_prestige": 20.0}
	},

	# 6. СВЯТИЛИЩЕ ДУХОВ / АЛТАРЬ
	"shrine_sacred_fire": {
		"id": "shrine_sacred_fire", "building_type": "shrine",
		"name": "Вечный жертвенный огонь", "desc": "+25% к выработке веры, укрепляет надежду при невзгодах.",
		"category": "rituals", "unlock_type": "ordinary",
		"cost": {"wood": 20, "stone": 30}, "prerequisites": [],
		"effects": {"faith_generation": 0.25}
	},
	"shrine_ancestor_totem": {
		"id": "shrine_ancestor_totem", "building_type": "shrine",
		"name": "Резной тотем Предков", "desc": "+10 к морали воинов, защита стоянки от дурного глаза.",
		"category": "faith", "unlock_type": "ordinary",
		"cost": {"wood": 35, "stone": 20}, "prerequisites": ["shrine_sacred_fire"],
		"effects": {"army_morale_bonus": 10.0}
	},
	"shrine_stone_tablets": {
		"id": "shrine_stone_tablets", "building_type": "shrine",
		"name": "Каменные скрижали догматов", "desc": "Закрепляет священные законы веры, открывает великие обряды.",
		"category": "dogma", "unlock_type": "event",
		"cost": {"stone": 50}, "prerequisites": ["shrine_ancestor_totem"],
		"effects": {"unlock_great_rituals": true}
	},

	# 7. ОХОТНИЧИЙ ЛАГЕРЬ
	"hunt_bone_traps": {
		"id": "hunt_bone_traps", "building_type": "hunting_camp",
		"name": "Костяные силки и петли", "desc": "+20% к пассивной добыче мелкой дичи и перьев.",
		"category": "traps", "unlock_type": "ordinary",
		"cost": {"wood": 20}, "prerequisites": [],
		"effects": {"small_game_yield": 0.20}
	},
	"hunt_tracking": {
		"id": "hunt_tracking", "building_type": "hunting_camp",
		"name": "Следопытство и выслеживание", "desc": "+30% к добыче ценных шкур и мяса крупных копытных.",
		"category": "skills", "unlock_type": "practical",
		"cost": {"wood": 25}, "prerequisites": ["hunt_bone_traps"],
		"effects": {"large_game_yield": 0.30}
	},
	"hunt_dogs": {
		"id": "hunt_dogs", "building_type": "hunting_camp",
		"name": "Приручение охотничьих собак", "desc": "Охотники загоняют дичь вдвое быстрее, защита от хищников.",
		"category": "beasts", "unlock_type": "event",
		"cost": {"food": 30, "wood": 20}, "prerequisites": ["hunt_tracking"],
		"effects": {"hunt_speed_boost": 0.50}
	},

	# 8. ПЛОЩАДКА ВОИНОВ
	"training_targets": {
		"id": "training_targets", "building_type": "training_grounds",
		"name": "Учебные манекены и мишени", "desc": "+25% к скорости начального обучения новобранцев.",
		"category": "drills", "unlock_type": "ordinary",
		"cost": {"wood": 25, "stone": 10}, "prerequisites": [],
		"effects": {"training_speed": 0.25}
	},
	"training_shield_wall": {
		"id": "training_shield_wall", "building_type": "training_grounds",
		"name": "Отработка Щитовой Стены", "desc": "Открывает тактическую формацию 'Стена щитов' (+35% защиты пехоты).",
		"category": "tactics", "unlock_type": "practical",
		"cost": {"wood": 30, "metal": 15}, "prerequisites": ["training_targets"],
		"effects": {"unlock_shield_wall": true}
	},
	"training_commander_tent": {
		"id": "training_commander_tent", "building_type": "training_grounds",
		"name": "Шатер Воеводы / Штаб", "desc": "Позволяет официально назначить соплеменника Воеводой (Генералом).",
		"category": "command", "unlock_type": "ordinary",
		"cost": {"wood": 40, "stone": 20}, "prerequisites": ["training_targets"],
		"effects": {"unlock_general_appointment": true}
	},
	# 9. ЛАГЕРЬ ЛЕСОРУБОВ
	"woodcutter_forestry": {
		"id": "woodcutter_forestry", "building_type": "woodcutter_camp",
		"name": "Лесоводство и питомник саженцев", "desc": "Открывает функцию сеять лес! Лесорубы высаживают саженцы деревьев на вырубках, и они снова вырастают.",
		"category": "ecology", "unlock_type": "ordinary",
		"cost": {"wood": 30, "stone": 10}, "prerequisites": [],
		"effects": {"can_plant_trees": true}
	},
	"woodcutter_iron_axes": {
		"id": "woodcutter_iron_axes", "building_type": "woodcutter_camp",
		"name": "Закалённые топоры лесорубов", "desc": "Ускоряет рубку деревьев на 30% и увеличивает скорость заготовки дров.",
		"category": "tools", "unlock_type": "ordinary",
		"cost": {"wood": 20, "metal": 10}, "prerequisites": [],
		"effects": {"woodcutting_speed": 0.30}
	}
}

static func get_modes_for_building(b_type: String) -> Array:
	return BUILDING_MODES.get(b_type, [])

static func get_upgrades_for_building(b_type: String) -> Array:
	var list = []
	for u_id in UPGRADES:
		if UPGRADES[u_id]["building_type"] == b_type:
			list.append(UPGRADES[u_id])
	return list

static func get_upgrade(u_id: String) -> Dictionary:
	return UPGRADES.get(u_id, {})
