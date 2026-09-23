class_name EmoteTextureManager
extends Object

## Менеджер текстур, категорий и метаданных облачков-эмоций/состояний NPC (96 иконок: 48 базовых + 48 социальных/жизненных)

const CATEGORY_EMOTIONS: String = "emotions"
const CATEGORY_NEEDS: String = "needs"
const CATEGORY_HEALTH: String = "health"
const CATEGORY_SOCIAL: String = "social"
const CATEGORY_EVENTS: String = "events"
const CATEGORY_WORLDVIEW: String = "worldview"
const CATEGORY_LEISURE: String = "leisure"
const CATEGORY_LIFECYCLE: String = "lifecycle"
const CATEGORY_HOUSING_LAW: String = "housing_law"
const CATEGORY_ECONOMY_LABOR: String = "economy_labor"
const CATEGORY_REPUTATION: String = "reputation"

const CATEGORIES: Dictionary = {
	"emotions": {"name": "Эмоции", "desc": "Радость, грусть, злость, страх, влюбленность и душевные переживания"},
	"needs": {"name": "Потребности", "desc": "Голод, жажда, сонливость, усталость, холод и жара"},
	"health": {"name": "Здоровье", "desc": "Болезни, травмы, ранения, боль и головокружение"},
	"social": {"name": "Отношения и социум", "desc": "Диалоги, знакомства, примирение, ссоры, слухи, ревность и зависть"},
	"reputation": {"name": "Репутация и психология", "desc": "Уважение, гордость, стыд, одиночество, отчаяние и самоуважение"},
	"lifecycle": {"name": "Семья и жизненный цикл", "desc": "Беременность, рождение, дети, сироты, старость, брак и семья"},
	"housing_law": {"name": "Жильё, закон и право", "desc": "Дом, пожар, налог, вор, тюрьма, рабство, свобода и восстание"},
	"economy_labor": {"name": "Экономика и труд", "desc": "Бедность, долг, торговля, просьба о помощи, приказ, нехватка орудий и забастовка"},
	"events": {"name": "События и дела", "desc": "Идеи, важные вести, опасность, законы, богатство и работа"},
	"worldview": {"name": "Мировоззрение и вера", "desc": "Молитвы, погребение, верность вождю, отказ и бунт"},
	"leisure": {"name": "Досуг и праздник", "desc": "Праздники, пиры, музыка, танцы и веселье у костра"}
}

const EMOTES_DATA: Dictionary = {
	# =========================================================================
	# ЛИСТ 1 (48 базовых эмоций, потребностей, состояний здоровья и сигналов)
	# =========================================================================
	"dialog": {
		"name": "Диалог",
		"category": CATEGORY_SOCIAL,
		"desc": "NPC хочет поговорить, обычная реплика или разговор.",
		"priority": 2
	},
	"question": {
		"name": "Вопрос",
		"category": CATEGORY_SOCIAL,
		"desc": "NPC чего-то не понимает, хочет спросить игрока или соплеменника.",
		"priority": 2
	},
	"important": {
		"name": "Важно / тревога",
		"category": CATEGORY_EVENTS,
		"desc": "Срочное событие, проблема, важное сообщение.",
		"priority": 4
	},
	"idea": {
		"name": "Идея",
		"category": CATEGORY_EVENTS,
		"desc": "NPC придумал решение, улучшение или новый способ что-то сделать.",
		"priority": 3
	},
	"thought": {
		"name": "Размышление",
		"category": CATEGORY_EVENTS,
		"desc": "Персонаж думает, сомневается, обдумывает ситуацию.",
		"priority": 1
	},
	"confusion": {
		"name": "Растерянность",
		"category": CATEGORY_EVENTS,
		"desc": "NPC не понимает, что происходит, несколько вопросов одновременно.",
		"priority": 2
	},
	"joy": {
		"name": "Радость",
		"category": CATEGORY_EMOTIONS,
		"desc": "Хорошее настроение, удовлетворённость жизнью.",
		"priority": 2
	},
	"great_fun": {
		"name": "Сильное веселье",
		"category": CATEGORY_LEISURE,
		"desc": "Смех, праздник, очень хорошее настроение.",
		"priority": 3
	},
	"sympathy": {
		"name": "Симпатия / довольство",
		"category": CATEGORY_SOCIAL,
		"desc": "NPC расположен к кому-то, лёгкая дружелюбность.",
		"priority": 2
	},
	"love": {
		"name": "Любовь",
		"category": CATEGORY_EMOTIONS,
		"desc": "Сильная привязанность, романтическое чувство.",
		"priority": 3
	},
	"romance": {
		"name": "Влюблённость / романтика",
		"category": CATEGORY_SOCIAL,
		"desc": "Начало отношений, флирт, романтический интерес.",
		"priority": 3
	},
	"couple": {
		"name": "Пара / отношения",
		"category": CATEGORY_SOCIAL,
		"desc": "Любовь между двумя NPC, семья, супружеская связь.",
		"priority": 3
	},
	"sadness": {
		"name": "Грусть",
		"category": CATEGORY_EMOTIONS,
		"desc": "Плохое настроение, разочарование.",
		"priority": 2
	},
	"grief": {
		"name": "Сильная печаль",
		"category": CATEGORY_EMOTIONS,
		"desc": "Плач, потеря близкого, глубокое горе.",
		"priority": 4
	},
	"depression": {
		"name": "Уныние",
		"category": CATEGORY_EMOTIONS,
		"desc": "Подавленность, недовольство жизнью.",
		"priority": 2
	},
	"anger": {
		"name": "Злость",
		"category": CATEGORY_EMOTIONS,
		"desc": "Раздражение или назревающий конфликт.",
		"priority": 3
	},
	"combat": {
		"name": "Бой / конфликт",
		"category": CATEGORY_SOCIAL,
		"desc": "NPC готов драться или находится в вооружённом конфликте.",
		"priority": 5
	},
	"rage": {
		"name": "Ярость",
		"category": CATEGORY_EMOTIONS,
		"desc": "Сильный гнев, драка, бунт или месть.",
		"priority": 4
	},
	"discontent": {
		"name": "Недовольство",
		"category": CATEGORY_EMOTIONS,
		"desc": "NPC раздражён условиями или приказом, но ещё не агрессивен.",
		"priority": 2
	},
	"anxiety": {
		"name": "Тревога",
		"category": CATEGORY_EMOTIONS,
		"desc": "Нервозность, опасение, ожидание плохого.",
		"priority": 2
	},
	"panic": {
		"name": "Паника",
		"category": CATEGORY_EMOTIONS,
		"desc": "Персонаж сильно напуган и спасается бегством.",
		"priority": 5
	},
	"surprise": {
		"name": "Удивление",
		"category": CATEGORY_EMOTIONS,
		"desc": "Неожиданное событие, открытие, новость.",
		"priority": 2
	},
	"shock": {
		"name": "Шок / ужас",
		"category": CATEGORY_EMOTIONS,
		"desc": "Сильный испуг, смерть, нападение зверя, катастрофа.",
		"priority": 5
	},
	"suspicion": {
		"name": "Подозрение",
		"category": CATEGORY_SOCIAL,
		"desc": "NPC кому-то не доверяет, выслеживает, считает странным.",
		"priority": 2
	},
	"skepticism": {
		"name": "Недоверие / скепсис",
		"category": CATEGORY_SOCIAL,
		"desc": "Персонаж не согласен, сомневается в словах другого.",
		"priority": 2
	},
	"disgust": {
		"name": "Отвращение",
		"category": CATEGORY_SOCIAL,
		"desc": "Испорченная еда, неприятный чужак, грязь, трупы.",
		"priority": 3
	},
	"embarrassment": {
		"name": "Смущение",
		"category": CATEGORY_EMOTIONS,
		"desc": "Неловкая ситуация, стыд, застенчивость.",
		"priority": 2
	},
	"calm": {
		"name": "Спокойствие / умиротворение",
		"category": CATEGORY_EMOTIONS,
		"desc": "NPC расслаблен, доволен жизнью и отдыхом.",
		"priority": 1
	},
	"sleepy": {
		"name": "Сонливость",
		"category": CATEGORY_NEEDS,
		"desc": "Персонаж хочет спать или должен идти домой на ночлег.",
		"priority": 3
	},
	"fatigue": {
		"name": "Усталость",
		"category": CATEGORY_NEEDS,
		"desc": "Мало энергии, переработка, изнурение.",
		"priority": 3
	},
	"hunger": {
		"name": "Голод",
		"category": CATEGORY_NEEDS,
		"desc": "NPC хочет есть, нехватка пищи.",
		"priority": 4
	},
	"thirst": {
		"name": "Жажда",
		"category": CATEGORY_NEEDS,
		"desc": "NPC хочет пить, нехватка воды.",
		"priority": 4
	},
	"illness": {
		"name": "Болезнь",
		"category": CATEGORY_HEALTH,
		"desc": "Персонаж болен, инфекция, слабость.",
		"priority": 4
	},
	"dizziness": {
		"name": "Головокружение / оглушение",
		"category": CATEGORY_HEALTH,
		"desc": "Травма головы, потеря ориентации, контузия.",
		"priority": 3
	},
	"pain": {
		"name": "Боль",
		"category": CATEGORY_HEALTH,
		"desc": "Физическая боль, тяжёлый недуг.",
		"priority": 4
	},
	"injury": {
		"name": "Ранение",
		"category": CATEGORY_HEALTH,
		"desc": "NPC получил повреждение, требуется перевязка и отдых.",
		"priority": 4
	},
	"cold": {
		"name": "Холод",
		"category": CATEGORY_NEEDS,
		"desc": "NPC мёрзнет, зимняя стужа, нехватка одежды или костра.",
		"priority": 3
	},
	"heat": {
		"name": "Жара",
		"category": CATEGORY_NEEDS,
		"desc": "Перегрев, знойная погода, тяжёлый труд на солнцепёке.",
		"priority": 3
	},
	"wealth": {
		"name": "Деньги / богатство",
		"category": CATEGORY_EVENTS,
		"desc": "Прибыль, оплата, торговля, накопления.",
		"priority": 2
	},
	"justice": {
		"name": "Справедливость / закон",
		"category": CATEGORY_EVENTS,
		"desc": "Спор, суд старейшин, закон, раздел добычи.",
		"priority": 3
	},
	"work": {
		"name": "Работа",
		"category": CATEGORY_EVENTS,
		"desc": "NPC усердно трудится или спешит на рабочее место.",
		"priority": 1
	},
	"danger": {
		"name": "Опасность",
		"category": CATEGORY_EVENTS,
		"desc": "Угроза, дикие хищники, пожар, вражеский набег.",
		"priority": 5
	},
	"observation": {
		"name": "Наблюдение",
		"category": CATEGORY_EVENTS,
		"desc": "NPC что-то заметил, выслеживает добычу или следит за горизонтом.",
		"priority": 2
	},
	"prayer": {
		"name": "Молитва / вера",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Обращение к духам предков, священный обряд у идола.",
		"priority": 2
	},
	"celebration": {
		"name": "Праздник",
		"category": CATEGORY_LEISURE,
		"desc": "Племенной праздник, победа, рождение ребёнка, свадьба.",
		"priority": 3
	},
	"music": {
		"name": "Музыка / развлечение",
		"category": CATEGORY_LEISURE,
		"desc": "Песни, ритуальные барабаны, танцы у вечернего огня.",
		"priority": 3
	},
	"ruler": {
		"name": "Власть / правитель",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Лояльность вождю, исполнение царского указа, порядок.",
		"priority": 3
	},
	"rebellion": {
		"name": "Отказ / запрет / бунт",
		"category": CATEGORY_WORLDVIEW,
		"desc": "NPC против решения вождя, открыто протестует или ропщет.",
		"priority": 4
	},

	# =========================================================================
	# ЛИСТ 2 (48 социальных состояний, жизненных событий, экономики и общества)
	# =========================================================================
	# 1-й ряд — Отношения, привязанность, власть
	"contact": {
		"name": "Новый контакт / знакомство",
		"category": CATEGORY_SOCIAL,
		"desc": "Два NPC заинтересовались друг другом, начало дружбы или разговора.",
		"priority": 2
	},
	"self_respect": {
		"name": "Самоуважение",
		"category": CATEGORY_REPUTATION,
		"desc": "NPC уверен в себе, доволен своей жизнью и свершёнными делами.",
		"priority": 2
	},
	"agreement": {
		"name": "Договор / примирение",
		"category": CATEGORY_SOCIAL,
		"desc": "Рукопожатие: соглашение, завершение спора, выгодная сделка.",
		"priority": 3
	},
	"loyalty_ruler": {
		"name": "Верность правителю",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Сердце с короной: высокая личная преданность вождю и закону.",
		"priority": 3
	},
	"disapproval": {
		"name": "Неприязнь / осуждение",
		"category": CATEGORY_SOCIAL,
		"desc": "Резкое неодобрение поступка другого жителя, нового налога или указа.",
		"priority": 3
	},
	"jealousy": {
		"name": "Ревность",
		"category": CATEGORY_SOCIAL,
		"desc": "Ревность к романтическому партнёру или супругу.",
		"priority": 3
	},
	"envy": {
		"name": "Зависть",
		"category": CATEGORY_SOCIAL,
		"desc": "Зависть к чужому богатству, роскошному дому или высокому положению.",
		"priority": 2
	},
	"heartbreak": {
		"name": "Разбитое сердце",
		"category": CATEGORY_SOCIAL,
		"desc": "Разрыв отношений, измена, предательство, тяжелый семейный конфликт.",
		"priority": 4
	},

	# 2-й ряд — Репутация и психология
	"respect": {
		"name": "Уважение / восхищение",
		"category": CATEGORY_REPUTATION,
		"desc": "NPC высоко ценит мастера, старейшину, героя или правителя.",
		"priority": 3
	},
	"lost_respect": {
		"name": "Потеря уважения",
		"category": CATEGORY_REPUTATION,
		"desc": "Падение репутации, разочарование в лидере или соплеменнике.",
		"priority": 3
	},
	"pride": {
		"name": "Гордость",
		"category": CATEGORY_REPUTATION,
		"desc": "Гордость своим мастерством, родом, победой или процветанием поселения.",
		"priority": 2
	},
	"shame": {
		"name": "Стыд",
		"category": CATEGORY_REPUTATION,
		"desc": "Постыдный поступок, осуждение общиной, унижение.",
		"priority": 3
	},
	"loneliness": {
		"name": "Одиночество",
		"category": CATEGORY_REPUTATION,
		"desc": "Отсутствие семьи и друзей, социальная изоляция.",
		"priority": 2
	},
	"quarrel": {
		"name": "Ссора",
		"category": CATEGORY_SOCIAL,
		"desc": "Открытый спор, бытовой конфликт соседей или сожителей.",
		"priority": 3
	},
	"gossip": {
		"name": "Сплетни / слухи",
		"category": CATEGORY_SOCIAL,
		"desc": "Обсуждение новостей, указа вождя, тайных связей или чужих неудач.",
		"priority": 2
	},
	"despair": {
		"name": "Отчаяние",
		"category": CATEGORY_REPUTATION,
		"desc": "Глубокое отчаяние после гибели близких, голода или потери крова.",
		"priority": 5
	},

	# 3-й ряд — Семья и жизненный цикл
	"pregnancy": {
		"name": "Беременность",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Женщина ждёт ребёнка, подготовка к прибавлению в роду.",
		"priority": 3
	},
	"newborn": {
		"name": "Новорождённый",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Рождение дитя, родительская забота и кормление.",
		"priority": 4
	},
	"happy_child": {
		"name": "Счастливое детство",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Ребёнок накормлен, окружён семьёй и растёт в безопасности.",
		"priority": 2
	},
	"orphan": {
		"name": "Сирота",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Ребёнок остался без родителей, требуется назначение опекуна.",
		"priority": 4
	},
	"old_age": {
		"name": "Старость",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Почтенный возраст, нехватка сил для тяжелого труда, почёт.",
		"priority": 2
	},
	"mourning": {
		"name": "Траур",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Скорбь по умершему родственнику или соратнику.",
		"priority": 4
	},
	"marriage": {
		"name": "Брак / свадьба",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Заключение семейного союза, общие кольца, новоселье.",
		"priority": 4
	},
	"family": {
		"name": "Семья",
		"category": CATEGORY_LIFECYCLE,
		"desc": "Крепкий семейный очаг: родители и дети вместе.",
		"priority": 3
	},

	# 4-й ряд — Жильё, преступность и свобода
	"house": {
		"name": "Дом / жильё",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Уютный дом, возвращение на ночлег в родную хижину.",
		"priority": 1
	},
	"house_ruin": {
		"name": "Потеря жилья / руины",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Хижина разрушена, снесена или обветшала; житель остался без крова.",
		"priority": 4
	},
	"house_fire": {
		"name": "Пожар дома",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Очаг возгорания: хижина горит, требуется срочное тушение!",
		"priority": 5
	},
	"tax": {
		"name": "Налог / платёж",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Обязательный сбор дани, подати или штрафа в казну поселения.",
		"priority": 3
	},
	"thief": {
		"name": "Кража / преступник",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Хищение припасов со склада или из чужой хижины, розыск вора.",
		"priority": 4
	},
	"prison": {
		"name": "Тюрьма / заключение",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Нарушитель под стражей, арест в ожидании суда старейшин.",
		"priority": 4
	},
	"slavery": {
		"name": "Рабство / неволя",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Подневольный труд, пленник или долговая зависимость.",
		"priority": 4
	},
	"freedom": {
		"name": "Освобождение",
		"category": CATEGORY_HOUSING_LAW,
		"desc": "Разорванные цепи: снятие кабалы, помилование, вольная грамота.",
		"priority": 4
	},

	# 5-й ряд — Экономика и труд
	"poverty": {
		"name": "Бедность",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Крайняя нужда, нехватка запасов, разорение семьи.",
		"priority": 3
	},
	"debt": {
		"name": "Долг",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Невыплаченный долг перед соседом или казной племени.",
		"priority": 3
	},
	"trade": {
		"name": "Торговля / обмен",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Прямой натуральный обмен товарами и ресурсами.",
		"priority": 2
	},
	"help_request": {
		"name": "Просьба о помощи",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Обращение к вождю или родственникам за едой, кровом или защитой.",
		"priority": 4
	},
	"order": {
		"name": "Приказ / указание",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Прямое распоряжение вождя или бригадира на выполнение задачи.",
		"priority": 3
	},
	"no_tools": {
		"name": "Нет инструментов",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Работа заблокирована: сломался топор, кирка или кончились молоты.",
		"priority": 4
	},
	"strike": {
		"name": "Отказ работать / забастовка",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Бунт рабочих: отказ рубить лес или копать руду из-за голода/обиды.",
		"priority": 4
	},
	"abundance": {
		"name": "Изобилие ресурсов",
		"category": CATEGORY_ECONOMY_LABOR,
		"desc": "Богатый улов, полные закрома, рекордная добыча древесины и зерна.",
		"priority": 3
	},

	# 6-й ряд — Внешние события, общество и смерть
	"nature_wealth": {
		"name": "Благополучие природы",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Цветущий лес, возрождение дичи, чистая вода и довольство краем.",
		"priority": 2
	},
	"wild_beast": {
		"name": "Опасный зверь",
		"category": CATEGORY_EVENTS,
		"desc": "Хищный волк или медведь подошел слишком близко к хижинам!",
		"priority": 5
	},
	"stranger": {
		"name": "Незнакомец / чужак",
		"category": CATEGORY_SOCIAL,
		"desc": "Появление чужеземца, бродяги или беженца у границы поселения.",
		"priority": 3
	},
	"neighbor_contact": {
		"name": "Контакт с соседями",
		"category": CATEGORY_SOCIAL,
		"desc": "Прибытие послов, каравана или гостей из соседнего племени.",
		"priority": 3
	},
	"burial_conflict": {
		"name": "Конфликт вокруг погребения",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Религиозный спор вокруг священной могилы, идолов или обычаев погребения.",
		"priority": 4
	},
	"uprising": {
		"name": "Восстание / бунт",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Поднятый кулак: открытое народное восстание против тирании вождя.",
		"priority": 5
	},
	"feast": {
		"name": "Пир / изобилие еды",
		"category": CATEGORY_LEISURE,
		"desc": "Большая праздничная трапеза, жареное мясо, угощение всего племени.",
		"priority": 4
	},
	"funeral": {
		"name": "Похороны / память",
		"category": CATEGORY_WORLDVIEW,
		"desc": "Торжественное предание земле, цветы на кургане, дань памяти предкам.",
		"priority": 3
	}
}

static var _texture_cache: Dictionary = {}

static func get_emote_texture(emote_id: String) -> Texture2D:
	if _texture_cache.has(emote_id):
		return _texture_cache[emote_id]
		
	var path = "res://Assets/emotes/%s.png" % emote_id
	if not ResourceLoader.exists(path):
		path = "res://assets/emotes/%s.png" % emote_id
		
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			_texture_cache[emote_id] = tex
			return tex
			
	return null

static func get_emote_info(emote_id: String) -> Dictionary:
	return EMOTES_DATA.get(emote_id, {})

static func get_emotes_by_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for e_id in EMOTES_DATA:
		if EMOTES_DATA[e_id].get("category", "") == category:
			result.append(e_id)
	return result

static func get_all_emotes() -> Array[String]:
	var result: Array[String] = []
	for e_id in EMOTES_DATA:
		result.append(e_id)
	return result
