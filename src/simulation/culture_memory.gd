class_name CultureMemory
extends RefCounted

# ==============================================================================
# PLANETKI — CULTURE MEMORY & CIVILIZATION STATE
# Автор авторитетного состояния традиций, норм, веры и форм власти
# ==============================================================================

# Запись отдельной культурной нормы
class MemoryEntry extends RefCounted:
	var id: String = ""
	var value: Variant = true
	var strength: float = 50.0 # 0..100 (Сила укоренения традиции)
	var established_year: int = 1
	var established_day: int = 1
	var source_event_id: String = ""
	var source_choice_title: String = ""
	var category: String = "Общее" # Брак, Власть, Вера, Суд, Земля, Война, Налоги
	var supporters: String = "Старейшины и соплеменники"
	var opponents: String = "Нет"
	var reformable: bool = true

# Взаимоисключающие группы (Exclusive Groups)
var exclusive_groups: Dictionary = {
	"marriage_structure": "UNDEFINED",   # MONOGAMY, POLYGYNY, POLYANDRY, UNREGULATED
	"marriage_consent": "UNDEFINED",     # INDIVIDUAL_CONSENT, FAMILY_CHOICE, PATRIARCHAL, FREE_UNREGULATED
	"union_recognition": "UNDEFINED",    # WORD_OF_COUPLE, FAMILY_CONSENT, PRIEST_BLESSING, RULER_REGISTRATION
	"burial_practice": "UNDEFINED",      # EARTH_BURIAL, CREMATION, NATURE_EXPOSURE, FAMILY_DISCRETION
	"cannibalism_taboo": "UNDEFINED",    # TOTAL_TABOO, OUTGROUP_ONLY, SURVIVAL_ALLOWED
	"land_ownership": "UNDEFINED",       # CULTIVATOR, CLAN, COMMUNAL, RULER_STATE
	"justice_system": "UNDEFINED",       # BLOOD_FEUD, COUNCIL_JUSTICE, COMPOSITION_FINE, RULER_JUSTICE, EXILE
	"authority_structure": "UNDEFINED",  # LIFELONG_RULER, COUNCIL_BOUND, PRESTIGE_MERIT, FIRST_AMONG_EQUALS
	"succession_rule": "UNDEFINED",      # PRIMOGENITURE_SON, PRIMOGENITURE_ANY, COUNCIL_ELECT, POPULAR_ASSEMBLY, BEST_WARRIOR, THEOCRATIC
	"religion_base": "UNDEFINED",        # ANIMISM, MONOTHEISM, POLYTHEISM, ANCESTOR_WORSHIP, EARLY_RATIONALISM
	"slavery_model": "UNDEFINED",        # FORBIDDEN, WAR_CAPTIVE_SLAVERY, TEMPORARY_BONDAGE, COMMUNAL_LABOR
	"military_duty": "UNDEFINED",        # UNIVERSAL_MALE, UNIVERSAL_ALL, CLAN_WARBANDS, WARRIOR_CLASS
	"tax_levy_model": "UNDEFINED"        # EQUAL_HOUSEHOLD, PROGRESSIVE, CLAN_QUOTA, RULER_DISCRETION, VOLUNTARY
}

# Реестр всех принятых норм: id -> MemoryEntry
var entries: Dictionary = {}

# Состояние религии (возникает строго из событий)
var religion_data: Dictionary = {
	"defined": false,
	"type": "UNDEFINED", # ANIMISM, MONOTHEISM, POLYTHEISM, ANCESTOR_WORSHIP, EARLY_RATIONALISM
	"name": "Не оформлено",
	"deity_name": "",
	"pantheon_name": "",
	"established_year": 1,
	"sacred_places": [],
	"clergy_model": "UNDEFINED", # NONE, PRIESTHOOD, RULER_PRIEST, CLAN_RITES, INDIVIDUAL
	"dogmas": []
}

# Открытые через события специальные здания
var unlocked_special_buildings: Array[String] = []

# Открытые практические открытия (вместо старого tech tree)
var discovered_practices: Array[String] = []

# Летопись решений цивилизации
var civilization_chronicle: Array[Dictionary] = []

# Название народа (формируется в событии EVENT-NAME-01)
var tribe_folk_name: String = "Люди Рассвета"

# ==============================================================================
# МЕТОДЫ РАБОТЫ С КУЛЬТУРНОЙ ПАМЯТЬЮ
# ==============================================================================

func set_tradition(entry_id: String, group_name: String, group_value: String, title: String, event_id: String, choice_title: String, category: String, cur_year: int, cur_day: int, initial_strength: float = 60.0) -> void:
	if group_name != "" and exclusive_groups.has(group_name):
		exclusive_groups[group_name] = group_value
		
	var entry = MemoryEntry.new()
	entry.id = entry_id
	entry.value = group_value if group_value != "" else true
	entry.strength = initial_strength
	entry.established_year = cur_year
	entry.established_day = cur_day
	entry.source_event_id = event_id
	entry.source_choice_title = choice_title
	entry.category = category
	
	entries[entry_id] = entry
	
	# Запись в летопись цивилизации
	civilization_chronicle.append({
		"year": cur_year,
		"day": cur_day,
		"title": title,
		"choice": choice_title,
		"event_id": event_id,
		"category": category
	})

func has_tradition(entry_id: String) -> bool:
	return entries.has(entry_id)

func get_group_value(group_name: String) -> String:
	return exclusive_groups.get(group_name, "UNDEFINED")

func is_group_value(group_name: String, check_value: String) -> bool:
	return exclusive_groups.get(group_name, "UNDEFINED") == check_value

func unlock_building(building_id: String) -> void:
	if not unlocked_special_buildings.has(building_id):
		unlocked_special_buildings.append(building_id)

func is_building_unlocked(building_id: String) -> bool:
	# Базовые здания 1-й эпохи доступны всегда, специальные требуют события
	var base_buildings = ["elders_house", "hunting_camp", "granary", "carpenter_workshop", "stone_quarry", "forge", "training_grounds"]
	if building_id in base_buildings:
		return true
	return unlocked_special_buildings.has(building_id)

func unlock_practice(practice_id: String) -> void:
	if not discovered_practices.has(practice_id):
		discovered_practices.append(practice_id)

# ==============================================================================
# ПРОИЗВОДНАЯ ФОРМА ПРАВЛЕНИЯ (DERIVED GOVERNMENT STATE)
# ==============================================================================

func get_derived_government() -> Dictionary:
	var auth = get_group_value("authority_structure")
	var succ = get_group_value("succession_rule")
	var rel = get_group_value("religion_base")
	
	var title = "Родовое вождество"
	var desc = "Традиционная родовая община, объединённая вокруг старейшин и костра."
	var council_power = "Умеренная"
	var ruler_power = "Ограниченная традициями"
	
	if auth == "LIFELONG_RULER":
		if succ == "PRIMOGENITURE_SON" or succ == "PRIMOGENITURE_ANY":
			title = "Наследственное вождество"
			desc = "Единоличная власть вождя, передаваемая по праву рождения из поколения в поколение."
			ruler_power = "Высокая"
			council_power = "Совещательная"
		elif succ == "BEST_WARRIOR":
			title = "Военная деспотия"
			desc = "Власть принадлежит сильнейшему воину, способному силой удерживать племя в повиновении."
			ruler_power = "Абсолютная"
			council_power = "Слабая"
		else:
			title = "Пожизненное вождество"
			desc = "Вождь правит пожизненно, обладая высшим авторитетом во всех делах племени."
			ruler_power = "Высокая"
			council_power = "Умеренная"
			
	elif auth == "COUNCIL_BOUND":
		if succ == "COUNCIL_ELECT":
			title = "Советное выборное вождество"
			desc = "Вождь подотчётен Совету старейшин, который утверждает ключевые решения и избирает нового лидера."
			council_power = "Верховная"
			ruler_power = "Исполнительная"
		else:
			title = "Племенной Совет"
			desc = "Власть разделена между старейшинами основных родов племени."
			council_power = "Высокая"
			ruler_power = "Ограниченная"
			
	elif auth == "FIRST_AMONG_EQUALS":
		if succ == "POPULAR_ASSEMBLY":
			title = "Общинное вечевое вождество"
			desc = "Все ключевые вопросы решаются на общем сходе свободных людей племени."
			council_power = "Народное собрание"
			ruler_power = "Первый среди равных"
		else:
			title = "Родовая община"
			desc = "Вождь лишь координирует действия семей и родов."
			council_power = "Автономия родов"
			ruler_power = "Слабая"
			
	if rel == "MONOTHEISM" and religion_data.get("clergy_model", "") == "RULER_PRIEST":
		title = "Священное теократическое вождество"
		desc = "Вождь признан наместником бога и верховным священнослужителем народа."
		ruler_power = "Сакральная"
		
	return {
		"title": title,
		"description": desc,
		"ruler_power": ruler_power,
		"council_power": council_power,
		"authority": auth,
		"succession": succ
	}

# ==============================================================================
# СЕРИАЛИЗАЦИЯ ДЛЯ СОХРАНЕНИЙ
# ==============================================================================

func serialize() -> Dictionary:
	var serialized_entries = {}
	for k in entries:
		var e = entries[k]
		serialized_entries[k] = {
			"id": e.id,
			"value": e.value,
			"strength": e.strength,
			"established_year": e.established_year,
			"established_day": e.established_day,
			"source_event_id": e.source_event_id,
			"source_choice_title": e.source_choice_title,
			"category": e.category,
			"supporters": e.supporters,
			"opponents": e.opponents
		}
	return {
		"exclusive_groups": exclusive_groups,
		"entries": serialized_entries,
		"religion_data": religion_data,
		"unlocked_special_buildings": unlocked_special_buildings,
		"discovered_practices": discovered_practices,
		"civilization_chronicle": civilization_chronicle,
		"tribe_folk_name": tribe_folk_name
	}

func deserialize(data: Dictionary) -> void:
	exclusive_groups = data.get("exclusive_groups", exclusive_groups)
	religion_data = data.get("religion_data", religion_data)
	unlocked_special_buildings = Array(data.get("unlocked_special_buildings", []))
	discovered_practices = Array(data.get("discovered_practices", []))
	civilization_chronicle = data.get("civilization_chronicle", [])
	tribe_folk_name = data.get("tribe_folk_name", "Люди Рассвета")
	
	entries.clear()
	var raw_entries = data.get("entries", {})
	for k in raw_entries:
		var item = raw_entries[k]
		var e = MemoryEntry.new()
		e.id = item.get("id", k)
		e.value = item.get("value", true)
		e.strength = float(item.get("strength", 50.0))
		e.established_year = int(item.get("established_year", 1))
		e.established_day = int(item.get("established_day", 1))
		e.source_event_id = item.get("source_event_id", "")
		e.source_choice_title = item.get("source_choice_title", "")
		e.category = item.get("category", "Общее")
		e.supporters = item.get("supporters", "")
		e.opponents = item.get("opponents", "")
		entries[k] = e
