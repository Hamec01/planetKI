extends Node

# Сигналы времени и симуляции
signal day_passed(day: int, month: int, year: int)
signal month_passed(month: int, year: int)
signal season_changed(season_name: String)
signal year_passed(year: int)
signal game_speed_changed(new_speed: float, is_paused: bool)
signal time_period_changed(period_name: String)

# Сигналы NPC и жителей
signal citizen_selected(citizen: RefCounted)
signal citizen_deselected()

# Сигналы ресурсов и экономики
signal resources_updated(faction_id: String, resources: Dictionary)
signal settlement_expanded(settlement_id: String, building_id: String)
signal building_constructed(settlement_id: String, building_data: Dictionary)
signal job_assigned(settlement_id: String, job_id: String, count: int)

# Сигналы населения и демографии
signal population_changed(faction_id: String, total: int, delta: int, reason: String)
signal person_born(settlement_id: String)
signal person_died(settlement_id: String, reason: String)

# Сигналы событий
signal event_triggered(event_data: Dictionary)
signal event_resolved(event_id: String, choice_index: int, results: Dictionary)
signal civilization_event_triggered(event_data: Dictionary)

# Сигналы политики, законов и религии
signal law_enacted(faction_id: String, law_id: String)
signal religion_reformed(faction_id: String, religion_data: Dictionary)
signal loyalty_changed(faction_id: String, new_loyalty: float)

# Сигналы строительства на карте
signal start_building_placement(building_id: String)
signal cancel_building_placement()
signal building_placed_on_map(building_id: String, coord: Vector2i)

# Сигналы войны и генералов
signal army_selected(army_data: RefCounted)
signal army_deselected()
signal army_command_given(army_id: String, command: String, target: Variant)
signal battle_started(battle_data: Dictionary)
signal battle_round_finished(battle_id: String, round_log: String)
signal battle_ended(battle_data: Dictionary, victory: bool)
signal general_gained_trait(general_id: String, trait_name: String)

# Сигналы дипломатии
signal diplomacy_relation_changed(faction_a: String, faction_b: String, new_value: int)
signal treaty_signed(type: String, faction_a: String, faction_b: String)

# Сигналы карты и мира
signal world_generated(planet_data: Dictionary)
signal tile_selected(coord: Vector2i, tile_data: Dictionary)
signal tile_right_clicked(coord: Vector2i, tile_data: Dictionary, screen_pos: Vector2)
signal nature_object_selected(nature_info: Dictionary, screen_pos: Vector2)
signal animal_selected(animal: RefCounted, screen_pos: Vector2)
signal selection_cleared()
signal order_harvest_resource(coord: Vector2i, category: String)
signal settlement_selected(settlement_data: RefCounted)
signal history_entry_added(year: int, title: String, description: String, category: String)
signal notification_toast(title: String, message: String, type: String)
signal map_mode_changed(mode_name: String)
signal ruler_died(ruler_name: String, killer_name: String)
signal game_over(reason: String)


