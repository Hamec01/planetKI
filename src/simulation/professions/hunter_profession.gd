class_name HunterProfession
extends ProfessionBehavior

# ==============================================================================
# ОХОТНИК: выслеживание -> погоня -> атака (общая боевая фаза поселения)
#   -> туша (мясо + шкура/мех/перья + кости) -> разделка в лагере -> амбар.
# ==============================================================================

func get_job_ids() -> Array[String]:
	return ["hunter"]

func pick_task(s: SettlementData, c: CitizenNPC, _delta: float) -> bool:
	if not is_working_age(c):
		return false
	if c.cargo_type == "carcass":
		var camp_p = s._find_hunting_camp_pos(c)
		c.path = GameManager.nav_grid.find_path(c.pos, camp_p)
		c.path_index = 0
		c.state = CitizenNPC.State.CARRYING
		c.last_status_reason = "Несёт тушу в охотничий лагерь"
		return true
	elif c.cargo_type == "food" and c.cargo_amount > 0:
		var dest_p = s._get_storage_pos(c)
		c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
		c.path_index = 0
		c.state = CitizenNPC.State.CARRYING
		c.last_status_reason = "Несёт %d еды в амбар" % int(c.cargo_amount)
		if GameManager.task_service and c.task_instance_id != "":
			GameManager.task_service.set_delivering(c.task_instance_id)
		return true

	var carcass = GameManager.wildlife_manager.find_nearest_carcass(c.pos, 500.0, c.citizen_id)
	if not carcass.is_empty():
		var c_path = GameManager.nav_grid.find_path(c.pos, carcass["pos"]) if GameManager.nav_grid else []
		if c_path.is_empty():
			if GameManager.task_service:
				var blocked_id = GameManager.task_service.create_task("harvest_carcass", carcass["id"], Vector2i(-1, -1), carcass["pos"])
				GameManager.task_service.fail_task(blocked_id, "Нет пути к туше", true)
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Нет пути к туше"
			c.decision_cooldown = randf_range(2.0, 4.0)
			return true
		GameManager.wildlife_manager.reserve_carcass(carcass["id"], c.citizen_id)
		c.task_id = "harvest_carcass"
		c.target_id = carcass["id"]
		c.target_pos = carcass["pos"]
		c.path = c_path
		c.path_index = 0
		c.state = CitizenNPC.State.MOVING_TO_WORK
		c.last_status_reason = "Идёт забирать тушу (%s)" % s._get_animal_display_name(carcass.get("type_id", carcass["species"]))
		c.decision_cooldown = 0.8
		if GameManager.task_service:
			var tid = GameManager.task_service.create_task("harvest_carcass", carcass["id"], Vector2i(-1, -1), carcass["pos"])
			GameManager.task_service.assign_actor(tid, c.citizen_id)
			c.task_instance_id = tid
		return true

	var target_animal = GameManager.wildlife_manager.find_nearest_hunt_target(c.pos, 1000.0, c.citizen_id)
	if target_animal != null:
		var a_path = GameManager.nav_grid.find_path(c.pos, target_animal.pos) if GameManager.nav_grid else []
		if a_path.is_empty():
			if GameManager.task_service:
				var blocked_id = GameManager.task_service.create_task("hunt_animal", target_animal.id, Vector2i(-1, -1), target_animal.pos)
				GameManager.task_service.fail_task(blocked_id, "Нет пути к добыче", true)
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Нет пути к добыче"
			c.decision_cooldown = randf_range(2.0, 4.0)
			return true
		if not GameManager.wildlife_manager.join_hunt_group(target_animal.id, c.citizen_id):
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Охотничья группа уже укомплектована"
			c.decision_cooldown = randf_range(2.0, 4.0)
			return true
		c.task_id = "hunt_animal"
		c.target_id = target_animal.id
		c.target_pos = target_animal.pos
		c.path = a_path
		c.path_index = 0
		c.action_timer = 0.0
		c.state = CitizenNPC.State.MOVING_TO_WORK
		c.last_status_reason = "Выслеживает %s" % s._get_animal_display_name(target_animal.type_id)
		c.decision_cooldown = 0.8
		if GameManager.task_service:
			var tid = GameManager.task_service.create_task("hunt_animal", target_animal.id, Vector2i(-1, -1), target_animal.pos)
			GameManager.task_service.assign_actor(tid, c.citizen_id)
			c.task_instance_id = tid
	else:
		var h_camp = s._get_hunting_camp_instance(c)
		if h_camp and h_camp.is_target_unlocked():
			c.state = CitizenNPC.State.WORKING
			c.work_timer = randf_range(3.0, 5.0)
			var xp_bonus = 0.5 * (1.35 if h_camp.is_mentor_unlocked() else 1.0)
			c.skill_hunter = minf(100.0, c.skill_hunter + xp_bonus)
			c.last_status_reason = "Тренируется на мишени у лагеря (Лук/Копьё XP +%.1f)" % xp_bonus
		else:
			c.state = CitizenNPC.State.WAITING
			c.last_status_reason = "Нет доступной добычи"
			c.decision_cooldown = randf_range(3.0, 5.0)
	return true

# Погоня за зверем и подход к туше. Движение охотника обрабатывается целиком здесь,
# чтобы общая логика движения не сдвигала его второй раз за кадр.
func on_moving(s: SettlementData, c: CitizenNPC, delta: float) -> bool:
	if c.state != CitizenNPC.State.MOVING_TO_WORK:
		return false
	if c.target_id.begins_with("carcass_"):
		var arrived_carcass = c.update_movement(delta)
		var reached_carcass = arrived_carcass
		if GameManager.wildlife_manager.carcasses.has(c.target_id):
			if c.pos.distance_to(GameManager.wildlife_manager.carcasses[c.target_id]["pos"]) <= 24.0:
				reached_carcass = true
		if reached_carcass:
			var h_res = GameManager.wildlife_manager.harvest_carcass(c.target_id, c.max_carry)
			GameManager.wildlife_manager.release_carcass(c.target_id, c.citizen_id)
			c.target_id = ""
			var meat = h_res.get("meat", 0.0) if h_res is Dictionary else float(h_res)
			# Шкура, мех, перья и кости не телепортируются на склад: охотник несёт их вместе с тушей
			var byproducts: Dictionary = h_res.get("byproducts", {}) if h_res is Dictionary else {}
			c.custom_data["hunt_byproducts"] = byproducts.duplicate()
			if meat > 0.0 or not byproducts.is_empty():
				c.cargo_type = "carcass"
				c.cargo_amount = meat
				c.add_work_xp("hunting_tracking", 0.6)
				var camp_p = s._find_hunting_camp_pos(c)
				c.path = GameManager.nav_grid.find_path(c.pos, camp_p)
				c.path_index = 0
				c.state = CitizenNPC.State.CARRYING
				c.last_status_reason = "Несёт тушу в охотничий лагерь" if meat > 0.0 else "Несёт снятую шкуру в охотничий лагерь"
			else:
				c.state = CitizenNPC.State.IDLE
				c.decision_cooldown = 1.0
		return true
	elif c.target_id != "":
		if not GameManager.wildlife_manager.animals.has(c.target_id):
			var group_carcass = GameManager.wildlife_manager.find_group_carcass_for_hunter(c.citizen_id)
			if not group_carcass.is_empty():
				c.target_id = group_carcass["id"]
				c.target_pos = group_carcass["pos"]
				c.path = GameManager.nav_grid.find_path(c.pos, c.target_pos)
				c.path_index = 0
				c.last_status_reason = "Идёт делить добычу группы"
			else:
				c.target_id = ""
				c.state = CitizenNPC.State.IDLE
				c.decision_cooldown = 1.0
			return true
		var animal = GameManager.wildlife_manager.animals[c.target_id]
		c.action_timer += delta

		# Проверка лимитов погони (ТЗ: не преследовать бесконечно через всю карту)
		var camp_p = s._find_hunting_camp_pos(c)
		var dist_from_camp = c.pos.distance_to(camp_p)
		var h_camp = s._get_hunting_camp_instance(c)
		var max_chase_dist = 1000.0 * (1.3 if (h_camp and h_camp.is_upgrade_unlocked("hunt_tracking")) else 1.0) * (h_camp.get_hunt_radius_mult() if h_camp else 1.0)
		if c.action_timer > 18.0 or dist_from_camp > max_chase_dist or animal.state == WildAnimal.State.SWIMMING:
			GameManager.wildlife_manager.release_animal(c.target_id, c.citizen_id)
			c.target_id = ""
			c.action_timer = 0.0
			c.state = CitizenNPC.State.IDLE
			c.decision_cooldown = 2.0
			c.last_status_reason = "Потерял добычу из виду" if animal.state != WildAnimal.State.SWIMMING else "Добыча спаслась на воде"
			return true

		var dist_to_animal = c.pos.distance_to(animal.pos)
		if dist_to_animal <= 70.0:
			c.path.clear()
			c.facing_dir = (animal.pos - c.pos).normalized()
			c.state = CitizenNPC.State.ATTACKING
			c.work_timer = 1.2
			c.last_status_reason = "Атакует %s" % s._get_animal_display_name(animal.type_id)
			return true
		else:
			if animal.pos.distance_to(c.target_pos) > 40.0:
				c.target_pos = animal.pos
				c.path = GameManager.nav_grid.find_path(c.pos, animal.pos)
				c.path_index = 0
			var hunter_spd = h_camp.get_hunter_speed_mult() if h_camp else 1.0
			var hunt_arrived = c.update_movement(delta * hunter_spd)
			if hunt_arrived and dist_to_animal > 70.0:
				c.target_pos = animal.pos
				c.path = GameManager.nav_grid.find_path(c.pos, animal.pos)
				c.path_index = 0
		return true
	return false

# Туша донесена до лагеря — начинается разделка
func on_cargo_delivered(s: SettlementData, c: CitizenNPC) -> bool:
	if c.cargo_type != "carcass":
		return false
	c.state = CitizenNPC.State.BUTCHERING
	var camp_inst = s._get_hunting_camp_instance(c)
	var speed_mult = camp_inst.get_butchering_speed_mult() if camp_inst else 1.0
	c.work_timer = 2.5 / speed_mult
	if camp_inst and camp_inst.is_upgrade_unlocked("hunt_campfire"):
		c.needs["rest"] = minf(100.0, c.needs.get("rest", 80.0) + 15.0)
		c.morale = minf(100.0, c.morale + 3.0)
	c.last_status_reason = "Разделывает добычу на оборудованной площадке" if (camp_inst and camp_inst.is_upgrade_unlocked("hunt_butcher_table")) else "Разделывает добычу в лагере"
	return true

# Разделка туши (состояние BUTCHERING): мясо в амбар, шкуры и кости — вместе с ним
func on_state_tick(s: SettlementData, c: CitizenNPC, delta: float) -> bool:
	if c.state != CitizenNPC.State.BUTCHERING:
		return false
	c.work_timer -= delta * c.get_work_speed_multiplier()
	if c.work_timer <= 0.0:
		var camp_inst = s._get_hunting_camp_instance(c)
		var meat_mult = camp_inst.get_meat_yield_mult() if camp_inst else 1.0
		var fur_bonus = camp_inst.get_fur_bonus() if camp_inst else 0
		var bone_bonus = camp_inst.get_bone_bonus() if camp_inst else 0
		# Бонусы площадки разделки зависят от реальной добычи: шкуру можно выделать лучше
		# только если она была снята с туши, кости — только если туша их дала
		var byproducts: Dictionary = c.custom_data.get("hunt_byproducts", {})
		if fur_bonus > 0 and (byproducts.has("leather") or byproducts.has("fur")):
			byproducts["leather"] = float(byproducts.get("leather", 0.0)) + float(fur_bonus)
		if bone_bonus > 0 and byproducts.has("bone"):
			byproducts["bone"] = float(byproducts.get("bone", 0.0)) + float(bone_bonus)
		c.custom_data["hunt_byproducts"] = byproducts
		var final_meat = c.cargo_amount * meat_mult
		c.cargo_type = "food"
		var is_smoked = camp_inst.is_smokehouse_unlocked() if camp_inst else false
		var freshness = 22500.0 if is_smoked else 4500.0
		c.cargo_batch = {
			"food_type": "smoked_meat" if is_smoked else "meat",
			"amount": final_meat,
			"created_sim_time": GameManager.sim_time_total,
			"max_freshness_sec": freshness,
			"spoilage_progress": 0.0
		}
		c.state = CitizenNPC.State.CARRYING
		var dest_p = s._get_storage_pos(c)
		c.path = GameManager.nav_grid.find_path(c.pos, dest_p)
		c.path_index = 0
		c.last_status_reason = "Несёт %d копчёного мяса в амбар" % int(final_meat) if is_smoked else "Несёт %d еды в амбар" % int(final_meat)
		var extras_txt = s._format_hunt_byproducts(byproducts)
		if extras_txt != "":
			c.last_status_reason += " и " + extras_txt
		if GameManager.task_service and c.task_instance_id != "":
			GameManager.task_service.set_delivering(c.task_instance_id)
	return true
