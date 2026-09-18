class_name BattleInstance
extends RefCounted


var id: String = ""
var battle_name: String = "Схватка у Каменного Брода"
var pos: Vector2i = Vector2i.ZERO
var terrain_name: String = "Равнина"

var attacker_faction: String = ""
var defender_faction: String = ""
var attacker_army: RefCounted
var defender_army: RefCounted

var current_round: int = 0
var max_rounds: int = 5
var is_finished: bool = false
var victory: bool = false

var chronicle: Array[String] = []

func _init(p_id: String = "", p_pos: Vector2i = Vector2i.ZERO, p_att: RefCounted = null, p_def: RefCounted = null, p_terrain: String = "Холмистая долина") -> void:
	id = p_id
	pos = p_pos
	attacker_army = p_att
	defender_army = p_def
	if p_att:
		attacker_faction = p_att.faction_id
	if p_def:
		defender_faction = p_def.faction_id
	terrain_name = p_terrain
	
	battle_name = "Битва у " + terrain_name + " (Коорд. %d:%d)" % [pos.x, pos.y]
	chronicle.append("06:00 — Стороны развернули боевые порядки на местности [%s]." % terrain_name)

func advance_round() -> Dictionary:
	if is_finished or attacker_army == null or defender_army == null:
		return {"finished": true, "victory": victory}
		
	current_round += 1
	var round_time = "%02d:00" % (6 + current_round * 2)
	
	var att_power = attacker_army.get_power_rating()
	var def_power = defender_army.get_power_rating()
	
	# Тактика атакующего генерала
	var att_gen = attacker_army.general
	var def_gen = defender_army.general
	
	var att_name = att_gen.get("name", "Командир атакующих")
	var _def_name = def_gen.get("name", "Командир защитников")
	
	var att_losses = 0
	var def_losses = 0
	var event_text = ""
	
	if att_gen.get("cunning", 50) > 70 and current_round == 1:
		event_text = "%s организует ложный отход и заводит врага под обстрел скрытых лучников!" % att_name
		def_losses = int(def_power * 0.08) + 2
		def_army_apply_losses(def_losses)
	elif att_gen.get("bravery", 50) > 80:
		event_text = "%s лично ведет воинов в яростный натиск на центр вражеского строя!" % att_name
		att_losses = int(att_power * 0.06) + 1
		def_losses = int(def_power * 0.07) + 2
		att_army_apply_losses(att_losses)
		def_army_apply_losses(def_losses)
	else:
		event_text = "Стрелки осыпают ряды врага градом стрел; копейщики сдерживают фланговые манёвры."
		att_losses = int(att_power * 0.04) + 1
		def_losses = int(def_power * 0.04) + 1
		att_army_apply_losses(att_losses)
		def_army_apply_losses(def_losses)
		
	chronicle.append("%s — %s (Потери: атакующие -%d, защитники -%d)" % [round_time, event_text, att_losses, def_losses])
	
	# Проверка морали и исхода
	if defender_army.get_total_soldiers() <= 3 or defender_army.morale <= 25.0:
		is_finished = true
		victory = (attacker_faction == GameManager.player_faction_id)
		chronicle.append("18:30 — Защитники сломлены и в беспорядке отступают с поля боя!")
	elif attacker_army.get_total_soldiers() <= 3 or attacker_army.morale <= 25.0:
		is_finished = true
		victory = (defender_faction == GameManager.player_faction_id)
		chronicle.append("18:30 — Атакующие исчерпали силы и вынуждены прекратить штурм!")
	elif current_round >= max_rounds:
		is_finished = true
		victory = (att_power > def_power) if attacker_faction == GameManager.player_faction_id else (def_power > att_power)
		chronicle.append("20:00 — С наступлением сумерек стороны разошлись на исходные позиции.")
		
	return {
		"round": current_round,
		"finished": is_finished,
		"victory": victory,
		"chronicle": chronicle
	}

func att_army_apply_losses(loss: int) -> void:
	if attacker_army == null: return
	attacker_army.spearmen = max(0, attacker_army.spearmen - int(loss * 0.4))
	attacker_army.archers = max(0, attacker_army.archers - int(loss * 0.3))
	attacker_army.warriors = max(0, attacker_army.warriors - int(loss * 0.3))
	attacker_army.morale = clampf(attacker_army.morale - loss * 1.5, 10.0, 100.0)

func def_army_apply_losses(loss: int) -> void:
	if defender_army == null: return
	defender_army.spearmen = max(0, defender_army.spearmen - int(loss * 0.4))
	defender_army.archers = max(0, defender_army.archers - int(loss * 0.3))
	defender_army.warriors = max(0, defender_army.warriors - int(loss * 0.3))
	defender_army.morale = clampf(defender_army.morale - loss * 1.5, 10.0, 100.0)
