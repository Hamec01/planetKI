class_name BattleModal
extends PanelContainer

@onready var title_label: Label = $Margin/VBox/Title
@onready var attacker_label: Label = $Margin/VBox/ArmiesBox/AttackerBox/Name
@onready var defender_label: Label = $Margin/VBox/ArmiesBox/DefenderBox/Name
@onready var att_stats_label: Label = $Margin/VBox/ArmiesBox/AttackerBox/Stats
@onready var def_stats_label: Label = $Margin/VBox/ArmiesBox/DefenderBox/Stats
@onready var chronicle_text: RichTextLabel = $Margin/VBox/ChronicleBox/RichText
@onready var next_round_btn: Button = $Margin/VBox/ActionsBox/NextRoundBtn
@onready var retreat_btn: Button = $Margin/VBox/ActionsBox/RetreatBtn
@onready var close_btn: Button = $Margin/VBox/ActionsBox/CloseBtn

var active_battle: BattleInstance = null

var arena_container: Control
var attacker_sprite: AnimatedSprite2D
var defender_sprite: AnimatedSprite2D
var fx_sprite: AnimatedSprite2D

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(func(): visible = false)
	next_round_btn.pressed.connect(_on_next_round)
	retreat_btn.pressed.connect(_on_retreat)
	
	_setup_animated_arena()

func _setup_animated_arena() -> void:
	var vbox = $Margin/VBox
	var armies_box = $Margin/VBox/ArmiesBox
	var idx = armies_box.get_index() + 1
	
	# Создаём контейнер арены тактического боя
	var arena_panel = PanelContainer.new()
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	sbox.border_color = Color(0.3, 0.4, 0.55, 0.8)
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(8)
	arena_panel.add_theme_stylebox_override("panel", sbox)
	arena_panel.custom_minimum_size = Vector2(0, 160)
	
	arena_container = Control.new()
	arena_container.custom_minimum_size = Vector2(0, 160)
	arena_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_panel.add_child(arena_container)
	
	# Спрайт атакующего
	attacker_sprite = AnimatedSprite2D.new()
	attacker_sprite.position = Vector2(170, 95)
	attacker_sprite.scale = Vector2(1.5, 1.5)
	arena_container.add_child(attacker_sprite)
	
	# Спрайт обороняющегося
	defender_sprite = AnimatedSprite2D.new()
	defender_sprite.position = Vector2(530, 95)
	defender_sprite.scale = Vector2(-1.5, 1.5) # Отзеркален влево
	arena_container.add_child(defender_sprite)
	
	# Спрайт эффектов удара (FX)
	fx_sprite = AnimatedSprite2D.new()
	fx_sprite.position = Vector2(350, 90)
	fx_sprite.scale = Vector2(1.6, 1.6)
	fx_sprite.visible = false
	arena_container.add_child(fx_sprite)
	
	var fx_frames = UnitAnimationManager.get_fx_frames("bladestorm")
	if fx_frames == null:
		fx_frames = UnitAnimationManager.get_fx_frames("artifacthit")
	if fx_frames:
		fx_sprite.sprite_frames = fx_frames
		fx_sprite.animation_finished.connect(func(): fx_sprite.visible = false)
	
	vbox.add_child(arena_panel)
	vbox.move_child(arena_panel, idx)

func open_battle(battle: BattleInstance) -> void:
	active_battle = battle
	visible = true
	_setup_units_sprites()
	_refresh()

func _setup_units_sprites() -> void:
	if active_battle == null:
		return
		
	# Загрузка спрайтов генералов / отрядов
	var att_gen = active_battle.attacker_army.general.get("name", "")
	var att_unit_id = "brock" if ("Брок" in att_gen or "Дружина" in active_battle.attacker_army.name) else "warrior"
	var att_sf = UnitAnimationManager.get_unit_frames(att_unit_id)
	if att_sf:
		attacker_sprite.sprite_frames = att_sf
		_play_anim(attacker_sprite, "idle", "breathing")
		
	var def_gen = active_battle.defender_army.general.get("name", "")
	var def_unit_id = "gwen" if "Гвен" in def_gen else "boss"
	var def_sf = UnitAnimationManager.get_unit_frames(def_unit_id)
	if def_sf:
		defender_sprite.sprite_frames = def_sf
		_play_anim(defender_sprite, "idle", "breathing")

func _play_anim(sprite: AnimatedSprite2D, anim_name: String, fallback: String = "breathing") -> void:
	if sprite.sprite_frames:
		if sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)
		elif sprite.sprite_frames.has_animation(fallback):
			sprite.play(fallback)

func _refresh() -> void:
	if active_battle == null:
		return
		
	title_label.text = "⚔️ " + active_battle.battle_name
	
	var att_army = active_battle.attacker_army
	var def_army = active_battle.defender_army
	
	attacker_label.text = "Атакующие: %s (Генерал: %s)" % [att_army.name, att_army.general.get("name", "Вождь")]
	defender_label.text = "Обороняющиеся: %s (Генерал: %s)" % [def_army.name, def_army.general.get("name", "Вождь")]
	
	att_stats_label.text = "Воины: %d (Копейщики: %d, Лучники: %d, Ударники: %d)\nМораль: %.1f%% | Снабжение: %.1f%%" % [
		att_army.get_total_soldiers(), att_army.spearmen, att_army.archers, att_army.warriors, att_army.morale, att_army.supply
	]
	def_stats_label.text = "Воины: %d (Копейщики: %d, Лучники: %d, Ударники: %d)\nМораль: %.1f%% | Снабжение: %.1f%%" % [
		def_army.get_total_soldiers(), def_army.spearmen, def_army.archers, def_army.warriors, def_army.morale, def_army.supply
	]
	
	chronicle_text.text = "\n".join(active_battle.chronicle)
	
	if active_battle.is_finished:
		next_round_btn.disabled = true
		retreat_btn.disabled = true
		var outcome_str = "\n\n🏆 ПОБЕДА НАШИХ ВОЙСК!" if active_battle.victory else "\n\n❌ ПОРАЖЕНИЕ В БИТВЕ!"
		chronicle_text.text += outcome_str
		
		if active_battle.victory:
			_play_anim(defender_sprite, "death")
			_play_anim(attacker_sprite, "breathing")
		else:
			_play_anim(attacker_sprite, "death")
			_play_anim(defender_sprite, "breathing")
	else:
		next_round_btn.disabled = false
		retreat_btn.disabled = false

func _on_next_round() -> void:
	if active_battle == null or active_battle.is_finished:
		return
		
	# Анимации удара и FX
	_play_anim(attacker_sprite, "attack")
	_play_anim(defender_sprite, "hit")
	
	if fx_sprite.sprite_frames:
		fx_sprite.visible = true
		var anims = fx_sprite.sprite_frames.get_animation_names()
		if anims.size() > 0:
			fx_sprite.play(anims[0])
			
	var timer = get_tree().create_timer(0.45)
	timer.timeout.connect(func():
		if active_battle and not active_battle.is_finished:
			_play_anim(attacker_sprite, "breathing")
			_play_anim(defender_sprite, "breathing")
	)
	
	var res = active_battle.advance_round()
	if res.get("finished", false):
		EventBus.battle_ended.emit({"id": active_battle.id}, res["victory"])
		GameManager.add_history_entry(
			GameManager.current_year,
			"Завершение битвы",
			"Битва завершена с исходом: " + ("Победа" if res["victory"] else "Поражение"),
			"Война"
		)
	_refresh()

func _on_retreat() -> void:
	if active_battle:
		active_battle.chronicle.append("Командование приказало отступить на оборонительные рубежи.")
		active_battle.is_finished = true
		active_battle.victory = false
		_play_anim(attacker_sprite, "death")
		EventBus.battle_ended.emit({"id": active_battle.id}, false)
		_refresh()
