class_name UnitAnimationManager
extends Object

static var _cache: Dictionary = {}

static func get_unit_frames(unit_id: String) -> SpriteFrames:
	if _cache.has(unit_id):
		return _cache[unit_id]
		
	var path = _resolve_unit_path(unit_id)
	if path != "" and ResourceLoader.exists(path):
		var sf = load(path)
		if sf is SpriteFrames:
			_cache[unit_id] = sf
			return sf
			
	return null

static func get_fx_frames(fx_id: String) -> SpriteFrames:
	var key = "fx_" + fx_id
	if _cache.has(key):
		return _cache[key]
		
	var path = "res://spriteframes/fx/%s.tres" % fx_id
	if not ResourceLoader.exists(path):
		path = "res://spriteframes/fx/fx_%s.tres" % fx_id
		
	if ResourceLoader.exists(path):
		var sf = load(path)
		if sf is SpriteFrames:
			_cache[key] = sf
			return sf
			
	return null

static func _resolve_unit_path(unit_id: String) -> String:
	match unit_id.to_lower():
		"brock", "player_general", "general_brock", "lyonar":
			return "res://spriteframes/units/f1_3rdgeneral.tres"
		"gwen", "general_gwen", "songhai":
			return "res://spriteframes/units/f2_altgeneral.tres"
		"spearman", "spearmen", "vanguard", "guard":
			return "res://spriteframes/units/f1_silversguardknight.tres"
		"archer", "archers", "bowman":
			return "res://spriteframes/units/f2_bowman.tres"
		"warrior", "swordsman", "infantry":
			return "res://spriteframes/units/neutral_swordsman.tres"
		"boss", "barbarian", "chaos", "enemy_general", "raider":
			return "res://spriteframes/units/boss_chaosknight.tres"
		"beast", "cavalry", "wolf":
			return "res://spriteframes/units/f5_beast.tres"
		"golem", "defender":
			return "res://spriteframes/units/f1_ironcliffegolem.tres"
		"mage", "pyromancer", "sage_unit":
			return "res://spriteframes/units/f3_pyromancer.tres"
		_:
			var direct = "res://spriteframes/units/%s.tres" % unit_id
			if ResourceLoader.exists(direct):
				return direct
			return "res://spriteframes/units/neutral_swordsman.tres"
