class_name ItemTextureManager
extends Object

static var _cache: Dictionary = {}

static func get_icon(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
		
	var path = _resolve_path(name)
	if path != "" and ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			_cache[name] = tex
			return tex
			
	return null

static func _resolve_path(name: String) -> String:
	match name.to_lower():
		"food", "wheat": return "res://tiles/wheat_grains_01.png"
		"wood", "axe": return "res://tiles/axe_wood_splitting_01.png"
		"stone", "pickaxe": return "res://tiles/pickaxe_01.png"
		"metal", "sword", "warrior": return "res://tiles/short_sword_01.png"
		"kubriki", "gold", "coins": return "res://tiles/gold-coin_pile-L_01.png"
		"coin_single": return "res://tiles/gold-coin_single_01.png"
		"knowledge", "tome", "science": return "res://tiles/tome_01.png"
		"book": return "res://tiles/book_01.png"
		"faith", "crystal", "mana": return "res://tiles/crystal_01.png"
		"magic_dust": return "res://tiles/magic_dust_01.png"
		"loyalty", "pouch": return "res://tiles/pouch_LVL_03.png"
		"pop", "population", "backpack": return "res://tiles/backpack_LVL_01.png"
		"hunter", "bow", "archer": return "res://tiles/bow_loaded_01.png"
		"arrow": return "res://tiles/arrow_01.png"
		"forager", "berry", "food_berry": return "res://tiles/blackberry_01.png"
		"farmer": return "res://tiles/rice_panicles_01.png"
		"woodcutter": return "res://tiles/axe_wood_splitting_01.png"
		"quarryman", "miner": return "res://tiles/pickaxe_01.png"
		"craftsman": return "res://tiles/pouch_LVL_01.png"
		"sage": return "res://tiles/inkwell_01.png"
		"priest": return "res://tiles/potion_blue_01.png"
		"builder", "shovel": return "res://tiles/shovel_01.png"
		"spear", "spearmen": return "res://tiles/pike_weapon_01.png"
		"flail": return "res://tiles/flail_01.png"
		"bomb": return "res://tiles/bomb_01.png"
		"carcass", "meat_raw": return "res://Assets/nature_clean/carcass.png"
		"meat", "beef", "game": return "res://tiles/beef_01.png"
		"fish", "cod": return "res://tiles/codfish_01.png"
		"hide", "leather": return "res://Assets/items/hide.png"
		"small_hide", "pelt": return "res://Assets/items/small_hide.png"
		"fur": return "res://Assets/items/fur.png"
		"feathers", "feather": return "res://tiles/feathers_01.png"
		"chest": return "res://tiles/chest_closed_01.png"
		"apple": return "res://tiles/apple_red_01.png"
		_:
			# Fallback direct lookup in tiles/ folder
			var direct = "res://tiles/%s.png" % name
			if ResourceLoader.exists(direct):
				return direct
			return ""
