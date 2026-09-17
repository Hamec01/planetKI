class_name EquipmentDB
extends RefCounted

# ==============================================================================
# ЕДИНЫЙ РЕЕСТР ОРУЖИЯ, БРОНИ, ЩИТОВ И РЕЦЕПТОВ МАСТЕРСКОЙ (PLANETKI v2)
# ==============================================================================

# 1. Оружие (Разделы 8 и 22 ТЗ)
const WEAPONS = {
	"unarmed": {
		"id": "unarmed",
		"name": "Кулаки",
		"damage": 0.0,
		"interval": 1.8,
		"range": 0.6,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "axe", # или нейтральный
		"is_ranged": false,
		"is_metal": false
	},
	"club": {
		"id": "club",
		"name": "Дубина",
		"damage": 8.0,
		"interval": 1.7,
		"range": 0.8,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "axe",
		"is_ranged": false,
		"is_metal": false
	},
	"knife": {
		"id": "knife",
		"name": "Нож",
		"damage": 5.0,
		"interval": 1.1,
		"range": 0.6,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "sword",
		"is_ranged": false,
		"is_metal": true
	},
	"work_axe": {
		"id": "work_axe",
		"name": "Рабочий топор",
		"damage": 10.0,
		"interval": 1.8,
		"range": 0.8,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "axe",
		"is_ranged": false,
		"is_metal": false
	},
	"copper_work_axe": {
		"id": "copper_work_axe",
		"name": "Медный рабочий топор",
		"damage": 10.0,
		"interval": 1.8,
		"range": 0.8,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "axe",
		"is_ranged": false,
		"is_metal": true,
		"woodcutting_speed_bonus": 0.15
	},
	"simple_spear": {
		"id": "simple_spear",
		"name": "Простое копьё",
		"damage": 13.0,
		"interval": 1.7,
		"range": 1.4,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "spear",
		"is_ranged": false,
		"is_metal": false
	},
	"reinforced_spear": {
		"id": "reinforced_spear",
		"name": "Усиленное копьё",
		"damage": 13.0,
		"interval": 1.7,
		"range": 1.4,
		"pen_flat": 0.0,
		"pen_fraction": 0.15, # игнорирует 15% брони
		"skill_type": "spear",
		"is_ranged": false,
		"is_metal": true
	},
	"short_sword": {
		"id": "short_sword",
		"name": "Короткий меч",
		"damage": 16.0,
		"interval": 1.3,
		"range": 0.9,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "sword",
		"is_ranged": false,
		"is_metal": true
	},
	"battle_axe": {
		"id": "battle_axe",
		"name": "Боевой топор",
		"damage": 20.0,
		"interval": 1.8,
		"range": 0.9,
		"pen_flat": 5.0, # пробитие 5 пунктов
		"pen_fraction": 0.0,
		"skill_type": "axe",
		"is_ranged": false,
		"is_metal": true
	},
	"hunting_bow": {
		"id": "hunting_bow",
		"name": "Охотничий лук",
		"damage": 12.0,
		"interval": 2.4,
		"range": 5.0,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "bow",
		"is_ranged": true,
		"is_metal": false
	},
	"improved_hunting_bow": {
		"id": "improved_hunting_bow",
		"name": "Улучшенный охотничий лук",
		"damage": 12.0,
		"interval": 2.4,
		"range": 6.25,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "bow",
		"is_ranged": true,
		"is_metal": false
	},
	"longbow": {
		"id": "longbow",
		"name": "Длинный боевой лук",
		"damage": 17.0,
		"interval": 2.2,
		"range": 6.0,
		"pen_flat": 0.0,
		"pen_fraction": 0.0,
		"skill_type": "bow",
		"is_ranged": true,
		"is_metal": false
	}
}

# 2. Защита тела (Раздел 9 ТЗ)
const BODY_ARMOR = {
	"clothes": {
		"id": "clothes",
		"name": "Обычная одежда",
		"armor": 0.0,
		"speed_mod": 0.0
	},
	"padded_armor": {
		"id": "padded_armor",
		"name": "Стёганая защита",
		"armor": 10.0,
		"speed_mod": -0.02
	},
	"leather_armor": {
		"id": "leather_armor",
		"name": "Кожаная защита",
		"armor": 15.0,
		"speed_mod": -0.03
	},
	"chainmail": {
		"id": "chainmail",
		"name": "Кольчуга",
		"armor": 30.0,
		"speed_mod": -0.08
	}
}

# 3. Шлемы (Раздел 9 ТЗ)
const HELMETS = {
	"iron_helmet": {
		"id": "iron_helmet",
		"name": "Простой железный шлем",
		"armor": 8.0,
		"speed_mod": -0.01
	},
	"reinforced_helmet": {
		"id": "reinforced_helmet",
		"name": "Большой усиленный шлем",
		"armor": 12.0,
		"speed_mod": -0.02
	}
}

# 4. Щиты (Раздел 9 ТЗ)
const SHIELDS = {
	"wooden_shield": {
		"id": "wooden_shield",
		"name": "Деревянный щит",
		"armor": 10.0,
		"speed_mod": -0.02
	},
	"reinforced_shield": {
		"id": "reinforced_shield",
		"name": "Усиленный щит",
		"armor": 15.0,
		"speed_mod": -0.03
	}
}

# 5. Рецепты производства в мастерской (Раздел 22.2 ТЗ)
const RECIPES = {
	"club": {
		"id": "club",
		"category": "weapon",
		"name": "Дубина",
		"workshop_type": "craft_workshop",
		"specialization": "basic",
		"cost": {"wood": 2},
		"work_days": 0.25,
		"tech_req": "",
		"upgrade_req": ""
	},
	"knife": {
		"id": "knife",
		"category": "weapon",
		"name": "Нож",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"wood": 1, "metal": 2},
		"work_days": 0.5,
		"tech_req": "bronze_working",
		"upgrade_req": ""
	},
	"work_axe": {
		"id": "work_axe",
		"category": "weapon",
		"name": "Рабочий топор",
		"workshop_type": "craft_workshop",
		"specialization": "basic",
		"cost": {"wood": 2, "stone": 2},
		"work_days": 0.5,
		"tech_req": "",
		"upgrade_req": ""
	},
	"copper_work_axe": {
		"id": "copper_work_axe",
		"category": "weapon",
		"name": "Медный рабочий топор",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"wood": 2, "metal": 3},
		"work_days": 0.75,
		"tech_req": "bronze_working",
		"upgrade_req": "forge_copper_axes"
	},
	"simple_spear": {
		"id": "simple_spear",
		"category": "weapon",
		"name": "Простое копьё",
		"workshop_type": "craft_workshop",
		"specialization": "basic",
		"cost": {"wood": 3, "stone": 1},
		"work_days": 0.5,
		"tech_req": "",
		"upgrade_req": ""
	},
	"reinforced_spear": {
		"id": "reinforced_spear",
		"category": "weapon",
		"name": "Усиленное копьё",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"wood": 3, "metal": 3},
		"work_days": 1.0,
		"tech_req": "bronze_working",
		"upgrade_req": "forge_bronze_spears"
	},
	"short_sword": {
		"id": "short_sword",
		"category": "weapon",
		"name": "Короткий меч",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"wood": 1, "metal": 6},
		"work_days": 1.5,
		"tech_req": "bronze_working",
		"upgrade_req": "forge_short_swords"
	},
	"battle_axe": {
		"id": "battle_axe",
		"category": "weapon",
		"name": "Боевой топор",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"wood": 2, "metal": 5},
		"work_days": 1.25,
		"tech_req": "bronze_working",
		"upgrade_req": "forge_bronze_spears" # после копий
	},
	"hunting_bow": {
		"id": "hunting_bow",
		"category": "weapon",
		"name": "Простой охотничий лук",
		"workshop_type": "craft_workshop",
		"specialization": "woodworking",
		"cost": {"wood": 4},
		"work_days": 0.75,
		"tech_req": "",
		"upgrade_req": ""
	},
	"improved_hunting_bow": {
		"id": "improved_hunting_bow",
		"category": "weapon",
		"name": "Улучшенный охотничий лук",
		"workshop_type": "craft_workshop",
		"specialization": "woodworking",
		"cost": {"wood": 6},
		"work_days": 1.0,
		"tech_req": "",
		"upgrade_req": "carpenter_hunting_bow"
	},
	"longbow": {
		"id": "longbow",
		"category": "weapon",
		"name": "Длинный боевой лук",
		"workshop_type": "craft_workshop",
		"specialization": "woodworking",
		"cost": {"wood": 8},
		"work_days": 1.5,
		"tech_req": "",
		"upgrade_req": "carpenter_longbow"
	},
	"wooden_shield": {
		"id": "wooden_shield",
		"category": "shield",
		"name": "Деревянный щит",
		"workshop_type": "craft_workshop",
		"specialization": "woodworking",
		"cost": {"wood": 3, "leather": 1},
		"work_days": 0.5,
		"tech_req": "",
		"upgrade_req": ""
	},
	"reinforced_shield": {
		"id": "reinforced_shield",
		"category": "shield",
		"name": "Усиленный щит",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"wood": 3, "metal": 2},
		"work_days": 1.0,
		"tech_req": "bronze_working",
		"upgrade_req": ""
	},
	"padded_armor": {
		"id": "padded_armor",
		"category": "body_armor",
		"name": "Стёганая защита",
		"workshop_type": "craft_workshop",
		"specialization": "basic",
		"cost": {"cloth": 3},
		"work_days": 0.75,
		"tech_req": "",
		"upgrade_req": ""
	},
	"leather_armor": {
		"id": "leather_armor",
		"category": "body_armor",
		"name": "Кожаная защита",
		"workshop_type": "craft_workshop",
		"specialization": "basic",
		"cost": {"leather": 4},
		"work_days": 1.0,
		"tech_req": "",
		"upgrade_req": ""
	},
	"chainmail": {
		"id": "chainmail",
		"category": "body_armor",
		"name": "Кольчуга",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"metal": 8},
		"work_days": 2.5,
		"tech_req": "bronze_working",
		"upgrade_req": ""
	},
	"iron_helmet": {
		"id": "iron_helmet",
		"category": "helmet",
		"name": "Простой железный шлем",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"metal": 3},
		"work_days": 0.75,
		"tech_req": "bronze_working",
		"upgrade_req": ""
	},
	"reinforced_helmet": {
		"id": "reinforced_helmet",
		"category": "helmet",
		"name": "Большой усиленный шлем",
		"workshop_type": "craft_workshop",
		"specialization": "metalworking",
		"cost": {"metal": 5},
		"work_days": 1.25,
		"tech_req": "bronze_working",
		"upgrade_req": ""
	}
}

# 6. Модификации предметов (Раздел 22.4 ТЗ)
const MODIFICATIONS = {
	"sharpening": {
		"id": "sharpening",
		"name": "Заточка",
		"target_category": "melee",
		"cost": {"metal": 1},
		"work_days": 0.25,
		"effect_desc": "+2 к урону ближнего оружия"
	},
	"tempering": {
		"id": "tempering",
		"name": "Закалка",
		"target_category": "metal_melee",
		"cost": {"metal": 2},
		"work_days": 0.5,
		"upgrade_req": "forge_tempering",
		"effect_desc": "+15% к компоненту урона металлического оружия"
	},
	"forged_arrows": {
		"id": "forged_arrows",
		"name": "Кованые наконечники стрел (комплект 20 шт.)",
		"target_category": "arrows",
		"cost": {"wood": 2, "metal": 2},
		"work_days": 0.5,
		"upgrade_req": "forge_arrow_heads",
		"effect_desc": "+20% к урону стрел"
	},
	"basic_arrows": {
		"id": "basic_arrows",
		"name": "Обычные стрелы (комплект 20 шт.)",
		"target_category": "arrows",
		"cost": {"wood": 2, "stone": 1},
		"work_days": 0.25,
		"effect_desc": "Базовые стрелы без бонуса"
	}
}

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ПОИСКА И ПРОВЕРКИ
# ==============================================================================
static func get_weapon(weapon_id: String) -> Dictionary:
	if WEAPONS.has(weapon_id):
		return WEAPONS[weapon_id]
	return WEAPONS["unarmed"]

static func get_armor_value(armor_id: String) -> float:
	if BODY_ARMOR.has(armor_id):
		return float(BODY_ARMOR[armor_id].get("armor", 0.0))
	return 0.0

static func get_helmet_value(helmet_id: String) -> float:
	if HELMETS.has(helmet_id):
		return float(HELMETS[helmet_id].get("armor", 0.0))
	return 0.0

static func get_shield_value(shield_id: String) -> float:
	if SHIELDS.has(shield_id):
		return float(SHIELDS[shield_id].get("armor", 0.0))
	return 0.0

static func get_recipe(item_id: String) -> Dictionary:
	if RECIPES.has(item_id):
		return RECIPES[item_id]
	return {}
