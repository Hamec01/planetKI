class_name WoodcutterProfession
extends ProfessionBehavior

# ==============================================================================
# ЛЕСОРУБ: топор со стойки лагеря -> дерево в зоне вырубки -> удары топором
#   (дерево убывает и исчезает с карты) -> брёвна в буфер лагеря -> склад.
#   Без деревьев — сажает саженцы на вырубке.
# ==============================================================================

func get_job_ids() -> Array[String]:
	return ["woodcutter"]

func pick_task(s: SettlementData, c: CitizenNPC, _delta: float) -> bool:
	if not is_working_age(c):
		return false
	if c.cargo_amount > 0.0:
		c.state = CitizenNPC.State.CARRYING
		var camp_lead = s.get_active_woodcutter_camp()
		if camp_lead and c.task_id == "deposit_to_camp" and not camp_lead.is_buffer_full():
			var camp_p = GameManager.nav_grid.tile_to_world_center(camp_lead.pos) if GameManager.nav_grid else Vector2(camp_lead.pos.x * 32.0 + 16, camp_lead.pos.y * 32.0 + 16)
			c.path = GameManager.nav_grid.find_path(c.pos, camp_p) if GameManager.nav_grid else []
			c.path_index = 0
			c.last_status_reason = "Несёт %d дров в лагерь лесорубов" % int(c.cargo_amount)
		else:
			var dest_p = s._get_storage_pos(c)
			c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
			c.path_index = 0
			c.task_id = ""
			c.last_status_reason = "Несёт %d дров на склад поселения" % int(c.cargo_amount)
		if GameManager.task_service and c.task_instance_id != "":
			GameManager.task_service.set_delivering(c.task_instance_id)
		return true

	# Без лагеря лесорубов рубка живого леса запрещена
	if not s.has_active_woodcutter_camp():
		c.state = CitizenNPC.State.WAITING
		c.task_id = ""
		c.last_status_reason = "Ожидание: требуется Лагерь лесорубов"
		c.decision_cooldown = randf_range(2.0, 4.0)
		return true

	# Проверяем топор (если лагерь еще не построен или инструменты пусты — лесоруб использует общинный рабочий топор)
	var camp = s.get_active_woodcutter_camp()
	if not c.has_tool("axe"):
		if camp and camp.has_available_tool("axe"):
			var tool = camp.take_tool("axe")
			tool["assigned_to"] = c.citizen_id
			c.equipped_tool = tool
			c.last_status_reason = "Взял топор в лагере лесорубов"
		elif camp and not camp.has_available_tool("axe"):
			c.state = CitizenNPC.State.WAITING
			c.task_id = ""
			c.last_status_reason = "Ожидание: Нет доступного топора в лагере"
			c.decision_cooldown = randf_range(2.0, 4.0)
			return true
		elif not s.has_active_woodcutter_camp():
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Ожидание: требуется Лагерь лесорубов"
			return true
		else:
			c.equipped_tool = {"id": "primitive_axe", "type": "axe", "durability": 60.0, "max_durability": 60.0}

	# Проверяем заполненность буфера лагеря: если буфер накоплен (>= 20.0), помогаем переносить на склад
	if camp and camp.local_buffer_wood >= 20.0:
		var take_amt = camp.take_wood(c.max_carry)
		if take_amt > 0.0:
			c.cargo_type = "wood"
			c.cargo_amount = take_amt
			c.task_id = "haul_from_camp"
			c.state = CitizenNPC.State.CARRYING
			var s_pos = s._get_storage_pos(c)
			c.path = GameManager.nav_grid.find_path(c.pos, s_pos) if GameManager.nav_grid else []
			c.path_index = 0
			c.last_status_reason = "Буфер накоплен: несёт %d дров из лагеря на склад" % int(take_amt)
			return true

	# Проверяем наличие Лагеря лесорубов и улучшения на посадку леса
	var can_plant = false
	var plant_mode = false
	for b_coord in GameManager.building_instances:
		var b_inst = GameManager.building_instances[b_coord]
		if b_inst and "type" in b_inst and b_inst.type == "woodcutter_camp":
			if b_inst.is_upgrade_unlocked("woodcutter_forestry"):
				can_plant = true
			if b_inst.active_mode == "reforestation":
				plant_mode = true
				can_plant = true

	# Если включен режим лесопосадки или есть улучшение (шанс посеять саженец)
	if can_plant and (plant_mode or randf() < 0.35):
		var plant_tile = GameManager.resource_manager.find_plantable_tile(s.pos, 12)
		if plant_tile != Vector2i(-1, -1):
			c.task_id = "plant_tree"
			c.target_coord = plant_tile
			c.target_pos = GameManager.nav_grid.tile_to_world_center(plant_tile)
			c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
			c.path_index = 0
			c.state = CitizenNPC.State.MOVING_TO_WORK
			c.last_status_reason = "Идёт сажать саженец дерева"
			c.decision_cooldown = 0.8
			return true

	# 0. Проверяем наличие активной зоны вырубки или прямого приказа игрока
	if not s.has_active_logging_zone():
		c.state = CitizenNPC.State.WAITING
		c.task_id = ""
		c.last_status_reason = "Ожидание: Не знаю, где разрешено рубить лес (нет зоны вырубки)"
		c.decision_cooldown = randf_range(2.0, 4.0)
		return true

	# 1. Проверяем первоочередные цели игрока (отмеченные кликом по дереву)
	var chosen_tree: Dictionary = {}
	for p_coord in s.priority_harvest_coords:
		var p_node = GameManager.resource_manager.nodes.get(p_coord, {}) if GameManager.resource_manager else {}
		if not p_node.is_empty() and p_node.get("category", "") == "wood" and not p_node.get("depleted", false) and p_node.get("amount", 0.0) > 0.0:
			if p_node.get("reserved_by", "") == "" or p_node.get("reserved_by", "") == c.citizen_id:
				chosen_tree = p_node
				break

	# 2. Обычная заготовка: поиск зрелого дерева (в выделенной зоне или в окрестностях поселения)
	var tree = chosen_tree
	if tree.is_empty() and GameManager.resource_manager:
		if not s.logging_zones.is_empty():
			var best_dist = 999999.0
			var best_node = {}
			for z_coord in s.logging_zones:
				var z_node = GameManager.resource_manager.nodes.get(z_coord, {})
				if not z_node.is_empty() and z_node.get("category", "") == "wood" and not z_node.get("depleted", false) and z_node.get("amount", 0.0) > 0.0:
					if z_node.get("reserved_by", "") == "" or z_node.get("reserved_by", "") == c.citizen_id:
						var d = c.pos.distance_squared_to(z_node["pos"])
						if d < best_dist:
							best_dist = d
							best_node = z_node
			if not best_node.is_empty():
				tree = best_node
			else:
				c.state = CitizenNPC.State.WAITING
				c.task_id = ""
				c.last_status_reason = "Ожидание: Нет допустимых деревьев в зоне вырубки"
				c.decision_cooldown = randf_range(2.0, 4.0)
				return true
		else:
			# Если зона не размечена — рубим ближайший зрелый лес по приказам
			tree = GameManager.resource_manager.find_available_node(s.pos, "wood", 28, c.citizen_id)
			if tree.is_empty():
				tree = GameManager.resource_manager.find_available_node(s.pos, "wood", 56, c.citizen_id)

	if not tree.is_empty():
		var t_path = GameManager.nav_grid.find_adjacent_path(c.pos, tree["coord"]) if GameManager.nav_grid else []
		if t_path.is_empty() and GameManager.nav_grid:
			t_path = GameManager.nav_grid.find_path(c.pos, tree["pos"], true)
		if t_path.is_empty() and c.pos.distance_to(tree["pos"]) <= 36.0:
			t_path = [c.pos]

		if t_path.is_empty():
			if GameManager.task_service:
				var blocked_id = GameManager.task_service.create_task("chop_tree", tree.get("id", ""), tree["coord"], tree["pos"])
				GameManager.task_service.fail_task(blocked_id, "Нет пути к дереву", true)
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Нет пути к дереву (%s)" % tree["name"]
			c.decision_cooldown = randf_range(2.0, 4.0)
			DebugLogger.log_warn("Woodcutter", "Лесоруб %s не нашел путь к дереву на %s" % [c.name, tree["coord"]])
			return true
		GameManager.resource_manager.reserve_node(tree["coord"], c.citizen_id)
		c.task_id = "chop_tree"
		c.target_coord = tree["coord"]
		c.target_pos = t_path[-1] if not t_path.is_empty() else tree["pos"]
		c.target_id = tree["id"]
		c.path = t_path
		c.path_index = 0
		c.state = CitizenNPC.State.MOVING_TO_WORK
		c.last_status_reason = "Идёт рубить: %s" % tree["name"]
		c.decision_cooldown = 0.8
		DebugLogger.log_info("Woodcutter", "Лесоруб %s направлен рубить %s на %s" % [c.name, tree["name"], tree["coord"]])
		if GameManager.task_service:
			var tid = GameManager.task_service.create_task("chop_tree", tree["id"], tree["coord"], tree["pos"])
			GameManager.task_service.assign_actor(tid, c.citizen_id)
			c.task_instance_id = tid
	else:
		if can_plant:
			var plant_tile = GameManager.resource_manager.find_plantable_tile(s.pos, 14)
			if plant_tile != Vector2i(-1, -1):
				c.task_id = "plant_tree"
				c.target_coord = plant_tile
				c.target_pos = GameManager.nav_grid.tile_to_world_center(plant_tile)
				c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
				c.path_index = 0
				c.state = CitizenNPC.State.MOVING_TO_WORK
				c.last_status_reason = "Восстанавливает вырубку: сажает дерево"
				c.decision_cooldown = 0.8
				return true
		c.state = CitizenNPC.State.WAITING
		c.last_status_reason = "Нет доступных деревьев"
		c.decision_cooldown = randf_range(3.0, 5.0)
	return true

func on_arrived(s: SettlementData, c: CitizenNPC) -> bool:
	c.state = CitizenNPC.State.WORKING
	if c.target_coord != Vector2i(-1, -1) and GameManager and GameManager.nav_grid:
		var tree_center = GameManager.nav_grid.tile_to_world_center(c.target_coord)
		var diff = tree_center - c.pos
		var dist_to_tree = diff.length()
		if dist_to_tree > 0.001:
			c.facing_dir = diff.normalized()
		# Подводим жителя вплотную к стволу, если путь до него завершился с зазором
		if c.task_id != "plant_tree" and dist_to_tree > 16.0:
			c.pos = tree_center - c.facing_dir * 14.0
	if GameManager.task_service and c.task_instance_id != "":
		GameManager.task_service.set_arrived(c.task_instance_id)
		GameManager.task_service.start_task(c.task_instance_id)
	if c.task_id == "plant_tree":
		c.work_timer = 2.5
		c.last_status_reason = "Сажает саженец дерева"
	else:
		c.work_timer = randf_range(4.5, 6.0)
		c.last_status_reason = "Рубит дерево топором"
	return true

# Удар топором или посадка саженца завершены
func on_work_done(s: SettlementData, c: CitizenNPC) -> bool:
	if c.task_id == "plant_tree":
		if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
			GameManager.resource_manager.plant_tree(c.target_coord, "tree_young", "tree_pine" if randf() > 0.5 else "tree_oak")
		c.target_coord = Vector2i(-1, -1)
		c.task_id = ""
		c.state = CitizenNPC.State.IDLE
		c.decision_cooldown = randf_range(1.5, 3.0)
		c.last_status_reason = "Посадил молодой саженец"
		EventBus.notification_toast.emit("Посадка леса", "Лесорубы посеяли молодое дерево", "good")
	else:
		# УДАР ТОПОРОМ: физический износ топора и постепенная рубка (2.0 древесины за удар с учетом сил)
		if not c.equipped_tool.is_empty():
			c.wear_tool(0.06)
			if not c.has_tool("axe"):
				c.state = CitizenNPC.State.WAITING
				c.last_status_reason = "Топор сломан во время рубки"
				c.task_id = ""
				c.decision_cooldown = randf_range(2.0, 4.0)
				if GameManager.resource_manager:
					GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
				return true

		var strike_harvest = 12.5 * c.get_vitality_multiplier()
		var h_amount = 0.0
		if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
			if GameManager.nav_grid:
				var tree_center = GameManager.nav_grid.tile_to_world_center(c.target_coord)
				var diff = tree_center - c.pos
				if diff.length_squared() > 0.001:
					c.facing_dir = diff.normalized()
			h_amount = GameManager.resource_manager.harvest_from_node(c.target_coord, strike_harvest)

		if h_amount > 0.0:
			c.cargo_type = "wood"
			c.cargo_amount += h_amount
			c.add_work_xp("woodcutting", 0.4)

		# Проверяем оставшийся запас в дереве
		var node = GameManager.resource_manager.nodes.get(c.target_coord, {}) if GameManager.resource_manager else {}
		var rem_wood = float(node.get("amount", 0.0)) if not node.is_empty() else 0.0
		var is_done = node.get("depleted", false) or rem_wood <= 0.0 or h_amount <= 0.0

		if is_done or c.cargo_amount >= minf(18.0, c.max_carry):
			# Дерево срублено полностью (или достигнут переносимый объем древесины)
			if GameManager.resource_manager:
				GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
			if s.priority_harvest_coords.has(c.target_coord):
				s.priority_harvest_coords.erase(c.target_coord)
			c.target_coord = Vector2i(-1, -1)

			if c.cargo_amount > 0.0:
				c.state = CitizenNPC.State.CARRYING
				var camp = s.get_active_woodcutter_camp()
				if camp:
					var camp_p = GameManager.nav_grid.tile_to_world_center(camp.pos) if GameManager.nav_grid else Vector2(camp.pos.x * 32.0 + 16, camp.pos.y * 32.0 + 16)
					c.path = GameManager.nav_grid.find_path(c.pos, camp_p) if GameManager.nav_grid else []
					c.path_index = 0
					c.task_id = "deposit_to_camp"
					c.last_status_reason = "Срубил дерево, несёт %d дров в лагерь лесорубов" % int(c.cargo_amount)
				else:
					var dest_p = s._get_storage_pos(c)
					c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
					c.path_index = 0
					c.task_id = ""
					c.last_status_reason = "Срубил дерево, несёт %d дров на склад" % int(c.cargo_amount)
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.set_delivering(c.task_instance_id)
			else:
				c.state = CitizenNPC.State.IDLE
				c.task_id = ""
				c.decision_cooldown = 1.0
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.cancel_task(c.task_instance_id, "Дерево пустое")
					c.task_instance_id = ""
		else:
			# Следующий удар топором через 4.5-6.0 сек (размеренная физическая рубка)
			c.work_timer = randf_range(4.5, 6.0)
			c.last_status_reason = "Рубит дерево (осталось %d дров)" % int(rem_wood)
	return true

# Брёвна донесены до лагеря лесорубов
func on_cargo_delivered(s: SettlementData, c: CitizenNPC) -> bool:
	if c.task_id != "deposit_to_camp":
		return false
	var camp = s.get_active_woodcutter_camp()
	if camp:
		if camp.is_buffer_full():
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Буфер лагеря лесорубов заполнен"
			c.decision_cooldown = 2.0
			return true
		else:
			var stored = camp.store_wood(c.cargo_amount)
			c.cargo_amount -= stored
			if c.cargo_amount <= 0.0:
				c.cargo_type = ""
				c.task_id = ""
				c.state = CitizenNPC.State.IDLE
				c.decision_cooldown = 0.5
				c.last_status_reason = "Сложил брёвна в буфер лагеря (%d/%d)" % [int(camp.local_buffer_wood), int(camp.local_buffer_max)]
				if GameManager.task_service and c.task_instance_id != "":
					GameManager.task_service.complete_task(c.task_instance_id)
					c.task_instance_id = ""
				return true
			else:
				c.state = CitizenNPC.State.WAITING
				c.last_status_reason = "Буфер лагеря лесорубов заполнен"
				c.decision_cooldown = 2.0
				return true
	return false
