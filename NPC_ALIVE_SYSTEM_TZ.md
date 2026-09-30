# PlanetKI — NPC ALIVE SYSTEM v1.0
## Техническое задание: Полное оживление жителей

> **Версия:** 1.0  
> **Дата:** 2026-09-28  
> **Статус:** УТВЕРЖДЕНО К РАЗРАБОТКЕ  
> **Файл-правила для разработчиков:** см. раздел «Правила добавления событий»

---

## СОДЕРЖАНИЕ

1. [Обзор и цели](#1-обзор-и-цели)
2. [Архитектура системы](#2-архитектура-системы)
3. [Система реакций на события](#3-система-реакций-на-события)
4. [Категории событий и реакции NPC](#4-категории-событий-и-реакции-npc)
5. [Система взаимоотношений](#5-система-взаимоотношений)
6. [Система индивидуальности и характера](#6-система-индивидуальности-и-характера)
7. [Система принятия решений NPC](#7-система-принятия-решений-npc)
8. [NPCEventReactor — новый компонент](#8-npceventreactor--новый-компонент)
9. [Новые EventBus сигналы](#9-новые-eventbus-сигналы)
10. [Поведенческие состояния](#10-поведенческие-состояния)
11. [ПРАВИЛА добавления новых событий](#11-правила-добавления-новых-событий)
12. [Интеграционная карта](#12-интеграционная-карта)
13. [Этапы реализации](#13-этапы-реализации)

---

## 1. ОБЗОР И ЦЕЛИ

### Текущее состояние

Жители (CitizenNPC) имеют:
- ГОТОВО: 13 черт личности в `traits` (diligence, bravery, empathy, sociability, temper, honesty, ambition, tradition, curiosity, unpredictable, aggression, pride, loyalty_ruler)
- ГОТОВО: Систему памяти (`memories[]`) с затуханием
- ГОТОВО: Базовые отношения (`relationships{}`) — тип + closeness + romance
- ГОТОВО: Эмоции-иконки (`show_emote`)
- ГОТОВО: Речевые пузыри (`shout`, `speech_bubble`)
- ГОТОВО: Детектор наблюдения событий (`can_observe_event`)
- ГОТОВО: Автономные эмоции от состояний (голод, усталость, FLEEING)
- ОТСУТСТВУЕТ: Реакции на цивилизационные события (civilization events)
- ОТСУТСТВУЕТ: Влияние культурной памяти (CultureMemory) на поведение NPC
- ОТСУТСТВУЕТ: Полноценная социальная сеть с историей отношений
- ОТСУТСТВУЕТ: Индивидуальные решения, диалоги и "мнения" NPC
- ОТСУТСТВУЕТ: Групповые реакции (массовые события — толпа, паника, праздник)

### Цели системы

1. Каждое игровое событие должно немедленно влиять на поведение конкретных NPC
2. Характер NPC определяет, как он реагирует на одно и то же событие
3. Отношения NPC должны быть живой сетью с историей конфликтов, дружбы, любви
4. NPC принимают самостоятельные решения на основе черт + памяти + отношений + культурных норм
5. Игрок должен чувствовать, что NPC — настоящие личности с характерами

---

## 2. АРХИТЕКТУРА СИСТЕМЫ

```
СОБЫТИЯ (TRIGGERS)
  CivilizationEventManager  |  EventManager  |  Прямые (Settlement)
              |
              | emit сигналы EventBus
              v
NPCEventReactor (НОВЫЙ)
  src/simulation/npc_event_reactor.gd
  - Подписан на все EventBus сигналы
  - Маршрутизирует событие к конкретным NPC
  - Фильтрует по расстоянию, доступности, занятости
              |
              | вызывает receive_world_event(ev)
              v
CitizenNPC.receive_world_event()
  - Фильтр по traits (personality gate)
  - Запись в memories[]
  - Изменение loyalty / morale
  - Изменение отношений relationships{}
  - Выбор эмоции + речевого пузыря
  - (опц.) Изменение поведения: State
              |
              v
NPCRelationshipGraph (РАСШИРЕНИЕ)
  src/simulation/npc_relationship_graph.gd
  - Граф всех отношений поселения
  - Отслеживает: дружба, вражда, любовь, клики
  - История событий в отношениях (max 20 на пару)
```

---

## 3. СИСТЕМА РЕАКЦИЙ НА СОБЫТИЯ

### 3.1 Принцип работы

Каждое событие в игре должно содержать поле `npc_reactions` — словарь правил реакции:

```gdscript
# Формат npc_reactions в любом событии:
"npc_reactions": {
    "scope": "all" | "nearby" | "involved" | "job:<job_id>" | "trait:<trait>:<threshold>",
    "radius": 320.0,           # пиксели, только если scope="nearby"
    "delay_range": [0.0, 3.0], # случайная задержка реакции (секунды)
    "reactions": [
        {
            "condition": "trait.bravery < 40",
            "loyalty_delta": -5.0,
            "emote": "fear",
            "emote_duration": 3.5,
            "memory": {
                "type": "civic_event",
                "importance": 0.6,
                "desc": "Был принят закон о военном призыве. Мне страшно."
            },
            "shout": ["«Это безумие!»", "«Я не воин...»"],
            "state_override": null,
            "relationship_changes": []
        },
        {
            "condition": "trait.bravery >= 70",
            "loyalty_delta": 8.0,
            "emote": "hero",
            "shout": ["«Наконец-то! Я давно ждал этого!»", "«Слава вождю!»"],
            "memory": {
                "type": "civic_pride",
                "importance": 0.7,
                "desc": "Нас призвали защищать племя. Я готов!"
            }
        }
    ]
}
```

### 3.2 Персонажный фильтр (Personality Gate)

Перед применением реакции NPCEventReactor проверяет условие:

```
trait.<name> <op> <value>
memory.<type>               -> NPC помнит событие типа <type>
relationship.<id>.<field> <op> <value>
job.<job_id>                -> NPC работает по данной профессии
cohort.<cohort>             -> возрастная группа
culture.<exclusive_group>   -> CultureMemory содержит решение по группе
season                      -> текущий сезон
random.<probability>        -> вероятность (0..1)
```

Условия можно комбинировать через AND / OR:

```
"condition": "trait.bravery < 40 AND random.0.7"
"condition": "job.hunter OR job.guard"
"condition": "memory.war_survivor AND trait.temper > 60"
```

---

## 4. КАТЕГОРИИ СОБЫТИЙ И РЕАКЦИИ NPC

### 4.1 ЗАКОНОДАТЕЛЬНЫЕ СОБЫТИЯ

| Событие | NPC с высоким tradition | NPC с высоким ambition | NPC с высоким temper |
|---------|-------------------------|------------------------|----------------------|
| Принят новый закон | +loyalty, emote=prayer | emote=thought, обдумывает выгоду | нейтрален или протест |
| Отменена традиция | emote=grief, -loyalty | нейтрален | +loyalty если традиция давила |
| Вождь ограничил власть Совета | emote=discontent, shout | emote=joy если амбициозен | emote=rebellion |

Алгоритм:
```
loyalty_delta = BASE_DELTA * trait_multiplier
  tradition > 70  -> x1.5 при консервативных законах, x0.5 при прогрессивных
  honesty > 65    -> +3 при справедливых, -5 при коррупционных
  aggression > 60 -> x1.3 при ужесточении наказаний
```

### 4.2 ВОЕННЫЕ СОБЫТИЯ (battle_started, battle_ended)

**battle_started:**
- Все NPC в радиусе 640px: emote=panic или hero (зависит от bravery)
- Охотники/стражники: автоматический shout «К оружию!»
- Дети/старики: state -> FLEEING (если bravery < 35)
- NPC с loyalty < 30: emote=desertion + memory типа war_fear

**battle_ended (победа):**
- Все NPC поселения: loyalty += 5..15
- Воины: emote=hero + shout победный клич
- NPC у которых погиб родственник: emote=grief, memory war_loss, -closeness с вождём

**battle_ended (поражение):**
- loyalty -= 10..25 для всех
- NPC с temper > 65: emote=rebellion + shout упрёк вождю
- NPC с empathy > 70: emote=grief + shout о потерях

### 4.3 ЭКОНОМИЧЕСКИЕ СОБЫТИЯ

**Голод (food < 20% от нормы):**
- Все NPC: emote=hunger, loyalty -= 2/день
- NPC с детьми: loyalty -= 5/день + memory child_starvation
- NPC с ambition > 65: shout обвинение вождя + emote=rebellion
- NPC с tradition > 70: emote=prayer + shout о жертвоприношении

**Изобилие (склад переполнен):**
- Случайные NPC: emote=joy + shout радости
- NPC-трудяги (diligence > 70): emote=pride + shout о своей работе

### 4.4 ДЕМОГРАФИЧЕСКИЕ СОБЫТИЯ (person_born, person_died)

**person_born:**
- Родители: emote=love, shout радостный
- Соседи/друзья (closeness > 60): emote=joy
- Жители с sociability > 65: shout поздравление

**person_died (причина = война):**
- Все родственники: emote=grief, loyalty -= 15, memory loss_war (permanent)
- Родственники с temper > 65: добавляют grudge против причины смерти
- Друзья (closeness > 70): emote=grief, loyalty -= 5

**person_died (причина = старость):**
- Родственники: emote=grief -> переходит в calm через 3 игровых дня
- memory типа peaceful_passing (permanent для ближайших)

### 4.5 РЕЛИГИОЗНЫЕ И КУЛЬТУРНЫЕ СОБЫТИЯ

**religion_reformed:**
- NPC с tradition > 75: emote=anger + shout возмущения + loyalty -= 8
- NPC с curiosity > 70: emote=thought + shout восхищения
- Жрецы (job=priest): emote=prayer или protest (зависит от направления)
- NPC с honesty > 70: принимают спокойно

**Принятие традиции через CultureMemory:**
- marriage_structure=POLYGYNY: NPC-мужчины с ambition > 60 ищут второго партнёра
- justice_system=BLOOD_FEUD: NPC с grudge могут атаковать обидчика (через temper)
- burial_practice=CREMATION: NPC-похоронщики меняют поведение
- military_duty=UNIVERSAL_ALL: NPC-женщины с bravery > 50 принимают военную профессию

### 4.6 СЕЗОННЫЕ СОБЫТИЯ (season_changed)

| Сезон | Реакция NPC |
|-------|-------------|
| Весна | emote=joy для всех (шанс 20%), shout о новом сезоне |
| Лето | emote=work для трудяг (diligence > 60), дети играют чаще |
| Осень | NPC с tradition > 60: emote=prayer (благодарность) |
| Зима | NPC без дома: emote=cold + shout жалоба; NPC с семьёй: emote=calm |

### 4.7 СОБЫТИЯ СТРОИТЕЛЬСТВА

**Построено новое здание:**
- NPC без дома при постройке хижины: emote=joy + shout
- Рабочие-строители: emote=pride + shout о достижении
- NPC у которых есть memory dream_fulfilled: happy_reaction

**Разрушено здание:**
- NPC, чей дом: emote=grief, memory home_lost + loyalty -= 20
- NPC с tradition > 70: emote=anger + shout

---

## 5. СИСТЕМА ВЗАИМООТНОШЕНИЙ

### 5.1 Расширенная модель отношений

Текущая структура `relationships{}` расширяется:

```gdscript
# relationships[other_id] = {
#   "type": "spouse" | "parent" | "child" | "sibling" |
#           "friend" | "rival" | "enemy" | "colleague" | "guardian" | "ward",
#   "closeness": float,       # 0..100 (близость)
#   "romance": float,         # 0..100 (романтика)
#   "trust": float,           # 0..100 (доверие) — НОВОЕ
#   "respect": float,         # 0..100 (уважение) — НОВОЕ
#   "resentment": float,      # 0..100 (обида) — НОВОЕ
#   "shared_history": Array,  # последние 10 совместных событий — НОВОЕ
#   "last_interaction_day": int,
#   "married": bool
# }
```

### 5.2 Событие-триггеры изменения отношений

| Действие | trust | closeness | resentment |
|----------|-------|-----------|------------|
| Совместная работа (>1 часа) | +2 | +3 | — |
| Один получил еду, другой голодал | +5 | +4 | — |
| NPC нанёс другому урон | -20 | -15 | +30 |
| NPC помог умирающему | +15 | +20 | — |
| Предательство (feud) | -40 | -30 | +50 |
| Свадьба | +20 | +30 | — |
| Смерть общего родственника | +10 | +15 | — |
| Долгое отсутствие (>30 дней) | -1/5дней | -1/5дней | — |

### 5.3 Расчёт совместимости двух NPC

```gdscript
func calculate_compatibility(a: CitizenNPC, b: CitizenNPC) -> float:
    var score = 50.0
    # Схожие черты притягивают (в пределах 20 пунктов)
    for trait in ["diligence", "tradition", "sociability", "honesty"]:
        var diff = abs(a.traits[trait] - b.traits[trait])
        score += (20.0 - diff) * 0.5 if diff < 20 else -diff * 0.1
    # Высокая empathy у обоих — бонус
    if a.traits["empathy"] > 65 and b.traits["empathy"] > 65:
        score += 15.0
    # Высокий temper у обоих — конфликт
    if a.traits["temper"] > 65 and b.traits["temper"] > 65:
        score -= 20.0
    return clampf(score, 0.0, 100.0)
```

### 5.4 Кланы и группировки (NPC Cliques)

Новый класс `NPCClique` в `NPCRelationshipGraph`:

```gdscript
class NPCClique:
    var id: String
    var member_ids: Array[String]
    var clique_type: String  # "family", "work_gang", "drinking_buddies", "council", "dissidents"
    var internal_trust: float
    var morale: float
    var shared_opinion: String  # "pro_ruler", "anti_ruler", "neutral", "fanatic"
```

Клики формируются автоматически:
- Семейная клика: супруги + дети -> type=family
- Рабочая клика: 3+ NPC одной профессии с closeness > 55 -> type=work_gang
- Диссиденты: NPC с loyalty < 35 и resentment > 60 -> type=dissidents
- Совет старейшин: NPC job=elder с respect > 70 -> type=council

Если клика типа dissidents достигает 5+ членов -> EventBus.npc_revolt_risk

---

## 6. СИСТЕМА ИНДИВИДУАЛЬНОСТИ И ХАРАКТЕРА

### 6.1 Архетипы личности

Каждый NPC получает один доминирующий архетип на основе traits:

| Архетип | Условие | Поведение |
|---------|---------|-----------|
| Вожак (leader) | ambition > 70, bravery > 65, sociability > 55 | Стремится стать лидером клики, оспаривает решения при loyalty < 60 |
| Труженик (worker) | diligence > 75, honesty > 60, ambition < 45 | Работает без устали, лоялен если работа есть |
| Мятежник (rebel) | temper > 70, loyalty_ruler < 50, ambition > 55 | Часто ворчит, генерирует shout-протест, создаёт dissidents-клику |
| Хранитель (keeper) | tradition > 75, honesty > 60, empathy > 55 | Защищает обычаи, возмущается при смене традиций |
| Дипломат (diplomat) | sociability > 70, empathy > 65, temper < 40 | Мирит конфликты, при конфликтах выступает посредником |
| Одиночка (loner) | sociability < 30, curiosity > 60 | Мало говорит, много работает, редкие но яркие реакции |
| Боец (fighter) | bravery > 75, temper > 55, aggression > 60 | Первым реагирует на угрозы, ищет конфликт с grudge-NPC |
| Провидец (visionary) | curiosity > 75, honesty > 65, tradition < 45 | Первым принимает изменения, задаёт вопросы |
| Заботливый (caretaker) | empathy > 75, sociability > 60, diligence > 50 | Ухаживает за больными, первым реагирует на рождения/смерти |

```gdscript
func get_personality_archetype() -> String:
    var t = traits
    if t["ambition"] > 70 and t["bravery"] > 65 and t["sociability"] > 55:
        return "leader"
    if t["diligence"] > 75 and t["honesty"] > 60 and t["ambition"] < 45:
        return "worker"
    if t["temper"] > 70 and t["loyalty_ruler"] < 50:
        return "rebel"
    if t["tradition"] > 75 and t["empathy"] > 55:
        return "keeper"
    if t["sociability"] > 70 and t["empathy"] > 65 and t["temper"] < 40:
        return "diplomat"
    if t["sociability"] < 30 and t["curiosity"] > 60:
        return "loner"
    if t["bravery"] > 75 and t["aggression"] > 60:
        return "fighter"
    if t["curiosity"] > 75 and t["tradition"] < 45:
        return "visionary"
    if t["empathy"] > 75 and t["sociability"] > 60:
        return "caretaker"
    return "common"
```

### 6.2 Изменение черт характера со временем

| Событие / Опыт | Изменение черты |
|----------------|-----------------|
| NPC выжил после атаки зверя | bravery += 3..8 |
| NPC потерял близкого в войне | empathy += 5, temper += 3 |
| NPC долго голодал | loyalty_ruler -= 5, aggression += 4 |
| NPC 10+ раз успешно поговорил (TALKING) | sociability += 2 |
| NPC живёт в поселении с BLOOD_FEUD | aggression += 1/год |
| NPC живёт в religious поселении | tradition += 2/год, curiosity -= 1/год |
| NPC стал старейшиной | ambition -= 5, honesty += 5 |
| NPC часто побеждал в боях | bravery += 5, aggression += 3 |

ПРАВИЛО: изменение черты не превышает +/-2 за один игровой день, диапазон [0, 100].

### 6.3 Уникальные «изюминки» NPC (Quirks)

При создании NPC через `init_personality` добавляется 1-2 случайных quirk:

```gdscript
var quirks: Array[String] = []  # НОВОЕ поле в CitizenNPC

const QUIRK_POOL = [
    "night_owl",        # работает эффективнее ночью (schedule_offset += 4h)
    "early_bird",       # пробуждается раньше всех (-2h)
    "storyteller",      # чаще начинает разговоры, дольше speech_bubble
    "grudge_keeper",    # grudge никогда не затухает (is_permanent=true)
    "peacemaker",       # при создании grudge сначала пробует помириться
    "risk_taker",       # игнорирует fleeing до health < 20
    "hoarder",          # предпочитает ресурсную работу, max_carry x1.2
    "wanderer",         # выбирает дальние цели ресурсов
    "homebody",         # не уходит далеко от home_pos (radius x0.6)
    "devout",           # prayer эмоция в 3x чаще
    "skeptic",          # tradition черта в 2x слабее влияет на решения
    "ambitious_climber" # при job_discontent shout напрямую к вождю
]
```

---

## 7. СИСТЕМА ПРИНЯТИЯ РЕШЕНИЙ NPC

### 7.1 Автономные решения (Autonomous Actions)

NPC раз в игровой час проверяет список действий-кандидатов:

```gdscript
func _evaluate_autonomous_action() -> void:
    var candidates = []
    
    # 1. Инициировать разговор с другом
    if traits["sociability"] > 55 and social_cooldown <= 0.0:
        var nearby_friends = _get_nearby_with_closeness(60.0, 160.0)
        if not nearby_friends.is_empty():
            candidates.append({"action": "talk_friend", "weight": traits["sociability"] * 0.01})
    
    # 2. Конфликт с grudge-NPC (если temper высокий)
    if traits["temper"] > 65 and traits["bravery"] > 50:
        var grudge_npc = _find_nearby_grudge_target(96.0)
        if grudge_npc:
            candidates.append({"action": "confront", "weight": traits["temper"] * 0.008})
    
    # 3. Попросить еду при голоде
    if hunger < 30.0 and traits["sociability"] > 40:
        candidates.append({"action": "beg_food", "weight": (30.0 - hunger) * 0.03})
    
    # 4. Помочь раненому другу
    if traits["empathy"] > 65:
        var wounded = _find_nearby_wounded_friend(160.0)
        if wounded:
            candidates.append({"action": "help_wounded", "weight": traits["empathy"] * 0.01})
    
    # 5. Пожаловаться вождю при loyalty < 40
    if loyalty < 40.0 and traits["ambition"] > 50 and not has_memory("ruler_complaint"):
        candidates.append({"action": "complain_to_ruler", "weight": (40.0 - loyalty) * 0.05})
    
    # Выбор взвешенным рандомом
    _execute_autonomous_action(_weighted_choice(candidates))
```

### 7.2 Диалоговый банк по архетипам

```gdscript
const DIALOGUE_BANK = {
    "rebel_law_event": [
        "«Нас снова обкладывают законами!»",
        "«Кто дал вождю право решать за всех?»",
        "«Я не подчинюсь!»"
    ],
    "worker_abundance": [
        "«Мой труд не был напрасным!»",
        "«Вот что значит работать не покладая рук!»"
    ],
    "fighter_battle_start": [
        "«К оружию! Я ждал этого!»",
        "«Наконец-то настоящее дело!»",
        "«За племя!»"
    ],
    "caretaker_person_died": [
        "«Нам всем будет его/её не хватать...»",
        "«Я должна присмотреть за детьми...»"
    ],
    "keeper_tradition_removed": [
        "«Это святотатство! Предки отвернутся от нас!»",
        "«Без корней дерево падает!»"
    ],
    "diplomat_conflict": [
        "«Давайте успокоимся и поговорим.»",
        "«Мы найдём выход без крови.»"
    ],
    "visionary_religion_reform": [
        "«Наконец! Новый взгляд на мир!»",
        "«Может, боги и правда другие?»"
    ],
    "loner_any": [
        "«...»",
        "«Хм.»"
    ]
}
```

### 7.3 Мнения NPC о решениях игрока (Opinion System)

```gdscript
# В CitizenNPC добавляется:
var opinions: Dictionary = {}
# opinions[decision_id] = {
#   "stance": "support" | "oppose" | "neutral",
#   "intensity": float,  # 0..1
#   "reason": String
# }

func form_opinion_on_decision(decision_id: String, choice_data: Dictionary) -> void:
    var stance = "neutral"
    var intensity = 0.3
    
    if choice_data.get("tags", []).has("military"):
        if traits["bravery"] > 65:
            stance = "support"; intensity += 0.3
        elif traits["bravery"] < 35:
            stance = "oppose"; intensity += 0.2
    
    if choice_data.get("tags", []).has("tradition_break"):
        if traits["tradition"] > 70:
            stance = "oppose"; intensity += 0.4
        elif traits["curiosity"] > 70:
            stance = "support"; intensity += 0.2
    
    if choice_data.get("tags", []).has("tax_increase"):
        stance = "oppose"
        intensity += (loyalty < 60.0) as float * 0.3
    
    opinions[decision_id] = {
        "stance": stance,
        "intensity": clampf(intensity, 0.0, 1.0),
        "reason": _generate_opinion_reason(stance, choice_data)
    }
    
    if stance == "support":
        loyalty = minf(100.0, loyalty + intensity * 8.0)
    elif stance == "oppose":
        loyalty = maxf(0.0, loyalty - intensity * 10.0)
```

---

## 8. NPCEventReactor — НОВЫЙ КОМПОНЕНТ

### 8.1 Файл: `src/simulation/npc_event_reactor.gd`

```gdscript
class_name NPCEventReactor
extends RefCounted

var settlement: RefCounted = null

func _ready_connect(p_settlement: RefCounted) -> void:
    settlement = p_settlement
    EventBus.civilization_event_triggered.connect(_on_civilization_event)
    EventBus.event_resolved.connect(_on_event_resolved)
    EventBus.battle_started.connect(_on_battle_started)
    EventBus.battle_ended.connect(_on_battle_ended)
    EventBus.person_born.connect(_on_person_born)
    EventBus.person_died.connect(_on_person_died)
    EventBus.season_changed.connect(_on_season_changed)
    EventBus.building_constructed.connect(_on_building_constructed)
    EventBus.religion_reformed.connect(_on_religion_reformed)
    EventBus.law_enacted.connect(_on_law_enacted)
    EventBus.resources_updated.connect(_on_resources_updated)
    # НОВЫЕ сигналы:
    EventBus.npc_feud_started.connect(_on_npc_feud)
    EventBus.npc_revolt_risk.connect(_on_revolt_risk)
    EventBus.npc_celebration.connect(_on_celebration)

func _dispatch_to_citizens(
    scope: String,
    filter_fn: Callable,
    reaction_fn: Callable,
    delay_range: Vector2 = Vector2(0.0, 2.0),
    radius: float = 320.0,
    source_pos: Vector2 = Vector2.ZERO
) -> void:
    if settlement == null:
        return
    for citizen in settlement.citizens.values():
        if not citizen.is_alive:
            continue
        match scope:
            "all":
                pass
            "nearby":
                if citizen.pos.distance_to(source_pos) > radius:
                    continue
            "job", "trait", "involved":
                if not filter_fn.call(citizen):
                    continue
        var delay = randf_range(delay_range.x, delay_range.y)
        settlement.call_deferred("_schedule_npc_reaction", citizen.citizen_id, reaction_fn, delay)
```

### 8.2 Новые методы CitizenNPC

```gdscript
# Добавить в citizen_npc.gd:

func receive_civilization_event(event_data: Dictionary, reactions_list: Array) -> void:
    for reaction in reactions_list:
        var condition = reaction.get("condition", "")
        if not _evaluate_condition(condition):
            continue
        
        var loyalty_delta = float(reaction.get("loyalty_delta", 0.0))
        if loyalty_delta != 0.0:
            loyalty = clampf(loyalty + loyalty_delta, 0.0, 100.0)
        
        var emote_id = reaction.get("emote", "")
        if emote_id != "":
            var dur = float(reaction.get("emote_duration", 3.5))
            show_emote(emote_id, dur, 3)
        
        var mem_data = reaction.get("memory", {})
        if not mem_data.is_empty():
            add_memory(
                mem_data.get("type", "civic_event"),
                event_data.get("id", ""),
                "",
                float(mem_data.get("importance", 0.5)),
                mem_data.get("desc", event_data.get("title", "")),
                mem_data.get("is_permanent", false)
            )
        
        var shout_list = reaction.get("shout", [])
        if not shout_list.is_empty() and social_cooldown <= 0.0:
            shout(shout_list[randi() % shout_list.size()], 3.0)
            social_cooldown = randf_range(30.0, 90.0)
        
        break  # применяем только первое подходящее условие

func _evaluate_condition(condition: String) -> bool:
    if condition == "" or condition == "true":
        return true
    # Парсим простые условия: "trait.X > N", "job.X", "random.N", "AND/OR"
    # Реализация через split(" AND ") / split(" OR ")
    # ... (см. раздел реализации)
    return true  # заглушка — заменить полной реализацией
```

---

## 9. НОВЫЕ EVENTBUS СИГНАЛЫ

Добавить в `src/core/event_bus.gd`:

```gdscript
# --- NPC социальные события ---
signal npc_feud_started(citizen_a_id: String, citizen_b_id: String, reason: String)
signal npc_feud_resolved(citizen_a_id: String, citizen_b_id: String, resolution: String)
signal npc_romance_started(citizen_a_id: String, citizen_b_id: String)
signal npc_friendship_formed(citizen_a_id: String, citizen_b_id: String)
signal npc_revolt_risk(settlement_id: String, dissident_count: int, leader_id: String)
signal npc_celebration(settlement_id: String, reason: String, pos: Vector2)
signal npc_opinion_formed(citizen_id: String, decision_id: String, stance: String)
signal npc_complaint_to_ruler(citizen_id: String, complaint_type: String)
signal npc_trait_changed(citizen_id: String, trait_name: String, old_val: float, new_val: float)
signal npc_clique_formed(clique_id: String, clique_type: String, member_ids: Array)
signal npc_autonomous_action(citizen_id: String, action: String, target_id: String)
```

---

## 10. ПОВЕДЕНЧЕСКИЕ СОСТОЯНИЯ

### 10.1 Новые состояния для State enum

Добавить в `CitizenNPC.State`:

```gdscript
enum State {
    # ... существующие ...
    CELEBRATING,      # Праздник (после победы, рождения, урожая)
    MOURNING,         # Траур (1-3 игровых дня)
    CONFRONTING,      # Выяснение отношений с grudge-NPC
    COMPLAINING,      # Идёт к вождю с жалобой
    HELPING,          # Помогает раненому или голодному
    PRAYING,          # Молится (при religious событиях)
    FLEEING_HOME,     # Мчится домой при военной угрозе
}
```

### 10.2 Длительность специальных состояний

| Состояние | Длительность | Условие выхода |
|-----------|-------------|----------------|
| CELEBRATING | 1..4 игровых часа | Истёк таймер OR hunger < 30 |
| MOURNING | 12..72 игровых часа | Зависит от closeness к умершему |
| CONFRONTING | 30..120 секунд | Нашёл цель OR цель недоступна |
| COMPLAINING | До встречи с вождём | Вождь найден OR 5 минут |
| PRAYING | 2..6 игровых часа | Истёк таймер OR hunger < 20 |

---

## 11. ПРАВИЛА ДОБАВЛЕНИЯ НОВЫХ СОБЫТИЙ

> ОБЯЗАТЕЛЬНО для всех разработчиков. Любое новое событие в civilization_event_db.gd
> или event_db.gd ОБЯЗАНО следовать всем правилам этого раздела.

---

### ПРАВИЛО 1: Каждое событие должно содержать `npc_reactions`

```gdscript
# ЗАПРЕЩЕНО — событие без NPC-реакций:
{
    "id": "MY_EVENT_01",
    "title": "Новый закон",
    "choices": [...]
    # npc_reactions ОТСУТСТВУЕТ — НАРУШЕНИЕ!
}

# ОБЯЗАТЕЛЬНО — событие с NPC-реакциями:
{
    "id": "MY_EVENT_01",
    "title": "Новый закон",
    "choices": [...],
    "npc_reactions": {
        "scope": "all",
        "delay_range": [0.5, 4.0],
        "reactions": [
            {
                "condition": "trait.tradition > 60",
                "loyalty_delta": -5.0,
                "emote": "discontent",
                "memory": {
                    "type": "civic_discontent",
                    "importance": 0.5,
                    "desc": "Принят закон, нарушающий традиции."
                },
                "shout": ["«Это против наших обычаев!»", "«Предки не простят!»"]
            },
            {
                "condition": "trait.tradition <= 60 AND trait.curiosity > 50",
                "loyalty_delta": 3.0,
                "emote": "thought",
                "shout": ["«Интересно... что это изменит?»"]
            }
        ]
    }
}
```

---

### ПРАВИЛО 2: Каждый выбор `choice` должен иметь `choice_npc_reactions`

```gdscript
"choices": [
    {
        "id": "choice_war",
        "text": "Объявить войну",
        "tags": ["military", "aggressive"],  # ОБЯЗАТЕЛЬНО
        "effects": {"loyalty": -5, "military_spirit": 15},
        "choice_npc_reactions": {            # ОБЯЗАТЕЛЬНО
            "scope": "all",
            "delay_range": [1.0, 5.0],
            "reactions": [
                {
                    "condition": "trait.bravery > 65",
                    "loyalty_delta": 10.0,
                    "emote": "hero",
                    "shout": ["«Да! Покажем им силу!»", "«К битве!»"]
                },
                {
                    "condition": "trait.empathy > 65 AND trait.bravery < 50",
                    "loyalty_delta": -12.0,
                    "emote": "grief",
                    "shout": ["«Зачем война?.. Погибнут люди...»"]
                }
            ]
        }
    }
]
```

---

### ПРАВИЛО 3: Каждое событие должно иметь `tags`

```gdscript
# Обязательные теги (использовать хотя бы один):
"tags": [
    # Тематика:
    "military",           # военные вопросы
    "religion",           # религиозные вопросы
    "tradition",          # традиции и обычаи
    "trade",              # торговля и экономика
    "justice",            # правосудие и законы
    "land",               # земля и ресурсы
    "social",             # социальные отношения
    "succession",         # наследование власти
    
    # Тональность:
    "aggressive",         # агрессивный вариант
    "peaceful",           # мирный вариант
    "tradition_break",    # нарушает традицию
    "tradition_preserve", # сохраняет традицию
    "tax_increase",       # повышает налоги
    "tax_decrease",       # снижает налоги
    "equality",           # равноправие
    "hierarchy",          # усиление иерархии
]
```

---

### ПРАВИЛО 4: Проверить `scope` под тип события

| Тип события | Рекомендуемый scope |
|-------------|---------------------|
| Законодательное (меняет CultureMemory) | "all" |
| Военное столкновение | "nearby" radius: 640.0 |
| Рождение/смерть | "all" |
| Экономический кризис | "all" |
| Локальный конфликт NPC | "nearby" radius: 256.0 |
| Строительство | "nearby" radius: 320.0 |
| Религиозная реформа | "all" |
| Сезонный | "all" |

---

### ПРАВИЛО 5: Указать `memory` для важных событий (importance >= 0.6)

```gdscript
"memory": {
    "type": String,           # тип памяти (из списка ниже)
    "importance": float,      # 0.0..1.0
    "desc": String,           # от лица NPC (первое лицо)
    "is_permanent": bool      # true только для судьбоносных событий
}

# Стандартные типы памяти:
# "civic_event"      — гражданское событие
# "civic_pride"      — гордость за поселение
# "civic_discontent" — недовольство событием
# "war_pride"        — гордость победой
# "war_fear"         — страх перед войной
# "war_loss"         — потеря в войне
# "loss_friend"      — потеря друга
# "loss_family"      — потеря семьи
# "tradition_broken" — нарушение традиции
# "tradition_upheld" — защита традиции
# "hunger_crisis"    — голодный кризис
# "abundance"        — изобилие
# "home_lost"        — потеря жилья
# "home_gained"      — получение жилья
# "ruler_decision"   — важное решение вождя
# "religious_reform" — религиозное изменение
# "job_happiness"    — любимая работа
# "job_discontent"   — нелюбимая работа
# "grudge"           — обида на NPC
# "gratitude"        — благодарность NPC
# "betrayal"         — предательство
# "child_born"       — рождение ребёнка
# "peaceful_passing" — мирная смерть близкого
```

---

### ПРАВИЛО 6: Тест через `dev_event_inspector.gd`

После добавления события убедиться:
- [ ] Событие появляется в списке инспектора
- [ ] При эмуляции 3+ NPC реагируют эмотами
- [ ] В памяти NPC появляется запись
- [ ] Loyalty изменяется в соответствии с реакцией

---

### ПРАВИЛО 7: Не создавать «немых» NPC

Минимальная реакция на любое событие:
- >= 30% жителей должны получить emote
- >= 10% жителей должны получить shout (для importance >= 0.5)
- >= 50% жителей должны получить memory (для importance >= 0.7)

---

## 12. ИНТЕГРАЦИОННАЯ КАРТА

```
civilization_event_db.gd
    [каждое событие] + npc_reactions{}
            |
            v
civilization_event_manager.gd
    emit EventBus.civilization_event_triggered
            |
            v
npc_event_reactor.gd  <-- НОВЫЙ ФАЙЛ
    _on_civilization_event()
    _dispatch_to_citizens()
            |
            v
citizen_npc.gd
    receive_civilization_event()   <-- НОВЫЙ МЕТОД
    receive_world_event()          <-- НОВЫЙ МЕТОД
    form_opinion_on_decision()     <-- НОВЫЙ МЕТОД
    get_personality_archetype()    <-- НОВЫЙ МЕТОД
    _evaluate_autonomous_action()  <-- НОВЫЙ МЕТОД
    [расширяет] relationships{}
    [добавляет] quirks[]
    [добавляет] opinions{}
            |
            v
npc_relationship_graph.gd  <-- НОВЫЙ ФАЙЛ
    NPCClique class
    update_cliques()
    get_clique_for_citizen()
            |
            v
event_bus.gd
    + 11 новых сигналов
```

---

## 13. ЭТАПЫ РЕАЛИЗАЦИИ

### Этап 1 — Базовая реактивность (ПРИОРИТЕТ ВЫСОКИЙ)
- [ ] `receive_civilization_event()` и `receive_world_event()` в citizen_npc.gd
- [ ] Создать `npc_event_reactor.gd` с базовыми обработчиками
- [ ] Добавить `npc_reactions` к 5 существующим событиям (тест)
- [ ] Добавить 11 новых EventBus сигналов
- [ ] Парсер условий `_evaluate_condition()`

### Этап 2 — Характер (ПРИОРИТЕТ ВЫСОКИЙ)
- [ ] `get_personality_archetype()` в citizen_npc.gd
- [ ] DIALOGUE_BANK + `_get_archetype_shout()`
- [ ] `quirks` массив и `init_quirks()` в `init_personality()`
- [ ] `form_opinion_on_decision()`
- [ ] `opinions{}` поле в CitizenNPC

### Этап 3 — Отношения (ПРИОРИТЕТ СРЕДНИЙ)
- [ ] Расширить `relationships{}` (trust, respect, resentment, shared_history)
- [ ] Создать `npc_relationship_graph.gd` с NPCClique
- [ ] `calculate_compatibility()` метод
- [ ] Автообновление клик в settlement.gd каждые 3 игровых дня

### Этап 4 — Автономность (ПРИОРИТЕТ СРЕДНИЙ)
- [ ] `_evaluate_autonomous_action()` в citizen_npc.gd
- [ ] Новые состояния: CELEBRATING, MOURNING, CONFRONTING, COMPLAINING, HELPING, PRAYING
- [ ] Изменение черт характера со временем (`_apply_trait_drift()`)

### Этап 5 — Полная база событий (ПРИОРИТЕТ СТАНДАРТНЫЙ)
- [ ] `npc_reactions` ко ВСЕМ событиям в civilization_event_db.gd
- [ ] `tags` ко всем событиям и выборам
- [ ] Интеграция CultureMemory-норм в поведение NPC

### Этап 6 — Полировка (ПРИОРИТЕТ СТАНДАРТНЫЙ)
- [ ] Групповые синхронизированные emote (клика реагирует вместе)
- [ ] Обновление dev_event_inspector.gd — показывать npc_reactions
- [ ] Балансировка loyalty_delta значений

---

## ПРИЛОЖЕНИЕ А: Список эмотов для событий

| Ситуация | Emote ID | Приоритет |
|----------|----------|-----------|
| Победа в бою | hero | 4 |
| Поражение / смерть близкого | grief | 4-5 |
| Рождение ребёнка | love | 3 |
| Голод | hunger | 4 |
| Праздник/изобилие | joy | 3 |
| Угроза/страх | panic | 5 |
| Недовольство законом | discontent | 3 |
| Мятеж | rebellion | 4 |
| Молитва | prayer | 2 |
| Размышление | thought | 2 |
| Гордость | pride | 2 |
| Работа | work | 1 |
| Протест | protest | 4 |
| Холод (зима без дома) | cold | 3 |
| Боль | pain | 4 |
| Романтика | romance / love | 3 |
| Стража / наблюдение | observation | 2 |

---

## ПРИЛОЖЕНИЕ Б: Пример полного события с NPC-реакциями

```gdscript
{
    "id": "REL-STORM-01",
    "title": "Гнев небес",
    "description": "Три дня бушует буря. Молнии сожгли амбар. Жрец говорит — это знак богов.",
    "category": "Вера",
    "tags": ["religion", "disaster", "tradition"],
    "once": true,
    "conditions": {"min_days": 90, "season": "Осень"},
    
    "npc_reactions": {
        "scope": "all",
        "delay_range": [0.5, 6.0],
        "reactions": [
            {
                "condition": "trait.tradition > 65",
                "loyalty_delta": -5.0,
                "emote": "prayer",
                "emote_duration": 4.0,
                "memory": {
                    "type": "civic_discontent",
                    "importance": 0.7,
                    "desc": "Буря уничтожила амбар. Боги недовольны нами.",
                    "is_permanent": false
                },
                "shout": [
                    "«Это знак! Мы прогневали духов!»",
                    "«Нужно принести жертву!»",
                    "«Боги видят наши грехи...»"
                ]
            },
            {
                "condition": "trait.curiosity > 70 AND trait.tradition < 50",
                "loyalty_delta": 0.0,
                "emote": "thought",
                "shout": [
                    "«Просто гроза. Нужно отстроить амбар.»",
                    "«Интересно, почему молния ударила именно туда?»"
                ]
            },
            {
                "condition": "job.priest",
                "loyalty_delta": 5.0,
                "emote": "prayer",
                "emote_duration": 5.0,
                "shout": [
                    "«Слушайте меня! Боги требуют ритуала!»",
                    "«Только через молитву мы умилостивим небеса!»"
                ],
                "memory": {
                    "type": "religious_reform",
                    "importance": 0.8,
                    "desc": "Буря — мой час. Паства нуждается в руководстве.",
                    "is_permanent": true
                }
            },
            {
                "condition": "random.0.3",
                "loyalty_delta": -2.0,
                "emote": "fear",
                "shout": ["«Уберите детей в дом!»", "«Страшно...»"]
            }
        ]
    },
    
    "choices": [
        {
            "id": "choice_sacrifice",
            "text": "Провести жертвенный ритуал",
            "tags": ["religion", "tradition", "tradition_preserve"],
            "effects": {"food": -10, "faith": 20, "loyalty": 5},
            "choice_npc_reactions": {
                "scope": "all",
                "delay_range": [1.0, 8.0],
                "reactions": [
                    {
                        "condition": "trait.tradition > 60",
                        "loyalty_delta": 10.0,
                        "emote": "prayer",
                        "shout": ["«Правильное решение, вождь!»", "«Духи услышат нас!»"]
                    },
                    {
                        "condition": "trait.tradition < 40 AND trait.honesty > 60",
                        "loyalty_delta": -5.0,
                        "emote": "discontent",
                        "shout": ["«Мы теряем еду ради суеверий...»"]
                    }
                ]
            }
        },
        {
            "id": "choice_rebuild",
            "text": "Немедленно восстановить амбар",
            "tags": ["trade", "land", "tradition_break", "peaceful"],
            "effects": {"wood": -15, "stone": -5, "stability": 8},
            "choice_npc_reactions": {
                "scope": "all",
                "delay_range": [0.5, 4.0],
                "reactions": [
                    {
                        "condition": "trait.diligence > 65",
                        "loyalty_delta": 8.0,
                        "emote": "work",
                        "shout": ["«Дело важнее обрядов! За работу!»", "«Вождь мыслит разумно!»"]
                    },
                    {
                        "condition": "trait.tradition > 70",
                        "loyalty_delta": -8.0,
                        "emote": "discontent",
                        "shout": ["«Мы игнорируем знак богов. Плохо кончится.»"]
                    },
                    {
                        "condition": "job.builder",
                        "loyalty_delta": 12.0,
                        "emote": "pride",
                        "shout": ["«Я возведу лучший амбар!»", "«Дайте мне двух помощников!»"]
                    }
                ]
            }
        }
    ]
}
```

---

*Документ создан: 2026-09-28 | PlanetKI NPC ALIVE SYSTEM v1.0*  
*Авторитетный источник для разработки системы реакций NPC*
