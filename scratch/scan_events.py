import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

with open("src/events/civilization_event_db.gd", "r", encoding="utf-8") as f:
    text = f.read()

# scan for consequences blocks
lines = text.split("\n")
current_event = None
current_choice = None
for i, line in enumerate(lines):
    ev_m = re.search(r'"id":\s*"([^"]+)",\s*"title":\s*"([^"]+)"', line)
    if ev_m:
        current_event = f"{ev_m.group(1)}: {ev_m.group(2)}"
    ch_m = re.search(r'"text":\s*"([^"]+)"', line)
    if ch_m:
        current_choice = ch_m.group(1)
    
    if any(k in line.lower() for k in ["unlock", "tame", "domestication", "animal", "deer", "wolf", "building", "corral", "pen", "smokehouse", "outpost"]):
        print(f"[{current_event}] (Choice: {current_choice})")
        print(f"  Line {i+1}: {line.strip()}\n")
