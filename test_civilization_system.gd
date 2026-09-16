# ==============================================================================
# PLANETKI — CIVILIZATION SYSTEM UNIT TEST
# ==============================================================================

func run_tests() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "errors": []}
	
	var CultureMemoryScript = load("res://src/simulation/culture_memory.gd")
	var CivilizationEventManagerScript = load("res://src/events/civilization_event_manager.gd")
	var CivilizationEventDBScript = load("res://src/events/civilization_event_db.gd")
	
	if CultureMemoryScript == null or CivilizationEventManagerScript == null or CivilizationEventDBScript == null:
		results["failed"] += 1
		results["errors"].append("Failed to load civilization scripts.")
		return results
		
	var culture = CultureMemoryScript.new()
	
	# Test 1: Exclusive groups
	culture.set_tradition("monogamy", "marriage_structure", "MONOGAMY", "Брак", "EVENT-FAM-02", "Моногамия", "Семья", 1, 1)
	if culture.get_group_value("marriage_structure") == "MONOGAMY" and culture.has_tradition("monogamy"):
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append("Test 1 Failed: Exclusive group marriage_structure not set correctly.")
		
	# Test 2: Derived government calculation
	culture.set_tradition("council_bound", "authority_structure", "COUNCIL_BOUND", "Власть", "EVENT-GOV-01", "Власть Совета", "Власть", 1, 2)
	culture.set_tradition("council_elect", "succession_rule", "COUNCIL_ELECT", "Наследование", "EVENT-GOV-02", "Выборы Советом", "Власть", 1, 3)
	var gov = culture.get_derived_government()
	if gov["title"] == "Советное выборное вождество":
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append("Test 2 Failed: Derived government title mismatch: " + str(gov["title"]))
		
	# Test 3: Building unlocks through choices
	culture.unlock_building("cemetery")
	if culture.is_building_unlocked("cemetery") and not culture.is_building_unlocked("shrine"):
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append("Test 3 Failed: Building unlock logic incorrect.")
		
	# Test 4: Batch 1 event DB validity
	var all_events = CivilizationEventDBScript.get_all_events()
	if all_events.size() >= 8:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append("Test 4 Failed: Event DB has fewer events than expected: " + str(all_events.size()))
		
	return results
