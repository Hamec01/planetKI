class_name ProfessionRegistry
extends RefCounted

# Реестр поведений профессий: job_id -> ProfessionBehavior.
# Чтобы добавить профессию, создайте наследника ProfessionBehavior и впишите его в _build().

static var _behaviors: Dictionary = {}

static func _build() -> void:
	var list: Array[ProfessionBehavior] = [
		MiningProfession.new(),
		CraftsmanProfession.new(),
		TannerProfession.new(),
		WoodcutterProfession.new(),
		HunterProfession.new(),
	]
	for b in list:
		for job in b.get_job_ids():
			_behaviors[job] = b

static func get_behavior(job_id: String) -> ProfessionBehavior:
	if _behaviors.is_empty():
		_build()
	return _behaviors.get(job_id, null)
