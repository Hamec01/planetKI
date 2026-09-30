class_name NPCRelationshipGraph
extends RefCounted

# ==============================================================================
# ГРАФ СОЦИАЛЬНЫХ СВЯЗЕЙ И КЛИК NPC (PLANETKI / ТЗ РАЗДЕЛ 3)
# ==============================================================================

class NPCClique:
	var id: String = ""
	var name: String = ""
	var type: String = "interest" # "elders", "hunters", "rebels", "workers", "youth", "devout"
	var leader_id: String = ""
	var member_ids: Array[String] = []
	var cohesion: float = 75.0 # 0..100
	var shared_opinion_stance: String = "neutral"
	var custom_data: Dictionary = {}
	
	func _init(p_id: String, p_name: String, p_type: String, p_leader_id: String) -> void:
		id = p_id
		name = p_name
		type = p_type
		leader_id = p_leader_id
		member_ids = [p_leader_id]

var settlement_id: String = ""
var cliques: Dictionary = {} # clique_id -> NPCClique
var update_timer: float = 0.0

func _init(p_settlement_id: String = "") -> void:
	settlement_id = p_settlement_id

func update(delta: float, settlement: RefCounted) -> void:
	if settlement == null:
		return
		
	update_timer += delta
	if update_timer >= 30.0: # Обновление структуры клик каждые 30 сек
		update_timer = 0.0
		_recalculate_cliques(settlement)
		_check_dissident_cells(settlement)

func get_cliques() -> Array:
	return cliques.values()

func get_clique(clique_id: String) -> NPCClique:
	return cliques.get(clique_id, null)

func get_citizen_clique(citizen_id: String) -> NPCClique:
	for cl in cliques.values():
		if cl.member_ids.has(citizen_id):
			return cl
	return null

func _recalculate_cliques(settlement: RefCounted) -> void:
	var citizens_list: Array = settlement.citizens.values() if settlement.citizens is Dictionary else settlement.citizens
	if citizens_list.is_empty():
		cliques.clear()
		return
		
	var active_cliques: Dictionary = {}
	
	# 1. Круг старейшин (elders)
	var elder_members: Array[String] = []
	var elder_leader = ""
	var max_elder_ambition = -1.0
	for c in citizens_list:
		if c != null and c.is_alive and c.cohort == "elder":
			elder_members.append(c.citizen_id)
			var amb = float(c.traits.get("ambition", 50.0))
			if amb > max_elder_ambition:
				max_elder_ambition = amb
				elder_leader = c.citizen_id
				
	if elder_members.size() >= 2:
		var c_id = "clique_elders_%s" % settlement_id
		var cl = NPCClique.new(c_id, "Совет Старейшин", "elders", elder_leader)
		cl.member_ids = elder_members
		active_cliques[c_id] = cl
		if not cliques.has(c_id):
			EventBus.npc_clique_formed.emit(c_id, "elders", elder_members)
			
	# 2. Охотничье братство (hunters)
	var hunter_members: Array[String] = []
	var hunter_leader = ""
	var max_hunter_skill = -1.0
	for c in citizens_list:
		if c != null and c.is_alive and (c.job_id == "hunter" or c.get_personality_archetype() == "fighter"):
			hunter_members.append(c.citizen_id)
			var h_lvl = float(c.skills.get("hunter", 0.0)) + float(c.traits.get("bravery", 50.0))
			if h_lvl > max_hunter_skill:
				max_hunter_skill = h_lvl
				hunter_leader = c.citizen_id
				
	if hunter_members.size() >= 2:
		var c_id = "clique_hunters_%s" % settlement_id
		var cl = NPCClique.new(c_id, "Охотничья Дружина", "hunters", hunter_leader)
		cl.member_ids = hunter_members
		active_cliques[c_id] = cl
		if not cliques.has(c_id):
			EventBus.npc_clique_formed.emit(c_id, "hunters", hunter_members)

	# 3. Артель строителей и ремесленников (workers)
	var worker_members: Array[String] = []
	var worker_leader = ""
	var max_worker_dil = -1.0
	for c in citizens_list:
		if c != null and c.is_alive and (c.job_id in ["builder", "woodcutter", "stonecutter", "miner"]):
			worker_members.append(c.citizen_id)
			var dil = float(c.traits.get("diligence", 50.0))
			if dil > max_worker_dil:
				max_worker_dil = dil
				worker_leader = c.citizen_id
				
	if worker_members.size() >= 3:
		var c_id = "clique_workers_%s" % settlement_id
		var cl = NPCClique.new(c_id, "Артель Мастеровых", "workers", worker_leader)
		cl.member_ids = worker_members
		active_cliques[c_id] = cl
		if not cliques.has(c_id):
			EventBus.npc_clique_formed.emit(c_id, "workers", worker_members)
			
	cliques = active_cliques

func _check_dissident_cells(settlement: RefCounted) -> void:
	var citizens_list: Array = settlement.citizens.values() if settlement.citizens is Dictionary else settlement.citizens
	var dissidents: Array[String] = []
	var dissident_leader = ""
	var max_rebel_power = -1.0
	
	for c in citizens_list:
		if c != null and c.is_alive and c.loyalty < 40.0:
			dissidents.append(c.citizen_id)
			var rebel_power = (100.0 - c.loyalty) + float(c.traits.get("temper", 50.0)) + float(c.traits.get("ambition", 50.0))
			if rebel_power > max_rebel_power:
				max_rebel_power = rebel_power
				dissident_leader = c.citizen_id
				
	if dissidents.size() >= 3:
		var c_id = "clique_rebels_%s" % settlement_id
		var cl = NPCClique.new(c_id, "Круг Недовольных", "rebels", dissident_leader)
		cl.member_ids = dissidents
		cliques[c_id] = cl
		
		# Оповещаем об угрозе бунта
		EventBus.npc_revolt_risk.emit(settlement_id, dissidents.size(), dissident_leader)
