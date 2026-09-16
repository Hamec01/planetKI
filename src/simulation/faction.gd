class_name FactionData
extends RefCounted

var id: String = ""
var name: String = "Племя Первого Костра"
var leader_name: String = "Вождь Таргон"
var culture: String = "Охотники и созидатели"
var religion_id: String = "ancestor_spirits"
var color: Color = Color(0.2, 0.6, 0.95)
var is_player: bool = false
var personality: String = "balanced" # aggressive, peaceful, diplomatic, religious, balanced

# Политические и общественные институты
var active_laws: Array[String] = ["rule_warrior_chief", "land_communal"]
var unlocked_techs: Array[String] = []
var current_research_tech: String = "trapping_hunting"
var research_progress: float = 0.0

# Генералы и армия
var generals: Array[Dictionary] = []
var armies: Array[ArmyData] = []

# Дипломатические отношения: other_faction_id -> Dictionary
var relations: Dictionary = {}

func _init(p_id: String = "", p_name: String = "", p_leader: String = "", p_color: Color = Color.WHITE, p_is_player: bool = false) -> void:
	id = p_id
	name = p_name
	leader_name = p_leader
	color = p_color
	is_player = p_is_player
	
	if is_player:
		# Добавляем стартовых генералов игрока
		generals.append(GeneralGenerator.create_brock())
		generals.append(GeneralGenerator.create_gwen())
	else:
		generals.append(GeneralGenerator.generate_random_general())

func get_relation(other_id: String) -> Dictionary:
	if not relations.has(other_id):
		relations[other_id] = {
			"opinion": 0,       # -100 to +100
			"trust": 50,        # 0 - 100
			"fear": 20,         # 0 - 100
			"is_at_war": false,
			"has_truce": false,
			"is_allied": false,
			"is_vassal": false
		}
	return relations[other_id]

func change_opinion(other_id: String, delta: int) -> void:
	var rel = get_relation(other_id)
	rel["opinion"] = clampi(rel["opinion"] + delta, -100, 100)

func sim_daily_research(knowledge_rate: float) -> void:
	if current_research_tech == "":
		return
	var t_info = TechTree.get_tech(current_research_tech)
	if t_info.is_empty():
		return
	research_progress += knowledge_rate
	if research_progress >= t_info["cost"]:
		unlocked_techs.append(current_research_tech)
		GameManager.add_history_entry(GameManager.current_year, "Открытие: " + t_info["name"], "Мудрецы племени %s постигли тайну: %s" % [name, t_info["description"]], "Наука")
		current_research_tech = ""
		research_progress = 0.0
