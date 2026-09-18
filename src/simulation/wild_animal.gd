class_name WildAnimal
extends RefCounted


enum State {
	GRAZING,
	RESTING,
	FOLLOWING,
	FLEEING,
	DEFENDING,
	HUNTING_PREY,
	SWIMMING,
	DEAD
}

# 24 вида и варианта животных
const SPECIES_CONFIG: Dictionary = {
	# Ряд 1: Волки и зайцы
	"wolf_grey": {"species": "wolf", "variant": "grey", "is_child": false, "hp": 65.0, "dmg": 12.0, "armor": 0.0,  "atk_interval": 1.3, "speed_mult": 1.65, "food": 4.0, "mat": "fur", "mat_count": 2, "detect": 140.0, "behavior": "predator"},
	"wolf_dark": {"species": "wolf", "variant": "dark", "is_child": false, "hp": 65.0, "dmg": 12.0, "armor": 0.0,  "atk_interval": 1.3, "speed_mult": 1.65, "food": 4.0, "mat": "fur", "mat_count": 2, "detect": 140.0, "behavior": "predator"},
	"wolf_pup":  {"species": "wolf", "variant": "pup",  "is_child": true,  "hp": 20.0, "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.10, "food": 1.0, "mat": "",    "mat_count": 0, "detect": 120.0, "behavior": "child"},
	"hare_brown":    {"species": "hare", "variant": "brown",    "is_child": false, "hp": 12.0, "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.85, "food": 2.0, "mat": "small_hide", "mat_count": 1, "detect": 160.0, "behavior": "skittish"},
	"hare_white":    {"species": "hare", "variant": "white",    "is_child": false, "hp": 12.0, "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.85, "food": 2.0, "mat": "small_hide", "mat_count": 1, "detect": 160.0, "behavior": "skittish"},
	"hare_leveret":  {"species": "hare", "variant": "leveret",  "is_child": true,  "hp": 6.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.25, "food": 1.0, "mat": "",           "mat_count": 0, "detect": 130.0, "behavior": "child"},

	# Ряд 2: Олени и лоси
	"deer_stag": {"species": "deer", "variant": "stag", "is_child": false, "hp": 85.0,  "dmg": 16.0, "armor": 0.0,  "atk_interval": 1.8, "speed_mult": 1.75, "food": 12.0, "mat": "hide",       "mat_count": 2, "detect": 150.0, "behavior": "herbivore_defensive"},
	"deer_doe":  {"species": "deer", "variant": "doe",  "is_child": false, "hp": 70.0,  "dmg": 10.0, "armor": 0.0,  "atk_interval": 1.8, "speed_mult": 1.75, "food": 10.0, "mat": "hide",       "mat_count": 2, "detect": 150.0, "behavior": "mother"},
	"deer_fawn": {"species": "deer", "variant": "fawn", "is_child": true,  "hp": 25.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.20, "food": 3.0,  "mat": "small_hide", "mat_count": 1, "detect": 120.0, "behavior": "child"},
	"moose_bull": {"species": "moose", "variant": "bull", "is_child": false, "hp": 160.0, "dmg": 28.0, "armor": 5.0,  "atk_interval": 2.0, "speed_mult": 1.55, "food": 22.0, "mat": "hide",       "mat_count": 3, "detect": 140.0, "behavior": "defensive"},
	"moose_cow":  {"species": "moose", "variant": "cow",  "is_child": false, "hp": 140.0, "dmg": 24.0, "armor": 5.0,  "atk_interval": 2.0, "speed_mult": 1.55, "food": 20.0, "mat": "hide",       "mat_count": 3, "detect": 140.0, "behavior": "mother_aggressive"},
	"moose_calf": {"species": "moose", "variant": "calf", "is_child": true,  "hp": 40.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.10, "food": 5.0,  "mat": "small_hide", "mat_count": 1, "detect": 120.0, "behavior": "child"},

	# Ряд 3: Медведи и кабаны
	"bear_brown": {"species": "bear", "variant": "brown", "is_child": false, "hp": 240.0, "dmg": 32.0, "armor": 10.0, "atk_interval": 2.2, "speed_mult": 1.45, "food": 24.0, "mat": "fur",  "mat_count": 3, "detect": 110.0, "behavior": "territorial"},
	"bear_dark":  {"species": "bear", "variant": "dark",  "is_child": false, "hp": 240.0, "dmg": 32.0, "armor": 10.0, "atk_interval": 2.2, "speed_mult": 1.45, "food": 24.0, "mat": "fur",  "mat_count": 3, "detect": 110.0, "behavior": "territorial"},
	"bear_cub":   {"species": "bear", "variant": "cub",   "is_child": true,  "hp": 55.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.00, "food": 5.0,  "mat": "fur",  "mat_count": 1, "detect": 100.0, "behavior": "child"},
	"boar_male":   {"species": "boar", "variant": "male",   "is_child": false, "hp": 110.0, "dmg": 20.0, "armor": 8.0,  "atk_interval": 1.6, "speed_mult": 1.50, "food": 14.0, "mat": "hide", "mat_count": 2, "detect": 130.0, "behavior": "defensive"},
	"boar_female": {"species": "boar", "variant": "female", "is_child": false, "hp": 100.0, "dmg": 18.0, "armor": 8.0,  "atk_interval": 1.6, "speed_mult": 1.50, "food": 12.0, "mat": "hide", "mat_count": 2, "detect": 130.0, "behavior": "mother_aggressive"},
	"boar_piglet": {"species": "boar", "variant": "piglet", "is_child": true,  "hp": 25.0,  "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.15, "food": 3.0,  "mat": "",     "mat_count": 0, "detect": 110.0, "behavior": "child"},

	# Ряд 4: Хищники, барсук и водоплавающие утки
	"fox_adult":   {"species": "fox", "variant": "adult", "is_child": false, "hp": 30.0, "dmg": 5.0,  "armor": 0.0,  "atk_interval": 1.2, "speed_mult": 1.65, "food": 2.0, "mat": "fur",        "mat_count": 1, "detect": 150.0, "behavior": "cunning_predator"},
	"fox_kit":     {"species": "fox", "variant": "kit",   "is_child": true,  "hp": 12.0, "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 1.10, "food": 1.0, "mat": "",           "mat_count": 0, "detect": 120.0, "behavior": "child"},
	"lynx_adult":  {"species": "lynx", "variant": "adult", "is_child": false, "hp": 70.0, "dmg": 15.0, "armor": 0.0,  "atk_interval": 1.4, "speed_mult": 1.70, "food": 4.0, "mat": "fur",        "mat_count": 2, "detect": 160.0, "behavior": "stealth_predator"},
	"badger_adult":{"species": "badger", "variant": "adult", "is_child": false, "hp": 45.0, "dmg": 9.0, "armor": 5.0,  "atk_interval": 1.5, "speed_mult": 0.95, "food": 3.0, "mat": "small_hide", "mat_count": 1, "detect": 100.0, "behavior": "nocturnal"},
	"drake":       {"species": "duck", "variant": "drake", "is_child": false, "hp": 10.0, "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 0.75, "food": 2.0, "mat": "feathers",   "mat_count": 1, "detect": 140.0, "behavior": "waterfowl"},
	"duck":        {"species": "duck", "variant": "duck",  "is_child": false, "hp": 10.0, "dmg": 0.0,  "armor": 0.0,  "atk_interval": 2.0, "speed_mult": 0.75, "food": 2.0, "mat": "feathers",   "mat_count": 1, "detect": 140.0, "behavior": "waterfowl"}
}

var id: String = ""
var type_id: String = "hare_brown"
var species: String = "hare"
var variant: String = "brown"
var is_child: bool = false
var parent_id: String = ""
var pack_id: String = ""

var pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var facing_dir: Vector2 = Vector2.RIGHT
var health: float = 12.0
var max_health: float = 12.0
var armor: float = 0.0
var attack_damage: float = 0.0
var attack_interval: float = 2.0
var attack_timer: float = 0.0
var state: int = State.GRAZING
var move_speed: float = 32.0 # 1.0x human speed (32 px/s)
var speed_multiplier: float = 1.85
var detect_radius: float = 160.0
var flee_timer: float = 0.0
var meat_yield: float = 2.0
var extra_material: String = "small_hide"
var extra_material_count: int = 1
var reserved_by: String = ""

var action_timer: float = 0.0
var wander_cooldown: float = 0.0
var wobble_timer: float = 0.0
var flee_from_pos: Vector2 = Vector2.ZERO
var home_coord: Vector2i = Vector2i.ZERO
var target_threat_id: String = ""
var target_threat_pos: Vector2 = Vector2.ZERO
var target_citizen = null

# Учёт урона от охотников/граждан для распределения опыта при добыче
var attackers_damage: Dictionary = {}

var cached_texture: Texture2D = null

func _init(p_id: String = "", p_type: String = "hare_brown", p_pos: Vector2 = Vector2.ZERO) -> void:
	id = p_id
	type_id = p_type if SPECIES_CONFIG.has(p_type) else "hare_brown"
	pos = p_pos
	target_pos = p_pos
	home_coord = Vector2i(int(p_pos.x / 32.0), int(p_pos.y / 32.0))
	_apply_species_stats()

func _apply_species_stats() -> void:
	var cfg = SPECIES_CONFIG.get(type_id, SPECIES_CONFIG["hare_brown"])
	species = cfg["species"]
	variant = cfg["variant"]
	is_child = cfg["is_child"]
	health = cfg["hp"]
	max_health = cfg["hp"]
	armor = cfg.get("armor", 0.0)
	attack_damage = cfg["dmg"]
	attack_interval = cfg["atk_interval"]
	speed_multiplier = cfg["speed_mult"]
	meat_yield = cfg["food"]
	extra_material = cfg["mat"]
	extra_material_count = cfg["mat_count"]
	detect_radius = cfg["detect"]

func get_combat_stats() -> Dictionary:
	return CombatStatsResolver.calculate_animal_stats(type_id)

func get_texture() -> Texture2D:
	if cached_texture:
		return cached_texture
	var path = "res://Assets/animals/%s.png" % type_id
	if ResourceLoader.exists(path):
		cached_texture = load(path)
		return cached_texture
	# Fallback
	if species == "hare":
		return load("res://Assets/animals/hare_brown.png")
	elif species == "deer":
		return load("res://Assets/animals/deer_stag.png")
	return null

func get_scale() -> float:
	if is_child:
		return 0.70
	if species in ["moose", "bear"]:
		return 1.15
	if species in ["boar", "deer"]:
		return 1.00
	if species in ["wolf", "fox", "lynx"]:
		return 0.90
	if species in ["badger", "hare", "duck"]:
		return 0.80
	return 1.00

func get_speed() -> float:
	var base = 32.0
	match state:
		State.FLEEING, State.DEFENDING:
			return base * speed_multiplier
		State.SWIMMING:
			return base * 0.90
		State.FOLLOWING:
			return base * minf(speed_multiplier, 1.25)
		_: # GRAZING / RESTING
			return base * 0.45

func update(delta: float, nav_grid, threat_positions: Array, parent_animal = null) -> void:
	if state == State.DEAD:
		return
		
	wobble_timer += delta * 6.0
	if attack_timer > 0.0:
		attack_timer -= delta
		
	var cfg = SPECIES_CONFIG.get(type_id, SPECIES_CONFIG["hare_brown"])
	var behavior = cfg.get("behavior", "skittish")
	
	# 1. Проверка обнаружения угрозы (охотника или враждебного хищника)
	var threat_spotted = false
	var nearest_threat_pos = Vector2.ZERO
	var spotted_citizen = null
	var min_threat_dist = detect_radius
	
	for t in threat_positions:
		var t_pos = Vector2.ZERO
		var t_c = null
		if t is Vector2:
			t_pos = t
		elif t is Dictionary:
			t_pos = t.get("pos", Vector2.ZERO)
			t_c = t.get("citizen", null)
			
		var d = pos.distance_to(t_pos)
		if d < min_threat_dist:
			min_threat_dist = d
			nearest_threat_pos = t_pos
			spotted_citizen = t_c
			threat_spotted = true
			
	# Поведение при обнаружении угрозы
	if threat_spotted:
		if behavior in ["mother_aggressive", "defensive", "territorial", "predator", "pack_predator", "stealth_predator", "cunning_predator"] and min_threat_dist < 80.0:
			# Контратака / нападение при сближении!
			state = State.DEFENDING
			target_threat_pos = nearest_threat_pos
			target_citizen = spotted_citizen
			facing_dir = (nearest_threat_pos - pos).normalized()
		elif behavior == "waterfowl":
			# Утка спасается на воде!
			state = State.SWIMMING
			flee_from_pos = nearest_threat_pos
			flee_timer = 5.0
			_seek_water_tile(nav_grid)
		else:
			# Обычное бегство от угрозы
			state = State.FLEEING
			flee_from_pos = nearest_threat_pos
			flee_timer = randf_range(3.5, 6.0)
			
			var flee_dir = (pos - nearest_threat_pos).normalized()
			if flee_dir.length_squared() < 0.01:
				flee_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			facing_dir = flee_dir
			
			var test_target = pos + flee_dir * randf_range(70.0, 140.0)
			if nav_grid:
				var target_tile = nav_grid.world_pos_to_tile(test_target)
				if nav_grid.is_tile_walkable(target_tile):
					target_pos = test_target
				else:
					var alt_tile = nav_grid.find_random_walkable_nearby(nav_grid.world_pos_to_tile(pos), 3)
					target_pos = nav_grid.tile_to_world_center(alt_tile)
			else:
				target_pos = test_target

	# 2. Поведение детёныша: следование за матерью/лидером
	if is_child and parent_animal != null and parent_animal.is_alive():
		var dist_to_parent = pos.distance_to(parent_animal.pos)
		if state not in [State.FLEEING, State.DEAD] and dist_to_parent > 35.0:
			state = State.FOLLOWING
			target_pos = parent_animal.pos + Vector2(randf_range(-14, 14), randf_range(-14, 14))

	# 3. Обработка состояний
	match state:
		State.DEFENDING:
			# Сближение для удара
			var to_threat = target_threat_pos - pos
			var d_threat = to_threat.length()
			if d_threat > 20.0:
				var step = to_threat.normalized() * minf(get_speed() * delta, d_threat)
				pos += step
				facing_dir = to_threat.normalized()
			else:
				if attack_timer <= 0.0:
					attack_timer = attack_interval
					if target_citizen != null and is_instance_valid(target_citizen) and "health" in target_citizen and target_citizen.health > 0:
						var a_stats = get_combat_stats()
						var c_stats = target_citizen.get_combat_stats() if target_citizen.has_method("get_combat_stats") else {"armor": 0.0}
						var outcome = CombatStatsResolver.resolve_attack(a_stats, c_stats)
						if outcome["is_hit"]:
							var final_dmg = outcome["damage"]
							var died = target_citizen.take_damage(final_dmg, cfg.get("name", "Зверь"))
							if EventBus:
								EventBus.notification_toast.emit("Нападение хищника!", "%s нанёс %d урона жителю %s!" % [cfg.get("name", "Зверь"), int(final_dmg), target_citizen.name], "danger")
						
						# Ответный удар защищающегося жителя (охотника или воина)
						if target_citizen.job_id in ["hunter", "guard", "warrior"]:
							var ret_stats = target_citizen.get_combat_stats() if target_citizen.has_method("get_combat_stats") else {"raw_damage": 16.0, "accuracy": 0.85, "pen_fraction": 0.0, "pen_flat": 0.0}
							var def_stats = get_combat_stats()
							var ret_outcome = CombatStatsResolver.resolve_attack(ret_stats, def_stats)
							var counter_dmg = ret_outcome["damage"] if ret_outcome["is_hit"] else maxi(1, int(round(ret_stats.get("raw_damage", 5.0))))
							take_damage(counter_dmg, target_citizen.citizen_id)
			if min_threat_dist > 140.0:
				state = State.GRAZING
				target_citizen = null
				
		State.SWIMMING:
			# Плавание утки по воде
			flee_timer -= delta
			var to_target = target_pos - pos
			var dist = to_target.length()
			if dist > 3.0:
				pos += to_target.normalized() * minf(get_speed() * delta, dist)
			else:
				if flee_timer <= 0.0 and not threat_spotted:
					state = State.GRAZING
					wander_cooldown = randf_range(3.0, 6.0)

		State.FLEEING:
			flee_timer -= delta
			var speed = get_speed()
			var to_target = target_pos - pos
			var dist = to_target.length()
			
			if dist > 3.0:
				pos += to_target.normalized() * minf(speed * delta, dist)
				if to_target.x != 0.0:
					facing_dir = Vector2.RIGHT if to_target.x > 0 else Vector2.LEFT
			else:
				if flee_timer > 0.0:
					var further_dir = (pos - flee_from_pos).normalized()
					var next_pos = pos + further_dir * 60.0
					if nav_grid:
						var n_tile = nav_grid.world_pos_to_tile(next_pos)
						if nav_grid.is_tile_walkable(n_tile):
							target_pos = next_pos
					else:
						target_pos = next_pos
						
			if flee_timer <= 0.0 and not threat_spotted:
				state = State.GRAZING
				wander_cooldown = randf_range(2.0, 4.0)

		State.FOLLOWING:
			var to_parent = target_pos - pos
			var dist = to_parent.length()
			if dist > 4.0:
				pos += to_parent.normalized() * minf(get_speed() * delta, dist)
				if to_parent.x != 0.0:
					facing_dir = Vector2.RIGHT if to_parent.x > 0 else Vector2.LEFT
			else:
				state = State.GRAZING
				wander_cooldown = randf_range(1.5, 3.5)

		State.GRAZING:
			wander_cooldown -= delta
			var to_target = target_pos - pos
			var dist = to_target.length()
			
			if dist > 3.0:
				pos += to_target.normalized() * minf(get_speed() * delta, dist)
				if to_target.x != 0.0:
					facing_dir = Vector2.RIGHT if to_target.x > 0 else Vector2.LEFT
			else:
				if wander_cooldown <= 0.0:
					wander_cooldown = randf_range(4.0, 8.0)
					if nav_grid:
						var cur_tile = nav_grid.world_pos_to_tile(pos)
						var wander_tile = nav_grid.find_random_walkable_nearby(cur_tile, 2)
						target_pos = nav_grid.tile_to_world_center(wander_tile) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
					else:
						target_pos = pos + Vector2(randf_range(-30, 30), randf_range(-30, 30))

func _seek_water_tile(nav_grid) -> void:
	if not nav_grid:
		return
	var cur_tile = nav_grid.world_pos_to_tile(pos)
	for r in range(1, 6):
		for dx in range(-r, r+1):
			for dy in range(-r, r+1):
				var check_t = cur_tile + Vector2i(dx, dy)
				if nav_grid.is_water_tile(check_t):
					target_pos = nav_grid.tile_to_world_center(check_t)
					return

func take_damage(amount: float, attacker_id: String) -> bool:
	health -= amount
	if attacker_id != "":
		attackers_damage[attacker_id] = attackers_damage.get(attacker_id, 0.0) + amount
	var cfg = SPECIES_CONFIG.get(type_id, SPECIES_CONFIG["hare_brown"])
	var behavior = cfg.get("behavior", "skittish")
	
	if behavior in ["mother_aggressive", "defensive", "territorial", "predator", "pack_predator", "stealth_predator", "cunning_predator"] and health > max_health * 0.25:
		state = State.DEFENDING
	else:
		state = State.FLEEING
		flee_timer = 6.0
		
	if health <= 0.0:
		health = 0.0
		state = State.DEAD
		return true
	return false

func is_alive() -> bool:
	return state != State.DEAD and health > 0.0

func serialize() -> Dictionary:
	return {
		"id": id,
		"type_id": type_id,
		"species": species,
		"variant": variant,
		"is_child": is_child,
		"parent_id": parent_id,
		"pack_id": pack_id,
		"pos_x": pos.x,
		"pos_y": pos.y,
		"target_pos_x": target_pos.x,
		"target_pos_y": target_pos.y,
		"health": health,
		"max_health": max_health,
		"state": state,
		"move_speed": move_speed,
		"detect_radius": detect_radius,
		"meat_yield": meat_yield,
		"extra_material": extra_material,
		"extra_material_count": extra_material_count,
		"reserved_by": reserved_by,
		"home_coord_x": home_coord.x,
		"home_coord_y": home_coord.y,
		"armor": armor,
		"attackers_damage": attackers_damage
	}

func deserialize(data: Dictionary) -> void:
	id = data.get("id", "")
	type_id = data.get("type_id", "hare_brown")
	_apply_species_stats()
	species = data.get("species", species)
	variant = data.get("variant", variant)
	is_child = data.get("is_child", is_child)
	parent_id = data.get("parent_id", "")
	pack_id = data.get("pack_id", "")
	pos = Vector2(data.get("pos_x", 0.0), data.get("pos_y", 0.0))
	target_pos = Vector2(data.get("target_pos_x", pos.x), data.get("target_pos_y", pos.y))
	health = float(data.get("health", health))
	max_health = float(data.get("max_health", max_health))
	armor = float(data.get("armor", armor))
	state = int(data.get("state", State.GRAZING))
	move_speed = float(data.get("move_speed", move_speed))
	detect_radius = float(data.get("detect_radius", detect_radius))
	meat_yield = float(data.get("meat_yield", meat_yield))
	extra_material = data.get("extra_material", extra_material)
	extra_material_count = int(data.get("extra_material_count", extra_material_count))
	reserved_by = data.get("reserved_by", "")
	home_coord = Vector2i(int(data.get("home_coord_x", 0)), int(data.get("home_coord_y", 0)))
	attackers_damage = data.get("attackers_damage", {})
