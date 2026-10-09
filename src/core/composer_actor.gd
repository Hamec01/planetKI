class_name ComposerActor
extends Node2D

var citizen: CitizenNPC
var action: String = "idle"
var clock: float = 0.0
var until: float = 0.0

func configure(id: String, role: String) -> void:
	citizen = ComposerAssets.proxy(id,role)
	citizen.pos = Vector2.ZERO
	queue_redraw()

func play_action(name: String) -> void:
	if name == "breathing": name = "idle"
	if name == "attack":
		name = String({"weapons_0":"bow_attack","weapons_1":"spear_attack"}.get(ComposerAssets.WEAPONS.get(citizen.equipment.get("weapon",""),""),"sword_attack"))
	action = name
	until = clock + 1.3 if name not in ["idle","death"] else INF
	citizen.custom_data.erase("composer_action")

func _process(delta: float) -> void:
	clock += delta
	if clock >= until: action = "idle"
	queue_redraw()

func _draw() -> void:
	if citizen: ComposerAssets.draw_citizen(self,citizen,clock,action)
