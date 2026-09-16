class_name ArmyData
extends RefCounted

var id: String = ""
var faction_id: String = ""
var name: String = "Отряд Племени"
var pos: Vector2i = Vector2i.ZERO
var world_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var move_speed: float = 32.0 # пикселей в секунду на карте

# Состав отряда
var spearmen: int = 15
var archers: int = 10
var scouts: int = 5
var warriors: int = 12

# Параметры армии
var morale: float = 85.0       # 0 - 100
var supply: float = 90.0       # 0 - 100
var fatigue: float = 0.0       # 0 - 100
var experience_level: String = "Обученные" # Необстрелянные, Обученные, Ветераны, Элита

# Командир и тактическое состояние
var general: Dictionary = {}
var current_order: String = "idle" # idle, march, assault, defend, skirmish, flank, retreat
var in_combat: bool = false
var target_army_id: String = ""
var speech_bubble: String = ""
var speech_timer: float = 0.0
var attack_cooldown: float = 0.0

func _init() -> void:
	pass

func get_total_soldiers() -> int:
	return spearmen + archers + scouts + warriors

func get_power_rating() -> float:
	var base = spearmen * 1.2 + archers * 1.5 + scouts * 0.8 + warriors * 1.8
	var gen_mod = 1.0 + (general.get("bravery", 50) + general.get("intellect", 50)) / 200.0
	var morale_mod = morale / 100.0
	var order_mod = 1.0
	if current_order == "assault": order_mod = 1.35
	elif current_order == "defend": order_mod = 0.85 # меньше урона наносит, но крепче защита
	return base * gen_mod * morale_mod * order_mod

func get_defense_multiplier() -> float:
	if current_order == "defend":
		return 0.55 # 45% снижение получаемого урона
	return 1.0

func apply_casualties(loss_count: int) -> void:
	var total = get_total_soldiers()
	if total <= 0:
		return
	var actual_loss = mini(loss_count, total)
	
	# Распределяем потери пропорционально
	var s_loss = int(round(float(spearmen) / total * actual_loss))
	var a_loss = int(round(float(archers) / total * actual_loss))
	var w_loss = int(round(float(warriors) / total * actual_loss))
	var sc_loss = actual_loss - (s_loss + a_loss + w_loss)
	
	spearmen = maxi(0, spearmen - s_loss)
	archers = maxi(0, archers - a_loss)
	warriors = maxi(0, warriors - w_loss)
	scouts = maxi(0, scouts - sc_loss)
	
	morale = clampf(morale - actual_loss * 2.2, 0.0, 100.0)

func shout(phrase: String, duration: float = 3.5) -> void:
	speech_bubble = phrase
	speech_timer = duration

