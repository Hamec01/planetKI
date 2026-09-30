import os
import sys

events_code = '''
	# --------------------------------------------------------------------------
	# ОХОТНИЧИЙ ЛАГЕРЬ (HUNTING CAMP) — 18 СЮЖЕТНЫХ ЦЕПОЧЕК (HC-01 .. HC-18)
	# --------------------------------------------------------------------------
	"HC-01": {
		"id": "HC-01",
		"chain_id": "HC_FIRST_BOAR",
		"title": "Первый кабан",
		"category": "Охота и испытания",
		"icon": "beast",
		"priority": 85,
		"once": true,
		"description": "Молодой охотник заметил следы матёрого секача. Опытные охотники советуют повременить, но юноша горит желанием доказать свою силу.",
		"conditions": {"min_days": 2, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Запретить опасную охоту",
				"desc": "Безопасность прежде всего. Не время рисковать жизнями молодых охотников.",
				"effects_desc": "🛡 Безопасность племени. Отношение юноши к вождю слегка снижается.",
				"consequences": {"modify_harmony": 2.0}
			},
			{
				"id": "B",
				"title": "Отправить вместе с опытными охотниками",
				"desc": "Командный выход. Ветераны подстрахуют и научат бить зверя точно под лопатку.",
				"effects_desc": "🏹 Опыт охоты +2, укрепление связи с наставником. Добыча доставлена.",
				"consequences": {"young_hunter_skill_boost": 2.0, "mentor_bond": 5.0, "modify_resources": {"food": 10.0, "leather": 1.0}}
			},
			{
				"id": "C",
				"title": "Пусть решает сам и докажет храбрость",
				"desc": "Право воина встретить опасность лицом к лицу. Либо триумф, либо шрамы.",
				"effects_desc": "🐗 Добыт крупный кабан (+14 еды, +2 шкуры), юноша заслужил всеобщее уважение.",
				"consequences": {"bravery_test": true, "modify_resources": {"food": 14.0, "leather": 2.0}}
			}
		]
	},

	"HC-02": {
		"id": "HC-02",
		"chain_id": "HC_WOUNDED_DEER",
		"title": "Раненый олень",
		"category": "Охотничий промысел",
		"icon": "bow",
		"priority": 84,
		"once": true,
		"description": "Стрела лишь ранила оленя, и зверь ушёл в чащу. Солнце клонится к закату, в лесу сгущаются сумерки.",
		"conditions": {"min_days": 4, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Продолжать преследование в сумерках",
				"desc": "Идти по кровавому следу до конца, даже если придётся ночевать в тайге.",
				"effects_desc": "🦌 Охотники приносят оленя (+12 еды, +1 шкура), но валятся с ног от усталости.",
				"consequences": {"modify_resources": {"food": 12.0, "leather": 1.0}}
			},
			{
				"id": "B",
				"title": "Вернуться в лагерь засветло",
				"desc": "Опасность ночного леса не стоит одной туши. Вернуться к безопасному очагу.",
				"effects_desc": "🏡 Охотники невредимы у костра. Добыча утеряна.",
				"consequences": {"safety_priority": true}
			},
			{
				"id": "C",
				"title": "Отправить следопыта на рассвете",
				"desc": "Утром следопыт быстро найдёт павшего оленя по птицам и следам.",
				"effects_desc": "🐾 Следопыт находит тушу на рассвете (+10 еды).",
				"consequences": {"tracker_efficiency": true, "modify_resources": {"food": 10.0}}
			}
		]
	},

	"HC-03": {
		"id": "HC-03",
		"chain_id": "HC_SPOILED_MEAT",
		"title": "Мясо испорчено",
		"category": "Запасы и сохранение",
		"icon": "meat",
		"priority": 83,
		"once": true,
		"description": "Охотники добыли громадного лося, но амбар переполнен. На жаре мясо быстро испортится, если срочно не найти решение.",
		"conditions": {"min_days": 6, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Устроить всеобщий пир в поселении",
				"desc": "Раздать лучшее мясо всем семьям и устроить празднество у очага.",
				"effects_desc": "🍖 Все жители сыты (+10 согласия, настроение на высоте).",
				"consequences": {"modify_harmony": 10.0, "modify_resources": {"food": 5.0}}
			},
			{
				"id": "B",
				"title": "Оставить в запасах как есть",
				"desc": "Съедим сколько успеем, остальное придётся выбросить.",
				"effects_desc": "⚠️ Часть мяса портится без пользы.",
				"consequences": {"meat_waste": true}
			},
			{
				"id": "C",
				"title": "Попробовать закоптить мясо над дымной ямой",
				"desc": "Вырыть яму, развести дымный ольховый костёр и вялить мясо на жердях.",
				"effects_desc": "🔥 Открыто улучшение: Коптильная яма (hunt_smokehouse)! Снижает порчу мяса на 80%.",
				"consequences": {"unlock_upgrade_smokehouse": true, "modify_harmony": 5.0}
			}
		]
	},

	"HC-04": {
		"id": "HC-04",
		"chain_id": "HC_QUIET_FOREST",
		"title": "Лес становится тихим",
		"category": "Экология и промысел",
		"icon": "forest",
		"priority": 82,
		"once": true,
		"description": "Следопыт докладывает: из-за непрерывной охоты дичи вокруг лагеря стало заметно меньше. Стада оленей ушли на дальние хребты.",
		"conditions": {"min_days": 8, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Продолжать бить любого найденного зверя",
				"desc": "Племя должно есть сегодня. О будущем подумаем завтра.",
				"effects_desc": "🍗 +15 еды сейчас, но плотность дичи вокруг лагеря надолго падает.",
				"consequences": {"short_term_meat": true, "modify_resources": {"food": 15.0}}
			},
			{
				"id": "B",
				"title": "Перенести охоту в дальние угодья",
				"desc": "Оборудовать дальнюю стоянку с ночлегом, дав ближнему лесу восстановиться.",
				"effects_desc": "🌲 Открыто улучшение: Дальняя стоянка (hunt_outpost)! Радиус охоты +50%.",
				"consequences": {"unlock_upgrade_outpost": true}
			},
			{
				"id": "C",
				"title": "Ввести правила и квоты на добычу",
				"desc": "Запретить бить больше двух крупных зверей в день. Беречь лес.",
				"effects_desc": "🌱 Закон бережной охоты: популяция животных восстанавливается быстрее (+20%).",
				"consequences": {"sustainable_hunting": true, "game_regeneration_boost": 0.20}
			}
		]
	},

	"HC-05": {
		"id": "HC-05",
		"chain_id": "HC_DOE_WITH_FAWN",
		"title": "Самка с детёнышем",
		"category": "Законы природы",
		"icon": "deer",
		"priority": 81,
		"once": true,
		"description": "Охотник наткнулся на олениху с маленьким детёнышем. Припасов в лагере мало, и рука стрелка замерла на тетиве.",
		"conditions": {"min_days": 10, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Добыть зверя — племени нужна еда",
				"desc": "Голод не знает жалости. Стрела спущена.",
				"effects_desc": "🍗 +10 мяса сейчас, но будущее поголовье оленей сокращается.",
				"consequences": {"modify_resources": {"food": 10.0, "leather": 1.0}}
			},
			{
				"id": "B",
				"title": "Не трогать матерей с детёнышами",
				"desc": "Закон предков: самка с приплодом неприкосновенна ради продолжения рода.",
				"effects_desc": "🌿 Традиция защиты матерей. Популяция оленей восстанавливается на +15% быстрее.",
				"consequences": {"tradition_spare_mothers": true, "game_regeneration_boost": 0.15}
			},
			{
				"id": "C",
				"title": "Поймать детёныша для содержания у лагеря",
				"desc": "Попробовать выкормить оленёнка молоком и приручить к людям.",
				"effects_desc": "🦌 Первый шаг к домашнему скотоводству и загонам для животных.",
				"consequences": {"domestication_seed": true, "modify_harmony": 5.0}
			}
		]
	},

	"HC-06": {
		"id": "HC-06",
		"chain_id": "HC_HUNTER_PELT",
		"title": "Охотник присвоил шкуру",
		"category": "Собственность и добыча",
		"icon": "pelt",
		"priority": 80,
		"once": true,
		"description": "Охотник сдал мясо в общий амбар, но роскошную шкуру лося оставил себе. Соплеменники спорят: «Мы все выслеживали зверя, почему шкура его?»",
		"conditions": {"min_days": 12, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Добыча принадлежит тому, кто убил зверя",
				"desc": "Право первого удара. Поощряет личное мастерство и меткость.",
				"effects_desc": "🎯 Индивидуализм и соревновательность. Охотники стремятся к лучшим трофеям.",
				"consequences": {"private_property": 10.0, "hunter_rivalry": true}
			},
			{
				"id": "B",
				"title": "Вся добыча принадлежит охотничьей артели",
				"desc": "Охотники делят шкуры между собой по общему согласию.",
				"effects_desc": "🤝 Сплочённость охотничьего лагеря +10.",
				"consequences": {"hunter_cohesion": 10.0}
			},
			{
				"id": "C",
				"title": "Вся добыча принадлежит поселению и вождю",
				"desc": "Шкуры и мясо идут в общий склад для нужд каждого соплеменника.",
				"effects_desc": "📦 +2 кожи на общий склад, авторитет общины.",
				"consequences": {"tribal_collectivism": 10.0, "modify_resources": {"leather": 2.0}}
			},
			{
				"id": "D",
				"title": "Мясо — общее, шкура и трофей — охотнику",
				"desc": "Справедливый компромисс: община сыта, а удачливый стрелок украшен почетом.",
				"effects_desc": "✨ Мудрый обычай охоты (+8 еды, +1 кожа). Гармония в поселении.",
				"consequences": {"balanced_tradition": true, "modify_resources": {"food": 8.0, "leather": 1.0}}
			}
		]
	},

	"HC-07": {
		"id": "HC-07",
		"chain_id": "HC_WHO_KILLED_BEAST",
		"title": "Кто убил зверя?",
		"category": "Споры охотников",
		"icon": "spear",
		"priority": 79,
		"once": true,
		"description": "Два охотника одновременно поразили могучего медведя. Теперь они спорят перед лагерем, чьё копьё пробило сердце.",
		"conditions": {"min_days": 14, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Разделить награду и славу поровну",
				"desc": "Оба проявили доблесть. Медвежья шкура делится на две накидки.",
				"effects_desc": "🤝 Братство охотников: оба признаны героями.",
				"consequences": {"hunter_cohesion": 8.0}
			},
			{
				"id": "B",
				"title": "Отдать трофей старшему охотнику",
				"desc": "Опыт и седины заслуживают первенства в любом споре.",
				"effects_desc": "🧓 Укрепление авторитета старейшин лагеря.",
				"consequences": {"elder_respect": true}
			},
			{
				"id": "C",
				"title": "Пусть решит мастер разделки по глубине раны",
				"desc": "Раздельщик осмотрит тушу и вынесет честный и неоспоримый приговор.",
				"effects_desc": "🔪 Справедливый суд. Открывает улучшение: Стол мастера разделки (hunt_master_butcher).",
				"consequences": {"butcher_adjudication": true, "unlock_upgrade_master_butcher": true}
			}
		]
	},

	"HC-08": {
		"id": "HC-08",
		"chain_id": "HC_WOLF_PUP",
		"title": "Охотник и волчонок",
		"category": "Приручение и звери",
		"icon": "wolf",
		"priority": 86,
		"once": true,
		"description": "После победы над стаей волков охотники нашли в логове одинокого скулящего волчонка. Одни тянутся за ножом, другие с жалостью смотрят на щенка.",
		"conditions": {"min_days": 16, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Забрать волчонка в поселение и вырастить",
				"desc": "Кормить волчонка мясом с рук и приучить к запаху людей и костра.",
				"effects_desc": "🐕 Открыто улучшение: Охотничьи собаки (hunt_dogs)! Псы охраняют лагерь и загоняют дичь.",
				"consequences": {"unlock_upgrade_dogs": true, "dog_taming": true, "modify_harmony": 8.0}
			},
			{
				"id": "B",
				"title": "Оставить волчонка на волю духов леса",
				"desc": "Не нам вмешиваться в закон дикой тайги. Пусть боги решат его участь.",
				"effects_desc": "🌲 Уважение к естественному порядку природы.",
				"consequences": {"nature_respect": true}
			},
			{
				"id": "C",
				"title": "Убить хищника, чтобы не плодить врагов",
				"desc": "Волк всегда останется волком. Нельзя рисковать детьми племени.",
				"effects_desc": "🛡 Безопасность троп (+1 мех хищника).",
				"consequences": {"modify_resources": {"leather": 1.0}}
			}
		]
	},

	"HC-09": {
		"id": "HC-09",
		"chain_id": "HC_BEAR_AT_CAMP",
		"title": "Медведь у лагеря",
		"category": "Опасные хищники",
		"icon": "bear",
		"priority": 78,
		"once": true,
		"description": "Огромный медведь-шатун подошёл к границам охотничьих стоянок. Женщины и дети боятся выходить на сбор трав.",
		"conditions": {"min_days": 18, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Собрать дружину охотников и сразить зверя",
				"desc": "Окружить хищника с копьями и луками и дать бой хозяину тайги.",
				"effects_desc": "⚔️ Славная победа: +26 еды, +3 кожи, +4 кости! Боевой дух лагеря взмывает.",
				"consequences": {"modify_resources": {"food": 26.0, "leather": 3.0, "bone": 4.0}, "hunter_morale": 10.0}
			},
			{
				"id": "B",
				"title": "Отогнать факелами и криками в дальние горы",
				"desc": "Шуметь сухими ветками и кидать горящие головни, не проливая крови.",
				"effects_desc": "🔥 Медведь напуган огнём и уходит без жертв.",
				"consequences": {"safe_scare": true}
			},
			{
				"id": "C",
				"title": "Объявить медведя священным тотемом племени",
				"desc": "Принести в дар часть рыбы и ягод, признав в звере дух-хранитель окрестных гор.",
				"effects_desc": "🐾 Культ Медведя: религиозное рвение +15, защита духа тайги.",
				"consequences": {"bear_totem": true, "spiritual_zeal": 15.0}
			}
		]
	},

	"HC-10": {
		"id": "HC-10",
		"chain_id": "HC_LOST_HUNTER",
		"title": "Охотник не вернулся",
		"category": "Поиски и спасение",
		"icon": "night",
		"priority": 77,
		"once": true,
		"description": "Ночь опустилась на лес, а один из лучших стрелков так и не вышел к костру. Из ущелья доносится волчий вой.",
		"conditions": {"min_days": 20, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Снарядить поисковый отряд с факелами",
				"desc": "Собрать людей и немедленно прочесать тропу до самого ущелья.",
				"effects_desc": "🔦 Охотника находят раненым, но живым. Преданность племени вождю +5.",
				"consequences": {"save_hunter": true, "modify_loyalty_all": 5.0}
			},
			{
				"id": "B",
				"title": "Отправить следопыта на рассвете",
				"desc": "Ночью в лесу легко сгинуть самим. Дождаться первых лучей солнца.",
				"effects_desc": "🌅 Следопыт находит потерявшегося охотника в расщелине.",
				"consequences": {"tracker_rescue": true}
			},
			{
				"id": "C",
				"title": "Ждать в лагере — опытный стрелок сам выберется",
				"desc": "Он знает тайгу лучше любого из нас. Лишний шум только привлечёт волков.",
				"effects_desc": "⏳ Охотник возвращается к полудню с раной ноги.",
				"consequences": {"hunter_loss_risk": true}
			}
		]
	},

	"HC-11": {
		"id": "HC-11",
		"chain_id": "HC_HUNTER_INJURY",
		"title": "Тяжёлая травма охотника",
		"category": "Судьба ветеранов",
		"icon": "wound",
		"priority": 76,
		"once": true,
		"description": "Опытный охотник получил тяжёлую травму в схватке со зверем. Он выжил, но хромает и больше не может бегать за оленями весь день.",
		"conditions": {"min_days": 22, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Сделать его Наставником молодых охотников",
				"desc": "Его опыт и знание повадок зверя бесценны. Пусть учит молодёжь ремеслу.",
				"effects_desc": "🧓 Открыто улучшение: Место наставника (hunt_mentor)! Опыт передаётся молодым охотникам.",
				"consequences": {"unlock_upgrade_mentor": true, "mentor_assigned": true}
			},
			{
				"id": "B",
				"title": "Перевести его на разделку и выделку шкур",
				"desc": "Его крепкие руки пригодятся на разделке туш и выделке пушнины.",
				"effects_desc": "🔪 Помощник мастера разделки ускоряет заготовку провианта.",
				"consequences": {"butcher_helper": true}
			},
			{
				"id": "C",
				"title": "Отправить на покой к старейшинам рода",
				"desc": "Он отдал силы племени, теперь племя обеспечит ему спокойную старость.",
				"effects_desc": "👴 Традиции уважения к ветеранам укрепляют согласие в роду.",
				"consequences": {"elder_respect": true}
			}
		]
	},

	"HC-12": {
		"id": "HC-12",
		"chain_id": "HC_YOUTH_WANT_HUNT",
		"title": "Молодые хотят охотиться",
		"category": "Обучение поколений",
		"icon": "apprentice",
		"priority": 75,
		"once": true,
		"description": "Подростки 14-16 лет смастерили луки из орешника и просят охотников взять их на промысел за дичью.",
		"conditions": {"min_days": 24, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Разрешить раннее ученичество в лагере",
				"desc": "Кто раньше взял в руки лук, тот вырастет непобедимым следопытом.",
				"effects_desc": "🏹 Подростки быстрее осваивают лук и копьё. Смена растёт крепкой.",
				"consequences": {"youth_hunt_training": true}
			},
			{
				"id": "B",
				"title": "Только после совершеннолетия (16 лет)",
				"desc": "Охота — смертельно опасный труд. Нельзя подвергать опасности детей.",
				"effects_desc": "🛡 Безопасность подрастающего поколения превыше всего.",
				"consequences": {"cautious_youth": true}
			},
			{
				"id": "C",
				"title": "Пусть тренируются на лагерных мишенях",
				"desc": "Поставить мишени из соломы и шкур возле лагеря, пока не набьют меткий глаз.",
				"effects_desc": "🎯 Открыто улучшение: Тренировочная мишень (hunt_target)! Охотники тренируются в лагере.",
				"consequences": {"unlock_upgrade_target": true}
			}
		]
	},

	"HC-13": {
		"id": "HC-13",
		"chain_id": "HC_STUBBORN_MENTOR",
		"title": "Хороший охотник не хочет учить",
		"category": "Охотничье ремесло",
		"icon": "teaching",
		"priority": 74,
		"once": true,
		"description": "Лучший стрелок лагеря ворчит: «Пока я вожусь с сопляками и правлю им пальцы, капканы пустуют, а моя семья недополучает мяса».",
		"conditions": {"min_days": 26, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Выделять наставнику особую долю добычи",
				"desc": "Наставничество — тоже благо для племени, и оно должно вознаграждаться.",
				"effects_desc": "🍖 Охотник охотно обучает учеников. Навыки молодёжи растут быстрее (+3 XP).",
				"consequences": {"paid_mentor": true, "skill_boost_youth": 3.0}
			},
			{
				"id": "B",
				"title": "Обязать обучать ради долга перед племенем",
				"desc": "Каждый охотник обязан вырастить себе замену по воле вождя.",
				"effects_desc": "📜 Повинность обучения введена в обычай общины.",
				"consequences": {"mandatory_teaching": true}
			},
			{
				"id": "C",
				"title": "Освободить его — пусть только добывает мясо",
				"desc": "Не отвлекать великого стрелка. Пусть его стрелы кормят всё племя.",
				"effects_desc": "🍗 +10 еды в запасы от сольной охоты мастера.",
				"consequences": {"solo_master": true, "modify_resources": {"food": 10.0}}
			}
		]
	},

	"HC-14": {
		"id": "HC-14",
		"chain_id": "HC_HUNTER_FACTION",
		"title": "Охотники становятся отдельной группой",
		"category": "Социальные узы",
		"icon": "brotherhood",
		"priority": 73,
		"once": true,
		"description": "Охотники проводят недели вместе в тайге. У них появились свои тайные знаки, обряды у костра и признанный атаман.",
		"conditions": {"min_days": 28, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Признать Охотничье Братство и их обычаи",
				"desc": "Уважать их узы крови и тайги. Братство охотников непобедимо в засадах.",
				"effects_desc": "🦅 Боевой дух и слаженность охотников +20%, урон в бою +15%.",
				"consequences": {"hunter_brotherhood": true, "hunt_damage_boost": 0.15}
			},
			{
				"id": "B",
				"title": "Напомнить, что они — часть единого племени",
				"desc": "Не допускать обособления. Все соплеменники подчиняются единой воле вождя.",
				"effects_desc": "👑 Единство племени и верность вождю +5.",
				"consequences": {"tribal_loyalty": 5.0}
			},
			{
				"id": "C",
				"title": "Назначить главного охотника сотником дружины",
				"desc": "Привлечь авторитетного вожака охотников к руководству обороной селения.",
				"effects_desc": "🛡 Охотники становятся костяком разведки и гарнизона.",
				"consequences": {"hunter_guard_link": true}
			}
		]
	},

	"HC-15": {
		"id": "HC-15",
		"chain_id": "HC_BEST_CUT",
		"title": "Лучший кусок",
		"category": "Распределение благ",
		"icon": "feast",
		"priority": 72,
		"once": true,
		"description": "После добычи громадного лося возник жаркий спор у очага: кому полагается нежная печень и отборная вырезка?",
		"conditions": {"min_days": 30, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Детям, матерям и немощным старикам",
				"desc": "Слабые нуждаются в нежном мясе больше всех. Забота общины превыше гордости.",
				"effects_desc": "👶 Забота о семье и стариках +10, согласие в роду +8.",
				"consequences": {"care_weak": 10.0, "modify_harmony": 8.0}
			},
			{
				"id": "B",
				"title": "Самим охотникам, добывшим зверя",
				"desc": "Кто рисковал жизнью под копытами лося, тот и вкушает лучший кусок.",
				"effects_desc": "🏹 Охотники горды справедливостью, рвение на охоте возрастает (+15%).",
				"consequences": {"hunter_motivation": 15.0}
			},
			{
				"id": "C",
				"title": "Вождю и совету старейшин",
				"desc": "Дань уважения правителю и мудрецам племени.",
				"effects_desc": "👑 Престиж власти вождя возрастает (+10).",
				"consequences": {"ruler_prestige": 10.0}
			},
			{
				"id": "D",
				"title": "Всем поровну в общий котёл",
				"desc": "Все соплеменники равны у огня. Мясо варится в едином котле.",
				"effects_desc": "🥣 Абсолютное братство и равенство племени (+10 согласия).",
				"consequences": {"absolute_equality": true, "modify_harmony": 10.0}
			}
		]
	},

	"HC-16": {
		"id": "HC-16",
		"chain_id": "HC_SACRED_BLOOD",
		"title": "Кровь на священном месте",
		"category": "Святыни и табу",
		"icon": "shrine",
		"priority": 71,
		"once": true,
		"description": "Охотник разделал кабана прямо возле священного камня предков. Жрец и набожные жители возмущены осквернением святыни.",
		"conditions": {"min_days": 32, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Охотник прав: добыча важнее суеверий",
				"desc": "Еда кормит тела, а духи подождут. Охотники довольны поддержкой вождя.",
				"effects_desc": "🥩 Прагматизм: охотники довольны, ропот верующих.",
				"consequences": {"pragmatism": true, "hunter_morale": 5.0}
			},
			{
				"id": "B",
				"title": "Запретить разделку возле святых мест",
				"desc": "Священная земля неприкосновенна. Ввести строгое табу на кровь у алтарей.",
				"effects_desc": "🕯 Уважение к вере предков, религиозное рвение +8.",
				"consequences": {"shrine_sanctity": true, "spiritual_zeal": 8.0}
			},
			{
				"id": "C",
				"title": "Освящать каждую добычу перед разделкой",
				"desc": "Приносить часть крови в дар духам леса. Превратить разделку в священный ритуал.",
				"effects_desc": "🐺 Ритуал благодарения духов природы (+6 согласия).",
				"consequences": {"hunter_blessing_ritual": true, "modify_harmony": 6.0}
			}
		]
	},

	"HC-17": {
		"id": "HC-17",
		"chain_id": "HC_TROPHY_HUNTING",
		"title": "Охота ради славы",
		"category": "Законы охоты",
		"icon": "trophy",
		"priority": 70,
		"once": true,
		"description": "Один стрелок убивает редких оленей только ради ветвистых рогов, бросая мясо воронам в овраге.",
		"conditions": {"min_days": 34, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Запретить бессмысленное убийство зверя",
				"desc": "Закон тайги: убил — съешь. Бесполезное убийство навлекает гнев духов.",
				"effects_desc": "🌱 Закон сохранения природы: табу на пустую трату добычи.",
				"consequences": {"sustainable_nature": true, "waste_taboo": true}
			},
			{
				"id": "B",
				"title": "Разрешить забирать рога для мастерской трофеев",
				"desc": "Рога и кости нужны резчикам для оберегов, оружия и украшений.",
				"effects_desc": "🦴 Открыто улучшение: Мастерская трофеев (hunt_trophies)! +4 кости на склад.",
				"consequences": {"unlock_upgrade_trophies": true, "modify_resources": {"bone": 4.0}}
			},
			{
				"id": "C",
				"title": "Это его личная добыча — не вмешиваться",
				"desc": "Каждый охотник волен поступать со своей добычей как сочтёт нужным.",
				"effects_desc": "🏹 Личная свобода воина, но старейшины качают головами.",
				"consequences": {"individualism": 5.0}
			}
		]
	},

	"HC-18": {
		"id": "HC-18",
		"chain_id": "HC_MEMORIAL_BONES",
		"title": "Кости погибших",
		"category": "Память и честь",
		"icon": "memorial",
		"priority": 69,
		"once": true,
		"description": "В схватке со стаей волков пал отважный следопыт. Товарищи просят укрепить в лагере его копьё и волчий череп как вечный мемориал.",
		"conditions": {"min_days": 36, "required_building": "hunting_camp"},
		"choices": [
			{
				"id": "A",
				"title": "Создать в лагере Мемориал павших охотников",
				"desc": "Установить резные столбы памяти. Лагерь становится местом великих преданий.",
				"effects_desc": "💀 Мемориал охотников: боевой дух лагеря +20, память предков вдохновляет молодёжь.",
				"consequences": {"hunter_memorial": true, "hunter_morale": 15.0, "unlock_upgrade_trophies": true}
			},
			{
				"id": "B",
				"title": "Похоронить с почестями на родовом кладбище",
				"desc": "Все сыны племени должны покоиться в единой священной земле предков.",
				"effects_desc": "🪦 Укрепление культа предков и родового кладбища (+6 согласия).",
				"consequences": {"ancestor_burial": true, "modify_harmony": 6.0}
			},
			{
				"id": "C",
				"title": "Сложить погребальный костёр в тайге",
				"desc": "Огонь очистит дух воина, и дым унесёт его душу к духам вечной охоты.",
				"effects_desc": "🔥 Обряд священного костра: покой душе охотника.",
				"consequences": {"pyre_spirit": true, "modify_harmony": 4.0}
			}
		]
	}
'''

path = r'E:\Planetki\src\events\civilization_event_db.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

idx = content.rfind('}')
if idx == -1:
    print('Error: closing brace not found')
    sys.exit(1)

new_content = content[:idx] + events_code + '\n' + content[idx:]
with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Success! Added 18 hunting camp events to civilization_event_db.gd')
