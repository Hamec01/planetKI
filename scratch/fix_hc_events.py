path = r'E:\Planetki\src\events\civilization_event_db.gd'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Find marker where HC-01 was placed:
marker_start = '	# --------------------------------------------------------------------------\n	# ОХОТНИЧИЙ ЛАГЕРЬ'
pos = text.find(marker_start)
if pos == -1:
    print('Marker not found!')
    exit(1)

# Extract the events code from pos up to the last "	}"
# The closing part before was:
# 	return EVENTS.get(event_id, {
# and ended with
# })
# static func get_all_events() -> Array:
# 	return EVENTS.values()

hc_code = text[pos:text.rfind('	}') + 2]

# The original text before "}\n\nstatic func get_event" was right before pos:
orig_prefix = text[:pos]
# orig_prefix ends with:
# 	}\n}\n\nstatic func get_event(event_id: String) -> Dictionary:\n	return EVENTS.get(event_id, {
# Let's find the closing of the previous event (which is "	}\n}\n\nstatic func get_event")
split_marker = '	}\n}\n\nstatic func get_event'
split_pos = orig_prefix.rfind(split_marker)
if split_pos == -1:
    print('Split marker not found')
    exit(1)

clean_prefix = orig_prefix[:split_pos + 2] # includes the '	}' of the previous event

clean_suffix = '''

static func get_event(event_id: String) -> Dictionary:
	return EVENTS.get(event_id, {})

static func get_all_events() -> Array:
	return EVENTS.values()
'''

result = clean_prefix + ',\n' + hc_code + '\n}\n' + clean_suffix
with open(path, 'w', encoding='utf-8') as f:
    f.write(result)

print('Successfully cleaned up civilization_event_db.gd!')
