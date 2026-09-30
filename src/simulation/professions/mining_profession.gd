class_name MiningProfession
extends ProfessionBehavior

# ==============================================================================
# КАМЕНОТЁС И РУДОКОП: поиск породы -> удары кайлом -> переноска на склад.
# Что добыто, определяет сама порода (камень из валуна, руда из жилы).
# ==============================================================================

const CONFIG: Dictionary = {
	"quarryman": {
		"category": "stone", "task": "mine_stone",
		"radius": 16, "far_radius": 36,
		"carry_word": "камня", "no_path": "Нет пути к камню",
		"going": "Идёт добывать: %s", "none": "Нет доступного камня"
	},
	"miner": {
		"category": "metal", "task": "mine_ore",
		"radius": 20, "far_radius": 40,
		"carry_word": "руды", "no_path": "Нет пути к руде",
		"going": "Идёт к: %s", "none": "Нет доступных жил руды"
	}
}

const STRIKE_AMOUNT: float = 4.0

func get_job_ids() -> Array[String]:
	return ["quarryman", "miner"]

func pick_task(s: SettlementData, c: CitizenNPC, _delta: float) -> bool:
	if not is_working_age(c):
		return false
	var cfg: Dictionary = CONFIG[c.job_id]
	if c.cargo_amount >= c.max_carry:
		send_to(c, s._get_storage_pos(c), CitizenNPC.State.CARRYING, "Несёт %d %s на склад" % [int(c.cargo_amount), cfg["carry_word"]])
		if GameManager.task_service and c.task_instance_id != "":
			GameManager.task_service.set_delivering(c.task_instance_id)
		return true
	var rock = GameManager.resource_manager.find_available_node(s.pos, cfg["category"], cfg["radius"], c.citizen_id)
	if rock.is_empty():
		rock = GameManager.resource_manager.find_available_node(s.pos, cfg["category"], cfg["far_radius"], c.citizen_id)
	if rock.is_empty():
		c.state = CitizenNPC.State.WAITING
		c.last_status_reason = cfg["none"]
		c.decision_cooldown = randf_range(3.0, 5.0)
		return true
	var r_path = GameManager.nav_grid.find_adjacent_path(c.pos, rock["coord"]) if GameManager.nav_grid else []
	if r_path.is_empty():
		if GameManager.task_service:
			var blocked_id = GameManager.task_service.create_task(cfg["task"], rock.get("id", ""), rock["coord"], rock["pos"])
			GameManager.task_service.fail_task(blocked_id, cfg["no_path"], true)
		c.state = CitizenNPC.State.WAITING
		c.last_status_reason = cfg["no_path"]
		c.decision_cooldown = randf_range(2.0, 4.0)
		return true
	GameManager.resource_manager.reserve_node(rock["coord"], c.citizen_id)
	c.task_id = cfg["task"]
	c.target_coord = rock["coord"]
	c.target_pos = r_path[-1]
	c.target_id = rock["id"]
	c.path = r_path
	c.path_index = 0
	c.state = CitizenNPC.State.MOVING_TO_WORK
	c.last_status_reason = cfg["going"] % rock["name"]
	c.decision_cooldown = 0.8
	if GameManager.task_service:
		var tid = GameManager.task_service.create_task(cfg["task"], rock["id"], rock["coord"], rock["pos"])
		GameManager.task_service.assign_actor(tid, c.citizen_id)
		c.task_instance_id = tid
	return true

func on_arrived(s: SettlementData, c: CitizenNPC) -> bool:
	c.state = CitizenNPC.State.WORKING
	c.work_timer = randf_range(3.0, 4.5)
	c.last_status_reason = s._get_job_action_name(c.job_id)
	start_task_timer(c)
	return true

func on_work_done(s: SettlementData, c: CitizenNPC) -> bool:
	var res_cat: String = CONFIG[c.job_id]["category"]
	var h_amount = 0.0
	if c.target_coord != Vector2i(-1, -1) and GameManager.resource_manager:
		var rock_node = GameManager.resource_manager.nodes.get(c.target_coord, {})
		res_cat = rock_node.get("category", res_cat)
		h_amount = GameManager.resource_manager.harvest_from_node(c.target_coord, STRIKE_AMOUNT)
		GameManager.resource_manager.release_node(c.target_coord, c.citizen_id)
	if h_amount > 0.0:
		c.cargo_type = res_cat
		c.cargo_amount = h_amount
		c.add_work_xp("ore_mining" if res_cat == "metal" else "stone_mining", 0.3)
	c.target_coord = Vector2i(-1, -1)
	send_to(c, s._get_storage_pos(c), CitizenNPC.State.CARRYING, "Несёт %d %s на склад" % [int(c.cargo_amount), "руды" if c.cargo_type == "metal" else "камня"])
	if GameManager.task_service and c.task_instance_id != "":
		GameManager.task_service.set_delivering(c.task_instance_id)
	return true
