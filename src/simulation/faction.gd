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
var research_saved: Dictionary = {} # tech_id -> накопленные очки (прогресс не теряется при смене темы)
var last_research_rate: float = 0.0 # очков знаний за последний день (для интерфейса)

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

# Все ли предшествующие открытия уже сделаны
func can_research(t_id: String) -> bool:
	var t = TechTree.get_tech(t_id)
	if t.is_empty() or unlocked_techs.has(t_id):
		return false
	for req in t.get("unlocked_by", []):
		if not unlocked_techs.has(req):
			return false
	return true

# Смена темы исследования: накопленные очки прежней темы сохраняются
func set_research(t_id: String) -> bool:
	if not can_research(t_id):
		return false
	if current_research_tech != "" and research_progress > 0.0:
		research_saved[current_research_tech] = research_progress
	current_research_tech = t_id
	research_progress = float(research_saved.get(t_id, 0.0))
	research_saved.erase(t_id)
	return true

func sim_daily_research(knowledge_rate: float) -> void:
	last_research_rate = knowledge_rate
	if current_research_tech == "":
		return
	var t_info = TechTree.get_tech(current_research_tech)
	if t_info.is_empty():
		return
	research_progress += knowledge_rate
	if research_progress >= t_info["cost"]:
		unlocked_techs.append(current_research_tech)
		# Эффекты технологии сразу входят в бонусы поселений (SettlementData.get_bonus)
		BuildingInstance.upgrade_revision += 1
		GameManager.add_history_entry(GameManager.current_year, "Открытие: " + t_info["name"], "Мудрецы племени %s постигли тайну: %s" % [name, t_info["description"]], "Наука")
		if id == GameManager.player_faction_id:
			EventBus.notification_toast.emit("Открытие: %s" % t_info["name"], "%s Выберите следующее исследование во вкладке «Наука»." % t_info["description"], "good")
		current_research_tech = ""
		research_progress = 0.0
