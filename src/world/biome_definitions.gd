class_name BiomeDefinitions
extends RefCounted

enum BiomeType {
	DEEP_OCEAN,
	SHALLOW_COAST,
	PLAINS,
	MEADOW,
	DECIDUOUS_FOREST,
	PINE_TAIGA,
	JUNGLE,
	SAVANNA,
	DESERT,
	SWAMP,
	HILLS,
	MOUNTAINS,
	SNOW_PEAKS,
	TUNDRA
}

const BIOME_DATA: Dictionary = {
	BiomeType.DEEP_OCEAN: {
		"name": "Глубокий океан",
		"color": Color(0.12, 0.22, 0.42),
		"is_water": true,
		"fertility": 0.0,
		"food": 0.2, # Рыболовство в будущем
		"wood": 0.0,
		"stone": 0.0,
		"metal": 0.0,
		"passable": false
	},
	BiomeType.SHALLOW_COAST: {
		"name": "Мелководье / Побережье",
		"color": Color(0.24, 0.46, 0.65),
		"is_water": true,
		"fertility": 0.1,
		"food": 0.6,
		"wood": 0.0,
		"stone": 0.1,
		"metal": 0.0,
		"passable": false
	},
	BiomeType.PLAINS: {
		"name": "Плодородные равнины",
		"color": Color(0.48, 0.68, 0.32),
		"is_water": false,
		"fertility": 0.8,
		"food": 0.7,
		"wood": 0.2,
		"stone": 0.2,
		"metal": 0.1,
		"passable": true
	},
	BiomeType.MEADOW: {
		"name": "Луга и степи",
		"color": Color(0.58, 0.76, 0.38),
		"is_water": false,
		"fertility": 0.7,
		"food": 0.8,
		"wood": 0.3,
		"stone": 0.3,
		"metal": 0.1,
		"passable": true
	},
	BiomeType.DECIDUOUS_FOREST: {
		"name": "Лиственный лес",
		"color": Color(0.28, 0.52, 0.22),
		"is_water": false,
		"fertility": 0.6,
		"food": 0.9, # Дичь, грибы, ягоды
		"wood": 1.0,
		"stone": 0.3,
		"metal": 0.2,
		"passable": true
	},
	BiomeType.PINE_TAIGA: {
		"name": "Хвойная тайга",
		"color": Color(0.18, 0.40, 0.26),
		"is_water": false,
		"fertility": 0.3,
		"food": 0.6,
		"wood": 0.9,
		"stone": 0.4,
		"metal": 0.3,
		"passable": true
	},
	BiomeType.JUNGLE: {
		"name": "Тропические джунгли",
		"color": Color(0.12, 0.45, 0.18),
		"is_water": false,
		"fertility": 0.7,
		"food": 0.8,
		"wood": 1.0,
		"stone": 0.2,
		"metal": 0.3,
		"passable": true
	},
	BiomeType.SAVANNA: {
		"name": "Саванна",
		"color": Color(0.72, 0.68, 0.32),
		"is_water": false,
		"fertility": 0.4,
		"food": 0.7, # Стада животных
		"wood": 0.3,
		"stone": 0.3,
		"metal": 0.2,
		"passable": true
	},
	BiomeType.DESERT: {
		"name": "Песчаная пустыня",
		"color": Color(0.85, 0.78, 0.48),
		"is_water": false,
		"fertility": 0.05,
		"food": 0.1,
		"wood": 0.05,
		"stone": 0.4,
		"metal": 0.4,
		"passable": true
	},
	BiomeType.SWAMP: {
		"name": "Болота и топи",
		"color": Color(0.35, 0.44, 0.28),
		"is_water": false,
		"fertility": 0.4,
		"food": 0.5,
		"wood": 0.5,
		"stone": 0.1,
		"metal": 0.3, # Болотная руда
		"passable": true
	},
	BiomeType.HILLS: {
		"name": "Холмистая гряда",
		"color": Color(0.55, 0.52, 0.38),
		"is_water": false,
		"fertility": 0.4,
		"food": 0.4,
		"wood": 0.4,
		"stone": 0.8,
		"metal": 0.6,
		"passable": true
	},
	BiomeType.MOUNTAINS: {
		"name": "Скалистые горы",
		"color": Color(0.48, 0.46, 0.45),
		"is_water": false,
		"fertility": 0.1,
		"food": 0.2,
		"wood": 0.2,
		"stone": 1.0,
		"metal": 0.9,
		"passable": true
	},
	BiomeType.SNOW_PEAKS: {
		"name": "Заснеженные вершины",
		"color": Color(0.88, 0.90, 0.94),
		"is_water": false,
		"fertility": 0.0,
		"food": 0.0,
		"wood": 0.0,
		"stone": 0.8,
		"metal": 0.7,
		"passable": false
	},
	BiomeType.TUNDRA: {
		"name": "Северная тундра",
		"color": Color(0.62, 0.68, 0.64),
		"is_water": false,
		"fertility": 0.15,
		"food": 0.3,
		"wood": 0.2,
		"stone": 0.5,
		"metal": 0.4,
		"passable": true
	}
}

static func get_biome_info(type: BiomeType) -> Dictionary:
	return BIOME_DATA.get(type, BIOME_DATA[BiomeType.PLAINS])
