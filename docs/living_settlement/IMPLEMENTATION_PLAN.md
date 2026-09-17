# Living Settlement & Scalable Simulation: Implementation Plan (S00–S17)

Спецификация: `PlanetKI_Living_Settlement_TZ_v2.md`
Версия движка: Godot 4.7.2.stable.official.ed1daf0bf
Базовый коммит: `73420397fa37f3150a4c5ea9647550141b5d6806` (ветка `main`)

---

## 1. Карта шагов и зависимостей

| Шаг | Название | Зависимости | Затрагиваемые файлы | Старый путь, который заменяется | Статус |
|---|---|---|---|---|---|
| **S00** | Исходное состояние и план | — | `docs/living_settlement/*`, `STATUS.md` | Инвентаризация разрозненных вызовов | **completed** |
| **S01** | Единый цикл, пауза и часы | S00 | `src/core/game_manager.gd`, `src/map/world_map_view.gd`, `src/ui/main_hud.gd`, `src/core/event_bus.gd`, `src/simulation/citizen_npc.gd` | `day_duration = 12.0`, разрозненные вызовы `update_citizens` и армий из UI/View, 4 сезона/месяцы | **completed** |
| **S02** | Идентичность, правитель и снимок | S01 | `src/simulation/settlement.gd`, `src/simulation/citizen_npc.gd`, `src/core/save_system.gd`, `src/simulation/population_sim.gd` | `home_id` как тип вместо instance_id, отсутствие schema_version, бессмертный или стареющий правитель без окончания игры | **in_progress** |
| **S03** | Задачи и цепочка добычи (лесоруб) | S02 | `src/simulation/settlement.gd`, `src/simulation/citizen_npc.gd`, `src/simulation/task_service.gd`, `src/simulation/inventory_service.gd`, `src/simulation/map_resource_manager.gd` | Ночной `deposit_resource`, мгновенное зачисление в экономику без фактической доставки складом | pending |
| **S04** | Общий учёт грузов, источников и порча | S03 | `src/simulation/settlement.gd`, `src/simulation/map_resource_manager.gd`, `src/simulation/inventory_service.gd`, `src/simulation/wildlife_manager.gd` | Пассивные начисления собирателей, каменотёсов, рудокопов; еда без срока порчи | pending |
| **S05** | Реальное строительство, улучшения, ремесло | S04 | `src/simulation/settlement.gd`, `src/simulation/building_instance.gd`, `src/ui/building_detail_panel.gd`, `src/simulation/production_service.gd` | `days_left -= builders` без труда, мгновенная покупка экипировки в UI без работы мастера | pending |
| **S06** | Проживание и домашние запасы | S05 | `src/simulation/settlement.gd`, `src/simulation/citizen_npc.gd`, `src/simulation/household_service.gd` | Общая абстрактная вместимость, сон в одной точке, отсутствие домашних запасов | pending |
| **S07** | Отношения, опека и демография | S06 | `src/simulation/population_sim.gd`, `src/simulation/citizen_npc.gd`, `src/simulation/relationship_service.gd` | Спавн детей по формуле прироста раз в месяц/год, отсутствие опекунов | pending |
| **S08** | Самостоятельная работа и характер | S07 | `src/simulation/citizen_npc.gd`, `src/simulation/settlement.gd` | Жесткий ежекадровый автомат состояний без учета усталости/помощи близким | pending |
| **S09** | Рыбалка, группы охоты и восстановление | S08 | `src/simulation/wildlife_manager.gd`, `src/simulation/map_resource_manager.gd`, `src/simulation/settlement.gd` | Одиночная охота без групп, мгновенная регенерация без стадий роста | **completed** |
| **S10** | Реальные экземпляры событий (3 вкладки) | S09 | `src/events/civilization_event_manager.gd`, `src/ui/event_registry_panel.gd`, `src/ui/civilization_event_modal.gd`, `src/ui/main_hud.gd` | Демо-карточки без проверки реального instance_id, фиктивные события амбаров | **in_progress** |
| **S11** | Законы, культура и социальные последствия | S10 | `src/simulation/law_system.gd`, `src/simulation/culture_memory.gd`, `src/simulation/settlement.gd` | Абстрактные модификаторы лояльности без изменения правил распределения и зон | pending |
| **S12** | Происшествия, расследования, суд | S11 | `src/simulation/justice_service.gd`, `src/simulation/settlement.gd`, `src/ui/events_dialog.gd` | Моментальное обвинение без улик и без процесса отбывания срока | pending |
| **S13** | Интеграция панелей зданий и угроз | S12 | `src/ui/building_detail_panel.gd`, `src/ui/citizen_detail_panel.gd`, `src/simulation/settlement.gd` | Одинаковые панели для всех зданий, фиктивные кнопки | pending |
| **S14** | Камера, знание мира и мини-карта | S13 | `src/map/map_camera.gd`, `src/map/world_map_view.gd`, `src/ui/main_hud.gd` | Неограниченный зум, раскрытие тумана войны при клике на мини-карту | pending |
| **S15** | Фоновое исполнение без второй экономики | S14 | `src/core/simulation_runner.gd`, `src/simulation/settlement.gd` | Полная симуляция только на экране, остановка или фиктивное начисление за экраном | pending |
| **S16** | Профилирование 500/1000 жителей | S15 | `tests/test_benchmark_scale.gd`, `src/core/simulation_runner.gd` | Бенчмарк только на 200 жителях | pending |
| **S17** | Завершение поставки и сквозная верификация | S16 | Полный проект, сценарии раздела 19, `tests/test_runner.gd` | Финальная зачистка legacy-кода и валидация сценариев приёмки | pending |

---

## 2. Критерии завершения каждого шага
Каждый шаг считается завершенным ТОЛЬКО при выполнении условий:
1. Запускается в обычной игре и через test_runner.
2. Единственный ответственный обработчик состояния (Single Source of Truth).
3. Проверка входных ресурсов, времени и физических участников.
4. Корректное поведение при отсутствии пути/ресурса, смерти участника.
5. Save/load сохраняет состояние и незавершенный процесс.
6. UI показывает честные данные и причины блокировок.
7. Старый альтернативный расчет удален в этом же шаге.
8. Тесты пройдены, результаты зафиксированы в STATUS.md и VERIFICATION.md.
