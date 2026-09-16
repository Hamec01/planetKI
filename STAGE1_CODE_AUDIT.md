# 📋 ПОЛНЫЙ АУДИТ КОДОВОЙ БАЗЫ ЭТАПА 1 (STAGE1_CODE_AUDIT.md)

**Источник правды:** [`STAGE1_CIVILIZATION_EVENTS_v3_SOURCE_OF_TRUTH.md`](file:///e:/Planetki/STAGE1_CIVILIZATION_EVENTS_v3_SOURCE_OF_TRUTH.md)  
**Дата проведения:** 2026-09-16  
**Статус аудита:** Завершён (Готов к поэтапной миграции)

---

## 1. Сводный реестр систем и классификация

| Система / Файл | Текущее поведение | Конфликт со Source of Truth | Решение | Риск | Зависимости |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`src/simulation/religion_system.gd`** | Статический каталог готовых религий (`ancestors`, `sun`, `spirits`, `rationalism`) с кнопками выбора. | Религия должна рождаться **только из событий** (EVENT-REL-01 и далее), накапливая `CultureMemory`. | **REFACTOR / MIGRATE** | Средний | `MainHUD`, `FactionView`, `SaveSystem` |
| **`src/simulation/law_system.gd`** | Каталог готовых законов со стоимостью и переключателями. | Игрок не должен покупать законы из каталога. Нормы возникают из событий и формируют `CultureMemory`. | **REFACTOR** | Средний | `Settlement`, `MainHUD`, `FactionView` |
| **`src/simulation/tech_tree.gd`** | Линейное дерево технологий за очки знаний (`knowledge`). | Запрещено общее абстрактное дерево. Открытия происходят через опыт NPC, работу зданий и события. | **REMOVE / MIGRATE** | Низкий | `Settlement`, `MainHUD` |
| **`src/events/event_db.gd`** | Набор разрозненных рандомных событий (засуха, хищник, находка). | Нужен централизованный граф фундаментальных цивилизационных цепочек (Смерть, Каннибализм, Брак, Власть и т.д.). | **REFACTOR / EXPAND** | Высокий | `EventManager`, `EventBus`, `MainHUD` |
| **`src/events/event_manager.gd`** | Базовый таймер случайных событий. | Требуется централизованный `EventEligibilityService`, chain locks, cooldowns, exclusive groups и idempotent effects. | **REFACTOR** | Высокий | `GameManager`, `EventBus` |
| **`src/simulation/building_system.gd`** | Каталог 8 активных институтов, режимов и локальных апгрейдов. | Соответствует концепции "Building Local Systems". Требуется связать открытие зданий/апгрейдов с событиями. | **KEEP / EXPAND** | Низкий | `BuildingInstance`, `BuildingDetailPanel`, `RTSBuildMenu` |
| **`src/simulation/building_instance.gd`** | Класс экземпляра здания (мастер, рабочие, режимы, история, заказы). | Полностью соответствует утверждённой архитектуре. | **KEEP** | Низкий | `GameManager`, `BuildingDetailPanel` |
| **`src/ui/rts_build_menu.gd`** | Меню строительства на карте по категориям (B). | Все специальные здания должны проверяться на условие открытия (разблокированы ли через события). | **REFACTOR** | Низкий | `BuildingDB`, `BuildingSystem`, `MainHUD` |
| **`src/ui/building_detail_panel.gd`** | 7-вкладочная карточка здания (Обзор, Люди, Режимы, Апгрейды, Заказы, События, Летопись). | Полностью соответствует концепции институционального развития. | **KEEP** | Низкий | `BuildingInstance`, `BuildingSystem` |
| **`src/ui/faction_view.gd`** | Старые окна законов и религии. | Содержит элементы прямого выбора. Должно стать **реестром возникших традиций и летописью веры**. | **REFACTOR** | Средний | `MainHUD`, `CultureMemory` |
| **`src/simulation/population_sim.gd`** | Симуляция жителей (когорты, имена, опыт, назначение). | Соответствует живой демографии. Добавить атрибуты для согласия на брак, семейных кланов и зависимости. | **KEEP / EXPAND** | Средний | `Settlement`, `WorldMapView` |
| **`src/simulation/economy_sim.gd`** | Симуляция ресурсов (пища, дерево, камень, металл, кубрики). | Удалить абстрактную валюту знаний, перевести налоги на модель общих сборов (доли амбара, труд). | **REFACTOR** | Средний | `Settlement`, `MainHUD` |
| **`src/map/world_map_view.gd`** | RTS рендеринг карты 160x160, жители 1:1, бои на карте. | Полностью соответствует вектору RTS / God-Sim. | **KEEP** | Низкий | `GameManager`, `MapCamera` |
| **`src/map/map_camera.gd`** | Плавная камера с зумом к курсору и перемещением. | Полностью оптимизирована и соответствует стандарту RTS. | **KEEP** | Низкий | `WorldMapView` |
| **`src/combat/general_generator.gd`** | Генерация случайных генералов. | Генералы не должны появляться из воздуха. Привязать к Штабу Воеводы, проявившимся воинам и событиям. | **REFACTOR** | Средний | `ArmyData`, `WorldMapView` |

---

## 2. Подробный анализ удаляемых и рефакторимых систем

### 2.1. Религия (`ReligionSystem` ➔ `EmergentReligionState`)
* **Что удаляется:** Прямой селектор пантеонов из списка; свободное переключение верований кнопкой; абстрактная валюта веры.
* **Что создаётся:** 
  * Вера рождается из `EVENT-REL-01` (Гроза над поселением) и фиксируется в `CultureMemory` (Анимизм / Монотеизм с вводом имени бога / Политеизм с именованием пантеона / Культ предков / Ранний рационализм).
  * Панель Религии (`ReligionPanel`) превращается в *Летопись веры и Священные обычаи* (показывает имя бога, догматы, происхождение, жрецов и священные места).

### 2.2. Законы и Институты (`LawSystem` ➔ `CultureMemory` + `InstitutionsRegistry`)
* **Что удаляется:** Меню-магазин законов с покупкой за очки.
* **Что создаётся:**
  * Authoritative реестр `CultureMemory` с силой традиции (`tradition_strength`), годом установления (`established_year`) и событиями-источниками.
  * Форма правления (`GovernmentState`) рассчитывается как **производное состояние (`derived state`)** на основе принятых норм власти (напр. *«Выборное вождество с Советом старейшин»* или *«Сакральная наследственная власть»*).
  * Взаимоисключающие группы (`exclusive_groups`): брак, наследование, суд, рабство, военная обязанность, налоги.

### 2.3. Наука и Технологии (`TechTree` ➔ `PracticeDiscoverySystem`)
* **Что удаляется:** Глобальное абстрактное дерево науки за очки `knowledge`.
* **Что создаётся:**
  * Открытия происходят на практике: работа в мастерских + опыт мастеров + природные условия + события = открытие локального рецепта/улучшения (напр. закалка в Кузнице, колесо у Плотника, лечебная хижина после эпидемии).

### 2.4. Армия и Генералы (`ArmySystem` ➔ `EmergentMilitaryState`)
* **Что удаляется:** Мгновенный найм генералов из выпадающего меню.
* **Что создаётся:**
  * Военная модель формируется решениями: *«Всеобщая обязанность»*, *«Родовые дружины»*, *«Профессиональная дружина»*.
  * Присяга: вождю, совету, роду или лично Воеводе.
  * Параметры генералов: `personal_loyalty`, `army_loyalty`, `ambition`, `prestige`, `clan_support`, риск мятежа.

---

## 3. Архитектура нового Ядра Цивилизации (`CivilizationState`)

```gdscript
class_name CivilizationState
extends RefCounted

var culture_memory: Dictionary = {} # id -> CultureMemoryEntry
var institutions: Dictionary = {}   # id -> InstitutionData
var religion_state: Dictionary = {} # base_type, deity_name, clergy_model, dogmas
var government_state: Dictionary = {} # derived_title, succession_rule, authority_source
var military_state: Dictionary = {} # warrior_duty, oath_target, private_warbands_allowed
var tax_state: Dictionary = {}      # levy_form, collector_model, budget_allocation
var discovered_practices: Array = [] # unlocked through experience & events
var history_records: Array = []     # chronicle of major choices
```

---

## 4. План перехода (Execution Steps)
1. **STEP 2:** Отключить старые пути прямого выбора в UI (`main_hud.gd`, `faction_view.gd`).
2. **STEP 3:** Создать `CivilizationState` и `CultureMemory` с поддержкой exclusive groups и derived government.
3. **STEP 4:** Создать централизованный `EventEligibilityService` и `CivilizationEventManager` с валидацией триггеров.
4. **STEP 5:** Реализовать цепочки **Batch 1 Events** (Смерть/Похороны, Каннибализм, Брак, Согласие, Собственность, Кровная месть, Власть вождя, Выбор преемника, Первая вера).
5. **STEP 6:** Связать разблокировку зданий в `RTSBuildMenu` с культурными решениями.
